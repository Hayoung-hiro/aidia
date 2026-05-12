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
  ct_is_estimated <- optimization_plan$diagnosis$current_ct_is_estimated %||% FALSE
  has_current <- !ct_is_estimated
  planned_cycle_time <- optimization_plan$actual_cycle_time_sec
  required_cycle_time <- optimization_plan$required_cycle_time_sec
  target_dppp <- optimization_plan$parameters$target_dppp
  target_satisfaction <- optimization_plan$parameters$target_satisfaction * 100

  # Extract FWHM data
  fwhm_sec <- ensure_fwhm_seconds(validated_data$data$FWHM)

  # Dynamic cycle time range
  if (is.null(cycle_time_range)) {
    key_points <- c(planned_cycle_time, required_cycle_time)
    if (has_current) key_points <- c(key_points, current_cycle_time)
    ct_min <- min(key_points)
    ct_max <- max(key_points)
    padding <- max(0.5, (ct_max - ct_min) * 0.5)
    cycle_time_range <- c(max(0.3, ct_min - padding), ct_max + padding)
  }

  # Calculate satisfaction across cycle time range
  cycle_times <- seq(cycle_time_range[1], cycle_time_range[2], length.out = n_points)

  satisfaction_data <- data.frame(
    cycle_time = cycle_times,
    satisfaction_pct = vapply(cycle_times, function(ct) {
      dppp_satisfaction_pct(calculate_dppp(fwhm_sec, ct), target_dppp)
    }, numeric(1))
  )

  # Calculate satisfaction at key operating points
  dppp_planned <- calculate_dppp(fwhm_sec, planned_cycle_time)
  planned_satisfaction_pct <- dppp_satisfaction_pct(dppp_planned, target_dppp)
  if (has_current) {
    dppp_current <- calculate_dppp(fwhm_sec, current_cycle_time)
    current_satisfaction_pct <- dppp_satisfaction_pct(dppp_current, target_dppp)
  }

  # ---- Knee point detection (Kneedle algorithm — upper knee) ----
  # Find the diminishing returns threshold: the cycle time below which
  # further reduction yields marginal satisfaction gain.
  # Uses signed perpendicular distance from the diagonal. Points in the
  # high-satisfaction plateau region deviate most below the diagonal
  # (signed distance < 0); the minimum = the upper knee.
  x_raw <- satisfaction_data$cycle_time
  y_raw <- satisfaction_data$satisfaction_pct
  x_norm <- (x_raw - min(x_raw)) / diff(range(x_raw))
  y_norm <- (y_raw - min(y_raw)) / max(1e-6, diff(range(y_raw)))

  # Signed distance from each point to the diagonal (first → last)
  # Negative = above the diagonal (high-satisfaction plateau)
  x1 <- x_norm[1]; y1 <- y_norm[1]
  x2 <- x_norm[length(x_norm)]; y2 <- y_norm[length(y_norm)]
  signed_dist <- ((y2 - y1) * x_norm - (x2 - x1) * y_norm +
                  x2 * y1 - y2 * x1) /
                 max(1e-6, sqrt((y2 - y1)^2 + (x2 - x1)^2))
  knee_idx <- which.min(signed_dist)  # most above diagonal = upper knee
  knee_ct <- x_raw[knee_idx]
  knee_sat <- y_raw[knee_idx]

  # Label placement — avoid overlap between knee and planned points
  planned_label_above <- (planned_satisfaction_pct >= target_satisfaction)
  knee_close_to_planned <- abs(knee_ct - planned_cycle_time) < diff(cycle_time_range) * 0.15
  knee_hjust <- if (knee_close_to_planned) 1.1 else -0.1
  knee_vjust <- if (knee_close_to_planned) 0.5 else 0.5

  # Build plot — S-curve with knee + planned markers; current only if user-provided
  p <- ggplot(satisfaction_data, aes(x = cycle_time, y = satisfaction_pct)) +
    # Feasibility region: above target satisfaction AND below required cycle time
    annotate(
      "rect",
      xmin = cycle_time_range[1], xmax = required_cycle_time,
      ymin = target_satisfaction, ymax = 100,
      fill = aidia_colors$success, alpha = 0.12
    ) +
    # Target satisfaction reference line
    geom_hline(
      yintercept = target_satisfaction,
      linetype = "dashed",
      color = "gray50",
      linewidth = 0.6
    ) +
    annotate(
      "text",
      x = cycle_time_range[2],
      y = target_satisfaction,
      label = sprintf("Target: %.0f%%", target_satisfaction),
      hjust = 1.05, vjust = -0.5,
      size = 3, fontface = "bold", color = "gray50"
    ) +
    # Main S-curve
    geom_line(color = aidia_colors$primary, linewidth = 1.5, alpha = 0.8) +
    # Knee point — diminishing returns threshold
    geom_point(
      data = data.frame(cycle_time = knee_ct, satisfaction_pct = knee_sat),
      aes(x = cycle_time, y = satisfaction_pct),
      color = aidia_colors$warning, fill = aidia_colors$warning,
      size = 4, shape = 18
    ) +
    annotate(
      "label",
      x = knee_ct, y = knee_sat,
      label = sprintf("Knee: %.2fs, %.0f%%", knee_ct, knee_sat),
      hjust = knee_hjust, vjust = knee_vjust,
      size = 3, fontface = "bold", color = aidia_colors$warning,
      fill = "white", alpha = 0.85
    )

  # Current state point — only when user provided actual cycle time
  if (has_current) {
    p <- p +
      geom_point(
        data = data.frame(cycle_time = current_cycle_time,
                          satisfaction_pct = current_satisfaction_pct),
        aes(x = cycle_time, y = satisfaction_pct),
        color = aidia_colors$before_dark, fill = aidia_colors$before,
        size = 4.5, shape = 21, stroke = 1.5
      ) +
      annotate(
        "label",
        x = current_cycle_time, y = current_satisfaction_pct,
        label = sprintf("Current: %.2fs, %.0f%%", current_cycle_time, current_satisfaction_pct),
        hjust = -0.1, vjust = 0.5,
        size = 3.2, fontface = "bold", color = aidia_colors$before_dark,
        fill = "white", alpha = 0.85
      )
  }

  # Planned state point
  planned_hjust <- if (knee_close_to_planned) -0.1
                   else if (has_current && current_cycle_time > planned_cycle_time) 1.1
                   else -0.1
  planned_vjust <- if (knee_close_to_planned) 1.5
                   else if (planned_label_above) -1.0
                   else 0.5

  p <- p +
    geom_vline(
      xintercept = planned_cycle_time,
      linetype = "dotted",
      color = aidia_colors$after,
      linewidth = 0.6
    ) +
    geom_point(
      data = data.frame(cycle_time = planned_cycle_time,
                        satisfaction_pct = planned_satisfaction_pct),
      aes(x = cycle_time, y = satisfaction_pct),
      color = aidia_colors$after_dark, fill = aidia_colors$after,
      size = 4.5, shape = 21, stroke = 1.5
    ) +
    annotate(
      "label",
      x = planned_cycle_time, y = planned_satisfaction_pct,
      label = sprintf("Planned: %.2fs, %.0f%%", planned_cycle_time, planned_satisfaction_pct),
      hjust = planned_hjust, vjust = planned_vjust,
      size = 3.2, fontface = "bold", color = aidia_colors$after_dark,
      fill = "white", alpha = 0.85
    ) +
    # Scales
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
        "Planned cycle time: %.2f sec | %.0f%% satisfaction at DPPP >= %.1f",
        planned_cycle_time, planned_satisfaction_pct, target_dppp
      ),
      x = "Cycle Time (seconds)",
      y = sprintf("Precursors with DPPP >= %.1f (%%)", target_dppp),
      caption = sprintf(
        "Shorter cycle time = higher DPPP | %s precursors | Knee = diminishing returns",
        format(nrow(validated_data$data), big.mark = ",")
      )
    ) +
    theme_aidia()

  return(p)
}

