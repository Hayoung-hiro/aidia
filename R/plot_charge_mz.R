# plot_charge_mz.R
# Plot 19: Charge State Distribution (Bar Chart)
#
# Purpose: Show precursor charge state composition as a bar chart.
#          Dominant 2+/3+ states justify forbidden zone (FZ) boundary
#          placement, since multi-charged precursors produce wide
#          isotope envelopes that span integer m/z boundaries.
#
# Dependencies: ggplot2, dplyr


#' Plot Charge State Distribution (Bar Chart)
#'
#' Creates a bar chart of precursor charge state percentages with count
#' labels. Highlights the fraction of multi-charged (z >= 2) precursors
#' that benefit from FZ offset boundary placement.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3 (unused,
#'   kept for API compatibility with visualization.R dispatcher)
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_charge_mz_distribution <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 19: Charge State Distribution...\n")

  precursor_data <- validated_data$data

  # Check for charge column
  if (!"Precursor.Charge" %in% colnames(precursor_data)) {
    return(create_insufficient_data_plot(
      title = "Charge State Distribution",
      message = "Precursor.Charge column not available"
    ))
  }

  # Per-charge stats
  n_total <- nrow(precursor_data)
  charge_stats <- precursor_data %>%
    dplyr::group_by(charge = factor(precursor_data$Precursor.Charge)) %>%
    dplyr::summarize(
      n = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::mutate(pct = n / sum(n) * 100)

  # Color palette
  n_charges <- nrow(charge_stats)
  bar_colors <- if (n_charges <= 5) {
    aidia_charge_colors[seq_len(n_charges)]
  } else {
    viridis::viridis(n_charges, option = "D")
  }

  subtitle_text <- sprintf("%s precursors", format(n_total, big.mark = ","))

  p <- ggplot(charge_stats, aes(x = charge, y = pct, fill = charge)) +
    geom_col(show.legend = FALSE, width = 0.6) +
    # Percentage labels above bars
    geom_text(
      aes(label = sprintf("%.0f%%", pct)),
      vjust = -1.5, size = 5, fontface = "bold"
    ) +
    # Count labels
    geom_text(
      aes(label = sprintf("n=%s", format(n, big.mark = ","))),
      vjust = -0.3, size = 3.2, color = "gray30"
    ) +
    scale_fill_manual(values = bar_colors) +
    scale_y_continuous(
      limits = c(0, max(charge_stats$pct) * 1.25),
      expand = expansion(mult = c(0, 0))
    ) +
    labs(
      title = "Charge State Distribution",
      subtitle = subtitle_text,
      x = "Charge State",
      y = "Percentage (%)"
    ) +
    theme_aidia() +
    theme(
      panel.grid.major.x = element_blank()
    )

  return(p)
}
