# stage2_optimization_planning.R - Stage 2: Optimization Planning (Refactored)
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

library(dplyr)
library(tibble)

# Load dependencies
if (!exists("print_header")) {
  source("R/utils_common.R")
}

if (!exists("get_instrument_config")) {
  source("R/instrument_utils.R")
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
#'
#' @return OptimizationPlan S3 object
#' @export
#'
#' @examples
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
#' @export
plan_optimization <- function(
  validated_data,
  current_cycle_time = NULL,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.85,
  dppp_tolerance = 0.0,
  load_factor = 0.8,
  ms1_scans_per_cycle = NULL,
  warning_threshold_windows = 5
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
  if (is.null(current_cycle_time)) {
    # Estimate from gradient length: cycle_time ≈ gradient_length / 15
    # This assumes ~15 data points per chromatographic peak as initial estimate
    gradient_length <- max(validated_data$data$RT.Start) - min(validated_data$data$RT.Start)
    current_cycle_time <- min(gradient_length / 15, 3.5)  # Cap at 3.5 sec
    cat(sprintf("  ℹ️  Auto-estimated cycle time: %.3f sec (from %.1f min gradient)\n",
                current_cycle_time, gradient_length))
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

  print_info(sprintf("Instrument: %s", instrument_config$name))
  print_info(sprintf("Max scan rate: %.0f Hz (%s acquisition)",
                     instrument_config$max_scan_rate,
                     instrument_config$cycle_calculation))
  print_info(sprintf("MS1 scans per cycle: %d", ms1_scans_per_cycle))
  print_info(sprintf("Max windows: %d (hardware limit)", max_windows))
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
  print_info(sprintf("Current DPPP: %.2f ± %.2f (median: %.2f)",
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
  print_info(sprintf("Required cycle time: ≤ %.2f sec", required_cycle_time))

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
  # Step 5: Determine Window Count
  # ===================================================================
  print_step(5, "Determine Window Count")

  # Calculate effective scan rate
  effective_scan_rate <- instrument_config$max_scan_rate * load_factor

  # Calculate window count from required cycle time
  window_count <- calculate_window_count_internal(
    target_cycle_time_sec = required_cycle_time,
    scan_rate_hz = effective_scan_rate,
    ms1_scans_per_cycle = ms1_scans_per_cycle,
    warning_threshold_windows = warning_threshold_windows,
    max_windows = max_windows
  )

  print_info(sprintf("Window count: %d per RT bin", window_count))
  print_info(sprintf("Calculation: floor(%.3f sec × %.1f Hz) - %d MS1 = %d",
                     required_cycle_time,
                     effective_scan_rate,
                     ms1_scans_per_cycle,
                     window_count))

  # ===================================================================
  # Step 6: Feasibility Checks
  # ===================================================================
  print_step(6, "Feasibility Checks")

  # Calculate actual cycle time with determined window count
  ms1_time <- instrument_config$ms1_time / 1000  # ms to sec
  ms2_time <- instrument_config$ms2_time / 1000  # ms to sec

  actual_cycle_time <- calculate_cycle_time_internal(
    n_windows = window_count,
    cycle_mode = instrument_config$cycle_calculation,
    ms1_time = ms1_time,
    ms2_time = ms2_time
  )

  print_info(sprintf("Actual cycle time: %.3f sec", actual_cycle_time))

  # Feasibility checks
  feasibility <- list()

  # Check 1: Cycle time constraint
  feasibility$cycle_time_ok <- actual_cycle_time <= (required_cycle_time + 0.01)
  if (feasibility$cycle_time_ok) {
    print_success(sprintf("Cycle time check: PASS (%.3f ≤ %.3f sec)",
                          actual_cycle_time, required_cycle_time))
  } else {
    print_warning(sprintf("Cycle time check: FAIL (%.3f > %.3f sec)",
                          actual_cycle_time, required_cycle_time))
  }

  # Check 2: Scan rate
  total_scans_needed <- window_count + ms1_scans_per_cycle
  max_possible_scans <- floor(required_cycle_time * instrument_config$max_scan_rate)
  feasibility$scan_rate_ok <- total_scans_needed <= max_possible_scans

  if (feasibility$scan_rate_ok) {
    print_success(sprintf("Scan rate check: PASS (%d scans ≤ %d max)",
                          total_scans_needed, max_possible_scans))
  } else {
    print_warning(sprintf("Scan rate check: FAIL (%d scans > %d max)",
                          total_scans_needed, max_possible_scans))
  }

  # Check 3: Window count - max only (warning threshold handled in calculation)
  feasibility$window_range_ok <- window_count <= max_windows
  if (feasibility$window_range_ok) {
    print_success(sprintf("Window range check: PASS (%d ≤ %d max)",
                          window_count, max_windows))
  } else {
    print_warning(sprintf("Window range check: FAIL (%d > %d max)",
                          window_count, max_windows))
  }

  # Overall feasibility
  is_feasible <- all(unlist(feasibility))

  # ===================================================================
  # Step 7: Package Results
  # ===================================================================
  print_step(7, "Package Results")

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
        effective_scan_rate_hz = effective_scan_rate,
        load_factor = load_factor,
        ms1_scans_per_cycle = ms1_scans_per_cycle,
        cycle_mode = instrument_config$cycle_calculation,
        ms1_time_sec = ms1_time,
        ms2_time_sec = ms2_time
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
  cat(rep("─", 55), "\n", sep = "")
  cat("Stage 2 Complete\n")
  cat(rep("─", 55), "\n", sep = "")

  if (is_feasible) {
    cat(sprintf("✅ Optimization plan is FEASIBLE\n"))
  } else {
    cat(sprintf("⚠️  Optimization plan has WARNINGS\n"))
  }

  cat(sprintf("   Window count: %d per RT bin\n", window_count))
  cat(sprintf("   Required cycle time: ≤ %.3f sec\n", required_cycle_time))
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
#' @keywords internal
calculate_required_cycle_time_internal <- function(fwhm_seconds, target_dppp,
                                                   target_satisfaction) {

  # Find critical FWHM (shortest among top X% precursors)
  critical_percentile <- 1 - target_satisfaction
  fwhm_critical <- quantile(fwhm_seconds, critical_percentile, names = FALSE)

  # Calculate maximum cycle time for this critical FWHM
  required_max_cycle_time <- (PEAK_WIDTH_FACTOR * fwhm_critical) / target_dppp

  return(required_max_cycle_time)
}

#' Calculate Window Count from Cycle Time (Internal)
#' @keywords internal
calculate_window_count_internal <- function(target_cycle_time_sec, scan_rate_hz,
                                            ms1_scans_per_cycle, warning_threshold_windows,
                                            max_windows) {

  # Total possible scans
  total_scans <- floor(target_cycle_time_sec * scan_rate_hz)

  # Reserve MS1 scans
  n_windows <- total_scans - ms1_scans_per_cycle

  # Warning if too low (no enforcement)
  if (n_windows <= warning_threshold_windows) {
    warning(sprintf(
      "Window count is low (%d ≤ %d). Consider adjusting target_cycle_time or load_factor.",
      n_windows, warning_threshold_windows
    ))
  }

  # Apply max constraint only
  n_windows <- min(n_windows, max_windows)

  return(as.integer(n_windows))
}

#' Calculate Cycle Time (Internal)
#' @keywords internal
calculate_cycle_time_internal <- function(n_windows, cycle_mode, ms1_time,
                                          ms2_time) {

  total_ms2_time <- n_windows * ms2_time

  if (cycle_mode == "parallel") {
    # MS2 during MS1
    cycle_time <- max(ms1_time, total_ms2_time)
  } else {
    # MS1 then MS2
    cycle_time <- ms1_time + total_ms2_time
  }

  return(cycle_time)
}


# =============================================================================
# S3 Methods
# =============================================================================
# Note: S3 methods (print, summary) are now centralized in R/s3_classes.R
# This ensures consistency and reduces code duplication.
# See: print.OptimizationPlan(), summary.OptimizationPlan()


# =============================================================================
# Module Loading
# =============================================================================

cat("✅ Stage 2 (Optimization Planning) loaded successfully\n")
cat("   Main function: plan_optimization(validated_data, current_cycle_time, ...)\n")
cat("   Output: OptimizationPlan object\n")
