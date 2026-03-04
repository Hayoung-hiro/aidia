# plot_density_overlay.R
# Plot 5: RT x m/z Density Heatmap with Optimized m/z Range Overlay (2x2 Grid)
#
# Purpose: Combine Plot 2 (density heatmap) with Plot 4 (m/z range optimization)
#          to visualize how each strategy adjusts m/z ranges across RT


#' Plot RT x m/z Density Heatmap with m/z Range Overlay (Single Strategy)
#'
#' Creates density heatmap of precursors and overlays optimized m/z range
#' boundaries for one strategy.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 50)
#'
#' @return ggplot object
#' @keywords internal
plot_density_with_mz_range <- function(optimized_windows, validated_data, bins = 50) {

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Apex, Precursor.Mz)

  # Extract m/z optimization info
  mz_ranges <- optimized_windows$mz_optimization$mz_ranges
  strategy_name <- optimized_windows$mz_optimization$strategy

  # Create boundary lines data
  # For each RT segment, we have mz_min and mz_max
  boundary_data <- mz_ranges %>%
    select(rt_start, rt_end, mz_min, mz_max) %>%
    mutate(
      rt_midpoint = (rt_start + rt_end) / 2
    )

  # Create line segments for upper and lower boundaries
  upper_boundary <- boundary_data %>%
    select(rt = rt_midpoint, mz = mz_max)

  lower_boundary <- boundary_data %>%
    select(rt = rt_midpoint, mz = mz_min)

  # Strategy label (canonical labels from theme_aidia.R)
  strategy_label <- format_strategy_label(strategy_name)

  # Calculate mean m/z width
  mean_width <- mean(mz_ranges$mz_width, na.rm = TRUE)
  mean_coverage <- mean(mz_ranges$coverage_ratio, na.rm = TRUE) * 100

  # Create density heatmap with overlay
  p <- ggplot(precursor_data, aes(x = RT.Apex, y = Precursor.Mz)) +
    # Density heatmap
    stat_density_2d(
      aes(fill = after_stat(density)),
      geom = "raster",
      contour = FALSE,
      n = bins,
      alpha = 0.8
    ) +

    # Upper boundary line
    geom_line(
      data = upper_boundary,
      aes(x = rt, y = mz),
      color = "#00FF00",  # Bright green
      linewidth = 1.2,
      linetype = "solid",
      inherit.aes = FALSE
    ) +

    # Lower boundary line
    geom_line(
      data = lower_boundary,
      aes(x = rt, y = mz),
      color = "#00FF00",  # Bright green
      linewidth = 1.2,
      linetype = "solid",
      inherit.aes = FALSE
    ) +

    # Add segment vertical dividers (optional, subtle)
    geom_vline(
      data = boundary_data,
      aes(xintercept = rt_start),
      color = "white",
      alpha = 0.2,
      linewidth = 0.3,
      linetype = "dotted"
    ) +

    scale_fill_viridis_c(
      option = "plasma",
      name = "Density"
    ) +

    labs(
      title = strategy_label,
      subtitle = sprintf("Mean width: %.1f Da | Coverage: %.1f%%",
                        mean_width, mean_coverage),
      x = "Retention Time (min)",
      y = "m/z (Da)",
      caption = NULL
    ) +

    theme_aidia() +
    theme(
      plot.title = element_text(hjust = 0.5),
      plot.subtitle = element_text(size = 10, hjust = 0.5, color = "gray30"),
      legend.position = "right",
      legend.key.height = unit(1, "cm"),
      legend.key.width = unit(0.4, "cm"),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "gray90", linewidth = 0.3)
    )

  return(p)
}


#' Plot RT x m/z Density Heatmap with m/z Range Overlay (All Strategies, 2x2 Grid)
#'
#' Creates a 2x2 grid showing density heatmap with optimized m/z range overlay
#' for all optimization strategies.
#'
#' @param windows_list Named list of OptimizedWindows objects for each strategy
#'   List names should match strategy keys (e.g., "greedy", "kde", "quantile")
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 50)
#'
#' @return Combined plot (grid.arrange object)
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' windows_list <- list(
#'   quantile = optimized_windows_q,
#'   smoothing = optimized_windows_s,
#'   outlier = optimized_windows_o,
#'   coverage = optimized_windows_c
#' )
#' plot5 <- plot_density_with_mz_ranges_grid(windows_list, validated_data)
#' }
plot_density_with_mz_ranges_grid <- function(windows_list, validated_data, bins = 50) {

  cat("  Generating Plot 5: RT x m/z Density with m/z Range Overlay (2x2 Grid)...\n")

  # Use all available strategies (preserve preferred order where applicable)
  preferred_order <- c("greedy", "kde", "quantile", "coverage", "outlier")
  strategy_order <- intersect(preferred_order, names(windows_list))
  # Add any strategies not in preferred order
  strategy_order <- unique(c(strategy_order, names(windows_list)))

  # Create individual plots for each strategy
  plot_list <- list()

  for (strategy_name in strategy_order) {
    cat(sprintf("    Creating density plot for %s...\n", strategy_name))

    plot_list[[strategy_name]] <- plot_density_with_mz_range(
      optimized_windows = windows_list[[strategy_name]],
      validated_data = validated_data,
      bins = bins
    )
  }

  # Determine grid layout based on number of strategies
  n_plots <- length(plot_list)
  if (n_plots == 0) {
    cat("    No strategies to plot\n")
    return(grid::textGrob("No strategies available"))
  }

  ncol <- min(2, n_plots)
  nrow <- ceiling(n_plots / ncol)

  # Create grid using grobs list (dynamic, not hardcoded)
  combined_plot <- gridExtra::arrangeGrob(
    grobs = plot_list,
    ncol = ncol,
    nrow = nrow,
    top = grid::textGrob(
      "RT x m/z Density with Optimized m/z Range Overlay",
      gp = grid::gpar(fontsize = 16, fontface = "bold")
    ),
    bottom = grid::textGrob(
      "Green lines = Optimized m/z boundaries | Bright regions = High precursor density",
      gp = grid::gpar(fontsize = 10, col = "gray40")
    )
  )

  return(combined_plot)
}
