# plot_load_balance.R
# Plot 16: Precursor Load Balance Across Windows
#
# Purpose: Visualize how evenly precursors are distributed across isolation
#          windows within each RT segment. Unbalanced loads indicate wasted
#          scan time on sparse windows while dense windows are under-sampled.
#
# Dependencies: ggplot2, dplyr


#' Plot Precursor Load Balance Across Windows
#'
#' Creates a box plot showing the distribution of precursor counts per window,
#' faceted by RT segment. Annotates each segment with the coefficient of
#' variation (CV) to quantify load balance quality.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_precursor_load_balance <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 16: Precursor Load Balance...\n")

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  # Count precursors per window using 2D matching
  counts <- count_precursors_in_2d_windows(
    precursor_rt  = precursor_data$RT.Apex,
    precursor_mz  = precursor_data$Precursor.Mz,
    window_rt_start = windows$rt_start,
    window_rt_end   = windows$rt_end,
    window_mz_start = windows$mz_start,
    window_mz_end   = windows$mz_end
  )

  # Build data frame
  df <- data.frame(
    rt_segment_id = windows$rt_segment_id,
    precursor_count = counts
  )

  if (nrow(df) < 2) {
    return(create_insufficient_data_plot(
      title = "Precursor Load Balance",
      message = "Insufficient data\n(need at least 2 windows)"
    ))
  }

  # Calculate per-segment stats
  segment_stats <- df %>%
    group_by(rt_segment_id) %>%
    summarize(
      mean_count = mean(precursor_count),
      sd_count   = sd(precursor_count),
      cv         = ifelse(mean_count > 0, sd_count / mean_count, NA),
      n_windows  = n(),
      .groups = "drop"
    )

  # Overall CV for subtitle
  overall_cv <- sd(df$precursor_count) / mean(df$precursor_count)

  # RT bin labels
  df$rt_label <- sprintf("RT %02d", df$rt_segment_id)
  df$rt_label <- factor(df$rt_label, levels = unique(df$rt_label[order(df$rt_segment_id)]))

  # CV annotation labels
  segment_stats$rt_label <- sprintf("RT %02d", segment_stats$rt_segment_id)

  # Color windows by load (relative to segment mean)
  p <- ggplot(df, aes(x = rt_label, y = precursor_count)) +
    # Box plot per RT segment
    geom_boxplot(
      fill = aidia_colors$success,
      alpha = 0.5,
      outlier.shape = 21,
      outlier.size = 1.5,
      outlier.fill = aidia_colors$accent,
      outlier.alpha = 0.6
    ) +
    # Individual window points (jittered)
    geom_jitter(
      width = 0.15,
      size = 1.2,
      alpha = 0.4,
      color = aidia_colors$primary
    ) +
    # Mean marker
    stat_summary(
      fun = mean,
      geom = "point",
      shape = 23,
      size = 2.5,
      fill = "white",
      color = "black"
    ) +
    # CV annotation at the top
    geom_text(
      data = segment_stats,
      aes(x = rt_label, y = Inf, label = sprintf("CV=%.0f%%", cv * 100)),
      vjust = 1.5,
      size = 3,
      fontface = "bold",
      color = aidia_colors$secondary
    ) +
    scale_y_continuous(expand = expansion(mult = c(0.02, 0.15))) +
    labs(
      title = "Precursor Load Balance Across Windows",
      subtitle = sprintf(
        "Overall CV: %.1f%% | %s windows across %d RT segments | Diamond = mean",
        overall_cv * 100,
        format(nrow(windows), big.mark = ","),
        length(unique(df$rt_segment_id))
      ),
      x = "RT Segment",
      y = "Precursors per Window"
    ) +
    theme_aidia() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank()
    )

  return(p)
}
