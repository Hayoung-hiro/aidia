#' Isolation Window Gantt Chart
#'
#' Creates a Gantt-style chart showing all isolation windows as rectangles in RT × m/z space.
#' Each window is colored by precursor density. Optional precursor overlay available.
#'
#' @param optimized_windows OptimizedWindows object containing windows tibble with columns:
#'   rt_segment_id, rt_start, rt_end, window_id, mz_start, mz_end, mz_center, mz_width, n_precursors
#' @param validated_data ValidatedData object (optional). If provided and show_precursors = TRUE,
#'   overlays actual precursor locations
#' @param show_precursors Logical. If TRUE and validated_data is provided, overlay precursor points
#' @param max_precursors Integer. Maximum precursors to plot (randomly sampled if exceeded).
#'   Prevents rendering issues with large datasets. Default: 5000
#'
#' @return A ggplot object showing isolation windows as rectangles in RT × m/z space
#'
#' @details
#' The plot shows:
#' - X-axis: Retention Time (minutes)
#' - Y-axis: m/z (Da)
#' - Rectangles: Isolation windows (rt_start to rt_end × mz_start to mz_end)
#' - Fill color: n_precursors (viridis cividis scale, colorblind safe)
#' - RT bin boundaries: Vertical dashed lines
#' - Optional precursor overlay: Scatter points showing actual precursor locations
#'
#' @examples
#' \dontrun{
#' # Basic Gantt chart
#' p1 <- plot_isolation_window_gantt(optimized_windows)
#'
#' # With precursor overlay
#' p2 <- plot_isolation_window_gantt(optimized_windows, validated_data,
#'                                    show_precursors = TRUE)
#' }
#'
library(ggplot2)
library(dplyr)

#' @export
plot_isolation_window_gantt <- function(optimized_windows,
                                        validated_data = NULL,
                                        show_precursors = FALSE,
                                        max_precursors = 5000) {

  # Extract windows tibble
  windows <- optimized_windows$windows

  if (nrow(windows) == 0) {
    stop("No windows found in optimized_windows object")
  }

  # Calculate summary statistics for subtitle
  n_windows <- nrow(windows)
  mean_width <- mean(windows$mz_width, na.rm = TRUE)
  n_rt_bins <- length(unique(windows$rt_segment_id))

  # Get RT bin boundaries for vertical lines
  rt_boundaries <- unique(c(windows$rt_start, max(windows$rt_end)))
  rt_boundaries <- sort(rt_boundaries)

  # Start building plot
  p <- ggplot(windows) +
    # Draw windows as rectangles
    geom_rect(aes(xmin = rt_start, xmax = rt_end,
                  ymin = mz_start, ymax = mz_end,
                  fill = n_precursors),
              alpha = 0.7, color = "white", linewidth = 0.2) +
    # Color scale for precursor density
    scale_fill_viridis_c(option = "cividis",
                         name = "Precursors",
                         guide = guide_colorbar(barwidth = 15,
                                               barheight = 0.8,
                                               title.position = "top",
                                               title.hjust = 0.5)) +
    # RT bin boundaries
    geom_vline(xintercept = rt_boundaries,
               linetype = "dashed",
               color = "gray70",
               linewidth = 0.3,
               alpha = 0.6) +
    # Labels and theme
    labs(
      title = "Isolation Window Map: RT × m/z",
      subtitle = sprintf("%d windows | Mean width: %.1f Da | %d RT bins",
                        n_windows, mean_width, n_rt_bins),
      x = "Retention Time (min)",
      y = "m/z (Da)"
    ) +
    theme_aidia() +
    theme(
      plot.title = element_text(hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5),
      legend.position = "bottom",
      legend.box.spacing = unit(0.3, "cm")
    ) +
    coord_cartesian(xlim = c(min(windows$rt_start), max(windows$rt_end)),
                    ylim = c(min(windows$mz_start), max(windows$mz_end)))

  # Add precursor overlay if requested
  if (show_precursors && !is.null(validated_data)) {
    precursor_data <- validated_data$data

    # Check if we need to sample precursors
    n_precursors <- nrow(precursor_data)
    if (n_precursors > max_precursors) {
      message(sprintf("Sampling %d of %d precursors for plotting (set max_precursors to increase)",
                     max_precursors, n_precursors))
      precursor_data <- precursor_data %>%
        slice_sample(n = max_precursors)
    }

    # Add precursor scatter layer
    p <- p +
      geom_point(data = precursor_data,
                aes(x = RT.Start, y = Precursor.Mz),
                size = 0.3,
                alpha = 0.1,
                color = "black",
                inherit.aes = FALSE) +
      labs(caption = sprintf("Showing %d precursors",
                            min(n_precursors, max_precursors)))
  }

  return(p)
}

cat("  [plot_window_gantt.R] Isolation window Gantt chart loaded\n")
