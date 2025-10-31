# plot4_mz_distribution_excluded.R
# Plot 4: m/z Density Distribution with Excluded Regions
#
# Purpose: Visualize m/z distribution for each RT bin and show which regions
#          were excluded by the optimization strategy (quantile/smoothing/outlier/coverage)

library(dplyr)
library(ggplot2)
library(tidyr)
library(gridExtra)

#' Plot m/z Distribution with Excluded Regions (Multiple RT Bins)
#'
#' For each RT segment, shows:
#' - m/z density distribution (histogram or density curve)
#' - Optimized m/z range (kept region)
#' - Excluded regions (shaded areas on both tails)
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param max_bins_to_show Maximum number of RT bins to display (default: NULL = all bins, or specify number to sample)
#'
#' @return ggplot object (grid of subplots)
#' @export
#'
#' @examples
#' # Show all bins (default)
#' plot4 <- plot_mz_distribution_with_exclusions(optimized_windows, validated_data)
#' # Show only 6 bins (sampled)
#' plot4 <- plot_mz_distribution_with_exclusions(optimized_windows, validated_data, max_bins_to_show = 6)
plot_mz_distribution_with_exclusions <- function(optimized_windows,
                                                  validated_data,
                                                  max_bins_to_show = NULL) {

  cat("  Generating Plot 4: m/z Distribution with Excluded Regions...\n")

  # Extract data
  mz_ranges <- optimized_windows$mz_optimization$mz_ranges
  precursor_data <- validated_data$data
  strategy_name <- optimized_windows$mz_optimization$strategy

  # Select RT bins to display (sample if max_bins_to_show specified)
  n_bins <- nrow(mz_ranges)
  if (!is.null(max_bins_to_show) && n_bins > max_bins_to_show) {
    # Sample evenly across RT range
    selected_bins <- round(seq(1, n_bins, length.out = max_bins_to_show))
    cat(sprintf("    Showing %d of %d RT bins (sampled evenly)\n", max_bins_to_show, n_bins))
  } else {
    selected_bins <- 1:n_bins
    cat(sprintf("    Showing all %d RT bins\n", n_bins))
  }

  # Create individual plots for each RT bin
  plot_list <- list()

  for (idx in seq_along(selected_bins)) {
    bin_id <- selected_bins[idx]
    bin_info <- mz_ranges[bin_id, ]

    # Filter precursors in this RT bin
    bin_precursors <- precursor_data %>%
      filter(RT.Start >= bin_info$rt_start & RT.Start < bin_info$rt_end)

    if (nrow(bin_precursors) == 0) next

    mz_values <- bin_precursors$Precursor.Mz

    # Calculate density for plotting
    dens <- density(mz_values, n = 200)
    density_data <- data.frame(
      mz = dens$x,
      density = dens$y
    )

    # Define regions
    optimized_min <- bin_info$mz_min
    optimized_max <- bin_info$mz_max
    original_min <- min(mz_values, na.rm = TRUE)
    original_max <- max(mz_values, na.rm = TRUE)

    # Count excluded precursors
    excluded_low <- sum(mz_values < optimized_min)
    excluded_high <- sum(mz_values > optimized_max)
    total_excluded <- excluded_low + excluded_high
    total_precursors <- length(mz_values)
    excluded_pct <- (total_excluded / total_precursors) * 100

    # Create plot
    p <- ggplot(density_data, aes(x = mz, y = density)) +
      # Excluded region: Low tail (left)
      annotate("rect",
               xmin = original_min, xmax = optimized_min,
               ymin = 0, ymax = Inf,
               fill = "red", alpha = 0.2) +

      # Excluded region: High tail (right)
      annotate("rect",
               xmin = optimized_max, xmax = original_max,
               ymin = 0, ymax = Inf,
               fill = "red", alpha = 0.2) +

      # Kept region (optimized range)
      annotate("rect",
               xmin = optimized_min, xmax = optimized_max,
               ymin = 0, ymax = Inf,
               fill = "green", alpha = 0.05) +

      # Density curve
      geom_line(color = "navy", linewidth = 1) +

      # Boundary lines
      geom_vline(xintercept = optimized_min, linetype = "dashed",
                 color = "darkgreen", linewidth = 0.8) +
      geom_vline(xintercept = optimized_max, linetype = "dashed",
                 color = "darkgreen", linewidth = 0.8) +

      # Labels
      annotate("text", x = optimized_min, y = Inf,
               label = sprintf("%.1f", optimized_min),
               hjust = 1.1, vjust = 1.5, size = 3, color = "darkgreen") +
      annotate("text", x = optimized_max, y = Inf,
               label = sprintf("%.1f", optimized_max),
               hjust = -0.1, vjust = 1.5, size = 3, color = "darkgreen") +

      labs(
        title = sprintf("RT Bin %02d: %.1f-%.1f min", bin_id,
                       bin_info$rt_start, bin_info$rt_end),
        subtitle = sprintf(
          "Excluded: %d (%.1f%%) | Coverage: %.1f%% | Range: %.1f Da",
          total_excluded, excluded_pct,
          bin_info$coverage_ratio * 100,
          bin_info$mz_width
        ),
        x = "m/z (Da)",
        y = "Density"
      ) +

      theme_minimal(base_size = 9) +
      theme(
        plot.title = element_text(face = "bold", size = 10),
        plot.subtitle = element_text(size = 8, color = "gray30"),
        axis.title = element_text(size = 9),
        axis.text = element_text(size = 8),
        panel.grid.minor = element_blank()
      )

    plot_list[[idx]] <- p
  }

  # Arrange in grid
  n_plots <- length(plot_list)
  n_cols <- ifelse(n_plots <= 3, n_plots, 3)
  n_rows <- ceiling(n_plots / n_cols)

  # Get strategy label
  strategy_label <- switch(
    strategy_name,
    "quantile" = "Quantile (P5-P95)",
    "smoothing" = "Savitzky-Golay Smoothing",
    "outlier" = "Outlier Removal",
    "coverage" = "Coverage-based",
    strategy_name
  )

  # Create title grob
  title_text <- sprintf(
    "m/z Distribution with Excluded Regions (Strategy: %s)",
    strategy_label
  )

  subtitle_text <- sprintf(
    "Green area: Kept region | Red areas: Excluded tails | %d/%d RT bins shown",
    n_plots, n_bins
  )

  combined_plot <- gridExtra::arrangeGrob(
    grobs = plot_list,
    ncol = n_cols,
    nrow = n_rows,
    top = grid::textGrob(
      title_text,
      gp = grid::gpar(fontsize = 14, fontface = "bold")
    ),
    bottom = grid::textGrob(
      subtitle_text,
      gp = grid::gpar(fontsize = 10, col = "gray40"),
      just = "center"
    )
  )

  return(combined_plot)
}
