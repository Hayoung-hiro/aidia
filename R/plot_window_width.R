# plot_window_width.R
# Plot 7: Window Width Distribution by RT Segment
#
# Purpose: Show precursor density and window width distribution
#          - Normalized Density curve (blue) on left y-axis
#          - Variable Window Width (red) on right y-axis
#
# Reference: Improved design based on user feedback


#' Plot Window m/z Range Across RT Segments
#'
#' Shows how the isolation window coverage band shifts across the gradient.
#' Each RT segment's m/z range is shown as a ribbon (lower to upper boundary),
#' with mean window width annotated. Reveals how the optimized window layout
#' adapts to changing precursor distributions over time.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_window_width_distribution <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 7: Window m/z Range Across RT Segments...\n")

  windows_data <- optimized_windows$windows

  # Per-RT-segment: m/z range, mean width, window count
  seg_summary <- windows_data %>%
    dplyr::group_by(rt_segment_id) %>%
    dplyr::summarize(
      rt_mid = mean(c(first(rt_start), first(rt_end))),
      rt_start = first(rt_start),
      rt_end = first(rt_end),
      mz_lower = min(mz_start),
      mz_upper = max(mz_end),
      mean_width = mean(window_width),
      width_sd = sd(window_width),
      n_windows = dplyr::n(),
      .groups = "drop"
    )

  # Overall stats for subtitle
  overall_range <- sprintf("%.0f\u2013%.0f Da",
                           min(seg_summary$mz_lower), max(seg_summary$mz_upper))
  overall_mean_w <- mean(seg_summary$mean_width)

  # Calculate span per segment
  seg_summary$mz_span <- seg_summary$mz_upper - seg_summary$mz_lower

  p <- ggplot(seg_summary) +
    # Color-encoded rectangles: fill = span width
    geom_rect(
      aes(xmin = rt_start, xmax = rt_end,
          ymin = mz_lower, ymax = mz_upper,
          fill = mz_span),
      alpha = 0.7
    ) +
    # Upper and lower boundary lines
    geom_step(aes(x = rt_start, y = mz_upper), color = aidia_colors$before_dark,
              linewidth = 0.7, direction = "hv") +
    geom_step(aes(x = rt_start, y = mz_lower), color = aidia_colors$before_dark,
              linewidth = 0.7, direction = "hv") +
    # Color scale: sequential, low span = narrow (blue) → high span = wide (amber)
    scale_fill_gradient(
      low = aidia_colors$before, high = aidia_colors$warning,
      name = "Span (Da)"
    ) +
    scale_x_continuous(
      breaks = scales::breaks_pretty(n = 8),
      expand = expansion(mult = c(0.01, 0.01))
    ) +
    scale_y_continuous(
      expand = expansion(mult = c(0.05, 0.05))
    ) +
    labs(
      title = "Window m/z Coverage Across Gradient",
      subtitle = sprintf(
        "m/z range: %s | Mean width: %.1f Da | %d windows/bin",
        overall_range, overall_mean_w, seg_summary$n_windows[1]
      ),
      x = "Retention Time (min)",
      y = "m/z (Da)",
      caption = sprintf(
        "Fill color = m/z span per RT bin | %d RT bins",
        nrow(seg_summary)
      )
    ) +
    theme_aidia() +
    theme(
      legend.position = "right",
      legend.key.height = unit(0.8, "cm")
    )

  return(p)
}


#' Plot 7B: Cumulative Window Width by RT Segment
#'
#' Shows how window widths stack up across m/z range
#' Y-axis represents cumulative width (in Da), showing each window's contribution
#' This visualizes the variable window width distribution clearly
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param max_segments_to_show Maximum number of RT segments to display (default: 6, NULL = all)
#'
#' @return ggplot object (combined grid)
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' plot7b <- plot_cumulative_window_count(optimized_windows, validated_data)
#' }
plot_cumulative_window_count <- function(optimized_windows,
                                          validated_data,
                                          max_segments_to_show = 6) {

  cat("  Generating Plot 7B: Cumulative Window Width by RT Segment...\n")

  # Extract data
  windows_data <- optimized_windows$windows

  # Extract RT bin information from windows
  rt_bins <- windows_data %>%
    group_by(rt_segment_id) %>%
    summarize(
      rt_start = first(rt_start),
      rt_end = first(rt_end),
      .groups = "drop"
    ) %>%
    arrange(rt_segment_id)

  # Select RT segments to display
  n_segments <- nrow(rt_bins)
  if (!is.null(max_segments_to_show) && n_segments > max_segments_to_show) {
    selected_segments <- round(seq(1, n_segments, length.out = max_segments_to_show))
    cat(sprintf("    Showing %d of %d RT segments (sampled evenly)\n",
                max_segments_to_show, n_segments))
  } else {
    selected_segments <- 1:n_segments
    cat(sprintf("    Showing all %d RT segments\n", n_segments))
  }

  # Filter data for selected segments
  windows_filtered <- windows_data %>%
    filter(rt_segment_id %in% selected_segments)

  rt_bins_filtered <- rt_bins %>%
    filter(rt_segment_id %in% selected_segments)

  # Create plot list
  plot_list <- list()

  for (seg_id in selected_segments) {
    # Get segment info
    seg_info <- rt_bins_filtered %>%
      filter(rt_segment_id == seg_id)

    if (nrow(seg_info) == 0) next

    # Get windows for this segment
    seg_windows <- windows_filtered %>%
      filter(rt_segment_id == seg_id) %>%
      arrange(mz_start)

    if (nrow(seg_windows) == 0) next

    # Calculate statistics
    total_width <- sum(seg_windows$window_width)
    mean_width <- mean(seg_windows$window_width)

    # Assign window index (1, 2, 3, ...)
    seg_windows <- seg_windows %>%
      mutate(window_index = row_number())

    # Create rectangle data for each window
    # X: m/z position, Y: window index, Width: window_width
    rect_data <- seg_windows %>%
      select(
        window_index,
        mz_start, mz_end,
        window_width
      )

    # Get m/z range for this segment
    mz_min <- min(seg_windows$mz_start)
    mz_max <- max(seg_windows$mz_end)

    # Create plot with stacked bars showing window width
    p <- ggplot(rect_data) +
      # Draw rectangles for each window
      # X: m/z position (mz_start ~ mz_end)
      # Y: window index (stacked vertically)
      # Rectangle width (horizontal length) represents window_width visually
      geom_rect(
        aes(
          xmin = mz_start,
          xmax = mz_start + window_width,  # Width = window_width
          ymin = window_index - 0.4,
          ymax = window_index + 0.4
        ),
        fill = aidia_colors$before,
        color = "white",
        linewidth = 0.3,
        alpha = 0.8
      ) +
      scale_x_continuous(
        limits = c(mz_min, mz_max),
        expand = expansion(mult = c(0.02, 0.02))
      ) +
      scale_y_continuous(
        breaks = seq(1, nrow(seg_windows), by = max(1, floor(nrow(seg_windows)/10))),
        expand = expansion(mult = c(0.02, 0.02))
      ) +
      labs(
        title = sprintf("RT%02d, with %d windows\n(total width: %.1f Da, mean width: %.1f Da)",
                       seg_id, nrow(seg_windows), total_width, mean_width),
        x = "m/z (Da)",
        y = "Window Index"
      ) +
      theme_aidia() +
      theme(
        plot.title = element_text(size = 9, face = "bold", lineheight = 1.1),
        axis.title = element_text(size = 9),
        axis.text = element_text(size = 8),
        panel.grid.minor = element_blank(),
        panel.border = element_rect(color = "gray70", fill = NA, linewidth = 0.5)
      )

    plot_list[[length(plot_list) + 1]] <- p
  }

  # Arrange all segments in a grid
  n_plots <- length(plot_list)
  if (n_plots == 0) {
    stop("No valid RT segments found for plotting")
  }

  # Calculate grid dimensions
  n_cols <- min(3, n_plots)
  n_rows <- ceiling(n_plots / n_cols)

  cat(sprintf("    Created %d panels (%d rows x %d cols)\n", n_plots, n_rows, n_cols))

  # Create final grid
  final_plot <- do.call(gridExtra::arrangeGrob, c(plot_list, ncol = n_cols))

  return(final_plot)
}
