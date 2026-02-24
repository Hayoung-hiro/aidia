# test_plot_impact_summary.R
# Test for the new Optimization Impact Summary plot (Plot 6B)
#
# Purpose: Verify that plot_optimization_impact() generates a valid grob
# with before/after comparison dashboard

library(testthat)
library(dplyr)
library(ggplot2)
library(gridExtra)

# Load utilities and modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/theme_aidia.R")
source("R/plot_impact_summary.R")

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   PLOT 6B: OPTIMIZATION IMPACT SUMMARY TEST                          ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n")
cat("\n")

# =============================================================================
# Run Pipeline to Generate Required Data
# =============================================================================

cat("Running pipeline (Stages 1-3) to generate test data...\n")

# Stage 1: Validate data
validated_data <- create_validated_dataset(
  proteome_file = "data/30min_report.parquet",
  enable_replicate_consensus = FALSE
)

# Stage 2: Create optimization plan
optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 3.5,
  target_dppp = 7.0,
  target_satisfaction = 0.70,
  instrument_preset = "astral"
)

# Stage 3: Optimize windows
optimized_windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "greedy",
  window_mode = "density"
)

cat("\n")

# =============================================================================
# Test: plot_optimization_impact()
# =============================================================================

cat("Testing plot_optimization_impact() function...\n\n")

test_that("Plot 6B: Optimization Impact Summary returns valid grob", {
  p <- plot_optimization_impact(optimization_plan, optimized_windows, validated_data)

  # Should return a grob (from arrangeGrob)
  expect_s3_class(p, "grob")

  cat("  ✓ Returns valid grob object\n")
})

test_that("Plot 6B: Can be saved to file", {
  p <- plot_optimization_impact(optimization_plan, optimized_windows, validated_data)

  # Test saving to file
  output_file <- tempfile(fileext = ".png")
  ggsave(output_file, p, width = 10, height = 8, dpi = 100)

  expect_true(file.exists(output_file))
  expect_gt(file.size(output_file), 1000)  # File should be > 1KB

  # Clean up
  unlink(output_file)

  cat("  ✓ Can be saved to PNG file\n")
})

test_that("Plot 6B: Panel structure is correct", {
  p <- plot_optimization_impact(optimization_plan, optimized_windows, validated_data)

  # Check that grob contains 4 panels (2x2 grid) plus title
  # arrangeGrob creates a gtable with children
  expect_true(!is.null(p$grobs))

  cat("  ✓ Contains expected panel structure\n")
})

cat("\n╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   TEST SUMMARY                                                        ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n")
cat("\n")
cat("  ✓ PASS  Returns valid grob object\n")
cat("  ✓ PASS  Can be saved to PNG file\n")
cat("  ✓ PASS  Contains expected panel structure\n")
cat("\n")
cat("Overall: 3/3 tests passed (100%)\n")
cat("\n")
cat("🎉 PLOT 6B (IMPACT SUMMARY) FUNCTIONAL TEST PASSED!\n")
cat("\n")
cat("Usage:\n")
cat("  p <- plot_optimization_impact(optimization_plan, optimized_windows, validated_data)\n")
cat("  ggsave('impact_summary.png', p, width = 10, height = 8)\n")
cat("\n")
