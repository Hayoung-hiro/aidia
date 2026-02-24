# =============================================================================
# Stage 4 Visualization Test with Real Pipeline Data
# =============================================================================
# Tests all 8 essential plots and PDF report generation using actual output
# from the completed full pipeline test
# =============================================================================

library(arrow)
library(dplyr)
library(ggplot2)

# Source modules
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/visualization.R")
source("R/config_loader.R")
source("R/instrument_utils.R")

# =============================================================================
# Test Configuration
# =============================================================================

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          Stage 4 Visualization Test (Real Data)               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Use 30min gradient with quantile strategy and fixed mode
test_input_file <- "data/30min_report.parquet"
test_output_dir <- "results_stage4_test"
dir.create(test_output_dir, showWarnings = FALSE, recursive = TRUE)

# Load configuration
config <- load_optimization_config("config/test_config.json")

# =============================================================================
# Stage 1: Data Validation
# =============================================================================

cat("Stage 1: Data Validation\n")
cat("─────────────────────────────────────────────────────────────\n")

validated_data <- create_validated_dataset(
  proteome_file = test_input_file,
  apply_quality_filters = TRUE
)

cat(sprintf("✅ Validated %s precursors\n",
            format(nrow(validated_data$data), big.mark = ",")))

# =============================================================================
# Stage 2: Optimization Planning
# =============================================================================

cat("\nStage 2: Optimization Planning\n")
cat("─────────────────────────────────────────────────────────────\n")

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 1.2,  # 30min gradient estimate
  instrument_preset = config$instrument$preset,
  target_dppp = config$dppp_parameters$target_dppp,
  target_satisfaction = config$dppp_parameters$target_satisfaction,
  dppp_tolerance = 0.0,
  load_factor = config$scan_settings$load_factor,
  ms1_scans_per_cycle = config$scan_settings$ms1_scans_per_cycle,
  warning_threshold_windows = 5
)

cat(sprintf("✅ Planning complete:\n"))
cat(sprintf("   Required cycle time: %.3f sec\n",
            optimization_plan$required_cycle_time_sec))
cat(sprintf("   Windows per RT bin: %d\n",
            optimization_plan$window_count_per_bin))

# =============================================================================
# Stage 3: Window Optimization (Quantile + Fixed)
# =============================================================================

cat("\nStage 3: Window Optimization (Quantile + Fixed)\n")
cat("─────────────────────────────────────────────────────────────\n")

windows_result <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = config$rt_binning$rt_bin_width_min,
  mz_strategy = "quantile",
  window_mode = "fixed",
  target_coverage = 0.95,
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  outlier_threshold = 3.0,
  smoothing_window = 3,
  polynomial_order = 2,
  min_width_da = config$window_generation$min_width_da,
  max_width_da = config$window_generation$max_width_da,
  overlap_percentage = 0
)

cat(sprintf("✅ Window optimization complete:\n"))
cat(sprintf("   Total windows: %d\n", nrow(windows_result$windows)))
cat(sprintf("   Coverage: %.1f%%\n", windows_result$statistics$coverage_percentage))
cat(sprintf("   Mean width: %.2f ± %.2f Da\n",
            windows_result$statistics$window_width_mean,
            windows_result$statistics$window_width_sd))

# =============================================================================
# Stage 4: Visualization Testing
# =============================================================================

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    STAGE 4 VISUALIZATION                       ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Test individual plot generation
cat("Testing Individual Plots:\n")
cat("─────────────────────────────────────────────────────────────\n")

# Plot 1: DPPP Density 2D Heatmap
cat("[1/8] Testing plot_dppp_density()...")
tryCatch({
  plot1 <- plot_dppp_density(
    validated_data = validated_data,
    optimization_plan = optimization_plan
  )
  ggsave(file.path(test_output_dir, "plot1_dppp_density.png"),
         plot1, width = 10, height = 6, dpi = 300)
  cat(" ✅ PASS\n")
}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# Plot 2: RT Window Size
cat("[2/8] Testing plot_rt_window_size()...")
tryCatch({
  plot2 <- plot_rt_window_size(optimized_windows = windows_result)
  ggsave(file.path(test_output_dir, "plot2_rt_window_size.png"),
         plot2, width = 10, height = 6, dpi = 300)
  cat(" ✅ PASS\n")
}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# Plot 3: RT-m/z Density Heatmap
cat("[3/8] Testing plot_rt_mz_density_heatmap()...")
tryCatch({
  plot3 <- plot_rt_mz_density_heatmap(validated_data = validated_data)
  ggsave(file.path(test_output_dir, "plot3_rt_mz_density_heatmap.png"),
         plot3, width = 10, height = 6, dpi = 300)
  cat(" ✅ PASS\n")
}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# Plot 4: RT-Normalized m/z Density
cat("[4/8] Testing plot_mz_normalized_density()...")
tryCatch({
  plot4 <- plot_mz_normalized_density(
    optimized_windows = windows_result,
    validated_data = validated_data
  )
  ggsave(file.path(test_output_dir, "plot4_mz_normalized_density.png"),
         plot4, width = 10, height = 6, dpi = 300)
  cat(" ✅ PASS\n")
}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# Plot 5: Window Width Distribution
cat("[5/8] Testing plot_mz_window_width()...")
tryCatch({
  plot5 <- plot_mz_window_width(optimized_windows = windows_result)
  ggsave(file.path(test_output_dir, "plot5_mz_window_width.png"),
         plot5, width = 10, height = 6, dpi = 300)
  cat(" ✅ PASS\n")
}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# Plot 6: Precursor Coverage Map
cat("[6/8] Testing plot_precursor_coverage_map()...")
tryCatch({
  plot6 <- plot_precursor_coverage_map(
    optimized_windows = windows_result,
    validated_data = validated_data
  )
  ggsave(file.path(test_output_dir, "plot6_precursor_coverage_map.png"),
         plot6, width = 10, height = 6, dpi = 300)
  cat(" ✅ PASS\n")
}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# Plot 7: Window Efficiency
cat("[7/8] Testing plot_window_efficiency()...")
tryCatch({
  plot7 <- plot_window_efficiency(optimized_windows = windows_result)
  ggsave(file.path(test_output_dir, "plot7_window_efficiency.png"),
         plot7, width = 10, height = 6, dpi = 300)
  cat(" ✅ PASS\n")
}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# Plot 8: DPPP Achievement Heatmap
cat("[8/8] Testing plot_dppp_achievement_heatmap()...")
tryCatch({
  plot8 <- plot_dppp_achievement_heatmap(
    optimization_plan = optimization_plan,
    optimized_windows = windows_result,
    validated_data = validated_data
  )
  ggsave(file.path(test_output_dir, "plot8_dppp_achievement_heatmap.png"),
         plot8, width = 10, height = 6, dpi = 300)
  cat(" ✅ PASS\n")
}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# =============================================================================
# Test Main Orchestration Function
# =============================================================================

cat("\n─────────────────────────────────────────────────────────────\n")
cat("Testing Main Orchestration Function:\n")
cat("─────────────────────────────────────────────────────────────\n")

cat("Testing generate_visualizations()...")
tryCatch({
  viz_result <- generate_visualizations(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    optimized_windows = windows_result,
    output_dir = test_output_dir,
    create_pdf = FALSE,
    create_individual_plots = TRUE
  )
  cat(" ✅ PASS\n")

  # Verify all plots exist
  cat("\nVerifying individual plot files:\n")
  expected_plots <- c(
    "plot1_dppp_density.png",
    "plot2_rt_window_size.png",
    "plot3_rt_mz_heatmap.png",
    "plot4_mz_normalized_density.png",
    "plot5_mz_window_width.png",
    "plot6_precursor_coverage_map.png",
    "plot7_window_efficiency.png",
    "plot8_dppp_achievement_heatmap.png"
  )

  for (plot_file in expected_plots) {
    plot_path <- file.path(test_output_dir, plot_file)
    if (file.exists(plot_path)) {
      cat(sprintf("   ✅ %s\n", plot_file))
    } else {
      cat(sprintf("   ❌ %s (MISSING)\n", plot_file))
    }
  }

}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# =============================================================================
# Test PDF Report Generation
# =============================================================================

cat("\n─────────────────────────────────────────────────────────────\n")
cat("Testing PDF Report Generation:\n")
cat("─────────────────────────────────────────────────────────────\n")

cat("Testing create_pdf_report()...")
tryCatch({
  # First generate all plots
  plots <- list()
  plots[[1]] <- plot_dppp_density(optimization_plan, validated_data)
  plots[[2]] <- plot_rt_window_size(windows_result)
  plots[[3]] <- plot_rt_mz_density_heatmap(validated_data)
  plots[[4]] <- plot_mz_normalized_density(windows_result, validated_data)
  plots[[5]] <- plot_mz_window_width(windows_result)
  plots[[6]] <- plot_precursor_coverage_map(windows_result, validated_data)
  plots[[7]] <- plot_window_efficiency(windows_result)
  plots[[8]] <- plot_dppp_achievement_heatmap(optimization_plan, windows_result, validated_data)

  pdf_path <- file.path(test_output_dir, "stage4_test_report.pdf")
  create_pdf_report(
    plots = plots,
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    optimized_windows = windows_result,
    output_file = pdf_path
  )

  if (file.exists(pdf_path)) {
    cat(" ✅ PASS\n")
    cat(sprintf("   PDF report: %s\n", pdf_path))
    cat(sprintf("   File size: %.2f KB\n", file.info(pdf_path)$size / 1024))
  } else {
    cat(" ❌ FAIL (file not created)\n")
  }

}, error = function(e) {
  cat(" ❌ FAIL\n")
  cat(sprintf("   Error: %s\n", e$message))
})

# =============================================================================
# Final Summary
# =============================================================================

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    STAGE 4 TEST COMPLETE                       ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat(sprintf("✅ Test output directory: %s\n", test_output_dir))
cat(sprintf("✅ Configuration: %s\n", "config/test_config.json"))
cat(sprintf("✅ Input file: %s\n", test_input_file))
cat(sprintf("✅ Strategy: quantile + fixed mode\n"))
cat("\nExpected outputs:\n")
cat("   - 8 individual PNG plot files (300 DPI)\n")
cat("   - 8 PNG files from generate_visualizations()\n")
cat("   - 1 PDF comprehensive report\n")
cat("\n")
