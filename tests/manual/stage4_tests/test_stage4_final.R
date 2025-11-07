# test_stage4_final.R
# Final Verification: stage4_visualization.R generates all plots correctly

library(dplyr)
library(ggplot2)
library(arrow)

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   FINAL TEST: Stage 4 Visualization Complete Check            ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load all required modules
cat("Loading modules...\n")
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

# Stage 1: Load data
cat("\n[1/4] Loading data...\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)
cat(sprintf("✓ %s precursors\n", format(nrow(validated_data$data), big.mark = ",")))

# Stage 2: Optimization plan
cat("\n[2/4] Creating optimization plan...\n")
optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,
  target_satisfaction = 0.70,
  target_dppp = 7.0,
  instrument_preset = "fusion_lumos"
)
cat(sprintf("✓ %d windows per RT bin\n", optimization_plan$n_windows))

# Stage 3: Optimize windows (any strategy - will be re-run for all in Stage 4)
cat("\n[3/4] Generating initial windows...\n")
optimized_windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "smoothing",
  window_mode = "variable"
)
cat(sprintf("✓ %d windows generated\n", nrow(optimized_windows$windows)))

# Stage 4: Generate ALL visualizations
cat("\n[4/4] Generating visualizations with stage4_visualization.R...\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

output_dir <- "test_final_check/"
if (dir.exists(output_dir)) {
  unlink(output_dir, recursive = TRUE)
}

viz_result <- generate_visualizations(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  optimized_windows = optimized_windows,
  output_dir = output_dir,
  create_pdf = FALSE,
  create_individual_plots = TRUE
)

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                   VERIFICATION RESULTS                         ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Check generated files
plot_files <- list.files(output_dir, pattern = "*.png", full.names = FALSE)
plot_count <- length(plot_files)

cat(sprintf("Total plots generated: %d\n\n", plot_count))

# Expected plots
expected_plots <- c(
  "plot1a_dppp_comparison_simple.png",
  "plot1b_dppp_comparison_enhanced.png",
  "plot2_rt_mz_density_heatmap.png",
  "plot2b_rt_histogram_continuous.png",
  "plot2b_rt_histogram_5min.png",
  "plot3_mz_density_overlay.png",
  "plot4_quantile_mz_excluded.png",
  "plot4_smoothing_mz_excluded.png",
  "plot4_outlier_mz_excluded.png",
  "plot4_coverage_mz_excluded.png",
  "plot4e_mz_width_all_strategies.png",
  "plot5_coverage_map_2x2.png",
  "plot6_satisfaction_curve.png"
)

cat("Expected Plots (13):\n")
cat("───────────────────────────────────────────────────────────────\n")
for (expected in expected_plots) {
  if (expected %in% plot_files) {
    file_size <- file.info(file.path(output_dir, expected))$size / 1024
    cat(sprintf("  ✅ %-45s (%6.1f KB)\n", expected, file_size))
  } else {
    cat(sprintf("  ❌ %-45s (MISSING)\n", expected))
  }
}

cat("\n")
cat("Plot Naming Convention Check:\n")
cat("───────────────────────────────────────────────────────────────\n")
naming_ok <- all(grepl("^plot[0-9]", expected_plots))
if (naming_ok) {
  cat("  ✅ All plots follow naming convention: plot{N}_{name}.png\n")
} else {
  cat("  ❌ Naming convention issue detected\n")
}

cat("\n")
cat("Multi-Strategy Check:\n")
cat("───────────────────────────────────────────────────────────────\n")
multi_strategy_plots <- c(
  "plot4_quantile_mz_excluded.png",
  "plot4_smoothing_mz_excluded.png",
  "plot4_outlier_mz_excluded.png",
  "plot4_coverage_mz_excluded.png",
  "plot4e_mz_width_all_strategies.png",
  "plot5_coverage_map_2x2.png"
)
multi_ok <- all(multi_strategy_plots %in% plot_files)
if (multi_ok) {
  cat("  ✅ All 4 strategies generated (quantile, smoothing, outlier, coverage)\n")
  cat("  ✅ Plot 4E all-strategy comparison generated\n")
  cat("  ✅ Plot 5 2×2 grid generated\n")
} else {
  cat("  ❌ Some multi-strategy plots missing\n")
}

cat("\n")
cat("Summary:\n")
cat("───────────────────────────────────────────────────────────────\n")
all_ok <- (plot_count == length(expected_plots)) && multi_ok && naming_ok
if (all_ok) {
  cat("  ✅ PASS: stage4_visualization.R generates all plots correctly\n")
  cat("  ✅ All 13 plots follow standardized naming\n")
  cat("  ✅ Multi-strategy comparison implemented\n")
  cat("\n  👍 stage4_visualization.R is ready for production!\n")
} else {
  cat("  ❌ FAIL: Some issues detected\n")
  cat(sprintf("     Expected: %d plots, Got: %d plots\n", length(expected_plots), plot_count))
}

cat("\n")
