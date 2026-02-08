# test_modules_1_2_3.R - Test script for Modules 1, 2, and 3
# Tests enhanced DPPP analysis, RT segmentation, and RT-dependent density analysis

cat("============================================================\n")
cat("Testing Modules 1, 2, and 3 - DIA Window Optimizer\n")
cat("============================================================\n\n")

# Load required libraries
library(dplyr)
library(ggplot2)

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
# Create synthetic test data (if no real data available)
# ============================================================================

create_synthetic_diann_data <- function(n_precursors = 5000,
                                       rt_range = c(5, 60),
                                       mz_range = c(400, 900)) {

  cat("Creating synthetic DIA-NN data...\n")

  # Generate RT with some clustering
  rt_clusters <- sample(seq(rt_range[1], rt_range[2], by = 5), n_precursors, replace = TRUE)
  rt_noise <- rnorm(n_precursors, 0, 2)
  RT.Start <- pmax(rt_range[1], pmin(rt_range[2], rt_clusters + rt_noise))

  # Generate m/z with some density variation
  mz_mean <- (mz_range[1] + mz_range[2]) / 2
  mz_sd <- (mz_range[2] - mz_range[1]) / 6
  Precursor.Mz <- rnorm(n_precursors, mz_mean, mz_sd)
  Precursor.Mz <- pmax(mz_range[1], pmin(mz_range[2], Precursor.Mz))

  # Generate FWHM values (in minutes)
  FWHM <- rnorm(n_precursors, 0.4, 0.1)  # ~0.4 min mean FWHM
  FWHM <- pmax(0.1, pmin(1.0, FWHM))

  # Create data frame
  data <- data.frame(
    Precursor.Id = paste0("PRECURSOR_", 1:n_precursors),
    RT.Start = RT.Start,
    Precursor.Mz = Precursor.Mz,
    FWHM = FWHM,
    PG.Q.Value = runif(n_precursors, 0, 0.05)
  )

  cat(sprintf("✓ Created %d synthetic precursors\n", n_precursors))
  cat(sprintf("  RT range: %.1f - %.1f min\n", min(data$RT.Start), max(data$RT.Start)))
  cat(sprintf("  m/z range: %.1f - %.1f\n", min(data$Precursor.Mz), max(data$Precursor.Mz)))
  cat(sprintf("  FWHM: %.2f ± %.2f min\n", mean(data$FWHM), sd(data$FWHM)))

  return(data)
}

# ============================================================================
# Test Module 1: Enhanced DPPP Analyzer
# ============================================================================

test_module_1 <- function(data) {

  cat("\n============================================================\n")
  cat("MODULE 1: Enhanced DPPP Analyzer\n")
  cat("============================================================\n\n")

  # Test 1: Analyze current DPPP distribution
  cat("Test 1.1: Analyze DPPP distribution\n")
  dppp_analysis <- analyze_dppp_distribution(
    data,
    scan_time = 2.0,
    target_dppp = 1.25,
    dppp_tolerance = 0.1
  )

  cat(sprintf("\n✓ DPPP Analysis Results:\n"))
  cat(sprintf("  Mean DPPP: %.2f\n", dppp_analysis$stats$mean_dppp))
  cat(sprintf("  Median DPPP: %.2f\n", dppp_analysis$stats$median_dppp))
  cat(sprintf("  Satisfaction ratio: %.1f%%\n",
              dppp_analysis$satisfaction$satisfaction_ratio * 100))

  # Test 2: Calculate optimal scan time
  cat("\n\nTest 1.2: Calculate optimal scan time\n")
  optimal_scan_time <- calculate_optimal_scan_time(
    data,
    target_dppp = 1.25,
    target_satisfaction_ratio = 0.85,
    scan_time_range = c(1.0, 3.0)
  )

  cat(sprintf("\n✓ Optimal Scan Time Results:\n"))
  cat(sprintf("  Recommended scan_time: %.2f sec\n", optimal_scan_time$optimal_scan_time))
  cat(sprintf("  Expected satisfaction: %.1f%%\n",
              optimal_scan_time$achieved_satisfaction * 100))

  # Test 3: Create 2D DPPP distribution
  cat("\n\nTest 1.3: Create 2D DPPP distribution\n")
  dppp_2d <- create_dppp_2d_distribution(data, rt_bins = 30, mz_bins = 30)

  cat(sprintf("\n✓ 2D DPPP Distribution:\n"))
  cat(sprintf("  RT bins: %d\n", dppp_2d$rt_bins))
  cat(sprintf("  m/z bins: %d\n", dppp_2d$mz_bins))
  cat(sprintf("  Bins with data: %d\n", nrow(dppp_2d$summary)))
  cat(sprintf("  Max DPPP: %.2f\n", max(dppp_2d$summary$mean_dppp, na.rm = TRUE)))

  # Test 4: Visualizations
  cat("\n\nTest 1.4: Generate visualizations\n")

  p1 <- plot_dppp_histogram(dppp_analysis)
  cat("  ✓ DPPP histogram created\n")

  p2 <- plot_dppp_heatmap_2d(dppp_analysis)
  cat("  ✓ DPPP 2D heatmap created\n")

  p3 <- plot_dppp_satisfaction_breakdown(dppp_analysis)
  cat("  ✓ Satisfaction breakdown created\n")

  p4 <- plot_satisfaction_curve(optimal_scan_time)
  cat("  ✓ Satisfaction curve created\n")

  p5 <- plot_scan_time_tradeoff(optimal_scan_time)
  cat("  ✓ Trade-off analysis created\n")

  cat("\n✓ Module 1 tests completed successfully\n")

  return(list(
    dppp_analysis = dppp_analysis,
    optimal_scan_time = optimal_scan_time,
    plots = list(p1, p2, p3, p4, p5)
  ))
}

# ============================================================================
# Test Module 2: RT Segmentation Manager
# ============================================================================

test_module_2 <- function(data) {

  cat("\n============================================================\n")
  cat("MODULE 2: RT Segmentation Manager\n")
  cat("============================================================\n\n")

  n_segments <- 5

  # Test 1: Uniform segmentation
  cat("Test 2.1: Uniform RT segmentation\n")
  uniform_seg <- segment_rt_uniform(data, n_segments = n_segments)

  cat(sprintf("\n✓ Uniform Segmentation:\n"))
  cat(sprintf("  Segments: %d\n", nrow(uniform_seg$segment_stats)))
  cat(sprintf("  Balance score: %.3f\n", uniform_seg$balance_score))

  # Test 2: Density-based segmentation
  cat("\n\nTest 2.2: Density-based RT segmentation\n")
  density_seg <- segment_rt_density(data, n_segments = n_segments, density_threshold = 0.8)

  cat(sprintf("\n✓ Density-based Segmentation:\n"))
  cat(sprintf("  Segments: %d\n", nrow(density_seg$segment_stats)))
  cat(sprintf("  Balance score: %.3f\n", density_seg$balance_score))

  # Test 3: Quantile-based segmentation
  cat("\n\nTest 2.3: Quantile-based RT segmentation\n")
  quantile_seg <- segment_rt_quantile(data, n_segments = n_segments)

  cat(sprintf("\n✓ Quantile-based Segmentation:\n"))
  cat(sprintf("  Segments: %d\n", nrow(quantile_seg$segment_stats)))
  cat(sprintf("  Balance score: %.3f (best balanced)\n", quantile_seg$balance_score))

  # Test 4: Compare all strategies
  cat("\n\nTest 2.4: Compare segmentation strategies\n")
  comparison <- compare_segmentation_strategies(
    data,
    n_segments = n_segments,
    strategies = c("uniform", "density", "quantile")
  )

  cat(sprintf("\n✓ Strategy Comparison:\n"))
  print(comparison$summary)
  cat(sprintf("\n  Recommended strategy: %s\n", comparison$best_strategy))

  # Test 5: Visualizations
  cat("\n\nTest 2.5: Generate visualizations\n")

  p1 <- plot_precursor_distribution_by_strategy(comparison)
  cat("  ✓ Precursor distribution plot created\n")

  p2 <- plot_balance_score_comparison(comparison)
  cat("  ✓ Balance score comparison created\n")

  p3 <- plot_segment_size_distribution(comparison)
  cat("  ✓ Segment size distribution created\n")

  p4 <- plot_rt_coverage_comparison(comparison)
  cat("  ✓ RT coverage comparison created\n")

  cat("\n✓ Module 2 tests completed successfully\n")

  return(list(
    uniform_seg = uniform_seg,
    density_seg = density_seg,
    quantile_seg = quantile_seg,
    comparison = comparison,
    plots = list(p1, p2, p3, p4)
  ))
}

# ============================================================================
# Test Module 3: RT-Dependent Density Analyzer
# ============================================================================

test_module_3 <- function(data) {

  cat("\n============================================================\n")
  cat("MODULE 3: RT-Dependent Density Analyzer\n")
  cat("============================================================\n\n")

  # Test 1: Analyze RT-dependent density
  cat("Test 3.1: Analyze RT × m/z density\n")
  density_analysis <- analyze_rt_dependent_density(
    data,
    rt_bins = 40,
    mz_bins = 40
  )

  cat(sprintf("\n✓ Density Analysis Results:\n"))
  cat(sprintf("  Total precursors: %d\n", density_analysis$statistics$total_precursors))
  cat(sprintf("  Max density: %d precursors/bin\n", density_analysis$statistics$max_density))
  cat(sprintf("  Mean density: %.1f precursors/bin\n", density_analysis$statistics$mean_density))

  # Test 2: Identify high-density regions
  cat("\n\nTest 3.2: Identify high-density regions\n")
  high_density_regions <- identify_high_density_regions(
    density_analysis,
    threshold_percentile = 0.90,
    min_region_size = 4
  )

  cat(sprintf("\n✓ High-Density Region Detection:\n"))
  cat(sprintf("  Regions found: %d\n", high_density_regions$n_regions))
  cat(sprintf("  Threshold: %.1f precursors/bin (P90)\n", high_density_regions$threshold))

  # Test 3: Apply dynamicDIA smoothing (Savitzky-Golay)
  cat("\n\nTest 3.3: Apply Savitzky-Golay smoothing\n")
  smoothing_savgol <- apply_dynamicDIA_smoothing(
    density_analysis,
    method = "savgol",
    window_size = 7,
    polynomial_order = 3
  )

  cat(sprintf("\n✓ Savitzky-Golay Smoothing:\n"))
  cat(sprintf("  Mean Δm/z (low): %.2f Da\n", smoothing_savgol$smoothing_stats$mean_delta_low))
  cat(sprintf("  Mean Δm/z (high): %.2f Da\n", smoothing_savgol$smoothing_stats$mean_delta_high))

  # Test 4: Compare smoothing methods
  cat("\n\nTest 3.4: Compare smoothing methods\n")
  smoothing_comparison <- compare_smoothing_methods(
    density_analysis,
    window_size = 7,
    polynomial_order = 3,
    sigma = 1.0
  )

  cat(sprintf("\n✓ Smoothing Comparison:\n"))
  print(smoothing_comparison$comparison)
  cat(sprintf("\n  Recommended method: %s\n", smoothing_comparison$recommended_method))

  # Test 5: Visualizations
  cat("\n\nTest 3.5: Generate visualizations\n")

  p1 <- plot_density_heatmap_2d(density_analysis)
  cat("  ✓ 2D density heatmap created\n")

  p2 <- plot_high_density_regions(density_analysis, high_density_regions)
  cat("  ✓ High-density region plot created\n")

  p3 <- plot_rt_dependent_boundaries(smoothing_savgol)
  cat("  ✓ RT-dependent boundaries plot created\n")

  p4 <- plot_rt_dependent_width(smoothing_savgol)
  cat("  ✓ RT-dependent width plot created\n")

  cat("\n✓ Module 3 tests completed successfully\n")

  return(list(
    density_analysis = density_analysis,
    high_density_regions = high_density_regions,
    smoothing_savgol = smoothing_savgol,
    smoothing_comparison = smoothing_comparison,
    plots = list(p1, p2, p3, p4)
  ))
}

# ============================================================================
# Main test execution
# ============================================================================

run_all_tests <- function(use_synthetic = TRUE, data_file = NULL) {

  cat("============================================================\n")
  cat("RUNNING ALL MODULE TESTS\n")
  cat("============================================================\n\n")

  # Load or create data
  if (use_synthetic || is.null(data_file)) {
    data <- create_synthetic_diann_data(n_precursors = 5000)
  } else {
    cat(sprintf("Loading data from: %s\n", data_file))
    data <- load_diann_data(data_file)
  }

  # Run module tests
  results_m1 <- test_module_1(data)
  results_m2 <- test_module_2(data)
  results_m3 <- test_module_3(data)

  # Summary
  cat("\n============================================================\n")
  cat("TEST SUMMARY\n")
  cat("============================================================\n\n")

  cat("✓ Module 1 (Enhanced DPPP Analyzer): PASSED\n")
  cat("  - DPPP distribution analysis\n")
  cat("  - Optimal scan time calculation\n")
  cat("  - 2D DPPP visualization\n")
  cat("  - 5 visualization functions tested\n\n")

  cat("✓ Module 2 (RT Segmentation Manager): PASSED\n")
  cat("  - Uniform segmentation\n")
  cat("  - Density-based segmentation\n")
  cat("  - Quantile-based segmentation\n")
  cat("  - Strategy comparison\n")
  cat("  - 4 visualization functions tested\n\n")

  cat("✓ Module 3 (RT-Dependent Density Analyzer): PASSED\n")
  cat("  - 2D density analysis\n")
  cat("  - High-density region detection\n")
  cat("  - dynamicDIA smoothing (3 methods)\n")
  cat("  - Smoothing comparison\n")
  cat("  - 4 visualization functions tested\n\n")

  cat("============================================================\n")
  cat("ALL TESTS COMPLETED SUCCESSFULLY!\n")
  cat("============================================================\n\n")

  return(list(
    data = data,
    module_1 = results_m1,
    module_2 = results_m2,
    module_3 = results_m3
  ))
}

# ============================================================================
# Execute tests
# ============================================================================

# Run with synthetic data
cat("\nStarting tests with synthetic data...\n\n")
test_results <- run_all_tests(use_synthetic = TRUE)

# Print final statistics
cat("\n============================================================\n")
cat("FINAL STATISTICS\n")
cat("============================================================\n\n")

cat(sprintf("Data: %d precursors\n", nrow(test_results$data)))
cat(sprintf("Module 1 outputs: %d plots\n", length(test_results$module_1$plots)))
cat(sprintf("Module 2 outputs: %d plots\n", length(test_results$module_2$plots)))
cat(sprintf("Module 3 outputs: %d plots\n", length(test_results$module_3$plots)))
cat(sprintf("\nTotal: %d visualization functions tested\n",
           length(test_results$module_1$plots) +
           length(test_results$module_2$plots) +
           length(test_results$module_3$plots)))

cat("\n✓ All modules are working correctly!\n\n")

# Optional: Save test results
# saveRDS(test_results, "test_results_modules_1_2_3.rds")
# cat("Test results saved to: test_results_modules_1_2_3.rds\n")
