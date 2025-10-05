# optimizer.R - Optimization algorithms for DIA isolation windows

library(dplyr)
library(stats)
library(purrr)
library(tibble)

#' Filter low-density m/z bins (Reference Implementation)
#' 
#' @param df Data frame with precursor data
#' @param mz_col Column name for m/z values
#' @param bin_width Width of m/z bins for density calculation
#' @param lower_percentile Lower percentile threshold for filtering
#' @return Filtered data frame
filter_low_density_mz_bins <- function(df, mz_col, bin_width, lower_percentile = 0.05) {
  
  mz_range <- range(df[[mz_col]], na.rm = TRUE)
  bin_breaks <- seq(mz_range[1], mz_range[2], by = bin_width)
  
  df <- df %>%
    mutate(mz_bin = cut(.data[[mz_col]], breaks = bin_breaks, include.lowest = TRUE))
  
  bin_counts <- df %>%
    count(mz_bin, name = "count") %>%
    mutate(percentile = cume_dist(count))
  
  valid_bins <- bin_counts %>%
    filter(percentile >= lower_percentile) %>%
    pull(mz_bin)
  
  df %>%
    filter(mz_bin %in% valid_bins) %>%
    dplyr::select(-mz_bin)
}

#' Analyze RT segments for dynamic window optimization
#' 
#' @param data DIA-NN data frame
#' @param rt_segments Number of RT segments
#' @return List with segment analysis results
analyze_rt_segments <- function(data, rt_segments = 5) {
  
  # Define RT segment boundaries
  rt_range <- range(data$RT.Start)
  rt_breaks <- seq(rt_range[1], rt_range[2], length.out = rt_segments + 1)
  
  # Assign segments to data
  data$rt_segment <- cut(data$RT.Start, breaks = rt_breaks, 
                         labels = 1:rt_segments, include.lowest = TRUE)
  
  # Analyze each segment
  segment_analysis <- list()
  
  for (seg in 1:rt_segments) {
    seg_data <- data %>% filter(rt_segment == seg)
    
    segment_analysis[[seg]] <- list(
      segment = seg,
      rt_range = c(rt_breaks[seg], rt_breaks[seg + 1]),
      n_precursors = nrow(seg_data),
      mz_range = range(seg_data$Precursor.Mz),
      mz_density = nrow(seg_data) / diff(range(seg_data$Precursor.Mz)),
      fwhm_mean = mean(seg_data$FWHM),
      fwhm_median = median(seg_data$FWHM),
      data = seg_data
    )
  }
  
  return(segment_analysis)
}

#' Optimize window distribution for a segment
#' 
#' @param segment_data Data for one RT segment
#' @param target_precursors_per_window Target number of precursors per window
#' @param mz_range Overall m/z range for windows
#' @param min_width Minimum window width
#' @param max_width Maximum window width
#' @return Data frame with optimized windows
optimize_window_distribution <- function(segment_info, 
                                       target_precursors_per_window,
                                       mz_range,
                                       min_width = 2.0,
                                       max_width = 80.0) {
  
  # Extract segment number
  segment_num <- segment_info$segment
  
  # Sort by m/z
  segment_data <- segment_info$data %>%
    arrange(Precursor.Mz)
  
  # Use cumulative distribution to create windows
  n_precursors <- nrow(segment_data)
  n_windows <- ceiling(n_precursors / target_precursors_per_window)
  
  windows <- data.frame()
  
  if (n_precursors > 0) {
    # Calculate quantiles for equal precursor distribution
    quantile_breaks <- quantile(segment_data$Precursor.Mz, 
                               probs = seq(0, 1, length.out = n_windows + 1))
    
    for (i in 1:n_windows) {
      window_start <- quantile_breaks[i]
      window_end <- quantile_breaks[i + 1]
      window_width <- window_end - window_start
      
      # Apply width constraints
      if (window_width < min_width) {
        # Expand window to minimum width
        center <- (window_start + window_end) / 2
        window_start <- center - min_width / 2
        window_end <- center + min_width / 2
        window_width <- min_width
      } else if (window_width > max_width) {
        # Split into multiple windows
        n_splits <- ceiling(window_width / max_width)
        split_width <- window_width / n_splits
        
        for (j in 1:n_splits) {
          sub_start <- window_start + (j - 1) * split_width
          sub_end <- window_start + j * split_width
          
          windows <- rbind(windows, data.frame(
            rt_segment = segment_num,
            window_start = sub_start,
            window_end = sub_end,
            window_width = split_width,
            center_mz = (sub_start + sub_end) / 2
          ))
        }
        next
      }
      
      windows <- rbind(windows, data.frame(
        rt_segment = segment_num,
        window_start = window_start,
        window_end = window_end,
        window_width = window_width,
        center_mz = (window_start + window_end) / 2
      ))
    }
  }
  
  return(windows)
}

#' Main optimization function (Reference Implementation)
#' 
#' @param data DIA-NN data
#' @param target_dppp Target DPPP value
#' @param instrument_config Instrument configuration
#' @param mz_range m/z range for windows
#' @param rt_segments Number of RT segments
#' @param window_mode "dynamic" or "fixed"
#' @param min_window_width Minimum window width
#' @param max_window_width Maximum window width
#' @param overlap_mode "none", "fixed", or "percentage"
#' @param overlap_value Overlap value
#' @param min_precursors_per_window Minimum precursors per window
#' @param fixed_window Use fixed window count
#' @param fixed_n_windows Fixed number of windows
#' @param lower_percentile Lower percentile for density filtering
#' @param bin_width Bin width for density calculation
#' @param PG_Q_Value Quality threshold for filtering
#' @param fwhm_strategy FWHM calculation strategy ("conservative", "balanced", "aggressive", "adaptive")
#' @param fwhm_analysis Pre-computed FWHM analysis (optional)
#' @return List with optimized windows and metadata
optimize_isolation_windows <- function(data,
                                     target_dppp = 1.25,
                                     instrument_config,
                                     mz_range = c(380, 980),
                                     rt_segments = 5,
                                     window_mode = "dynamic",
                                     min_window_width = 2.0,
                                     max_window_width = 80.0,
                                     overlap_mode = "percentage",
                                     overlap_value = 0.5,
                                     min_precursors_per_window = 100,
                                     fixed_window = FALSE,
                                     fixed_n_windows = 30,
                                     lower_percentile = 0.05,
                                     bin_width = NULL,
                                     PG_Q_Value = 0.01,
                                     fwhm_strategy = "balanced",
                                     fwhm_analysis = NULL) {
  
  cat("\n=== Starting Isolation Window Optimization (Reference Method) ===\n")
  
  # Step 1: Pre-filter data (Reference Implementation)
  rt_min <- min(data$RT.Start, na.rm = TRUE)
  rt_max <- max(data$RT.Start, na.rm = TRUE)
  
  # Filter by quality and add RT segments
  data_filtered <- data %>%
    filter(RT.Start >= rt_min, RT.Start <= rt_max) %>%
    mutate(RT_segment = if (rt_segments == 1) "all" else cut(RT.Start, breaks = rt_segments))
  
  # Add quality filtering if PG.Q.Value column exists
  if ("PG.Q.Value" %in% names(data_filtered)) {
    data_filtered <- data_filtered %>% filter(PG.Q.Value <= PG_Q_Value)
  }
  
  cat(sprintf("Filtered data: %d precursors in %d RT segments\n", 
              nrow(data_filtered), rt_segments))
  
  # Step 2: Calculate FWHM based on strategy (Enhanced Implementation)
  cat(sprintf("FWHM Strategy: %s\n", fwhm_strategy))
  
  if (is.null(fwhm_analysis)) {
    # Quick analysis for strategy-based FWHM
    valid_fwhm <- data_filtered %>% 
      filter(!is.na(FWHM), FWHM > 0) %>%
      mutate(FWHM_seconds = FWHM * 60)
    
    if (fwhm_strategy == "conservative") {
      mean_fwhm <- quantile(valid_fwhm$FWHM_seconds, 0.95)
    } else if (fwhm_strategy == "aggressive") {
      mean_fwhm <- quantile(valid_fwhm$FWHM_seconds, 0.50)
    } else if (fwhm_strategy == "balanced") {
      mean_fwhm <- quantile(valid_fwhm$FWHM_seconds, 0.75)
    } else {
      # Default to median for unknown strategies
      mean_fwhm <- median(valid_fwhm$FWHM_seconds)
    }
  } else {
    # Use pre-computed analysis
    mean_fwhm <- get_strategy_fwhm(fwhm_analysis, fwhm_strategy)
  }
  
  cat(sprintf("Selected FWHM (%s): %.2f seconds\n", fwhm_strategy, mean_fwhm))
  
  # Step 3: Calculate cycle time and window count (Reference Implementation)
  if (!fixed_window) {
    cycle_time <- calculate_cycle_time_from_dppp(target_dppp, mean_fwhm)
    n_windows <- calculate_windows_from_cycle_time(
      cycle_time, 
      instrument_config$ms1_time, 
      instrument_config$ms2_time,
      fixed_window,
      fixed_n_windows
    )
    
    # Warnings for extreme values
    if (cycle_time > 9000) {
      warning(sprintf("Cycle time (%.1f ms) exceeds threshold (9000 ms)", cycle_time))
    }
    if (n_windows > 80) {
      warning(sprintf("%d windows calculated - may overload instrument. Consider increasing DPPP", n_windows))
    }
  } else {
    n_windows <- fixed_n_windows
    cycle_time <- instrument_config$ms1_time + instrument_config$ms2_time * fixed_n_windows
  }
  
  cat(sprintf("Calculated cycle time: %.1f ms\n", cycle_time))
  cat(sprintf("Number of windows: %d\n", n_windows))
  
  # Validate scan rate against instrument capabilities
  # Correct calculation: scan rate = MS2 scans per second
  initial_scan_rate <- n_windows / (cycle_time / 1000)  # n_windows per cycle time in seconds
  cat(sprintf("Required scan rate: %.1f Hz (%.0f MS2 scans in %.3f sec cycle)\n", 
              initial_scan_rate, n_windows, cycle_time/1000))
  
  scan_validation <- validate_scan_rate(initial_scan_rate, instrument_config, n_windows, target_dppp)
  
  if (!scan_validation$is_achievable) {
    cat("\n⚠️ WARNING: Target parameters exceed instrument capabilities!\n")
    for (warning in scan_validation$warnings) {
      cat(sprintf("%s\n", warning))
    }
    cat("\nAdjusting parameters for achievable performance...\n")
    
    if (!is.null(scan_validation$suggested_dppp)) {
      # Recalculate with suggested DPPP
      target_dppp <- scan_validation$suggested_dppp
      cycle_time <- calculate_cycle_time_from_dppp(target_dppp, mean_fwhm)
      n_windows <- calculate_windows_from_cycle_time(
        cycle_time, 
        instrument_config$ms1_time, 
        instrument_config$ms2_time,
        fixed_window,
        fixed_n_windows
      )
      cat(sprintf("Adjusted DPPP: %.2f\n", target_dppp))
      cat(sprintf("Adjusted cycle time: %.1f ms\n", cycle_time))
      cat(sprintf("Adjusted windows: %d\n", n_windows))
    }
  }
  
  # Set default bin width if not provided
  if (is.null(bin_width)) {
    bin_width <- (mz_range[2] - mz_range[1]) / fixed_n_windows
  }
  
  # Step 4: RT segment-wise adaptive window design (Reference Implementation)
  cat("Generating windows per RT segment using quantile-based distribution...\n")
  
  all_windows <- data_filtered %>%
    group_by(RT_segment) %>%
    group_split() %>%
    purrr::map_dfr(function(df) {
      seg_name <- unique(df$RT_segment)
      
      cat(sprintf("Processing segment: %s (%d precursors)\n", seg_name, nrow(df)))
      
      # Apply low-density filtering (Reference Implementation)
      df_filtered <- filter_low_density_mz_bins(
        df, 
        mz_col = "Precursor.Mz",
        bin_width = bin_width,
        lower_percentile = lower_percentile
      )
      
      if (nrow(df_filtered) < n_windows) {
        cat(sprintf("Skipping segment %s: insufficient precursors after filtering\n", seg_name))
        return(tibble())
      }
      
      # Calculate segment-specific FWHM based on strategy
      if (fwhm_strategy == "adaptive" && !is.null(fwhm_analysis)) {
        # Use RT-segment specific FWHM from analysis
        seg_num <- as.numeric(seg_name)
        if (seg_num <= nrow(fwhm_analysis$rt_analysis$stats)) {
          med_fwhm <- fwhm_analysis$rt_analysis$stats$median_fwhm[seg_num]
        } else {
          med_fwhm <- median(df_filtered$FWHM, na.rm = TRUE) * 60
        }
      } else if (fwhm_strategy == "adaptive") {
        # Calculate segment-specific FWHM on the fly
        valid_fwhm_seg <- df_filtered %>% filter(!is.na(FWHM), FWHM > 0)
        if (nrow(valid_fwhm_seg) >= 10) {
          med_fwhm <- median(valid_fwhm_seg$FWHM) * 60
        } else {
          med_fwhm <- mean_fwhm  # Fallback to global FWHM
        }
      } else {
        # Use global strategy-based FWHM
        med_fwhm <- mean_fwhm
      }
      
      actual_dppp <- calculate_actual_dppp(med_fwhm, cycle_time)
      
      # Quantile-based window distribution (Reference Implementation)
      cuts <- quantile(df_filtered$Precursor.Mz, 
                      probs = seq(0, 1, length.out = n_windows + 1), 
                      na.rm = TRUE)
      
      mz_start <- cuts[-length(cuts)]
      mz_end <- cuts[-1]
      
      # Apply overlap (Reference Implementation)
      if (overlap_mode != "none") {
        if (overlap_mode == "percentage") {
          overlap_da <- (mz_end - mz_start) * overlap_value / 100
        } else {
          overlap_da <- overlap_value
        }
        mz_start <- mz_start - overlap_da / 2
        mz_end <- mz_end + overlap_da / 2
      }
      
      width <- mz_end - mz_start
      center <- (mz_start + mz_end) / 2
      
      # Return windows for this segment
      tibble(
        RT_segment = seg_name,
        window_start = mz_start,
        window_end = mz_end,
        window_width = width,
        center_mz = center,
        FWHM_sec = mean_fwhm,
        cycle_time = cycle_time,
        Target_DPPP = target_dppp,
        actual_DPPP = actual_dppp,
        window_n = n_windows
      )
    })
  
  if (nrow(all_windows) == 0) {
    stop("No windows generated. Check filtering parameters and data quality.")
  }
  
  # Step 5: Validate constraints
  validation <- validate_constraints(all_windows, instrument_config, data_filtered)
  
  # Step 6: Calculate final metrics (Reference Implementation)
  final_cycle_time_seconds <- cycle_time / 1000
  final_dppp <- calculate_actual_dppp(mean_fwhm, cycle_time)
  # Correct scan rate calculation: MS2 scans per second
  scan_rate <- nrow(all_windows) / final_cycle_time_seconds
  
  cat(sprintf("\nOptimization complete (Reference Method):\n"))
  cat(sprintf("  Final windows: %d\n", nrow(all_windows)))
  cat(sprintf("  Target DPPP: %.2f\n", target_dppp))
  cat(sprintf("  Achieved DPPP: %.2f\n", final_dppp))
  cat(sprintf("  Cycle time: %.1f ms (%.3f seconds)\n", cycle_time, final_cycle_time_seconds))
  cat(sprintf("  Scan rate: %.1f Hz\n", scan_rate))
  
  # Final scan rate validation
  final_validation <- validate_scan_rate(scan_rate, instrument_config, nrow(all_windows), target_dppp)
  
  if (!final_validation$is_achievable) {
    cat("\n⚠️ CRITICAL WARNING: Final configuration exceeds instrument limits!\n")
    print_scan_rate_validation(final_validation)
  } else if (length(final_validation$warnings) > 0) {
    cat("\n📋 Performance Notes:\n")
    for (warning in final_validation$warnings) {
      cat(sprintf("  %s\n", warning))
    }
  }
  
  # Print achievable DPPP values for reference
  achievable_dppp <- calculate_achievable_dppp(mean_fwhm, nrow(all_windows), instrument_config)
  cat(sprintf("\n📊 Achievable DPPP values for %s:\n", instrument_config$name))
  cat(sprintf("  At max rate (%.0f Hz): DPPP = %.2f\n", 
              achievable_dppp$max_rate$scan_rate_hz, achievable_dppp$max_rate$dppp))
  cat(sprintf("  At optimal rate (%.0f Hz): DPPP = %.2f\n", 
              achievable_dppp$optimal_rate$scan_rate_hz, achievable_dppp$optimal_rate$dppp))
  cat(sprintf("  Current setting (%.1f Hz): DPPP = %.2f\n", 
              scan_rate, final_dppp))
  
  return(list(
    windows = all_windows,
    n_windows = nrow(all_windows),
    dppp = final_dppp,
    cycle_time = final_cycle_time_seconds,
    scan_rate = scan_rate,
    validation = validation,
    filtered_data = data_filtered
  ))
}

#' Apply overlap to windows
#' 
#' @param windows Data frame with windows
#' @param overlap_mode "none", "fixed", or "percentage"
#' @param overlap_value Overlap value
#' @return Modified windows with overlap
apply_overlap <- function(windows, overlap_mode, overlap_value) {
  
  if (overlap_mode == "none") {
    return(windows)
  }
  
  # Sort windows by center m/z
  windows <- windows %>% arrange(center_mz)
  
  for (i in 1:nrow(windows)) {
    if (overlap_mode == "fixed") {
      # Fixed overlap in Da
      windows$window_start[i] <- windows$window_start[i] - overlap_value / 2
      windows$window_end[i] <- windows$window_end[i] + overlap_value / 2
    } else if (overlap_mode == "percentage") {
      # Percentage overlap
      overlap_da <- windows$window_width[i] * overlap_value / 100
      windows$window_start[i] <- windows$window_start[i] - overlap_da / 2
      windows$window_end[i] <- windows$window_end[i] + overlap_da / 2
    }
    
    # Update width and center
    windows$window_width[i] <- windows$window_end[i] - windows$window_start[i]
    windows$center_mz[i] <- (windows$window_start[i] + windows$window_end[i]) / 2
  }
  
  return(windows)
}

#' Validate constraints for optimized windows
#' 
#' @param windows Optimized windows
#' @param instrument_config Instrument configuration
#' @param data Original data
#' @return List with validation results
validate_constraints <- function(windows, instrument_config, data) {
  
  warnings <- character()
  
  # Check window width constraints
  min_width <- min(windows$window_width)
  max_width <- max(windows$window_width)
  
  if (min_width < 2.0) {
    warnings <- c(warnings, sprintf("Window width below 2 Da: %.1f Da", min_width))
  }
  
  if (max_width > 80.0) {
    warnings <- c(warnings, sprintf("Window width above 80 Da: %.1f Da", max_width))
  }
  
  # Check scan rate
  cycle_time <- calculate_cycle_time(
    nrow(windows),
    instrument_config$ms1_time,
    instrument_config$ms2_time,
    instrument_config$cycle_calculation
  )
  
  scan_rate <- 1 / cycle_time
  
  if (scan_rate > instrument_config$max_scan_rate) {
    warnings <- c(warnings, 
                 sprintf("Scan rate (%.1f Hz) exceeds limit (%.1f Hz)",
                        scan_rate, instrument_config$max_scan_rate))
  }
  
  # Check coverage
  mz_coverage <- c(min(windows$window_start), max(windows$window_end))
  data_range <- range(data$Precursor.Mz)
  
  uncovered_low <- data_range[1] < mz_coverage[1]
  uncovered_high <- data_range[2] > mz_coverage[2]
  
  if (uncovered_low || uncovered_high) {
    warnings <- c(warnings, "Some precursors are outside window coverage")
  }
  
  # Calculate precursor coverage
  covered_precursors <- 0
  for (i in 1:nrow(windows)) {
    in_window <- data$Precursor.Mz >= windows$window_start[i] & 
                 data$Precursor.Mz <= windows$window_end[i]
    covered_precursors <- covered_precursors + sum(in_window)
  }
  
  coverage_pct <- 100 * covered_precursors / nrow(data)
  
  return(list(
    valid = length(warnings) == 0,
    warnings = warnings,
    coverage_pct = coverage_pct,
    min_width = min_width,
    max_width = max_width,
    scan_rate = scan_rate
  ))
}

# ============================================================================
# Module 3: RT-Dependent Density Analyzer
# Enhanced RT × m/z density analysis with dynamicDIA integration
# ============================================================================

#' Analyze RT-dependent m/z distribution (2D density)
#'
#' Creates a 2D histogram of precursor distribution across RT and m/z dimensions
#' to identify high-density regions and optimize window placement.
#'
#' @param data DIA-NN data frame with RT.Start and Precursor.Mz columns
#' @param rt_bins Number of RT bins (default: 50)
#' @param mz_bins Number of m/z bins (default: 50)
#' @param rt_range Optional RT range to analyze (default: full range)
#' @param mz_range Optional m/z range to analyze (default: full range)
#' @return List with 2D density data and bin information
#' @export
analyze_rt_dependent_density <- function(data,
                                        rt_bins = 50,
                                        mz_bins = 50,
                                        rt_range = NULL,
                                        mz_range = NULL) {

  cat("\n=== RT-Dependent Density Analysis ===\n")

  # Validate input
  if (!all(c("RT.Start", "Precursor.Mz") %in% names(data))) {
    stop("Data must contain 'RT.Start' and 'Precursor.Mz' columns")
  }

  # Filter data by ranges if specified
  analysis_data <- data
  if (!is.null(rt_range)) {
    analysis_data <- analysis_data %>%
      filter(RT.Start >= rt_range[1], RT.Start <= rt_range[2])
  }
  if (!is.null(mz_range)) {
    analysis_data <- analysis_data %>%
      filter(Precursor.Mz >= mz_range[1], Precursor.Mz <= mz_range[2])
  }

  cat(sprintf("Analyzing %d precursors\n", nrow(analysis_data)))

  # Determine actual ranges
  rt_min <- min(analysis_data$RT.Start, na.rm = TRUE)
  rt_max <- max(analysis_data$RT.Start, na.rm = TRUE)
  mz_min <- min(analysis_data$Precursor.Mz, na.rm = TRUE)
  mz_max <- max(analysis_data$Precursor.Mz, na.rm = TRUE)

  cat(sprintf("RT range: %.2f - %.2f min\n", rt_min, rt_max))
  cat(sprintf("m/z range: %.1f - %.1f\n", mz_min, mz_max))

  # Create bin edges
  rt_breaks <- seq(rt_min, rt_max, length.out = rt_bins + 1)
  mz_breaks <- seq(mz_min, mz_max, length.out = mz_bins + 1)

  # Assign bins to each precursor
  analysis_data <- analysis_data %>%
    mutate(
      rt_bin = cut(RT.Start, breaks = rt_breaks, labels = FALSE, include.lowest = TRUE),
      mz_bin = cut(Precursor.Mz, breaks = mz_breaks, labels = FALSE, include.lowest = TRUE)
    )

  # Create 2D density matrix
  density_matrix <- matrix(0, nrow = rt_bins, ncol = mz_bins)

  for (i in 1:nrow(analysis_data)) {
    rt_idx <- analysis_data$rt_bin[i]
    mz_idx <- analysis_data$mz_bin[i]

    if (!is.na(rt_idx) && !is.na(mz_idx)) {
      density_matrix[rt_idx, mz_idx] <- density_matrix[rt_idx, mz_idx] + 1
    }
  }

  # Calculate bin centers
  rt_centers <- (rt_breaks[-length(rt_breaks)] + rt_breaks[-1]) / 2
  mz_centers <- (mz_breaks[-length(mz_breaks)] + mz_breaks[-1]) / 2

  # Calculate statistics
  total_precursors <- sum(density_matrix)
  max_density <- max(density_matrix)
  mean_density <- mean(density_matrix)
  median_density <- median(density_matrix)

  # Calculate density percentiles
  density_percentiles <- quantile(as.vector(density_matrix),
                                  probs = c(0.25, 0.50, 0.75, 0.90, 0.95, 0.99))

  cat(sprintf("\nDensity Statistics:\n"))
  cat(sprintf("  Total precursors: %d\n", total_precursors))
  cat(sprintf("  Max density (single bin): %d\n", max_density))
  cat(sprintf("  Mean density: %.1f\n", mean_density))
  cat(sprintf("  Median density: %.1f\n", median_density))
  cat(sprintf("  P90 density: %.1f\n", density_percentiles["90%"]))
  cat(sprintf("  P95 density: %.1f\n", density_percentiles["95%"]))

  # Return comprehensive results
  result <- list(
    density_matrix = density_matrix,
    rt_centers = rt_centers,
    mz_centers = mz_centers,
    rt_breaks = rt_breaks,
    mz_breaks = mz_breaks,
    rt_bin_width = (rt_max - rt_min) / rt_bins,
    mz_bin_width = (mz_max - mz_min) / mz_bins,
    statistics = list(
      total_precursors = total_precursors,
      max_density = max_density,
      mean_density = mean_density,
      median_density = median_density,
      percentiles = density_percentiles
    ),
    data = analysis_data
  )

  class(result) <- c("rt_density_analysis", "list")

  cat("\n✓ RT-dependent density analysis complete\n")

  return(result)
}

#' Identify high-density regions in RT × m/z space
#'
#' Detects regions with precursor density above specified threshold.
#' Useful for adaptive window sizing and identifying crowded areas.
#'
#' @param density_analysis Output from analyze_rt_dependent_density()
#' @param threshold_percentile Percentile threshold for high-density (default: 0.90)
#' @param min_region_size Minimum number of adjacent bins to form a region (default: 4)
#' @return List with high-density region information
#' @export
identify_high_density_regions <- function(density_analysis,
                                         threshold_percentile = 0.90,
                                         min_region_size = 4) {

  cat("\n=== Identifying High-Density Regions ===\n")

  # Calculate threshold
  threshold <- quantile(as.vector(density_analysis$density_matrix),
                       probs = threshold_percentile)

  cat(sprintf("Threshold (P%.0f): %.1f precursors/bin\n",
              threshold_percentile * 100, threshold))

  # Create binary matrix of high-density bins
  high_density_mask <- density_analysis$density_matrix > threshold

  # Count high-density bins
  n_high_density_bins <- sum(high_density_mask)
  pct_high_density <- 100 * n_high_density_bins / length(high_density_mask)

  cat(sprintf("High-density bins: %d (%.1f%% of total)\n",
              n_high_density_bins, pct_high_density))

  # Extract high-density coordinates
  high_density_coords <- which(high_density_mask, arr.ind = TRUE)

  if (nrow(high_density_coords) == 0) {
    cat("⚠ No high-density regions found at this threshold\n")
    return(list(
      n_regions = 0,
      threshold = threshold,
      high_density_mask = high_density_mask,
      regions = list()
    ))
  }

  # Convert to RT and m/z coordinates
  high_density_regions <- data.frame(
    rt_bin = high_density_coords[, 1],
    mz_bin = high_density_coords[, 2],
    rt_center = density_analysis$rt_centers[high_density_coords[, 1]],
    mz_center = density_analysis$mz_centers[high_density_coords[, 2]],
    density = density_analysis$density_matrix[high_density_coords]
  ) %>%
    arrange(desc(density))

  # Group into contiguous regions (simple clustering by RT proximity)
  high_density_regions <- high_density_regions %>%
    arrange(rt_bin, mz_bin) %>%
    mutate(
      rt_group = cumsum(c(1, diff(rt_bin) > 2)),  # New group if RT gap > 2 bins
      region_id = paste0("R", rt_group)
    )

  # Summarize regions
  region_summary <- high_density_regions %>%
    group_by(region_id) %>%
    summarise(
      rt_min = min(rt_center),
      rt_max = max(rt_center),
      mz_min = min(mz_center),
      mz_max = max(mz_center),
      n_bins = n(),
      total_precursors = sum(density),
      mean_density = mean(density),
      max_density = max(density),
      .groups = "drop"
    ) %>%
    filter(n_bins >= min_region_size) %>%  # Filter by minimum size
    arrange(desc(total_precursors))

  cat(sprintf("\nIdentified %d high-density regions (>= %d bins)\n",
              nrow(region_summary), min_region_size))

  if (nrow(region_summary) > 0) {
    cat("\nTop 3 regions by precursor count:\n")
    for (i in 1:min(3, nrow(region_summary))) {
      cat(sprintf("  %s: RT %.1f-%.1f, m/z %.1f-%.1f, %d precursors\n",
                  region_summary$region_id[i],
                  region_summary$rt_min[i],
                  region_summary$rt_max[i],
                  region_summary$mz_min[i],
                  region_summary$mz_max[i],
                  region_summary$total_precursors[i]))
    }
  }

  return(list(
    n_regions = nrow(region_summary),
    threshold = threshold,
    threshold_percentile = threshold_percentile,
    high_density_mask = high_density_mask,
    regions = region_summary,
    region_details = high_density_regions
  ))
}

#' Apply dynamicDIA smoothing to RT-dependent m/z boundaries
#'
#' Integrates with dynamicDIA.R to apply professional smoothing methods
#' (Savitzky-Golay, moving average, Gaussian) to RT-dependent m/z ranges.
#'
#' @param density_analysis Output from analyze_rt_dependent_density()
#' @param method Smoothing method: "savgol", "movav", or "gaussian"
#' @param window_size Smoothing window size (default: 7)
#' @param polynomial_order Polynomial order for Savitzky-Golay (default: 3)
#' @param sigma Sigma for Gaussian smoothing (default: 1.0)
#' @return List with smoothed boundaries and comparison data
#' @export
apply_dynamicDIA_smoothing <- function(density_analysis,
                                      method = "savgol",
                                      window_size = 7,
                                      polynomial_order = 3,
                                      sigma = 1.0) {

  cat(sprintf("\n=== Applying dynamicDIA Smoothing (%s) ===\n", method))

  # Source dynamicDIA functions if not already loaded
  if (!exists("smooth_boundaries")) {
    source("R/dynamicDIA.R")
  }

  # Extract RT-dependent m/z boundaries from density matrix
  # For each RT bin, find the m/z range that covers high-density regions
  n_rt_bins <- nrow(density_analysis$density_matrix)

  raw_mz_low <- numeric(n_rt_bins)
  raw_mz_high <- numeric(n_rt_bins)

  for (i in 1:n_rt_bins) {
    rt_row <- density_analysis$density_matrix[i, ]

    # Find non-zero density range
    nonzero_idx <- which(rt_row > 0)

    if (length(nonzero_idx) > 0) {
      raw_mz_low[i] <- density_analysis$mz_centers[min(nonzero_idx)]
      raw_mz_high[i] <- density_analysis$mz_centers[max(nonzero_idx)]
    } else {
      # No precursors in this RT bin - use previous or overall range
      if (i > 1) {
        raw_mz_low[i] <- raw_mz_low[i - 1]
        raw_mz_high[i] <- raw_mz_high[i - 1]
      } else {
        raw_mz_low[i] <- min(density_analysis$mz_centers)
        raw_mz_high[i] <- max(density_analysis$mz_centers)
      }
    }
  }

  cat(sprintf("Raw m/z boundaries extracted from density matrix\n"))
  cat(sprintf("RT bins: %d\n", n_rt_bins))

  # Apply smoothing using dynamicDIA functions
  if (method == "savgol") {
    smooth_mz_low <- smooth_boundaries(raw_mz_low, method = "savgol",
                                      window_size = window_size,
                                      poly_order = polynomial_order)
    smooth_mz_high <- smooth_boundaries(raw_mz_high, method = "savgol",
                                       window_size = window_size,
                                       poly_order = polynomial_order)
  } else if (method == "movav") {
    smooth_mz_low <- smooth_boundaries(raw_mz_low, method = "movav",
                                      window_size = window_size)
    smooth_mz_high <- smooth_boundaries(raw_mz_high, method = "movav",
                                       window_size = window_size)
  } else if (method == "gaussian") {
    smooth_mz_low <- smooth_boundaries(raw_mz_low, method = "gaussian",
                                      sigma = sigma)
    smooth_mz_high <- smooth_boundaries(raw_mz_high, method = "gaussian",
                                       sigma = sigma)
  } else {
    stop(sprintf("Unknown smoothing method: %s. Use 'savgol', 'movav', or 'gaussian'", method))
  }

  # Handle length mismatch due to edge effects in smoothing
  # Some smoothing methods (especially prospectr) may truncate edges
  rt_centers <- density_analysis$rt_centers
  if (length(smooth_mz_low) != length(raw_mz_low)) {
    warning("Smoothing changed array length. Adjusting RT centers to match.")
    # Calculate the offset and truncate raw data and RT centers accordingly
    offset <- (n_rt_bins - length(smooth_mz_low)) %/% 2
    if (offset > 0) {
      indices <- (offset + 1):(offset + length(smooth_mz_low))
      raw_mz_low <- raw_mz_low[indices]
      raw_mz_high <- raw_mz_high[indices]
      rt_centers <- rt_centers[indices]
      n_rt_bins <- length(smooth_mz_low)
    } else if (offset < 0) {
      # Smoothing returned longer array (rare) - truncate smoothed
      smooth_mz_low <- smooth_mz_low[1:length(raw_mz_low)]
      smooth_mz_high <- smooth_mz_high[1:length(raw_mz_high)]
    }
  }

  cat(sprintf("✓ Smoothing applied using %s method\n", method))
  cat(sprintf("  Output length: %d RT bins\n", length(smooth_mz_low)))

  # Calculate smoothing effect metrics
  delta_low <- abs(smooth_mz_low - raw_mz_low)
  delta_high <- abs(smooth_mz_high - raw_mz_high)

  smoothing_stats <- list(
    mean_delta_low = mean(delta_low),
    max_delta_low = max(delta_low),
    mean_delta_high = mean(delta_high),
    max_delta_high = max(delta_high),
    total_range_change = sum(delta_low) + sum(delta_high)
  )

  cat(sprintf("\nSmoothing Effect:\n"))
  cat(sprintf("  Mean Δm/z (low): %.2f Da\n", smoothing_stats$mean_delta_low))
  cat(sprintf("  Max Δm/z (low): %.2f Da\n", smoothing_stats$max_delta_low))
  cat(sprintf("  Mean Δm/z (high): %.2f Da\n", smoothing_stats$mean_delta_high))
  cat(sprintf("  Max Δm/z (high): %.2f Da\n", smoothing_stats$max_delta_high))

  # Return comprehensive results
  result <- list(
    method = method,
    parameters = list(
      window_size = window_size,
      polynomial_order = polynomial_order,
      sigma = sigma
    ),
    rt_centers = rt_centers,  # Use adjusted rt_centers, not original
    raw_boundaries = list(
      mz_low = raw_mz_low,
      mz_high = raw_mz_high
    ),
    smoothed_boundaries = list(
      mz_low = smooth_mz_low,
      mz_high = smooth_mz_high
    ),
    smoothing_stats = smoothing_stats,
    density_analysis = density_analysis
  )

  class(result) <- c("dynamicDIA_smoothing", "list")

  cat("\n✓ dynamicDIA smoothing complete\n")

  return(result)
}

#' Compare different smoothing methods
#'
#' Applies all three smoothing methods (Savitzky-Golay, moving average, Gaussian)
#' and compares their effects on RT-dependent m/z boundaries.
#'
#' @param density_analysis Output from analyze_rt_dependent_density()
#' @param window_size Smoothing window size (default: 7)
#' @param polynomial_order Polynomial order for Savitzky-Golay (default: 3)
#' @param sigma Sigma for Gaussian smoothing (default: 1.0)
#' @return List with all smoothing results and comparison metrics
#' @export
compare_smoothing_methods <- function(density_analysis,
                                     window_size = 7,
                                     polynomial_order = 3,
                                     sigma = 1.0) {

  cat("\n=== Comparing Smoothing Methods ===\n")

  # Apply all three methods
  savgol_result <- apply_dynamicDIA_smoothing(
    density_analysis,
    method = "savgol",
    window_size = window_size,
    polynomial_order = polynomial_order
  )

  movav_result <- apply_dynamicDIA_smoothing(
    density_analysis,
    method = "movav",
    window_size = window_size
  )

  gaussian_result <- apply_dynamicDIA_smoothing(
    density_analysis,
    method = "gaussian",
    sigma = sigma
  )

  # Create comparison summary
  comparison <- data.frame(
    Method = c("Savitzky-Golay", "Moving Average", "Gaussian"),
    Mean_Delta_Low = c(
      savgol_result$smoothing_stats$mean_delta_low,
      movav_result$smoothing_stats$mean_delta_low,
      gaussian_result$smoothing_stats$mean_delta_low
    ),
    Max_Delta_Low = c(
      savgol_result$smoothing_stats$max_delta_low,
      movav_result$smoothing_stats$max_delta_low,
      gaussian_result$smoothing_stats$max_delta_low
    ),
    Mean_Delta_High = c(
      savgol_result$smoothing_stats$mean_delta_high,
      movav_result$smoothing_stats$mean_delta_high,
      gaussian_result$smoothing_stats$mean_delta_high
    ),
    Max_Delta_High = c(
      savgol_result$smoothing_stats$max_delta_high,
      movav_result$smoothing_stats$max_delta_high,
      gaussian_result$smoothing_stats$max_delta_high
    ),
    Total_Range_Change = c(
      savgol_result$smoothing_stats$total_range_change,
      movav_result$smoothing_stats$total_range_change,
      gaussian_result$smoothing_stats$total_range_change
    )
  )

  cat("\n=== Smoothing Method Comparison ===\n")
  print(comparison, row.names = FALSE)

  # Recommend best method (least aggressive = smallest total change)
  best_idx <- which.min(comparison$Total_Range_Change)
  best_method <- comparison$Method[best_idx]

  cat(sprintf("\n💡 Recommended method: %s (smallest boundary change)\n", best_method))

  return(list(
    savgol = savgol_result,
    movav = movav_result,
    gaussian = gaussian_result,
    comparison = comparison,
    recommended_method = tolower(gsub(" ", "", best_method))
  ))
}