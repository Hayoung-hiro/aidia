# stage3_mz_optimization.R - m/z Range Optimization Functions
#
# Purpose: Optimize m/z ranges for each RT bin using various strategies
#
# Functions:
#   - optimize_mz_ranges_internal(): LOCAL optimization (quantile, coverage, outlier)
#   - optimize_mz_ranges_smoothing_internal(): GLOBAL smoothing strategy
#   - interpolate_at_rt(): RT interpolation helper
#
# Dependencies: dplyr, R/smoothing_utils.R

library(dplyr)

# =============================================================================
# LOCAL Optimization: Quantile, Coverage, Outlier Strategies
# =============================================================================

#' Optimize m/z Ranges (Internal)
#'
#' LOCAL optimization - calculates m/z range independently per RT bin.
#' Supports quantile, coverage, and outlier strategies.
#' For smoothing strategy, delegates to GLOBAL optimizer.
#'
#' @param precursor_data Data frame with rt_group and Precursor.Mz columns
#' @param rt_stats RT statistics data frame
#' @param strategy Character: "quantile", "coverage", "outlier", or "smoothing"
#' @param target_coverage Numeric, target coverage for coverage strategy
#' @param quantile_lower Numeric, lower quantile
#' @param quantile_upper Numeric, upper quantile
#' @param outlier_threshold Numeric, SD multiplier for outlier strategy
#' @param smoothing_window Integer, SG window size
#' @param polynomial_order Integer, SG polynomial order
#'
#' @return Data frame with m/z ranges per RT segment
#' @keywords internal
optimize_mz_ranges_internal <- function(precursor_data, rt_stats, strategy,
                                       target_coverage, quantile_lower,
                                       quantile_upper, outlier_threshold,
                                       smoothing_window, polynomial_order) {

  n_bins <- nrow(rt_stats)

  # =================================================================
  # Strategy-Specific Processing
  # SMOOTHING: GLOBAL optimization (continuous RT function)
  # OTHERS: LOCAL optimization (per RT bin)
  # =================================================================

  if (strategy == "smoothing") {
    cat("  Strategy: SMOOTHING (GLOBAL optimization)\n")
    cat("  -> Fine RT sampling -> Sliding window -> Smooth -> Assign to bins\n\n")

    return(optimize_mz_ranges_smoothing_internal(
      precursor_data, rt_stats, quantile_lower, quantile_upper,
      smoothing_window, polynomial_order
    ))
  }

  # =================================================================
  # LOCAL OPTIMIZATION for quantile, coverage, outlier strategies
  # =================================================================
  cat(sprintf("  Strategy: %s (LOCAL optimization)\n", toupper(strategy)))
  cat("  -> Calculate m/z independently per RT bin\n\n")

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
      # Outlier removal: mean +/- threshold*SD
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

# =============================================================================
# GLOBAL Optimization: Smoothing Strategy
# =============================================================================

#' Optimize m/z Ranges with GLOBAL Smoothing Strategy (Internal)
#'
#' GLOBAL optimization for smoothing strategy:
#' 1. Fine RT sampling across entire gradient (high-resolution)
#' 2. Calculate m/z at each RT point using sliding window
#' 3. Apply Savitzky-Golay smoothing to high-resolution curve
#' 4. Assign smoothed values to RT bins
#'
#' @param precursor_data Data frame with RT.Start and Precursor.Mz
#' @param rt_stats RT statistics data frame
#' @param quantile_lower Numeric, lower quantile
#' @param quantile_upper Numeric, upper quantile
#' @param smoothing_window Integer, SG window size
#' @param polynomial_order Integer, SG polynomial order
#'
#' @return Data frame with m/z ranges per RT segment
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

  cat(sprintf("  GLOBAL smoothing mode\n"))
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

  # Sliding window width (+/-window around each RT point)
  rt_window_halfwidth <- max(1.0, rt_range / 20)  # Adaptive: ~5% of gradient

  # Generate fine RT grid
  rt_points <- seq(rt_min, rt_max, by = rt_sampling_interval)
  n_rt_points <- length(rt_points)

  cat(sprintf("     Sampling: %d RT points (interval: %.2f min)\n",
              n_rt_points, rt_sampling_interval))
  cat(sprintf("     Sliding window: +/- %.2f min\n", rt_window_halfwidth))

  # Check if we have enough points for smoothing
  if (n_rt_points < smoothing_window) {
    cat(sprintf("  WARNING: %d RT points < smoothing window (%d)\n",
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

  cat(sprintf("     OK Smoothing successful\n"))

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
    # GLOBAL smoothing: Filter by RT range (not rt_group)
    bin_data <- precursor_data %>%
      filter(RT.Start >= rt_bin_start & RT.Start <= rt_bin_end)

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

# =============================================================================
# Helper Functions
# =============================================================================

#' Interpolate value at given RT from RT-value curve
#'
#' @param rt_points Numeric vector of RT points
#' @param values Numeric vector of values at each RT point
#' @param target_rt Target RT for interpolation
#'
#' @return Interpolated value at target_rt
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

cat("  [stage3_mz_optimization.R] m/z optimization functions loaded\n")
