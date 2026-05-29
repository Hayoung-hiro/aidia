# rt_binning.R - RT Binning Functions for Stage 3
#
# Purpose: Perform RT (retention time) binning/segmentation
#   Supports two modes:
#     - "fixed":    Equal-width bins (original behavior, default)
#     - "adaptive": KS-test change-point detection for density-aware bins
#
# Functions:
#   - perform_rt_binning_internal(): Dispatcher (backward-compatible)
#   - perform_fixed_rt_binning_internal(): Fixed-width binning
#   - perform_adaptive_rt_binning_internal(): KS-based adaptive binning
#   - apply_edge_handling(): Void-volume and wash-region edge correction
#   - get_rt_column(): Determine best RT column available in data
#   - calculate_auto_rt_bin_width(): Shiny UI helper for auto bin width calculation
#
# Dependencies: dplyr, stats (base R)


# =============================================================================
# RT Column Helper
# =============================================================================

#' Determine Best RT Column Available in Data
#'
#' Returns "RT.Apex" (computed in Stage 1 from midpoint of RT.Start and
#' RT.Stop). Falls back to "RT.Start" with a warning if RT.Apex is absent.
#'
#' @param precursor_data Data frame with RT columns
#' @return Character, column name to use for RT binning
#' @keywords internal
get_rt_column <- function(precursor_data) {
  if ("RT.Apex" %in% colnames(precursor_data)) return("RT.Apex")
  warning("RT.Apex not found, falling back to RT.Start")
  if ("RT.Start" %in% colnames(precursor_data)) return("RT.Start")
  stop("Neither RT.Apex nor RT.Start found in data")
}

# =============================================================================
# Dispatcher (Backward-Compatible)
# =============================================================================

#' Perform RT Binning (Internal Dispatcher)
#'
#' Routes to fixed or adaptive RT binning based on \code{rt_binning_mode}.
#' All new parameters have defaults, so existing callers that only pass
#' \code{precursor_data} and \code{rt_bin_width_min} continue to work.
#'
#' @param precursor_data Data frame with RT.Apex column (computed in Stage 1)
#' @param rt_bin_width_min Numeric, RT bin width in minutes (used by fixed mode)
#' @param rt_binning_mode Character, "fixed" (default) or "adaptive"
#' @param rt_column Character, which RT column to use. NULL = auto-detect via get_rt_column()
#' @param cpd_significance_level Numeric, KS-test p-value threshold (adaptive only, default 0.05)
#' @param cpd_min_bin_width Numeric, minimum bin width in minutes (adaptive only, default 1.0)
#' @param cpd_max_bin_width Numeric, maximum bin width in minutes (adaptive only, default 15.0)
#' @param cpd_min_precursors_per_bin Integer, minimum precursors per bin (adaptive only, default 50)
#' @param edge_void_buffer_min Numeric, void-volume buffer in minutes (default 0.5)
#' @param edge_wash_min_precursors Integer, merge last bin if fewer than this (default 30)
#'
#' @return List containing:
#'   - data: precursor_data with rt_group column added
#'   - stats: RT statistics per bin (rt_group, rt_start, rt_end, n_precursors, rt_segment_id)
#'   - n_bins: Number of bins created
#'   - rt_breaks: RT breakpoints
#'   - adaptive_info: NULL for fixed mode; list of KS diagnostics for adaptive mode
#'
#' @keywords internal
perform_rt_binning_internal <- function(precursor_data,
                                        rt_bin_width_min,
                                        rt_binning_mode = "fixed",
                                        rt_column = NULL,
                                        cpd_significance_level = 0.05,
                                        cpd_min_bin_width = 1.0,
                                        cpd_max_bin_width = 15.0,
                                        cpd_min_precursors_per_bin = 50,
                                        edge_void_buffer_min = 0.5,
                                        edge_wash_min_precursors = 30) {

  # Determine which RT column to use
  if (is.null(rt_column)) {
    rt_column <- get_rt_column(precursor_data)
  }

  # Dispatch to the appropriate binning function
  if (rt_binning_mode == "adaptive") {
    rt_result <- perform_adaptive_rt_binning_internal(
      precursor_data = precursor_data,
      rt_column = rt_column,
      cpd_significance_level = cpd_significance_level,
      cpd_min_bin_width = cpd_min_bin_width,
      cpd_max_bin_width = cpd_max_bin_width,
      cpd_min_precursors_per_bin = cpd_min_precursors_per_bin
    )
  } else {
    # Fixed mode: use RT.Apex as the single RT reference
    rt_result <- perform_fixed_rt_binning_internal(
      precursor_data = precursor_data,
      rt_bin_width_min = rt_bin_width_min
    )
  }

  # Apply edge handling to both modes
  rt_result <- apply_edge_handling(
    rt_result = rt_result,
    edge_void_buffer_min = edge_void_buffer_min,
    edge_wash_min_precursors = edge_wash_min_precursors
  )

  return(rt_result)
}

# =============================================================================
# Fixed RT Binning (Original Implementation)
# =============================================================================

#' Perform Fixed-Width RT Binning (Internal)
#'
#' Segments precursor data into equal-width RT bins using RT.Apex as the
#' single RT reference (computed in Stage 1 from midpoint of RT.Start/RT.Stop).
#'
#' @param precursor_data Data frame with RT.Apex column
#' @param rt_bin_width_min Numeric, RT bin width in minutes
#'
#' @return List containing data, stats, n_bins, rt_breaks, adaptive_info (NULL)
#' @keywords internal
perform_fixed_rt_binning_internal <- function(precursor_data, rt_bin_width_min) {

  # Get RT range using RT.Apex as single RT reference
  rt_range <- range(precursor_data$RT.Apex, na.rm = TRUE)

  # Guard: a single distinct RT value yields one break point, and cut() needs
  # at least two boundaries to form a valid interval. Expand by one bin width.
  if (rt_range[1] == rt_range[2]) {
    rt_range[2] <- rt_range[1] + rt_bin_width_min
  }

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
    precursor_data$RT.Apex,
    breaks = rt_breaks,
    labels = FALSE,
    include.lowest = TRUE
  )

  # Calculate RT statistics per group
  rt_stats <- precursor_data %>%
    group_by(rt_group) %>%
    summarise(
      rt_start = min(RT.Apex, na.rm = TRUE),
      rt_end = max(RT.Apex, na.rm = TRUE),
      n_precursors = n(),
      .groups = 'drop'
    ) %>%
    mutate(rt_segment_id = rt_group)

  n_bins <- nrow(rt_stats)

  list(
    data = precursor_data,
    stats = rt_stats,
    n_bins = n_bins,
    rt_breaks = rt_breaks,
    adaptive_info = NULL
  )
}

# =============================================================================
# Adaptive RT Binning (KS Change-Point Detection)
# =============================================================================

#' Perform Adaptive RT Binning Using KS Change-Point Detection (Internal)
#'
#' Creates RT bins at points where the m/z distribution changes significantly,
#' as detected by the Kolmogorov-Smirnov test on adjacent pre-bins.
#'
#' Algorithm:
#'   1. Divide RT range into 100 fine-grained pre-bins
#'   2. Run KS test on m/z distributions of each adjacent pre-bin pair
#'   3. Mark change points where p-value < significance threshold
#'   4. Enforce minimum/maximum bin width constraints
#'   5. Merge sparse bins (< min precursors)
#'   6. Assign final rt_group and compute stats
#'
#' @param precursor_data Data frame with RT and Precursor.Mz columns
#' @param rt_column Character, name of the RT column to use
#' @param cpd_significance_level Numeric, KS p-value threshold (default 0.05)
#' @param cpd_min_bin_width Numeric, minimum bin width in minutes (default 1.0)
#' @param cpd_max_bin_width Numeric, maximum bin width in minutes (default 15.0)
#' @param cpd_min_precursors_per_bin Integer, minimum precursors per bin (default 50)
#'
#' @return List containing data, stats, n_bins, rt_breaks, adaptive_info
#' @keywords internal
perform_adaptive_rt_binning_internal <- function(precursor_data,
                                                  rt_column = "RT.Apex",
                                                  cpd_significance_level = 0.05,
                                                  cpd_min_bin_width = 1.0,
                                                  cpd_max_bin_width = 15.0,
                                                  cpd_min_precursors_per_bin = 50) {

  rt_values <- precursor_data[[rt_column]]
  rt_range <- range(rt_values, na.rm = TRUE)

  # --- Step 1: Create 100 fine-grained pre-bins ---
  n_pre_bins <- 100
  pre_breaks <- seq(from = rt_range[1], to = rt_range[2], length.out = n_pre_bins + 1)
  pre_bin_centers <- (pre_breaks[-length(pre_breaks)] + pre_breaks[-1]) / 2

  precursor_data$.pre_bin <- cut(
    rt_values,
    breaks = pre_breaks,
    labels = FALSE,
    include.lowest = TRUE
  )

  # Collect m/z values per pre-bin
  mz_by_prebin <- split(precursor_data$Precursor.Mz, precursor_data$.pre_bin)

  # --- Step 2: KS test on adjacent pre-bin pairs ---
  n_pairs <- n_pre_bins - 1
  ks_statistics <- numeric(n_pairs)
  p_values <- numeric(n_pairs)

  for (i in seq_len(n_pairs)) {
    bin_a <- mz_by_prebin[[as.character(i)]]
    bin_b <- mz_by_prebin[[as.character(i + 1)]]

    # Skip if either bin is empty or has too few observations
    if (is.null(bin_a) || is.null(bin_b) || length(bin_a) < 2 || length(bin_b) < 2) {
      ks_statistics[i] <- 0
      p_values[i] <- 1
      next
    }

    ks_result <- stats::ks.test(bin_a, bin_b)
    ks_statistics[i] <- ks_result$statistic
    p_values[i] <- ks_result$p.value
  }

  # --- Step 3: Identify change points ---
  change_point_indices <- which(p_values < cpd_significance_level)

  # Fallback: if no change points detected, use fixed-width binning
  if (length(change_point_indices) == 0) {
    warning("No significant m/z distribution changes detected; falling back to fixed-width RT binning")
    # Clean up temporary column
    precursor_data$.pre_bin <- NULL

    gradient_length <- rt_range[2] - rt_range[1]
    fallback_width <- gradient_length / 10
    fallback_width <- max(cpd_min_bin_width, min(fallback_width, cpd_max_bin_width))

    result <- perform_fixed_rt_binning_internal(precursor_data, fallback_width)
    result$adaptive_info <- list(
      ks_statistics = ks_statistics,
      p_values = p_values,
      pre_bin_centers = pre_bin_centers,
      change_point_positions = numeric(0),
      n_change_points = 0L,
      significance_level = cpd_significance_level,
      fallback = TRUE
    )
    return(result)
  }

  # Convert change point indices to RT positions (boundary between pre-bins)
  change_point_positions <- pre_breaks[change_point_indices + 1]

  # --- Step 4: Enforce bin constraints ---
  change_point_positions <- enforce_bin_constraints(
    change_points = change_point_positions,
    p_values = p_values,
    change_indices = change_point_indices,
    rt_range = rt_range,
    min_bin_width = cpd_min_bin_width,
    max_bin_width = cpd_max_bin_width
  )

  # Build final breaks: rt_min, change_points, rt_max
  rt_breaks <- sort(unique(c(rt_range[1], change_point_positions, rt_range[2])))

  # --- Step 5: Assign groups and merge sparse bins ---
  precursor_data$rt_group <- cut(
    rt_values,
    breaks = rt_breaks,
    labels = FALSE,
    include.lowest = TRUE
  )

  merge_result <- merge_sparse_bins(
    precursor_data = precursor_data,
    rt_breaks = rt_breaks,
    rt_column = rt_column,
    min_precursors = cpd_min_precursors_per_bin
  )
  precursor_data <- merge_result$data
  rt_breaks <- merge_result$rt_breaks

  # --- Step 6: Compute final stats ---
  rt_stats <- precursor_data %>%
    group_by(rt_group) %>%
    summarise(
      rt_start = min(.data[[rt_column]], na.rm = TRUE),
      rt_end = max(.data[[rt_column]], na.rm = TRUE),
      n_precursors = n(),
      .groups = 'drop'
    ) %>%
    mutate(rt_segment_id = rt_group)

  n_bins <- nrow(rt_stats)

  # Clean up temporary column
  precursor_data$.pre_bin <- NULL

  adaptive_info <- list(
    ks_statistics = ks_statistics,
    p_values = p_values,
    pre_bin_centers = pre_bin_centers,
    change_point_positions = change_point_positions,
    n_change_points = length(change_point_positions),
    significance_level = cpd_significance_level,
    fallback = FALSE
  )

  list(
    data = precursor_data,
    stats = rt_stats,
    n_bins = n_bins,
    rt_breaks = rt_breaks,
    adaptive_info = adaptive_info
  )
}

# =============================================================================
# Constraint Enforcement
# =============================================================================

#' Enforce Minimum and Maximum Bin Width Constraints
#'
#' Merges change points that are closer than min_bin_width (keeping the one
#' with the lower p-value) and splits bins that exceed max_bin_width.
#'
#' @param change_points Numeric vector of change point RT positions
#' @param p_values Numeric vector of p-values for all pre-bin pairs
#' @param change_indices Integer vector of indices into p_values for the change points
#' @param rt_range Numeric vector of length 2
#' @param min_bin_width Numeric, minimum bin width in minutes
#' @param max_bin_width Numeric, maximum bin width in minutes
#'
#' @return Numeric vector of adjusted change point positions
#' @keywords internal
enforce_bin_constraints <- function(change_points,
                                    p_values,
                                    change_indices,
                                    rt_range,
                                    min_bin_width,
                                    max_bin_width) {

  # --- Merge too-close change points (only when 2+ points) ---
  if (length(change_points) >= 2) {
  # Greedily scan left-to-right: keep the point with the smaller p-value
  kept <- logical(length(change_points))
  kept[1] <- TRUE
  last_kept <- 1

  for (i in 2:length(change_points)) {
    if ((change_points[i] - change_points[last_kept]) < min_bin_width) {
      # Too close - keep the one with the lower p-value
      if (p_values[change_indices[i]] < p_values[change_indices[last_kept]]) {
        kept[last_kept] <- FALSE
        kept[i] <- TRUE
        last_kept <- i
      }
      # else: discard the current point (kept[i] stays FALSE)
    } else {
      kept[i] <- TRUE
      last_kept <- i
    }
  }
    change_points <- change_points[kept]
  }

  # --- Split bins wider than max_bin_width ---
  all_boundaries <- c(rt_range[1], change_points, rt_range[2])
  new_change_points <- c()

  for (i in seq_len(length(all_boundaries) - 1)) {
    bin_start <- all_boundaries[i]
    bin_end <- all_boundaries[i + 1]
    bin_width <- bin_end - bin_start

    if (bin_width > max_bin_width) {
      # Add midpoint splits until each sub-bin is within max_bin_width
      n_splits <- ceiling(bin_width / max_bin_width)
      split_points <- seq(bin_start, bin_end, length.out = n_splits + 1)
      # Exclude the endpoints (they are already boundaries)
      new_change_points <- c(new_change_points, split_points[-c(1, length(split_points))])
    }
  }

  change_points <- sort(unique(c(change_points, new_change_points)))
  return(change_points)
}

# =============================================================================
# Sparse Bin Merging
# =============================================================================

#' Merge Sparse Bins (Below Minimum Precursor Count)
#'
#' If any bin has fewer than \code{min_precursors} precursors, merge it with
#' the adjacent bin that has fewer precursors. Iterates until all bins meet
#' the threshold or no more merges are possible.
#'
#' @param precursor_data Data frame with rt_group column
#' @param rt_breaks Numeric vector of break points
#' @param rt_column Character, name of the RT column
#' @param min_precursors Integer, minimum precursors per bin
#'
#' @return List with updated data and rt_breaks
#' @keywords internal
merge_sparse_bins <- function(precursor_data, rt_breaks, rt_column, min_precursors) {

  max_iterations <- length(rt_breaks)  # Safety limit

  for (iter in seq_len(max_iterations)) {
    bin_counts <- table(precursor_data$rt_group)
    sparse_bins <- as.integer(names(bin_counts[bin_counts < min_precursors]))

    if (length(sparse_bins) == 0) break

    n_bins_current <- length(rt_breaks) - 1
    if (n_bins_current <= 1) break  # Can't merge further

    # Find the first sparse bin and merge it
    target_bin <- sparse_bins[1]

    if (target_bin == 1) {
      # Merge with next bin: remove the break between bin 1 and bin 2
      rt_breaks <- rt_breaks[-(target_bin + 1)]
    } else if (target_bin == n_bins_current) {
      # Merge with previous bin: remove the break between last two bins
      rt_breaks <- rt_breaks[-target_bin]
    } else {
      # Merge with the adjacent bin that has fewer precursors
      prev_count <- bin_counts[as.character(target_bin - 1)]
      next_count <- bin_counts[as.character(target_bin + 1)]

      if (is.na(prev_count)) prev_count <- Inf
      if (is.na(next_count)) next_count <- Inf

      if (prev_count <= next_count) {
        rt_breaks <- rt_breaks[-target_bin]
      } else {
        rt_breaks <- rt_breaks[-(target_bin + 1)]
      }
    }

    # Re-assign groups with updated breaks
    precursor_data$rt_group <- cut(
      precursor_data[[rt_column]],
      breaks = rt_breaks,
      labels = FALSE,
      include.lowest = TRUE
    )
  }

  list(data = precursor_data, rt_breaks = rt_breaks)
}

# =============================================================================
# Edge Handling
# =============================================================================

#' Apply Edge Handling (Void Volume + Wash Region)
#'
#' Adjusts RT bin boundaries at the gradient edges:
#'   - Void volume: extends the first break by a buffer to capture early-eluting peptides
#'   - Wash region: merges the last bin with the previous if it is too sparse
#'
#' @param rt_result List from a binning function (data, stats, n_bins, rt_breaks, ...)
#' @param edge_void_buffer_min Numeric, minutes to subtract from the first break (default 0.5)
#' @param edge_wash_min_precursors Integer, merge last bin if fewer precursors (default 30)
#'
#' @return Updated rt_result list
#' @keywords internal
apply_edge_handling <- function(rt_result,
                                edge_void_buffer_min = 0.5,
                                edge_wash_min_precursors = 30) {

  rt_breaks <- rt_result$rt_breaks
  precursor_data <- rt_result$data
  n_bins <- rt_result$n_bins

  # Skip edge handling if we have fewer than 2 bins

  if (n_bins < 2) return(rt_result)

  modified <- FALSE

  # --- Void volume buffer ---
  if (edge_void_buffer_min > 0) {
    rt_breaks[1] <- rt_breaks[1] - edge_void_buffer_min
    modified <- TRUE
  }

  # --- Wash region: merge last bin if too sparse ---
  if (length(rt_breaks) > 2) {
    last_bin_count <- sum(rt_result$stats$n_precursors[rt_result$stats$rt_group == n_bins])
    if (length(last_bin_count) > 0 && last_bin_count < edge_wash_min_precursors) {
      # Remove the second-to-last break to merge last two bins
      rt_breaks <- rt_breaks[-(length(rt_breaks) - 1)]
      modified <- TRUE
    }
  }

  if (!modified) return(rt_result)

  # Determine RT column for re-assignment (RT.Apex is always the primary reference)
  rt_col <- get_rt_column(precursor_data)

  # Re-assign rt_group with adjusted breaks
  precursor_data$rt_group <- cut(
    precursor_data[[rt_col]],
    breaks = rt_breaks,
    labels = FALSE,
    include.lowest = TRUE
  )

  # Recalculate stats
  rt_stats <- precursor_data %>%
    group_by(rt_group) %>%
    summarise(
      rt_start = min(.data[[rt_col]], na.rm = TRUE),
      rt_end = max(.data[[rt_col]], na.rm = TRUE),
      n_precursors = n(),
      .groups = 'drop'
    ) %>%
    mutate(rt_segment_id = rt_group)

  rt_result$data <- precursor_data
  rt_result$stats <- rt_stats
  rt_result$n_bins <- nrow(rt_stats)
  rt_result$rt_breaks <- rt_breaks

  return(rt_result)
}

# =============================================================================
# Auto RT Bin Width Calculation (for Shiny UI)
# =============================================================================

#' Calculate Auto RT Bin Width
#'
#' Automatically calculates optimal RT bin width based on gradient length
#' and m/z optimization strategy. Used by Shiny "Fixed" mode to determine
#' a sensible bin width without user input.
#'
#' Note: This is NOT related to KS adaptive binning. It is a simple formula
#' that divides gradient length by a strategy-dependent target bin count.
#'
#' @param rt_range Numeric vector of length 2, c(min_rt, max_rt) in minutes
#' @param mz_strategy Character, m/z optimization strategy ("greedy", "quantile", etc.)
#' @param target_min_bins Integer, minimum number of bins to create (default: 5)
#' @return List with bin_width and n_bins
#' @export
calculate_auto_rt_bin_width <- function(rt_range,
                                            mz_strategy = "greedy",
                                            target_min_bins = 5) {

  gradient_length <- rt_range[2] - rt_range[1]

  # Strategy-specific adjustments
  if (mz_strategy %in% c("greedy", "kde")) {
    # GLOBAL strategies - can use wider bins
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

