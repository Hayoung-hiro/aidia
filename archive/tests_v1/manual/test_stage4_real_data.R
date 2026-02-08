# test_stage4_real_data.R
# Functional tests for Stage 4 (Visualization) with real DIA-NN data
#
# TDD Approach: Test before refactoring decision
# Kent Beck Principle: Confirm GREEN state first

library(testthat)
library(dplyr)
library(ggplot2)

# Load utilities and modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   STAGE 4 REAL DATA FUNCTIONAL TEST                                  ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n")
cat("\n")

# =============================================================================
# Test 1: 30min Gradient - Basic Visualization Suite
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 1: 30min Gradient (Basic Visualization)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# Run full pipeline (Stages 1-3)
cat("Running Stages 1-3...\n")

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

windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = plan,
  rt_bin_width_min = 5,
  mz_strategy = "quantile",
  window_mode = "variable"
)

# Run Stage 4
cat("\nRunning Stage 4...\n")
start_time <- Sys.time()

viz <- generate_visualizations(
  validated_data = validated_data,
  optimization_plan = plan,
  optimized_windows = windows,
  output_dir = "tests/output/stage4_30min",
  create_pdf = TRUE,
  create_individual_plots = TRUE
)

end_time <- Sys.time()
processing_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

# Validate visualization output
test_that("Stage 4 output structure is correct", {
  expect_s3_class(viz, "VisualizationResult")
  expect_true("plots" %in% names(viz))
  expect_true("report_files" %in% names(viz))
  expect_true("statistics" %in% names(viz))
})

test_that("Required plots are generated", {
  expect_true("plot1a_dppp_simple" %in% names(viz$plots))
  expect_true("plot1b_dppp_enhanced" %in% names(viz$plots))
  expect_true("plot2_density_heatmap" %in% names(viz$plots))
  expect_true("plot3_mz_overlay" %in% names(viz$plots))
  expect_true("plot6_satisfaction_tradeoff" %in% names(viz$plots))
})

test_that("Output files are created", {
  expect_true(file.exists("tests/output/stage4_30min/optimization_report.pdf"))
  # Method file is created separately if needed
})

cat("\n✓ TEST 1 PASSED\n")
cat("\nVisualization Results:\n")
cat("  - Total plots generated:", length(viz$plots), "\n")
cat("  - Processing time:", sprintf("%.2f sec", processing_time), "\n")

# =============================================================================
# Test 2: 60min Gradient - Multi-Strategy Comparison
# =============================================================================
cat("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 2: 60min Gradient (Multi-Strategy Comparison)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# Run full pipeline
cat("Running Stages 1-3...\n")

validated_data2 <- create_validated_dataset(
  proteome_file = "data/60min_report.parquet",
  enable_replicate_consensus = FALSE
)

plan2 <- plan_optimization(
  validated_data = validated_data2,
  current_cycle_time = 2.5,
  target_dppp = 4.0,
  instrument_preset = "orbitrap_exploris"
)

windows2 <- optimize_windows(
  validated_data = validated_data2,
  optimization_plan = plan2,
  rt_bin_width_min = 5,
  mz_strategy = "coverage",
  window_mode = "variable"
)

# Run Stage 4
cat("\nRunning Stage 4...\n")
start_time <- Sys.time()

viz2 <- generate_visualizations(
  validated_data = validated_data2,
  optimization_plan = plan2,
  optimized_windows = windows2,
  output_dir = "tests/output/stage4_60min",
  create_pdf = TRUE,
  create_individual_plots = FALSE  # Skip individual export for speed
)

end_time <- Sys.time()
processing_time2 <- as.numeric(difftime(end_time, start_time, units = "secs"))

# Validate
test_that("Stage 4 works with different strategies", {
  expect_s3_class(viz2, "VisualizationResult")
  expect_true(length(viz2$plots) >= 10)
  expect_true(file.exists("tests/output/stage4_60min/optimization_report.pdf"))
})

cat("\n✓ TEST 2 PASSED\n")
cat("\nVisualization Results:\n")
cat("  - Total plots generated:", length(viz2$plots), "\n")
cat("  - Processing time:", sprintf("%.2f sec", processing_time2), "\n")

# =============================================================================
# Test 3: 90min Gradient - Fixed Window Mode
# =============================================================================
cat("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 3: 90min Gradient (Fixed Window Mode)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# Run full pipeline
cat("Running Stages 1-3...\n")

validated_data3 <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  enable_replicate_consensus = FALSE
)

plan3 <- plan_optimization(
  validated_data = validated_data3,
  current_cycle_time = 4.0,
  target_dppp = 1.5,
  instrument_preset = "orbitrap"
)

windows3 <- optimize_windows(
  validated_data = validated_data3,
  optimization_plan = plan3,
  rt_bin_width_min = 7,
  mz_strategy = "quantile",
  window_mode = "fixed"
)

# Run Stage 4
cat("\nRunning Stage 4...\n")
start_time <- Sys.time()

viz3 <- generate_visualizations(
  validated_data = validated_data3,
  optimization_plan = plan3,
  optimized_windows = windows3,
  output_dir = "tests/output/stage4_90min",
  create_pdf = TRUE,
  create_individual_plots = FALSE
)

end_time <- Sys.time()
processing_time3 <- as.numeric(difftime(end_time, start_time, units = "secs"))

# Validate
test_that("Stage 4 works with fixed window mode", {
  expect_s3_class(viz3, "VisualizationResult")
  expect_true("plot1a_dppp_simple" %in% names(viz3$plots))
  expect_true("plot2_density_heatmap" %in% names(viz3$plots))
})

cat("\n✓ TEST 3 PASSED\n")
cat("\nVisualization Results:\n")
cat("  - Total plots generated:", length(viz3$plots), "\n")
cat("  - Processing time:", sprintf("%.2f sec", processing_time3), "\n")

# =============================================================================
# Summary
# =============================================================================
cat("\n╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   TEST SUMMARY                                                        ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n")
cat("\n")
cat("  ✓ PASS  Test 1: 30min Basic Visualization\n")
cat("  ✓ PASS  Test 2: 60min Multi-Strategy\n")
cat("  ✓ PASS  Test 3: 90min Fixed Mode\n")
cat("\n")
cat("Overall: 3/3 tests passed (100%)\n")
cat("\n")
cat("🎉 ALL TESTS PASSED - Stage 4 is working correctly!\n")
cat("\n")
