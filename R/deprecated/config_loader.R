# config_loader.R - Configuration file loader and validator
#
# Purpose: Load and validate YAML/JSON configuration files for DIA window optimization
#          YAML is the primary format (recommended). JSON supported for legacy compatibility.
#
# Version: 2.0
# Last Updated: 2025-11-17

library(jsonlite)  # For JSON support (legacy)

# =============================================================================
# YAML Parser (Using yaml package for reliability)
# =============================================================================

#' Parse YAML file into R list
#'
#' Uses yaml package for robust YAML parsing.
#' Falls back to jsonlite for JSON files.
#'
#' @param yaml_path Path to YAML file
#' @return Parsed configuration list
#' @keywords internal
parse_yaml <- function(yaml_path) {

  # Check if yaml package is available
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("yaml package is required for YAML configuration files.\n",
         "Please install it with: install.packages('yaml')")
  }

  # Parse YAML using yaml package
  config <- yaml::read_yaml(yaml_path)

  return(config)
}

# =============================================================================
# Configuration Loading
# =============================================================================

#' Load optimization configuration from YAML or JSON file
#'
#' @param config_path Path to YAML (.yaml, .yml) or JSON (.json) configuration file
#' @return List with configuration parameters
#' @export
#'
#' @examples
#' config <- load_optimization_config("config/optimization_config.yaml")
#' config <- load_optimization_config("config/optimization_config.json")  # Legacy
load_optimization_config <- function(config_path) {

  # Check file existence
  if (!file.exists(config_path)) {
    stop(sprintf("Configuration file not found: %s", config_path))
  }

  # Detect file format
  file_ext <- tolower(tools::file_ext(config_path))

  # Load configuration
  cat(sprintf("Loading configuration: %s\n", config_path))
  config <- tryCatch(
    {
      if (file_ext %in% c("yaml", "yml")) {
        # YAML (primary format)
        parse_yaml(config_path)
      } else if (file_ext == "json") {
        # JSON (legacy format)
        cat("  ℹ️  Note: JSON format is legacy. Consider converting to YAML for better readability.\n")
        fromJSON(config_path, simplifyVector = TRUE, simplifyDataFrame = FALSE)
      } else {
        stop(sprintf("Unsupported file format: %s (use .yaml, .yml, or .json)", file_ext))
      }
    },
    error = function(e) {
      stop(sprintf("Failed to parse configuration: %s\nError: %s", config_path, e$message))
    }
  )

  # Validate configuration
  validation_result <- validate_optimization_config(config)

  if (!validation_result$valid) {
    cat("\n❌ Configuration validation failed:\n")
    for (error in validation_result$errors) {
      cat(sprintf("   - %s\n", error))
    }
    stop("Invalid configuration file")
  }

  cat("✅ Configuration loaded and validated successfully\n\n")

  return(config)
}

# =============================================================================
# Configuration Validation
# =============================================================================

#' Validate optimization configuration
#'
#' @param config Configuration list
#' @return List with valid (logical) and errors (character vector)
#' @export
validate_optimization_config <- function(config) {

  errors <- character()

  # ===================================================================
  # 1. Project Metadata Validation
  # ===================================================================

  if (is.null(config$project_metadata)) {
    errors <- c(errors, "Missing 'project_metadata' section")
  } else {
    pm <- config$project_metadata

    # Required fields
    if (is.null(pm$project_name) || pm$project_name == "") {
      errors <- c(errors, "project_metadata.project_name is required")
    }

    if (is.null(pm$date) || pm$date == "") {
      errors <- c(errors, "project_metadata.date is required")
    }
  }

  # ===================================================================
  # 2. Input Data Validation
  # ===================================================================

  if (is.null(config$input_data)) {
    errors <- c(errors, "Missing 'input_data' section")
  } else {
    input_data <- config$input_data

    # Required fields
    if (is.null(input_data$input_files) || length(input_data$input_files) == 0) {
      errors <- c(errors, "input_data.input_files is required and must not be empty")
    } else {
      # Check file existence
      for (file_path in input_data$input_files) {
        if (!file.exists(file_path)) {
          errors <- c(errors, sprintf("Input file not found: %s", file_path))
        }
      }
    }
  }

  # ===================================================================
  # 3. Instrument Validation
  # ===================================================================

  if (is.null(config$instrument)) {
    errors <- c(errors, "Missing 'instrument' section")
  } else {
    inst <- config$instrument

    # Required fields
    if (is.null(inst$preset) || inst$preset == "") {
      errors <- c(errors, "instrument.preset is required")
    } else {
      # Check if preset exists
      valid_presets <- c("astral", "orbitrap", "orbitrap_exploris", "fusion_lumos",
                         "timstof", "timstof_pro", "sciex_7600", "waters_synapt", "custom")

      if (!inst$preset %in% valid_presets) {
        errors <- c(errors, sprintf("Invalid instrument.preset: %s (valid: %s)",
                                   inst$preset, paste(valid_presets, collapse = ", ")))
      }
    }

    # Custom settings validation (if provided)
    if (!is.null(inst$custom_settings)) {
      cs <- inst$custom_settings

      if (!is.null(cs$ms1_time) && (cs$ms1_time <= 0 || cs$ms1_time > 1000)) {
        errors <- c(errors, "instrument.custom_settings.ms1_time must be between 0 and 1000 ms")
      }

      if (!is.null(cs$ms2_time) && (cs$ms2_time <= 0 || cs$ms2_time > 500)) {
        errors <- c(errors, "instrument.custom_settings.ms2_time must be between 0 and 500 ms")
      }

      if (!is.null(cs$max_scan_rate) && (cs$max_scan_rate <= 0 || cs$max_scan_rate > 500)) {
        errors <- c(errors, "instrument.custom_settings.max_scan_rate must be between 0 and 500 Hz")
      }

      if (!is.null(cs$cycle_calculation) && !cs$cycle_calculation %in% c("parallel", "sequential")) {
        errors <- c(errors, "instrument.custom_settings.cycle_calculation must be 'parallel' or 'sequential'")
      }
    }
  }

  # ===================================================================
  # 4. DPPP Parameters Validation
  # ===================================================================

  if (is.null(config$dppp_parameters)) {
    errors <- c(errors, "Missing 'dppp_parameters' section")
  } else {
    dppp <- config$dppp_parameters

    # Required fields with range checks
    if (is.null(dppp$target_dppp)) {
      errors <- c(errors, "dppp_parameters.target_dppp is required")
    } else if (dppp$target_dppp < 0.5 || dppp$target_dppp > 15.0) {
      errors <- c(errors, "dppp_parameters.target_dppp must be between 0.5 and 15.0")
    }

    if (is.null(dppp$target_satisfaction)) {
      errors <- c(errors, "dppp_parameters.target_satisfaction is required")
    } else if (dppp$target_satisfaction < 0.5 || dppp$target_satisfaction > 1.0) {
      errors <- c(errors, "dppp_parameters.target_satisfaction must be between 0.5 and 1.0")
    }

    # load_factor moved to scan_settings section (removed from here)

    # Optional with defaults
    if (!is.null(dppp$dppp_tolerance) && (dppp$dppp_tolerance < 0 || dppp$dppp_tolerance > 2.0)) {
      errors <- c(errors, "dppp_parameters.dppp_tolerance must be between 0 and 2.0")
    }
  }

  # ===================================================================
  # 5. Scan Settings Validation (NEW)
  # ===================================================================

  if (is.null(config$scan_settings)) {
    errors <- c(errors, "Missing 'scan_settings' section")
  } else {
    scan <- config$scan_settings

    # Required: load_factor
    if (is.null(scan$load_factor)) {
      errors <- c(errors, "scan_settings.load_factor is required")
    } else if (scan$load_factor < 0.5 || scan$load_factor > 1.0) {
      errors <- c(errors, "scan_settings.load_factor must be between 0.5 and 1.0")
    }

    # Optional: ms1_scans_per_cycle
    if (!is.null(scan$ms1_scans_per_cycle)) {
      if (!scan$ms1_scans_per_cycle %in% c(0, 1)) {
        errors <- c(errors, "scan_settings.ms1_scans_per_cycle must be 0 or 1")
      }
    }

    # Optional: warning_threshold_windows
    if (!is.null(scan$warning_threshold_windows)) {
      if (scan$warning_threshold_windows < 1 || scan$warning_threshold_windows > 20) {
        errors <- c(errors, "scan_settings.warning_threshold_windows must be between 1 and 20")
      }
    }
  }

  # ===================================================================
  # 6. RT Binning Validation
  # ===================================================================

  if (is.null(config$rt_binning)) {
    errors <- c(errors, "Missing 'rt_binning' section")
  } else {
    rt <- config$rt_binning

    # Required fields
    if (is.null(rt$rt_bin_width_min)) {
      errors <- c(errors, "rt_binning.rt_bin_width_min is required")
    } else if (rt$rt_bin_width_min < 0.5 || rt$rt_bin_width_min > 30) {
      errors <- c(errors, "rt_binning.rt_bin_width_min must be between 0.5 and 30 minutes")
    }
  }

  # ===================================================================
  # 7. m/z Optimization Validation
  # ===================================================================

  if (is.null(config$mz_optimization)) {
    errors <- c(errors, "Missing 'mz_optimization' section")
  } else {
    mz <- config$mz_optimization

    # Required fields
    if (is.null(mz$strategies) || length(mz$strategies) == 0) {
      errors <- c(errors, "mz_optimization.strategies is required and must not be empty")
    } else {
      valid_strategies <- c("quantile", "smoothing", "outlier", "coverage")
      invalid_strategies <- setdiff(mz$strategies, valid_strategies)

      if (length(invalid_strategies) > 0) {
        errors <- c(errors, sprintf("Invalid mz_optimization.strategies: %s (valid: %s)",
                                   paste(invalid_strategies, collapse = ", "),
                                   paste(valid_strategies, collapse = ", ")))
      }
    }

    # Range checks for optional parameters
    if (!is.null(mz$quantile_lower) && (mz$quantile_lower < 0 || mz$quantile_lower > 0.5)) {
      errors <- c(errors, "mz_optimization.quantile_lower must be between 0 and 0.5")
    }

    if (!is.null(mz$quantile_upper) && (mz$quantile_upper < 0.5 || mz$quantile_upper > 1.0)) {
      errors <- c(errors, "mz_optimization.quantile_upper must be between 0.5 and 1.0")
    }

    if (!is.null(mz$target_coverage) && (mz$target_coverage < 0.5 || mz$target_coverage > 1.0)) {
      errors <- c(errors, "mz_optimization.target_coverage must be between 0.5 and 1.0")
    }

    if (!is.null(mz$outlier_threshold) && (mz$outlier_threshold < 1.0 || mz$outlier_threshold > 10.0)) {
      errors <- c(errors, "mz_optimization.outlier_threshold must be between 1.0 and 10.0")
    }

    if (!is.null(mz$smoothing_window) && (mz$smoothing_window < 1 || mz$smoothing_window > 15)) {
      errors <- c(errors, "mz_optimization.smoothing_window must be between 1 and 15")
    }

    if (!is.null(mz$polynomial_order) && (mz$polynomial_order < 1 || mz$polynomial_order > 5)) {
      errors <- c(errors, "mz_optimization.polynomial_order must be between 1 and 5")
    }
  }

  # ===================================================================
  # 8. Window Generation Validation
  # ===================================================================

  if (is.null(config$window_generation)) {
    errors <- c(errors, "Missing 'window_generation' section")
  } else {
    wg <- config$window_generation

    # Required fields
    if (is.null(wg$modes) || length(wg$modes) == 0) {
      errors <- c(errors, "window_generation.modes is required and must not be empty")
    } else {
      valid_modes <- c("fixed", "variable")
      invalid_modes <- setdiff(wg$modes, valid_modes)

      if (length(invalid_modes) > 0) {
        errors <- c(errors, sprintf("Invalid window_generation.modes: %s (valid: %s)",
                                   paste(invalid_modes, collapse = ", "),
                                   paste(valid_modes, collapse = ", ")))
      }
    }

    # Range checks
    if (is.null(wg$min_width_da)) {
      errors <- c(errors, "window_generation.min_width_da is required")
    } else if (wg$min_width_da < 0.5 || wg$min_width_da > 50) {
      errors <- c(errors, "window_generation.min_width_da must be between 0.5 and 50 Da")
    }

    if (is.null(wg$max_width_da)) {
      errors <- c(errors, "window_generation.max_width_da is required")
    } else if (wg$max_width_da < 1 || wg$max_width_da > 200) {
      errors <- c(errors, "window_generation.max_width_da must be between 1 and 200 Da")
    }

    # Logical check
    if (!is.null(wg$min_width_da) && !is.null(wg$max_width_da)) {
      if (wg$min_width_da > wg$max_width_da) {
        errors <- c(errors, "window_generation.min_width_da must be <= max_width_da")
      }
    }

    if (!is.null(wg$overlap_percentage) && (wg$overlap_percentage < 0 || wg$overlap_percentage > 50)) {
      errors <- c(errors, "window_generation.overlap_percentage must be between 0 and 50")
    }
  }

  # ===================================================================
  # 9. Output Validation
  # ===================================================================

  if (is.null(config$output)) {
    errors <- c(errors, "Missing 'output' section")
  } else {
    output <- config$output

    # Required fields
    if (is.null(output$output_dir) || output$output_dir == "") {
      errors <- c(errors, "output.output_dir is required")
    }

    # Logical defaults
    if (is.null(output$include_summary)) {
      config$output$include_summary <- TRUE
    }

    if (is.null(output$include_plots)) {
      config$output$include_plots <- FALSE
    }
  }

  # ===================================================================
  # Return Validation Result
  # ===================================================================

  valid <- length(errors) == 0

  return(list(
    valid = valid,
    errors = errors
  ))
}

# =============================================================================
# Configuration Printing
# =============================================================================

#' Print configuration summary
#'
#' @param config Configuration list
#' @export
print_config_summary <- function(config) {

  cat("\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║             DIA WINDOW OPTIMIZATION CONFIGURATION              ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  # Project metadata
  cat("📋 PROJECT METADATA\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  Project name: %s\n", config$project_metadata$project_name))
  cat(sprintf("  Date: %s\n", config$project_metadata$date))
  if (!is.null(config$project_metadata$description)) {
    cat(sprintf("  Description: %s\n", config$project_metadata$description))
  }
  if (!is.null(config$project_metadata$analyst)) {
    cat(sprintf("  Analyst: %s\n", config$project_metadata$analyst))
  }

  # Input data
  cat("\n📁 INPUT DATA\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  Files: %d\n", length(config$input_data$input_files)))
  for (i in seq_along(config$input_data$input_files)) {
    cat(sprintf("    %d. %s\n", i, config$input_data$input_files[i]))
  }

  # Instrument
  cat("\n🔬 INSTRUMENT\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  Preset: %s\n", config$instrument$preset))
  if (!is.null(config$instrument$custom_settings)) {
    cat("  Custom settings:\n")
    for (name in names(config$instrument$custom_settings)) {
      cat(sprintf("    %s: %s\n", name, config$instrument$custom_settings[[name]]))
    }
  }

  # DPPP parameters
  cat("\n🎯 DPPP PARAMETERS\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  Target DPPP: %.1f\n", config$dppp_parameters$target_dppp))
  cat(sprintf("  Target satisfaction: %.0f%%\n", config$dppp_parameters$target_satisfaction * 100))
  if (!is.null(config$dppp_parameters$dppp_tolerance)) {
    cat(sprintf("  DPPP tolerance: %.2f\n", config$dppp_parameters$dppp_tolerance))
  }

  # Scan settings
  cat("\n⚙️  SCAN SETTINGS\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  Load factor: %.0f%%\n", config$scan_settings$load_factor * 100))
  if (!is.null(config$scan_settings$ms1_scans_per_cycle)) {
    cat(sprintf("  MS1 scans per cycle: %d\n", config$scan_settings$ms1_scans_per_cycle))
  }

  # RT binning
  cat("\n⏱️  RT BINNING\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  RT bin width: %.1f min\n", config$rt_binning$rt_bin_width_min))

  # m/z optimization
  cat("\n📊 m/z OPTIMIZATION\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  Strategies: %s\n", paste(config$mz_optimization$strategies, collapse = ", ")))
  cat(sprintf("  Quantile range: P%.0f - P%.0f\n",
             config$mz_optimization$quantile_lower * 100,
             config$mz_optimization$quantile_upper * 100))
  cat(sprintf("  Target coverage: %.0f%%\n", config$mz_optimization$target_coverage * 100))

  # Window generation
  cat("\n🪟 WINDOW GENERATION\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  Modes: %s\n", paste(config$window_generation$modes, collapse = ", ")))
  cat(sprintf("  Window width: %.1f - %.1f Da\n",
             config$window_generation$min_width_da,
             config$window_generation$max_width_da))
  cat(sprintf("  Overlap: %.0f%%\n", config$window_generation$overlap_percentage))

  # Output
  cat("\n💾 OUTPUT\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  Output directory: %s\n", config$output$output_dir))
  cat(sprintf("  Include summary: %s\n", ifelse(config$output$include_summary, "Yes", "No")))
  cat(sprintf("  Include plots: %s\n", ifelse(config$output$include_plots, "Yes", "No")))

  # Calculate total combinations
  total_files <- length(config$input_data$input_files)
  total_strategies <- length(config$mz_optimization$strategies)
  total_modes <- length(config$window_generation$modes)
  total_combinations <- total_files * total_strategies * total_modes

  cat("\n📈 PROCESSING SUMMARY\n")
  cat("───────────────────────────────────────────────────────────────\n")
  cat(sprintf("  Total files: %d\n", total_files))
  cat(sprintf("  Strategies per file: %d\n", total_strategies))
  cat(sprintf("  Modes per strategy: %d\n", total_modes))
  cat(sprintf("  Total CSV files to generate: %d\n", total_combinations))

  cat("\n")
}

# =============================================================================
# Helper Functions
# =============================================================================

#' Get configuration value with default
#'
#' @param config Configuration list
#' @param path Dot-separated path to value (e.g., "dppp_parameters.target_dppp")
#' @param default Default value if not found
#' @return Configuration value or default
#' @export
get_config_value <- function(config, path, default = NULL) {

  parts <- strsplit(path, "\\.")[[1]]

  current <- config
  for (part in parts) {
    if (is.null(current[[part]])) {
      return(default)
    }
    current <- current[[part]]
  }

  return(current)
}
