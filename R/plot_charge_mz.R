# plot_charge_mz.R
# Plot 19: Charge State x m/z Distribution with Window Boundaries
#
# Purpose: Visualize how precursor charge states distribute across the m/z
#          range and how isolation windows cover different charge state
#          populations. Reveals whether optimization inadvertently
#          disadvantages specific charge states (e.g., z=4+ from PTM peptides).
#
# Dependencies: ggplot2, dplyr


#' Plot Charge State × m/z Distribution
#'
#' Creates a scatter/jitter plot of precursor charge state vs m/z value,
#' colored by charge state, with window boundaries from a representative
#' RT segment overlaid as vertical lines. Includes per-charge summary stats.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_charge_mz_distribution <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 19: Charge State x m/z Distribution...\n")

  precursor_data <- validated_data$data

  # Check for charge column
  if (!"Precursor.Charge" %in% colnames(precursor_data)) {
    return(create_insufficient_data_plot(
      title = "Charge State \u00d7 m/z Distribution",
      message = "Precursor.Charge column not available"
    ))
  }

  windows <- optimized_windows$windows

  # Select representative RT segment (median)
  median_seg <- select_median_rt_segment(windows)
  rep_windows <- windows[windows$rt_segment_id == median_seg, ]

  # Build plot data
  df <- data.frame(
    mz = precursor_data$Precursor.Mz,
    charge = factor(precursor_data$Precursor.Charge)
  )

  # Per-charge stats
  charge_stats <- df %>%
    group_by(charge) %>%
    summarize(
      n = n(),
      mz_median = median(mz, na.rm = TRUE),
      mz_range = sprintf("%.0f-%.0f", min(mz), max(mz)),
      .groups = "drop"
    )

  # Subtitle with charge distribution
  charge_pcts <- charge_stats %>%
    mutate(pct = n / sum(n) * 100) %>%
    mutate(label = sprintf("z=%s: %.0f%%", charge, pct))
  subtitle_text <- paste(charge_pcts$label, collapse = " | ")

  # Charge-aware color palette (sequential, distinct)
  n_charges <- length(unique(df$charge))
  charge_colors <- if (n_charges <= 5) {
    c("#3498DB", "#27AE60", "#F39C12", "#E74C3C", "#9B59B6")[seq_len(n_charges)]
  } else {
    viridis::viridis(n_charges, option = "D")
  }

  p <- ggplot(df, aes(x = mz, y = charge, color = charge)) +
    # Window boundary lines from representative RT segment
    geom_vline(
      xintercept = rep_windows$mz_start,
      color = "gray75",
      linewidth = 0.3,
      alpha = 0.7
    ) +
    # Jittered points (violin-style beeswarm with jitter)
    geom_jitter(
      height = 0.3,
      width = 0,
      size = 0.5,
      alpha = 0.25
    ) +
    # Box plot overlay for m/z range per charge
    geom_boxplot(
      fill = NA,
      color = "gray30",
      linewidth = 0.5,
      outlier.shape = NA,
      width = 0.5,
      alpha = 0.8
    ) +
    # Median markers
    stat_summary(
      fun = median,
      geom = "point",
      shape = 18,
      size = 3,
      color = "black"
    ) +
    # Count annotation on right
    geom_text(
      data = charge_stats,
      aes(x = Inf, y = charge,
          label = sprintf("n=%s", format(n, big.mark = ","))),
      hjust = 1.1,
      size = 3,
      fontface = "bold",
      color = "gray40"
    ) +
    scale_color_manual(values = charge_colors, guide = "none") +
    labs(
      title = "Charge State \u00d7 m/z Distribution",
      subtitle = subtitle_text,
      x = "Precursor m/z (Da)",
      y = "Charge State",
      caption = sprintf(
        "Window boundaries from RT segment %d (median) shown as vertical lines",
        median_seg
      )
    ) +
    theme_aidia() +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_blank()
    )

  return(p)
}
