# plot2b_rt_histogram.R
# Plot 2B: RT Distribution Histogram (Supplementary to Density Heatmap)
#
# Purpose: Show RT distribution of precursors to complement the density heatmap
#          and help understand temporal precursor elution patterns

library(dplyr)
library(ggplot2)

if (!exists("theme_aidia")) {
  if (file.exists("R/plots/theme_aidia.R")) {
    source("R/plots/theme_aidia.R")
  }
}

#' Plot RT Distribution Histogram
#'
#' Creates a histogram showing the distribution of precursors across retention time.
#' This helps identify peak elution regions and understand the temporal pattern
#' of precursor identification.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of histogram bins (default: 50)
#'
#' @return ggplot object
#' @export
#'
#' @examples
#' plot2b <- plot_rt_histogram(validated_data)
plot_rt_histogram <- function(validated_data, bins = 50) {

  cat("  Generating Plot 2B: RT Distribution Histogram...\n")

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Apex)

  # Calculate statistics
  n_total <- nrow(precursor_data)
  rt_min <- min(precursor_data$RT.Apex, na.rm = TRUE)
  rt_max <- max(precursor_data$RT.Apex, na.rm = TRUE)
  rt_mean <- mean(precursor_data$RT.Apex, na.rm = TRUE)
  rt_median <- median(precursor_data$RT.Apex, na.rm = TRUE)

  # Find peak RT region (highest density bin)
  hist_data <- hist(precursor_data$RT.Apex, breaks = bins, plot = FALSE)
  peak_idx <- which.max(hist_data$counts)
  peak_rt_start <- hist_data$breaks[peak_idx]
  peak_rt_end <- hist_data$breaks[peak_idx + 1]
  peak_count <- hist_data$counts[peak_idx]

  # Calculate early vs late RT proportions
  early_rt <- sum(precursor_data$RT.Apex < rt_mean)
  late_rt <- sum(precursor_data$RT.Apex >= rt_mean)
  early_pct <- (early_rt / n_total) * 100
  late_pct <- (late_rt / n_total) * 100

  # Create histogram
  p <- ggplot(precursor_data, aes(x = RT.Apex)) +
    # Histogram
    geom_histogram(
      bins = bins,
      fill = "steelblue",
      alpha = 0.7,
      color = "white",
      linewidth = 0.1
    ) +

    # Median line
    geom_vline(
      xintercept = rt_median,
      linetype = "dashed",
      color = "coral",
      linewidth = 1
    ) +

    # Mean line
    geom_vline(
      xintercept = rt_mean,
      linetype = "dotted",
      color = "darkred",
      linewidth = 0.8
    ) +

    # Highlight peak region
    annotate(
      "rect",
      xmin = peak_rt_start,
      xmax = peak_rt_end,
      ymin = 0,
      ymax = peak_count,
      fill = "yellow",
      alpha = 0.3
    ) +

    # Peak region label
    annotate(
      "text",
      x = (peak_rt_start + peak_rt_end) / 2,
      y = peak_count * 1.05,
      label = sprintf("Peak: %.1f-%.1f min\n(%s precursors)",
                      peak_rt_start, peak_rt_end,
                      format(peak_count, big.mark = ",")),
      hjust = 0.5,
      vjust = 0,
      size = 3.5,
      fontface = "bold",
      color = "darkorange"
    ) +

    # Median annotation
    annotate(
      "text",
      x = rt_median,
      y = Inf,
      label = sprintf("Median: %.1f min", rt_median),
      hjust = 1.1,
      vjust = 1.5,
      size = 3,
      color = "coral",
      fontface = "bold"
    ) +

    # Mean annotation
    annotate(
      "text",
      x = rt_mean,
      y = Inf,
      label = sprintf("Mean: %.1f min", rt_mean),
      hjust = -0.1,
      vjust = 1.5,
      size = 3,
      color = "darkred",
      fontface = "bold"
    ) +

    # Statistics box
    annotate(
      "text",
      x = rt_max,
      y = Inf,
      label = sprintf(
        "Early RT (<%.1f min): %s (%.1f%%)\nLate RT (≥%.1f min): %s (%.1f%%)",
        rt_mean,
        format(early_rt, big.mark = ","), early_pct,
        rt_mean,
        format(late_rt, big.mark = ","), late_pct
      ),
      hjust = 1.05,
      vjust = 1.8,
      size = 3,
      family = "mono",
      lineheight = 0.9,
      color = "gray20"
    ) +

    scale_y_continuous(
      expand = expansion(mult = c(0, 0.15)),
      labels = scales::comma
    ) +

    scale_x_continuous(
      expand = expansion(mult = c(0.01, 0.01))
    ) +

    labs(
      title = "RT Distribution of Identified Precursors",
      subtitle = sprintf(
        "Total: %s precursors | RT range: %.1f - %.1f min | Gradient length: %.1f min",
        format(n_total, big.mark = ","),
        rt_min, rt_max, rt_max - rt_min
      ),
      x = "Retention Time (min)",
      y = "Number of Precursors",
      caption = "Dashed line = median RT | Dotted line = mean RT | Yellow = peak elution region"
    ) +

    theme_aidia(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      plot.caption = element_text(size = 9, hjust = 0, color = "gray50"),
      axis.title = element_text(face = "bold"),
      axis.text = element_text(size = 10),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color = "gray90", linewidth = 0.3)
    )

  return(p)
}


#' Plot RT Distribution with Time Bins (Bar Chart)
#'
#' Creates a bar chart showing precursor counts in fixed time intervals
#' (e.g., 5 or 10 minute bins) with more detailed statistics.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param bin_width_min Width of time bins in minutes (default: 5)
#'
#' @return ggplot object
#' @export
#'
#' @examples
#' plot2b_binned <- plot_rt_histogram_binned(validated_data, bin_width_min = 10)
plot_rt_histogram_binned <- function(validated_data, bin_width_min = 5) {

  cat(sprintf("  Generating Plot 2B (binned): RT Distribution (%d-min bins)...\n", bin_width_min))

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Apex)

  # Calculate statistics
  n_total <- nrow(precursor_data)
  rt_min <- min(precursor_data$RT.Apex, na.rm = TRUE)
  rt_max <- max(precursor_data$RT.Apex, na.rm = TRUE)

  # Create bins
  bin_breaks <- seq(floor(rt_min), ceiling(rt_max) + bin_width_min, by = bin_width_min)

  binned_data <- precursor_data %>%
    mutate(
      rt_bin = cut(
        RT.Apex,
        breaks = bin_breaks,
        include.lowest = TRUE,
        right = FALSE
      ),
      rt_bin_start = floor(RT.Apex / bin_width_min) * bin_width_min
    ) %>%
    group_by(rt_bin_start) %>%
    summarise(
      n_precursors = n(),
      pct = n() / n_total * 100,
      .groups = "drop"
    ) %>%
    mutate(
      rt_label = sprintf("%02d-%02d", rt_bin_start, rt_bin_start + bin_width_min)
    )

  # Find peak bin
  peak_bin <- binned_data %>% filter(n_precursors == max(n_precursors))

  # Create bar chart
  p <- ggplot(binned_data, aes(x = rt_bin_start, y = n_precursors)) +
    # Bars
    geom_col(
      fill = "steelblue",
      alpha = 0.8,
      width = bin_width_min * 0.9
    ) +

    # Highlight peak bin
    geom_col(
      data = peak_bin,
      aes(x = rt_bin_start, y = n_precursors),
      fill = "coral",
      alpha = 0.8,
      width = bin_width_min * 0.9
    ) +

    # Add percentage labels on bars
    geom_text(
      aes(label = sprintf("%.1f%%", pct)),
      vjust = -0.5,
      size = 2.5,
      color = "gray20"
    ) +

    # Add count labels on peak bar
    geom_text(
      data = peak_bin,
      aes(label = sprintf("%s\nprecursors", format(n_precursors, big.mark = ","))),
      vjust = 1.5,
      size = 3,
      fontface = "bold",
      color = "white"
    ) +

    scale_y_continuous(
      expand = expansion(mult = c(0, 0.15)),
      labels = scales::comma
    ) +

    scale_x_continuous(
      breaks = binned_data$rt_bin_start,
      labels = binned_data$rt_label,
      expand = expansion(mult = c(0.01, 0.01))
    ) +

    labs(
      title = sprintf("RT Distribution by %d-Minute Bins", bin_width_min),
      subtitle = sprintf(
        "Total: %s precursors | Peak: %d-%d min (%s precursors, %.1f%%)",
        format(n_total, big.mark = ","),
        peak_bin$rt_bin_start,
        peak_bin$rt_bin_start + bin_width_min,
        format(peak_bin$n_precursors, big.mark = ","),
        peak_bin$pct
      ),
      x = "Retention Time (min)",
      y = "Number of Precursors",
      caption = "Coral bar = peak elution bin | Labels show percentage of total precursors"
    ) +

    theme_aidia(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      plot.caption = element_text(size = 9, hjust = 0, color = "gray50"),
      axis.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
      axis.text.y = element_text(size = 10),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color = "gray90", linewidth = 0.3)
    )

  return(p)
}
