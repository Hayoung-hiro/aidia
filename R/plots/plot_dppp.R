# plot_dppp.R - DPPP Distribution Visualization Functions
#
# Purpose: Generate DPPP distribution comparison plots (current vs recommended)
#
# Functions:
#   - plot_dppp_comparison(): Simple dual density plot
#   - plot_dppp_comparison_enhanced(): Enhanced version with visual annotations
#
# Dependencies: ggplot2, dplyr, tidyr, utils_common.R (calculate_dppp)

library(ggplot2)
library(dplyr)
library(tidyr)

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
      mutate(FWHM_sec = FWHM * 60)
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
#' @export
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
    "DPPP = (FWHM × 1.7) / cycle_time\n\nCurrent State:\n  Median FWHM: %.1f sec\n  Cycle time: %.1f sec\n  Satisfaction: %.1f%%\n\nRecommended:\n  Cycle time: %.1f sec\n  Expected satisfaction: %.1f%%+\n\nTotal precursors: %s",
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
      values = c("steelblue", "coral"),
      name = "Cycle Time"
    ) +
    scale_color_manual(
      values = c("steelblue4", "coral4"),
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
    theme_dia_optimizer() +
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
# Plot 1B: DPPP Distribution Comparison (Enhanced Version)
# =============================================================================

#' Plot DPPP Distribution: Enhanced Version with Visual Annotations
#'
#' Enhanced version of plot_dppp_comparison() with additional visual elements:
#' - Target region highlighting (satisfied zone)
#' - Median DPPP vertical lines for both conditions
#' - Shift arrow showing DPPP improvement
#' - Clearer visual separation of satisfied/unsatisfied regions
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_dppp_comparison_enhanced <- function(optimization_plan, validated_data) {

  cat("  Generating Plot 1 Enhanced: DPPP Distribution with Visual Annotations...\n")

  inputs <- extract_dppp_inputs(optimization_plan, validated_data)
  current_cycle_time <- inputs$current_cycle_time
  required_cycle_time <- inputs$required_cycle_time
  target_dppp <- inputs$target_dppp
  fwhm_data <- inputs$fwhm_data

  if (nrow(fwhm_data) < 2) {
    return(create_insufficient_data_plot(
      title = "DPPP Distribution Comparison (Enhanced)",
      message = "Insufficient data for density plot\n(need at least 2 precursors)"
    ))
  }

  # Calculate current and expected DPPP
  dppp_data <- fwhm_data %>%
    mutate(
      current_dppp = calculate_dppp(FWHM_sec, current_cycle_time),
      expected_dppp = calculate_dppp(FWHM_sec, required_cycle_time)
    )

  # Calculate median DPPP for both conditions
  median_current_dppp <- median(dppp_data$current_dppp, na.rm = TRUE)
  median_expected_dppp <- median(dppp_data$expected_dppp, na.rm = TRUE)
  dppp_shift <- median_expected_dppp - median_current_dppp

  # Reshape for plotting
  dppp_plot_data <- dppp_data %>%
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
          sprintf("Current (%.2f sec)", current_cycle_time),
          sprintf("Recommended (%.2f sec)", required_cycle_time)
        )
      )
    )

  # Calculate statistics for annotation
  median_fwhm_sec <- median(fwhm_data$FWHM_sec)
  n_precursors <- nrow(validated_data$data)
  current_satisfaction <- optimization_plan$diagnosis$current_satisfaction_ratio * 100

  # Calculate expected satisfaction
  expected_satisfaction <- sum(dppp_plot_data$condition == levels(dppp_plot_data$condition)[2] &
                                dppp_plot_data$dppp >= target_dppp) /
                           (n_precursors) * 100

  # Create annotation text
  annotation_text <- sprintf(
    "DPPP = (FWHM × 1.7) / cycle_time\n\nCurrent State:\n  Median FWHM: %.1f sec\n  Cycle time: %.1f sec\n  Median DPPP: %.2f\n  Satisfaction: %.1f%%\n\nRecommended:\n  Cycle time: %.1f sec\n  Median DPPP: %.2f\n  Expected satisfaction: %.1f%%+\n\nDPPP Improvement: +%.2f\nTotal precursors: %s",
    median_fwhm_sec,
    current_cycle_time,
    median_current_dppp,
    current_satisfaction,
    required_cycle_time,
    median_expected_dppp,
    expected_satisfaction,
    dppp_shift,
    format(n_precursors, big.mark = ",")
  )

  # Create enhanced plot
  p <- ggplot(dppp_plot_data, aes(x = dppp, fill = condition, color = condition)) +
    # Background: Target satisfied region (green zone)
    annotate(
      "rect",
      xmin = target_dppp, xmax = 15,
      ymin = 0, ymax = Inf,
      fill = "green", alpha = 0.05
    ) +
    annotate(
      "text",
      x = target_dppp + 0.5,
      y = Inf,
      label = "Satisfied Region",
      hjust = 0,
      vjust = 3,
      size = 3,
      color = "darkgreen",
      fontface = "italic"
    ) +
    # Main density curves
    geom_density(alpha = 0.3, linewidth = 1.2) +
    # Target DPPP line
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
    # Median lines with values
    geom_vline(
      xintercept = median_current_dppp,
      linetype = "dotted",
      color = "steelblue4",
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = median_current_dppp,
      y = 0,
      label = sprintf("Current\nMedian: %.2f", median_current_dppp),
      hjust = 0.5,
      vjust = -0.5,
      size = 3,
      color = "steelblue4",
      fontface = "bold"
    ) +
    geom_vline(
      xintercept = median_expected_dppp,
      linetype = "dotted",
      color = "coral4",
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = median_expected_dppp,
      y = 0,
      label = sprintf("Recommended\nMedian: %.2f", median_expected_dppp),
      hjust = 0.5,
      vjust = -0.5,
      size = 3,
      color = "coral4",
      fontface = "bold"
    ) +
    # Shift arrow between medians
    annotate(
      "segment",
      x = median_current_dppp + 0.3,
      xend = median_expected_dppp - 0.3,
      y = 0.05,
      yend = 0.05,
      arrow = arrow(length = unit(0.3, "cm"), type = "closed"),
      color = "black",
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = (median_current_dppp + median_expected_dppp) / 2,
      y = 0.05,
      label = sprintf("Shift: +%.2f DPPP", dppp_shift),
      hjust = 0.5,
      vjust = -0.5,
      size = 3.5,
      fontface = "bold"
    ) +
    # Statistics annotation box
    annotate(
      "text",
      x = Inf,
      y = Inf,
      label = annotation_text,
      hjust = 1.05,
      vjust = 1.05,
      size = 3.2,
      family = "mono",
      lineheight = 0.95
    ) +
    # Scales
    scale_fill_manual(
      values = c("steelblue", "coral"),
      name = "Cycle Time"
    ) +
    scale_color_manual(
      values = c("steelblue4", "coral4"),
      name = "Cycle Time"
    ) +
    scale_x_continuous(
      limits = c(0, 15),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(
      expand = expansion(mult = c(0, 0.1))
    ) +
    # Labels
    labs(
      title = "DPPP Distribution: Current vs Recommended (Enhanced)",
      subtitle = "Optimization reduces cycle time to improve DPPP achievement - with visual annotations",
      x = "DPPP (Data Points Per Peak)",
      y = "Density",
      caption = "Green zone = satisfied region (DPPP >= target); dotted lines = median DPPP"
    ) +
    # Theme
    theme_dia_optimizer() +
    theme(
      legend.position.inside = c(0.02, 0.75),  # ggplot2 3.5.0+ syntax
      legend.position = "inside",
      legend.justification = c(0, 1),
      legend.background = element_rect(fill = "white", color = "gray80"),
      legend.key.size = unit(0.8, "cm"),
      legend.title = element_text(size = 11, face = "bold")
    )

  return(p)
}

cat("  [plot_dppp.R] DPPP distribution functions loaded\n")
