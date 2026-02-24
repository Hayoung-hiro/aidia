# test_plot5_density_overlay.R
# Test Plot 5: RT × m/z Density Heatmap with Optimized m/z Range Overlay
#
# Purpose: Generate 2×2 grid showing density heatmap with m/z range boundaries
#          for all 4 optimization strategies

library(dplyr)
library(ggplot2)
library(tidyr)
library(arrow)
library(gridExtra)
library(grid)
library(viridis)

# Load modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/plot_density_overlay.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Test Plot 5: Density Heatmap with m/z Range Overlay         ║\n")
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

for (strategy in strategies) {
  cat(sprintf("\nGenerating optimized windows with %s strategy...\n", strategy))

  windows_list[[strategy]] <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    rt_bin_width_min = 5,
    mz_strategy = strategy,
    window_mode = "variable",
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
# Plot 5: Density heatmap with m/z range overlay (2×2 grid)
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Generating Plot 5: Density Heatmap with m/z Range Overlay\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Creating 2×2 grid plot with all 4 strategies...\n")

plot5 <- plot_density_with_mz_ranges_grid(
  windows_list = windows_list,
  validated_data = validated_data,
  bins = 50
)

output_dir <- "test_plots/"
output_file <- file.path(output_dir, "plot5_density_mz_ranges_grid.png")

ggsave(
  output_file,
  plot5,
  width = 14,
  height = 12,
  dpi = 300,
  bg = "white"
)

file_size <- file.info(output_file)$size / 1024
cat(sprintf("✅ Saved: %s (%.1f KB)\n\n", basename(output_file), file_size))

# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║           PLOT 5 TEST COMPLETE                                 ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Generated File:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat(sprintf("  ✅ plot5_density_mz_ranges_grid.png (%.1f KB)\n", file_size))

cat("\n")
cat("Output Directory:\n")
cat(sprintf("  %s\n", output_dir))

cat("\n")
cat("Plot Description:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("  Plot 5: 2×2 grid of density heatmaps with m/z range overlay\n")
cat("    - Background: Precursor density heatmap (plasma colormap)\n")
cat("    - Green lines: Optimized m/z boundaries (upper & lower)\n")
cat("    - Layout: Quantile (top-left) | Smoothing (top-right)\n")
cat("              Outlier (bottom-left) | Coverage (bottom-right)\n")
cat("    - Shows: How each strategy adjusts m/z range across RT\n")
cat("\n")

cat("✅ Plot 5 generated successfully!\n")
cat("\n")
