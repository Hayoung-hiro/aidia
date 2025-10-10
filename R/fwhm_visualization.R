# fwhm_visualization.R - RT-dependent FWHM visualization functions
#
# This module provides intuitive visualizations for understanding
# how FWHM (chromatographic peak width) varies across retention time.

library(dplyr)
library(ggplot2)
library(scales)

#' Plot RT vs FWHM scatter with trend
#'
#' Shows the relationship between retention time and peak width (FWHM).
#' Includes smoothing to reveal the overall trend.
#'
#' @param data DIA-NN data with RT.Start and FWHM columns
#' @param sample_size Number of points to plot (default: 50000 for performance)
#' @param add_segments Add RT segment boundaries (default: TRUE)
#' @param n_segments Number of RT segments to show (default: 5)
#' @return ggplot object
#' @export
plot_rt_vs_fwhm_scatter <- function(data,
                                    sample_size = 50000,
                                    add_segments = TRUE,
                                    n_segments = 5) {

  # Filter valid data
  valid_data <- data %>%
    filter(!is.na(RT.Start), !is.na(FWHM), FWHM > 0)

  # Sample if too large
  if (nrow(valid_data) > sample_size) {
    set.seed(42)
    plot_data <- valid_data %>% sample_n(sample_size)
    subtitle_note <- sprintf("(Showing %s random samples)", comma(sample_size))
  } else {
    plot_data <- valid_data
    subtitle_note <- sprintf("(All %s precursors)", comma(nrow(plot_data)))
  }

  # Convert FWHM to seconds for easier interpretation
  plot_data <- plot_data %>%
    mutate(FWHM_seconds = FWHM * 60)

  # Calculate statistics
  mean_fwhm <- mean(plot_data$FWHM_seconds)
  median_fwhm <- median(plot_data$FWHM_seconds)

  # Create base plot
  p <- ggplot(plot_data, aes(x = RT.Start, y = FWHM_seconds)) +
    geom_hex(bins = 50, alpha = 0.8) +
    scale_fill_viridis_c(
      name = "Count",
      trans = "log10",
      option = "inferno"
    ) +
    geom_smooth(
      method = "loess",
      span = 0.3,
      color = "red",
      size = 1.5,
      se = TRUE,
      alpha = 0.2
    ) +
    geom_hline(
      yintercept = mean_fwhm,
      linetype = "dashed",
      color = "white",
      alpha = 0.7,
      size = 0.8
    ) +
    annotate(
      "text",
      x = max(plot_data$RT.Start) * 0.95,
      y = mean_fwhm,
      label = sprintf("Mean: %.1f sec", mean_fwhm),
      vjust = -0.5,
      hjust = 1,
      color = "white",
      fontface = "bold",
      size = 3.5
    ) +
    labs(
      title = "RT-Dependent Peak Width (FWHM)",
      subtitle = sprintf("Mean FWHM: %.1f sec | Median: %.1f sec | %s",
                        mean_fwhm, median_fwhm, subtitle_note),
      x = "Retention Time (min)",
      y = "FWHM (seconds)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "right"
    )

  # Add RT segment boundaries if requested
  if (add_segments) {
    rt_range <- range(plot_data$RT.Start)
    segment_breaks <- seq(rt_range[1], rt_range[2], length.out = n_segments + 1)

    for (i in 2:n_segments) {
      p <- p + geom_vline(
        xintercept = segment_breaks[i],
        linetype = "dotted",
        color = "cyan",
        alpha = 0.5,
        size = 0.5
      )
    }

    p <- p + annotate(
      "text",
      x = segment_breaks[1] + diff(segment_breaks)[1] / 2,
      y = max(plot_data$FWHM_seconds) * 0.95,
      label = "Segment 1",
      color = "cyan",
      size = 3,
      alpha = 0.7
    )
  }

  return(p)
}

#' Plot FWHM distribution by RT segments
#'
#' Shows how FWHM distribution changes across retention time segments.
#' Uses violin plots to show the full distribution shape.
#'
#' @param data DIA-NN data with RT.Start and FWHM columns
#' @param n_segments Number of RT segments (default: 5)
#' @return ggplot object
#' @export
plot_fwhm_by_rt_segments <- function(data, n_segments = 5) {

  # Filter valid data
  valid_data <- data %>%
    filter(!is.na(RT.Start), !is.na(FWHM), FWHM > 0) %>%
    mutate(FWHM_seconds = FWHM * 60)

  # Create RT segments
  rt_breaks <- seq(min(valid_data$RT.Start), max(valid_data$RT.Start),
                   length.out = n_segments + 1)

  valid_data <- valid_data %>%
    mutate(
      RT_segment = cut(RT.Start, breaks = rt_breaks, include.lowest = TRUE),
      RT_segment_num = as.numeric(RT_segment)
    )

  # Calculate segment statistics
  segment_stats <- valid_data %>%
    group_by(RT_segment_num, RT_segment) %>%
    summarise(
      n = n(),
      mean_fwhm = mean(FWHM_seconds),
      median_fwhm = median(FWHM_seconds),
      sd_fwhm = sd(FWHM_seconds),
      rt_min = min(RT.Start),
      rt_max = max(RT.Start),
      .groups = 'drop'
    ) %>%
    mutate(
      segment_label = sprintf("Seg %d\n(%.0f-%.0f min)",
                             RT_segment_num, rt_min, rt_max)
    )

  # Join back to data
  valid_data <- valid_data %>%
    left_join(segment_stats %>% select(RT_segment_num, segment_label),
              by = "RT_segment_num")

  # Create plot
  p <- ggplot(valid_data, aes(x = factor(RT_segment_num), y = FWHM_seconds,
                               fill = factor(RT_segment_num))) +
    geom_violin(alpha = 0.6, scale = "width", draw_quantiles = c(0.25, 0.5, 0.75)) +
    geom_boxplot(width = 0.2, alpha = 0.8, outlier.alpha = 0.2, outlier.size = 0.5) +
    scale_fill_viridis_d(option = "plasma", guide = "none") +
    stat_summary(
      fun = mean,
      geom = "point",
      shape = 23,
      size = 4,
      fill = "white",
      color = "black"
    ) +
    stat_summary(
      fun = mean,
      geom = "text",
      aes(label = sprintf("%.1f", after_stat(y))),
      vjust = -1.5,
      size = 3.5,
      fontface = "bold"
    ) +
    scale_x_discrete(labels = segment_stats$segment_label) +
    labs(
      title = "FWHM Distribution by RT Segments",
      subtitle = sprintf("%d segments | Diamond = mean, Box = quartiles, Violin = distribution",
                        n_segments),
      x = "RT Segment",
      y = "FWHM (seconds)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      axis.text.x = element_text(size = 9)
    )

  return(p)
}

#' Plot FWHM trend with summary statistics
#'
#' Shows FWHM trends across RT with rolling statistics (mean, quartiles).
#' Provides a clear view of how peak width evolves over the gradient.
#'
#' @param data DIA-NN data with RT.Start and FWHM columns
#' @param rt_bins Number of bins for rolling statistics (default: 30)
#' @return ggplot object
#' @export
plot_fwhm_trend_summary <- function(data, rt_bins = 30) {

  # Filter valid data
  valid_data <- data %>%
    filter(!is.na(RT.Start), !is.na(FWHM), FWHM > 0) %>%
    mutate(FWHM_seconds = FWHM * 60)

  # Create RT bins
  rt_breaks <- seq(min(valid_data$RT.Start), max(valid_data$RT.Start),
                   length.out = rt_bins + 1)

  # Calculate statistics per bin
  trend_data <- valid_data %>%
    mutate(RT_bin = cut(RT.Start, breaks = rt_breaks, include.lowest = TRUE)) %>%
    group_by(RT_bin) %>%
    summarise(
      n = n(),
      RT_center = mean(RT.Start),
      mean_fwhm = mean(FWHM_seconds),
      median_fwhm = median(FWHM_seconds),
      P25_fwhm = quantile(FWHM_seconds, 0.25),
      P75_fwhm = quantile(FWHM_seconds, 0.75),
      P10_fwhm = quantile(FWHM_seconds, 0.10),
      P90_fwhm = quantile(FWHM_seconds, 0.90),
      .groups = 'drop'
    ) %>%
    filter(n > 10)  # Remove bins with too few points

  # Create plot
  p <- ggplot(trend_data, aes(x = RT_center)) +
    # Ribbon for 10-90 percentile range
    geom_ribbon(
      aes(ymin = P10_fwhm, ymax = P90_fwhm),
      fill = "lightblue",
      alpha = 0.3
    ) +
    # Ribbon for 25-75 percentile range (IQR)
    geom_ribbon(
      aes(ymin = P25_fwhm, ymax = P75_fwhm),
      fill = "steelblue",
      alpha = 0.4
    ) +
    # Median line
    geom_line(
      aes(y = median_fwhm, color = "Median"),
      size = 1.5
    ) +
    # Mean line
    geom_line(
      aes(y = mean_fwhm, color = "Mean"),
      size = 1.5,
      linetype = "dashed"
    ) +
    scale_color_manual(
      name = "Statistic",
      values = c("Median" = "darkblue", "Mean" = "red")
    ) +
    labs(
      title = "FWHM Trend Across Retention Time",
      subtitle = "Blue ribbon: IQR (25-75%) | Light blue: P10-P90 | Lines: Mean & Median",
      x = "Retention Time (min)",
      y = "FWHM (seconds)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "bottom"
    )

  return(p)
}

#' Plot FWHM coefficient of variation by RT
#'
#' Shows the relative variability of FWHM across retention time.
#' Useful for identifying regions with inconsistent peak shapes.
#'
#' @param data DIA-NN data with RT.Start and FWHM columns
#' @param rt_bins Number of bins (default: 20)
#' @return ggplot object
#' @export
plot_fwhm_cv_by_rt <- function(data, rt_bins = 20) {

  # Filter valid data
  valid_data <- data %>%
    filter(!is.na(RT.Start), !is.na(FWHM), FWHM > 0) %>%
    mutate(FWHM_seconds = FWHM * 60)

  # Create RT bins
  rt_breaks <- seq(min(valid_data$RT.Start), max(valid_data$RT.Start),
                   length.out = rt_bins + 1)

  # Calculate CV per bin
  cv_data <- valid_data %>%
    mutate(RT_bin = cut(RT.Start, breaks = rt_breaks, include.lowest = TRUE)) %>%
    group_by(RT_bin) %>%
    summarise(
      n = n(),
      RT_center = mean(RT.Start),
      mean_fwhm = mean(FWHM_seconds),
      sd_fwhm = sd(FWHM_seconds),
      CV = (sd_fwhm / mean_fwhm) * 100,
      .groups = 'drop'
    ) %>%
    filter(n > 10)

  # Create plot
  p <- ggplot(cv_data, aes(x = RT_center, y = CV)) +
    geom_area(fill = "steelblue", alpha = 0.4) +
    geom_line(color = "darkblue", size = 1.2) +
    geom_point(aes(size = n), color = "darkblue", alpha = 0.6) +
    geom_hline(
      yintercept = mean(cv_data$CV),
      linetype = "dashed",
      color = "red",
      size = 1
    ) +
    annotate(
      "text",
      x = max(cv_data$RT_center) * 0.95,
      y = mean(cv_data$CV),
      label = sprintf("Mean CV: %.1f%%", mean(cv_data$CV)),
      vjust = -0.5,
      hjust = 1,
      color = "red",
      fontface = "bold"
    ) +
    scale_size_continuous(name = "Precursors", range = c(2, 8)) +
    labs(
      title = "FWHM Variability Across Retention Time",
      subtitle = "Coefficient of Variation (CV) = SD / Mean × 100%",
      x = "Retention Time (min)",
      y = "CV (%)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "right"
    )

  return(p)
}

#' Create comprehensive FWHM analysis report
#'
#' Generates multiple visualizations to understand RT-dependent FWHM patterns.
#'
#' @param data DIA-NN data with RT.Start and FWHM columns
#' @param n_segments Number of RT segments (default: 5)
#' @param output_file PDF file path (optional)
#' @return List of ggplot objects
#' @export
create_fwhm_analysis_report <- function(data,
                                       n_segments = 5,
                                       output_file = NULL) {

  cat("\n=== Creating FWHM Analysis Report ===\n")

  plots <- list()

  # Plot 1: RT vs FWHM scatter with trend
  cat("  Creating RT vs FWHM scatter...\n")
  plots$scatter <- plot_rt_vs_fwhm_scatter(data, n_segments = n_segments)

  # Plot 2: FWHM by RT segments
  cat("  Creating segment distribution...\n")
  plots$segments <- plot_fwhm_by_rt_segments(data, n_segments = n_segments)

  # Plot 3: FWHM trend summary
  cat("  Creating trend summary...\n")
  plots$trend <- plot_fwhm_trend_summary(data)

  # Plot 4: FWHM CV by RT
  cat("  Creating variability analysis...\n")
  plots$cv <- plot_fwhm_cv_by_rt(data)

  # Save if output file specified
  if (!is.null(output_file)) {
    combined <- gridExtra::grid.arrange(
      grobs = plots,
      ncol = 2,
      top = grid::textGrob("RT-Dependent FWHM Analysis",
                           gp = grid::gpar(fontsize = 18, fontface = "bold"))
    )

    ggplot2::ggsave(
      output_file,
      combined,
      width = 14,
      height = 14,
      dpi = 300
    )

    cat(sprintf("\n✓ Report saved to: %s\n", output_file))
  }

  return(plots)
}
