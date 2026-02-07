#' Optimization Impact Summary - Before/After Comparison
#'
#' Purpose: Generate a dashboard-style multi-panel visualization showing
#' the impact of AIDIA optimization by comparing before (current) vs after
#' (optimized) state across key metrics.
#'
#' Functions:
#'   - plot_optimization_impact(): 4-panel dashboard with cycle time,
#'     satisfaction, window count, and metrics table
#'
#' Dependencies: ggplot2, dplyr, gridExtra, grid

library(ggplot2)
library(dplyr)
library(gridExtra)
library(grid)

# =============================================================================
# Helper Functions
# =============================================================================

#' Calculate DPPP satisfaction after optimization
#'
#' @param validated_data ValidatedData object
#' @param cycle_time_sec Numeric, cycle time in seconds
#' @param target_dppp Numeric, target DPPP threshold
#'
#' @return Numeric, satisfaction ratio (0-1)
calculate_satisfaction <- function(validated_data, cycle_time_sec, target_dppp) {
  fwhm_sec <- validated_data$data$FWHM * 60  # Convert to seconds
  dppp <- calculate_dppp(fwhm_sec, cycle_time_sec)
  satisfaction <- mean(dppp >= target_dppp, na.rm = TRUE)
  return(satisfaction)
}

#' Create a before/after bar chart
#'
#' @param before_value Numeric, before value
#' @param after_value Numeric, after value
#' @param title Character, plot title
#' @param y_label Character, y-axis label
#' @param value_format Character, sprintf format for text labels (e.g., "%.2f sec")
#' @param y_limits Numeric vector length 2, y-axis limits (default: auto)
#'
#' @return ggplot object
create_before_after_bar <- function(before_value, after_value, title, y_label,
                                    value_format = "%.2f", y_limits = NULL) {
  df <- data.frame(
    state = factor(c("Before", "After"), levels = c("Before", "After")),
    value = c(before_value, after_value),
    color = c("#BDC3C7", "#27AE60")  # Gray, Green
  )

  # Auto-calculate y-limits if not provided
  if (is.null(y_limits)) {
    max_val <- max(df$value, na.rm = TRUE)
    y_limits <- c(0, max_val * 1.2)
  }

  # Format value labels
  df$label <- sprintf(value_format, df$value)

  p <- ggplot(df, aes(x = state, y = value, fill = color)) +
    geom_col(show.legend = FALSE) +
    geom_text(aes(label = label), vjust = -0.5, size = 5, fontface = "bold") +
    scale_fill_identity() +
    scale_y_continuous(limits = y_limits, expand = expansion(mult = c(0, 0.05))) +
    labs(title = title, x = NULL, y = y_label) +
    theme_aidia(base_size = 10) +
    theme(
      axis.text.x = element_text(size = 11, face = "bold"),
      panel.grid.major.x = element_blank()
    )

  return(p)
}

#' Create a metrics summary text panel
#'
#' @param optimized_windows OptimizedWindows object
#' @param validated_data ValidatedData object
#'
#' @return ggplot object (text-based)
create_metrics_table <- function(optimized_windows, validated_data) {
  # Extract metrics
  strategy <- optimized_windows$mz_optimization$strategy
  window_mode <- optimized_windows$window_generation$window_mode
  n_precursors <- validated_data$summary$n_precursors
  n_rt_bins <- length(unique(optimized_windows$windows$rt_segment_id))

  # Calculate mean window width
  mean_width <- mean(optimized_windows$windows$mz_width, na.rm = TRUE)

  # Extract coverage from statistics (handle both list and tibble formats)
  if (is.list(optimized_windows$statistics)) {
    coverage <- optimized_windows$statistics$mean_coverage_ratio
  } else if (is.data.frame(optimized_windows$statistics)) {
    coverage <- mean(optimized_windows$statistics$coverage_ratio, na.rm = TRUE)
  } else {
    coverage <- NA
  }

  # If coverage not available, calculate from mz_ranges
  if (is.na(coverage) && !is.null(optimized_windows$mz_optimization$mz_ranges)) {
    coverage <- mean(optimized_windows$mz_optimization$mz_ranges$coverage_ratio, na.rm = TRUE)
  }

  # Format text
  text_lines <- c(
    sprintf("Strategy:    %s", toupper(strategy)),
    sprintf("Window Mode: %s", toupper(window_mode)),
    sprintf("Precursors:  %s", format(n_precursors, big.mark = ",")),
    sprintf("RT Bins:     %d", n_rt_bins),
    sprintf("Mean Width:  %.1f Da", mean_width),
    if (!is.na(coverage)) sprintf("Coverage:    %.1f%%", coverage * 100) else NULL
  )

  # Remove NULL entries
  text_lines <- text_lines[!sapply(text_lines, is.null)]

  # Create data frame for plotting
  df <- data.frame(
    x = 0.05,
    y = seq(0.9, 0.1, length.out = length(text_lines)),
    label = text_lines
  )

  p <- ggplot(df, aes(x = x, y = y, label = label)) +
    geom_text(hjust = 0, vjust = 0.5, size = 4, family = "mono", fontface = "bold") +
    scale_x_continuous(limits = c(0, 1)) +
    scale_y_continuous(limits = c(0, 1)) +
    labs(title = "Key Metrics") +
    theme_void() +
    theme(
      plot.title = element_text(
        hjust = 0.5,
        face = "bold",
        size = 12,
        color = "#2C3E50",
        margin = margin(b = 10)
      ),
      plot.background = element_rect(fill = "white", color = "gray80", linewidth = 0.5),
      plot.margin = margin(10, 10, 10, 10)
    )

  return(p)
}

# =============================================================================
# Main Plot Function
# =============================================================================

#' Plot Optimization Impact Summary (Before/After Dashboard)
#'
#' Creates a 2x2 panel dashboard showing the impact of optimization:
#' - Panel 1: Cycle time before/after
#' - Panel 2: DPPP satisfaction before/after
#' - Panel 3: Window count before/after
#' - Panel 4: Key metrics summary table
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return grob object (from gridExtra::arrangeGrob)
#' @export
#'
#' @examples
#' p <- plot_optimization_impact(optimization_plan, optimized_windows, validated_data)
#' ggsave("impact_summary.png", p, width = 10, height = 8)
plot_optimization_impact <- function(optimization_plan, optimized_windows, validated_data) {

  cat("  Generating Optimization Impact Summary (Before/After)...\n")

  # Extract before (current) values
  before_cycle_time <- optimization_plan$diagnosis$current_cycle_time_sec
  before_n_windows <- optimization_plan$diagnosis$current_n_windows
  before_satisfaction <- optimization_plan$diagnosis$current_satisfaction_ratio

  # Extract after (optimized) values
  after_cycle_time <- optimization_plan$required_cycle_time_sec
  after_n_windows <- nrow(optimized_windows$windows)

  # Calculate after satisfaction using optimized cycle time
  target_dppp <- optimization_plan$parameters$target_dppp
  after_satisfaction <- calculate_satisfaction(validated_data, after_cycle_time, target_dppp)
  target_satisfaction <- optimization_plan$parameters$target_satisfaction

  # Panel 1: Cycle Time Before/After
  p1 <- create_before_after_bar(
    before_value = before_cycle_time,
    after_value = after_cycle_time,
    title = "Cycle Time",
    y_label = "Seconds",
    value_format = "%.2f sec"
  )

  # Panel 2: DPPP Satisfaction Before/After (with target line)
  p2_base <- create_before_after_bar(
    before_value = before_satisfaction * 100,
    after_value = after_satisfaction * 100,
    title = "DPPP Satisfaction",
    y_label = "Satisfaction (%)",
    value_format = "%.1f%%",
    y_limits = c(0, 100)
  )

  # Add target line
  p2 <- p2_base +
    geom_hline(
      yintercept = target_satisfaction * 100,
      linetype = "dashed",
      color = "#E74C3C",
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = 1.5,
      y = target_satisfaction * 100,
      label = sprintf("Target: %.0f%%", target_satisfaction * 100),
      vjust = -0.5,
      size = 3.5,
      fontface = "bold",
      color = "#E74C3C"
    )

  # Panel 3: Window Count Before/After
  p3 <- create_before_after_bar(
    before_value = before_n_windows,
    after_value = after_n_windows,
    title = "Isolation Windows",
    y_label = "Count",
    value_format = "%.0f"
  )

  # Panel 4: Key Metrics Table
  p4 <- create_metrics_table(optimized_windows, validated_data)

  # Assemble composite plot
  title_grob <- textGrob(
    "AIDIA Optimization Impact Summary",
    gp = gpar(fontsize = 16, fontface = "bold")
  )

  composite <- arrangeGrob(
    p1, p2, p3, p4,
    ncol = 2,
    top = title_grob
  )

  return(composite)
}

cat("  [plot_impact_summary.R] Optimization impact summary loaded\n")
