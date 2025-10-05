# utils.R - Utility functions for DIA window optimizer

# Spectronaut standard: Peak width = 1.7 × FWHM
PEAK_WIDTH_FACTOR <- 1.7
#' Load configuration from JSON file
#' 
#' @param config_file Path to JSON configuration file
#' @return List with configuration parameters
load_config <- function(config_file) {
  
  if (!file.exists(config_file)) {
    stop(sprintf("Configuration file not found: %s", config_file))
  }
  
  library(jsonlite)
  config <- fromJSON(config_file)
  
  # Validate required parameters
  required <- c("proteome_file", "mz_range", "instrument_preset")
  missing <- setdiff(required, names(config))
  
  if (length(missing) > 0) {
    stop(sprintf("Missing required parameters: %s", paste(missing, collapse = ", ")))
  }
  
  return(config)
}

#' Save configuration to JSON file
#' 
#' @param config Configuration list
#' @param output_file Output file path
save_config <- function(config, output_file) {
  
  library(jsonlite)
  json_str <- toJSON(config, pretty = TRUE, auto_unbox = TRUE)
  writeLines(json_str, output_file)
  cat(sprintf("Configuration saved to: %s\n", output_file))
}

#' Validate numeric range
#' 
#' @param value Value to check
#' @param min_val Minimum allowed value
#' @param max_val Maximum allowed value
#' @param name Parameter name for error message
#' @return Validated value
validate_range <- function(value, min_val, max_val, name) {
  
  if (value < min_val || value > max_val) {
    stop(sprintf("%s must be between %g and %g (got %g)", 
                name, min_val, max_val, value))
  }
  
  return(value)
}

#' Create default configuration
#' 
#' @return List with default configuration
create_default_config <- function() {

  config <- list(
    # Input parameters
    proteome_file = "path/to/diann_output.parquet",
    mz_range = c(380, 980),
    rt_segments = 5,

    # Instrument settings
    instrument_preset = "astral",
    scan_rate_limit = NULL,
    ms1_time = NULL,
    ms2_time = NULL,

    # Raw metadata integration
    enable_raw_metadata = FALSE,  # Enable raw file metadata extraction
    use_user_config = FALSE,      # Use user config generated from raw metadata

    # Optimization settings
    target_dppp = 1.25,
    dppp_range = c(1.0, 5.0),

    # FWHM strategy settings
    fwhm_strategy = "balanced",  # "conservative", "balanced", "aggressive", "adaptive"
    fwhm_analysis_enabled = TRUE,

    # Window settings
    window_mode = "dynamic",
    min_window_width = 2.0,
    max_window_width = 80.0,
    overlap_mode = "percentage",
    overlap_value = 0.5,

    # RT range
    rt_min = 0,
    rt_max = NULL,

    # Other
    min_precursors_per_window = 100,

    # Output settings
    output_format = "csv",
    output_path = "optimized_windows",
    create_plots = TRUE,
    plot_output = "optimization_report.pdf"
  )

  return(config)
}

#' Print configuration summary
#' 
#' @param config Configuration list
print_config <- function(config) {
  
  cat("\n=== Configuration Summary ===\n")
  cat(sprintf("Input file: %s\n", config$proteome_file))
  cat(sprintf("m/z range: %.1f - %.1f\n", config$mz_range[1], config$mz_range[2]))
  cat(sprintf("RT segments: %d\n", config$rt_segments))
  cat(sprintf("Instrument: %s\n", config$instrument_preset))
  cat(sprintf("Target DPPP: %.2f\n", config$target_dppp))
  cat(sprintf("FWHM Strategy: %s\n", config$fwhm_strategy))
  cat(sprintf("Window mode: %s\n", config$window_mode))
  cat(sprintf("Overlap: %s (%.1f)\n", config$overlap_mode, config$overlap_value))
  cat("=============================\n\n")
}

#' Check required packages
#' 
#' @param packages Character vector of package names
#' @return Logical indicating if all packages are available
check_packages <- function(packages = c("arrow", "dplyr", "ggplot2", "gridExtra", 
                                        "jsonlite", "tidyr", "viridis", "scales")) {
  
  missing <- character()
  
  for (pkg in packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      missing <- c(missing, pkg)
    }
  }
  
  if (length(missing) > 0) {
    cat("Missing required packages:\n")
    cat(paste("  -", missing, collapse = "\n"), "\n\n")
    cat("Install with:\n")
    cat(sprintf('install.packages(c(%s))\n', 
                paste(sprintf('"%s"', missing), collapse = ", ")))
    return(FALSE)
  }
  
  return(TRUE)
}

#' Timer function for performance monitoring
#' 
#' @param start_time Start time from Sys.time()
#' @param task_name Name of the task
#' @return Elapsed time
timer <- function(start_time, task_name = "Task") {
  
  elapsed <- difftime(Sys.time(), start_time, units = "secs")
  cat(sprintf("%s completed in %.1f seconds\n", task_name, elapsed))
  return(elapsed)
}

#' Validate scan rate against instrument capabilities
#' 
#' @param scan_rate_hz Calculated scan rate in Hz
#' @param instrument_config Instrument configuration
#' @param n_windows Number of windows
#' @param target_dppp Target DPPP value
#' @return List with validation results and recommendations
validate_scan_rate <- function(scan_rate_hz, instrument_config, n_windows, target_dppp) {
  
  result <- list(
    scan_rate_hz = scan_rate_hz,
    is_achievable = TRUE,
    warnings = character(),
    recommendations = character(),
    suggested_dppp = NULL
  )
  
  # Check against maximum scan rate
  if (scan_rate_hz > instrument_config$max_scan_rate) {
    result$is_achievable <- FALSE
    result$warnings <- c(result$warnings,
      sprintf("⚠️ SCAN RATE EXCEEDS INSTRUMENT LIMIT: %.1f Hz > %.1f Hz (max)",
              scan_rate_hz, instrument_config$max_scan_rate))
    
    # Calculate suggested DPPP for achievable scan rate
    # For max scan rate, cycle time = n_windows / max_scan_rate
    max_cycle_time_s <- n_windows / instrument_config$max_scan_rate
    # DPPP = (1.7 × FWHM) / cycle_time, so peak_width = target_dppp × current_cycle_time
    current_cycle_time_s <- n_windows / scan_rate_hz
    peak_width_s <- target_dppp * current_cycle_time_s
    suggested_dppp <- peak_width_s / max_cycle_time_s
    result$suggested_dppp <- suggested_dppp
    
    # Calculate max achievable windows at max scan rate
    max_achievable_windows <- floor(instrument_config$max_scan_rate * current_cycle_time_s)
    
    result$recommendations <- c(result$recommendations,
      sprintf("→ Increase DPPP to %.2f to achieve %.1f Hz scan rate", 
              suggested_dppp, instrument_config$max_scan_rate),
      sprintf("→ Or reduce windows from %d to %d (max achievable at %.1f Hz)", 
              n_windows, max_achievable_windows, instrument_config$max_scan_rate))
  }
  
  # Check against optimal scan rate
  if (scan_rate_hz > instrument_config$optimal_scan_rate && 
      scan_rate_hz <= instrument_config$max_scan_rate) {
    result$warnings <- c(result$warnings,
      sprintf("⚠️ Scan rate (%.1f Hz) exceeds optimal rate (%.1f Hz) - may impact data quality",
              scan_rate_hz, instrument_config$optimal_scan_rate))
    
    result$recommendations <- c(result$recommendations,
      sprintf("→ Consider increasing DPPP to %.2f for optimal performance",
              target_dppp * (scan_rate_hz / instrument_config$optimal_scan_rate)))
  }
  
  # Check against minimum scan rate
  if (scan_rate_hz < instrument_config$min_scan_rate) {
    result$warnings <- c(result$warnings,
      sprintf("ℹ️ Scan rate (%.1f Hz) is below typical minimum (%.1f Hz) - may be oversampling",
              scan_rate_hz, instrument_config$min_scan_rate))
    
    result$recommendations <- c(result$recommendations,
      sprintf("→ Consider decreasing DPPP to %.2f to increase scan rate",
              target_dppp * (scan_rate_hz / instrument_config$min_scan_rate)))
  }
  
  return(result)
}

#' Calculate achievable DPPP for given instrument constraints
#' 
#' @param fwhm_seconds FWHM in seconds
#' @param n_windows Number of windows
#' @param instrument_config Instrument configuration
#' @return List with achievable DPPP values
calculate_achievable_dppp <- function(fwhm_seconds, n_windows, instrument_config) {
  
  # Calculate cycle time based on instrument type
  if (instrument_config$parallel_acquisition) {
    cycle_time_ms <- max(instrument_config$ms1_time, n_windows * instrument_config$ms2_time)
  } else {
    cycle_time_ms <- instrument_config$ms1_time + n_windows * instrument_config$ms2_time
  }
  
  cycle_time_s <- cycle_time_ms / 1000
  # Correct scan rate: MS2 scans per second
  scan_rate_hz <- n_windows / cycle_time_s
  
  # Calculate DPPP values for different scan rates
  result <- list(
    current = list(
      dppp = (fwhm_seconds * PEAK_WIDTH_FACTOR) / cycle_time_s,
      scan_rate_hz = scan_rate_hz,
      cycle_time_s = cycle_time_s
    ),
    max_rate = list(
      dppp = calculate_dppp_from_scan_rate(fwhm_seconds, instrument_config$max_scan_rate, n_windows),
      scan_rate_hz = instrument_config$max_scan_rate,
      cycle_time_s = n_windows / instrument_config$max_scan_rate,
      max_windows = floor(instrument_config$max_scan_rate * (cycle_time_s))
    ),
    optimal_rate = list(
      dppp = calculate_dppp_from_scan_rate(fwhm_seconds, instrument_config$optimal_scan_rate, n_windows),
      scan_rate_hz = instrument_config$optimal_scan_rate,
      cycle_time_s = n_windows / instrument_config$optimal_scan_rate,
      max_windows = floor(instrument_config$optimal_scan_rate * (cycle_time_s))
    ),
    min_rate = list(
      dppp = calculate_dppp_from_scan_rate(fwhm_seconds, instrument_config$min_scan_rate, n_windows),
      scan_rate_hz = instrument_config$min_scan_rate,
      cycle_time_s = n_windows / instrument_config$min_scan_rate,
      max_windows = floor(instrument_config$min_scan_rate * (cycle_time_s))
    )
  )
  
  return(result)
}

#' Calculate DPPP from scan rate and window configuration
#' 
#' @param fwhm_seconds FWHM in seconds
#' @param scan_rate_hz Scan rate in Hz
#' @param n_windows Number of windows
#' @return DPPP value
calculate_dppp_from_scan_rate <- function(fwhm_seconds, scan_rate_hz, n_windows) {
  # For given scan rate, calculate cycle time needed for n_windows
  cycle_time_s <- n_windows / scan_rate_hz
  # DPPP = (1.7 × FWHM) / cycle_time
  dppp <- (fwhm_seconds * PEAK_WIDTH_FACTOR) / cycle_time_s
  return(dppp)
}

#' Print scan rate validation results
#' 
#' @param validation_result Result from validate_scan_rate
print_scan_rate_validation <- function(validation_result) {
  
  cat("\n╔════════════════════════════════════════════╗\n")
  cat("║       SCAN RATE VALIDATION RESULTS        ║\n")
  cat("╚════════════════════════════════════════════╝\n\n")
  
  cat(sprintf("Calculated scan rate: %.1f Hz\n", validation_result$scan_rate_hz))
  cat(sprintf("Achievable on instrument: %s\n\n", 
              ifelse(validation_result$is_achievable, "✅ YES", "❌ NO")))
  
  if (length(validation_result$warnings) > 0) {
    cat("Warnings:\n")
    for (warning in validation_result$warnings) {
      cat(sprintf("  %s\n", warning))
    }
    cat("\n")
  }
  
  if (length(validation_result$recommendations) > 0) {
    cat("Recommendations:\n")
    for (rec in validation_result$recommendations) {
      cat(sprintf("  %s\n", rec))
    }
    cat("\n")
  }
  
  if (!is.null(validation_result$suggested_dppp)) {
    cat(sprintf("📊 Suggested DPPP for achievable performance: %.2f\n", 
                validation_result$suggested_dppp))
  }
  
  cat("═══════════════════════════════════════════\n")
}