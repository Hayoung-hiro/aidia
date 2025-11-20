# stage4_visualization.R - Stage 4: Visualization & Reporting
#
# Purpose: Generate comprehensive visualizations and reports for DIA window optimization
#
# Version: 4.0 (Complete plot suite with multi-strategy comparison)
#
# Main Functions:
#   1. generate_visualizations() - Main orchestration function
#   2. Complete plot suite (24 plots total):
#      - Plot 1A/1B: DPPP Distribution Comparison (Simple & Enhanced)
#      - Plot 2: RT × m/z Density Heatmap
#      - Plot 2B: RT Histogram (Continuous & 5-min binned)
#      - Plot 3: m/z Density Overlay by RT Segment
#      - Plot 4 (A-E): m/z Range Optimization (4 strategies + comparison)
#      - Plot 5: Coverage Map 2×2 Grid (All strategies)
#      - Plot 6: Satisfaction vs Cycle Time Trade-off Curve
#      - Plot 7 (×4): Window Width Distribution by Strategy (Quantile, Smoothing, Outlier, Coverage)
#      - Plot 7B (×4): Window Index Width Bars by Strategy
#      - Plot 8A: Ridge Plot - Strategy Width Comparison (ggridges)
#      - Plot 8B: Box Plot - Strategy Statistical Summary
#      - Plot 8C: CDF - Strategy Cumulative Distribution
#   3. create_pdf_report() - Multi-panel PDF generation
#   4. export_method_file() - Thermo Orbitrap method CSV
#   5. export_individual_plots() - Individual plot export
#
# New in Version 4.0:
#   - Plot 8 (A/B/C): 4-strategy window width comparison with 3 visualization types
#   - ggridges integration for professional ridge plots
#   - Comprehensive multi-strategy analysis across Plot 4, 5, 7, and 8
#   - Total plot count increased from 13 to 24
#
# Deprecated Functions Removed:
#   - plot_rt_window_size (replaced by Plot 3 overlay)
#   - plot_precursor_coverage_map (replaced by Plot 5)
#   - plot_window_efficiency (no longer needed)
#   - plot_dppp_achievement_heatmap (removed in redesign)
#
# Input: Refactored pipeline outputs
#   - validated_data (ValidatedData from Stage 1)
#   - optimization_plan (OptimizationPlan from Stage 2)
#   - optimized_windows (OptimizedWindows from Stage 3)
#
# Output: VisualizationResult with plots, reports, and method files

library(ggplot2)
library(dplyr)
library(tidyr)
library(viridis)
library(scales)
library(gridExtra)
library(grid)

# =============================================================================
# Source Modular Plot Functions
# =============================================================================

# Plot 2B: RT Histogram (supplementary to density heatmap)
if (file.exists("R/plot2b_rt_histogram.R")) {
  source("R/plot2b_rt_histogram.R")
}

# Plot 4: m/z Range Optimization (multiple strategies)
if (file.exists("R/plot4_mz_distribution_excluded.R")) {
  source("R/plot4_mz_distribution_excluded.R")
}
if (file.exists("R/plot4_mz_width_comparison.R")) {
  source("R/plot4_mz_width_comparison.R")
}
if (file.exists("R/plot4_mz_range_optimization.R")) {
  source("R/plot4_mz_range_optimization.R")
}

# Plot 5: Coverage Map 2×2 Grid
if (file.exists("R/plot5_density_with_mz_ranges.R")) {
  source("R/plot5_density_with_mz_ranges.R")
}

# Plot 7: Window Width Distribution by RT Segment
if (file.exists("R/plot7_window_width_distribution.R")) {
  source("R/plot7_window_width_distribution.R")
}

# Plot 8: Strategy Width Comparison (Ridge, Box, CDF)
if (file.exists("R/plot8_strategy_width_comparison.R")) {
  source("R/plot8_strategy_width_comparison.R")
}

# =============================================================================
# Custom Theme
# =============================================================================

#' Custom ggplot2 Theme for DIA Optimizer
#'
#' @export
theme_dia_optimizer <- function() {
  theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      plot.caption = element_text(size = 9, color = "gray50", hjust = 0),
      axis.title = element_text(size = 11),
      axis.text = element_text(size = 10),
      legend.title = element_text(face = "bold", size = 10),
      legend.text = element_text(size = 9),
      panel.grid.minor = element_blank()
    )
}

# =============================================================================
# Plot 1: DPPP Distribution Comparison (Before/After)
# =============================================================================

#' Plot DPPP Distribution: Current vs Recommended Cycle Time
#'
#' Shows dual density curves comparing current DPPP with expected DPPP
#' after applying recommended cycle time. Includes target line and statistics.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_dppp_comparison <- function(optimization_plan, validated_data) {

  cat("  Generating Plot 1: DPPP Distribution Comparison...\n")

  # Extract cycle times
  current_cycle_time <- optimization_plan$diagnosis$current_cycle_time_sec
  required_cycle_time <- optimization_plan$required_cycle_time_sec
  target_dppp <- optimization_plan$parameters$target_dppp

  # Extract FWHM data
  fwhm_data <- validated_data$data %>%
    select(FWHM) %>%
    mutate(FWHM_sec = FWHM * 60)  # Convert to seconds

  # Calculate current and expected DPPP
  dppp_data <- fwhm_data %>%
    mutate(
      current_dppp = (FWHM_sec * 1.7) / current_cycle_time,
      expected_dppp = (FWHM_sec * 1.7) / required_cycle_time
    ) %>%
    select(current_dppp, expected_dppp) %>%
    pivot_longer(
      cols = everything(),
      names_to = "condition",
      values_to = "dppp"
    ) %>%
    mutate(
      condition = factor(
        condition,
        levels = c("current_dppp", "expected_dppp"),
        labels = c(
          sprintf("Current (%.3f sec)", current_cycle_time),
          sprintf("Recommended (%.3f sec)", required_cycle_time)
        )
      )
    )

  # Calculate statistics for annotation
  median_fwhm_sec <- median(fwhm_data$FWHM_sec)
  n_precursors <- nrow(validated_data$data)
  current_satisfaction <- optimization_plan$diagnosis$current_satisfaction_ratio * 100

  # Calculate expected satisfaction (approximate)
  expected_satisfaction <- sum(dppp_data$condition == levels(dppp_data$condition)[2] &
                                dppp_data$dppp >= target_dppp) /
                           (n_precursors) * 100

  # Create annotation text with larger font and simplified formula
  annotation_text <- sprintf(
    "DPPP = (FWHM × 1.7) / cycle_time\n\nCurrent State:\n  Median FWHM: %.1f sec\n  Cycle time: %.1f sec\n  Satisfaction: %.1f%%\n\nRecommended:\n  Cycle time: %.1f sec\n  Expected satisfaction: %.1f%%+\n\nTotal precursors: %s",
    median_fwhm_sec,
    current_cycle_time,
    current_satisfaction,
    required_cycle_time,
    expected_satisfaction,
    format(n_precursors, big.mark = ",")
  )

  # Create dual density plot with improved visibility
  p <- ggplot(dppp_data, aes(x = dppp, fill = condition, color = condition)) +
    geom_density(alpha = 0.3, linewidth = 1.2) +  # More transparent, thicker line
    geom_vline(
      xintercept = target_dppp,
      linetype = "dashed",
      color = "black",
      linewidth = 1
    ) +
    annotate(
      "text",
      x = target_dppp,
      y = Inf,
      label = sprintf("Target DPPP = %.1f", target_dppp),
      hjust = -0.1,
      vjust = 1.5,
      size = 4,
      fontface = "bold"
    ) +
    annotate(
      "text",
      x = Inf,
      y = Inf,
      label = annotation_text,
      hjust = 1.05,
      vjust = 1.05,
      size = 3.5,  # Increased from 3 to 3.5
      family = "mono",
      lineheight = 0.95
    ) +
    scale_fill_manual(
      values = c("steelblue", "coral"),
      name = "Cycle Time"
    ) +
    scale_color_manual(
      values = c("steelblue4", "coral4"),
      name = "Cycle Time"
    ) +
    scale_x_continuous(
      limits = c(0, 15),  # Focus on main data region (x < 10)
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    labs(
      title = "DPPP Distribution: Current vs Recommended Cycle Time",
      subtitle = "Optimization reduces cycle time to improve DPPP achievement",
      x = "DPPP (Data Points Per Peak)",
      y = "Density",
      caption = "Shaded area shows probability density; dashed line = target DPPP"
    ) +
    theme_dia_optimizer() +
    theme(
      legend.position = c(0.02, 0.85),  # Moved down to avoid title overlap
      legend.justification = c(0, 1),
      legend.background = element_rect(fill = "white", color = "gray80"),
      legend.key.size = unit(0.8, "cm"),
      legend.title = element_text(size = 11, face = "bold")
    )

  return(p)
}

#' Plot DPPP Distribution: Enhanced Version with Visual Annotations
#'
#' Enhanced version of plot_dppp_comparison() with additional visual elements:
#' - Target region highlighting (satisfied zone)
#' - Median DPPP vertical lines for both conditions
#' - Shift arrow showing DPPP improvement
#' - Clearer visual separation of satisfied/unsatisfied regions
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_dppp_comparison_enhanced <- function(optimization_plan, validated_data) {

  cat("  Generating Plot 1 Enhanced: DPPP Distribution with Visual Annotations...\n")

  # Extract cycle times
  current_cycle_time <- optimization_plan$diagnosis$current_cycle_time_sec
  required_cycle_time <- optimization_plan$required_cycle_time_sec
  target_dppp <- optimization_plan$parameters$target_dppp

  # Extract FWHM data
  fwhm_data <- validated_data$data %>%
    select(FWHM) %>%
    mutate(FWHM_sec = FWHM * 60)  # Convert to seconds

  # Calculate current and expected DPPP
  dppp_data <- fwhm_data %>%
    mutate(
      current_dppp = (FWHM_sec * 1.7) / current_cycle_time,
      expected_dppp = (FWHM_sec * 1.7) / required_cycle_time
    )

  # Calculate median DPPP for both conditions
  median_current_dppp <- median(dppp_data$current_dppp, na.rm = TRUE)
  median_expected_dppp <- median(dppp_data$expected_dppp, na.rm = TRUE)
  dppp_shift <- median_expected_dppp - median_current_dppp

  # Reshape for plotting
  dppp_plot_data <- dppp_data %>%
    select(current_dppp, expected_dppp) %>%
    pivot_longer(
      cols = everything(),
      names_to = "condition",
      values_to = "dppp"
    ) %>%
    mutate(
      condition = factor(
        condition,
        levels = c("current_dppp", "expected_dppp"),
        labels = c(
          sprintf("Current (%.2f sec)", current_cycle_time),
          sprintf("Recommended (%.2f sec)", required_cycle_time)
        )
      )
    )

  # Calculate statistics for annotation
  median_fwhm_sec <- median(fwhm_data$FWHM_sec)
  n_precursors <- nrow(validated_data$data)
  current_satisfaction <- optimization_plan$diagnosis$current_satisfaction_ratio * 100

  # Calculate expected satisfaction
  expected_satisfaction <- sum(dppp_plot_data$condition == levels(dppp_plot_data$condition)[2] &
                                dppp_plot_data$dppp >= target_dppp) /
                           (n_precursors) * 100

  # Create annotation text
  annotation_text <- sprintf(
    "DPPP = (FWHM × 1.7) / cycle_time\n\nCurrent State:\n  Median FWHM: %.1f sec\n  Cycle time: %.1f sec\n  Median DPPP: %.2f\n  Satisfaction: %.1f%%\n\nRecommended:\n  Cycle time: %.1f sec\n  Median DPPP: %.2f\n  Expected satisfaction: %.1f%%+\n\nDPPP Improvement: +%.2f\nTotal precursors: %s",
    median_fwhm_sec,
    current_cycle_time,
    median_current_dppp,
    current_satisfaction,
    required_cycle_time,
    median_expected_dppp,
    expected_satisfaction,
    dppp_shift,
    format(n_precursors, big.mark = ",")
  )

  # Create enhanced plot
  p <- ggplot(dppp_plot_data, aes(x = dppp, fill = condition, color = condition)) +
    # Background: Target satisfied region (green zone)
    annotate(
      "rect",
      xmin = target_dppp, xmax = 15,
      ymin = 0, ymax = Inf,
      fill = "green", alpha = 0.05
    ) +
    annotate(
      "text",
      x = target_dppp + 0.5,
      y = Inf,
      label = "Satisfied Region",
      hjust = 0,
      vjust = 3,
      size = 3,
      color = "darkgreen",
      fontface = "italic"
    ) +
    # Main density curves
    geom_density(alpha = 0.3, linewidth = 1.2) +
    # Target DPPP line
    geom_vline(
      xintercept = target_dppp,
      linetype = "dashed",
      color = "black",
      linewidth = 1
    ) +
    annotate(
      "text",
      x = target_dppp,
      y = Inf,
      label = sprintf("Target DPPP = %.1f", target_dppp),
      hjust = -0.1,
      vjust = 1.5,
      size = 4,
      fontface = "bold"
    ) +
    # Median lines with values
    geom_vline(
      xintercept = median_current_dppp,
      linetype = "dotted",
      color = "steelblue4",
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = median_current_dppp,
      y = 0,
      label = sprintf("Current\nMedian: %.2f", median_current_dppp),
      hjust = 0.5,
      vjust = -0.5,
      size = 3,
      color = "steelblue4",
      fontface = "bold"
    ) +
    geom_vline(
      xintercept = median_expected_dppp,
      linetype = "dotted",
      color = "coral4",
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = median_expected_dppp,
      y = 0,
      label = sprintf("Recommended\nMedian: %.2f", median_expected_dppp),
      hjust = 0.5,
      vjust = -0.5,
      size = 3,
      color = "coral4",
      fontface = "bold"
    ) +
    # Shift arrow between medians
    annotate(
      "segment",
      x = median_current_dppp + 0.3,
      xend = median_expected_dppp - 0.3,
      y = 0.05,
      yend = 0.05,
      arrow = arrow(length = unit(0.3, "cm"), type = "closed"),
      color = "black",
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = (median_current_dppp + median_expected_dppp) / 2,
      y = 0.05,
      label = sprintf("Shift: +%.2f DPPP", dppp_shift),
      hjust = 0.5,
      vjust = -0.5,
      size = 3.5,
      fontface = "bold"
    ) +
    # Statistics annotation box
    annotate(
      "text",
      x = Inf,
      y = Inf,
      label = annotation_text,
      hjust = 1.05,
      vjust = 1.05,
      size = 3.2,
      family = "mono",
      lineheight = 0.95
    ) +
    # Scales
    scale_fill_manual(
      values = c("steelblue", "coral"),
      name = "Cycle Time"
    ) +
    scale_color_manual(
      values = c("steelblue4", "coral4"),
      name = "Cycle Time"
    ) +
    scale_x_continuous(
      limits = c(0, 15),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(
      expand = expansion(mult = c(0, 0.1))
    ) +
    # Labels
    labs(
      title = "DPPP Distribution: Current vs Recommended (Enhanced)",
      subtitle = "Optimization reduces cycle time to improve DPPP achievement - with visual annotations",
      x = "DPPP (Data Points Per Peak)",
      y = "Density",
      caption = "Green zone = satisfied region (DPPP ≥ target); dotted lines = median DPPP"
    ) +
    # Theme
    theme_dia_optimizer() +
    theme(
      legend.position = c(0.02, 0.75),
      legend.justification = c(0, 1),
      legend.background = element_rect(fill = "white", color = "gray80"),
      legend.key.size = unit(0.8, "cm"),
      legend.title = element_text(size = 11, face = "bold")
    )

  return(p)
}

# =============================================================================
# Plot 2: RT Window Size - DEPRECATED (Replaced by Plot 3 overlay)
# =============================================================================
# This function has been removed as part of the redesign.
# RT window allocation is now visualized in Plot 3 (m/z Density Overlay).

# =============================================================================
# Plot 3: RT × m/z Density Heatmap
# =============================================================================

#' Plot Precursor Density Distribution
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 50)
#'
#' @return ggplot object
#' @export
plot_rt_mz_density_heatmap <- function(validated_data, bins = 50) {

  cat("  Generating Plot 3: RT × m/z Density Heatmap...\n")

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Start, Precursor.Mz)

  # Create 2D density heatmap
  p <- ggplot(precursor_data, aes(x = RT.Start, y = Precursor.Mz)) +
    stat_density_2d(
      aes(fill = after_stat(density)),
      geom = "raster",
      contour = FALSE,
      n = bins
    ) +
    scale_fill_viridis_c(option = "plasma", name = "Density") +
    labs(
      title = "Precursor Density Distribution",
      subtitle = sprintf("%s precursors analyzed",
                        format(nrow(precursor_data), big.mark = ",")),
      x = "Retention Time (min)",
      y = "Precursor m/z (Da)",
      caption = "Bright regions = high precursor concentration"
    ) +
    theme_dia_optimizer()

  return(p)
}

# =============================================================================
# Plot 2B: RT Distribution Histogram (Supplementary)
# =============================================================================

#' Plot RT Distribution Histogram
#'
#' Creates a histogram showing the distribution of precursors across retention time.
#' Supplementary plot to the density heatmap to show temporal elution patterns.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of histogram bins (default: 50)
#'
#' @return ggplot object
#' @export
plot_rt_histogram <- function(validated_data, bins = 50) {

  cat("  Generating Plot 2B: RT Distribution Histogram...\n")

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Start)

  # Calculate statistics
  n_total <- nrow(precursor_data)
  rt_min <- min(precursor_data$RT.Start, na.rm = TRUE)
  rt_max <- max(precursor_data$RT.Start, na.rm = TRUE)
  rt_mean <- mean(precursor_data$RT.Start, na.rm = TRUE)
  rt_median <- median(precursor_data$RT.Start, na.rm = TRUE)

  # Find peak RT region
  hist_data <- hist(precursor_data$RT.Start, breaks = bins, plot = FALSE)
  peak_idx <- which.max(hist_data$counts)
  peak_rt_start <- hist_data$breaks[peak_idx]
  peak_rt_end <- hist_data$breaks[peak_idx + 1]
  peak_count <- hist_data$counts[peak_idx]

  # Calculate early vs late RT proportions
  early_rt <- sum(precursor_data$RT.Start < rt_mean)
  late_rt <- sum(precursor_data$RT.Start >= rt_mean)
  early_pct <- (early_rt / n_total) * 100
  late_pct <- (late_rt / n_total) * 100

  # Create histogram
  p <- ggplot(precursor_data, aes(x = RT.Start)) +
    geom_histogram(bins = bins, fill = "steelblue", alpha = 0.7,
                   color = "white", linewidth = 0.1) +
    geom_vline(xintercept = rt_median, linetype = "dashed",
               color = "coral", linewidth = 1) +
    geom_vline(xintercept = rt_mean, linetype = "dotted",
               color = "darkred", linewidth = 0.8) +
    annotate("rect", xmin = peak_rt_start, xmax = peak_rt_end,
             ymin = 0, ymax = peak_count, fill = "yellow", alpha = 0.3) +
    annotate("text", x = (peak_rt_start + peak_rt_end) / 2, y = peak_count * 1.05,
             label = sprintf("Peak: %.1f-%.1f min\n(%s precursors)",
                           peak_rt_start, peak_rt_end,
                           format(peak_count, big.mark = ",")),
             hjust = 0.5, vjust = 0, size = 3.5, fontface = "bold", color = "darkorange") +
    annotate("text", x = rt_median, y = Inf,
             label = sprintf("Median: %.1f min", rt_median),
             hjust = 1.1, vjust = 1.5, size = 3, color = "coral", fontface = "bold") +
    annotate("text", x = rt_mean, y = Inf,
             label = sprintf("Mean: %.1f min", rt_mean),
             hjust = -0.1, vjust = 1.5, size = 3, color = "darkred", fontface = "bold") +
    annotate("text", x = rt_max, y = Inf,
             label = sprintf("Early RT (<%.1f min): %s (%.1f%%)\nLate RT (≥%.1f min): %s (%.1f%%)",
                           rt_mean, format(early_rt, big.mark = ","), early_pct,
                           rt_mean, format(late_rt, big.mark = ","), late_pct),
             hjust = 1.05, vjust = 1.8, size = 3, family = "mono",
             lineheight = 0.9, color = "gray20") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15)), labels = scales::comma) +
    scale_x_continuous(expand = expansion(mult = c(0.01, 0.01))) +
    labs(
      title = "RT Distribution of Identified Precursors",
      subtitle = sprintf("Total: %s precursors | RT range: %.1f - %.1f min | Gradient: %.1f min",
                        format(n_total, big.mark = ","), rt_min, rt_max, rt_max - rt_min),
      x = "Retention Time (min)",
      y = "Number of Precursors",
      caption = "Dashed = median | Dotted = mean | Yellow = peak elution region"
    ) +
    theme_dia_optimizer() +
    theme(panel.grid.major.x = element_blank())

  return(p)
}

# =============================================================================
# Plot 5: Density Heatmap with m/z Range Overlay
# =============================================================================

#' Plot RT × m/z Density with Optimized m/z Range Overlay (Single Strategy)
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 50)
#'
#' @return ggplot object
#' @export
plot_density_with_mz_range <- function(optimized_windows, validated_data, bins = 50) {

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Start, Precursor.Mz)

  # Extract m/z optimization info
  mz_ranges <- optimized_windows$mz_optimization$mz_ranges
  strategy_name <- optimized_windows$mz_optimization$strategy

  # Create boundary data
  boundary_data <- mz_ranges %>%
    select(rt_start, rt_end, mz_min, mz_max) %>%
    mutate(rt_midpoint = (rt_start + rt_end) / 2)

  upper_boundary <- boundary_data %>% select(rt = rt_midpoint, mz = mz_max)
  lower_boundary <- boundary_data %>% select(rt = rt_midpoint, mz = mz_min)

  # Strategy label
  strategy_label <- switch(
    strategy_name,
    "quantile" = "Quantile (P5-P95)",
    "smoothing" = "Smoothing (SG)",
    "outlier" = "Outlier (±3SD)",
    "coverage" = "Coverage (95%)",
    strategy_name
  )

  mean_width <- mean(mz_ranges$mz_width, na.rm = TRUE)
  mean_coverage <- mean(mz_ranges$coverage_ratio, na.rm = TRUE) * 100

  # Create plot
  p <- ggplot(precursor_data, aes(x = RT.Start, y = Precursor.Mz)) +
    stat_density_2d(aes(fill = after_stat(density)), geom = "raster",
                    contour = FALSE, n = bins, alpha = 0.8) +
    geom_line(data = upper_boundary, aes(x = rt, y = mz),
              color = "#00FF00", linewidth = 1.2, inherit.aes = FALSE) +
    geom_line(data = lower_boundary, aes(x = rt, y = mz),
              color = "#00FF00", linewidth = 1.2, inherit.aes = FALSE) +
    geom_vline(data = boundary_data, aes(xintercept = rt_start),
               color = "white", alpha = 0.2, linewidth = 0.3, linetype = "dotted") +
    scale_fill_viridis_c(option = "plasma", name = "Density") +
    labs(
      title = strategy_label,
      subtitle = sprintf("Mean width: %.1f Da | Coverage: %.1f%%", mean_width, mean_coverage),
      x = "Retention Time (min)",
      y = "m/z (Da)"
    ) +
    theme_dia_optimizer() +
    theme(
      plot.title = element_text(hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, size = 10),
      legend.position = "right",
      legend.key.height = unit(1, "cm"),
      legend.key.width = unit(0.4, "cm")
    )

  return(p)
}

# =============================================================================
# Plot 4: m/z Normalized Density (Line Plot)
# =============================================================================

#' Plot m/z Density Profiles Across RT Segments
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_mz_normalized_density <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 4: m/z Normalized Density Profiles...\n")

  # Extract RT binning and m/z optimization info from optimized_windows
  n_segments <- optimized_windows$rt_binning$n_bins
  sampled_segments <- seq(1, n_segments, by = max(1, floor(n_segments / 6)))

  # Extract density profiles for sampled segments
  density_profiles <- list()

  # Get precursor data
  precursor_data <- validated_data$data

  # Get mz_ranges from optimized_windows
  if (!is.null(optimized_windows$mz_optimization$mz_ranges)) {
    mz_ranges <- optimized_windows$mz_optimization$mz_ranges
  } else {
    # Fallback: compute from windows directly
    mz_ranges <- optimized_windows$windows %>%
      group_by(rt_segment_id) %>%
      summarise(
        rt_start = min(rt_start),
        rt_end = max(rt_end),
        mz_min = min(mz_start),
        mz_max = max(mz_end),
        .groups = "drop"
      )
  }

  for (i in sampled_segments) {
    # Get RT and m/z range for this segment
    segment_range <- mz_ranges %>%
      filter(rt_segment_id == i)

    if (nrow(segment_range) == 0) next

    # Extract scalar values
    rt_start_val <- as.numeric(segment_range$rt_start[1])
    rt_end_val <- as.numeric(segment_range$rt_end[1])

    # Filter precursors in this RT segment
    segment_data <- precursor_data %>%
      filter(RT.Start >= rt_start_val & RT.Start < rt_end_val)

    if (nrow(segment_data) == 0) next

    # Calculate density
    mz_values <- segment_data$Precursor.Mz
    dens <- density(mz_values, n = 100,
                   from = segment_range$mz_min,
                   to = segment_range$mz_max)

    # Normalize
    normalized_y <- dens$y / max(dens$y)

    density_profiles[[length(density_profiles) + 1]] <- tibble(
      rt_segment = i,
      rt_label = sprintf("RT %.0f-%.0f min",
                        segment_range$rt_start,
                        segment_range$rt_end),
      mz_center = dens$x,
      normalized_density = normalized_y
    )
  }

  if (length(density_profiles) == 0) {
    # Return empty plot if no data
    return(ggplot() +
             labs(title = "m/z Normalized Density (No Data Available)") +
             theme_dia_optimizer())
  }

  density_data <- bind_rows(density_profiles)

  # Plot
  p <- ggplot(density_data, aes(x = mz_center, y = normalized_density,
                                 color = factor(rt_label))) +
    geom_line(linewidth = 1, alpha = 0.8) +
    scale_color_viridis_d(name = "RT Segment", option = "turbo") +
    labs(
      title = "m/z Density Profiles Across RT Segments",
      subtitle = "Normalized to max density per segment (sampled segments shown)",
      x = "Precursor m/z (Da)",
      y = "Normalized Density",
      caption = "Each line shows m/z distribution for one RT segment"
    ) +
    theme_dia_optimizer() +
    theme(legend.position = "right")

  return(p)
}

# =============================================================================
# Plot 5: m/z Window Width (Scatter Plot)
# =============================================================================

#' Plot Window Width Distribution Across m/z Range
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return ggplot object
#' @export
plot_mz_window_width <- function(optimized_windows) {

  cat("  Generating Plot 5: m/z Window Width Profile...\n")

  # Extract window data
  window_data <- optimized_windows$windows %>%
    mutate(rt_midpoint = (rt_start + rt_end) / 2)

  # Calculate statistics
  mean_width <- mean(window_data$window_width)
  sd_width <- sd(window_data$window_width)

  # Plot window width
  p <- ggplot(window_data, aes(x = mz_center, y = window_width,
                                color = rt_midpoint)) +
    geom_point(alpha = 0.6, size = 2) +
    geom_hline(yintercept = mean_width,
               linetype = "dashed", color = "black", linewidth = 0.8) +
    scale_color_viridis_c(name = "RT (min)", option = "viridis") +
    labs(
      title = "Window Width Distribution Across m/z Range",
      subtitle = sprintf("Mean: %.1f Da | SD: %.1f Da | CV: %.3f",
                        mean_width, sd_width, sd_width / mean_width),
      x = "Window Center m/z (Da)",
      y = "Window Width (Da)",
      caption = "Black dashed line = mean width | Color = RT segment"
    ) +
    theme_dia_optimizer()

  return(p)
}


# =============================================================================
# Deprecated Plot Functions (Removed in v3.0)
# =============================================================================
# The following functions have been removed as part of the redesign:
#   - plot_precursor_coverage_map() → Replaced by Plot 5 (2×2 coverage grid)
#   - plot_window_efficiency() → No longer needed per redesign
#   - plot_dppp_achievement_heatmap() → To be redesigned in future version
#
# New modular plot functions are sourced from separate files at the top of this module.
# See: plot4_*.R and plot5_*.R


# =============================================================================
# Main Visualization Function
# =============================================================================

#' Generate All Visualizations
#'
#' Main orchestration function that generates all 8 plots, PDF report,
#' method file, and individual plot exports.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_dir Character, output directory path
#' @param create_pdf Logical, create comprehensive PDF report
#' @param create_individual_plots Logical, export individual plots
#' @param plot_format Character, "png" or "pdf"
#' @param plot_dpi Numeric, plot resolution (default: 300)
#'
#' @return VisualizationResult object
#' @export
generate_visualizations <- function(
  validated_data,
  optimization_plan,
  optimized_windows,
  output_dir = "output/",
  create_pdf = TRUE,
  create_individual_plots = TRUE,
  plot_format = "png",
  plot_dpi = 300,
  windows_list = NULL  # Optional: Pre-computed windows for all strategies
) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   STAGE 4: Visualization & Reporting         ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  viz_start <- Sys.time()

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  cat("Step 1: Generating all plots...\n")

  # Generate all plots with standardized naming: {plot순서}_{plot이름}
  plots <- list()

  # Plot 1: DPPP Comparison - Both versions (always generate both)
  cat("  Generating Plot 1A: DPPP Comparison (Simple)...\n")
  plots$`plot1a_dppp_comparison_simple` <- plot_dppp_comparison(optimization_plan, validated_data)

  cat("  Generating Plot 1B: DPPP Comparison (Enhanced)...\n")
  plots$`plot1b_dppp_comparison_enhanced` <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)

  # Plot 2: RT × m/z Density Heatmap
  cat("  Generating Plot 2: RT × m/z Density Heatmap...\n")
  plots$`plot2_rt_mz_density_heatmap` <- plot_rt_mz_density_heatmap(validated_data)

  # Plot 2B: RT Histogram (supplementary - always generate if available)
  if (exists("plot_rt_histogram")) {
    cat("  Generating Plot 2B: RT Histogram...\n")
    plots$`plot2b_rt_histogram_continuous` <- plot_rt_histogram(validated_data)
    plots$`plot2b_rt_histogram_5min` <- plot_rt_histogram_binned(validated_data, bin_width_min = 5)
  }

  # Plot 3: m/z Density Overlay by RT Segment (limit to 6 bins for clarity)
  cat("  Generating Plot 3: m/z Density Overlay...\n")
  plots$`plot3_mz_density_overlay` <- plot_mz_normalized_density(optimized_windows, validated_data)

  # ═══════════════════════════════════════════════════════════════════════
  # Plot 4: Multi-Strategy m/z Range Optimization Comparison
  # ═══════════════════════════════════════════════════════════════════════
  # Generate optimization for all 4 strategies to compare approaches

  cat("\n  Preparing Plot 4: Multi-Strategy Comparison...\n")

  strategies <- c("quantile", "smoothing", "outlier", "coverage")

  # Use pre-computed windows_list if provided, otherwise compute
  if (is.null(windows_list)) {
    cat("  Running optimization with all 4 m/z strategies...\n")
    windows_list <- list()

    # Load Stage 3 module for optimization
    if (!exists("optimize_windows")) {
      if (file.exists("R/stage3_window_optimization.R")) {
        source("R/stage3_window_optimization.R")
      }
    }

    # Generate windows for each strategy
    for (strategy in strategies) {
      cat(sprintf("    - Optimizing with '%s' strategy...\n", strategy))
      windows_list[[strategy]] <- optimize_windows(
        validated_data = validated_data,
        optimization_plan = optimization_plan,
        rt_bin_width_min = optimized_windows$parameters$rt_bin_width_min,
        mz_strategy = strategy,
        window_mode = optimized_windows$parameters$window_mode,
        quantile_lower = 0.05,
        quantile_upper = 0.95,
        outlier_threshold = 3.0,
        smoothing_window = 7,
        polynomial_order = 3,
        target_coverage = 0.95
      )
    }
  } else {
    cat("  Using pre-computed windows for all 4 strategies (skipping re-optimization)...\n")
  }

  # Plot 4A-4D: Individual strategy m/z excluded regions (6 RT bins each)
  if (exists("plot_mz_distribution_with_exclusions")) {
    for (strategy in strategies) {
      plot_name <- sprintf("plot4_%s_mz_excluded", strategy)
      cat(sprintf("  Generating Plot 4 (%s): m/z Excluded Regions...\n", toupper(strategy)))
      plots[[plot_name]] <- plot_mz_distribution_with_exclusions(
        windows_list[[strategy]], validated_data, max_bins_to_show = 6
      )
    }
  }

  # Plot 4E: All-strategy width comparison
  if (exists("plot_mz_width_comparison_all_strategies")) {
    cat("  Generating Plot 4E: Width Comparison (All Strategies)...\n")
    plots$`plot4e_mz_width_all_strategies` <- plot_mz_width_comparison_all_strategies(
      windows_list, validated_data
    )
  }

  # Plot 5: Coverage Map 2×2 Grid (multi-strategy comparison)
  if (exists("plot_density_with_mz_ranges_grid")) {
    cat("  Generating Plot 5: Coverage Map 2×2 Grid (All Strategies)...\n")
    plots$`plot5_coverage_map_2x2` <- plot_density_with_mz_ranges_grid(
      windows_list, validated_data
    )
  } else if (exists("plot_density_with_mz_range")) {
    cat("  Generating Plot 5: Coverage Map (Single Strategy - fallback)...\n")
    plots$`plot5_coverage_map_single` <- plot_density_with_mz_range(optimized_windows, validated_data)
  }

  # Plot 6: Satisfaction Curve
  cat("  Generating Plot 6: Satisfaction vs Cycle Time Curve...\n")
  plots$`plot6_satisfaction_curve` <- plot_satisfaction_curve(optimization_plan, validated_data)

  # ═══════════════════════════════════════════════════════════════════════
  # Plot 7: Window Width Distribution by RT Segment (Multi-Strategy)
  # ═══════════════════════════════════════════════════════════════════════
  # Generate Plot 7 and 7B for each strategy to compare window width patterns

  if (exists("plot_window_width_distribution") && exists("plot_cumulative_window_count")) {
    cat("\n  Preparing Plot 7 & 7B: Window Width Analysis (Multi-Strategy)...\n")

    for (strategy in strategies) {
      # Plot 7: Density + Window Width overlay
      plot7_name <- sprintf("plot7_%s_window_width_distribution", strategy)
      cat(sprintf("  Generating Plot 7 (%s): Density + Width Overlay...\n", toupper(strategy)))
      plots[[plot7_name]] <- plot_window_width_distribution(
        windows_list[[strategy]], validated_data, max_segments_to_show = 6
      )

      # Plot 7B: Window Index + Width bars
      plot7b_name <- sprintf("plot7b_%s_window_index_width", strategy)
      cat(sprintf("  Generating Plot 7B (%s): Window Index Width Bars...\n", toupper(strategy)))
      plots[[plot7b_name]] <- plot_cumulative_window_count(
        windows_list[[strategy]], validated_data, max_segments_to_show = 6
      )
    }
  }

  # ═══════════════════════════════════════════════════════════════════════
  # Plot 8: Strategy Width Comparison (Ridge, Box, CDF)
  # ═══════════════════════════════════════════════════════════════════════
  # Compare window width distributions across all 4 strategies

  if (exists("plot_strategy_width_ridge") && exists("plot_strategy_width_boxplot") && exists("plot_strategy_width_cdf")) {
    cat("\n  Preparing Plot 8: Strategy Width Comparison (3 visualization types)...\n")

    # Plot 8A: Ridge plot
    cat("  Generating Plot 8A: Ridge Plot...\n")
    plots$`plot8a_strategy_width_ridge` <- plot_strategy_width_ridge(windows_list, validated_data)

    # Plot 8B: Box plot
    cat("  Generating Plot 8B: Box Plot...\n")
    plots$`plot8b_strategy_width_boxplot` <- plot_strategy_width_boxplot(windows_list, validated_data)

    # Plot 8C: CDF plot
    cat("  Generating Plot 8C: CDF Plot...\n")
    plots$`plot8c_strategy_width_cdf` <- plot_strategy_width_cdf(windows_list, validated_data)
  }

  cat(sprintf("✅ All %d plots generated successfully\n\n", length(plots)))

  plot_end <- Sys.time()
  plot_time <- as.numeric(difftime(plot_end, viz_start, units = "secs"))

  # Initialize result structure
  report_files <- list()

  # Step 2: Export individual plots (optional)
  if (create_individual_plots) {
    cat("Step 2: Exporting individual plots...\n")
    individual_files <- export_individual_plots(
      plots, output_dir, plot_format, plot_dpi
    )
    report_files$individual_plots <- individual_files
  } else {
    cat("Step 2: Skipping individual plot export\n")
    report_files$individual_plots <- character()
  }

  # Step 3: Create PDF report (optional)
  if (create_pdf) {
    cat("\nStep 3: Creating PDF report...\n")
    pdf_file <- file.path(output_dir, "optimization_report.pdf")
    create_pdf_report(plots, validated_data, optimization_plan, optimized_windows, pdf_file)
    report_files$pdf_report <- pdf_file
  } else {
    cat("\nStep 3: Skipping PDF report creation\n")
    report_files$pdf_report <- NULL
  }

  # Step 4: Export method file (CSV for Thermo)
  cat("\nStep 4: Exporting instrument method file...\n")
  method_file <- file.path(output_dir, "method.csv")
  export_method_file(optimized_windows, optimization_plan, method_file, validated_data)
  report_files$method_file <- method_file

  # Step 5: Calculate summary statistics
  cat("\nStep 5: Calculating summary statistics...\n")
  summary_stats <- calculate_summary_statistics(validated_data, optimization_plan, optimized_windows)

  viz_end <- Sys.time()
  total_time <- as.numeric(difftime(viz_end, viz_start, units = "secs"))

  # Package results
  result <- structure(
    list(
      plots = plots,

      report_files = report_files,

      summary_statistics = summary_stats,

      metadata = list(
        instrument_type = optimization_plan$instrument$preset,
        mz_strategy = optimized_windows$parameters$mz_strategy,
        window_mode = optimized_windows$parameters$window_mode,
        generation_timestamp = viz_start,
        plot_generation_time = plot_time,
        report_generation_time = total_time - plot_time,
        total_time = total_time
      )
    ),
    class = c("VisualizationResult", "list")
  )

  cat("\n═══════════════════════════════════════════════\n")
  cat(" STAGE 4 COMPLETE\n")
  cat("═══════════════════════════════════════════════\n")
  cat(sprintf("✓ Generated: %d plots\n", length(plots)))
  cat(sprintf("✓ Method file: %s\n", basename(method_file)))
  if (!is.null(report_files$pdf_report)) {
    cat(sprintf("✓ PDF report: %s\n", basename(report_files$pdf_report)))
  }
  cat(sprintf("✓ Total time: %.2f seconds\n", total_time))
  cat("\n")

  return(result)
}

# =============================================================================
# Helper Functions
# =============================================================================

#' Export Individual Plots
#'
#' @param plots List of ggplot objects
#' @param output_dir Output directory
#' @param format "png" or "pdf"
#' @param dpi Resolution
#'
#' @return Vector of file paths
#' @export
export_individual_plots <- function(plots, output_dir, format = "png", dpi = 300) {

  # Use plot names directly from the list
  # This makes it flexible and handles dynamically generated plots
  plot_names <- names(plots)

  if (is.null(plot_names) || length(plot_names) == 0) {
    stop("Plot list must have named elements")
  }

  file_paths <- character(length(plots))

  for (i in seq_along(plots)) {
    filename <- paste0(plot_names[i], ".", format)
    filepath <- file.path(output_dir, filename)

    ggsave(
      filepath,
      plot = plots[[i]],
      width = 10,
      height = 7,
      dpi = dpi,
      bg = "white"
    )

    file_paths[i] <- filepath
    cat(sprintf("  ✓ Saved: %s\n", filename))
  }

  return(file_paths)
}

#' Create PDF Report
#'
#' @param plots List of ggplot objects
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_file PDF output path
#'
#' @export
create_pdf_report <- function(plots, validated_data, optimization_plan,
                               optimized_windows, output_file) {

  # Create multi-panel PDF with all plots
  pdf(output_file, width = 16, height = 10)

  # Title page
  grid.newpage()
  grid.text("DIA Window Optimization Report",
            x = 0.5, y = 0.7,
            gp = gpar(fontsize = 24, fontface = "bold"))
  grid.text(sprintf("Generated: %s", Sys.time()),
            x = 0.5, y = 0.4,
            gp = gpar(fontsize = 14))
  grid.text(sprintf("Instrument: %s | Windows: %d | Coverage: %.1f%%",
                   optimization_plan$instrument$preset,
                   nrow(optimized_windows$windows),
                   optimized_windows$statistics$coverage_percentage),
            x = 0.5, y = 0.3,
            gp = gpar(fontsize = 12))

  # Plot pages (2 plots per page)
  plot_pairs <- list(
    c(1, 2), c(3, 4), c(5, 6), c(7, 8)
  )

  for (pair in plot_pairs) {
    grid.newpage()
    grid.arrange(
      plots[[pair[1]]],
      plots[[pair[2]]],
      ncol = 1
    )
  }

  dev.off()

  cat(sprintf("  ✓ PDF report saved: %s\n", basename(output_file)))
}

#' Export Method File
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_file CSV output path
#'
#' @export
export_method_file <- function(optimized_windows, optimization_plan, output_file, validated_data = NULL) {

  # Use Stage 3's export_windows_to_csv() for 22-column format consistency
  # This ensures compatibility with legacy format from results_config_based_with_viz/
  export_windows_to_csv(
    optimized_windows = optimized_windows,
    output_file = output_file,
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    instrument_type = optimization_plan$instrument$preset,
    project_name = "report",
    normalized_agc_target = 100
  )
}

#' Calculate Summary Statistics
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return List of summary statistics
#' @export
calculate_summary_statistics <- function(validated_data, optimization_plan, optimized_windows) {

  windows <- optimized_windows$windows
  window_stats <- optimized_windows$statistics

  list(
    optimization_metrics = list(
      total_windows = nrow(windows),
      window_count_per_rt = optimization_plan$window_count_per_bin,
      mean_window_width_da = mean(windows$window_width),
      precursor_coverage_pct = window_stats$coverage_percentage,
      mean_precursors_per_window = window_stats$mean_precursors_per_window,
      cv_precursors = window_stats$cv_precursors
    ),

    performance_metrics = list(
      cycle_time_sec = optimization_plan$actual_cycle_time_sec,
      scan_rate_hz = 1 / optimization_plan$actual_cycle_time_sec,
      target_dppp = optimization_plan$parameters$target_dppp,
      current_dppp_satisfaction_pct = optimization_plan$diagnosis$current_satisfaction_ratio * 100,
      required_cycle_time_sec = optimization_plan$required_cycle_time_sec
    ),

    instrument_config = list(
      instrument_type = optimization_plan$instrument$preset,
      mz_strategy = optimized_windows$parameters$mz_strategy,
      window_mode = optimized_windows$parameters$window_mode,
      n_precursors = validated_data$metadata$n_precursors,
      rt_range = validated_data$metadata$rt_range,
      mz_range = validated_data$metadata$mz_range
    )
  )
}

# =============================================================================
# Plot 9: Satisfaction vs Cycle Time Trade-off Curve
# =============================================================================

#' Plot Satisfaction Ratio vs Cycle Time Trade-off
#'
#' Shows the relationship between cycle time and DPPP satisfaction ratio
#' as a continuous curve, highlighting current state, recommended state,
#' and the optimization trade-off.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#' @param cycle_time_range Numeric vector of length 2, range of cycle times to display (default: c(0.5, 3.0))
#' @param n_points Integer, number of points to calculate along curve (default: 50)
#'
#' @return ggplot object
#' @export
plot_satisfaction_curve <- function(optimization_plan, validated_data,
                                   cycle_time_range = c(0.5, 3.0),
                                   n_points = 50) {

  cat("  Generating Plot 9: Satisfaction vs Cycle Time Trade-off Curve...\n")

  # Extract parameters
  current_cycle_time <- optimization_plan$diagnosis$current_cycle_time_sec
  required_cycle_time <- optimization_plan$required_cycle_time_sec
  target_dppp <- optimization_plan$parameters$target_dppp
  target_satisfaction <- optimization_plan$parameters$target_satisfaction * 100

  # Extract FWHM data
  fwhm_sec <- validated_data$data$FWHM * 60  # Convert to seconds

  # Calculate satisfaction across cycle time range
  cycle_times <- seq(cycle_time_range[1], cycle_time_range[2], length.out = n_points)

  satisfaction_data <- data.frame(
    cycle_time = cycle_times,
    satisfaction_pct = sapply(cycle_times, function(ct) {
      dppp <- (fwhm_sec * 1.7) / ct
      mean(dppp >= target_dppp, na.rm = TRUE) * 100
    })
  )

  # Calculate current and recommended satisfaction
  dppp_current <- (fwhm_sec * 1.7) / current_cycle_time
  current_satisfaction_pct <- mean(dppp_current >= target_dppp, na.rm = TRUE) * 100

  dppp_recommended <- (fwhm_sec * 1.7) / required_cycle_time
  recommended_satisfaction_pct <- mean(dppp_recommended >= target_dppp, na.rm = TRUE) * 100

  # Calculate improvement metrics
  cycle_time_reduction_pct <- ((current_cycle_time - required_cycle_time) / current_cycle_time) * 100
  satisfaction_gain_pp <- recommended_satisfaction_pct - current_satisfaction_pct  # percentage points

  # Create annotation text
  annotation_text <- sprintf(
    "Trade-off Analysis:\n\nCycle time: %.2f → %.2f sec\nReduction: %.1f%%\n\nSatisfaction: %.1f%% → %.1f%%\nGain: +%.1f pp\n\nFormula:\nSatisfaction = f(FWHM, cycle_time)\nTarget DPPP ≥ %.1f",
    current_cycle_time,
    required_cycle_time,
    cycle_time_reduction_pct,
    current_satisfaction_pct,
    recommended_satisfaction_pct,
    satisfaction_gain_pp,
    target_dppp
  )

  # Create plot
  p <- ggplot(satisfaction_data, aes(x = cycle_time, y = satisfaction_pct)) +
    # Reference lines
    geom_hline(
      yintercept = target_satisfaction,
      linetype = "dashed",
      color = "gray40",
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = cycle_time_range[1] + 0.1,
      y = target_satisfaction,
      label = sprintf("Target: %.0f%%", target_satisfaction),
      hjust = 0,
      vjust = -0.5,
      size = 3.5,
      fontface = "bold",
      color = "gray40"
    ) +
    geom_vline(
      xintercept = current_cycle_time,
      linetype = "dotted",
      color = "steelblue",
      linewidth = 0.6,
      alpha = 0.7
    ) +
    geom_vline(
      xintercept = required_cycle_time,
      linetype = "dotted",
      color = "coral",
      linewidth = 0.6,
      alpha = 0.7
    ) +
    # Main S-curve
    geom_line(color = "navy", linewidth = 1.5, alpha = 0.8) +
    # Current state point
    geom_point(
      data = data.frame(
        cycle_time = current_cycle_time,
        satisfaction_pct = current_satisfaction_pct
      ),
      aes(x = cycle_time, y = satisfaction_pct),
      color = "steelblue4",
      fill = "steelblue",
      size = 5,
      shape = 21,
      stroke = 2
    ) +
    annotate(
      "text",
      x = current_cycle_time,
      y = current_satisfaction_pct,
      label = sprintf("Current\n(%.2f sec, %.1f%%)", current_cycle_time, current_satisfaction_pct),
      hjust = 1.2,
      vjust = 0.5,
      size = 3.5,
      fontface = "bold",
      color = "steelblue4"
    ) +
    # Recommended state point
    geom_point(
      data = data.frame(
        cycle_time = required_cycle_time,
        satisfaction_pct = recommended_satisfaction_pct
      ),
      aes(x = cycle_time, y = satisfaction_pct),
      color = "coral4",
      fill = "coral",
      size = 5,
      shape = 21,
      stroke = 2
    ) +
    annotate(
      "text",
      x = required_cycle_time,
      y = recommended_satisfaction_pct,
      label = sprintf("Recommended\n(%.2f sec, %.1f%%)", required_cycle_time, recommended_satisfaction_pct),
      hjust = -0.2,
      vjust = 0.5,
      size = 3.5,
      fontface = "bold",
      color = "coral4"
    ) +
    # Improvement arrow (curved)
    geom_curve(
      data = data.frame(
        x = current_cycle_time,
        xend = required_cycle_time,
        y = current_satisfaction_pct + 5,
        yend = recommended_satisfaction_pct - 5
      ),
      aes(x = x, xend = xend, y = y, yend = yend),
      arrow = arrow(length = unit(0.3, "cm"), type = "closed"),
      color = "black",
      linewidth = 1,
      curvature = -0.3,
      alpha = 0.7
    ) +
    annotate(
      "text",
      x = (current_cycle_time + required_cycle_time) / 2,
      y = (current_satisfaction_pct + recommended_satisfaction_pct) / 2 + 8,
      label = sprintf("%.1f%% cycle time ↓\n+%.1f pp satisfaction ↑",
                     cycle_time_reduction_pct, satisfaction_gain_pp),
      hjust = 0.5,
      vjust = 0.5,
      size = 3.5,
      fontface = "bold",
      lineheight = 0.9
    ) +
    # Annotation box (right side, mid-to-top position to avoid overlap)
    annotate(
      "text",
      x = cycle_time_range[2] - 0.1,
      y = 90,
      label = annotation_text,
      hjust = 1,
      vjust = 1,
      size = 3,
      family = "mono",
      lineheight = 0.95
    ) +
    # Scales
    scale_x_continuous(
      breaks = seq(cycle_time_range[1], cycle_time_range[2], by = 0.5),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(
      breaks = seq(0, 100, by = 10),
      limits = c(0, 100),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    # Labels
    labs(
      title = "DPPP Satisfaction vs Cycle Time Trade-off",
      subtitle = sprintf("Optimization path from %.2f sec (%.1f%%) to %.2f sec (%.1f%%) for %s precursors",
                        current_cycle_time, current_satisfaction_pct,
                        required_cycle_time, recommended_satisfaction_pct,
                        format(nrow(validated_data$data), big.mark = ",")),
      x = "Cycle Time (seconds)",
      y = "Satisfaction Ratio (%)",
      caption = "S-curve shows trade-off between cycle time and DPPP achievement; shorter cycle time = higher satisfaction"
    ) +
    # Theme
    theme_dia_optimizer() +
    theme(
      panel.grid.minor = element_line(color = "gray95", linewidth = 0.3)
    )

  return(p)
}

cat("✅ Stage 4 (Visualization & Reporting) loaded successfully\n")
cat("   Version: 4.0 (Complete suite with multi-strategy comparison)\n")
cat("   Main function: generate_visualizations() → produces 24 plots\n")
cat("   Plot suite:\n")
cat("     - Plot 1A/1B: DPPP Distribution (Simple + Enhanced)\n")
cat("     - Plot 2/2B: RT × m/z Density Heatmap + RT Histogram\n")
cat("     - Plot 3: m/z Density Overlay by RT Segment\n")
cat("     - Plot 4 (A-E): m/z Optimization (4 strategies + comparison)\n")
cat("     - Plot 5: Coverage Map 2×2 Grid\n")
cat("     - Plot 6: Satisfaction vs Cycle Time Trade-off\n")
cat("     - Plot 7/7B (×4): Window Width Distribution (4 strategies)\n")
cat("     - Plot 8 (A/B/C): Strategy Width Comparison (Ridge/Box/CDF)\n")
cat("   Export functions: create_pdf_report(), export_method_file()\n")
cat("   Dependencies: ggplot2, dplyr, tidyr, viridis, scales, gridExtra, grid, ggridges\n")
