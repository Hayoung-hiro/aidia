# plot_dppp_distribution.R
# Plot 15: Per-Precursor DPPP Distribution (Before vs After)
#
# Purpose: Show the full distribution of DPPP values across all precursors,
#          comparing before (current) vs after (optimized) cycle time.
#          Reveals whether under-sampled precursors are marginally or severely
#          below the target — information hidden by the satisfaction ratio alone.
#
# Dependencies: ggplot2, dplyr


#' Plot Per-Precursor DPPP Distribution (Before vs After)
#'
#' Creates overlapping density curves of per-precursor DPPP values for
#' the current and optimized cycle times. Highlights the target threshold
#' and shades the under-sampled region.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_dppp_distribution <- function(optimization_plan, validated_data) {

  cat("  Generating Plot 15: Per-Precursor DPPP Distribution...\n")

  # Extract parameters
  fwhm_sec <- ensure_fwhm_seconds(validated_data$data$FWHM)
  target_dppp <- optimization_plan$parameters$target_dppp
  before_cycle <- optimization_plan$diagnosis$current_cycle_time_sec
  after_cycle <- optimization_plan$required_cycle_time_sec

  # Calculate per-precursor DPPP for both conditions
  dppp_before <- calculate_dppp(fwhm_sec, before_cycle)
  dppp_after <- calculate_dppp(fwhm_sec, after_cycle)

  # Guard: need at least 2 data points for density

  if (length(dppp_before) < 2 || length(dppp_after) < 2) {
    return(create_insufficient_data_plot(
      title = "Per-Precursor DPPP Distribution",
      message = "Insufficient data\n(need at least 2 precursors)"
    ))
  }

  # Build combined data frame
  df <- rbind(
    data.frame(dppp = dppp_before, condition = "Before (Current)"),
    data.frame(dppp = dppp_after, condition = "After (Optimized)")
  )
  df$condition <- factor(df$condition, levels = c("Before (Current)", "After (Optimized)"))

  # Satisfaction stats for subtitle
  sat_before <- mean(dppp_before >= target_dppp, na.rm = TRUE) * 100
  sat_after <- mean(dppp_after >= target_dppp, na.rm = TRUE) * 100

  # Clip x-axis for readability (0 to 3x target or max, whichever is larger)
  x_max <- max(quantile(dppp_after, 0.99, na.rm = TRUE), target_dppp * 3)

  p <- ggplot(df, aes(x = dppp, fill = condition, color = condition)) +
    # Density curves
    geom_density(alpha = 0.35, linewidth = 0.8) +
    # Target threshold line
    geom_vline(
      xintercept = target_dppp,
      linetype = "dashed",
      color = aidia_colors$accent,
      linewidth = 0.9
    ) +
    # Target label
    annotate(
      "text",
      x = target_dppp,
      y = Inf,
      label = sprintf("Target: %.1f DPPP", target_dppp),
      vjust = 2,
      hjust = -0.05,
      size = 3.5,
      fontface = "bold",
      color = aidia_colors$accent
    ) +
    # Color scheme
    scale_fill_manual(
      values = c(
        "Before (Current)" = aidia_colors$before_muted,
        "After (Optimized)" = aidia_colors$success
      )
    ) +
    scale_color_manual(
      values = c(
        "Before (Current)" = aidia_colors$before_muted_dark,
        "After (Optimized)" = aidia_colors$after_success
      )
    ) +
    scale_x_continuous(
      limits = c(0, x_max),
      expand = expansion(mult = c(0, 0.02))
    ) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    labs(
      title = "Per-Precursor DPPP Distribution",
      subtitle = sprintf(
        "Before: %.1f%% satisfied | After: %.1f%% satisfied (target \u2265 %.1f)",
        sat_before, sat_after, target_dppp
      ),
      x = "Data Points Per Peak (DPPP)",
      y = "Density",
      fill = "Condition",
      color = "Condition"
    ) +
    theme_aidia() +
    theme(
      legend.position = "top",
      legend.title = element_text(face = "bold"),
      panel.grid.minor = element_blank()
    )

  return(p)
}
