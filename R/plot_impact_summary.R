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
  fwhm_sec <- ensure_fwhm_seconds(validated_data$data$FWHM)
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
    color = c(aidia_colors$before_muted, aidia_colors$success)
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
  # Extract metrics — use canonical S3 field paths
  strategy <- optimized_windows$parameters$mz_strategy %||%
              optimized_windows$mz_optimization$strategy %||% "unknown"
  window_mode <- optimized_windows$parameters$window_mode %||% "unknown"
  n_precursors <- validated_data$metadata$n_precursors %||%
                  validated_data$summary$n_precursors %||% nrow(validated_data$data)
  n_rt_bins <- length(unique(optimized_windows$windows$rt_segment_id))

  # Calculate mean window width (column is window_width, not mz_width)
  if ("window_width" %in% colnames(optimized_windows$windows)) {
    mean_width <- mean(optimized_windows$windows$window_width, na.rm = TRUE)
  } else if ("mz_width" %in% colnames(optimized_windows$windows)) {
    mean_width <- mean(optimized_windows$windows$mz_width, na.rm = TRUE)
  } else {
    mean_width <- NA
  }

  # Extract coverage from statistics (handle both list and tibble formats)
  if (is.list(optimized_windows$statistics)) {
    coverage <- optimized_windows$statistics$mean_coverage_ratio
  } else if (is.data.frame(optimized_windows$statistics)) {
    coverage <- mean(optimized_windows$statistics$coverage_ratio, na.rm = TRUE)
  } else {
    coverage <- NA
  }

  # If coverage is NULL, NA, or length 0, try alternative sources
  if (is.null(coverage) || length(coverage) == 0 || is.na(coverage)) {
    coverage <- optimized_windows$statistics$coverage_percentage
    if (!is.null(coverage) && length(coverage) > 0 && !is.na(coverage)) {
      coverage <- coverage / 100  # Convert from percentage to ratio
    }
  }

  # If coverage not available, calculate from mz_ranges
  if (is.null(coverage) || length(coverage) == 0 || is.na(coverage)) {
    if (!is.null(optimized_windows$mz_optimization$mz_ranges)) {
      coverage <- mean(optimized_windows$mz_optimization$mz_ranges$coverage_ratio, na.rm = TRUE)
    }
  }

  # Format coverage: show "N/A" instead of silent 0%
  coverage_display <- if (is.null(coverage) || length(coverage) == 0 ||
                          is.na(coverage) || coverage == 0) {
    "N/A"
  } else {
    sprintf("%.1f%%", coverage * 100)
  }

  # Format text
  text_lines <- c(
    sprintf("Strategy:    %s", format_strategy_label(strategy)),
    sprintf("Window Mode: %s", tools::toTitleCase(window_mode)),
    sprintf("Precursors:  %s", format(n_precursors, big.mark = ",")),
    sprintf("RT Bins:     %d", n_rt_bins),
    sprintf("Mean Width:  %.1f Da", mean_width),
    sprintf("Coverage:    %s", coverage_display)
  )

  # Remove NULL entries (defensive)
  text_lines <- text_lines[!vapply(text_lines, is.null, logical(1))]

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
        color = aidia_colors$primary,
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
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' p <- plot_optimization_impact(optimization_plan, optimized_windows, validated_data)
#' ggsave("impact_summary.png", p, width = 10, height = 8)
#' }
plot_optimization_impact <- function(optimization_plan, optimized_windows, validated_data) {

  cat("  Generating Optimization Impact Summary (Before/After)...\n")

  # Extract before (current) values
  before_cycle_time <- optimization_plan$diagnosis$current_cycle_time_sec
  before_satisfaction <- optimization_plan$diagnosis$current_satisfaction_ratio

  after_n_windows <- nrow(optimized_windows$windows)

  # Extract after (optimized) values
  after_cycle_time <- optimization_plan$required_cycle_time_sec

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
      color = aidia_colors$accent,
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
      color = aidia_colors$accent
    )

  # Panel 3: Optimized Window Count (no "before" — original method is unknown)
  n_rt_bins <- length(unique(optimized_windows$windows$rt_segment_id))
  windows_per_bin <- optimization_plan$window_count_per_bin
  p3_df <- data.frame(
    label = c(
      sprintf("Total Windows: %s", format(after_n_windows, big.mark = ",")),
      sprintf("RT Bins: %d", n_rt_bins),
      sprintf("Windows/Bin: %d", windows_per_bin)
    ),
    x = 0.05,
    y = c(0.7, 0.5, 0.3)
  )
  p3 <- ggplot(p3_df, aes(x = x, y = y, label = label)) +
    geom_text(hjust = 0, vjust = 0.5, size = 4.5, fontface = "bold",
              color = aidia_colors$primary) +
    scale_x_continuous(limits = c(0, 1)) +
    scale_y_continuous(limits = c(0, 1)) +
    labs(title = "Optimized Window Layout") +
    theme_void() +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold", size = 12,
                                color = aidia_colors$primary, margin = margin(b = 10)),
      plot.background = element_rect(fill = "white", color = "gray80", linewidth = 0.5),
      plot.margin = margin(10, 10, 10, 10)
    )

  # Panel 4: Key Metrics Table
  p4 <- create_metrics_table(optimized_windows, validated_data)

  # Assemble composite plot
  title_grob <- grid::textGrob(
    "AIDIA Configuration Summary",
    gp = grid::gpar(fontsize = 16, fontface = "bold")
  )

  composite <- gridExtra::arrangeGrob(
    p1, p2, p3, p4,
    ncol = 2,
    top = title_grob
  )

  return(composite)
}

