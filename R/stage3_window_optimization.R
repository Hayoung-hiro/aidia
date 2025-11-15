# stage3_window_optimization.R - Stage 3: Window Optimization (Refactored)
#
# Purpose: Unified module for RT binning, m/z optimization, and window generation
#
# This module integrates:
#   - Former module3b_rt_binning.R: RT segmentation
#   - Former module3c_mz_range_optimization.R: m/z range optimization
#   - Former module3d_window_generation.R: Window generation
#
# Input: ValidatedData (Stage 1) + OptimizationPlan (Stage 2)
# Output: OptimizedWindows with complete isolation window set
#
# Version: 2.0 (Refactored)
# Last Updated: 2025-10-25

library(dplyr)
library(tibble)

# Load dependencies
if (!exists("print_header")) {
  source("R/utils_common.R")
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
#' the specified number of windows, resulting in total_windows = n_bins × n_windows.
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
#' @param window_mode Character, window generation mode (default: "variable")
#'   - "fixed": Equal-width windows
#'   - "variable": Density-based adaptive windows (recommended)
#' @param target_coverage Numeric, target m/z coverage 0-1 (default: 0.95)
#' @param quantile_lower Numeric, lower quantile for quantile strategy (default: 0.05)
#' @param quantile_upper Numeric, upper quantile for quantile strategy (default: 0.95)
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
#'   rt_bin_width_min = 3,  # Shorter bins
#'   mz_strategy = "coverage",  # Conservative m/z
#'   target_coverage = 0.98,  # High coverage
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
  outlier_threshold = 3.0,      # NEW: For outlier strategy
  smoothing_window = 7,          # NEW: For smoothing strategy
  polynomial_order = 3,          # NEW: For smoothing strategy
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
  print_info(sprintf("Precursors per bin: %.0f ± %.0f (range: %d - %d)",
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
                     mean(mz_ranges$coverage_ratio) * 100))

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
  print_info(sprintf("Expected: %d bins × %d = %d windows",
                     n_bins, n_windows_per_bin, expected_windows))
  print_info(sprintf("Deviation: %.1f%%",
                     100 * abs(total_windows - expected_windows) / expected_windows))

  # ===================================================================
  # Step 5: Calculate Statistics
  # ===================================================================
  print_step(5, "Calculate Statistics")

  statistics <- calculate_window_statistics_internal(windows, precursor_data)

  print_info(sprintf("Window width: %.2f ± %.2f Da",
                     statistics$window_width_mean,
                     statistics$window_width_sd))
  print_info(sprintf("Precursors/window: %.1f ± %.1f (CV: %.2f)",
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
        mean_coverage = mean(mz_ranges$coverage_ratio),
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
  cat(rep("─", 55), "\n", sep = "")
  cat("Stage 3 Complete\n")
  cat(rep("─", 55), "\n", sep = "")
  cat(sprintf("✅ Window optimization successful\n"))
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
# Internal Helper Functions
# =============================================================================

#' Perform RT Binning (Internal)
#' @keywords internal
perform_rt_binning_internal <- function(precursor_data, rt_bin_width_min) {

  # Get RT range
  rt_range <- range(precursor_data$RT.Start, na.rm = TRUE)

  # Create RT breaks
  rt_breaks <- seq(from = rt_range[1],
                   to = rt_range[2],
                   by = rt_bin_width_min)

  # Extend to cover full range
  if (tail(rt_breaks, 1) < rt_range[2]) {
    rt_breaks <- c(rt_breaks, rt_range[2])
  }

  # Assign RT groups
  precursor_data$rt_group <- cut(
    precursor_data$RT.Start,
    breaks = rt_breaks,
    labels = FALSE,
    include.lowest = TRUE
  )

  # Calculate RT statistics per group
  rt_stats <- precursor_data %>%
    group_by(rt_group) %>%
    summarise(
      rt_start = min(RT.Start, na.rm = TRUE),
      rt_end = max(RT.Start, na.rm = TRUE),
      n_precursors = n(),
      .groups = 'drop'
    ) %>%
    mutate(rt_segment_id = rt_group)

  n_bins <- nrow(rt_stats)

  list(
    data = precursor_data,
    stats = rt_stats,
    n_bins = n_bins,
    rt_breaks = rt_breaks
  )
}

#' Optimize m/z Ranges (Internal)
#' @keywords internal
optimize_mz_ranges_internal <- function(precursor_data, rt_stats, strategy,
                                       target_coverage, quantile_lower,
                                       quantile_upper, outlier_threshold,
                                       smoothing_window, polynomial_order) {

  n_bins <- nrow(rt_stats)

  # =================================================================
  # Strategy-Specific Processing
  # =================================================================
  # SMOOTHING: GLOBAL optimization (continuous RT function)
  # OTHERS: LOCAL optimization (per RT bin)
  # =================================================================

  if (strategy == "smoothing") {
    cat("  Strategy: SMOOTHING (GLOBAL optimization)\n")
    cat("  → Fine RT sampling → Sliding window → Smooth → Assign to bins\n\n")

    return(optimize_mz_ranges_smoothing_internal(
      precursor_data, rt_stats, quantile_lower, quantile_upper,
      smoothing_window, polynomial_order
    ))
  }

  # =================================================================
  # LOCAL OPTIMIZATION for quantile, coverage, outlier strategies
  # =================================================================
  cat(sprintf("  Strategy: %s (LOCAL optimization)\n", toupper(strategy)))
  cat("  → Calculate m/z independently per RT bin\n\n")

  mz_ranges <- vector("list", n_bins)

  for (i in 1:n_bins) {
    # Get precursors for this RT bin
    bin_data <- precursor_data %>%
      filter(rt_group == i)

    if (nrow(bin_data) == 0) {
      # Empty bin - use full range
      mz_ranges[[i]] <- data.frame(
        rt_segment_id = i,
        rt_start = rt_stats$rt_start[i],
        rt_end = rt_stats$rt_end[i],
        mz_min = 400,
        mz_max = 1200,
        mz_width = 800,
        n_precursors_covered = 0,
        coverage_ratio = NA
      )
      next
    }

    mz_values <- bin_data$Precursor.Mz

    # Apply strategy
    if (strategy == "quantile") {
      # Quantile-based: simple and robust
      mz_min <- quantile(mz_values, quantile_lower, na.rm = TRUE, names = FALSE)
      mz_max <- quantile(mz_values, quantile_upper, na.rm = TRUE, names = FALSE)

    } else if (strategy == "coverage") {
      # Coverage-based: find minimum range that covers target %
      mz_sorted <- sort(mz_values)
      n_target <- ceiling(length(mz_sorted) * target_coverage)

      # Find narrowest window containing n_target precursors
      best_width <- Inf
      best_min <- min(mz_sorted)
      best_max <- max(mz_sorted)

      for (start_idx in 1:(length(mz_sorted) - n_target + 1)) {
        end_idx <- start_idx + n_target - 1
        width <- mz_sorted[end_idx] - mz_sorted[start_idx]

        if (width < best_width) {
          best_width <- width
          best_min <- mz_sorted[start_idx]
          best_max <- mz_sorted[end_idx]
        }
      }

      mz_min <- best_min
      mz_max <- best_max

    } else if (strategy == "outlier") {
      # Outlier removal: mean ± threshold*SD
      mz_mean <- mean(mz_values, na.rm = TRUE)
      mz_sd <- sd(mz_values, na.rm = TRUE)

      lower_bound <- mz_mean - (outlier_threshold * mz_sd)
      upper_bound <- mz_mean + (outlier_threshold * mz_sd)

      # Filter outliers
      inliers <- mz_values >= lower_bound & mz_values <= upper_bound
      mz_inliers <- mz_values[inliers]

      if (length(mz_inliers) > 0) {
        mz_min <- min(mz_inliers, na.rm = TRUE)
        mz_max <- max(mz_inliers, na.rm = TRUE)
      } else {
        # All outliers - use full range
        mz_min <- min(mz_values, na.rm = TRUE)
        mz_max <- max(mz_values, na.rm = TRUE)
      }
    }

    # Calculate coverage
    covered <- sum(mz_values >= mz_min & mz_values <= mz_max)
    coverage_ratio <- covered / length(mz_values)

    mz_ranges[[i]] <- data.frame(
      rt_segment_id = i,
      rt_start = rt_stats$rt_start[i],
      rt_end = rt_stats$rt_end[i],
      mz_min = mz_min,
      mz_max = mz_max,
      mz_width = mz_max - mz_min,
      n_precursors_covered = covered,
      coverage_ratio = coverage_ratio
    )
  }

  bind_rows(mz_ranges)
}

#' Generate Windows (Internal)
#' @keywords internal
generate_windows_internal <- function(precursor_data, rt_stats, mz_ranges,
                                     n_windows_per_bin, window_mode,
                                     min_width_da, max_width_da,
                                     overlap_percentage) {

  n_bins <- nrow(rt_stats)
  all_windows <- vector("list", n_bins)

  for (i in 1:n_bins) {
    # Get data for this RT bin
    bin_data <- precursor_data %>%
      filter(rt_group == i)

    mz_range <- mz_ranges %>%
      filter(rt_segment_id == i)

    if (nrow(mz_range) == 0) next

    mz_min <- mz_range$mz_min[1]
    mz_max <- mz_range$mz_max[1]
    rt_start <- rt_stats$rt_start[i]
    rt_end <- rt_stats$rt_end[i]

    # Generate windows based on mode
    if (window_mode == "fixed") {
      bin_windows <- generate_fixed_windows_internal(
        mz_min, mz_max, n_windows_per_bin, min_width_da, max_width_da
      )
    } else {  # variable
      bin_windows <- generate_variable_windows_internal(
        bin_data$Precursor.Mz, mz_min, mz_max, n_windows_per_bin,
        min_width_da, max_width_da
      )
    }

    # Count precursors in each window (OPTIMIZED with vectorization)
    bin_windows$n_precursors <- count_precursors_in_windows(
      bin_data$Precursor.Mz,
      bin_windows$mz_start,
      bin_windows$mz_end
    )

    # Add RT information
    bin_windows$rt_segment_id <- i
    bin_windows$rt_start <- rt_start
    bin_windows$rt_end <- rt_end
    bin_windows$window_id <- paste0("RT", i, "_W", 1:nrow(bin_windows))

    # Apply overlap if requested
    if (overlap_percentage > 0) {
      bin_windows <- apply_overlap_internal(bin_windows, overlap_percentage,
                                            mz_min, mz_max)
    }

    all_windows[[i]] <- bin_windows
  }

  # Combine all windows
  windows <- bind_rows(all_windows)

  # Reorder columns
  windows <- windows %>%
    select(window_id, rt_segment_id, rt_start, rt_end,
           mz_start, mz_end, mz_center, window_width,
           n_precursors, everything())

  return(windows)
}

#' Generate Fixed Windows (Internal)
#' @keywords internal
generate_fixed_windows_internal <- function(mz_min, mz_max, n_windows,
                                           min_width_da, max_width_da) {

  mz_range <- mz_max - mz_min
  ideal_width <- mz_range / n_windows

  # Apply width constraints
  if (ideal_width < min_width_da) {
    actual_width <- min_width_da
    actual_count <- floor(mz_range / actual_width)
  } else if (ideal_width > max_width_da) {
    actual_width <- max_width_da
    actual_count <- ceiling(mz_range / actual_width)
  } else {
    actual_width <- ideal_width
    actual_count <- n_windows
  }

  actual_count <- max(1, actual_count)

  # Generate window boundaries
  windows <- tibble(
    mz_start = mz_min + (0:(actual_count - 1)) * actual_width,
    mz_end = pmin(mz_min + (1:actual_count) * actual_width, mz_max),
    mz_center = (mz_start + mz_end) / 2,
    window_width = mz_end - mz_start
  )

  return(windows)
}

#' Generate Variable Windows (Internal)
#' @keywords internal
generate_variable_windows_internal <- function(precursor_mz, mz_min, mz_max,
                                              n_windows, min_width_da,
                                              max_width_da) {

  # Filter precursors within range
  precursor_mz <- precursor_mz[precursor_mz >= mz_min & precursor_mz <= mz_max]

  if (length(precursor_mz) == 0) {
    # No precursors - fallback to fixed
    return(generate_fixed_windows_internal(mz_min, mz_max, n_windows,
                                           min_width_da, max_width_da))
  }

  # Sort precursors
  precursor_mz <- sort(precursor_mz)

  # Calculate quantile breakpoints for equal-precursor windows
  quantile_probs <- seq(0, 1, length.out = n_windows + 1)
  quantile_boundaries <- quantile(precursor_mz, probs = quantile_probs,
                                  na.rm = TRUE, names = FALSE)

  # Constrain to mz_min/mz_max
  quantile_boundaries[1] <- mz_min
  quantile_boundaries[length(quantile_boundaries)] <- mz_max

  # Create windows
  windows <- tibble(
    mz_start = quantile_boundaries[-length(quantile_boundaries)],
    mz_end = quantile_boundaries[-1],
    window_width = mz_end - mz_start,
    mz_center = (mz_start + mz_end) / 2
  )

  # Apply width constraints (simplified - just flag violations)
  windows <- windows %>%
    filter(window_width >= min_width_da) %>%
    filter(window_width <= max_width_da)

  return(windows)
}

#' Apply Window Overlap (Internal)
#' @keywords internal
apply_overlap_internal <- function(windows, overlap_percentage, mz_min, mz_max) {

  if (nrow(windows) == 0) return(windows)

  # Calculate overlap amount
  windows$overlap_prev <- 0
  windows$overlap_next <- 0

  for (i in 1:nrow(windows)) {
    overlap_amount <- windows$window_width[i] * (overlap_percentage / 100) / 2

    # Extend start (overlap with previous)
    if (i > 1) {
      windows$mz_start[i] <- max(windows$mz_start[i] - overlap_amount, mz_min)
      windows$overlap_prev[i] <- windows$mz_start[i] - windows$mz_start[i]
    }

    # Extend end (overlap with next)
    if (i < nrow(windows)) {
      windows$mz_end[i] <- min(windows$mz_end[i] + overlap_amount, mz_max)
      windows$overlap_next[i] <- windows$mz_end[i] - windows$mz_end[i]
    }
  }

  # Recalculate width and center
  windows$window_width <- windows$mz_end - windows$mz_start
  windows$mz_center <- (windows$mz_start + windows$mz_end) / 2

  return(windows)
}

#' Calculate Window Statistics (Internal)
#' @keywords internal
calculate_window_statistics_internal <- function(windows, precursor_data) {

  # Count covered precursors
  precursor_data$covered <- FALSE

  for (i in 1:nrow(windows)) {
    window <- windows[i, ]

    in_window <- (precursor_data$rt_group == window$rt_segment_id) &
                 (precursor_data$Precursor.Mz >= window$mz_start) &
                 (precursor_data$Precursor.Mz < window$mz_end)

    precursor_data$covered[in_window] <- TRUE
  }

  covered_precursors <- sum(precursor_data$covered)
  total_precursors <- nrow(precursor_data)
  coverage_ratio <- covered_precursors / total_precursors

  list(
    total_windows = nrow(windows),
    total_precursors = total_precursors,
    covered_precursors = covered_precursors,
    coverage_ratio = coverage_ratio,
    coverage_percentage = coverage_ratio * 100,
    window_width_mean = mean(windows$window_width, na.rm = TRUE),
    window_width_sd = sd(windows$window_width, na.rm = TRUE),
    window_width_cv = calculate_cv(windows$window_width),
    min_window_width = min(windows$window_width, na.rm = TRUE),
    max_window_width = max(windows$window_width, na.rm = TRUE),
    mean_precursors_per_window = mean(windows$n_precursors, na.rm = TRUE),
    sd_precursors_per_window = sd(windows$n_precursors, na.rm = TRUE),
    cv_precursors = calculate_cv(windows$n_precursors),
    min_precursors_per_window = min(windows$n_precursors, na.rm = TRUE),
    max_precursors_per_window = max(windows$n_precursors, na.rm = TRUE)
  )
}

#' Optimize m/z Ranges with GLOBAL Smoothing Strategy (Internal)
#'
#' This function implements GLOBAL optimization for smoothing strategy:
#' 1. Fine RT sampling across entire gradient (high-resolution)
#' 2. Calculate m/z at each RT point using sliding window
#' 3. Apply Savitzky-Golay smoothing to high-resolution curve
#' 4. Assign smoothed values to RT bins
#'
#' This differs from local strategies (quantile, coverage, outlier) which
#' calculate m/z independently per RT bin.
#'
#' @keywords internal
optimize_mz_ranges_smoothing_internal <- function(precursor_data, rt_stats,
                                                   quantile_lower, quantile_upper,
                                                   smoothing_window, polynomial_order) {
  # Load smoothing utilities if not already loaded
  if (!exists("smooth_savgol")) {
    source("R/smoothing_utils.R")
  }

  n_bins <- nrow(rt_stats)

  # Get full RT range
  rt_min <- min(precursor_data$RT.Start, na.rm = TRUE)
  rt_max <- max(precursor_data$RT.Start, na.rm = TRUE)
  rt_range <- rt_max - rt_min

  cat(sprintf("  🌐 GLOBAL smoothing mode\n"))
  cat(sprintf("     RT range: %.2f - %.2f min (span: %.2f min)\n",
              rt_min, rt_max, rt_range))

  # =================================================================
  # Step 1: Fine RT sampling (high-resolution)
  # =================================================================
  # Adaptive sampling interval based on gradient length
  if (rt_range <= 15) {
    rt_sampling_interval <- 0.5  # Short gradient: 0.5 min
  } else if (rt_range <= 40) {
    rt_sampling_interval <- 0.75  # Medium gradient: 0.75 min
  } else {
    rt_sampling_interval <- 1.0  # Long gradient: 1 min
  }

  # Sliding window width (±window around each RT point)
  rt_window_halfwidth <- max(1.0, rt_range / 20)  # Adaptive: ~5% of gradient

  # Generate fine RT grid
  rt_points <- seq(rt_min, rt_max, by = rt_sampling_interval)
  n_rt_points <- length(rt_points)

  cat(sprintf("     Sampling: %d RT points (interval: %.2f min)\n",
              n_rt_points, rt_sampling_interval))
  cat(sprintf("     Sliding window: ± %.2f min\n", rt_window_halfwidth))

  # Check if we have enough points for smoothing
  if (n_rt_points < smoothing_window) {
    cat(sprintf("  ⚠️  WARNING: %d RT points < smoothing window (%d)\n",
                n_rt_points, smoothing_window))
    cat("     Reducing sampling interval to ensure sufficient points...\n")

    # Calculate required interval
    required_points <- smoothing_window + 2
    rt_sampling_interval <- rt_range / required_points
    rt_points <- seq(rt_min, rt_max, by = rt_sampling_interval)
    n_rt_points <- length(rt_points)

    cat(sprintf("     Adjusted: %d RT points (interval: %.2f min)\n",
                n_rt_points, rt_sampling_interval))
  }

  # =================================================================
  # Step 2: Calculate m/z at each RT point (sliding window)
  # =================================================================
  mz_min_raw <- numeric(n_rt_points)
  mz_max_raw <- numeric(n_rt_points)

  for (i in 1:n_rt_points) {
    rt_center <- rt_points[i]
    rt_lower <- rt_center - rt_window_halfwidth
    rt_upper <- rt_center + rt_window_halfwidth

    # Get precursors in sliding window
    window_precursors <- precursor_data %>%
      filter(RT.Start >= rt_lower & RT.Start <= rt_upper)

    if (nrow(window_precursors) > 0) {
      mz_values <- window_precursors$Precursor.Mz
      mz_min_raw[i] <- quantile(mz_values, quantile_lower, na.rm = TRUE, names = FALSE)
      mz_max_raw[i] <- quantile(mz_values, quantile_upper, na.rm = TRUE, names = FALSE)
    } else {
      # Empty window - use global fallback
      mz_min_raw[i] <- 400
      mz_max_raw[i] <- 1200
    }
  }

  cat(sprintf("     Calculated m/z at %d RT points\n", n_rt_points))
  cat(sprintf("     m/z range: %.1f - %.1f Da (min), %.1f - %.1f Da (max)\n",
              min(mz_min_raw), max(mz_min_raw),
              min(mz_max_raw), max(mz_max_raw)))

  # =================================================================
  # Step 3: Apply Savitzky-Golay smoothing
  # =================================================================
  # Adaptive smoothing window
  adaptive_window <- min(smoothing_window, floor(n_rt_points * 0.7))
  if (adaptive_window %% 2 == 0) adaptive_window <- adaptive_window + 1
  adaptive_window <- max(3, adaptive_window)  # Minimum 3

  adaptive_poly <- min(polynomial_order, adaptive_window - 2)

  cat(sprintf("     Smoothing: window=%d, poly_order=%d\n",
              adaptive_window, adaptive_poly))

  mz_min_smooth <- smooth_savgol(mz_min_raw,
                                  window_size = adaptive_window,
                                  poly_order = adaptive_poly)
  mz_max_smooth <- smooth_savgol(mz_max_raw,
                                  window_size = adaptive_window,
                                  poly_order = adaptive_poly)

  cat(sprintf("     ✓ Smoothing successful\n"))

  # =================================================================
  # Step 4: Assign to RT bins (interpolation)
  # =================================================================
  mz_ranges <- vector("list", n_bins)

  for (i in 1:n_bins) {
    rt_bin_start <- rt_stats$rt_start[i]
    rt_bin_end <- rt_stats$rt_end[i]
    rt_bin_center <- (rt_bin_start + rt_bin_end) / 2

    # Interpolate from smoothed curve
    mz_min <- interpolate_at_rt(rt_points, mz_min_smooth, rt_bin_center)
    mz_max <- interpolate_at_rt(rt_points, mz_max_smooth, rt_bin_center)

    # Calculate coverage for this bin
    bin_data <- precursor_data %>%
      filter(rt_group == i)

    if (nrow(bin_data) > 0) {
      mz_values <- bin_data$Precursor.Mz
      covered <- sum(mz_values >= mz_min & mz_values <= mz_max)
      coverage_ratio <- covered / length(mz_values)
    } else {
      covered <- 0
      coverage_ratio <- NA
    }

    mz_ranges[[i]] <- data.frame(
      rt_segment_id = i,
      rt_start = rt_bin_start,
      rt_end = rt_bin_end,
      mz_min = mz_min,
      mz_max = mz_max,
      mz_width = mz_max - mz_min,
      n_precursors_covered = covered,
      coverage_ratio = coverage_ratio
    )
  }

  cat(sprintf("     Assigned to %d RT bins\n", n_bins))

  bind_rows(mz_ranges)
}

#' Interpolate value at given RT from RT-value curve
#' @keywords internal
interpolate_at_rt <- function(rt_points, values, target_rt) {

  # Find bounding points
  if (target_rt <= rt_points[1]) {
    return(values[1])
  }

  if (target_rt >= rt_points[length(rt_points)]) {
    return(values[length(values)])
  }

  # Linear interpolation
  idx_upper <- which(rt_points >= target_rt)[1]
  idx_lower <- idx_upper - 1

  rt_lower <- rt_points[idx_lower]
  rt_upper <- rt_points[idx_upper]
  val_lower <- values[idx_lower]
  val_upper <- values[idx_upper]

  # Interpolate
  fraction <- (target_rt - rt_lower) / (rt_upper - rt_lower)
  interpolated <- val_lower + fraction * (val_upper - val_lower)

  return(interpolated)
}


# =============================================================================
# Helper Functions for CSV Export
# =============================================================================

#' Calculate N_Precursors for Each Window (Internal)
#' @keywords internal
calculate_precursors_per_window <- function(windows, precursor_data) {
  # Vectorized matching for performance
  windows$n_precursors <- sapply(1:nrow(windows), function(i) {
    w <- windows[i, ]
    sum(
      precursor_data$RT.Start >= w$rt_start &
      precursor_data$RT.Start <= w$rt_end &
      precursor_data$Precursor.Mz >= w$mz_start &
      precursor_data$Precursor.Mz <= w$mz_end,
      na.rm = TRUE
    )
  })

  windows
}


# =============================================================================
# CSV Export Function
# =============================================================================

#' Export Windows to CSV for Instrument Upload (Extended Format)
#'
#' Creates instrument-ready CSV file with 21-column extended format
#' compatible with Thermo Orbitrap instruments.
#'
#' @param optimized_windows OptimizedWindows object
#' @param output_file Character, output CSV file path
#' @param validated_data ValidatedData object (for N_Precursors calculation)
#' @param instrument_type Character, instrument type (default: "orbitrap")
#' @param project_name Character, project name for filename (default: "report")
#' @param normalized_agc_target Numeric, AGC target percentage (default: 800)
#'
#' @return NULL (invisible), writes CSV file
#' @export
export_windows_to_csv <- function(optimized_windows, output_file,
                                  validated_data,
                                  optimization_plan = NULL,
                                  instrument_type = "orbitrap",
                                  project_name = "report",
                                  normalized_agc_target = 800) {

  validate_input_type(optimized_windows, "OptimizedWindows", "optimized_windows")
  validate_input_type(validated_data, "ValidatedData", "validated_data")

  # Extract recommended cycle time
  recommended_cycle_time <- if (!is.null(optimization_plan)) {
    optimization_plan$required_cycle_time_sec
  } else {
    NA_real_
  }

  windows <- optimized_windows$windows
  precursor_data <- get_precursor_data(validated_data)

  # Calculate N_Precursors for each window
  cat("  Calculating precursors per window...\n")
  windows_with_counts <- calculate_precursors_per_window(windows, precursor_data)

  # Create 22-column extended format (Thermo Orbitrap compatible)
  method_file <- windows_with_counts %>%
    mutate(
      # Empty columns (Thermo format compatibility)
      Compound = "",
      Formula = "",
      Adduct = "(no adduct)",

      # Core columns
      `m/z` = round(mz_center, 1),
      z = 1,
      `t start (min)` = round(rt_start, 1),
      `t stop (min)` = round(rt_end, 1),
      `Isolation Window (m/z)` = round(mz_end - mz_start, 1),
      `Normalized AGC Target (%)` = normalized_agc_target,
      `Start (m/z)` = round(mz_start, 1),
      `End (m/z)` = round(mz_end, 1),

      # Metadata columns
      Window_ID = row_number(),
      RT_Segment_ID = rt_segment_id,
      RT_Center = round((rt_start + rt_end) / 2, 1),
      RT_Width = round(rt_end - rt_start, 1),
      N_Precursors = n_precursors,
      Overlap_Prev = 0,
      Overlap_Next = 0,

      # Configuration
      Instrument = instrument_type,
      Generation_Method = optimized_windows$parameters$mz_strategy,
      Window_Type = optimized_windows$parameters$window_mode,

      # Column 22: Recommended cycle time (rounded to 1 decimal)
      Recommended_Cycle_Time_Sec = round(recommended_cycle_time, 1)
    ) %>%
    select(Compound, Formula, Adduct, `m/z`, z,
           `t start (min)`, `t stop (min)`,
           `Isolation Window (m/z)`, `Normalized AGC Target (%)`,
           `Start (m/z)`, `End (m/z)`,
           Window_ID, RT_Segment_ID, RT_Center, RT_Width,
           N_Precursors, Overlap_Prev, Overlap_Next,
           Instrument, Generation_Method, Window_Type,
           Recommended_Cycle_Time_Sec)

  # Write CSV file (no header comments for extended format)
  write.csv(method_file, output_file, row.names = FALSE, quote = TRUE)

  cat(sprintf("✅ Method file exported: %s (%d windows, 22 columns)\n",
              output_file, nrow(method_file)))
  invisible(NULL)
}


# =============================================================================
# S3 Methods
# =============================================================================

#' Print method for OptimizedWindows
#' @export
print.OptimizedWindows <- function(x, ...) {
  cat("OptimizedWindows object\n")
  cat(sprintf("  Total windows: %d\n", nrow(x$windows)))
  cat(sprintf("  RT bins: %d (%.1f min each)\n",
              x$rt_binning$n_bins,
              x$parameters$rt_bin_width_min))
  cat(sprintf("  Windows per bin: %d\n", x$parameters$n_windows_per_bin))
  cat(sprintf("  Coverage: %.1f%%\n", x$statistics$coverage_percentage))
  cat(sprintf("  Window mode: %s\n", x$parameters$window_mode))
  cat(sprintf("  m/z strategy: %s\n", x$parameters$mz_strategy))
  invisible(x)
}

#' Summary method for OptimizedWindows
#' @export
summary.OptimizedWindows <- function(object, ...) {
  cat("═══════════════════════════════════════════════════════\n")
  cat(" Optimized Windows Summary\n")
  cat("═══════════════════════════════════════════════════════\n\n")

  cat("Window Generation:\n")
  cat(sprintf("  Total windows: %d\n", object$statistics$total_windows))
  cat(sprintf("  RT bins: %d (%.1f min each)\n",
              object$rt_binning$n_bins,
              object$parameters$rt_bin_width_min))
  cat(sprintf("  Windows per bin: %d\n", object$parameters$n_windows_per_bin))
  cat(sprintf("  Expected total: %d\n",
              object$rt_binning$n_bins * object$parameters$n_windows_per_bin))

  cat("\nWindow Characteristics:\n")
  cat(sprintf("  Width: %.2f ± %.2f Da (range: %.1f - %.1f)\n",
              object$statistics$window_width_mean,
              object$statistics$window_width_sd,
              object$statistics$min_window_width,
              object$statistics$max_window_width))
  cat(sprintf("  Width CV: %.2f\n", object$statistics$window_width_cv))

  cat("\nPrecursor Distribution:\n")
  cat(sprintf("  Precursors per window: %.1f ± %.1f\n",
              object$statistics$mean_precursors_per_window,
              object$statistics$sd_precursors_per_window))
  cat(sprintf("  CV: %.2f\n", object$statistics$cv_precursors))
  cat(sprintf("  Range: %d - %d\n",
              object$statistics$min_precursors_per_window,
              object$statistics$max_precursors_per_window))

  cat("\nCoverage:\n")
  cat(sprintf("  Total precursors: %s\n",
              format(object$statistics$total_precursors, big.mark = ",")))
  cat(sprintf("  Covered precursors: %s (%.1f%%)\n",
              format(object$statistics$covered_precursors, big.mark = ","),
              object$statistics$coverage_percentage))

  cat("\nm/z Optimization:\n")
  cat(sprintf("  Strategy: %s\n", object$mz_optimization$strategy))
  cat(sprintf("  Mean m/z range: %.1f Da\n", object$mz_optimization$mean_width))
  cat(sprintf("  Mean coverage: %.1f%%\n",
              object$mz_optimization$mean_coverage * 100))

  cat("\nParameters:\n")
  cat(sprintf("  Window mode: %s\n", object$parameters$window_mode))
  cat(sprintf("  Width constraints: %.1f - %.1f Da\n",
              object$parameters$min_width_da,
              object$parameters$max_width_da))
  if (object$parameters$overlap_percentage > 0) {
    cat(sprintf("  Overlap: %.1f%%\n", object$parameters$overlap_percentage))
  }

  invisible(object)
}


# =============================================================================
# Module Loading
# =============================================================================

cat("✅ Stage 3 (Window Optimization) loaded successfully\n")
cat("   Main function: optimize_windows(validated_data, optimization_plan, ...)\n")
cat("   Output: OptimizedWindows object\n")
cat("   Export: export_windows_to_csv(optimized_windows, output_file)\n")
