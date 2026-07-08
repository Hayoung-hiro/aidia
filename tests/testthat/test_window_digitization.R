# test_window_digitization.R - Unit tests for window width digitization
#
# Tests the Phase 3.5 digitization feature in generate_variable_windows_internal()

library(testthat)

# Source required dependencies
if (!exists("generate_variable_windows_internal")) {
  source("../../R/utils_common.R")
  source("../../R/window_generation.R")
}
# ABSOLUTE_MIN_WIDTH_DA is defined in window_optimization.R and is loaded by
# devtools::test(); provide a fallback so this file also runs standalone.
if (!exists("ABSOLUTE_MIN_WIDTH_DA")) ABSOLUTE_MIN_WIDTH_DA <- 1.0

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

test_that("digitization yields integer widths regardless of grid_step (constraint model)", {
  # Intended change (SPEC 2026-07-08): width_grid_step is vestigial -- the
  # constraint model digitizes to INTEGER widths (1 Da grid). All grid_step
  # values now behave identically. The old 2.0-grid multiple assertion no
  # longer holds (e.g. a 3 Da window is not a multiple of 2).
  set.seed(321)
  precursor_mz <- runif(80, min = 300, max = 500)
  mz_min <- 300; mz_max <- 500
  n_windows <- 8; min_width_da <- 10; max_width_da <- 60

  gen <- function(step) suppressWarnings(generate_variable_windows_internal(
    precursor_mz = precursor_mz, mz_min = mz_min, mz_max = mz_max,
    n_windows = n_windows, min_width_da = min_width_da,
    max_width_da = max_width_da, width_grid_step = step))

  for (step in c(0.5, 1.0, 2.0)) {
    w <- gen(step)
    expect_equal(sum(w$window_width), mz_max - mz_min, tolerance = 1e-6)
    expect_equal(nrow(w), n_windows)
    expect_true(all(abs(w$window_width - round(w$window_width)) < 1e-9),
                info = "constraint model yields integer widths")
  }
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

# ===========================================================================
# SPEC 2026-07-08 constraint-model invariants + redistribute unit tests
# ===========================================================================

test_that("redistribute_integer_widths: exact split, clamp, NULL, sum/length", {
  # (a) exact division -> uniform integer widths
  w <- redistribute_integer_widths(W = 200, N = 10, raw_widths = rep(1, 10), floor_da = 5)
  expect_equal(length(w), 10)
  expect_equal(sum(w), 200)
  expect_true(all(w == 20))
  expect_true(is.integer(w))

  # (b) skewed shape forces clamp + redistribution; floor always held
  w <- redistribute_integer_widths(W = 100, N = 10,
                                   raw_widths = c(100, rep(1, 9)), floor_da = 5)
  expect_equal(sum(w), 100)
  expect_equal(length(w), 10)
  expect_true(all(w >= 5))
  expect_equal(which.max(w), 1L)            # largest shape -> widest window

  # (c) infeasible (N * floor > W) -> NULL (rule 4 signal)
  expect_null(redistribute_integer_widths(W = 15, N = 10,
                                          raw_widths = rep(1, 10), floor_da = 2))

  # (d) degenerate shape (zero sum / wrong length) -> uniform fallback, valid
  w0 <- redistribute_integer_widths(W = 100, N = 10, raw_widths = rep(0, 10), floor_da = 5)
  expect_equal(sum(w0), 100); expect_equal(length(w0), 10); expect_true(all(w0 >= 5))
  wl <- redistribute_integer_widths(W = 100, N = 10, raw_widths = rep(1, 7), floor_da = 5)
  expect_equal(sum(wl), 100); expect_equal(length(wl), 10); expect_true(all(wl >= 5))
})

test_that("SPEC A8: redistribute preserves strategy shape (correlation)", {
  raw <- c(10, 30, 20, 40, 15, 25)
  w <- redistribute_integer_widths(W = 100, N = 6, raw_widths = raw, floor_da = 2)
  expect_equal(sum(w), 100)
  expect_true(stats::cor(w, raw) >= 0.7)
})

test_that("SPEC A5: all widths >= absolute floor, no exception", {
  # Tight range + large N: widths pushed near the floor but never below absolute.
  set.seed(11)
  precursor_mz <- runif(300, min = 400, max = 430)
  windows <- suppressWarnings(suppressMessages(generate_variable_windows_internal(
    precursor_mz = precursor_mz, mz_min = 400, mz_max = 430,
    n_windows = 14, min_width_da = 2, max_width_da = 50, fz_offset = 0)))
  expect_equal(nrow(windows), 14)
  expect_true(all(windows$window_width >= ABSOLUTE_MIN_WIDTH_DA - 1e-9))
})

test_that("SPEC A6: count == N always (narrow bin edge-expands, no reduction)", {
  # W = 15 < N*min_width = 20: old code reduced count; new code edge-expands.
  set.seed(22)
  precursor_mz <- runif(200, min = 400, max = 415)
  windows <- suppressWarnings(suppressMessages(generate_variable_windows_internal(
    precursor_mz = precursor_mz, mz_min = 400, mz_max = 415,
    n_windows = 10, min_width_da = 2, max_width_da = 50, fz_offset = 0)))
  expect_equal(nrow(windows), 10)                       # A6: exactly N
  expect_true(min(windows$mz_start) <= floor(400))      # edge-expanded downward
  expect_true(max(windows$mz_end)  >= ceiling(415))     # covers original range
  expect_true(all(windows$window_width >= ABSOLUTE_MIN_WIDTH_DA - 1e-9))
})

test_that("SPEC A2/A3: coverage + contiguity (gap/overlap = 0)", {
  set.seed(33)
  precursor_mz <- runif(300, min = 400, max = 600)
  windows <- suppressWarnings(generate_variable_windows_internal(
    precursor_mz = precursor_mz, mz_min = 400, mz_max = 600,
    n_windows = 10, min_width_da = 5, max_width_da = 50, fz_offset = 0))
  # A2 coverage
  expect_true(min(windows$mz_start) <= floor(400))
  expect_true(max(windows$mz_end)  >= ceiling(600))
  # A3 contiguity: each start equals the previous end
  expect_equal(windows$mz_start[-1], windows$mz_end[-nrow(windows)])
  # A1 integer boundaries (fz off)
  expect_true(all(windows$mz_start == round(windows$mz_start)))
  expect_true(all(windows$mz_end == round(windows$mz_end)))
})

test_that("SPEC A4: fz deterministic + integer-width scaling", {
  set.seed(44)
  precursor_mz <- runif(300, min = 400, max = 600)
  args <- list(precursor_mz = precursor_mz, mz_min = 400, mz_max = 600,
               n_windows = 10, min_width_da = 5, max_width_da = 50)

  w_nofz <- suppressWarnings(do.call(generate_variable_windows_internal,
                                     c(args, fz_offset = 0)))
  w_fz1 <- suppressWarnings(do.call(generate_variable_windows_internal,
                                    c(args, fz_offset = 0.25)))
  w_fz2 <- suppressWarnings(do.call(generate_variable_windows_internal,
                                    c(args, fz_offset = 0.25)))

  # Determinism: identical inputs -> identical output
  expect_equal(w_fz1, w_fz2)

  # fz spacing == integer width * OPTIMAL_INCREMENT (within double-rounding)
  expect_equal(nrow(w_fz1), nrow(w_nofz))
  expect_true(all(abs(w_fz1$window_width -
                      w_nofz$window_width * OPTIMAL_INCREMENT) < 2e-4))
})

test_that("SPEC A7: rule-2 density partition fires (not fixed uniform)", {
  # Skewed density over a wide range -> adaptive (non-uniform) integer widths,
  # proving the fixed fallback (rule 4) did NOT fire.
  set.seed(55)
  precursor_mz <- c(runif(400, min = 400, max = 480),   # concentrated low
                    runif(60,  min = 480, max = 800))    # spread high
  windows <- suppressWarnings(suppressMessages(generate_variable_windows_internal(
    precursor_mz = precursor_mz, mz_min = 400, mz_max = 800,
    n_windows = 10, min_width_da = 5, max_width_da = 200, fz_offset = 0)))
  expect_equal(nrow(windows), 10)                        # count preserved
  expect_gt(length(unique(windows$window_width)), 1)     # not fixed uniform
})

cat("✅ test_window_digitization.R loaded - 15 tests defined\n")
