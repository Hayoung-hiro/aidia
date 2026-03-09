# optimization_planning.R - Stage 2: Optimization Planning (Refactored)
#
# Purpose: Unified module for DPPP diagnosis and window count determination
#
# This module integrates:
#   - Former stage2_dppp_diagnosis.R: DPPP analysis and cycle time recommendation
#   - Former module3a_window_count.R: Window count calculation and feasibility checks
#
# Input: ValidatedData from Stage 1
# Output: OptimizationPlan with cycle time constraints and window count
#
# Version: 2.0 (Refactored)
# Last Updated: 2025-10-25


# =============================================================================
# Helper Functions
# =============================================================================

#' Estimate cycle time from RT gradient length
#'
#' Auto-estimates cycle time when not provided by user.
#' Uses heuristic: cycle_time ~= gradient_length / 15 (capped at 3.5 sec)
#' This assumes ~15 data points per chromatographic peak as initial estimate.
#'
#' @param rt_values Numeric vector of RT.Start values (in minutes)
#' @param verbose Logical, whether to print estimation message (default: TRUE)
#' @return Estimated cycle time in seconds
#' @keywords internal
estimate_cycle_time_from_gradient <- function(rt_values, verbose = TRUE) {
  gradient_length <- max(rt_values) - min(rt_values)
  cycle_time <- min(gradient_length / 15, 3.5)  # Cap at 3.5 sec

  if (verbose) {
    cat(sprintf("  [i] Auto-estimated cycle time: %.3f sec (from %.1f min gradient)\n",
                cycle_time, gradient_length))
  }

  cycle_time
}

# =============================================================================
# Main Planning Function
# =============================================================================

#' Plan DIA Window Optimization (Stage 2 Main Function)
#'
#' Integrates DPPP diagnosis and window count determination into a unified
#' planning stage. This function analyzes current DPPP status, calculates
#' required cycle time, and determines feasible window count.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param current_cycle_time Numeric, current cycle time in seconds (default: NULL = auto-estimate)
#'   If NULL, automatically estimated from gradient length (gradient_min / 15, max 3.5 sec)
#' @param instrument_preset Character, instrument type (default: "astral")
#'   Options: "astral", "orbitrap", "exploris", "timstof", etc.
#' @param target_dppp Numeric, target minimum DPPP value (default: 7.0)
#'   - 7.0: Quantification mode (recommended)
#'   - 4.0: Balanced mode
#'   - 1.5: Identification mode
#' @param target_satisfaction Numeric, target satisfaction ratio 0-1 (default: 0.85)
#'   - 0.85 = 85% of precursors meet target DPPP
#' @param dppp_tolerance Numeric, tolerance for DPPP matching (default: 0.0)
#' @param load_factor Numeric, scan rate utilization 0-1 (default: 0.8)
#'   - 0.8: Conservative (recommended for stability)
#'   - 0.9: Moderate
#'   - 1.0: Aggressive (may cause instability)
#' @param ms1_scans_per_cycle Integer, MS1 scans per duty cycle (default: NULL = auto-detect)
#'   - NULL: Auto-detect from instrument (parallel=0, sequential=1)
#'   - 0: Parallel instruments (Astral, TimsTOF) - MS1 acquired during MS2
#'   - 1: Sequential instruments (Orbitrap) - MS1 acquired before MS2
#' @param warning_threshold_windows Integer, low window count warning threshold (default: 5)
#'   - Issues warning if window count falls below this threshold
#' @param ms2_resolution Integer or NULL, optional MS2 resolution override (default: NULL)
#' @param ms2_time_override Numeric or NULL, optional MS2 injection time override in seconds (default: NULL)
#'
#' @return OptimizationPlan S3 object
#' @export
#'
#' @examples
#' \dontrun{
#' # Basic usage
#' plan <- plan_optimization(
#'   validated_data,
#'   current_cycle_time = 3.5,
#'   instrument_preset = "astral"
#' )
#'
#' # Custom parameters
#' plan <- plan_optimization(
#'   validated_data,
#'   current_cycle_time = 2.0,
#'   instrument_preset = "orbitrap",
#'   target_dppp = 4.0,  # Balanced mode
#'   target_satisfaction = 0.90,  # Stricter
#'   load_factor = 0.9  # More aggressive
#' )
#' }
plan_optimization <- function(
  validated_data,
  current_cycle_time = NULL,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.85,
  dppp_tolerance = 0.0,
  load_factor = 1.0,
  ms1_scans_per_cycle = NULL,
  warning_threshold_windows = 5,
  ms2_resolution = NULL,  # Optional MS2 resolution override (e.g., 30000)
  ms2_time_override = NULL  # Optional MS2 IT override in seconds (e.g., 0.050 = 50ms)
) {

  # Start timing
  timer <- create_timer()

  print_header("Stage 2: Optimization Planning", width = 55)

  # ===================================================================
  # Step 1: Input Validation
  # ===================================================================
  print_step(1, "Input Validation")

  validate_input_type(validated_data, "ValidatedData", "validated_data")

  # Auto-estimate cycle_time if not provided
  # IMPORTANT: Use simple heuristic WITHOUT target_dppp to avoid current ~= recommended
  # The "current" cycle time should reflect a reasonable starting point, not the optimal value
  if (is.null(current_cycle_time)) {
    # Use simple heuristic: gradient_length / 15, capped at 3.5 sec
    # This represents a typical DIA cycle time, NOT the optimal for target_dppp
    current_cycle_time <- estimate_cycle_time_from_gradient(
      validated_data$data$RT.Apex,
      verbose = TRUE
    )
  }

  validate_numeric_range(current_cycle_time, min = 0, param_name = "current_cycle_time")
  validate_numeric_range(target_dppp, min = 0, param_name = "target_dppp")
  validate_numeric_range(target_satisfaction, min = 0, max = 1, param_name = "target_satisfaction")
  validate_numeric_range(load_factor, min = 0, max = 1, param_name = "load_factor")

  print_success("Input validation passed")

  # ===================================================================
  # Step 2: Load Instrument Configuration
  # ===================================================================
  print_step(2, "Load Instrument Configuration")

  instrument_config <- get_instrument_config(instrument_preset)

  # Auto-detect MS1 scans per cycle if not specified
  if (is.null(ms1_scans_per_cycle)) {
    ms1_scans_per_cycle <- get_ms1_scans_per_cycle(NULL, instrument_config)
  }

  # Get max_windows from instrument config (hardware constraint)
  max_windows <- instrument_config$max_windows

  # Get resolution and analyzer type (use config default if not overridden)
  resolution <- if (!is.null(ms2_resolution)) {
    ms2_resolution
  } else if (!is.null(instrument_config$ms2_resolution)) {
    instrument_config$ms2_resolution
  } else {
    30000  # Default 30K for backwards compatibility
  }

  analyzer_type <- if (!is.null(instrument_config$analyzer_type)) {
    instrument_config$analyzer_type
  } else {
    "orbitrap"  # Default to Orbitrap
  }

  print_info(sprintf("Instrument: %s", instrument_config$name))
  print_info(sprintf("Max scan rate: %.0f Hz (%s acquisition)",
                     instrument_config$max_scan_rate,
                     instrument_config$cycle_calculation))
  print_info(sprintf("MS1 scans per cycle: %d", ms1_scans_per_cycle))
  print_info(sprintf("Max windows: %d (hardware limit)", max_windows))
  print_info(sprintf("MS2 Resolution: %gK (%s analyzer)",
                     resolution / 1000, analyzer_type))
  print_info(sprintf("Load factor: %.0f%% (effective: %.1f Hz)",
                     load_factor * 100,
                     instrument_config$max_scan_rate * load_factor))

  # ===================================================================
  # Step 3: DPPP Diagnosis
  # ===================================================================
  print_step(3, "DPPP Diagnosis")

  diagnosis <- diagnose_dppp_internal(
    validated_data = validated_data,
    current_cycle_time = current_cycle_time,
    target_dppp = target_dppp,
    target_satisfaction = target_satisfaction,
    dppp_tolerance = dppp_tolerance
  )

  print_info(sprintf("Current satisfaction: %.1f%% (%d / %d precursors)",
                     diagnosis$satisfaction_ratio * 100,
                     diagnosis$n_satisfied,
                     diagnosis$n_total))
  print_info(sprintf("Current DPPP: %.2f +/- %.2f (median: %.2f)",
                     diagnosis$dppp_stats$mean,
                     diagnosis$dppp_stats$sd,
                     diagnosis$dppp_stats$median))

  # ===================================================================
  # Step 4: Calculate Required Cycle Time
  # ===================================================================
  print_step(4, "Calculate Required Cycle Time")

  required_cycle_time <- calculate_required_cycle_time_internal(
    fwhm_seconds = get_fwhm_values(validated_data, unit = "seconds"),
    target_dppp = target_dppp,
    target_satisfaction = target_satisfaction
  )

  # Round to 2 decimal places (instrument precision limit)
  required_cycle_time <- round(required_cycle_time, 2)

  print_info(sprintf("Current cycle time: %.3f sec", current_cycle_time))
  print_info(sprintf("Required cycle time: <= %.2f sec", required_cycle_time))

  # Determine adjustment needed
  needs_adjustment <- abs(required_cycle_time - current_cycle_time) > 0.01

  if (required_cycle_time < current_cycle_time) {
    adjustment_direction <- "REDUCE"
    print_warning(sprintf("Need to REDUCE cycle time by %.3f sec (%.1f%%)",
                          current_cycle_time - required_cycle_time,
                          (1 - required_cycle_time / current_cycle_time) * 100))
  } else if (required_cycle_time > current_cycle_time) {
    adjustment_direction <- "INCREASE"
    print_success(sprintf("Can INCREASE cycle time by %.3f sec (%.1f%%)",
                          required_cycle_time - current_cycle_time,
                          (required_cycle_time / current_cycle_time - 1) * 100))
  } else {
    adjustment_direction <- "MAINTAIN"
    print_success("Current cycle time is optimal")
  }

  # ===================================================================
  # Step 5: Determine Window Count (using t_scan formula)
  # ===================================================================
  print_step(5, "Determine Window Count")

  # Get MS1 time in seconds
  ms1_time <- instrument_config$ms1_time / 1000  # ms to sec

  # Resolve MS2 time (handle "auto" mode and override)
  if (!is.null(ms2_time_override)) {
    # User provided custom IT override
    ms2_time_resolved <- ms2_time_override * 1000  # sec to ms
    ms2_time <- ms2_time_override
    print_info(sprintf("IT Mode: CUSTOM (IT = %.1f ms, user override)",
                       ms2_time_resolved))
  } else {
    # Use config value (may be "auto" or numeric)
    ms2_time_raw <- instrument_config$ms2_time
    ms2_time_resolved <- resolve_injection_time(
      ms2_time = ms2_time_raw,
      resolution = resolution,
      analyzer_type = analyzer_type
    )
    ms2_time <- ms2_time_resolved / 1000  # ms to sec

    # Display IT mode info
    if (is.character(ms2_time_raw) && tolower(ms2_time_raw) == "auto") {
      print_info(sprintf("IT Mode: AUTO (IT = T_transient = %.1f ms, Sweet Spot)",
                         ms2_time_resolved))
    }
  }

  # Calculate window count using the correct t_scan formula
  # t_scan = max(T_transient, IT) + delta
  window_result <- calculate_window_count_internal(
    target_cycle_time_sec = required_cycle_time,
    ms1_time_sec = ms1_time,
    ms2_time_sec = ms2_time,
    resolution = resolution,
    analyzer_type = analyzer_type,
    cycle_mode = instrument_config$cycle_calculation,
    warning_threshold_windows = warning_threshold_windows,
    max_windows = max_windows
  )

  window_count <- window_result$n_windows

  # Display scan time breakdown
  print_info(sprintf("Scan Time Breakdown:"))
  print_info(sprintf("   T_transient: %.1f ms (from %gK resolution)",
                     window_result$transient_ms, resolution / 1000))
  print_info(sprintf("   IT (config): %.1f ms", ms2_time * 1000))
  print_info(sprintf("   Overhead delta: %.1f ms", window_result$overhead_ms))
  print_info(sprintf("   t_scan: %.1f ms (max(%.1f, %.1f) + %.1f)",
                     window_result$t_scan_ms,
                     window_result$transient_ms,
                     ms2_time * 1000,
                     window_result$overhead_ms))
  print_info(sprintf("   Limiting factor: %s", window_result$limiting_factor))

  print_info(sprintf("Window count: %d per RT bin", window_count))

  # Show calculation method based on cycle mode
  if (instrument_config$cycle_calculation == "sequential") {
    print_info(sprintf("Calculation: floor((%.3f - %.3f) sec / %.3f sec) = %d",
                       required_cycle_time, ms1_time,
                       window_result$t_scan_ms / 1000, window_count))
  } else {
    print_info(sprintf("Calculation (parallel): floor(%.3f sec / %.3f sec) = %d",
                       required_cycle_time,
                       window_result$t_scan_ms / 1000, window_count))
  }

  # ===================================================================
  # Step 6: Feasibility Checks
  # ===================================================================
  print_step(6, "Feasibility Checks")

  # Calculate actual cycle time with determined window count (using t_scan)
  actual_cycle_time <- calculate_cycle_time_internal(
    n_windows = window_count,
    cycle_mode = instrument_config$cycle_calculation,
    ms1_time = ms1_time,
    ms2_time = ms2_time,
    resolution = resolution,
    analyzer_type = analyzer_type
  )

  print_info(sprintf("Actual cycle time: %.3f sec", actual_cycle_time))

  # Feasibility checks
  feasibility <- list()

  # Check 1: Cycle time constraint
  feasibility$cycle_time_ok <- actual_cycle_time <= (required_cycle_time + 0.01)
  if (feasibility$cycle_time_ok) {
    print_success(sprintf("Cycle time check: PASS (%.3f <= %.3f sec)",
                          actual_cycle_time, required_cycle_time))
  } else {
    print_warning(sprintf("Cycle time check: FAIL (%.3f > %.3f sec)",
                          actual_cycle_time, required_cycle_time))
  }

  # Check 2: Scan rate (apply load_factor to effective scan rate)
  total_scans_needed <- window_count + ms1_scans_per_cycle
  effective_scan_rate <- instrument_config$max_scan_rate * load_factor
  max_possible_scans <- floor(required_cycle_time * effective_scan_rate)
  feasibility$scan_rate_ok <- total_scans_needed <= max_possible_scans

  if (feasibility$scan_rate_ok) {
    print_success(sprintf("Scan rate check: PASS (%d scans <= %d max)",
                          total_scans_needed, max_possible_scans))
  } else {
    print_warning(sprintf("Scan rate check: FAIL (%d scans > %d max)",
                          total_scans_needed, max_possible_scans))
  }

  # Check 3: Window count - max only (warning threshold handled in calculation)
  feasibility$window_range_ok <- window_count <= max_windows
  if (feasibility$window_range_ok) {
    print_success(sprintf("Window range check: PASS (%d <= %d max)",
                          window_count, max_windows))
  } else {
    print_warning(sprintf("Window range check: FAIL (%d > %d max)",
                          window_count, max_windows))
  }

  # Overall feasibility
  is_feasible <- all(unlist(feasibility))

  # ===================================================================
  # Step 7: Injection Time Optimization
  # ===================================================================
  print_step(7, "Injection Time Optimization")

  # Calculate IT optimization based on cycle time budget
  it_optimization <- optimize_injection_time_internal(
    n_windows = window_count,
    cycle_mode = instrument_config$cycle_calculation,
    required_cycle_time_sec = required_cycle_time,
    ms1_time_sec = ms1_time,
    base_ms2_time_sec = ms2_time,
    max_windows = max_windows
  )

  print_info(sprintf("Base IT: %.1f ms (from instrument config)",
                     ms2_time * 1000))
  print_info(sprintf("Optimized IT: %.1f ms", it_optimization$optimized_it_ms))
  print_info(sprintf("IT gain: +%.1f ms (%.1f%% increase)",
                     it_optimization$it_gain_ms,
                     it_optimization$it_gain_pct))

  if (it_optimization$is_spec_limited) {
    print_warning(sprintf(
      "Window count reduced from %d to %d (instrument spec limit)",
      it_optimization$requested_windows,
      it_optimization$actual_windows
    ))
  }

  # ===================================================================
  # Step 8: Package Results
  # ===================================================================
  print_step(8, "Package Results")

  result <- create_s3_object(
    list(
      # Primary outputs
      required_cycle_time_sec = required_cycle_time,
      window_count_per_bin = window_count,
      actual_cycle_time_sec = actual_cycle_time,

      # Diagnosis
      diagnosis = list(
        current_cycle_time_sec = current_cycle_time,
        current_satisfaction_ratio = diagnosis$satisfaction_ratio,
        current_dppp_mean = diagnosis$dppp_stats$mean,
        current_dppp_median = diagnosis$dppp_stats$median,
        current_dppp_sd = diagnosis$dppp_stats$sd,
        n_satisfied = diagnosis$n_satisfied,
        n_total = diagnosis$n_total
      ),

      # Recommendation
      recommendation = list(
        needs_adjustment = needs_adjustment,
        adjustment_direction = adjustment_direction,
        adjustment_magnitude_sec = abs(required_cycle_time - current_cycle_time),
        adjustment_magnitude_pct = abs(required_cycle_time / current_cycle_time - 1) * 100
      ),

      # Feasibility
      feasibility = list(
        is_feasible = is_feasible,
        cycle_time_ok = feasibility$cycle_time_ok,
        scan_rate_ok = feasibility$scan_rate_ok,
        window_range_ok = feasibility$window_range_ok,
        total_scans_needed = total_scans_needed,
        max_possible_scans = max_possible_scans
      ),

      # Instrument configuration
      instrument = list(
        preset = instrument_preset,
        name = instrument_config$name,
        max_scan_rate_hz = instrument_config$max_scan_rate,
        load_factor = load_factor,
        ms1_scans_per_cycle = ms1_scans_per_cycle,
        cycle_mode = instrument_config$cycle_calculation,
        ms1_time_sec = ms1_time,
        ms2_time_sec = ms2_time,
        ms2_resolution = resolution,
        analyzer_type = analyzer_type
      ),

      # Scan Time Analysis (NEW - t_scan = max(T_transient, IT) + delta)
      scan_time = list(
        t_scan_ms = window_result$t_scan_ms,
        transient_ms = window_result$transient_ms,
        injection_time_ms = ms2_time * 1000,
        overhead_ms = window_result$overhead_ms,
        limiting_factor = window_result$limiting_factor,
        sweet_spot_it_ms = window_result$sweet_spot_it_ms
      ),

      # IT Optimization (NEW)
      it_optimization = list(
        base_it_ms = ms2_time * 1000,
        optimized_it_ms = it_optimization$optimized_it_ms,
        it_gain_ms = it_optimization$it_gain_ms,
        it_gain_pct = it_optimization$it_gain_pct,
        is_spec_limited = it_optimization$is_spec_limited,
        parallel_filling_efficiency = it_optimization$parallel_filling_efficiency,
        slack_time_ms = it_optimization$slack_time_ms
      ),

      # Parameters
      parameters = list(
        target_dppp = target_dppp,
        target_satisfaction = target_satisfaction,
        dppp_tolerance = dppp_tolerance,
        warning_threshold_windows = warning_threshold_windows,
        max_windows = max_windows
      ),

      # Metadata
      metadata = list(
        planning_timestamp = Sys.time(),
        processing_time_sec = timer$elapsed()
      )
    ),
    class_name = "OptimizationPlan"
  )

  # ===================================================================
  # Summary
  # ===================================================================
  cat("\n")
  cat(rep("-", 55), "\n", sep = "")
  cat("Stage 2 Complete\n")
  cat(rep("-", 55), "\n", sep = "")

  if (is_feasible) {
    cat(sprintf("[OK] Optimization plan is FEASIBLE\n"))
  } else {
    cat(sprintf("[!] Optimization plan has WARNINGS\n"))
  }

  cat(sprintf("   Window count: %d per RT bin\n", window_count))
  cat(sprintf("   Required cycle time: <= %.3f sec\n", required_cycle_time))
  cat(sprintf("   Actual cycle time: %.3f sec\n", actual_cycle_time))
  cat(sprintf("   Target satisfaction: %.0f%% (current: %.1f%%)\n",
              target_satisfaction * 100,
              diagnosis$satisfaction_ratio * 100))
  cat(sprintf("   Processing time: %.2f sec\n", timer$elapsed()))
  cat("\n")

  return(result)
}


# =============================================================================
# Internal Helper Functions
# =============================================================================

#' Diagnose Current DPPP Status (Internal)
#' @keywords internal
diagnose_dppp_internal <- function(validated_data, current_cycle_time,
                                   target_dppp, target_satisfaction,
                                   dppp_tolerance) {

  fwhm_seconds <- get_fwhm_values(validated_data, unit = "seconds")

  # Calculate DPPP for all precursors
  dppp_values <- calculate_dppp(fwhm_seconds, current_cycle_time)

  # Calculate satisfaction
  satisfaction <- calculate_satisfaction_ratio(
    dppp_values,
    target_dppp,
    tolerance = dppp_tolerance,
    direction = "greater"
  )

  # Calculate statistics
  dppp_stats <- calculate_summary_stats(dppp_values)

  list(
    dppp_values = dppp_values,
    dppp_stats = dppp_stats,
    satisfaction_ratio = satisfaction$satisfaction_ratio,
    n_satisfied = satisfaction$n_satisfied,
    n_total = satisfaction$n_total,
    threshold = satisfaction$threshold_lower
  )
}

#' Calculate Required Cycle Time (Internal)
#'
#' Uses windowed percentile for robustness against FWHM outliers.
#' Instead of single percentile, averages over a small window (+/-2%).
#'
#' @keywords internal
calculate_required_cycle_time_internal <- function(fwhm_seconds, target_dppp,
                                                   target_satisfaction,
                                                   robustness_window = 0.02) {

  # Find critical FWHM using windowed percentile for robustness
  critical_percentile <- 1 - target_satisfaction

  # Use percentile window for robustness against outliers
  percentile_lower <- max(0, critical_percentile - robustness_window)
  percentile_upper <- min(1, critical_percentile + robustness_window)

  # Get FWHM values at both ends of window
  fwhm_range <- quantile(fwhm_seconds, c(percentile_lower, percentile_upper),
                         names = FALSE, na.rm = TRUE)

  # Use mean of the window for stability
  fwhm_critical <- mean(fwhm_range)

  # Calculate maximum cycle time for this critical FWHM
  required_max_cycle_time <- (PEAK_WIDTH_FACTOR * fwhm_critical) / target_dppp

  return(required_max_cycle_time)
}

#' Calculate Window Count from Cycle Time (Internal)
#'
#' Uses the correct scan time formula: t_scan = max(T_transient, IT) + delta
#' Resolution determines T_transient, which sets the minimum scan time floor.
#'
#' @param target_cycle_time_sec Target cycle time in seconds
#' @param ms1_time_sec MS1 scan time in seconds
#' @param ms2_time_sec MS2 injection time in seconds (IT)
#' @param resolution MS2 resolution (e.g., 30000 for 30K)
#' @param analyzer_type Analyzer type ("orbitrap" or "tof")
#' @param cycle_mode "parallel" or "sequential"
#' @param warning_threshold_windows Low window count warning threshold
#' @param max_windows Instrument maximum windows
#'
#' @return List with window count and scan time details
#' @keywords internal
calculate_window_count_internal <- function(target_cycle_time_sec,
                                            ms1_time_sec,
                                            ms2_time_sec,
                                            resolution = 30000,
                                            analyzer_type = "orbitrap",
                                            cycle_mode = "sequential",
                                            warning_threshold_windows = 5,
                                            max_windows = 300) {

  # Calculate actual MS2 scan time using the correct formula
  # t_scan = max(T_transient, IT) + delta
  scan_time_info <- calculate_ms2_scan_time(
    resolution = resolution,
    injection_time_ms = ms2_time_sec * 1000,  # sec to ms
    analyzer = analyzer_type
  )

  t_scan_sec <- scan_time_info$t_scan_ms / 1000  # ms to sec

  # Calculate window count based on cycle mode
  if (cycle_mode == "parallel") {
    # Parallel: MS2 total must fit within cycle time
    # cycle_time = max(ms1_time, n_windows * t_scan)
    # If ms1_time is limiting, MS2 can run alongside
    # Effective available time for MS2 = cycle_time
    n_windows <- floor(target_cycle_time_sec / t_scan_sec)
  } else {
    # Sequential: ms1_time + n_windows * t_scan <= cycle_time
    available_time <- target_cycle_time_sec - ms1_time_sec

    if (available_time <= 0) {
      stop(sprintf(
        "Insufficient cycle time (%.3f sec) for MS1 (%.3f sec). Cannot create valid windows.",
        target_cycle_time_sec, ms1_time_sec
      ))
    }

    n_windows <- floor(available_time / t_scan_sec)
  }

  # Validate non-negative window count
  if (n_windows < 0) {
    stop(sprintf(
      "Insufficient cycle time (%.3f sec) for scan time (%.1f ms). Cannot create valid windows.",
      target_cycle_time_sec, scan_time_info$t_scan_ms
    ))
  }

  # Ensure at least 1 window
  if (n_windows == 0) {
    warning("Only 1 window possible at current cycle time. Forcing n_windows = 1.")
    n_windows <- 1
  }

  # Warning if too low (no enforcement)
  if (n_windows <= warning_threshold_windows) {
    warning(sprintf(
      "Window count is low (%d <= %d). Consider adjusting target_cycle_time or resolution.",
      n_windows, warning_threshold_windows
    ))
  }

  # Apply max constraint only
  n_windows <- min(n_windows, max_windows)

  return(list(
    n_windows = as.integer(n_windows),
    t_scan_ms = scan_time_info$t_scan_ms,
    transient_ms = scan_time_info$transient_ms,
    overhead_ms = scan_time_info$overhead_ms,
    limiting_factor = scan_time_info$limiting_factor,
    sweet_spot_it_ms = scan_time_info$sweet_spot_it_ms
  ))
}

#' Calculate Cycle Time (Internal)
#'
#' Uses the correct scan time formula: t_scan = max(T_transient, IT) + delta
#'
#' @param n_windows Number of MS2 windows
#' @param cycle_mode "parallel" or "sequential"
#' @param ms1_time MS1 scan time in seconds
#' @param ms2_time MS2 injection time in seconds (IT)
#' @param resolution MS2 resolution (e.g., 30000)
#' @param analyzer_type Analyzer type ("orbitrap" or "tof")
#'
#' @return Cycle time in seconds
#' @keywords internal
calculate_cycle_time_internal <- function(n_windows, cycle_mode, ms1_time,
                                          ms2_time, resolution = 30000,
                                          analyzer_type = "orbitrap") {

  # Calculate actual MS2 scan time
  scan_time_info <- calculate_ms2_scan_time(
    resolution = resolution,
    injection_time_ms = ms2_time * 1000,  # sec to ms
    analyzer = analyzer_type
  )

  t_scan_sec <- scan_time_info$t_scan_ms / 1000  # ms to sec
  total_ms2_time <- n_windows * t_scan_sec

  if (cycle_mode == "parallel") {
    # MS2 during MS1
    cycle_time <- max(ms1_time, total_ms2_time)
  } else {
    # MS1 then MS2
    cycle_time <- ms1_time + total_ms2_time
  }

  return(cycle_time)
}

#' Optimize Injection Time (Internal)
#'
#' Core IT optimization logic:
#' 1. Calculate N windows from required cycle time
#' 2. Verify N against instrument spec (max_windows)
#' 3. If N exceeds spec, cap at max and use slack time for IT
#' 4. Calculate optimized IT and efficiency metrics
#'
#' @param n_windows Calculated window count
#' @param cycle_mode "parallel" or "sequential"
#' @param required_cycle_time_sec Required cycle time in seconds
#' @param ms1_time_sec MS1 scan time in seconds
#' @param base_ms2_time_sec Base MS2/IT time in seconds (from instrument config)
#' @param max_windows Instrument spec maximum windows
#'
#' @return List with IT optimization results
#' @keywords internal
optimize_injection_time_internal <- function(n_windows,
                                              cycle_mode,
                                              required_cycle_time_sec,
                                              ms1_time_sec,
                                              base_ms2_time_sec,
                                              max_windows) {

  # Initialize results
  requested_windows <- n_windows
  actual_windows <- n_windows
  is_spec_limited <- FALSE

  # Step 1: Check if N exceeds instrument spec
  if (n_windows > max_windows) {
    actual_windows <- max_windows
    is_spec_limited <- TRUE
  }

  # Step 2: Calculate actual cycle time with current settings
  base_cycle_time <- calculate_cycle_time_internal(
    n_windows = actual_windows,
    cycle_mode = cycle_mode,
    ms1_time = ms1_time_sec,
    ms2_time = base_ms2_time_sec
  )

  # Step 3: Calculate slack time (available for IT boost)
  # slack_time = required_cycle_time - actual_cycle_time
  slack_time_sec <- required_cycle_time_sec - base_cycle_time

  # Step 4: Distribute slack time to IT
  # For sequential: slack can be distributed to each MS2 scan
  # For parallel: more complex - depends on whether MS1 or MS2 dominates
  if (cycle_mode == "sequential") {
    # Sequential: each window can get extra IT
    it_gain_per_window_sec <- slack_time_sec / actual_windows
    optimized_it_sec <- base_ms2_time_sec + max(0, it_gain_per_window_sec)
  } else {
    # Parallel: only if MS2 total is limiting (not MS1)
    total_ms2_time <- actual_windows * base_ms2_time_sec

    if (total_ms2_time >= ms1_time_sec) {
      # MS2 is limiting - can use slack for IT
      it_gain_per_window_sec <- slack_time_sec / actual_windows
      optimized_it_sec <- base_ms2_time_sec + max(0, it_gain_per_window_sec)
    } else {
      # MS1 is limiting - MS2 has inherent slack
      inherent_slack_sec <- (ms1_time_sec - total_ms2_time) / actual_windows
      # Plus any additional slack from required > actual
      additional_slack_sec <- max(0, slack_time_sec) / actual_windows
      optimized_it_sec <- base_ms2_time_sec + inherent_slack_sec + additional_slack_sec
    }
  }

  # Convert to ms for output
  base_it_ms <- base_ms2_time_sec * 1000
  optimized_it_ms <- optimized_it_sec * 1000
  it_gain_ms <- optimized_it_ms - base_it_ms
  it_gain_pct <- (it_gain_ms / base_it_ms) * 100

  # Step 5: Calculate Parallel Filling Efficiency (for parallel instruments)
  # Efficiency = IT / (Transient + delta)
  # Approximation: using ms2_time as proxy for transient
  if (cycle_mode == "parallel") {
    # Estimate overhead (20% of base IT as approximation)
    overhead_ms <- base_it_ms * 0.20
    parallel_filling_efficiency <- optimized_it_ms / (base_it_ms + overhead_ms)
  } else {
    parallel_filling_efficiency <- NA
  }

  return(list(
    requested_windows = requested_windows,
    actual_windows = actual_windows,
    is_spec_limited = is_spec_limited,
    base_it_ms = base_it_ms,
    optimized_it_ms = round(optimized_it_ms, 2),
    it_gain_ms = round(it_gain_ms, 2),
    it_gain_pct = round(it_gain_pct, 1),
    slack_time_ms = round(slack_time_sec * 1000, 2),
    parallel_filling_efficiency = if (!is.na(parallel_filling_efficiency))
      round(parallel_filling_efficiency, 3) else NA
  ))
}


# =============================================================================
# S3 Methods
# =============================================================================
# Note: S3 methods (print, summary) are now centralized in R/s3_classes.R
# This ensures consistency and reduces code duplication.
# See: print.OptimizationPlan(), summary.OptimizationPlan()


# =============================================================================
# Quick DPPP Preview (for Shiny UI)
# =============================================================================

#' Quick DPPP Preview for Multiple Cycle Times
#'
#' Calculates DPPP satisfaction across multiple cycle times for quick preview.
#' Used in Shiny app to show user how different cycle times affect DPPP.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param cycle_times Numeric vector of cycle times to evaluate (in seconds)
#' @param target_dppp Numeric, target DPPP value (default: 7.0)
#' @param target_satisfaction Numeric, target satisfaction ratio 0-1 (default: 0.85)
#' @return List with fwhm_stats, dppp_preview, recommended_cycle_time, target_dppp, gradient_length
#' @export
quick_dppp_preview <- function(validated_data,
                               cycle_times = c(1.5, 2.0, 2.5, 3.0, 3.5),
                               target_dppp = 7.0,
                               target_satisfaction = 0.85) {

  # Get FWHM values
  data <- validated_data$data
  fwhm_col <- if ("FWHM" %in% names(data)) "FWHM" else NULL

  # Calculate gradient length
  rt_range <- range(data$RT.Apex, na.rm = TRUE)
  gradient_length <- rt_range[2] - rt_range[1]

  if (is.null(fwhm_col) || all(is.na(data[[fwhm_col]]))) {
    return(list(
      fwhm_stats = list(median = NA, q25 = NA, q75 = NA, min = NA, max = NA),
      dppp_preview = data.frame(
        cycle_time_sec = cycle_times,
        dppp_median = NA,
        satisfaction_pct = NA
      ),
      recommendation = "FWHM data not available",
      recommended_cycle_time = NA,
      target_dppp = target_dppp,
      gradient_length = gradient_length
    ))
  }

  # Convert FWHM to seconds if in minutes
  fwhm_values <- data[[fwhm_col]]
  fwhm_seconds <- ensure_fwhm_seconds(fwhm_values)
  fwhm_seconds <- fwhm_seconds[!is.na(fwhm_seconds)]

  # Calculate FWHM statistics
  fwhm_stats <- list(
    median = median(fwhm_seconds, na.rm = TRUE),
    q25 = quantile(fwhm_seconds, 0.25, na.rm = TRUE, names = FALSE),
    q75 = quantile(fwhm_seconds, 0.75, na.rm = TRUE, names = FALSE),
    min = min(fwhm_seconds, na.rm = TRUE),
    max = max(fwhm_seconds, na.rm = TRUE)
  )

  # Calculate DPPP for each cycle time
  dppp_results <- lapply(cycle_times, function(ct) {
    dppp_values <- calculate_dppp(fwhm_seconds, ct)
    list(
      cycle_time_sec = ct,
      dppp_median = median(dppp_values, na.rm = TRUE),
      satisfaction_pct = dppp_satisfaction_pct(dppp_values, target_dppp)
    )
  })

  dppp_preview <- do.call(rbind, lapply(dppp_results, as.data.frame))

  # Calculate recommended cycle time based on FWHM distribution
  # Formula: cycle_time = (1.7 * fwhm_critical) / target_dppp
  # fwhm_critical = quantile at (1 - target_satisfaction)
  critical_percentile <- 1 - target_satisfaction
  fwhm_critical <- quantile(fwhm_seconds, critical_percentile, na.rm = TRUE, names = FALSE)
  recommended_cycle_time <- round((PEAK_WIDTH_FACTOR * fwhm_critical) / target_dppp, 2)

  # Find recommendation message
  good_idx <- which(dppp_preview$satisfaction_pct >= target_satisfaction * 100)
  if (length(good_idx) > 0) {
    best_tested_ct <- dppp_preview$cycle_time_sec[max(good_idx)]
    recommendation <- sprintf("%.2f sec cycle time recommended (%.0f%% satisfaction at DPPP %.1f)",
                              recommended_cycle_time,
                              dppp_preview$satisfaction_pct[max(good_idx)],
                              target_dppp)
  } else {
    best_idx <- which.max(dppp_preview$satisfaction_pct)
    recommendation <- sprintf("Recommended: %.2f sec (tested best: %.1f sec with %.0f%% satisfaction)",
                              recommended_cycle_time,
                              dppp_preview$cycle_time_sec[best_idx],
                              dppp_preview$satisfaction_pct[best_idx])
  }

  return(list(
    fwhm_stats = fwhm_stats,
    dppp_preview = dppp_preview,
    recommendation = recommendation,
    recommended_cycle_time = recommended_cycle_time,
    target_dppp = target_dppp,
    gradient_length = gradient_length
  ))
}


# =============================================================================
# Module Loading
# =============================================================================

