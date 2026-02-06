# plot4_mz_range_optimization.R
# Plot 4: m/z Range Optimization (Original vs Optimized)
#
# Purpose: Visualize m/z range reduction from Stage 3C optimization
# Shows before/after comparison for each RT segment

library(dplyr)
library(ggplot2)
library(tidyr)

#' Plot m/z Range Optimization (Original vs Optimized)
#'
#' Compares original m/z range (full data range) vs optimized range
#' (after quantile/smoothing/outlier/coverage strategy) for each RT segment.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
#'
#' @examples
#' plot4 <- plot_mz_range_optimization(optimized_windows, validated_data)
plot_mz_range_optimization <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 4: m/z Range Optimization...\n")

  # Extract optimized m/z ranges from Stage 3C
  mz_ranges <- optimized_windows$mz_optimization$mz_ranges

  # Calculate original m/z range for each RT segment
  precursor_data <- validated_data$data

  original_ranges <- precursor_data %>%
    mutate(
      # Assign to RT bins using same logic as Stage 3
      rt_group = cut(
        RT.Start,
        breaks = c(mz_ranges$rt_start[1], mz_ranges$rt_end),
        labels = FALSE,
        include.lowest = TRUE
      )
    ) %>%
    filter(!is.na(rt_group)) %>%
    group_by(rt_group) %>%
    summarise(
      original_min = min(Precursor.Mz, na.rm = TRUE),
      original_max = max(Precursor.Mz, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      rt_segment_id = rt_group,
      original_width = original_max - original_min
    )

  # Combine original and optimized ranges
  comparison_data <- mz_ranges %>%
    select(rt_segment_id, rt_start, rt_end,
           optimized_min = mz_min, optimized_max = mz_max,
           optimized_width = mz_width, coverage_ratio) %>%
    left_join(original_ranges, by = "rt_segment_id") %>%
    mutate(
      rt_label = sprintf("RT%d\n%.0f-%.0f min",
                        rt_segment_id, rt_start, rt_end),
      reduction_pct = (1 - optimized_width / original_width) * 100
    )

  # Pivot for side-by-side bars
  plot_data <- comparison_data %>%
    select(rt_segment_id, rt_label,
           Original = original_width,
           Optimized = optimized_width,
           coverage_ratio, reduction_pct) %>%
    pivot_longer(
      cols = c(Original, Optimized),
      names_to = "range_type",
      values_to = "width"
    ) %>%
    mutate(
      range_type = factor(range_type, levels = c("Original", "Optimized"))
    )

  # Get strategy name
  strategy_name <- optimized_windows$mz_optimization$strategy
  strategy_label <- switch(
    strategy_name,
    "greedy" = "Greedy (MacCoss)",
    "kde" = "KDE (Density Peak)",
    "quantile" = "Quantile (P5-P95)",
    "outlier" = "Outlier Removal",
    "coverage" = "Coverage-based",
    strategy_name
  )

  # Calculate mean reduction
  mean_reduction <- mean(comparison_data$reduction_pct, na.rm = TRUE)
  mean_coverage <- mean(comparison_data$coverage_ratio, na.rm = TRUE) * 100

  # Create plot
  p <- ggplot(plot_data, aes(x = rt_label, y = width, fill = range_type)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7, alpha = 0.8) +

    # Add coverage labels on top of Optimized bars
    geom_text(
      data = comparison_data,
      aes(x = rt_label, y = optimized_width,
          label = sprintf("%.0f%%", coverage_ratio * 100)),
      vjust = -0.5,
      size = 2.5,
      inherit.aes = FALSE
    ) +

    scale_fill_manual(
      name = "m/z Range",
      values = c("Original" = "gray60", "Optimized" = "steelblue"),
      labels = c("Original" = "Original (full range)",
                 "Optimized" = sprintf("Optimized (%s)", strategy_label))
    ) +

    labs(
      title = "m/z Range Optimization by RT Segment",
      subtitle = sprintf(
        "Strategy: %s | Mean reduction: %.1f%% | Mean coverage: %.1f%%",
        strategy_label, mean_reduction, mean_coverage
      ),
      x = "RT Segment",
      y = "m/z Range Width (Da)",
      caption = "Labels show coverage % of precursors within optimized range"
    ) +

    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +

    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      plot.caption = element_text(size = 9, hjust = 0, color = "gray50"),
      legend.position = "top",
      legend.title = element_text(face = "bold", size = 10),
      legend.text = element_text(size = 9),
      axis.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank()
    )

  return(p)
}
