# module3a_window_count.R - Phase 3A: Window Count Determination
#
# Purpose: Determine optimal window count from scan_time and instrument constraints
# Input: DiagnosisResult from Phase 2
# Output: WindowCountResult with feasibility checks
#
# Author: DIA Window Optimizer Project
# Version: 2.0

library(dplyr)

# ============================================================================
# Module 3A Global Constants
# ============================================================================

#' Module 3A Default Settings
#'
#' Global defaults that apply to all instruments unless overridden by user.
#' These settings control scan rate utilization, maxIT optimization behavior,
#' and MS1 scan reservation.
#'
#' @format List with the following elements:
#' \describe{
#'   \item{scan_rate_load_factor}{Numeric, fraction of max scan rate to use (default: 0.8 = 80%)}
#'   \item{maxIT_optimization}{List of maxIT optimization settings}
#'   \item{default_ms1_scans}{Integer, default MS1 scans to reserve (default: 1)}
#' }
#'
#' @keywords internal
MODULE3A_DEFAULTS <- list(
  # Scan rate utilization (conservative for stability)
  scan_rate_load_factor = 0.8,  # Use 80% of max scan rate

  # MaxIT optimization settings
  maxIT_optimization = list(
    enabled = TRUE,               # Enable optimization by default
    slack_threshold_sec = 0.5,    # Optimize if cycle time slack >= 0.5 sec
    increment_step_ms = 10,       # Increase maxIT by 10 ms per iteration
    max_maxIT_ms = 100            # Safety limit: max 100 ms
  ),

  # MS1 scan reservation (user can override per experiment)
  default_ms1_scans = 1  # Conservative default for most instruments
)


# ============================================================================
# Core Window Count Calculation
# ============================================================================

#' Calculate Window Count from Target Cycle Time
#'
#' Calculates the number of MS2 isolation windows based on target maximum cycle time
#' (constraint from Phase 2) and instrument scan rate, accounting for MS1 scan reservation.
#' This is the REVERSE calculation: given a target cycle time constraint, determine
#' how many windows can fit.
#'
#' @param target_cycle_time_sec Numeric, target maximum cycle time in seconds
#'   (this is the constraint from Phase 2's required_cycle_time_sec)
#' @param scan_rate_hz Numeric, instrument scan rate in Hz
#' @param ms1_scans Integer, number of MS1 scans to reserve (default: 1)
#'   - Parallel instruments (Astral, TimsTOF): typically 0 (MS1 during MS2)
#'   - Sequential instruments (Orbitrap): typically 1 (MS1 before MS2)
#'   - Custom experiments: can be 0, 1, 2, etc.
#' @param min_windows Integer, minimum allowed windows (default: 20)
#' @param max_windows Integer, maximum allowed windows (default: 500)
#'
#' @return Integer, number of MS2 windows
#' @export
#'
#' @examples
#' # Astral (parallel): Target cycle time 1.85 sec at 50 Hz, ms1_scans=0
#' n_windows <- calculate_window_count_from_target_cycletime(1.85, 50, ms1_scans=0)
#' # Result: floor(1.85 * 50) - 0 = 92 windows
#'
#' # Orbitrap (sequential): Target cycle time 2.0 sec at 12 Hz, ms1_scans=1
#' n_windows <- calculate_window_count_from_target_cycletime(2.0, 12, ms1_scans=1)
#' # Result: floor(2.0 * 12) - 1 = 24 - 1 = 23 windows
calculate_window_count_from_target_cycletime <- function(
  target_cycle_time_sec,
  scan_rate_hz,
  ms1_scans = 1,
  min_windows = 20,
  max_windows = 500
) {
  # === Input Validation ===
  if (target_cycle_time_sec <= 0) {
    stop("target_cycle_time_sec must be positive (> 0)")
  }

  if (scan_rate_hz <= 0) {
    stop("scan_rate_hz must be positive (> 0)")
  }

  if (!is.numeric(ms1_scans) || ms1_scans < 0 || ms1_scans != floor(ms1_scans)) {
    stop("ms1_scans must be a non-negative integer (0, 1, 2, ...)")
  }

  if (min_windows < 1) {
    stop("min_windows must be at least 1")
  }

  if (max_windows < min_windows) {
    stop("max_windows must be >= min_windows")
  }

  # === Calculate Total Scans ===
  # Total possible scans in given target_cycle_time_sec
  total_scans <- floor(target_cycle_time_sec * scan_rate_hz)

  # Check minimum scans required (MS1 + at least 1 MS2)
  min_required_scans <- ms1_scans + 1
  if (total_scans < min_required_scans) {
    stop(sprintf(
      "Target cycle time (%.2f sec) too short for scan rate (%.0f Hz). Need at least %d scans (MS1: %d + MS2: 1). Current: %d scans.",
      target_cycle_time_sec, scan_rate_hz, min_required_scans, ms1_scans, total_scans
    ))
  }

  # === Reserve Scans for MS1 ===
  # Subtract ms1_scans for MS1 acquisition
  # Parallel (ms1_scans=0): n_windows = total_scans
  # Sequential (ms1_scans=1): n_windows = total_scans - 1
  n_windows <- total_scans - ms1_scans

  # === Apply Minimum Constraint ===
  if (n_windows < min_windows) {
    warning(sprintf(
      "Calculated window count (%d) below minimum (%d). Using minimum.",
      n_windows, min_windows
    ))
    n_windows <- min_windows
  }

  # === Apply Maximum Constraint ===
  if (n_windows > max_windows) {
    warning(sprintf(
      "Calculated window count (%d) exceeds maximum (%d). Capping at maximum.",
      n_windows, max_windows
    ))
    n_windows <- max_windows
  }

  return(as.integer(n_windows))
}


# ============================================================================
# Effective Scan Rate Calculation
# ============================================================================

#' Calculate Effective Scan Rate with Load Factor
#'
#' Calculates the effective scan rate by applying a load factor to the maximum
#' hardware scan rate. Conservative load factors (e.g., 0.8 = 80%) provide
#' stability and prevent instrument overload.
#'
#' @param max_scan_rate_hz Numeric, maximum instrument scan rate in Hz
#' @param load_factor Numeric, utilization factor between 0 and 1 (default: 0.8)
#'   - 0.8 (80%): Conservative, recommended for stability
#'   - 0.9 (90%): Moderate, good balance
#'   - 1.0 (100%): Aggressive, may cause instability
#'
#' @return Numeric, effective scan rate in Hz
#' @export
#'
#' @examples
#' # Astral: 100 Hz max, use 80%
#' effective_rate <- calculate_effective_scan_rate(100, 0.8)
#' # Result: 80 Hz
#'
#' # Aggressive: use 100%
#' effective_rate <- calculate_effective_scan_rate(50, 1.0)
#' # Result: 50 Hz
calculate_effective_scan_rate <- function(
  max_scan_rate_hz,
  load_factor = 0.8
) {
  # === Input Validation ===
  if (!is.numeric(max_scan_rate_hz) || max_scan_rate_hz <= 0) {
    stop("max_scan_rate_hz must be a positive number")
  }

  if (!is.numeric(load_factor) || load_factor <= 0 || load_factor > 1) {
    stop("load_factor must be between 0 and 1 (exclusive of 0, inclusive of 1)")
  }

  # === Calculate Effective Rate ===
  effective_rate <- max_scan_rate_hz * load_factor

  return(effective_rate)
}


# ============================================================================
# Cycle Time Calculation
# ============================================================================

#' Calculate Cycle Time
#'
#' Calculates duty cycle time based on number of windows and acquisition mode.
#' Handles both parallel (Astral) and sequential (Orbitrap) acquisition modes.
#'
#' @param n_windows Integer, number of isolation windows
#' @param cycle_calculation Character, "parallel" or "sequential"
#'   - "parallel": MS1 and MS2 overlap (Astral, TimsTOF)
#'   - "sequential": MS1 then MS2 (Orbitrap, QTOF)
#' @param ms1_time Numeric, MS1 acquisition time (seconds)
#' @param ms2_time Numeric, MS2 acquisition time per window (seconds)
#'
#' @return List with cycle_time, ms1_time, ms2_time_per_window, total_ms2_time
#' @export
#'
#' @examples
#' # Parallel (Astral): 120 windows
#' timing <- calculate_cycle_time(120, "parallel", 0.1, 0.015)
#' # cycle_time = max(0.1, 120 * 0.015) = max(0.1, 1.8) = 1.8 sec
#'
#' # Sequential (Orbitrap): 120 windows
#' timing <- calculate_cycle_time(120, "sequential", 0.05, 0.02)
#' # cycle_time = 0.05 + (120 * 0.02) = 0.05 + 2.4 = 2.45 sec
calculate_cycle_time <- function(n_windows, cycle_calculation, ms1_time, ms2_time) {

  # === Input Validation ===
  if (n_windows < 1) {
    stop("n_windows must be at least 1")
  }

  if (!cycle_calculation %in% c("parallel", "sequential")) {
    stop("cycle_calculation must be 'parallel' or 'sequential'")
  }

  if (ms1_time <= 0) {
    stop("ms1_time must be positive (> 0)")
  }

  if (ms2_time <= 0) {
    stop("ms2_time must be positive (> 0)")
  }

  # === Calculate Total MS2 Time ===
  total_ms2_time <- n_windows * ms2_time

  # === Determine Acquisition Mode ===
  is_parallel <- (cycle_calculation == "parallel")

  # === Calculate Cycle Time ===
  if (is_parallel) {
    # Parallel acquisition: MS2 scans happen during MS1
    # Cycle time is the maximum of MS1 time or total MS2 time
    cycle_time <- max(ms1_time, total_ms2_time)
  } else {
    # Sequential acquisition: MS1 then MS2
    # Cycle time is MS1 time plus total MS2 time
    cycle_time <- ms1_time + total_ms2_time
  }

  # === Return Detailed Timing Breakdown ===
  return(list(
    cycle_time = cycle_time,
    ms1_time = ms1_time,
    ms2_time_per_window = ms2_time,
    total_ms2_time = total_ms2_time,
    overhead_time = 0  # Reserved for future use
  ))
}


# ============================================================================
# MaxIT Optimization from Slack
# ============================================================================

#' Optimize MaxIT from Cycle Time Slack
#'
#' Iteratively increases MS2 maxIT to utilize available cycle time slack,
#' improving signal quality without affecting DPPP target. Optimization occurs
#' when slack >= threshold (default: 0.5 sec).
#'
#' @param n_windows Integer, number of windows
#' @param target_cycle_time_sec Numeric, target maximum cycle time (constraint from Phase 2)
#' @param calculated_cycle_time_initial Numeric, initial calculated cycle time
#' @param ms1_time Numeric, MS1 time in seconds
#' @param ms2_time_initial Numeric, initial MS2 time per window in seconds
#' @param cycle_calculation Character, "parallel" or "sequential"
#' @param optimization_config List, optimization settings (from MODULE3A_DEFAULTS or custom)
#'
#' @return List with optimization results:
#'   \item{optimization_applied}{Logical, whether optimization was performed}
#'   \item{original_maxIT_ms2}{Numeric, original maxIT in ms}
#'   \item{recommended_maxIT_ms2}{Numeric, optimized maxIT in ms}
#'   \item{slack_before}{Numeric, initial slack in seconds}
#'   \item{slack_after}{Numeric, remaining slack after optimization}
#'   \item{improvement_ms}{Numeric, maxIT increase in ms}
#'   \item{optimized_ms2_time_sec}{Numeric, optimized MS2 time in seconds (only if applied)}
#'
#' @export
#'
#' @examples
#' # High slack case - optimization applied
#' result <- optimize_maxIT_from_slack(
#'   n_windows = 80,
#'   target_cycle_time_sec = 2.0,
#'   calculated_cycle_time_initial = 1.2,
#'   ms1_time = 0.1,
#'   ms2_time_initial = 0.015,
#'   cycle_calculation = "parallel",
#'   optimization_config = MODULE3A_DEFAULTS$maxIT_optimization
#' )
#' # Result: optimization_applied = TRUE, improvement_ms = 10
optimize_maxIT_from_slack <- function(
  n_windows,
  target_cycle_time_sec,
  calculated_cycle_time_initial,
  ms1_time,
  ms2_time_initial,
  cycle_calculation,
  optimization_config
) {

  # === Calculate Slack ===
  slack <- target_cycle_time_sec - calculated_cycle_time_initial

  cat(sprintf("  Cycle time slack: %.3f sec\n", slack))

  # === Check if Optimization Enabled ===
  if (!optimization_config$enabled) {
    cat("  MaxIT optimization: DISABLED (by config)\n")
    return(list(
      optimization_applied = FALSE,
      original_maxIT_ms2 = ms2_time_initial * 1000,
      recommended_maxIT_ms2 = ms2_time_initial * 1000,
      slack_before = slack,
      slack_after = slack,
      improvement_ms = 0
    ))
  }

  # === Check Slack Threshold ===
  if (slack < optimization_config$slack_threshold_sec) {
    cat(sprintf("  MaxIT optimization: SKIPPED (slack %.3f < threshold %.2f sec)\n",
                slack, optimization_config$slack_threshold_sec))
    return(list(
      optimization_applied = FALSE,
      original_maxIT_ms2 = ms2_time_initial * 1000,
      recommended_maxIT_ms2 = ms2_time_initial * 1000,
      slack_before = slack,
      slack_after = slack,
      improvement_ms = 0
    ))
  }

  cat("  MaxIT optimization: ENABLED\n")

  # === Iteratively Increase MaxIT ===
  ms2_time_optimized <- ms2_time_initial
  increment_sec <- optimization_config$increment_step_ms / 1000
  max_maxIT_sec <- optimization_config$max_maxIT_ms / 1000

  iteration <- 0
  repeat {
    iteration <- iteration + 1
    ms2_time_trial <- ms2_time_optimized + increment_sec

    # Safety check: max maxIT limit
    if (ms2_time_trial > max_maxIT_sec) {
      cat(sprintf("    Iteration %d: Reached max maxIT limit (%.0f ms)\n",
                  iteration, max_maxIT_sec * 1000))
      break
    }

    # Calculate trial cycle time
    timing_trial <- calculate_cycle_time(
      n_windows, cycle_calculation, ms1_time, ms2_time_trial
    )

    # Check if still feasible
    if (timing_trial$cycle_time <= target_cycle_time_sec) {
      ms2_time_optimized <- ms2_time_trial
      cat(sprintf("    Iteration %d: maxIT_MS2 = %.0f ms → cycle_time = %.3f sec ✅\n",
                  iteration, ms2_time_optimized * 1000, timing_trial$cycle_time))
    } else {
      cat(sprintf("    Iteration %d: maxIT_MS2 = %.0f ms → cycle_time = %.3f sec ❌ Exceeded target\n",
                  iteration, ms2_time_trial * 1000, timing_trial$cycle_time))
      break
    }
  }

  # === Calculate Final Results ===
  timing_final <- calculate_cycle_time(
    n_windows, cycle_calculation, ms1_time, ms2_time_optimized
  )
  slack_after <- target_cycle_time_sec - timing_final$cycle_time
  improvement <- (ms2_time_optimized - ms2_time_initial) * 1000

  if (improvement > 0) {
    cat(sprintf("  Optimization result: maxIT_MS2 increased by %.0f ms (%.0f → %.0f ms)\n",
                improvement, ms2_time_initial * 1000, ms2_time_optimized * 1000))
    cat(sprintf("  Final slack: %.3f sec\n", slack_after))
  } else {
    cat("  Optimization result: No improvement possible\n")
  }

  return(list(
    optimization_applied = (improvement > 0),
    original_maxIT_ms2 = ms2_time_initial * 1000,
    recommended_maxIT_ms2 = ms2_time_optimized * 1000,
    slack_before = slack,
    slack_after = slack_after,
    improvement_ms = improvement,
    optimized_ms2_time_sec = ms2_time_optimized
  ))
}


# ============================================================================
# Feasibility Checks
# ============================================================================

#' Check Scan Rate Feasibility
#'
#' Verifies that the required number of scans (MS1 + MS2 windows) fits
#' within the instrument's maximum scan rate constraint.
#'
#' @param n_windows Integer, number of windows
#' @param target_cycle_time_sec Numeric, target cycle time in seconds
#' @param max_scan_rate_hz Numeric, maximum scan rate in Hz
#' @param ms1_scans Integer, number of MS1 scans to reserve (default: 1)
#'
#' @return List with is_feasible, total_scans_needed, max_possible_scans, ms1_scans_reserved, warning
#' @export
check_scan_rate_feasibility <- function(n_windows, target_cycle_time_sec, max_scan_rate_hz, ms1_scans = 1) {

  # === Calculate Maximum Possible Scans ===
  max_possible_scans <- floor(target_cycle_time_sec * max_scan_rate_hz)

  # === Calculate Total Scans Needed ===
  # MS1 scans + MS2 windows
  total_scans_needed <- n_windows + ms1_scans

  # === Check Feasibility ===
  is_feasible <- total_scans_needed <= max_possible_scans

  # === Generate Warning if Infeasible ===
  warning_msg <- NULL
  if (!is_feasible) {
    warning_msg <- sprintf(
      "Window count (%d) + MS1 (%d) = %d scans exceeds maximum (%d scans in %.2f sec at %.0f Hz). Reduce window count to %d or increase cycle time.",
      n_windows, ms1_scans, total_scans_needed, max_possible_scans,
      target_cycle_time_sec, max_scan_rate_hz, max_possible_scans - ms1_scans
    )
  }

  return(list(
    is_feasible = is_feasible,
    total_scans_needed = total_scans_needed,
    max_possible_scans = max_possible_scans,
    ms1_scans_reserved = ms1_scans,
    warning = warning_msg
  ))
}


#' Check Cycle Time Feasibility
#'
#' Verifies that calculated cycle time does not exceed the target scan time.
#' Includes floating point tolerance to avoid precision issues.
#'
#' @param cycle_time Numeric, calculated cycle time (seconds)
#' @param scan_time Numeric, target scan time (seconds)
#' @param tolerance Numeric, tolerance for floating point comparison (default: 0.01)
#'
#' @return List with is_feasible, cycle_time, scan_time, margin, warning
#' @export
check_cycle_time_feasibility <- function(cycle_time, scan_time, tolerance = 0.01) {

  # === Apply Tolerance ===
  # Allow small tolerance for floating point precision
  is_feasible <- cycle_time <= (scan_time + tolerance)

  # === Calculate Margin ===
  # Positive margin = time available, Negative = time deficit
  margin <- scan_time - cycle_time

  # === Generate Warning if Infeasible ===
  warning_msg <- NULL
  if (!is_feasible) {
    warning_msg <- sprintf(
      "Calculated cycle time (%.3f sec) exceeds scan time (%.2f sec). Reduce window count or increase MS2 speed.",
      cycle_time, scan_time
    )
  }

  return(list(
    is_feasible = is_feasible,
    cycle_time = cycle_time,
    scan_time = scan_time,
    margin = margin,
    warning = warning_msg
  ))
}


# ============================================================================
# Raw Metadata Integration (Optional)
# ============================================================================

#' Adjust for Injection Time (Raw Metadata)
#'
#' Recommends maxIT adjustment based on actual injection times from raw files.
#' This is an optional enhancement for fine-tuning cycle time.
#'
#' @param rawfile_dir Character, path to raw files directory
#' @param current_ms2_time Numeric, current MS2 time (seconds)
#' @param target_reduction_pct Numeric, target IT reduction (default: 0.9 = 10% reduction)
#'
#' @return List with injection time statistics and recommended maxIT
#' @export
adjust_for_injection_time <- function(
  rawfile_dir,
  current_ms2_time,
  target_reduction_pct = 0.9
) {

  # === Check Directory Existence ===
  if (!dir.exists(rawfile_dir)) {
    warning(sprintf("Raw file directory not found: %s. Skipping adjustment.", rawfile_dir))
    return(list(
      it_adjustment_applied = FALSE,
      message = "Directory not found"
    ))
  }

  # === Load Raw Metadata ===
  # TODO: Implement raw metadata loading
  # This would call Phase 1 functions to extract injection times
  # For now, return placeholder

  warning("Raw metadata integration not yet implemented. Placeholder return.")

  return(list(
    actual_injection_times = numeric(0),
    mean_it = NA,
    median_it = NA,
    p95_it = NA,
    current_median_it = NA,
    recommended_maxIT = NA,
    current_ms2_time = current_ms2_time,
    adjusted_ms2_time = current_ms2_time,
    time_saved_per_window = 0,
    it_adjustment_applied = FALSE,
    message = "Not implemented yet"
  ))
}


# ============================================================================
# Main Integration Function
# ============================================================================

#' Determine Window Count (Phase 3A Main Function)
#'
#' Integrates all Phase 3A calculations to determine optimal window count
#' with comprehensive feasibility checks and optional maxIT optimization.
#'
#' @param diagnosis DiagnosisResult from Phase 2
#' @param target_cycle_time_sec Numeric, target maximum cycle time in seconds
#'   (NULL = use Phase 2 recommendation from required_cycle_time_sec).
#' @param n_windows_override Character or Integer, window count mode:
#'   - "optimize" (default): Script calculates optimal count
#'   - NULL: Same as "optimize"
#'   - Integer (e.g., 150): User-specified count (with feasibility check)
#' @param ms1_scans Integer, number of MS1 scans to reserve
#'   (NULL = use MODULE3A_DEFAULTS$default_ms1_scans = 1)
#' @param target_dppp Numeric, target DPPP (default: 7.0)
#' @param instrument_preset Character, instrument type (default: "astral")
#' @param custom_scan_rate_load_factor Numeric, override default load factor (0.8)
#' @param custom_maxIT_optimization List, override maxIT optimization config
#' @param enable_raw_metadata Logical, enable raw metadata integration (default: FALSE)
#' @param rawfile_dir Character, path to raw files (default: NULL)
#' @param min_windows Integer, minimum windows (default: 20)
#' @param max_windows Integer, maximum windows (default: 500)
#'
#' @return WindowCountResult object
#' @export
determine_window_count <- function(
  diagnosis,
  target_cycle_time_sec = NULL,
  n_windows_override = "optimize",
  ms1_scans = NULL,
  target_dppp = 7.0,
  instrument_preset = "astral",
  custom_scan_rate_load_factor = NULL,
  custom_maxIT_optimization = NULL,
  enable_raw_metadata = FALSE,
  rawfile_dir = NULL,
  min_windows = 20,
  max_windows = 500
) {

  cat("=== Phase 3A: Window Count Determination ===\n\n")

  # === Step 0: Load Instrument Configuration ===
  cat("Step 0: Loading instrument configuration...\n")

  # Source instrument config
  if (!exists("get_instrument_config")) {
    source("config/instruments.R")
  }

  instrument_config <- get_instrument_config(instrument_preset)

  # Convert ms to seconds
  ms1_time <- instrument_config$ms1_time / 1000
  ms2_time <- instrument_config$ms2_time / 1000
  max_scan_rate_hz <- instrument_config$max_scan_rate
  cycle_calculation <- instrument_config$cycle_calculation

  cat(sprintf("  Instrument: %s\n", instrument_config$name))
  cat(sprintf("  MS1 time: %.3f sec, MS2 time: %.3f sec\n", ms1_time, ms2_time))
  cat(sprintf("  Max scan rate: %.0f Hz (%s)\n",
              max_scan_rate_hz, cycle_calculation))

  # === Use Recommended Target Cycle Time if Not Provided ===
  # Phase 2 provides "required_cycle_time_sec" which is the MAXIMUM allowed cycle time
  # to achieve target DPPP. Phase 3A must ensure calculated cycle time <= this value.
  if (is.null(target_cycle_time_sec)) {
    # Try multiple field name patterns for compatibility
    # 1. Phase 2 actual format: diagnosis$recommendation$required_cycle_time_sec (primary)
    # 2. Mock generator format: diagnosis$recommended_cycle_time_sec
    # 3. Legacy alias: diagnosis$recommended_scan_time (deprecated but supported)
    # 4. Alternative: diagnosis$required_cycle_time_sec

    target_cycle_time_sec <- diagnosis$recommendation$required_cycle_time_sec

    if (is.null(target_cycle_time_sec)) {
      target_cycle_time_sec <- diagnosis$recommended_cycle_time_sec
    }

    if (is.null(target_cycle_time_sec)) {
      # Legacy compatibility: old mock generators used "recommended_scan_time"
      target_cycle_time_sec <- diagnosis$recommended_scan_time
    }

    if (is.null(target_cycle_time_sec)) {
      target_cycle_time_sec <- diagnosis$required_cycle_time_sec
    }

    if (is.null(target_cycle_time_sec)) {
      stop("Cannot find target cycle time in diagnosis result. ",
           "Expected one of: $recommendation$required_cycle_time_sec (Phase 2 standard), ",
           "$recommended_cycle_time_sec, $recommended_scan_time (legacy), ",
           "or $required_cycle_time_sec")
    }

    cat(sprintf("  Using recommended target cycle time: %.2f sec (from Phase 2)\n", target_cycle_time_sec))
  } else {
    cat(sprintf("  Using user-provided target cycle time: %.2f sec\n", target_cycle_time_sec))
  }

  # === Step 0.5: Process User Parameters and Apply Defaults ===
  cat("\nStep 0.5: Processing user parameters...\n")

  # MS1 scans: use user value or MODULE3A_DEFAULTS
  if (is.null(ms1_scans)) {
    ms1_scans <- MODULE3A_DEFAULTS$default_ms1_scans
    cat(sprintf("  MS1 scans: %d (using default)\n", ms1_scans))
  } else {
    cat(sprintf("  MS1 scans: %d (user-specified)\n", ms1_scans))
  }

  # Load factor: use custom or MODULE3A_DEFAULTS
  if (is.null(custom_scan_rate_load_factor)) {
    load_factor <- MODULE3A_DEFAULTS$scan_rate_load_factor
    cat(sprintf("  Scan rate load factor: %.2f (using default)\n", load_factor))
  } else {
    load_factor <- custom_scan_rate_load_factor
    cat(sprintf("  Scan rate load factor: %.2f (custom)\n", load_factor))
  }

  # MaxIT optimization config: use custom or MODULE3A_DEFAULTS
  if (is.null(custom_maxIT_optimization)) {
    maxIT_config <- MODULE3A_DEFAULTS$maxIT_optimization
    cat(sprintf("  MaxIT optimization: %s (using default config)\n",
                if (maxIT_config$enabled) "ENABLED" else "DISABLED"))
  } else {
    maxIT_config <- custom_maxIT_optimization
    cat(sprintf("  MaxIT optimization: %s (custom config)\n",
                if (maxIT_config$enabled) "ENABLED" else "DISABLED"))
  }

  # Calculate effective scan rate
  effective_scan_rate_hz <- calculate_effective_scan_rate(max_scan_rate_hz, load_factor)
  cat(sprintf("  Effective scan rate: %.1f Hz (%.0f%% of max %.0f Hz)\n",
              effective_scan_rate_hz, load_factor * 100, max_scan_rate_hz))

  # === Step 1: Determine Window Count (3-Mode Logic) ===
  cat("\nStep 1: Determining window count...\n")

  # Normalize NULL to "optimize"
  if (is.null(n_windows_override)) {
    n_windows_override <- "optimize"
    cat("  Mode: optimize (NULL → optimize)\n")
  }

  # Branch on mode
  if (is.character(n_windows_override) && n_windows_override == "optimize") {
    # Mode 1: Optimize
    cat("  Mode: optimize (script calculates optimal count)\n")
    n_windows <- calculate_window_count_from_target_cycletime(
      target_cycle_time_sec,
      effective_scan_rate_hz,
      ms1_scans,
      min_windows,
      max_windows
    )
    cat(sprintf("  Calculated window count: %d\n", n_windows))
    window_count_mode <- "optimize"

  } else if (is.numeric(n_windows_override) && length(n_windows_override) == 1) {
    # Mode 2: User-specified integer
    cat(sprintf("  Mode: user-specified (%d windows requested)\n", n_windows_override))
    n_windows <- as.integer(n_windows_override)

    # Feasibility check
    total_scans_needed <- n_windows + ms1_scans
    max_possible_scans <- floor(target_cycle_time_sec * max_scan_rate_hz)

    if (total_scans_needed > max_possible_scans) {
      stop(sprintf(
        "User-specified window count (%d) is INFEASIBLE.\n",
        n_windows,
        "  Reason: Total scans needed (%d = %d windows + %d MS1) exceeds maximum (%d scans in %.2f sec at %.0f Hz).\n",
        total_scans_needed, n_windows, ms1_scans, max_possible_scans,
        target_cycle_time_sec, max_scan_rate_hz,
        "  Solutions:\n",
        "    1. Reduce window count to ≤ %d\n",
        max_possible_scans - ms1_scans,
        "    2. Increase target_cycle_time_sec (current: %.2f sec)\n",
        target_cycle_time_sec,
        "    3. Reduce MS1 scans (current: %d)\n",
        ms1_scans
      ))
    }

    cat(sprintf("  Feasibility check: PASS (%d + %d MS1 = %d scans ≤ %d max)\n",
                n_windows, ms1_scans, total_scans_needed, max_possible_scans))
    window_count_mode <- sprintf("user_specified_%d", n_windows)

  } else {
    stop(sprintf(
      "Invalid n_windows_override: must be 'optimize', NULL, or a single positive integer. Got: %s",
      paste(deparse(n_windows_override), collapse = " ")
    ))
  }

  # === Step 2: Adjust for Raw Metadata (Optional) ===
  raw_metadata_result <- NULL
  if (enable_raw_metadata && !is.null(rawfile_dir)) {
    cat("\nStep 2: Adjusting for raw metadata...\n")
    raw_metadata_result <- adjust_for_injection_time(rawfile_dir, ms2_time)
    if (raw_metadata_result$it_adjustment_applied) {
      ms2_time <- raw_metadata_result$adjusted_ms2_time
      cat(sprintf("  Adjusted MS2 time: %.4f sec (from %.4f sec)\n",
                  ms2_time, raw_metadata_result$current_ms2_time))
    } else {
      cat(sprintf("  %s\n", raw_metadata_result$message))
    }
  } else {
    cat("\nStep 2: Raw metadata integration disabled\n")
  }

  # === Step 3: Calculate Cycle Time ===
  cat("\nStep 3: Calculating cycle time...\n")
  timing <- calculate_cycle_time(n_windows, cycle_calculation, ms1_time, ms2_time)
  cycle_time <- timing$cycle_time
  cat(sprintf("  Cycle time: %.3f sec (%s)\n",
              cycle_time, cycle_calculation))
  cat(sprintf("  MS1: %.3f sec, Total MS2: %.3f sec (%.3f sec/window × %d)\n",
              timing$ms1_time, timing$total_ms2_time, timing$ms2_time_per_window, n_windows))

  # === Step 3.5: MaxIT Optimization (if enabled and slack available) ===
  maxIT_result <- NULL
  if (maxIT_config$enabled) {
    cat("\nStep 3.5: MaxIT optimization from slack...\n")
    maxIT_result <- optimize_maxIT_from_slack(
      n_windows,
      target_cycle_time_sec,
      cycle_time,
      ms1_time,
      ms2_time,
      cycle_calculation,
      maxIT_config
    )

    # Update ms2_time if optimization applied
    if (maxIT_result$optimization_applied) {
      ms2_time <- maxIT_result$optimized_ms2_time_sec

      # Recalculate cycle time with optimized maxIT
      timing <- calculate_cycle_time(n_windows, cycle_calculation, ms1_time, ms2_time)
      cycle_time <- timing$cycle_time

      cat(sprintf("  ✅ Updated cycle time: %.3f sec (with optimized maxIT)\n", cycle_time))
    }
  } else {
    cat("\nStep 3.5: MaxIT optimization disabled\n")
  }

  # === Step 4: Feasibility Checks ===
  cat("\nStep 4: Checking feasibility...\n")

  # Check 4a: Scan Rate
  scan_rate_check <- check_scan_rate_feasibility(
    n_windows, target_cycle_time_sec, instrument_config$max_scan_rate, ms1_scans
  )
  if (scan_rate_check$is_feasible) {
    cat("  ✅ Scan rate check: PASS\n")
    cat(sprintf("     %d scans needed ≤ %d scans possible\n",
                scan_rate_check$total_scans_needed,
                scan_rate_check$max_possible_scans))
  } else {
    cat(sprintf("  ⚠️  Scan rate check: FAIL\n     %s\n", scan_rate_check$warning))
  }

  # Check 4b: Cycle Time
  # Verify calculated cycle time <= target cycle time constraint
  cycle_time_check <- check_cycle_time_feasibility(cycle_time, target_cycle_time_sec)
  if (cycle_time_check$is_feasible) {
    cat(sprintf("  ✅ Cycle time check: PASS (margin: %.3f sec)\n",
                cycle_time_check$margin))
  } else {
    cat(sprintf("  ⚠️  Cycle time check: FAIL\n     %s\n", cycle_time_check$warning))
  }

  # Check 4c: Minimum Windows
  min_windows_check <- (n_windows >= min_windows)
  if (min_windows_check) {
    cat(sprintf("  ✅ Minimum windows check: PASS (%d >= %d)\n",
                n_windows, min_windows))
  } else {
    cat(sprintf("  ⚠️  Minimum windows check: FAIL (%d < %d)\n",
                n_windows, min_windows))
  }

  # === Overall Feasibility ===
  is_feasible <- scan_rate_check$is_feasible &&
                 cycle_time_check$is_feasible &&
                 min_windows_check

  # === Collect Warnings ===
  warnings <- character(0)
  if (!is.null(scan_rate_check$warning)) {
    warnings <- c(warnings, scan_rate_check$warning)
  }
  if (!is.null(cycle_time_check$warning)) {
    warnings <- c(warnings, cycle_time_check$warning)
  }
  if (!min_windows_check) {
    warnings <- c(warnings, sprintf(
      "Window count (%d) below minimum (%d)", n_windows, min_windows
    ))
  }

  # === Step 5: Package Results ===
  cat("\nStep 5: Packaging results...\n")
  result <- structure(
    list(
      window_count = n_windows,
      target_cycle_time_sec = target_cycle_time_sec,  # CONSTRAINT from Phase 2
      calculated_cycle_time_sec = cycle_time,         # ACTUAL calculated cycle time

      window_count_mode = list(
        mode = window_count_mode,
        description = if (window_count_mode == "optimize") {
          "Script-optimized based on target cycle time and scan rate"
        } else {
          sprintf("User-specified count: %d windows", n_windows)
        }
      ),

      scan_rate_settings = list(
        max_scan_rate_hz = max_scan_rate_hz,
        load_factor = load_factor,
        effective_scan_rate_hz = effective_scan_rate_hz,
        ms1_scans = ms1_scans
      ),

      timing_breakdown = list(
        ms1_time = timing$ms1_time,
        ms2_time_per_window = timing$ms2_time_per_window,
        total_ms2_time = timing$total_ms2_time,
        overhead_time = timing$overhead_time
      ),

      maxIT_optimization = if (!is.null(maxIT_result)) maxIT_result else list(
        optimization_applied = FALSE,
        message = "MaxIT optimization disabled"
      ),

      feasibility = list(
        is_feasible = is_feasible,
        scan_rate_check = scan_rate_check$is_feasible,
        cycle_time_check = cycle_time_check$is_feasible,
        min_windows_check = min_windows_check,
        warnings = warnings
      ),

      raw_metadata = if (!is.null(raw_metadata_result)) raw_metadata_result else list(),

      metadata = list(
        cycle_calculation = cycle_calculation,
        instrument_name = instrument_config$name,
        target_dppp = target_dppp,
        calculation_timestamp = Sys.time()
      )
    ),
    class = c("WindowCountResult", "list")
  )

  cat("\n=== Phase 3A Complete ===\n")
  if (is_feasible) {
    cat(sprintf("✅ Window count determination successful: %d windows\n", n_windows))
    cat(sprintf("   Calculated cycle time: %.3f sec (≤ target: %.2f sec)\n",
                cycle_time, target_cycle_time_sec))
  } else {
    cat("⚠️  Window count determination completed with warnings.\n")
    cat("   Review feasibility checks above.\n")
    if (length(warnings) > 0) {
      cat("\n   Warnings:\n")
      for (w in warnings) {
        cat(sprintf("   - %s\n", w))
      }
    }
  }

  return(result)
}


cat("✅ Module 3A (Window Count Determination) loaded successfully\n")
cat("   Available functions:\n")
cat("   - calculate_window_count_from_target_cycletime(target_cycle_time_sec, scan_rate_hz, ...)\n")
cat("   - calculate_cycle_time(n_windows, instrument_type, ms1_time, ms2_time)\n")
cat("   - check_scan_rate_feasibility(n_windows, target_cycle_time_sec, max_scan_rate_hz)\n")
cat("   - check_cycle_time_feasibility(calculated_cycle_time_sec, target_cycle_time_sec)\n")
cat("   - adjust_for_injection_time(rawfile_dir, current_ms2_time)\n")
cat("   - determine_window_count(diagnosis, ...) [main function]\n")
