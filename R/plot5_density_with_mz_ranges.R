# plot5_density_with_mz_ranges.R
# Plot 5: RT × m/z Density Heatmap with Optimized m/z Range Overlay (2×2 Grid)
#
# Purpose: Combine Plot 2 (density heatmap) with Plot 4 (m/z range optimization)
#          to visualize how each strategy adjusts m/z ranges across RT

library(dplyr)
library(ggplot2)
library(tidyr)
library(gridExtra)
library(grid)
library(viridis)

#' Plot RT × m/z Density Heatmap with m/z Range Overlay (Single Strategy)
#'
#' Creates density heatmap of precursors and overlays optimized m/z range
#' boundaries for one strategy.
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

  # Get strategy label
  strategy_label <- switch(
    strategy_name,
    "quantile" = "Quantile (P5-P95)",
    "smoothing" = "Smoothing (SG)",
    "outlier" = "Outlier (±3SD)",
    "coverage" = "Coverage (95%)",
    strategy_name
  )

  # Calculate mean m/z width
  mean_width <- mean(mz_ranges$mz_width, na.rm = TRUE)
  mean_coverage <- mean(mz_ranges$coverage_ratio, na.rm = TRUE) * 100

  # Create density heatmap with overlay
  p <- ggplot(precursor_data, aes(x = RT.Start, y = Precursor.Mz)) +
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

    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold", size = 12, hjust = 0.5),
      plot.subtitle = element_text(size = 10, hjust = 0.5, color = "gray30"),
      legend.position = "right",
      legend.key.height = unit(1, "cm"),
      legend.key.width = unit(0.4, "cm"),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "gray90", linewidth = 0.3)
    )

  return(p)
}


#' Plot RT × m/z Density Heatmap with m/z Range Overlay (All Strategies, 2×2 Grid)
#'
#' Creates a 2×2 grid showing density heatmap with optimized m/z range overlay
#' for all 4 optimization strategies.
#'
#' @param windows_list Named list of OptimizedWindows objects for each strategy
#'   List names should be: "quantile", "smoothing", "outlier", "coverage"
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 50)
#'
#' @return Combined plot (grid.arrange object)
#' @export
#'
#' @examples
#' windows_list <- list(
#'   quantile = optimized_windows_q,
#'   smoothing = optimized_windows_s,
#'   outlier = optimized_windows_o,
#'   coverage = optimized_windows_c
#' )
#' plot5 <- plot_density_with_mz_ranges_grid(windows_list, validated_data)
plot_density_with_mz_ranges_grid <- function(windows_list, validated_data, bins = 50) {

  cat("  Generating Plot 5: RT × m/z Density with m/z Range Overlay (2×2 Grid)...\n")

  # Ensure correct order
  strategy_order <- c("quantile", "smoothing", "outlier", "coverage")

  # Create individual plots for each strategy
  plot_list <- list()

  for (strategy_name in strategy_order) {
    if (!strategy_name %in% names(windows_list)) {
      stop(sprintf("Strategy '%s' not found in windows_list", strategy_name))
    }

    cat(sprintf("    Creating density plot for %s...\n", strategy_name))

    plot_list[[strategy_name]] <- plot_density_with_mz_range(
      optimized_windows = windows_list[[strategy_name]],
      validated_data = validated_data,
      bins = bins
    )
  }

  # Create 2×2 grid
  combined_plot <- gridExtra::arrangeGrob(
    plot_list$quantile,
    plot_list$smoothing,
    plot_list$outlier,
    plot_list$coverage,
    ncol = 2,
    nrow = 2,
    top = grid::textGrob(
      "RT × m/z Density with Optimized m/z Range Overlay",
      gp = grid::gpar(fontsize = 16, fontface = "bold")
    ),
    bottom = grid::textGrob(
      "Green lines = Optimized m/z boundaries | Bright regions = High precursor density",
      gp = grid::gpar(fontsize = 10, col = "gray40")
    )
  )

  return(combined_plot)
}
