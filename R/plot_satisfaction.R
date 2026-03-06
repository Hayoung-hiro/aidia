# plot_satisfaction.R - Satisfaction Curve Visualization Functions
#
# Purpose: Generate satisfaction vs cycle time trade-off curves
#
# Functions:
#   - plot_satisfaction_curve(): S-curve showing DPPP satisfaction trade-off
#
# Dependencies: ggplot2, dplyr, utils_common.R (calculate_dppp)


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
#' @keywords internal
plot_satisfaction_curve <- function(optimization_plan, validated_data,
                                   cycle_time_range = NULL,
                                   n_points = 50) {

  cat("  Generating Plot 6: Satisfaction vs Cycle Time Trade-off Curve...\n")

  # Extract parameters
  current_cycle_time <- optimization_plan$diagnosis$current_cycle_time_sec
  required_cycle_time <- optimization_plan$required_cycle_time_sec
  target_dppp <- optimization_plan$parameters$target_dppp
  target_satisfaction <- optimization_plan$parameters$target_satisfaction * 100

  # Extract FWHM data
  fwhm_sec <- ensure_fwhm_seconds(validated_data$data$FWHM)

  # Dynamic cycle time range: pad around actual values to ensure both points visible
  if (is.null(cycle_time_range)) {
    ct_min <- min(current_cycle_time, required_cycle_time)
    ct_max <- max(current_cycle_time, required_cycle_time)
    padding <- max(0.5, (ct_max - ct_min) * 0.5)
    cycle_time_range <- c(max(0.3, ct_min - padding), ct_max + padding)
  }

  # Calculate satisfaction across cycle time range
  cycle_times <- seq(cycle_time_range[1], cycle_time_range[2], length.out = n_points)

  satisfaction_data <- data.frame(
    cycle_time = cycle_times,
    satisfaction_pct = sapply(cycle_times, function(ct) {
      dppp <- calculate_dppp(fwhm_sec, ct)
      mean(dppp >= target_dppp, na.rm = TRUE) * 100
    })
  )

  # Calculate current and recommended satisfaction (reuse shared helper)
  km <- compute_dppp_key_metrics(fwhm_sec, current_cycle_time, required_cycle_time, target_dppp)
  current_satisfaction_pct <- km$current_sat
  recommended_satisfaction_pct <- km$required_sat

  # Create plot — clean S-curve with minimal crosshair annotation
  p <- ggplot(satisfaction_data, aes(x = cycle_time, y = satisfaction_pct)) +
    # Target satisfaction reference line
    geom_hline(
      yintercept = target_satisfaction,
      linetype = "dashed",
      color = "gray50",
      linewidth = 0.6
    ) +
    annotate(
      "text",
      x = cycle_time_range[1],
      y = target_satisfaction,
      label = sprintf("Target: %.0f%%", target_satisfaction),
      hjust = -0.1, vjust = -0.5,
      size = 3, fontface = "bold", color = "gray50"
    ) +
    # Required cycle time crosshair (vertical)
    geom_vline(
      xintercept = required_cycle_time,
      linetype = "dotted",
      color = aidia_colors$after,
      linewidth = 0.6
    ) +
    # Main S-curve
    geom_line(color = aidia_colors$primary, linewidth = 1.5, alpha = 0.8) +
    # Current state point
    geom_point(
      data = data.frame(
        cycle_time = current_cycle_time,
        satisfaction_pct = current_satisfaction_pct
      ),
      aes(x = cycle_time, y = satisfaction_pct),
      color = aidia_colors$before_dark, fill = aidia_colors$before,
      size = 4.5, shape = 21, stroke = 1.5
    ) +
    annotate(
      "label",
      x = current_cycle_time,
      y = current_satisfaction_pct,
      label = sprintf("Current: %.2fs, %.0f%%", current_cycle_time, current_satisfaction_pct),
      hjust = if (current_cycle_time > required_cycle_time) -0.1 else 1.1,
      vjust = 0.5,
      size = 3.2, fontface = "bold", color = aidia_colors$before_dark,
      fill = "white", alpha = 0.85, label.linewidth = 0.3
    ) +
    # Required state point (intersection)
    geom_point(
      data = data.frame(
        cycle_time = required_cycle_time,
        satisfaction_pct = recommended_satisfaction_pct
      ),
      aes(x = cycle_time, y = satisfaction_pct),
      color = aidia_colors$after_dark, fill = aidia_colors$after,
      size = 4.5, shape = 21, stroke = 1.5
    ) +
    annotate(
      "label",
      x = required_cycle_time,
      y = recommended_satisfaction_pct,
      label = sprintf("Required: %.2fs, %.0f%%", required_cycle_time, recommended_satisfaction_pct),
      hjust = if (current_cycle_time > required_cycle_time) 1.1 else -0.1,
      vjust = 0.5,
      size = 3.2, fontface = "bold", color = aidia_colors$after_dark,
      fill = "white", alpha = 0.85, label.linewidth = 0.3
    ) +
    # Scales — clean breaks
    scale_x_continuous(
      breaks = scales::breaks_pretty(n = 8),
      expand = expansion(mult = c(0.05, 0.05))
    ) +
    scale_y_continuous(
      breaks = seq(0, 100, by = 10),
      limits = c(0, 100),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    labs(
      title = "Satisfaction vs Cycle Time",
      subtitle = sprintf(
        "Required cycle time: %.2f sec for %.0f%% satisfaction at DPPP >= %.1f",
        required_cycle_time, target_satisfaction, target_dppp
      ),
      x = "Cycle Time (seconds)",
      y = sprintf("Precursors with DPPP >= %.1f (%%)", target_dppp),
      caption = sprintf(
        "Shorter cycle time = higher DPPP | %s precursors",
        format(nrow(validated_data$data), big.mark = ",")
      )
    ) +
    theme_aidia()

  return(p)
}

