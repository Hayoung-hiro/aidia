# test_stage4_complete.R
# Complete Stage 4 Visualization Test
#
# Purpose: Test integrated Stage 4 visualization with Plot 2B and Plot 5

library(dplyr)
library(ggplot2)
library(tidyr)
library(arrow)
library(gridExtra)
library(grid)
library(viridis)
library(scales)

# Load modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Test Stage 4: Complete Visualization Pipeline               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Stage 1: Data Validation
# =============================================================================

cat("Stage 1: Loading validated data...\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)
cat(sprintf("✅ %s precursors\n\n", format(nrow(validated_data$data), big.mark = ",")))

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
# Stage 3: Generate optimized windows (single strategy for basic plots)
# =============================================================================

cat("Stage 3: Generating optimized windows (quantile strategy)...\n")
optimized_windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "quantile",
  window_mode = "variable",
  quantile_lower = 0.05,
  quantile_upper = 0.95
)
cat(sprintf("✅ %d windows generated\n\n", nrow(optimized_windows$windows)))

# =============================================================================
# Stage 4: Test Key Visualization Functions
# =============================================================================

output_dir <- "test_plots/stage4_complete/"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Stage 4: Testing Visualization Functions\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# Plot 1: DPPP Comparison
cat("Generating Plot 1: DPPP Distribution Comparison...\n")
plot1 <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)
ggsave(file.path(output_dir, "plot1_dppp_comparison.png"), plot1,
       width = 12, height = 8, dpi = 300, bg = "white")
cat("✅ Plot 1 saved\n\n")

# Plot 2: RT Window Size
cat("Generating Plot 2: RT Window Size Distribution...\n")
plot2 <- plot_rt_window_size(optimized_windows)
ggsave(file.path(output_dir, "plot2_rt_window_size.png"), plot2,
       width = 12, height = 7, dpi = 300, bg = "white")
cat("✅ Plot 2 saved\n\n")

# Plot 2B: RT Histogram (NEW)
cat("Generating Plot 2B: RT Distribution Histogram...\n")
plot2b <- plot_rt_histogram(validated_data, bins = 50)
ggsave(file.path(output_dir, "plot2b_rt_histogram.png"), plot2b,
       width = 12, height = 7, dpi = 300, bg = "white")
cat("✅ Plot 2B saved\n\n")

# Plot 3: RT × m/z Density Heatmap
cat("Generating Plot 3: RT × m/z Density Heatmap...\n")
plot3 <- plot_rt_mz_density_heatmap(validated_data, bins = 50)
ggsave(file.path(output_dir, "plot3_density_heatmap.png"), plot3,
       width = 12, height = 8, dpi = 300, bg = "white")
cat("✅ Plot 3 saved\n\n")

# Plot 5: Density with m/z Range Overlay (NEW)
cat("Generating Plot 5: Density with m/z Range Overlay...\n")
plot5 <- plot_density_with_mz_range(optimized_windows, validated_data, bins = 50)
ggsave(file.path(output_dir, "plot5_density_with_mz_range.png"), plot5,
       width = 12, height = 8, dpi = 300, bg = "white")
cat("✅ Plot 5 saved\n\n")

# Plot 6: Precursor Coverage Map
cat("Generating Plot 6: Precursor Coverage Map...\n")
plot6 <- plot_precursor_coverage_map(optimized_windows, validated_data)
ggsave(file.path(output_dir, "plot6_coverage_map.png"), plot6,
       width = 12, height = 8, dpi = 300, bg = "white")
cat("✅ Plot 6 saved\n\n")

# Plot 7: Window Efficiency
cat("Generating Plot 7: Window Efficiency Analysis...\n")
plot7 <- plot_window_efficiency(optimized_windows)
ggsave(file.path(output_dir, "plot7_window_efficiency.png"), plot7,
       width = 12, height = 7, dpi = 300, bg = "white")
cat("✅ Plot 7 saved\n\n")

# Plot 8: DPPP Achievement Heatmap
cat("Generating Plot 8: DPPP Achievement Heatmap...\n")
plot8 <- plot_dppp_achievement_heatmap(optimization_plan, optimized_windows, validated_data)
ggsave(file.path(output_dir, "plot8_dppp_heatmap.png"), plot8,
       width = 12, height = 8, dpi = 300, bg = "white")
cat("✅ Plot 8 saved\n\n")

# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║           STAGE 4 COMPLETE TEST FINISHED                       ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# List all generated files
all_files <- list.files(output_dir, pattern = "\\.png$", full.names = TRUE)
file_sizes <- sapply(all_files, function(f) file.info(f)$size / 1024)

cat("Generated Files:\n")
cat("─────────────────────────────────────────────────────────────────\n")
for (i in seq_along(all_files)) {
  cat(sprintf("  ✅ %s (%.1f KB)\n", basename(all_files[i]), file_sizes[i]))
}

cat("\n")
cat("Output Directory:\n")
cat(sprintf("  %s\n", output_dir))

cat("\n")
cat("New Plots Added to Stage 4:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("  Plot 2B: RT Distribution Histogram\n")
cat("    - Supplementary to Plot 3 (density heatmap)\n")
cat("    - Shows temporal precursor elution pattern\n")
cat("    - Highlights peak elution region and statistics\n")
cat("\n")
cat("  Plot 5: Density Heatmap with m/z Range Overlay\n")
cat("    - Combines Plot 3 (density) with m/z optimization\n")
cat("    - Green lines show optimized m/z boundaries\n")
cat("    - Visualizes strategy-specific m/z range adjustment\n")
cat("\n")

cat("✅ Stage 4 visualization functions integrated and tested successfully!\n")
cat("\n")
