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
#' @keywords internal
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
# Data Quality Score Panel (Section 1 text block)
# =============================================================================

#' Draw Data Summary Table on PDF
#'
#' Clean tableGrob showing dataset statistics and quality score breakdown.
#' Replaces the old text-based quality panel.
#'
#' @keywords internal
.draw_data_quality_summary <- function(validated_data) {
  grid::grid.newpage()

  data <- validated_data$data
  meta <- validated_data$metadata
  vs <- validated_data$validation_status
  fwhm_sec <- ensure_fwhm_seconds(data$FWHM)

  # Raw precursor count (before consensus)
  n_raw <- meta$n_precursors_before %||% meta$n_precursors %||% nrow(data)
  n_runs <- meta$n_runs %||% 1L
  n_final <- nrow(data)

  # FWHM outlier percentage
  qd <- vs$quality_details %||% vs$details
  fwhm_outlier_pct <- if (!is.null(qd$fwhm_outliers)) {
    qd$fwhm_outliers$pct_outliers * 100
  } else 0

  # Build table
  table_data <- data.frame(
    Metric = c(
      "Raw Precursors",
      "Replicates",
      "Consensus Precursors",
      "m/z Range",
      "RT Range",
      "Median FWHM",
      "Mean FWHM",
      "FWHM Outliers"
    ),
    Value = c(
      format(n_raw, big.mark = ","),
      as.character(n_runs),
      sprintf("%s (CV <= 30%%, filtered %s)",
              format(n_final, big.mark = ","),
              format(meta$n_filtered_cv %||% 0, big.mark = ",")),
      sprintf("%.1f \u2013 %.1f Da",
              min(data$Precursor.Mz), max(data$Precursor.Mz)),
      sprintf("%.1f \u2013 %.1f min",
              min(data$RT.Apex), max(data$RT.Apex)),
      sprintf("%.1f sec", median(fwhm_sec)),
      sprintf("%.1f sec", mean(fwhm_sec)),
      sprintf("%.1f%%", fwhm_outlier_pct)
    ),
    stringsAsFactors = FALSE
  )

  n_r <- nrow(table_data)

  table_grob <- gridExtra::tableGrob(
    table_data,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core = list(
        fg_params = list(fontsize = 12, col = "black",
                          hjust = 0, x = 0.05),
        bg_params = list(
          fill = rep(c("white", "gray95"), length.out = n_r),
          col = "gray85", lwd = 0.5
        )
      ),
      colhead = list(
        fg_params = list(fontsize = 13, col = "white", fontface = "bold",
                          hjust = 0, x = 0.05),
        bg_params = list(fill = "gray20", col = "white", lwd = 1)
      )
    )
  )

  title_grob <- grid::textGrob(
    "Data Summary",
    gp = grid::gpar(fontsize = 18, fontface = "bold", col = "black")
  )

  combined <- gridExtra::arrangeGrob(
    title_grob,
    table_grob,
    ncol = 1,
    heights = grid::unit(c(1, 6), "null"),
    padding = grid::unit(1, "lines")
  )

  grid::grid.draw(combined)
}

# =============================================================================
# Instrument Metadata Footer (Section 2 text block)
# =============================================================================

#' Draw Instrument Metadata on PDF
#' @keywords internal
# =============================================================================
# Create PDF Report (Structured)
# =============================================================================

#' Create Structured PDF Report
#'
#' Creates a professionally structured AIDIA optimization report with
#' cover page, parameter summary, and logically grouped plot sections.
#'
#' Report Structure (5-section narrative):
#'   Cover Page (AIDIA branding + key metrics)
#'   Executive Summary (target-oriented scorecard with verdict)
#'   Configuration Summary (parameter table)
#'   S1. Input Data Profile (intensity heatmap, FWHM, quality score panel)
#'   S2. Acquisition Diagnosis (DPPP table, satisfaction curve, instrument metadata)
#'   S3. Optimized Window Layout (tiling, load balance, m/z density)
#'   S4. Optimization Validation (impact dashboard, edge proximity, FZ zoom)
#'   S5. Strategy Comparison (conditional: table, width ridge, boundary grid)
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

  # --- Section 1: Input Data Profile ---
  .draw_section_page(1, "Input Data Profile",
                     "Precursor distribution characteristics and chromatographic quality")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "s1_01_density_heatmap",
    "s1_02_fwhm_distribution"
  ))
  n_pages <- n_pages + n
  .draw_data_quality_summary(validated_data)
  n_pages <- n_pages + 1

  # --- Section 2: Acquisition Diagnosis ---
  .draw_section_page(2, "Acquisition Diagnosis",
                     "Current DPPP status, cycle time trade-off, and instrument parameters")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "s2_01_dppp_diagnosis",
    "s2_02_satisfaction_curve"
  ))
  n_pages <- n_pages + n

  # --- Section 3: Optimized Window Layout ---
  .draw_section_page(3, "Optimized Window Layout",
                     "Isolation window tiling, density alignment, and precursor load balance")
  n_pages <- n_pages + 1
  s3_keys <- c("s3_02_load_balance", "s3_03_mz_density")
  # Tiling coverage map: staggered mode only (shows cycle interleaving)
  if (identical(optimized_windows$parameters$window_mode, "staggered")) {
    s3_keys <- c("s3_01_tiling_coverage", s3_keys)
  }
  n <- .emit_section_plots(plots, s3_keys)
  n_pages <- n_pages + n

  # --- Section 4: Optimization Validation ---
  validation_keys <- c("s4_01_impact_summary",
                       "s4_02_edge_proximity",
                       "s4_03_edge_proximity_spatial",
                       "s4_04_charge_state",
                       "s4_05_fz_validation")
  if (any(validation_keys %in% names(plots))) {
    .draw_section_page(4, "Optimization Validation",
                       "Impact summary, boundary safety, forbidden zone, and charge state distribution")
    n_pages <- n_pages + 1
    n <- .emit_section_plots(plots, validation_keys)
    n_pages <- n_pages + n
  }

  # --- Section 5: Strategy Comparison (CONDITIONAL: only when >= 2 strategies) ---
  strategy_keys <- c("s5_01_strategy_table",
                     "s5_02_strategy_ridge",
                     "s5_03_heatmap_boundary",
                     "s5_04_width_profile")
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

  # --- Appendix B: FZ Boundary Zoom (micro view) ---
  if ("s4_app_fz_zoom" %in% names(plots)) {
    .draw_section_page("B", "FZ Boundary Zoom",
                       "Zoomed view of precursor m/z density around a representative window boundary")
    n_pages <- n_pages + 1
    n <- .emit_section_plots(plots, "s4_app_fz_zoom")
    n_pages <- n_pages + n
  }

  # --- Appendix C: Adaptive RT Binning (conditional) ---
  adaptive_keys <- grep("^plot11", names(plots), value = TRUE)
  if (length(adaptive_keys) > 0) {
    .draw_section_page("C", "Adaptive RT Binning",
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

#' Draw Executive Summary Table
#'
#' Clean tabular summary of optimization results: key metrics, targets,
#' and verdict. Matches the Configuration Summary page style.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1 (for satisfaction calc)
#'
#' @keywords internal
.draw_executive_summary <- function(optimization_plan, optimized_windows,
                                    validated_data = NULL) {
  grid::grid.newpage()

  # Extract metrics via shared accessor
  m <- extract_before_after_metrics(optimization_plan, optimized_windows)

  # Calculate after-optimization satisfaction
  after_sat <- NA_real_
  if (!is.null(validated_data) && !is.na(m$new_ct) && !is.na(m$target_dppp)) {
    fwhm_sec <- ensure_fwhm_seconds(get_precursor_data(validated_data)$FWHM)
    dppp_vals <- calculate_dppp(fwhm_sec, m$new_ct)
    after_sat <- dppp_satisfaction_pct(dppp_vals, m$target_dppp) / 100
  }
  target_sat <- m$target_satisfaction
  if (is.na(target_sat)) target_sat <- 0.7

  sat_met <- !is.na(after_sat) && after_sat >= target_sat
  dppp_met <- !is.na(m$new_dppp) && !is.na(m$target_dppp) && m$new_dppp >= m$target_dppp

  # Build table data
  table_data <- data.frame(
    Metric = c(
      "Instrument",
      "Strategy / Window Mode",
      "Cycle Time",
      "Target DPPP",
      "Satisfaction",
      "Coverage",
      "Total Windows",
      "Mean Window Width",
      "Overall Verdict"
    ),
    Value = c(
      sprintf("%s (%s)",
              optimization_plan$instrument$name %||% "N/A",
              optimization_plan$instrument$cycle_mode %||% "sequential"),
      sprintf("%s / %s",
              format_strategy_label(m$strategy),
              tools::toTitleCase(m$window_mode)),
      if (!is.na(m$new_ct)) sprintf("%.3f sec", m$new_ct) else "N/A",
      sprintf("%.1f (actual: %.1f)", m$target_dppp, m$new_dppp),
      if (!is.na(after_sat)) {
        sprintf("%.1f%% (target: %.0f%%)", after_sat * 100, target_sat * 100)
      } else "N/A",
      if (!is.na(m$coverage_pct) && m$coverage_pct > 0) {
        sprintf("%.1f%%", m$coverage_pct)
      } else "N/A",
      if (!is.na(m$windows_per_bin)) {
        sprintf("%d (%d per RT bin)", m$n_windows, m$windows_per_bin)
      } else as.character(m$n_windows),
      if (!is.na(m$mean_width)) sprintf("%.1f Da", m$mean_width) else "N/A",
      if (sat_met) "TARGET MET" else "TARGET NOT MET"
    ),
    stringsAsFactors = FALSE
  )

  # Verdict row color
  n_r <- nrow(table_data)
  fg_colors <- rep("black", n_r)
  fg_colors[n_r] <- if (sat_met) aidia_colors$success else aidia_colors$accent

  table_grob <- gridExtra::tableGrob(
    table_data,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core = list(
        fg_params = list(fontsize = 12, col = fg_colors,
                          hjust = 0, x = 0.05),
        bg_params = list(
          fill = rep(c("white", "gray95"), length.out = n_r),
          col = "gray85", lwd = 0.5
        )
      ),
      colhead = list(
        fg_params = list(fontsize = 13, col = "white", fontface = "bold",
                          hjust = 0, x = 0.05),
        bg_params = list(fill = "gray20", col = "white", lwd = 1)
      )
    )
  )

  # Title
  title_grob <- grid::textGrob(
    "Executive Summary",
    gp = grid::gpar(fontsize = 18, fontface = "bold", col = "black")
  )

  # Recommendation
  rec_text <- if (sat_met) {
    "Target conditions achieved. Apply the exported CSV method file to your instrument."
  } else if (!is.na(after_sat) && after_sat >= 0.5) {
    "Close to target. Review the satisfaction curve (Section 2) for cycle time trade-offs."
  } else {
    "Target not met. Consider adjusting target DPPP, satisfaction, or strategy."
  }
  rec_grob <- grid::textGrob(
    rec_text,
    gp = grid::gpar(fontsize = 11, fontface = "italic", col = "gray30")
  )

  combined <- gridExtra::arrangeGrob(
    title_grob,
    table_grob,
    rec_grob,
    ncol = 1,
    heights = grid::unit(c(1.2, 5, 0.8), "null"),
    padding = grid::unit(1, "lines")
  )

  grid::grid.draw(combined)
}

