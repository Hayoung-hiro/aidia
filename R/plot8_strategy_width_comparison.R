# plot8_strategy_width_comparison.R
# Plot 8: 4-Strategy Window Width Comparison
#
# Purpose: Compare window width distributions across different m/z optimization strategies
#          - Plot 8A: Ridge Plot (Density overlay)
#          - Plot 8B: Box Plot (Statistical summary)
#          - Plot 8C: CDF (Cumulative distribution)


if (!exists("theme_aidia") && !isNamespaceLoaded("aidia")) {
  if (file.exists("R/theme_aidia.R")) {
    source("R/theme_aidia.R")
  }
}

#' Plot 8A: Ridge Plot - Window Width Distribution by Strategy
#'
#' Shows overlapping density curves for each strategy (ridge plot style)
#' Useful for comparing distribution shapes across strategies
#'
#' @param windows_list Named list of OptimizedWindows objects (quantile, smoothing, outlier, coverage)
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_strategy_width_ridge <- function(windows_list, validated_data) {

  cat("  Generating Plot 8A: Ridge Plot (Window Width by Strategy)...\n")

  # Source theme_aidia for format_strategy_label() and color scales
  if (!exists("format_strategy_label") && !isNamespaceLoaded("aidia")) {
    if (file.exists("R/theme_aidia.R")) {
      source("R/theme_aidia.R")
    }
  }

  # Extract window width data from all strategies
  strategy_names <- names(windows_list)
  strategy_data <- lapply(strategy_names, function(strategy) {
    windows_list[[strategy]]$windows %>%
      select(window_width) %>%
      mutate(
        strategy = strategy,
        strategy_label = factor(format_strategy_label(strategy),
                               levels = format_strategy_label(strategy_names))
      )
  }) %>%
    safe_bind_rows()

  # Check for minimum data points (density estimation requires >= 2 points per group)
  if (nrow(strategy_data) < 2) {
    return(create_insufficient_data_plot(
      title = "Window Width Distribution by Strategy (Ridge)",
      message = "Insufficient data for ridge plot\n(need at least 2 windows)"
    ))
  }

  # Calculate statistics for subtitle
  stats_summary <- strategy_data %>%
    group_by(strategy) %>%
    summarize(
      mean = mean(window_width),
      median = median(window_width),
      sd = sd(window_width),
      .groups = "drop"
    )

  # Create ridge plot using ggridges
  p <- ggplot(strategy_data, aes(x = window_width, y = strategy_label, fill = strategy)) +
    # Ridge density plot
    geom_density_ridges(
      alpha = 0.7,
      scale = 0.9,
      rel_min_height = 0.01,
      quantile_lines = TRUE,
      quantiles = 2  # Show median line
    ) +
    # Color scheme (using theme_aidia's scale)
    scale_fill_strategy(guide = "none") +
    scale_color_strategy(guide = "none") +
    scale_x_continuous(
      breaks = seq(0, 100, by = 10),
      labels = function(x) sprintf("%.0f", x)
    ) +
    labs(
      title = "Window Width Distribution Comparison",
      subtitle = "Ridge plot showing density curves for each m/z optimization strategy",
      x = "Window Width (Da)",
      y = "Strategy"
    ) +
    theme_aidia() +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 9),
      axis.title = element_text(size = 10),
      axis.text = element_text(size = 9),
      axis.text.y = element_text(face = "bold"),
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_blank()
    )

  return(p)
}


#' Plot 8B: Box Plot - Window Width Statistical Summary
#'
#' Shows box plots with statistical summaries for each strategy
#' Includes median, quartiles, and outliers
#'
#' @param windows_list Named list of OptimizedWindows objects
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_strategy_width_boxplot <- function(windows_list, validated_data) {

  cat("  Generating Plot 8B: Box Plot (Window Width by Strategy)...\n")

  # Source theme_aidia for format_strategy_label() and color scales
  if (!exists("format_strategy_label") && !isNamespaceLoaded("aidia")) {
    if (file.exists("R/theme_aidia.R")) {
      source("R/theme_aidia.R")
    }
  }

  # Extract window width data from all strategies
  strategy_names <- names(windows_list)
  strategy_data <- lapply(strategy_names, function(strategy) {
    windows_list[[strategy]]$windows %>%
      select(window_width) %>%
      mutate(strategy = strategy)
  }) %>%
    safe_bind_rows()

  # Calculate statistics for annotation
  stats_summary <- strategy_data %>%
    group_by(strategy) %>%
    summarize(
      n = n(),
      mean = mean(window_width),
      median = median(window_width),
      q1 = quantile(window_width, 0.25),
      q3 = quantile(window_width, 0.75),
      min = min(window_width),
      max = max(window_width),
      cv = sd(window_width) / mean(window_width),
      .groups = "drop"
    )

  # Create box plot with formatted labels
  strategy_data_formatted <- strategy_data %>%
    mutate(strategy_label = factor(format_strategy_label(strategy),
                                   levels = format_strategy_label(strategy_names)))

  p <- ggplot(strategy_data_formatted, aes(x = strategy_label, y = window_width, fill = strategy)) +
    # Box plot
    geom_boxplot(
      alpha = 0.7,
      outlier.shape = 21,
      outlier.size = 1.5,
      outlier.stroke = 0.5
    ) +
    # Add mean points
    stat_summary(
      fun = mean,
      geom = "point",
      shape = 23,
      size = 3,
      fill = "white",
      color = "black"
    ) +
    # Color scheme (using theme_aidia's scale)
    scale_fill_strategy(guide = "none") +
    scale_y_continuous(
      breaks = seq(0, 100, by = 10),
      labels = function(x) sprintf("%.1f", x)
    ) +
    labs(
      title = "Window Width Statistical Comparison",
      subtitle = "Box plot with median (line), mean (diamond), and outliers\nLower/Upper hinges = 25th/75th percentiles",
      x = "Strategy",
      y = "Window Width (Da)"
    ) +
    theme_aidia() +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 8, lineheight = 1.2),
      axis.title = element_text(size = 10),
      axis.text = element_text(size = 9),
      axis.text.x = element_text(face = "bold"),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank()
    )

  return(p)
}


#' Plot 8C: CDF - Cumulative Distribution Function
#'
#' Shows cumulative distribution of window widths for each strategy
#' Useful for comparing distributions statistically
#'
#' @param windows_list Named list of OptimizedWindows objects
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_strategy_width_cdf <- function(windows_list, validated_data) {

  cat("  Generating Plot 8C: CDF (Window Width by Strategy)...\n")

  # Source theme_aidia for format_strategy_label() and color scales
  if (!exists("format_strategy_label") && !isNamespaceLoaded("aidia")) {
    if (file.exists("R/theme_aidia.R")) {
      source("R/theme_aidia.R")
    }
  }

  # Extract window width data from all strategies
  strategy_names <- names(windows_list)
  strategy_data <- lapply(strategy_names, function(strategy) {
    windows_list[[strategy]]$windows %>%
      select(window_width) %>%
      mutate(strategy = strategy)
  }) %>%
    safe_bind_rows()

  # Calculate statistics for annotation
  stats_summary <- strategy_data %>%
    group_by(strategy) %>%
    summarize(
      median = median(window_width),
      mean = mean(window_width),
      .groups = "drop"
    )

  # Create CDF plot
  p <- ggplot(strategy_data, aes(x = window_width, color = strategy)) +
    # CDF lines
    stat_ecdf(
      geom = "step",
      linewidth = 1.2,
      pad = FALSE
    ) +
    # Add median reference lines (vertical)
    geom_vline(
      data = stats_summary,
      aes(xintercept = median, color = strategy),
      linetype = "dashed",
      linewidth = 0.5,
      alpha = 0.5
    ) +
    # Color scheme (using theme_aidia's scale)
    scale_color_strategy() +
    scale_x_continuous(
      breaks = seq(0, 100, by = 10),
      labels = function(x) sprintf("%.0f", x)
    ) +
    scale_y_continuous(
      breaks = seq(0, 1, by = 0.1),
      labels = scales::percent_format(accuracy = 1)
    ) +
    labs(
      title = "Cumulative Distribution Function (CDF)",
      subtitle = "Shows cumulative probability of window width\nDashed lines indicate median width for each strategy",
      x = "Window Width (Da)",
      y = "Cumulative Probability"
    ) +
    theme_aidia() +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 8, lineheight = 1.2),
      axis.title = element_text(size = 10),
      axis.text = element_text(size = 9),
      legend.position = "right",
      legend.title = element_text(size = 9, face = "bold"),
      legend.text = element_text(size = 8),
      panel.grid.minor = element_blank()
    )

  return(p)
}


#' Plot 8: Combined Strategy Width Comparison (3-panel)
#'
#' Creates a combined figure with Ridge, Box, and CDF plots
#'
#' @param windows_list Named list of OptimizedWindows objects
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return Combined grid plot
#' @export
plot_strategy_width_comparison_combined <- function(windows_list, validated_data) {

  cat("  Generating Plot 8: Combined Strategy Width Comparison (3-panel)...\n")

  # Generate individual plots
  p_ridge <- plot_strategy_width_ridge(windows_list, validated_data)
  p_box <- plot_strategy_width_boxplot(windows_list, validated_data)
  p_cdf <- plot_strategy_width_cdf(windows_list, validated_data)

  # Combine in 3-row layout
  combined <- grid.arrange(
    p_ridge,
    p_box,
    p_cdf,
    ncol = 1,
    heights = c(1, 1, 1)
  )

  return(combined)
}
