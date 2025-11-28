# stage3_rt_binning.R - RT Binning Functions for Stage 3
#
# Purpose: Perform RT (retention time) binning/segmentation
#
# Functions:
#   - perform_rt_binning_internal(): Create RT bins from precursor data
#
# Dependencies: dplyr

library(dplyr)

# =============================================================================
# RT Binning Function
# =============================================================================

#' Perform RT Binning (Internal)
#'
#' Segments precursor data into RT bins based on specified bin width.
#' Calculates statistics for each bin.
#'
#' @param precursor_data Data frame with RT.Start column
#' @param rt_bin_width_min Numeric, RT bin width in minutes
#'
#' @return List containing:
#'   - data: precursor_data with rt_group column added
#'   - stats: RT statistics per bin
#'   - n_bins: Number of bins created
#'   - rt_breaks: RT breakpoints
#'
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

cat("  [stage3_rt_binning.R] RT binning functions loaded\n")
