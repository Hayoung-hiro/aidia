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

# AIDIA colors (duplicated here for standalone sourcing; matches theme_aidia.R)
.report_colors <- list(
  primary   = "#2C3E50",
  secondary = "#7F8C8D",
  accent    = "#E74C3C",
  success   = "#27AE60",
  grid      = "#ECF0F1"
)

#' Draw Cover Page
#' @keywords internal
.draw_cover_page <- function(optimization_plan, optimized_windows, validated_data) {
  grid::grid.newpage()

  # Background accent bar at top
  grid::grid.rect(x = 0, y = 1, width = 1, height = 0.08,
            just = c("left", "top"),
            gp = grid::gpar(fill = .report_colors$primary, col = NA))

  # Title
  grid::grid.text("AIDIA",
            x = 0.5, y = 0.72,
            gp = grid::gpar(fontsize = 42, fontface = "bold",
                       col = .report_colors$primary))
  grid::grid.text("Adaptive Isolation for DIA",
            x = 0.5, y = 0.65,
            gp = grid::gpar(fontsize = 16, col = .report_colors$secondary))

  # Divider line
  grid::grid.lines(x = c(0.3, 0.7), y = c(0.60, 0.60),
             gp = grid::gpar(col = .report_colors$accent, lwd = 2))

  # Subtitle
  grid::grid.text("Window Optimization Report",
            x = 0.5, y = 0.55,
            gp = grid::gpar(fontsize = 20, fontface = "bold",
                       col = .report_colors$primary))

  # Key metrics (centered block)
  instrument <- optimization_plan$instrument$preset %||% "custom"
  n_windows <- nrow(optimized_windows$windows)
  coverage <- optimized_windows$statistics$coverage_percentage
  n_precursors <- format(validated_data$metadata$n_precursors, big.mark = ",")
  mz_strategy <- optimized_windows$parameters$mz_strategy
  window_mode <- optimized_windows$parameters$window_mode

  metrics <- c(
    sprintf("Instrument: %s", instrument),
    sprintf("Precursors: %s", n_precursors),
    sprintf("Strategy: %s | Mode: %s", mz_strategy, window_mode),
    sprintf("Windows: %d | Coverage: %.1f%%", n_windows, coverage)
  )

  for (i in seq_along(metrics)) {
    grid::grid.text(metrics[i],
              x = 0.5, y = 0.44 - (i - 1) * 0.05,
              gp = grid::gpar(fontsize = 13, col = .report_colors$primary))
  }

  # Timestamp at bottom
  grid::grid.text(sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M")),
            x = 0.5, y = 0.15,
            gp = grid::gpar(fontsize = 11, col = .report_colors$secondary,
                       fontface = "italic"))

  # Bottom bar
  grid::grid.rect(x = 0, y = 0, width = 1, height = 0.04,
            just = c("left", "bottom"),
            gp = grid::gpar(fill = .report_colors$primary, col = NA))
}

#' Draw Section Divider Page
#' @keywords internal
.draw_section_page <- function(section_number, section_title, section_subtitle = NULL) {
  grid::grid.newpage()

  # Left accent bar
  grid::grid.rect(x = 0, y = 0, width = 0.02, height = 1,
            just = c("left", "bottom"),
            gp = grid::gpar(fill = .report_colors$accent, col = NA))

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
                       col = .report_colors$grid))

  # Section title
  grid::grid.text(section_title,
            x = 0.12, y = 0.45,
            just = "left",
            gp = grid::gpar(fontsize = 22, fontface = "bold",
                       col = .report_colors$primary))

  # Subtitle
  if (!is.null(section_subtitle)) {
    grid::grid.text(section_subtitle,
              x = 0.12, y = 0.38,
              just = "left",
              gp = grid::gpar(fontsize = 12, col = .report_colors$secondary,
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
                       col = .report_colors$primary))

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
      "Width Grid Step (Da)",
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
      params$mz_strategy,
      params$window_mode,
      as.character(params$width_grid_step %||% 0.5),
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
        fg_params = list(fontsize = 10, col = .report_colors$primary,
                          hjust = 0, x = 0.05),
        bg_params = list(
          fill = c(rep(c("white", .report_colors$grid),
                       length.out = nrow(param_data))),
          col = .report_colors$grid, lwd = 0.5
        )
      ),
      colhead = list(
        fg_params = list(fontsize = 11, col = "white", fontface = "bold",
                          hjust = 0, x = 0.05),
        bg_params = list(fill = .report_colors$primary, col = "white", lwd = 1)
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
              gp = grid::gpar(fontsize = 12, col = .report_colors$accent))
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
#' Report Structure:
#'   1. Cover Page (AIDIA branding + key metrics)
#'   2. Parameter Summary (configuration table)
#'   3. Input Data Profile (FWHM, RT x m/z heatmap, histograms)
#'   4. DPPP Analysis & Optimization (DPPP, satisfaction, impact)
#'   5. Window Optimization Results (density overlay, quality, gantt)
#'   6. Strategy Comparison (table, ridge, box, CDF)
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

  # --- Parameter Summary ---
  .draw_parameter_summary(optimization_plan, optimized_windows, validated_data)
  n_pages <- n_pages + 1

  # --- Section 1: Input Data Profile ---
  .draw_section_page(1, "Input Data Profile",
                     "Chromatographic and mass spectrometric characteristics of the dataset")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot0_fwhm_distribution",
    "plot2_rt_mz_density_heatmap",
    "plot2b_rt_histogram_continuous",
    "plot2b_rt_histogram_5min"
  ))
  n_pages <- n_pages + n

  # --- Section 2: DPPP Analysis & Optimization ---
  .draw_section_page(2, "DPPP Analysis & Optimization",
                     "Data Points Per Peak diagnosis, cycle time optimization, and impact assessment")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot1a_dppp_comparison_simple",
    "plot1b_dppp_comparison_enhanced",
    "plot6_satisfaction_curve",
    "plot6b_impact_summary"
  ))
  n_pages <- n_pages + n

  # --- Section 3: Window Optimization Results ---
  .draw_section_page(3, "Window Optimization Results",
                     "RT binning, m/z density overlay, and isolation window layout")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot3_mz_density_overlay",
    "plot9_rt_bin_quality_heatmap",
    "plot10_isolation_window_gantt"
  ))
  n_pages <- n_pages + n

  # --- Section 4: Strategy Comparison ---
  .draw_section_page(4, "Strategy Comparison",
                     "Side-by-side comparison of m/z optimization strategies")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot8d_strategy_comparison_table",
    "plot4e_mz_width_all_strategies",
    "plot8a_strategy_width_ridge",
    "plot8b_strategy_width_boxplot",
    "plot8c_strategy_width_cdf"
  ))
  n_pages <- n_pages + n

  # --- Appendix A: Detailed Per-Strategy Analysis ---
  # Only emit if any per-strategy plots exist
  per_strategy_keys <- grep("^plot[47]_", names(plots), value = TRUE)
  # Exclude the all-strategies comparison already shown above
  per_strategy_keys <- setdiff(per_strategy_keys, "plot4e_mz_width_all_strategies")
  if (length(per_strategy_keys) > 0) {
    .draw_section_page("A", "Detailed Per-Strategy Analysis",
                       "Per-strategy m/z excluded regions, coverage maps, and window width distributions")
    n_pages <- n_pages + 1

    # Coverage map grid (2x2)
    n <- .emit_section_plots(plots, c(
      "plot5_coverage_map_2x2",
      "plot5_coverage_map_single"
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

