# plot_histogram.R - RT Distribution Histogram Functions
#
# Purpose: Generate RT distribution histograms for temporal elution analysis
#
# Functions:
#   - plot_rt_histogram(): RT distribution with statistics and peak annotation
#
# Dependencies: ggplot2, dplyr, scales

library(ggplot2)
library(dplyr)
library(scales)

# =============================================================================
# Plot 2B: RT Distribution Histogram
# =============================================================================

#' Plot RT Distribution Histogram
#'
#' Creates a histogram showing the distribution of precursors across retention time.
#' Supplementary plot to the density heatmap to show temporal elution patterns.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of histogram bins (default: 50)
#'
#' @return ggplot object
#' @export
plot_rt_histogram <- function(validated_data, bins = 50) {

  cat("  Generating Plot 2B: RT Distribution Histogram...\n")

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Start)

  # Calculate statistics
  n_total <- nrow(precursor_data)
  rt_min <- min(precursor_data$RT.Start, na.rm = TRUE)
  rt_max <- max(precursor_data$RT.Start, na.rm = TRUE)
  rt_mean <- mean(precursor_data$RT.Start, na.rm = TRUE)
  rt_median <- median(precursor_data$RT.Start, na.rm = TRUE)

  # Find peak RT region
  hist_data <- hist(precursor_data$RT.Start, breaks = bins, plot = FALSE)
  peak_idx <- which.max(hist_data$counts)
  peak_rt_start <- hist_data$breaks[peak_idx]
  peak_rt_end <- hist_data$breaks[peak_idx + 1]
  peak_count <- hist_data$counts[peak_idx]

  # Calculate early vs late RT proportions
  early_rt <- sum(precursor_data$RT.Start < rt_mean)
  late_rt <- sum(precursor_data$RT.Start >= rt_mean)
  early_pct <- (early_rt / n_total) * 100
  late_pct <- (late_rt / n_total) * 100

  # Create histogram
  p <- ggplot(precursor_data, aes(x = RT.Start)) +
    geom_histogram(bins = bins, fill = "steelblue", alpha = 0.7,
                   color = "white", linewidth = 0.1) +
    geom_vline(xintercept = rt_median, linetype = "dashed",
               color = "coral", linewidth = 1) +
    geom_vline(xintercept = rt_mean, linetype = "dotted",
               color = "darkred", linewidth = 0.8) +
    annotate("rect", xmin = peak_rt_start, xmax = peak_rt_end,
             ymin = 0, ymax = peak_count, fill = "yellow", alpha = 0.3) +
    annotate("text", x = (peak_rt_start + peak_rt_end) / 2, y = peak_count * 1.05,
             label = sprintf("Peak: %.1f-%.1f min\n(%s precursors)",
                           peak_rt_start, peak_rt_end,
                           format(peak_count, big.mark = ",")),
             hjust = 0.5, vjust = 0, size = 3.5, fontface = "bold", color = "darkorange") +
    annotate("text", x = rt_median, y = Inf,
             label = sprintf("Median: %.1f min", rt_median),
             hjust = 1.1, vjust = 1.5, size = 3, color = "coral", fontface = "bold") +
    annotate("text", x = rt_mean, y = Inf,
             label = sprintf("Mean: %.1f min", rt_mean),
             hjust = -0.1, vjust = 1.5, size = 3, color = "darkred", fontface = "bold") +
    annotate("text", x = rt_max, y = Inf,
             label = sprintf("Early RT (<%.1f min): %s (%.1f%%)\nLate RT (>=%.1f min): %s (%.1f%%)",
                           rt_mean, format(early_rt, big.mark = ","), early_pct,
                           rt_mean, format(late_rt, big.mark = ","), late_pct),
             hjust = 1.05, vjust = 1.8, size = 3, family = "mono",
             lineheight = 0.9, color = "gray20") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15)), labels = scales::comma) +
    scale_x_continuous(expand = expansion(mult = c(0.01, 0.01))) +
    labs(
      title = "RT Distribution of Identified Precursors",
      subtitle = sprintf("Total: %s precursors | RT range: %.1f - %.1f min | Gradient: %.1f min",
                        format(n_total, big.mark = ","), rt_min, rt_max, rt_max - rt_min),
      x = "Retention Time (min)",
      y = "Number of Precursors",
      caption = "Dashed = median | Dotted = mean | Yellow = peak elution region"
    ) +
    theme_dia_optimizer() +
    theme(panel.grid.major.x = element_blank())

  return(p)
}

cat("  [plot_histogram.R] RT histogram functions loaded\n")
