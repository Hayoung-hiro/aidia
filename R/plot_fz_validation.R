# plot_fz_validation.R - Forbidden Zone Offset Validation Plot
#
# Purpose: Visualize precursor m/z distribution within the amino acid mass
#          defect cycle (OPTIMAL_INCREMENT = 1.00045475 Da) and overlay the
#          selected FZ offset to confirm it targets a low-density gap.
#
# Dependencies: ggplot2, stats, theme_aidia.R, window_generation.R (OPTIMAL_INCREMENT)


#' Forbidden Zone Offset Validation Plot
#'
#' Creates a histogram of precursor m/z modulo OPTIMAL_INCREMENT (1.00045475 Da,
#' the amino acid mass defect period). The FZ offset line should fall in a
#' low-density gap between precursor clusters.
#'
#' Unlike simple \code{mz \%\% 1}, this uses the true mass defect periodicity
#' so that the FZ offset position is correctly aligned regardless of m/z range.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param fz_offset Numeric, forbidden zone offset to validate (default: 0.25)
#' @param n_bins Integer, number of histogram bins (default: 100)
#'
#' @return A ggplot object
#' @keywords internal
plot_fz_validation <- function(validated_data,
                               fz_offset = 0.25,
                               n_bins = 100) {
  cat("  Generating FZ Validation plot...\n")

  # Extract precursor m/z values via shared accessor
  mz_values <- get_precursor_data(validated_data)$Precursor.Mz

  if (is.null(mz_values) || length(mz_values) < 10) {
    return(create_insufficient_data_plot(
      title = "FZ Offset Validation",
      message = "Insufficient precursor data for FZ validation"
    ))
  }

  # Use amino acid mass defect period, not integer period
  increment <- OPTIMAL_INCREMENT  # 1.00045475 Da

  # Compute phase within the mass defect cycle: mz mod OPTIMAL_INCREMENT
  frac_mz <- mz_values %% increment

  df <- data.frame(frac_mz = frac_mz)

  # FZ band visual width
  fz_band_width <- 0.04

  # Density at FZ offset position (for quality assessment)
  kde <- stats::density(frac_mz, n = 512, from = 0, to = increment, adjust = 0.5)
  density_at_fz <- stats::approx(kde$x, kde$y, xout = fz_offset)$y
  density_max <- max(kde$y)
  density_ratio <- density_at_fz / density_max

  # Quality assessment
  if (density_ratio < 0.15) {
    quality <- "Excellent"
    quality_color <- aidia_colors$success
  } else if (density_ratio < 0.30) {
    quality <- "Good"
    quality_color <- aidia_colors$success
  } else if (density_ratio < 0.50) {
    quality <- "Marginal"
    quality_color <- aidia_colors$warning
  } else {
    quality <- "Poor"
    quality_color <- aidia_colors$accent
  }

  # Build plot
  p <- ggplot(df, aes(x = frac_mz)) +
    # Histogram
    geom_histogram(bins = n_bins, fill = aidia_colors$before, color = "white",
                   alpha = 0.6, linewidth = 0.1) +

    # FZ offset line
    geom_vline(xintercept = fz_offset, color = aidia_colors$success, linewidth = 1.2, linetype = "solid") +

    # Shade FZ zone
    annotate("rect",
             xmin = fz_offset - fz_band_width / 2,
             xmax = fz_offset + fz_band_width / 2,
             ymin = -Inf, ymax = Inf,
             fill = aidia_colors$success, alpha = 0.15) +

    # Label
    annotate("text", x = fz_offset, y = Inf,
             label = sprintf("FZ offset = %.4f", fz_offset),
             vjust = 2, hjust = 0.5, size = 3.5, fontface = "bold",
             color = aidia_colors$success) +

    # Quality badge
    annotate("label", x = increment / 2, y = Inf,
             label = sprintf("%s (%.0f%% of peak density)", quality, density_ratio * 100),
             vjust = 1.5, size = 3.2, fontface = "bold",
             fill = quality_color, color = "white") +

    labs(
      x = sprintf("m/z mod %.8f (mass defect cycle)", increment),
      y = "Count",
      title = "Forbidden Zone Offset Validation",
      subtitle = sprintf(
        "%s precursors | FZ offset %.4f | Density at FZ: %.0f%% of peak",
        format(length(mz_values), big.mark = ","),
        fz_offset,
        density_ratio * 100
      )
    ) +
    scale_x_continuous(
      breaks = seq(0, 1, 0.1),
      limits = c(0, increment)
    ) +
    theme_aidia() +
    theme(plot.subtitle = element_text(size = 10, color = "grey50"))

  p
}
