# window_statistics.R - Window Statistics Functions
#
# Purpose: Calculate statistics for generated DIA windows
#
# Functions:
#   - calculate_window_statistics_internal(): Overall window statistics
#   - calculate_precursors_per_window(): Per-window precursor counts
#
# Dependencies: dplyr, utils_common.R


# =============================================================================
# Window Statistics Calculation
# =============================================================================

#' Calculate Window Statistics (Internal)
#'
#' Computes comprehensive statistics for the generated windows including
#' coverage, width distribution, and precursor distribution metrics.
#' Uses a single grouped pass for both coverage and per-window counts,
#' avoiding redundant O(n*w) computation.
#'
#' @param windows Data frame with window specifications
#' @param precursor_data Data frame with precursor data
#'
#' @return List of statistics
#' @keywords internal
calculate_window_statistics_internal <- function(windows, precursor_data) {

  .account_window_precursors(windows, precursor_data)$statistics
}

# Counts and unique coverage are derived together from final geometry. This is
# also the evaluation test surface; callers never need to order separate counts
# and coverage passes or decide whether an attached count is stale.
.account_window_precursors <- function(windows, precursor_data) {
  matched <- .match_precursors_in_2d_windows(
    precursor_data$RT.Apex, precursor_data$Precursor.Mz,
    windows$rt_start, windows$rt_end, windows$mz_start, windows$mz_end,
    precursor_group = precursor_data$rt_group, window_group = windows$rt_segment_id
  )
  windows$n_precursors <- matched$counts
  covered_precursors <- sum(matched$covered)
  total_precursors <- nrow(precursor_data)
  coverage_ratio <- if (total_precursors > 0L) covered_precursors / total_precursors else 0

  statistics <- list(
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
  list(windows = windows, statistics = statistics, covered = matched$covered)
}

# =============================================================================
# Per-Window Precursor Count
# =============================================================================

#' Calculate N_Precursors for Each Window (Internal)
#'
#' Uses vectorized 2D matching for 50-100x faster performance
#' compared to loop-based approaches.
#'
#' @param windows Data frame with window specifications
#' @param precursor_data Data frame with precursor data
#'
#' @return Windows data frame with n_precursors column updated
#' @keywords internal
calculate_precursors_per_window <- function(windows, precursor_data) {
  # Count precursors in each window using vectorized 2D matching
  # 50-100x faster than loop-based approach for large datasets
  windows$n_precursors <- .match_precursors_in_2d_windows(
    precursor_rt = precursor_data$RT.Apex,
    precursor_mz = precursor_data$Precursor.Mz,
    window_rt_start = windows$rt_start,
    window_rt_end = windows$rt_end,
    window_mz_start = windows$mz_start,
    window_mz_end = windows$mz_end,
    precursor_group = precursor_data$rt_group,
    window_group = windows$rt_segment_id
  )$counts

  windows
}

