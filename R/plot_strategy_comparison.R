# plot_strategy_comparison.R
# Plot 8: 4-Strategy Window Width Comparison
#
# Purpose: Compare window width distributions across different m/z optimization strategies
#          - Plot 8A: Ridge Plot (Density overlay)
#          - Plot 8B: Box Plot (Statistical summary)
#          - Plot 8C: CDF (Cumulative distribution)


#' Plot 8A: Ridge Plot - Window Width Distribution by Strategy
#'
#' Shows overlapping density curves for each strategy (ridge plot style)
#' Useful for comparing distribution shapes across strategies
#'
#' @param windows_list Named list of OptimizedWindows objects (quantile, smoothing, outlier, coverage)
#' @param validated_data ValidatedData object from Stage 1
#' @param active_strategy Character, the user's selected strategy key (optional).
#'   When provided, the active strategy ridge is fully opaque with a bold label,
#'   while others are dimmed.
#'
#' @return ggplot object
#' @keywords internal
plot_strategy_width_ridge <- function(windows_list, validated_data,
                                      active_strategy = NULL) {

  cat("  Generating Plot 8A: Ridge Plot (Window Width by Strategy)...\n")

  # Extract window width data from all strategies
  strategy_names <- names(windows_list)
  strategy_data <- lapply(strategy_names, function(strategy) {
    windows_list[[strategy]]$windows %>%
      select(window_width) %>%
      mutate(
        strategy = strategy,
        strategy_label = factor(format_strategy_label(strategy),
                               levels = format_strategy_label(strategy_names)),
        is_active = identical(strategy, active_strategy)
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

  # Per-strategy alpha: active = full, others = dimmed
  alpha_values <- setNames(
    ifelse(strategy_names == active_strategy, 0.85, 0.4),
    strategy_names
  )
  if (is.null(active_strategy)) alpha_values[] <- 0.7

  # Y-axis label formatting: bold + marker for active strategy
  y_labels <- format_strategy_label(strategy_names)
  if (!is.null(active_strategy)) {
    active_label <- format_strategy_label(active_strategy)
    y_labels[y_labels == active_label] <- paste0("\u25b6 ", active_label, " (selected)")
  }
  y_label_map <- setNames(y_labels, format_strategy_label(strategy_names))
  y_face <- ifelse(format_strategy_label(strategy_names) ==
                     format_strategy_label(active_strategy %||% ""), "bold", "plain")

  # Create ridge plot using ggridges
  p <- ggplot(strategy_data, aes(x = window_width, y = strategy_label,
                                  fill = strategy, alpha = strategy)) +
    # Ridge density plot
    geom_density_ridges(
      scale = 0.9,
      rel_min_height = 0.01,
      quantile_lines = TRUE,
      quantiles = 2  # Show median line
    ) +
    # Color scheme (using theme_aidia's scale)
    scale_fill_strategy(guide = "none") +
    scale_color_strategy(guide = "none") +
    scale_alpha_manual(values = alpha_values, guide = "none") +
    scale_x_continuous(
      breaks = seq(0, 100, by = 10),
      labels = function(x) sprintf("%.0f", x)
    ) +
    scale_y_discrete(labels = y_label_map) +
    labs(
      title = "Window Width Distribution Comparison",
      subtitle = sprintf("%s precursors | %d strategies | Vertical line = median",
                         format(nrow(validated_data$data), big.mark = ","),
                         length(strategy_names)),
      x = "Window Width (Da)",
      y = "Strategy"
    ) +
    theme_aidia() +
    theme(
      axis.text.y = element_text(
        face = y_face
      ),
      panel.grid.major.y = element_blank()
    )

  return(p)
}
