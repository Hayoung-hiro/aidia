# plot_strategy_radar.R
# Plot 18: Multi-Dimensional Strategy Comparison (Radar/Spider Chart)
#
# Purpose: Compare all m/z optimization strategies across multiple quality
#          dimensions simultaneously. Provides an intuitive "shape" for each
#          strategy's trade-off profile using a polar coordinate system.
#
# Dependencies: ggplot2, dplyr, tidyr


#' Compute Strategy Quality Metrics for Radar Chart
#'
#' Calculates 5 normalized quality metrics for each strategy:
#'   1. Coverage: Fraction of precursors inside at least one window
#'   2. Load Balance: 1 - CV of precursors per window (higher = more balanced)
#'   3. Width Uniformity: 1 - CV of window widths (higher = more uniform)
#'   4. Edge Safety: Fraction of precursors with edge distance >= 1 Da
#'   5. Compactness: 1 - (mean_width / max_possible_width) (smaller windows = higher)
#'
#' @param windows_list Named list of OptimizedWindows objects
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return Data frame with columns: strategy, metric, value (0-1 normalized)
#' @keywords internal
compute_strategy_radar_metrics <- function(windows_list, validated_data) {

  precursor_data <- validated_data$data
  mz_range <- range(precursor_data$Precursor.Mz, na.rm = TRUE)
  max_possible_width <- diff(mz_range)

  metrics_list <- lapply(names(windows_list), function(strategy) {
    opt <- windows_list[[strategy]]
    w <- opt$windows

    # 1. Coverage: fraction of precursors inside any window
    counts_per_precursor <- vapply(seq_len(nrow(precursor_data)), function(i) {
      rt <- precursor_data$RT.Apex[i]
      mz <- precursor_data$Precursor.Mz[i]
      any(mz >= w$mz_start & mz < w$mz_end &
          rt >= w$rt_start & rt <= w$rt_end)
    }, logical(1))
    coverage <- mean(counts_per_precursor)

    # 2. Load Balance: 1 - CV of precursor counts per window
    pcounts <- count_precursors_in_2d_windows(
      precursor_data$RT.Apex, precursor_data$Precursor.Mz,
      w$rt_start, w$rt_end, w$mz_start, w$mz_end
    )
    mean_pc <- mean(pcounts)
    load_cv <- if (mean_pc > 0) sd(pcounts) / mean_pc else 1
    load_balance <- max(0, 1 - load_cv)

    # 3. Width Uniformity: 1 - CV of window widths
    widths <- w$window_width %||% (w$mz_end - w$mz_start)
    mean_w <- mean(widths, na.rm = TRUE)
    width_cv <- if (mean_w > 0) sd(widths, na.rm = TRUE) / mean_w else 1
    width_uniformity <- max(0, 1 - width_cv)

    # 4. Edge Safety: fraction of precursors >= 1 Da from boundary
    edge_dists <- calculate_edge_distances(precursor_data, w)
    edge_dists_clean <- edge_dists[!is.na(edge_dists)]
    edge_safety <- if (length(edge_dists_clean) > 0) {
      mean(edge_dists_clean >= 1.0)
    } else {
      0
    }

    # 5. Compactness: smaller mean width = better (normalized)
    compactness <- max(0, 1 - (mean_w / max_possible_width))

    data.frame(
      strategy = strategy,
      metric = c("Coverage", "Load Balance", "Width Uniformity", "Edge Safety", "Compactness"),
      value  = c(coverage, load_balance, width_uniformity, edge_safety, compactness),
      stringsAsFactors = FALSE
    )
  })

  safe_bind_rows(metrics_list)
}


#' Plot Strategy Radar Chart
#'
#' Creates a radar/spider chart comparing all strategies across 5 quality
#' dimensions. Uses ggplot2 with coord_polar() on a closed polygon.
#'
#' @param windows_list Named list of OptimizedWindows objects
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_strategy_radar <- function(windows_list, validated_data) {

  cat("  Generating Plot 18: Strategy Radar Chart...\n")

  if (length(windows_list) < 2) {
    return(create_insufficient_data_plot(
      title = "Strategy Radar Comparison",
      message = "Need at least 2 strategies for comparison"
    ))
  }

  # Compute metrics
  metrics_df <- compute_strategy_radar_metrics(windows_list, validated_data)

  # Create metric factor with ordered levels for consistent axis arrangement
  metric_levels <- c("Coverage", "Load Balance", "Width Uniformity", "Edge Safety", "Compactness")
  metrics_df$metric <- factor(metrics_df$metric, levels = metric_levels)

  # Close the polygon: duplicate first metric row at the end for each strategy
  closing_rows <- metrics_df %>%
    filter(metric == metric_levels[1])
  metrics_closed <- rbind(metrics_df, closing_rows)

  # Assign numeric angle position (1-based, with wrap)
  metrics_closed$angle_pos <- as.numeric(metrics_closed$metric)
  # For closing rows, set position to max + 1
  n_metrics <- length(metric_levels)
  closing_idx <- (nrow(metrics_df) + 1):nrow(metrics_closed)
  metrics_closed$angle_pos[closing_idx] <- n_metrics + 1

  # Strategy labels (add to both data frames — layers reference both)
  metrics_df$strategy_label <- format_strategy_label(metrics_df$strategy)
  metrics_closed$strategy_label <- format_strategy_label(metrics_closed$strategy)

  # Grid circles data (0.25, 0.50, 0.75, 1.00)
  grid_df <- expand.grid(
    angle_pos = 1:n_metrics,
    level = c(0.25, 0.5, 0.75, 1.0)
  )

  p <- ggplot(metrics_closed, aes(x = angle_pos, y = value,
                                   group = strategy_label,
                                   color = strategy,
                                   fill = strategy)) +
    # Grid circles
    geom_hline(yintercept = c(0.25, 0.5, 0.75, 1.0),
               color = "gray85", linewidth = 0.3) +
    # Polygon fill
    geom_polygon(alpha = 0.08, linewidth = 0) +
    # Lines
    geom_path(linewidth = 1, alpha = 0.85) +
    # Points
    geom_point(
      data = metrics_df,
      aes(x = as.numeric(metric), y = value),
      size = 2.5,
      alpha = 0.9
    ) +
    # Value labels
    geom_text(
      data = metrics_df,
      aes(x = as.numeric(metric), y = value,
          label = sprintf("%.0f%%", value * 100)),
      vjust = -1,
      size = 2.5,
      show.legend = FALSE,
      fontface = "bold"
    ) +
    # Strategy colors
    scale_color_strategy() +
    scale_fill_strategy(guide = "none") +
    # Polar coordinates
    coord_polar(start = -pi / n_metrics) +
    scale_x_continuous(
      breaks = 1:n_metrics,
      labels = metric_levels,
      limits = c(0.5, n_metrics + 0.5)
    ) +
    scale_y_continuous(
      limits = c(0, 1.15),
      breaks = c(0.25, 0.5, 0.75, 1.0),
      labels = c("25%", "50%", "75%", "100%")
    ) +
    labs(
      title = "Strategy Quality Comparison",
      subtitle = "Normalized metrics (0-100%) | Larger area = better overall quality",
      color = "Strategy"
    ) +
    theme_aidia() +
    theme(
      axis.title = element_blank(),
      axis.text.y = element_text(size = 7, color = "gray50"),
      axis.text.x = element_text(face = "bold", size = 10),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      legend.position = "bottom",
      legend.title = element_text(face = "bold")
    )

  return(p)
}
