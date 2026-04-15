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
  plots$`s1_06_dppp_comparison` <- plot_dppp_comparison(optimization_plan, validated_data)

  # Plot 1B: Acquisition Diagnosis Table (primary for PDF)
  plots$`s1_04_dppp_diagnosis` <- plot_dppp_diagnosis_table(optimization_plan, validated_data)

  # Legacy versions (kept for individual export, not used in PDF)
  cat("  Generating Plot 1B curve: DPPP vs Cycle Time (legacy)...\n")
  plots$`s1_07_dppp_curve` <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)
  cat("  Generating Plot 1B+6: DPPP & Satisfaction Combined (legacy)...\n")
  plots$`s1_08_dppp_satisfaction` <- plot_dppp_satisfaction_combined(optimization_plan, validated_data)

  # Plot 2: RT x m/z Intensity/Density Heatmap
  cat("  Generating Plot 2: RT x m/z Heatmap...\n")
  plots$`s1_01_density_heatmap` <- plot_rt_mz_density_heatmap(validated_data)

  # Plot 6: Satisfaction vs Cycle Time Curve
  cat("  Generating Plot 6: Satisfaction Curve...\n")
  plots$`s1_05_satisfaction_curve` <- plot_satisfaction_curve(optimization_plan, validated_data)

  # Plot 2B: RT Histogram (supplementary — kept for individual export, removed from PDF)
  cat("  Generating Plot 2B: RT Histogram...\n")
  plots$`s1_09_rt_histogram` <- plot_rt_histogram(validated_data)
  plots$`s1_10_rt_histogram_5min` <- plot_rt_histogram_binned(validated_data, bin_width_min = 5)

  # S1-03: m/z Density Overlay by RT Segment
  cat("  Generating S1-03: m/z Density Overlay...\n")
  plots$`s1_03_mz_density` <- plot_mz_normalized_density(optimized_windows, validated_data)

  # S2-02: Window m/z Range Across Gradient (active strategy)
  cat("  Generating S2-02: Window m/z Range...\n")
  plots$`s2_02_window_layout` <- plot_window_width_distribution(
    optimized_windows, validated_data
  )

  # S2-03: Window Index Width Bars (active strategy)
  cat("  Generating S2-03: Window Index Width Bars...\n")
  plots$`s2_03_window_index` <- plot_cumulative_window_count(
    optimized_windows, validated_data, max_segments_to_show = 6
  )

  # ===================================================================
  # In-Silico Evaluation (runs first — results shared with plots below)
  # ===================================================================

  cat("\n  Running in-silico window evaluation...\n")
  evaluation_result <- tryCatch(
    evaluate_windows(optimized_windows, validated_data, optimization_plan),
    error = function(e) {
      cat("  [!] Evaluation failed:", e$message, "\n")
      NULL
    }
  )

  # S2-05: Precursor Distribution Across Windows
  # (reuses evaluation per-window counts when available)
  cat("  Generating S2-05: Precursor Distribution...\n")
  plots$`s2_05_precursor_distribution` <- plot_precursors_per_window(
    optimized_windows, validated_data, optimization_plan,
    evaluation_result = evaluation_result
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
    plot_name <- sprintf("app_b_%s_mz_excluded", strategy)
    cat(sprintf("  Generating Plot 4 (%s): m/z Excluded Regions...\n", toupper(strategy)))
    plots[[plot_name]] <- plot_mz_distribution_with_exclusions(
      windows_list[[strategy]], validated_data, max_bins_to_show = 6
    )
  }

  # Plot 4E: All-strategy width comparison
  cat("  Generating Plot 4E: Width Comparison (All Strategies)...\n")
  plots$`app_b_width_all_strategies` <- plot_mz_width_comparison_all_strategies(
    windows_list, validated_data
  )

  # Strategy Width Profile (overlay line chart)
  cat("  Generating S5-04: Strategy Width Profile...\n")
  plots$`s3_04_width_profile` <- plot_strategy_width_profile(
    windows_list, validated_data
  )

  # Plot 6B: Optimization Impact Summary (Before/After Dashboard)
  cat("  Generating Plot 6B: Optimization Impact Summary...\n")
  plots$`s2_01_impact_summary` <- plot_optimization_impact(optimization_plan, optimized_windows, validated_data)

  # Plot 9: RT Bin Quality Heatmap (kept for individual export, removed from PDF)
  cat("  Generating Plot 9: RT Bin Quality Heatmap...\n")
  plots$`s2_07_rt_bin_quality` <- plot_rt_bin_quality_heatmap(
    optimized_windows, validated_data, optimization_plan
  )

  # Plot 2C: RT x m/z Heatmap with m/z Range Overlay (per-strategy grid)
  cat("  Generating Plot 2C: Heatmap with m/z Range (All Strategies)...\n")
  plots$`s3_03_heatmap_boundary` <- plot_density_with_mz_ranges_grid(
    windows_list, validated_data
  )

  # Plot 10: Removed — redundant with Plot 7 (window width distribution)

  # Plot 11: RT Change Point Validation (only when adaptive RT binning used)
  rt_binning_mode <- optimized_windows$rt_binning$rt_binning_mode %||% "fixed"
  if (rt_binning_mode == "adaptive") {
    cat("  Generating Plot 11: RT Change Point Validation...\n")
    plots$`app_d_changepoint` <- plot_rt_changepoint_validation(
      validated_data, optimized_windows
    )

    cat("  Generating Plot 11B: KS Statistic Trace...\n")
    plots$`app_d_ks_trace` <- plot_ks_statistic_trace(optimized_windows)
  }

  # ===================================================================
  # Plot 12-14: Window Verification (Tiling, Alignment, FZ Zoom)
  # ===================================================================

  # Plot 12: Tiling Coverage Map (staggered mode only — shows cycle interleaving)
  if (identical(optimized_windows$parameters$window_mode, "staggered")) {
    cat("  Generating Plot 12: Tiling Coverage Map (Staggered Interleaving)...\n")
    plots$`s2_tiling_coverage` <- plot_tiling_coverage_map(
      optimized_windows, validated_data
    )
  }

  # Plot 13: Alignment Density
  cat("  Generating Plot 13: Alignment Density (Precursor-Window Alignment)...\n")
  plots$`app_a_alignment_density` <- plot_alignment_density(
    optimized_windows, validated_data
  )

  # Plot 14: FZ Zoom-in (always-on: isotope envelope protection is default)
  fz_offset <- optimized_windows$parameters$fz_offset %||% 0.25
  cat("  Generating Plot 14: Forbidden Zone Zoom-in...\n")
  plots$`app_a_fz_zoom` <- plot_fz_zoom(
    optimized_windows, validated_data, fz_offset = fz_offset
  )

  # Plot 14B: FZ Validation (mass defect histogram)
  cat("  Generating Plot 14B: Forbidden Zone Validation...\n")
  plots$`app_a_fz_validation` <- plot_fz_validation(
    validated_data, fz_offset = fz_offset
  )

  # ===================================================================
  # Plot 7: Window Width Distribution by RT Segment (Multi-Strategy)
  # ===================================================================

  cat("\n  Preparing Plot 7 & 7B: Window Width Analysis (Multi-Strategy)...\n")

  for (strategy in strategies) {
    # Plot 7: Density + Window Width overlay
    plot7_name <- sprintf("app_b_%s_window_layout", strategy)
    cat(sprintf("  Generating Plot 7 (%s): Density + Width Overlay...\n", toupper(strategy)))
    plots[[plot7_name]] <- plot_window_width_distribution(
      windows_list[[strategy]], validated_data
    )

    # Plot 7B: Window Index + Width bars
    plot7b_name <- sprintf("app_b_%s_window_index", strategy)
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
  plots$`s3_01_strategy_table` <- plot_strategy_comparison_table(windows_list)

  # S5-02: Width Ridge Plot
  cat("  Generating S5-02: Width Ridge Plot...\n")
  plots$`s3_02_strategy_ridge` <- plot_strategy_width_ridge(windows_list, validated_data)

  # ===================================================================
  # Plot 15: Per-Precursor DPPP Distribution (Before vs After)
  # ===================================================================

  cat("\n  Generating Plot 15: Per-Precursor DPPP Distribution...\n")
  plots$`s1_11_dppp_distribution` <- plot_dppp_distribution(optimization_plan, validated_data)

  # ===================================================================
  # Plot 16: Precursor Load Balance Across Windows
  # ===================================================================

  cat("  Generating Plot 16: Precursor Load Balance...\n")
  plots$`s2_04_load_balance` <- plot_precursor_load_balance(optimized_windows, validated_data)

  # ===================================================================
  # Plot 17: Window Edge Proximity
  # ===================================================================

  cat("  Generating Plot 17: Window Edge Proximity...\n")
  plots$`app_a_edge_proximity` <- plot_edge_proximity(optimized_windows, validated_data)

  cat("  Generating Plot 17B: Edge Proximity Spatial View...\n")
  plots$`app_a_edge_spatial` <- plot_edge_proximity_spatial(optimized_windows, validated_data)

  # ===================================================================
  # App-A: Charge State Distribution
  # ===================================================================

  cat("  Generating App-A: Charge State Distribution...\n")
  plots$`app_a_charge_state` <- plot_charge_mz_distribution(optimized_windows, validated_data)

  # S2-06: Temporal Density (Co-Elution Proxy)
  # Compute baseline density for before/after comparison
  baseline_density <- NULL
  if (!is.null(evaluation_result)) {
    baseline_density <- tryCatch({
      precursors <- validated_data$data
      windows <- optimized_windows$windows
      n_bins <- length(unique(windows$rt_segment_id))
      # Estimate baseline window count from current acquisition conditions
      current_ct <- optimization_plan$diagnosis$current_cycle_time_sec
      ms2_time <- optimization_plan$instrument$ms2_scan_time_ms / 1000
      baseline_n <- if (!is.na(current_ct) && !is.na(ms2_time) && ms2_time > 0) {
        as.integer(floor(current_ct / ms2_time))
      } else {
        as.integer(nrow(windows) / n_bins)
      }
      # Build naive fixed windows per RT bin
      rt_bins_df <- unique(windows[, c("rt_start", "rt_end", "rt_segment_id")])
      naive_list <- lapply(seq_len(nrow(rt_bins_df)), function(i) {
        bin_prec <- precursors[precursors$RT.Apex >= rt_bins_df$rt_start[i] &
                               precursors$RT.Apex <= rt_bins_df$rt_end[i], ]
        if (nrow(bin_prec) < 2) return(NULL)
        mz_rng <- range(bin_prec$Precursor.Mz, na.rm = TRUE)
        n_win <- min(baseline_n, 500L)
        if (n_win < 1) return(NULL)
        bw <- generate_fixed_windows_internal(
          mz_min = mz_rng[1], mz_max = mz_rng[2],
          n_windows = n_win, min_width_da = 1, max_width_da = 500, fz_offset = 0
        )
        bw$rt_start <- rt_bins_df$rt_start[i]
        bw$rt_end   <- rt_bins_df$rt_end[i]
        bw
      })
      naive_windows <- do.call(rbind, naive_list)
      if (is.null(naive_windows) || nrow(naive_windows) < 1) stop("no baseline windows")
      td <- calculate_precursor_temporal_density(
        precursor_mz    = precursors$Precursor.Mz,
        precursor_rt    = precursors$RT.Apex,
        precursor_fwhm  = precursors$FWHM,
        window_mz_start = naive_windows$mz_start,
        window_mz_end   = naive_windows$mz_end,
        window_rt_start = naive_windows$rt_start,
        window_rt_end   = naive_windows$rt_end
      )
      list(
        median = median(td$density_max, na.rm = TRUE),
        mean   = mean(td$density_max, na.rm = TRUE),
        max    = max(td$density_max, na.rm = TRUE),
        n_per_bin = baseline_n
      )
    }, error = function(e) NULL)

    cat("  Generating S2-06: Temporal Density...\n")
    plots$`s2_06_temporal_density` <- plot_temporal_density(
      evaluation_result, baseline_density = baseline_density
    )
  }

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

