# =============================================================================
# Main Pipeline: Complete DIA Window Optimization with Visualization
# =============================================================================
# Batch processing pipeline for multiple parquet files
# Generates optimized windows + comprehensive visualization for all strategies
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)

# Source all modules
source("R/utils_common.R")
source("R/instrument_utils.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

# =============================================================================
# Main Function: Process All Parquet Files with Visualization
# =============================================================================

#' Run complete DIA optimization pipeline with visualization
#'
#' @param data_dir Directory containing *min_report.parquet files
#' @param output_base_dir Base output directory (subdirectories per gradient)
#' @param instrument_preset Instrument preset name
#' @param current_cycle_time Current cycle time in seconds (NULL = auto-estimate from gradient)
#' @param target_dppp Target DPPP value (7.0 for Quant, 1.5 for ID)
#' @param target_satisfaction Target satisfaction ratio (0.70-0.90)
#' @param mz_strategies Vector of m/z strategies (default: all 5)
#' @param window_mode Window generation mode (default: "density")
#' @param rt_bin_width_min RT bin width in minutes (default: 5)
#' @param edge_void_buffer_min Void volume buffer in minutes (default: 0.5). Extends first RT bin start.
#' @param edge_wash_min_precursors Wash region merge threshold (default: 30). Merges last bin if sparse.
#' @param width_grid_step Grid step for width digitization in Da (default: 0.5). Set to NULL or 0 to disable.
#' @param create_plots Generate visualizations (default: TRUE)
#' @param create_pdf Generate PDF report (default: TRUE)
#' @param verbose Print detailed progress (default: TRUE)
#'
#' @return List of results for all files
#' @export
run_complete_pipeline <- function(
  data_dir = "data",
  output_base_dir = "output_complete",
  instrument_preset = "fusion_lumos",
  current_cycle_time = NULL,
  target_dppp = 7.0,
  target_satisfaction = 0.70,
  mz_strategies = c("greedy", "kde", "quantile", "coverage", "outlier"),
  window_mode = "density",
  rt_bin_width_min = 5,
  rt_binning_mode = "fixed",
  edge_void_buffer_min = 0.5,
  edge_wash_min_precursors = 30,
  width_grid_step = 0.5,
  create_plots = TRUE,
  create_pdf = TRUE,
  verbose = TRUE
) {

  # ===================================================================
  # Pipeline Header
  # ===================================================================

  if (verbose) {
    cat("\n")
    cat("╔════════════════════════════════════════════════════════════════╗\n")
    cat("║       Complete DIA Window Optimization Pipeline               ║\n")
    cat("║       With Multi-Strategy Visualization (24 Plots)            ║\n")
    cat("╚════════════════════════════════════════════════════════════════╝\n\n")

    cat("Configuration:\n")
    cat("─────────────────────────────────────────────────────────────\n")
    cat(sprintf("  Data directory    : %s\n", data_dir))
    cat(sprintf("  Output directory  : %s\n", output_base_dir))
    cat(sprintf("  Instrument        : %s\n", instrument_preset))
    cat(sprintf("  Current cycle time: %s\n",
                ifelse(is.null(current_cycle_time), "Auto-detect", sprintf("%.3f sec", current_cycle_time))))
    cat(sprintf("  Target DPPP       : %.1f\n", target_dppp))
    cat(sprintf("  Target satisfaction: %.0f%%\n", target_satisfaction * 100))
    cat(sprintf("  m/z strategies    : %s\n", paste(mz_strategies, collapse = ", ")))
    cat(sprintf("  Window mode       : %s\n", window_mode))
    cat(sprintf("  RT bin width      : %.0f min\n", rt_bin_width_min))
    cat(sprintf("  RT binning mode   : %s\n", rt_binning_mode))
    cat(sprintf("  Edge void buffer  : %.1f min\n", edge_void_buffer_min))
    cat(sprintf("  Edge wash threshold: %d precursors\n", edge_wash_min_precursors))
    cat(sprintf("  Create plots      : %s\n", ifelse(create_plots, "Yes (24 plots)", "No")))
    cat(sprintf("  Create PDF        : %s\n", ifelse(create_pdf, "Yes", "No")))
    cat("\n")
  }

  # ===================================================================
  # Find Input Files
  # ===================================================================

  # Find all *min_report.parquet files
  parquet_files <- list.files(
    path = data_dir,
    pattern = ".*min_report\\.parquet$",
    full.names = TRUE
  )

  if (length(parquet_files) == 0) {
    stop(sprintf("No *min_report.parquet files found in %s", data_dir))
  }

  if (verbose) {
    cat(sprintf("Found %d parquet file(s):\n", length(parquet_files)))
    for (f in parquet_files) {
      cat(sprintf("  - %s\n", basename(f)))
    }
    cat("\n")
  }

  # ===================================================================
  # Process All Files
  # ===================================================================

  all_results <- list()

  for (input_file in parquet_files) {

    gradient_name <- extract_gradient_name(input_file)

    if (verbose) {
      cat("\n")
      cat("═══════════════════════════════════════════════════════════════\n")
      cat(sprintf("Processing: %s (%s gradient)\n", basename(input_file), gradient_name))
      cat("═══════════════════════════════════════════════════════════════\n\n")
    }

    # Create gradient-specific output directory
    output_dir <- file.path(output_base_dir, gradient_name)
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

    # ==================================================================
    # Stage 1: Data Validation
    # ==================================================================

    if (verbose) {
      cat("Stage 1: Data Validation\n")
      cat("─────────────────────────────────────────────────────────────\n")
    }

    pipeline_start <- Sys.time()

    validated_data <- create_validated_dataset(
      proteome_file = input_file,
      apply_quality_filters = TRUE
    )

    if (verbose) {
      cat(sprintf("✅ Validated %s precursors\n",
                  format(nrow(validated_data$data), big.mark = ",")))
    }

    # ==================================================================
    # Stage 2: Optimization Planning
    # ==================================================================

    if (verbose) {
      cat("\nStage 2: Optimization Planning\n")
      cat("─────────────────────────────────────────────────────────────\n")
    }

    # Use provided cycle time if available, otherwise estimate
    if (!is.null(current_cycle_time)) {
      initial_cycle_time <- current_cycle_time
      if (verbose) {
        cat(sprintf("Using provided cycle time: %.3f sec\n", initial_cycle_time))
      }
    } else {
      initial_cycle_time <- estimate_cycle_time(gradient_name)
      if (verbose) {
        cat(sprintf("Estimated cycle time: %.3f sec (auto-detected from gradient)\n", initial_cycle_time))
      }
    }

    optimization_plan <- plan_optimization(
      validated_data = validated_data,
      current_cycle_time = initial_cycle_time,
      instrument_preset = instrument_preset,
      target_dppp = target_dppp,
      target_satisfaction = target_satisfaction,
      dppp_tolerance = 0.0,
      load_factor = 0.8,
      ms1_scans_per_cycle = NULL
    )

    if (verbose) {
      cat(sprintf("✅ Planning complete:\n"))
      cat(sprintf("   Required cycle time: %.3f sec\n",
                  optimization_plan$required_cycle_time_sec))
      cat(sprintf("   Windows per RT bin: %d\n",
                  optimization_plan$window_count_per_bin))
      cat(sprintf("   Current satisfaction: %.1f%%\n",
                  optimization_plan$diagnosis$current_satisfaction_ratio * 100))
    }

    # ==================================================================
    # Stage 3: Window Optimization (All Strategies)
    # ==================================================================

    if (verbose) {
      cat("\nStage 3: Window Optimization (All Strategies)\n")
      cat("─────────────────────────────────────────────────────────────\n")
    }

    windows_list <- list()

    for (strategy in mz_strategies) {

      if (verbose) {
        cat(sprintf("  Generating windows for %s strategy...\n", toupper(strategy)))
      }

      windows_result <- optimize_windows(
        validated_data = validated_data,
        optimization_plan = optimization_plan,
        rt_bin_width_min = rt_bin_width_min,
        mz_strategy = strategy,
        window_mode = window_mode,
        rt_binning_mode = rt_binning_mode,
        edge_void_buffer_min = edge_void_buffer_min,
        edge_wash_min_precursors = edge_wash_min_precursors,
        quantile_lower = 0.05,
        quantile_upper = 0.95,
        target_coverage = 0.95,
        outlier_threshold = 3.0,
        smoothing_window = 3,
        polynomial_order = 2,
        min_width_da = 2,
        max_width_da = 100,
        overlap_percentage = 0,
        width_grid_step = width_grid_step
      )

      windows_list[[strategy]] <- windows_result

      # Export method file for each strategy
      method_filename <- format_output_filename(
        type = "method",
        instrument_preset = instrument_preset,
        strategy = strategy,
        window_mode = window_mode,
        rt_binning_mode = rt_binning_mode,
        rt_bin_width_min = rt_bin_width_min
      )
      method_path <- file.path(output_dir, method_filename)

      export_windows_to_csv(
        optimized_windows = windows_result,
        output_file = method_path,
        validated_data = validated_data,
        optimization_plan = optimization_plan,
        instrument_type = instrument_preset
      )

      if (verbose) {
        cat(sprintf("     ✅ %s: %d windows, %.1f%% coverage, %.2f ± %.2f Da\n",
                    toupper(strategy),
                    nrow(windows_result$windows),
                    windows_result$statistics$coverage_percentage,
                    windows_result$statistics$window_width_mean,
                    windows_result$statistics$window_width_sd))
        cat(sprintf("     📄 Method file: %s\n", method_filename))
      }
    }

    if (verbose) {
      cat(sprintf("\n✅ All %d strategies completed\n", length(mz_strategies)))
    }

    # ==================================================================
    # Stage 4: Visualization & Reporting
    # ==================================================================

    if (create_plots) {

      if (verbose) {
        cat("\nStage 4: Visualization & Reporting\n")
        cat("─────────────────────────────────────────────────────────────\n")
        cat("Generating 24 plots across 8 categories...\n")
      }

      viz_start <- Sys.time()

      viz_result <- generate_visualizations(
        validated_data = validated_data,
        optimization_plan = optimization_plan,
        optimized_windows = windows_list[[1]],  # Use first strategy as reference
        windows_list = windows_list,  # All 4 strategies for multi-strategy plots
        output_dir = output_dir,
        create_pdf = create_pdf,
        create_individual_plots = TRUE,
        plot_format = "png",
        plot_dpi = 300
      )

      viz_end <- Sys.time()
      viz_time <- as.numeric(difftime(viz_end, viz_start, units = "secs"))

      if (verbose) {
        cat(sprintf("✅ Generated %d plots in %.1f seconds\n",
                    length(viz_result$plots), viz_time))
        cat(sprintf("   Output directory: %s\n", output_dir))
        if (create_pdf) {
          cat(sprintf("   PDF report: %s\n",
                      basename(viz_result$report_files$pdf_report)))
        }
      }

    } else {
      viz_result <- NULL
    }

    pipeline_end <- Sys.time()
    total_time <- as.numeric(difftime(pipeline_end, pipeline_start, units = "secs"))

    # Store results
    all_results[[gradient_name]] <- list(
      validated_data = validated_data,
      optimization_plan = optimization_plan,
      windows_list = windows_list,
      viz_result = viz_result,
      output_dir = output_dir,
      timing = list(
        total_time = total_time,
        viz_time = ifelse(create_plots, viz_time, 0)
      )
    )

    if (verbose) {
      cat(sprintf("\n✅ %s complete: %.1f seconds\n", gradient_name, total_time))
    }
  }

  # ===================================================================
  # Generate Summary Report
  # ===================================================================

  if (verbose) {
    cat("\n")
    cat("╔════════════════════════════════════════════════════════════════╗\n")
    cat("║                   GENERATING SUMMARY REPORT                    ║\n")
    cat("╚════════════════════════════════════════════════════════════════╝\n\n")
  }

  # Create summary table
  summary_rows <- list()

  for (gradient in names(all_results)) {
    result <- all_results[[gradient]]

    for (strategy in names(result$windows_list)) {
      windows_result <- result$windows_list[[strategy]]
      stats <- windows_result$statistics
      params <- windows_result$parameters

      if (verbose) {
        cat(sprintf("  - Strategy: %s (%d windows, %.1f%% coverage, %.2f ± %.2f Da)\n",
                    toupper(strategy),
                    nrow(windows_result$windows),
                    stats$coverage_percentage,
                    stats$window_width_mean,
                    stats$window_width_sd))
      }

      # Create row with proper scalar values, handling NULL/length-0 fields
      satisfaction_ratio <- result$optimization_plan$diagnosis$current_satisfaction_ratio
      if (is.null(satisfaction_ratio) || length(satisfaction_ratio) == 0) {
        satisfaction_pct <- NA
      } else {
        satisfaction_pct <- as.numeric(round(satisfaction_ratio * 100, 1))
      }

      new_row <- data.frame(
        Gradient = as.character(gradient),
        Precursors = as.integer(nrow(result$validated_data$data)),
        Strategy = as.character(strategy),
        Mode = as.character(params$window_mode),
        Total_Windows = as.integer(nrow(windows_result$windows)),
        RT_Bins = as.integer(windows_result$rt_binning$n_bins),
        Mean_Width_Da = as.numeric(round(stats$window_width_mean, 2)),
        SD_Width_Da = as.numeric(round(stats$window_width_sd, 2)),
        CV_Width = as.numeric(round(stats$window_width_sd / stats$window_width_mean, 3)),
        Coverage_Pct = as.numeric(round(stats$coverage_percentage, 1)),
        Mean_Precursors_Per_Window = as.numeric(round(stats$mean_precursors_per_window, 1)),
        CV_Precursors = as.numeric(round(stats$cv_precursors, 3)),
        Cycle_Time_Sec = as.numeric(round(result$optimization_plan$required_cycle_time_sec, 3)),
        Satisfaction_Pct = satisfaction_pct,
        Processing_Time_Sec = as.numeric(round(result$timing$total_time, 1)),
        Output_Dir = as.character(basename(result$output_dir)),
        stringsAsFactors = FALSE
      )

      summary_rows[[length(summary_rows) + 1]] <- new_row
    }
  }

  # Check if we have any summary rows
  if (length(summary_rows) == 0) {
    cat("⚠️ Warning: No summary data to generate\n")
    return(all_results)
  }

  summary_table <- do.call(rbind, summary_rows)

  # Print summary
  if (verbose) {
    print(summary_table)
    cat("\n")
  }

  # Save summary
  summary_path <- file.path(output_base_dir, "batch_processing_summary.csv")
  write.csv(summary_table, summary_path, row.names = FALSE)

  if (verbose) {
    cat(sprintf("✅ Summary saved to: %s\n", summary_path))
  }

  # ===================================================================
  # Final Report
  # ===================================================================

  if (verbose) {
    cat("\n")
    cat("╔════════════════════════════════════════════════════════════════╗\n")
    cat("║                  PIPELINE COMPLETE                             ║\n")
    cat("╚════════════════════════════════════════════════════════════════╝\n\n")

    cat("Summary:\n")
    cat("─────────────────────────────────────────────────────────────\n")
    cat(sprintf("✅ Processed files     : %d\n", length(parquet_files)))
    cat(sprintf("✅ Total strategies    : %d per file\n", length(mz_strategies)))
    cat(sprintf("✅ Method files        : %d\n", nrow(summary_table)))
    if (create_plots) {
      cat(sprintf("✅ Plots per file      : 24\n"))
      cat(sprintf("✅ Total plots         : %d\n", length(parquet_files) * 24))
    }
    cat(sprintf("✅ Output directory    : %s/\n", output_base_dir))
    cat("\n")

    cat("Output Structure:\n")
    cat("─────────────────────────────────────────────────────────────\n")
    for (gradient in names(all_results)) {
      cat(sprintf("  %s/\n", gradient))
      cat(sprintf("    ├── *_method.csv (4 files - one per strategy)\n"))
      if (create_plots) {
        cat(sprintf("    ├── plot*.png (24 plots)\n"))
        if (create_pdf) {
          cat(sprintf("    └── optimization_report.pdf\n"))
        }
      }
    }
    cat(sprintf("  └── batch_processing_summary.csv\n"))
    cat("\n")

    cat("Next Steps:\n")
    cat("─────────────────────────────────────────────────────────────\n")
    cat("  1. Review plots in output_complete/[gradient]/ directories\n")
    cat("  2. Compare strategies using Plot 8 (Ridge/Box/CDF)\n")
    cat("  3. Select optimal strategy based on your priorities:\n")
    cat("     - QUANTILE/SMOOTHING: Best spectral quality (~14-16 Da)\n")
    cat("     - OUTLIER: Maximum coverage (97%, ~18-20 Da)\n")
    cat("     - COVERAGE: Balanced approach (95%, ~17 Da)\n")
    cat("  4. Import *_method.csv to Thermo Orbitrap for acquisition\n")
    cat("\n")
  }

  return(invisible(all_results))
}

# =============================================================================
# Usage Examples
# =============================================================================

# Example 1: Run with all defaults (recommended)
# results <- run_complete_pipeline()

# Example 2: Custom parameters
# results <- run_complete_pipeline(
#   data_dir = "data",
#   output_base_dir = "output_complete",
#   instrument_preset = "fusion_lumos",
#   target_dppp = 7.0,
#   target_satisfaction = 0.70,
#   mz_strategies = c("greedy", "kde", "quantile", "coverage", "outlier"),
#   window_mode = "density",
#   rt_bin_width_min = 5,
#   create_plots = TRUE,
#   create_pdf = TRUE
# )

# Example 3: Quick test without plots
# results <- run_complete_pipeline(
#   create_plots = FALSE,
#   create_pdf = FALSE
# )

# Example 4: Specific strategies only
# results <- run_complete_pipeline(
#   mz_strategies = c("quantile", "outlier")
# )

cat("✅ main.R loaded successfully\n")
cat("   Main function: run_complete_pipeline()\n")
cat("   Usage: results <- run_complete_pipeline()\n")
cat("   Default: Processes all *min_report.parquet in data/ directory\n")
cat("   Output: Complete pipeline with 4 strategies + 24 plots per file\n")
