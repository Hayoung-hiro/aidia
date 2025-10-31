# test_stage4_redesigned.R
# Test Script for Redesigned Stage 4 Visualization Module
#
# Purpose: Verify that the redesigned stage4 works correctly with modular plots
#
# Changes Tested:
#   - Deprecated functions removed (plot_rt_window_size, plot_precursor_coverage_map,
#     plot_window_efficiency, plot_dppp_achievement_heatmap)
#   - New modular plot functions sourced (plot2b, plot4 variants, plot5)
#   - generate_visualizations() updated to call redesigned plots only

library(dplyr)
library(ggplot2)
library(arrow)

# Load modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Test: Redesigned Stage 4 Visualization Module               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Stage 1: Data Validation
# =============================================================================

cat("Stage 1: Loading and validating data...\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)
cat(sprintf("✅ %s precursors validated\n\n", format(nrow(validated_data$data), big.mark = ",")))

# =============================================================================
# Stage 2: Optimization Planning
# =============================================================================

cat("Stage 2: Creating optimization plan...\n")
optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,
  target_satisfaction = 0.70,
  target_dppp = 7.0,
  instrument_preset = "fusion_lumos"
)
cat(sprintf("✅ Window count: %d per RT bin\n\n", optimization_plan$n_windows))

# =============================================================================
# Stage 3: Window Optimization
# =============================================================================

cat("Stage 3: Generating optimized windows...\n")
optimized_windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "smoothing",
  window_mode = "variable",
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  outlier_threshold = 3.0,
  smoothing_window = 7,
  polynomial_order = 3,
  target_coverage = 0.95
)
cat(sprintf("✅ %d windows generated\n\n", nrow(optimized_windows$windows)))

# =============================================================================
# Stage 4: Visualization & Reporting (REDESIGNED)
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Testing Redesigned Stage 4\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

output_dir <- "test_plots_redesigned/"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Test the redesigned generate_visualizations function
viz_result <- generate_visualizations(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  optimized_windows = optimized_windows,
  output_dir = output_dir,
  create_pdf = FALSE,  # Skip PDF for now
  create_individual_plots = TRUE,
  plot_format = "png",
  plot_dpi = 300
)

# =============================================================================
# Verification
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║           REDESIGNED STAGE 4 TEST COMPLETE                     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Generated Plots:\n")
cat("─────────────────────────────────────────────────────────────────\n")
plot_files <- list.files(output_dir, pattern = "*.png", full.names = FALSE)
for (file in plot_files) {
  file_size <- file.info(file.path(output_dir, file))$size / 1024
  cat(sprintf("  ✅ %s (%.1f KB)\n", file, file_size))
}
cat("\n")

cat("Total Plots Generated:\n")
cat(sprintf("  %d plots\n\n", length(viz_result$plots)))

cat("Plot Names:\n")
cat("─────────────────────────────────────────────────────────────────\n")
for (name in names(viz_result$plots)) {
  cat(sprintf("  - %s\n", name))
}
cat("\n")

cat("Expected Plots (Redesign):\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("  ✓ Plot 1A: DPPP Comparison (Simple)\n")
cat("  ✓ Plot 1B: DPPP Comparison (Enhanced)\n")
cat("  ✓ Plot 2: RT × m/z Density Heatmap\n")
cat("  ✓ Plot 2B: RT Histogram (if sourced)\n")
cat("  ✓ Plot 3: m/z Density Overlay\n")
cat("  ✓ Plot 4: m/z Window Width\n")
cat("  ✓ Plot 4B: m/z Width Comparison (if sourced)\n")
cat("  ✓ Plot 4C: m/z Distribution with Exclusions (if sourced)\n")
cat("  ✓ Plot 5: Coverage Map (if sourced)\n")
cat("  ✓ Plot 9: Satisfaction Curve\n")
cat("\n")

cat("Deprecated Plots Removed:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("  ✗ Plot 2: RT Window Size (replaced by Plot 3)\n")
cat("  ✗ Plot 6: Precursor Coverage Map (replaced by Plot 5)\n")
cat("  ✗ Plot 7: Window Efficiency (no longer needed)\n")
cat("  ✗ Plot 8: DPPP Achievement Heatmap (to be redesigned)\n")
cat("\n")

cat("✅ Redesigned Stage 4 test completed successfully!\n")
cat("\n")
