#' Optimization Impact Summary - Before/After Comparison
#'
#' Purpose: Generate a 3-panel dashboard showing the impact of AIDIA
#' optimization: two bar charts (cycle time, DPPP satisfaction) and a
#' configuration/results summary table.
#'
#' Functions:
#'   - plot_optimization_impact(): 3-panel dashboard (2 bars + 1 table)
#'
#' Dependencies: ggplot2, dplyr, gridExtra, grid


# =============================================================================
# Internal: Bar chart for impact comparison
# =============================================================================

#' @keywords internal
.impact_bar_chart <- function(current_value, planned_value, title, y_label,
                              value_format = "%.2f", y_limits = NULL,
                              has_current = TRUE) {
  if (has_current && !is.na(current_value)) {
    df <- data.frame(
      state = factor(c("Current", "Planned"), levels = c("Current", "Planned")),
      value = c(current_value, planned_value),
      fill_color = c(aidia_colors$before_muted, aidia_colors$success)
    )
  } else {
    df <- data.frame(
      state = factor("Planned", levels = "Planned"),
      value = planned_value,
      fill_color = aidia_colors$success
    )
  }

  df$label <- sprintf(value_format, df$value)

  if (is.null(y_limits)) {
    max_val <- max(df$value, na.rm = TRUE)
    y_limits <- c(0, max_val * 1.25)
  }

  ggplot(df, aes(x = state, y = value, fill = fill_color)) +
    geom_col(show.legend = FALSE, width = 0.6) +
    geom_text(aes(label = label), vjust = -0.5, size = 5, fontface = "bold") +
    scale_fill_identity() +
    scale_y_continuous(limits = y_limits, expand = expansion(mult = c(0, 0.05))) +
    labs(title = title, x = NULL, y = y_label) +
    theme_aidia(base_size = 10) +
    theme(
      axis.text.x = element_text(size = 11, face = "bold"),
      panel.grid.major.x = element_blank()
    )
}


# =============================================================================
# Main Plot Function
# =============================================================================

#' Plot Optimization Impact Summary (Before/After Dashboard)
#'
#' Creates a 3-panel dashboard showing the impact of optimization:
#' - Panel 1: Cycle time (current vs planned, or planned only if CT estimated)
#' - Panel 2: DPPP satisfaction (current vs planned, with target line)
#' - Panel 3: Configuration and results summary table
#'
#' When the current cycle time is auto-estimated (not user-provided),
#' the "Current" bar is omitted and only the planned result is shown.
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
#' grid::grid.draw(p)
#' }
plot_optimization_impact <- function(optimization_plan, optimized_windows, validated_data) {

  cat("  Generating Optimization Impact Summary...\n")

  # --- Extract metrics via shared accessor ---
  m <- extract_before_after_metrics(optimization_plan, optimized_windows)
  has_current <- !isTRUE(optimization_plan$diagnosis$current_ct_is_estimated)

  # Planned cycle time
  planned_ct <- m$new_ct
  current_ct <- if (has_current) m$orig_ct else NA_real_

  # DPPP satisfaction
  target_dppp <- m$target_dppp
  target_sat <- m$target_satisfaction
  if (is.na(target_sat)) target_sat <- 0.70

  fwhm_sec <- ensure_fwhm_seconds(validated_data$data$FWHM)

  # Planned satisfaction
  dppp_planned <- calculate_dppp(fwhm_sec, planned_ct)
  planned_sat_pct <- dppp_satisfaction_pct(dppp_planned, target_dppp)
  planned_dppp_median <- median(dppp_planned, na.rm = TRUE)

  # Current satisfaction (only when user-provided CT)
  current_sat_pct <- NA_real_
  if (has_current) {
    dppp_current <- calculate_dppp(fwhm_sec, current_ct)
    current_sat_pct <- dppp_satisfaction_pct(dppp_current, target_dppp)
  }

  # --- Panel 1: Cycle Time ---
  p1 <- .impact_bar_chart(
    current_value = current_ct,
    planned_value = planned_ct,
    title = "Cycle Time",
    y_label = "Seconds",
    value_format = "%.2f s",
    has_current = has_current
  )

  # --- Panel 2: DPPP Satisfaction ---
  p2 <- .impact_bar_chart(
    current_value = current_sat_pct,
    planned_value = planned_sat_pct,
    title = "DPPP Satisfaction",
    y_label = "%",
    value_format = "%.1f%%",
    y_limits = c(0, 118),
    has_current = has_current
  ) +
    geom_hline(
      yintercept = target_sat * 100,
      linetype = "dashed",
      color = aidia_colors$accent,
      linewidth = 0.8
    ) +
    annotate(
      "text",
      x = if (has_current) 1.5 else 1,
      y = target_sat * 100,
      label = sprintf("Target: %.0f%%", target_sat * 100),
      vjust = -0.5, size = 3.5, fontface = "bold",
      color = aidia_colors$accent
    )

  # --- Panel 3: Metrics Table ---
  windows <- optimized_windows$windows
  n_rt_bins <- length(unique(windows$rt_segment_id))
  rt_bin_width <- optimized_windows$parameters$rt_bin_width_min %||% NA_real_
  fz_offset <- optimized_windows$parameters$fz_offset %||% 0

  # Verdict
  sat_met <- planned_sat_pct >= (target_sat * 100)

  table_data <- data.frame(
    Metric = c(
      "Instrument",
      "Strategy",
      "Window Mode",
      "Total Windows",
      "RT Bins",
      "Mean Width",
      "Median DPPP",
      "Coverage",
      "FZ Offset",
      "Verdict"
    ),
    Value = c(
      sprintf("%s (%s)",
              optimization_plan$instrument$name %||% "N/A",
              optimization_plan$instrument$cycle_mode %||% "sequential"),
      format_strategy_label(m$strategy),
      tools::toTitleCase(m$window_mode),
      if (!is.na(m$windows_per_bin)) {
        sprintf("%s (%d/bin)", format(m$n_windows, big.mark = ","), m$windows_per_bin)
      } else {
        format(m$n_windows, big.mark = ",")
      },
      if (!is.na(rt_bin_width)) {
        sprintf("%d (%.1f min)", n_rt_bins, rt_bin_width)
      } else {
        as.character(n_rt_bins)
      },
      sprintf("%.1f Da", m$mean_width),
      sprintf("%.1f", planned_dppp_median),
      if (!is.na(m$coverage_pct) && m$coverage_pct > 0) {
        sprintf("%.1f%%", m$coverage_pct)
      } else {
        "N/A"
      },
      if (fz_offset > 0) sprintf("%.2f Da", fz_offset) else "Off",
      if (sat_met) "TARGET MET" else "TARGET NOT MET"
    ),
    stringsAsFactors = FALSE
  )

  # Table styling (matching S2_04 dark-header style)
  n_r <- nrow(table_data)
  fg_colors <- rep("black", n_r)
  fg_colors[n_r] <- if (sat_met) aidia_colors$success else aidia_colors$accent

  tbl <- gridExtra::tableGrob(
    table_data,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core = list(
        fg_params = list(fontsize = 11, col = fg_colors,
                         hjust = 0, x = 0.05),
        bg_params = list(
          fill = rep(c("white", "gray95"), length.out = n_r),
          col = "gray85", lwd = 0.5
        )
      ),
      colhead = list(
        fg_params = list(fontsize = 12, col = "white", fontface = "bold",
                         hjust = 0, x = 0.05),
        bg_params = list(fill = "gray20", col = "white", lwd = 1)
      )
    )
  )

  # --- Assemble 3-panel layout ---
  title_grob <- grid::textGrob(
    "Optimization Impact Summary",
    gp = grid::gpar(fontsize = 16, fontface = "bold"),
    vjust = 0.5
  )

  composite <- gridExtra::arrangeGrob(
    title_grob, p1, p2, tbl,
    ncol = 2,
    layout_matrix = rbind(c(1, 1), c(2, 3), c(4, 4)),
    heights = grid::unit(c(0.07, 0.38, 0.55), "npc")
  )

  return(composite)
}
