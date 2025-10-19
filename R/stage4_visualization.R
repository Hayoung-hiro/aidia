# stage4_visualization.R - Phase 4: Visualization & Reporting
#
# Purpose: Generate scientific journal-quality visualizations and reports
#   - 8 essential plots for comprehensive optimization analysis
#   - PDF report with all figures and summary statistics
#   - Method file export for instrument programming
#
# Input: All outputs from Phases 1-3 (ValidatedData, DiagnosisResult, WindowCountResult, etc.)
# Output: VisualizationResult with plots, report files, and statistics
#
# Scientific Quality Standards:
#   - High resolution (300+ DPI for publication)
#   - Colorblind-friendly palettes (viridis, ColorBrewer)
#   - Clear axis labels with units
#   - Statistical annotations (mean, median, CI)
#   - Consistent theme across all plots

library(ggplot2)
library(gridExtra)
library(scales)
library(viridis)
library(dplyr)
library(tidyr)

# =============================================================================
# Plot 1: DPPP Density Distribution (Before vs After)
# =============================================================================

#' Plot DPPP Distribution Comparison
#'
#' Shows current DPPP distribution vs target threshold with satisfaction ratio.
#' Interpretation: Visualizes how many precursors meet target DPPP requirements.
#'
#' @param diagnosis_result DiagnosisResult from Phase 2
#' @param target_dppp Numeric, target DPPP threshold (default: 7.0)
#' @return ggplot object
#' @export
plot_dppp_density <- function(diagnosis_result, target_dppp = 7.0) {

  # Extract DPPP distribution
  dppp_data <- data.frame(
    dppp = diagnosis_result$current_status$dppp_distribution
  )

  # Calculate statistics
  mean_dppp <- mean(dppp_data$dppp, na.rm = TRUE)
  median_dppp <- median(dppp_data$dppp, na.rm = TRUE)
  satisfaction_ratio <- diagnosis_result$current_status$satisfaction_ratio

  # Create plot
  p <- ggplot(dppp_data, aes(x = dppp)) +
    # Density curve
    geom_density(fill = "#440154FF", alpha = 0.6, color = "#440154FF", size = 1.2) +

    # Target threshold line
    geom_vline(xintercept = target_dppp, linetype = "dashed",
               color = "#FDE725FF", size = 1.2) +

    # Mean and median lines
    geom_vline(xintercept = mean_dppp, linetype = "solid",
               color = "#31688EFF", size = 0.8, alpha = 0.7) +
    geom_vline(xintercept = median_dppp, linetype = "dotted",
               color = "#35B779FF", size = 0.8, alpha = 0.7) +

    # Annotations
    annotate("text", x = target_dppp, y = Inf,
             label = sprintf("Target DPPP = %.1f", target_dppp),
             hjust = -0.1, vjust = 2, size = 4, fontface = "bold", color = "#FDE725FF") +

    annotate("text", x = mean_dppp, y = Inf,
             label = sprintf("Mean = %.2f", mean_dppp),
             hjust = -0.1, vjust = 4, size = 3.5, color = "#31688EFF") +

    annotate("text", x = median_dppp, y = Inf,
             label = sprintf("Median = %.2f", median_dppp),
             hjust = -0.1, vjust = 5.5, size = 3.5, color = "#35B779FF") +

    # Satisfaction ratio annotation
    annotate("rect", xmin = target_dppp, xmax = Inf, ymin = -Inf, ymax = Inf,
             alpha = 0.1, fill = "#FDE725FF") +

    annotate("text", x = Inf, y = Inf,
             label = sprintf("Satisfaction: %.1f%%\n(DPPP ≥ %.1f)",
                           satisfaction_ratio * 100, target_dppp),
             hjust = 1.1, vjust = 2, size = 4.5, fontface = "bold") +

    # Labels and theme
    labs(
      title = "DPPP Distribution Analysis",
      subtitle = sprintf("Current cycle time: %.2f sec | Target DPPP ≥ %.1f",
                        diagnosis_result$current_status$current_cycle_time, target_dppp),
      x = "Data Points Per Peak (DPPP)",
      y = "Density"
    ) +

    scale_x_continuous(breaks = pretty_breaks(n = 10), limits = c(0, NA)) +

    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold", hjust = 0),
      plot.subtitle = element_text(size = 12, color = "gray30"),
      axis.title = element_text(size = 13, face = "bold"),
      axis.text = element_text(size = 11),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "gray90"),
      plot.margin = margin(15, 15, 15, 15)
    )

  return(p)
}


# =============================================================================
# Plot 2: RT-dependent Window Count Allocation
# =============================================================================

#' Plot RT-dependent Window Allocation
#'
#' Shows how windows are distributed across RT segments.
#' Interpretation: Uniform distribution indicates balanced coverage over time.
#'
#' @param rt_binning_result RTBinningResult from Phase 3B
#' @param windows_result WindowGenerationResult from Phase 3D
#' @return ggplot object
#' @export
plot_rt_window_allocation <- function(rt_binning_result, windows_result) {

  # Get RT segment statistics
  rt_stats <- rt_binning_result$rt_group_stats

  # Count windows per RT segment
  window_counts <- windows_result$windows %>%
    group_by(rt_bin_id) %>%
    summarise(
      n_windows = n(),
      .groups = 'drop'
    )

  # Merge with RT stats
  plot_data <- rt_stats %>%
    left_join(window_counts, by = c("rt_group" = "rt_bin_id")) %>%
    mutate(
      rt_center = (rt_start + rt_end) / 2,
      windows_per_precursor = n_windows / n_precursors
    )

  # Create dual-axis plot (precursors + windows)
  p1 <- ggplot(plot_data, aes(x = rt_center)) +
    # Precursor count (bar)
    geom_col(aes(y = n_precursors), fill = "#440154FF", alpha = 0.6, width = 0.8) +

    # Window count (line)
    geom_line(aes(y = n_windows * max(plot_data$n_precursors) / max(plot_data$n_windows)),
              color = "#FDE725FF", size = 1.5) +
    geom_point(aes(y = n_windows * max(plot_data$n_precursors) / max(plot_data$n_windows)),
               color = "#FDE725FF", size = 3, shape = 16) +

    # Secondary axis for windows
    scale_y_continuous(
      name = "Number of Precursors",
      sec.axis = sec_axis(~ . * max(plot_data$n_windows) / max(plot_data$n_precursors),
                          name = "Number of Windows")
    ) +

    labs(
      title = "RT-dependent Window Allocation",
      subtitle = sprintf("Total: %d RT segments | %d windows | %.1f windows/segment (avg)",
                        nrow(plot_data), sum(plot_data$n_windows), mean(plot_data$n_windows)),
      x = "Retention Time (min)"
    ) +

    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      axis.title = element_text(size = 13, face = "bold"),
      axis.title.y.right = element_text(color = "#FDE725FF"),
      axis.text.y.right = element_text(color = "#FDE725FF"),
      axis.text = element_text(size = 11),
      panel.grid.minor = element_blank(),
      legend.position = "none"
    )

  return(p1)
}


# =============================================================================
# Plot 3: RT-m/z Precursor Density Heatmap
# =============================================================================

#' Plot RT-m/z Precursor Density Heatmap
#'
#' 2D heatmap showing precursor distribution across RT and m/z dimensions.
#' Interpretation: High-density regions (red) require more/narrower windows.
#'
#' @param validated_data ValidatedData from Phase 1 with rt_group column
#' @param n_mz_bins Integer, number of m/z bins for heatmap (default: 50)
#' @return ggplot object
#' @export
plot_rt_mz_density_heatmap <- function(validated_data, n_mz_bins = 50) {

  # Extract precursor data
  precursor_data <- validated_data$data

  # Check if rt_group exists
  if (!"rt_group" %in% colnames(precursor_data)) {
    stop("validated_data must have 'rt_group' column from Phase 3B")
  }

  # Create m/z bins
  mz_range <- range(precursor_data$Precursor.Mz, na.rm = TRUE)
  mz_breaks <- seq(mz_range[1], mz_range[2], length.out = n_mz_bins + 1)

  precursor_data <- precursor_data %>%
    mutate(mz_bin = cut(Precursor.Mz, breaks = mz_breaks, labels = FALSE, include.lowest = TRUE))

  # Count precursors in each RT-m/z bin
  density_data <- precursor_data %>%
    group_by(rt_group, mz_bin) %>%
    summarise(count = n(), .groups = 'drop') %>%
    complete(rt_group, mz_bin, fill = list(count = 0))

  # Calculate m/z bin centers for axis labels
  mz_centers <- (mz_breaks[-1] + mz_breaks[-length(mz_breaks)]) / 2

  # Create heatmap
  p <- ggplot(density_data, aes(x = rt_group, y = mz_bin, fill = count)) +
    geom_tile(color = NA) +

    scale_fill_viridis_c(
      option = "inferno",
      name = "Precursor\nCount",
      trans = "log1p",
      breaks = c(0, 10, 100, 1000),
      labels = c("0", "10", "100", "1000")
    ) +

    scale_x_continuous(
      name = "RT Segment",
      breaks = pretty_breaks(n = 10)
    ) +

    scale_y_continuous(
      name = "m/z (Da)",
      breaks = seq(1, n_mz_bins, length.out = 10),
      labels = round(mz_centers[seq(1, n_mz_bins, length.out = 10)])
    ) +

    labs(
      title = "Precursor Density Heatmap (RT × m/z)",
      subtitle = sprintf("Total precursors: %s | Resolution: %d RT bins × %d m/z bins",
                        format(nrow(precursor_data), big.mark = ","),
                        max(density_data$rt_group, na.rm = TRUE), n_mz_bins)
    ) +

    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      axis.title = element_text(size = 13, face = "bold"),
      axis.text = element_text(size = 10),
      legend.title = element_text(size = 11, face = "bold"),
      legend.text = element_text(size = 10),
      panel.grid = element_blank(),
      plot.margin = margin(15, 15, 15, 15)
    )

  return(p)
}


# =============================================================================
# Plot 4: m/z Normalized Density Profile
# =============================================================================

#' Plot m/z Normalized Density Profile
#'
#' Shows precursor m/z distribution normalized across RT segments.
#' Interpretation: Identifies m/z regions requiring special attention.
#'
#' @param validated_data ValidatedData from Phase 1 with rt_group column
#' @param mz_range_result MzRangeResult from Phase 3C
#' @return ggplot object
#' @export
plot_mz_normalized_density <- function(validated_data, mz_range_result) {

  precursor_data <- validated_data$data
  mz_boundaries <- mz_range_result$mz_boundaries

  # Overall m/z density
  p <- ggplot(precursor_data, aes(x = Precursor.Mz)) +
    # Histogram
    geom_histogram(aes(y = after_stat(density)), bins = 100,
                   fill = "#440154FF", alpha = 0.5, color = "white", size = 0.3) +

    # Density curve
    geom_density(color = "#FDE725FF", size = 1.5, alpha = 0.8) +

    # Add optimized m/z boundaries as vertical lines
    geom_vline(data = mz_boundaries,
               aes(xintercept = mz_min),
               linetype = "dashed", color = "#31688EFF", alpha = 0.4, size = 0.5) +

    geom_vline(data = mz_boundaries,
               aes(xintercept = mz_max),
               linetype = "dashed", color = "#35B779FF", alpha = 0.4, size = 0.5) +

    # Statistical annotations
    geom_vline(xintercept = median(precursor_data$Precursor.Mz, na.rm = TRUE),
               linetype = "solid", color = "red", size = 1, alpha = 0.7) +

    annotate("text",
             x = median(precursor_data$Precursor.Mz, na.rm = TRUE),
             y = Inf, vjust = 2,
             label = sprintf("Median = %.1f Da", median(precursor_data$Precursor.Mz, na.rm = TRUE)),
             color = "red", fontface = "bold", size = 4) +

    labs(
      title = "m/z Normalized Density Profile",
      subtitle = sprintf("Range: %.1f - %.1f Da | RT-dependent boundaries shown",
                        min(precursor_data$Precursor.Mz, na.rm = TRUE),
                        max(precursor_data$Precursor.Mz, na.rm = TRUE)),
      x = "Precursor m/z (Da)",
      y = "Normalized Density"
    ) +

    scale_x_continuous(breaks = pretty_breaks(n = 15)) +

    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      axis.title = element_text(size = 13, face = "bold"),
      axis.text = element_text(size = 11),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_line(color = "gray90"),
      plot.margin = margin(15, 15, 15, 15)
    )

  return(p)
}


# =============================================================================
# Plot 5: m/z Window Width Distribution
# =============================================================================

#' Plot Window Width Distribution
#'
#' Shows distribution of isolation window widths.
#' Interpretation: Fixed method = single peak, Variable method = spread distribution.
#'
#' @param windows_result WindowGenerationResult from Phase 3D
#' @param method Character, "fixed" or "variable"
#' @return ggplot object
#' @export
plot_window_width_distribution <- function(windows_result, method = "variable") {

  windows_data <- windows_result$windows

  # Calculate statistics
  mean_width <- mean(windows_data$window_width, na.rm = TRUE)
  median_width <- median(windows_data$window_width, na.rm = TRUE)
  sd_width <- sd(windows_data$window_width, na.rm = TRUE)
  cv_width <- sd_width / mean_width * 100

  p <- ggplot(windows_data, aes(x = window_width)) +
    # Histogram
    geom_histogram(aes(y = after_stat(density)), bins = 50,
                   fill = "#440154FF", alpha = 0.6, color = "white", size = 0.3) +

    # Density curve
    geom_density(fill = "#FDE725FF", alpha = 0.3, color = "#FDE725FF", size = 1.2) +

    # Mean and median
    geom_vline(xintercept = mean_width, linetype = "solid",
               color = "#31688EFF", size = 1.2) +
    geom_vline(xintercept = median_width, linetype = "dashed",
               color = "#35B779FF", size = 1.2) +

    # Statistical annotations
    annotate("text", x = Inf, y = Inf, hjust = 1.1, vjust = 2,
             label = sprintf("Mean = %.2f Da\nMedian = %.2f Da\nSD = %.2f Da\nCV = %.1f%%",
                           mean_width, median_width, sd_width, cv_width),
             size = 4, fontface = "bold", color = "gray20") +

    labs(
      title = sprintf("Isolation Window Width Distribution (%s method)",
                     tools::toTitleCase(method)),
      subtitle = sprintf("Total windows: %s | Range: %.2f - %.2f Da",
                        format(nrow(windows_data), big.mark = ","),
                        min(windows_data$window_width, na.rm = TRUE),
                        max(windows_data$window_width, na.rm = TRUE)),
      x = "Window Width (Da)",
      y = "Density"
    ) +

    scale_x_continuous(breaks = pretty_breaks(n = 10)) +

    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      axis.title = element_text(size = 13, face = "bold"),
      axis.text = element_text(size = 11),
      panel.grid.minor = element_blank(),
      plot.margin = margin(15, 15, 15, 15)
    )

  return(p)
}


# =============================================================================
# Plot 6: Precursor Coverage Map
# =============================================================================

#' Plot Precursor Coverage Map
#'
#' Shows how many windows cover each precursor (should be ≥1 for all).
#' Interpretation: Coverage >1 indicates overlap; 0 indicates missing precursors.
#'
#' @param validated_data ValidatedData from Phase 1
#' @param windows_result WindowGenerationResult from Phase 3D
#' @return ggplot object
#' @export
plot_precursor_coverage_map <- function(validated_data, windows_result) {

  precursor_data <- validated_data$data
  windows_data <- windows_result$windows

  # Calculate coverage for each precursor
  coverage_data <- precursor_data %>%
    rowwise() %>%
    mutate(
      coverage_count = sum(
        windows_data$mz_start <= Precursor.Mz &
        windows_data$mz_end >= Precursor.Mz &
        windows_data$rt_bin_id == rt_group
      )
    ) %>%
    ungroup()

  # Calculate statistics
  total_precursors <- nrow(coverage_data)
  covered_precursors <- sum(coverage_data$coverage_count > 0)
  uncovered_precursors <- sum(coverage_data$coverage_count == 0)
  coverage_pct <- covered_precursors / total_precursors * 100
  mean_coverage <- mean(coverage_data$coverage_count, na.rm = TRUE)

  # Create coverage histogram
  p <- ggplot(coverage_data, aes(x = coverage_count)) +
    geom_histogram(aes(y = after_stat(count)), binwidth = 1,
                   fill = "#440154FF", alpha = 0.7, color = "white", size = 0.5) +

    # Highlight zero coverage
    geom_histogram(data = filter(coverage_data, coverage_count == 0),
                   aes(x = coverage_count, y = after_stat(count)),
                   binwidth = 1, fill = "red", alpha = 0.8) +

    # Add vertical line at coverage = 1
    geom_vline(xintercept = 1, linetype = "dashed", color = "#FDE725FF", size = 1.2) +

    annotate("text", x = 1, y = Inf, vjust = 2, hjust = -0.1,
             label = "Minimum\nCoverage",
             color = "#FDE725FF", fontface = "bold", size = 4) +

    # Statistics annotation
    annotate("text", x = Inf, y = Inf, hjust = 1.1, vjust = 2,
             label = sprintf(
               "Coverage: %.1f%%\nCovered: %s\nUncovered: %s\nMean coverage: %.2f",
               coverage_pct,
               format(covered_precursors, big.mark = ","),
               format(uncovered_precursors, big.mark = ","),
               mean_coverage
             ),
             size = 4, fontface = "bold",
             color = ifelse(uncovered_precursors > 0, "red", "darkgreen")) +

    labs(
      title = "Precursor Coverage Analysis",
      subtitle = sprintf("Total precursors: %s | Windows: %s",
                        format(total_precursors, big.mark = ","),
                        format(nrow(windows_data), big.mark = ",")),
      x = "Number of Windows Covering Each Precursor",
      y = "Number of Precursors"
    ) +

    scale_x_continuous(breaks = 0:max(coverage_data$coverage_count, na.rm = TRUE)) +
    scale_y_continuous(labels = comma) +

    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      axis.title = element_text(size = 13, face = "bold"),
      axis.text = element_text(size = 11),
      panel.grid.minor = element_blank(),
      plot.margin = margin(15, 15, 15, 15)
    )

  return(p)
}


# =============================================================================
# Plot 7: Window Efficiency Analysis
# =============================================================================

#' Plot Window Efficiency (Precursors per Window)
#'
#' Shows distribution of precursor counts per window.
#' Interpretation: Variable method should show more uniform distribution.
#'
#' @param validated_data ValidatedData from Phase 1 with rt_group
#' @param windows_result WindowGenerationResult from Phase 3D
#' @return ggplot object
#' @export
plot_window_efficiency <- function(validated_data, windows_result) {

  precursor_data <- validated_data$data
  windows_data <- windows_result$windows

  # Count precursors in each window
  window_efficiency <- windows_data %>%
    rowwise() %>%
    mutate(
      n_precursors = sum(
        precursor_data$Precursor.Mz >= mz_start &
        precursor_data$Precursor.Mz <= mz_end &
        precursor_data$rt_group == rt_bin_id
      )
    ) %>%
    ungroup()

  # Statistics
  mean_prec <- mean(window_efficiency$n_precursors, na.rm = TRUE)
  median_prec <- median(window_efficiency$n_precursors, na.rm = TRUE)
  cv_prec <- sd(window_efficiency$n_precursors, na.rm = TRUE) / mean_prec * 100
  empty_windows <- sum(window_efficiency$n_precursors == 0)

  p <- ggplot(window_efficiency, aes(x = n_precursors)) +
    # Histogram
    geom_histogram(aes(y = after_stat(density)), bins = 50,
                   fill = "#440154FF", alpha = 0.6, color = "white", size = 0.3) +

    # Density curve
    geom_density(fill = "#FDE725FF", alpha = 0.3, color = "#FDE725FF", size = 1.2) +

    # Mean and median
    geom_vline(xintercept = mean_prec, linetype = "solid",
               color = "#31688EFF", size = 1.2) +
    geom_vline(xintercept = median_prec, linetype = "dashed",
               color = "#35B779FF", size = 1.2) +

    # Annotations
    annotate("text", x = Inf, y = Inf, hjust = 1.1, vjust = 2,
             label = sprintf(
               "Mean = %.1f\nMedian = %.1f\nCV = %.1f%%\nEmpty windows = %d",
               mean_prec, median_prec, cv_prec, empty_windows
             ),
             size = 4, fontface = "bold",
             color = ifelse(empty_windows > nrow(window_efficiency) * 0.05, "red", "darkgreen")) +

    labs(
      title = "Window Efficiency Distribution",
      subtitle = sprintf("Precursors per window | Total windows: %s",
                        format(nrow(window_efficiency), big.mark = ",")),
      x = "Number of Precursors per Window",
      y = "Density"
    ) +

    scale_x_continuous(breaks = pretty_breaks(n = 10)) +

    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      axis.title = element_text(size = 13, face = "bold"),
      axis.text = element_text(size = 11),
      panel.grid.minor = element_blank(),
      plot.margin = margin(15, 15, 15, 15)
    )

  return(p)
}


# =============================================================================
# Plot 8: DPPP Achievement Heatmap (RT × m/z)
# =============================================================================

#' Plot Expected DPPP Achievement Heatmap
#'
#' 2D heatmap showing predicted DPPP across RT and m/z space.
#' Interpretation: All regions should be green (≥target DPPP) for optimal method.
#'
#' @param validated_data ValidatedData from Phase 1 with rt_group
#' @param diagnosis_result DiagnosisResult from Phase 2
#' @param target_dppp Numeric, target DPPP threshold
#' @param n_mz_bins Integer, number of m/z bins
#' @return ggplot object
#' @export
plot_dppp_achievement_heatmap <- function(validated_data, diagnosis_result,
                                          target_dppp = 7.0, n_mz_bins = 50) {

  precursor_data <- validated_data$data
  recommended_cycle_time <- diagnosis_result$recommendation$optimal_cycle_time

  # Create m/z bins
  mz_range <- range(precursor_data$Precursor.Mz, na.rm = TRUE)
  mz_breaks <- seq(mz_range[1], mz_range[2], length.out = n_mz_bins + 1)

  precursor_data <- precursor_data %>%
    mutate(mz_bin = cut(Precursor.Mz, breaks = mz_breaks, labels = FALSE, include.lowest = TRUE))

  # Calculate predicted DPPP for each bin
  dppp_heatmap <- precursor_data %>%
    group_by(rt_group, mz_bin) %>%
    summarise(
      median_fwhm_min = median(FWHM, na.rm = TRUE),
      n_precursors = n(),
      .groups = 'drop'
    ) %>%
    mutate(
      # DPPP = (1.7 × FWHM_sec) / cycle_time_sec
      predicted_dppp = (1.7 * median_fwhm_min * 60) / recommended_cycle_time,
      achievement = ifelse(predicted_dppp >= target_dppp, "Met", "Below")
    ) %>%
    complete(rt_group, mz_bin, fill = list(predicted_dppp = NA, achievement = "No Data"))

  # Calculate achievement rate
  achievement_rate <- sum(dppp_heatmap$achievement == "Met", na.rm = TRUE) /
                     sum(!is.na(dppp_heatmap$predicted_dppp)) * 100

  # m/z bin centers for axis
  mz_centers <- (mz_breaks[-1] + mz_breaks[-length(mz_breaks)]) / 2

  p <- ggplot(dppp_heatmap, aes(x = rt_group, y = mz_bin, fill = predicted_dppp)) +
    geom_tile(color = NA) +

    # Diverging color scale centered on target
    scale_fill_gradient2(
      low = "#D73027",
      mid = "#FEE08B",
      high = "#1A9850",
      midpoint = target_dppp,
      na.value = "gray80",
      name = "Predicted\nDPPP",
      limits = c(0, max(target_dppp * 2, max(dppp_heatmap$predicted_dppp, na.rm = TRUE)))
    ) +

    # Contour line at target DPPP
    geom_contour(aes(z = predicted_dppp), breaks = target_dppp,
                 color = "black", size = 1.2, linetype = "dashed") +

    scale_x_continuous(
      name = "RT Segment",
      breaks = pretty_breaks(n = 10)
    ) +

    scale_y_continuous(
      name = "m/z (Da)",
      breaks = seq(1, n_mz_bins, length.out = 10),
      labels = round(mz_centers[seq(1, n_mz_bins, length.out = 10)])
    ) +

    labs(
      title = "DPPP Achievement Heatmap (Predicted)",
      subtitle = sprintf(
        "Recommended cycle time: %.2f sec | Target DPPP ≥ %.1f | Achievement: %.1f%%",
        recommended_cycle_time, target_dppp, achievement_rate
      )
    ) +

    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      axis.title = element_text(size = 13, face = "bold"),
      axis.text = element_text(size = 10),
      legend.title = element_text(size = 11, face = "bold"),
      legend.text = element_text(size = 10),
      panel.grid = element_blank(),
      plot.margin = margin(15, 15, 15, 15)
    )

  return(p)
}


# =============================================================================
# Main Visualization Function
# =============================================================================

#' Generate All Visualization Plots (Phase 4 Main Function)
#'
#' Creates all 8 essential plots and returns VisualizationResult object.
#'
#' @param validated_data ValidatedData from Phase 1
#' @param diagnosis_result DiagnosisResult from Phase 2
#' @param window_count_result WindowCountResult from Phase 3A
#' @param rt_binning_result RTBinningResult from Phase 3B
#' @param mz_range_result MzRangeResult from Phase 3C
#' @param windows_result WindowGenerationResult from Phase 3D
#' @param target_dppp Numeric, target DPPP threshold (default: 7.0)
#' @param output_dir Character, directory for saving plots (default: "output/plots")
#' @param save_individual Logical, save individual plots (default: TRUE)
#' @param dpi Numeric, resolution for saved plots (default: 300)
#' @return VisualizationResult object
#' @export
generate_all_visualizations <- function(
  validated_data,
  diagnosis_result,
  window_count_result,
  rt_binning_result,
  mz_range_result,
  windows_result,
  target_dppp = 7.0,
  output_dir = "output/plots",
  save_individual = TRUE,
  dpi = 300
) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   Phase 4: Visualization & Reporting         ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  start_time <- Sys.time()

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat(sprintf("Created output directory: %s\n", output_dir))
  }

  # Generate all 8 plots
  cat("Generating visualization plots...\n")

  plots <- list(
    dppp_density = plot_dppp_density(diagnosis_result, target_dppp),
    rt_window_allocation = plot_rt_window_allocation(rt_binning_result, windows_result),
    rt_mz_density_heatmap = plot_rt_mz_density_heatmap(validated_data),
    mz_normalized_density = plot_mz_normalized_density(validated_data, mz_range_result),
    window_width_distribution = plot_window_width_distribution(
      windows_result,
      method = windows_result$metadata$method
    ),
    precursor_coverage_map = plot_precursor_coverage_map(validated_data, windows_result),
    window_efficiency = plot_window_efficiency(validated_data, windows_result),
    dppp_achievement_heatmap = plot_dppp_achievement_heatmap(
      validated_data, diagnosis_result, target_dppp
    )
  )

  cat(sprintf("✓ Generated %d plots\n\n", length(plots)))

  # Save individual plots if requested
  plot_files <- character(0)
  if (save_individual) {
    cat("Saving individual plots...\n")
    for (plot_name in names(plots)) {
      filename <- file.path(output_dir, sprintf("%s.png", plot_name))
      ggsave(filename, plots[[plot_name]], width = 10, height = 7, dpi = dpi)
      plot_files <- c(plot_files, filename)
      cat(sprintf("  ✓ %s\n", filename))
    }
    cat("\n")
  }

  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

  # Create result object
  result <- structure(
    list(
      plots = plots,

      report_files = list(
        individual_plots = plot_files,
        pdf_report = character(0),  # To be implemented
        method_file = character(0)   # To be implemented
      ),

      summary_statistics = list(
        optimization_metrics = list(
          target_dppp = target_dppp,
          current_satisfaction = diagnosis_result$current_status$satisfaction_ratio,
          recommended_cycle_time = diagnosis_result$recommendation$optimal_cycle_time,
          total_windows = nrow(windows_result$windows),
          total_rt_bins = max(windows_result$windows$rt_bin_id, na.rm = TRUE)
        ),

        performance_metrics = list(
          mean_window_width = mean(windows_result$windows$window_width, na.rm = TRUE),
          window_width_cv = sd(windows_result$windows$window_width, na.rm = TRUE) /
                           mean(windows_result$windows$window_width, na.rm = TRUE) * 100
        )
      ),

      metadata = list(
        generation_timestamp = Sys.time(),
        plot_generation_time = elapsed,
        output_directory = output_dir,
        dpi = dpi,
        n_plots_generated = length(plots)
      )
    ),
    class = c("VisualizationResult", "list")
  )

  cat("═══════════════════════════════════════════════\n")
  cat(sprintf("Visualization complete! (%.1f sec)\n", elapsed))
  cat(sprintf("Output directory: %s\n", output_dir))
  cat("═══════════════════════════════════════════════\n\n")

  return(result)
}
