# module3c_mz_range_optimization.R - Phase 3C: m/z Range Optimization
#
# Purpose: Optimize RT-dependent m/z ranges using 4 strategies:
#   1. Quantile-based (P5-P95)
#   2. Smoothing-based (DynamicDIA)
#   3. Outlier removal (statistical)
#   4. Coverage-based (minimum range for target coverage)
#
# Input: RTBinningResult from Phase 3B
# Output: MzRangeResult with optimized m/z ranges per RT segment

library(dplyr)
library(prospectr)

# =============================================================================
# Main Optimization Function
# =============================================================================

#' Optimize m/z Ranges (Phase 3C Main Function)
#'
#' @param rt_binning_result RTBinningResult from Phase 3B
#' @param strategy Character, "quantile", "smoothing", "outlier", "coverage"
#' @param dynamic Logical, enable DynamicDIA smoothing (default: TRUE, only for "smoothing")
#' @param smoothing_method Character, "savgol", "movav", "gaussian"
#' @param smoothing_window_size Integer, smoothing window size (default: 7)
#' @param polynomial_order Integer, polynomial order for savgol (default: 3)
#' @param target_coverage Numeric, target coverage for coverage-based (0-1, default: 0.95)
#' @param quantile_lower Numeric, lower quantile for quantile-based (default: 0.05)
#' @param quantile_upper Numeric, upper quantile for quantile-based (default: 0.95)
#' @param outlier_threshold Numeric, SD threshold for outlier removal (default: 3.0)
#' @param compare_strategies Logical, compare all strategies (default: FALSE)
#' @param continuous_smooth Logical, use continuous RT-based smoothing (default: FALSE, only for "smoothing")
#' @param n_smooth_points Integer, number of RT points for continuous smoothing (default: 100)
#' @param rt_window_width Numeric, RT window width in minutes for continuous smoothing (default: 2.0)
#'
#' @return MzRangeResult object
#' @export
optimize_mz_ranges <- function(
  rt_binning_result,
  strategy = "smoothing",
  dynamic = TRUE,
  smoothing_method = "savgol",
  smoothing_window_size = 7,
  polynomial_order = 3,
  target_coverage = 0.95,
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  outlier_threshold = 3.0,
  compare_strategies = FALSE,
  continuous_smooth = FALSE,
  n_smooth_points = 100,
  rt_window_width = 2.0
) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   Phase 3C: m/z Range Optimization           ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  # Validate strategy
  valid_strategies <- c("quantile", "smoothing", "outlier", "coverage")
  if (!strategy %in% valid_strategies) {
    stop(sprintf("Invalid strategy: %s. Must be one of: %s",
                 strategy, paste(valid_strategies, collapse = ", ")))
  }

  cat(sprintf("Strategy: %s\n", strategy))
  if (strategy == "smoothing" && dynamic) {
    cat(sprintf("Smoothing: %s (dynamic mode)\n", smoothing_method))
  }

  # Extract data from Phase 3B output (simplified format)
  precursor_data <- rt_binning_result$data$data  # ValidatedData with rt_group
  rt_group_stats <- rt_binning_result$rt_group_stats
  n_segments <- nrow(rt_group_stats)

  cat(sprintf("RT segments: %d\n", n_segments))
  cat(sprintf("Total precursors: %d\n\n", nrow(precursor_data)))

  # === Apply Selected Strategy ===
  if (compare_strategies) {
    cat("Running ALL strategies for comparison...\n\n")

    # Run all strategies
    results_list <- list()
    for (strat in valid_strategies) {
      cat(sprintf("→ Testing %s strategy...\n", strat))

      result <- apply_strategy_to_segments(
        rt_group_stats = rt_group_stats,
        precursor_data = precursor_data,
        strategy = strat,
        dynamic = (strat == "smoothing" && dynamic),
        smoothing_method = smoothing_method,
        smoothing_window_size = smoothing_window_size,
        polynomial_order = polynomial_order,
        target_coverage = target_coverage,
        quantile_lower = quantile_lower,
        quantile_upper = quantile_upper,
        outlier_threshold = outlier_threshold,
        continuous_smooth = continuous_smooth,
        n_smooth_points = n_smooth_points,
        rt_window_width = rt_window_width
      )

      results_list[[strat]] <- result
    }

    # Create strategy comparison
    strategy_comparison <- compare_all_strategies(results_list)

    # Use selected strategy as primary result
    mz_ranges <- results_list[[strategy]]$mz_ranges
    smoothing_data <- if (strategy == "smoothing") results_list[[strategy]]$smoothing_data else list()

  } else {
    # Single strategy
    cat(sprintf("Applying %s strategy to %d RT segments...\n\n", strategy, n_segments))

    result <- apply_strategy_to_segments(
      rt_group_stats = rt_group_stats,
      precursor_data = precursor_data,
      strategy = strategy,
      dynamic = (strategy == "smoothing" && dynamic),
      smoothing_method = smoothing_method,
      smoothing_window_size = smoothing_window_size,
      polynomial_order = polynomial_order,
      target_coverage = target_coverage,
      quantile_lower = quantile_lower,
      quantile_upper = quantile_upper,
      outlier_threshold = outlier_threshold,
      continuous_smooth = continuous_smooth,
      n_smooth_points = n_smooth_points,
      rt_window_width = rt_window_width
    )

    mz_ranges <- result$mz_ranges
    smoothing_data <- result$smoothing_data
    strategy_comparison <- NULL
  }

  # === Calculate Overall Statistics ===
  overall_stats <- list(
    n_segments = n_segments,
    total_precursors = nrow(precursor_data),
    overall_coverage_ratio = sum(mz_ranges$n_precursors_covered) / nrow(precursor_data),
    mz_range_original_mean = 800,  # Default: 1200-400
    mz_range_optimized_mean = mean(mz_ranges$mz_range_width, na.rm = TRUE),
    mz_range_reduction_mean = 100 * (1 - mean(mz_ranges$mz_range_width) /
                                       800),  # Default full range
    coverage_per_segment_min = min(mz_ranges$coverage_ratio, na.rm = TRUE),
    coverage_per_segment_max = max(mz_ranges$coverage_ratio, na.rm = TRUE),
    coverage_per_segment_mean = mean(mz_ranges$coverage_ratio, na.rm = TRUE)
  )

  # === INSIGHT: Per-Segment m/z Range Summary ===
  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   m/z Range Optimization Insights            ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  cat(sprintf("Strategy: %s\n\n", strategy))

  cat("RT Seg | RT Range (min)  | m/z Range (Da)        | Width (Da) | Coverage\n")
  cat("-------|------------------|------------------------|------------|----------\n")

  for (i in 1:min(nrow(mz_ranges), 10)) {  # Show first 10 segments
    seg <- mz_ranges[i, ]
    cat(sprintf("  %2d   | %5.1f - %5.1f    | %6.1f - %6.1f    | %10.1f | %7.1f%%\n",
                seg$rt_segment_id,
                seg$rt_start,
                seg$rt_end,
                seg$mz_min,
                seg$mz_max,
                seg$mz_range_width,
                seg$coverage_ratio * 100))
  }

  if (nrow(mz_ranges) > 10) {
    cat(sprintf("  ...  |      (+ %d more segments)       \n", nrow(mz_ranges) - 10))
  }

  cat("-------|------------------|------------------------|------------|----------\n")
  cat(sprintf("  Mean |                  |                        | %10.1f | %7.1f%%\n",
              mean(mz_ranges$mz_range_width, na.rm = TRUE),
              mean(mz_ranges$coverage_ratio, na.rm = TRUE) * 100))
  cat("\n")

  cat("\n═══════════════════════════════════════════════\n")
  cat(" Phase 3C Complete\n")
  cat("═══════════════════════════════════════════════\n")
  cat(sprintf("✓ Overall coverage: %.1f%%\n", overall_stats$overall_coverage_ratio * 100))
  cat(sprintf("  Mean m/z range: %.1f Da (was: %.1f Da)\n",
              overall_stats$mz_range_optimized_mean,
              overall_stats$mz_range_original_mean))
  cat(sprintf("  Range reduction: %.1f%%\n", overall_stats$mz_range_reduction_mean))

  # === Package Results ===
  result <- structure(
    list(
      mz_ranges = mz_ranges,

      strategy_comparison = strategy_comparison,

      smoothing_data = smoothing_data,

      optimization_stats = overall_stats,

      metadata = list(
        strategy_used = strategy,
        dynamic_mode = (strategy == "smoothing" && dynamic),
        outlier_threshold = if (strategy == "outlier") outlier_threshold else NULL,
        optimization_timestamp = Sys.time()
      ),

      # Reference to input
      rt_binning_result = rt_binning_result
    ),
    class = c("MzRangeResult", "list")
  )

  return(result)
}

# =============================================================================
# Strategy Application
# =============================================================================

#' Apply strategy to all RT segments
#' @keywords internal
apply_strategy_to_segments <- function(
  rt_group_stats,
  precursor_data,
  strategy,
  dynamic,
  smoothing_method,
  smoothing_window_size,
  polynomial_order,
  target_coverage,
  quantile_lower,
  quantile_upper,
  outlier_threshold,
  continuous_smooth = FALSE,
  n_smooth_points = 100,
  rt_window_width = 2.0
) {

  if (strategy == "smoothing" && dynamic) {
    # Special handling for smoothing strategy
    if (continuous_smooth) {
      # Load continuous smoothing module
      if (!exists("optimize_range_smoothing_continuous")) {
        source("R/stage3_window_optimization/smoothing_continuous.R")
      }

      return(optimize_range_smoothing_continuous(
        rt_group_stats = rt_group_stats,
        precursor_data = precursor_data,
        smoothing_window_size = smoothing_window_size,
        polynomial_order = polynomial_order,
        quantile_lower = quantile_lower,
        quantile_upper = quantile_upper,
        n_smooth_points = n_smooth_points,
        rt_window_width = rt_window_width
      ))
    } else {
      # Original bin-wise smoothing
      return(optimize_range_smoothing(
        rt_group_stats = rt_group_stats,
        precursor_data = precursor_data,
        smoothing_method = smoothing_method,
        smoothing_window_size = smoothing_window_size,
        polynomial_order = polynomial_order,
        quantile_lower = quantile_lower,
        quantile_upper = quantile_upper
      ))
    }
  }

  # For other strategies, apply segment-by-segment
  mz_ranges_list <- list()

  for (i in 1:nrow(rt_group_stats)) {
    segment <- rt_group_stats[i, ]
    segment_id <- segment$rt_group

    # Get precursors for this segment
    segment_precursors <- precursor_data %>%
      filter(rt_group == segment_id)

    if (nrow(segment_precursors) == 0) {
      # Empty segment - use full range
      mz_ranges_list[[i]] <- data.frame(
        rt_segment_id = segment_id,
        rt_start = segment$rt_start,
        rt_end = segment$rt_end,
        mz_min = 400,  # Default mz_min
        mz_max = 1200,  # Default mz_max
        mz_range_width = 800,  # Default mz_range
        n_precursors_covered = 0,
        coverage_ratio = NA
      )
      next
    }

    # Apply strategy
    if (strategy == "quantile") {
      opt_result <- optimize_range_quantile(
        precursor_data = segment_precursors,
        quantile_lower = quantile_lower,
        quantile_upper = quantile_upper
      )
    } else if (strategy == "outlier") {
      opt_result <- optimize_range_outlier_removal(
        precursor_data = segment_precursors,
        outlier_threshold = outlier_threshold
      )
    } else if (strategy == "coverage") {
      opt_result <- optimize_range_coverage_based(
        precursor_data = segment_precursors,
        target_coverage = target_coverage
      )
    }

    # Package result
    mz_ranges_list[[i]] <- data.frame(
      rt_segment_id = segment_id,
      rt_start = segment$rt_start,
      rt_end = segment$rt_end,
      mz_min = opt_result$mz_min,
      mz_max = opt_result$mz_max,
      mz_range_width = opt_result$mz_range_width,
      n_precursors_covered = opt_result$n_precursors_covered,
      coverage_ratio = opt_result$coverage_ratio
    )
  }

  mz_ranges <- bind_rows(mz_ranges_list)

  return(list(
    mz_ranges = mz_ranges,
    smoothing_data = list()
  ))
}

# =============================================================================
# Strategy 1: Quantile-Based
# =============================================================================

#' Optimize Range: Quantile Strategy
#'
#' @param precursor_data Data frame with precursor m/z values
#' @param quantile_lower Numeric, lower quantile (default: 0.05)
#' @param quantile_upper Numeric, upper quantile (default: 0.95)
#'
#' @return List with mz_min, mz_max, coverage_ratio
#' @export
optimize_range_quantile <- function(
  precursor_data,
  quantile_lower = 0.05,
  quantile_upper = 0.95
) {

  mz_values <- precursor_data$Precursor.Mz

  # Calculate quantiles
  mz_min <- quantile(mz_values, quantile_lower, na.rm = TRUE)
  mz_max <- quantile(mz_values, quantile_upper, na.rm = TRUE)

  # Count covered precursors
  covered <- mz_values >= mz_min & mz_values <= mz_max
  n_covered <- sum(covered, na.rm = TRUE)
  coverage_ratio <- n_covered / length(mz_values)

  return(list(
    mz_min = as.numeric(mz_min),
    mz_max = as.numeric(mz_max),
    mz_range_width = as.numeric(mz_max - mz_min),
    n_precursors_covered = n_covered,
    coverage_ratio = coverage_ratio
  ))
}

# =============================================================================
# Strategy 2: Smoothing-Based (DynamicDIA)
# =============================================================================

#' Optimize Range: Smoothing Strategy (Quantile + Smoothing Hybrid)
#'
#' @param rt_group_stats RT group statistics data frame (from Phase 3B)
#' @param precursor_data Full precursor data with rt_group assignment
#' @param smoothing_method Character, "savgol" only (simplified)
#' @param smoothing_window_size Integer, window size (default: 7)
#' @param polynomial_order Integer, polynomial order (for savgol, default: 3)
#' @param quantile_lower Numeric, lower quantile for initial filtering (default: 0.05)
#' @param quantile_upper Numeric, upper quantile for initial filtering (default: 0.95)
#'
#' @return List with mz_ranges and smoothing_data
#' @export
optimize_range_smoothing <- function(
  rt_group_stats,
  precursor_data,
  smoothing_method = "savgol",
  smoothing_window_size = 7,
  polynomial_order = 3,
  quantile_lower = 0.05,
  quantile_upper = 0.95
) {

  # Source smoothing utilities if not loaded
  if (!exists("smooth_savgol")) {
    source("R/smoothing_utils.R")
  }

  n_segments <- nrow(rt_group_stats)

  # === Step 1: Extract Quantile-Based Boundaries ===
  raw_boundaries_list <- list()

  for (i in 1:n_segments) {
    segment <- rt_group_stats[i, ]
    segment_id <- segment$rt_group

    segment_precursors <- precursor_data %>%
      filter(rt_group == segment_id)

    if (nrow(segment_precursors) > 0) {
      # Use quantiles instead of min/max to reduce sensitivity to outliers
      mz_values <- segment_precursors$Precursor.Mz
      mz_min_quantile <- quantile(mz_values, quantile_lower, na.rm = TRUE)
      mz_max_quantile <- quantile(mz_values, quantile_upper, na.rm = TRUE)
    } else {
      mz_min_quantile <- 400  # Default mz_min
      mz_max_quantile <- 1200  # Default mz_max
    }

    raw_boundaries_list[[i]] <- data.frame(
      rt_segment_id = segment_id,
      rt_center = (segment$rt_start + segment$rt_end) / 2,
      mz_min_raw = mz_min_quantile,
      mz_max_raw = mz_max_quantile
    )
  }

  raw_boundaries <- bind_rows(raw_boundaries_list)

  # === Step 2: Apply Savitzky-Golay Smoothing ===
  mz_min_smooth <- smooth_savgol(
    raw_boundaries$mz_min_raw,
    window_size = smoothing_window_size,
    poly_order = polynomial_order
  )
  mz_max_smooth <- smooth_savgol(
    raw_boundaries$mz_max_raw,
    window_size = smoothing_window_size,
    poly_order = polynomial_order
  )

  # Handle potential length mismatch from edge effects
  if (length(mz_min_smooth) != nrow(raw_boundaries)) {
    warning("Smoothing changed array length. Padding with edge values.")

    # Pad to match original length
    n_missing <- nrow(raw_boundaries) - length(mz_min_smooth)
    if (n_missing > 0) {
      # Pad edges
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

  # === Step 3: Create Smoothed Boundaries ===
  smoothed_boundaries <- raw_boundaries %>%
    mutate(
      mz_min_smooth = mz_min_smooth,
      mz_max_smooth = mz_max_smooth,
      mz_range_width = mz_max_smooth - mz_min_smooth,
      delta_min = abs(mz_min_smooth - mz_min_raw),
      delta_max = abs(mz_max_smooth - mz_max_raw)
    )

  # === Step 4: Calculate Coverage ===
  mz_ranges_list <- list()

  for (i in 1:n_segments) {
    segment <- rt_group_stats[i, ]
    segment_id <- segment$rt_group

    segment_precursors <- precursor_data %>%
      filter(rt_group == segment_id)

    mz_min <- smoothed_boundaries$mz_min_smooth[i]
    mz_max <- smoothed_boundaries$mz_max_smooth[i]

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
    raw_boundaries = raw_boundaries,
    smoothed_boundaries = smoothed_boundaries,
    smoothing_method = smoothing_method,
    smoothing_params = list(
      window_size = smoothing_window_size,
      polynomial_order = polynomial_order,
      quantile_lower = quantile_lower,
      quantile_upper = quantile_upper
    )
  )

  cat(sprintf("  Quantile-based smoothing: P%.0f-P%.0f boundaries\n",
              quantile_lower * 100, quantile_upper * 100))
  cat(sprintf("  Mean smoothing effect: %.2f Da (min), %.2f Da (max)\n",
              mean(smoothed_boundaries$delta_min, na.rm = TRUE),
              mean(smoothed_boundaries$delta_max, na.rm = TRUE)))

  return(list(
    mz_ranges = mz_ranges,
    smoothing_data = smoothing_data
  ))
}

# =============================================================================
# Strategy 3: Outlier Removal
# =============================================================================

#' Optimize Range: Outlier Removal Strategy
#'
#' @param precursor_data Data frame with precursor m/z values
#' @param outlier_threshold Numeric, SD threshold (default: 3.0)
#'
#' @return List with mz_min, mz_max, coverage_ratio, n_outliers_removed
#' @export
optimize_range_outlier_removal <- function(
  precursor_data,
  outlier_threshold = 3.0
) {

  mz_values <- precursor_data$Precursor.Mz

  # Calculate mean and SD
  mz_mean <- mean(mz_values, na.rm = TRUE)
  mz_sd <- sd(mz_values, na.rm = TRUE)

  # Define outlier boundaries (mean ± threshold*SD)
  lower_bound <- mz_mean - (outlier_threshold * mz_sd)
  upper_bound <- mz_mean + (outlier_threshold * mz_sd)

  # Filter outliers
  inliers <- mz_values >= lower_bound & mz_values <= upper_bound
  mz_inliers <- mz_values[inliers]

  if (length(mz_inliers) == 0) {
    # All outliers - use full range
    return(list(
      mz_min = min(mz_values, na.rm = TRUE),
      mz_max = max(mz_values, na.rm = TRUE),
      mz_range_width = max(mz_values, na.rm = TRUE) - min(mz_values, na.rm = TRUE),
      n_precursors_covered = length(mz_values),
      coverage_ratio = 1.0,
      n_outliers_removed = 0
    ))
  }

  # Determine range from inliers
  mz_min <- min(mz_inliers, na.rm = TRUE)
  mz_max <- max(mz_inliers, na.rm = TRUE)

  # Calculate coverage
  covered <- mz_values >= mz_min & mz_values <= mz_max
  n_covered <- sum(covered, na.rm = TRUE)
  coverage_ratio <- n_covered / length(mz_values)

  return(list(
    mz_min = mz_min,
    mz_max = mz_max,
    mz_range_width = mz_max - mz_min,
    n_precursors_covered = n_covered,
    coverage_ratio = coverage_ratio,
    n_outliers_removed = sum(!inliers, na.rm = TRUE)
  ))
}

# =============================================================================
# Strategy 4: Coverage-Based
# =============================================================================

#' Optimize Range: Coverage-Based Strategy
#'
#' @param precursor_data Data frame with precursor m/z values
#' @param target_coverage Numeric, target coverage ratio (0-1, default: 0.95)
#'
#' @return List with mz_min, mz_max, coverage_ratio
#' @export
optimize_range_coverage_based <- function(
  precursor_data,
  target_coverage = 0.95
) {

  # Extract m/z values and sort
  mz_values <- sort(precursor_data$Precursor.Mz)
  n_total <- length(mz_values)
  n_target <- ceiling(n_total * target_coverage)

  if (n_target <= 0 || n_target > n_total) {
    # Edge case
    return(list(
      mz_min = min(mz_values, na.rm = TRUE),
      mz_max = max(mz_values, na.rm = TRUE),
      mz_range_width = max(mz_values, na.rm = TRUE) - min(mz_values, na.rm = TRUE),
      n_precursors_covered = n_total,
      coverage_ratio = 1.0
    ))
  }

  # Find minimum range that covers target number of precursors
  min_range_width <- Inf
  best_mz_min <- NULL
  best_mz_max <- NULL

  for (i in 1:(n_total - n_target + 1)) {
    # Window: [i, i + n_target - 1]
    mz_min <- mz_values[i]
    mz_max <- mz_values[i + n_target - 1]
    range_width <- mz_max - mz_min

    if (range_width < min_range_width) {
      min_range_width <- range_width
      best_mz_min <- mz_min
      best_mz_max <- mz_max
    }
  }

  # Calculate actual coverage
  covered <- mz_values >= best_mz_min & mz_values <= best_mz_max
  n_covered <- sum(covered, na.rm = TRUE)
  coverage_ratio <- n_covered / n_total

  return(list(
    mz_min = best_mz_min,
    mz_max = best_mz_max,
    mz_range_width = min_range_width,
    n_precursors_covered = n_covered,
    coverage_ratio = coverage_ratio
  ))
}

# =============================================================================
# Strategy Comparison
# =============================================================================

#' Compare All Strategies
#' @keywords internal
compare_all_strategies <- function(results_list) {

  comparison_list <- list()

  for (strategy_name in names(results_list)) {
    result <- results_list[[strategy_name]]
    mz_ranges <- result$mz_ranges

    comparison_list[[strategy_name]] <- data.frame(
      strategy = strategy_name,
      mean_coverage = mean(mz_ranges$coverage_ratio, na.rm = TRUE),
      mean_mz_width = mean(mz_ranges$mz_range_width, na.rm = TRUE),
      total_precursors_covered = sum(mz_ranges$n_precursors_covered, na.rm = TRUE),
      min_coverage = min(mz_ranges$coverage_ratio, na.rm = TRUE),
      max_coverage = max(mz_ranges$coverage_ratio, na.rm = TRUE)
    )
  }

  comparison_df <- bind_rows(comparison_list)

  cat("\n=== Strategy Comparison ===\n")
  print(comparison_df, row.names = FALSE)

  return(comparison_df)
}

cat("✅ Phase 3C (m/z Range Optimization) loaded\n")
cat("   Main function: optimize_mz_ranges()\n")
cat("   Strategies: quantile, smoothing, outlier, coverage\n")
