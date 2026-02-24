# plot_window_width.R
# Plot 7: Window Width Distribution by RT Segment
#
# Purpose: Show precursor density and window width distribution
#          - Normalized Density curve (blue) on left y-axis
#          - Variable Window Width (red) on right y-axis
#
# Reference: Improved design based on user feedback


if (!exists("theme_aidia") && !isNamespaceLoaded("aidia")) {
  if (file.exists("R/theme_aidia.R")) {
    source("R/theme_aidia.R")
  }
}

#' Plot Window Width Distribution by RT Segment
#'
#' Creates a multi-panel visualization showing:
#' - Blue line: Normalized density of precursor m/z distribution
#' - Red line: Variable window width across m/z range
#' - Dual y-axis for different scales
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param max_segments_to_show Maximum number of RT segments to display (default: 6, NULL = all)
#'
#' @return ggplot object (combined grid)
#' @export
#'
#' @examples
#' \dontrun{
#' plot7 <- plot_window_width_distribution(optimized_windows, validated_data)
#' # Show all segments
#' plot7 <- plot_window_width_distribution(optimized_windows, validated_data, max_segments_to_show = NULL)
#' }
plot_window_width_distribution <- function(optimized_windows,
                                            validated_data,
                                            max_segments_to_show = 6) {

  cat("  Generating Plot 7: Window Width Distribution by RT Segment...\n")

  # Extract data
  windows_data <- optimized_windows$windows
  precursor_data <- validated_data$data

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

    # Get precursors for this segment
    seg_precursors <- precursor_data %>%
      filter(RT.Apex >= seg_info$rt_start,
             RT.Apex < seg_info$rt_end)

    # Get windows for this segment
    seg_windows <- windows_filtered %>%
      filter(rt_segment_id == seg_id) %>%
      arrange(mz_start)

    if (nrow(seg_windows) == 0 || nrow(seg_precursors) < 2) next  # Need at least 2 points for density

    # Calculate normalized density using density()
    mz_range <- range(seg_precursors$Precursor.Mz)
    density_result <- density(seg_precursors$Precursor.Mz, n = 512, from = mz_range[1], to = mz_range[2])

    # Normalize density to 0-1 range
    density_df <- tibble(
      mz = density_result$x,
      density = density_result$y / max(density_result$y)
    )

    # Prepare window width data for step function
    # For each window, create step data: (mz_start -> mz_end) with constant window_width
    window_steps <- seg_windows %>%
      rowwise() %>%
      mutate(
        mz_seq = list(c(mz_start, mz_end)),
        width_seq = list(c(window_width, window_width))
      ) %>%
      ungroup() %>%
      select(mz_seq, width_seq) %>%
      tidyr::unnest(cols = c(mz_seq, width_seq)) %>%
      rename(mz = mz_seq, window_width = width_seq)

    # Calculate scaling factor for dual y-axis
    max_width <- max(seg_windows$window_width, na.rm = TRUE)
    scaling_factor <- 1.0 / max_width  # Scale width to 0-1 range

    # Create plot with dual y-axis
    p <- ggplot() +
      # Normalized density (blue line, left y-axis)
      geom_line(
        data = density_df,
        aes(x = mz, y = density, color = "Input Histogram"),
        linewidth = 1.0,
        alpha = 0.8
      ) +
      # Window width (red step function, right y-axis - scaled to 0-1)
      geom_step(
        data = window_steps,
        aes(x = mz, y = window_width * scaling_factor, color = "Variable Windows"),
        linewidth = 1.0,
        direction = "hv"
      ) +
      # Manual color scale for legend
      scale_color_manual(
        name = NULL,
        values = c("Input Histogram" = "steelblue", "Variable Windows" = "coral"),
        breaks = c("Input Histogram", "Variable Windows")
      ) +
      # Dual y-axis setup
      scale_y_continuous(
        name = "Normalized Density",
        limits = c(0, 1.1),
        breaks = seq(0, 1, by = 0.2),
        sec.axis = sec_axis(
          trans = ~ . / scaling_factor,
          name = "Window Width (Da)",
          breaks = seq(0, max_width, length.out = 5),
          labels = function(x) sprintf("%.1f", x)
        )
      ) +
      labs(
        title = sprintf("RT%02d\n(%d precursors, %d windows)",
                       seg_id, nrow(seg_precursors), nrow(seg_windows)),
        x = "m/z (Da)"
      ) +
      theme_aidia() +
      theme(
        plot.title = element_text(size = 10, face = "bold", hjust = 0.5),
        axis.title.x = element_text(size = 9),
        axis.title.y.left = element_text(size = 9, color = "steelblue"),
        axis.title.y.right = element_text(size = 9, color = "coral"),
        axis.text = element_text(size = 8),
        axis.text.y.left = element_text(color = "steelblue"),
        axis.text.y.right = element_text(color = "coral"),
        panel.grid.minor = element_blank(),
        legend.position = "top",
        legend.text = element_text(size = 8),
        legend.key.width = unit(1.5, "cm"),
        legend.spacing.x = unit(0.3, "cm")
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

  # Create final grid with shared legend
  final_plot <- do.call(grid.arrange, c(plot_list, ncol = n_cols))

  return(final_plot)
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
#' @export
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
        fill = "steelblue",
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
        plot.title = element_text(size = 9, face = "bold", hjust = 0.5, lineheight = 1.1),
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
  final_plot <- do.call(grid.arrange, c(plot_list, ncol = n_cols))

  return(final_plot)
}
