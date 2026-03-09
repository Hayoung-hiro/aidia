# window_generation.R - Window Generation Functions
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
#' @param fz_offset Numeric, forbidden zone offset for staggered mode (default: 0.25, use 0.18 for phospho)
#'
#' @return Data frame with window specifications
#' @keywords internal
generate_windows_internal <- function(precursor_data, rt_stats, mz_ranges,
                                     n_windows_per_bin, window_mode,
                                     min_width_da, max_width_da,
                                     overlap_percentage, width_grid_step = 0.5,
                                     fz_offset = 0.25) {

  n_bins <- nrow(rt_stats)

  # Warn once if overlap and forbidden zone are both active (invariant across bins)
  if (overlap_percentage > 0 && fz_offset > 0 && window_mode != "staggered") {
    warning("Overlap margins conflict with forbidden zone placement. ",
            "Consider setting overlap_percentage = 0.")
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
    # All generators handle FZ internally via boundary-array-first architecture
    if (window_mode == "fixed") {
      bin_windows <- generate_fixed_windows_internal(
        mz_min, mz_max, n_windows_per_bin, min_width_da, max_width_da,
        fz_offset = fz_offset
      )
    } else if (window_mode == "staggered") {
      bin_windows <- generate_staggered_windows_internal(
        mz_min, mz_max, n_windows_per_bin, min_width_da, max_width_da,
        rt_bin_index = i,
        fz_offset = fz_offset
      )
    } else {  # density (variable)
      bin_windows <- generate_variable_windows_internal(
        bin_data$Precursor.Mz, mz_min, mz_max, n_windows_per_bin,
        min_width_da, max_width_da, width_grid_step = width_grid_step,
        fz_offset = fz_offset
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
  all_windows <- lapply(bin_indices, process_func)

  # Combine all windows
  windows <- safe_bind_rows(all_windows)

  # For staggered mode, sort C1 before C2 within each RT bin
  # (required for Thermo Loop Control N to cycle correctly)
  if (window_mode == "staggered" && "cycle" %in% colnames(windows)) {
    windows <- windows %>%
      arrange(rt_segment_id, cycle, mz_start)
  }

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
#' Uses boundary-array-first architecture: boundaries are always integerized
#' for clean edges, then optionally FZ-transformed when fz_offset > 0.
#' Continuity is guaranteed by construction (adjacent boundary pairs).
#'
#' @param mz_min Minimum m/z
#' @param mz_max Maximum m/z
#' @param n_windows Target number of windows
#' @param min_width_da Minimum window width
#' @param max_width_da Maximum window width
#' @param fz_offset Forbidden zone constant (0 to disable)
#'
#' @return Data frame with window specifications
#' @keywords internal
generate_fixed_windows_internal <- function(mz_min, mz_max, n_windows,
                                           min_width_da, max_width_da,
                                           fz_offset = 0) {

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

  # Generate boundaries
  boundaries <- seq(mz_min, mz_max, length.out = actual_count + 1)

  # Always integerize for clean boundaries
  boundaries <- integerize_boundaries(boundaries, mz_min, mz_max)

  # Conditionally apply forbidden zone transform
  if (fz_offset > 0) {
    boundaries <- transform_boundaries_to_fz(boundaries, fz_offset)
  }

  # Assemble windows from boundary array (continuity guaranteed by construction)
  windows <- assemble_windows_from_boundaries(boundaries)

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
                                               width_grid_step = 0.5,
                                               fz_offset = 0) {

  # Filter precursors within range
  precursor_mz <- precursor_mz[precursor_mz >= mz_min & precursor_mz <= mz_max]
  n_precursors <- length(precursor_mz)

  # Fallback to fixed windows if insufficient precursors
  if (n_precursors < n_windows * 2) {
    warning(sprintf(
      "Density mode fallback: only %d precursors in bin (need >= %d for %d windows). Using fixed-width.",
      n_precursors, n_windows * 2, n_windows
    ))
    return(generate_fixed_windows_internal(mz_min, mz_max, n_windows,
                                           min_width_da, max_width_da,
                                           fz_offset = fz_offset))
  }

  # Validate that n_windows is feasible
  mz_range <- mz_max - mz_min
  max_possible_windows <- floor(mz_range / min_width_da)

  if (max_possible_windows < 1) {
    # Range too small for even 1 window at min_width
    return(generate_fixed_windows_internal(mz_min, mz_max, 1,
                                           min_width_da, max_width_da,
                                           fz_offset = fz_offset))
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
  # Phase 4: Forbidden zone transform (if active) or direct assembly
  # =========================================================================

  # Always integerize for clean boundaries
  boundaries <- integerize_boundaries(boundaries, mz_min, mz_max)

  # Validate width constraints after integer rounding
  int_widths <- diff(boundaries)
  if (any(int_widths < min_width_da * 0.9) || any(int_widths > max_width_da * 1.1)) {
    warning("Variable mode: integer rounding violated width constraints. Falling back to fixed mode.")
    return(generate_fixed_windows_internal(mz_min, mz_max, n_windows,
                                           min_width_da, max_width_da,
                                           fz_offset = fz_offset))
  }

  # Conditionally apply forbidden zone transform
  if (fz_offset > 0) {
    boundaries <- transform_boundaries_to_fz(boundaries, fz_offset)

    # Re-validate width constraints after FZ transform
    fz_widths <- diff(boundaries)
    if (any(fz_widths < min_width_da * 0.9) || any(fz_widths > max_width_da * 1.1)) {
      warning("Variable+FZ: FZ transform violated width constraints. Falling back to fixed+FZ.")
      return(generate_fixed_windows_internal(mz_min, mz_max, n_windows,
                                             min_width_da, max_width_da,
                                             fz_offset = fz_offset))
    }
  }

  # Assemble windows from boundary array (continuity guaranteed by construction)
  windows <- assemble_windows_from_boundaries(boundaries)

  return(windows)
}

# =============================================================================
# Staggered Window Mode (2-Cycle Interleaved + Forbidden Zone)
# =============================================================================

# Average mass defect of amino acid residues (Da).
# Peptide precursors cannot exist at multiples of this increment,
# making these m/z positions ideal for isolation window boundaries.
OPTIMAL_INCREMENT <- 1.00045475

#' Calculate Forbidden Zone Edge (Mass Defect)
#'
#' Calculates the nearest forbidden zone m/z boundary using mass defect.
#' Peptide precursors cannot exist at these m/z values due to the mass defect
#' of amino acids, making them ideal for quadrupole isolation window boundaries.
#'
#' @param nominal_mz Nominal m/z value to shift to forbidden zone
#' @param fz_offset Constant for forbidden zone offset (0.25 standard, 0.18 phospho)
#'
#' @return Numeric, forbidden zone edge m/z value
#' @keywords internal
calc_forbidden_edge <- function(nominal_mz, fz_offset = 0.25) {
  round(ceiling(nominal_mz / OPTIMAL_INCREMENT) * OPTIMAL_INCREMENT + fz_offset, 4)
}

#' Integerize Boundary Array
#'
#' Rounds all boundaries to nearest integer, ensuring the first boundary
#' covers mz_min (floor) and the last covers mz_max (ceiling).
#' Always applied regardless of FZ setting to produce clean integer
#' boundaries. When FZ is active, integer inputs also guarantee
#' deterministic FZ transform (ceil(N / 1.00045475) = N for integers).
#'
#' @param boundaries Numeric vector of N+1 boundary positions
#' @param mz_min Minimum m/z to cover
#' @param mz_max Maximum m/z to cover
#'
#' @return Integer vector of length N+1
#' @keywords internal
integerize_boundaries <- function(boundaries, mz_min, mz_max) {
  boundaries <- round(boundaries)
  boundaries[1] <- floor(mz_min)
  boundaries[length(boundaries)] <- ceiling(mz_max)
  as.integer(boundaries)
}

#' Transform Boundary Array to Forbidden Zones
#'
#' Applies calc_forbidden_edge() to an entire boundary array at once.
#' Each boundary is shifted to the nearest mass defect forbidden zone
#' where peptide precursors cannot exist.
#'
#' @param boundaries Numeric vector of N+1 boundary positions
#' @param fz_offset Forbidden zone constant (0.25 standard, 0.18 phospho)
#'
#' @return Numeric vector of FZ-transformed boundaries
#' @keywords internal
transform_boundaries_to_fz <- function(boundaries, fz_offset = 0.25) {
  # Vectorized: calc_forbidden_edge already works on vectors
  round(ceiling(boundaries / OPTIMAL_INCREMENT) * OPTIMAL_INCREMENT + fz_offset, 4)
}

#' Assemble Windows from Boundary Array
#'
#' Creates a window tibble from an N+1 boundary array by pairing
#' adjacent elements: window\[i\] = (array\[i\], array\[i+1\]).
#' Continuity is guaranteed by construction: mz_start\[j\] == mz_end\[j-1\]
#' because both reference the same array element.
#'
#' @param boundaries Numeric vector of N+1 boundary positions
#'
#' @return Tibble with mz_start, mz_end, mz_center, window_width columns
#' @keywords internal
assemble_windows_from_boundaries <- function(boundaries) {
  n <- length(boundaries) - 1
  mz_start <- boundaries[1:n]
  mz_end <- boundaries[2:(n + 1)]
  tibble(
    mz_start = mz_start,
    mz_end = mz_end,
    mz_center = (mz_start + mz_end) / 2,
    window_width = mz_end - mz_start
  )
}

#' Generate Staggered Windows (Internal)
#'
#' Creates two interleaved acquisition cycles with 50% offset for demultiplexing.
#' Window boundaries are placed at mass defect-based forbidden zones where
#' peptide precursors cannot exist, maximizing quadrupole transmission efficiency.
#'
#' After computational demultiplexing (e.g., Skyline, SpectronautDIA),
#' the effective isolation width is halved without reducing scan speed.
#'
#' IMPORTANT: Staggered windows must NOT use margins (±0.5 m/z) as this
#' complicates the demultiplexing model.
#'
#' @param mz_min Minimum m/z for this RT bin
#' @param mz_max Maximum m/z for this RT bin
#' @param n_windows Target number of windows PER CYCLE
#' @param min_width_da Minimum window width in Da
#' @param max_width_da Maximum window width in Da
#' @param rt_bin_index Current RT bin index (1-based)
#' @param fz_offset Forbidden zone constant (0.25 standard, 0.18 phospho)
#'
#' @return Data frame with window specifications including `cycle` column (1 or 2)
#' @keywords internal
generate_staggered_windows_internal <- function(mz_min, mz_max, n_windows,
                                                 min_width_da, max_width_da,
                                                 rt_bin_index,
                                                 fz_offset = 0.25) {

  mz_range <- mz_max - mz_min

  # Use n_windows directly (do NOT recalculate) to guarantee consistent
  # window count across all RT bins — required for Loop Control N.
  nominal_width <- mz_range / n_windows

  # --- Helper: build one cycle using boundary-array-first architecture ---
  # Generates N+1 integer boundaries, FZ-transforms, assembles as adjacent pairs.
  # Continuity is guaranteed by construction (no chaining loop needed).
  build_cycle <- function(start_offset) {
    # Generate N+1 boundary positions with offset
    boundaries <- seq(mz_min + start_offset,
                      mz_min + start_offset + n_windows * nominal_width,
                      length.out = n_windows + 1)

    # Integerize for deterministic FZ transform
    boundaries <- integerize_boundaries(boundaries,
                                        mz_min + start_offset,
                                        mz_min + start_offset + n_windows * nominal_width)

    # Apply forbidden zone transform
    boundaries <- transform_boundaries_to_fz(boundaries, fz_offset)

    # Assemble windows from adjacent boundary pairs
    assemble_windows_from_boundaries(boundaries)
  }

  # --- Cycle 1: Base windows ---
  cycle1 <- build_cycle(start_offset = 0) %>%
    mutate(cycle = 1L, is_staggered = FALSE)

  # --- Cycle 2: 50% offset windows ---
  # Round offset to ensure integer boundaries
  offset <- round(nominal_width / 2)
  cycle2 <- build_cycle(start_offset = offset) %>%
    mutate(cycle = 2L, is_staggered = TRUE)

  # --- Combine both cycles ---
  windows <- bind_rows(cycle1, cycle2)

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

