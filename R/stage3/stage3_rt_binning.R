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

# =============================================================================
# Adaptive RT Bin Width Calculation (for Shiny UI)
# =============================================================================

#' Calculate Adaptive RT Bin Width
#'
#' Automatically calculates optimal RT bin width based on gradient length
#' and m/z optimization strategy.
#'
#' @param rt_range Numeric vector of length 2, c(min_rt, max_rt) in minutes
#' @param mz_strategy Character, m/z optimization strategy ("smoothing", "quantile", etc.)
#' @param target_min_bins Integer, minimum number of bins to create (default: 5)
#' @return List with bin_width and n_bins
#' @export
calculate_adaptive_rt_bin_width <- function(rt_range,
                                            mz_strategy = "smoothing",
                                            target_min_bins = 5) {

  gradient_length <- rt_range[2] - rt_range[1]

  # Strategy-specific adjustments
  if (mz_strategy == "smoothing") {
    # Smoothing is GLOBAL - can use wider bins
    # Aim for 5-10 bins typically
    target_bins <- max(target_min_bins, ceiling(gradient_length / 10))
    target_bins <- min(target_bins, 15)  # Cap at 15 bins
  } else {
    # LOCAL strategies (quantile, coverage, outlier) - narrower bins preferred
    # Aim for more bins for better local adaptation
    target_bins <- max(target_min_bins, ceiling(gradient_length / 5))
    target_bins <- min(target_bins, 20)  # Cap at 20 bins
  }

  # Calculate bin width
  bin_width <- gradient_length / target_bins

  # Round to sensible values (0.5 min increments)
  bin_width <- round(bin_width * 2) / 2
  bin_width <- max(1.0, min(bin_width, 15.0))  # Clamp between 1 and 15 min

  # Recalculate actual number of bins
  n_bins <- ceiling(gradient_length / bin_width)

  list(
    bin_width = bin_width,
    n_bins = n_bins,
    gradient_length = gradient_length
  )
}

cat("  [stage3_rt_binning.R] RT binning functions loaded\n")
