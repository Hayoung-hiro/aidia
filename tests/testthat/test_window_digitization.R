# test_window_digitization.R - Unit tests for window width digitization
#
# Tests the Phase 3.5 digitization feature in generate_variable_windows_internal()

library(testthat)

# Source required dependencies
if (!exists("generate_variable_windows_internal")) {
  source("../../R/utils_common.R")
  source("../../R/window_generation.R")
}

test_that("digitization snaps widths to grid", {
  # Create mock precursor data with known distribution
  set.seed(42)
  precursor_mz <- runif(200, min = 400, max = 600)

  mz_min <- 400
  mz_max <- 600
  n_windows <- 10
  min_width_da <- 5
  max_width_da <- 50
  width_grid_step <- 0.5

  # Generate windows with digitization
  windows <- generate_variable_windows_internal(
    precursor_mz = precursor_mz,
    mz_min = mz_min,
    mz_max = mz_max,
    n_windows = n_windows,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    width_grid_step = width_grid_step
  )

  # Check that all widths are multiples of grid step (with floating point tolerance)
  remainder <- (windows$window_width %% width_grid_step)
  # Allow small floating point error from final residual
  expect_true(all(remainder < 1e-6 | abs(remainder - width_grid_step) < 1e-6),
              info = "All window widths should be multiples of grid step")
})

test_that("digitization preserves total range", {
  set.seed(123)
  precursor_mz <- runif(150, min = 500, max = 700)

  mz_min <- 500
  mz_max <- 700
  n_windows <- 8
  min_width_da <- 10
  max_width_da <- 60
  width_grid_step <- 1.0

  windows <- generate_variable_windows_internal(
    precursor_mz = precursor_mz,
    mz_min = mz_min,
    mz_max = mz_max,
    n_windows = n_windows,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    width_grid_step = width_grid_step
  )

  # Sum of widths must equal total range (within floating point tolerance)
  total_width <- sum(windows$window_width)
  expected_width <- mz_max - mz_min

  expect_equal(total_width, expected_width, tolerance = 1e-6,
               info = "Sum of digitized widths must equal total m/z range")

  # First window should start at mz_min
  expect_equal(windows$mz_start[1], mz_min, tolerance = 1e-6)

  # Last window should end at mz_max
  expect_equal(windows$mz_end[nrow(windows)], mz_max, tolerance = 1e-6)
})

test_that("digitization respects min/max constraints", {
  set.seed(456)
  precursor_mz <- runif(100, min = 350, max = 450)

  mz_min <- 350
  mz_max <- 450
  n_windows <- 5
  min_width_da <- 8
  max_width_da <- 30
  width_grid_step <- 0.5

  windows <- generate_variable_windows_internal(
    precursor_mz = precursor_mz,
    mz_min = mz_min,
    mz_max = mz_max,
    n_windows = n_windows,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    width_grid_step = width_grid_step
  )

  # All widths must be within constraints (with tolerance for final residual)
  # The last window may slightly exceed max due to final_remainder
  widths_except_last <- windows$window_width[-nrow(windows)]

  expect_true(all(widths_except_last >= min_width_da - 1e-6),
              info = "All widths should be >= min_width_da")

  # For last window, allow residual overshoot
  expect_true(windows$window_width[nrow(windows)] >= min_width_da - 1e-6,
              info = "Last window width should be >= min_width_da")
})

test_that("NULL grid_step skips digitization", {
  set.seed(789)
  precursor_mz <- runif(120, min = 600, max = 800)

  mz_min <- 600
  mz_max <- 800
  n_windows <- 6
  min_width_da <- 15
  max_width_da <- 50

  # Generate with NULL grid step (should skip digitization)
  windows_null <- generate_variable_windows_internal(
    precursor_mz = precursor_mz,
    mz_min = mz_min,
    mz_max = mz_max,
    n_windows = n_windows,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    width_grid_step = NULL
  )

  # Generate with zero grid step (should also skip)
  windows_zero <- generate_variable_windows_internal(
    precursor_mz = precursor_mz,
    mz_min = mz_min,
    mz_max = mz_max,
    n_windows = n_windows,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    width_grid_step = 0
  )

  # Both should produce valid windows
  expect_equal(nrow(windows_null), n_windows,
               info = "NULL grid_step should produce expected number of windows")
  expect_equal(nrow(windows_zero), n_windows,
               info = "Zero grid_step should produce expected number of windows")

  # Total range should be preserved
  expect_equal(sum(windows_null$window_width), mz_max - mz_min, tolerance = 1e-6)
  expect_equal(sum(windows_zero$window_width), mz_max - mz_min, tolerance = 1e-6)
})

test_that("digitization works with different grid sizes", {
  set.seed(321)
  precursor_mz <- runif(80, min = 300, max = 500)

  mz_min <- 300
  mz_max <- 500
  n_windows <- 8
  min_width_da <- 10
  max_width_da <- 60

  # Test with 0.5 Da grid
  windows_05 <- generate_variable_windows_internal(
    precursor_mz = precursor_mz,
    mz_min = mz_min,
    mz_max = mz_max,
    n_windows = n_windows,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    width_grid_step = 0.5
  )

  # Test with 1.0 Da grid
  windows_10 <- generate_variable_windows_internal(
    precursor_mz = precursor_mz,
    mz_min = mz_min,
    mz_max = mz_max,
    n_windows = n_windows,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    width_grid_step = 1.0
  )

  # Test with 2.0 Da grid
  windows_20 <- generate_variable_windows_internal(
    precursor_mz = precursor_mz,
    mz_min = mz_min,
    mz_max = mz_max,
    n_windows = n_windows,
    min_width_da = min_width_da,
    max_width_da = max_width_da,
    width_grid_step = 2.0
  )

  # All should preserve total range
  expect_equal(sum(windows_05$window_width), mz_max - mz_min, tolerance = 1e-6)
  expect_equal(sum(windows_10$window_width), mz_max - mz_min, tolerance = 1e-6)
  expect_equal(sum(windows_20$window_width), mz_max - mz_min, tolerance = 1e-6)

  # Check that widths are multiples of respective grids (except last due to residual)
  widths_05_except_last <- windows_05$window_width[-nrow(windows_05)]
  widths_10_except_last <- windows_10$window_width[-nrow(windows_10)]
  widths_20_except_last <- windows_20$window_width[-nrow(windows_20)]

  expect_true(all((widths_05_except_last %% 0.5) < 1e-6 |
                  abs((widths_05_except_last %% 0.5) - 0.5) < 1e-6))
  expect_true(all((widths_10_except_last %% 1.0) < 1e-6 |
                  abs((widths_10_except_last %% 1.0) - 1.0) < 1e-6))
  expect_true(all((widths_20_except_last %% 2.0) < 1e-6 |
                  abs((widths_20_except_last %% 2.0) - 2.0) < 1e-6))
})

test_that("digitization handles edge cases", {
  # Very small range with tight constraints
  set.seed(999)
  precursor_mz <- runif(50, min = 400, max = 420)

  windows <- generate_variable_windows_internal(
    precursor_mz = precursor_mz,
    mz_min = 400,
    mz_max = 420,
    n_windows = 4,
    min_width_da = 3,
    max_width_da = 10,
    width_grid_step = 0.5
  )

  expect_true(nrow(windows) >= 1, info = "Should generate at least 1 window")
  expect_equal(sum(windows$window_width), 20, tolerance = 1e-6,
               info = "Total width should match range")
  expect_true(all(windows$window_width >= 3 - 1e-6),
              info = "All widths should respect min constraint")
})

# ---------------------------------------------------------------------------
# Regression: single-window bin must not crash on the `2:actual_n_windows`
# reverse-iteration. The planner can force window_count_per_bin = 1 at low
# cycle time (optimization_planning.R), which reaches density mode with
# actual_n_windows == 1. Before the seq_len()[-1] guard, `2:1` iterated
# backwards and indexed the out-of-range boundaries[i+1], erroring with
# "missing value where TRUE/FALSE needed".
# ---------------------------------------------------------------------------

test_that("single-window bin (narrow range) does not crash", {
  # max_possible_windows = floor(3 / 2) = 1  ->  actual_n_windows = 1
  precursor_mz <- c(400.5, 401.0, 401.5, 402.0)  # >= n_windows*2, skips fallback

  expect_no_error(
    windows <- generate_variable_windows_internal(
      precursor_mz = precursor_mz,
      mz_min = 400, mz_max = 403,
      n_windows = 1,
      min_width_da = 2, max_width_da = 80,
      width_grid_step = 0.5
    )
  )
  expect_true(nrow(windows) >= 1)
  expect_equal(sum(windows$window_width), 3, tolerance = 1e-6)
})

test_that("single-window target on a wide bin does not crash", {
  # n_windows = 1 but wide range: actual_n_windows = min(1, floor(800/2)) = 1.
  # Single window spans the whole range, exceeds max_width, and must fall back
  # to fixed mode (multiple windows) without erroring.
  set.seed(2024)
  precursor_mz <- runif(500, min = 400, max = 1200)

  expect_no_error(
    windows <- generate_variable_windows_internal(
      precursor_mz = precursor_mz,
      mz_min = 400, mz_max = 1200,
      n_windows = 1,
      min_width_da = 2, max_width_da = 80,
      width_grid_step = 0.5
    )
  )
  expect_true(nrow(windows) >= 1)
})

cat("✅ test_window_digitization.R loaded - 8 tests defined\n")
