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

  # --- Executive Summary (moved before Parameter Summary — pyramid principle) ---
  .draw_executive_summary(optimization_plan, optimized_windows)
  n_pages <- n_pages + 1

  # --- Parameter Summary ---
  .draw_parameter_summary(optimization_plan, optimized_windows, validated_data)
  n_pages <- n_pages + 1

  # --- Section 1: Input Data Profile ---
  # FWHM distribution + RT x m/z heatmap only (RT histograms removed as 1D projections)
  .draw_section_page(1, "Input Data Profile",
                     "Chromatographic and mass spectrometric characteristics of the dataset")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot0_fwhm_distribution",
    "plot2_rt_mz_density_heatmap",
    "plot19_charge_mz"
  ))
  n_pages <- n_pages + n

  # --- Section 2: DPPP Analysis & Optimization ---
  # Enhanced DPPP only (Simple removed — Enhanced is strict superset)
  .draw_section_page(2, "DPPP Analysis & Optimization",
                     "Data Points Per Peak diagnosis, cycle time optimization, and impact assessment")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot1b_dppp_comparison_enhanced",
    "plot15_dppp_distribution",
    "plot6_satisfaction_curve",
    "plot6b_impact_summary"
  ))
  n_pages <- n_pages + n

  # --- Section 3: Window Optimization Results ---
  # Density overlay + Gantt (RT Bin Quality heatmap removed — normalization issue)
  .draw_section_page(3, "Window Optimization Results",
                     "m/z density overlay and isolation window layout")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot3_mz_density_overlay",
    "plot10_isolation_window_gantt",
    "plot16_load_balance"
  ))
  n_pages <- n_pages + n

  # --- Section 4: Strategy Comparison ---
  # Table + Ridge only (Box/CDF removed — Ridge with quantile lines is sufficient)
  .draw_section_page(4, "Strategy Comparison",
                     "Side-by-side comparison of m/z optimization strategies")
  n_pages <- n_pages + 1
  n <- .emit_section_plots(plots, c(
    "plot8d_strategy_comparison_table",
    "plot8a_strategy_width_ridge",
    "plot18_strategy_radar"
  ))
  n_pages <- n_pages + n

  # --- Section 5: Window Verification ---
  # Tiling (12) and Alignment (13) removed — internal QC only, replaced by Edge Proximity (17)
  verification_keys <- c("plot17_edge_proximity",
                         "plot14_fz_zoom")
  if (any(verification_keys %in% names(plots))) {
    .draw_section_page(5, "Window Quality Assessment",
                       "Edge proximity analysis and forbidden zone boundary validation")
    n_pages <- n_pages + 1
    n <- .emit_section_plots(plots, verification_keys)
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


# =============================================================================
# Executive Summary Insight Panel
# =============================================================================

.draw_executive_summary <- function(optimization_plan, optimized_windows) {
  grid::grid.newpage()

  # Header
  grid::grid.text("Executive Summary & Insights",
            x = 0.5, y = 0.95,
            gp = grid::gpar(fontsize = 18, fontface = "bold",
                       col = aidia_colors$primary))

  # Background panel for insights
  grid::grid.rect(x = 0.5, y = 0.5, width = 0.8, height = 0.7,
            gp = grid::gpar(fill = "#f8f9fa", col = "#bdc3c7", lwd = 2))

  # Extract metrics via shared accessor
  m <- extract_before_after_metrics(optimization_plan, optimized_windows)
  orig_dppp   <- m$orig_dppp
  new_dppp    <- m$new_dppp
  target_dppp <- m$target_dppp

  orig_ct     <- m$orig_ct
  new_ct      <- m$new_ct

  strategy    <- m$strategy
  window_mode <- m$window_mode

  # Insight 1: DPPP Analysis
  dppp_text <- if (!is.na(orig_dppp) && !is.na(new_dppp) && orig_dppp < target_dppp) {
    sprintf("1. Data Points Per Peak (DPPP): The original DPPP was %.1f, failing to meet the target of %.1f.\n   The new optimization plan adjusted the cycle time to achieve a robust DPPP of %.1f.", orig_dppp, target_dppp, new_dppp)
  } else if (!is.na(orig_dppp) && !is.na(new_dppp)) {
    sprintf("1. Data Points Per Peak (DPPP): The original DPPP (%.1f) was sufficient for the target (%.1f).\n   The new plan maintains a high DPPP of %.1f while optimizing window boundaries.", orig_dppp, target_dppp, new_dppp)
  } else {
    sprintf("1. Data Points Per Peak (DPPP): Target DPPP is %.1f.\n   DPPP metrics were not available for comparison.", target_dppp)
  }

  # Insight 2: Cycle Time Analysis
  ct_text <- if (!is.na(orig_ct) && !is.na(new_ct) && orig_ct > 0) {
    ct_diff_pct <- round((orig_ct - new_ct) / orig_ct * 100, 1)
    if (ct_diff_pct > 0) {
      sprintf("2. Scan Efficiency: Cycle time was reduced by %.1f%% (from %.2fs to %.2fs).\n   This faster scanning allows for better chromatographic peak shape reconstruction.", ct_diff_pct, orig_ct, new_ct)
    } else if (ct_diff_pct < 0) {
      sprintf("2. Scan Efficiency: Cycle time was increased by %.1f%% (from %.2fs to %.2fs).\n   This slower scanning trades temporal resolution for more/narrower isolation windows.", abs(ct_diff_pct), orig_ct, new_ct)
    } else {
      sprintf("2. Scan Efficiency: Overall cycle time remained stable at %.2fs.\n   Window widths were re-distributed internally for optimal precursor coverage.", new_ct)
    }
  } else if (!is.na(new_ct)) {
    sprintf("2. Scan Efficiency: Optimized cycle time is %.2fs.", new_ct)
  } else {
    "2. Scan Efficiency: Cycle time metrics were not available for comparison."
  }

  # Insight 3: Strategy & Window Placement
  win_text <- sprintf("3. Isolation Strategy: Using the '%s' strategy with '%s' window mode.\n   This combination ensures that narrow windows are dynamically allocated to m/z regions\n   with the highest density of precursors, maximizing detection sensitivity.", format_strategy_label(strategy), tools::toTitleCase(window_mode))
  
  # Draw Insights
  grid::grid.text(dppp_text, x = 0.15, y = 0.75, just = c("left", "top"), 
            gp = grid::gpar(fontsize = 12, lineheight = 1.5, col = aidia_colors$primary))
            
  grid::grid.text(ct_text, x = 0.15, y = 0.55, just = c("left", "top"), 
            gp = grid::gpar(fontsize = 12, lineheight = 1.5, col = aidia_colors$primary))
            
  grid::grid.text(win_text, x = 0.15, y = 0.35, just = c("left", "top"), 
            gp = grid::gpar(fontsize = 12, lineheight = 1.5, col = aidia_colors$primary))
            
  # Recommendation
  rec_text <- "Recommendation: Apply the generated CSV method file to your instrument.\nThe changes ensure the acquisition is tailored to the true complexity of your sample."
  
  grid::grid.rect(x = 0.5, y = 0.15, width = 0.7, height = 0.1, 
            gp = grid::gpar(fill = "#e8f8f5", col = "#1abc9c", lwd = 1))
  grid::grid.text(rec_text, x = 0.5, y = 0.15, just = "center", 
            gp = grid::gpar(fontsize = 11, fontface = "italic", col = "#16a085", lineheight = 1.3))
}

