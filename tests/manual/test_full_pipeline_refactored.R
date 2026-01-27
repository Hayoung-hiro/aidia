# Test Script: Full Pipeline Integration Test (Refactored Version)
# Purpose: Verify end-to-end pipeline functionality with refactored modules
# Version: 1.0
# Date: 2025-11-28

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Full Pipeline Integration Test (Refactored)                 ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Set up test environment
setwd("d:/Projects/dia_window_optimizer")

# Load all modules
cat("Loading modules...\n")
suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(ggplot2)
  library(yaml)
})

source("R/s3_classes.R")
source("R/utils_common.R")
source("R/smoothing_utils.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")

# Load Stage 3 modules
source("R/stage3/stage3_rt_binning.R")
source("R/stage3/stage3_mz_optimization.R")
source("R/stage3/stage3_window_generation.R")
source("R/stage3/stage3_statistics.R")
source("R/stage3/stage3_export.R")
source("R/stage3_window_optimization.R")

# Load Stage 4 modules
source("R/plots/plot_dppp.R")
source("R/plots/plot_density.R")
source("R/plots/plot_histogram.R")
source("R/plots/plot_coverage.R")
source("R/plots/plot_satisfaction.R")
source("R/plots/plot_window.R")
source("R/stage4_export.R")
source("R/stage4_visualization.R")

cat("✅ All modules loaded\n\n")

# Test configuration
test_file <- "data/30min_report.parquet"
output_dir <- "tests/manual/refactored_output"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

test_results <- list()
timing <- list()

# =============================================================================
# Stage 1: Data Validation
# =============================================================================

cat("═══════════════════════════════════════════════════════════════\n")
cat("Stage 1: Data Validation\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

stage1_start <- Sys.time()

tryCatch({
  cat(sprintf("Input file: %s\n", test_file))

  validated <- create_validated_dataset(
    proteome_file = test_file,
    enable_replicate_consensus = TRUE,
    max_intensity_cv_percent = 30
  )

  # Verify output
  if (!inherits(validated, "ValidatedData")) {
    stop("Output is not ValidatedData class")
  }

  # Validate structure
  validate_ValidatedData(validated)

  # Check data
  n_precursors <- nrow(validated$data)
  rt_range <- range(validated$data$RT.Start)
  mz_range <- range(validated$data$Precursor.Mz)

  cat(sprintf("\n✅ Stage 1 PASSED\n"))
  cat(sprintf("   Precursors: %d\n", n_precursors))
  cat(sprintf("   RT range: %.1f - %.1f min\n", rt_range[1], rt_range[2]))
  cat(sprintf("   m/z range: %.1f - %.1f\n", mz_range[1], mz_range[2]))

  test_results[["stage1"]] <- "PASS"

}, error = function(e) {
  cat(sprintf("\n❌ Stage 1 FAILED: %s\n", e$message))
  test_results[["stage1"]] <- "FAIL"
  stop("Stage 1 failed, cannot continue")
})

stage1_end <- Sys.time()
timing[["stage1"]] <- as.numeric(difftime(stage1_end, stage1_start, units = "secs"))

# =============================================================================
# Stage 2: Optimization Planning
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Stage 2: Optimization Planning\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

stage2_start <- Sys.time()

tryCatch({
  # current_cycle_time = NULL → auto-estimated from gradient length
  plan <- plan_optimization(
    validated_data = validated,
    current_cycle_time = NULL,  # Auto-estimate from gradient
    instrument_preset = "fusion_lumos",
    target_dppp = 7.0,
    target_satisfaction = 0.70,
    load_factor = 0.80
  )

  # Verify output
  if (!inherits(plan, "OptimizationPlan")) {
    stop("Output is not OptimizationPlan class")
  }

  # Validate structure
  validate_OptimizationPlan(plan)

  cat(sprintf("\n✅ Stage 2 PASSED\n"))
  cat(sprintf("   Required cycle time: %.3f sec\n", plan$recommendation$required_cycle_time))
  cat(sprintf("   Windows per RT bin: %d\n", plan$recommendation$windows_per_rt_bin))
  cat(sprintf("   Current satisfaction: %.1f%%\n", plan$current_state$satisfaction_ratio * 100))

  test_results[["stage2"]] <- "PASS"

}, error = function(e) {
  cat(sprintf("\n❌ Stage 2 FAILED: %s\n", e$message))
  test_results[["stage2"]] <- "FAIL"
  stop("Stage 2 failed, cannot continue")
})

stage2_end <- Sys.time()
timing[["stage2"]] <- as.numeric(difftime(stage2_end, stage2_start, units = "secs"))

# =============================================================================
# Stage 3: Window Optimization (4 strategies)
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Stage 3: Window Optimization (4 Strategies)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

stage3_start <- Sys.time()

strategies <- c("quantile", "smoothing", "outlier", "coverage")
windows_list <- list()
stage3_passed <- 0
stage3_failed <- 0

for (strategy in strategies) {
  cat(sprintf("\nTesting strategy: %s\n", strategy))

  tryCatch({
    windows <- optimize_windows(
      validated_data = validated,
      optimization_plan = plan,
      rt_bin_width_min = 5.0,
      mz_strategy = strategy,
      window_mode = "variable"
    )

    # Verify output
    if (!inherits(windows, "OptimizedWindows")) {
      stop(sprintf("Output for %s is not OptimizedWindows class", strategy))
    }

    # Validate structure
    validate_OptimizedWindows(windows)

    # Store result
    windows_list[[strategy]] <- windows

    cat(sprintf("  ✅ %s: %d windows, %.1f%% coverage\n",
                strategy,
                nrow(windows$windows),
                windows$statistics$coverage_pct))

    stage3_passed <- stage3_passed + 1
    test_results[[paste0("stage3_", strategy)]] <- "PASS"

  }, error = function(e) {
    cat(sprintf("  ❌ %s FAILED: %s\n", strategy, e$message))
    stage3_failed <- stage3_failed + 1
    test_results[[paste0("stage3_", strategy)]] <- "FAIL"
  })
}

cat(sprintf("\n✅ Stage 3 Summary: %d/%d strategies passed\n",
            stage3_passed, length(strategies)))

if (stage3_failed > 0) {
  cat(sprintf("⚠️  Warning: %d strategies failed\n", stage3_failed))
}

test_results[["stage3"]] <- if (stage3_passed == length(strategies)) "PASS" else "PARTIAL"

stage3_end <- Sys.time()
timing[["stage3"]] <- as.numeric(difftime(stage3_end, stage3_start, units = "secs"))

# =============================================================================
# Stage 3 Export: Method Files
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Stage 3 Export: Method Files\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

export_start <- Sys.time()

tryCatch({
  # Export all strategies
  export_method_files(
    windows_list = windows_list,
    output_dir = output_dir,
    validated_data = validated,
    optimization_plan = plan,
    instrument_type = "fusion_lumos"
  )

  # Count exported files
  method_files <- list.files(output_dir, pattern = ".*_thermo\\.csv$")

  cat(sprintf("\n✅ Export PASSED\n"))
  cat(sprintf("   Exported %d method files:\n", length(method_files)))
  for (file in method_files) {
    cat(sprintf("     - %s\n", file))
  }

  test_results[["export"]] <- "PASS"

}, error = function(e) {
  cat(sprintf("\n❌ Export FAILED: %s\n", e$message))
  test_results[["export"]] <- "FAIL"
})

export_end <- Sys.time()
timing[["export"]] <- as.numeric(difftime(export_end, export_start, units = "secs"))

# =============================================================================
# Stage 4: Visualization (Plot Generation)
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Stage 4: Visualization (6 Key Plots)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

stage4_start <- Sys.time()

tryCatch({
  # Select one strategy for detailed visualization
  selected_strategy <- "coverage"

  viz <- generate_visualizations(
    validated_data = validated,
    optimization_plan = plan,
    optimized_windows = windows_list[[selected_strategy]],
    windows_list = windows_list,
    output_dir = output_dir,
    create_individual_plots = TRUE,
    create_pdf = FALSE  # Skip PDF for faster testing
  )

  # Verify plots were created
  plot_files <- list.files(output_dir, pattern = "\\.png$")

  cat(sprintf("\n✅ Stage 4 PASSED\n"))
  cat(sprintf("   Generated %d plot files\n", length(plot_files)))

  test_results[["stage4"]] <- "PASS"

}, error = function(e) {
  cat(sprintf("\n❌ Stage 4 FAILED: %s\n", e$message))
  cat(sprintf("   Error details: %s\n", traceback()))
  test_results[["stage4"]] <- "FAIL"
})

stage4_end <- Sys.time()
timing[["stage4"]] <- as.numeric(difftime(stage4_end, stage4_start, units = "secs"))

# =============================================================================
# Final Summary
# =============================================================================

cat("\n\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║             FULL PIPELINE TEST SUMMARY                        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Calculate statistics
total_tests <- length(test_results)
passed <- sum(test_results == "PASS")
failed <- sum(test_results == "FAIL")
partial <- sum(test_results == "PARTIAL")

cat(sprintf("Total stages: %d\n", total_tests))
cat(sprintf("✅ Passed: %d\n", passed))
cat(sprintf("⚠️  Partial: %d\n", partial))
cat(sprintf("❌ Failed: %d\n", failed))
cat(sprintf("Success rate: %.1f%%\n\n", (passed / total_tests) * 100))

# Timing report
cat("Timing Report:\n")
total_time <- 0
for (stage in names(timing)) {
  cat(sprintf("  %s: %.2f sec\n", stage, timing[[stage]]))
  total_time <- total_time + timing[[stage]]
}
cat(sprintf("\nTotal execution time: %.2f sec\n\n", total_time))

# Test results detail
cat("Detailed Results:\n")
status_icons <- c(PASS = "✅", PARTIAL = "⚠️", FAIL = "❌")
for (test_name in names(test_results)) {
  result <- test_results[[test_name]]
  icon <- status_icons[[result]] %||% "❌"  # Default to fail icon
  cat(sprintf("  %s %s: %s\n", icon, test_name, result))
}

# Overall verdict
cat("\n")
if (failed == 0 && partial == 0) {
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║          ✅ ALL TESTS PASSED - PIPELINE FUNCTIONAL             ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n")
  verdict <- "SUCCESS"
} else if (failed == 0) {
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║       ⚠️  PARTIAL SUCCESS - SOME FEATURES DEGRADED              ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n")
  verdict <- "PARTIAL"
} else {
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║          ❌ TESTS FAILED - PIPELINE NOT FUNCTIONAL              ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n")
  verdict <- "FAILURE"
}

# Save results
saveRDS(list(
  test_results = test_results,
  timing = timing,
  summary = list(
    total = total_tests,
    passed = passed,
    partial = partial,
    failed = failed,
    success_rate = (passed / total_tests) * 100,
    total_time = total_time
  ),
  verdict = verdict,
  output_dir = output_dir
), "tests/manual/pipeline_test_results.rds")

cat(sprintf("\nResults saved to: tests/manual/pipeline_test_results.rds\n"))
cat(sprintf("Output files in: %s\n\n", output_dir))
