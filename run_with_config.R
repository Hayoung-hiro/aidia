# =============================================================================
# JSON Configuration-Based Batch Processing Pipeline
# =============================================================================
# Uses JSON configuration files to control optimization parameters
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)

# Source modules
source("R/config_loader.R")
source("R/instrument_utils.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/utils_common.R")

# =============================================================================
# Main Optimization Function
# =============================================================================

#' Run DIA window optimization with JSON configuration
#'
#' @param config_path Path to JSON configuration file
#' @return List of results for all combinations
#' @export
#'
#' @examples
#' # Use default configuration
#' results <- run_optimization("config/optimization_config.json")
#'
#' # Use preset
#' results <- run_optimization("config/presets/fusion_lumos_standard.json")
run_optimization <- function(config_path) {

  # ===================================================================
  # Load and Validate Configuration
  # ===================================================================

  cat("\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║   JSON Configuration-Based Batch Processing Pipeline          ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  config <- load_optimization_config(config_path)
  print_config_summary(config)

  # Create output directory
  output_dir <- config$output$output_dir
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  # ===================================================================
  # Extract Configuration Parameters
  # ===================================================================

  input_files <- config$input_data$input_files
  current_cycle_time_config <- config$input_data$current_cycle_time  # NULL = auto-estimate
  instrument_preset <- config$instrument$preset
  custom_settings <- config$instrument$custom_settings

  # DPPP parameters
  target_dppp <- config$dppp_parameters$target_dppp
  target_satisfaction <- config$dppp_parameters$target_satisfaction
  dppp_tolerance <- get_config_value(config, "dppp_parameters.dppp_tolerance", 0.0)

  # Scan settings
  load_factor <- config$scan_settings$load_factor
  ms1_scans_per_cycle <- config$scan_settings$ms1_scans_per_cycle  # NULL = auto-detect
  warning_threshold_windows <- get_config_value(config, "scan_settings.warning_threshold_windows", 5)

  # RT binning
  rt_bin_width_min <- config$rt_binning$rt_bin_width_min

  # m/z optimization
  mz_strategies <- config$mz_optimization$strategies
  quantile_lower <- get_config_value(config, "mz_optimization.quantile_lower", 0.05)
  quantile_upper <- get_config_value(config, "mz_optimization.quantile_upper", 0.95)
  target_coverage <- get_config_value(config, "mz_optimization.target_coverage", 0.95)
  outlier_threshold <- get_config_value(config, "mz_optimization.outlier_threshold", 3.0)
  smoothing_window <- get_config_value(config, "mz_optimization.smoothing_window", 3)
  polynomial_order <- get_config_value(config, "mz_optimization.polynomial_order", 2)

  # Window generation
  window_modes <- config$window_generation$modes
  min_width_da <- config$window_generation$min_width_da
  max_width_da <- config$window_generation$max_width_da
  overlap_percentage <- get_config_value(config, "window_generation.overlap_percentage", 0)

  # ===================================================================
  # Process All Files
  # ===================================================================

  all_results <- list()

  for (input_file in input_files) {

    if (!file.exists(input_file)) {
      cat(sprintf("⚠️  File not found: %s (skipping)\n", input_file))
      next
    }

    gradient_name <- extract_gradient_name(input_file)

    cat("\n")
    cat("═══════════════════════════════════════════════════════════════\n")
    cat(sprintf("Processing: %s (%s gradient)\n", basename(input_file), gradient_name))
    cat("═══════════════════════════════════════════════════════════════\n\n")

    # ==================================================================
    # Stage 1: Data Validation (once per file)
    # ==================================================================

    cat("Stage 1: Data Validation\n")
    cat("─────────────────────────────────────────────────────────────\n")

    validated_data <- create_validated_dataset(
      proteome_file = input_file,
      apply_quality_filters = TRUE
    )

    cat(sprintf("✅ Validated %s precursors\n",
                format(nrow(validated_data$data), big.mark = ",")))

    # ==================================================================
    # Stage 2: Optimization Planning (once per file)
    # ==================================================================

    cat("\nStage 2: Optimization Planning\n")
    cat("─────────────────────────────────────────────────────────────\n")

    # Use config cycle time if provided, otherwise estimate
    if (!is.null(current_cycle_time_config)) {
      initial_cycle_time <- current_cycle_time_config
      cat(sprintf("Using configured cycle time: %.3f sec\n", initial_cycle_time))
    } else {
      initial_cycle_time <- estimate_cycle_time(gradient_name)
      cat(sprintf("Estimated cycle time: %.3f sec (auto-detected from gradient)\n", initial_cycle_time))
    }

    optimization_plan <- plan_optimization(
      validated_data = validated_data,
      current_cycle_time = initial_cycle_time,
      instrument_preset = instrument_preset,
      target_dppp = target_dppp,
      target_satisfaction = target_satisfaction,
      dppp_tolerance = dppp_tolerance,
      load_factor = load_factor,
      ms1_scans_per_cycle = ms1_scans_per_cycle,
      warning_threshold_windows = warning_threshold_windows
    )

    cat(sprintf("✅ Planning complete:\n"))
    cat(sprintf("   Required cycle time: %.3f sec\n",
                optimization_plan$required_cycle_time_sec))
    cat(sprintf("   Windows per RT bin: %d\n",
                optimization_plan$window_count_per_bin))
    cat(sprintf("   Current satisfaction: %.1f%%\n",
                optimization_plan$diagnosis$satisfaction_ratio * 100))

    # ==================================================================
    # Stage 3: Window Optimization (for each strategy/mode combination)
    # ==================================================================

    cat("\nStage 3: Window Optimization\n")
    cat("─────────────────────────────────────────────────────────────\n")

    total_combinations <- length(mz_strategies) * length(window_modes)
    current_combo <- 0

    file_results <- list()

    for (strategy in mz_strategies) {
      for (mode in window_modes) {

        current_combo <- current_combo + 1

        cat(sprintf("\n[%d/%d] Strategy: %s, Mode: %s\n",
                    current_combo, total_combinations, strategy, mode))

        # Generate windows
        windows_result <- optimize_windows(
          validated_data = validated_data,
          optimization_plan = optimization_plan,
          rt_bin_width_min = rt_bin_width_min,
          mz_strategy = strategy,
          window_mode = mode,
          target_coverage = target_coverage,
          quantile_lower = quantile_lower,
          quantile_upper = quantile_upper,
          outlier_threshold = outlier_threshold,
          smoothing_window = smoothing_window,
          polynomial_order = polynomial_order,
          min_width_da = min_width_da,
          max_width_da = max_width_da,
          overlap_percentage = overlap_percentage
        )

        # Generate output filename
        output_filename <- sprintf("%s_%s_%s_thermo.csv",
                                   gradient_name, strategy, mode)
        output_path <- file.path(output_dir, output_filename)

        # Export windows with Thermo 22-column format
        export_windows_thermo_format(
          windows_result = windows_result,
          optimization_plan = optimization_plan,
          validated_data = validated_data,
          gradient_name = gradient_name,
          output_path = output_path
        )

        cat(sprintf("   ✅ Exported: %s\n", output_filename))
        cat(sprintf("      Windows: %d, Coverage: %.1f%%, Width: %.2f ± %.2f Da\n",
                    nrow(windows_result$windows),
                    windows_result$statistics$coverage_percentage,
                    windows_result$statistics$window_width_mean,
                    windows_result$statistics$window_width_sd))

        # Store results
        file_results[[paste(strategy, mode, sep = "_")]] <- list(
          windows_result = windows_result,
          output_path = output_path
        )
      }
    }

    all_results[[gradient_name]] <- file_results
  }

  # ===================================================================
  # Generate Summary Report
  # ===================================================================

  if (config$output$include_summary) {

    cat("\n")
    cat("╔════════════════════════════════════════════════════════════════╗\n")
    cat("║                   GENERATING SUMMARY REPORT                    ║\n")
    cat("╚════════════════════════════════════════════════════════════════╝\n\n")

    # Create summary table
    summary_rows <- list()

    for (gradient in names(all_results)) {
      for (combo_name in names(all_results[[gradient]])) {

        result <- all_results[[gradient]][[combo_name]]
        stats <- result$windows_result$statistics
        params <- result$windows_result$parameters

        summary_rows[[length(summary_rows) + 1]] <- data.frame(
          Gradient = gradient,
          Strategy = params$mz_strategy,
          Mode = params$window_mode,
          Total_Windows = nrow(result$windows_result$windows),
          RT_Bins = result$windows_result$rt_binning$n_bins,
          Mean_Width_Da = round(stats$window_width_mean, 2),
          SD_Width_Da = round(stats$window_width_sd, 2),
          Coverage_Pct = round(stats$coverage_percentage, 1),
          Mean_Precursors = round(stats$mean_precursors_per_window, 1),
          CV_Precursors = round(stats$cv_precursors, 3),
          Output_File = basename(result$output_path),
          stringsAsFactors = FALSE
        )
      }
    }

    summary_table <- do.call(rbind, summary_rows)

    # Print summary
    print(summary_table)

    # Save summary
    summary_path <- file.path(output_dir, "batch_processing_summary.csv")
    write.csv(summary_table, summary_path, row.names = FALSE)

    cat(sprintf("\n✅ Summary saved to: %s\n", summary_path))
  }

  # ===================================================================
  # Final Report
  # ===================================================================

  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║                   BATCH PROCESSING COMPLETE                    ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  cat(sprintf("✅ Total CSV files generated: %d\n", length(summary_rows)))
  cat(sprintf("✅ Output directory: %s\n", output_dir))
  cat(sprintf("✅ Configuration: %s\n", config_path))
  cat("\n")

  return(invisible(all_results))
}

# =============================================================================
# Helper Functions
# =============================================================================

#' Estimate initial cycle time based on gradient length
#'
#' @param gradient_name Gradient identifier (e.g., "30min", "60min")
#' @return Estimated cycle time in seconds
estimate_cycle_time <- function(gradient_name) {
  # Extract gradient length
  gradient_min <- as.numeric(gsub("min.*", "", gradient_name))

  # Empirical estimates based on gradient length
  if (gradient_min <= 30) {
    return(1.2)  # Fast gradient
  } else if (gradient_min <= 60) {
    return(1.6)  # Medium gradient
  } else {
    return(2.0)  # Long gradient
  }
}

#' Extract gradient name from file path
#'
#' @param file_path Path to input file
#' @return Gradient name (e.g., "30min")
extract_gradient_name <- function(file_path) {
  basename_file <- basename(file_path)

  if (grepl("30min", basename_file)) {
    return("30min")
  } else if (grepl("60min", basename_file)) {
    return("60min")
  } else if (grepl("90min", basename_file)) {
    return("90min")
  } else {
    stop("Cannot determine gradient type from filename: ", file_path)
  }
}

# =============================================================================
# CSV Export Function (Thermo 22-column format with cycle time)
# =============================================================================

#' Export windows in Thermo Orbitrap standard 22-column format
#'
#' @param windows_result OptimizedWindows object
#' @param optimization_plan OptimizationPlan object
#' @param validated_data ValidatedData object
#' @param gradient_name Gradient identifier
#' @param output_path Output file path
export_windows_thermo_format <- function(
  windows_result,
  optimization_plan,
  validated_data,
  gradient_name,
  output_path
) {

  windows <- windows_result$windows

  # Extract metadata
  instrument_name <- optimization_plan$instrument$name
  strategy <- windows_result$parameters$mz_strategy
  mode <- windows_result$parameters$window_mode
  recommended_cycle_time <- optimization_plan$required_cycle_time_sec

  # Calculate overlap with previous/next windows
  overlap_prev <- c(0, diff(windows$mz_start))
  overlap_prev[overlap_prev < 0] <- 0
  overlap_prev <- abs(overlap_prev)

  overlap_next <- c(diff(windows$mz_end), 0)
  overlap_next[overlap_next < 0] <- 0
  overlap_next <- abs(overlap_next)

  # Create 22-column Thermo standard CSV
  csv_data <- windows %>%
    mutate(
      # Columns 1-3: Compound identification (empty for DIA)
      Compound = "",
      Formula = "",
      Adduct = "",

      # Columns 4-5: Precursor information
      `m/z` = round((mz_start + mz_end) / 2, 1),
      z = 2,

      # Columns 6-7: RT window (in minutes)
      `t start (min)` = round(rt_start, 1),
      `t stop (min)` = round(rt_end, 1),

      # Column 8: Isolation window width
      `Isolation Window (m/z)` = round(window_width, 1),

      # Column 9: AGC target
      `Normalized AGC Target (%)` = 100,

      # Columns 10-11: Window m/z range
      `Start (m/z)` = round(mz_start, 1),
      `End (m/z)` = round(mz_end, 1),

      # Column 12: Window ID
      Window_ID = row_number(),

      # Column 13: RT Segment ID
      RT_Segment_ID = rt_segment_id,

      # Column 14: RT Center
      RT_Center = round((rt_start + rt_end) / 2, 1),

      # Column 15: RT Width
      RT_Width = round(rt_end - rt_start, 1),

      # Column 16: Number of precursors
      N_Precursors = n_precursors,

      # Columns 17-18: Overlap with adjacent windows
      Overlap_Prev = round(overlap_prev[row_number()], 1),
      Overlap_Next = round(overlap_next[row_number()], 1),

      # Column 19: Instrument
      Instrument = instrument_name,

      # Column 20: Generation method
      Generation_Method = paste0(strategy, "_", mode),

      # Column 21: Window type
      Window_Type = mode,

      # Column 22: Recommended cycle time (important for analysis)
      Recommended_Cycle_Time_Sec = round(recommended_cycle_time, 1)
    ) %>%
    select(
      Compound, Formula, Adduct,
      `m/z`, z,
      `t start (min)`, `t stop (min)`,
      `Isolation Window (m/z)`,
      `Normalized AGC Target (%)`,
      `Start (m/z)`, `End (m/z)`,
      Window_ID, RT_Segment_ID, RT_Center, RT_Width,
      N_Precursors,
      Overlap_Prev, Overlap_Next,
      Instrument, Generation_Method, Window_Type,
      Recommended_Cycle_Time_Sec
    )

  # Write CSV
  write.csv(csv_data, output_path, row.names = FALSE)

  return(invisible(csv_data))
}

# =============================================================================
# Usage Examples
# =============================================================================

# Example 1: Run with default configuration
# results <- run_optimization("config/optimization_config.json")

# Example 2: Run with preset
# results <- run_optimization("config/presets/fusion_lumos_standard.json")
# results <- run_optimization("config/presets/quant_mode_85pct.json")
# results <- run_optimization("config/presets/id_mode_70pct.json")
# results <- run_optimization("config/presets/astral_narrow_dia.json")
