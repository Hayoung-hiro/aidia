# export_plots.R - Export Functions for Stage 4 Visualization
#
# Purpose: Handle export of plots and PDF reports
#
# Functions:
#   - export_individual_plots(): Export plots to individual files
#   - create_pdf_report(): Create multi-panel PDF report
#
# Dependencies: ggplot2, gridExtra, grid


# =============================================================================
# Export Individual Plots
# =============================================================================

#' Export Individual Plots
#'
#' Exports each plot in the list to individual files with the specified format.
#'
#' @param plots List of ggplot objects (must be named)
#' @param output_dir Output directory path
#' @param format File format: "png" or "pdf" (default: "png")
#' @param dpi Resolution in DPI (default: 300)
#'
#' @return Vector of file paths
#' @export
export_individual_plots <- function(plots, output_dir, format = "png", dpi = 300) {

  # Use plot names directly from the list
  # This makes it flexible and handles dynamically generated plots
  plot_names <- names(plots)

  if (is.null(plot_names) || length(plot_names) == 0) {
    stop("Plot list must have named elements")
  }

  file_paths <- character(length(plots))

  for (i in seq_along(plots)) {
    filename <- paste0(plot_names[i], ".", format)
    filepath <- file.path(output_dir, filename)

    ggsave(
      filepath,
      plot = plots[[i]],
      width = 10,
      height = 7,
      dpi = dpi,
      bg = "white"
    )

    file_paths[i] <- filepath
    cat(sprintf("  OK Saved: %s\n", filename))
  }

  return(file_paths)
}

# =============================================================================
# PDF Report Helpers
# =============================================================================

# Colors: use aidia_colors from theme_aidia.R (shared package namespace)

#' Draw Cover Page
#' @keywords internal
.draw_cover_page <- function(optimization_plan, optimized_windows, validated_data) {
  grid::grid.newpage()

  # Background accent bar at top
  grid::grid.rect(x = 0, y = 1, width = 1, height = 0.08,
            just = c("left", "top"),
            gp = grid::gpar(fill = aidia_colors$primary, col = NA))

  # Title
  grid::grid.text("AIDIA",
            x = 0.5, y = 0.72,
            gp = grid::gpar(fontsize = 42, fontface = "bold",
                       col = aidia_colors$primary))
  # Version from package metadata
  pkg_version <- tryCatch(
    as.character(utils::packageVersion("aidia")),
    error = function(e) "dev"
  )
  grid::grid.text(sprintf("Adaptive Isolation for DIA  v%s", pkg_version),
            x = 0.5, y = 0.65,
            gp = grid::gpar(fontsize = 16, col = aidia_colors$secondary))

  # Divider line
  grid::grid.lines(x = c(0.3, 0.7), y = c(0.60, 0.60),
             gp = grid::gpar(col = aidia_colors$accent, lwd = 2))

  # Subtitle
  grid::grid.text("Window Optimization Report",
            x = 0.5, y = 0.55,
            gp = grid::gpar(fontsize = 20, fontface = "bold",
                       col = aidia_colors$primary))

  # Key metrics (centered block) — guard all values for NULL safety
  instrument <- optimization_plan$instrument$preset %||% "custom"
  n_windows <- nrow(optimized_windows$windows) %||% 0L
  coverage <- as.numeric(optimized_windows$statistics$coverage_percentage %||% 0)[1]
  n_precursors <- format(validated_data$metadata$n_precursors %||% 0, big.mark = ",")
  mz_strategy <- optimized_windows$parameters$mz_strategy %||% "unknown"
  window_mode <- optimized_windows$parameters$window_mode %||% "unknown"

  # Dataset identifier from gradient name if available
  gradient_name <- optimized_windows$metadata$gradient_name %||%
                   validated_data$metadata$gradient_name %||% NULL

  metrics <- c(
    if (!is.null(gradient_name)) sprintf("Dataset: %s", gradient_name),
    sprintf("Instrument: %s", instrument),
    sprintf("Precursors: %s", n_precursors),
    sprintf("Strategy: %s | Mode: %s", mz_strategy, window_mode),
    sprintf("Windows: %d | Coverage: %.1f%%", n_windows, coverage)
  )

  for (i in seq_along(metrics)) {
    grid::grid.text(metrics[i],
              x = 0.5, y = 0.44 - (i - 1) * 0.05,
              gp = grid::gpar(fontsize = 13, col = aidia_colors$primary))
  }

  # Timestamp at bottom
  grid::grid.text(sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M")),
            x = 0.5, y = 0.15,
            gp = grid::gpar(fontsize = 11, col = aidia_colors$secondary,
                       fontface = "italic"))

  # Bottom bar
  grid::grid.rect(x = 0, y = 0, width = 1, height = 0.04,
            just = c("left", "bottom"),
            gp = grid::gpar(fill = aidia_colors$primary, col = NA))
}

#' Draw Section Divider Page
#' @keywords internal
.draw_section_page <- function(section_number, section_title, section_subtitle = NULL) {
  grid::grid.newpage()

  # Left accent bar
  grid::grid.rect(x = 0, y = 0, width = 0.02, height = 1,
            just = c("left", "bottom"),
            gp = grid::gpar(fill = aidia_colors$accent, col = NA))

  # Section number (large, supports numeric or string like "A", "B")
  section_label <- if (is.numeric(section_number)) {
    sprintf("%02d", section_number)
  } else {
    as.character(section_number)
  }
  grid::grid.text(section_label,
            x = 0.12, y = 0.55,
            just = "left",
            gp = grid::gpar(fontsize = 60, fontface = "bold",
                       col = aidia_colors$grid))

  # Section title
  grid::grid.text(section_title,
            x = 0.12, y = 0.45,
            just = "left",
            gp = grid::gpar(fontsize = 22, fontface = "bold",
                       col = aidia_colors$primary))

  # Subtitle
  if (!is.null(section_subtitle)) {
    grid::grid.text(section_subtitle,
              x = 0.12, y = 0.38,
              just = "left",
              gp = grid::gpar(fontsize = 12, col = aidia_colors$secondary,
                         fontface = "italic"))
  }
}

#' Draw Parameter Summary Page
#' @keywords internal
.draw_parameter_summary <- function(optimization_plan, optimized_windows, validated_data) {
  grid::grid.newpage()

  # Header
  grid::grid.text("Configuration Summary",
            x = 0.5, y = 0.95,
            gp = grid::gpar(fontsize = 18, fontface = "bold",
                       col = aidia_colors$primary))

  # Build parameter table
  params <- optimized_windows$parameters
  instrument <- optimization_plan$instrument

  param_data <- data.frame(
    Parameter = c(
      "Instrument Preset",
      "Cycle Time Mode",
      "MS1 Resolution",
      "MS2 Resolution",
      "Target DPPP",
      "Target Satisfaction",
      "m/z Strategy",
      "Window Mode",
      "FZ Offset (Da)",
      "RT Binning Mode",
      "RT Bin Width (min)",
      "Precursors",
      "m/z Range (Da)",
      "RT Range (min)",
      "Total Windows",
      "Windows per RT Bin",
      "Required Cycle Time (s)",
      "Coverage (%)"
    ),
    Value = c(
      instrument$preset %||% "N/A",
      instrument$cycle_calculation_mode %||% "N/A",
      format(instrument$ms1_resolution %||% NA, big.mark = ","),
      format(instrument$ms2_resolution %||% NA, big.mark = ","),
      sprintf("%.1f", optimization_plan$parameters$target_dppp),
      sprintf("%.0f%%", (optimization_plan$parameters$target_satisfaction %||% 0.7) * 100),
      params$mz_strategy %||% "N/A",
      params$window_mode %||% "N/A",
      as.character(params$fz_offset %||% 0.25),
      params$rt_binning_mode %||% "fixed",
      as.character(params$rt_bin_width_min %||% 5),
      format(validated_data$metadata$n_precursors, big.mark = ","),
      sprintf("%.0f - %.0f",
              validated_data$metadata$mz_range[1],
              validated_data$metadata$mz_range[2]),
      sprintf("%.1f - %.1f",
              validated_data$metadata$rt_range[1],
              validated_data$metadata$rt_range[2]),
      format(nrow(optimized_windows$windows), big.mark = ","),
      as.character(optimization_plan$window_count_per_bin),
      sprintf("%.2f", optimization_plan$required_cycle_time_sec),
      sprintf("%.1f", optimized_windows$statistics$coverage_percentage)
    ),
    stringsAsFactors = FALSE
  )

  table_grob <- gridExtra::tableGrob(
    param_data,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core = list(
        fg_params = list(fontsize = 10, col = aidia_colors$primary,
                          hjust = 0, x = 0.05),
        bg_params = list(
          fill = c(rep(c("white", aidia_colors$grid),
                       length.out = nrow(param_data))),
          col = aidia_colors$grid, lwd = 0.5
        )
      ),
      colhead = list(
        fg_params = list(fontsize = 11, col = "white", fontface = "bold",
                          hjust = 0, x = 0.05),
        bg_params = list(fill = aidia_colors$primary, col = "white", lwd = 1)
      )
    )
  )

  # Position table centered with some padding
  grid::pushViewport(grid::viewport(x = 0.5, y = 0.45, width = 0.7, height = 0.8))
  grid::grid.draw(table_grob)
  grid::popViewport()
}

#' Safely render a plot to the PDF device
#' @keywords internal
.render_plot <- function(p) {
  tryCatch({
    if (inherits(p, "grob") || inherits(p, "gTree") || inherits(p, "gtable")) {
      grid::grid.newpage()
      grid::grid.draw(p)
    } else if (inherits(p, "ggplot")) {
      print(p)
    } else {
      # Fallback: try print
      grid::grid.newpage()
      print(p)
    }
  }, error = function(e) {
    grid::grid.newpage()
    grid::grid.text(sprintf("Error rendering plot: %s", e$message),
              x = 0.5, y = 0.5,
              gp = grid::gpar(fontsize = 12, col = aidia_colors$accent))
  })
}

#' Emit all matching plots for a given set of keys
#' @keywords internal
.emit_section_plots <- function(plots, keys) {
  n_emitted <- 0
  for (key in keys) {
    if (key %in% names(plots)) {
      .render_plot(plots[[key]])
      n_emitted <- n_emitted + 1
    }
  }
  n_emitted
}

#' Emit plots matching a name prefix pattern
#' @keywords internal
.emit_plots_by_prefix <- function(plots, prefix) {
  matching <- grep(paste0("^", prefix), names(plots), value = TRUE)
  n_emitted <- 0
  for (key in matching) {
    .render_plot(plots[[key]])
    n_emitted <- n_emitted + 1
  }
  n_emitted
}


# =============================================================================
# Create PDF Report (Structured)
# =============================================================================

#' Create Structured PDF Report
#'
#' Creates a professionally structured AIDIA optimization report with
#' cover page, parameter summary, and logically grouped plot sections.
#'
#' Report Structure (narrative-driven decision flow):
#'   Cover Page (AIDIA branding + key metrics)
#'   Executive Summary (target-oriented scorecard with verdict)
#'   Configuration Summary (parameter table)
#'   S1. Input Data Characterization (heatmap, FWHM, charge)
#'   S2. Acquisition Diagnosis (DPPP enhanced, distribution, satisfaction)
#'   S3. Optimized Window Layout (Gantt, density overlay, load balance)
#'   S4. Optimization Validation (impact summary, edge proximity, FZ zoom)
#'   S5. Strategy Comparison (conditional: only when >= 2 strategies)
#'   A. Detailed Per-Strategy Analysis (appendix)
#'   B. Adaptive RT Binning (conditional, only if adaptive mode)
#'
#' @param plots Named list of ggplot/grob objects from generate_visualizations()
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_file PDF output path
#'
#' @export
create_pdf_report <- function(plots, validated_data, optimization_plan,
                               optimized_windows, output_file) {

  cat("  Building structured PDF report...\n")
  n_pages <- 0

  pdf(output_file, width = 16, height = 10)
  on.exit(dev.off(), add = TRUE)

  # --- Cover Page ---
  .draw_cover_page(optimization_plan, optimized_windows, validated_data)
  n_pages <- n_pages + 1

  # --- Executive Summary (moved before Parameter Summary — pyramid principle) ---
  .draw_executive_summary(optimization_plan, optimized_windows, validated_data)
  n_pages <- n_pages + 1

  # --- Parameter Summary ---
  .draw_parameter_summary(optimization_plan, optimized_windows, validated_data)
  n_pages <- n_pages + 1

  # --- Section 1: Input Data Characterization ---
  # Broadest overview first (heatmap), then single-variable deep-dive (FWHM), then complexity
  .draw_section_page(1, "Input Data Characterization",
                     "Chromatographic quality, precursor landscape, and sample complexity")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot2_rt_mz_density_heatmap",
    "plot0_fwhm_distribution",
    "plot19_charge_mz"
  ))
  n_pages <- n_pages + n

  # --- Section 2: Acquisition Diagnosis ---
  # DPPP distribution + satisfaction trade-off (Plot 15 removed — redundant with 1B)
  .draw_section_page(2, "Acquisition Diagnosis",
                     "Current DPPP status and cycle time trade-off space")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot1b_dppp_diagnosis_table"
  ))
  n_pages <- n_pages + n

  # --- Section 3: Optimized Window Layout ---
  # Overview (heatmap + m/z range overlay), then dense bin detail, then load balance
  .draw_section_page(3, "Optimized Window Layout",
                     "Isolation window design, density-adaptive boundaries, and precursor load distribution")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot2c_heatmap_with_mz_range",
    "plot16_load_balance"
  ))
  n_pages <- n_pages + n

  # --- Section 4: Optimization Validation ---
  # Target achievement (6B moved here), boundary safety, forbidden zone
  validation_keys <- c("plot6b_impact_summary",
                       "plot17_edge_proximity",
                       "plot14_fz_zoom")
  if (any(validation_keys %in% names(plots))) {
    .draw_section_page(4, "Optimization Validation",
                       "Target achievement, boundary safety, and forbidden zone verification")
    n_pages <- n_pages + 1
    n <- .emit_section_plots(plots, validation_keys)
    n_pages <- n_pages + n
  }

  # --- Section 5: Strategy Comparison (CONDITIONAL: only when >= 2 strategies) ---
  strategy_keys <- c("plot8d_strategy_comparison_table",
                     "plot8a_strategy_width_ridge",
                     "plot18_strategy_radar")
  if (any(strategy_keys %in% names(plots))) {
    .draw_section_page(5, "Strategy Comparison",
                       "Multi-strategy performance comparison across quality dimensions")
    n_pages <- n_pages + 1
    n <- .emit_section_plots(plots, strategy_keys)
    n_pages <- n_pages + n
  }

  # --- Appendix A: Detailed Per-Strategy Analysis ---
  # Plot 7/7B removed — single-strategy views don't enable comparison;
  # Ridge (8A) + Radar (18) provide cross-strategy comparison in Section 4
  per_strategy_keys <- grep("^plot4_", names(plots), value = TRUE)
  per_strategy_keys <- setdiff(per_strategy_keys, "plot4e_mz_width_all_strategies")
  if (length(per_strategy_keys) > 0) {
    .draw_section_page("A", "Detailed Per-Strategy Analysis",
                       "Per-strategy m/z excluded regions and coverage maps")
    n_pages <- n_pages + 1

    # Strategy m/z width comparison (grouped bar chart)
    n <- .emit_section_plots(plots, c(
      "plot4e_mz_width_all_strategies"
    ))
    n_pages <- n_pages + n

    # Per-strategy plots in order
    for (key in per_strategy_keys) {
      .render_plot(plots[[key]])
      n_pages <- n_pages + 1
    }
  }

  # --- Appendix B: Adaptive RT Binning (conditional) ---
  adaptive_keys <- grep("^plot11", names(plots), value = TRUE)
  if (length(adaptive_keys) > 0) {
    .draw_section_page("B", "Adaptive RT Binning",
                       "Change point detection validation and KS statistic trace")
    n_pages <- n_pages + 1
    for (key in adaptive_keys) {
      .render_plot(plots[[key]])
      n_pages <- n_pages + 1
    }
  }

  cat(sprintf("  OK PDF report saved: %s (%d pages)\n", basename(output_file), n_pages))
}


# =============================================================================
# Executive Summary — Target-Oriented Scorecard
# =============================================================================

#' Draw a single metric tile in the scorecard grid
#' @keywords internal
.draw_metric_tile <- function(label, target_text, actual_text, verdict = NULL,
                              x, y, w = 0.22, h = 0.14) {
  # Tile background
  grid::grid.rect(x = x, y = y, width = w, height = h,
            gp = grid::gpar(fill = "#f8f9fa", col = "#dee2e6", lwd = 1))
  # Label

  grid::grid.text(label, x = x, y = y + h * 0.35,
            gp = grid::gpar(fontsize = 11, fontface = "bold",
                       col = aidia_colors$primary))
  # Target line (if provided)
  if (!is.null(target_text) && nchar(target_text) > 0) {
    grid::grid.text(target_text, x = x, y = y + h * 0.05,
              gp = grid::gpar(fontsize = 10, col = aidia_colors$secondary))
  }
  # Actual value
  grid::grid.text(actual_text, x = x, y = y - h * 0.2,
            gp = grid::gpar(fontsize = 12, fontface = "bold",
                       col = aidia_colors$primary))
  # Verdict badge (check/cross)
  if (!is.null(verdict)) {
    badge_col <- if (verdict) aidia_colors$success else aidia_colors$warning
    badge_text <- if (verdict) "Met" else "Not met"
    grid::grid.text(badge_text, x = x, y = y - h * 0.42,
              gp = grid::gpar(fontsize = 9, fontface = "bold", col = badge_col))
  }
}

#' Draw Executive Summary Scorecard
#'
#' Target-oriented scorecard showing verdict + 2x3 metric tiles +
#' conditional recommendation. Replaces the previous narrative paragraphs.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1 (for satisfaction calc)
#'
#' @keywords internal
.draw_executive_summary <- function(optimization_plan, optimized_windows,
                                    validated_data = NULL) {
  grid::grid.newpage()

  # Header
  grid::grid.text("Executive Summary",
            x = 0.5, y = 0.95,
            gp = grid::gpar(fontsize = 18, fontface = "bold",
                       col = aidia_colors$primary))

  # Extract metrics via shared accessor
  m <- extract_before_after_metrics(optimization_plan, optimized_windows)

  # Calculate after-optimization satisfaction
  after_sat <- NA_real_
  if (!is.null(validated_data) && !is.na(m$new_ct) && !is.na(m$target_dppp)) {
    fwhm_sec <- ensure_fwhm_seconds(get_precursor_data(validated_data)$FWHM)
    dppp_vals <- calculate_dppp(fwhm_sec, m$new_ct)
    after_sat <- dppp_satisfaction_pct(dppp_vals, m$target_dppp) / 100  # fraction
  }
  target_sat <- m$target_satisfaction
  if (is.na(target_sat)) target_sat <- 0.7  # fallback default

  # --- Verdict Banner ---
  sat_met <- !is.na(after_sat) && after_sat >= target_sat
  dppp_met <- !is.na(m$new_dppp) && !is.na(m$target_dppp) && m$new_dppp >= m$target_dppp

  verdict_text <- if (sat_met) "TARGET CONDITIONS MET" else "TARGET NOT FULLY MET"
  verdict_col <- if (sat_met) aidia_colors$success else aidia_colors$warning
  verdict_bg <- if (sat_met) "#e8f8f5" else "#fef9e7"
  verdict_border <- if (sat_met) aidia_colors$success else aidia_colors$warning

  # Verdict box
  grid::grid.rect(x = 0.5, y = 0.83, width = 0.6, height = 0.08,
            gp = grid::gpar(fill = verdict_bg, col = verdict_border, lwd = 2))
  grid::grid.text(verdict_text, x = 0.5, y = 0.83,
            gp = grid::gpar(fontsize = 16, fontface = "bold", col = verdict_col))

  # --- 2x3 Metric Tiles ---
  # Row 1 (y = 0.66): Target DPPP, Satisfaction, Coverage
  # Row 2 (y = 0.48): Cycle Time, Windows, Mean Width
  tile_x <- c(0.22, 0.50, 0.78)  # 3 columns

  # Row 1
  .draw_metric_tile(
    label = "Target DPPP",
    target_text = sprintf("Target: %.1f", m$target_dppp),
    actual_text = sprintf("Actual: %.1f", m$new_dppp),
    verdict = dppp_met,
    x = tile_x[1], y = 0.66
  )
  .draw_metric_tile(
    label = "Satisfaction",
    target_text = sprintf("Target: %.0f%%", target_sat * 100),
    actual_text = if (!is.na(after_sat)) sprintf("Actual: %.1f%%", after_sat * 100) else "N/A",
    verdict = if (!is.na(after_sat)) sat_met else NULL,
    x = tile_x[2], y = 0.66
  )
  coverage_text <- if (!is.na(m$coverage_pct) && m$coverage_pct > 0) {
    sprintf("%.1f%%", m$coverage_pct)
  } else {
    "N/A"
  }
  .draw_metric_tile(
    label = "Coverage",
    target_text = "",
    actual_text = sprintf("Achieved: %s", coverage_text),
    verdict = NULL,
    x = tile_x[3], y = 0.66
  )

  # Row 2
  ct_text <- if (!is.na(m$new_ct)) sprintf("%.2f sec", m$new_ct) else "N/A"
  .draw_metric_tile(
    label = "Cycle Time",
    target_text = "",
    actual_text = ct_text,
    verdict = NULL,
    x = tile_x[1], y = 0.48
  )
  win_detail <- if (!is.na(m$windows_per_bin)) {
    sprintf("%d (%d per bin)", m$n_windows, m$windows_per_bin)
  } else {
    as.character(m$n_windows)
  }
  .draw_metric_tile(
    label = "Windows",
    target_text = "",
    actual_text = win_detail,
    verdict = NULL,
    x = tile_x[2], y = 0.48
  )
  width_text <- if (!is.na(m$mean_width)) sprintf("%.1f Da", m$mean_width) else "N/A"
  .draw_metric_tile(
    label = "Mean Width",
    target_text = "",
    actual_text = width_text,
    verdict = NULL,
    x = tile_x[3], y = 0.48
  )

  # --- Strategy / Mode Info ---
  info_text <- sprintf("Strategy: %s  |  Window Mode: %s",
                       format_strategy_label(m$strategy),
                       tools::toTitleCase(m$window_mode))
  grid::grid.text(info_text, x = 0.5, y = 0.37,
            gp = grid::gpar(fontsize = 11, col = aidia_colors$secondary))

  # --- Conditional Recommendation ---
  rec_text <- if (sat_met) {
    "Your target conditions are achievable with this configuration.\nApply the CSV method file to your instrument."
  } else if (!is.na(after_sat) && after_sat >= 0.5) {
    "Close to target. Review the satisfaction curve (Section 2) to evaluate\ncycle time trade-offs for your use case."
  } else {
    "Target not met with current parameters. Consider adjusting target DPPP,\nsatisfaction rate, or trying a different strategy."
  }

  rec_bg <- if (sat_met) "#e8f8f5" else "#fef9e7"
  rec_border <- if (sat_met) aidia_colors$success else aidia_colors$warning
  rec_col <- if (sat_met) "#16a085" else "#b7950b"

  grid::grid.rect(x = 0.5, y = 0.26, width = 0.7, height = 0.1,
            gp = grid::gpar(fill = rec_bg, col = rec_border, lwd = 1))
  grid::grid.text(rec_text, x = 0.5, y = 0.26, just = "center",
            gp = grid::gpar(fontsize = 11, fontface = "italic", col = rec_col,
                       lineheight = 1.3))

  # Bottom note
  grid::grid.text("See subsequent sections for detailed analysis",
            x = 0.5, y = 0.17,
            gp = grid::gpar(fontsize = 9, col = aidia_colors$secondary,
                       fontface = "italic"))
}

