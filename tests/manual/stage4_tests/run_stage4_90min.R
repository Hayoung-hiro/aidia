# =============================================================================
# Run Stage 4 Visualization for 90min Gradient
# =============================================================================
# Generates all 24 plots for 90min gradient dataset

library(arrow)
library(dplyr)

# Source all required modules
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/visualization.R")
source("R/utils_common.R")

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║        Stage 4 Visualization - 90min Gradient                 ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Stage 1: Load and Validate Data
# =============================================================================

cat("Stage 1: Data Validation\n")
cat("─────────────────────────────────────────────────────────────\n")

validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)

cat(sprintf("✅ Loaded %s precursors\n\n", format(nrow(validated_data$data), big.mark = ",")))

# =============================================================================
# Stage 2: Optimization Planning
# =============================================================================

cat("Stage 2: Optimization Planning\n")
cat("─────────────────────────────────────────────────────────────\n")

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,  # User-specified
  instrument_preset = "fusion_lumos",
  target_dppp = 7.0,
  target_satisfaction = 0.70,
  dppp_tolerance = 0.0,
  load_factor = 0.8,
  ms1_scans_per_cycle = NULL,
  warning_threshold_windows = 5
)

cat(sprintf("✅ Required cycle time: %.3f sec\n", optimization_plan$required_cycle_time_sec))
cat(sprintf("   Windows per RT bin: %d\n\n", optimization_plan$window_count_per_bin))

# =============================================================================
# Stage 3: Window Optimization (All 8 Combinations)
# =============================================================================

cat("Stage 3: Window Optimization\n")
cat("─────────────────────────────────────────────────────────────\n")

strategies <- c("quantile", "smoothing", "outlier", "coverage")
modes <- c("fixed", "variable")

all_results <- list()
combo_id <- 0

for (strategy in strategies) {
  for (mode in modes) {
    combo_id <- combo_id + 1
    cat(sprintf("[%d/8] Strategy: %s, Mode: %s\n", combo_id, strategy, mode))

    result <- optimize_windows(
      validated_data = validated_data,
      optimization_plan = optimization_plan,
      rt_bin_width_min = 5.0,
      mz_strategy = strategy,
      window_mode = mode,
      quantile_lower = 0.05,
      quantile_upper = 0.95,
      target_coverage = 0.95,
      outlier_threshold = 3.0,
      smoothing_window = 3,
      polynomial_order = 2,
      min_width_da = 2,
      max_width_da = 80,
      overlap_percentage = 0
    )

    all_results[[paste(strategy, mode, sep = "_")]] <- result

    cat(sprintf("   ✅ Windows: %d, Coverage: %.1f%%, Width: %.2f ± %.2f Da\n\n",
                nrow(result$windows),
                result$statistics$coverage_ratio * 100,
                result$statistics$mean_window_width,
                result$statistics$sd_window_width))
  }
}

cat("✅ All 8 combinations optimized\n\n")

# =============================================================================
# Stage 4: Visualization & Reporting
# =============================================================================

cat("Stage 4: Visualization & Reporting\n")
cat("─────────────────────────────────────────────────────────────\n")

output_dir <- "results_90min_visualization"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Prepare windows_list for comparison plots (using 'variable' mode)
# Extract only the 4 strategies with variable mode
windows_list_variable <- list(
  quantile = all_results[["quantile_variable"]],
  smoothing = all_results[["smoothing_variable"]],
  outlier = all_results[["outlier_variable"]],
  coverage = all_results[["coverage_variable"]]
)

# Use quantile_variable as the primary strategy for single-strategy plots
viz_result <- generate_visualizations(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  optimized_windows = all_results[["quantile_variable"]],
  output_dir = output_dir,
  create_pdf = TRUE,
  create_individual_plots = TRUE,
  plot_format = "png",
  plot_dpi = 300,
  windows_list = windows_list_variable
)

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                   VISUALIZATION COMPLETE!                      ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat(sprintf("✅ Total plots generated: %d\n", length(viz_result$plots)))
cat(sprintf("✅ Output directory: %s\n", output_dir))
cat(sprintf("✅ PDF report: %s/visualization_report_90min.pdf\n", output_dir))

# List all generated plot files
plot_files <- list.files(output_dir, pattern = "\\.png$", full.names = FALSE)
cat(sprintf("\n📊 Generated %d plot files:\n", length(plot_files)))
for (f in sort(plot_files)) {
  cat(sprintf("   - %s\n", f))
}

cat("\n✅ Done!\n")
