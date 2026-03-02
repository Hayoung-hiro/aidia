# plot_alignment_density.R - Plot 13: Precursor Density Alignment (Alignment View)
#
# Purpose: Overlay window boundaries on precursor m/z density to verify that
#          boundaries fall in low-density regions between isotope clusters.
#
# Dependencies: ggplot2, dplyr, stats, theme_aidia.R


#' Precursor Density Alignment Plot (Alignment View)
#'
#' Shows precursor m/z density as a smooth KDE curve with window boundaries
#' overlaid as vertical lines. For staggered DIA, Cycle 1 boundaries are solid
#' and Cycle 2 boundaries are dashed. Width annotations mark the narrowest and
#' widest windows.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param rt_segment_id Integer, RT segment to display. NULL (default) selects
#'   the median segment.
#' @param bw_adjust Numeric, bandwidth adjustment factor for density estimation
#'   (default: 1.0). Smaller values give more detail.
#' @param base_size Numeric, base font size for theme_aidia (default: 12)
#'
#' @return A ggplot object
#' @keywords internal
plot_alignment_density <- function(optimized_windows,
                                    validated_data,
                                    rt_segment_id = NULL,
                                    bw_adjust = 1.0,
                                    base_size = 12) {

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  if (nrow(windows) == 0) stop("No windows found in optimized_windows object")
  if (nrow(precursor_data) == 0) stop("No precursor data found")

  is_staggered <- "cycle" %in% colnames(windows)

  # Select representative RT segment
  all_segments <- sort(unique(windows$rt_segment_id))
  if (is.null(rt_segment_id)) {
    rt_segment_id <- all_segments[ceiling(length(all_segments) / 2)]
  }

  seg_windows <- windows %>% filter(rt_segment_id == !!rt_segment_id)

  if (nrow(seg_windows) == 0) {
    stop(sprintf("No windows found for rt_segment_id = %d", rt_segment_id))
  }

  # Get RT range for this segment to filter precursors
  rt_min <- min(seg_windows$rt_start)
  rt_max <- max(seg_windows$rt_end)

  seg_precursors <- precursor_data %>%
    filter(RT.Apex >= rt_min & RT.Apex <= rt_max)

  if (nrow(seg_precursors) < 10) {
    # Fall back to all precursors in m/z range
    mz_min <- min(seg_windows$mz_start)
    mz_max <- max(seg_windows$mz_end)
    seg_precursors <- precursor_data %>%
      filter(Precursor.Mz >= mz_min & Precursor.Mz <= mz_max)
  }

  # Compute KDE
  mz_values <- seg_precursors$Precursor.Mz
  mz_range <- range(mz_values)
  d <- stats::density(mz_values, adjust = bw_adjust,
                      from = mz_range[1] - 5, to = mz_range[2] + 5,
                      n = 1024)
  density_df <- data.frame(mz = d$x, density = d$y)

  # Extract unique boundaries (internal boundaries only)
  if (!is_staggered) {
    seg_windows$cycle <- 1L
  }

  boundary_df <- seg_windows %>%
    arrange(cycle, mz_start) %>%
    group_by(cycle) %>%
    summarise(
      boundaries = list(unique(c(mz_start, mz_end))),
      .groups = "drop"
    ) %>%
    tidyr::unnest(boundaries) %>%
    rename(mz = boundaries) %>%
    mutate(
      linetype = ifelse(cycle == 1L, "solid", "dashed"),
      cycle_label = sprintf("Cycle %d", cycle)
    )

  # Width statistics for annotation
  seg_windows <- seg_windows %>%
    mutate(width = mz_end - mz_start)
  min_width_row <- seg_windows %>% slice_min(width, n = 1, with_ties = FALSE)
  max_width_row <- seg_windows %>% slice_max(width, n = 1, with_ties = FALSE)

  # Subtitle
  n_boundaries <- nrow(boundary_df)
  subtitle_text <- sprintf(
    "RT Segment %d | %d precursors | Width range: %.1f - %.1f Da",
    rt_segment_id, nrow(seg_precursors),
    min(seg_windows$width), max(seg_windows$width)
  )

  # --- Build Plot ---
  p <- ggplot() +
    # Density area
    geom_area(
      data = density_df,
      aes(x = mz, y = density),
      fill = viridis::viridis(1, option = "cividis", begin = 0.3),
      alpha = 0.3
    ) +
    geom_line(
      data = density_df,
      aes(x = mz, y = density),
      color = viridis::viridis(1, option = "cividis", begin = 0.5),
      linewidth = 0.6
    )

  # Window boundaries
  if (is_staggered) {
    # Cycle 1: solid, Cycle 2: dashed
    c1_bounds <- boundary_df %>% filter(cycle == 1L)
    c2_bounds <- boundary_df %>% filter(cycle == 2L)

    p <- p +
      geom_vline(
        data = c1_bounds,
        aes(xintercept = mz),
        color = aidia_colors$accent, alpha = 0.7,
        linetype = "solid", linewidth = 0.4
      ) +
      geom_vline(
        data = c2_bounds,
        aes(xintercept = mz),
        color = aidia_colors$warning, alpha = 0.6,
        linetype = "dashed", linewidth = 0.4
      )
  } else {
    p <- p +
      geom_vline(
        data = boundary_df,
        aes(xintercept = mz),
        color = aidia_colors$accent, alpha = 0.7,
        linetype = "solid", linewidth = 0.4
      )
  }

  # Width annotation brackets (min and max)
  y_max <- max(density_df$density)

  # Min width bracket
  p <- p +
    annotate("segment",
             x = min_width_row$mz_start, xend = min_width_row$mz_end,
             y = y_max * 1.05, yend = y_max * 1.05,
             color = aidia_colors$primary, linewidth = 0.5,
             arrow = arrow(ends = "both", length = unit(0.08, "inches"))) +
    annotate("text",
             x = min_width_row$mz_center, y = y_max * 1.12,
             label = sprintf("Min: %.1f Da", min_width_row$width),
             size = base_size / 4, color = aidia_colors$primary)

  # Max width bracket
  p <- p +
    annotate("segment",
             x = max_width_row$mz_start, xend = max_width_row$mz_end,
             y = y_max * 1.18, yend = y_max * 1.18,
             color = aidia_colors$secondary, linewidth = 0.5,
             arrow = arrow(ends = "both", length = unit(0.08, "inches"))) +
    annotate("text",
             x = max_width_row$mz_center, y = y_max * 1.25,
             label = sprintf("Max: %.1f Da", max_width_row$width),
             size = base_size / 4, color = aidia_colors$secondary)

  # Labels and theme
  legend_labels <- if (is_staggered) {
    "\nSolid = Cycle 1 boundaries | Dashed = Cycle 2 boundaries"
  } else {
    NULL
  }

  p <- p +
    labs(
      title = "Precursor-Window Alignment: Density vs Boundaries",
      subtitle = subtitle_text,
      caption = legend_labels,
      x = "m/z (Da)",
      y = "Precursor Density"
    ) +
    theme_aidia(base_size = base_size) +
    theme(
      plot.title = element_text(hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5)
    ) +
    coord_cartesian(
      xlim = c(min(seg_windows$mz_start) - 5, max(seg_windows$mz_end) + 5),
      ylim = c(0, y_max * 1.35)
    )

  return(p)
}
