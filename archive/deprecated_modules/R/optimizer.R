# optimizer.R - Module 3: DynamicDIA-Driven Density Optimization
#
# Module 3: Window Optimization with 3-Step Workflow
#
# This module implements RT-dependent window optimization following a strict
# 3-step workflow:
#
# Step 1: m/z Boundary Determination (Dynamic Mode)
#   - Apply DynamicDIA smoothing (Savitzky-Golay, Gaussian, or Moving Average)
#   - OR use raw data min/max boundaries (dynamic = FALSE)
#
# Step 2: Precursor Distribution Analysis
#   - Analyze precursor density within smoothed (or raw) boundaries
#   - Generate 1 Da resolution m/z histogram for precise characterization
#   - Classify high/low density regions
#
# Step 3: Window Allocation for Uniform Density
#   - Goal: Each window contains similar number of precursors
#   - High density → more windows (narrow windows)
#   - Low density → fewer windows (wide windows)
#   - Respect user-specified min_width_da and max_width_da constraints
#
# Key Principle: Uniform precursor density (similar count per window),
# NOT uniform segment precursor counts (that's handled by Module 2 RT binning)

library(dplyr)
library(stats)
library(purrr)
library(tibble)

# ============================================================================
# Helper Functions (Reused from existing implementation)
# ============================================================================

#' Calculate cycle time from target DPPP
#'
#' @param target_dppp Target DPPP value
#' @param fwhm_seconds FWHM in seconds
#' @return Cycle time in milliseconds
#' @export
calculate_cycle_time_from_dppp <- function(target_dppp, fwhm_seconds) {
  # DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds
  # cycle_time_seconds = (1.7 × FWHM_seconds) / DPPP
  cycle_time_seconds <- (1.7 * fwhm_seconds) / target_dppp
  cycle_time_ms <- cycle_time_seconds * 1000
  return(cycle_time_ms)
}

#' Calculate actual DPPP from cycle time
#'
#' @param fwhm_seconds FWHM in seconds
#' @param cycle_time_ms Cycle time in milliseconds
#' @return Actual DPPP value
#' @export
calculate_actual_dppp <- function(fwhm_seconds, cycle_time_ms) {
  cycle_time_seconds <- cycle_time_ms / 1000
  dppp <- (1.7 * fwhm_seconds) / cycle_time_seconds
  return(dppp)
}

#' Calculate number of windows from cycle time
#'
#' @param cycle_time_ms Cycle time in milliseconds
#' @param ms1_time MS1 acquisition time (ms)
#' @param ms2_time MS2 acquisition time per window (ms)
#' @param fixed_window Use fixed window count
#' @param fixed_n_windows Fixed number of windows
#' @return Number of windows
#' @export
calculate_windows_from_cycle_time <- function(cycle_time_ms,
                                             ms1_time,
                                             ms2_time,
                                             fixed_window = FALSE,
                                             fixed_n_windows = 30) {
  if (fixed_window) {
    return(fixed_n_windows)
  }

  # Calculate available time for MS2 scans
  available_ms2_time <- cycle_time_ms - ms1_time

  # Number of MS2 scans that fit in available time
  n_windows <- floor(available_ms2_time / ms2_time)

  # Ensure minimum of 1 window
  n_windows <- max(1, n_windows)

  return(n_windows)
}

#' Calculate cycle time for given window count
#'
#' @param n_windows Number of windows
#' @param ms1_time MS1 acquisition time (ms)
#' @param ms2_time MS2 acquisition time per window (ms)
#' @param cycle_calculation Cycle calculation mode ("parallel" or "sequential")
#' @return Cycle time in seconds
#' @export
calculate_cycle_time <- function(n_windows, ms1_time, ms2_time, cycle_calculation = "sequential") {
  if (cycle_calculation == "parallel") {
    # Astral: MS2 during MS1
    cycle_time_ms <- max(ms1_time, n_windows * ms2_time)
  } else {
    # Traditional: Sequential
    cycle_time_ms <- ms1_time + (n_windows * ms2_time)
  }

  cycle_time_seconds <- cycle_time_ms / 1000
  return(cycle_time_seconds)
}

# ============================================================================
# Step 1: m/z Boundary Determination
# ============================================================================

#' Compute smoothed m/z boundaries using DynamicDIA
#'
#' Step 1 of the 3-step workflow: Determine RT-dependent m/z ranges.
#' Applies DynamicDIA smoothing to create smooth gradient transitions.
#'
#' @param rt_binning_result Result from Module 2 (segment_rt_by_time_unit or segment_rt_by_time_breaks)
#' @param dynamic Use smoothed boundaries (TRUE) or raw data min/max (FALSE)
#' @param smoothing_method DynamicDIA smoothing method: "savgol", "movav", or "gaussian"
#' @param smoothing_window_size Smoothing window size (default: 7)
#' @param polynomial_order Polynomial order for Savitzky-Golay (default: 3)
#' @param sigma Sigma for Gaussian smoothing (default: 1.0)
#' @return List with m/z boundaries for each RT bin
#' @export
compute_smooth_mz_boundaries <- function(rt_binning_result,
                                        dynamic = TRUE,
                                        smoothing_method = "savgol",
                                        smoothing_window_size = 7,
                                        polynomial_order = 3,
                                        sigma = 1.0) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   STEP 1: m/z Boundary Determination         ║\n")
  cat("╚═══════════════════════════════════════════════╝\n")

  data <- rt_binning_result$data
  bin_stats <- rt_binning_result$stats
  n_bins <- rt_binning_result$n_bins

  if (!dynamic) {
    cat("\n📊 Mode: Static (raw data min/max boundaries)\n")

    # Use raw data min/max for each RT bin
    boundaries <- data %>%
      group_by(rt_bin) %>%
      summarise(
        mz_min = min(Precursor.Mz, na.rm = TRUE),
        mz_max = max(Precursor.Mz, na.rm = TRUE),
        mz_range = mz_max - mz_min,
        .groups = 'drop'
      )

    cat(sprintf("\n✓ Static boundaries computed for %d RT bins\n", n_bins))
    cat(sprintf("  Overall m/z range: %.1f - %.1f Da\n",
                min(boundaries$mz_min), max(boundaries$mz_max)))

    return(list(
      method = "static",
      boundaries = boundaries,
      rt_bins = unique(data$rt_bin),
      n_bins = n_bins
    ))
  }

  # Dynamic mode: Apply DynamicDIA smoothing
  cat(sprintf("\n📊 Mode: Dynamic (%s smoothing)\n", smoothing_method))

  # Source dynamicDIA functions if not already loaded
  if (!exists("smooth_boundaries")) {
    source("R/dynamicDIA.R")
  }

  # Extract raw m/z boundaries for each RT bin
  raw_boundaries <- data %>%
    group_by(rt_bin) %>%
    summarise(
      rt_center = mean(RT.Start, na.rm = TRUE),
      mz_min = min(Precursor.Mz, na.rm = TRUE),
      mz_max = max(Precursor.Mz, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    arrange(rt_bin)

  # Apply smoothing to m/z boundaries
  if (smoothing_method == "savgol") {
    smooth_mz_min <- smooth_boundaries(raw_boundaries$mz_min,
                                       method = "savgol",
                                       window_size = smoothing_window_size,
                                       poly_order = polynomial_order)
    smooth_mz_max <- smooth_boundaries(raw_boundaries$mz_max,
                                       method = "savgol",
                                       window_size = smoothing_window_size,
                                       poly_order = polynomial_order)
  } else if (smoothing_method == "movav") {
    smooth_mz_min <- smooth_boundaries(raw_boundaries$mz_min,
                                       method = "movav",
                                       window_size = smoothing_window_size)
    smooth_mz_max <- smooth_boundaries(raw_boundaries$mz_max,
                                       method = "movav",
                                       window_size = smoothing_window_size)
  } else if (smoothing_method == "gaussian") {
    smooth_mz_min <- smooth_boundaries(raw_boundaries$mz_min,
                                       method = "gaussian",
                                       sigma = sigma)
    smooth_mz_max <- smooth_boundaries(raw_boundaries$mz_max,
                                       method = "gaussian",
                                       sigma = sigma)
  } else {
    stop(sprintf("Unknown smoothing method: %s", smoothing_method))
  }

  # Handle potential length mismatch from edge effects
  if (length(smooth_mz_min) != nrow(raw_boundaries)) {
    warning("Smoothing changed array length. Adjusting data to match.")
    offset <- (nrow(raw_boundaries) - length(smooth_mz_min)) %/% 2
    if (offset > 0) {
      indices <- (offset + 1):(offset + length(smooth_mz_min))
      raw_boundaries <- raw_boundaries[indices, ]
    }
  }

  # Create smoothed boundaries data frame
  smoothed_boundaries <- raw_boundaries %>%
    mutate(
      mz_min_smooth = smooth_mz_min,
      mz_max_smooth = smooth_mz_max,
      mz_range = mz_max_smooth - mz_min_smooth,
      delta_min = abs(mz_min_smooth - mz_min),
      delta_max = abs(mz_max_smooth - mz_max)
    )

  cat(sprintf("\n✓ Dynamic boundaries computed with %s smoothing\n", smoothing_method))
  cat(sprintf("  RT bins: %d\n", nrow(smoothed_boundaries)))
  cat(sprintf("  Overall m/z range: %.1f - %.1f Da\n",
              min(smoothed_boundaries$mz_min_smooth),
              max(smoothed_boundaries$mz_max_smooth)))
  cat(sprintf("  Mean smoothing effect: %.2f Da (min), %.2f Da (max)\n",
              mean(smoothed_boundaries$delta_min),
              mean(smoothed_boundaries$delta_max)))

  return(list(
    method = "dynamic",
    smoothing_method = smoothing_method,
    parameters = list(
      window_size = smoothing_window_size,
      polynomial_order = polynomial_order,
      sigma = sigma
    ),
    boundaries = smoothed_boundaries,
    raw_boundaries = raw_boundaries,
    rt_bins = unique(data$rt_bin),
    n_bins = nrow(smoothed_boundaries)
  ))
}

# ============================================================================
# Step 2: Precursor Distribution Analysis
# ============================================================================

#' Analyze precursor density within m/z boundaries
#'
#' Step 2 of the 3-step workflow: Analyze precursor distribution within
#' the boundaries determined in Step 1.
#'
#' @param rt_binning_result Result from Module 2
#' @param boundary_result Result from Step 1 (compute_smooth_mz_boundaries)
#' @param mz_bin_width_da Resolution for density analysis (default: 1 Da)
#' @return List with density profiles for each RT bin
#' @export
analyze_density_within_boundaries <- function(rt_binning_result,
                                             boundary_result,
                                             mz_bin_width_da = 1) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   STEP 2: Precursor Distribution Analysis    ║\n")
  cat("╚═══════════════════════════════════════════════╝\n")

  cat(sprintf("\n📊 Resolution: %.1f Da bins\n", mz_bin_width_da))

  data <- rt_binning_result$data
  boundaries <- boundary_result$boundaries

  # Analyze density for each RT bin
  density_profiles <- list()

  for (i in 1:nrow(boundaries)) {
    rt_bin_name <- boundaries$rt_bin[i]

    # Get m/z boundaries for this RT bin
    if (boundary_result$method == "static") {
      mz_min <- boundaries$mz_min[i]
      mz_max <- boundaries$mz_max[i]
    } else {
      mz_min <- boundaries$mz_min_smooth[i]
      mz_max <- boundaries$mz_max_smooth[i]
    }

    # Filter data for this RT bin and within boundaries
    bin_data <- data %>%
      filter(rt_bin == rt_bin_name,
             Precursor.Mz >= mz_min,
             Precursor.Mz <= mz_max)

    if (nrow(bin_data) == 0) {
      cat(sprintf("⚠ RT bin %s: No precursors within boundaries\n", rt_bin_name))
      next
    }

    # Create m/z bins for density histogram
    mz_breaks <- seq(mz_min, mz_max, by = mz_bin_width_da)
    if (mz_breaks[length(mz_breaks)] < mz_max) {
      mz_breaks <- c(mz_breaks, mz_max)
    }

    # Calculate density histogram
    mz_hist <- hist(bin_data$Precursor.Mz, breaks = mz_breaks, plot = FALSE)

    # Create density profile
    density_profile <- data.frame(
      mz_center = mz_hist$mids,
      mz_start = mz_breaks[-length(mz_breaks)],
      mz_end = mz_breaks[-1],
      n_precursors = mz_hist$counts,
      density = mz_hist$counts / mz_bin_width_da
    )

    # Calculate density statistics
    total_precursors <- sum(density_profile$n_precursors)
    mean_density <- mean(density_profile$density)
    median_density <- median(density_profile$density)
    max_density <- max(density_profile$density)

    # Classify density regions
    density_threshold <- quantile(density_profile$density, 0.75)
    density_profile$density_class <- ifelse(
      density_profile$density >= density_threshold,
      "high",
      ifelse(density_profile$density >= mean_density, "medium", "low")
    )

    cat(sprintf("RT bin %s: %d precursors, mean density: %.1f/Da, max: %.1f/Da\n",
                rt_bin_name, total_precursors, mean_density, max_density))

    density_profiles[[as.character(rt_bin_name)]] <- list(
      rt_bin = rt_bin_name,
      mz_range = c(mz_min, mz_max),
      n_precursors = total_precursors,
      n_mz_bins = nrow(density_profile),
      density_profile = density_profile,
      statistics = list(
        mean_density = mean_density,
        median_density = median_density,
        max_density = max_density,
        density_threshold = density_threshold
      )
    )
  }

  cat(sprintf("\n✓ Density analysis complete for %d RT bins\n", length(density_profiles)))

  return(list(
    mz_bin_width_da = mz_bin_width_da,
    profiles = density_profiles,
    boundary_result = boundary_result
  ))
}

# ============================================================================
# Step 3: Window Allocation for Uniform Density
# ============================================================================

#' Allocate windows for uniform precursor density
#'
#' Step 3 of the 3-step workflow: Allocate isolation windows to achieve
#' uniform precursor density (similar count per window).
#'
#' Goal: Each window contains similar number of precursors
#' - High density regions → more windows (narrow windows)
#' - Low density regions → fewer windows (wide windows)
#' - Respect min_width_da and max_width_da constraints
#'
#' @param rt_binning_result Result from Module 2
#' @param density_result Result from Step 2 (analyze_density_within_boundaries)
#' @param n_windows Total number of windows to generate (default: 100)
#' @param min_width_da Minimum window width in Da (default: 2)
#' @param max_width_da Maximum window width in Da (default: 80)
#' @param target_precursors_per_window Target precursors per window (optional, overrides n_windows)
#' @return List with optimized windows
#' @export
allocate_windows_for_uniform_density <- function(rt_binning_result,
                                                density_result,
                                                n_windows = 100,
                                                min_width_da = 2,
                                                max_width_da = 80,
                                                target_precursors_per_window = NULL) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   STEP 3: Window Allocation for Uniform      ║\n")
  cat("║           Density                             ║\n")
  cat("╚═══════════════════════════════════════════════╝\n")

  cat(sprintf("\n📊 Parameters:\n"))
  cat(sprintf("  Target windows: %d\n", n_windows))
  cat(sprintf("  Min width: %.1f Da\n", min_width_da))
  cat(sprintf("  Max width: %.1f Da\n", max_width_da))

  data <- rt_binning_result$data
  density_profiles <- density_result$profiles

  # Calculate total precursors across all RT bins
  total_precursors <- sum(sapply(density_profiles, function(p) p$n_precursors))

  # Determine target precursors per window
  if (is.null(target_precursors_per_window)) {
    target_precursors_per_window <- total_precursors / n_windows
  } else {
    n_windows <- ceiling(total_precursors / target_precursors_per_window)
  }

  cat(sprintf("  Target precursors/window: %.1f\n", target_precursors_per_window))
  cat(sprintf("  Total precursors: %d\n", total_precursors))

  # Allocate windows across RT bins proportionally to precursor count
  all_windows <- data.frame()

  for (rt_bin_name in names(density_profiles)) {
    profile <- density_profiles[[rt_bin_name]]

    # Calculate number of windows for this RT bin (proportional allocation)
    bin_precursors <- profile$n_precursors
    bin_n_windows <- max(1, round(n_windows * bin_precursors / total_precursors))

    cat(sprintf("\nRT bin %s: %d precursors → %d windows\n",
                rt_bin_name, bin_precursors, bin_n_windows))

    # Get precursors for this RT bin
    bin_data <- data %>%
      filter(rt_bin == rt_bin_name) %>%
      arrange(Precursor.Mz)

    if (nrow(bin_data) == 0) {
      cat(sprintf("  ⚠ Skipping (no precursors)\n"))
      next
    }

    # Use cumulative distribution to create windows with equal precursor counts
    target_per_bin_window <- bin_precursors / bin_n_windows

    # Calculate quantile breaks for equal precursor distribution
    quantile_probs <- seq(0, 1, length.out = bin_n_windows + 1)
    mz_breaks <- quantile(bin_data$Precursor.Mz, probs = quantile_probs, na.rm = TRUE)

    # Generate windows with constraint enforcement
    for (j in 1:(length(mz_breaks) - 1)) {
      window_start <- mz_breaks[j]
      window_end <- mz_breaks[j + 1]
      window_width <- window_end - window_start

      # Apply width constraints
      if (window_width < min_width_da) {
        # Expand window to minimum width (centered)
        center <- (window_start + window_end) / 2
        window_start <- max(profile$mz_range[1], center - min_width_da / 2)
        window_end <- min(profile$mz_range[2], center + min_width_da / 2)
        window_width <- window_end - window_start

        # If still too small (edge case), force minimum width
        if (window_width < min_width_da) {
          window_width <- min_width_da
          window_end <- window_start + window_width
        }
      } else if (window_width > max_width_da) {
        # Split into multiple narrower windows
        n_splits <- ceiling(window_width / max_width_da)
        split_width <- window_width / n_splits

        for (k in 1:n_splits) {
          sub_start <- window_start + (k - 1) * split_width
          sub_end <- window_start + k * split_width
          sub_width <- sub_end - sub_start
          sub_center <- (sub_start + sub_end) / 2

          # Count precursors in this sub-window
          n_prec <- sum(bin_data$Precursor.Mz >= sub_start &
                       bin_data$Precursor.Mz < sub_end)

          all_windows <- rbind(all_windows, data.frame(
            rt_bin = rt_bin_name,
            window_start = sub_start,
            window_end = sub_end,
            window_width = sub_width,
            center_mz = sub_center,
            n_precursors = n_prec,
            stringsAsFactors = FALSE
          ))
        }
        next  # Skip adding the original wide window
      }

      # Count precursors in this window
      n_prec <- sum(bin_data$Precursor.Mz >= window_start &
                   bin_data$Precursor.Mz < window_end)

      all_windows <- rbind(all_windows, data.frame(
        rt_bin = rt_bin_name,
        window_start = window_start,
        window_end = window_end,
        window_width = window_width,
        center_mz = (window_start + window_end) / 2,
        n_precursors = n_prec,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Calculate final statistics
  total_windows <- nrow(all_windows)
  mean_precursors_per_window <- mean(all_windows$n_precursors)
  sd_precursors_per_window <- sd(all_windows$n_precursors)
  cv_precursors <- sd_precursors_per_window / mean_precursors_per_window

  min_window_width <- min(all_windows$window_width)
  max_window_width <- max(all_windows$window_width)
  mean_window_width <- mean(all_windows$window_width)

  cat(sprintf("\n═══════════════════════════════════════════════\n"))
  cat(sprintf("✓ Window Allocation Complete\n"))
  cat(sprintf("═══════════════════════════════════════════════\n"))
  cat(sprintf("  Total windows: %d (target: %d)\n", total_windows, n_windows))
  cat(sprintf("  Precursors/window: %.1f ± %.1f (CV: %.2f)\n",
              mean_precursors_per_window, sd_precursors_per_window, cv_precursors))
  cat(sprintf("  Window width: %.1f - %.1f Da (mean: %.1f Da)\n",
              min_window_width, max_window_width, mean_window_width))

  # Check constraint violations
  n_below_min <- sum(all_windows$window_width < min_width_da * 0.99)
  n_above_max <- sum(all_windows$window_width > max_width_da * 1.01)

  if (n_below_min > 0) {
    cat(sprintf("  ⚠ %d windows below min width (%.1f Da)\n", n_below_min, min_width_da))
  }
  if (n_above_max > 0) {
    cat(sprintf("  ⚠ %d windows above max width (%.1f Da)\n", n_above_max, max_width_da))
  }

  return(list(
    windows = all_windows,
    n_windows = total_windows,
    target_n_windows = n_windows,
    statistics = list(
      mean_precursors_per_window = mean_precursors_per_window,
      sd_precursors_per_window = sd_precursors_per_window,
      cv_precursors = cv_precursors,
      min_window_width = min_window_width,
      max_window_width = max_window_width,
      mean_window_width = mean_window_width,
      n_below_min = n_below_min,
      n_above_max = n_above_max
    ),
    parameters = list(
      n_windows = n_windows,
      min_width_da = min_width_da,
      max_width_da = max_width_da,
      target_precursors_per_window = target_precursors_per_window
    )
  ))
}

# ============================================================================
# Main Orchestrator: 3-Step Workflow
# ============================================================================

#' Optimize windows per RT bin (Main Module 3 Function)
#'
#' Main orchestrator function that enforces the 3-step workflow:
#' Step 1 → Step 2 → Step 3
#'
#' This is the primary entry point for Module 3 optimization.
#'
#' @param rt_binning_result Result from Module 2 (segment_rt_by_time_unit or segment_rt_by_time_breaks)
#' @param n_windows Total number of windows (default: 100)
#' @param min_width_da Minimum window width (default: 2)
#' @param max_width_da Maximum window width (default: 80)
#' @param dynamic Use DynamicDIA smoothed boundaries (TRUE) or raw data (FALSE)
#' @param smoothing_method Smoothing method: "savgol", "movav", or "gaussian"
#' @param smoothing_window_size Smoothing window size (default: 7)
#' @param polynomial_order Polynomial order for Savitzky-Golay (default: 3)
#' @param sigma Sigma for Gaussian smoothing (default: 1.0)
#' @param mz_bin_width_da Resolution for density analysis (default: 1 Da)
#' @param target_precursors_per_window Target precursors per window (optional)
#' @return List with complete optimization results
#' @export
#'
#' @examples
#' # Basic usage with default parameters
#' rt_bins <- segment_rt_by_time_unit(data, rt_bin_width_min = 5)
#' result <- optimize_windows_per_rt_bin(rt_bins, n_windows = 100)
#'
#' # With custom parameters
#' result <- optimize_windows_per_rt_bin(
#'   rt_bins,
#'   n_windows = 120,
#'   min_width_da = 2,
#'   max_width_da = 50,
#'   dynamic = TRUE,
#'   smoothing_method = "savgol"
#' )
#'
#' # Static mode (no smoothing)
#' result <- optimize_windows_per_rt_bin(
#'   rt_bins,
#'   n_windows = 100,
#'   dynamic = FALSE
#' )
optimize_windows_per_rt_bin <- function(rt_binning_result,
                                       n_windows = 100,
                                       min_width_da = 2,
                                       max_width_da = 80,
                                       dynamic = TRUE,
                                       smoothing_method = "savgol",
                                       smoothing_window_size = 7,
                                       polynomial_order = 3,
                                       sigma = 1.0,
                                       mz_bin_width_da = 1,
                                       target_precursors_per_window = NULL) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   MODULE 3: DynamicDIA-Driven Optimization   ║\n")
  cat("║   3-Step Workflow                             ║\n")
  cat("╚═══════════════════════════════════════════════╝\n")

  start_time <- Sys.time()

  # Validate input
  if (!"rt_bin" %in% colnames(rt_binning_result$data)) {
    stop("rt_binning_result must be output from Module 2 (segment_rt_by_time_unit or segment_rt_by_time_breaks)")
  }

  cat(sprintf("\n📊 Input: %d RT bins, %d precursors\n",
              rt_binning_result$n_bins,
              nrow(rt_binning_result$data)))

  # STEP 1: m/z Boundary Determination
  boundary_result <- compute_smooth_mz_boundaries(
    rt_binning_result = rt_binning_result,
    dynamic = dynamic,
    smoothing_method = smoothing_method,
    smoothing_window_size = smoothing_window_size,
    polynomial_order = polynomial_order,
    sigma = sigma
  )

  # STEP 2: Precursor Distribution Analysis
  density_result <- analyze_density_within_boundaries(
    rt_binning_result = rt_binning_result,
    boundary_result = boundary_result,
    mz_bin_width_da = mz_bin_width_da
  )

  # STEP 3: Window Allocation for Uniform Density
  window_result <- allocate_windows_for_uniform_density(
    rt_binning_result = rt_binning_result,
    density_result = density_result,
    n_windows = n_windows,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    target_precursors_per_window = target_precursors_per_window
  )

  end_time <- Sys.time()
  elapsed_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

  cat(sprintf("\n╔═══════════════════════════════════════════════╗\n"))
  cat(sprintf("║   OPTIMIZATION COMPLETE                       ║\n"))
  cat(sprintf("╚═══════════════════════════════════════════════╝\n"))
  cat(sprintf("\n⏱ Execution time: %.2f seconds\n", elapsed_time))

  # Return comprehensive results
  result <- list(
    # Results from each step
    step1_boundaries = boundary_result,
    step2_density = density_result,
    step3_windows = window_result,

    # Quick access to key outputs
    windows = window_result$windows,
    n_windows = window_result$n_windows,
    statistics = window_result$statistics,

    # Input parameters
    parameters = list(
      n_windows = n_windows,
      min_width_da = min_width_da,
      max_width_da = max_width_da,
      dynamic = dynamic,
      smoothing_method = smoothing_method,
      smoothing_window_size = smoothing_window_size,
      polynomial_order = polynomial_order,
      sigma = sigma,
      mz_bin_width_da = mz_bin_width_da
    ),

    # Metadata
    module = "Module_3",
    method = "DynamicDIA_3step",
    timestamp = Sys.time(),
    execution_time = elapsed_time
  )

  class(result) <- c("module3_optimization", "list")

  return(result)
}

# ============================================================================
# Validation and Quality Control Functions
# ============================================================================

#' Validate optimization results
#'
#' Performs comprehensive validation of optimization results including
#' coverage, density uniformity, and constraint compliance.
#'
#' @param optimization_result Result from optimize_windows_per_rt_bin()
#' @param rt_binning_result Original RT binning result from Module 2
#' @return List with validation results and warnings
#' @export
validate_optimization_results <- function(optimization_result, rt_binning_result) {

  cat("\n═══════════════════════════════════════════════\n")
  cat("  Validation: Optimization Quality Check\n")
  cat("═══════════════════════════════════════════════\n")

  data <- rt_binning_result$data
  windows <- optimization_result$windows

  warnings <- character()
  checks <- list()

  # Check 1: Precursor coverage
  covered_precursors <- 0
  for (i in 1:nrow(windows)) {
    in_window <- data$Precursor.Mz >= windows$window_start[i] &
                 data$Precursor.Mz <= windows$window_end[i]
    covered_precursors <- covered_precursors + sum(in_window)
  }

  coverage_pct <- 100 * covered_precursors / nrow(data)
  checks$coverage <- list(
    covered = covered_precursors,
    total = nrow(data),
    percentage = coverage_pct
  )

  cat(sprintf("✓ Coverage: %d / %d precursors (%.1f%%)\n",
              covered_precursors, nrow(data), coverage_pct))

  if (coverage_pct < 95) {
    warnings <- c(warnings,
                 sprintf("Low coverage: %.1f%% (target: ≥95%%)", coverage_pct))
  }

  # Check 2: Window width constraints
  stats <- optimization_result$statistics
  checks$width_constraints <- stats

  cat(sprintf("✓ Window widths: %.1f - %.1f Da (mean: %.1f Da)\n",
              stats$min_window_width, stats$max_window_width, stats$mean_window_width))

  if (stats$n_below_min > 0) {
    warnings <- c(warnings,
                 sprintf("%d windows below minimum width", stats$n_below_min))
  }
  if (stats$n_above_max > 0) {
    warnings <- c(warnings,
                 sprintf("%d windows above maximum width", stats$n_above_max))
  }

  # Check 3: Density uniformity (CV of precursors per window)
  cat(sprintf("✓ Density uniformity: CV = %.2f (target: <0.3)\n",
              stats$cv_precursors))

  if (stats$cv_precursors > 0.3) {
    warnings <- c(warnings,
                 sprintf("High density variation: CV = %.2f (target: <0.3)",
                        stats$cv_precursors))
  }

  # Check 4: Window count
  window_diff <- abs(optimization_result$n_windows -
                    optimization_result$parameters$n_windows)
  window_diff_pct <- 100 * window_diff / optimization_result$parameters$n_windows

  cat(sprintf("✓ Window count: %d (target: %d, diff: %.1f%%)\n",
              optimization_result$n_windows,
              optimization_result$parameters$n_windows,
              window_diff_pct))

  if (window_diff_pct > 10) {
    warnings <- c(warnings,
                 sprintf("Window count deviation: %.1f%% (target: <10%%)",
                        window_diff_pct))
  }

  # Print summary
  if (length(warnings) == 0) {
    cat("\n✅ All validation checks passed\n")
  } else {
    cat(sprintf("\n⚠ %d validation warnings:\n", length(warnings)))
    for (w in warnings) {
      cat(sprintf("  - %s\n", w))
    }
  }

  return(list(
    valid = length(warnings) == 0,
    warnings = warnings,
    checks = checks,
    coverage_pct = coverage_pct
  ))
}

cat("✅ Module 3 (DynamicDIA Optimizer) loaded successfully\n")
cat("   Main function:\n")
cat("   - optimize_windows_per_rt_bin(rt_binning_result, n_windows, min_width_da, max_width_da, dynamic, ...)\n")
cat("   \n")
cat("   3-Step Workflow Functions:\n")
cat("   - Step 1: compute_smooth_mz_boundaries()\n")
cat("   - Step 2: analyze_density_within_boundaries()\n")
cat("   - Step 3: allocate_windows_for_uniform_density()\n")
cat("   \n")
cat("   Validation:\n")
cat("   - validate_optimization_results(optimization_result, rt_binning_result)\n")
