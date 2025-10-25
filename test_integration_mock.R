# test_integration_mock.R - Integration Test with Mock Data
#
# Purpose: Test Stage 2 and Stage 3 integration with mock data
# This verifies that the refactored modules work together correctly.

cat("═══════════════════════════════════════════════════════════\n")
cat("  Integration Test - Mock Data\n")
cat("═══════════════════════════════════════════════════════════\n\n")

library(dplyr)
library(tibble)

# Load refactored modules
cat("Loading modules...\n")
source("R/utils_common.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
cat("✅ Modules loaded\n\n")

# =============================================================================
# Create Mock ValidatedData (simulating Stage 1 output)
# =============================================================================

cat("Creating mock ValidatedData...\n")

set.seed(42)
n_precursors <- 10000

# Simulate realistic precursor data
mock_data <- tibble(
  RT.Start = runif(n_precursors, min = 5, max = 120),  # 5-120 min gradient
  Precursor.Mz = runif(n_precursors, min = 400, max = 1200),  # 400-1200 Da
  FWHM = rnorm(n_precursors, mean = 0.3, sd = 0.05),  # ~0.3 min FWHM
  Precursor.Id = paste0("P", 1:n_precursors),
  Protein.Names = paste0("Protein", sample(1:1000, n_precursors, replace = TRUE))
)

# Create ValidatedData structure (matching Stage 1 output format)
validated_data <- structure(
  list(
    data = mock_data,

    metadata = list(
      n_precursors = n_precursors,
      rt_range = c(min(mock_data$RT.Start), max(mock_data$RT.Start)),
      mz_range = c(min(mock_data$Precursor.Mz), max(mock_data$Precursor.Mz)),
      fwhm_stats = list(
        mean = mean(mock_data$FWHM),
        median = median(mock_data$FWHM),
        sd = sd(mock_data$FWHM),
        min = min(mock_data$FWHM),
        max = max(mock_data$FWHM)
      ),
      file_info = list(
        source_file = "mock_data",
        n_rows_original = n_precursors,
        n_rows_filtered = n_precursors
      ),
      processing_time_sec = 0.1
    ),

    validation_status = list(
      all_passed = TRUE,
      quality_score = 0.95,
      errors = character(0),
      warnings = character(0)
    )
  ),
  class = c("ValidatedData", "list")
)

cat(sprintf("✅ Mock ValidatedData created: %d precursors\n", n_precursors))
cat(sprintf("   RT range: %.1f - %.1f min\n",
            validated_data$metadata$rt_range[1],
            validated_data$metadata$rt_range[2]))
cat(sprintf("   m/z range: %.1f - %.1f Da\n",
            validated_data$metadata$mz_range[1],
            validated_data$metadata$mz_range[2]))
cat(sprintf("   FWHM median: %.3f min (%.1f sec)\n",
            validated_data$metadata$fwhm_stats$median,
            validated_data$metadata$fwhm_stats$median * 60))

# =============================================================================
# Test Stage 2: Optimization Planning
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  Testing Stage 2: Optimization Planning\n")
cat("═══════════════════════════════════════════════════════════\n\n")

# Estimate current cycle time
current_cycle_time <- validated_data$metadata$fwhm_stats$mean * 60 / 7.0

cat(sprintf("Test parameters:\n"))
cat(sprintf("  Current cycle time: %.3f sec\n", current_cycle_time))
cat(sprintf("  Target DPPP: 7.0\n"))
cat(sprintf("  Target satisfaction: 85%%\n"))
cat(sprintf("  Instrument: orbitrap\n\n"))

# Run Stage 2
tryCatch({
  optimization_plan <- plan_optimization(
    validated_data = validated_data,
    current_cycle_time = current_cycle_time,
    instrument_preset = "orbitrap",
    target_dppp = 7.0,
    target_satisfaction = 0.85,
    load_factor = 0.8
  )

  cat("\n✅ Stage 2 SUCCESS\n")
  cat(sprintf("   Output type: %s\n", paste(class(optimization_plan), collapse = ", ")))
  cat(sprintf("   Window count: %d per RT bin\n",
              optimization_plan$window_count_per_bin))
  cat(sprintf("   Required cycle time: %.3f sec\n",
              optimization_plan$required_cycle_time_sec))
  cat(sprintf("   Feasibility: %s\n",
              if(optimization_plan$feasibility$is_feasible) "✅ PASS" else "⚠️  WARNINGS"))

}, error = function(e) {
  cat("\n❌ Stage 2 FAILED\n")
  cat("Error:", e$message, "\n")
  stop("Stage 2 integration test failed")
})

# =============================================================================
# Test Stage 3: Window Optimization
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  Testing Stage 3: Window Optimization\n")
cat("═══════════════════════════════════════════════════════════\n\n")

cat("Test parameters:\n")
cat("  RT bin width: 5 min\n")
cat("  m/z strategy: quantile\n")
cat("  Window mode: variable\n\n")

# Run Stage 3
tryCatch({
  optimized_windows <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    rt_bin_width_min = 5,
    mz_strategy = "quantile",
    window_mode = "variable",
    target_coverage = 0.95,
    quantile_lower = 0.05,
    quantile_upper = 0.95
  )

  cat("\n✅ Stage 3 SUCCESS\n")
  cat(sprintf("   Output type: %s\n", paste(class(optimized_windows), collapse = ", ")))
  cat(sprintf("   Total windows: %d\n", nrow(optimized_windows$windows)))
  cat(sprintf("   RT bins: %d\n", optimized_windows$rt_binning$n_bins))
  cat(sprintf("   Coverage: %.1f%%\n",
              optimized_windows$statistics$coverage_percentage))
  cat(sprintf("   Mean window width: %.2f Da\n",
              optimized_windows$statistics$window_width_mean))

}, error = function(e) {
  cat("\n❌ Stage 3 FAILED\n")
  cat("Error:", e$message, "\n")
  stop("Stage 3 integration test failed")
})

# =============================================================================
# Verify Data Flow Integration
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  Verifying Data Flow Integration\n")
cat("═══════════════════════════════════════════════════════════\n\n")

checks_passed <- 0
checks_total <- 0

# Check 1: Stage 2 consumed Stage 1 correctly
checks_total <- checks_total + 1
if (optimization_plan$diagnosis$n_total == n_precursors) {
  cat("✅ Check 1: Stage 2 received correct precursor count\n")
  checks_passed <- checks_passed + 1
} else {
  cat(sprintf("❌ Check 1: Precursor count mismatch (%d vs %d)\n",
              optimization_plan$diagnosis$n_total, n_precursors))
}

# Check 2: Stage 3 consumed Stage 2 correctly
checks_total <- checks_total + 1
expected_total_windows <- optimization_plan$window_count_per_bin *
                          optimized_windows$rt_binning$n_bins
actual_windows <- nrow(optimized_windows$windows)
deviation_pct <- abs(actual_windows - expected_total_windows) / expected_total_windows * 100

if (deviation_pct < 10) {  # Allow 10% deviation
  cat(sprintf("✅ Check 2: Window count matches plan (%.1f%% deviation)\n",
              deviation_pct))
  checks_passed <- checks_passed + 1
} else {
  cat(sprintf("❌ Check 2: Window count deviation too large (%.1f%%)\n",
              deviation_pct))
}

# Check 3: Stage 3 consumed Stage 1 correctly
checks_total <- checks_total + 1
if (optimized_windows$statistics$total_precursors == n_precursors) {
  cat("✅ Check 3: Stage 3 received correct precursor count\n")
  checks_passed <- checks_passed + 1
} else {
  cat(sprintf("❌ Check 3: Precursor count mismatch (%d vs %d)\n",
              optimized_windows$statistics$total_precursors, n_precursors))
}

# Check 4: Output data structures are valid
checks_total <- checks_total + 1
required_plan_fields <- c("window_count_per_bin", "required_cycle_time_sec",
                          "diagnosis", "feasibility", "instrument")
plan_ok <- all(required_plan_fields %in% names(optimization_plan))

required_windows_fields <- c("windows", "statistics", "rt_binning",
                             "mz_optimization", "parameters")
windows_ok <- all(required_windows_fields %in% names(optimized_windows))

if (plan_ok && windows_ok) {
  cat("✅ Check 4: Output data structures are valid\n")
  checks_passed <- checks_passed + 1
} else {
  cat("❌ Check 4: Missing required fields in outputs\n")
  if (!plan_ok) cat("   Missing in OptimizationPlan:",
                     setdiff(required_plan_fields, names(optimization_plan)), "\n")
  if (!windows_ok) cat("   Missing in OptimizedWindows:",
                        setdiff(required_windows_fields, names(optimized_windows)), "\n")
}

# Check 5: Windows tibble has required columns
checks_total <- checks_total + 1
required_window_cols <- c("window_id", "rt_segment_id", "rt_start", "rt_end",
                          "mz_start", "mz_end", "window_width", "n_precursors")
windows_cols_ok <- all(required_window_cols %in% names(optimized_windows$windows))

if (windows_cols_ok) {
  cat("✅ Check 5: Windows tibble has all required columns\n")
  checks_passed <- checks_passed + 1
} else {
  cat("❌ Check 5: Missing columns in windows tibble\n")
  cat("   Missing:", setdiff(required_window_cols, names(optimized_windows$windows)), "\n")
}

# Check 6: Coverage is reasonable
checks_total <- checks_total + 1
if (optimized_windows$statistics$coverage_percentage > 80) {
  cat(sprintf("✅ Check 6: Coverage is reasonable (%.1f%%)\n",
              optimized_windows$statistics$coverage_percentage))
  checks_passed <- checks_passed + 1
} else {
  cat(sprintf("⚠️  Check 6: Low coverage (%.1f%%)\n",
              optimized_windows$statistics$coverage_percentage))
}

# =============================================================================
# Final Results
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  Integration Test Results\n")
cat("═══════════════════════════════════════════════════════════\n\n")

cat(sprintf("Checks passed: %d / %d\n", checks_passed, checks_total))

if (checks_passed == checks_total) {
  cat("\n✅✅✅ ALL INTEGRATION TESTS PASSED ✅✅✅\n")
  cat("\nConclusion:\n")
  cat("  - Stage 2 (Optimization Planning) works correctly\n")
  cat("  - Stage 3 (Window Optimization) works correctly\n")
  cat("  - Data flows correctly between stages\n")
  cat("  - Output structures are valid\n")
  cat("\n🎉 The refactored 3-stage pipeline is FULLY INTEGRATED! 🎉\n")

} else {
  cat("\n⚠️  SOME INTEGRATION TESTS FAILED\n")
  cat(sprintf("\nFailed checks: %d\n", checks_total - checks_passed))
  cat("Please review the errors above.\n")
}

cat("\n═══════════════════════════════════════════════════════════\n\n")
