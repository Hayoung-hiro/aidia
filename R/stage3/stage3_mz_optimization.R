# stage3_mz_optimization.R - m/z Range Optimization Functions
#
# Purpose: Optimize m/z ranges for each RT bin using various strategies
#
# Strategies:
#   - greedy: MacCoss Lab algorithm (with optional SG smoothing)
#   - kde: Kernel Density Estimation based range
#   - quantile: P5-P95 percentiles (with optional SG smoothing)
#   - coverage: Minimum range for target coverage
#   - outlier: Mean ± 3σ (with optional SG smoothing)
#
# Functions:
#   - optimize_mz_ranges_internal(): Main dispatcher
#   - optimize_mz_ranges_greedy_internal(): Greedy algorithm
#   - optimize_mz_ranges_kde_internal(): KDE-based optimization
#   - apply_sg_smoothing_to_mz_ranges(): Post-processing SG smoothing
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
                                       smoothing_window, polynomial_order,
                                       n_windows_per_bin = 10,
                                       min_width_da = 8,
                                       mz_step = 0.5,
                                       greedy_apply_smoothing = TRUE,
                                       kde_density_threshold = 0.1,
                                       kde_min_coverage = 0.80,
                                       quantile_apply_smoothing = FALSE,
                                       outlier_apply_smoothing = FALSE) {

  n_bins <- nrow(rt_stats)

  # =================================================================
  # Strategy-Specific Processing
  # GREEDY: m/z axis sliding optimization
  # SMOOTHING: GLOBAL optimization (continuous RT function)
  # OTHERS: LOCAL optimization (per RT bin)
  # =================================================================

  # =================================================================
  # GREEDY Strategy: m/z axis sliding optimization
  # =================================================================
  if (strategy == "greedy") {
    cat("  Strategy: GREEDY (m/z sliding optimization)\n")
    cat("  -> Slide window across m/z axis, maximize precursor count\n")
    if (greedy_apply_smoothing) {
      cat("  -> Apply Savitzky-Golay smoothing to prevent abrupt jumps\n\n")
    } else {
      cat("  -> No smoothing (raw boundaries)\n\n")
    }

    return(optimize_mz_ranges_greedy_internal(
      precursor_data = precursor_data,
      rt_stats = rt_stats,
      n_windows_per_bin = n_windows_per_bin,
      min_width_da = min_width_da,
      mz_step = mz_step,
      apply_smoothing = greedy_apply_smoothing,
      smoothing_window = smoothing_window,
      polynomial_order = polynomial_order
    ))
  }

  # =================================================================
  # KDE Strategy: Kernel Density Estimation based m/z range
  # =================================================================
  if (strategy == "kde") {
    cat("  Strategy: KDE (Density-Peak based m/z range)\n")
    cat("  -> Find density peak, expand until threshold reached\n\n")

    return(optimize_mz_ranges_kde_internal(
      precursor_data = precursor_data,
      rt_stats = rt_stats,
      density_threshold = kde_density_threshold,
      min_coverage = kde_min_coverage
    ))
  }

  # =================================================================
  # LOCAL OPTIMIZATION for quantile, coverage, outlier strategies
  # =================================================================

  # Determine if SG smoothing will be applied
  apply_smoothing <- FALSE
  if (strategy == "quantile" && quantile_apply_smoothing) {
    apply_smoothing <- TRUE
  } else if (strategy == "outlier" && outlier_apply_smoothing) {
    apply_smoothing <- TRUE
  }

  cat(sprintf("  Strategy: %s (LOCAL optimization)\n", toupper(strategy)))
  if (apply_smoothing) {
    cat("  -> Calculate m/z per RT bin, then apply SG smoothing\n\n")
  } else {
    cat("  -> Calculate m/z independently per RT bin\n\n")
  }

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

  # Combine results
  result <- safe_bind_rows(mz_ranges)

  # =================================================================
  # Apply SG Smoothing (post-processing for quantile/outlier)
  # =================================================================
  if (apply_smoothing && nrow(result) >= 3) {
    cat("  Applying Savitzky-Golay smoothing to m/z boundaries...\n")

    result <- apply_sg_smoothing_to_mz_ranges(
      result,
      smoothing_window = smoothing_window,
      polynomial_order = polynomial_order,
      precursor_data = precursor_data
    )

    cat("  -> Smoothing applied successfully\n\n")
  }

  result
}

# =============================================================================
# Post-processing: SG Smoothing for LOCAL strategies
# =============================================================================

#' Apply Savitzky-Golay Smoothing to m/z Ranges
#'
#' Post-processing function to smooth m/z boundaries across RT bins.
#' Recalculates coverage after smoothing.
#'
#' @param mz_ranges Data frame with mz_min, mz_max columns
#' @param smoothing_window Integer, SG window size
#' @param polynomial_order Integer, SG polynomial order
#' @param precursor_data Original precursor data for coverage recalculation
#'
#' @return Data frame with smoothed m/z ranges
#' @keywords internal
apply_sg_smoothing_to_mz_ranges <- function(mz_ranges, smoothing_window,
                                             polynomial_order, precursor_data) {
  # Load smoothing utilities if not already loaded
  if (!exists("smooth_savgol")) {
    source("R/smoothing_utils.R")
  }

  n_bins <- nrow(mz_ranges)

  # Adaptive smoothing window
  adaptive_window <- min(smoothing_window, floor(n_bins * 0.7))
  if (adaptive_window %% 2 == 0) adaptive_window <- adaptive_window + 1
  adaptive_window <- max(3, adaptive_window)

  adaptive_poly <- min(polynomial_order, adaptive_window - 2)

  cat(sprintf("     SG params: window=%d, poly_order=%d\n",
              adaptive_window, adaptive_poly))

  # Apply smoothing to mz_min and mz_max
  mz_min_smooth <- smooth_savgol(mz_ranges$mz_min,
                                  window_size = adaptive_window,
                                  poly_order = adaptive_poly)
  mz_max_smooth <- smooth_savgol(mz_ranges$mz_max,
                                  window_size = adaptive_window,
                                  poly_order = adaptive_poly)

  # Update values
  mz_ranges$mz_min <- mz_min_smooth
  mz_ranges$mz_max <- mz_max_smooth
  mz_ranges$mz_width <- mz_max_smooth - mz_min_smooth

  # Recalculate coverage
  for (i in 1:n_bins) {
    bin_data <- precursor_data %>%
      filter(RT.Start >= mz_ranges$rt_start[i] & RT.Start <= mz_ranges$rt_end[i])

    if (nrow(bin_data) > 0) {
      mz_values <- bin_data$Precursor.Mz
      covered <- sum(mz_values >= mz_ranges$mz_min[i] & mz_values <= mz_ranges$mz_max[i])
      mz_ranges$n_precursors_covered[i] <- covered
      mz_ranges$coverage_ratio[i] <- covered / length(mz_values)
    }
  }

  mz_ranges
}

# =============================================================================
# LEGACY: Smoothing Strategy Function (kept for reference, not used)
# =============================================================================

#' Optimize m/z Ranges with GLOBAL Smoothing Strategy (Internal)
#' @note DEPRECATED: Use quantile with quantile_apply_smoothing=TRUE instead
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

  safe_bind_rows(mz_ranges)
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

# =============================================================================
# GREEDY Optimization: MacCoss Lab Dynamic DIA Algorithm
# =============================================================================

#' Optimize m/z Ranges with GREEDY Strategy (Internal)
#'
#' GREEDY optimization based on MacCoss Lab dynamicDIA.py algorithm.
#'
#' **Key Concept**: The m/z range per cycle is FIXED by instrument constraints:
#'   mz_range_per_cycle = n_windows × isolation_width
#'
#' The algorithm slides this fixed range across the m/z axis to find the
#' position that covers the MAXIMUM number of precursors.
#'
#' **Post-processing**: Following the original dynamicDIA implementation,
#' Savitzky-Golay smoothing is applied to m/z boundaries across RT bins
#' to prevent abrupt jumps between adjacent bins.
#'
#' **Difference from Coverage strategy**:
#' - Coverage: Fixed target coverage → Variable m/z range
#' - Greedy:   Fixed m/z range → Variable coverage (maximized within constraint)
#'
#' Reference: https://github.com/uw-maccosslab/manuscript-dynamic-dia
#'
#' @param precursor_data Data frame with rt_group and Precursor.Mz columns
#' @param rt_stats RT statistics data frame
#' @param n_windows_per_bin Integer, number of windows per RT bin
#' @param min_width_da Numeric, minimum window width in Da (determines fixed range)
#' @param mz_step Numeric, step size for sliding window in Da (default: 0.5)
#' @param apply_smoothing Logical, whether to apply SG smoothing (default: TRUE)
#' @param smoothing_window Integer, SG window size (default: 5)
#' @param polynomial_order Integer, SG polynomial order (default: 2)
#' @param target_coverage Not used (kept for API consistency)
#'
#' @return Data frame with m/z ranges per RT segment
#' @keywords internal
optimize_mz_ranges_greedy_internal <- function(precursor_data, rt_stats,
                                                n_windows_per_bin, min_width_da,
                                                mz_step = 0.5,
                                                apply_smoothing = TRUE,
                                                smoothing_window = 5,
                                                polynomial_order = 2,
                                                target_coverage = 0.90) {
  n_bins <- nrow(rt_stats)

  # Calculate FIXED m/z range per cycle (MacCoss Lab approach)
  # This is the total m/z coverage possible given instrument constraints
  mz_range_per_cycle <- n_windows_per_bin * min_width_da

  cat(sprintf("  GREEDY m/z optimization mode (MacCoss Lab algorithm)\n"))
  cat(sprintf("     Windows per bin: %d\n", n_windows_per_bin))
  cat(sprintf("     Isolation width: %.1f Da\n", min_width_da))
  cat(sprintf("     Fixed m/z range per cycle: %.1f Da\n", mz_range_per_cycle))
  cat(sprintf("     Sliding step: %.1f Da\n", mz_step))
  cat(sprintf("     Post-smoothing: %s\n", ifelse(apply_smoothing, "YES (SG filter)", "NO")))
  cat(sprintf("     Finding optimal m/z position per RT bin...\n\n"))

  # =========================================================================
  # Phase 1: Greedy search for optimal position in each RT bin
  # =========================================================================
  mz_min_raw <- numeric(n_bins)
  mz_max_raw <- numeric(n_bins)
  n_precursors_covered <- numeric(n_bins)
  coverage_ratios <- numeric(n_bins)
  n_precursors_total <- numeric(n_bins)

  for (i in 1:n_bins) {
    # Get precursors for this RT bin
    bin_data <- precursor_data %>%
      filter(rt_group == i)

    if (nrow(bin_data) == 0) {
      # Empty bin - use default range centered at 800
      mz_min_raw[i] <- 800 - mz_range_per_cycle / 2
      mz_max_raw[i] <- 800 + mz_range_per_cycle / 2
      n_precursors_covered[i] <- 0
      coverage_ratios[i] <- NA
      n_precursors_total[i] <- 0
      next
    }

    mz_values <- bin_data$Precursor.Mz
    n_precursors <- length(mz_values)
    n_precursors_total[i] <- n_precursors
    global_mz_min <- min(mz_values)
    global_mz_max <- max(mz_values)
    global_mz_range <- global_mz_max - global_mz_min

    # If precursor range is smaller than our fixed range, cover all
    if (global_mz_range <= mz_range_per_cycle) {
      # Center the fixed range around precursors
      center <- (global_mz_min + global_mz_max) / 2
      mz_min_raw[i] <- center - mz_range_per_cycle / 2
      mz_max_raw[i] <- center + mz_range_per_cycle / 2
      n_precursors_covered[i] <- n_precursors
    } else {
      # Greedy search: slide fixed range across m/z axis
      # Find position with maximum precursor count
      best_count <- 0
      best_mz_min <- global_mz_min

      # Generate trial positions
      trial_starts <- seq(global_mz_min, global_mz_max - mz_range_per_cycle, by = mz_step)

      for (trial_mz_min in trial_starts) {
        trial_mz_max <- trial_mz_min + mz_range_per_cycle

        # Count precursors within this range
        precursors_in_range <- sum(mz_values >= trial_mz_min & mz_values <= trial_mz_max)

        if (precursors_in_range > best_count) {
          best_count <- precursors_in_range
          best_mz_min <- trial_mz_min
        }
      }

      mz_min_raw[i] <- best_mz_min
      mz_max_raw[i] <- best_mz_min + mz_range_per_cycle
      n_precursors_covered[i] <- best_count
    }

    coverage_ratios[i] <- n_precursors_covered[i] / n_precursors
  }

  # =========================================================================
  # Phase 2: Apply Savitzky-Golay smoothing (following dynamicDIA.py)
  # =========================================================================
  if (apply_smoothing && n_bins >= 3) {
    # Load smoothing utilities if not already loaded
    if (!exists("smooth_savgol")) {
      tryCatch({
        source("R/smoothing_utils.R")
      }, error = function(e) {
        cat("     Warning: Could not load smoothing_utils.R, skipping smoothing\n")
        apply_smoothing <- FALSE
      })
    }

    if (apply_smoothing && exists("smooth_savgol")) {
      # Adaptive window size based on number of bins
      adaptive_window <- min(smoothing_window, floor(n_bins * 0.7))
      if (adaptive_window %% 2 == 0) adaptive_window <- adaptive_window + 1
      adaptive_window <- max(3, adaptive_window)

      adaptive_poly <- min(polynomial_order, adaptive_window - 2)
      adaptive_poly <- max(1, adaptive_poly)

      cat(sprintf("     Applying Savitzky-Golay smoothing (window=%d, poly=%d)...\n",
                  adaptive_window, adaptive_poly))

      # Smooth mz_min and mz_max separately
      mz_min_smooth <- smooth_savgol(mz_min_raw,
                                      window_size = adaptive_window,
                                      poly_order = adaptive_poly)
      mz_max_smooth <- smooth_savgol(mz_max_raw,
                                      window_size = adaptive_window,
                                      poly_order = adaptive_poly)

      # Ensure width constraint is maintained after smoothing
      # If smoothing made the range narrower than mz_range_per_cycle, adjust
      for (i in 1:n_bins) {
        smoothed_width <- mz_max_smooth[i] - mz_min_smooth[i]
        if (smoothed_width < mz_range_per_cycle * 0.95) {
          # Re-center to maintain fixed width
          center <- (mz_min_smooth[i] + mz_max_smooth[i]) / 2
          mz_min_smooth[i] <- center - mz_range_per_cycle / 2
          mz_max_smooth[i] <- center + mz_range_per_cycle / 2
        }
      }

      # Calculate change from raw to smoothed
      max_change <- max(abs(mz_min_smooth - mz_min_raw), abs(mz_max_smooth - mz_max_raw))
      cat(sprintf("     Max boundary shift from smoothing: %.1f Da\n", max_change))

      mz_min_final <- mz_min_smooth
      mz_max_final <- mz_max_smooth
    } else {
      mz_min_final <- mz_min_raw
      mz_max_final <- mz_max_raw
    }
  } else {
    if (n_bins < 3) {
      cat("     Skipping smoothing (need at least 3 RT bins)\n")
    }
    mz_min_final <- mz_min_raw
    mz_max_final <- mz_max_raw
  }

  # =========================================================================
  # Phase 3: Recalculate coverage after smoothing
  # =========================================================================
  if (apply_smoothing && n_bins >= 3) {
    for (i in 1:n_bins) {
      if (n_precursors_total[i] > 0) {
        bin_data <- precursor_data %>% filter(rt_group == i)
        mz_values <- bin_data$Precursor.Mz
        n_precursors_covered[i] <- sum(mz_values >= mz_min_final[i] &
                                        mz_values <= mz_max_final[i])
        coverage_ratios[i] <- n_precursors_covered[i] / n_precursors_total[i]
      }
    }
  }

  # =========================================================================
  # Phase 4: Build result data frame
  # =========================================================================
  mz_ranges <- vector("list", n_bins)
  for (i in 1:n_bins) {
    mz_ranges[[i]] <- data.frame(
      rt_segment_id = i,
      rt_start = rt_stats$rt_start[i],
      rt_end = rt_stats$rt_end[i],
      mz_min = mz_min_final[i],
      mz_max = mz_max_final[i],
      mz_width = mz_max_final[i] - mz_min_final[i],
      n_precursors_covered = n_precursors_covered[i],
      coverage_ratio = coverage_ratios[i]
    )
  }

  mean_coverage <- mean(coverage_ratios, na.rm = TRUE)

  cat(sprintf("     Optimized %d RT bins\n", n_bins))
  cat(sprintf("     Mean coverage: %.1f%% (within fixed %.0f Da range)\n",
              mean_coverage * 100, mz_range_per_cycle))

  if (mean_coverage < 0.5) {
    cat(sprintf("\n  ⚠ Note: Low coverage is expected when precursor m/z distribution\n"))
    cat(sprintf("         is wider than instrument capacity (%.0f Da range).\n", mz_range_per_cycle))
    cat(sprintf("         Consider using 'coverage' strategy for higher coverage.\n"))
  }

  safe_bind_rows(mz_ranges)
}

# =============================================================================
# KDE Optimization: Density-Peak Based m/z Range Strategy
# =============================================================================

#' Optimize m/z Ranges with KDE Strategy (Internal)
#'
#' KDE (Kernel Density Estimation) based optimization finds the densest
#' m/z regions while ensuring minimum coverage.
#'
#' **Key Concept**: Unlike quantile (percentile-based) or greedy (fixed range),
#' KDE finds actual density peaks and sets boundaries based on where
#' density drops below a threshold.
#'
#' Algorithm:
#' 1. Compute 1D KDE along m/z axis for each RT bin
#' 2. Find the density peak (mode)
#' 3. Expand from peak until density < threshold OR coverage met
#' 4. Ensure minimum coverage is achieved
#'
#' @param precursor_data Data frame with rt_group and Precursor.Mz columns
#' @param rt_stats RT statistics data frame
#' @param density_threshold Numeric 0-1, relative density threshold (default: 0.1 = 10% of peak)
#' @param min_coverage Numeric 0-1, minimum coverage to achieve (default: 0.80)
#'
#' @return Data frame with m/z ranges per RT segment
#' @keywords internal
optimize_mz_ranges_kde_internal <- function(precursor_data, rt_stats,
                                            density_threshold = 0.1,
                                            min_coverage = 0.80) {
  n_bins <- nrow(rt_stats)
  mz_ranges <- vector("list", n_bins)

  cat(sprintf("  KDE m/z optimization mode (Density-Peak based)\n"))
  cat(sprintf("     Density threshold: %.0f%% of peak\n", density_threshold * 100))
  cat(sprintf("     Minimum coverage target: %.0f%%\n", min_coverage * 100))
  cat(sprintf("     Finding density peaks per RT bin...\n\n"))

  for (i in 1:n_bins) {
    # Get precursors for this RT bin
    bin_data <- precursor_data %>%
      filter(rt_group == i)

    if (nrow(bin_data) == 0) {
      # Empty bin - use default range
      mz_ranges[[i]] <- data.frame(
        rt_segment_id = i,
        rt_start = rt_stats$rt_start[i],
        rt_end = rt_stats$rt_end[i],
        mz_min = 400,
        mz_max = 1200,
        mz_width = 800,
        n_precursors_covered = 0,
        coverage_ratio = NA,
        kde_peak_mz = NA
      )
      next
    }

    mz_values <- bin_data$Precursor.Mz
    n_precursors <- length(mz_values)

    # Need at least 10 points for meaningful KDE
    if (n_precursors < 10) {
      # Fallback to simple min/max with margin
      mz_min <- min(mz_values) - 10
      mz_max <- max(mz_values) + 10
      kde_peak <- median(mz_values)
    } else {
      # Compute 1D KDE
      # Use density() function with appropriate bandwidth
      kde <- tryCatch({
        density(mz_values, bw = "SJ", n = 512)  # Sheather-Jones bandwidth
      }, error = function(e) {
        density(mz_values, bw = "nrd0", n = 512)  # Fallback to default
      })

      # Find peak (mode) of KDE
      peak_idx <- which.max(kde$y)
      kde_peak <- kde$x[peak_idx]
      peak_density <- kde$y[peak_idx]

      # Find boundaries where density drops below threshold
      threshold_value <- peak_density * density_threshold

      # Search left from peak
      left_idx <- peak_idx
      while (left_idx > 1 && kde$y[left_idx] > threshold_value) {
        left_idx <- left_idx - 1
      }
      kde_mz_min <- kde$x[left_idx]

      # Search right from peak
      right_idx <- peak_idx
      while (right_idx < length(kde$y) && kde$y[right_idx] > threshold_value) {
        right_idx <- right_idx + 1
      }
      kde_mz_max <- kde$x[right_idx]

      # Check coverage with KDE-based boundaries
      covered_kde <- sum(mz_values >= kde_mz_min & mz_values <= kde_mz_max)
      coverage_kde <- covered_kde / n_precursors

      # If coverage is below minimum, expand boundaries
      if (coverage_kde < min_coverage) {
        # Sort m/z values and find boundaries for minimum coverage
        sorted_mz <- sort(mz_values)
        n_needed <- ceiling(n_precursors * min_coverage)

        # Find narrowest range containing n_needed precursors
        # centered around the density peak
        best_width <- Inf
        best_start <- 1

        for (start_idx in 1:(n_precursors - n_needed + 1)) {
          end_idx <- start_idx + n_needed - 1
          width <- sorted_mz[end_idx] - sorted_mz[start_idx]

          # Prefer ranges that include the density peak
          range_includes_peak <- sorted_mz[start_idx] <= kde_peak &&
                                 sorted_mz[end_idx] >= kde_peak

          if (range_includes_peak && width < best_width) {
            best_width <- width
            best_start <- start_idx
          }
        }

        # If no range includes peak, find any narrowest range
        if (best_width == Inf) {
          for (start_idx in 1:(n_precursors - n_needed + 1)) {
            end_idx <- start_idx + n_needed - 1
            width <- sorted_mz[end_idx] - sorted_mz[start_idx]
            if (width < best_width) {
              best_width <- width
              best_start <- start_idx
            }
          }
        }

        mz_min <- sorted_mz[best_start]
        mz_max <- sorted_mz[best_start + n_needed - 1]
      } else {
        mz_min <- kde_mz_min
        mz_max <- kde_mz_max
      }
    }

    # Add small margin (2%)
    margin <- (mz_max - mz_min) * 0.02
    mz_min <- mz_min - margin
    mz_max <- mz_max + margin

    # Calculate final coverage
    covered <- sum(mz_values >= mz_min & mz_values <= mz_max)
    coverage_ratio <- covered / n_precursors

    mz_ranges[[i]] <- data.frame(
      rt_segment_id = i,
      rt_start = rt_stats$rt_start[i],
      rt_end = rt_stats$rt_end[i],
      mz_min = mz_min,
      mz_max = mz_max,
      mz_width = mz_max - mz_min,
      n_precursors_covered = covered,
      coverage_ratio = coverage_ratio,
      kde_peak_mz = if (exists("kde_peak")) kde_peak else median(mz_values)
    )
  }

  mean_coverage <- mean(sapply(mz_ranges, function(x) x$coverage_ratio), na.rm = TRUE)
  mean_width <- mean(sapply(mz_ranges, function(x) x$mz_width), na.rm = TRUE)

  cat(sprintf("     Optimized %d RT bins\n", n_bins))
  cat(sprintf("     Mean coverage: %.1f%%\n", mean_coverage * 100))
  cat(sprintf("     Mean m/z width: %.1f Da\n", mean_width))

  safe_bind_rows(mz_ranges)
}

cat("  [stage3_mz_optimization.R] m/z optimization functions loaded\n")
