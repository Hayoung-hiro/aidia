# plot_dppp.R - DPPP Distribution Visualization Functions
#
# Purpose: Generate DPPP distribution comparison plots (current vs recommended)
#
# Functions:
#   - plot_dppp_comparison(): Simple dual density plot
#   - plot_dppp_comparison_enhanced(): Enhanced version with visual annotations
#
# Dependencies: ggplot2, dplyr, tidyr, utils_common.R (calculate_dppp)


# =============================================================================
# Shared Helper
# =============================================================================

#' Extract FWHM data and cycle times from plan/validated inputs
#' @keywords internal
extract_dppp_inputs <- function(optimization_plan, validated_data) {
  list(
    current_cycle_time = optimization_plan$diagnosis$current_cycle_time_sec,
    required_cycle_time = optimization_plan$required_cycle_time_sec,
    target_dppp = optimization_plan$parameters$target_dppp,
    fwhm_data = validated_data$data %>%
      select(FWHM) %>%
      mutate(FWHM_sec = ensure_fwhm_seconds(FWHM))
  )
}

#' Compute DPPP key metrics at two operating points
#'
#' Calculates median DPPP and satisfaction at both current and required
#' cycle times. Avoids redundant calculate_dppp() calls by computing
#' each DPPP vector once.
#'
#' @param fwhm_sec Numeric vector of FWHM in seconds
#' @param current_ct Current cycle time (seconds)
#' @param required_ct Required cycle time (seconds)
#' @param target_dppp Target DPPP threshold
#'
#' @return Named list with current_dppp, required_dppp, current_sat, required_sat
#' @keywords internal
compute_dppp_key_metrics <- function(fwhm_sec, current_ct, required_ct, target_dppp) {
  dppp_current  <- calculate_dppp(fwhm_sec, current_ct)
  dppp_required <- calculate_dppp(fwhm_sec, required_ct)
  list(
    current_dppp  = median(dppp_current, na.rm = TRUE),
    required_dppp = median(dppp_required, na.rm = TRUE),
    current_sat   = dppp_satisfaction_pct(dppp_current, target_dppp),
    required_sat  = dppp_satisfaction_pct(dppp_required, target_dppp)
  )
}

# =============================================================================
# Plot 1A: DPPP Distribution Comparison (Simple Version)
# =============================================================================

#' Plot DPPP Distribution: Current vs Recommended Cycle Time
#'
#' Shows dual density curves comparing current DPPP with expected DPPP
#' after applying recommended cycle time. Includes target line and statistics.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_dppp_comparison <- function(optimization_plan, validated_data) {

  cat("  Generating Plot 1: DPPP Distribution Comparison...\n")

  inputs <- extract_dppp_inputs(optimization_plan, validated_data)
  current_cycle_time <- inputs$current_cycle_time
  required_cycle_time <- inputs$required_cycle_time
  target_dppp <- inputs$target_dppp
  fwhm_data <- inputs$fwhm_data

  if (nrow(fwhm_data) < 2) {
    return(create_insufficient_data_plot(
      title = "DPPP Distribution Comparison",
      message = "Insufficient data for density plot\n(need at least 2 precursors)"
    ))
  }

  # Calculate current and expected DPPP
  dppp_data <- fwhm_data %>%
    mutate(
      current_dppp = calculate_dppp(FWHM_sec, current_cycle_time),
      expected_dppp = calculate_dppp(FWHM_sec, required_cycle_time)
    ) %>%
    select(current_dppp, expected_dppp) %>%
    pivot_longer(
      cols = everything(),
      names_to = "condition",
      values_to = "dppp"
    ) %>%
    mutate(
      condition = factor(
        condition,
        levels = c("current_dppp", "expected_dppp"),
        labels = c(
          sprintf("Current (%.3f sec)", current_cycle_time),
          sprintf("Recommended (%.3f sec)", required_cycle_time)
        )
      )
    )

  # Calculate statistics for annotation
  median_fwhm_sec <- median(fwhm_data$FWHM_sec)
  n_precursors <- nrow(validated_data$data)
  current_satisfaction <- optimization_plan$diagnosis$current_satisfaction_ratio * 100

  # Calculate expected satisfaction (approximate)
  expected_satisfaction <- sum(dppp_data$condition == levels(dppp_data$condition)[2] &
                                dppp_data$dppp >= target_dppp) /
                           (n_precursors) * 100

  # Create annotation text with larger font and simplified formula
  annotation_text <- sprintf(
    "DPPP = (FWHM x 1.7) / cycle_time\n\nCurrent State:\n  Median FWHM: %.1f sec\n  Cycle time: %.1f sec\n  Satisfaction: %.1f%%\n\nRecommended:\n  Cycle time: %.1f sec\n  Expected satisfaction: %.1f%%+\n\nTotal precursors: %s",
    median_fwhm_sec,
    current_cycle_time,
    current_satisfaction,
    required_cycle_time,
    expected_satisfaction,
    format(n_precursors, big.mark = ",")
  )

  # Create dual density plot with improved visibility
  p <- ggplot(dppp_data, aes(x = dppp, fill = condition, color = condition)) +
    geom_density(alpha = 0.3, linewidth = 1.2) +  # More transparent, thicker line
    geom_vline(
      xintercept = target_dppp,
      linetype = "dashed",
      color = "black",
      linewidth = 1
    ) +
    annotate(
      "text",
      x = target_dppp,
      y = Inf,
      label = sprintf("Target DPPP = %.1f", target_dppp),
      hjust = -0.1,
      vjust = 1.5,
      size = 4,
      fontface = "bold"
    ) +
    annotate(
      "text",
      x = Inf,
      y = Inf,
      label = annotation_text,
      hjust = 1.05,
      vjust = 1.05,
      size = 3.5,  # Increased from 3 to 3.5
      family = "mono",
      lineheight = 0.95
    ) +
    scale_fill_manual(
      values = c(aidia_colors$before, aidia_colors$after),
      name = "Cycle Time"
    ) +
    scale_color_manual(
      values = c(aidia_colors$before_dark, aidia_colors$after_dark),
      name = "Cycle Time"
    ) +
    scale_x_continuous(
      limits = c(0, 15),  # Focus on main data region (x < 10)
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    labs(
      title = "DPPP Distribution: Current vs Recommended Cycle Time",
      subtitle = "Optimization reduces cycle time to improve DPPP achievement",
      x = "DPPP (Data Points Per Peak)",
      y = "Density",
      caption = "Shaded area shows probability density; dashed line = target DPPP"
    ) +
    theme_aidia() +
    theme(
      legend.position.inside = c(0.02, 0.85),  # ggplot2 3.5.0+ syntax
      legend.position = "inside",
      legend.justification = c(0, 1),
      legend.background = element_rect(fill = "white", color = "gray80"),
      legend.key.size = unit(0.8, "cm"),
      legend.title = element_text(size = 11, face = "bold")
    )

  return(p)
}

# =============================================================================
# Plot 1B: Median DPPP vs Cycle Time Curve
# =============================================================================

#' Plot Median DPPP vs Cycle Time
#'
#' Shows the hyperbolic relationship between cycle time and median DPPP.
#' Marks the current operating point and the required cycle time to meet
#' the target DPPP + satisfaction. Clearly shows whether cycle time must
#' increase or decrease.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#' @param n_points Number of points along the curve (default: 80)
#'
#' @return ggplot object
#' @keywords internal
plot_dppp_comparison_enhanced <- function(optimization_plan, validated_data,
                                          n_points = 80) {

  cat("  Generating Plot 1B: Median DPPP vs Cycle Time Curve...\n")

  inputs <- extract_dppp_inputs(optimization_plan, validated_data)
  current_cycle_time <- inputs$current_cycle_time
  required_cycle_time <- inputs$required_cycle_time
  target_dppp <- inputs$target_dppp
  fwhm_data <- inputs$fwhm_data

  if (nrow(fwhm_data) < 2) {
    return(create_insufficient_data_plot(
      title = "DPPP vs Cycle Time",
      message = "Insufficient data\n(need at least 2 precursors)"
    ))
  }

  fwhm_sec <- fwhm_data$FWHM_sec
  target_satisfaction <- (optimization_plan$parameters$target_satisfaction %||% 0.7) * 100

  # Build cycle time range with padding around both key points
  ct_min <- min(current_cycle_time, required_cycle_time)
  ct_max <- max(current_cycle_time, required_cycle_time)
  padding <- max(0.3, (ct_max - ct_min) * 0.4)
  ct_range <- c(max(0.2, ct_min - padding), ct_max + padding)

  # Calculate median DPPP across the cycle time range
  cycle_times <- seq(ct_range[1], ct_range[2], length.out = n_points)
  curve_data <- data.frame(
    cycle_time = cycle_times,
    median_dppp = vapply(cycle_times, function(ct) {
      median(calculate_dppp(fwhm_sec, ct), na.rm = TRUE)
    }, numeric(1))
  )

  # Key point metrics (compute each DPPP vector once)
  km <- compute_dppp_key_metrics(fwhm_sec, current_cycle_time, required_cycle_time, target_dppp)
  current_dppp <- km$current_dppp
  required_dppp <- km$required_dppp
  current_sat <- km$current_sat
  required_sat <- km$required_sat

  # Direction label
  ct_change <- required_cycle_time - current_cycle_time
  direction <- if (ct_change < 0) "decrease" else "increase"

  # Key points data
  points_df <- data.frame(
    cycle_time = c(current_cycle_time, required_cycle_time),
    median_dppp = c(current_dppp, required_dppp),
    label = c("Current", "Required"),
    color_key = c("current", "required")
  )

  # Y-axis upper limit
  y_max <- max(curve_data$median_dppp) * 1.15

  p <- ggplot() +
    # Target DPPP reference line
    geom_hline(
      yintercept = target_dppp,
      linetype = "dashed",
      color = aidia_colors$accent,
      linewidth = 0.7
    ) +
    annotate(
      "text",
      x = ct_range[2],
      y = target_dppp,
      label = sprintf("Target DPPP = %.1f", target_dppp),
      hjust = 1.05, vjust = -0.6,
      size = 3.2, fontface = "bold",
      color = aidia_colors$accent
    ) +
    # Main curve
    geom_line(
      data = curve_data,
      aes(x = cycle_time, y = median_dppp),
      color = aidia_colors$primary,
      linewidth = 1.5,
      alpha = 0.8
    ) +
    # Current state point
    geom_point(
      data = points_df[1, ],
      aes(x = cycle_time, y = median_dppp),
      color = aidia_colors$before_dark, fill = aidia_colors$before,
      size = 5, shape = 21, stroke = 1.5
    ) +
    annotate(
      "label",
      x = current_cycle_time,
      y = current_dppp,
      label = sprintf("Current\n%.2f sec | DPPP %.1f | Sat %.0f%%",
                     current_cycle_time, current_dppp, current_sat),
      hjust = if (ct_change < 0) -0.1 else 1.1,
      vjust = 0.5,
      size = 3.2, fontface = "bold",
      color = aidia_colors$before_dark,
      fill = "white", alpha = 0.85,
      label.linewidth = 0.3, label.padding = unit(0.3, "lines")
    ) +
    # Required state point
    geom_point(
      data = points_df[2, ],
      aes(x = cycle_time, y = median_dppp),
      color = aidia_colors$after_dark, fill = aidia_colors$after,
      size = 5, shape = 21, stroke = 1.5
    ) +
    annotate(
      "label",
      x = required_cycle_time,
      y = required_dppp,
      label = sprintf("Required\n%.2f sec | DPPP %.1f | Sat %.0f%%",
                     required_cycle_time, required_dppp, required_sat),
      hjust = if (ct_change < 0) 1.1 else -0.1,
      vjust = 0.5,
      size = 3.2, fontface = "bold",
      color = aidia_colors$after_dark,
      fill = "white", alpha = 0.85,
      label.linewidth = 0.3, label.padding = unit(0.3, "lines")
    ) +
    # Direction arrow between points
    annotate(
      "segment",
      x = current_cycle_time,
      xend = required_cycle_time,
      y = min(current_dppp, required_dppp) * 0.85,
      yend = min(current_dppp, required_dppp) * 0.85,
      arrow = arrow(length = unit(0.25, "cm"), type = "closed"),
      color = "gray40", linewidth = 0.8
    ) +
    annotate(
      "text",
      x = (current_cycle_time + required_cycle_time) / 2,
      y = min(current_dppp, required_dppp) * 0.85,
      label = sprintf("Cycle time %s", direction),
      vjust = -0.8, size = 3, color = "gray40"
    ) +
    # Scales
    scale_x_continuous(
      breaks = scales::breaks_pretty(n = 8),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(
      limits = c(0, y_max),
      breaks = scales::breaks_pretty(n = 6),
      expand = expansion(mult = c(0, 0.02))
    ) +
    labs(
      title = "Median DPPP vs Cycle Time",
      subtitle = sprintf(
        "DPPP = 1.7 \u00d7 FWHM / cycle_time | Median FWHM: %.1f sec | %s precursors",
        median(fwhm_sec), format(length(fwhm_sec), big.mark = ",")
      ),
      x = "Cycle Time (seconds)",
      y = "Median DPPP",
      caption = sprintf(
        "Shorter cycle time = higher DPPP | Target: DPPP >= %.1f, Satisfaction >= %.0f%%",
        target_dppp, target_satisfaction
      )
    ) +
    theme_aidia() +
    theme(
      panel.grid.minor = element_line(color = "gray95", linewidth = 0.3)
    )

  return(p)
}


# =============================================================================
# Plot 1B+6 Combined: DPPP Curve + Satisfaction Curve (Dual-Panel)
# =============================================================================

#' Plot Combined DPPP and Satisfaction vs Cycle Time
#'
#' Dual-panel figure with shared x-axis:
#' - Top: Median DPPP vs Cycle Time (hyperbolic curve)
#' - Bottom: Satisfaction (% meeting target) vs Cycle Time (S-curve)
#'
#' Both panels mark Current and Required operating points.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#' @param n_points Number of points along the curve (default: 80)
#'
#' @return gtable object (gridExtra)
#' @keywords internal
plot_dppp_satisfaction_combined <- function(optimization_plan, validated_data,
                                            n_points = 80) {

  cat("  Generating Plot 1B+6: DPPP & Satisfaction vs Cycle Time...\n")

  inputs <- extract_dppp_inputs(optimization_plan, validated_data)
  current_cycle_time <- inputs$current_cycle_time
  required_cycle_time <- inputs$required_cycle_time
  target_dppp <- inputs$target_dppp
  fwhm_data <- inputs$fwhm_data

  if (nrow(fwhm_data) < 2) {
    return(create_insufficient_data_plot(
      title = "DPPP & Satisfaction vs Cycle Time",
      message = "Insufficient data\n(need at least 2 precursors)"
    ))
  }

  fwhm_sec <- fwhm_data$FWHM_sec
  target_satisfaction <- (optimization_plan$parameters$target_satisfaction %||% 0.7) * 100

  # Shared cycle time range
  ct_min <- min(current_cycle_time, required_cycle_time)
  ct_max <- max(current_cycle_time, required_cycle_time)
  padding <- max(0.3, (ct_max - ct_min) * 0.4)
  ct_range <- c(max(0.2, ct_min - padding), ct_max + padding)

  cycle_times <- seq(ct_range[1], ct_range[2], length.out = n_points)

  # Pre-compute both curves (single DPPP vector per cycle time)
  curve_metrics <- vapply(cycle_times, function(ct) {
    dppp <- calculate_dppp(fwhm_sec, ct)
    c(median(dppp, na.rm = TRUE), mean(dppp >= target_dppp, na.rm = TRUE) * 100)
  }, numeric(2))

  curve_data <- data.frame(
    cycle_time = cycle_times,
    median_dppp = curve_metrics[1, ],
    satisfaction_pct = curve_metrics[2, ]
  )

  # Key metrics at operating points (compute each DPPP vector once)
  km <- compute_dppp_key_metrics(fwhm_sec, current_cycle_time, required_cycle_time, target_dppp)
  current_dppp <- km$current_dppp
  required_dppp <- km$required_dppp
  current_sat <- km$current_sat
  required_sat <- km$required_sat

  ct_change <- required_cycle_time - current_cycle_time
  direction <- if (ct_change < 0) "decrease" else "increase"

  y_max_dppp <- max(curve_data$median_dppp) * 1.15

  # --- Top Panel: DPPP vs Cycle Time ---
  p_top <- ggplot(curve_data, aes(x = cycle_time, y = median_dppp)) +
    geom_hline(yintercept = target_dppp, linetype = "dashed",
               color = aidia_colors$accent, linewidth = 0.7) +
    annotate("text", x = ct_range[2], y = target_dppp,
             label = sprintf("Target DPPP = %.1f", target_dppp),
             hjust = 1.05, vjust = -0.6, size = 3.2, fontface = "bold",
             color = aidia_colors$accent) +
    geom_line(color = aidia_colors$primary, linewidth = 1.5, alpha = 0.8) +
    # Current point
    geom_point(data = data.frame(cycle_time = current_cycle_time, median_dppp = current_dppp),
               color = aidia_colors$before_dark, fill = aidia_colors$before, size = 5, shape = 21, stroke = 1.5) +
    annotate("label", x = current_cycle_time, y = current_dppp,
             label = sprintf("Current\n%.2f sec | DPPP %.1f",
                            current_cycle_time, current_dppp),
             hjust = if (ct_change < 0) -0.1 else 1.1, vjust = 0.5,
             size = 3, fontface = "bold", color = aidia_colors$before_dark,
             fill = "white", alpha = 0.85, label.linewidth = 0.3) +
    # Required point
    geom_point(data = data.frame(cycle_time = required_cycle_time, median_dppp = required_dppp),
               color = aidia_colors$after_dark, fill = aidia_colors$after, size = 5, shape = 21, stroke = 1.5) +
    annotate("label", x = required_cycle_time, y = required_dppp,
             label = sprintf("Required\n%.2f sec | DPPP %.1f",
                            required_cycle_time, required_dppp),
             hjust = if (ct_change < 0) 1.1 else -0.1, vjust = 0.5,
             size = 3, fontface = "bold", color = aidia_colors$after_dark,
             fill = "white", alpha = 0.85, label.linewidth = 0.3) +
    # Direction arrow
    annotate("segment",
             x = current_cycle_time, xend = required_cycle_time,
             y = min(current_dppp, required_dppp) * 0.85,
             yend = min(current_dppp, required_dppp) * 0.85,
             arrow = arrow(length = unit(0.25, "cm"), type = "closed"),
             color = "gray40", linewidth = 0.8) +
    annotate("text",
             x = (current_cycle_time + required_cycle_time) / 2,
             y = min(current_dppp, required_dppp) * 0.85,
             label = sprintf("Cycle time %s", direction),
             vjust = -0.8, size = 3, color = "gray40") +
    scale_x_continuous(breaks = scales::breaks_pretty(n = 8),
                       expand = expansion(mult = c(0.02, 0.02))) +
    scale_y_continuous(limits = c(0, y_max_dppp),
                       breaks = scales::breaks_pretty(n = 6),
                       expand = expansion(mult = c(0, 0.02))) +
    labs(title = "Acquisition Diagnosis: DPPP & Satisfaction vs Cycle Time",
         subtitle = sprintf(
           "DPPP = 1.7 \u00d7 FWHM / cycle_time | Median FWHM: %.1f sec | %s precursors",
           median(fwhm_sec), format(length(fwhm_sec), big.mark = ",")),
         y = "Median DPPP") +
    theme_aidia() +
    theme(axis.title.x = element_blank(),
          axis.text.x = element_blank(),
          axis.ticks.x = element_blank(),
          plot.margin = margin(5, 10, 0, 10))

  # --- Bottom Panel: Satisfaction vs Cycle Time ---
  p_bottom <- ggplot(curve_data, aes(x = cycle_time, y = satisfaction_pct)) +
    geom_hline(yintercept = target_satisfaction, linetype = "dashed",
               color = "gray50", linewidth = 0.6) +
    annotate("text", x = ct_range[1], y = target_satisfaction,
             label = sprintf("Target: %.0f%%", target_satisfaction),
             hjust = -0.1, vjust = -0.5, size = 3, fontface = "bold",
             color = "gray50") +
    geom_vline(xintercept = required_cycle_time, linetype = "dotted",
               color = aidia_colors$after, linewidth = 0.6) +
    geom_line(color = aidia_colors$primary, linewidth = 1.5, alpha = 0.8) +
    # Current point
    geom_point(data = data.frame(cycle_time = current_cycle_time,
                                  satisfaction_pct = current_sat),
               color = aidia_colors$before_dark, fill = aidia_colors$before, size = 4.5, shape = 21, stroke = 1.5) +
    annotate("label", x = current_cycle_time, y = current_sat,
             label = sprintf("%.0f%%", current_sat),
             hjust = if (current_cycle_time > required_cycle_time) -0.1 else 1.1,
             vjust = 0.5, size = 3.2, fontface = "bold", color = aidia_colors$before_dark,
             fill = "white", alpha = 0.85, label.linewidth = 0.3) +
    # Required point
    geom_point(data = data.frame(cycle_time = required_cycle_time,
                                  satisfaction_pct = required_sat),
               color = aidia_colors$after_dark, fill = aidia_colors$after, size = 4.5, shape = 21, stroke = 1.5) +
    annotate("label", x = required_cycle_time, y = required_sat,
             label = sprintf("%.0f%%", required_sat),
             hjust = if (current_cycle_time > required_cycle_time) 1.1 else -0.1,
             vjust = 0.5, size = 3.2, fontface = "bold", color = aidia_colors$after_dark,
             fill = "white", alpha = 0.85, label.linewidth = 0.3) +
    scale_x_continuous(breaks = scales::breaks_pretty(n = 8),
                       expand = expansion(mult = c(0.05, 0.05))) +
    scale_y_continuous(breaks = seq(0, 100, by = 10), limits = c(0, 100),
                       expand = expansion(mult = c(0.02, 0.02))) +
    labs(x = "Cycle Time (seconds)",
         y = sprintf("Satisfaction (DPPP >= %.1f)", target_dppp),
         caption = sprintf(
           "Target: DPPP >= %.1f, Satisfaction >= %.0f%% | Shorter cycle time = higher DPPP",
           target_dppp, target_satisfaction)) +
    theme_aidia() +
    theme(plot.margin = margin(0, 10, 5, 10))

  # --- Combine with shared x-axis ---
  combined <- gridExtra::arrangeGrob(p_top, p_bottom,
                                      ncol = 1, heights = c(1.1, 1))
  return(combined)
}


# =============================================================================
# Plot 1B Table: Acquisition Diagnosis Summary Table
# =============================================================================

#' Acquisition Diagnosis Summary Table
#'
#' Creates a clean Before/After comparison table showing key acquisition
#' metrics: cycle time, DPPP, satisfaction, and window count. Designed
#' for PDF report where clarity trumps visual flair.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return gtable (gridExtra::tableGrob)
#' @keywords internal
plot_dppp_diagnosis_table <- function(optimization_plan, validated_data) {

  cat("  Generating Plot 1B: Acquisition Diagnosis Table...\n")

  inputs <- extract_dppp_inputs(optimization_plan, validated_data)
  fwhm_sec <- inputs$fwhm_data$FWHM_sec
  target_dppp <- inputs$target_dppp
  current_ct <- inputs$current_cycle_time
  required_ct <- inputs$required_cycle_time

  # Calculate metrics at both operating points (compute each DPPP vector once)
  km <- compute_dppp_key_metrics(fwhm_sec, current_ct, required_ct, target_dppp)
  current_dppp  <- km$current_dppp
  required_dppp <- km$required_dppp
  current_sat   <- km$current_sat
  required_sat  <- km$required_sat

  target_satisfaction <- (optimization_plan$parameters$target_satisfaction %||% 0.7) * 100
  n_precursors <- length(fwhm_sec)
  median_fwhm  <- median(fwhm_sec, na.rm = TRUE)
  window_count <- optimization_plan$window_count_per_bin

  # Build table data
  table_data <- data.frame(
    Metric = c(
      "Cycle Time (sec)",
      "Median DPPP",
      sprintf("Satisfaction (DPPP >= %.1f)", target_dppp),
      "Windows per RT Bin"
    ),
    Current = c(
      sprintf("%.2f", current_ct),
      sprintf("%.1f", current_dppp),
      sprintf("%.1f%%", current_sat),
      "\u2014"
    ),
    Required = c(
      sprintf("%.2f", required_ct),
      sprintf("%.1f", required_dppp),
      sprintf("%.1f%%", required_sat),
      as.character(window_count)
    ),
    Target = c(
      "\u2014",
      sprintf(">= %.1f", target_dppp),
      sprintf(">= %.0f%%", target_satisfaction),
      "\u2014"
    ),
    stringsAsFactors = FALSE
  )

  # Verdict column
  table_data$Verdict <- c(
    ifelse(required_ct <= current_ct, "Feasible", "Needs longer CT"),
    ifelse(required_dppp >= target_dppp, "Met", "Not met"),
    ifelse(required_sat >= target_satisfaction, "Met", "Not met"),
    ""
  )

  # Create styled table grob
  table_grob <- gridExtra::tableGrob(
    table_data,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core = list(
        fg_params = list(fontsize = 11, col = aidia_colors$primary,
                          hjust = 0, x = 0.05),
        bg_params = list(
          fill = c(rep(c("white", aidia_colors$grid), length.out = nrow(table_data))),
          col = aidia_colors$grid, lwd = 0.5
        )
      ),
      colhead = list(
        fg_params = list(fontsize = 12, col = "white", fontface = "bold",
                          hjust = 0, x = 0.05),
        bg_params = list(fill = aidia_colors$primary, col = "white", lwd = 1)
      )
    )
  )

  # Wrap in a page with title and context
  title_grob <- grid::textGrob(
    "Acquisition Diagnosis",
    gp = grid::gpar(fontsize = 18, fontface = "bold", col = aidia_colors$primary)
  )
  subtitle_grob <- grid::textGrob(
    sprintf(
      "DPPP = 1.7 x FWHM / cycle_time | Median FWHM: %.1f sec | %s precursors",
      median_fwhm, format(n_precursors, big.mark = ",")
    ),
    gp = grid::gpar(fontsize = 11, col = aidia_colors$secondary)
  )

  # Direction note
  ct_change <- required_ct - current_ct
  direction_text <- if (ct_change < 0) {
    sprintf("Cycle time must decrease by %.2f sec (%.0f%%) to meet targets",
            abs(ct_change), abs(ct_change) / current_ct * 100)
  } else {
    sprintf("Cycle time can increase by %.2f sec -- targets already met at current settings",
            ct_change)
  }
  direction_grob <- grid::textGrob(
    direction_text,
    gp = grid::gpar(fontsize = 11, fontface = "italic", col = aidia_colors$secondary)
  )

  combined <- gridExtra::arrangeGrob(
    title_grob,
    subtitle_grob,
    table_grob,
    direction_grob,
    ncol = 1,
    heights = grid::unit(c(1.2, 0.8, 4, 0.8), "null"),
    padding = grid::unit(1, "lines")
  )

  return(combined)
}

