# test_phase1_plots_90min.R
# Test Phase 1 Core Plots (Plots 1, 2, 3, 8) with 90min dataset
#
# Purpose: Verify Stage 4 Phase 1 implementation (core plots)
# Dataset: data/90min_report.parquet (FWHM ~8.9 sec, 80,763 precursors)
#
# Expected Outputs:
#   - Plot 1a: Simple DPPP comparison
#   - Plot 1b: Enhanced DPPP comparison with annotations
#   - Plot 2: RT × m/z density heatmap
#   - Plot 3: m/z density overlay (RT segments)
#   - Plot 8: DPPP achievement heatmap (FIXED window_id parsing)

library(dplyr)
library(ggplot2)
library(arrow)
library(tibble)
library(viridis)
library(scales)

# Load modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/visualization.R")

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║     Test Phase 1 Core Plots (90min Dataset)                  ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")
cat("\n")

# =============================================================================
# Stage 1: Data Validation
# =============================================================================

cat("Stage 1: Data Validation\n")
cat("─────────────────────────────────────────────────────────────\n")

validated_data <- create_validated_dataset(
  input_file = "data/90min_report.parquet",
  proteome_file = "",  # Not using proteome filtering
  file_type = "parquet",
  use_quality_filter = TRUE,
  extract_raw_metadata = FALSE
)

cat(sprintf("✅ %s precursors validated\n\n",
            format(nrow(validated_data$data), big.mark = ",")))

# =============================================================================
# Stage 2: Optimization Planning
# =============================================================================

cat("Stage 2: Optimization Planning\n")
cat("─────────────────────────────────────────────────────────────\n")

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,
  target_satisfaction = 0.70,
  target_dppp = 7.0,
  instrument_preset = "fusion_lumos"
)

cat(sprintf("✅ Required cycle time: %.2f sec, Window count: %d\n\n",
            optimization_plan$required_cycle_time_sec,
            optimization_plan$n_windows))

# =============================================================================
# Stage 3: Window Optimization
# =============================================================================

cat("Stage 3: Window Optimization\n")
cat("─────────────────────────────────────────────────────────────\n")

optimized_windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "quantile",
  window_mode = "variable",
  quantile_lower = 0.05,
  quantile_upper = 0.95
)

cat(sprintf("✅ %d windows generated across %d RT segments\n\n",
            nrow(optimized_windows$windows),
            length(unique(optimized_windows$windows$rt_segment_id))))

# =============================================================================
# Phase 1 Plot Generation
# =============================================================================

cat("Phase 1: Core Plot Generation\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# Create output directory
output_dir <- "test_plots/phase1/"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Track generation time
plot_start <- Sys.time()

# -----------------------------------------------------------------------------
# Plot 1a: Simple DPPP Comparison
# -----------------------------------------------------------------------------

cat("1. Plot 1a: DPPP Comparison (Simple Version)\n")
plot1a <- plot_dppp_comparison(optimization_plan, validated_data)

ggsave(
  file.path(output_dir, "plot1a_dppp_simple.png"),
  plot1a,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size_1a <- file.info(file.path(output_dir, "plot1a_dppp_simple.png"))$size / 1024
cat(sprintf("   ✅ Saved: plot1a_dppp_simple.png (%.1f KB)\n\n", file_size_1a))

# -----------------------------------------------------------------------------
# Plot 1b: Enhanced DPPP Comparison
# -----------------------------------------------------------------------------

cat("2. Plot 1b: DPPP Comparison (Enhanced Version)\n")
plot1b <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)

ggsave(
  file.path(output_dir, "plot1b_dppp_enhanced.png"),
  plot1b,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size_1b <- file.info(file.path(output_dir, "plot1b_dppp_enhanced.png"))$size / 1024
cat(sprintf("   ✅ Saved: plot1b_dppp_enhanced.png (%.1f KB)\n\n", file_size_1b))

# -----------------------------------------------------------------------------
# Plot 2: RT × m/z Density Heatmap
# -----------------------------------------------------------------------------

cat("3. Plot 2: RT × m/z Density Heatmap\n")
plot2 <- plot_rt_mz_density_heatmap(validated_data)

ggsave(
  file.path(output_dir, "plot2_rt_mz_heatmap.png"),
  plot2,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size_2 <- file.info(file.path(output_dir, "plot2_rt_mz_heatmap.png"))$size / 1024
cat(sprintf("   ✅ Saved: plot2_rt_mz_heatmap.png (%.1f KB)\n\n", file_size_2))

# -----------------------------------------------------------------------------
# Plot 3: m/z Density Overlay
# -----------------------------------------------------------------------------

cat("4. Plot 3: m/z Density Overlay (RT Segments)\n")
plot3 <- plot_mz_normalized_density(optimized_windows, validated_data)

ggsave(
  file.path(output_dir, "plot3_mz_density_overlay.png"),
  plot3,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size_3 <- file.info(file.path(output_dir, "plot3_mz_density_overlay.png"))$size / 1024
cat(sprintf("   ✅ Saved: plot3_mz_density_overlay.png (%.1f KB)\n\n", file_size_3))

# -----------------------------------------------------------------------------
# Plot 8: DPPP Achievement Heatmap (FIXED)
# -----------------------------------------------------------------------------

cat("5. Plot 8: DPPP Achievement Heatmap (FIXED window_id parsing)\n")
plot8 <- plot_dppp_achievement_heatmap(
  optimization_plan, optimized_windows, validated_data
)

ggsave(
  file.path(output_dir, "plot8_dppp_achievement_fixed.png"),
  plot8,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size_8 <- file.info(file.path(output_dir, "plot8_dppp_achievement_fixed.png"))$size / 1024
cat(sprintf("   ✅ Saved: plot8_dppp_achievement_fixed.png (%.1f KB)\n\n", file_size_8))

# =============================================================================
# Summary
# =============================================================================

plot_end <- Sys.time()
total_time <- as.numeric(difftime(plot_end, plot_start, units = "secs"))

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    PHASE 1 TEST COMPLETE                       ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")
cat("\n")

cat("Generated Plots:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat(sprintf("  📊 plot1a_dppp_simple.png           (%.1f KB)\n", file_size_1a))
cat(sprintf("  📊 plot1b_dppp_enhanced.png         (%.1f KB)\n", file_size_1b))
cat(sprintf("  📊 plot2_rt_mz_heatmap.png          (%.1f KB)\n", file_size_2))
cat(sprintf("  📊 plot3_mz_density_overlay.png     (%.1f KB)\n", file_size_3))
cat(sprintf("  📊 plot8_dppp_achievement_fixed.png (%.1f KB)\n", file_size_8))
cat("\n")

cat("Phase 1 Plot Details:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("  ✅ Plot 1: DPPP Comparison (Simple + Enhanced)\n")
cat("     - Dual density curves\n")
cat("     - Target DPPP reference line\n")
cat("     - Enhanced: Green zone, median lines, shift arrow\n")
cat("\n")
cat("  ✅ Plot 2: RT × m/z Density Heatmap\n")
cat("     - 2D density visualization\n")
cat("     - Shows precursor concentration\n")
cat("\n")
cat("  ✅ Plot 3: m/z Density Overlay\n")
cat("     - Multiple RT segments overlaid\n")
cat("     - Normalized density profiles\n")
cat("     - User feedback: 'overlay가 더 명확해보여'\n")
cat("\n")
cat("  ✅ Plot 8: DPPP Achievement Heatmap\n")
cat("     - FIXED: window_id parsing bug resolved\n")
cat("     - Uses window_index instead of parsed window_id\n")
cat("     - Shows DPPP achievement per window\n")
cat("\n")

cat("Stage 4 Phase 1 Status:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("  ✅ Plot 1: DPPP Comparison - COMPLETE\n")
cat("  ✅ Plot 2: RT × m/z Heatmap - REUSED (no changes needed)\n")
cat("  ✅ Plot 3: m/z Density Overlay - ALREADY IMPLEMENTED\n")
cat("  ✅ Plot 8: DPPP Achievement - FIXED (window_id bug)\n")
cat("\n")

cat(sprintf("Total generation time: %.2f seconds\n", total_time))
cat(sprintf("Output directory: %s\n", output_dir))
cat("\n")

cat("✅ Phase 1 (Core Plots) Implementation Complete!\n")
cat("\n")
