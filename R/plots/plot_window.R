# plot_window.R - Window Width Visualization Functions
#
# Purpose: Generate window width distribution plots
#
# Functions:
#   - plot_mz_window_width(): Window width scatter plot across m/z range
#
# Dependencies: ggplot2, dplyr, viridis

library(ggplot2)
library(dplyr)
library(viridis)

# =============================================================================
# Plot 5: m/z Window Width Distribution
# =============================================================================

#' Plot Window Width Distribution Across m/z Range
#'
#' Creates a scatter plot showing how window widths are distributed
#' across the m/z range, colored by RT segment.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return ggplot object
#' @export
plot_mz_window_width <- function(optimized_windows) {

  cat("  Generating Plot 5: m/z Window Width Profile...\n")

  # Extract window data
  window_data <- optimized_windows$windows %>%
    mutate(rt_midpoint = (rt_start + rt_end) / 2)

  # Calculate statistics
  mean_width <- mean(window_data$window_width)
  sd_width <- sd(window_data$window_width)

  # Plot window width
  p <- ggplot(window_data, aes(x = mz_center, y = window_width,
                                color = rt_midpoint)) +
    geom_point(alpha = 0.6, size = 2) +
    geom_hline(yintercept = mean_width,
               linetype = "dashed", color = "black", linewidth = 0.8) +
    scale_color_viridis_c(name = "RT (min)", option = "viridis") +
    labs(
      title = "Window Width Distribution Across m/z Range",
      subtitle = sprintf("Mean: %.1f Da | SD: %.1f Da | CV: %.3f",
                        mean_width, sd_width, sd_width / mean_width),
      x = "Window Center m/z (Da)",
      y = "Window Width (Da)",
      caption = "Black dashed line = mean width | Color = RT segment"
    ) +
    theme_aidia()

  return(p)
}

cat("  [plot_window.R] Window width functions loaded\n")
