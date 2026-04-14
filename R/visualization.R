# visualization.R - Stage 4: Visualization & Reporting (Orchestrator)
#
# Purpose: Generate comprehensive visualizations and reports for DIA window optimization
#
# Version: 4.1 (Modularized architecture)
#
# Architecture:
#   This file is the orchestrator that sources modular plot functions from R/
#   and coordinates the overall visualization pipeline.
#
# Sourced Modules:
#   - R/plot_dppp.R: DPPP distribution comparison plots
#   - R/plot_density.R: Density heatmap and normalized density
#   - R/plot_satisfaction.R: Satisfaction vs cycle time curve
#   - R/export_plots.R: Export and PDF report functions
#
# Legacy Plot Modules (consolidated into R/):
#   - R/plot_rt_histogram.R: Binned RT histogram
#   - R/plot_density_overlay.R: Coverage map grid
#   - R/plot_window_width.R: Window width distribution
#   - R/plot_strategy_comparison.R: Strategy width comparison
#
# Main Functions:
#   1. generate_visualizations() - Main orchestration function
#   2. calculate_summary_statistics() - Calculate optimization metrics
#
# Input: Refactored pipeline outputs
#   - validated_data (ValidatedData from Stage 1)
#   - optimization_plan (OptimizationPlan from Stage 2)
#   - optimized_windows (OptimizedWindows from Stage 3)
#
# Output: VisualizationResult with plots, reports, and method files


# =============================================================================
# Main Visualization Function
# =============================================================================

#' Generate All Visualizations
#'
#' Main orchestration function that generates all plots, PDF report,
#' and individual plot exports.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_dir Character, output directory path
#' @param create_pdf Logical, create comprehensive PDF report
#' @param create_individual_plots Logical, export individual plots
#' @param plot_format Character, "png" or "pdf"
#' @param plot_dpi Numeric, plot resolution (default: 300)
#' @param windows_list Optional: Pre-computed windows for all strategies
#'
#' @return VisualizationResult object
#' @export
generate_visualizations <- function(
  validated_data,
  optimization_plan,
  optimized_windows,
  output_dir = "output/",
  create_pdf = TRUE,
  create_individual_plots = TRUE,
  plot_format = "png",
  plot_dpi = 300,
  windows_list = NULL
) {

  cat("\n==================================================\n")
  cat("   STAGE 4: Visualization & Reporting\n")
  cat("==================================================\n\n")

  viz_start <- Sys.time()

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  cat("Step 1: Generating all plots...\n")

  # Generate all plots with standardized naming
  plots <- list()

  # Plot 0: FWHM Distribution (Fundamental Input)
  cat("  Generating Plot 0: FWHM Distribution (Fundamental Input)...\n")
  plots$`s1_02_fwhm_distribution` <- plot_fwhm_distribution(validated_data, optimization_plan)

  # Plot 1: DPPP Comparison - Both versions
  cat("  Generating Plot 1A: DPPP Comparison (Simple)...\n")
  plots$`plot1a_dppp_comparison_simple` <- plot_dppp_comparison(optimization_plan, validated_data)

  # Plot 1B: Acquisition Diagnosis Table (primary for PDF)
  plots$`s2_01_dppp_diagnosis` <- plot_dppp_diagnosis_table(optimization_plan, validated_data)

  # Legacy versions (kept for individual export, not used in PDF)
  cat("  Generating Plot 1B curve: DPPP vs Cycle Time (legacy)...\n")
  plots$`plot1b_dppp_enhanced` <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)
  cat("  Generating Plot 1B+6: DPPP & Satisfaction Combined (legacy)...\n")
  plots$`plot1b_dppp_satisfaction_combined` <- plot_dppp_satisfaction_combined(optimization_plan, validated_data)

  # Plot 2: RT x m/z Intensity/Density Heatmap
  cat("  Generating Plot 2: RT x m/z Heatmap...\n")
  plots$`s1_01_density_heatmap` <- plot_rt_mz_density_heatmap(validated_data)

  # Plot 6: Satisfaction vs Cycle Time Curve
  cat("  Generating Plot 6: Satisfaction Curve...\n")
  plots$`s2_02_satisfaction_curve` <- plot_satisfaction_curve(optimization_plan, validated_data)

  # Plot 2B: RT Histogram (supplementary — kept for individual export, removed from PDF)
  cat("  Generating Plot 2B: RT Histogram...\n")
  plots$`plot2b_rt_histogram_continuous` <- plot_rt_histogram(validated_data)
  plots$`plot2b_rt_histogram_5min` <- plot_rt_histogram_binned(validated_data, bin_width_min = 5)

  # S3-03: m/z Density Overlay by RT Segment
  cat("  Generating S3-03: m/z Density Overlay...\n")
  plots$`s3_03_mz_density` <- plot_mz_normalized_density(optimized_windows, validated_data)

  # S3-04: Window Width + Density Overlay (active strategy)
  cat("  Generating S3-04: Window Width Distribution...\n")
  plots$`s3_04_window_width` <- plot_window_width_distribution(
    optimized_windows, validated_data, max_segments_to_show = 6
  )

  # S3-05: Window Index Width Bars (active strategy)
  cat("  Generating S3-05: Window Index Width Bars...\n")
  plots$`s3_05_window_index` <- plot_cumulative_window_count(
    optimized_windows, validated_data, max_segments_to_show = 6
  )

  # ===================================================================
  # Multi-Strategy m/z Range Optimization (for S5 + Appendix)
  # ===================================================================

  cat("\n  Preparing Plot 4: Multi-Strategy Comparison...\n")

  # Default strategies for re-computation when no windows_list provided
  default_strategies <- STRATEGY_PREFERRED_ORDER

  # Use pre-computed windows_list if provided, otherwise compute
  if (is.null(windows_list)) {
    cat("  Running optimization with all 5 m/z strategies...\n")
    windows_list <- list()
    strategies <- default_strategies

    # Generate windows for each strategy
    for (strategy in strategies) {
      cat(sprintf("    - Optimizing with '%s' strategy...\n", strategy))
      windows_list[[strategy]] <- optimize_windows(
        validated_data = validated_data,
        optimization_plan = optimization_plan,
        rt_bin_width_min = optimized_windows$parameters$rt_bin_width_min,
        mz_strategy = strategy,
        window_mode = optimized_windows$parameters$window_mode,
        rt_binning_mode = optimized_windows$parameters$rt_binning_mode %||% "fixed",
        quantile_lower = 0.05,
        quantile_upper = 0.95,
        outlier_threshold = 3.0,
        smoothing_window = 7,
        polynomial_order = 3,
        target_coverage = 0.95
      )
    }
  } else {
    # Use the actual strategies from the provided windows_list
    strategies <- names(windows_list)
    cat(sprintf("  Using pre-computed windows for %d strategies (skipping re-optimization)...\n",
                length(strategies)))
  }

  # Plot 4A-4D: Individual strategy m/z excluded regions
  for (strategy in strategies) {
    plot_name <- sprintf("plot4_%s_mz_excluded", strategy)
    cat(sprintf("  Generating Plot 4 (%s): m/z Excluded Regions...\n", toupper(strategy)))
    plots[[plot_name]] <- plot_mz_distribution_with_exclusions(
      windows_list[[strategy]], validated_data, max_bins_to_show = 6
    )
  }

  # Plot 4E: All-strategy width comparison
  cat("  Generating Plot 4E: Width Comparison (All Strategies)...\n")
  plots$`plot4e_mz_width_all_strategies` <- plot_mz_width_comparison_all_strategies(
    windows_list, validated_data
  )

  # Strategy Width Profile (overlay line chart)
  cat("  Generating S5-04: Strategy Width Profile...\n")
  plots$`s5_04_width_profile` <- plot_strategy_width_profile(
    windows_list, validated_data
  )

  # Plot 6B: Optimization Impact Summary (Before/After Dashboard)
  cat("  Generating Plot 6B: Optimization Impact Summary...\n")
  plots$`s4_01_impact_summary` <- plot_optimization_impact(optimization_plan, optimized_windows, validated_data)

  # Plot 9: RT Bin Quality Heatmap (kept for individual export, removed from PDF)
  cat("  Generating Plot 9: RT Bin Quality Heatmap...\n")
  plots$`plot9_rt_bin_quality_heatmap` <- plot_rt_bin_quality_heatmap(
    optimized_windows, validated_data, optimization_plan
  )

  # Plot 2C: RT x m/z Heatmap with m/z Range Overlay (per-strategy grid)
  cat("  Generating Plot 2C: Heatmap with m/z Range (All Strategies)...\n")
  plots$`s5_03_heatmap_boundary` <- plot_density_with_mz_ranges_grid(
    windows_list, validated_data
  )

  # Plot 10: Removed — redundant with Plot 7 (window width distribution)

  # Plot 11: RT Change Point Validation (only when adaptive RT binning used)
  rt_binning_mode <- optimized_windows$rt_binning$rt_binning_mode %||% "fixed"
  if (rt_binning_mode == "adaptive") {
    cat("  Generating Plot 11: RT Change Point Validation...\n")
    plots$`plot11_rt_changepoint_validation` <- plot_rt_changepoint_validation(
      validated_data, optimized_windows
    )

    cat("  Generating Plot 11B: KS Statistic Trace...\n")
    plots$`plot11b_ks_statistic_trace` <- plot_ks_statistic_trace(optimized_windows)
  }

  # ===================================================================
  # Plot 12-14: Window Verification (Tiling, Alignment, FZ Zoom)
  # ===================================================================

  # Plot 12: Tiling Coverage Map (staggered mode only — shows cycle interleaving)
  if (identical(optimized_windows$parameters$window_mode, "staggered")) {
    cat("  Generating Plot 12: Tiling Coverage Map (Staggered Interleaving)...\n")
    plots$`s3_01_tiling_coverage` <- plot_tiling_coverage_map(
      optimized_windows, validated_data
    )
  }

  # Plot 13: Alignment Density
  cat("  Generating Plot 13: Alignment Density (Precursor-Window Alignment)...\n")
  plots$`plot13_alignment_density` <- plot_alignment_density(
    optimized_windows, validated_data
  )

  # Plot 14: FZ Zoom-in (always-on: isotope envelope protection is default)
  fz_offset <- optimized_windows$parameters$fz_offset %||% 0.25
  cat("  Generating Plot 14: Forbidden Zone Zoom-in...\n")
  plots$`s4_app_fz_zoom` <- plot_fz_zoom(
    optimized_windows, validated_data, fz_offset = fz_offset
  )

  # Plot 14B: FZ Validation (mass defect histogram)
  cat("  Generating Plot 14B: Forbidden Zone Validation...\n")
  plots$`s4_05_fz_validation` <- plot_fz_validation(
    validated_data, fz_offset = fz_offset
  )

  # ===================================================================
  # Plot 7: Window Width Distribution by RT Segment (Multi-Strategy)
  # ===================================================================

  cat("\n  Preparing Plot 7 & 7B: Window Width Analysis (Multi-Strategy)...\n")

  for (strategy in strategies) {
    # Plot 7: Density + Window Width overlay
    plot7_name <- sprintf("plot7_%s_window_width_distribution", strategy)
    cat(sprintf("  Generating Plot 7 (%s): Density + Width Overlay...\n", toupper(strategy)))
    plots[[plot7_name]] <- plot_window_width_distribution(
      windows_list[[strategy]], validated_data, max_segments_to_show = 6
    )

    # Plot 7B: Window Index + Width bars
    plot7b_name <- sprintf("plot7b_%s_window_index_width", strategy)
    cat(sprintf("  Generating Plot 7B (%s): Window Index Width Bars...\n", toupper(strategy)))
    plots[[plot7b_name]] <- plot_cumulative_window_count(
      windows_list[[strategy]], validated_data, max_segments_to_show = 6
    )
  }

  # ===================================================================
  # S5: Strategy Comparison
  # ===================================================================

  cat("\n  Preparing S5: Strategy Comparison...\n")

  # S5-01: Strategy Comparison Summary Table
  cat("  Generating S5-01: Strategy Comparison Table...\n")
  plots$`s5_01_strategy_table` <- plot_strategy_comparison_table(windows_list)

  # S5-02: Width Ridge Plot
  cat("  Generating S5-02: Width Ridge Plot...\n")
  plots$`s5_02_strategy_ridge` <- plot_strategy_width_ridge(windows_list, validated_data)

  # ===================================================================
  # Plot 15: Per-Precursor DPPP Distribution (Before vs After)
  # ===================================================================

  cat("\n  Generating Plot 15: Per-Precursor DPPP Distribution...\n")
  plots$`plot15_dppp_distribution` <- plot_dppp_distribution(optimization_plan, validated_data)

  # ===================================================================
  # Plot 16: Precursor Load Balance Across Windows
  # ===================================================================

  cat("  Generating Plot 16: Precursor Load Balance...\n")
  plots$`s3_02_load_balance` <- plot_precursor_load_balance(optimized_windows, validated_data)

  # ===================================================================
  # Plot 17: Window Edge Proximity
  # ===================================================================

  cat("  Generating Plot 17: Window Edge Proximity...\n")
  plots$`s4_02_edge_proximity` <- plot_edge_proximity(optimized_windows, validated_data)

  cat("  Generating Plot 17B: Edge Proximity Spatial View...\n")
  plots$`s4_03_edge_proximity_spatial` <- plot_edge_proximity_spatial(optimized_windows, validated_data)

  # ===================================================================
  # S4-04: Charge State Distribution
  # ===================================================================

  cat("  Generating S4-04: Charge State Distribution...\n")
  plots$`s4_04_charge_state` <- plot_charge_mz_distribution(optimized_windows, validated_data)

  cat(sprintf("\nOK All %d plots generated successfully\n\n", length(plots)))

  plot_end <- Sys.time()
  plot_time <- as.numeric(difftime(plot_end, viz_start, units = "secs"))

  # Initialize result structure
  report_files <- list()

  # Step 2: Export individual plots (optional)
  if (create_individual_plots) {
    cat("Step 2: Exporting individual plots...\n")
    individual_files <- export_individual_plots(
      plots, output_dir, plot_format, plot_dpi
    )
    report_files$individual_plots <- individual_files
  } else {
    cat("Step 2: Skipping individual plot export\n")
    report_files$individual_plots <- character()
  }

  # Step 3: Create PDF report (optional)
  if (create_pdf) {
    cat("\nStep 3: Creating PDF report...\n")
    # Build report filename from optimized_windows metadata
    pdf_filename <- if (!is.null(optimized_windows$parameters$window_mode)) {
      format_output_filename(
        type = "report",
        instrument_preset = optimized_windows$metadata$instrument_preset %||%
                            optimization_plan$instrument$preset %||% "custom",
        strategy = NULL,
        window_mode = optimized_windows$parameters$window_mode,
        rt_binning_mode = optimized_windows$parameters$rt_binning_mode %||% "fixed",
        rt_bin_width_min = optimized_windows$parameters$rt_bin_width_min %||% 5,
        ext = "pdf"
      )
    } else {
      "optimization_report.pdf"
    }
    pdf_file <- file.path(output_dir, pdf_filename)
    create_pdf_report(plots, validated_data, optimization_plan, optimized_windows, pdf_file)
    report_files$pdf_report <- pdf_file
  } else {
    cat("\nStep 3: Skipping PDF report creation\n")
    report_files$pdf_report <- NULL
  }

  # NOTE: Method file export has been moved to Stage 3 (export_method_files)
  # Stage 4 now focuses solely on visualization

  # Step 4: Calculate summary statistics
  cat("\nStep 4: Calculating summary statistics...\n")
  summary_stats <- calculate_summary_statistics(validated_data, optimization_plan, optimized_windows)

  viz_end <- Sys.time()
  total_time <- as.numeric(difftime(viz_end, viz_start, units = "secs"))

  # Package results
  result <- structure(
    list(
      plots = plots,

      report_files = report_files,

      summary_statistics = summary_stats,

      metadata = list(
        instrument_type = optimization_plan$instrument$preset,
        mz_strategy = optimized_windows$parameters$mz_strategy,
        window_mode = optimized_windows$parameters$window_mode,
        generation_timestamp = viz_start,
        plot_generation_time = plot_time,
        report_generation_time = total_time - plot_time,
        total_time = total_time
      )
    ),
    class = c("VisualizationResult", "list")
  )

  cat("\n==================================================\n")
  cat(" STAGE 4 COMPLETE (Visualization Only)\n")
  cat("==================================================\n")
  cat(sprintf("OK Generated: %d plots\n", length(plots)))
  if (!is.null(report_files$pdf_report)) {
    cat(sprintf("OK PDF report: %s\n", basename(report_files$pdf_report)))
  }
  cat(sprintf("OK Total time: %.2f seconds\n", total_time))
  cat("\nNote: Method files should be exported using Stage 3's export_method_files()\n")
  cat("\n")

  return(result)
}

# =============================================================================
# Summary Statistics
# =============================================================================

#' Calculate Summary Statistics
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return List of summary statistics
#' @keywords internal
calculate_summary_statistics <- function(validated_data, optimization_plan, optimized_windows) {

  windows <- optimized_windows$windows
  window_stats <- optimized_windows$statistics

  list(
    optimization_metrics = list(
      total_windows = nrow(windows),
      window_count_per_rt = optimization_plan$window_count_per_bin,
      mean_window_width_da = mean(windows$window_width),
      precursor_coverage_pct = window_stats$coverage_percentage,
      mean_precursors_per_window = window_stats$mean_precursors_per_window,
      cv_precursors = window_stats$cv_precursors
    ),

    performance_metrics = list(
      cycle_time_sec = optimization_plan$actual_cycle_time_sec,
      scan_rate_hz = 1 / optimization_plan$actual_cycle_time_sec,
      target_dppp = optimization_plan$parameters$target_dppp,
      current_dppp_satisfaction_pct = optimization_plan$diagnosis$current_satisfaction_ratio * 100,
      required_cycle_time_sec = optimization_plan$required_cycle_time_sec
    ),

    instrument_config = list(
      instrument_type = optimization_plan$instrument$preset,
      mz_strategy = optimized_windows$parameters$mz_strategy,
      window_mode = optimized_windows$parameters$window_mode,
      n_precursors = validated_data$metadata$n_precursors,
      rt_range = validated_data$metadata$rt_range,
      mz_range = validated_data$metadata$mz_range
    )
  )
}

