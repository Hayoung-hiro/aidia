# stage3_statistics.R - Window Statistics Functions
#
# Purpose: Calculate statistics for generated DIA windows
#
# Functions:
#   - calculate_window_statistics_internal(): Overall window statistics
#   - calculate_precursors_per_window(): Per-window precursor counts
#
# Dependencies: dplyr, utils_common.R

library(dplyr)

# =============================================================================
# Window Statistics Calculation
# =============================================================================

#' Calculate Window Statistics (Internal)
#'
#' Computes comprehensive statistics for the generated windows including
#' coverage, width distribution, and precursor distribution metrics.
#'
#' @param windows Data frame with window specifications
#' @param precursor_data Data frame with precursor data
#'
#' @return List of statistics
#' @keywords internal
calculate_window_statistics_internal <- function(windows, precursor_data) {

  # Count covered precursors
  precursor_data$covered <- FALSE

  for (i in 1:nrow(windows)) {
    window <- windows[i, ]

    # Check rt_group column presence for LOCAL vs GLOBAL strategies
    if ("rt_group" %in% colnames(precursor_data)) {
      in_window <- (precursor_data$rt_group == window$rt_segment_id) &
                   (precursor_data$Precursor.Mz >= window$mz_start) &
                   (precursor_data$Precursor.Mz < window$mz_end)
    } else {
      in_window <- (precursor_data$RT.Start >= window$rt_start) &
                   (precursor_data$RT.Start <= window$rt_end) &
                   (precursor_data$Precursor.Mz >= window$mz_start) &
                   (precursor_data$Precursor.Mz < window$mz_end)
    }

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
  windows$n_precursors <- count_precursors_in_2d_windows(
    precursor_rt = precursor_data$RT.Start,
    precursor_mz = precursor_data$Precursor.Mz,
    window_rt_start = windows$rt_start,
    window_rt_end = windows$rt_end,
    window_mz_start = windows$mz_start,
    window_mz_end = windows$mz_end
  )

  windows
}

cat("  [stage3_statistics.R] Statistics functions loaded\n")
