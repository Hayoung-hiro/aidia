# plot_satisfaction.R - Satisfaction Curve Visualization Functions
#
# Purpose: Generate satisfaction vs cycle time trade-off curves
#
# Functions:
#   - plot_satisfaction_curve(): S-curve showing DPPP satisfaction trade-off
#
# Dependencies: ggplot2, dplyr, utils_common.R (calculate_dppp)

library(ggplot2)
library(dplyr)

# =============================================================================
# Plot 6: Satisfaction vs Cycle Time Trade-off Curve
# =============================================================================

#' Plot Satisfaction Ratio vs Cycle Time Trade-off
#'
#' Shows the relationship between cycle time and DPPP satisfaction ratio
#' as a continuous S-curve, highlighting current state, recommended state,
#' and the optimization trade-off.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#' @param cycle_time_range Numeric vector of length 2, range of cycle times to display (default: c(0.5, 3.0))
#' @param n_points Integer, number of points to calculate along curve (default: 50)
#'
#' @return ggplot object
#' @export
plot_satisfaction_curve <- function(optimization_plan, validated_data,
                                   cycle_time_range = c(0.5, 3.0),
                                   n_points = 50) {

  cat("  Generating Plot 9: Satisfaction vs Cycle Time Trade-off Curve...\n")

  # Extract parameters
  current_cycle_time <- optimization_plan$diagnosis$current_cycle_time_sec
  required_cycle_time <- optimization_plan$required_cycle_time_sec
  target_dppp <- optimization_plan$parameters$target_dppp
  target_satisfaction <- optimization_plan$parameters$target_satisfaction * 100

  # Extract FWHM data
  fwhm_sec <- validated_data$data$FWHM * 60  # Convert to seconds

  # Calculate satisfaction across cycle time range
  cycle_times <- seq(cycle_time_range[1], cycle_time_range[2], length.out = n_points)

  satisfaction_data <- data.frame(
    cycle_time = cycle_times,
    satisfaction_pct = sapply(cycle_times, function(ct) {
      dppp <- calculate_dppp(fwhm_sec, ct)
      mean(dppp >= target_dppp, na.rm = TRUE) * 100
    })
  )

  # Calculate current and recommended satisfaction
  dppp_current <- calculate_dppp(fwhm_sec, current_cycle_time)
  current_satisfaction_pct <- mean(dppp_current >= target_dppp, na.rm = TRUE) * 100

  dppp_recommended <- calculate_dppp(fwhm_sec, required_cycle_time)
  recommended_satisfaction_pct <- mean(dppp_recommended >= target_dppp, na.rm = TRUE) * 100

  # Calculate improvement metrics
  cycle_time_reduction_pct <- ((current_cycle_time - required_cycle_time) / current_cycle_time) * 100
  satisfaction_gain_pp <- recommended_satisfaction_pct - current_satisfaction_pct  # percentage points

  # Create annotation text
  annotation_text <- sprintf(
    "Trade-off Analysis:\n\nCycle time: %.2f -> %.2f sec\nReduction: %.1f%%\n\nSatisfaction: %.1f%% -> %.1f%%\nGain: +%.1f pp\n\nFormula:\nSatisfaction = f(FWHM, cycle_time)\nTarget DPPP >= %.1f",
    current_cycle_time,
    required_cycle_time,
    cycle_time_reduction_pct,
    current_satisfaction_pct,
    recommended_satisfaction_pct,
    satisfaction_gain_pp,
    target_dppp
  )

  # Create plot
  p <- ggplot(satisfaction_data, aes(x = cycle_time, y = satisfaction_pct)) +
    # Reference lines
    geom_hline(
      yintercept = target_satisfaction,
      linetype = "dashed",
      color = "gray40",
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = cycle_time_range[1] + 0.1,
      y = target_satisfaction,
      label = sprintf("Target: %.0f%%", target_satisfaction),
      hjust = 0,
      vjust = -0.5,
      size = 3.5,
      fontface = "bold",
      color = "gray40"
    ) +
    geom_vline(
      xintercept = current_cycle_time,
      linetype = "dotted",
      color = "steelblue",
      linewidth = 0.6,
      alpha = 0.7
    ) +
    geom_vline(
      xintercept = required_cycle_time,
      linetype = "dotted",
      color = "coral",
      linewidth = 0.6,
      alpha = 0.7
    ) +
    # Main S-curve
    geom_line(color = "navy", linewidth = 1.5, alpha = 0.8) +
    # Current state point
    geom_point(
      data = data.frame(
        cycle_time = current_cycle_time,
        satisfaction_pct = current_satisfaction_pct
      ),
      aes(x = cycle_time, y = satisfaction_pct),
      color = "steelblue4",
      fill = "steelblue",
      size = 5,
      shape = 21,
      stroke = 2
    ) +
    annotate(
      "text",
      x = current_cycle_time,
      y = current_satisfaction_pct,
      label = sprintf("Current\n(%.2f sec, %.1f%%)", current_cycle_time, current_satisfaction_pct),
      hjust = 1.2,
      vjust = 0.5,
      size = 3.5,
      fontface = "bold",
      color = "steelblue4"
    ) +
    # Recommended state point
    geom_point(
      data = data.frame(
        cycle_time = required_cycle_time,
        satisfaction_pct = recommended_satisfaction_pct
      ),
      aes(x = cycle_time, y = satisfaction_pct),
      color = "coral4",
      fill = "coral",
      size = 5,
      shape = 21,
      stroke = 2
    ) +
    annotate(
      "text",
      x = required_cycle_time,
      y = recommended_satisfaction_pct,
      label = sprintf("Recommended\n(%.2f sec, %.1f%%)", required_cycle_time, recommended_satisfaction_pct),
      hjust = -0.2,
      vjust = 0.5,
      size = 3.5,
      fontface = "bold",
      color = "coral4"
    ) +
    # Improvement arrow (curved)
    geom_curve(
      data = data.frame(
        x = current_cycle_time,
        xend = required_cycle_time,
        y = current_satisfaction_pct + 5,
        yend = recommended_satisfaction_pct - 5
      ),
      aes(x = x, xend = xend, y = y, yend = yend),
      arrow = arrow(length = unit(0.3, "cm"), type = "closed"),
      color = "black",
      linewidth = 1,
      curvature = -0.3,
      alpha = 0.7
    ) +
    annotate(
      "text",
      x = (current_cycle_time + required_cycle_time) / 2,
      y = (current_satisfaction_pct + recommended_satisfaction_pct) / 2 + 8,
      label = sprintf("%.1f%% cycle time down\n+%.1f pp satisfaction up",
                     cycle_time_reduction_pct, satisfaction_gain_pp),
      hjust = 0.5,
      vjust = 0.5,
      size = 3.5,
      fontface = "bold",
      lineheight = 0.9
    ) +
    # Annotation box (right side, mid-to-top position to avoid overlap)
    annotate(
      "text",
      x = cycle_time_range[2] - 0.1,
      y = 90,
      label = annotation_text,
      hjust = 1,
      vjust = 1,
      size = 3,
      family = "mono",
      lineheight = 0.95
    ) +
    # Scales
    scale_x_continuous(
      breaks = seq(cycle_time_range[1], cycle_time_range[2], by = 0.5),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(
      breaks = seq(0, 100, by = 10),
      limits = c(0, 100),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    # Labels
    labs(
      title = "DPPP Satisfaction vs Cycle Time Trade-off",
      subtitle = sprintf("Optimization path from %.2f sec (%.1f%%) to %.2f sec (%.1f%%) for %s precursors",
                        current_cycle_time, current_satisfaction_pct,
                        required_cycle_time, recommended_satisfaction_pct,
                        format(nrow(validated_data$data), big.mark = ",")),
      x = "Cycle Time (seconds)",
      y = "Satisfaction Ratio (%)",
      caption = "S-curve shows trade-off between cycle time and DPPP achievement; shorter cycle time = higher satisfaction"
    ) +
    # Theme
    theme_dia_optimizer() +
    theme(
      panel.grid.minor = element_line(color = "gray95", linewidth = 0.3)
    )

  return(p)
}

cat("  [plot_satisfaction.R] Satisfaction curve functions loaded\n")
