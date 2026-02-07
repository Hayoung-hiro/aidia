# plot_rt_quality.R - RT Bin Quality Heatmap Visualization
#
# Purpose: Generate RT bin quality metrics heatmap for identifying problematic regions
#
# Functions:
#   - plot_rt_bin_quality_heatmap(): Multi-metric quality heatmap across RT bins
#
# Dependencies: ggplot2, dplyr, tidyr, utils_common.R (calculate_dppp)

library(ggplot2)
library(dplyr)
library(tidyr)

# =============================================================================
# RT Bin Quality Heatmap
# =============================================================================

#' Plot RT Bin Quality Metrics as Heatmap
#'
#' Visualizes multiple quality metrics across RT bins using a tile/heatmap plot.
#' Each metric is shown as a separate row with normalized 0-1 values for comparable
#' color mapping. Helps identify problematic RT regions that may need attention.
#'
#' Metrics displayed:
#' 1. Precursor Count: Number of precursors per RT bin
#' 2. Coverage Ratio: Mean coverage across windows per bin
#' 3. Mean Window Width: Average m/z window width per bin
#' 4. Window Count: Number of isolation windows per bin
#' 5. DPPP Satisfaction: Fraction of precursors meeting target DPPP per bin
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#'
#' @return ggplot object
#' @export
plot_rt_bin_quality_heatmap <- function(optimized_windows, validated_data, optimization_plan) {

  cat("  Generating RT Bin Quality Heatmap...\n")

  # Extract key parameters
  target_dppp <- optimization_plan$parameters$target_dppp
  cycle_time_sec <- optimization_plan$required_cycle_time_sec

  # Extract data structures
  windows_data <- optimized_windows$windows
  mz_ranges_data <- optimized_windows$mz_optimization$mz_ranges
  precursor_data <- validated_data$data

  # Check for required columns
  if (!all(c("rt_segment_id", "rt_start", "rt_end") %in% names(windows_data))) {
    stop("windows_data missing required RT columns", call. = FALSE)
  }

  # =========================================================================
  # Metric 1: Precursor Count per RT bin
  # =========================================================================

  metric1_precursor_count <- mz_ranges_data %>%
    group_by(rt_segment_id, rt_start, rt_end) %>%
    summarise(
      value = sum(n_precursors, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(metric = "Precursor Count")

  # =========================================================================
  # Metric 2: Coverage Ratio per RT bin
  # =========================================================================

  metric2_coverage <- mz_ranges_data %>%
    group_by(rt_segment_id, rt_start, rt_end) %>%
    summarise(
      value = mean(coverage_ratio, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(metric = "Coverage Ratio")

  # =========================================================================
  # Metric 3: Mean Window Width per RT bin
  # =========================================================================

  metric3_window_width <- windows_data %>%
    group_by(rt_segment_id, rt_start, rt_end) %>%
    summarise(
      value = mean(mz_width, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(metric = "Mean Window Width (Da)")

  # =========================================================================
  # Metric 4: Window Count per RT bin
  # =========================================================================

  metric4_window_count <- windows_data %>%
    group_by(rt_segment_id, rt_start, rt_end) %>%
    summarise(
      value = n(),
      .groups = "drop"
    ) %>%
    mutate(metric = "Window Count")

  # =========================================================================
  # Metric 5: DPPP Satisfaction per RT bin
  # =========================================================================

  # For each RT bin, calculate fraction of precursors meeting target DPPP
  # DPPP formula: (1.7 * FWHM_seconds) / cycle_time_seconds

  # Get RT bin boundaries from windows_data
  rt_bins <- windows_data %>%
    select(rt_segment_id, rt_start, rt_end) %>%
    distinct() %>%
    arrange(rt_segment_id)

  # Calculate DPPP satisfaction for each RT bin
  metric5_dppp_satisfaction <- rt_bins %>%
    rowwise() %>%
    mutate(
      value = {
        # Filter precursors in this RT range
        bin_precursors <- precursor_data %>%
          filter(RT.Start >= rt_start & RT.Start < rt_end)

        if (nrow(bin_precursors) == 0) {
          NA_real_
        } else {
          # Calculate DPPP for precursors in this bin
          fwhm_sec <- bin_precursors$FWHM * 60  # Convert minutes to seconds
          dppp_values <- calculate_dppp(fwhm_sec, cycle_time_sec)

          # Fraction meeting target
          mean(dppp_values >= target_dppp, na.rm = TRUE)
        }
      }
    ) %>%
    ungroup() %>%
    mutate(metric = "DPPP Satisfaction")

  # =========================================================================
  # Combine all metrics
  # =========================================================================

  combined_metrics <- bind_rows(
    metric1_precursor_count,
    metric2_coverage,
    metric3_window_width,
    metric4_window_count,
    metric5_dppp_satisfaction
  )

  # =========================================================================
  # Normalize metrics to 0-1 scale for comparable color mapping
  # =========================================================================

  normalized_metrics <- combined_metrics %>%
    group_by(metric) %>%
    mutate(
      value_norm = if_else(
        is.na(value) | max(value, na.rm = TRUE) == min(value, na.rm = TRUE),
        0.5,  # Default for constant or NA values
        (value - min(value, na.rm = TRUE)) / (max(value, na.rm = TRUE) - min(value, na.rm = TRUE))
      ),
      value_display = round(value, 2)  # For text labels
    ) %>%
    ungroup()

  # =========================================================================
  # Create RT bin labels (formatted as "10.0-15.0 min")
  # =========================================================================

  normalized_metrics <- normalized_metrics %>%
    mutate(
      rt_label = sprintf("%.1f-%.1f", rt_start, rt_end),
      # Factor for proper ordering
      metric = factor(metric, levels = c(
        "Precursor Count",
        "Coverage Ratio",
        "Mean Window Width (Da)",
        "Window Count",
        "DPPP Satisfaction"
      ))
    )

  # =========================================================================
  # Create heatmap plot
  # =========================================================================

  p <- ggplot(normalized_metrics, aes(x = rt_label, y = metric, fill = value_norm)) +
    geom_tile(color = "white", linewidth = 0.5) +
    # Add text labels for actual values
    geom_text(
      aes(label = value_display),
      color = "black",
      size = 2.8,
      fontface = "bold"
    ) +
    # Color scale (viridis cividis for colorblind safety)
    scale_fill_viridis_c(
      option = "cividis",
      name = "Normalized\nValue (0-1)",
      limits = c(0, 1),
      breaks = seq(0, 1, by = 0.25),
      na.value = "gray90"
    ) +
    # Labels and titles
    labs(
      title = "RT Bin Quality Metrics Heatmap",
      subtitle = sprintf(
        "Quality assessment across %d RT bins | Target DPPP: %.1f | Cycle time: %.2f sec",
        length(unique(normalized_metrics$rt_segment_id)),
        target_dppp,
        cycle_time_sec
      ),
      x = "RT Range (minutes)",
      y = "Metric",
      caption = "Normalized values (0-1) enable cross-metric comparison; actual values shown in tiles"
    ) +
    # Theme
    theme_aidia() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
      axis.text.y = element_text(size = 10),
      panel.grid = element_blank(),
      legend.position = "right",
      legend.key.height = unit(1.2, "cm"),
      plot.caption = element_text(hjust = 0)
    )

  return(p)
}

cat("  [plot_rt_quality.R] RT bin quality heatmap loaded\n")
