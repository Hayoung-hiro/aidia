# test_plot8_strategy_comparison.R
# Test Plot 8: 4-Strategy Window Width Comparison
#
# Purpose: Test ridge, box, and CDF comparison plots

library(dplyr)
library(ggplot2)
library(tidyr)
library(arrow)
library(gridExtra)
library(grid)
library(ggridges)

# Load modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/plot_strategy_comparison.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Test Plot 8: 4-Strategy Window Width Comparison             ║\n")
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
# Stage 3: Generate optimized windows (all 4 strategies)
# =============================================================================

cat("Stage 3: Generating optimized windows for all 4 strategies...\n")

strategies <- c("quantile", "smoothing", "outlier", "coverage")
windows_list <- list()

for (strategy in strategies) {
  cat(sprintf("  Generating windows for %s strategy...\n", toupper(strategy)))

  windows_list[[strategy]] <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    rt_bin_width_min = 5,
    mz_strategy = strategy,
    window_mode = "variable",
    quantile_lower = 0.05,
    quantile_upper = 0.95
  )
}

cat(sprintf("✅ All 4 strategies completed\n\n"))

# =============================================================================
# Plot 8: Strategy Width Comparison
# =============================================================================

output_dir <- "test_plots/"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat("═══════════════════════════════════════════════════════════════\n")
cat("Generating Plot 8: Strategy Width Comparison\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# Plot 8A: Ridge Plot
cat("Generating Plot 8A: Ridge Plot...\n")
plot8a <- plot_strategy_width_ridge(windows_list, validated_data)
ggsave(
  file.path(output_dir, "plot8a_strategy_width_ridge.png"),
  plot8a,
  width = 10,
  height = 8,
  dpi = 300,
  bg = "white"
)
cat("✅ Plot 8A saved\n\n")

# Plot 8B: Box Plot
cat("Generating Plot 8B: Box Plot...\n")
plot8b <- plot_strategy_width_boxplot(windows_list, validated_data)
ggsave(
  file.path(output_dir, "plot8b_strategy_width_boxplot.png"),
  plot8b,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)
cat("✅ Plot 8B saved\n\n")

# Plot 8C: CDF Plot
cat("Generating Plot 8C: CDF Plot...\n")
plot8c <- plot_strategy_width_cdf(windows_list, validated_data)
ggsave(
  file.path(output_dir, "plot8c_strategy_width_cdf.png"),
  plot8c,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)
cat("✅ Plot 8C saved\n\n")

# Plot 8: Combined 3-panel
cat("Generating Plot 8 Combined: 3-panel comparison...\n")
plot8_combined <- plot_strategy_width_comparison_combined(windows_list, validated_data)
ggsave(
  file.path(output_dir, "plot8_combined_strategy_comparison.png"),
  plot8_combined,
  width = 10,
  height = 15,
  dpi = 300,
  bg = "white"
)
cat("✅ Plot 8 Combined saved\n\n")

# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║           PLOT 8 TEST COMPLETE                                 ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Generated Files:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("  ✅ plot8a_strategy_width_ridge.png\n")
cat("  ✅ plot8b_strategy_width_boxplot.png\n")
cat("  ✅ plot8c_strategy_width_cdf.png\n")
cat("  ✅ plot8_combined_strategy_comparison.png\n")

cat("\n")
cat("Output Directory:\n")
cat(sprintf("  %s\n", output_dir))

cat("\n")
cat("Plot Descriptions:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("  Plot 8A (Ridge): Overlapping density curves\n")
cat("    - Shows distribution shape for each strategy\n")
cat("    - Uses ggridges for professional ridge plot\n")
cat("    - Median lines shown within each distribution\n")
cat("\n")
cat("  Plot 8B (Box): Statistical summaries\n")
cat("    - Median (horizontal line in box)\n")
cat("    - Mean (white diamond)\n")
cat("    - Quartiles (box boundaries)\n")
cat("    - Outliers (individual points)\n")
cat("\n")
cat("  Plot 8C (CDF): Cumulative distribution function\n")
cat("    - X-axis: Window width (Da)\n")
cat("    - Y-axis: Cumulative probability (0-100%)\n")
cat("    - Dashed lines: Median width per strategy\n")
cat("    - Steeper slope = narrower distribution\n")
cat("\n")
cat("  Plot 8 Combined: All 3 plots in vertical layout\n")
cat("    - Comprehensive comparison view\n")
cat("    - Ideal for presentations and reports\n")
cat("\n")

cat("✅ All strategy comparison plots generated successfully!\n")
cat("\n")
