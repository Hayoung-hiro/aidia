# instrument_utils.R - Instrument configuration utilities
#
# Purpose: Load and manage instrument hardware specifications from JSON
# Version: 2.1 (Updated with Astral MR-TOF support)
# Last Updated: 2026-01-29


# =============================================================================
# Constants: Resolution-Transient Time Mapping (Orbitrap)
# =============================================================================
# Theoretical relationship: Transient Time proportional to Resolution
# These values are for Orbitrap analyzers (Thermo Fisher)
# Reference: Orbitrap physics - higher resolution requires longer transient
#
# Source: https://proteomicsresource.washington.edu/instruments/orbitrapexploris480.php

#' Orbitrap Resolution to Transient Time Mapping
#'
#' Standard mapping for Thermo Orbitrap analyzers.
#' Transient time is the ion detection time in the Orbitrap.
#'
#' @format Named numeric vector (resolution -> transient_time_ms)
#' @keywords internal
ORBITRAP_TRANSIENT_TIME_MS <- c(
  "7500"   = 16,
  "15000"  = 32,
  "30000"  = 64,
  "45000"  = 96,
  "60000"  = 128,
  "120000" = 256,
  "240000" = 512,
  "480000" = 1024
)

# =============================================================================
# Constants: Astral Analyzer (Multi-Reflection TOF)
# =============================================================================
# The Astral analyzer is NOT an Orbitrap - it's a Multi-Reflection TOF
# Key characteristics:
#   - Fixed resolution: 80,000 @ m/z 524 (cannot be changed)
#   - Scan rate depends on injection time (NOT resolution)
#   - Parallel architecture: ion accumulation overlaps with detection
#   - Max rate: 200 Hz (5ms/scan) with up to 3ms IT
#
# Source: https://proteomicsresource.washington.edu/instruments/astral.php
# Reference: Anal. Chem. 2023 (PMC10603608)
#
# Timing breakdown at 200 Hz:
#   - Total cycle: 5 ms (1000/200)
#   - Non-parallelizable stages: ~4.5 ms
#   - Max IT at 200 Hz: ~3 ms (60% duty cycle)
#   - Parallelization allows IT to overlap with detection/processing

#' Astral Analyzer Fixed Parameters
#'
#' The Astral uses a Multi-Reflection TOF design with fixed resolution.
#' Scan rate is determined by injection time, not resolution.
#'
#' @keywords internal
ASTRAL_FIXED_RESOLUTION <- 80000  # Fixed at m/z 524

#' Astral Detection Time (ms)
#'
#' Fixed detection time for the Astral MR-TOF analyzer.
#' Unlike Orbitrap, this doesn't change with resolution (fixed at 80K).
#' The MR-TOF has ~2.5ms detection time in standard operation.
#'
#' @keywords internal
ASTRAL_DETECTION_TIME_MS <- 2.5

#' Astral Minimum Cycle Time (ms)
#'
#' The minimum time per scan at maximum speed (200 Hz).
#' This includes all parallelized operations.
#'
#' @keywords internal
ASTRAL_MIN_CYCLE_TIME_MS <- 5.0  # 1000 / 200 Hz

#' Astral Injection Time to Scan Rate Mapping
#'
#' Empirical relationship between max IT and achievable scan rate.
#' Due to parallel architecture, IT up to 3ms doesn't slow down 200 Hz operation.
#' Beyond 3ms, IT starts to dominate the cycle time.
#'
#' Source: https://proteomicsresource.washington.edu/instruments/astral.php
#'
#' @format Named numeric vector (injection_time_ms -> scan_rate_hz)
#' @keywords internal
ASTRAL_IT_TO_SCANRATE <- c(
  "2.5" = 200,   # Maximum speed
  "3.0" = 200,   # Still at max (parallelized)
  "3.5" = 187,   # IT starts to dominate
  "5.0" = 133,   # Moderate IT
  "10.0" = 67,   # Longer IT for sensitivity
  "20.0" = 25,   # High sensitivity mode
  "40.0" = 12.5  # Maximum sensitivity
)

#' Default Orbitrap 240K Transient Time (ms)
#'
#' Fallback value when resolution lookup returns NA.
#' 240K is the default MS1 resolution for Astral instruments.
#' @keywords internal
ORBITRAP_240K_TRANSIENT_MS <- 512

#' Default MS1 Overhead (ms)
#'
#' Fallback value when instrument JSON does not specify ms1_overhead_ms.
#' Based on typical C-trap/IRM timing for modern Orbitrap instruments.
#' @keywords internal
DEFAULT_MS1_OVERHEAD_MS <- 10.0


# =============================================================================
# Constants: Overhead Modeling
# =============================================================================
# delta (overhead) includes:
#   - Ion transfer time between mass analyzers
#   - C-trap fill/empty time
#   - Orbitrap stabilization time
#   - HCD cell operation time
#   - Data transfer overhead
#
# Typical values:
#   - delta ~= 0.15-0.25 x Transient Time (15-25% overhead)
#   - Minimum delta ~= 3-5 ms for modern instruments

#' Default Overhead Factor
#'
#' Overhead as fraction of transient time.
#' Conservative estimate for stable operation.
#' @keywords internal
DEFAULT_OVERHEAD_FACTOR <- 0.20  # 20% of transient time

#' Minimum Overhead (ms)
#'
#' Hardware minimum overhead regardless of transient time.
#' Accounts for ion transfer and settling times.
#' @keywords internal
MINIMUM_OVERHEAD_MS <- 5.0

#' Calculate Scan Overhead
#'
#' Estimates the overhead time (delta) for each MS2 scan.
#' delta includes ion transfer, C-trap operation, and data handling.
#'
#' @param transient_time_ms Numeric, transient time in milliseconds
#' @param overhead_factor Numeric, overhead as fraction of transient (default: 0.20)
#' @param min_overhead_ms Numeric, minimum overhead in ms (default: 5.0)
#'
#' @return Numeric, overhead time in milliseconds
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' calculate_scan_overhead(64)   # For 30K resolution: returns ~12.8 ms
#' calculate_scan_overhead(32)   # For 15K resolution: returns ~6.4 ms
#' calculate_scan_overhead(16)   # For 7.5K resolution: returns 5 ms (minimum)
#' }
calculate_scan_overhead <- function(transient_time_ms,
                                     overhead_factor = DEFAULT_OVERHEAD_FACTOR,
                                     min_overhead_ms = MINIMUM_OVERHEAD_MS) {

  calculated_overhead <- transient_time_ms * overhead_factor
  overhead <- max(calculated_overhead, min_overhead_ms)

  return(round(overhead, 2))
}

#' Calculate Maximum Injection Time
#'
#' Determines the maximum IT that maintains efficiency.
#' Formula: IT_max <= Transient_Time - delta
#'
#' @param transient_time_ms Numeric, transient time in ms
#' @param overhead_ms Numeric, overhead time in ms (or NULL for auto-calculate)
#' @param safety_margin Numeric, additional margin factor (default: 0.95)
#'
#' @return Numeric, maximum injection time in milliseconds
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' calculate_max_injection_time(64)  # 30K: ~64 - 12.8 = ~51 ms
#' calculate_max_injection_time(32)  # 15K: ~32 - 6.4 = ~25.6 ms
#' }
calculate_max_injection_time <- function(transient_time_ms,
                                          overhead_ms = NULL,
                                          safety_margin = 0.95) {

  if (is.null(overhead_ms)) {
    overhead_ms <- calculate_scan_overhead(transient_time_ms)
  }

  # IT_max = Transient - delta, with safety margin
  it_max <- (transient_time_ms - overhead_ms) * safety_margin

  # Ensure positive IT
  it_max <- max(it_max, 1.0)

  return(round(it_max, 2))
}

#' Calculate MS2 Scan Time
#'
#' Calculates the total time for a single MS2 scan based on the fundamental
#' scan time equation: t_scan = max(T_transient, IT) + delta
#'
#' This is the core formula for accurate window count calculation:
#' - Resolution determines T_transient (detection time floor)
#' - IT can be shorter (Resolution-Limited) or longer (Sensitivity-Limited)
#' - Overhead (delta) is always added
#'
#' ## Efficiency Modes (Orbitrap)
#'
#' **Auto Mode (IT = T_transient)**: 100% efficiency (Resolution Limited)
#' - Optimal balance between speed and sensitivity
#' - No wasted scan time
#'
#' **Custom Mode (IT > T_transient)**: Reduced efficiency (Injection Limited)
#' - Longer cycle time, fewer windows per cycle
#' - DPPP may decrease
#' - Use for low-abundance samples requiring more sensitivity
#'
#' @param resolution Numeric, Orbitrap resolution (e.g., 30000)
#' @param injection_time_ms Numeric, injection time in milliseconds
#' @param overhead_ms Numeric, overhead in ms (NULL for auto-calculate from transient)
#' @param analyzer Character, analyzer type (default: "orbitrap")
#' @param verbose Logical, print efficiency warnings (default: TRUE)
#'
#' @return List with scan time breakdown:
#'   - t_scan_ms: Total scan time in milliseconds
#'   - transient_ms: Transient time from resolution
#'   - injection_time_ms: Input IT
#'   - overhead_ms: Calculated or provided overhead
#'   - limiting_factor: "resolution", "sensitivity", "balanced", or "parallel"
#'   - sweet_spot_it_ms: Recommended IT for optimal efficiency
#'   - efficiency_pct: Efficiency percentage (100% = optimal)
#'   - efficiency_mode: "auto" (optimal) or "custom" (user-defined)
#'   - efficiency_message: Human-readable efficiency status
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' calculate_ms2_scan_time(30000, 50)   # 30K, 50ms IT -> 76.8 ms
#' calculate_ms2_scan_time(30000, 80)   # 30K, 80ms IT -> 92.8 ms
#' calculate_ms2_scan_time(80000, 3.0, analyzer = "astral")  # Astral
#' }
calculate_ms2_scan_time <- function(resolution = 30000,
                                     injection_time_ms,
                                     overhead_ms = NULL,
                                     analyzer = "orbitrap",
                                     verbose = TRUE) {

  # =========================================================================
  # Astral Analyzer (Multi-Reflection TOF with Parallel Architecture)
  # =========================================================================
  # Astral uses parallel ion accumulation - IT overlaps with detection/processing
  # Key timing:
  #   - Minimum cycle: 5 ms (200 Hz max)
  #   - IT up to 3 ms: parallelized, doesn't slow down 200 Hz
  #   - IT > 3 ms: starts to dominate cycle time
  #
  # Formula: t_scan = max(5.0 ms, IT + buffer)
  # where buffer accounts for non-overlapping operations (~2 ms)
  if (analyzer == "astral") {
    min_cycle_ms <- ASTRAL_MIN_CYCLE_TIME_MS  # 5.0 ms
    parallel_threshold_ms <- 3.0  # IT threshold for parallel operation

    # Astral parallel architecture:
    # - IT <= 3ms: cycle time stays at minimum (5ms)
    # - IT > 3ms: cycle time = IT + ~2ms buffer
    if (injection_time_ms <= parallel_threshold_ms) {
      t_scan_ms <- min_cycle_ms
      limiting_factor <- "parallel"  # Operating within parallel capacity
      effective_time_ms <- min_cycle_ms
      efficiency_pct <- 100.0
      efficiency_mode <- "auto"
      efficiency_message <- "\uc7a5\ube44 \ud6a8\uc728 100% (Parallel Mode - 200 Hz)"
      efficiency_message_en <- "Instrument efficiency 100% (Parallel Mode - 200 Hz)"
    } else {
      # IT exceeds parallel capacity, becomes IT-limited
      buffer_ms <- overhead_ms %||% 2.0
      t_scan_ms <- injection_time_ms + buffer_ms
      limiting_factor <- "sensitivity"
      effective_time_ms <- injection_time_ms

      # Calculate efficiency relative to max speed (200 Hz = 5ms)
      efficiency_pct <- round((min_cycle_ms / t_scan_ms) * 100, 1)
      efficiency_mode <- "custom"
      efficiency_message <- sprintf(
        "\uc7a5\ube44 \ud6a8\uc728 %.1f%% (Sensitivity Mode) - \ub354 \uae34 IT\ub85c \uac10\ub3c4 \ud5a5\uc0c1",
        efficiency_pct
      )
      efficiency_message_en <- sprintf(
        "Instrument efficiency %.1f%% (Sensitivity Mode) - Increased IT for better sensitivity",
        efficiency_pct
      )

      if (verbose) {
        message(sprintf(
          "Astral Sensitivity Mode: IT=%.1f ms -> %.0f Hz (Max: 200 Hz at IT<=3ms)",
          injection_time_ms, 1000 / t_scan_ms
        ))
      }
    }

    # Calculate theoretical scan rate
    scan_rate_hz <- 1000 / t_scan_ms

    # Sweet spot for Astral: 3ms (maximum IT without slowing down)
    sweet_spot_it_ms <- parallel_threshold_ms

    return(list(
      t_scan_ms = round(t_scan_ms, 2),
      transient_ms = ASTRAL_DETECTION_TIME_MS,  # Detection time for reference
      injection_time_ms = injection_time_ms,
      overhead_ms = 0,   # No separate overhead (parallel architecture)
      effective_time_ms = round(effective_time_ms, 2),
      limiting_factor = limiting_factor,
      sweet_spot_it_ms = sweet_spot_it_ms,
      scan_rate_hz = round(scan_rate_hz, 1),
      analyzer = "astral",
      efficiency_pct = efficiency_pct,
      efficiency_mode = efficiency_mode,
      efficiency_message = efficiency_message,
      efficiency_message_en = efficiency_message_en
    ))
  }

  # =========================================================================
  # TOF Analyzers (timsTOF, SCIEX, Waters)
  # =========================================================================
  # TOF has no transient time concept; scan time ~= IT + fixed overhead
  if (analyzer == "tof") {
    if (is.null(overhead_ms)) {
      overhead_ms <- MINIMUM_OVERHEAD_MS
    }

    # Simple formula: t_scan = IT + overhead
    t_scan_ms <- injection_time_ms + overhead_ms
    scan_rate_hz <- 1000 / t_scan_ms

    return(list(
      t_scan_ms = round(t_scan_ms, 2),
      transient_ms = 0,
      injection_time_ms = injection_time_ms,
      overhead_ms = round(overhead_ms, 2),
      effective_time_ms = injection_time_ms,
      limiting_factor = "sensitivity",  # TOF is always IT-limited
      sweet_spot_it_ms = injection_time_ms,
      scan_rate_hz = round(scan_rate_hz, 1),
      analyzer = "tof",
      efficiency_pct = 100.0,  # TOF efficiency is relative to IT chosen
      efficiency_mode = "auto",
      efficiency_message = "TOF \ud6a8\uc728 100% (IT-dependent)",
      efficiency_message_en = "TOF efficiency 100% (IT-dependent)"
    ))
  }

  # =========================================================================
  # Orbitrap Analyzers (Q Exactive, Exploris, Eclipse, Fusion)
  # =========================================================================
  transient_ms <- get_transient_time(resolution, analyzer)

  # Handle unknown analyzer types (fallback to Orbitrap-like)
  if (is.na(transient_ms)) {
    transient_ms <- 0
    if (is.null(overhead_ms)) {
      overhead_ms <- MINIMUM_OVERHEAD_MS
    }
  } else {
    # Calculate overhead if not provided
    if (is.null(overhead_ms)) {
      overhead_ms <- calculate_scan_overhead(transient_ms)
    }
  }

  # Core formula: t_scan = max(T_transient, IT) + delta
  effective_time_ms <- max(transient_ms, injection_time_ms)
  t_scan_ms <- effective_time_ms + overhead_ms

  # Determine limiting factor and efficiency
  if (transient_ms > injection_time_ms) {
    limiting_factor <- "resolution"
    efficiency_mode <- "auto"  # Resolution-limited = optimal for speed
    efficiency_pct <- 100.0    # Full efficiency
    efficiency_message <- "\uc7a5\ube44 \ud6a8\uc728 100% (Resolution Limited)"
    efficiency_message_en <- "Instrument efficiency 100% (Resolution Limited)"
  } else if (injection_time_ms > transient_ms) {
    limiting_factor <- "sensitivity"
    efficiency_mode <- "custom"  # User chose longer IT for sensitivity

    # Calculate efficiency loss: ratio of optimal vs actual scan time
    optimal_scan_ms <- transient_ms + overhead_ms
    efficiency_pct <- round((optimal_scan_ms / t_scan_ms) * 100, 1)
    efficiency_message <- sprintf(
      "\uc7a5\ube44 \ud6a8\uc728 \uac10\uc18c %.1f%% (Injection Limited) - IT\uac00 T_transient\ubcf4\ub2e4 %.1f ms \uae41\ub2c8\ub2e4",
      efficiency_pct, injection_time_ms - transient_ms
    )
    efficiency_message_en <- sprintf(
      "Reduced efficiency %.1f%% (Injection Limited) - IT exceeds T_transient by %.1f ms",
      efficiency_pct, injection_time_ms - transient_ms
    )

    # Print warning if verbose
    if (verbose && transient_ms > 0) {
      message(sprintf(
        paste0(
          "\n",
          "====================================================================\n",
          "[!] \ud6a8\uc728\uc131 \uacbd\uace0 (Efficiency Warning)\n",
          "====================================================================\n",
          "  \ud604\uc7ac IT (%.1f ms) > T_transient (%.1f ms)\n",
          "  \uc774\uc628 \uc8fc\uc785 \uc2dc\uac04\uc73c\ub85c \uc778\ud574 \uc804\uccb4 \uc0ac\uc774\ud074\uc774 \ub290\ub824\uc9c0\uba70 DPPP\uac00 \ud558\ub77d\ud560 \uc218 \uc788\uc2b5\ub2c8\ub2e4.\n",
          "\n",
          "  Current IT (%.1f ms) > T_transient (%.1f ms)\n",
          "  Longer injection time may slow cycle time and reduce DPPP.\n",
          "\n",
          "  \uad8c\uc7a5 (Recommended): IT = %.1f ms (Auto/Sweet Spot \ubaa8\ub4dc)\n",
          "  \ud6a8\uc728\uc131 (Efficiency): %.1f%%\n",
          "====================================================================\n"
        ),
        injection_time_ms, transient_ms,
        injection_time_ms, transient_ms,
        transient_ms, efficiency_pct
      ))
    }
  } else {
    limiting_factor <- "balanced"  # IT ~= T_transient (Sweet Spot)
    efficiency_mode <- "auto"
    efficiency_pct <- 100.0
    efficiency_message <- "\uc7a5\ube44 \ud6a8\uc728 100% (Balanced - Sweet Spot)"
    efficiency_message_en <- "Instrument efficiency 100% (Balanced - Sweet Spot)"
  }

  # Sweet spot IT (~= T_transient for Orbitrap)
  sweet_spot_it_ms <- ifelse(transient_ms > 0, transient_ms, injection_time_ms)

  # Calculate scan rate
  scan_rate_hz <- 1000 / t_scan_ms

  return(list(
    t_scan_ms = round(t_scan_ms, 2),
    transient_ms = round(transient_ms, 2),
    injection_time_ms = injection_time_ms,
    overhead_ms = round(overhead_ms, 2),
    effective_time_ms = round(effective_time_ms, 2),
    limiting_factor = limiting_factor,
    sweet_spot_it_ms = round(sweet_spot_it_ms, 2),
    scan_rate_hz = round(scan_rate_hz, 1),
    analyzer = "orbitrap",
    efficiency_pct = efficiency_pct,
    efficiency_mode = efficiency_mode,
    efficiency_message = efficiency_message,
    efficiency_message_en = efficiency_message_en
  ))
}


#' Get Transient Time (or Detection Time) for Resolution
#'
#' Returns the transient/detection time (ms) for a given resolution and analyzer.
#' - Orbitrap: Uses linear interpolation for non-standard resolutions
#' - Astral: Returns fixed detection time (resolution is fixed at 80K)
#' - TOF: Returns NA (no transient time concept)
#'
#' @param resolution Numeric, target resolution (e.g., 30000)
#' @param analyzer Character, analyzer type: "orbitrap", "astral", or "tof"
#'
#' @return Numeric, transient/detection time in milliseconds (NA for TOF)
#' @export
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' get_transient_time(30000, "orbitrap")  # Returns 64 ms
#' get_transient_time(15000, "orbitrap")  # Returns 32 ms
#' get_transient_time(80000, "astral")    # Returns 2.5 ms (fixed)
#' get_transient_time(30000, "tof")       # Returns NA
#' }
get_transient_time <- function(resolution, analyzer = "orbitrap") {

 # Astral analyzer (Multi-Reflection TOF)
  # Fixed resolution, fixed detection time
  if (analyzer == "astral") {
    # Astral has fixed detection time regardless of resolution setting
    return(ASTRAL_DETECTION_TIME_MS)
  }

  # TOF analyzers don't have transient time concept
  if (analyzer == "tof") {
    return(NA)
  }

  # Orbitrap analyzers
  if (analyzer != "orbitrap") {
    warning(sprintf(
      "Unknown analyzer type '%s'. Assuming Orbitrap-like behavior.",
      analyzer
    ))
  }

  resolution <- as.numeric(resolution)

  # Check for exact match
  res_str <- as.character(resolution)
  if (res_str %in% names(ORBITRAP_TRANSIENT_TIME_MS)) {
    return(as.numeric(ORBITRAP_TRANSIENT_TIME_MS[res_str]))
  }

  # Interpolate for non-standard resolution
  known_res <- as.numeric(names(ORBITRAP_TRANSIENT_TIME_MS))
  known_times <- as.numeric(ORBITRAP_TRANSIENT_TIME_MS)

  if (resolution < min(known_res)) {
    warning(sprintf("Resolution %d below minimum (%d). Using minimum transient time.",
                    resolution, min(known_res)))
    return(min(known_times))
  }

  if (resolution > max(known_res)) {
    warning(sprintf("Resolution %d above maximum (%d). Using maximum transient time.",
                    resolution, max(known_res)))
    return(max(known_times))
  }

  # Linear interpolation (in log-log space for accuracy)
  log_res <- log10(known_res)
  log_times <- log10(known_times)
  interpolated <- 10^approx(log_res, log_times, xout = log10(resolution))$y

  return(round(interpolated, 1))
}

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
#' @keywords internal
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
#' @export
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
#' @return Data frame with instrument information
#' @keywords internal
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
# Helper Functions
# =============================================================================

#' Calculate effective scan rate with load factor
#'
#' @param max_scan_rate_hz Maximum scan rate in Hz
#' @param load_factor Load factor (0-1), typically 0.8 for stability
#' @return Effective scan rate in Hz
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' # Fusion Lumos with 80% load factor
#' calculate_effective_scan_rate(20, 0.8)  # Returns 16 Hz
#' }
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

#' Resolve Injection Time (Handle 'auto' Mode)
#'
#' Resolves the injection time value, handling the special 'auto' mode
#' used by Thermo Orbitrap instruments. When IT is set to 'auto', the
#' instrument synchronizes IT to T_transient (Sweet Spot mode).
#'
#' @param ms2_time Injection time in ms, or "auto" string
#' @param resolution Numeric, Orbitrap resolution (required when ms2_time is "auto")
#' @param analyzer_type Character, analyzer type (default: "orbitrap")
#'
#' @return Numeric, resolved injection time in milliseconds
#' @keywords internal
#'
#' @details
#' When ms2_time = "auto":
#'   - For Orbitrap analyzers: IT = T_transient (balanced/sweet spot mode)
#'   - This maximizes efficiency: no wasted time, no sensitivity loss
#'   - Example: 30K resolution -> IT = 64 ms (= T_transient)
#'
#' When ms2_time is numeric:
#'   - Returns the value unchanged
#'
#' @examples
#' \dontrun{
#' resolve_injection_time("auto", 30000, "orbitrap")  # 64 ms
#' resolve_injection_time(50, 30000, "orbitrap")       # Returns 50
#' }
resolve_injection_time <- function(ms2_time, resolution = NULL, analyzer_type = "orbitrap") {

  # Case 1: Numeric value - return as-is

if (is.numeric(ms2_time)) {
    return(ms2_time)
  }

  # Case 2: "auto" mode
  if (is.character(ms2_time) && tolower(ms2_time) == "auto") {

    # Require resolution for auto mode
    if (is.null(resolution)) {
      stop("resolution is required when ms2_time = 'auto'")
    }

    # Non-Orbitrap analyzers don't support auto mode
    if (analyzer_type != "orbitrap") {
      stop(sprintf(
        "Auto IT mode is only supported for Orbitrap analyzers, not '%s'",
        analyzer_type
      ))
    }

    # Get T_transient for this resolution
    transient_ms <- get_transient_time(resolution, analyzer_type)

    if (is.na(transient_ms)) {
      stop(sprintf(
        "Could not determine transient time for resolution %d",
        resolution
      ))
    }

    message(sprintf(
      "Auto IT mode: Setting IT = T_transient = %.1f ms (Resolution: %gK, Sweet Spot)",
      transient_ms, resolution / 1000
    ))

    return(transient_ms)
  }

  # Invalid input
  stop(sprintf(
    "Invalid ms2_time value: '%s'. Must be numeric or 'auto'.",
    as.character(ms2_time)
  ))
}


# =============================================================================
# User Experiment Configuration Functions
# =============================================================================

#' Calculate Actual Cycle Time from User Experiment Config
#'
#' Calculates the precise cycle time based on actual experimental parameters
#' rather than using heuristic estimates. This provides accurate DPPP calculations.
#'
#' @param experiment_config List containing experiment parameters (from YAML or Shiny input)
#' @param verbose Logical, print detailed breakdown (default: TRUE)
#' @param language Character, output language: "ko" (Korean) or "en" (English)
#'
#' @return List with calculated cycle time and detailed breakdown
#' @export
#' @keywords internal
#'
#' @details
#' The cycle time calculation uses the fundamental scan time equations:
#'
#' **For Orbitrap:**
#' - t_scan = max(T_transient, IT) + overhead
#' - T_transient is determined by resolution
#'
#' **For Astral:**
#' - t_scan = max(5.0 ms, IT + 2.0 ms) for parallel architecture
#'
#' **Cycle Time:**
#' - Sequential: cycle_time = MS1_time + (n_windows x MS2_time)
#' - Parallel: cycle_time = max(MS1_time, n_windows x MS2_time)
#'
#' @examples
#' \dontrun{
#' # From YAML config
#' config <- yaml::read_yaml("config/user_experiment_config.yaml")
#' result <- calculate_cycle_time_from_experiment(config)
#'
#' # From direct parameters
#' config <- list(
#'   instrument = list(preset = "exploris"),
#'   ms1 = list(resolution = 60000, max_injection_time_ms = 50),
#'   ms2 = list(resolution = 15000, max_injection_time_ms = "auto"),
#'   dia_windows = list(window_count = 40)
#' )
#' result <- calculate_cycle_time_from_experiment(config)
#' cat(sprintf("Cycle time: %.3f sec\\n", result$cycle_time_sec))
#' }
calculate_cycle_time_from_experiment <- function(experiment_config,
                                                  verbose = TRUE,
                                                  language = "ko") {

  # =========================================================================
  # 1. Load Instrument Base Configuration
  # =========================================================================
  instrument_preset <- experiment_config$instrument$preset %||% "exploris"
  base_config <- get_instrument_config(instrument_preset)

  analyzer_type <- experiment_config$instrument$analyzer_type %||%
                   base_config$analyzer_type %||% "orbitrap"

  cycle_calculation <- base_config$cycle_calculation %||% "sequential"

  # =========================================================================
  # 2. Extract MS1 Parameters
  # =========================================================================
  ms1_resolution <- experiment_config$ms1$resolution %||% 60000
  ms1_max_it <- experiment_config$ms1$max_injection_time_ms %||% 50

  # Resolve MS1 IT (handle "auto" mode)
  if (is.character(ms1_max_it) && tolower(ms1_max_it) == "auto") {
    if (analyzer_type == "orbitrap") {
      ms1_it_resolved <- get_transient_time(ms1_resolution, "orbitrap")
    } else if (analyzer_type == "astral") {
      # Astral MS1 is on Orbitrap — auto IT = transient time
      ms1_it_resolved <- resolve_astral_ms1(base_config, ms1_resolution)$transient_ms
    } else {
      ms1_it_resolved <- base_config$ms1_time %||% 50.0
    }
  } else {
    ms1_it_resolved <- as.numeric(ms1_max_it)
  }

  # Calculate MS1 scan time
  if (analyzer_type == "orbitrap") {
    ms1_transient <- get_transient_time(ms1_resolution, "orbitrap")
    ms1_overhead <- base_config$ms1_overhead_ms %||% DEFAULT_MS1_OVERHEAD_MS
    ms1_scan_time_ms <- max(ms1_transient, ms1_it_resolved) + ms1_overhead
  } else if (analyzer_type == "astral") {
    # Astral MS1 is on the Orbitrap analyzer
    astral_ms1 <- resolve_astral_ms1(base_config, ms1_resolution)
    ms1_transient <- astral_ms1$transient_ms
    ms1_overhead <- astral_ms1$overhead_ms
    ms1_scan_time_ms <- max(ms1_transient, ms1_it_resolved) + ms1_overhead
  } else {
    # TOF
    ms1_scan_time_ms <- (base_config$ms1_time %||% 50.0) + MINIMUM_OVERHEAD_MS
    ms1_transient <- 0
    ms1_overhead <- MINIMUM_OVERHEAD_MS
  }

  # =========================================================================
  # 3. Extract MS2 Parameters
  # =========================================================================
  ms2_resolution <- experiment_config$ms2$resolution %||%
                    base_config$ms2_resolution %||% 30000
  ms2_max_it <- experiment_config$ms2$max_injection_time_ms %||%
                base_config$ms2_time %||% "auto"

  # Resolve MS2 IT (handle "auto" mode)
  if (is.character(ms2_max_it) && tolower(ms2_max_it) == "auto") {
    ms2_it_resolved <- resolve_injection_time("auto", ms2_resolution, analyzer_type)
  } else {
    ms2_it_resolved <- as.numeric(ms2_max_it)
  }

  # Calculate MS2 scan time using the core function
  # Pass instrument-specific overhead from JSON config
  ms2_scan_info <- calculate_ms2_scan_time(
    resolution = ms2_resolution,
    injection_time_ms = ms2_it_resolved,
    analyzer = analyzer_type,
    overhead_ms = base_config$ms2_overhead_ms,
    verbose = FALSE
  )

  ms2_scan_time_ms <- ms2_scan_info$t_scan_ms

  # =========================================================================
  # 4. Get Window Count and MS1 Scans per Cycle
  # =========================================================================
  window_count <- experiment_config$dia_windows$window_count %||% 40

  # MS1 scans per cycle: 0 = parallel, 1 = standard sequential, 3-4 = Boxcar

  ms1_scans_per_cycle <- experiment_config$ms1$scans_per_cycle %||%
                          base_config$ms1_scans_per_cycle %||%
                          ifelse(cycle_calculation == "parallel", 0, 1)

  # =========================================================================
  # 5. Calculate Cycle Time
  # =========================================================================
  ms2_total_time_ms <- window_count * ms2_scan_time_ms

  if (ms1_scans_per_cycle == 0 || cycle_calculation == "parallel") {
    # Parallel: MS1 acquired during MS2 scans (Astral, timsTOF, etc.)
    ms1_total_time_ms <- ms1_scan_time_ms  # Single MS1 overlapped
    cycle_time_ms <- max(ms1_scan_time_ms, ms2_total_time_ms)
    ms1_contribution <- ifelse(ms1_scan_time_ms >= ms2_total_time_ms, "dominant", "parallel")
  } else {
    # Sequential: MS1(s) then MS2s
    # Boxcar DIA: multiple MS1 scans (e.g., 3-4 segments)
    ms1_total_time_ms <- ms1_scans_per_cycle * ms1_scan_time_ms
    cycle_time_ms <- ms1_total_time_ms + ms2_total_time_ms
    ms1_contribution <- ifelse(ms1_scans_per_cycle > 1, "boxcar", "sequential")
  }

  cycle_time_sec <- cycle_time_ms / 1000

  # =========================================================================
  # 6. Calculate Theoretical Scan Rate
  # =========================================================================
  theoretical_scan_rate_hz <- 1000 / ms2_scan_time_ms
  effective_scan_rate_hz <- window_count / cycle_time_sec

  # =========================================================================
  # 7. Generate Summary Report
  # =========================================================================
  if (verbose) {
    if (language == "ko") {
      cat("\n")
      cat("+========================================================================+\n")
      cat("|            \uc2e4\uc81c \uc2e4\ud5d8 \uc870\uac74 \uae30\ubc18 Cycle Time \uacc4\uc0b0                         |\n")
      cat("|            Actual Experiment-Based Cycle Time Calculation              |\n")
      cat("+========================================================================+\n")
      cat("\n")
      cat(sprintf("\uc7a5\ube44 \uc124\uc815 (Instrument): %s (%s)\n",
                  base_config$name, toupper(analyzer_type)))
      cat(sprintf("Cycle \uacc4\uc0b0 \ubaa8\ub4dc: %s\n\n", cycle_calculation))

      cat("+-------------------------------------------------------------------------+\n")
      cat("| MS1 \uc2a4\uce94 \ud30c\ub77c\ubbf8\ud130                                                       |\n")
      cat("+-------------------------------------------------------------------------+\n")
      cat(sprintf("|  Resolution:     %s\n", format(ms1_resolution, big.mark = ",")))
      cat(sprintf("|  T_transient:    %.1f ms\n", ms1_transient))
      cat(sprintf("|  Max IT:         %.1f ms (\uc785\ub825: %s)\n",
                  ms1_it_resolved,
                  ifelse(is.character(experiment_config$ms1$max_injection_time_ms),
                         experiment_config$ms1$max_injection_time_ms,
                         sprintf("%.1f ms", experiment_config$ms1$max_injection_time_ms %||% ms1_it_resolved))))
      cat(sprintf("|  Overhead:       %.1f ms\n", ms1_overhead))
      cat(sprintf("|  >> MS1 Scan Time: %.1f ms\n", ms1_scan_time_ms))
      cat("+-------------------------------------------------------------------------+\n\n")

      cat("+-------------------------------------------------------------------------+\n")
      cat("| MS2 \uc2a4\uce94 \ud30c\ub77c\ubbf8\ud130                                                       |\n")
      cat("+-------------------------------------------------------------------------+\n")
      cat(sprintf("|  Resolution:     %s\n", format(ms2_resolution, big.mark = ",")))
      cat(sprintf("|  T_transient:    %.1f ms\n", ms2_scan_info$transient_ms))
      cat(sprintf("|  Max IT:         %.1f ms (\uc785\ub825: %s)\n",
                  ms2_it_resolved,
                  ifelse(is.character(experiment_config$ms2$max_injection_time_ms),
                         experiment_config$ms2$max_injection_time_ms,
                         sprintf("%.1f ms", experiment_config$ms2$max_injection_time_ms %||% ms2_it_resolved))))
      cat(sprintf("|  Overhead:       %.1f ms\n", ms2_scan_info$overhead_ms))
      cat(sprintf("|  >> MS2 Scan Time: %.1f ms (%.1f Hz)\n",
                  ms2_scan_time_ms, theoretical_scan_rate_hz))
      cat(sprintf("|  \ud6a8\uc728 \uc0c1\ud0dc:      %s\n", ms2_scan_info$efficiency_message))
      cat("+-------------------------------------------------------------------------+\n\n")

      cat("+-------------------------------------------------------------------------+\n")
      cat("| DIA \uc708\ub3c4\uc6b0 \uc124\uc815                                                         |\n")
      cat("+-------------------------------------------------------------------------+\n")
      cat(sprintf("|  MS1 Scans/Cycle: %d %s\n", ms1_scans_per_cycle,
                  ifelse(ms1_scans_per_cycle > 1, "(Boxcar)", ifelse(ms1_scans_per_cycle == 0, "(Parallel)", ""))))
      cat(sprintf("|  MS2 Window \uc218:   %d \uac1c\n", window_count))
      cat(sprintf("|  MS1 \ucd1d \uc2dc\uac04:     %.1f ms (= %d x %.1f ms)\n",
                  ms1_total_time_ms, ms1_scans_per_cycle, ms1_scan_time_ms))
      cat(sprintf("|  MS2 \ucd1d \uc2dc\uac04:     %.1f ms (= %d x %.1f ms)\n",
                  ms2_total_time_ms, window_count, ms2_scan_time_ms))
      cat("+-------------------------------------------------------------------------+\n\n")

      cat("+=========================================================================+\n")
      cat("|                    \ucd5c\uc885 Cycle Time \uacc4\uc0b0 \uacb0\uacfc                            |\n")
      cat("+=========================================================================+\n")

      if (ms1_scans_per_cycle == 0 || cycle_calculation == "parallel") {
        cat(sprintf("|  Cycle Time = max(MS1, MS2 \ucd1d\ud569) = max(%.1f, %.1f) ms\n",
                    ms1_scan_time_ms, ms2_total_time_ms))
      } else if (ms1_scans_per_cycle > 1) {
        cat(sprintf("|  Cycle Time = %dxMS1 + MS2 \ucd1d\ud569 = %.1f + %.1f ms (Boxcar)\n",
                    ms1_scans_per_cycle, ms1_total_time_ms, ms2_total_time_ms))
      } else {
        cat(sprintf("|  Cycle Time = MS1 + MS2 \ucd1d\ud569 = %.1f + %.1f ms\n",
                    ms1_scan_time_ms, ms2_total_time_ms))
      }

      cat("|                                                                         |\n")
      cat(sprintf("|  >>> Cycle Time = %.1f ms = %.3f \ucd08 <<<\n",
                  cycle_time_ms, cycle_time_sec))
      cat("|                                                                         |\n")
      cat(sprintf("|  \uc720\ud6a8 \uc2a4\uce94 \uc18d\ub3c4: %.1f windows/sec\n", effective_scan_rate_hz))
      cat("+=========================================================================+\n\n")
    } else {
      # English version (abbreviated)
      cat("\n")
      cat("+========================================================================+\n")
      cat("|            Experiment-Based Cycle Time Calculation                      |\n")
      cat("+========================================================================+\n")
      cat(sprintf("\nInstrument: %s (%s), Mode: %s\n\n",
                  base_config$name, toupper(analyzer_type), cycle_calculation))

      cat(sprintf("MS1: %dK res, IT=%.1f ms -> Scan=%.1f ms\n",
                  ms1_resolution/1000, ms1_it_resolved, ms1_scan_time_ms))
      cat(sprintf("MS2: %dK res, IT=%.1f ms -> Scan=%.1f ms (%.1f Hz)\n",
                  ms2_resolution/1000, ms2_it_resolved, ms2_scan_time_ms, theoretical_scan_rate_hz))
      cat(sprintf("Windows: %d x %.1f ms = %.1f ms\n\n",
                  window_count, ms2_scan_time_ms, ms2_total_time_ms))

      cat(sprintf(">>> CYCLE TIME = %.1f ms = %.3f sec <<<\n\n",
                  cycle_time_ms, cycle_time_sec))
    }
  }

  # =========================================================================
  # 8. Return Results
  # =========================================================================
  return(list(
    # Primary result
    cycle_time_sec = cycle_time_sec,
    cycle_time_ms = cycle_time_ms,

    # MS1 breakdown
    ms1 = list(
      resolution = ms1_resolution,
      transient_ms = ms1_transient,
      injection_time_ms = ms1_it_resolved,
      overhead_ms = ms1_overhead,
      scan_time_ms = ms1_scan_time_ms,
      scans_per_cycle = ms1_scans_per_cycle,
      total_time_ms = ms1_total_time_ms
    ),

    # MS2 breakdown
    ms2 = list(
      resolution = ms2_resolution,
      transient_ms = ms2_scan_info$transient_ms,
      injection_time_ms = ms2_it_resolved,
      overhead_ms = ms2_scan_info$overhead_ms,
      scan_time_ms = ms2_scan_time_ms,
      sweet_spot_it_ms = ms2_scan_info$sweet_spot_it_ms,
      limiting_factor = ms2_scan_info$limiting_factor,
      efficiency_pct = ms2_scan_info$efficiency_pct,
      efficiency_mode = ms2_scan_info$efficiency_mode
    ),

    # DIA windows
    window_count = window_count,
    ms2_total_time_ms = ms2_total_time_ms,

    # Instrument info
    instrument = list(
      preset = instrument_preset,
      name = base_config$name,
      analyzer_type = analyzer_type,
      cycle_calculation = cycle_calculation
    ),

    # Scan rates
    theoretical_ms2_rate_hz = theoretical_scan_rate_hz,
    effective_windows_per_sec = effective_scan_rate_hz,

    # For compatibility with existing code
    current_cycle_time = cycle_time_sec
  ))
}


#' Get ms1_scans_per_cycle with automatic detection
#'
#' @param ms1_scans_per_cycle User-specified value (NULL for auto-detect)
#' @param instrument_config Instrument configuration from JSON
#' @return Integer (0 or 1)
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' config <- get_instrument_config("fusion_lumos")
#' get_ms1_scans_per_cycle(NULL, config)  # Returns 1 (sequential)
#' }
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


# =============================================================================
# Astral MS1 Resolution Helper
# =============================================================================

#' Resolve Astral MS1 (Orbitrap) Parameters
#'
#' Centralizes the Astral MS1 resolution lookup, transient time calculation,
#' and overhead retrieval. Astral MS1 is always on the Orbitrap analyzer.
#'
#' @param instrument_config List, instrument config (from get_instrument_config()
#'   or plan_optimization's instrument_config). Must contain at least
#'   \code{default_ms1_resolution}.
#' @param ms1_resolution Optional override for MS1 resolution. If NULL, uses
#'   \code{instrument_config$ms1_resolution} or \code{instrument_config$default_ms1_resolution}.
#'
#' @return List with:
#'   \describe{
#'     \item{resolution}{Integer, resolved MS1 resolution}
#'     \item{transient_ms}{Numeric, Orbitrap transient time in ms}
#'     \item{overhead_ms}{Numeric, MS1 overhead in ms}
#'     \item{scan_time_ms}{Numeric, total MS1 scan time (transient + overhead)}
#'   }
#' @keywords internal
resolve_astral_ms1 <- function(instrument_config, ms1_resolution = NULL) {
  res <- ms1_resolution %||%
         instrument_config$ms1_resolution %||%
         instrument_config$default_ms1_resolution %||% 240000

  transient <- get_transient_time(res, "orbitrap")
  if (is.na(transient)) transient <- ORBITRAP_240K_TRANSIENT_MS

  overhead <- instrument_config$ms1_overhead_ms %||% DEFAULT_MS1_OVERHEAD_MS

  list(
    resolution = res,
    transient_ms = transient,
    overhead_ms = overhead,
    scan_time_ms = transient + overhead
  )
}


# =============================================================================
# Duty Cycle Sync (Parallel Instruments)
# =============================================================================

#' Calculate Duty Cycle Sync for Parallel Instruments
#'
#' For parallel instruments (Astral, TimsTOF), MS1 and MS2 run simultaneously.
#' Cycle time = max(MS1_time, n_windows * MS2_time). If total MS2 time does
#' not match MS1 total scan time, one analyzer idles. This function quantifies
#' the sync quality.
#'
#' @param ms1_time_ms Numeric, total MS1 scan time in milliseconds
#'   (transient + overhead; for Astral: Orbitrap total, e.g. 266 ms at 120K, 522 ms at 240K)
#' @param ms2_scan_time_ms Numeric, single MS2 scan time in milliseconds
#' @param n_windows Integer, number of MS2 windows per cycle
#'
#' @return List with:
#'   \describe{
#'     \item{duty_cycle_pct}{Numeric, duty cycle percentage (100% = perfect sync)}
#'     \item{ms1_idle_ms}{Numeric, MS1 idle time (ms), > 0 when MS2 > MS1}
#'     \item{ms2_idle_ms}{Numeric, MS2 idle time (ms), > 0 when MS1 > MS2}
#'     \item{total_ms2_time_ms}{Numeric, total MS2 acquisition time}
#'     \item{cycle_time_ms}{Numeric, actual cycle time (max of MS1, total MS2)}
#'     \item{sync_status}{Character, "synced" / "ms1_idle" / "ms2_idle"}
#'     \item{n_sync_optimal}{Integer, window count for perfect sync}
#'   }
#' @keywords internal
calculate_duty_cycle_sync <- function(ms1_time_ms, ms2_scan_time_ms, n_windows) {
  total_ms2_ms <- n_windows * ms2_scan_time_ms
  cycle_time_ms <- max(ms1_time_ms, total_ms2_ms)

  # Idle times

  ms1_idle_ms <- max(0, total_ms2_ms - ms1_time_ms)
  ms2_idle_ms <- max(0, ms1_time_ms - total_ms2_ms)

  # Duty cycle: fraction of cycle where both analyzers are active
  active_time_ms <- min(ms1_time_ms, total_ms2_ms)
  duty_cycle_pct <- (active_time_ms / cycle_time_ms) * 100

  # Sync status
  idle_threshold_ms <- 1.0
  sync_status <- if (ms1_idle_ms <= idle_threshold_ms && ms2_idle_ms <= idle_threshold_ms) {
    "synced"
  } else if (ms1_idle_ms > ms2_idle_ms) {
    "ms1_idle"
  } else {
    "ms2_idle"
  }

  # Optimal window count for perfect sync
  n_sync_optimal <- calculate_sync_optimal_windows(ms1_time_ms, ms2_scan_time_ms)

  list(
    duty_cycle_pct = round(duty_cycle_pct, 1),
    ms1_idle_ms = round(ms1_idle_ms, 1),
    ms2_idle_ms = round(ms2_idle_ms, 1),
    total_ms2_time_ms = round(total_ms2_ms, 1),
    cycle_time_ms = round(cycle_time_ms, 1),
    sync_status = sync_status,
    n_sync_optimal = n_sync_optimal
  )
}


#' Calculate Sync-Optimal Window Count for Parallel Instruments
#'
#' Returns the window count that minimizes idle time by matching total MS2
#' time to MS1 total scan time: n_sync = floor(ms1_time / ms2_scan_time).
#'
#' @param ms1_time_ms Numeric, total MS1 scan time in milliseconds (transient + overhead)
#' @param ms2_scan_time_ms Numeric, single MS2 scan time in milliseconds
#'
#' @return Integer, sync-optimal window count
#' @keywords internal
calculate_sync_optimal_windows <- function(ms1_time_ms, ms2_scan_time_ms) {
  if (ms2_scan_time_ms <= 0) return(1L)
  as.integer(floor(ms1_time_ms / ms2_scan_time_ms))
}


#' Get Instrument Width Recommendations from JSON Config
#'
#' Reads recommended_min_width_da and recommended_max_width_da from the
#' instrument JSON configuration. Falls back to sensible defaults.
#'
#' @param instrument_config List, instrument config from get_instrument_config()
#'
#' @return List with min_width_da and max_width_da
#' @keywords internal
get_instrument_width_recommendations <- function(instrument_config) {
  list(
    min_width_da = instrument_config$recommended_min_width_da %||% 2,
    max_width_da = instrument_config$recommended_max_width_da %||% 80
  )
}
