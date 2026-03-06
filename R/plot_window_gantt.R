#' Faceted Window Density Panels
#'
#' Creates faceted panels showing m/z density per RT bin with optimized
#' window regions shaded. Each panel shows how window placement tracks
#' precursor density within that RT segment.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param max_facets Integer, maximum RT bins to show (default: 12).
#'   Evenly sampled if more bins exist.
#'
#' @return ggplot object
#' @keywords internal
plot_faceted_window_density <- function(optimized_windows,
                                        validated_data,
                                        max_facets = 12) {

  cat("  Generating Faceted Window Density Panels...\n")

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  if (nrow(windows) == 0) {
    stop("No windows found in optimized_windows object")
  }

  # Get RT bin info
  rt_bins <- windows %>%
    dplyr::group_by(rt_segment_id) %>%
    dplyr::summarize(
      rt_start = min(rt_start),
      rt_end = max(rt_end),
      .groups = "drop"
    ) %>%
    dplyr::arrange(rt_segment_id)

  n_bins <- nrow(rt_bins)

  # Sample bins if too many
  if (n_bins > max_facets) {
    sample_idx <- seq(1, n_bins, length.out = max_facets) %>% round() %>% unique()
    rt_bins <- rt_bins[sample_idx, ]
  }

  selected_segments <- rt_bins$rt_segment_id

  # Build per-bin precursor data with facet labels
  precursor_list <- list()
  for (i in seq_len(nrow(rt_bins))) {
    seg <- rt_bins$rt_segment_id[i]
    rt_s <- rt_bins$rt_start[i]
    rt_e <- rt_bins$rt_end[i]

    seg_precursors <- precursor_data %>%
      dplyr::filter(RT.Apex >= rt_s & RT.Apex < rt_e) %>%
      dplyr::mutate(
        facet_label = sprintf("RT %.0f\u2013%.0f min (n=%d)",
                             rt_s, rt_e, dplyr::n()),
        rt_segment_id = seg
      )
    precursor_list[[i]] <- seg_precursors
  }
  precursor_df <- safe_bind_rows(precursor_list)

  # Filter windows to selected segments and add facet labels
  windows_df <- windows %>%
    dplyr::filter(rt_segment_id %in% selected_segments) %>%
    dplyr::left_join(
      precursor_df %>%
        dplyr::distinct(rt_segment_id, facet_label),
      by = "rt_segment_id"
    )

  # Ensure facet ordering by RT
  facet_order <- precursor_df %>%
    dplyr::distinct(rt_segment_id, facet_label) %>%
    dplyr::arrange(rt_segment_id)
  precursor_df$facet_label <- factor(precursor_df$facet_label,
                                      levels = facet_order$facet_label)
  windows_df$facet_label <- factor(windows_df$facet_label,
                                    levels = facet_order$facet_label)

  # Calculate global m/z range for consistent axes
  mz_range <- range(precursor_data$Precursor.Mz, na.rm = TRUE)

  # Summary stats
  n_windows <- nrow(optimized_windows$windows)
  if ("window_width" %in% names(windows)) {
    widths <- windows$window_width
  } else {
    widths <- windows$mz_end - windows$mz_start
  }

  # Window band colors: alternate for visual separation
  window_colors <- rep(c(aidia_colors$accent, aidia_colors$success),
                       length.out = max(windows_df$window_id, na.rm = TRUE))

  p <- ggplot() +
    # Layer 1: Window bands (vertical shading)
    geom_rect(
      data = windows_df,
      aes(xmin = mz_start, xmax = mz_end,
          ymin = -Inf, ymax = Inf),
      fill = aidia_colors$accent,
      alpha = 0.12
    ) +
    # Layer 2: Window boundary lines
    geom_vline(
      data = windows_df,
      aes(xintercept = mz_start),
      color = aidia_colors$accent,
      linewidth = 0.3,
      alpha = 0.5
    ) +
    geom_vline(
      data = windows_df,
      aes(xintercept = mz_end),
      color = aidia_colors$accent,
      linewidth = 0.3,
      alpha = 0.5
    ) +
    # Layer 3: Precursor density curve
    geom_density(
      data = precursor_df,
      aes(x = Precursor.Mz),
      fill = aidia_colors$primary,
      color = aidia_colors$primary,
      alpha = 0.4,
      linewidth = 0.6
    ) +
    # Facet by RT bin
    facet_wrap(~ facet_label, scales = "free_y",
               ncol = min(4, length(selected_segments))) +
    scale_x_continuous(limits = mz_range) +
    labs(
      title = "Window Placement vs Precursor Density by RT Bin",
      subtitle = sprintf(
        "%d windows across %d RT bins | Width: %.0f\u2013%.0f Da (mean %.1f)",
        n_windows, n_bins,
        min(widths), max(widths), mean(widths)
      ),
      x = "m/z (Da)",
      y = "Precursor Density",
      caption = "Shaded bands = isolation windows | Density curve = precursor m/z distribution per RT bin"
    ) +
    theme_aidia() +
    theme(
      strip.text = element_text(size = 9, face = "bold"),
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      panel.spacing = unit(0.3, "lines")
    )

  return(p)
}
