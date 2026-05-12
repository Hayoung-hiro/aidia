#' Plot FWHM Distribution
#'
#' Shows chromatographic peak width distribution — the fundamental input
#' driving DPPP optimization. Displays histogram with density overlay,
#' median marker, and DPPP context when optimization_plan is provided.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object (optional, for DPPP annotation)
#'
#' @return ggplot object
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' p <- plot_fwhm_distribution(validated_data, optimization_plan)
#' ggsave("fwhm_distribution.png", p, width = 10, height = 6)
#' }
plot_fwhm_distribution <- function(validated_data, optimization_plan = NULL) {

  cat("  Generating FWHM Distribution Plot...\n")

  data <- validated_data$data
  fwhm_sec <- ensure_fwhm_seconds(data$FWHM)

  # Statistics
  n_precursors <- length(fwhm_sec)
  median_fwhm <- median(fwhm_sec, na.rm = TRUE)
  mean_fwhm <- mean(fwhm_sec, na.rm = TRUE)

  # Mode: peak of kernel density estimate
  dens <- density(fwhm_sec, na.rm = TRUE)
  mode_fwhm <- dens$x[which.max(dens$y)]

  # X-axis upper limit
  x_max <- ceiling(quantile(fwhm_sec, 0.99, na.rm = TRUE) * 1.3)

  p <- ggplot(data.frame(fwhm_sec = fwhm_sec), aes(x = fwhm_sec)) +
    geom_histogram(
      aes(y = after_stat(density)),
      bins = 50,
      fill = aidia_colors$before,
      alpha = 0.6,
      color = "white",
      linewidth = 0.3
    ) +
    geom_density(
      color = "black",
      linewidth = 0.9
    ) +
    # Median line
    geom_vline(
      xintercept = median_fwhm,
      linetype = "solid",
      color = aidia_colors$success,
      linewidth = 1.0
    ) +
    # Mode line
    geom_vline(
      xintercept = mode_fwhm,
      linetype = "dashed",
      color = aidia_colors$accent,
      linewidth = 0.8
    ) +
    # Median label
    annotate(
      "text",
      x = median_fwhm, y = Inf,
      label = sprintf("Median: %.1f s", median_fwhm),
      vjust = 1.5, hjust = -0.1,
      size = 3.5, fontface = "bold",
      color = aidia_colors$success
    ) +
    # Mode label
    annotate(
      "text",
      x = mode_fwhm, y = Inf,
      label = sprintf("Mode: %.1f s", mode_fwhm),
      vjust = 3.0, hjust = -0.1,
      size = 3.5, fontface = "bold",
      color = aidia_colors$accent
    ) +
    scale_x_continuous(
      limits = c(0, x_max),
      breaks = scales::breaks_pretty(n = 8),
      labels = function(x) sprintf("%.0fs", x)
    ) +
    labs(
      title = "Chromatographic Peak Width Distribution (FWHM)",
      subtitle = sprintf(
        "N = %s | Median: %.1f s | Mode: %.1f s | Mean: %.1f s",
        format(n_precursors, big.mark = ","),
        median_fwhm, mode_fwhm, mean_fwhm
      ),
      x = "FWHM (seconds)",
      y = "Density"
    ) +
    theme_aidia()

  # DPPP context when optimization_plan is provided
  if (!is.null(optimization_plan)) {
    target_ct <- optimization_plan$required_cycle_time_sec
    target_dppp <- optimization_plan$parameters$target_dppp

    # DPPP at median FWHM with required cycle time
    dppp_at_median <- calculate_dppp(median_fwhm, target_ct)

    p <- p +
      annotate(
        "label",
        x = x_max * 0.95, y = Inf,
        label = sprintf(
          "At required CT (%.2f s):\nMedian DPPP = %.1f\nTarget DPPP = %.1f",
          target_ct, dppp_at_median, target_dppp
        ),
        vjust = 1.3, hjust = 1,
        size = 3.2, fontface = "bold",
        color = "black",
        fill = "gray95", label.padding = unit(0.4, "lines")
      ) +
      labs(
        caption = sprintf(
          "DPPP = 1.7 x FWHM / cycle_time | Required CT: %.2f s for DPPP >= %.1f",
          target_ct, target_dppp
        )
      )
  }

  return(p)
}
