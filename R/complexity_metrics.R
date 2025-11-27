# complexity_metrics.R - DIA Spectra Complexity Measurement
# DIA Window Optimizer v2.2
#
# Purpose: Measure and quantify the complexity of LC-MS DIA spectra
# to guide window optimization and predict data quality.
#
# Metrics Implemented:
#   - PCI (Precursor Co-isolation Index): Co-isolated precursors per window
#   - RCI (RT Crowding Index): RT-dimension precursor density distribution
#   - MSS (m/z Spacing Score): m/z dimension precursor spacing
#   - CSI (Chimeric Spectrum Index): Expected chimeric spectrum ratio
#   - CHS (Complexity Heatmap Score): 2D RT×m/z density distribution
#   - UDCS (Unified DIA Complexity Score): Integrated complexity score
#
# Author: DIAoptimizer Team
# Version: 1.0
# Last Updated: 2025-11-27

library(dplyr)
library(tibble)

# =============================================================================
# Helper Functions
# =============================================================================

#' Calculate Gini Coefficient
#'
#' Measures inequality in distribution (0 = perfect equality, 1 = maximum inequality)
#'
#' @param x Numeric vector of values
#' @return Numeric, Gini coefficient between 0 and 1
calculate_gini <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0 || all(x == 0)) return(0)

  x <- sort(x)
  n <- length(x)

  # Gini formula: G = (2 * sum(i * x[i])) / (n * sum(x)) - (n + 1) / n
  numerator <- 2 * sum(seq_along(x) * x)
  denominator <- n * sum(x)

  gini <- (numerator / denominator) - (n + 1) / n
  return(max(0, min(1, gini)))  # Clamp to [0, 1]
}

#' Calculate Shannon Entropy
#'
#' Measures uniformity of distribution (higher = more uniform)
#'
#' @param x Numeric vector (will be normalized to probabilities)
#' @return Numeric, normalized entropy between 0 and 1
calculate_entropy <- function(x) {
  x <- x[!is.na(x) & x > 0]
  if (length(x) == 0) return(0)

  # Normalize to probabilities
  p <- x / sum(x)

  # Shannon entropy: H = -sum(p * log2(p))
  entropy <- -sum(p * log2(p))

  # Normalize by maximum possible entropy (uniform distribution)
  max_entropy <- log2(length(p))

  if (max_entropy == 0) return(1)
  return(entropy / max_entropy)
}


# =============================================================================
# PCI: Precursor Co-isolation Index
# =============================================================================

#' Calculate Precursor Co-isolation Index (PCI)
#'
#' Measures the average number of precursors co-isolated in a DIA window.
#' This is the most direct measure of spectral complexity.
#'
#' Algorithm:
#' 1. For each precursor, count how many other precursors fall within
#'    the same RT × m/z window
#' 2. Summarize the distribution of co-isolation counts
#'
#' Interpretation:
#'   - PCI = 0: Ideal (no co-isolation)
#'   - PCI = 1-3: Low complexity (good)
#'   - PCI = 4-10: Moderate complexity (manageable)
#'   - PCI > 10: High complexity (difficult deconvolution)
#'
#' @param data Tibble with RT.Start and Precursor.Mz columns
#' @param rt_window_sec RT window width in seconds (default: 60, ~1 min elution)
#' @param mz_window_da m/z window width in Da (default: 25 Da typical DIA width)
#' @param sample_size Integer, number of precursors to sample for speed (default: NULL = all)
#'
#' @return List with PCI statistics and distribution
#' @export
#'
#' @examples
#' pci <- calculate_pci(validated_data$data, rt_window_sec = 60, mz_window_da = 25)
#' print(pci$mean_pci)
calculate_pci <- function(data,
                          rt_window_sec = 60,
                          mz_window_da = 25,
                          sample_size = NULL) {

  # Validate inputs
  if (!all(c("RT.Start", "Precursor.Mz") %in% names(data))) {
    stop("Data must contain RT.Start and Precursor.Mz columns")
  }

  n_total <- nrow(data)
  rt_window_min <- rt_window_sec / 60

  # Sampling for large datasets
  if (!is.null(sample_size) && sample_size < n_total) {
    sample_idx <- sample(n_total, sample_size)
  } else {
    sample_idx <- seq_len(n_total)
  }

  # Vectorized co-isolation counting
  # For each sampled precursor, count neighbors
  rt_values <- data$RT.Start
  mz_values <- data$Precursor.Mz

  co_isolation_counts <- vapply(sample_idx, function(i) {
    target_rt <- rt_values[i]
    target_mz <- mz_values[i]

    # Count precursors within window (excluding self)
    in_rt_window <- abs(rt_values - target_rt) <= rt_window_min / 2
    in_mz_window <- abs(mz_values - target_mz) <= mz_window_da / 2
    in_window <- in_rt_window & in_mz_window

    sum(in_window) - 1  # Exclude self
  }, FUN.VALUE = numeric(1))

  # Calculate statistics
  result <- list(
    mean_pci = mean(co_isolation_counts),
    median_pci = median(co_isolation_counts),
    sd_pci = sd(co_isolation_counts),
    min_pci = min(co_isolation_counts),
    max_pci = max(co_isolation_counts),

    # Quantiles
    p25_pci = quantile(co_isolation_counts, 0.25, names = FALSE),
    p75_pci = quantile(co_isolation_counts, 0.75, names = FALSE),
    p95_pci = quantile(co_isolation_counts, 0.95, names = FALSE),

    # Distribution summary
    n_clean = sum(co_isolation_counts == 0),        # No co-isolation
    n_low = sum(co_isolation_counts >= 1 & co_isolation_counts <= 3),
    n_moderate = sum(co_isolation_counts >= 4 & co_isolation_counts <= 10),
    n_high = sum(co_isolation_counts > 10),

    # Metadata
    n_sampled = length(sample_idx),
    n_total = n_total,
    rt_window_sec = rt_window_sec,
    mz_window_da = mz_window_da,

    # Raw distribution (for plotting)
    distribution = co_isolation_counts,

    # Interpretation
    complexity_level = case_when(
      mean(co_isolation_counts) <= 1 ~ "very_low",
      mean(co_isolation_counts) <= 3 ~ "low",
      mean(co_isolation_counts) <= 7 ~ "moderate",
      mean(co_isolation_counts) <= 15 ~ "high",
      TRUE ~ "very_high"
    )
  )

  class(result) <- c("PCI", "list")
  return(result)
}


# =============================================================================
# RCI: RT Crowding Index
# =============================================================================

#' Calculate RT Crowding Index (RCI)
#'
#' Measures the uniformity of precursor distribution across the RT gradient.
#' High crowding in specific RT regions increases spectral complexity.
#'
#' Metrics:
#'   - Gini coefficient: 0 = uniform, 1 = extremely uneven
#'   - Peak-to-average ratio: How much denser is the busiest region
#'   - CV of RT density: Coefficient of variation
#'   - Hotspot detection: RT regions with >2σ precursor density
#'
#' @param data Tibble with RT.Start column
#' @param n_bins Integer, number of RT bins (default: 50)
#'
#' @return List with RCI statistics
#' @export
calculate_rci <- function(data, n_bins = 50) {

  if (!"RT.Start" %in% names(data)) {
    stop("Data must contain RT.Start column")
  }

  rt_values <- data$RT.Start
  rt_range <- range(rt_values, na.rm = TRUE)
  gradient_length_min <- diff(rt_range)

  # Create RT histogram
  bin_width <- gradient_length_min / n_bins
  breaks <- seq(rt_range[1], rt_range[2], length.out = n_bins + 1)

  hist_result <- hist(rt_values, breaks = breaks, plot = FALSE)
  rt_counts <- hist_result$counts
  bin_mids <- hist_result$mids

  # Calculate metrics
  expected_per_bin <- nrow(data) / n_bins

  # Density per minute
  density_per_min <- rt_counts / bin_width

  # Gini coefficient
  gini <- calculate_gini(rt_counts)

  # Peak-to-average ratio
  peak_to_avg <- max(rt_counts) / mean(rt_counts)

  # Coefficient of variation
  rt_density_cv <- sd(rt_counts) / mean(rt_counts) * 100

  # Hotspot detection (>2σ above mean)
  threshold <- mean(rt_counts) + 2 * sd(rt_counts)
  hotspot_bins <- which(rt_counts > threshold)
  hotspot_rt_ranges <- if (length(hotspot_bins) > 0) {
    data.frame(
      bin_idx = hotspot_bins,
      rt_start = breaks[hotspot_bins],
      rt_end = breaks[hotspot_bins + 1],
      precursor_count = rt_counts[hotspot_bins],
      fold_over_mean = rt_counts[hotspot_bins] / mean(rt_counts)
    )
  } else {
    NULL
  }

  # Entropy (uniformity measure)
  uniformity <- calculate_entropy(rt_counts)

  result <- list(
    # Core metrics
    gini_coefficient = gini,
    peak_to_avg_ratio = peak_to_avg,
    rt_density_cv = rt_density_cv,
    uniformity_score = uniformity,

    # Gradient info
    gradient_length_min = gradient_length_min,
    n_bins = n_bins,
    bin_width_min = bin_width,

    # Statistics
    mean_per_bin = mean(rt_counts),
    sd_per_bin = sd(rt_counts),
    min_per_bin = min(rt_counts),
    max_per_bin = max(rt_counts),

    # Density per minute
    mean_density_per_min = mean(density_per_min),
    max_density_per_min = max(density_per_min),

    # Hotspots
    n_hotspots = length(hotspot_bins),
    hotspot_threshold = threshold,
    hotspot_details = hotspot_rt_ranges,

    # Distribution data (for plotting)
    bin_mids = bin_mids,
    bin_counts = rt_counts,
    density_per_min = density_per_min,

    # Interpretation
    crowding_level = case_when(
      gini < 0.2 ~ "uniform",
      gini < 0.35 ~ "slight_crowding",
      gini < 0.5 ~ "moderate_crowding",
      TRUE ~ "severe_crowding"
    )
  )

  class(result) <- c("RCI", "list")
  return(result)
}


# =============================================================================
# MSS: m/z Spacing Score
# =============================================================================

#' Calculate m/z Spacing Score (MSS)
#'
#' Measures the spacing between precursors in the m/z dimension within RT bins.
#' Close spacing indicates potential interference and complexity.
#'
#' Critical threshold: <0.01 Da spacing is essentially indistinguishable
#'
#' @param data Tibble with RT.Start and Precursor.Mz columns
#' @param rt_bin_width_min RT bin width in minutes (default: 1.0)
#'
#' @return List with MSS statistics and per-RT-bin details
#' @export
calculate_mss <- function(data, rt_bin_width_min = 1.0) {

  if (!all(c("RT.Start", "Precursor.Mz") %in% names(data))) {
    stop("Data must contain RT.Start and Precursor.Mz columns")
  }

  # Assign RT bins
  rt_range <- range(data$RT.Start, na.rm = TRUE)
  data <- data %>%
    mutate(rt_bin = floor((RT.Start - rt_range[1]) / rt_bin_width_min))

  # Calculate spacing within each RT bin
  spacing_by_bin <- data %>%
    group_by(rt_bin) %>%
    arrange(Precursor.Mz) %>%
    mutate(
      mz_spacing = Precursor.Mz - lag(Precursor.Mz)
    ) %>%
    filter(!is.na(mz_spacing)) %>%
    summarise(
      n_precursors = n() + 1,  # +1 for first precursor
      n_pairs = n(),
      mean_spacing = mean(mz_spacing),
      min_spacing = min(mz_spacing),
      max_spacing = max(mz_spacing),
      sd_spacing = sd(mz_spacing),
      n_critical = sum(mz_spacing < 0.01),     # Essentially same m/z
      n_very_close = sum(mz_spacing < 0.1),    # Very close
      n_close = sum(mz_spacing < 1.0),         # Within 1 Da
      .groups = "drop"
    )

  # Global statistics
  all_spacings <- data %>%
    group_by(rt_bin) %>%
    arrange(Precursor.Mz) %>%
    mutate(mz_spacing = Precursor.Mz - lag(Precursor.Mz)) %>%
    filter(!is.na(mz_spacing)) %>%
    pull(mz_spacing)

  total_pairs <- length(all_spacings)

  result <- list(
    # Global metrics
    global_mean_spacing = mean(all_spacings),
    global_median_spacing = median(all_spacings),
    global_min_spacing = min(all_spacings),
    global_max_spacing = max(all_spacings),
    global_sd_spacing = sd(all_spacings),

    # Critical pair statistics
    n_critical_pairs = sum(all_spacings < 0.01),
    n_very_close_pairs = sum(all_spacings < 0.1),
    n_close_pairs = sum(all_spacings < 1.0),

    # Ratios
    critical_pair_ratio = sum(all_spacings < 0.01) / total_pairs,
    very_close_pair_ratio = sum(all_spacings < 0.1) / total_pairs,
    close_pair_ratio = sum(all_spacings < 1.0) / total_pairs,

    # Quantiles
    spacing_p5 = quantile(all_spacings, 0.05, names = FALSE),
    spacing_p25 = quantile(all_spacings, 0.25, names = FALSE),
    spacing_p75 = quantile(all_spacings, 0.75, names = FALSE),
    spacing_p95 = quantile(all_spacings, 0.95, names = FALSE),

    # Per-bin details
    n_bins = nrow(spacing_by_bin),
    rt_bin_width_min = rt_bin_width_min,
    spacing_by_rt = spacing_by_bin,

    # Raw data
    all_spacings = all_spacings,
    total_pairs = total_pairs,

    # Interpretation
    spacing_level = case_when(
      mean(all_spacings) > 2.0 ~ "well_spaced",
      mean(all_spacings) > 1.0 ~ "adequate_spacing",
      mean(all_spacings) > 0.5 ~ "moderate_crowding",
      mean(all_spacings) > 0.1 ~ "dense",
      TRUE ~ "very_dense"
    )
  )

  class(result) <- c("MSS", "list")
  return(result)
}


# =============================================================================
# CSI: Chimeric Spectrum Index
# =============================================================================

#' Calculate Chimeric Spectrum Index (CSI)
#'
#' Predicts the proportion of chimeric spectra (multiple precursors fragmented
#' together) based on defined DIA windows.
#'
#' Chimeric spectrum: DIA window contains >1 eluting precursor
#'
#' @param data Tibble with RT.Start and Precursor.Mz columns
#' @param windows Tibble with rt_start, rt_end, mz_start, mz_end columns
#'        If NULL, uses simulated windows based on typical DIA settings
#' @param rt_tolerance_sec Additional RT tolerance in seconds (default: 30)
#'
#' @return List with CSI statistics
#' @export
calculate_csi <- function(data,
                          windows = NULL,
                          rt_tolerance_sec = 30) {

  if (!all(c("RT.Start", "Precursor.Mz") %in% names(data))) {
    stop("Data must contain RT.Start and Precursor.Mz columns")
  }

  rt_tolerance_min <- rt_tolerance_sec / 60

  # If no windows provided, create simulated windows
  if (is.null(windows)) {
    # Create a grid of typical DIA windows
    rt_range <- range(data$RT.Start, na.rm = TRUE)
    mz_range <- range(data$Precursor.Mz, na.rm = TRUE)

    # Simulate ~20 m/z windows across the range, 1-min RT bins
    mz_width <- 25  # Da
    n_mz_windows <- ceiling(diff(mz_range) / mz_width)

    rt_bin_width <- 1.0  # minutes
    n_rt_bins <- ceiling(diff(rt_range) / rt_bin_width)

    # Create window grid
    windows <- expand.grid(
      rt_bin = seq_len(n_rt_bins),
      mz_bin = seq_len(n_mz_windows)
    ) %>%
      mutate(
        rt_start = rt_range[1] + (rt_bin - 1) * rt_bin_width,
        rt_end = rt_start + rt_bin_width,
        mz_start = mz_range[1] + (mz_bin - 1) * mz_width,
        mz_end = mz_start + mz_width
      ) %>%
      select(rt_start, rt_end, mz_start, mz_end)
  }

  # Count precursors in each window (vectorized)
  precursor_rt <- data$RT.Start
  precursor_mz <- data$Precursor.Mz

  # Apply RT tolerance to window boundaries
  window_rt_start <- windows$rt_start - rt_tolerance_min
  window_rt_end <- windows$rt_end + rt_tolerance_min
  window_mz_start <- windows$mz_start
  window_mz_end <- windows$mz_end

  # Use vectorized counting
  precursors_per_window <- vapply(seq_len(nrow(windows)), function(i) {
    in_rt <- precursor_rt >= window_rt_start[i] & precursor_rt <= window_rt_end[i]
    in_mz <- precursor_mz >= window_mz_start[i] & precursor_mz <= window_mz_end[i]
    sum(in_rt & in_mz)
  }, FUN.VALUE = integer(1))

  # Calculate statistics
  n_windows <- length(precursors_per_window)
  n_clean <- sum(precursors_per_window <= 1)
  n_chimeric <- sum(precursors_per_window > 1)

  # Severity distribution
  severity <- cut(precursors_per_window,
                  breaks = c(-Inf, 1, 2, 5, 10, Inf),
                  labels = c("clean", "low", "medium", "high", "severe"))
  severity_table <- table(severity)

  result <- list(
    # Core metrics
    chimeric_ratio = n_chimeric / n_windows,
    clean_ratio = n_clean / n_windows,

    # Severity distribution
    n_clean = as.integer(severity_table["clean"]),
    n_low = as.integer(severity_table["low"]),
    n_medium = as.integer(severity_table["medium"]),
    n_high = as.integer(severity_table["high"]),
    n_severe = as.integer(severity_table["severe"]),

    # Co-isolation statistics
    mean_co_isolation = mean(precursors_per_window),
    median_co_isolation = median(precursors_per_window),
    max_co_isolation = max(precursors_per_window),
    sd_co_isolation = sd(precursors_per_window),

    # Window info
    n_windows = n_windows,
    n_windows_with_precursors = sum(precursors_per_window > 0),

    # Raw distribution
    precursors_per_window = precursors_per_window,

    # Interpretation
    chimeric_level = case_when(
      n_chimeric / n_windows < 0.1 ~ "minimal",
      n_chimeric / n_windows < 0.3 ~ "low",
      n_chimeric / n_windows < 0.5 ~ "moderate",
      n_chimeric / n_windows < 0.7 ~ "high",
      TRUE ~ "severe"
    )
  )

  class(result) <- c("CSI", "list")
  return(result)
}


# =============================================================================
# CHS: Complexity Heatmap Score
# =============================================================================

#' Calculate Complexity Heatmap Score (CHS)
#'
#' Creates a 2D density map of precursors in RT × m/z space and calculates
#' metrics describing the spatial distribution of complexity.
#'
#' @param data Tibble with RT.Start and Precursor.Mz columns
#' @param rt_bins Integer, number of RT bins (default: 50)
#' @param mz_bins Integer, number of m/z bins (default: 50)
#'
#' @return List with CHS statistics and density matrix
#' @export
calculate_chs <- function(data, rt_bins = 50, mz_bins = 50) {

  if (!all(c("RT.Start", "Precursor.Mz") %in% names(data))) {
    stop("Data must contain RT.Start and Precursor.Mz columns")
  }

  rt_range <- range(data$RT.Start, na.rm = TRUE)
  mz_range <- range(data$Precursor.Mz, na.rm = TRUE)

  rt_breaks <- seq(rt_range[1], rt_range[2], length.out = rt_bins + 1)
  mz_breaks <- seq(mz_range[1], mz_range[2], length.out = mz_bins + 1)

  # Create 2D histogram
  density_matrix <- matrix(0, nrow = rt_bins, ncol = mz_bins)

  rt_idx <- findInterval(data$RT.Start, rt_breaks, all.inside = TRUE)
  mz_idx <- findInterval(data$Precursor.Mz, mz_breaks, all.inside = TRUE)

  for (i in seq_len(nrow(data))) {
    density_matrix[rt_idx[i], mz_idx[i]] <- density_matrix[rt_idx[i], mz_idx[i]] + 1
  }

  # Calculate metrics
  total_cells <- rt_bins * mz_bins
  non_empty_cells <- sum(density_matrix > 0)
  empty_cells <- total_cells - non_empty_cells

  # Hotspot detection (>P95 density)
  p95_threshold <- quantile(density_matrix[density_matrix > 0], 0.95, na.rm = TRUE)
  n_hotspots <- sum(density_matrix > p95_threshold)

  # Find hotspot locations
  hotspot_locations <- which(density_matrix > p95_threshold, arr.ind = TRUE)
  if (nrow(hotspot_locations) > 0) {
    hotspot_details <- data.frame(
      rt_bin = hotspot_locations[, 1],
      mz_bin = hotspot_locations[, 2],
      rt_center = (rt_breaks[hotspot_locations[, 1]] + rt_breaks[hotspot_locations[, 1] + 1]) / 2,
      mz_center = (mz_breaks[hotspot_locations[, 2]] + mz_breaks[hotspot_locations[, 2] + 1]) / 2,
      density = density_matrix[hotspot_locations]
    )
  } else {
    hotspot_details <- NULL
  }

  # Spatial entropy
  spatial_entropy <- calculate_entropy(as.vector(density_matrix))

  result <- list(
    # Core metrics
    max_density = max(density_matrix),
    mean_density = mean(density_matrix),
    median_density = median(density_matrix[density_matrix > 0]),

    # Cell statistics
    total_cells = total_cells,
    non_empty_cells = non_empty_cells,
    empty_cells = empty_cells,
    occupancy_ratio = non_empty_cells / total_cells,
    empty_ratio = empty_cells / total_cells,

    # Hotspots
    p95_threshold = p95_threshold,
    n_hotspots = n_hotspots,
    hotspot_ratio = n_hotspots / non_empty_cells,
    hotspot_details = hotspot_details,

    # Distribution metrics
    spatial_entropy = spatial_entropy,
    density_cv = sd(density_matrix[density_matrix > 0]) / mean(density_matrix[density_matrix > 0]) * 100,

    # Grid info
    rt_bins = rt_bins,
    mz_bins = mz_bins,
    rt_range = rt_range,
    mz_range = mz_range,
    rt_breaks = rt_breaks,
    mz_breaks = mz_breaks,

    # Density matrix (for plotting)
    density_matrix = density_matrix,

    # Interpretation
    distribution_type = case_when(
      spatial_entropy > 0.8 ~ "uniform",
      spatial_entropy > 0.6 ~ "slightly_clustered",
      spatial_entropy > 0.4 ~ "moderately_clustered",
      TRUE ~ "highly_clustered"
    )
  )

  class(result) <- c("CHS", "list")
  return(result)
}


# =============================================================================
# UDCS: Unified DIA Complexity Score
# =============================================================================

#' Calculate Unified DIA Complexity Score (UDCS)
#'
#' Integrates all complexity metrics into a single score (0-100).
#' Higher score = more complex = harder to analyze.
#'
#' Components (each 0-25 points):
#'   1. Density component: Precursor density per minute
#'   2. Crowding component: RT distribution uniformity
#'   3. Spacing component: m/z spacing adequacy
#'   4. Chimeric component: Expected chimeric ratio
#'
#' @param data Tibble with RT.Start and Precursor.Mz columns
#' @param windows Optional window definitions for CSI calculation
#' @param verbose Logical, print progress messages (default: FALSE)
#'
#' @return List with UDCS score and component details
#' @export
calculate_udcs <- function(data, windows = NULL, verbose = FALSE) {

  if (!all(c("RT.Start", "Precursor.Mz") %in% names(data))) {
    stop("Data must contain RT.Start and Precursor.Mz columns")
  }

  n_precursors <- nrow(data)

  if (verbose) cat("Calculating Unified DIA Complexity Score (UDCS)...\n")

  # Component 1: Precursor Density (0-25 points)
  # Reference: 40 precursors/min = moderate, 100+ = high
  rt_span <- diff(range(data$RT.Start, na.rm = TRUE))
  precursors_per_min <- n_precursors / rt_span

  # Scoring: 0-25 scaled, capped at 100 precursors/min
  density_score <- min(25, precursors_per_min / 4)  # 100/min = 25 points

  if (verbose) cat(sprintf("  Density: %.1f precursors/min → %.1f points\n",
                           precursors_per_min, density_score))

  # Component 2: RT Crowding (0-25 points)
  # Based on Gini coefficient and peak-to-avg ratio
  rci <- calculate_rci(data, n_bins = 50)

  # Combine Gini (0-1) and peak-to-avg (1-inf) into score
  crowding_raw <- (rci$gini_coefficient * 15) + (min(rci$peak_to_avg_ratio, 4) - 1) * 5
  crowding_score <- min(25, crowding_raw)

  if (verbose) cat(sprintf("  Crowding: Gini=%.2f, Peak/Avg=%.1f → %.1f points\n",
                           rci$gini_coefficient, rci$peak_to_avg_ratio, crowding_score))

  # Component 3: m/z Spacing (0-25 points)
  # Reference: Mean spacing <0.5 Da = high complexity
  mss <- calculate_mss(data, rt_bin_width_min = 1.0)

  # Inverse relationship: smaller spacing = higher score
  # 2.0 Da mean = 0 points, 0.1 Da mean = 25 points
  spacing_raw <- max(0, (2.0 - mss$global_mean_spacing) / 2.0 * 25)
  spacing_score <- min(25, spacing_raw)

  if (verbose) cat(sprintf("  Spacing: Mean=%.2f Da → %.1f points\n",
                           mss$global_mean_spacing, spacing_score))

  # Component 4: Chimeric Prediction (0-25 points)
  # Based on chimeric spectrum ratio
  csi <- calculate_csi(data, windows = windows)

  # 100% chimeric = 25 points
  chimeric_score <- min(25, csi$chimeric_ratio * 25)

  if (verbose) cat(sprintf("  Chimeric: %.1f%% → %.1f points\n",
                           csi$chimeric_ratio * 100, chimeric_score))

  # Total score
  total_score <- density_score + crowding_score + spacing_score + chimeric_score

  # Interpretation
  interpretation <- case_when(
    total_score < 20 ~ "Very Low - Excellent DIA performance expected",
    total_score < 40 ~ "Low - Good performance with standard settings",
    total_score < 60 ~ "Moderate - Optimization recommended",
    total_score < 80 ~ "High - Careful window optimization required",
    TRUE ~ "Very High - Consider narrower windows or gas-phase fractionation"
  )

  result <- list(
    # Total score
    total_score = round(total_score, 1),

    # Component scores
    components = list(
      density = round(density_score, 1),
      crowding = round(crowding_score, 1),
      spacing = round(spacing_score, 1),
      chimeric = round(chimeric_score, 1)
    ),

    # Component max values
    max_per_component = 25,
    max_total = 100,

    # Raw component outputs
    component_details = list(
      rci = rci,
      mss = mss,
      csi = csi
    ),

    # Summary statistics
    n_precursors = n_precursors,
    precursors_per_min = precursors_per_min,
    rt_span_min = rt_span,

    # Interpretation
    interpretation = interpretation,
    complexity_level = case_when(
      total_score < 20 ~ "very_low",
      total_score < 40 ~ "low",
      total_score < 60 ~ "moderate",
      total_score < 80 ~ "high",
      TRUE ~ "very_high"
    )
  )

  class(result) <- c("UDCS", "list")
  return(result)
}


# =============================================================================
# Convenience Functions
# =============================================================================

#' Calculate All Complexity Metrics
#'
#' Convenience function to calculate all complexity metrics at once.
#'
#' @param data Tibble with RT.Start, Precursor.Mz columns
#' @param windows Optional window definitions
#' @param verbose Logical, print progress (default: TRUE)
#'
#' @return List with all complexity metrics
#' @export
calculate_all_complexity_metrics <- function(data,
                                              windows = NULL,
                                              verbose = TRUE) {

  if (verbose) {
    cat("\n")
    cat("╔═══════════════════════════════════════════════╗\n")
    cat("║   DIA Complexity Analysis                    ║\n")
    cat("╚═══════════════════════════════════════════════╝\n\n")
  }

  start_time <- Sys.time()

  # Calculate each metric
  if (verbose) cat("1. Calculating Precursor Co-isolation Index (PCI)...\n")
  pci <- calculate_pci(data, sample_size = min(5000, nrow(data)))

  if (verbose) cat("2. Calculating RT Crowding Index (RCI)...\n")
  rci <- calculate_rci(data)

  if (verbose) cat("3. Calculating m/z Spacing Score (MSS)...\n")
  mss <- calculate_mss(data)

  if (verbose) cat("4. Calculating Chimeric Spectrum Index (CSI)...\n")
  csi <- calculate_csi(data, windows = windows)

  if (verbose) cat("5. Calculating Complexity Heatmap Score (CHS)...\n")
  chs <- calculate_chs(data)

  if (verbose) cat("6. Calculating Unified DIA Complexity Score (UDCS)...\n")
  # Reuse already calculated components
  udcs <- calculate_udcs(data, windows = windows, verbose = FALSE)

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  if (verbose) {
    cat("\n")
    cat("═══════════════════════════════════════════════\n")
    cat("            COMPLEXITY SUMMARY                 \n")
    cat("═══════════════════════════════════════════════\n")
    cat(sprintf("  UDCS Total Score: %.1f / 100\n", udcs$total_score))
    cat(sprintf("  Interpretation: %s\n", udcs$interpretation))
    cat("───────────────────────────────────────────────\n")
    cat("  Component Scores:\n")
    cat(sprintf("    • Density:  %5.1f / 25  (%.0f precursors/min)\n",
                udcs$components$density, udcs$precursors_per_min))
    cat(sprintf("    • Crowding: %5.1f / 25  (Gini: %.2f)\n",
                udcs$components$crowding, rci$gini_coefficient))
    cat(sprintf("    • Spacing:  %5.1f / 25  (Mean: %.2f Da)\n",
                udcs$components$spacing, mss$global_mean_spacing))
    cat(sprintf("    • Chimeric: %5.1f / 25  (%.1f%% chimeric)\n",
                udcs$components$chimeric, csi$chimeric_ratio * 100))
    cat("───────────────────────────────────────────────\n")
    cat(sprintf("  Analysis completed in %.2f seconds\n", elapsed))
    cat("═══════════════════════════════════════════════\n\n")
  }

  result <- list(
    pci = pci,
    rci = rci,
    mss = mss,
    csi = csi,
    chs = chs,
    udcs = udcs,

    # Quick summary
    summary = list(
      n_precursors = nrow(data),
      udcs_score = udcs$total_score,
      complexity_level = udcs$complexity_level,
      interpretation = udcs$interpretation
    ),

    elapsed_seconds = elapsed
  )

  class(result) <- c("DIAComplexity", "list")
  return(result)
}


#' Print Summary of Complexity Analysis
#'
#' @param x DIAComplexity object
#' @param ... Additional arguments (ignored)
#' @export
print.DIAComplexity <- function(x, ...) {
  cat("\n=== DIA Complexity Analysis ===\n")
  cat(sprintf("  Precursors: %d\n", x$summary$n_precursors))
  cat(sprintf("  UDCS Score: %.1f / 100 (%s)\n",
              x$summary$udcs_score, x$summary$complexity_level))
  cat(sprintf("  %s\n", x$summary$interpretation))
  cat("\nComponent Details:\n")
  cat(sprintf("  PCI: Mean %.1f co-isolated precursors (%s)\n",
              x$pci$mean_pci, x$pci$complexity_level))
  cat(sprintf("  RCI: %s (Gini: %.2f)\n",
              x$rci$crowding_level, x$rci$gini_coefficient))
  cat(sprintf("  MSS: %s (Mean spacing: %.2f Da)\n",
              x$mss$spacing_level, x$mss$global_mean_spacing))
  cat(sprintf("  CSI: %s (%.1f%% chimeric windows)\n",
              x$csi$chimeric_level, x$csi$chimeric_ratio * 100))
  cat(sprintf("  CHS: %s (Entropy: %.2f)\n",
              x$chs$distribution_type, x$chs$spatial_entropy))
  invisible(x)
}


# =============================================================================
# Module Loading
# =============================================================================

cat("✅ Complexity metrics module loaded successfully\n")
cat("   Available functions:\n")
cat("   - calculate_pci(): Precursor Co-isolation Index\n")
cat("   - calculate_rci(): RT Crowding Index\n")
cat("   - calculate_mss(): m/z Spacing Score\n")
cat("   - calculate_csi(): Chimeric Spectrum Index\n")
cat("   - calculate_chs(): Complexity Heatmap Score\n")
cat("   - calculate_udcs(): Unified DIA Complexity Score\n")
cat("   - calculate_all_complexity_metrics(): All metrics at once\n")
