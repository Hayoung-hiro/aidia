# plot4_mz_width_comparison.R
# Plot 4 Supplementary: m/z Range Width Comparison (Bar Charts)
#
# Purpose: Compare Original vs Optimized m/z width across RT segments
#          as a quantitative bar chart visualization

library(dplyr)
library(ggplot2)
library(tidyr)
library(gridExtra)
library(grid)

#' Plot m/z Width Comparison (Single Strategy)
#'
#' Creates a side-by-side bar chart comparing original m/z range width
#' vs optimized width for each RT segment.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
#'
#' @examples
#' plot4b <- plot_mz_width_comparison(optimized_windows, validated_data)
plot_mz_width_comparison <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 4B: m/z Width Comparison (Bar Chart)...\n")

  # Extract optimized m/z ranges
  mz_ranges <- optimized_windows$mz_optimization$mz_ranges
  precursor_data <- validated_data$data

  # Calculate original m/z width for each RT segment
  original_widths <- precursor_data %>%
    mutate(
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
      original_width = max(Precursor.Mz, na.rm = TRUE) - min(Precursor.Mz, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(rt_segment_id = rt_group)

  # Combine with optimized widths
  comparison_data <- mz_ranges %>%
    select(rt_segment_id, rt_start, rt_end,
           optimized_width = mz_width, coverage_ratio) %>%
    left_join(original_widths, by = "rt_segment_id") %>%
    mutate(
      rt_label = sprintf("RT%02d\n%.0f-%.0f", rt_segment_id, rt_start, rt_end),
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
      names_to = "width_type",
      values_to = "width"
    ) %>%
    mutate(
      width_type = factor(width_type, levels = c("Original", "Optimized"))
    )

  # Get strategy info
  strategy_name <- optimized_windows$mz_optimization$strategy
  strategy_label <- switch(
    strategy_name,
    "greedy" = "Greedy (MacCoss)",
    "kde" = "KDE (Density Peak)",
    "quantile" = "Quantile (P5-P95)",
    "outlier" = "Outlier Removal (±3SD)",
    "coverage" = "Coverage-based (95%)",
    strategy_name
  )

  # Calculate statistics
  mean_original <- mean(comparison_data$original_width, na.rm = TRUE)
  mean_optimized <- mean(comparison_data$optimized_width, na.rm = TRUE)
  mean_reduction <- mean(comparison_data$reduction_pct, na.rm = TRUE)
  mean_coverage <- mean(comparison_data$coverage_ratio, na.rm = TRUE) * 100

  # Create plot
  p <- ggplot(plot_data, aes(x = rt_label, y = width, fill = width_type)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7, alpha = 0.8) +

    # Add coverage labels on optimized bars
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
      labels = c("Original" = sprintf("Original (mean: %.1f Da)", mean_original),
                 "Optimized" = sprintf("Optimized (mean: %.1f Da)", mean_optimized))
    ) +

    labs(
      title = "m/z Range Width Comparison by RT Segment",
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


#' Plot m/z Width Comparison - All Strategies Overlay
#'
#' Creates a single grouped bar chart comparing Original m/z width
#' vs all strategies in one plot.
#'
#' @param windows_list Named list of OptimizedWindows objects
#'   Names: strategy name keys (e.g., "greedy", "kde", "quantile", "coverage", "outlier")
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
#'
#' @examples
#' windows_list <- list(
#'   quantile = optimized_windows_q,
#'   smoothing = optimized_windows_s,
#'   outlier = optimized_windows_o,
#'   coverage = optimized_windows_c
#' )
#' plot4c <- plot_mz_width_comparison_all_strategies(windows_list, validated_data)
plot_mz_width_comparison_all_strategies <- function(windows_list, validated_data) {

  cat("  Generating Plot 4C: m/z Width Comparison (All Strategies Overlay)...\n")

  # Strategy colors (Original = gray, 4 strategies colored)
  bar_colors <- c(
    "Original" = "gray60",
    "Quantile" = "steelblue",
    "Smoothing" = "seagreen",
    "Outlier" = "darkorange",
    "Coverage" = "mediumpurple"
  )

  strategy_labels <- c(
    "greedy" = "Greedy (MacCoss)",
    "kde" = "KDE (Density Peak)",
    "quantile" = "Quantile (P5-P95)",
    "outlier" = "Outlier (±3SD)",
    "coverage" = "Coverage (95%)"
  )

  # Get reference mz_ranges (use quantile for RT bin structure)
  ref_mz_ranges <- windows_list[[1]]$mz_optimization$mz_ranges
  precursor_data <- validated_data$data

  # Calculate original widths
  original_widths <- precursor_data %>%
    mutate(
      rt_group = cut(
        RT.Start,
        breaks = c(ref_mz_ranges$rt_start[1], ref_mz_ranges$rt_end),
        labels = FALSE,
        include.lowest = TRUE
      )
    ) %>%
    filter(!is.na(rt_group)) %>%
    group_by(rt_group) %>%
    summarise(
      width = max(Precursor.Mz, na.rm = TRUE) - min(Precursor.Mz, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      rt_segment_id = rt_group,
      rt_label = sprintf("RT%02d", rt_group),
      strategy = "Original"
    ) %>%
    select(rt_segment_id, rt_label, strategy, width)

  # Collect optimized widths from all strategies
  all_widths <- list()
  all_widths[[1]] <- original_widths

  for (strategy_name in names(windows_list)) {
    mz_ranges <- windows_list[[strategy_name]]$mz_optimization$mz_ranges

    strategy_widths <- mz_ranges %>%
      mutate(
        rt_label = sprintf("RT%02d", rt_segment_id),
        strategy = tools::toTitleCase(strategy_name),
        width = mz_width
      ) %>%
      select(rt_segment_id, rt_label, strategy, width)

    all_widths[[length(all_widths) + 1]] <- strategy_widths
  }

  # Combine all data
  plot_data <- safe_bind_rows(all_widths) %>%
    mutate(
      strategy = factor(
        strategy,
        levels = c("Original", "Quantile", "Smoothing", "Outlier", "Coverage")
      )
    )

  # Calculate summary statistics
  strategy_stats <- plot_data %>%
    filter(strategy != "Original") %>%
    group_by(strategy) %>%
    summarise(
      mean_width = mean(width, na.rm = TRUE),
      .groups = "drop"
    )

  mean_original <- mean(original_widths$width, na.rm = TRUE)

  subtitle_text <- sprintf(
    "Original: %.1f Da | Quantile: %.1f | Smoothing: %.1f | Outlier: %.1f | Coverage: %.1f Da",
    mean_original,
    strategy_stats$mean_width[strategy_stats$strategy == "Quantile"],
    strategy_stats$mean_width[strategy_stats$strategy == "Smoothing"],
    strategy_stats$mean_width[strategy_stats$strategy == "Outlier"],
    strategy_stats$mean_width[strategy_stats$strategy == "Coverage"]
  )

  # Create grouped bar chart
  p <- ggplot(plot_data, aes(x = rt_label, y = width, fill = strategy)) +
    geom_col(position = position_dodge(width = 0.85), width = 0.8, alpha = 0.85) +

    scale_fill_manual(
      name = "Strategy",
      values = bar_colors,
      labels = c("Original" = "Original (full range)",
                 "Quantile" = "Quantile (P5-P95)",
                 "Smoothing" = "Smoothing (SG)",
                 "Outlier" = "Outlier (±3SD)",
                 "Coverage" = "Coverage (95%)")
    ) +

    labs(
      title = "m/z Range Width Comparison: All Strategies",
      subtitle = subtitle_text,
      x = "RT Segment",
      y = "m/z Range Width (Da)",
      caption = "Grouped bars show Original + 4 optimization strategies per RT segment"
    ) +

    scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +

    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 9, color = "gray30"),
      plot.caption = element_text(size = 9, hjust = 0, color = "gray50"),
      legend.position = "top",
      legend.title = element_text(face = "bold", size = 10),
      legend.text = element_text(size = 9),
      axis.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank()
    )

  return(p)
}
