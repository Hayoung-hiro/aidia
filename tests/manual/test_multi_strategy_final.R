# test_multi_strategy_final.R - Final test of multi-strategy plots

library(dplyr)
library(arrow)

# Source files
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

cat("\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  Multi-Strategy Visualization Final Test\n")
cat("═══════════════════════════════════════════════════════════\n\n")

# =============================================================================
# Test: Generate all 4 strategies and visualize
# =============================================================================

# Load data
validated_data <- create_validated_dataset(
  proteome_file = "data/30min_report.parquet",
  enable_replicate_consensus = FALSE
)

# Create plan
plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 3.5,
  target_dppp = 7.0,
  instrument_preset = "astral"
)

# Generate windows for all 4 strategies
cat("\n=== Generating Windows for 4 Strategies ===\n\n")

strategies <- c("quantile", "coverage", "outlier", "smoothing")
windows_list <- list()

for (strategy in strategies) {
  cat(sprintf("--- Strategy: %s ---\n", toupper(strategy)))

  windows_list[[strategy]] <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = plan,
    rt_bin_width_min = 5,
    mz_strategy = strategy,
    window_mode = "variable"
  )

  cat(sprintf("✓ %s: %d windows, %.1f%% coverage\n\n",
              toupper(strategy),
              nrow(windows_list[[strategy]]$windows),
              windows_list[[strategy]]$statistics$coverage_percentage))
}

cat("\n=== Attempting Multi-Strategy Visualization ===\n\n")

# Try to generate plots (this previously failed)
tryCatch({
  viz <- generate_visualizations(
    validated_data = validated_data,
    optimization_plan = plan,
    optimized_windows = windows_list[["quantile"]],  # Use quantile as primary
    windows_list = windows_list,  # Provide all 4 strategies
    output_dir = "output/test_multi_strategy",
    create_individual_plots = FALSE  # Don't save individual plots
  )

  cat("✅ SUCCESS: Multi-strategy visualization completed!\n")
  cat(sprintf("   Generated %d plots\n", length(viz$plots)))
  cat("   Plot names:\n")
  for (plot_name in names(viz$plots)) {
    cat(sprintf("     - %s\n", plot_name))
  }

}, error = function(e) {
  cat("❌ ERROR: Multi-strategy visualization failed\n")
  cat(sprintf("   Error message: %s\n", e$message))
  cat("\n")
  traceback()
})

cat("\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  Test Complete\n")
cat("═══════════════════════════════════════════════════════════\n")
