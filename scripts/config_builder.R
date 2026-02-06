# =============================================================================
# Interactive Configuration Builder for DIA Window Optimizer
# =============================================================================
# Creates YAML/JSON configuration files through interactive Q&A
# No additional packages required (base R only)
# =============================================================================

# Load necessary functions
if (!exists("get_instrument_presets")) {
  source("R/instrument_utils.R")
}

# =============================================================================
# Helper Functions
# =============================================================================

#' Print section header
print_section <- function(title) {
  cat("\n")
  cat(strrep("=", 70), "\n")
  cat(sprintf("  %s\n", title))
  cat(strrep("=", 70), "\n")
}

#' Print option list
print_options <- function(options, descriptions = NULL) {
  for (i in seq_along(options)) {
    if (!is.null(descriptions)) {
      cat(sprintf("  [%d] %s - %s\n", i, options[i], descriptions[i]))
    } else {
      cat(sprintf("  [%d] %s\n", i, options[i]))
    }
  }
}

#' Get user input with validation
get_input <- function(prompt, default = NULL, validator = NULL) {
  if (!is.null(default)) {
    prompt_text <- sprintf("%s [default: %s]: ", prompt, default)
  } else {
    prompt_text <- sprintf("%s: ", prompt)
  }

  repeat {
    cat(prompt_text)
    input <- readline()

    # Use default if empty
    if (input == "" && !is.null(default)) {
      input <- default
    }

    # Validate
    if (!is.null(validator)) {
      validation <- validator(input)
      if (validation$valid) {
        return(validation$value)
      } else {
        cat(sprintf("  ⚠️  %s\n", validation$message))
      }
    } else {
      return(input)
    }
  }
}

#' Get numeric input
get_numeric <- function(prompt, default = NULL, min = NULL, max = NULL) {
  validator <- function(x) {
    num <- suppressWarnings(as.numeric(x))
    if (is.na(num)) {
      return(list(valid = FALSE, message = "Please enter a valid number"))
    }
    if (!is.null(min) && num < min) {
      return(list(valid = FALSE, message = sprintf("Must be >= %s", min)))
    }
    if (!is.null(max) && num > max) {
      return(list(valid = FALSE, message = sprintf("Must be <= %s", max)))
    }
    return(list(valid = TRUE, value = num))
  }

  get_input(prompt, default, validator)
}

#' Get yes/no input
get_yesno <- function(prompt, default = "y") {
  validator <- function(x) {
    x_lower <- tolower(x)
    if (x_lower %in% c("y", "yes")) {
      return(list(valid = TRUE, value = TRUE))
    } else if (x_lower %in% c("n", "no")) {
      return(list(valid = TRUE, value = FALSE))
    } else {
      return(list(valid = FALSE, message = "Please enter 'y' or 'n'"))
    }
  }

  get_input(prompt, default, validator)
}

#' Get choice from list
get_choice <- function(prompt, options, default = NULL) {
  validator <- function(x) {
    idx <- suppressWarnings(as.integer(x))
    if (is.na(idx) || idx < 1 || idx > length(options)) {
      return(list(valid = FALSE,
                  message = sprintf("Please enter 1-%d", length(options))))
    }
    return(list(valid = TRUE, value = options[idx]))
  }

  get_input(prompt, default, validator)
}

#' Get multiple choices
get_multiple_choices <- function(prompt, options, default = NULL) {
  cat(sprintf("%s\n", prompt))
  cat("  Enter numbers separated by commas (e.g., 1,2,4) or 'all'\n")

  if (!is.null(default)) {
    prompt_text <- sprintf("  Choice [default: %s]: ", default)
  } else {
    prompt_text <- "  Choice: "
  }

  repeat {
    cat(prompt_text)
    input <- readline()

    if (input == "" && !is.null(default)) {
      input <- default
    }

    if (tolower(input) == "all") {
      return(options)
    }

    # Parse comma-separated numbers
    indices <- suppressWarnings(as.integer(strsplit(input, ",")[[1]]))

    if (any(is.na(indices)) || any(indices < 1) || any(indices > length(options))) {
      cat(sprintf("  ⚠️  Invalid choice. Enter 1-%d or 'all'\n", length(options)))
    } else {
      return(options[indices])
    }
  }
}

# =============================================================================
# Main Configuration Builder
# =============================================================================

#' Interactive Configuration Builder
#'
#' @return Configuration list
build_config_interactive <- function() {

  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║   DIA Window Optimizer - Interactive Configuration Builder    ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n")
  cat("\n")
  cat("This tool will guide you through creating a configuration file.\n")
  cat("Press Enter to accept default values shown in [brackets].\n")

  config <- list()

  # =========================================================================
  # 1. Project Metadata
  # =========================================================================

  print_section("1. Project Metadata")

  config$project_metadata <- list(
    project_name = get_input("Project name", "DIA_Optimization"),
    date = get_input("Date", format(Sys.Date(), "%Y-%m-%d")),
    analyst = get_input("Analyst name", Sys.getenv("USER")),
    description = get_input("Description (optional)", "")
  )

  # =========================================================================
  # 2. Input Data
  # =========================================================================

  print_section("2. Input Data Files")

  # Auto-detect parquet files
  data_dir <- get_input("Data directory", "data")

  if (dir.exists(data_dir)) {
    parquet_files <- list.files(data_dir, pattern = "\\.parquet$",
                                 full.names = TRUE, recursive = FALSE)

    if (length(parquet_files) > 0) {
      cat(sprintf("\n  Found %d parquet file(s):\n", length(parquet_files)))
      print_options(basename(parquet_files))
      cat("\n")

      use_auto <- get_yesno("Use all detected files?", "y")

      if (use_auto) {
        input_files <- parquet_files
      } else {
        cat("\nEnter file paths (one per line, empty line to finish):\n")
        input_files <- c()
        repeat {
          file <- readline("  File: ")
          if (file == "") break
          if (file.exists(file)) {
            input_files <- c(input_files, file)
          } else {
            cat(sprintf("  ⚠️  File not found: %s\n", file))
          }
        }
      }
    } else {
      cat("  ⚠️  No parquet files found in directory\n")
      input_files <- c()
    }
  } else {
    cat(sprintf("  ⚠️  Directory not found: %s\n", data_dir))
    input_files <- c()
  }

  # Cycle time
  cat("\n")
  auto_cycle <- get_yesno("Auto-estimate cycle time from gradient length?", "y")

  if (auto_cycle) {
    current_cycle_time <- NULL
  } else {
    current_cycle_time <- get_numeric("Current cycle time (seconds)",
                                       default = "1.5", min = 0.1, max = 10.0)
  }

  # Replicate handling
  cat("\n")
  enable_replicate <- get_yesno("Enable technical replicate consensus?", "y")

  config$input_data <- list(
    input_files = input_files,
    current_cycle_time = current_cycle_time,
    enable_replicate_consensus = enable_replicate,
    min_replicates = 1,
    max_intensity_cv_percent = 30
  )

  # =========================================================================
  # 3. Instrument Configuration
  # =========================================================================

  print_section("3. Instrument Configuration")

  # Get available presets
  presets <- get_instrument_presets()
  preset_names <- names(presets)
  preset_descriptions <- sapply(presets, function(x) x$name)

  cat("\nAvailable instrument presets:\n")
  print_options(preset_names, preset_descriptions)
  cat("\n")

  instrument_preset <- get_choice("Select instrument preset", preset_names, "1")

  config$instrument <- list(
    preset = instrument_preset,
    custom_settings = NULL
  )

  # =========================================================================
  # 4. DPPP Parameters
  # =========================================================================

  print_section("4. DPPP (Data Points Per Peak) Parameters")

  cat("\nTarget DPPP modes:\n")
  cat("  [1] Quant Mode (7.0) - Optimal quantification accuracy (recommended)\n")
  cat("  [2] ID Mode (1.5) - Maximum precursor identification\n")
  cat("  [3] Balanced Mode (4.0) - Compromise between ID and Quant\n")
  cat("  [4] Custom value\n")
  cat("\n")

  dppp_choice <- get_choice("Select DPPP mode", c("7.0", "1.5", "4.0", "custom"), "1")

  if (dppp_choice == "custom") {
    target_dppp <- get_numeric("Enter target DPPP", default = "7.0",
                                min = 1.0, max = 15.0)
  } else {
    target_dppp <- as.numeric(dppp_choice)
  }

  cat("\n")
  target_satisfaction <- get_numeric("Target satisfaction ratio (0.70-0.90)",
                                      default = "0.70", min = 0.5, max = 0.95)

  config$dppp_parameters <- list(
    target_dppp = target_dppp,
    target_satisfaction = target_satisfaction,
    dppp_tolerance = 0.0
  )

  # =========================================================================
  # 5. Scan Settings
  # =========================================================================

  print_section("5. Scan Settings")

  load_factor <- get_numeric("Load factor (0.7-0.9)",
                              default = "0.8", min = 0.5, max = 1.0)

  config$scan_settings <- list(
    load_factor = load_factor,
    ms1_scans_per_cycle = NULL,
    warning_threshold_windows = 5
  )

  # =========================================================================
  # 6. RT Binning
  # =========================================================================

  print_section("6. Retention Time Binning")

  rt_bin_width <- get_numeric("RT bin width (minutes)",
                               default = "5.0", min = 1.0, max = 30.0)

  config$rt_binning <- list(
    rt_bin_width_min = rt_bin_width
  )

  # =========================================================================
  # 7. m/z Optimization Strategies
  # =========================================================================

  print_section("7. m/z Optimization Strategies")

  cat("\nAvailable strategies:\n")
  cat("  [1] greedy - MacCoss Lab sliding window (GLOBAL, recommended)\n")
  cat("  [2] kde - Kernel Density Estimation peak-based (GLOBAL)\n")
  cat("  [3] quantile - Fast, robust (P5-P95 range)\n")
  cat("  [4] coverage - Balanced coverage optimization\n")
  cat("  [5] outlier - Maximum coverage with outlier removal\n")
  cat("\n")

  all_strategies <- c("greedy", "kde", "quantile", "coverage", "outlier")

  strategies <- get_multiple_choices("Select strategies", all_strategies, "all")

  config$mz_optimization <- list(
    strategies = strategies,
    quantile_lower = 0.05,
    quantile_upper = 0.95,
    target_coverage = 0.95,
    outlier_threshold = 3.0,
    smoothing_window = 3,
    polynomial_order = 2
  )

  # =========================================================================
  # 8. Window Generation
  # =========================================================================

  print_section("8. Window Generation Mode")

  cat("\nWindow generation modes:\n")
  cat("  [1] variable - Density-adaptive windows (recommended)\n")
  cat("  [2] fixed - Equal-width windows\n")
  cat("  [3] both - Generate both modes\n")
  cat("\n")

  mode_choice <- get_choice("Select mode", c("variable", "fixed", "both"), "1")

  if (mode_choice == "both") {
    window_modes <- c("variable", "fixed")
  } else {
    window_modes <- c(mode_choice)
  }

  cat("\n")
  min_width <- get_numeric("Minimum window width (Da)",
                           default = "2", min = 1, max = 20)
  max_width <- get_numeric("Maximum window width (Da)",
                           default = "80", min = 10, max = 200)

  config$window_generation <- list(
    modes = window_modes,
    min_width_da = min_width,
    max_width_da = max_width,
    overlap_percentage = 0
  )

  # =========================================================================
  # 9. Output Options
  # =========================================================================

  print_section("9. Output Options")

  output_dir <- get_input("Output directory", "results")

  cat("\n")
  include_plots <- get_yesno("Generate visualizations (24 plots)?", "y")
  include_summary <- get_yesno("Generate summary report?", "y")

  config$output <- list(
    output_dir = output_dir,
    include_summary = include_summary,
    include_plots = include_plots
  )

  # =========================================================================
  # Configuration Summary
  # =========================================================================

  print_section("Configuration Summary")

  cat("\n")
  cat(sprintf("  Project: %s\n", config$project_metadata$project_name))
  cat(sprintf("  Input files: %d\n", length(config$input_data$input_files)))
  cat(sprintf("  Instrument: %s\n", config$instrument$preset))
  cat(sprintf("  Target DPPP: %.1f (%.0f%% satisfaction)\n",
              config$dppp_parameters$target_dppp,
              config$dppp_parameters$target_satisfaction * 100))
  cat(sprintf("  Strategies: %s\n", paste(config$mz_optimization$strategies,
                                          collapse = ", ")))
  cat(sprintf("  Window modes: %s\n", paste(config$window_generation$modes,
                                            collapse = ", ")))
  cat(sprintf("  Output: %s\n", config$output$output_dir))
  cat("\n")

  return(config)
}

# =============================================================================
# YAML/JSON Export Functions
# =============================================================================

#' Convert config list to YAML string
#' @param config Configuration list
#' @return YAML string
config_to_yaml <- function(config) {
  lines <- c()

  # Recursive function to convert list to YAML
  list_to_yaml <- function(x, indent = 0) {
    result <- c()
    spaces <- strrep("  ", indent)

    for (name in names(x)) {
      value <- x[[name]]

      if (is.list(value) && !is.null(names(value))) {
        # Named list (object)
        result <- c(result, sprintf("%s%s:", spaces, name))
        result <- c(result, list_to_yaml(value, indent + 1))
      } else if (is.list(value)) {
        # Unnamed list (array)
        result <- c(result, sprintf("%s%s:", spaces, name))
        for (item in value) {
          if (is.character(item)) {
            result <- c(result, sprintf("%s  - \"%s\"", spaces, item))
          } else {
            result <- c(result, sprintf("%s  - %s", spaces,
                                       format(item, scientific = FALSE)))
          }
        }
      } else if (is.null(value)) {
        result <- c(result, sprintf("%s%s: null", spaces, name))
      } else if (is.logical(value)) {
        result <- c(result, sprintf("%s%s: %s", spaces, name,
                                   tolower(as.character(value))))
      } else if (is.character(value)) {
        result <- c(result, sprintf("%s%s: \"%s\"", spaces, name, value))
      } else {
        result <- c(result, sprintf("%s%s: %s", spaces, name,
                                   format(value, scientific = FALSE)))
      }
    }

    return(result)
  }

  yaml_lines <- list_to_yaml(config, 0)
  return(paste(yaml_lines, collapse = "\n"))
}

#' Save configuration to file
#'
#' @param config Configuration list
#' @param file_path Output file path
#' @param format Format ("yaml" or "json")
save_config <- function(config, file_path, format = "yaml") {

  if (format == "yaml") {
    yaml_content <- config_to_yaml(config)
    writeLines(yaml_content, file_path)
  } else if (format == "json") {
    # Use built-in JSON encoder
    if (requireNamespace("jsonlite", quietly = TRUE)) {
      jsonlite::write_json(config, file_path, pretty = TRUE, auto_unbox = TRUE)
    } else {
      stop("jsonlite package required for JSON export. Please install it or use YAML format.")
    }
  } else {
    stop("Unsupported format. Use 'yaml' or 'json'")
  }

  cat(sprintf("\n✅ Configuration saved to: %s\n", file_path))
}

# =============================================================================
# Main Entry Point
# =============================================================================

#' Run interactive configuration builder
#'
#' @param run_immediately Run optimization after creating config?
#' @export
run_config_builder <- function(run_immediately = FALSE) {

  # Build configuration (YAML format only)
  config <- build_config_interactive()

  # Save configuration
  print_section("Save Configuration")

  default_filename <- sprintf("config_%s.yaml",
                              config$project_metadata$project_name)

  output_path <- get_input("Output file path", default_filename)

  # Ensure .yaml extension
  if (!grepl("\\.ya?ml$", output_path, ignore.case = TRUE)) {
    output_path <- sprintf("%s.yaml", output_path)
  }

  # Create config directory if needed
  config_dir <- dirname(output_path)
  if (config_dir != "." && !dir.exists(config_dir)) {
    dir.create(config_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Save as YAML
  save_config(config, output_path, "yaml")

  # Run optimization?
  cat("\n")

  if (run_immediately) {
    should_run <- TRUE
  } else {
    should_run <- get_yesno("Run optimization now?", "n")
  }

  if (should_run) {
    cat("\n")
    cat("╔════════════════════════════════════════════════════════════════╗\n")
    cat("║             Starting Optimization Pipeline                     ║\n")
    cat("╚════════════════════════════════════════════════════════════════╝\n")
    cat("\n")

    # Load and run
    source("run_with_config.R")
    results <- run_optimization(output_path)

    return(invisible(list(config = config, results = results)))
  } else {
    cat("\n")
    cat("To run optimization later:\n")
    cat(sprintf("  source('run_with_config.R')\n"))
    cat(sprintf("  results <- run_optimization('%s')\n", output_path))
    cat("\n")

    return(invisible(config))
  }
}

# =============================================================================
# Usage
# =============================================================================

if (!interactive()) {
  cat("✅ config_builder.R loaded successfully\n")
  cat("   Usage:\n")
  cat("     source('scripts/config_builder.R')\n")
  cat("     config <- run_config_builder()  # Creates YAML configuration\n")
  cat("\n")
}
