# smoothing_continuous.R - Continuous RT-based Smoothing for m/z Range Optimization
#
# Purpose: Apply continuous smoothing across entire RT range, then map to RT bins
#
# Approach:
# 1. Create many RT points across entire RT range (e.g., 100 points)
# 2. For each RT point, calculate quantile-based m/z boundaries from nearby precursors
# 3. Apply Savitzky-Golay smoothing to the continuous m/z boundary curves
# 4. Map smoothed boundaries back to RT bins (average values for overlapping regions)

library(dplyr)

#' Optimize Range: Continuous Smoothing Strategy
#'
#' @param rt_group_stats RT group statistics data frame (from Phase 3B)
#' @param precursor_data Full precursor data with rt_group and RT.Start
#' @param smoothing_window_size Integer, window size for Savitzky-Golay (default: 7)
#' @param polynomial_order Integer, polynomial order for savgol (default: 3)
#' @param quantile_lower Numeric, lower quantile (default: 0.05)
#' @param quantile_upper Numeric, upper quantile (default: 0.95)
#' @param n_smooth_points Integer, number of RT points for continuous smoothing (default: 100)
#' @param rt_window_width Numeric, RT window width for local quantile calculation in minutes (default: 2.0)
#'
#' @return List with mz_ranges and smoothing_data
#' @export
optimize_range_smoothing_continuous <- function(
  rt_group_stats,
  precursor_data,
  smoothing_window_size = 7,
  polynomial_order = 3,
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  n_smooth_points = 100,
  rt_window_width = 2.0
) {

  # Source smoothing utilities if not loaded
  if (!exists("smooth_savgol")) {
    source("R/smoothing_utils.R")
  }

  n_segments <- nrow(rt_group_stats)

  # === Step 1: Create continuous RT grid ===
  rt_min <- min(precursor_data$RT.Start, na.rm = TRUE)
  rt_max <- max(precursor_data$RT.Start, na.rm = TRUE)
  rt_points <- seq(rt_min, rt_max, length.out = n_smooth_points)

  cat(sprintf("  Creating continuous RT grid: %d points from %.1f to %.1f min\n",
              n_smooth_points, rt_min, rt_max))
  cat(sprintf("  RT window for local quantiles: %.1f min\n", rt_window_width))

  # === Step 2: Calculate quantile boundaries at each RT point ===
  continuous_boundaries_list <- list()

  for (i in 1:length(rt_points)) {
    rt_center <- rt_points[i]

    # Get precursors within RT window
    rt_lower <- rt_center - (rt_window_width / 2)
    rt_upper <- rt_center + (rt_window_width / 2)

    local_precursors <- precursor_data %>%
      filter(RT.Start >= rt_lower & RT.Start <= rt_upper)

    if (nrow(local_precursors) > 0) {
      mz_values <- local_precursors$Precursor.Mz
      mz_min_quantile <- quantile(mz_values, quantile_lower, na.rm = TRUE)
      mz_max_quantile <- quantile(mz_values, quantile_upper, na.rm = TRUE)
    } else {
      # No precursors in this RT window - use defaults
      mz_min_quantile <- 400
      mz_max_quantile <- 1200
    }

    continuous_boundaries_list[[i]] <- data.frame(
      rt_point = rt_center,
      mz_min_raw = mz_min_quantile,
      mz_max_raw = mz_max_quantile,
      n_precursors_local = nrow(local_precursors)
    )
  }

  continuous_boundaries <- bind_rows(continuous_boundaries_list)

  # === Step 3: Apply Savitzky-Golay Smoothing to continuous curves ===
  mz_min_smooth <- smooth_savgol(
    continuous_boundaries$mz_min_raw,
    window_size = smoothing_window_size,
    poly_order = polynomial_order
  )
  mz_max_smooth <- smooth_savgol(
    continuous_boundaries$mz_max_raw,
    window_size = smoothing_window_size,
    poly_order = polynomial_order
  )

  # Handle potential length mismatch
  if (length(mz_min_smooth) != nrow(continuous_boundaries)) {
    warning("Smoothing changed array length. Padding with edge values.")

    n_missing <- nrow(continuous_boundaries) - length(mz_min_smooth)
    if (n_missing > 0) {
      pad_start <- ceiling(n_missing / 2)
      pad_end <- floor(n_missing / 2)

      mz_min_smooth <- c(rep(mz_min_smooth[1], pad_start),
                         mz_min_smooth,
                         rep(mz_min_smooth[length(mz_min_smooth)], pad_end))
      mz_max_smooth <- c(rep(mz_max_smooth[1], pad_start),
                         mz_max_smooth,
                         rep(mz_max_smooth[length(mz_max_smooth)], pad_end))
    }
  }

  continuous_boundaries$mz_min_smooth <- mz_min_smooth
  continuous_boundaries$mz_max_smooth <- mz_max_smooth

  cat(sprintf("  Continuous smoothing applied: %.2f Da (min), %.2f Da (max) smoothing effect\n",
              mean(abs(continuous_boundaries$mz_min_smooth - continuous_boundaries$mz_min_raw), na.rm = TRUE),
              mean(abs(continuous_boundaries$mz_max_smooth - continuous_boundaries$mz_max_raw), na.rm = TRUE)))

  # === Step 4: Map smoothed boundaries back to RT bins ===
  mz_ranges_list <- list()

  for (i in 1:n_segments) {
    segment <- rt_group_stats[i, ]
    segment_id <- segment$rt_group

    # Find all RT points that fall within this RT bin
    bin_points <- continuous_boundaries %>%
      filter(rt_point >= segment$rt_start & rt_point <= segment$rt_end)

    if (nrow(bin_points) > 0) {
      # Average the smoothed boundaries across all RT points in this bin
      mz_min <- mean(bin_points$mz_min_smooth, na.rm = TRUE)
      mz_max <- mean(bin_points$mz_max_smooth, na.rm = TRUE)
    } else {
      # No RT points in this bin - use nearest point
      nearest_idx <- which.min(abs(continuous_boundaries$rt_point - (segment$rt_start + segment$rt_end) / 2))
      mz_min <- continuous_boundaries$mz_min_smooth[nearest_idx]
      mz_max <- continuous_boundaries$mz_max_smooth[nearest_idx]
    }

    # Calculate coverage for this RT bin
    segment_precursors <- precursor_data %>%
      filter(rt_group == segment_id)

    if (nrow(segment_precursors) > 0) {
      covered <- segment_precursors$Precursor.Mz >= mz_min & segment_precursors$Precursor.Mz <= mz_max
      n_covered <- sum(covered, na.rm = TRUE)
      coverage_ratio <- n_covered / nrow(segment_precursors)
    } else {
      n_covered <- 0
      coverage_ratio <- NA
    }

    mz_ranges_list[[i]] <- data.frame(
      rt_segment_id = segment_id,
      rt_start = segment$rt_start,
      rt_end = segment$rt_end,
      mz_min = mz_min,
      mz_max = mz_max,
      mz_range_width = mz_max - mz_min,
      n_precursors_covered = n_covered,
      coverage_ratio = coverage_ratio
    )
  }

  mz_ranges <- bind_rows(mz_ranges_list)

  # === Package Smoothing Data ===
  smoothing_data <- list(
    continuous_boundaries = continuous_boundaries,
    smoothing_method = "continuous_savgol",
    smoothing_params = list(
      window_size = smoothing_window_size,
      polynomial_order = polynomial_order,
      quantile_lower = quantile_lower,
      quantile_upper = quantile_upper,
      n_smooth_points = n_smooth_points,
      rt_window_width = rt_window_width
    )
  )

  cat(sprintf("  Continuous smoothing mode: %d RT points mapped to %d RT bins\n",
              n_smooth_points, n_segments))

  return(list(
    mz_ranges = mz_ranges,
    smoothing_data = smoothing_data
  ))
}

cat("✅ Continuous smoothing utilities loaded\n")
cat("   Main function: optimize_range_smoothing_continuous()\n")
