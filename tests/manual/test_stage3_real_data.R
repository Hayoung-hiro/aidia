# test_stage3_real_data.R - Real Data Functional Test for Stage 3
# DIA Window Optimizer v2.0
#
# Purpose: Test Stage 3 (Window Optimization) with actual data pipeline
# Tests: RT binning, m/z optimization, window generation

library(dplyr)
library(tibble)

# Source all required modules
source("R/data_validation.R")
source("R/replicate_utils.R")
source("R/column_selection.R")
source("R/quality_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   STAGE 3 REAL DATA FUNCTIONAL TEST                                  ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n\n")

# ============================================================================
# Test 1: 30min Gradient - Quantile Strategy + Variable Mode
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 1: 30min Gradient (Quantile + Variable)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

test1_result <- tryCatch({
  # Stage 1: Validate data
  cat("Running Stage 1...\n")
  validated_data <- create_validated_dataset(
    proteome_file = "data/30min_report.parquet",
    enable_replicate_consensus = FALSE,
    quality_threshold = 0.7
  )

  cat("\n")

  # Stage 2: Plan optimization
  cat("Running Stage 2...\n")
  plan <- plan_optimization(
    validated_data = validated_data,
    current_cycle_time = 3.5,
    instrument_preset = "astral",
    target_dppp = 7.0,
    target_satisfaction = 0.85
  )

  cat("\n")

  # Stage 3: Optimize windows
  cat("Running Stage 3...\n")
  windows <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = plan,
    rt_bin_width_min = 5,
    mz_strategy = "quantile",
    window_mode = "density"
  )

  cat("\n✓ TEST 1 PASSED\n")
  cat("\nWindow Optimization Results:\n")
  cat(sprintf("  - Total windows: %d\n", nrow(windows$windows)))
  cat(sprintf("  - RT bins: %d\n", windows$metadata$n_rt_bins))
  cat(sprintf("  - Windows per bin: %d\n", windows$metadata$n_windows_per_bin))
  cat(sprintf("  - Total precursors: %d\n", windows$metadata$n_precursors))
  cat(sprintf("  - Covered precursors: %d (%.1f%%)\n",
              windows$statistics$n_covered,
              windows$statistics$coverage_pct))
  cat(sprintf("  - Processing time: %.2f sec\n", windows$metadata$processing_time_sec))

  windows

}, error = function(e) {
  cat("\n✗ TEST 1 FAILED\n")
  cat(sprintf("  Error: %s\n", e$message))
  cat(sprintf("  Traceback:\n%s\n", paste(capture.output(traceback()), collapse = "\n")))
  NULL
})


# ============================================================================
# Test 2: 60min Gradient - Coverage Strategy + Variable Mode
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 2: 60min Gradient (Coverage + Variable)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

test2_result <- tryCatch({
  cat("Running Stage 1...\n")
  validated_data <- create_validated_dataset(
    proteome_file = "data/60min_report.parquet",
    enable_replicate_consensus = FALSE,
    quality_threshold = 0.7
  )

  cat("\n")
  cat("Running Stage 2...\n")
  plan <- plan_optimization(
    validated_data = validated_data,
    current_cycle_time = 2.5,
    instrument_preset = "orbitrap_exploris",
    target_dppp = 4.0
  )

  cat("\n")
  cat("Running Stage 3...\n")
  windows <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = plan,
    rt_bin_width_min = 5,
    mz_strategy = "coverage",
    target_coverage = 0.95,
    window_mode = "density"
  )

  cat("\n✓ TEST 2 PASSED\n")
  cat("\nWindow Optimization Results:\n")
  cat(sprintf("  - Total windows: %d\n", nrow(windows$windows)))
  cat(sprintf("  - RT bins: %d\n", windows$metadata$n_rt_bins))
  cat(sprintf("  - Coverage: %.1f%%\n", windows$statistics$coverage_pct))
  cat(sprintf("  - Processing time: %.2f sec\n", windows$metadata$processing_time_sec))

  windows

}, error = function(e) {
  cat("\n✗ TEST 2 FAILED\n")
  cat(sprintf("  Error: %s\n", e$message))
  NULL
})


# ============================================================================
# Test 3: 90min Gradient - Quantile + Fixed Mode
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 3: 90min Gradient (Quantile + Fixed)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

test3_result <- tryCatch({
  cat("Running Stage 1...\n")
  validated_data <- create_validated_dataset(
    proteome_file = "data/90min_report.parquet",
    enable_replicate_consensus = FALSE,
    quality_threshold = 0.7
  )

  cat("\n")
  cat("Running Stage 2...\n")
  plan <- plan_optimization(
    validated_data = validated_data,
    current_cycle_time = 4.0,
    instrument_preset = "orbitrap",
    target_dppp = 1.5
  )

  cat("\n")
  cat("Running Stage 3...\n")
  windows <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = plan,
    rt_bin_width_min = 7,  # Longer bins for 90min gradient
    mz_strategy = "quantile",
    window_mode = "fixed"  # Test fixed mode
  )

  cat("\n✓ TEST 3 PASSED\n")
  cat("\nWindow Optimization Results:\n")
  cat(sprintf("  - Total windows: %d\n", nrow(windows$windows)))
  cat(sprintf("  - RT bins: %d\n", windows$metadata$n_rt_bins))
  cat(sprintf("  - Coverage: %.1f%%\n", windows$statistics$coverage_pct))
  cat(sprintf("  - Window mode: %s\n", windows$metadata$window_mode))
  cat(sprintf("  - Processing time: %.2f sec\n", windows$metadata$processing_time_sec))

  windows

}, error = function(e) {
  cat("\n✗ TEST 3 FAILED\n")
  cat(sprintf("  Error: %s\n", e$message))
  NULL
})


# ============================================================================
# Summary
# ============================================================================

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   TEST SUMMARY                                                        ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n\n")

test_results <- c(
  test1 = !is.null(test1_result),
  test2 = !is.null(test2_result),
  test3 = !is.null(test3_result)
)

for (i in seq_along(test_results)) {
  test_name <- names(test_results)[i]
  status <- ifelse(test_results[i], "✓ PASS", "✗ FAIL")

  test_desc <- switch(test_name,
    test1 = "30min Quantile+Variable",
    test2 = "60min Coverage+Variable",
    test3 = "90min Quantile+Fixed"
  )

  cat(sprintf("  %s  Test %d: %s\n", status, i, test_desc))
}

passed <- sum(test_results, na.rm = TRUE)
total <- length(test_results)

cat(sprintf("\nOverall: %d/%d tests passed (%.0f%%)\n", passed, total, 100 * passed / total))

if (passed == total) {
  cat("\n🎉 ALL TESTS PASSED - Stage 3 is working correctly!\n\n")
} else {
  cat("\n⚠️  SOME TESTS FAILED - Review errors above\n\n")
}

# Return summary invisibly
invisible(list(
  test1 = test1_result,
  test2 = test2_result,
  test3 = test3_result,
  passed = passed,
  total = total
))
