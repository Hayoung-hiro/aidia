# test_refactored_workflow.R - Test Refactored 3-Stage Workflow
#
# Purpose: Test the new streamlined 3-stage pipeline
#
# New Architecture:
#   Stage 1: Data Validation (existing)
#   Stage 2: Optimization Planning (DPPP + Window Count, merged)
#   Stage 3: Window Optimization (RT + m/z + Windows, unified)
#
# Version: 2.0 (Refactored)
# Last Updated: 2025-10-25

cat("═══════════════════════════════════════════════════════════\n")
cat("  DIA Window Optimizer - Refactored Workflow Test\n")
cat("═══════════════════════════════════════════════════════════\n\n")

# =============================================================================
# Setup
# =============================================================================

# Load required libraries
suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(ggplot2)
  library(arrow)
})

# Load refactored modules
cat("Loading refactored modules...\n")
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
cat("✅ All modules loaded\n\n")

# Configuration
OUTPUT_DIR <- "test_refactored_output"
INPUT_FILE <- "rawfile/report.parquet"

cat("Configuration:\n")
cat(sprintf("  Input file: %s\n", INPUT_FILE))
cat(sprintf("  Output directory: %s\n", OUTPUT_DIR))
cat("\n")

# Create output directory
if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  cat(sprintf("✅ Created output directory: %s\n\n", OUTPUT_DIR))
}

# Check input file
if (!file.exists(INPUT_FILE)) {
  stop(sprintf("❌ Input file not found: %s\n", INPUT_FILE))
}

# Start overall timer
overall_timer <- create_timer()

# =============================================================================
# Stage 1: Data Validation (Existing Module)
# =============================================================================

cat("═══════════════════════════════════════════════════════════\n")
cat(" Stage 1: Data Validation\n")
cat("═══════════════════════════════════════════════════════════\n\n")

stage1_timer <- create_timer()

validated_data <- create_validated_dataset(
  proteome_file = INPUT_FILE,
  rt_range = NULL,
  mz_range = NULL,
  enable_raw_metadata = FALSE,
  quality_threshold = 0.8,
  apply_quality_filters = TRUE
)

stage1_time <- stage1_timer$elapsed()

cat(sprintf("\n✅ Stage 1 complete (%.2f sec)\n", stage1_time))
cat(sprintf("   Precursors: %s\n",
            format(validated_data$metadata$n_precursors, big.mark = ",")))
cat(sprintf("   RT range: %.2f - %.2f min\n",
            validated_data$metadata$rt_range[1],
            validated_data$metadata$rt_range[2]))
cat(sprintf("   m/z range: %.2f - %.2f Da\n",
            validated_data$metadata$mz_range[1],
            validated_data$metadata$mz_range[2]))
cat(sprintf("   FWHM median: %.2f sec\n",
            validated_data$metadata$fwhm_stats$median * 60))

# Save Stage 1 output
saveRDS(validated_data, file.path(OUTPUT_DIR, "stage1_validated_data.rds"))
cat(sprintf("   Saved: %s\n", file.path(OUTPUT_DIR, "stage1_validated_data.rds")))

# =============================================================================
# Stage 2: Optimization Planning (NEW - Merged Module)
# =============================================================================

cat("\n")
stage2_timer <- create_timer()

# Estimate current cycle time from FWHM
# For Orbitrap with ~25 windows: cycle_time ≈ FWHM / 7.0
current_cycle_time <- validated_data$metadata$fwhm_stats$mean * 60 / 7.0

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = current_cycle_time,
  instrument_preset = "orbitrap",  # Use Orbitrap for this test
  target_dppp = 7.0,
  target_satisfaction = 0.85,
  load_factor = 0.8,
  ms1_scans = NULL,  # Auto-detect (=1 for orbitrap)
  min_windows = 20,
  max_windows = 500
)

stage2_time <- stage2_timer$elapsed()

# Save Stage 2 output
saveRDS(optimization_plan, file.path(OUTPUT_DIR, "stage2_optimization_plan.rds"))
cat(sprintf("Saved: %s\n", file.path(OUTPUT_DIR, "stage2_optimization_plan.rds")))

# Print plan summary
cat("\n")
summary(optimization_plan)

# =============================================================================
# Stage 3: Window Optimization (NEW - Unified Module)
# =============================================================================

cat("\n")
stage3_timer <- create_timer()

optimized_windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,  # 5-minute RT bins
  mz_strategy = "quantile",  # Fast and robust
  window_mode = "variable",  # Density-based
  target_coverage = 0.95,
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  min_width_da = 2,
  max_width_da = 80,
  overlap_percentage = 0
)

stage3_time <- stage3_timer$elapsed()

# Save Stage 3 output
saveRDS(optimized_windows, file.path(OUTPUT_DIR, "stage3_optimized_windows.rds"))
cat(sprintf("Saved: %s\n", file.path(OUTPUT_DIR, "stage3_optimized_windows.rds")))

# Export method file (CSV)
method_file <- file.path(OUTPUT_DIR, "method_file.csv")
export_windows_to_csv(
  optimized_windows,
  output_file = method_file,
  instrument_type = "orbitrap"
)

# Print window summary
cat("\n")
summary(optimized_windows)

# =============================================================================
# Performance Comparison
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════\n")
cat(" Performance Summary\n")
cat("═══════════════════════════════════════════════════════════\n\n")

total_time <- overall_timer$elapsed()

cat("Timing Breakdown:\n")
cat(sprintf("  Stage 1 (Data Validation):      %7.2f sec (%5.1f%%)\n",
            stage1_time, stage1_time / total_time * 100))
cat(sprintf("  Stage 2 (Optimization Planning): %7.2f sec (%5.1f%%)\n",
            stage2_time, stage2_time / total_time * 100))
cat(sprintf("  Stage 3 (Window Optimization):   %7.2f sec (%5.1f%%)\n",
            stage3_time, stage3_time / total_time * 100))
cat(sprintf("  ─────────────────────────────────────────────────\n"))
cat(sprintf("  Total:                           %7.2f sec\n\n", total_time))

cat("Key Metrics:\n")
cat(sprintf("  Total precursors: %s\n",
            format(validated_data$metadata$n_precursors, big.mark = ",")))
cat(sprintf("  Total windows: %d\n", nrow(optimized_windows$windows)))
cat(sprintf("  RT bins: %d\n", optimized_windows$rt_binning$n_bins))
cat(sprintf("  Windows per bin: %d\n",
            optimization_plan$window_count_per_bin))
cat(sprintf("  Coverage: %.1f%%\n",
            optimized_windows$statistics$coverage_percentage))
cat(sprintf("  Mean window width: %.2f Da\n",
            optimized_windows$statistics$window_width_mean))
cat(sprintf("  Precursors per window: %.1f (CV: %.2f)\n",
            optimized_windows$statistics$mean_precursors_per_window,
            optimized_windows$statistics$cv_precursors))

# =============================================================================
# Optimization Quality Assessment
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════\n")
cat(" Optimization Quality Assessment\n")
cat("═══════════════════════════════════════════════════════════\n\n")

cat("DPPP Improvement:\n")
cat(sprintf("  Current satisfaction: %.1f%%\n",
            optimization_plan$diagnosis$current_satisfaction_ratio * 100))
cat(sprintf("  Target satisfaction: %.0f%%\n",
            optimization_plan$parameters$target_satisfaction * 100))
cat(sprintf("  Gap: %.1f%%\n",
            (optimization_plan$parameters$target_satisfaction -
             optimization_plan$diagnosis$current_satisfaction_ratio) * 100))

cat("\nCycle Time:\n")
cat(sprintf("  Current: %.3f sec\n",
            optimization_plan$diagnosis$current_cycle_time_sec))
cat(sprintf("  Required: ≤ %.3f sec\n",
            optimization_plan$required_cycle_time_sec))
cat(sprintf("  Planned: %.3f sec\n",
            optimization_plan$actual_cycle_time_sec))
cat(sprintf("  Margin: %.3f sec\n",
            optimization_plan$required_cycle_time_sec -
            optimization_plan$actual_cycle_time_sec))

cat("\nWindow Distribution Uniformity:\n")
cat(sprintf("  Window width CV: %.3f\n",
            optimized_windows$statistics$window_width_cv))
cat(sprintf("  Precursor count CV: %.3f\n",
            optimized_windows$statistics$cv_precursors))
cat(sprintf("  → %s distribution uniformity\n",
            if (optimized_windows$statistics$cv_precursors < 0.3) {
              "✅ Excellent"
            } else if (optimized_windows$statistics$cv_precursors < 0.5) {
              "✅ Good"
            } else {
              "⚠️  Moderate"
            }))

# =============================================================================
# Save Summary Report
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════\n")
cat(" Saving Summary Report\n")
cat("═══════════════════════════════════════════════════════════\n\n")

summary_report <- list(
  metadata = list(
    timestamp = Sys.time(),
    input_file = INPUT_FILE,
    output_dir = OUTPUT_DIR,
    total_time_sec = total_time,
    workflow_version = "2.0-refactored"
  ),

  stage1 = list(
    n_precursors = validated_data$metadata$n_precursors,
    rt_range = validated_data$metadata$rt_range,
    mz_range = validated_data$metadata$mz_range,
    fwhm_median_sec = validated_data$metadata$fwhm_stats$median * 60,
    time_sec = stage1_time
  ),

  stage2 = list(
    window_count_per_bin = optimization_plan$window_count_per_bin,
    required_cycle_time_sec = optimization_plan$required_cycle_time_sec,
    actual_cycle_time_sec = optimization_plan$actual_cycle_time_sec,
    current_satisfaction_ratio = optimization_plan$diagnosis$current_satisfaction_ratio,
    target_satisfaction_ratio = optimization_plan$parameters$target_satisfaction,
    is_feasible = optimization_plan$feasibility$is_feasible,
    instrument_preset = optimization_plan$instrument$preset,
    time_sec = stage2_time
  ),

  stage3 = list(
    total_windows = nrow(optimized_windows$windows),
    n_bins = optimized_windows$rt_binning$n_bins,
    rt_bin_width_min = optimized_windows$parameters$rt_bin_width_min,
    window_mode = optimized_windows$parameters$window_mode,
    mz_strategy = optimized_windows$parameters$mz_strategy,
    coverage_percentage = optimized_windows$statistics$coverage_percentage,
    window_width_mean = optimized_windows$statistics$window_width_mean,
    window_width_cv = optimized_windows$statistics$window_width_cv,
    precursors_per_window_mean = optimized_windows$statistics$mean_precursors_per_window,
    precursors_per_window_cv = optimized_windows$statistics$cv_precursors,
    time_sec = stage3_time
  ),

  performance = list(
    stage1_sec = stage1_time,
    stage2_sec = stage2_time,
    stage3_sec = stage3_time,
    total_sec = total_time,
    precursors_per_sec = validated_data$metadata$n_precursors / total_time
  )
)

# Save as RDS
saveRDS(summary_report, file.path(OUTPUT_DIR, "summary_report.rds"))
cat(sprintf("✅ Saved: %s\n", file.path(OUTPUT_DIR, "summary_report.rds")))

# Save as JSON
library(jsonlite)
write_json(
  summary_report,
  file.path(OUTPUT_DIR, "summary_report.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)
cat(sprintf("✅ Saved: %s\n", file.path(OUTPUT_DIR, "summary_report.json")))

# =============================================================================
# Final Summary
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════\n")
cat("✅ REFACTORED WORKFLOW TEST COMPLETE\n")
cat("═══════════════════════════════════════════════════════════\n\n")

cat("Output Files:\n")
output_files <- list.files(OUTPUT_DIR, full.names = FALSE)
for (f in output_files) {
  cat(sprintf("  - %s\n", f))
}

cat("\nRecommendations:\n")
cat(sprintf("  Window count: %d per RT bin\n",
            optimization_plan$window_count_per_bin))
cat(sprintf("  Total windows: %d\n", nrow(optimized_windows$windows)))
cat(sprintf("  RT bins: %d (%.1f min each)\n",
            optimized_windows$rt_binning$n_bins,
            optimized_windows$parameters$rt_bin_width_min))
cat(sprintf("  m/z strategy: %s\n",
            optimized_windows$parameters$mz_strategy))
cat(sprintf("  Window mode: %s\n",
            optimized_windows$parameters$window_mode))
cat(sprintf("  Expected coverage: %.1f%%\n",
            optimized_windows$statistics$coverage_percentage))
cat(sprintf("  Expected DPPP satisfaction: %.0f%% → %.0f%%\n",
            optimization_plan$diagnosis$current_satisfaction_ratio * 100,
            optimization_plan$parameters$target_satisfaction * 100))

cat("\nMethod File Ready:\n")
cat(sprintf("  📁 %s\n", method_file))
cat("  → Upload this file to your instrument\n")

cat("\n═══════════════════════════════════════════════════════════\n\n")
