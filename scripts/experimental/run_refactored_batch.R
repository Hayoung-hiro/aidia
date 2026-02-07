# =============================================================================
# Refactored 3-Stage Batch Processing Pipeline
# =============================================================================
# Uses Claude refactored branch architecture:
#   - Stage 1: Data Validation
#   - Stage 2: Optimization Planning (DPPP + Window Count)
#   - Stage 3: Window Optimization (RT + m/z + Windows)
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)

# Source refactored modules
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/utils_common.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Refactored 3-Stage Batch Processing Pipeline                ║\n")
cat("║   Option B: Full Strategy Comparison                          ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Configuration
# =============================================================================

# Input files
INPUT_FILES <- c(
  "data/30min_report.parquet",
  "data/60min_report.parquet",
  "data/90min_report.parquet"
)

# Instrument configuration
INSTRUMENT_PRESET <- "fusion_lumos"  # Thermo Fusion Lumos (20 Hz)

# DPPP parameters (MODIFIED: 70% satisfaction, min_windows=10)
TARGET_DPPP <- 7.0
TARGET_SATISFACTION <- 0.70  # Changed from 0.85
LOAD_FACTOR <- 0.8
MIN_WINDOWS <- 10  # Changed from default 20

# RT binning
RT_BIN_WIDTH_MIN <- 5.0  # 5 minutes

# m/z strategies (Option B: all 4)
MZ_STRATEGIES <- c("quantile", "smoothing", "outlier", "coverage")

# Window modes (Option B: both)
WINDOW_MODES <- c("fixed", "variable")

# Window constraints
MIN_WIDTH_DA <- 2
MAX_WIDTH_DA <- 80
OVERLAP_PERCENTAGE <- 0

# Output directory (MODIFIED: Fusion Lumos results)
OUTPUT_DIR <- "results_fusion_lumos_min10_sat70"
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

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
  # Longer gradients allow longer cycle times
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
# Main Processing Function
# =============================================================================

#' Process single file with all strategy/mode combinations
#'
#' @param input_file Path to input parquet file
#' @param instrument_preset Instrument type
#' @param strategies Vector of m/z strategies
#' @param modes Vector of window modes
#' @return List of results for all combinations
process_file_all_combinations <- function(
  input_file,
  instrument_preset,
  strategies,
  modes
) {

  gradient_name <- extract_gradient_name(input_file)

  cat("\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat(sprintf("Processing: %s (%s gradient)\n", basename(input_file), gradient_name))
  cat("═══════════════════════════════════════════════════════════════\n\n")

  # ===================================================================
  # Stage 1: Data Validation (once per file)
  # ===================================================================

  cat("Stage 1: Data Validation\n")
  cat("─────────────────────────────────────────────────────────────\n")

  validated_data <- create_validated_dataset(
    proteome_file = input_file,
    apply_quality_filters = TRUE
  )

  cat(sprintf("✅ Validated %s precursors\n",
              format(nrow(validated_data$data), big.mark = ",")))

  # ===================================================================
  # Stage 2: Optimization Planning (once per file)
  # ===================================================================

  cat("\nStage 2: Optimization Planning\n")
  cat("─────────────────────────────────────────────────────────────\n")

  initial_cycle_time <- estimate_cycle_time(gradient_name)

  optimization_plan <- plan_optimization(
    validated_data = validated_data,
    current_cycle_time = initial_cycle_time,
    instrument_preset = instrument_preset,
    target_dppp = TARGET_DPPP,
    target_satisfaction = TARGET_SATISFACTION,
    load_factor = LOAD_FACTOR,
    min_windows = MIN_WINDOWS  # Apply custom minimum
  )

  cat(sprintf("✅ Planning complete:\n"))
  cat(sprintf("   Required cycle time: %.3f sec\n",
              optimization_plan$required_cycle_time_sec))
  cat(sprintf("   Windows per RT bin: %d\n",
              optimization_plan$window_count_per_bin))
  cat(sprintf("   Current satisfaction: %.1f%%\n",
              optimization_plan$diagnosis$current_satisfaction_ratio * 100))

  # ===================================================================
  # Stage 3: Window Optimization (for each strategy/mode combination)
  # ===================================================================

  cat("\nStage 3: Window Optimization\n")
  cat("─────────────────────────────────────────────────────────────\n")

  total_combinations <- length(strategies) * length(modes)
  current_combo <- 0

  results <- list()

  for (strategy in strategies) {
    for (mode in modes) {

      current_combo <- current_combo + 1

      cat(sprintf("\n[%d/%d] Strategy: %s, Mode: %s\n",
                  current_combo, total_combinations, strategy, mode))

      # Generate windows
      # For smoothing strategy, adjust window size based on expected RT bins
      smoothing_window <- 3  # Reduced from default 7 for small RT bin counts
      polynomial_order <- 2  # Reduced from default 3

      windows_result <- optimize_windows(
        validated_data = validated_data,
        optimization_plan = optimization_plan,
        rt_bin_width_min = RT_BIN_WIDTH_MIN,
        mz_strategy = strategy,
        window_mode = mode,
        smoothing_window = smoothing_window,
        polynomial_order = polynomial_order,
        min_width_da = MIN_WIDTH_DA,
        max_width_da = MAX_WIDTH_DA,
        overlap_percentage = OVERLAP_PERCENTAGE
      )

      # Generate output filename
      output_filename <- sprintf("%s_%s_%s_thermo.csv",
                                 gradient_name, strategy, mode)
      output_path <- file.path(OUTPUT_DIR, output_filename)

      # Export windows with Thermo 20-column format
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
      results[[paste(strategy, mode, sep = "_")]] <- list(
        windows_result = windows_result,
        output_path = output_path
      )
    }
  }

  return(results)
}

# =============================================================================
# CSV Export Function (Thermo 20-column standard format)
# =============================================================================

#' Export windows in Thermo Orbitrap standard 20-column format
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

  # Total windows
  total_windows <- nrow(windows)

  # Calculate overlap with previous/next windows
  overlap_prev <- c(0, diff(windows$mz_start))
  overlap_prev[overlap_prev < 0] <- 0  # Negative means gap, not overlap
  overlap_prev <- abs(overlap_prev)

  overlap_next <- c(diff(windows$mz_end), 0)
  overlap_next[overlap_next < 0] <- 0
  overlap_next <- abs(overlap_next)

  # Extract recommended cycle time from optimization plan
  recommended_cycle_time <- optimization_plan$required_cycle_time_sec

  # Create 22-column Thermo standard CSV (added Recommended_Cycle_Time_Sec)
  csv_data <- windows %>%
    mutate(
      # Columns 1-3: Compound identification (empty for DIA)
      Compound = "",
      Formula = "",
      Adduct = "",

      # Columns 4-5: Precursor information
      `m/z` = round((mz_start + mz_end) / 2, 1),  # Center m/z
      z = 2,  # Default charge state (not used in DIA)

      # Columns 6-7: RT window (in minutes)
      `t start (min)` = round(rt_start, 1),
      `t stop (min)` = round(rt_end, 1),

      # Column 8: Isolation window width
      `Isolation Window (m/z)` = round(window_width, 1),

      # Column 9: AGC target (normalized percentage)
      `Normalized AGC Target (%)` = 100,  # Default 100%

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

      # Column 22: Recommended cycle time (NEW - important for analysis)
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
# Execute Batch Processing
# =============================================================================

cat("\n")
cat("Configuration:\n")
cat(sprintf("  Instrument: %s (Traditional Orbitrap)\n", INSTRUMENT_PRESET))
cat(sprintf("  Target DPPP: %.1f (Satisfaction: %.0f%%)\n",
            TARGET_DPPP, TARGET_SATISFACTION * 100))
cat(sprintf("  RT bin width: %.1f min\n", RT_BIN_WIDTH_MIN))
cat(sprintf("  Strategies: %s\n", paste(MZ_STRATEGIES, collapse = ", ")))
cat(sprintf("  Modes: %s\n", paste(WINDOW_MODES, collapse = ", ")))
cat(sprintf("  Combinations per file: %d\n",
            length(MZ_STRATEGIES) * length(WINDOW_MODES)))
cat(sprintf("  Total files to generate: %d\n",
            length(INPUT_FILES) * length(MZ_STRATEGIES) * length(WINDOW_MODES)))
cat(sprintf("  Output directory: %s\n", OUTPUT_DIR))
cat("\n")

# Process all files
all_results <- list()

for (input_file in INPUT_FILES) {

  if (!file.exists(input_file)) {
    cat(sprintf("⚠️  File not found: %s (skipping)\n", input_file))
    next
  }

  gradient_name <- extract_gradient_name(input_file)

  file_results <- process_file_all_combinations(
    input_file = input_file,
    instrument_preset = INSTRUMENT_PRESET,
    strategies = MZ_STRATEGIES,
    modes = WINDOW_MODES
  )

  all_results[[gradient_name]] <- file_results
}

# =============================================================================
# Generate Summary Report
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                   BATCH PROCESSING COMPLETE                    ║\n")
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
summary_path <- file.path(OUTPUT_DIR, "batch_processing_summary.csv")
write.csv(summary_table, summary_path, row.names = FALSE)

cat(sprintf("\n✅ Summary saved to: %s\n", summary_path))
cat(sprintf("✅ Total CSV files generated: %d\n", nrow(summary_table)))
cat(sprintf("✅ Output directory: %s\n", OUTPUT_DIR))
cat("\n")
