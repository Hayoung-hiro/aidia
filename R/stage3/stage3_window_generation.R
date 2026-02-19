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
#' @param width_grid_step Grid step for width digitization in Da (default: 0.5)
#' @param use_parallel Logical, whether to use parallel processing (default: FALSE)
#' @param n_cores Integer, number of cores for parallel processing (NULL = auto)
#' @param stagger_offset_pct Numeric, offset percentage for staggered mode (default: 0.5)
#'
#' @return Data frame with window specifications
#' @keywords internal
generate_windows_internal <- function(precursor_data, rt_stats, mz_ranges,
                                     n_windows_per_bin, window_mode,
                                     min_width_da, max_width_da,
                                     overlap_percentage, width_grid_step = 0.5,
                                     use_parallel = FALSE,
                                     n_cores = NULL,
                                     stagger_offset_pct = 0.5) {

  n_bins <- nrow(rt_stats)

  if (use_parallel) {
    cat("  -> Parallel window generation (future plan set by orchestrator)\n")
  }

  # Prepare indices for iteration
  bin_indices <- 1:n_bins

  # Define per-bin processing function
  process_func <- function(i) {
    # Get m/z range for this RT bin
    mz_range <- mz_ranges %>%
      filter(rt_segment_id == i)

    if (nrow(mz_range) == 0) return(NULL)

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
        filter(RT.Apex >= rt_start & RT.Apex <= rt_end)
    }

    # Generate windows based on mode
    if (window_mode == "fixed") {
      bin_windows <- generate_fixed_windows_internal(
        mz_min, mz_max, n_windows_per_bin, min_width_da, max_width_da
      )
    } else if (window_mode == "staggered") {
      bin_windows <- generate_staggered_windows_internal(
        mz_min, mz_max, n_windows_per_bin, min_width_da, max_width_da,
        rt_bin_index = i,
        stagger_fraction = stagger_offset_pct
      )
    } else {  # density (variable)
      bin_windows <- generate_variable_windows_internal(
        bin_data$Precursor.Mz, mz_min, mz_max, n_windows_per_bin,
        min_width_da, max_width_da, width_grid_step = width_grid_step
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

    return(bin_windows)
  }

  # Execute processing (plan is set by orchestrator if parallel)
  if (use_parallel) {
    all_windows <- future.apply::future_lapply(bin_indices, process_func, future.seed = TRUE)
  } else {
    all_windows <- lapply(bin_indices, process_func)
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
# Variable Window Mode (v2: Constrained Density Partitioning)
# =============================================================================

#' Generate Variable Windows (Internal)
#'
#' Creates density-based adaptive windows with guaranteed width constraints
#' and smooth transitions between adjacent windows.
#'
#' Algorithm: Constrained Density Partitioning
#'   Phase 1: Start with uniform distribution (guaranteed valid)
#'   Phase 2: Iteratively adjust boundaries based on precursor density
#'   Phase 3: Apply smoothing for gradual width transitions
#'   Phase 3.5: Width digitization for batch reproducibility (if enabled)
#'   Phase 4: Final validation
#'
#' Constraints enforced:
#'   - min_width_da <= window_width <= max_width_da (always)
#'   - Adjacent windows differ by at most max_change_ratio (smooth transitions)
#'   - Exactly n_windows are generated (when possible)
#'
#' @param precursor_mz Vector of precursor m/z values
#' @param mz_min Minimum m/z
#' @param mz_max Maximum m/z
#' @param n_windows Target number of windows
#' @param min_width_da Minimum window width in Da
#' @param max_width_da Maximum window width in Da
#' @param max_iterations Maximum iterations for density adjustment (default: 20)
#' @param max_change_ratio Maximum width change ratio between adjacent windows (default: 0.5)
#' @param width_grid_step Grid step for width digitization in Da (default: 0.5). Set to NULL or 0 to disable.
#'
#' @return Data frame with window specifications
#' @keywords internal
generate_variable_windows_internal <- function(precursor_mz, mz_min, mz_max,
                                               n_windows, min_width_da,
                                               max_width_da,
                                               max_iterations = 20,
                                               max_change_ratio = 0.5,
                                               width_grid_step = 0.5) {

  # Filter precursors within range
  precursor_mz <- precursor_mz[precursor_mz >= mz_min & precursor_mz <= mz_max]
  n_precursors <- length(precursor_mz)

  # Fallback to fixed windows if insufficient precursors
 if (n_precursors < n_windows * 2) {
    return(generate_fixed_windows_internal(mz_min, mz_max, n_windows,
                                           min_width_da, max_width_da))
  }

  # Validate that n_windows is feasible
  mz_range <- mz_max - mz_min
  max_possible_windows <- floor(mz_range / min_width_da)

  if (max_possible_windows < 1) {
    # Range too small for even 1 window at min_width
    return(generate_fixed_windows_internal(mz_min, mz_max, 1,
                                           min_width_da, max_width_da))
  }

  actual_n_windows <- min(n_windows, max_possible_windows)

  # =========================================================================
  # Phase 1: Initialize with uniform distribution
  # =========================================================================
  uniform_width <- mz_range / actual_n_windows
  boundaries <- seq(mz_min, mz_max, length.out = actual_n_windows + 1)

  # Sort precursors for efficient counting
  precursor_mz <- sort(precursor_mz)

  # =========================================================================
  # Phase 2: Iterative density-based boundary adjustment
  # =========================================================================
  # Goal: Move boundaries to equalize precursor counts while respecting constraints

  adjustment_step <- uniform_width * 0.1  # 10% of uniform width per iteration

  for (iter in 1:max_iterations) {
    boundaries_changed <- FALSE

    # Adjust internal boundaries (indices 2 to n)
    for (i in 2:actual_n_windows) {
      # Current boundary position
      current_boundary <- boundaries[i]

      # Count precursors in left and right windows
      left_count <- sum(precursor_mz >= boundaries[i - 1] &
                          precursor_mz < boundaries[i])
      right_count <- sum(precursor_mz >= boundaries[i] &
                           precursor_mz < boundaries[i + 1])

      # Skip if balanced (within 20% difference)
      total <- left_count + right_count
      if (total == 0) next
      imbalance_ratio <- abs(left_count - right_count) / total
      if (imbalance_ratio < 0.2) next

      # Determine direction: move toward the denser side
      if (left_count > right_count) {
        # Move boundary left (shrink left, expand right)
        new_boundary <- current_boundary - adjustment_step
      } else {
        # Move boundary right (expand left, shrink right)
        new_boundary <- current_boundary + adjustment_step
      }

      # Check constraints before applying
      left_width_new <- new_boundary - boundaries[i - 1]
      right_width_new <- boundaries[i + 1] - new_boundary

      # Constraint 1: min_width
      if (left_width_new < min_width_da || right_width_new < min_width_da) {
        next  # Reject this move
      }

      # Constraint 2: max_width
      if (left_width_new > max_width_da || right_width_new > max_width_da) {
        next  # Reject this move
      }

      # All constraints satisfied - apply the move
      boundaries[i] <- new_boundary
      boundaries_changed <- TRUE
    }

    # Early exit if no changes in this iteration
    if (!boundaries_changed) break
  }

  # =========================================================================
  # Phase 3: Smooth transitions between adjacent windows
  # =========================================================================
  # Ensure width changes gradually (no abrupt jumps)

  widths <- diff(boundaries)

  for (smooth_iter in 1:5) {
    widths_changed <- FALSE

    for (i in 2:length(widths)) {
      prev_width <- widths[i - 1]
      curr_width <- widths[i]

      # Calculate change ratio
      change_ratio <- abs(curr_width - prev_width) / prev_width

      if (change_ratio > max_change_ratio) {
        # Need to smooth this transition
        # Target: bring curr_width closer to prev_width
        if (curr_width > prev_width) {
          # Current is wider - try to shrink it
          target_width <- prev_width * (1 + max_change_ratio)
          new_width <- max(target_width, min_width_da)
        } else {
          # Current is narrower - try to expand it
          target_width <- prev_width * (1 - max_change_ratio)
          new_width <- min(target_width, max_width_da)
          new_width <- max(new_width, min_width_da)
        }

        # Adjust boundary between window i-1 and i
        # boundary[i] = boundary[i-1] + width[i-1]
        # We need to adjust boundary[i+1] to change width[i]
        if (i < length(widths)) {
          # Check if adjustment is feasible
          width_diff <- new_width - curr_width
          new_next_width <- widths[i + 1] - width_diff

          if (new_next_width >= min_width_da && new_next_width <= max_width_da) {
            widths[i] <- new_width
            widths[i + 1] <- new_next_width
            widths_changed <- TRUE
          }
        }
      }
    }

    if (!widths_changed) break
  }

  # Reconstruct boundaries from widths
  boundaries <- c(mz_min, mz_min + cumsum(widths))

  # Ensure last boundary is exactly mz_max (fix floating point drift)
  boundaries[length(boundaries)] <- mz_max

  # =========================================================================
  # Phase 3.5: Width digitization for robustness
  # =========================================================================
  if (!is.null(width_grid_step) && width_grid_step > 0) {
    widths_raw <- widths
    widths <- round(widths / width_grid_step) * width_grid_step

    # Clamp to min/max constraints
    widths <- pmax(widths, min_width_da)
    widths <- pmin(widths, max_width_da)

    # Redistribute remainder to preserve total range
    mz_range <- mz_max - mz_min
    remainder <- mz_range - sum(widths)

    if (abs(remainder) > 1e-10) {
      n_adjustments <- round(remainder / width_grid_step)
      if (n_adjustments != 0) {
        direction <- sign(n_adjustments)
        rounding_errors <- widths_raw - widths
        candidates <- order(direction * rounding_errors, decreasing = TRUE)
        for (j in seq_len(abs(n_adjustments))) {
          idx <- candidates[j]
          new_width <- widths[idx] + direction * width_grid_step
          if (new_width >= min_width_da && new_width <= max_width_da) {
            widths[idx] <- new_width
          }
        }
      }
      # Final residual goes to last window
      final_remainder <- mz_range - sum(widths)
      if (abs(final_remainder) > 1e-10) {
        widths[length(widths)] <- widths[length(widths)] + final_remainder
      }
    }

    # Reconstruct boundaries from digitized widths
    boundaries <- c(mz_min, mz_min + cumsum(widths))
    boundaries[length(boundaries)] <- mz_max  # ensure exact endpoint
  }

  # =========================================================================
  # Phase 4: Create final windows with validation
  # =========================================================================

  windows <- tibble(
    mz_start = boundaries[-length(boundaries)],
    mz_end = boundaries[-1],
    window_width = mz_end - mz_start,
    mz_center = (mz_start + mz_end) / 2
  )

  # Final validation - should always pass if algorithm is correct
  if (any(windows$window_width < min_width_da * 0.99)) {
    # Fallback to fixed if constraints violated (shouldn't happen)
    warning("Variable window generation violated min_width constraint. Falling back to fixed mode.")
    return(generate_fixed_windows_internal(mz_min, mz_max, n_windows,
                                           min_width_da, max_width_da))
  }

  if (any(windows$window_width > max_width_da * 1.01)) {
    # Allow slight overshoot due to floating point
    windows$window_width <- pmin(windows$window_width, max_width_da)
  }

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
  # When ideal_width < min: use min_width, floor() gives fewer windows that fit
  # When ideal_width > max: use max_width, ceiling() ensures full coverage
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
  half_window_offset <- actual_width * stagger_fraction
  stagger_offset <- if (is_even_bin) half_window_offset else 0

  # Generate window boundaries with stagger offset
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
  edge_min_width <- min_width_da * 0.5
  windows <- windows %>%
    filter(window_width >= edge_min_width)

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
