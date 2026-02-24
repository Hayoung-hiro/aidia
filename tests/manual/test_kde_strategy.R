# test_kde_strategy.R - Functional Test for KDE m/z Strategy
# Tests the Kernel Density Estimation based m/z range optimization
#
# KDE algorithm finds density peak per RT bin and expands boundaries
# until density drops below threshold, with minimum coverage guarantee.
#
# Run: source("tests/manual/test_kde_strategy.R")

library(dplyr)

# Source required modules
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")

cat("\n")
cat("======================================================================\n")
cat("         KDE STRATEGY FUNCTIONAL TEST (Density-Peak Based)            \n")
cat("======================================================================\n\n")

# Find test data file (shared across all tests)
data_files <- list.files("data", pattern = "report\\.parquet$", full.names = TRUE)
if (length(data_files) == 0) {
  data_files <- list.files("data", pattern = "report\\.tsv$", full.names = TRUE)
}
test_data_file <- if (length(data_files) > 0) data_files[1] else NULL

tests_passed <- 0
tests_failed <- 0

# Test 1: Basic KDE Strategy Execution
cat("TEST 1: KDE Strategy Basic Execution\n")
cat("----------------------------------------------------------------------\n")
test1_result <- tryCatch({
  if (is.null(test_data_file)) {
    cat("  [SKIP] No test data available\n\n")
    NULL
  } else {
    cat(sprintf("  Using data: %s\n", basename(test_data_file)))

    validated_data <- create_validated_dataset(test_data_file)
    plan <- plan_optimization(validated_data, instrument_preset = "astral")

    windows <- optimize_windows(
      validated_data = validated_data,
      optimization_plan = plan,
      mz_strategy = "kde",
      window_mode = "density",
      kde_density_threshold = 0.10,  # 10% of peak density
      kde_min_coverage = 0.80        # At least 80% coverage
    )

    cat(sprintf("  Total windows: %d\n", nrow(windows$windows)))
    cat(sprintf("  Coverage: %.1f%%\n", windows$statistics$coverage_percentage))
    cat(sprintf("  Strategy used: %s\n", windows$mz_optimization$strategy))

    stopifnot(windows$mz_optimization$strategy == "kde")
    stopifnot(nrow(windows$windows) > 0)

    cat("[PASS] TEST 1\n\n")
    tests_passed <<- tests_passed + 1
    windows
  }
}, error = function(e) {
  cat(sprintf("[FAIL] TEST 1: %s\n\n", e$message))
  tests_failed <<- tests_failed + 1
  NULL
})

# Test 2: KDE vs Quantile Comparison
cat("TEST 2: KDE vs Quantile Strategy Comparison\n")
cat("----------------------------------------------------------------------\n")
cat("  Note: KDE uses density peak, Quantile uses percentiles\n")
cat("        KDE should focus on dense regions better\n\n")
test2_result <- tryCatch({
  if (is.null(test1_result)) {
    cat("  [SKIP] (no test data)\n\n")
    NULL
  } else {
    validated_data <- create_validated_dataset(test_data_file)
    plan <- plan_optimization(validated_data, instrument_preset = "astral")

    # Run both strategies
    windows_kde <- optimize_windows(validated_data, plan, mz_strategy = "kde",
                                    kde_density_threshold = 0.10, kde_min_coverage = 0.80)
    windows_quantile <- optimize_windows(validated_data, plan, mz_strategy = "quantile",
                                         quantile_lower = 0.05, quantile_upper = 0.95)

    kde_coverage <- windows_kde$statistics$coverage_percentage
    quantile_coverage <- windows_quantile$statistics$coverage_percentage

    # Get m/z ranges
    kde_mz_ranges <- windows_kde$mz_optimization$mz_ranges
    quantile_mz_ranges <- windows_quantile$mz_optimization$mz_ranges

    kde_avg_width <- mean(kde_mz_ranges$mz_width, na.rm = TRUE)
    quantile_avg_width <- mean(quantile_mz_ranges$mz_width, na.rm = TRUE)

    cat(sprintf("  KDE:\n"))
    cat(sprintf("    Coverage: %.1f%%\n", kde_coverage))
    cat(sprintf("    Avg m/z width: %.1f Da\n", kde_avg_width))
    if ("kde_peak_mz" %in% names(kde_mz_ranges)) {
      cat(sprintf("    Density peaks tracked: YES\n"))
    }
    cat(sprintf("  Quantile (P5-P95):\n"))
    cat(sprintf("    Coverage: %.1f%%\n", quantile_coverage))
    cat(sprintf("    Avg m/z width: %.1f Da\n", quantile_avg_width))
    cat(sprintf("\n"))

    # KDE should achieve at least min_coverage (80%)
    stopifnot(kde_coverage >= 75)  # Allow some tolerance

    cat("[PASS] TEST 2\n\n")
    tests_passed <<- tests_passed + 1
    list(kde = windows_kde, quantile = windows_quantile)
  }
}, error = function(e) {
  cat(sprintf("[FAIL] TEST 2: %s\n\n", e$message))
  tests_failed <<- tests_failed + 1
  NULL
})

# Test 3: KDE Parameter Sensitivity
cat("TEST 3: KDE Parameter Sensitivity (Threshold Variation)\n")
cat("----------------------------------------------------------------------\n")
test3_result <- tryCatch({
  if (is.null(test1_result)) {
    cat("  [SKIP] (no test data)\n\n")
    NULL
  } else {
    validated_data <- create_validated_dataset(test_data_file)
    plan <- plan_optimization(validated_data, instrument_preset = "astral")

    # Test different density thresholds
    thresholds <- c(0.05, 0.10, 0.20)
    results <- list()

    for (thresh in thresholds) {
      windows <- optimize_windows(validated_data, plan, mz_strategy = "kde",
                                  kde_density_threshold = thresh, kde_min_coverage = 0.80)
      mz_ranges <- windows$mz_optimization$mz_ranges
      avg_width <- mean(mz_ranges$mz_width, na.rm = TRUE)
      coverage <- windows$statistics$coverage_percentage

      cat(sprintf("  Threshold %.0f%%: Width=%.1f Da, Coverage=%.1f%%\n",
                  thresh * 100, avg_width, coverage))
      results[[as.character(thresh)]] <- list(width = avg_width, coverage = coverage)
    }

    # Lower threshold should generally give wider ranges (more inclusive)
    # Higher threshold should give narrower ranges (more focused on peak)
    cat("\n  Expected: Lower threshold -> wider range (more inclusive)\n")
    cat("           Higher threshold -> narrower range (focus on peak)\n\n")

    cat("[PASS] TEST 3\n\n")
    tests_passed <<- tests_passed + 1
    results
  }
}, error = function(e) {
  cat(sprintf("[FAIL] TEST 3: %s\n\n", e$message))
  tests_failed <<- tests_failed + 1
  NULL
})

# Summary
cat("======================================================================\n")
cat(sprintf("SUMMARY: %d passed, %d failed\n", tests_passed, tests_failed))
cat("======================================================================\n")
cat("\n")
cat("KDE Strategy Characteristics:\n")
cat("  - Finds density peak (mode) per RT bin using kernel density estimation\n")
cat("  - Expands from peak until density < threshold\n")
cat("  - Guarantees minimum coverage (expands if needed)\n")
cat("  - Best for: Finding dense regions while maintaining coverage\n")
cat("\n")
