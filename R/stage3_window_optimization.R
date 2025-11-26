# stage3_window_optimization.R - Stage 3: Window Optimization (Orchestrator)
#
# Purpose: Unified module for RT binning, m/z optimization, and window generation
#
# Version: 2.1 (Modularized architecture)
#
# Architecture:
#   This file is the orchestrator that sources modular functions from R/stage3/
#   and coordinates the overall window optimization pipeline.
#
# Sourced Modules:
#   - R/stage3/stage3_rt_binning.R: RT segmentation
#   - R/stage3/stage3_mz_optimization.R: m/z range optimization (LOCAL & GLOBAL)
#   - R/stage3/stage3_window_generation.R: Window generation (fixed/variable)
#   - R/stage3/stage3_statistics.R: Statistics calculation
#   - R/stage3/stage3_export.R: CSV export and S3 methods
#
# Input: ValidatedData (Stage 1) + OptimizationPlan (Stage 2)
# Output: OptimizedWindows with complete isolation window set

library(dplyr)
library(tibble)

# =============================================================================
# Source Dependencies and Modules
# =============================================================================

# Load common utilities
if (!exists("print_header")) {
  source("R/utils_common.R")
}

# Source Stage 3 modules
stage3_modules <- c(
  "R/stage3/stage3_rt_binning.R",
  "R/stage3/stage3_mz_optimization.R",
  "R/stage3/stage3_window_generation.R",
  "R/stage3/stage3_statistics.R",
  "R/stage3/stage3_export.R"
)

for (module in stage3_modules) {
  if (file.exists(module)) {
    source(module)
  }
}

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
#' @param mz_strategy Character, m/z optimization strategy (default: "quantile")
#'   - "quantile": Use percentiles (P5-P95), fast and robust
#'   - "coverage": Minimum range for target coverage, conservative
#'   - "outlier": Mean +/- 3*SD, removes outliers
#'   - "smoothing": GLOBAL Savitzky-Golay smoothing across RT
#' @param window_mode Character, window generation mode (default: "variable")
#'   - "fixed": Equal-width windows
#'   - "variable": Density-based adaptive windows (recommended)
#' @param target_coverage Numeric, target m/z coverage 0-1 (default: 0.95)
#' @param quantile_lower Numeric, lower quantile for quantile strategy (default: 0.05)
#' @param quantile_upper Numeric, upper quantile for quantile strategy (default: 0.95)
#' @param outlier_threshold Numeric, SD multiplier for outlier strategy (default: 3.0)
#' @param smoothing_window Integer, SG window size for smoothing (default: 7)
#' @param polynomial_order Integer, SG polynomial order (default: 3)
#' @param min_width_da Numeric, minimum window width in Da (default: 2)
#' @param max_width_da Numeric, maximum window width in Da (default: 80)
#' @param overlap_percentage Numeric, overlap % between windows (default: 0)
#'
#' @return OptimizedWindows S3 object
#' @export
#'
#' @examples
#' # Basic usage
#' windows <- optimize_windows(
#'   validated_data,
#'   optimization_plan,
#'   rt_bin_width_min = 5,
#'   mz_strategy = "quantile",
#'   window_mode = "variable"
#' )
#'
#' # Conservative settings
#' windows <- optimize_windows(
#'   validated_data,
#'   optimization_plan,
#'   rt_bin_width_min = 3,
#'   mz_strategy = "coverage",
#'   target_coverage = 0.98,
#'   window_mode = "variable"
#' )
optimize_windows <- function(
  validated_data,
  optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "quantile",
  window_mode = "variable",
  target_coverage = 0.95,
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  outlier_threshold = 3.0,
  smoothing_window = 7,
  polynomial_order = 3,
  min_width_da = 2,
  max_width_da = 80,
  overlap_percentage = 0
) {

  # Start timing
  timer <- create_timer()

  print_header("Stage 3: Window Optimization", width = 55)

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

  valid_strategies <- c("quantile", "coverage", "outlier", "smoothing")
  if (!mz_strategy %in% valid_strategies) {
    stop(sprintf("mz_strategy must be one of: %s",
                 paste(valid_strategies, collapse = ", ")))
  }

  valid_modes <- c("fixed", "variable")
  if (!window_mode %in% valid_modes) {
    stop(sprintf("window_mode must be one of: %s",
                 paste(valid_modes, collapse = ", ")))
  }

  print_success("Input validation passed")

  # Extract key parameters
  n_windows_per_bin <- optimization_plan$window_count_per_bin
  precursor_data <- get_precursor_data(validated_data)
  n_total_precursors <- nrow(precursor_data)

  print_info(sprintf("Total precursors: %s",
                     format(n_total_precursors, big.mark = ",")))
  print_info(sprintf("Windows per RT bin: %d", n_windows_per_bin))
  print_info(sprintf("RT bin width: %.1f min", rt_bin_width_min))
  print_info(sprintf("m/z strategy: %s", mz_strategy))
  print_info(sprintf("Window mode: %s", window_mode))

  # ===================================================================
  # Step 2: RT Binning
  # ===================================================================
  print_step(2, "RT Binning")

  rt_result <- perform_rt_binning_internal(
    precursor_data = precursor_data,
    rt_bin_width_min = rt_bin_width_min
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

  # ===================================================================
  # Step 3: m/z Range Optimization
  # ===================================================================
  print_step(3, "m/z Range Optimization")

  mz_ranges <- optimize_mz_ranges_internal(
    precursor_data = precursor_data,
    rt_stats = rt_stats,
    strategy = mz_strategy,
    target_coverage = target_coverage,
    quantile_lower = quantile_lower,
    quantile_upper = quantile_upper,
    outlier_threshold = outlier_threshold,
    smoothing_window = smoothing_window,
    polynomial_order = polynomial_order
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

  windows <- generate_windows_internal(
    precursor_data = precursor_data,
    rt_stats = rt_stats,
    mz_ranges = mz_ranges,
    n_windows_per_bin = n_windows_per_bin,
    window_mode = window_mode,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    overlap_percentage = overlap_percentage
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
        rt_stats = rt_stats
      ),

      # m/z optimization info
      mz_optimization = list(
        strategy = mz_strategy,
        mz_ranges = mz_ranges,
        mean_coverage = mean(mz_ranges$coverage_ratio, na.rm = TRUE),
        mean_width = mean(mz_ranges$mz_width)
      ),

      # Parameters
      parameters = list(
        window_mode = window_mode,
        n_windows_per_bin = n_windows_per_bin,
        rt_bin_width_min = rt_bin_width_min,
        mz_strategy = mz_strategy,
        target_coverage = target_coverage,
        min_width_da = min_width_da,
        max_width_da = max_width_da,
        overlap_percentage = overlap_percentage
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

# =============================================================================
# Module Loading
# =============================================================================

cat("OK Stage 3 (Window Optimization) loaded successfully\n")
cat("   Version: 2.1 (Modularized architecture)\n")
cat("   Main function: optimize_windows(validated_data, optimization_plan, ...)\n")
cat("   Output: OptimizedWindows object\n")
cat("   Sourced modules:\n")
cat("     - R/stage3/stage3_rt_binning.R\n")
cat("     - R/stage3/stage3_mz_optimization.R\n")
cat("     - R/stage3/stage3_window_generation.R\n")
cat("     - R/stage3/stage3_statistics.R\n")
cat("     - R/stage3/stage3_export.R\n")
cat("   Export:\n")
cat("     - export_windows_to_csv(optimized_windows, output_file)  # Single strategy\n")
cat("     - export_method_files(windows_list, output_dir, ...)     # All strategies\n")
