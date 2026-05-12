# instrument_config.R - Instrument metadata: loading, validation, classification
#
# Purpose: All queries about "what does this instrument look like" \u2014 JSON I/O,
#          schema validation, analyzer-type predicates, width recommendations.
# Split from the legacy instrument_utils.R in v0.4.1.


# =============================================================================
# Configuration Loading
# =============================================================================

#' Load all instrument configurations from JSON
#'
#' @return List of instrument configurations
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' configs <- load_instruments_config()
#' names(configs)  # List available instruments
#' }
load_instruments_config <- function() {
  # Package-aware path resolution
  json_path <- system.file("config", "instruments.json", package = "aidia")
  if (!nzchar(json_path) || !file.exists(json_path)) {
    # Development fallback paths
    candidates <- c(
      "inst/config/instruments.json",
      "config/instruments.json",
      "../config/instruments.json",
      "../inst/config/instruments.json"
    )
    for (candidate in candidates) {
      if (file.exists(candidate)) {
        json_path <- candidate
        break
      }
    }
  }

  if (!nzchar(json_path) || !file.exists(json_path)) {
    stop(paste(
      "Instrument configuration file not found.",
      "Please ensure config/instruments.json exists."
    ))
  }

  configs <- tryCatch(
    {
      jsonlite::fromJSON(json_path, simplifyVector = FALSE)
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
#' \dontrun{
#' config <- get_instrument_config("fusion_lumos")
#' config$max_scan_rate
#' }
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
# Instrument Classification
# =============================================================================

#' Get Instrument Analyzer Type
#'
#' Returns the analyzer_type field from the instrument configuration.
#'
#' @param preset_name Character, instrument preset name
#'
#' @return Character, analyzer type (e.g., "orbitrap", "astral")
#' @keywords internal
get_instrument_analyzer_type <- function(preset_name) {
  config <- get_instrument_config(preset_name)
  config$analyzer_type
}

#' Check if Instrument is Orbitrap-Based
#'
#' @param preset_name Character, instrument preset name
#'
#' @return Logical, TRUE if the instrument uses an Orbitrap analyzer
#' @export
is_orbitrap_instrument <- function(preset_name) {
  get_instrument_analyzer_type(preset_name) == "orbitrap"
}

#' Check if Instrument is Astral-Based
#'
#' @param preset_name Character, instrument preset name
#'
#' @return Logical, TRUE if the instrument uses an Astral analyzer
#' @export
is_astral_instrument <- function(preset_name) {
  get_instrument_analyzer_type(preset_name) == "astral"
}


# =============================================================================
# Information and Listing
# =============================================================================

#' List all available instruments
#'
#' Returns a data frame summarising every instrument preset shipped with the
#' package, sourced from \code{inst/config/instruments.json}. Use this to
#' discover which presets you can pass to \code{run_complete_pipeline()} or
#' \code{get_instrument_config()}.
#'
#' @return Data frame with one row per instrument preset, columns: Preset,
#'   Name, MS1_Time_ms, MS2_Time_ms, Max_Hz, Cycle_Calc, MS1_Scans.
#' @export
#'
#' @examples
#' \dontrun{
#' list_available_instruments()
#' }
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
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' print_instrument_info("fusion_lumos")
#' }
print_instrument_info <- function(preset_name) {
  config <- get_instrument_config(preset_name)

  cat("\n+================================================================+\n")
  cat("|              INSTRUMENT CONFIGURATION                          |\n")
  cat("+================================================================+\n\n")

  cat(sprintf("Preset: %s\n", preset_name))
  cat(sprintf("Name: %s\n", config$name))
  cat(sprintf("Description: %s\n\n", config$description))

  cat("Hardware Specifications:\n")
  cat(sprintf("  MS1 time: %.1f ms\n", config$ms1_time))
  if (is.numeric(config$ms2_time)) {
    cat(sprintf("  MS2 time: %.1f ms\n", config$ms2_time))
  } else {
    cat(sprintf("  MS2 time: %s\n", config$ms2_time))
  }
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

  # Validate ms2_time (numeric or "auto")
  if (!is.null(config$ms2_time)) {
    is_auto <- is.character(config$ms2_time) && tolower(config$ms2_time) == "auto"
    is_valid_numeric <- is.numeric(config$ms2_time) &&
                        config$ms2_time > 0 &&
                        config$ms2_time <= 500

    if (!is_auto && !is_valid_numeric) {
      errors <- c(errors, "ms2_time must be numeric (0-500 ms) or 'auto'")
    }

    # "auto" requires Orbitrap analyzer
    if (is_auto && !is.null(config$analyzer_type) &&
        config$analyzer_type != "orbitrap") {
      errors <- c(errors,
        "ms2_time='auto' is only supported for Orbitrap analyzers")
    }

    # "auto" requires ms2_resolution
    if (is_auto && is.null(config$ms2_resolution)) {
      errors <- c(errors,
        "ms2_time='auto' requires ms2_resolution to be specified")
    }
  }

  # Validate analyzer_type
  valid_analyzers <- c("orbitrap", "astral", "tof")
  if (!is.null(config$analyzer_type)) {
    if (!config$analyzer_type %in% valid_analyzers) {
      errors <- c(errors, sprintf(
        "analyzer_type must be one of: %s (got: '%s')",
        paste(valid_analyzers, collapse = ", "),
        config$analyzer_type
      ))
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
# Width Recommendations
# =============================================================================

#' Get Instrument Width Recommendations from JSON Config
#'
#' Reads recommended_min_width_da and recommended_max_width_da from the
#' instrument JSON configuration. Falls back to sensible defaults.
#'
#' @param instrument_config List, instrument config from get_instrument_config()
#'
#' @return List with min_width_da and max_width_da
#' @export
get_instrument_width_recommendations <- function(instrument_config) {
  list(
    min_width_da = instrument_config$recommended_min_width_da %||% 2,
    max_width_da = instrument_config$recommended_max_width_da %||% 80
  )
}
