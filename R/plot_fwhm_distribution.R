#' Plot FWHM Distribution
#'
#' Shows chromatographic peak width distribution - the fundamental input
#' driving the entire DPPP optimization. Displays histogram with density overlay,
#' median, P15 (critical percentile for DPPP), and optional cycle time context.
#'
#' Purpose: Understand the underlying FWHM distribution that determines
#' the target cycle time. P15 (15th percentile) is the critical threshold
#' used in DPPP calculations (1.7 * P15_FWHM / cycle_time).
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object (optional, for cycle time annotation)
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

  # Extract FWHM in seconds (convert from minutes)
  data <- validated_data$data
  fwhm_sec <- ensure_fwhm_seconds(data$FWHM)

  # Calculate statistics
  n_precursors <- length(fwhm_sec)
  median_fwhm <- median(fwhm_sec, na.rm = TRUE)
  p15_fwhm <- quantile(fwhm_sec, 0.15, na.rm = TRUE)
  mean_fwhm <- mean(fwhm_sec, na.rm = TRUE)

  # Create histogram with density overlay
  p <- ggplot(data.frame(fwhm_sec = fwhm_sec), aes(x = fwhm_sec)) +
    # Histogram
    geom_histogram(
      aes(y = after_stat(density)),
      bins = 50,
      fill = aidia_colors$primary,
      alpha = 0.6,
      color = "white",
      linewidth = 0.3
    ) +
    # Density curve
    geom_density(
      color = aidia_colors$accent,
      linewidth = 1.2,
      alpha = 0
    ) +
    # Median line (solid)
    geom_vline(
      xintercept = median_fwhm,
      linetype = "solid",
      color = aidia_colors$success,
      linewidth = 1.0
    ) +
    # P15 line (dashed, critical percentile)
    geom_vline(
      xintercept = p15_fwhm,
      linetype = "dashed",
      color = aidia_colors$accent,
      linewidth = 1.0
    ) +
    # Annotations
    annotate(
      "text",
      x = median_fwhm,
      y = Inf,
      label = sprintf("Median: %.1fs", median_fwhm),
      vjust = 1.5,
      hjust = -0.1,
      size = 3.5,
      fontface = "bold",
      color = aidia_colors$success
    ) +
    annotate(
      "text",
      x = p15_fwhm,
      y = Inf,
      label = sprintf("Critical P15: %.1fs", p15_fwhm),
      vjust = 3.0,
      hjust = -0.1,
      size = 3.5,
      fontface = "bold",
      color = aidia_colors$accent
    ) +
    scale_x_continuous(
      limits = c(0, ceiling(quantile(fwhm_sec, 0.99, na.rm = TRUE) * 1.3)),
      breaks = scales::breaks_pretty(n = 8),
      labels = function(x) sprintf("%.0fs", x)
    ) +
    labs(
      title = "Chromatographic Peak Width Distribution (FWHM)",
      subtitle = sprintf(
        "N = %s precursors | Median: %.1fs | P15: %.1fs (critical for DPPP)",
        format(n_precursors, big.mark = ","),
        median_fwhm,
        p15_fwhm
      ),
      x = "FWHM (Full-Width at Half Maximum)",
      y = "Density"
    ) +
    theme_aidia()

  # Add cycle time context if optimization_plan provided
  if (!is.null(optimization_plan)) {
    target_cycle_time <- optimization_plan$required_cycle_time_sec
    target_dppp <- optimization_plan$parameters$target_dppp

    # Calculate implied FWHM threshold from cycle time
    # DPPP = 1.7 * FWHM / cycle_time => FWHM = DPPP * cycle_time / 1.7
    implied_fwhm_threshold <- target_dppp * target_cycle_time / 1.7

    # Add annotation about cycle time relationship
    p <- p +
      annotate(
        "text",
        x = Inf,
        y = Inf,
        label = sprintf(
          "Target Cycle Time: %.2fs\n(for DPPP >= %.1f)",
          target_cycle_time,
          target_dppp
        ),
        vjust = 1.5,
        hjust = 1.1,
        size = 3,
        fontface = "italic",
        color = aidia_colors$secondary
      )
  }

  return(p)
}

