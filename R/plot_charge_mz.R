# plot_charge_mz.R
# Plot 19: Charge State x m/z Distribution (Violin)
#
# Purpose: Visualize how precursor charge states distribute across the m/z
#          range. Reveals the mass-to-charge landscape and charge state
#          composition of the sample — key for understanding precursor
#          complexity without imposing RT-dependent window boundaries.
#
# Dependencies: ggplot2, dplyr


#' Plot Charge State x m/z Distribution (Violin)
#'
#' Creates violin plots of precursor m/z distribution per charge state,
#' showing the density shape, median, and count per charge. No window
#' boundaries are overlaid because windows are RT-dependent and a single
#' snapshot would be misleading.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3 (unused,
#'   kept for API compatibility with visualization.R dispatcher)
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

  # Build plot data
  df <- data.frame(
    mz = precursor_data$Precursor.Mz,
    charge = factor(precursor_data$Precursor.Charge)
  )

  # Per-charge stats
  charge_stats <- df %>%
    dplyr::group_by(charge) %>%
    dplyr::summarize(
      n = dplyr::n(),
      mz_median = median(mz, na.rm = TRUE),
      .groups = "drop"
    )

  # Subtitle with charge distribution
  charge_pcts <- charge_stats %>%
    dplyr::mutate(pct = n / sum(n) * 100) %>%
    dplyr::mutate(label = sprintf("z=%s: %.0f%%", charge, pct))
  subtitle_text <- paste(charge_pcts$label, collapse = " | ")

  # Charge-aware color palette
  n_charges <- length(unique(df$charge))
  charge_colors <- if (n_charges <= 5) {
    aidia_charge_colors[seq_len(n_charges)]
  } else {
    viridis::viridis(n_charges, option = "D")
  }

  p <- ggplot(df, aes(x = charge, y = mz, fill = charge)) +
    # Violin plot showing density shape
    geom_violin(
      alpha = 0.5,
      color = "gray40",
      linewidth = 0.4,
      scale = "width",
      trim = FALSE
    ) +
    # Actual data points (jittered) for visual n per charge
    geom_jitter(
      width = 0.12,
      size = 0.4,
      alpha = 0.15,
      color = "gray30"
    ) +
    # Box plot inside for quartiles
    geom_boxplot(
      width = 0.12,
      fill = "white",
      color = "gray30",
      linewidth = 0.4,
      outlier.shape = NA,
      alpha = 0.7
    ) +
    # Median markers
    stat_summary(
      fun = median,
      geom = "point",
      shape = 18,
      size = 2.5,
      color = "black"
    ) +
    # Count annotation at top
    geom_text(
      data = charge_stats,
      aes(x = charge, y = Inf,
          label = sprintf("n=%s", format(n, big.mark = ","))),
      vjust = 1.5,
      size = 3,
      fontface = "bold",
      color = "gray40",
      inherit.aes = FALSE
    ) +
    scale_fill_manual(values = charge_colors, guide = "none") +
    labs(
      title = "Charge State \u00d7 m/z Distribution",
      subtitle = subtitle_text,
      x = "Charge State",
      y = "Precursor m/z (Da)"
    ) +
    theme_aidia() +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank()
    )

  return(p)
}
