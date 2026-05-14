# test_plot4_width_comparison.R
# Test Plot 4B & 4C: m/z Width Comparison Bar Charts
#
# Plot 4B: Individual strategy comparison (Original vs Optimized)
# Plot 4C: 2x2 grid of all 4 strategies

library(dplyr)
library(ggplot2)
library(tidyr)
library(arrow)
library(gridExtra)
library(grid)

# Load modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/plot_mz_width.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Test Plot 4B & 4C: m/z Width Comparison (Bar Charts)        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Stage 1: Data Validation (once)
# =============================================================================

cat("Stage 1: Loading validated data...\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)
cat(sprintf("✅ %s precursors\n\n", format(nrow(validated_data$data), big.mark = ",")))

# =============================================================================
# Stage 2: Optimization Planning (once)
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
# Stage 3: Generate optimized windows for all 4 strategies
# =============================================================================

strategies <- c("quantile", "smoothing", "outlier", "coverage")
windows_list <- list()

output_dir_b <- "test_plots/plot4b_width_bars/"
dir.create(output_dir_b, showWarnings = FALSE, recursive = TRUE)

for (strategy in strategies) {
  cat(sprintf("\nGenerating optimized windows with %s strategy...\n", strategy))

  windows_list[[strategy]] <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    rt_bin_width_min = 5,
    mz_strategy = strategy,
    window_mode = "density",
    quantile_lower = 0.05,
    quantile_upper = 0.95,
    outlier_threshold = 3.0,
    smoothing_window = 7,
    polynomial_order = 3,
    target_coverage = 0.95
  )

  cat(sprintf("✅ %s: Mean m/z width = %.1f Da, Coverage = %.1f%%\n",
              strategy,
              windows_list[[strategy]]$mz_optimization$mean_width,
              windows_list[[strategy]]$mz_optimization$mean_coverage * 100))
}

# =============================================================================
# Plot 4B: Individual strategy bar charts
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Generating Plot 4B: Individual Strategy Bar Charts\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

for (strategy in strategies) {
  cat(sprintf("Creating Plot 4B for %s...\n", strategy))

  plot4b <- plot_mz_width_comparison(
    optimized_windows = windows_list[[strategy]],
    validated_data = validated_data
  )

  output_file <- file.path(output_dir_b, sprintf("plot4b_width_%s.png", strategy))

  ggsave(
    output_file,
    plot4b,
    width = 12,
    height = 7,
    dpi = 300,
    bg = "white"
  )

  file_size <- file.info(output_file)$size / 1024
  cat(sprintf("✅ Saved: %s (%.1f KB)\n\n", basename(output_file), file_size))
}

# =============================================================================
# Plot 4C: All Strategies Overlay (Grouped Bar Chart)
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Generating Plot 4C: All Strategies Overlay (Grouped Bar Chart)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Creating grouped bar chart with all strategies...\n")

plot4c <- plot_mz_width_comparison_all_strategies(
  windows_list = windows_list,
  validated_data = validated_data
)

output_dir_c <- "test_plots/"
output_file_c <- file.path(output_dir_c, "plot4c_width_comparison_all_strategies.png")

ggsave(
  output_file_c,
  plot4c,
  width = 12,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size_c <- file.info(output_file_c)$size / 1024
cat(sprintf("✅ Saved: %s (%.1f KB)\n\n", basename(output_file_c), file_size_c))

# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║           PLOT 4B & 4C TEST COMPLETE                           ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Generated Files:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("\nPlot 4B (Individual Strategy Bar Charts):\n")
for (strategy in strategies) {
  filename <- sprintf("plot4b_width_%s.png", strategy)
  filepath <- file.path(output_dir_b, filename)
  if (file.exists(filepath)) {
    size <- file.info(filepath)$size / 1024
    cat(sprintf("  ✅ %s (%.1f KB)\n", filename, size))
  }
}

cat("\nPlot 4C (All Strategies Grouped Bar Chart):\n")
cat(sprintf("  ✅ plot4c_width_comparison_all_strategies.png (%.1f KB)\n", file_size_c))

cat("\n")
cat("Output Directories:\n")
cat(sprintf("  Plot 4B: %s\n", output_dir_b))
cat(sprintf("  Plot 4C: %s\n", output_dir_c))

cat("\n")
cat("Plot Descriptions:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("  Plot 4B: Side-by-side bar chart per strategy\n")
cat("    - Gray bars: Original m/z width\n")
cat("    - Colored bars: Optimized m/z width\n")
cat("    - Labels: Coverage % on top of optimized bars\n")
cat("    - Shows: RT-dependent width reduction patterns\n")
cat("\n")
cat("  Plot 4C: Grouped bar chart with all strategies overlay\n")
cat("    - Gray: Original | Blue: Quantile | Green: Smoothing\n")
cat("    - Orange: Outlier | Purple: Coverage\n")
cat("    - Shows: All 5 bars (Original + 4 strategies) per RT segment\n")
cat("    - Subtitle: Mean widths for all strategies\n")
cat("\n")

cat("✅ All m/z width comparison plots generated successfully!\n")
cat("\n")
