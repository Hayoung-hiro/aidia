# plot_tiling_coverage.R - Plot 12: Tiling Coverage Map (Macro View)
#
# Purpose: Verify window tiling integrity — gap/overlap detection with
#          cycle stacking for staggered DIA and Loop N annotation.
#
# Dependencies: ggplot2, dplyr, theme_aidia.R, export_methods.R (calculate_loop_n)


#' Tiling Coverage Map (Macro View)
#'
#' Creates a 1D tiling map showing isolation windows as contiguous rectangles
#' along the m/z axis, with one row per cycle (staggered) or a single row
#' (fixed/density). Windows are colored by precursor count. Gaps and overlaps
#' between adjacent windows are highlighted in red.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1 (optional, unused
#'   currently but reserved for future precursor scatter overlay)
#' @param rt_segment_id Integer, RT segment to display. NULL (default) selects
#'   the median segment as a representative view.
#' @param show_loop_n Logical, annotate Loop N value for staggered windows
#'   (default: TRUE)
#' @param base_size Numeric, base font size for theme_aidia (default: 12)
#'
#' @return A ggplot object
#' @keywords internal
plot_tiling_coverage_map <- function(optimized_windows,
                                     validated_data = NULL,
                                     rt_segment_id = NULL,
                                     show_loop_n = TRUE,
                                     base_size = 12) {
  cat("  Generating Tiling Coverage Map...\n")

  windows <- optimized_windows$windows

  if (nrow(windows) == 0) {
    stop("No windows found in optimized_windows object")
  }

  is_staggered <- "cycle" %in% colnames(windows)

  # Select representative RT segment (median) if not specified
  if (is.null(rt_segment_id)) {
    rt_segment_id <- select_median_rt_segment(windows)
  }

  seg_windows <- windows %>%
    filter(rt_segment_id == !!rt_segment_id)

  if (nrow(seg_windows) == 0) {
    stop(sprintf("No windows found for rt_segment_id = %d", rt_segment_id))
  }

  # For non-staggered, synthesize cycle = 1L for unified code path
  if (!is_staggered) {
    seg_windows$cycle <- 1L
  }

  # Prepare tile data: Y = factor cycle label
  seg_windows <- seg_windows %>%
    mutate(
      cycle_label = factor(
        sprintf("Cycle %d", cycle),
        levels = c("Cycle 2", "Cycle 1")
      )
    )

  # --- Gap/Overlap Detection ---
  defects <- seg_windows %>%
    arrange(cycle, mz_start) %>%
    group_by(cycle) %>%
    mutate(
      prev_end = lag(mz_end),
      gap = mz_start - prev_end
    ) %>%
    filter(!is.na(gap) & abs(gap) > 1e-6) %>%
    mutate(
      defect_start = pmin(prev_end, mz_start),
      defect_end = pmax(prev_end, mz_start),
      defect_type = ifelse(gap > 0, "Gap", "Overlap"),
      cycle_label = factor(
        sprintf("Cycle %d", cycle),
        levels = c("Cycle 2", "Cycle 1")
      )
    ) %>%
    ungroup()

  # --- Build Plot ---
  n_windows_per_cycle <- seg_windows %>%
    filter(cycle == 1L) %>%
    nrow()

  # Calculate Loop N for staggered

  loop_n <- if (is_staggered) calculate_loop_n(windows) else NULL

  # Subtitle construction
  if (is_staggered && !is.null(loop_n)) {
    subtitle_text <- sprintf(
      "RT Segment %d | %d windows/cycle x 2 cycles | Loop N = %d",
      rt_segment_id, n_windows_per_cycle, loop_n
    )
  } else {
    subtitle_text <- sprintf(
      "RT Segment %d | %d windows",
      rt_segment_id, nrow(seg_windows)
    )
  }

  # Defect summary for caption
  n_defects <- nrow(defects)
  caption_text <- if (n_defects == 0) {
    "No gaps or overlaps detected"
  } else {
    sprintf("%d tiling defect%s detected (highlighted in red)",
            n_defects, ifelse(n_defects > 1, "s", ""))
  }

  p <- ggplot(seg_windows) +
    # Window tiles
    geom_rect(
      aes(xmin = mz_start, xmax = mz_end,
          ymin = as.numeric(cycle_label) - 0.4,
          ymax = as.numeric(cycle_label) + 0.4,
          fill = n_precursors),
      color = "white", linewidth = 0.3
    ) +
    # Precursor count fill
    scale_fill_viridis_c(
      option = "cividis",
      name = "Precursors",
      guide = guide_colorbar(barwidth = 15, barheight = 0.8,
                             title.position = "top", title.hjust = 0.5)
    ) +
    # Y-axis as cycle labels
    scale_y_continuous(
      breaks = seq_along(levels(seg_windows$cycle_label)),
      labels = levels(seg_windows$cycle_label),
      expand = expansion(mult = 0.3)
    ) +
    labs(
      title = "Tiling Coverage Map: Window Integrity Verification",
      subtitle = subtitle_text,
      caption = caption_text,
      x = "m/z (Da)",
      y = NULL
    ) +
    theme_aidia(base_size = base_size) +
    theme(
      legend.position = "bottom",
      panel.grid.major.y = element_blank(),
      panel.grid.major.x = element_line(linewidth = 0.2)
    )

  # Highlight defects in red
  if (n_defects > 0) {
    p <- p +
      geom_rect(
        data = defects,
        aes(xmin = defect_start, xmax = defect_end,
            ymin = as.numeric(cycle_label) - 0.4,
            ymax = as.numeric(cycle_label) + 0.4),
        fill = aidia_colors$accent, alpha = 0.5,
        color = aidia_colors$accent, linewidth = 0.5,
        inherit.aes = FALSE
      )
  }

  # Loop N annotation for staggered
  if (is_staggered && show_loop_n && !is.null(loop_n)) {
    mz_mid <- mean(c(min(seg_windows$mz_start), max(seg_windows$mz_end)))
    p <- p +
      annotate("text",
               x = mz_mid,
               y = max(as.numeric(seg_windows$cycle_label)) + 0.6,
               label = sprintf("Thermo Loop Control N = %d", loop_n),
               size = base_size / 3,
               fontface = "bold",
               color = aidia_colors$primary)
  }

  return(p)
}
