# complexity_visualization.R - DIA Complexity Visualization
# DIA Window Optimizer v2.2
#
# Purpose: Visualization functions for DIA complexity metrics
# Creates publication-quality plots for complexity analysis
#
# Author: DIAoptimizer Team
# Version: 1.0
# Last Updated: 2025-11-27

library(ggplot2)
library(dplyr)
library(tidyr)

# =============================================================================
# Theme and Color Constants
# =============================================================================

#' DIA Optimizer Color Palette for Complexity
complexity_colors <- list(
  # Complexity levels (green to red)
  very_low = "#2E7D32",   # Dark green
  low = "#66BB6A",        # Light green
  moderate = "#FFA726",   # Orange
  high = "#EF5350",       # Light red
  very_high = "#B71C1C",  # Dark red

  # Component colors
  density = "#1976D2",    # Blue
  crowding = "#7B1FA2",   # Purple
  spacing = "#00796B",    # Teal
  chimeric = "#C62828",   # Red

  # Heatmap
  low_density = "#FFFFFF",
  high_density = "#B71C1C"
)


# =============================================================================
# Individual Metric Plots
# =============================================================================

#' Plot PCI Distribution
#'
#' Creates a histogram of Precursor Co-isolation Index values
#'
#' @param pci PCI object from calculate_pci()
#' @param title Character, plot title (default: auto-generated)
#'
#' @return ggplot object
#' @export
plot_pci_distribution <- function(pci, title = NULL) {

  if (is.null(title)) {
    title <- sprintf("Precursor Co-isolation Distribution (Mean: %.1f)",
                     pci$mean_pci)
  }

  # Create data frame for plotting
  df <- data.frame(co_isolation = pci$distribution)

  # Add complexity level coloring
  df <- df %>%
    mutate(
      level = case_when(
        co_isolation == 0 ~ "Clean (0)",
        co_isolation <= 3 ~ "Low (1-3)",
        co_isolation <= 10 ~ "Moderate (4-10)",
        TRUE ~ "High (>10)"
      ),
      level = factor(level, levels = c("Clean (0)", "Low (1-3)",
                                        "Moderate (4-10)", "High (>10)"))
    )

  # Create plot
  p <- ggplot(df, aes(x = co_isolation, fill = level)) +
    geom_histogram(binwidth = 1, color = "white", size = 0.2) +
    geom_vline(xintercept = pci$mean_pci, linetype = "dashed",
               color = "black", size = 1) +
    annotate("text", x = pci$mean_pci, y = Inf,
             label = sprintf("Mean: %.1f", pci$mean_pci),
             hjust = -0.1, vjust = 2, fontface = "bold") +
    scale_fill_manual(
      values = c(
        "Clean (0)" = complexity_colors$very_low,
        "Low (1-3)" = complexity_colors$low,
        "Moderate (4-10)" = complexity_colors$moderate,
        "High (>10)" = complexity_colors$high
      ),
      name = "Complexity"
    ) +
    labs(
      title = title,
      subtitle = sprintf("Based on %d precursors, RT window: %.0fs, m/z window: %.0f Da",
                         pci$n_sampled, pci$rt_window_sec, pci$mz_window_da),
      x = "Number of Co-isolated Precursors",
      y = "Count"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      legend.position = "right"
    )

  return(p)
}


#' Plot RCI RT Density Profile
#'
#' Creates a line plot showing precursor density across the RT gradient
#'
#' @param rci RCI object from calculate_rci()
#' @param highlight_hotspots Logical, highlight hotspot regions (default: TRUE)
#'
#' @return ggplot object
#' @export
plot_rci_profile <- function(rci, highlight_hotspots = TRUE) {

  # Create data frame
  df <- data.frame(
    rt = rci$bin_mids,
    density = rci$density_per_min,
    count = rci$bin_counts
  )

  # Base plot
  p <- ggplot(df, aes(x = rt, y = density)) +
    geom_area(fill = complexity_colors$crowding, alpha = 0.3) +
    geom_line(color = complexity_colors$crowding, size = 1)

  # Add hotspot highlighting
  if (highlight_hotspots && !is.null(rci$hotspot_details)) {
    hotspots <- rci$hotspot_details
    p <- p +
      geom_rect(
        data = hotspots,
        aes(xmin = rt_start, xmax = rt_end, ymin = 0, ymax = Inf),
        fill = complexity_colors$high, alpha = 0.2, inherit.aes = FALSE
      )
  }

  # Add mean line
  p <- p +
    geom_hline(yintercept = rci$mean_density_per_min, linetype = "dashed",
               color = "gray40") +
    annotate("text", x = max(df$rt), y = rci$mean_density_per_min,
             label = sprintf("Mean: %.0f/min", rci$mean_density_per_min),
             hjust = 1, vjust = -0.5, size = 3)

  # Labels and theme
  p <- p +
    labs(
      title = "RT Crowding Profile",
      subtitle = sprintf("Gini: %.2f, Peak/Avg: %.1fx, %d hotspots detected",
                         rci$gini_coefficient, rci$peak_to_avg_ratio, rci$n_hotspots),
      x = "Retention Time (min)",
      y = "Precursor Density (per min)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14)
    )

  return(p)
}


#' Plot MSS Spacing Distribution
#'
#' Creates a histogram/density plot of m/z spacing values
#'
#' @param mss MSS object from calculate_mss()
#' @param log_scale Logical, use log scale for x-axis (default: TRUE)
#'
#' @return ggplot object
#' @export
plot_mss_distribution <- function(mss, log_scale = TRUE) {

  df <- data.frame(spacing = mss$all_spacings)

  # Add spacing category
  df <- df %>%
    mutate(
      category = case_when(
        spacing < 0.01 ~ "Critical (<0.01 Da)",
        spacing < 0.1 ~ "Very Close (0.01-0.1 Da)",
        spacing < 1.0 ~ "Close (0.1-1.0 Da)",
        spacing < 2.0 ~ "Adequate (1-2 Da)",
        TRUE ~ "Well Spaced (>2 Da)"
      ),
      category = factor(category, levels = c(
        "Critical (<0.01 Da)", "Very Close (0.01-0.1 Da)",
        "Close (0.1-1.0 Da)", "Adequate (1-2 Da)", "Well Spaced (>2 Da)"
      ))
    )

  p <- ggplot(df, aes(x = spacing, fill = category)) +
    geom_histogram(bins = 50, color = "white", size = 0.1)

  if (log_scale) {
    p <- p + scale_x_log10(
      breaks = c(0.01, 0.1, 1, 10),
      labels = c("0.01", "0.1", "1", "10")
    )
  }

  p <- p +
    scale_fill_manual(
      values = c(
        "Critical (<0.01 Da)" = complexity_colors$very_high,
        "Very Close (0.01-0.1 Da)" = complexity_colors$high,
        "Close (0.1-1.0 Da)" = complexity_colors$moderate,
        "Adequate (1-2 Da)" = complexity_colors$low,
        "Well Spaced (>2 Da)" = complexity_colors$very_low
      ),
      name = "Spacing"
    ) +
    geom_vline(xintercept = mss$global_mean_spacing, linetype = "dashed",
               color = "black", size = 1) +
    labs(
      title = "m/z Spacing Distribution",
      subtitle = sprintf("Mean: %.2f Da, Median: %.2f Da, %d critical pairs (<0.01 Da)",
                         mss$global_mean_spacing, mss$global_median_spacing,
                         mss$n_critical_pairs),
      x = if (log_scale) "m/z Spacing (Da, log scale)" else "m/z Spacing (Da)",
      y = "Count"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      legend.position = "right"
    )

  return(p)
}


#' Plot CSI Chimeric Distribution
#'
#' Creates a bar chart showing chimeric spectrum severity distribution
#'
#' @param csi CSI object from calculate_csi()
#'
#' @return ggplot object
#' @export
plot_csi_distribution <- function(csi) {

  # Create severity data
  df <- data.frame(
    severity = factor(c("Clean", "Low", "Medium", "High", "Severe"),
                      levels = c("Clean", "Low", "Medium", "High", "Severe")),
    count = c(csi$n_clean, csi$n_low, csi$n_medium, csi$n_high, csi$n_severe),
    label = c("1 precursor", "2 precursors", "3-5 precursors",
              "6-10 precursors", ">10 precursors")
  )

  df <- df %>%
    mutate(
      percentage = count / sum(count) * 100,
      bar_label = sprintf("%.1f%%", percentage)
    )

  p <- ggplot(df, aes(x = severity, y = count, fill = severity)) +
    geom_bar(stat = "identity", color = "white", size = 0.5) +
    geom_text(aes(label = bar_label), vjust = -0.5, fontface = "bold") +
    scale_fill_manual(
      values = c(
        "Clean" = complexity_colors$very_low,
        "Low" = complexity_colors$low,
        "Medium" = complexity_colors$moderate,
        "High" = complexity_colors$high,
        "Severe" = complexity_colors$very_high
      ),
      guide = "none"
    ) +
    labs(
      title = "Chimeric Spectrum Severity Distribution",
      subtitle = sprintf("Total windows: %d, Chimeric ratio: %.1f%%",
                         csi$n_windows, csi$chimeric_ratio * 100),
      x = "Severity Level",
      y = "Number of Windows"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14)
    )

  return(p)
}


#' Plot CHS Density Heatmap
#'
#' Creates a 2D heatmap of precursor density in RT × m/z space
#'
#' @param chs CHS object from calculate_chs()
#' @param data Original data for optional precursor overlay
#' @param show_hotspots Logical, highlight hotspot regions (default: TRUE)
#'
#' @return ggplot object
#' @export
plot_chs_heatmap <- function(chs, data = NULL, show_hotspots = TRUE) {

  # Convert matrix to long format
  df <- expand.grid(
    rt_idx = seq_len(chs$rt_bins),
    mz_idx = seq_len(chs$mz_bins)
  ) %>%
    mutate(
      rt = (chs$rt_breaks[rt_idx] + chs$rt_breaks[rt_idx + 1]) / 2,
      mz = (chs$mz_breaks[mz_idx] + chs$mz_breaks[mz_idx + 1]) / 2,
      density = as.vector(chs$density_matrix)
    )

  p <- ggplot(df, aes(x = rt, y = mz, fill = density)) +
    geom_tile() +
    scale_fill_gradient(
      low = "white",
      high = complexity_colors$high_density,
      name = "Precursors",
      trans = "sqrt"  # Square root scale for better visualization
    )

  # Highlight hotspots
  if (show_hotspots && !is.null(chs$hotspot_details)) {
    hotspots <- chs$hotspot_details
    p <- p +
      geom_point(
        data = hotspots,
        aes(x = rt_center, y = mz_center),
        color = "yellow", size = 2, shape = 8, inherit.aes = FALSE
      )
  }

  p <- p +
    labs(
      title = "Precursor Density Heatmap (RT × m/z)",
      subtitle = sprintf("Max density: %d, Hotspots: %d, Entropy: %.2f",
                         chs$max_density, chs$n_hotspots, chs$spatial_entropy),
      x = "Retention Time (min)",
      y = "m/z (Da)"
    ) +
    coord_fixed(ratio = diff(chs$rt_range) / diff(chs$mz_range) * 0.5) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14)
    )

  return(p)
}


# =============================================================================
# UDCS Composite Plots
# =============================================================================

#' Plot UDCS Radar Chart
#'
#' Creates a radar/spider chart showing UDCS component scores
#'
#' @param udcs UDCS object from calculate_udcs()
#'
#' @return ggplot object
#' @export
plot_udcs_radar <- function(udcs) {

  # Prepare data for radar chart
  components <- data.frame(
    component = c("Density", "Crowding", "Spacing", "Chimeric"),
    score = c(
      udcs$components$density,
      udcs$components$crowding,
      udcs$components$spacing,
      udcs$components$chimeric
    ),
    max_score = 25
  ) %>%
    mutate(
      normalized = score / max_score,
      angle = (seq_len(n()) - 1) * 2 * pi / n(),
      x = normalized * cos(angle),
      y = normalized * sin(angle)
    )

  # Close the polygon
  components_closed <- rbind(components, components[1, ])

  # Create radar plot
  p <- ggplot() +
    # Background circles
    geom_path(
      data = data.frame(
        x = cos(seq(0, 2*pi, length.out = 100)),
        y = sin(seq(0, 2*pi, length.out = 100))
      ),
      aes(x = x, y = y), color = "gray80", size = 0.5
    ) +
    geom_path(
      data = data.frame(
        x = 0.5 * cos(seq(0, 2*pi, length.out = 100)),
        y = 0.5 * sin(seq(0, 2*pi, length.out = 100))
      ),
      aes(x = x, y = y), color = "gray80", size = 0.5, linetype = "dashed"
    ) +
    # Radial lines
    geom_segment(
      data = components,
      aes(x = 0, y = 0, xend = cos(angle), yend = sin(angle)),
      color = "gray80", size = 0.5
    ) +
    # Score polygon
    geom_polygon(
      data = components_closed,
      aes(x = x, y = y),
      fill = complexity_colors$density, alpha = 0.3
    ) +
    geom_path(
      data = components_closed,
      aes(x = x, y = y),
      color = complexity_colors$density, size = 1.5
    ) +
    # Points
    geom_point(
      data = components,
      aes(x = x, y = y),
      color = complexity_colors$density, size = 4
    ) +
    # Labels
    geom_text(
      data = components,
      aes(
        x = 1.2 * cos(angle),
        y = 1.2 * sin(angle),
        label = sprintf("%s\n%.1f/25", component, score)
      ),
      size = 3.5, fontface = "bold"
    ) +
    # Center label
    annotate("text", x = 0, y = 0,
             label = sprintf("UDCS\n%.1f", udcs$total_score),
             size = 5, fontface = "bold") +
    coord_fixed() +
    labs(
      title = "UDCS Component Breakdown",
      subtitle = udcs$interpretation
    ) +
    theme_void() +
    theme(
      plot.title = element_text(face = "bold", size = 14, hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, color = "gray40")
    )

  return(p)
}


#' Plot UDCS Gauge
#'
#' Creates a gauge-style visualization of the total UDCS score
#'
#' @param udcs UDCS object from calculate_udcs()
#'
#' @return ggplot object
#' @export
plot_udcs_gauge <- function(udcs) {

  score <- udcs$total_score

  # Determine color based on score
  score_color <- case_when(
    score < 20 ~ complexity_colors$very_low,
    score < 40 ~ complexity_colors$low,
    score < 60 ~ complexity_colors$moderate,
    score < 80 ~ complexity_colors$high,
    TRUE ~ complexity_colors$very_high
  )

  # Create gauge data
  gauge_bg <- data.frame(
    x = c(0, 100),
    y = c(1, 1)
  )

  gauge_fill <- data.frame(
    xmin = 0,
    xmax = score,
    ymin = 0.8,
    ymax = 1.2
  )

  # Zone markers
  zones <- data.frame(
    xmin = c(0, 20, 40, 60, 80),
    xmax = c(20, 40, 60, 80, 100),
    label = c("Very Low", "Low", "Moderate", "High", "Very High"),
    color = c(
      complexity_colors$very_low,
      complexity_colors$low,
      complexity_colors$moderate,
      complexity_colors$high,
      complexity_colors$very_high
    )
  )

  p <- ggplot() +
    # Background zones
    geom_rect(
      data = zones,
      aes(xmin = xmin, xmax = xmax, ymin = 0.4, ymax = 0.6, fill = color),
      alpha = 0.3
    ) +
    scale_fill_identity() +
    # Score bar
    geom_rect(
      data = gauge_fill,
      aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
      fill = score_color
    ) +
    # Score indicator
    geom_segment(
      aes(x = score, xend = score, y = 0.7, yend = 1.3),
      color = "black", size = 2
    ) +
    # Score label
    annotate("text", x = score, y = 1.5,
             label = sprintf("%.1f", score),
             size = 8, fontface = "bold") +
    # Zone labels
    geom_text(
      data = zones,
      aes(x = (xmin + xmax) / 2, y = 0.2, label = label),
      size = 3, color = "gray40"
    ) +
    # Axis
    scale_x_continuous(breaks = seq(0, 100, 20), limits = c(-5, 105)) +
    coord_fixed(ratio = 20) +
    labs(
      title = "Unified DIA Complexity Score (UDCS)",
      subtitle = udcs$interpretation
    ) +
    theme_void() +
    theme(
      plot.title = element_text(face = "bold", size = 14, hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, color = "gray40")
    )

  return(p)
}


# =============================================================================
# Complexity Dashboard
# =============================================================================

#' Create Complexity Dashboard
#'
#' Creates a multi-panel dashboard with all complexity metrics
#'
#' @param complexity DIAComplexity object from calculate_all_complexity_metrics()
#' @param data Original data tibble (optional, for heatmap precursor overlay)
#'
#' @return List of ggplot objects or combined plot
#' @export
plot_complexity_dashboard <- function(complexity, data = NULL) {

  # Individual plots
  p1 <- plot_pci_distribution(complexity$pci)
  p2 <- plot_rci_profile(complexity$rci)
  p3 <- plot_mss_distribution(complexity$mss)
  p4 <- plot_csi_distribution(complexity$csi)
  p5 <- plot_chs_heatmap(complexity$chs, data = data)
  p6 <- plot_udcs_radar(complexity$udcs)

  # Return list of plots
  plots <- list(
    pci = p1,
    rci = p2,
    mss = p3,
    csi = p4,
    chs = p5,
    udcs = p6
  )

  return(plots)
}


#' Save Complexity Dashboard to PDF
#'
#' Creates a multi-page PDF with all complexity visualizations
#'
#' @param complexity DIAComplexity object
#' @param output_path Character, path to save PDF
#' @param data Original data (optional)
#' @param width Numeric, page width in inches (default: 11)
#' @param height Numeric, page height in inches (default: 8.5)
#'
#' @export
save_complexity_dashboard <- function(complexity,
                                       output_path,
                                       data = NULL,
                                       width = 11,
                                       height = 8.5) {

  plots <- plot_complexity_dashboard(complexity, data)

  # Open PDF device
  pdf(output_path, width = width, height = height)

  # Page 1: UDCS Overview
  print(plots$udcs)

  # Page 2: PCI Distribution
  print(plots$pci)

  # Page 3: RCI Profile
  print(plots$rci)

  # Page 4: MSS Distribution
  print(plots$mss)

  # Page 5: CSI Distribution
  print(plots$csi)

  # Page 6: CHS Heatmap
  print(plots$chs)

  dev.off()

  cat(sprintf("✅ Complexity dashboard saved to: %s\n", output_path))
  cat(sprintf("   6 pages generated\n"))

  invisible(output_path)
}


# =============================================================================
# Module Loading
# =============================================================================

cat("✅ Complexity visualization module loaded successfully\n")
cat("   Available functions:\n")
cat("   - plot_pci_distribution(): PCI histogram\n")
cat("   - plot_rci_profile(): RT density profile\n")
cat("   - plot_mss_distribution(): m/z spacing histogram\n")
cat("   - plot_csi_distribution(): Chimeric severity bars\n")
cat("   - plot_chs_heatmap(): 2D density heatmap\n")
cat("   - plot_udcs_radar(): UDCS component radar\n")
cat("   - plot_udcs_gauge(): UDCS score gauge\n")
cat("   - plot_complexity_dashboard(): All plots\n")
cat("   - save_complexity_dashboard(): Export to PDF\n")
