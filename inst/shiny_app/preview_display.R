# Display selection does not enter the optimization request or confirmation.
.shiny_preview_slice <- function(run, id = "all") {
  if (is.null(id) || !id %in% names(run$profiles)) id <- "all"
  ranges <- run$windows$mz_optimization$mz_ranges
  windows <- run$windows$windows
  if (id != "all") {
    ranges <- ranges[ranges$rt_segment_id == as.integer(id), , drop = FALSE]
    windows <- windows[windows$rt_segment_id == as.integer(id), , drop = FALSE]
  }
  list(run = run, profile = run$profiles[[id]], range = ranges,
       windows = windows, all = identical(id, "all"))
}

# Reuse the report's whole-data RT/mz density layer, independently of strategy.
.shiny_plot_overview <- function(windows, validated_data) {
  plot <- aidia:::plot_density_with_mz_range(windows, validated_data)
  # The report connects RT midpoints. In the live editor, outline the exact
  # selected interval for each group, including its first and last RT edges.
  plot$layers <- Filter(function(layer) !inherits(layer$geom, "GeomLine"), plot$layers)
  plot +
    ggplot2::geom_rect(data = windows$mz_optimization$mz_ranges,
      ggplot2::aes(xmin = rt_start, xmax = rt_end, ymin = mz_min, ymax = mz_max),
      inherit.aes = FALSE, fill = NA, color = aidia:::aidia_colors$success,
      linewidth = 0.7) +
    # Keep the visible axes tied to the uploaded distribution while editing.
    ggplot2::coord_cartesian(xlim = range(validated_data$data$RT.Apex, finite = TRUE),
      ylim = range(validated_data$data$Precursor.Mz, finite = TRUE)) +
    ggplot2::labs(title = NULL, subtitle = NULL, x = "RT (min)", y = "m/z") +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(),
      legend.position = "right", legend.title = ggplot2::element_text(size = 9),
      legend.text = ggplot2::element_text(size = 8),
      legend.key.height = grid::unit(0.6, "cm"),
      legend.key.width = grid::unit(0.3, "cm"),
      plot.margin = ggplot2::margin(4, 4, 2, 4))
}
