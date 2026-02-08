# module3d_window_generation.R - Phase 3D: Window Generation (Per-RT-Bin Architecture)
#
# NEW ARCHITECTURE (2025-10-17):
# - Each RT bin independently generates n_windows
# - Total windows = n_bins × n_windows (e.g., 22 bins × 200 = 4,400 windows)
# - Method (fixed/variable) applies per RT bin
# - Overlap is optional (default: OFF)
#
# Purpose: Generate RT-dependent isolation windows
#   1. Fixed Method: Equal-width windows per RT bin
#   2. Variable Method: Density-based adaptive windows per RT bin (quantile-based)
#   3. Overlap: Optional post-processing expansion
#
# Input: RTBinningResult (Phase 3B) + MzRangeResult (Phase 3C)
# Output: WindowGenerationResult with isolation windows

library(dplyr)

# =============================================================================
# Core Window Generation Functions (Per-RT-Bin)
# =============================================================================

#' Create Fixed-Width Windows for a Single RT Bin
#'
#' Generates equal-width windows with min/max width constraints.
#' Example: n_windows=200, mz_range=400-600 Da (200 Da span)
#'   - ideal_width = 200/200 = 1.0 Da
#'   - If min_width_da=2, actual_width = 2.0 Da → 100 windows
#'
#' @param mz_min Numeric, minimum m/z boundary for this RT bin
#' @param mz_max Numeric, maximum m/z boundary for this RT bin
#' @param n_windows Integer, target window count for this bin
#' @param min_width_da Numeric, minimum window width constraint (default: 2)
#' @param max_width_da Numeric, maximum window width constraint (default: 80)
#'
#' @return List with:
#'   - windows: tibble with window boundaries
#'   - actual_count: actual number of windows generated
#'   - actual_width: actual window width used
#'
#' @export
create_fixed_windows <- function(
  mz_min,
  mz_max,
  n_windows,
  min_width_da = 2,
  max_width_da = 80
) {

  mz_range <- mz_max - mz_min

  # Calculate ideal window width
  ideal_width <- mz_range / n_windows

  # Apply constraints
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

  # Ensure at least 1 window
  actual_count <- max(1, actual_count)

  # Generate windows
  windows_list <- list()
  for (i in 1:actual_count) {
    mz_start <- mz_min + (i - 1) * actual_width
    mz_end <- min(mz_start + actual_width, mz_max)

    windows_list[[i]] <- data.frame(
      mz_start = mz_start,
      mz_end = mz_end,
      mz_center = (mz_start + mz_end) / 2,
      window_width = mz_end - mz_start
    )
  }

  windows <- bind_rows(windows_list)

  return(list(
    windows = windows,
    actual_count = actual_count,
    actual_width = actual_width
  ))
}


#' Create Variable-Width Windows for a Single RT Bin
#'
#' Generates density-based adaptive windows that flatten precursor distribution.
#' Uses quantile-based approach to create windows with similar precursor counts.
#'
#' @param precursor_mz Numeric vector, m/z values of precursors in this RT bin
#' @param mz_min Numeric, minimum m/z boundary for this RT bin
#' @param mz_max Numeric, maximum m/z boundary for this RT bin
#' @param n_windows Integer, target window count for this bin
#' @param min_width_da Numeric, minimum window width constraint (default: 2)
#' @param max_width_da Numeric, maximum window width constraint (default: 80)
#'
#' @return List with:
#'   - windows: tibble with window boundaries
#'   - actual_count: actual number of windows generated
#'
#' @export
create_variable_windows <- function(
  precursor_mz,
  mz_min,
  mz_max,
  n_windows,
  min_width_da = 2,
  max_width_da = 80
) {

  # Filter precursors within range
  precursor_mz <- precursor_mz[precursor_mz >= mz_min & precursor_mz <= mz_max]

  if (length(precursor_mz) == 0) {
    # No precursors → fallback to fixed windows
    return(create_fixed_windows(mz_min, mz_max, n_windows, min_width_da, max_width_da))
  }

  # Sort precursors
  precursor_mz <- sort(precursor_mz)

  # Calculate quantile breakpoints for equal-precursor windows
  quantile_probs <- seq(0, 1, length.out = n_windows + 1)
  quantile_boundaries <- quantile(precursor_mz, probs = quantile_probs, na.rm = TRUE)

  # Constrain boundaries to mz_min/mz_max
  quantile_boundaries[1] <- mz_min
  quantile_boundaries[length(quantile_boundaries)] <- mz_max

  # Generate windows with width constraints
  windows_list <- list()
  valid_windows <- 0

  for (i in 1:(length(quantile_boundaries) - 1)) {
    mz_start <- quantile_boundaries[i]
    mz_end <- quantile_boundaries[i + 1]
    window_width <- mz_end - mz_start

    # Apply width constraints
    if (window_width < min_width_da) {
      # Expand to min_width_da (but not beyond mz_max)
      mz_end <- min(mz_start + min_width_da, mz_max)
      window_width <- mz_end - mz_start
    } else if (window_width > max_width_da) {
      # Split into multiple windows
      n_splits <- ceiling(window_width / max_width_da)
      split_width <- window_width / n_splits

      for (j in 1:n_splits) {
        split_start <- mz_start + (j - 1) * split_width
        split_end <- min(split_start + split_width, mz_end)

        valid_windows <- valid_windows + 1
        windows_list[[valid_windows]] <- data.frame(
          mz_start = split_start,
          mz_end = split_end,
          mz_center = (split_start + split_end) / 2,
          window_width = split_end - split_start
        )
      }
      next
    }

    # Valid window
    valid_windows <- valid_windows + 1
    windows_list[[valid_windows]] <- data.frame(
      mz_start = mz_start,
      mz_end = mz_end,
      mz_center = (mz_start + mz_end) / 2,
      window_width = window_width
    )
  }

  windows <- bind_rows(windows_list)

  return(list(
    windows = windows,
    actual_count = nrow(windows)
  ))
}


#' Apply Overlap to Window Boundaries
#'
#' Post-processing function to expand window boundaries by specified percentage.
#' Default: OFF (overlap_percentage = 0).
#'
#' @param windows Tibble, window boundaries (must have mz_start, mz_end, window_width)
#' @param overlap_percentage Numeric, overlap percentage (0-50, default: 0)
#' @param mz_min Numeric, minimum m/z constraint (to prevent overflow)
#' @param mz_max Numeric, maximum m/z constraint (to prevent overflow)
#'
#' @return Tibble with expanded window boundaries
#'
#' @export
apply_overlap <- function(
  windows,
  overlap_percentage = 0,
  mz_min,
  mz_max
) {

  if (overlap_percentage <= 0) {
    # No overlap, return as-is
    windows$overlap_prev <- 0
    windows$overlap_next <- 0
    return(windows)
  }

  overlap_fraction <- overlap_percentage / 100

  # Calculate overlap amounts for each window
  windows$overlap_da <- windows$window_width * overlap_fraction

  # Expand boundaries (symmetrical expansion)
  windows$mz_start_expanded <- windows$mz_start - windows$overlap_da / 2
  windows$mz_end_expanded <- windows$mz_end + windows$overlap_da / 2

  # Constrain to mz_min/mz_max
  windows$mz_start_expanded <- pmax(windows$mz_start_expanded, mz_min)
  windows$mz_end_expanded <- pmin(windows$mz_end_expanded, mz_max)

  # Calculate actual overlaps with neighbors
  windows$overlap_prev <- 0
  windows$overlap_next <- 0

  for (i in 1:nrow(windows)) {
    if (i > 1) {
      overlap_prev <- max(0, windows$mz_end_expanded[i - 1] - windows$mz_start_expanded[i])
      windows$overlap_prev[i] <- overlap_prev
    }

    if (i < nrow(windows)) {
      overlap_next <- max(0, windows$mz_end_expanded[i] - windows$mz_start_expanded[i + 1])
      windows$overlap_next[i] <- overlap_next
    }
  }

  # Update window boundaries and width
  windows$mz_start <- windows$mz_start_expanded
  windows$mz_end <- windows$mz_end_expanded
  windows$mz_center <- (windows$mz_start + windows$mz_end) / 2
  windows$window_width <- windows$mz_end - windows$mz_start

  # Clean up temporary columns
  windows <- windows %>%
    select(-overlap_da, -mz_start_expanded, -mz_end_expanded)

  return(windows)
}


#' Generate Windows for a Single RT Bin
#'
#' Orchestrator function that generates windows for a single RT bin using
#' specified method (fixed/variable) and optional overlap.
#'
#' @param bin_data Tibble, precursor data for this RT bin (must have Precursor.Mz)
#' @param mz_min Numeric, minimum m/z boundary for this RT bin
#' @param mz_max Numeric, maximum m/z boundary for this RT bin
#' @param rt_start Numeric, RT bin start time (minutes)
#' @param rt_end Numeric, RT bin end time (minutes)
#' @param bin_id Integer, RT bin ID
#' @param n_windows Integer, target window count for this bin
#' @param method Character, "fixed" or "variable"
#' @param min_width_da Numeric, minimum window width (default: 2)
#' @param max_width_da Numeric, maximum window width (default: 80)
#' @param overlap_percentage Numeric, overlap percentage (default: 0, OFF)
#'
#' @return Tibble with complete window information for this RT bin
#'
#' @export
generate_windows_for_rt_bin <- function(
  bin_data,
  mz_min,
  mz_max,
  rt_start,
  rt_end,
  bin_id,
  n_windows,
  method = "variable",
  min_width_da = 2,
  max_width_da = 80,
  overlap_percentage = 0
) {

  # Step 1: Generate base windows
  if (method == "fixed") {
    result <- create_fixed_windows(mz_min, mz_max, n_windows, min_width_da, max_width_da)
  } else if (method == "variable") {
    precursor_mz <- bin_data$Precursor.Mz
    result <- create_variable_windows(precursor_mz, mz_min, mz_max, n_windows, min_width_da, max_width_da)
  } else {
    stop(sprintf("Unknown method: %s. Use 'fixed' or 'variable'", method))
  }

  windows <- result$windows

  # Step 2: Apply overlap (if requested)
  if (overlap_percentage > 0) {
    windows <- apply_overlap(windows, overlap_percentage, mz_min, mz_max)
  } else {
    windows$overlap_prev <- 0
    windows$overlap_next <- 0
  }

  # Step 3: Count precursors in each window
  windows$n_precursors <- 0
  for (i in 1:nrow(windows)) {
    in_window <- bin_data$Precursor.Mz >= windows$mz_start[i] &
                 bin_data$Precursor.Mz < windows$mz_end[i]
    windows$n_precursors[i] <- sum(in_window)
  }

  # Step 4: Add RT bin information
  windows$rt_segment_id <- bin_id
  windows$rt_start <- rt_start
  windows$rt_end <- rt_end

  # Step 5: Reorder columns
  windows <- windows %>%
    select(rt_segment_id, rt_start, rt_end,
           mz_start, mz_end, mz_center, window_width,
           n_precursors, overlap_prev, overlap_next)

  return(windows)
}


# =============================================================================
# Main Window Generation Function
# =============================================================================

#' Generate Isolation Windows (Phase 3D Main Function)
#'
#' NEW ARCHITECTURE (Per-RT-Bin Window Generation):
#' - Each RT bin independently generates n_windows
#' - Total windows = n_bins × n_windows
#' - Method (fixed/variable) applies to each RT bin separately
#' - Overlap is optional (default: OFF)
#'
#' @param rt_binning_result RTBinningResult from Phase 3B
#' @param mz_range_result MzRangeResult from Phase 3C
#' @param window_type Character, "fixed" or "variable"
#' @param n_windows Integer, target window count PER RT BIN
#' @param min_width_da Numeric, minimum window width (default: 2)
#' @param max_width_da Numeric, maximum window width (default: 80)
#' @param overlap_percentage Numeric, overlap % (default: 0, OFF)
#'
#' @return WindowGenerationResult object
#' @export
generate_isolation_windows <- function(
  rt_binning_result,
  mz_range_result,
  window_type = "variable",
  n_windows = 100,
  min_width_da = 2,
  max_width_da = 80,
  overlap_percentage = 0
) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   Phase 3D: Window Generation (Per-RT-Bin)   ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  # === INSIGHT: Input Validation & Parameters ===
  cat("╔═══════════════════════════════════════════════╗\n")
  cat("║   Input Validation                           ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  # Validate window_type
  valid_types <- c("fixed", "variable")
  if (!window_type %in% valid_types) {
    stop(sprintf("Invalid window_type: %s. Must be one of: %s",
                 window_type, paste(valid_types, collapse = ", ")))
  }
  cat(sprintf("✓ Window type: %s (valid)\n", window_type))

  # Validate and extract RT binning data
  if (is.null(rt_binning_result$rt_group_stats)) {
    stop("Missing rt_group_stats in rt_binning_result")
  }
  rt_group_stats <- rt_binning_result$rt_group_stats
  cat(sprintf("✓ RT binning: %d bins detected\n", nrow(rt_group_stats)))

  # Validate and extract m/z range data
  if (is.null(mz_range_result$mz_ranges)) {
    stop("Missing mz_ranges in mz_range_result")
  }
  mz_ranges <- mz_range_result$mz_ranges
  cat(sprintf("✓ m/z ranges: %d segments detected\n", nrow(mz_ranges)))

  # Validate and extract precursor data
  if (is.null(rt_binning_result$data$data)) {
    stop("Missing precursor data in rt_binning_result")
  }
  precursor_data <- rt_binning_result$data$data
  cat(sprintf("✓ Precursor data: %s precursors available\n",
              format(nrow(precursor_data), big.mark = ",")))

  n_bins <- nrow(rt_group_stats)

  # Validate consistency
  if (nrow(rt_group_stats) != nrow(mz_ranges)) {
    warning(sprintf("RT bins (%d) != m/z segments (%d). Will match by rt_segment_id.",
                    nrow(rt_group_stats), nrow(mz_ranges)))
  }

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   Window Generation Parameters               ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  cat(sprintf("Method:                  %s\n", window_type))
  cat(sprintf("Target windows/RT bin:   %d\n", n_windows))
  cat(sprintf("Number of RT bins:       %d\n", n_bins))
  cat(sprintf("Expected total windows:  %d (= %d bins × %d windows/bin)\n",
              n_bins * n_windows, n_bins, n_windows))
  cat(sprintf("Width constraints:       %.1f - %.1f Da\n", min_width_da, max_width_da))
  if (overlap_percentage > 0) {
    cat(sprintf("Overlap:                 %.1f%%\n", overlap_percentage))
  } else {
    cat("Overlap:                 OFF (0%)\n")
  }
  cat("\n")

  # === Step 1: Generate Windows for Each RT Bin ===
  cat("Step 1: Generating windows per RT bin...\n")

  all_windows_list <- list()
  window_id_global <- 1

  for (i in 1:n_bins) {
    rt_bin <- rt_group_stats[i, ]
    mz_bin <- mz_ranges %>% filter(rt_segment_id == i)

    if (nrow(mz_bin) == 0) {
      cat(sprintf("  ⚠️  RT bin %d: No m/z range defined, skipping\n", i))
      next
    }

    # Get precursors for this RT bin
    bin_precursors <- precursor_data %>%
      filter(rt_group == i)

    # Generate windows for this bin
    bin_windows <- generate_windows_for_rt_bin(
      bin_data = bin_precursors,
      mz_min = mz_bin$mz_min[1],
      mz_max = mz_bin$mz_max[1],
      rt_start = rt_bin$rt_start,
      rt_end = rt_bin$rt_end,
      bin_id = i,
      n_windows = n_windows,
      method = window_type,
      min_width_da = min_width_da,
      max_width_da = max_width_da,
      overlap_percentage = overlap_percentage
    )

    # Add global window IDs
    bin_windows$window_id <- window_id_global:(window_id_global + nrow(bin_windows) - 1)
    window_id_global <- window_id_global + nrow(bin_windows)

    all_windows_list[[i]] <- bin_windows

    cat(sprintf("  ✓ RT bin %d: Generated %d windows (%.1f-%.1f min, %.1f-%.1f Da)\n",
                i, nrow(bin_windows),
                rt_bin$rt_start, rt_bin$rt_end,
                mz_bin$mz_min[1], mz_bin$mz_max[1]))
  }

  # Combine all windows
  windows <- bind_rows(all_windows_list)

  cat(sprintf("\n  Total windows generated: %d\n", nrow(windows)))

  # === Step 2: Calculate Statistics ===
  cat("\nStep 2: Calculating statistics...\n")
  statistics <- calculate_window_statistics(windows, n_bins * n_windows)

  # === Step 3: Analyze Coverage ===
  cat("\nStep 3: Analyzing coverage...\n")
  coverage <- analyze_precursor_coverage(
    windows, rt_binning_result, mz_range_result
  )

  # === Step 4: Package Results ===
  cat("\nStep 4: Packaging results...\n")

  # Determine generation method
  generation_method <- if (window_type == "fixed") {
    "fixed_width_per_rt_bin"
  } else {
    "density_based_per_rt_bin"
  }

  allocation_method <- if (overlap_percentage > 0) {
    "per_rt_bin_with_overlap"
  } else {
    "per_rt_bin"
  }

  result <- structure(
    list(
      windows = windows,

      statistics = statistics,

      coverage_analysis = coverage,

      parameters = list(
        window_type = window_type,
        n_windows_per_bin = n_windows,
        n_bins = n_bins,
        total_windows_target = n_bins * n_windows,
        min_width_da = min_width_da,
        max_width_da = max_width_da,
        overlap_percentage = overlap_percentage
      ),

      metadata = list(
        generation_method = generation_method,
        allocation_method = allocation_method,
        generation_timestamp = Sys.time()
      )
    ),
    class = c("WindowGenerationResult", "list")
  )

  cat("\n═══════════════════════════════════════════════\n")
  cat(" Phase 3D Complete (Per-RT-Bin Architecture)\n")
  cat("═══════════════════════════════════════════════\n")
  cat(sprintf("✓ Generated %d windows\n", nrow(windows)))
  cat(sprintf("  Target: %d bins × %d windows/bin = %d total\n",
              n_bins, n_windows, n_bins * n_windows))
  cat(sprintf("  Deviation: %.1f%%\n",
              100 * abs(nrow(windows) - n_bins * n_windows) / (n_bins * n_windows)))
  cat(sprintf("  Coverage: %.1f%% (%d/%d precursors)\n",
              coverage$coverage_percentage,
              coverage$covered_precursors,
              coverage$total_precursors))
  cat(sprintf("  Window width: %.1f ± %.1f Da (range: %.1f - %.1f)\n",
              statistics$window_width_mean,
              statistics$window_width_sd,
              statistics$min_window_width,
              statistics$max_window_width))
  cat(sprintf("  Precursors/window: %.1f ± %.1f (CV: %.2f)\n",
              statistics$mean_precursors_per_window,
              statistics$sd_precursors_per_window,
              statistics$cv_precursors))

  return(result)
}

# =============================================================================
# Deprecated Functions (Old Architecture - Do Not Use)
# =============================================================================
#
# NOTE: The following functions use the old architecture where n_windows
# is distributed ACROSS all RT bins. They are kept for backward compatibility
# but should NOT be used in new code. Use generate_isolation_windows() instead.
#
# Old architecture: generate_fixed_windows(), generate_overlapped_windows()
# New architecture: generate_isolation_windows() with per-RT-bin window generation
#
# =============================================================================

# =============================================================================
# Helper Functions
# =============================================================================

#' Calculate Window Statistics
#'
#' @param windows Tibble of generated windows
#' @param target_windows Target window count
#'
#' @return List with statistics
calculate_window_statistics <- function(windows, target_windows) {
  list(
    total_windows = nrow(windows),
    target_windows = target_windows,
    mean_precursors_per_window = mean(windows$n_precursors, na.rm = TRUE),
    sd_precursors_per_window = sd(windows$n_precursors, na.rm = TRUE),
    cv_precursors = sd(windows$n_precursors, na.rm = TRUE) /
                    mean(windows$n_precursors, na.rm = TRUE),
    min_window_width = min(windows$window_width, na.rm = TRUE),
    max_window_width = max(windows$window_width, na.rm = TRUE),
    window_width_mean = mean(windows$window_width, na.rm = TRUE),
    window_width_sd = sd(windows$window_width, na.rm = TRUE),
    total_overlap_da = sum(windows$overlap_prev + windows$overlap_next, na.rm = TRUE) / 2
  )
}

#' Analyze Precursor Coverage
#'
#' @param windows Tibble of windows
#' @param rt_binning_result RTBinningResult
#' @param mz_range_result MzRangeResult
#'
#' @return List with coverage analysis
analyze_precursor_coverage <- function(
  windows,
  rt_binning_result,
  mz_range_result
) {

  precursor_data <- rt_binning_result$data$data
  total_precursors <- nrow(precursor_data)

  # Check which precursors are covered by at least one window
  precursor_data$covered <- FALSE

  for (i in 1:nrow(windows)) {
    window <- windows[i, ]

    # Find precursors in this window's RT segment and m/z range
    in_window <- precursor_data$rt_group == window$rt_segment_id &
                 precursor_data$Precursor.Mz >= window$mz_start &
                 precursor_data$Precursor.Mz < window$mz_end

    precursor_data$covered[in_window] <- TRUE
  }

  covered_precursors <- sum(precursor_data$covered)
  coverage_ratio <- covered_precursors / total_precursors

  # Identify uncovered regions (simplified)
  uncovered_regions <- tibble()

  list(
    total_precursors = total_precursors,
    covered_precursors = covered_precursors,
    coverage_ratio = coverage_ratio,
    coverage_percentage = coverage_ratio * 100,
    uncovered_regions = uncovered_regions
  )
}

#' Convert Phase 3B output to old RT binning format
#'
#' Helper function to convert simplified Phase 3B output to format expected by
#' existing R/window_generator.R functions
#'
#' @param rt_binning_result RTBinningResult from Phase 3B (simplified)
#'
#' @return rt_binning_result in old Module 2 format
convert_phase3b_to_old_format <- function(rt_binning_result) {

  # Extract data
  precursor_data <- rt_binning_result$data$data
  rt_group_stats <- rt_binning_result$rt_group_stats

  # Calculate n_bins (CRITICAL: window_generator.R expects this field)
  n_bins <- nrow(rt_group_stats)

  # Rename columns to old format
  # NOTE: window_generator.R uses "Precursor.Mz" not "mz", so only rename rt_group
  precursor_data <- precursor_data %>%
    rename(
      rt_bin = rt_group
    )

  # Create old-style rt_segments
  rt_segments <- rt_group_stats %>%
    mutate(
      segment_id = row_number(),
      rt_start_min = rt_start,
      rt_end_min = rt_end
    ) %>%
    select(segment_id, rt_start_min, rt_end_min, n_precursors)

  # Create old format structure with ALL required fields
  old_format <- list(
    data = precursor_data,
    rt_segments = rt_segments,
    n_bins = n_bins,  # CRITICAL: Required by window_generator.R line 163
    parameters = rt_binning_result$parameters,
    metadata = list(
      method = "time_unit",
      converted_from_phase3b = TRUE
    )
  )

  return(old_format)
}

#' Convert MzRangeResult to boundary_result format
#'
#' Helper function to convert Phase 3C output to format expected by
#' existing R/window_generator.R functions
#'
#' @param mz_range_result MzRangeResult from Phase 3C
#'
#' @return boundary_result in Module 3 format
convert_mz_range_to_boundary_format <- function(mz_range_result) {

  # Create boundaries tibble matching Module 3 format
  boundaries <- mz_range_result$mz_ranges %>%
    mutate(
      rt_bin = rt_segment_id,
      mz_min_smooth = mz_min,
      mz_max_smooth = mz_max,
      mz_range = mz_range_width
    ) %>%
    select(rt_bin, mz_min_smooth, mz_max_smooth, mz_range)

  # Create boundary_result structure
  boundary_result <- list(
    method = "dynamic",
    boundaries = boundaries,
    rt_bins = unique(boundaries$rt_bin),
    n_bins = nrow(boundaries)
  )

  return(boundary_result)
}

# =============================================================================
# CSV Export Functions for Isolation Windows
# =============================================================================

#' Export Single WindowGenerationResult to CSV
#'
#' @param window_result WindowGenerationResult object
#' @param output_file Character, output CSV file path
#' @param instrument_type Character, "astral", "orbitrap", "exploris", or "traditional" (default: "astral")
#' @param strategy Character, m/z optimization strategy: "coverage", "quantile", "outlier", or "smoothing" (default: "unknown")
#' @param include_metadata Logical, add metadata columns (default: TRUE)
#'
#' @return Invisible path to output file
#' @export
export_windows_to_csv <- function(
  window_result,
  output_file,
  instrument_type = "astral",
  strategy = "unknown",
  include_metadata = TRUE
) {

  # Extract windows tibble
  windows <- window_result$windows

  # Create Thermo Orbitrap method file format with appropriate decimal precision
  method_df <- windows %>%
    mutate(
      # Core isolation window fields (Thermo format) - m/z: 1 decimal place
      Start = round(mz_start, 1),
      End = round(mz_end, 1),
      Center = round(mz_center, 1),
      Width = round(window_width, 1),

      # RT segment information - RT: 1 decimal place (0.1 min = 6 sec precision)
      RT_Start = round(rt_start, 1),
      RT_End = round(rt_end, 1),
      RT_Center = round((rt_start + rt_end) / 2, 1),
      RT_Width = round(rt_end - rt_start, 1),

      # Window ID
      Window_ID = window_id,
      RT_Segment_ID = rt_segment_id
    )

  # Add metadata if requested
  if (include_metadata) {
    method_df <- method_df %>%
      mutate(
        N_Precursors = n_precursors,
        Overlap_Prev = overlap_prev,
        Overlap_Next = overlap_next,
        Instrument = instrument_type,
        Generation_Method = strategy,
        Window_Type = window_result$parameters$window_type
      )
  }

  # Select and order columns for Thermo method file
  output_cols <- if (include_metadata) {
    c("Window_ID", "RT_Segment_ID",
      "RT_Start", "RT_End", "RT_Center", "RT_Width",
      "Start", "End", "Center", "Width",
      "N_Precursors", "Overlap_Prev", "Overlap_Next",
      "Instrument", "Generation_Method", "Window_Type")
  } else {
    c("Window_ID", "RT_Segment_ID",
      "RT_Start", "RT_End", "RT_Center", "RT_Width",
      "Start", "End", "Center", "Width")
  }

  method_df <- method_df %>%
    select(all_of(output_cols))

  # Write CSV
  write.csv(method_df, output_file, row.names = FALSE)

  cat(sprintf("✅ Exported %d windows to: %s\n",
              nrow(method_df),
              output_file))

  invisible(output_file)
}


#' Export All Results from RDS File to CSV Files
#'
#' Loads an RDS file containing multiple WindowGenerationResult objects
#' (e.g., from test_full_pipeline.R) and exports each to a separate CSV file.
#'
#' @param rds_file Character, path to RDS file with results list
#' @param output_dir Character, directory for CSV files (default: "results_csv")
#' @param instrument_type Character, instrument type for all exports (default: "astral")
#' @param include_metadata Logical, include metadata columns (default: TRUE)
#' @param create_summary Logical, create summary comparison CSV (default: TRUE)
#'
#' @return Invisible list of exported file paths
#' @export
export_all_results_to_csv <- function(
  rds_file,
  output_dir = "results_csv",
  instrument_type = "astral",
  include_metadata = TRUE,
  create_summary = TRUE
) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   Exporting Results to CSV                   ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  # Load results
  if (!file.exists(rds_file)) {
    stop(sprintf("RDS file not found: %s", rds_file))
  }

  cat(sprintf("Loading results from: %s\n", rds_file))
  all_results <- readRDS(rds_file)

  n_combinations <- length(all_results)
  cat(sprintf("Found %d result combinations\n\n", n_combinations))

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat(sprintf("Created output directory: %s\n\n", output_dir))
  }

  # Export each result to CSV
  exported_files <- list()
  summary_data <- list()

  for (name in names(all_results)) {
    result <- all_results[[name]]

    # Generate filename
    csv_file <- file.path(output_dir, sprintf("%s.csv", name))

    # Export to CSV
    cat(sprintf("Exporting: %s...\n", name))
    export_windows_to_csv(
      window_result = result,
      output_file = csv_file,
      instrument_type = instrument_type,
      include_metadata = include_metadata
    )

    exported_files[[name]] <- csv_file

    # Collect summary statistics
    summary_data[[name]] <- data.frame(
      Combination = name,
      Strategy = strsplit(name, "_")[[1]][1],
      Mode = paste(strsplit(name, "_")[[1]][-1], collapse = "_"),
      N_Windows = nrow(result$windows),
      Coverage_Percent = result$coverage_analysis$coverage_percentage,
      Mean_Precursors = result$statistics$mean_precursors_per_window,
      SD_Precursors = result$statistics$sd_precursors_per_window,
      CV_Precursors = result$statistics$cv_precursors,
      Min_Width_Da = result$statistics$min_window_width,
      Max_Width_Da = result$statistics$max_window_width,
      Mean_Width_Da = result$statistics$window_width_mean,
      Generation_Method = result$metadata$generation_method,
      stringsAsFactors = FALSE
    )
  }

  # Create summary comparison file
  if (create_summary) {
    cat("\n")
    summary_df <- bind_rows(summary_data)
    summary_file <- file.path(output_dir, "SUMMARY_all_combinations.csv")
    write.csv(summary_df, summary_file, row.names = FALSE)
    cat(sprintf("✅ Summary saved to: %s\n", summary_file))
    exported_files[["SUMMARY"]] <- summary_file
  }

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   CSV Export Complete!                        ║\n")
  cat("╚═══════════════════════════════════════════════╝\n")
  cat(sprintf("\nTotal files exported: %d\n", length(exported_files)))
  cat(sprintf("Output directory: %s\n", normalizePath(output_dir)))

  invisible(exported_files)
}


#' Export Best Result Based on Criteria
#'
#' Analyzes all results and exports the best one based on specified criterion
#'
#' @param rds_file Character, path to RDS file with results list
#' @param criterion Character, "cv" (lowest CV), "coverage" (highest coverage),
#'                  or "windows" (closest to target)
#' @param output_file Character, output CSV file path (default: "best_result.csv")
#' @param instrument_type Character, instrument type (default: "astral")
#'
#' @return Invisible list with best result name and file path
#' @export
export_best_result <- function(
  rds_file,
  criterion = "cv",
  output_file = "best_result.csv",
  instrument_type = "astral"
) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   Selecting and Exporting Best Result        ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  # Load results
  all_results <- readRDS(rds_file)

  # Calculate scores for each criterion
  scores <- sapply(names(all_results), function(name) {
    result <- all_results[[name]]

    if (criterion == "cv") {
      # Lower CV is better
      return(result$statistics$cv_precursors)
    } else if (criterion == "coverage") {
      # Higher coverage is better (invert for min selection)
      return(-result$coverage_analysis$coverage_percentage)
    } else if (criterion == "windows") {
      # Closer to target is better
      target <- result$statistics$target_windows
      actual <- result$statistics$total_windows
      return(abs(actual - target) / target)
    } else {
      stop(sprintf("Unknown criterion: %s. Use 'cv', 'coverage', or 'windows'", criterion))
    }
  })

  # Find best result
  best_name <- names(all_results)[which.min(scores)]
  best_result <- all_results[[best_name]]
  best_score <- if (criterion == "coverage") {
    -scores[best_name]  # Convert back to positive
  } else {
    scores[best_name]
  }

  cat(sprintf("Selected: %s\n", best_name))
  cat(sprintf("Criterion: %s\n", criterion))
  cat(sprintf("Score: %.3f\n\n", best_score))

  cat("Result details:\n")
  cat(sprintf("  Windows: %d (target: %d)\n",
              nrow(best_result$windows),
              best_result$parameters$n_windows))
  cat(sprintf("  Coverage: %.1f%%\n",
              best_result$coverage_analysis$coverage_percentage))
  cat(sprintf("  CV: %.3f\n",
              best_result$statistics$cv_precursors))
  cat(sprintf("  Mean precursors/window: %.1f ± %.1f\n\n",
              best_result$statistics$mean_precursors_per_window,
              best_result$statistics$sd_precursors_per_window))

  # Export best result
  export_windows_to_csv(
    window_result = best_result,
    output_file = output_file,
    instrument_type = instrument_type,
    include_metadata = TRUE
  )

  invisible(list(
    name = best_name,
    file = output_file,
    score = best_score
  ))
}

cat("✅ Phase 3D (Window Generation) loaded\n")
cat("   Main function: generate_isolation_windows()\n")
cat("   Window types: fixed, variable, overlapped\n")
cat("   Export functions: export_windows_to_csv(), export_all_results_to_csv(), export_best_result()\n")
