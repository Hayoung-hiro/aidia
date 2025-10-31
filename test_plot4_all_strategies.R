# test_plot4_all_strategies.R
# Test Plot 4 with all 4 m/z optimization strategies
#
# Strategies:
# 1. Quantile (P5-P95)
# 2. Smoothing (Savitzky-Golay)
# 3. Outlier Removal (±3SD)
# 4. Coverage-based (target 95%)

library(dplyr)
library(ggplot2)
library(tidyr)
library(arrow)
library(gridExtra)
library(grid)

# Load modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/plot4_mz_distribution_excluded.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║      Test Plot 4: All 4 m/z Optimization Strategies           ║\n")
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
# Stage 3 + Plot 4: Test each strategy
# =============================================================================

strategies <- c("quantile", "smoothing", "outlier", "coverage")
strategy_labels <- c(
  "Quantile (P5-P95)",
  "Savitzky-Golay Smoothing",
  "Outlier Removal (±3SD)",
  "Coverage-based (95%)"
)

output_dir <- "test_plots/plot4_strategies/"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

results_summary <- data.frame(
  strategy = character(),
  strategy_label = character(),
  mean_mz_width = numeric(),
  mean_coverage = numeric(),
  file_name = character(),
  file_size_kb = numeric(),
  stringsAsFactors = FALSE
)

for (i in seq_along(strategies)) {
  strategy <- strategies[i]
  label <- strategy_labels[i]

  cat("\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat(sprintf("Testing Strategy %d: %s\n", i, label))
  cat("═══════════════════════════════════════════════════════════════\n\n")

  # Stage 3: Generate optimized windows with this strategy
  cat(sprintf("Running Stage 3 with %s strategy...\n", strategy))

  optimized_windows <- optimize_windows(
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

  cat(sprintf("✅ %d windows generated\n", nrow(optimized_windows$windows)))
  cat(sprintf("   Mean m/z width: %.1f Da\n",
              optimized_windows$mz_optimization$mean_width))
  cat(sprintf("   Mean coverage: %.1f%%\n\n",
              optimized_windows$mz_optimization$mean_coverage * 100))

  # Generate Plot 4 for this strategy
  cat(sprintf("Generating Plot 4 for %s...\n", strategy))

  plot4 <- plot_mz_distribution_with_exclusions(
    optimized_windows = optimized_windows,
    validated_data = validated_data,
    max_bins_to_show = 6
  )

  # Save plot
  output_file <- file.path(output_dir, sprintf("plot4_%s.png", strategy))

  ggsave(
    output_file,
    plot4,
    width = 14,
    height = 10,
    dpi = 300,
    bg = "white"
  )

  file_size <- file.info(output_file)$size / 1024

  cat(sprintf("✅ Saved: %s (%.1f KB)\n", basename(output_file), file_size))

  # Store results
  results_summary <- rbind(results_summary, data.frame(
    strategy = strategy,
    strategy_label = label,
    mean_mz_width = optimized_windows$mz_optimization$mean_width,
    mean_coverage = optimized_windows$mz_optimization$mean_coverage * 100,
    file_name = basename(output_file),
    file_size_kb = file_size,
    stringsAsFactors = FALSE
  ))
}

# =============================================================================
# Summary
# =============================================================================

cat("\n\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                ALL 4 STRATEGIES TEST COMPLETE                  ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Strategy Comparison Summary:\n")
cat("─────────────────────────────────────────────────────────────────\n")
print(results_summary, row.names = FALSE)
cat("\n")

cat("Output Directory:\n")
cat(sprintf("  %s\n", output_dir))
cat("\n")

cat("Generated Files:\n")
for (i in 1:nrow(results_summary)) {
  cat(sprintf("  %d. %s\n", i, results_summary$file_name[i]))
  cat(sprintf("     - Strategy: %s\n", results_summary$strategy_label[i]))
  cat(sprintf("     - Mean m/z width: %.1f Da\n", results_summary$mean_mz_width[i]))
  cat(sprintf("     - Mean coverage: %.1f%%\n", results_summary$mean_coverage[i]))
  cat(sprintf("     - File size: %.1f KB\n", results_summary$file_size_kb[i]))
  cat("\n")
}

cat("Key Insights:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("  • Quantile: Fixed percentile (P5-P95), uniform exclusion\n")
cat("  • Smoothing: RT-dependent boundaries, smooth transitions\n")
cat("  • Outlier: Statistical (±3SD), most conservative\n")
cat("  • Coverage: Target-driven (95%), most aggressive\n")
cat("\n")

cat("✅ All 4 strategies successfully tested!\n")
cat("\n")
