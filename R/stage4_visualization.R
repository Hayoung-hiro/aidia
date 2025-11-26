# stage4_visualization.R - Stage 4: Visualization & Reporting (Orchestrator)
#
# Purpose: Generate comprehensive visualizations and reports for DIA window optimization
#
# Version: 4.1 (Modularized architecture)
#
# Architecture:
#   This file is the orchestrator that sources modular plot functions from R/plots/
#   and coordinates the overall visualization pipeline.
#
# Sourced Modules:
#   - R/plots/plot_dppp.R: DPPP distribution comparison plots
#   - R/plots/plot_density.R: Density heatmap and normalized density
#   - R/plots/plot_histogram.R: RT distribution histogram
#   - R/plots/plot_coverage.R: Coverage map with m/z overlay
#   - R/plots/plot_window.R: Window width distribution
#   - R/plots/plot_satisfaction.R: Satisfaction vs cycle time curve
#   - R/stage4_export.R: Export and PDF report functions
#
# External Modules (from R/ root):
#   - R/plot2b_rt_histogram.R: Binned RT histogram
#   - R/plot4_*.R: m/z range optimization plots
#   - R/plot5_*.R: Coverage map grid
#   - R/plot7_*.R: Window width distribution
#   - R/plot8_*.R: Strategy width comparison
#
# Main Functions:
#   1. generate_visualizations() - Main orchestration function
#   2. calculate_summary_statistics() - Calculate optimization metrics
#   3. theme_dia_optimizer() - Custom ggplot2 theme
#
# Input: Refactored pipeline outputs
#   - validated_data (ValidatedData from Stage 1)
#   - optimization_plan (OptimizationPlan from Stage 2)
#   - optimized_windows (OptimizedWindows from Stage 3)
#
# Output: VisualizationResult with plots, reports, and method files

library(ggplot2)
library(dplyr)
library(tidyr)
library(viridis)
library(scales)
library(gridExtra)
library(grid)

# =============================================================================
# Source Dependencies
# =============================================================================

# Load common utilities and S3 classes
if (!exists("print_header")) {
  if (file.exists("R/utils_common.R")) {
    source("R/utils_common.R")
  }
}

# =============================================================================
# Source Modular Plot Functions
# =============================================================================

# Core plot modules (R/plots/)
plot_modules <- c(
  "R/plots/plot_dppp.R",
  "R/plots/plot_density.R",
  "R/plots/plot_histogram.R",
  "R/plots/plot_coverage.R",
  "R/plots/plot_window.R",
  "R/plots/plot_satisfaction.R"
)

for (module in plot_modules) {
  if (file.exists(module)) {
    source(module)
  }
}

# Export functions
if (file.exists("R/stage4_export.R")) {
  source("R/stage4_export.R")
}

# External plot modules (from R/ root - for multi-strategy comparison)
external_modules <- c(
  "R/plot2b_rt_histogram.R",
  "R/plot4_mz_distribution_excluded.R",
  "R/plot4_mz_width_comparison.R",
  "R/plot4_mz_range_optimization.R",
  "R/plot5_density_with_mz_ranges.R",
  "R/plot7_window_width_distribution.R",
  "R/plot8_strategy_width_comparison.R"
)

for (module in external_modules) {
  if (file.exists(module)) {
    source(module)
  }
}

# =============================================================================
# Custom Theme
# =============================================================================

#' Custom ggplot2 Theme for DIA Optimizer
#'
#' @export
theme_dia_optimizer <- function() {
  theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      plot.caption = element_text(size = 9, color = "gray50", hjust = 0),
      axis.title = element_text(size = 11),
      axis.text = element_text(size = 10),
      legend.title = element_text(face = "bold", size = 10),
      legend.text = element_text(size = 9),
      panel.grid.minor = element_blank()
    )
}

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

  # Plot 1: DPPP Comparison - Both versions
  cat("  Generating Plot 1A: DPPP Comparison (Simple)...\n")
  plots$`plot1a_dppp_comparison_simple` <- plot_dppp_comparison(optimization_plan, validated_data)

  cat("  Generating Plot 1B: DPPP Comparison (Enhanced)...\n")
  plots$`plot1b_dppp_comparison_enhanced` <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)

  # Plot 2: RT x m/z Density Heatmap
  cat("  Generating Plot 2: RT x m/z Density Heatmap...\n")
  plots$`plot2_rt_mz_density_heatmap` <- plot_rt_mz_density_heatmap(validated_data)

  # Plot 2B: RT Histogram (supplementary)
  if (exists("plot_rt_histogram")) {
    cat("  Generating Plot 2B: RT Histogram...\n")
    plots$`plot2b_rt_histogram_continuous` <- plot_rt_histogram(validated_data)
    if (exists("plot_rt_histogram_binned")) {
      plots$`plot2b_rt_histogram_5min` <- plot_rt_histogram_binned(validated_data, bin_width_min = 5)
    }
  }

  # Plot 3: m/z Density Overlay by RT Segment
  cat("  Generating Plot 3: m/z Density Overlay...\n")
  plots$`plot3_mz_density_overlay` <- plot_mz_normalized_density(optimized_windows, validated_data)

  # ===================================================================
  # Plot 4: Multi-Strategy m/z Range Optimization Comparison
  # ===================================================================

  cat("\n  Preparing Plot 4: Multi-Strategy Comparison...\n")

  strategies <- c("quantile", "smoothing", "outlier", "coverage")

  # Use pre-computed windows_list if provided, otherwise compute
  if (is.null(windows_list)) {
    cat("  Running optimization with all 4 m/z strategies...\n")
    windows_list <- list()

    # Load Stage 3 module for optimization
    if (!exists("optimize_windows")) {
      if (file.exists("R/stage3_window_optimization.R")) {
        source("R/stage3_window_optimization.R")
      }
    }

    # Generate windows for each strategy
    for (strategy in strategies) {
      cat(sprintf("    - Optimizing with '%s' strategy...\n", strategy))
      windows_list[[strategy]] <- optimize_windows(
        validated_data = validated_data,
        optimization_plan = optimization_plan,
        rt_bin_width_min = optimized_windows$parameters$rt_bin_width_min,
        mz_strategy = strategy,
        window_mode = optimized_windows$parameters$window_mode,
        quantile_lower = 0.05,
        quantile_upper = 0.95,
        outlier_threshold = 3.0,
        smoothing_window = 7,
        polynomial_order = 3,
        target_coverage = 0.95
      )
    }
  } else {
    cat("  Using pre-computed windows for all 4 strategies (skipping re-optimization)...\n")
  }

  # Plot 4A-4D: Individual strategy m/z excluded regions
  if (exists("plot_mz_distribution_with_exclusions")) {
    for (strategy in strategies) {
      plot_name <- sprintf("plot4_%s_mz_excluded", strategy)
      cat(sprintf("  Generating Plot 4 (%s): m/z Excluded Regions...\n", toupper(strategy)))
      plots[[plot_name]] <- plot_mz_distribution_with_exclusions(
        windows_list[[strategy]], validated_data, max_bins_to_show = 6
      )
    }
  }

  # Plot 4E: All-strategy width comparison
  if (exists("plot_mz_width_comparison_all_strategies")) {
    cat("  Generating Plot 4E: Width Comparison (All Strategies)...\n")
    plots$`plot4e_mz_width_all_strategies` <- plot_mz_width_comparison_all_strategies(
      windows_list, validated_data
    )
  }

  # Plot 5: Coverage Map 2x2 Grid (multi-strategy comparison)
  if (exists("plot_density_with_mz_ranges_grid")) {
    cat("  Generating Plot 5: Coverage Map 2x2 Grid (All Strategies)...\n")
    plots$`plot5_coverage_map_2x2` <- plot_density_with_mz_ranges_grid(
      windows_list, validated_data
    )
  } else if (exists("plot_density_with_mz_range")) {
    cat("  Generating Plot 5: Coverage Map (Single Strategy - fallback)...\n")
    plots$`plot5_coverage_map_single` <- plot_density_with_mz_range(optimized_windows, validated_data)
  }

  # Plot 6: Satisfaction Curve
  cat("  Generating Plot 6: Satisfaction vs Cycle Time Curve...\n")
  plots$`plot6_satisfaction_curve` <- plot_satisfaction_curve(optimization_plan, validated_data)

  # ===================================================================
  # Plot 7: Window Width Distribution by RT Segment (Multi-Strategy)
  # ===================================================================

  if (exists("plot_window_width_distribution") && exists("plot_cumulative_window_count")) {
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
  }

  # ===================================================================
  # Plot 8: Strategy Width Comparison (Ridge, Box, CDF)
  # ===================================================================

  if (exists("plot_strategy_width_ridge") && exists("plot_strategy_width_boxplot") && exists("plot_strategy_width_cdf")) {
    cat("\n  Preparing Plot 8: Strategy Width Comparison (3 visualization types)...\n")

    # Plot 8A: Ridge plot
    cat("  Generating Plot 8A: Ridge Plot...\n")
    plots$`plot8a_strategy_width_ridge` <- plot_strategy_width_ridge(windows_list, validated_data)

    # Plot 8B: Box plot
    cat("  Generating Plot 8B: Box Plot...\n")
    plots$`plot8b_strategy_width_boxplot` <- plot_strategy_width_boxplot(windows_list, validated_data)

    # Plot 8C: CDF plot
    cat("  Generating Plot 8C: CDF Plot...\n")
    plots$`plot8c_strategy_width_cdf` <- plot_strategy_width_cdf(windows_list, validated_data)
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
    pdf_file <- file.path(output_dir, "optimization_report.pdf")
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
#' @export
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

# =============================================================================
# Module Load Message
# =============================================================================

cat("OK Stage 4 (Visualization & Reporting) loaded successfully\n")
cat("   Version: 4.1 (Modularized architecture)\n")
cat("   Main function: generate_visualizations()\n")
cat("   Sourced modules:\n")
cat("     - R/plots/plot_dppp.R\n")
cat("     - R/plots/plot_density.R\n")
cat("     - R/plots/plot_histogram.R\n")
cat("     - R/plots/plot_coverage.R\n")
cat("     - R/plots/plot_window.R\n")
cat("     - R/plots/plot_satisfaction.R\n")
cat("     - R/stage4_export.R\n")
cat("   Dependencies: ggplot2, dplyr, tidyr, viridis, scales, gridExtra, grid\n")
