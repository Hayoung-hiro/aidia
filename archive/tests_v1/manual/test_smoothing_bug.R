# test_smoothing_bug.R - Debug smoothing strategy bug in multi-strategy plots
#
# Purpose: Reproduce and fix the empty mz_ranges issue in smoothing strategy
# Issue: Line 841 in stage3_window_optimization.R filters by rt_group,
#        but for GLOBAL smoothing, we should use RT.Start range instead

library(testthat)
library(dplyr)
library(arrow)

# Source required files
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")

# =============================================================================
# Test 1: Reproduce the smoothing bug
# =============================================================================

test_that("Smoothing strategy generates valid mz_ranges (not empty)", {
  # Arrange
  cat("\n=== Test 1: Smoothing Strategy Bug Reproduction ===\n")

  # Load 30min data
  validated_data <- create_validated_dataset(
    proteome_file = "data/30min_report.parquet",
    enable_replicate_consensus = FALSE
  )

  # Create optimization plan
  plan <- plan_optimization(
    validated_data = validated_data,
    current_cycle_time = 3.5,
    target_dppp = 7.0,
    instrument_preset = "astral"
  )

  # Act - Run optimization with smoothing strategy
  cat("\nRunning optimization with SMOOTHING strategy...\n")

  windows <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = plan,
    rt_bin_width_min = 5,
    mz_strategy = "smoothing",  # This should trigger the bug
    window_mode = "variable"
  )

  # Assert
  cat("\n=== Validation ===\n")

  # Check that mz_ranges is not empty
  expect_true("mz_optimization" %in% names(windows))
  expect_true("mz_ranges" %in% names(windows$mz_optimization))

  mz_ranges <- windows$mz_optimization$mz_ranges

  cat(sprintf("mz_ranges: %d rows\n", nrow(mz_ranges)))
  cat(sprintf("Columns: %s\n", paste(colnames(mz_ranges), collapse = ", ")))

  # Should have rows equal to number of RT bins
  expect_gt(nrow(mz_ranges), 0)

  # Check for valid m/z values
  expect_true(all(!is.na(mz_ranges$mz_min)))
  expect_true(all(!is.na(mz_ranges$mz_max)))
  expect_true(all(mz_ranges$mz_min < mz_ranges$mz_max))

  # Check coverage values
  cat(sprintf("\nCoverage statistics:\n"))
  cat(sprintf("  Mean coverage: %.2f%%\n", mean(mz_ranges$coverage_ratio, na.rm = TRUE) * 100))
  cat(sprintf("  Min coverage: %.2f%%\n", min(mz_ranges$coverage_ratio, na.rm = TRUE) * 100))
  cat(sprintf("  Max coverage: %.2f%%\n", max(mz_ranges$coverage_ratio, na.rm = TRUE) * 100))

  # Coverage should be reasonable (not all NA)
  non_na_coverage <- sum(!is.na(mz_ranges$coverage_ratio))
  cat(sprintf("  Non-NA coverage values: %d / %d\n", non_na_coverage, nrow(mz_ranges)))

  expect_gt(non_na_coverage, 0)

  cat("\n✅ Test PASSED: Smoothing strategy generates valid mz_ranges\n")
})

# =============================================================================
# Test 2: Compare smoothing vs quantile strategies
# =============================================================================

test_that("Smoothing and quantile strategies both generate valid windows", {
  # Arrange
  cat("\n=== Test 2: Compare Smoothing vs Quantile ===\n")

  validated_data <- create_validated_dataset(
    proteome_file = "data/30min_report.parquet",
    enable_replicate_consensus = FALSE
  )

  plan <- plan_optimization(
    validated_data = validated_data,
    current_cycle_time = 3.5,
    target_dppp = 7.0,
    instrument_preset = "astral"
  )

  # Act - Run both strategies
  cat("\n--- Strategy 1: QUANTILE ---\n")
  windows_quantile <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = plan,
    rt_bin_width_min = 5,
    mz_strategy = "quantile",
    window_mode = "variable"
  )

  cat("\n--- Strategy 2: SMOOTHING ---\n")
  windows_smoothing <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = plan,
    rt_bin_width_min = 5,
    mz_strategy = "smoothing",
    window_mode = "variable"
  )

  # Assert
  cat("\n=== Comparison ===\n")

  # Both should have same number of RT bins
  n_bins_quantile <- nrow(windows_quantile$mz_optimization$mz_ranges)
  n_bins_smoothing <- nrow(windows_smoothing$mz_optimization$mz_ranges)

  cat(sprintf("Quantile RT bins: %d\n", n_bins_quantile))
  cat(sprintf("Smoothing RT bins: %d\n", n_bins_smoothing))

  expect_equal(n_bins_quantile, n_bins_smoothing)

  # Both should have valid coverage
  coverage_quantile <- mean(windows_quantile$mz_optimization$mz_ranges$coverage_ratio, na.rm = TRUE)
  coverage_smoothing <- mean(windows_smoothing$mz_optimization$mz_ranges$coverage_ratio, na.rm = TRUE)

  cat(sprintf("Quantile mean coverage: %.2f%%\n", coverage_quantile * 100))
  cat(sprintf("Smoothing mean coverage: %.2f%%\n", coverage_smoothing * 100))

  expect_gt(coverage_quantile, 0.5)  # Should cover >50%
  expect_gt(coverage_smoothing, 0.5)

  # Both should have similar total windows
  cat(sprintf("Quantile total windows: %d\n", nrow(windows_quantile$windows)))
  cat(sprintf("Smoothing total windows: %d\n", nrow(windows_smoothing$windows)))

  expect_gt(nrow(windows_smoothing$windows), 0)

  cat("\n✅ Test PASSED: Both strategies generate valid windows\n")
})

# =============================================================================
# Run tests
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  Smoothing Strategy Bug Test\n")
cat("═══════════════════════════════════════════════════════════\n")

test_file("tests/manual/test_smoothing_bug.R")
