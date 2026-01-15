# instrument_utils.R - Instrument configuration utilities
#
# Purpose: Load and manage instrument hardware specifications from JSON
# Version: 2.0 (JSON-based, replaces config/instruments.R)
# Last Updated: 2025-10-27

library(jsonlite)

# =============================================================================
# Configuration Loading
# =============================================================================

#' Load all instrument configurations from JSON
#'
#' @return List of instrument configurations
#' @export
#'
#' @examples
#' configs <- load_instruments_config()
#' names(configs)  # List available instruments
load_instruments_config <- function() {
  # Support both project root and shiny_app/ subdirectory
  json_path <- "config/instruments.json"

  if (!file.exists(json_path)) {
    # Try parent directory (for shiny_app/)
    json_path <- "../config/instruments.json"
  }

  if (!file.exists(json_path)) {
    stop(paste(
      "Instrument configuration file not found.",
      "Please ensure config/instruments.json exists."
    ))
  }

  configs <- tryCatch(
    {
      fromJSON(json_path, simplifyVector = FALSE)
    },
    error = function(e) {
      stop(sprintf(
        "Failed to parse instruments.json: %s\nError: %s",
        json_path, e$message
      ))
    }
  )

  return(configs)
}

#' Get specific instrument configuration
#'
#' @param preset_name Instrument preset name (e.g., "fusion_lumos", "astral")
#' @return Instrument configuration list
#' @export
#'
#' @examples
#' config <- get_instrument_config("fusion_lumos")
#' config$max_scan_rate
get_instrument_config <- function(preset_name) {
  configs <- load_instruments_config()

  if (!preset_name %in% names(configs)) {
    stop(sprintf(
      paste(
        "Unknown instrument preset: '%s'",
        "Available presets: %s"
      ),
      preset_name,
      paste(names(configs), collapse = ", ")
    ))
  }

  config <- configs[[preset_name]]

  # Validate configuration
  validate_instrument_config(config, preset_name)

  return(config)
}

# =============================================================================
# Information and Listing
# =============================================================================

#' List all available instruments
#'
#' @return Data frame with instrument information
#' @export
#'
#' @examples
#' list_available_instruments()
list_available_instruments <- function() {
  configs <- load_instruments_config()

  df <- data.frame(
    Preset = names(configs),
    Name = sapply(configs, function(x) x$name),
    MS1_Time_ms = sapply(configs, function(x) x$ms1_time),
    MS2_Time_ms = sapply(configs, function(x) x$ms2_time),
    Max_Hz = sapply(configs, function(x) x$max_scan_rate),
    Cycle_Calc = sapply(configs, function(x) x$cycle_calculation),
    MS1_Scans = sapply(configs, function(x) x$ms1_scans_per_cycle),
    stringsAsFactors = FALSE
  )

  return(df)
}

#' Print instrument information
#'
#' @param preset_name Instrument preset name
#' @export
#'
#' @examples
#' print_instrument_info("fusion_lumos")
print_instrument_info <- function(preset_name) {
  config <- get_instrument_config(preset_name)

  cat("\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║              INSTRUMENT CONFIGURATION                          ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  cat(sprintf("Preset: %s\n", preset_name))
  cat(sprintf("Name: %s\n", config$name))
  cat(sprintf("Description: %s\n\n", config$description))

  cat("Hardware Specifications:\n")
  cat(sprintf("  MS1 time: %.1f ms\n", config$ms1_time))
  cat(sprintf("  MS2 time: %.1f ms\n", config$ms2_time))
  cat(sprintf("  Max scan rate: %d Hz\n", config$max_scan_rate))
  cat(sprintf("  Cycle calculation: %s\n", config$cycle_calculation))
  cat(sprintf("  MS1 scans per cycle: %d\n", config$ms1_scans_per_cycle))

  cat("\n")
}

# =============================================================================
# Validation
# =============================================================================

#' Validate instrument configuration
#'
#' @param config Instrument configuration list
#' @param preset_name Preset name for error messages
#' @return Logical (TRUE if valid, stops on error)
#' @keywords internal
validate_instrument_config <- function(config, preset_name = "unknown") {
  errors <- character()

  # Required fields
  required <- c("name", "ms1_time", "ms2_time", "max_scan_rate",
                "cycle_calculation", "ms1_scans_per_cycle", "max_windows", "description")

  missing <- setdiff(required, names(config))
  if (length(missing) > 0) {
    errors <- c(errors, sprintf(
      "Missing required fields: %s",
      paste(missing, collapse = ", ")
    ))
  }

  # Validate ms1_time
  if (!is.null(config$ms1_time)) {
    if (!is.numeric(config$ms1_time) ||
        config$ms1_time <= 0 ||
        config$ms1_time > 1000) {
      errors <- c(errors, "ms1_time must be numeric between 0 and 1000 ms")
    }
  }

  # Validate ms2_time
  if (!is.null(config$ms2_time)) {
    if (!is.numeric(config$ms2_time) ||
        config$ms2_time <= 0 ||
        config$ms2_time > 500) {
      errors <- c(errors, "ms2_time must be numeric between 0 and 500 ms")
    }
  }

  # Validate max_scan_rate
  if (!is.null(config$max_scan_rate)) {
    if (!is.numeric(config$max_scan_rate) ||
        config$max_scan_rate <= 0 ||
        config$max_scan_rate > 500) {
      errors <- c(errors, "max_scan_rate must be numeric between 0 and 500 Hz")
    }
  }

  # Validate cycle_calculation
  if (!is.null(config$cycle_calculation)) {
    if (!config$cycle_calculation %in% c("parallel", "sequential")) {
      errors <- c(errors,
                 "cycle_calculation must be 'parallel' or 'sequential'")
    }
  }

  # Validate ms1_scans_per_cycle
  if (!is.null(config$ms1_scans_per_cycle)) {
    if (!is.numeric(config$ms1_scans_per_cycle) ||
        !config$ms1_scans_per_cycle %in% c(0, 1)) {
      errors <- c(errors, "ms1_scans_per_cycle must be 0 or 1")
    }
  }

  # Validate max_windows
  if (!is.null(config$max_windows)) {
    if (!is.numeric(config$max_windows) ||
        config$max_windows < 50 ||
        config$max_windows > 1000) {
      errors <- c(errors, "max_windows must be numeric between 50 and 1000")
    }
  }

  # Logical consistency checks
  if (!is.null(config$cycle_calculation) &&
      !is.null(config$ms1_scans_per_cycle)) {

    # Parallel instruments should have 0 MS1 scans (MS1 acquired during MS2)
    if (config$cycle_calculation == "parallel" &&
        config$ms1_scans_per_cycle != 0) {
      errors <- c(errors,
        "Parallel instruments should have ms1_scans_per_cycle = 0 (MS1 acquired during MS2)")
    }

    # Sequential instruments should have 1 MS1 scan (MS1 before MS2)
    if (config$cycle_calculation == "sequential" &&
        config$ms1_scans_per_cycle != 1) {
      errors <- c(errors,
        "Sequential instruments should have ms1_scans_per_cycle = 1 (MS1 acquired before MS2)")
    }
  }

  if (length(errors) > 0) {
    stop(sprintf(
      "Instrument config validation failed for '%s':\n  - %s",
      preset_name,
      paste(errors, collapse = "\n  - ")
    ))
  }

  return(TRUE)
}

# =============================================================================
# Helper Functions
# =============================================================================

#' Calculate effective scan rate with load factor
#'
#' @param max_scan_rate_hz Maximum scan rate in Hz
#' @param load_factor Load factor (0-1), typically 0.8 for stability
#' @return Effective scan rate in Hz
#' @export
#'
#' @examples
#' # Fusion Lumos with 80% load factor
#' calculate_effective_scan_rate(20, 0.8)  # Returns 16 Hz
calculate_effective_scan_rate <- function(max_scan_rate_hz, load_factor = 0.8) {

  # Validate inputs
  if (!is.numeric(max_scan_rate_hz) || max_scan_rate_hz <= 0) {
    stop("max_scan_rate_hz must be a positive number")
  }

  if (!is.numeric(load_factor) || load_factor <= 0 || load_factor > 1) {
    stop("load_factor must be between 0 and 1")
  }

  effective_rate <- max_scan_rate_hz * load_factor

  return(effective_rate)
}

#' Get ms1_scans_per_cycle with automatic detection
#'
#' @param ms1_scans_per_cycle User-specified value (NULL for auto-detect)
#' @param instrument_config Instrument configuration from JSON
#' @return Integer (0 or 1)
#' @export
#'
#' @examples
#' config <- get_instrument_config("fusion_lumos")
#' get_ms1_scans_per_cycle(NULL, config)  # Returns 1 (sequential)
get_ms1_scans_per_cycle <- function(ms1_scans_per_cycle, instrument_config) {

  if (!is.null(ms1_scans_per_cycle)) {
    # User specified value
    if (!ms1_scans_per_cycle %in% c(0, 1)) {
      stop("ms1_scans_per_cycle must be 0 or 1")
    }
    return(as.integer(ms1_scans_per_cycle))
  }

  # Auto-detect from instrument config
  if (!is.null(instrument_config$ms1_scans_per_cycle)) {
    return(as.integer(instrument_config$ms1_scans_per_cycle))
  }

  # Fallback: Use cycle_calculation
  if (!is.null(instrument_config$cycle_calculation)) {
    value <- ifelse(instrument_config$cycle_calculation == "parallel", 0, 1)
    return(as.integer(value))
  }

  # Ultimate fallback: Sequential (most common)
  warning("Could not determine ms1_scans_per_cycle, using default value 1 (sequential)")
  return(1L)
}
