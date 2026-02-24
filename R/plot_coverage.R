# plot_coverage.R - Coverage Map Visualization Functions
#
# Purpose: Generate coverage map plots showing m/z range optimization overlays
#
# Functions:
#   - plot_density_with_mz_range(): Single strategy coverage overlay
#
# Dependencies: ggplot2, dplyr, viridis


# =============================================================================
# Plot 5: Density Heatmap with m/z Range Overlay
# =============================================================================

#' Plot RT x m/z Density with Optimized m/z Range Overlay (Single Strategy)
#'
#' Creates a 2D density heatmap with optimized m/z range boundaries overlaid.
#' Shows how the optimization strategy defines the m/z coverage region.
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
    select(RT.Apex, Precursor.Mz)

  # Extract m/z optimization info
  mz_ranges <- optimized_windows$mz_optimization$mz_ranges
  strategy_name <- optimized_windows$mz_optimization$strategy

  # Create boundary data
  boundary_data <- mz_ranges %>%
    select(rt_start, rt_end, mz_min, mz_max) %>%
    mutate(rt_midpoint = (rt_start + rt_end) / 2)

  upper_boundary <- boundary_data %>% select(rt = rt_midpoint, mz = mz_max)
  lower_boundary <- boundary_data %>% select(rt = rt_midpoint, mz = mz_min)

  # Strategy label (canonical labels from theme_aidia.R)
  strategy_label <- format_strategy_label(strategy_name)

  mean_width <- mean(mz_ranges$mz_width, na.rm = TRUE)
  mean_coverage <- mean(mz_ranges$coverage_ratio, na.rm = TRUE) * 100

  # Create plot
  p <- ggplot(precursor_data, aes(x = RT.Apex, y = Precursor.Mz)) +
    stat_density_2d(aes(fill = after_stat(density)), geom = "raster",
                    contour = FALSE, n = bins, alpha = 0.8) +
    geom_line(data = upper_boundary, aes(x = rt, y = mz),
              color = "#00FF00", linewidth = 1.2, inherit.aes = FALSE) +
    geom_line(data = lower_boundary, aes(x = rt, y = mz),
              color = "#00FF00", linewidth = 1.2, inherit.aes = FALSE) +
    geom_vline(data = boundary_data, aes(xintercept = rt_start),
               color = "white", alpha = 0.2, linewidth = 0.3, linetype = "dotted") +
    scale_fill_viridis_c(option = "plasma", name = "Density") +
    labs(
      title = strategy_label,
      subtitle = sprintf("Mean width: %.1f Da | Coverage: %.1f%%", mean_width, mean_coverage),
      x = "Retention Time (min)",
      y = "m/z (Da)"
    ) +
    theme_aidia() +
    theme(
      plot.title = element_text(hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, size = 10),
      legend.position = "right",
      legend.key.height = unit(1, "cm"),
      legend.key.width = unit(0.4, "cm")
    )

  return(p)
}

if (!isNamespaceLoaded("aidia")) cat("  [plot_coverage.R] Coverage map functions loaded\n")
