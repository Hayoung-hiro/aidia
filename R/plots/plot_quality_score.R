# plot_quality_score.R - Quality Score Visualization
#
# Purpose: Generate visualization for Quality Score metrics comparison
#
# Version: 1.0 (Initial implementation)
#
# Plots:
#   1. plot_quality_radar(): Radar/Spider chart for 4 metrics
#   2. plot_quality_comparison(): Bar chart comparing strategies
#   3. plot_quality_breakdown(): Stacked bar showing metric contributions
#
# Dependencies: ggplot2, dplyr, tidyr

library(ggplot2)
library(dplyr)
library(tidyr)

# =============================================================================
# Main Quality Score Plot Functions
# =============================================================================

#' Create Quality Score Comparison Plot
#'
#' Bar chart comparing overall quality scores and individual metrics
#' across different m/z optimization strategies.
#'
#' @param quality_scores Named list of quality score results
#'   Each element should be output from calculate_quality_score()
#' @param theme_func Optional custom ggplot2 theme function
#'
#' @return ggplot2 object
#' @export
plot_quality_comparison <- function(quality_scores, theme_func = theme_minimal) {
  if (length(quality_scores) == 0) {
    return(NULL)
  }

  # Prepare data for plotting
  plot_data <- data.frame(
    strategy = names(quality_scores),
    quality_score = sapply(quality_scores, function(q) q$quality_score),
    coverage = sapply(quality_scores, function(q) q$metrics["coverage"] * 100),
    uniformity = sapply(quality_scores, function(q) q$metrics["uniformity"] * 100),
    efficiency = sapply(quality_scores, function(q) q$metrics["efficiency"] * 100),
    specificity = sapply(quality_scores, function(q) q$metrics["specificity"] * 100),
    stringsAsFactors = FALSE
  )

  # Reorder by quality score
  plot_data$strategy <- factor(plot_data$strategy,
                               levels = plot_data$strategy[order(-plot_data$quality_score)])

  # Long format for metrics
  plot_long <- plot_data %>%
    tidyr::pivot_longer(
      cols = c(coverage, uniformity, efficiency, specificity),
      names_to = "metric",
      values_to = "value"
    )

  # Capitalize metric names
  plot_long$metric <- factor(
    plot_long$metric,
    levels = c("coverage", "uniformity", "efficiency", "specificity"),
    labels = c("Coverage", "Uniformity", "Efficiency", "Specificity")
  )

  # Define colors
  strategy_colors <- c(
    "quantile" = "#3498db",
    "smoothing" = "#e74c3c",
    "outlier" = "#2ecc71",
    "coverage" = "#f39c12"
  )

  # Create main comparison plot
  p <- ggplot(plot_data, aes(x = strategy, y = quality_score, fill = strategy)) +
    geom_bar(stat = "identity", width = 0.7, alpha = 0.9) +
    geom_text(aes(label = sprintf("%.1f%%", quality_score)),
              vjust = -0.5, size = 4, fontface = "bold") +
    scale_fill_manual(values = strategy_colors, guide = "none") +
    scale_y_continuous(limits = c(0, 105), expand = c(0, 0)) +
    labs(
      title = "Window Optimization Quality Score",
      subtitle = "Higher score = better optimization quality",
      x = "m/z Optimization Strategy",
      y = "Quality Score (%)"
    ) +
    theme_func() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 10, color = "gray40"),
      axis.text.x = element_text(size = 11),
      axis.title = element_text(size = 11)
    )

  p
}


#' Create Quality Metrics Breakdown Plot
#'
#' Shows individual metric contributions to the overall quality score
#' with weighted contributions highlighted.
#'
#' @param quality_scores Named list of quality score results
#' @param theme_func Optional custom ggplot2 theme function
#'
#' @return ggplot2 object
#' @export
plot_quality_breakdown <- function(quality_scores, theme_func = theme_minimal) {
  if (length(quality_scores) == 0) {
    return(NULL)
  }

  # Get weights from first result
  weights <- quality_scores[[1]]$weights

  # Prepare data
  plot_data <- lapply(names(quality_scores), function(strategy) {
    q <- quality_scores[[strategy]]
    data.frame(
      strategy = strategy,
      metric = c("Coverage", "Uniformity", "Efficiency", "Specificity"),
      raw_value = as.numeric(q$metrics) * 100,
      weight = as.numeric(weights),
      weighted_value = as.numeric(q$metrics) * as.numeric(weights) * 100,
      stringsAsFactors = FALSE
    )
  }) %>% bind_rows()

  # Reorder strategies by total score
  strategy_order <- names(quality_scores)[order(
    -sapply(quality_scores, function(q) q$quality_score)
  )]
  plot_data$strategy <- factor(plot_data$strategy, levels = strategy_order)

  # Metric order and colors
  plot_data$metric <- factor(
    plot_data$metric,
    levels = c("Specificity", "Efficiency", "Uniformity", "Coverage")
  )

  metric_colors <- c(
    "Coverage" = "#3498db",
    "Uniformity" = "#2ecc71",
    "Efficiency" = "#f39c12",
    "Specificity" = "#9b59b6"
  )

  p <- ggplot(plot_data, aes(x = strategy, y = weighted_value, fill = metric)) +
    geom_bar(stat = "identity", position = "stack", width = 0.7, alpha = 0.85) +
    geom_text(data = plot_data %>%
                group_by(strategy) %>%
                summarize(total = sum(weighted_value), .groups = "drop"),
              aes(x = strategy, y = total, label = sprintf("%.1f%%", total)),
              inherit.aes = FALSE,
              vjust = -0.5, size = 3.5, fontface = "bold") +
    scale_fill_manual(values = metric_colors, name = "Metric") +
    scale_y_continuous(limits = c(0, 105), expand = c(0, 0)) +
    labs(
      title = "Quality Score Breakdown by Metric",
      subtitle = sprintf("Weights: Coverage=%.0f%%, Uniformity=%.0f%%, Efficiency=%.0f%%, Specificity=%.0f%%",
                         weights["coverage"] * 100,
                         weights["uniformity"] * 100,
                         weights["efficiency"] * 100,
                         weights["specificity"] * 100),
      x = "Strategy",
      y = "Weighted Contribution (%)"
    ) +
    theme_func() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 9, color = "gray40"),
      axis.text.x = element_text(size = 11),
      legend.position = "right"
    )

  p
}


#' Create Quality Metrics Heatmap
#'
#' Heatmap showing all 4 metrics across all strategies
#' for easy visual comparison.
#'
#' @param quality_scores Named list of quality score results
#' @param theme_func Optional custom ggplot2 theme function
#'
#' @return ggplot2 object
#' @export
plot_quality_heatmap <- function(quality_scores, theme_func = theme_minimal) {
  if (length(quality_scores) == 0) {
    return(NULL)
  }

  # Prepare heatmap data
  plot_data <- lapply(names(quality_scores), function(strategy) {
    q <- quality_scores[[strategy]]
    data.frame(
      strategy = strategy,
      metric = c("Coverage", "Uniformity", "Efficiency", "Specificity"),
      value = as.numeric(q$metrics) * 100,
      stringsAsFactors = FALSE
    )
  }) %>% bind_rows()

  # Order strategies by total score
  strategy_order <- names(quality_scores)[order(
    -sapply(quality_scores, function(q) q$quality_score)
  )]
  plot_data$strategy <- factor(plot_data$strategy, levels = strategy_order)

  # Order metrics
  plot_data$metric <- factor(
    plot_data$metric,
    levels = c("Coverage", "Uniformity", "Efficiency", "Specificity")
  )

  p <- ggplot(plot_data, aes(x = metric, y = strategy, fill = value)) +
    geom_tile(color = "white", linewidth = 1) +
    geom_text(aes(label = sprintf("%.0f%%", value)),
              size = 4, fontface = "bold") +
    scale_fill_gradient2(
      low = "#e74c3c",
      mid = "#f1c40f",
      high = "#27ae60",
      midpoint = 50,
      limits = c(0, 100),
      name = "Score (%)"
    ) +
    labs(
      title = "Quality Metrics Heatmap",
      subtitle = "Comparison across all strategies and metrics",
      x = "Metric",
      y = "Strategy"
    ) +
    theme_func() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 10, color = "gray40"),
      axis.text = element_text(size = 11),
      panel.grid = element_blank(),
      legend.position = "right"
    )

  p
}


#' Create Single Strategy Quality Summary Plot
#'
#' For cases where only one strategy is used, show a single
#' quality gauge/summary visualization.
#'
#' @param quality_score Single quality score result from calculate_quality_score()
#' @param strategy_name Character, name of the strategy
#' @param theme_func Optional custom ggplot2 theme function
#'
#' @return ggplot2 object
#' @export
plot_quality_single <- function(quality_score, strategy_name = "Strategy", theme_func = theme_minimal) {
  if (is.null(quality_score) || is.na(quality_score$quality_score)) {
    return(NULL)
  }

  # Prepare data
  metrics_df <- data.frame(
    metric = c("Coverage", "Uniformity", "Efficiency", "Specificity"),
    value = as.numeric(quality_score$metrics) * 100,
    weight = as.numeric(quality_score$weights) * 100
  )
  metrics_df$weighted = metrics_df$value * quality_score$weights

  # Reorder by value
  metrics_df$metric <- factor(metrics_df$metric,
                              levels = metrics_df$metric[order(metrics_df$value)])

  # Metric colors
  metric_colors <- c(
    "Coverage" = "#3498db",
    "Uniformity" = "#2ecc71",
    "Efficiency" = "#f39c12",
    "Specificity" = "#9b59b6"
  )

  # Score interpretation
  interpretation <- interpret_quality_score(quality_score$quality_score)

  p <- ggplot(metrics_df, aes(x = metric, y = value, fill = metric)) +
    geom_bar(stat = "identity", width = 0.7, alpha = 0.85) +
    geom_text(aes(label = sprintf("%.1f%%", value)),
              hjust = -0.2, size = 3.5) +
    geom_hline(yintercept = c(40, 55, 70, 85),
               linetype = "dashed", color = "gray60", alpha = 0.5) +
    coord_flip(ylim = c(0, 105)) +
    scale_fill_manual(values = metric_colors, guide = "none") +
    labs(
      title = sprintf("Quality Score: %.1f%% (%s)", quality_score$quality_score, strategy_name),
      subtitle = interpretation,
      x = NULL,
      y = "Score (%)"
    ) +
    theme_func() +
    theme(
      plot.title = element_text(hjust = 0, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0, size = 10, color = "gray40"),
      axis.text.y = element_text(size = 11, face = "bold")
    )

  p
}


cat("  [plot_quality_score.R] Quality Score plot functions loaded\n")
