# Publication Figures with 16:9 Aspect Ratio (Corrected - Using Original Functions)
# - Figure 1: DPPP comparison WITHOUT legend
# - Figure 2: Skip (already OK)
# - Figure 3: plot3 (mz_normalized_density) + plot4 (greedy excluded) in 1×2 layout
# - Figure 4: plot7 (greedy window_width_distribution) with adjusted density width scale

library(ggplot2)
library(dplyr)
library(gridExtra)
library(grid)

source("R/utils_common.R")
source("R/instrument_utils.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/visualization.R")
source("R/plot_mz_excluded.R")
source("R/plot_window_width.R")

OUTPUT_DIR <- "publication_ready"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║     Publication Figures (Corrected - Original Functions)      ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Data Loading
# =============================================================================

cat("Loading data...\n")

validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,
  instrument_preset = "fusion_lumos",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)

# Generate greedy strategy windows
windows_greedy <- optimize_windows(
  validated_data, optimization_plan,
  rt_bin_width_min = 5, mz_strategy = "greedy", window_mode = "density",
  smoothing_window = 3, polynomial_order = 2
)

# =============================================================================
# Figure 1: DPPP Comparison (16:9, NO LEGEND)
# =============================================================================

cat("\n=== Figure 1: DPPP Comparison (NO LEGEND) ===\n")

plot1b <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)

# Remove legend completely
plot1b_pub <- plot1b +
  theme(legend.position = "none")

ggsave(
  filename = file.path(OUTPUT_DIR, "Figure1_DPPP_comparison.png"),
  plot = plot1b_pub,
  width = 16,
  height = 9,
  dpi = 300,
  bg = "white"
)

cat("✅ Figure1_DPPP_comparison.png (16:9 ratio, legend removed)\n")

# =============================================================================
# Figure 3: plot3 + plot4 in 1×2 Grid (16:9)
# Using ORIGINAL stage4 functions
# =============================================================================

cat("\n=== Figure 3: plot3 (mz_normalized_density) + plot4 (greedy excluded) ===\n")

# Plot 3: m/z Normalized Density (original function from visualization.R)
plot3_original <- plot_mz_normalized_density(windows_greedy, validated_data)

# Plot 4: m/z Distribution with Excluded Regions (greedy strategy, 6 bins)
# Original function from plot_mz_excluded.R
plot4_original <- plot_mz_distribution_with_exclusions(
  windows_greedy, validated_data, max_bins_to_show = 6
)

# Combine in 1×2 layout (side by side)
# Note: plot4_original is a grob (arrangeGrob output), plot3_original is ggplot
fig3_combined <- grid.arrange(
  plot3_original,
  plot4_original,
  ncol = 2,
  widths = c(1, 1)
)

ggsave(
  file.path(OUTPUT_DIR, "Figure3_mz_optimization.png"),
  fig3_combined,
  width = 16,
  height = 9,
  dpi = 300,
  bg = "white"
)

cat("✅ Figure3_mz_optimization.png (16:9 ratio, 1×2 grid: plot3 + plot4 greedy)\n")

# =============================================================================
# Figure 4: plot7 Window Width Distribution (16:9, adjusted variable width scale)
# Using ORIGINAL plot7_window_width_distribution function
# =============================================================================

cat("\n=== Figure 4: plot7 Window Width Distribution (Smoothing Strategy) ===\n")

# Original function from plot_window_width.R
# This already has dual y-axis with:
# - Left: Normalized Density (0-1)
# - Right: Window Width (Da)
# The scaling is done internally via scaling_factor

plot7_original <- plot_window_width_distribution(
  windows_greedy, validated_data, max_segments_to_show = 6
)

# Save directly (it's already a grid object with 6 panels)
ggsave(
  file.path(OUTPUT_DIR, "Figure4_window_width.png"),
  plot7_original,
  width = 16,
  height = 9,
  dpi = 300,
  bg = "white"
)

cat("✅ Figure4_window_width.png (16:9 ratio, original plot7 with dual y-axis)\n")

# =============================================================================
# Summary
# =============================================================================

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║       All Publication Figures Complete (Corrected)            ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Output files in publication_ready/:\n")
cat("  ├── Figure1_DPPP_comparison.png (16:9, legend removed)\n")
cat("  ├── Figure2_coverage_map.png (16:9, skipped - already OK)\n")
cat("  ├── Figure3_mz_optimization.png (16:9, 1×2: plot3 + plot4 greedy)\n")
cat("  └── Figure4_window_width.png (16:9, plot7 greedy with dual y-axis)\n\n")

cat("All figures use ORIGINAL functions from:\n")
cat("  - visualization.R: plot_dppp_comparison_enhanced(), plot_mz_normalized_density()\n")
cat("  - plot_mz_excluded.R: plot_mz_distribution_with_exclusions()\n")
cat("  - plot_window_width.R: plot_window_width_distribution()\n\n")

cat("All figures generated at 300 dpi, 16:9 ratio for publication quality.\n")
