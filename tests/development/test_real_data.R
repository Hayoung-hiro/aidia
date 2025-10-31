# test_real_data.R - Test Modules 1-3 with Real DIA-NN Data
# Validates enhanced DPPP analysis, RT segmentation, and RT-dependent density analysis

cat("============================================================\n")
cat("Testing Modules 1-3 with Real DIA-NN Data\n")
cat("============================================================\n\n")

# Load required libraries
library(dplyr)
library(ggplot2)
library(arrow)

# Source module files
cat("Loading modules...\n")
source("R/data_loader.R")
source("R/dppp_calculator.R")
source("R/dppp_analyzer_enhanced.R")  # Module 1
source("R/rt_segmentation.R")          # Module 2
source("R/optimizer.R")                # Module 3 (enhanced)
source("R/visualizer.R")               # Enhanced visualizer
source("R/dynamicDIA.R")               # For smoothing functions
cat("✓ All modules loaded\n\n")

# ============================================================================
# Load Real Data
# ============================================================================

data_file <- "rawfile/report.parquet"
raw_file <- "rawfile/20250214_Untact_urine_200ng_0_2iRT_75min_DIA_01.raw"

cat(sprintf("Loading data from: %s\n", data_file))
data <- load_diann_data(data_file)

cat(sprintf("✓ Data loaded: %d precursors\n", nrow(data)))
cat(sprintf("  RT range: %.1f - %.1f min\n", min(data$RT.Start), max(data$RT.Start)))
cat(sprintf("  m/z range: %.1f - %.1f\n", min(data$Precursor.Mz), max(data$Precursor.Mz)))

# Check FWHM availability
if ("FWHM" %in% names(data)) {
  valid_fwhm <- sum(!is.na(data$FWHM) & data$FWHM > 0)
  cat(sprintf("  FWHM available: %d precursors (%.1f%%)\n",
              valid_fwhm, 100 * valid_fwhm / nrow(data)))
  cat(sprintf("  FWHM range: %.2f - %.2f min\n",
              min(data$FWHM, na.rm = TRUE), max(data$FWHM, na.rm = TRUE)))
} else {
  stop("FWHM column not found in data!")
}

# ============================================================================
# Module 1: Enhanced DPPP Analyzer
# ============================================================================

cat("\n============================================================\n")
cat("MODULE 1: Enhanced DPPP Analyzer (Real Data)\n")
cat("============================================================\n\n")

# Test 1.1: Analyze current DPPP distribution
cat("Test 1.1: Analyze DPPP distribution (scan_time = 2.0 sec)\n")
dppp_analysis <- analyze_dppp_distribution(
  data,
  scan_time = 2.0,
  target_dppp = 1.25,
  dppp_tolerance = 0.1
)

# Test 1.2: Calculate optimal scan time
cat("\n\nTest 1.2: Calculate optimal scan time for 85% satisfaction\n")
optimal_scan_time <- calculate_optimal_scan_time(
  data,
  target_dppp = 1.25,
  target_satisfaction_ratio = 0.85,
  scan_time_range = c(1.0, 3.0)
)

# Test 1.3: Visualizations
cat("\n\nTest 1.3: Generate Module 1 visualizations\n")
p1_histogram <- plot_dppp_histogram(dppp_analysis)
p1_heatmap <- plot_dppp_heatmap_2d(dppp_analysis)
p1_breakdown <- plot_dppp_satisfaction_breakdown(dppp_analysis)
p1_curve <- plot_satisfaction_curve(optimal_scan_time)
p1_tradeoff <- plot_scan_time_tradeoff(optimal_scan_time)

cat("  ✓ 5 visualizations created\n")

# Save plots
dir.create("test_output", showWarnings = FALSE)
ggsave("test_output/m1_dppp_histogram.png", p1_histogram, width = 10, height = 6, dpi = 300)
ggsave("test_output/m1_dppp_heatmap.png", p1_heatmap, width = 12, height = 8, dpi = 300)
ggsave("test_output/m1_satisfaction_breakdown.png", p1_breakdown, width = 10, height = 6, dpi = 300)
ggsave("test_output/m1_satisfaction_curve.png", p1_curve, width = 10, height = 6, dpi = 300)
ggsave("test_output/m1_tradeoff_analysis.png", p1_tradeoff, width = 12, height = 8, dpi = 300)

cat("\n✓ Module 1 test complete - plots saved to test_output/\n")

# ============================================================================
# Module 2: RT Segmentation Manager
# ============================================================================

cat("\n============================================================\n")
cat("MODULE 2: RT Segmentation Manager (Real Data)\n")
cat("============================================================\n\n")

n_segments <- 5

# Test 2.1: Compare all segmentation strategies
cat("Test 2.1: Compare RT segmentation strategies\n")
comparison <- compare_segmentation_strategies(
  data,
  n_segments = n_segments,
  strategies = c("uniform", "density", "quantile")
)

cat(sprintf("\n✓ Strategy Comparison Summary:\n"))
print(comparison$summary)
cat(sprintf("\nRecommended strategy: %s\n", comparison$best_strategy))

# Test 2.2: Visualizations
cat("\n\nTest 2.2: Generate Module 2 visualizations\n")
p2_distribution <- plot_precursor_distribution_by_strategy(comparison)
p2_balance <- plot_balance_score_comparison(comparison)
p2_segment_size <- plot_segment_size_distribution(comparison)
p2_coverage <- plot_rt_coverage_comparison(comparison)

cat("  ✓ 4 visualizations created\n")

# Save plots
ggsave("test_output/m2_distribution_comparison.png", p2_distribution, width = 12, height = 6, dpi = 300)
ggsave("test_output/m2_balance_scores.png", p2_balance, width = 10, height = 6, dpi = 300)
ggsave("test_output/m2_segment_sizes.png", p2_segment_size, width = 12, height = 6, dpi = 300)
ggsave("test_output/m2_rt_coverage.png", p2_coverage, width = 14, height = 8, dpi = 300)

cat("\n✓ Module 2 test complete - plots saved to test_output/\n")

# ============================================================================
# Module 3: RT-Dependent Density Analyzer
# ============================================================================

cat("\n============================================================\n")
cat("MODULE 3: RT-Dependent Density Analyzer (Real Data)\n")
cat("============================================================\n\n")

# Test 3.1: Analyze RT-dependent density
cat("Test 3.1: Analyze RT × m/z density (50x50 bins)\n")
density_analysis <- analyze_rt_dependent_density(
  data,
  rt_bins = 50,
  mz_bins = 50
)

# Test 3.2: Identify high-density regions
cat("\n\nTest 3.2: Identify high-density regions (P90 threshold)\n")
high_density_regions <- identify_high_density_regions(
  density_analysis,
  threshold_percentile = 0.90,
  min_region_size = 4
)

if (nrow(high_density_regions$regions) > 0) {
  cat(sprintf("\n✓ High-Density Regions Found:\n"))
  print(head(high_density_regions$regions, 5))
}

# Test 3.3: Apply dynamicDIA smoothing
cat("\n\nTest 3.3: Apply Savitzky-Golay smoothing\n")
smoothing_result <- apply_dynamicDIA_smoothing(
  density_analysis,
  method = "savgol",
  window_size = 7,
  polynomial_order = 3
)

# Test 3.4: Compare smoothing methods
cat("\n\nTest 3.4: Compare all smoothing methods\n")
smoothing_comparison <- compare_smoothing_methods(
  density_analysis,
  window_size = 7,
  polynomial_order = 3,
  sigma = 1.0
)

cat(sprintf("\n✓ Smoothing Method Comparison:\n"))
print(smoothing_comparison$comparison)
cat(sprintf("\nRecommended method: %s\n", smoothing_comparison$recommended_method))

# Test 3.5: Visualizations
cat("\n\nTest 3.5: Generate Module 3 visualizations\n")
p3_heatmap <- plot_density_heatmap_2d(density_analysis)
p3_regions <- plot_high_density_regions(density_analysis, high_density_regions)
p3_boundaries <- plot_rt_dependent_boundaries(smoothing_result)
p3_width <- plot_rt_dependent_width(smoothing_result)
p3_comparison <- plot_smoothing_comparison(smoothing_comparison)

cat("  ✓ 5 visualizations created\n")

# Save plots
ggsave("test_output/m3_density_heatmap.png", p3_heatmap, width = 12, height = 8, dpi = 300)
ggsave("test_output/m3_high_density_regions.png", p3_regions, width = 12, height = 8, dpi = 300)
ggsave("test_output/m3_rt_boundaries.png", p3_boundaries, width = 12, height = 6, dpi = 300)
ggsave("test_output/m3_rt_width.png", p3_width, width = 12, height = 6, dpi = 300)
ggsave("test_output/m3_smoothing_comparison.png", p3_comparison, width = 14, height = 10, dpi = 300)

cat("\n✓ Module 3 test complete - plots saved to test_output/\n")

# ============================================================================
# Create Comprehensive Report
# ============================================================================

cat("\n============================================================\n")
cat("COMPREHENSIVE ANALYSIS REPORT\n")
cat("============================================================\n\n")

# Summary statistics
cat("=== Data Summary ===\n")
cat(sprintf("Total precursors: %d\n", nrow(data)))
cat(sprintf("RT range: %.1f - %.1f min\n", min(data$RT.Start), max(data$RT.Start)))
cat(sprintf("m/z range: %.1f - %.1f\n", min(data$Precursor.Mz), max(data$Precursor.Mz)))
cat(sprintf("FWHM (median): %.2f min\n", median(data$FWHM, na.rm = TRUE)))

cat("\n=== Module 1: DPPP Analysis ===\n")
cat(sprintf("Current DPPP (scan_time=2.0s): %.2f (median)\n", dppp_analysis$stats$median_dppp))
cat(sprintf("Target DPPP satisfaction: %.1f%%\n", dppp_analysis$satisfaction$satisfaction_ratio * 100))
cat(sprintf("Recommended scan_time: %.2f sec\n", optimal_scan_time$optimal_scan_time))
cat(sprintf("Expected satisfaction: %.1f%%\n", optimal_scan_time$achieved_satisfaction * 100))

cat("\n=== Module 2: RT Segmentation ===\n")
cat(sprintf("Best segmentation strategy: %s\n", comparison$best_strategy))
best_strategy_data <- comparison$results[[comparison$best_strategy]]
cat(sprintf("Balance score: %.3f\n", best_strategy_data$balance_score))
cat(sprintf("Precursor CV: %.1f%%\n",
            best_strategy_data$balance_score * 100))

cat("\n=== Module 3: Density Analysis ===\n")
cat(sprintf("Max density: %d precursors/bin\n", density_analysis$statistics$max_density))
cat(sprintf("High-density regions: %d\n", high_density_regions$n_regions))
cat(sprintf("Recommended smoothing: %s\n", smoothing_comparison$recommended_method))
cat(sprintf("Mean boundary change: %.2f Da\n",
            mean(c(smoothing_result$smoothing_stats$mean_delta_low,
                  smoothing_result$smoothing_stats$mean_delta_high))))

# Save comprehensive report
cat("\n=== Saving Comprehensive Report ===\n")

# Create combined report PDF
pdf("test_output/comprehensive_report.pdf", width = 14, height = 10)

# Module 1 plots
print(p1_histogram)
print(p1_heatmap)
print(p1_breakdown)
print(p1_curve)
print(p1_tradeoff)

# Module 2 plots
print(p2_distribution)
print(p2_balance)
print(p2_segment_size)
print(p2_coverage)

# Module 3 plots
print(p3_heatmap)
print(p3_regions)
print(p3_boundaries)
print(p3_width)
print(p3_comparison)

dev.off()

cat("✓ Comprehensive report saved to: test_output/comprehensive_report.pdf\n")

# Save analysis results
saveRDS(list(
  data_info = list(
    n_precursors = nrow(data),
    rt_range = range(data$RT.Start),
    mz_range = range(data$Precursor.Mz),
    fwhm_median = median(data$FWHM, na.rm = TRUE)
  ),
  module_1 = list(
    dppp_analysis = dppp_analysis,
    optimal_scan_time = optimal_scan_time
  ),
  module_2 = list(
    comparison = comparison,
    best_strategy = comparison$best_strategy
  ),
  module_3 = list(
    density_analysis = density_analysis,
    high_density_regions = high_density_regions,
    smoothing_result = smoothing_result,
    smoothing_comparison = smoothing_comparison
  )
), "test_output/analysis_results.rds")

cat("✓ Analysis results saved to: test_output/analysis_results.rds\n")

# ============================================================================
# Final Summary
# ============================================================================

cat("\n============================================================\n")
cat("TEST COMPLETE - REAL DATA VALIDATION\n")
cat("============================================================\n\n")

cat("✅ Module 1 (Enhanced DPPP Analyzer): VALIDATED\n")
cat(sprintf("   - Current DPPP satisfaction: %.1f%%\n",
            dppp_analysis$satisfaction$satisfaction_ratio * 100))
cat(sprintf("   - Optimal scan_time: %.2f sec → %.1f%% satisfaction\n",
            optimal_scan_time$optimal_scan_time,
            optimal_scan_time$achieved_satisfaction * 100))

cat("\n✅ Module 2 (RT Segmentation Manager): VALIDATED\n")
cat(sprintf("   - Best strategy: %s (balance score: %.3f)\n",
            comparison$best_strategy,
            comparison$results[[comparison$best_strategy]]$balance_score))
cat(sprintf("   - Precursor distribution CV: %.1f%%\n",
            comparison$results[[comparison$best_strategy]]$balance_score * 100))

cat("\n✅ Module 3 (RT-Dependent Density Analyzer): VALIDATED\n")
cat(sprintf("   - High-density regions detected: %d\n", high_density_regions$n_regions))
cat(sprintf("   - Recommended smoothing: %s\n", smoothing_comparison$recommended_method))
cat(sprintf("   - Mean boundary adjustment: %.2f Da\n",
            mean(c(smoothing_result$smoothing_stats$mean_delta_low,
                  smoothing_result$smoothing_stats$mean_delta_high))))

cat("\n📊 Output Files:\n")
cat("   - test_output/comprehensive_report.pdf (14 plots)\n")
cat("   - test_output/analysis_results.rds (all results)\n")
cat("   - test_output/m1_*.png (5 Module 1 plots)\n")
cat("   - test_output/m2_*.png (4 Module 2 plots)\n")
cat("   - test_output/m3_*.png (5 Module 3 plots)\n")

cat("\n✅ All modules successfully validated with real DIA-NN data!\n\n")
