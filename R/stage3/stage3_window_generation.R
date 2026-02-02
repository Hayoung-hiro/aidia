# stage3_window_generation.R - Window Generation Functions
#
# Purpose: Generate DIA isolation windows from optimized m/z ranges
#
# Functions:
#   - generate_windows_internal(): Main window generation orchestrator
#   - generate_fixed_windows_internal(): Equal-width windows
#   - generate_variable_windows_internal(): Density-based adaptive windows
#   - apply_overlap_internal(): Apply overlap between windows
#
# Dependencies: dplyr, tibble, utils_common.R

library(dplyr)
library(tibble)

# =============================================================================
# Main Window Generation Function
# =============================================================================

#' Generate Windows (Internal)
#'
#' Generates DIA isolation windows for each RT bin using the specified mode.
#'
#' @param precursor_data Data frame with precursor data
#' @param rt_stats RT statistics data frame
#' @param mz_ranges m/z ranges per RT segment
#' @param n_windows_per_bin Number of windows per RT bin
#' @param window_mode Character: "fixed" or "variable"
#' @param min_width_da Minimum window width in Da
#' @param max_width_da Maximum window width in Da
#' @param overlap_percentage Overlap percentage between windows
#'
#' @return Data frame with window specifications
#' @keywords internal
generate_windows_internal <- function(precursor_data, rt_stats, mz_ranges,
                                     n_windows_per_bin, window_mode,
                                     min_width_da, max_width_da,
                                     overlap_percentage) {

  n_bins <- nrow(rt_stats)
  all_windows <- vector("list", n_bins)

  for (i in 1:n_bins) {
    # Get m/z range for this RT bin
    mz_range <- mz_ranges %>%
      filter(rt_segment_id == i)

    if (nrow(mz_range) == 0) next

    mz_min <- mz_range$mz_min[1]
    mz_max <- mz_range$mz_max[1]
    rt_start <- rt_stats$rt_start[i]
    rt_end <- rt_stats$rt_end[i]

    # Get precursors for this RT bin
    # Use rt_group if available (LOCAL strategies), otherwise use RT range (GLOBAL smoothing)
    if ("rt_group" %in% colnames(precursor_data)) {
      bin_data <- precursor_data %>%
        filter(rt_group == i)
    } else {
      bin_data <- precursor_data %>%
        filter(RT.Start >= rt_start & RT.Start <= rt_end)
    }

    # Generate windows based on mode
    if (window_mode == "fixed") {
      bin_windows <- generate_fixed_windows_internal(
        mz_min, mz_max, n_windows_per_bin, min_width_da, max_width_da
      )
    } else if (window_mode == "staggered") {
      bin_windows <- generate_staggered_windows_internal(
        mz_min, mz_max, n_windows_per_bin, min_width_da, max_width_da,
        rt_bin_index = i
      )
    } else {  # density (variable)
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
  windows <- safe_bind_rows(all_windows)

  # Reorder columns
  windows <- windows %>%
    select(window_id, rt_segment_id, rt_start, rt_end,
           mz_start, mz_end, mz_center, window_width,
           n_precursors, everything())

  return(windows)
}

# =============================================================================
# Fixed Window Mode
# =============================================================================

#' Generate Fixed Windows (Internal)
#'
#' Creates equal-width windows across the m/z range.
#'
#' @param mz_min Minimum m/z
#' @param mz_max Maximum m/z
#' @param n_windows Target number of windows
#' @param min_width_da Minimum window width
#' @param max_width_da Maximum window width
#'
#' @return Data frame with window specifications
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

# =============================================================================
# Variable Window Mode
# =============================================================================

#' Generate Variable Windows (Internal)
#'
#' Creates density-based adaptive windows that contain approximately
#' equal numbers of precursors.
#'
#' @param precursor_mz Vector of precursor m/z values
#' @param mz_min Minimum m/z
#' @param mz_max Maximum m/z
#' @param n_windows Target number of windows
#' @param min_width_da Minimum window width
#' @param max_width_da Maximum window width
#'
#' @return Data frame with window specifications
#' @keywords internal
generate_variable_windows_internal <- function(precursor_mz, mz_min, mz_max,
                                              n_windows, min_width_da,
                                              max_width_da) {

  # Filter precursors within range
  precursor_mz <- precursor_mz[precursor_mz >= mz_min & precursor_mz <= mz_max]

  # Fallback to fixed windows if insufficient precursors for density-based splitting
  if (length(precursor_mz) < n_windows) {
    return(generate_fixed_windows_internal(mz_min, mz_max, n_windows,
                                           min_width_da, max_width_da))
  }

  # Pre-adjust n_windows based on width constraints
  # This prevents windows from being too narrow (< min_width)
  mz_range <- mz_max - mz_min
  max_possible_windows <- floor(mz_range / min_width_da)
  actual_n_windows <- min(n_windows, max_possible_windows)
  actual_n_windows <- max(actual_n_windows, 1)  # At least 1 window

  # Sort precursors
  precursor_mz <- sort(precursor_mz)

  # Calculate quantile breakpoints for equal-precursor windows
  quantile_probs <- seq(0, 1, length.out = actual_n_windows + 1)
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

  # Apply max_width constraint only (min_width already handled by pre-adjustment)
  # Windows exceeding max_width are kept but flagged
  windows <- windows %>%
    filter(window_width <= max_width_da)

  return(windows)
}

# =============================================================================
# Staggered Window Mode
# =============================================================================

#' Generate Staggered Windows (Internal)
#'
#' Creates fixed-width windows with staggered (offset) placement across RT bins.
#' Odd RT bins use normal placement, even RT bins are shifted by half window width.
#' This reduces edge effects by ensuring precursors near boundaries are fully
#' covered in adjacent RT bins.
#'
#' @param mz_min Minimum m/z
#' @param mz_max Maximum m/z
#' @param n_windows Target number of windows
#' @param min_width_da Minimum window width
#' @param max_width_da Maximum window width
#' @param rt_bin_index Current RT bin index (1-based)
#' @param stagger_fraction Fraction of window width to offset (default: 0.5 = half)
#'
#' @return Data frame with window specifications
#' @keywords internal
generate_staggered_windows_internal <- function(mz_min, mz_max, n_windows,
                                                 min_width_da, max_width_da,
                                                 rt_bin_index,
                                                 stagger_fraction = 0.5) {

  mz_range <- mz_max - mz_min
  ideal_width <- mz_range / n_windows

  # Apply width constraints (same as fixed mode)
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

  # Calculate stagger offset for even RT bins
  # Odd bins (1, 3, 5...): no offset
  # Even bins (2, 4, 6...): offset by stagger_fraction * window_width
  is_even_bin <- (rt_bin_index %% 2 == 0)
  stagger_offset <- if (is_even_bin) actual_width * stagger_fraction else 0

  # Generate window boundaries with stagger
  # For staggered bins, we need to handle edge cases
  if (is_even_bin) {
    # Even bins: start earlier, may need extra window at the end
    start_mz <- mz_min - stagger_offset

    # Generate windows
    mz_starts <- start_mz + (0:(actual_count)) * actual_width
    mz_ends <- mz_starts + actual_width

    # Filter to only include windows that overlap with [mz_min, mz_max]
    valid_mask <- (mz_ends > mz_min) & (mz_starts < mz_max)
    mz_starts <- mz_starts[valid_mask]
    mz_ends <- mz_ends[valid_mask]

    # Clip to mz_min/mz_max boundaries
    mz_starts <- pmax(mz_starts, mz_min)
    mz_ends <- pmin(mz_ends, mz_max)
  } else {
    # Odd bins: normal placement (same as fixed)
    mz_starts <- mz_min + (0:(actual_count - 1)) * actual_width
    mz_ends <- pmin(mz_min + (1:actual_count) * actual_width, mz_max)
  }

  # Create windows tibble
  windows <- tibble(
    mz_start = mz_starts,
    mz_end = mz_ends,
    mz_center = (mz_start + mz_end) / 2,
    window_width = mz_end - mz_start,
    is_staggered = is_even_bin
  )

  # Remove windows that are too narrow (edge artifacts from clipping)
  windows <- windows %>%
    filter(window_width >= min_width_da * 0.5)  # Allow slightly narrower at edges

  return(windows)
}

# =============================================================================
# Overlap Application
# =============================================================================

#' Apply Window Overlap (Internal)
#'
#' Extends window boundaries to create overlap between adjacent windows.
#'
#' @param windows Data frame with window specifications
#' @param overlap_percentage Overlap percentage
#' @param mz_min Overall minimum m/z
#' @param mz_max Overall maximum m/z
#'
#' @return Data frame with overlapped window specifications
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
    }

    # Extend end (overlap with next)
    if (i < nrow(windows)) {
      windows$mz_end[i] <- min(windows$mz_end[i] + overlap_amount, mz_max)
    }
  }

  # Recalculate width and center
  windows$window_width <- windows$mz_end - windows$mz_start
  windows$mz_center <- (windows$mz_start + windows$mz_end) / 2

  return(windows)
}

cat("  [stage3_window_generation.R] Window generation functions loaded\n")
