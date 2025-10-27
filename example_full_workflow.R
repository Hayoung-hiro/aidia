# =============================================================================
# Example: Full 4-Stage Workflow Usage
# =============================================================================
# This script demonstrates different ways to use the full pipeline
# =============================================================================

library(arrow)
library(dplyr)

source("run_full_pipeline.R")

# =============================================================================
# Example 1: Basic Usage (Default Settings)
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Example 1: Basic Usage with Default Settings                ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

result_basic <- run_full_pipeline(
  input_file = "data/30min_report_01.parquet",
  instrument_type = "astral",
  output_dir = "results_example1_basic"
)

# Access stage results
cat("\nAccessing stage results:\n")
cat(sprintf("  Stage 1: %d precursors\n", nrow(result_basic$stage1$data)))
cat(sprintf("  Stage 2: %.1f%% satisfaction\n",
            result_basic$stage2$current_state$satisfaction_ratio * 100))
cat(sprintf("  Stage 3D: %d windows\n", nrow(result_basic$stage3d$windows)))

# =============================================================================
# Example 2: Custom Configuration
# =============================================================================

cat("\n\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Example 2: Custom Configuration                              ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

result_custom <- run_full_pipeline(
  input_file = "data/60min_report_01.parquet",
  instrument_type = "exploris",
  target_dppp = 7.0,
  target_satisfaction = 0.90,  # Higher satisfaction target
  rt_binning_mode = "time_unit",
  rt_time_unit = 10.0,  # 10-minute RT bins
  mz_strategy = "outlier",  # Use outlier strategy
  window_mode = "fixed",  # Fixed-width windows
  output_dir = "results_example2_custom"
)

# =============================================================================
# Example 3: Time Breaks Mode for RT Binning
# =============================================================================

cat("\n\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Example 3: Custom RT Breakpoints                             ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

result_breaks <- run_full_pipeline(
  input_file = "data/90min_report_01.parquet",
  instrument_type = "astral",
  rt_binning_mode = "time_breaks",
  rt_time_breaks = c(0, 20, 40, 60, 80),  # Custom breakpoints
  mz_strategy = "smoothing",
  window_mode = "variable",
  output_dir = "results_example3_breaks"
)

# =============================================================================
# Example 4: Processing Multiple Files
# =============================================================================

cat("\n\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Example 4: Batch Processing Multiple Files                   ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

# Find all parquet files
parquet_files <- list.files("data", pattern = "30min.*\\.parquet$", full.names = TRUE)

cat(sprintf("Found %d files to process\n\n", length(parquet_files)))

results_batch <- lapply(parquet_files, function(file) {

  cat(sprintf("Processing: %s\n", basename(file)))

  # Extract replicate number from filename
  replicate <- gsub(".*_(\\d+)\\.parquet", "\\1", basename(file))

  # Run pipeline
  result <- run_full_pipeline(
    input_file = file,
    instrument_type = "astral",
    mz_strategy = "smoothing",
    window_mode = "variable",
    output_dir = sprintf("results_example4_rep%s", replicate)
  )

  cat(sprintf("  ✓ Complete: %d windows generated\n\n",
              nrow(result$stage3d$windows)))

  return(result)
})

# =============================================================================
# Example 5: Strategy Comparison
# =============================================================================

cat("\n\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Example 5: Compare Different m/z Strategies                  ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

strategies <- c("quantile", "smoothing", "outlier", "coverage")
modes <- c("fixed", "variable")

comparison_results <- expand.grid(
  strategy = strategies,
  mode = modes,
  stringsAsFactors = FALSE
)

cat(sprintf("Running %d combinations...\n\n", nrow(comparison_results)))

for (i in 1:nrow(comparison_results)) {

  strat <- comparison_results$strategy[i]
  mod <- comparison_results$mode[i]

  cat(sprintf("[%d/%d] Strategy: %s, Mode: %s\n",
              i, nrow(comparison_results), strat, mod))

  result <- run_full_pipeline(
    input_file = "data/30min_report_01.parquet",
    instrument_type = "astral",
    mz_strategy = strat,
    window_mode = mod,
    output_dir = sprintf("results_example5_%s_%s", strat, mod)
  )

  comparison_results$n_windows[i] <- nrow(result$stage3d$windows)
  comparison_results$mean_width[i] <- result$stage3d$statistics$mean_width
  comparison_results$coverage[i] <- result$stage3d$coverage_analysis$coverage_ratio

  cat(sprintf("  Windows: %d, Width: %.1f Da, Coverage: %.1f%%\n\n",
              comparison_results$n_windows[i],
              comparison_results$mean_width[i],
              comparison_results$coverage[i] * 100))
}

# Save comparison results
write.csv(comparison_results,
          "results_example5_comparison_summary.csv",
          row.names = FALSE)

cat("\n✅ All examples completed!\n")
cat("   Comparison summary saved to: results_example5_comparison_summary.csv\n")

# =============================================================================
# Print Comparison Table
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Strategy Comparison Summary                                  ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

comparison_results <- comparison_results %>%
  mutate(
    coverage_pct = sprintf("%.1f%%", coverage * 100),
    mean_width = sprintf("%.1f", mean_width)
  ) %>%
  select(strategy, mode, n_windows, mean_width, coverage_pct)

print(comparison_results)
