# test_stage2_real_data.R - Real Data Functional Test for Stage 2
# DIA Window Optimizer v2.0
#
# Purpose: Test Stage 2 (Optimization Planning) with actual Stage 1 output
# Tests: DPPP diagnosis, cycle time calculation, window count determination

library(dplyr)
library(tibble)

# Source Stage 1 and Stage 2 modules
source("R/stage1_data_validation.R")
source("R/replicate_utils.R")
source("R/column_selection_simple.R")
source("R/quality_validation.R")
source("R/stage2_optimization_planning.R")

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   STAGE 2 REAL DATA FUNCTIONAL TEST                                  ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n\n")

# ============================================================================
# Test 1: 30min Gradient - Astral Instrument
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 1: 30min Gradient (Thermo Astral, DPPP 7.0)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

test1_result <- tryCatch({
  # Stage 1: Load and validate data
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
    current_cycle_time = 3.5,  # Example current cycle time
    instrument_preset = "astral",
    target_dppp = 7.0,
    target_satisfaction = 0.85,
    load_factor = 0.8
  )

  cat("\n✓ TEST 1 PASSED\n")
  cat("\nDPPP Diagnosis:\n")
  cat(sprintf("  - Current mean DPPP: %.2f\n", plan$diagnosis$current_dppp_mean))
  cat(sprintf("  - Current median DPPP: %.2f\n", plan$diagnosis$current_dppp_median))
  cat(sprintf("  - Satisfaction ratio: %.1f%% (target: %.0f%%)\n",
              plan$diagnosis$current_satisfaction_ratio * 100,
              plan$diagnosis$target_satisfaction * 100))

  cat("\nCycle Time Recommendation:\n")
  cat(sprintf("  - Current cycle time: %.2f sec\n", plan$diagnosis$current_cycle_time_sec))
  cat(sprintf("  - Required for DPPP %.1f: %.2f sec\n",
              plan$diagnosis$target_dppp,
              plan$required_cycle_time_sec))
  cat(sprintf("  - Status: %s\n", ifelse(plan$feasibility$is_feasible, "✓ Feasible", "✗ Not feasible")))

  cat("\nWindow Count:\n")
  cat(sprintf("  - Recommended windows: %d\n", plan$window_count_per_bin))
  cat(sprintf("  - Feasibility: %s\n", ifelse(plan$feasibility$is_feasible, "✓ Feasible", "✗ Not feasible")))
  cat(sprintf("  - Max possible: %d\n", plan$feasibility$max_possible_scans))

  cat(sprintf("\nProcessing time: %.2f sec\n", plan$metadata$processing_time_sec))

  plan

}, error = function(e) {
  cat("\n✗ TEST 1 FAILED\n")
  cat(sprintf("  Error: %s\n", e$message))
  cat(sprintf("  Traceback: %s\n", paste(as.character(sys.calls()), collapse = "\n  ")))
  NULL
})


# ============================================================================
# Test 2: 60min Gradient - Orbitrap Exploris
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 2: 60min Gradient (Orbitrap Exploris, DPPP 4.0 Balanced)\n")
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
    target_dppp = 4.0,  # Balanced mode
    target_satisfaction = 0.85,
    load_factor = 0.8
  )

  cat("\n✓ TEST 2 PASSED\n")
  cat("\nDPPP Diagnosis:\n")
  cat(sprintf("  - Current mean DPPP: %.2f\n", plan$diagnosis$current_dppp_mean))
  cat(sprintf("  - Satisfaction ratio: %.1f%%\n", plan$diagnosis$current_satisfaction_ratio * 100))

  cat("\nWindow Count:\n")
  cat(sprintf("  - Recommended windows: %d\n", plan$window_count_per_bin))
  cat(sprintf("  - Feasibility: %s\n", ifelse(plan$feasibility$is_feasible, "✓", "✗")))

  cat(sprintf("\nProcessing time: %.2f sec\n", plan$metadata$processing_time_sec))

  plan

}, error = function(e) {
  cat("\n✗ TEST 2 FAILED\n")
  cat(sprintf("  Error: %s\n", e$message))
  NULL
})


# ============================================================================
# Test 3: 90min Gradient - Traditional Orbitrap (ID mode)
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 3: 90min Gradient (Traditional Orbitrap, DPPP 1.5 ID mode)\n")
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
    target_dppp = 1.5,  # ID mode
    target_satisfaction = 0.85,
    load_factor = 0.8
  )

  cat("\n✓ TEST 3 PASSED\n")
  cat("\nDPPP Diagnosis:\n")
  cat(sprintf("  - Current mean DPPP: %.2f\n", plan$diagnosis$current_dppp_mean))
  cat(sprintf("  - Satisfaction ratio: %.1f%%\n", plan$diagnosis$current_satisfaction_ratio * 100))

  cat("\nWindow Count:\n")
  cat(sprintf("  - Recommended windows: %d\n", plan$window_count_per_bin))
  cat(sprintf("  - Feasibility: %s\n", ifelse(plan$feasibility$is_feasible, "✓", "✗")))

  cat(sprintf("\nProcessing time: %.2f sec\n", plan$metadata$processing_time_sec))

  plan

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
    test1 = "30min Astral (DPPP 7.0)",
    test2 = "60min Exploris (DPPP 4.0)",
    test3 = "90min Orbitrap (DPPP 1.5)"
  )

  cat(sprintf("  %s  Test %d: %s\n", status, i, test_desc))
}

passed <- sum(test_results, na.rm = TRUE)
total <- length(test_results)

cat(sprintf("\nOverall: %d/%d tests passed (%.0f%%)\n", passed, total, 100 * passed / total))

if (passed == total) {
  cat("\n🎉 ALL TESTS PASSED - Stage 2 is working correctly!\n\n")
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
