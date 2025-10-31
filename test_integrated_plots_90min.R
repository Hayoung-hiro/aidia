# Test Integrated Stage 4 Pipeline with 10 Plots (90min dataset)

library(arrow)
library(dplyr)
library(ggplot2)
library(jsonlite)

# Source modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║     Test Integrated Stage 4 Pipeline (10 Plots, 90min)       ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load configuration
config_path <- "config/test_config.json"
cat(sprintf("Loading configuration: %s\n", config_path))
config <- fromJSON(config_path)
cat("✅ Configuration loaded successfully\n\n")

# ===========================================================================
# Stage 1: Data Validation
# ===========================================================================
cat("Stage 1: Data Validation\n")
cat("─────────────────────────────────────────────────────────────\n")

validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)

cat(sprintf("✅ %s precursors validated\n\n", format(nrow(validated_data$data), big.mark = ",")))

# ===========================================================================
# Stage 2: Optimization Planning
# ===========================================================================
cat("Stage 2: Optimization Planning\n")
cat("─────────────────────────────────────────────────────────────\n")

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,
  instrument_preset = config$instrument$preset,
  target_dppp = config$dppp_parameters$target_dppp,
  target_satisfaction = config$dppp_parameters$target_satisfaction,
  dppp_tolerance = 0.0,
  load_factor = config$scan_settings$load_factor,
  ms1_scans_per_cycle = config$scan_settings$ms1_scans_per_cycle
)

cat(sprintf("✅ Required cycle time: %.2f sec, Window count: %d\n\n",
            optimization_plan$required_cycle_time_sec,
            optimization_plan$window_count))

# ===========================================================================
# Stage 3: Window Optimization
# ===========================================================================
cat("Stage 3: Window Optimization\n")
cat("─────────────────────────────────────────────────────────────\n")

optimized_windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = config$rt_binning$rt_bin_width,
  mz_strategy = "quantile",
  window_mode = "variable",
  quantile_lower = 0.05,
  quantile_upper = 0.95
)

cat(sprintf("✅ %d windows generated across %d RT segments\n\n",
            nrow(optimized_windows$windows),
            length(unique(optimized_windows$windows$rt_segment_id))))

# ===========================================================================
# Stage 4: Visualization & Reporting (NEW - 10 Plots)
# ===========================================================================
cat("Stage 4: Integrated Visualization Test\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# Create test output directory
output_dir <- "test_plots/integrated/"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Generate all visualizations
viz_result <- generate_visualizations(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  optimized_windows = optimized_windows,
  output_dir = output_dir,
  create_pdf = FALSE,  # Skip PDF for now
  create_individual_plots = TRUE,
  plot_format = "png",
  plot_dpi = 300
)

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    INTEGRATION TEST COMPLETE                   ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Generated Plots:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat(sprintf("  Total plots: %d\n", length(viz_result$plots)))
cat(sprintf("  Output directory: %s\n\n", output_dir))

cat("Plot List:\n")
for (name in names(viz_result$plots)) {
  cat(sprintf("  ✅ %s\n", name))
}
cat("\n")

cat("Individual Plot Files:\n")
cat("─────────────────────────────────────────────────────────────\n")
for (file in viz_result$report_files$individual_plots) {
  size_kb <- file.info(file)$size / 1024
  cat(sprintf("  📊 %s (%.1f KB)\n", basename(file), size_kb))
}
cat("\n")

cat("Summary:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat(sprintf("  Plot generation time: %.2f sec\n", viz_result$metadata$plot_generation_time))
cat(sprintf("  Total processing time: %.2f sec\n", viz_result$metadata$total_time))
cat("\n")

cat("✅ All plots successfully generated and exported!\n")
cat("\n")
