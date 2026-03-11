# plot_fz_validation.R - Forbidden Zone Offset Validation Plot
#
# Purpose: Visualize fractional m/z distribution from real precursor data
#          and overlay the selected FZ offset band to confirm it falls in a
#          true forbidden zone (low-density gap between isotope clusters).
#
# Dependencies: ggplot2, stats, theme_aidia.R


#' Forbidden Zone Offset Validation Plot
#'
#' Creates a histogram of fractional m/z values (distance from nearest integer)
#' for all precursors in the dataset. Overlays the FZ offset band to visually
#' confirm that it targets a low-density region between isotope clusters.
#'
#' Peptide precursors cluster near integer m/z values due to amino acid mass
#' defect (~1.00045 Da). The forbidden zone offset should be positioned in the
#' gap between these clusters (typically around 0.2-0.3 or 0.7-0.8).
#'
#' @param validated_data ValidatedData object from Stage 1, or a data.frame
#'   with a \code{Precursor.Mz} column
#' @param fz_offset Numeric, forbidden zone offset to validate (default: 0.25)
#' @param n_bins Integer, number of histogram bins (default: 100)
#'
#' @return A ggplot object
#' @keywords internal
plot_fz_validation <- function(validated_data,
                               fz_offset = 0.25,
                               n_bins = 100) {

  # Extract precursor m/z values
  if (inherits(validated_data, "ValidatedData")) {
    mz_values <- validated_data$data$Precursor.Mz
  } else if (is.data.frame(validated_data)) {
    mz_values <- validated_data$Precursor.Mz
  } else {
    stop("validated_data must be a ValidatedData object or data.frame with Precursor.Mz")
  }

  if (is.null(mz_values) || length(mz_values) < 10) {
    return(create_insufficient_data_plot(
      title = "FZ Offset Validation",
      message = "Insufficient precursor data for FZ validation"
    ))
  }

  # Compute fractional m/z (0 to 1)
  frac_mz <- mz_values %% 1

  df <- data.frame(frac_mz = frac_mz)

  # FZ band: the offset marks where boundaries should be placed
  # Show both the offset and its complement (1 - offset) since the
  # distribution wraps around at 0/1
  fz_band_width <- 0.04  # visual width of the band
  fz_primary <- fz_offset
  fz_complement <- 1 - fz_offset

  # Density at FZ offset position (for annotation)
  kde <- stats::density(frac_mz, n = 512, from = 0, to = 1, adjust = 0.5)
  density_at_fz <- stats::approx(kde$x, kde$y, xout = fz_primary)$y
  density_max <- max(kde$y)
  density_ratio <- density_at_fz / density_max

  # Quality assessment
  if (density_ratio < 0.15) {
    quality <- "Excellent"
    quality_color <- "#27ae60"
  } else if (density_ratio < 0.30) {
    quality <- "Good"
    quality_color <- "#27ae60"
  } else if (density_ratio < 0.50) {
    quality <- "Marginal"
    quality_color <- "#f39c12"
  } else {
    quality <- "Poor"
    quality_color <- "#e74c3c"
  }

  # Build plot
  p <- ggplot(df, aes(x = frac_mz)) +
    # Histogram
    geom_histogram(bins = n_bins, fill = "#3498DB", color = NA, alpha = 0.6) +

    # FZ bands (primary + complement)
    geom_vline(xintercept = fz_primary, color = "#27ae60", linewidth = 1.2, linetype = "solid") +
    geom_vline(xintercept = fz_complement, color = "#27ae60", linewidth = 1.2, linetype = "dashed") +

    # Shade FZ zones
    annotate("rect",
             xmin = fz_primary - fz_band_width / 2,
             xmax = fz_primary + fz_band_width / 2,
             ymin = -Inf, ymax = Inf,
             fill = "#27ae60", alpha = 0.15) +
    annotate("rect",
             xmin = fz_complement - fz_band_width / 2,
             xmax = fz_complement + fz_band_width / 2,
             ymin = -Inf, ymax = Inf,
             fill = "#27ae60", alpha = 0.10) +

    # Labels
    annotate("text", x = fz_primary, y = Inf,
             label = sprintf("FZ offset = %.2f", fz_primary),
             vjust = 2, hjust = 0.5, size = 3.5, fontface = "bold",
             color = "#27ae60") +
    annotate("text", x = fz_complement, y = Inf,
             label = sprintf("1 - offset = %.2f", fz_complement),
             vjust = 3.5, hjust = 0.5, size = 3, color = "#27ae60") +

    # Quality badge
    annotate("label", x = 0.5, y = Inf,
             label = sprintf("%s (%.0f%% of peak density)", quality, density_ratio * 100),
             vjust = 1.5, size = 3.2, fontface = "bold",
             fill = quality_color, color = "white", label.size = 0) +

    labs(
      x = "Fractional m/z (precursor m/z mod 1)",
      y = "Count",
      title = "Forbidden Zone Offset Validation",
      subtitle = sprintf(
        "%s precursors | FZ offset %.4f | Density at FZ: %.0f%% of peak",
        format(length(mz_values), big.mark = ","),
        fz_offset,
        density_ratio * 100
      )
    ) +
    scale_x_continuous(breaks = seq(0, 1, 0.1), limits = c(0, 1)) +
    theme_aidia() +
    theme(plot.subtitle = element_text(size = 10, color = "grey50"))

  p
}
