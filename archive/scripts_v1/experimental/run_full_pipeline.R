# =============================================================================
# Full 4-Stage DIA Window Optimization Pipeline
# =============================================================================
# Complete workflow:
#   Stage 1: Data Validation
#   Stage 2: DPPP Diagnosis
#   Stage 3A-D: Window Optimization (Count, RT Binning, m/z Range, Generation)
#   Stage 4: Visualization & Reporting
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)

# Source all stage modules
source("R/stage1_data_validation.R")
source("R/stage2_dppp_diagnosis.R")
source("R/stage3_window_optimization/module3a_window_count.R")
source("R/stage3_window_optimization/module3b_rt_binning.R")
source("R/stage3_window_optimization/module3c_mz_range_optimization.R")
source("R/stage3_window_optimization/module3d_window_generation.R")
source("R/stage4_visualization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Full 4-Stage DIA Window Optimization Pipeline               ║\n")
cat("║   Stage 1 → Stage 2 → Stage 3A-D → Stage 4                   ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Configuration
# =============================================================================

# Input file
INPUT_FILE <- "data/30min_report_01.parquet"

# Instrument configuration
INSTRUMENT_TYPE <- "astral"
INSTRUMENT_CONFIG <- list(
  astral = list(
    name = "Thermo Astral",
    max_scan_rate = 50,
    ms1_time = 0.1,
    ms2_time = 0.015,
    parallel_acquisition = TRUE
  ),
  exploris = list(
    name = "Thermo Orbitrap Exploris",
    max_scan_rate = 25,
    ms1_time = 0.05,
    ms2_time = 0.02,
    parallel_acquisition = FALSE
  ),
  traditional = list(
    name = "Traditional Orbitrap",
    max_scan_rate = 8,
    ms1_time = 0.1,
    ms2_time = 0.08,
    parallel_acquisition = FALSE
  )
)

# DPPP parameters
TARGET_DPPP <- 7.0
TARGET_SATISFACTION <- 0.85
DPPP_TOLERANCE <- 0.0

# RT binning parameters
RT_BINNING_MODE <- "time_unit"  # "time_unit" or "time_breaks"
RT_TIME_UNIT <- 5.0  # minutes per bin (if using time_unit mode)
# RT_TIME_BREAKS <- c(0, 15, 30, 45, 60)  # custom breakpoints (if using time_breaks mode)

# m/z range strategy
MZ_STRATEGY <- "smoothing"  # "quantile", "smoothing", "outlier", "coverage"

# Window generation parameters
WINDOW_MODE <- "variable"  # "fixed", "variable", "overlapped"
MIN_WIDTH_DA <- 10
MAX_WIDTH_DA <- 80
OVERLAP_PERCENT <- 0.02  # 2% overlap

# Output directory
OUTPUT_DIR <- "results_full_pipeline"
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

# =============================================================================
# Main Pipeline Function
# =============================================================================

#' Run Full 4-Stage Pipeline
#'
#' @param input_file Path to DIA-NN parquet/tsv/csv file
#' @param instrument_type Instrument type ("astral", "exploris", "traditional")
#' @param target_dppp Target DPPP value (default: 7.0)
#' @param target_satisfaction Target satisfaction ratio (default: 0.85)
#' @param rt_binning_mode RT binning mode ("time_unit" or "time_breaks")
#' @param rt_time_unit Time unit in minutes (if using time_unit mode)
#' @param rt_time_breaks Custom RT breakpoints (if using time_breaks mode)
#' @param mz_strategy m/z range strategy ("quantile", "smoothing", "outlier", "coverage")
#' @param window_mode Window generation mode ("fixed", "variable", "overlapped")
#' @param output_dir Output directory for results
#'
#' @return List containing all stage results
#' @export
run_full_pipeline <- function(
  input_file,
  instrument_type = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.85,
  rt_binning_mode = "time_unit",
  rt_time_unit = 5.0,
  rt_time_breaks = NULL,
  mz_strategy = "smoothing",
  window_mode = "variable",
  output_dir = "results_full_pipeline"
) {

  cat("\n═══════════════════════════════════════════════════════════════\n")
  cat("Starting Full Pipeline Execution\n")
  cat("═══════════════════════════════════════════════════════════════\n\n")

  pipeline_start <- Sys.time()

  # Get instrument configuration
  inst_config <- INSTRUMENT_CONFIG[[instrument_type]]
  if (is.null(inst_config)) {
    stop("Unknown instrument type: ", instrument_type)
  }

  cat(sprintf("Configuration:\n"))
  cat(sprintf("  Input file: %s\n", basename(input_file)))
  cat(sprintf("  Instrument: %s\n", inst_config$name))
  cat(sprintf("  Target DPPP: %.1f (satisfaction: %.0f%%)\n", target_dppp, target_satisfaction * 100))
  cat(sprintf("  RT binning: %s\n", rt_binning_mode))
  cat(sprintf("  m/z strategy: %s\n", mz_strategy))
  cat(sprintf("  Window mode: %s\n", window_mode))
  cat(sprintf("  Output directory: %s\n", output_dir))

  # ============================================================
  # STAGE 1: Data Validation
  # ============================================================

  cat("\n\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat("STAGE 1: Data Validation\n")
  cat("═══════════════════════════════════════════════════════════════\n")

  stage1_result <- create_validated_dataset(
    proteome_file = input_file,
    raw_file_dir = NULL,  # Optional: set to raw file directory if available
    rt_range = NULL,      # Optional: c(min_rt, max_rt)
    mz_range = NULL,      # Optional: c(min_mz, max_mz)
    enable_raw_metadata = FALSE,
    quality_threshold = 0.8,
    apply_quality_filters = TRUE
  )

  cat(sprintf("\n✅ Stage 1 Complete: %d precursors validated\n",
              nrow(stage1_result$data)))

  # ============================================================
  # STAGE 2: DPPP Diagnosis
  # ============================================================

  cat("\n\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat("STAGE 2: DPPP Diagnosis\n")
  cat("═══════════════════════════════════════════════════════════════\n")

  # Initial cycle time estimate (will be refined in Stage 2)
  initial_cycle_time <- estimate_initial_cycle_time(stage1_result, target_dppp)

  stage2_result <- diagnose_dppp_status(
    validated_data = stage1_result,
    current_cycle_time = initial_cycle_time,
    target_dppp = target_dppp,
    target_satisfaction = target_satisfaction,
    dppp_tolerance = DPPP_TOLERANCE
  )

  cat(sprintf("\n✅ Stage 2 Complete:\n"))
  cat(sprintf("  Current satisfaction: %.1f%%\n",
              stage2_result$current_state$satisfaction_ratio * 100))
  cat(sprintf("  Required cycle time: %.3f sec\n",
              stage2_result$recommendation$required_cycle_time))

  # ============================================================
  # STAGE 3A: Window Count Determination
  # ============================================================

  cat("\n\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat("STAGE 3A: Window Count Determination\n")
  cat("═══════════════════════════════════════════════════════════════\n")

  stage3a_result <- determine_window_count(
    diagnosis_result = stage2_result,
    validated_data = stage1_result,
    instrument_type = instrument_type,
    raw_metadata = NULL  # Optional: from Stage 1 if available
  )

  cat(sprintf("\n✅ Stage 3A Complete:\n"))
  cat(sprintf("  Optimal window count: %d\n",
              stage3a_result$window_count_result$optimal_windows))
  cat(sprintf("  Cycle time: %.3f sec\n",
              stage3a_result$window_count_result$cycle_time))
  cat(sprintf("  Feasibility: %s\n",
              ifelse(stage3a_result$feasibility$is_feasible, "✓ FEASIBLE", "✗ NOT FEASIBLE")))

  # ============================================================
  # STAGE 3B: RT Binning
  # ============================================================

  cat("\n\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat("STAGE 3B: RT Binning\n")
  cat("═══════════════════════════════════════════════════════════════\n")

  stage3b_result <- create_rt_bins(
    validated_data = stage1_result,
    mode = rt_binning_mode,
    time_unit = if (rt_binning_mode == "time_unit") rt_time_unit else NULL,
    time_breaks = if (rt_binning_mode == "time_breaks") rt_time_breaks else NULL
  )

  cat(sprintf("\n✅ Stage 3B Complete:\n"))
  cat(sprintf("  RT bins created: %d\n", nrow(stage3b_result$rt_bins)))
  cat(sprintf("  RT range: %.1f - %.1f min\n",
              min(stage3b_result$rt_bins$rt_start),
              max(stage3b_result$rt_bins$rt_end)))

  # ============================================================
  # STAGE 3C: m/z Range Optimization
  # ============================================================

  cat("\n\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat("STAGE 3C: m/z Range Optimization\n")
  cat("═══════════════════════════════════════════════════════════════\n")

  stage3c_result <- optimize_mz_ranges(
    validated_data = stage1_result,
    rt_binning_result = stage3b_result,
    strategy = mz_strategy
  )

  cat(sprintf("\n✅ Stage 3C Complete:\n"))
  cat(sprintf("  Strategy: %s\n", mz_strategy))
  cat(sprintf("  m/z ranges calculated for %d RT bins\n",
              nrow(stage3c_result$mz_ranges)))

  # ============================================================
  # STAGE 3D: Window Generation
  # ============================================================

  cat("\n\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat("STAGE 3D: Window Generation\n")
  cat("═══════════════════════════════════════════════════════════════\n")

  stage3d_result <- generate_isolation_windows(
    validated_data = stage1_result,
    window_count_result = stage3a_result,
    rt_binning_result = stage3b_result,
    mz_range_result = stage3c_result,
    window_config = list(
      window_mode = window_mode,
      total_windows = stage3a_result$window_count_result$optimal_windows,
      per_bin_mode = TRUE,  # NEW ARCHITECTURE: windows PER bin
      min_width_da = MIN_WIDTH_DA,
      max_width_da = MAX_WIDTH_DA,
      overlap = OVERLAP_PERCENT
    )
  )

  cat(sprintf("\n✅ Stage 3D Complete:\n"))
  cat(sprintf("  Total windows: %d\n", nrow(stage3d_result$windows)))
  cat(sprintf("  Mean width: %.1f Da\n", stage3d_result$statistics$mean_width))
  cat(sprintf("  Coverage: %.1f%%\n",
              stage3d_result$coverage_analysis$coverage_ratio * 100))

  # ============================================================
  # STAGE 4: Visualization & Reporting
  # ============================================================

  cat("\n\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat("STAGE 4: Visualization & Reporting\n")
  cat("═══════════════════════════════════════════════════════════════\n")

  stage4_result <- generate_visualizations(
    validated_data = stage1_result,
    diagnosis_result = stage2_result,
    window_count_result = stage3a_result,
    rt_binning_result = stage3b_result,
    mz_range_result = stage3c_result,
    window_generation_result = stage3d_result,
    output_dir = output_dir
  )

  cat(sprintf("\n✅ Stage 4 Complete:\n"))
  cat(sprintf("  Plots generated: %d\n", length(stage4_result$plots)))
  cat(sprintf("  PDF report: %s\n", basename(stage4_result$report_files$pdf_report)))
  cat(sprintf("  Method file: %s\n", basename(stage4_result$report_files$method_file)))

  # ============================================================
  # Pipeline Summary
  # ============================================================

  pipeline_end <- Sys.time()
  pipeline_duration <- as.numeric(difftime(pipeline_end, pipeline_start, units = "secs"))

  cat("\n\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║                  PIPELINE EXECUTION COMPLETE                   ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  cat(sprintf("Total execution time: %.1f seconds\n\n", pipeline_duration))

  cat("Summary:\n")
  cat(sprintf("  • Validated precursors: %d\n", nrow(stage1_result$data)))
  cat(sprintf("  • Current DPPP satisfaction: %.1f%%\n",
              stage2_result$current_state$satisfaction_ratio * 100))
  cat(sprintf("  • Required cycle time: %.3f sec\n",
              stage2_result$recommendation$required_cycle_time))
  cat(sprintf("  • Optimal window count: %d\n",
              stage3a_result$window_count_result$optimal_windows))
  cat(sprintf("  • RT bins: %d\n", nrow(stage3b_result$rt_bins)))
  cat(sprintf("  • Total windows generated: %d\n", nrow(stage3d_result$windows)))
  cat(sprintf("  • Window coverage: %.1f%%\n",
              stage3d_result$coverage_analysis$coverage_ratio * 100))
  cat(sprintf("  • Output directory: %s\n", output_dir))

  # Return all stage results
  return(list(
    stage1 = stage1_result,
    stage2 = stage2_result,
    stage3a = stage3a_result,
    stage3b = stage3b_result,
    stage3c = stage3c_result,
    stage3d = stage3d_result,
    stage4 = stage4_result,
    execution_time = pipeline_duration
  ))
}

# =============================================================================
# Helper Function: Estimate Initial Cycle Time
# =============================================================================

#' Estimate Initial Cycle Time for Stage 2
#'
#' Provides a reasonable starting point for DPPP diagnosis.
#' Can be refined based on FWHM distribution.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param target_dppp Target DPPP value
#'
#' @return Estimated cycle time in seconds
#' @export
estimate_initial_cycle_time <- function(validated_data, target_dppp = 7.0) {

  # Get median FWHM
  fwhm_minutes <- median(validated_data$data$FWHM, na.rm = TRUE)
  fwhm_seconds <- fwhm_minutes * 60

  # Estimate cycle time using DPPP formula
  # DPPP = (1.7 × FWHM) / cycle_time
  # → cycle_time = (1.7 × FWHM) / DPPP
  estimated_cycle_time <- (1.7 * fwhm_seconds) / target_dppp

  cat(sprintf("Estimated initial cycle time: %.3f sec (based on median FWHM = %.2f sec)\n",
              estimated_cycle_time, fwhm_seconds))

  return(estimated_cycle_time)
}

# =============================================================================
# Execute Pipeline
# =============================================================================

if (interactive() || !interactive()) {
  result <- run_full_pipeline(
    input_file = INPUT_FILE,
    instrument_type = INSTRUMENT_TYPE,
    target_dppp = TARGET_DPPP,
    target_satisfaction = TARGET_SATISFACTION,
    rt_binning_mode = RT_BINNING_MODE,
    rt_time_unit = RT_TIME_UNIT,
    rt_time_breaks = NULL,
    mz_strategy = MZ_STRATEGY,
    window_mode = WINDOW_MODE,
    output_dir = OUTPUT_DIR
  )

  cat("\n✅ Pipeline completed successfully!\n")
  cat(sprintf("   Results saved to: %s\n", OUTPUT_DIR))
}
