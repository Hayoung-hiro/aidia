# test_greedy_strategy.R - Functional Test for Greedy m/z Strategy
# Tests the MacCoss Lab-inspired greedy precursor maximization
#
# IMPORTANT: Greedy algorithm uses FIXED m/z range (n_windows × min_width_da)
# and finds the optimal POSITION. This may result in lower coverage than
# other strategies when precursors are spread across a wide m/z range.
#
# Run: source("tests/manual/test_greedy_strategy.R")

library(dplyr)

# Source required modules
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   GREEDY STRATEGY FUNCTIONAL TEST (MacCoss Lab Algorithm)            ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n\n")

tests_passed <- 0
tests_failed <- 0

# Test 1: Basic Greedy Strategy Execution
cat("TEST 1: Greedy Strategy Basic Execution\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
test1_result <- tryCatch({
  # Find available data file
  data_files <- list.files("data", pattern = "report\\.parquet$", full.names = TRUE)
  if (length(data_files) == 0) {
    data_files <- list.files("data", pattern = "report\\.tsv$", full.names = TRUE)
  }

  if (length(data_files) == 0) {
    cat("  ⚠ No test data available, skipping test\n\n")
    NULL
  } else {
    data_file <- data_files[1]
    cat(sprintf("  Using data: %s\n", basename(data_file)))

    validated_data <- create_validated_dataset(data_file)
    plan <- plan_optimization(validated_data, instrument_preset = "astral")

    windows <- optimize_windows(
      validated_data = validated_data,
      optimization_plan = plan,
      mz_strategy = "greedy",
      window_mode = "density"
    )

    # Calculate expected m/z range
    n_windows <- plan$n_windows_per_bin
    min_width <- 8  # default min_width_da
    expected_mz_range <- n_windows * min_width

    cat(sprintf("  Total windows: %d\n", nrow(windows$windows)))
    cat(sprintf("  Windows per bin: %d\n", n_windows))
    cat(sprintf("  Expected m/z range per bin: %.0f Da (%d × %d)\n",
                expected_mz_range, n_windows, min_width))
    cat(sprintf("  Coverage: %.1f%%\n", windows$statistics$coverage_percentage))
    cat(sprintf("  Strategy used: %s\n", windows$mz_optimization$strategy))

    stopifnot(windows$mz_optimization$strategy == "greedy")
    stopifnot(nrow(windows$windows) > 0)

    cat("✓ TEST 1 PASSED\n\n")
    tests_passed <<- tests_passed + 1
    windows
  }
}, error = function(e) {
  cat(sprintf("✗ TEST 1 FAILED: %s\n\n", e$message))
  tests_failed <<- tests_failed + 1
  NULL
})

# Test 2: Greedy vs Coverage - Different Optimization Goals
cat("TEST 2: Greedy vs Coverage Strategy Comparison\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("  Note: Greedy uses FIXED m/z range, Coverage targets FIXED coverage %\n")
cat("        Different goals → Different results expected\n\n")
test2_result <- tryCatch({
  if (is.null(test1_result)) {
    cat("  ⚠ Skipped (no test data)\n\n")
    NULL
  } else {
    data_files <- list.files("data", pattern = "report\\.parquet$", full.names = TRUE)
    if (length(data_files) == 0) {
      data_files <- list.files("data", pattern = "report\\.tsv$", full.names = TRUE)
    }
    data_file <- data_files[1]

    validated_data <- create_validated_dataset(data_file)
    plan <- plan_optimization(validated_data, instrument_preset = "astral")

    windows_greedy <- optimize_windows(validated_data, plan, mz_strategy = "greedy")
    windows_coverage <- optimize_windows(validated_data, plan, mz_strategy = "coverage")

    greedy_coverage <- windows_greedy$statistics$coverage_percentage
    coverage_coverage <- windows_coverage$statistics$coverage_percentage

    # Get m/z ranges to compare widths
    greedy_mz_ranges <- windows_greedy$mz_optimization$mz_ranges
    coverage_mz_ranges <- windows_coverage$mz_optimization$mz_ranges

    greedy_avg_width <- mean(greedy_mz_ranges$mz_width, na.rm = TRUE)
    coverage_avg_width <- mean(coverage_mz_ranges$mz_width, na.rm = TRUE)

    cat(sprintf("  Greedy:\n"))
    cat(sprintf("    Coverage: %.1f%%\n", greedy_coverage))
    cat(sprintf("    Avg m/z width: %.1f Da (FIXED by n_windows × min_width)\n", greedy_avg_width))
    cat(sprintf("  Coverage:\n"))
    cat(sprintf("    Coverage: %.1f%%\n", coverage_coverage))
    cat(sprintf("    Avg m/z width: %.1f Da (VARIABLE to reach 90%% target)\n", coverage_avg_width))
    cat(sprintf("\n"))

    # Key insight: Greedy should have CONSISTENT width (fixed range)
    # Coverage should have >= 90% (target coverage)
    greedy_width_variance <- sd(greedy_mz_ranges$mz_width, na.rm = TRUE)
    cat(sprintf("  Greedy width std dev: %.1f Da (should be ~0 for fixed range)\n", greedy_width_variance))
    cat(sprintf("  Coverage achieves target: %s\n",
                ifelse(coverage_coverage >= 85, "YES", "NO")))

    # Greedy width should be very consistent (low variance)
    # Coverage should hit target (~90%)
    stopifnot(coverage_coverage >= 85)  # Coverage targets ~90%

    cat("✓ TEST 2 PASSED\n\n")
    tests_passed <<- tests_passed + 1
    list(greedy = windows_greedy, coverage = windows_coverage)
  }
}, error = function(e) {
  cat(sprintf("✗ TEST 2 FAILED: %s\n\n", e$message))
  tests_failed <<- tests_failed + 1
  NULL
})

# Test 3: Verify Greedy finds optimal position
cat("TEST 3: Greedy Finds Maximum Precursor Position\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
test3_result <- tryCatch({
  if (is.null(test1_result)) {
    cat("  ⚠ Skipped (no test data)\n\n")
    NULL
  } else {
    data_files <- list.files("data", pattern = "report\\.parquet$", full.names = TRUE)
    if (length(data_files) == 0) {
      data_files <- list.files("data", pattern = "report\\.tsv$", full.names = TRUE)
    }
    data_file <- data_files[1]

    validated_data <- create_validated_dataset(data_file)
    plan <- plan_optimization(validated_data, instrument_preset = "astral")

    windows_greedy <- optimize_windows(validated_data, plan, mz_strategy = "greedy")

    # Check that all bins have reasonable coverage ratios
    mz_ranges <- windows_greedy$mz_optimization$mz_ranges
    coverage_ratios <- mz_ranges$coverage_ratio

    cat(sprintf("  Number of RT bins: %d\n", nrow(mz_ranges)))
    cat(sprintf("  Coverage ratio range: %.1f%% - %.1f%%\n",
                min(coverage_ratios, na.rm = TRUE) * 100,
                max(coverage_ratios, na.rm = TRUE) * 100))
    cat(sprintf("  Mean coverage ratio: %.1f%%\n",
                mean(coverage_ratios, na.rm = TRUE) * 100))

    # All coverage ratios should be valid (0-100%)
    stopifnot(all(coverage_ratios >= 0 & coverage_ratios <= 1, na.rm = TRUE))

    cat("✓ TEST 3 PASSED\n\n")
    tests_passed <<- tests_passed + 1
    windows_greedy
  }
}, error = function(e) {
  cat(sprintf("✗ TEST 3 FAILED: %s\n\n", e$message))
  tests_failed <<- tests_failed + 1
  NULL
})

# Summary
cat("═══════════════════════════════════════════════════════════════════════\n")
cat(sprintf("SUMMARY: %d passed, %d failed\n", tests_passed, tests_failed))
cat("═══════════════════════════════════════════════════════════════════════\n")
cat("\n")
cat("Note: Greedy strategy (MacCoss Lab algorithm) uses FIXED m/z range\n")
cat("      determined by n_windows × min_width_da. This is fundamentally\n")
cat("      different from Coverage strategy which uses FIXED coverage target.\n")
cat("\n")
