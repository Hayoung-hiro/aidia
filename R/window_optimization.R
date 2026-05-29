# window_optimization.R - Stage 3: Window Optimization (Orchestrator)
#
# Purpose: Unified module for RT binning, m/z optimization, and window generation
#
# Version: 2.1 (Modularized architecture)
#
# Architecture:
#   This file is the orchestrator that sources modular functions from R/
#   and coordinates the overall window optimization pipeline.
#
# Sourced Modules:
#   - R/rt_binning.R: RT segmentation
#   - R/mz_optimization.R: m/z range optimization (6 strategies)
#   - R/window_generation.R: Window generation (fixed/variable)
#   - R/window_statistics.R: Statistics calculation
#   - R/export_methods.R: CSV export and S3 methods
#
# Input: ValidatedData (Stage 1) + OptimizationPlan (Stage 2)
# Output: OptimizedWindows with complete isolation window set


# =============================================================================
# Main Window Optimization Function
# =============================================================================

#' Optimize DIA Isolation Windows (Stage 3 Main Function)
#'
#' Performs complete window optimization including RT binning, m/z range
#' optimization, and window generation in a single integrated workflow.
#'
#' This function operates per-RT-bin: each RT bin independently generates
#' the specified number of windows, resulting in total_windows = n_bins x n_windows.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param rt_bin_width_min Numeric, RT bin width in minutes (default: 5)
#'   - Recommended: 3-7 minutes for typical proteomics gradients
#'   - Shorter bins: Better RT specificity, more bins to manage
#'   - Longer bins: Simpler, fewer total windows
#' @param strategy_config A strategy_config object created by one of:
#'   [greedy_config()], [quantile_config()], [coverage_config()],
#'   [outlier_config()], [kde_config()]. When provided, overrides
#'   mz_strategy and all strategy-specific parameters below.
#' @param mz_strategy Character, m/z optimization strategy (default: "quantile").
#'   Ignored when strategy_config is provided.
#'   - "greedy": MacCoss Lab algorithm, maximize precursor count (recommended)
#'   - "kde": Kernel Density Estimation, find density peak and expand
#'   - "quantile": Use percentiles (P5-P95), fast and robust
#'   - "coverage": Minimum range for target coverage, conservative
#'   - "outlier": Mean +/- 3*SD, removes outliers
#' @param window_mode Character, window generation mode (default: "density")
#'   - "fixed": Equal-width windows
#'   - "density": Density-based adaptive windows (recommended)
#' @param target_coverage Numeric, target m/z coverage 0-1 (default: 0.95)
#' @param quantile_lower Numeric, lower quantile for quantile strategy (default: 0.05)
#' @param quantile_upper Numeric, upper quantile for quantile strategy (default: 0.95)
#' @param outlier_threshold Numeric, SD multiplier for outlier strategy (default: 3.0)
#' @param smoothing_window Integer, SG window size for smoothing (default: 7)
#' @param polynomial_order Integer, SG polynomial order (default: 3)
#' @param min_width_da Numeric, minimum window width in Da (default: 2)
#' @param max_width_da Numeric, maximum window width in Da (default: 80)
#' @param overlap_percentage Numeric, overlap % between windows (default: 0)
#' @param mz_step Numeric, step size for greedy sliding window in Da (default: 0.5)
#' @param n_windows_override Integer or NULL, override window count (for Greedy strategy)
#' @param greedy_apply_smoothing Logical, apply SG smoothing to greedy boundaries (default: TRUE)
#' @param kde_density_threshold Numeric, KDE density threshold 0-1 (default: 0.1)
#' @param kde_min_coverage Numeric, KDE minimum coverage 0-1 (default: 0.80)
#' @param quantile_apply_smoothing Logical, apply SG smoothing to quantile boundaries (default: FALSE)
#' @param outlier_apply_smoothing Logical, apply SG smoothing to outlier boundaries (default: FALSE)
#' @param fz_offset Numeric, forbidden zone offset for staggered mode (default: 0.25, use 0.18 for phospho)
#' @param coverage_mode Character, coverage strategy mode: "narrowest" or "centered"
#' @param mz_range_min Numeric, fallback minimum m/z for empty RT bins (default: 400)
#' @param mz_range_max Numeric, fallback maximum m/z for empty RT bins (default: 1200)
#' @param rt_binning_mode Character, RT binning mode: "fixed" or "adaptive" (default: "fixed")
#' @param cpd_min_bin_width Numeric, minimum RT bin width in minutes for adaptive binning (default: 1.0)
#' @param cpd_max_bin_width Numeric, maximum RT bin width in minutes for adaptive binning (default: 15.0)
#' @param cpd_min_precursors_per_bin Integer, minimum precursors per bin for adaptive binning (default: 50)
#' @param cpd_significance_level Numeric, significance level for changepoint detection (default: 0.05)
#' @param edge_void_buffer_min Numeric, buffer in minutes for edge bins with no precursors (default: 0.5)
#' @param edge_wash_min_precursors Integer, minimum precursors for edge bin retention (default: 30)
#' @param width_grid_step Numeric, grid step for width digitization in Da (default: 0.5)
#'   - Snaps window widths to nearest multiple for batch reproducibility
#'   - Set to NULL or 0 to disable digitization
#'   - Only applies to density (variable) window mode
#' @param smoothing_method Character, boundary smoothing method (default: "whittaker").
#'   "whittaker" for Whittaker-Henderson penalized least squares,
#'   "sg" for Savitzky-Golay polynomial filter.
#' @param whittaker_lambda Numeric, lambda penalty for Whittaker-Henderson smoother
#'   (default: 10). Higher values produce smoother boundaries.
#'
#' @return OptimizedWindows S3 object
#' @export
#'
#' @examples
#' \dontrun{
#' # New way: strategy config objects (recommended)
#' windows <- optimize_windows(
#'   validated_data, optimization_plan,
#'   strategy_config = greedy_config(apply_smoothing = TRUE)
#' )
#'
#' # Legacy way: flat parameters (still works)
#' windows <- optimize_windows(
#'   validated_data, optimization_plan,
#'   mz_strategy = "quantile", window_mode = "density"
#' )
#' }
optimize_windows <- function(
  validated_data,
  optimization_plan,
  strategy_config = NULL,
  rt_bin_width_min = 5,
  mz_strategy = "quantile",
  window_mode = "density",
  mz_range_min = 400,
  mz_range_max = 1200,
  target_coverage = 0.95,
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  outlier_threshold = 3.0,
  smoothing_window = 7,
  polynomial_order = 3,
  min_width_da = 2,
  max_width_da = 80,
  overlap_percentage = 0,
  mz_step = 0.5,
  n_windows_override = NULL,
  greedy_apply_smoothing = TRUE,
  kde_density_threshold = 0.1,
  kde_min_coverage = 0.80,
  quantile_apply_smoothing = FALSE,
  outlier_apply_smoothing = FALSE,
  fz_offset = 0.25,
  coverage_mode = "narrowest",
  # RT binning parameters
  rt_binning_mode = "fixed",
  cpd_min_bin_width = 1.0,
  cpd_max_bin_width = 15.0,
  cpd_min_precursors_per_bin = 50,
  cpd_significance_level = 0.05,
  edge_void_buffer_min = 0.5,
  edge_wash_min_precursors = 30,
  width_grid_step = 0.5,
  smoothing_method = "whittaker",
  whittaker_lambda = 10
) {

  # Start timing
  timer <- create_timer()

  print_header("Stage 3: Window Optimization", width = 55)

  # ===================================================================
  # Step 0: Resolve strategy_config (typed) vs flat params (deprecated)
  # ===================================================================
  if (is.null(strategy_config)) {
    # Legacy path: caller passed flat params. Build a typed config from
    # them so the rest of the pipeline runs through S3 dispatch uniformly.
    .Deprecated(
      msg = paste0(
        "Calling optimize_windows() with flat strategy parameters is ",
        "deprecated. Use strategy_config = ", mz_strategy, "_config(...) ",
        "instead. Flat parameters will be removed in v0.6.0."
      )
    )
    strategy_config <- build_strategy_config(
      mz_strategy = mz_strategy,
      quantile_lower = quantile_lower,
      quantile_upper = quantile_upper,
      quantile_apply_smoothing = quantile_apply_smoothing,
      target_coverage = target_coverage,
      coverage_mode = coverage_mode,
      outlier_threshold = outlier_threshold,
      outlier_apply_smoothing = outlier_apply_smoothing,
      mz_step = mz_step,
      n_windows_override = n_windows_override,
      greedy_apply_smoothing = greedy_apply_smoothing,
      kde_density_threshold = kde_density_threshold,
      kde_min_coverage = kde_min_coverage,
      smoothing_window = smoothing_window,
      polynomial_order = polynomial_order,
      smoothing_method = smoothing_method,
      whittaker_lambda = whittaker_lambda
    )
  } else {
    if (!inherits(strategy_config, "strategy_config")) {
      stop("strategy_config must be created by greedy_config(), quantile_config(), ",
           "coverage_config(), outlier_config(), or kde_config().")
    }
  }

  # Derived values needed downstream (window_mode dispatch, output naming).
  mz_strategy <- strategy_config$strategy
  # n_windows override: only present on greedy_config
  if ("n_windows_override" %in% names(strategy_config)) {
    n_windows_override <- strategy_config$n_windows_override
  }

  # ===================================================================
  # Step 1: Input Validation
  # ===================================================================
  print_step(1, "Input Validation")

  validate_input_type(validated_data, "ValidatedData", "validated_data")
  validate_input_type(optimization_plan, "OptimizationPlan", "optimization_plan")

  validate_numeric_range(rt_bin_width_min, min = 0.1, param_name = "rt_bin_width_min")
  validate_numeric_range(target_coverage, min = 0, max = 1, param_name = "target_coverage")
  validate_numeric_range(quantile_lower, min = 0, max = 1, param_name = "quantile_lower")
  validate_numeric_range(quantile_upper, min = 0, max = 1, param_name = "quantile_upper")
  validate_numeric_range(outlier_threshold, min = 0, param_name = "outlier_threshold")
  validate_numeric_range(smoothing_window, min = 3, param_name = "smoothing_window")
  validate_numeric_range(polynomial_order, min = 1, max = 5, param_name = "polynomial_order")
  validate_numeric_range(min_width_da, min = 0, param_name = "min_width_da")
  validate_numeric_range(max_width_da, min = min_width_da, param_name = "max_width_da")
  validate_numeric_range(overlap_percentage, min = 0, max = 50, param_name = "overlap_percentage")
  validate_numeric_range(mz_range_min, min = 0, param_name = "mz_range_min")
  validate_numeric_range(mz_range_max, min = mz_range_min, param_name = "mz_range_max")
  validate_numeric_range(fz_offset, min = 0, max = 1, param_name = "fz_offset")

  valid_strategies <- c("quantile", "coverage", "outlier", "greedy", "kde")
  if (!mz_strategy %in% valid_strategies) {
    stop(sprintf("mz_strategy must be one of: %s",
                 paste(valid_strategies, collapse = ", ")))
  }

  valid_modes <- c("fixed", "density", "staggered")
  if (!window_mode %in% valid_modes) {
    stop(sprintf("window_mode must be one of: %s",
                 paste(valid_modes, collapse = ", ")))
  }

  valid_rt_binning_modes <- c("fixed", "adaptive")
  if (!rt_binning_mode %in% valid_rt_binning_modes) {
    stop(sprintf("rt_binning_mode must be one of: %s",
                 paste(valid_rt_binning_modes, collapse = ", ")))
  }

  valid_coverage_modes <- c("narrowest", "centered")
  if (!coverage_mode %in% valid_coverage_modes) {
    stop(sprintf("coverage_mode must be one of: %s",
                 paste(valid_coverage_modes, collapse = ", ")))
  }

  print_success("Input validation passed")

  # Extract key parameters
  # Use override if provided (for Greedy strategy with manual window count)
  if (!is.null(n_windows_override) && n_windows_override > 0) {
    n_windows_per_bin <- as.integer(n_windows_override)
    print_info(sprintf("Window count override: %d (user-specified)", n_windows_per_bin))
  } else {
    n_windows_per_bin <- optimization_plan$window_count_per_bin
  }
  precursor_data <- get_precursor_data(validated_data)
  n_total_precursors <- nrow(precursor_data)

  print_info(sprintf("Total precursors: %s",
                     format(n_total_precursors, big.mark = ",")))
  print_info(sprintf("Windows per RT bin: %d", n_windows_per_bin))
  print_info(sprintf("RT bin width: %.1f min", rt_bin_width_min))
  print_info(sprintf("m/z strategy: %s", mz_strategy))
  print_info(sprintf("Window mode: %s", window_mode))
  print_info(sprintf("RT binning mode: %s", rt_binning_mode))
  # ===================================================================
  # Step 2: RT Binning
  # ===================================================================
  print_step(2, "RT Binning")

    rt_result <- perform_rt_binning_internal(
      precursor_data = precursor_data,
      rt_bin_width_min = rt_bin_width_min,
      rt_binning_mode = rt_binning_mode,
      cpd_min_bin_width = cpd_min_bin_width,
      cpd_max_bin_width = cpd_max_bin_width,
      cpd_min_precursors_per_bin = cpd_min_precursors_per_bin,
      cpd_significance_level = cpd_significance_level,
      edge_void_buffer_min = edge_void_buffer_min,
      edge_wash_min_precursors = edge_wash_min_precursors
    )

    precursor_data <- rt_result$data
    rt_stats <- rt_result$stats
    n_bins <- rt_result$n_bins

    print_info(sprintf("Created %d RT bins", n_bins))
    print_info(sprintf("Precursors per bin: %.0f +/- %.0f (range: %d - %d)",
                       mean(rt_stats$n_precursors),
                       sd(rt_stats$n_precursors),
                       min(rt_stats$n_precursors),
                       max(rt_stats$n_precursors)))

    # Step 3: m/z Range Optimization
    print_step(3, "m/z Range Optimization")

    mz_ranges <- optimize_mz_ranges(
      strategy_config,
      precursor_data = precursor_data,
      rt_stats = rt_stats,
      n_windows_per_bin = n_windows_per_bin,
      min_width_da = min_width_da,
      mz_range_min = mz_range_min,
      mz_range_max = mz_range_max
    )

    # Post-processor: boundary smoothing (S3-dispatched; no-op for kde/coverage)
    mz_ranges <- apply_smoothing(
      strategy_config,
      mz_ranges = mz_ranges,
      precursor_data = precursor_data,
      n_windows_per_bin = n_windows_per_bin,
      min_width_da = min_width_da
    )

    print_info(sprintf("Optimized m/z ranges for %d RT bins", nrow(mz_ranges)))
    print_info(sprintf("Mean m/z width: %.1f Da (range: %.1f - %.1f)",
                       mean(mz_ranges$mz_width),
                       min(mz_ranges$mz_width),
                       max(mz_ranges$mz_width)))
    print_info(sprintf("Mean coverage: %.1f%%",
                       mean(mz_ranges$coverage_ratio, na.rm = TRUE) * 100))

  # ===================================================================
  # Step 4: Window Generation
  # ===================================================================
  print_step(4, "Window Generation")

  # Decouple generation min_width from greedy's range calculation.
  # Greedy sets mz_range = n_windows × min_width_da, so using the same

  # value as the generation floor forces all windows to identical width
  # (no room for density variation). Use half min_width (floor 1 Da)
  # for density mode to allow adaptive widths within the greedy range.
  gen_min_width_da <- if (mz_strategy == "greedy" && window_mode == "density") {
    effective <- max(1.0, min_width_da * 0.5)
    print_info(sprintf("Greedy+Density: generation min_width relaxed %.1f -> %.1f Da",
                       min_width_da, effective))
    effective
  } else {
    min_width_da
  }

  windows <- generate_windows_internal(
    precursor_data = precursor_data,
    rt_stats = rt_stats,
    mz_ranges = mz_ranges,
    n_windows_per_bin = n_windows_per_bin,
    window_mode = window_mode,
    min_width_da = gen_min_width_da,
    max_width_da = max_width_da,
    overlap_percentage = overlap_percentage,
    fz_offset = fz_offset,
    width_grid_step = width_grid_step
  )

  total_windows <- nrow(windows)
  expected_windows <- n_bins * n_windows_per_bin

  print_info(sprintf("Generated %d windows", total_windows))
  print_info(sprintf("Expected: %d bins x %d = %d windows",
                     n_bins, n_windows_per_bin, expected_windows))
  print_info(sprintf("Deviation: %.1f%%",
                     100 * abs(total_windows - expected_windows) / expected_windows))

  # ===================================================================
  # Step 5: Calculate Statistics
  # ===================================================================
  print_step(5, "Calculate Statistics")

  statistics <- calculate_window_statistics_internal(windows, precursor_data)

  print_info(sprintf("Window width: %.2f +/- %.2f Da",
                     statistics$window_width_mean,
                     statistics$window_width_sd))
  print_info(sprintf("Precursors/window: %.1f +/- %.1f (CV: %.2f)",
                     statistics$mean_precursors_per_window,
                     statistics$sd_precursors_per_window,
                     statistics$cv_precursors))
  print_info(sprintf("Coverage: %.1f%% (%s / %s precursors)",
                     statistics$coverage_percentage,
                     format(statistics$covered_precursors, big.mark = ","),
                     format(statistics$total_precursors, big.mark = ",")))

  # ===================================================================
  # Step 5b: DPPP Re-verification (actual vs planned)
  # ===================================================================
  # After window generation, the actual window count per bin may differ from
  # the planned count due to width constraints, staggered mode, or fallbacks.
  # Re-calculate the effective cycle time and DPPP with the real window count.
  # For staggered mode, total_windows includes both cycles.

  # Cycle time is determined by windows per cycle (half of total for staggered).
  if (window_mode == "staggered") {
    actual_windows_per_bin <- total_windows / (n_bins * 2)
  } else {
    actual_windows_per_bin <- total_windows / n_bins
  }
  instrument <- optimization_plan$instrument

  # Use the actual MS2 scan time (t_scan = max(transient, IT) + overhead) computed
  # in Stage 2, NOT the bare injection time, and route through the canonical
  # simple_cycle_time() helper rather than re-inlining the parallel/sequential formula.
  t_scan_sec <- optimization_plan$scan_time$t_scan_ms / 1000
  actual_cycle_time <- simple_cycle_time(
    ms1_time = instrument$ms1_time_sec,
    total_ms2_time = actual_windows_per_bin * t_scan_sec,
    cycle_mode = instrument$cycle_mode
  )

  planned_cycle_time <- optimization_plan$required_cycle_time_sec
  fwhm_values <- get_fwhm_values(validated_data)
  actual_dppp_median <- calculate_dppp(median(fwhm_values), actual_cycle_time)

  dppp_deviation_pct <- 100 * (actual_cycle_time - planned_cycle_time) / planned_cycle_time

  if (abs(dppp_deviation_pct) > 5) {
    print_warning(sprintf("DPPP re-check: actual cycle time %.3fs (%.1f%% from plan %.3fs)",
                          actual_cycle_time, dppp_deviation_pct, planned_cycle_time))
    print_warning(sprintf("  Actual median DPPP: %.2f (planned windows: %d, actual avg: %.1f)",
                          actual_dppp_median, n_windows_per_bin, actual_windows_per_bin))
  } else {
    print_success(sprintf("DPPP re-check: PASS (cycle time %.3fs, median DPPP %.2f)",
                          actual_cycle_time, actual_dppp_median))
  }

  # ===================================================================
  # Step 6: Package Results
  # ===================================================================
  print_step(6, "Package Results")

  result <- create_s3_object(
    list(
      # Primary output
      windows = windows,

      # Statistics
      statistics = statistics,

      # RT binning info
      rt_binning = list(
        n_bins = n_bins,
        rt_bin_width_min = rt_bin_width_min,
        rt_binning_mode = rt_binning_mode,
        rt_stats = rt_stats,
        adaptive_info = rt_result$adaptive_info
      ),

      # m/z optimization info
      mz_optimization = list(
        strategy = mz_strategy,
        mz_ranges = mz_ranges,
        mean_coverage = mean(mz_ranges$coverage_ratio, na.rm = TRUE),
        mean_width = mean(mz_ranges$mz_width)
      ),

      # DPPP verification (actual vs planned)
      dppp_verification = list(
        planned_cycle_time_sec = planned_cycle_time,
        actual_cycle_time_sec = actual_cycle_time,
        actual_dppp_median = actual_dppp_median,
        actual_windows_per_bin = actual_windows_per_bin,
        deviation_pct = dppp_deviation_pct
      ),

      # Parameters
      parameters = list(
        window_mode = window_mode,
        n_windows_per_bin = n_windows_per_bin,
        rt_bin_width_min = rt_bin_width_min,
        rt_binning_mode = rt_binning_mode,
        mz_strategy = mz_strategy,
        target_coverage = target_coverage,
        min_width_da = min_width_da,
        max_width_da = max_width_da,
        overlap_percentage = overlap_percentage,
        width_grid_step = width_grid_step,
        fz_offset = fz_offset
      ),

      # Metadata
      metadata = list(
        optimization_timestamp = Sys.time(),
        processing_time_sec = timer$elapsed(),
        instrument_preset = optimization_plan$instrument$preset
      )
    ),
    class_name = "OptimizedWindows"
  )

  # ===================================================================
  # Summary
  # ===================================================================
  cat("\n")
  cat(rep("-", 55), "\n", sep = "")
  cat("Stage 3 Complete\n")
  cat(rep("-", 55), "\n", sep = "")
  cat(sprintf("OK Window optimization successful\n"))
  cat(sprintf("   Total windows: %d\n", total_windows))
  cat(sprintf("   RT bins: %d (%.1f min each)\n", n_bins, rt_bin_width_min))
  cat(sprintf("   Windows per bin: %d\n", n_windows_per_bin))
  cat(sprintf("   Mean window width: %.2f Da\n",
              statistics$window_width_mean))
  cat(sprintf("   Coverage: %.1f%%\n", statistics$coverage_percentage))
  cat(sprintf("   Processing time: %.2f sec\n", timer$elapsed()))
  cat("\n")

  return(result)
}

