# test-width-semantics-split.R
#
# Regression guard for PLAN-width-semantics-split. The width-semantics rename
# (ABSOLUTE_MIN_WIDTH_DA / isolation_width_floor_da / greedy_cycle_range_da /
# generation_min_width_da) MUST be behavior-preserving. These snapshot tests
# pin the generated window boundaries.
#
# PROTOCOL (before/after): record the snapshot on the PRE-rename code
# (devtools::test(filter = "width-semantics-split")), THEN apply the rename and
# re-run. A passing snapshot proves the window output is unchanged. Recording it
# only after the rename captures the new baseline and cannot detect drift.
#
# NOTE (digitization flagship, PLAN-stage3-digitization-compliance): that plan
# INTENTIONALLY reworks the density-path window generation, so the snapshots
# guard the post-digitization baseline against future drift; the rename
# byte-identity they originally proved is preserved in git history.
#
# NOTE (cross-platform reproducibility): the quantile path runs precursor
# densities through Whittaker-Henderson smoothing, whose BLAS/LAPACK results
# vary by CPU microarchitecture (they differ even between CI runs on the same
# OS). The integer width digitization amplifies that sub-ULP jitter into +/-1 Da
# reassignments between windows, so byte-identical quantile boundaries are not
# reproducible in CI. Both tests therefore pin the platform-stable invariants
# the SPEC v2 constraint model guarantees (uniform N, contiguous tiling, width
# floor) instead of exact boundaries.
#
# NOTE (degenerate-bin fix): the greedy test was an exact byte-identity snapshot
# until the H6 uniform-N fix routed the sparse early guard through
# digitize_windows_to_n() (was: the max-width-capping fixed generator). A greedy
# bin spans only N*min_width Da, so its precursor count sits near the 2N sparse
# threshold and some bins take the guard -- the fix changes their widths (count
# stays exactly N). The snapshot baseline is preserved in git history; the test
# now asserts the invariants the fix guarantees.

.wss_mock_validated <- function(seed, n = 400) {
  set.seed(seed)
  vd <- list(data = tibble::tibble(
    Precursor.Mz = runif(n, 400, 1000),
    RT.Apex      = runif(n, 0, 20),
    FWHM         = rep(4, n)
  ))
  class(vd) <- c("ValidatedData", "list")
  vd
}

.wss_mock_plan <- function(n_windows = 8) {
  plan <- list(
    window_count_per_bin   = n_windows,
    instrument             = list(preset = "test", cycle_mode = "sequential",
                                  ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    scan_time              = list(t_scan_ms = 50),
    required_cycle_time_sec = 2.0
  )
  class(plan) <- c("OptimizationPlan", "list")
  plan
}

.wss_fingerprint <- function(res) {
  w <- res$windows
  cols <- intersect(c("rt_segment_id", "mz_start", "mz_end", "window_width"),
                    colnames(w))
  w <- w[, cols, drop = FALSE]
  num <- vapply(w, is.numeric, logical(1))
  w[num] <- lapply(w[num], function(x) round(x, 9))
  w
}

test_that("greedy+density window layout matches SPEC v2 invariants (halving path)", {
  # Previously a byte-identity snapshot. The degenerate-bin fix (route the sparse
  # early guard through digitize_windows_to_n() instead of the max-width-capping
  # fixed generator) changes the widths of greedy's borderline-sparse bins -- a
  # greedy bin spans only N*min_width Da, so its precursor count sits near the
  # 2N sparse threshold and some bins take the guard. The window COUNT is
  # unchanged (still exactly N per bin), so this now pins the platform-stable
  # SPEC v2 invariants (uniform N, contiguous tiling, width floor) the fix
  # guarantees, matching the quantile test's approach. See file header.
  n_windows <- 8L
  min_w     <- 3
  vd   <- .wss_mock_validated(123)
  plan <- .wss_mock_plan(n_windows)
  invisible(capture.output(
    res <- suppressWarnings(optimize_windows(
      validated_data    = vd,
      optimization_plan = plan,
      strategy_config   = greedy_config(apply_smoothing = TRUE),
      window_mode       = "density",
      min_width_da      = min_w
    ))
  ))
  w <- .wss_fingerprint(res)

  by_bin <- split(w, w$rt_segment_id)
  # H6 uniform-N: every RT bin has exactly N windows (the fix's core guarantee).
  expect_true(all(vapply(by_bin, nrow, integer(1)) == n_windows),
              info = "each RT bin must hold exactly N windows")

  for (b in by_bin) {
    b <- b[order(b$mz_start), , drop = FALSE]
    # H3 contiguous tiling within the bin: no gaps / overlaps.
    expect_equal(b$mz_start[-1], b$mz_end[-nrow(b)], tolerance = 1e-6)
    # H5 hard floor: greedy sizes each bin to N*min_width, so widths hold >= min.
    expect_true(all(b$window_width >= min_w - 1e-6))
  }
})

test_that("quantile+density window layout matches SPEC v2 invariants (else path)", {
  vd   <- .wss_mock_validated(456)
  plan <- .wss_mock_plan(6)
  invisible(capture.output(
    res <- suppressWarnings(optimize_windows(
      validated_data    = vd,
      optimization_plan = plan,
      strategy_config   = quantile_config(),
      window_mode       = "density",
      min_width_da      = 2
    ))
  ))
  w <- .wss_fingerprint(res)

  # Uniform N: 4 RT bins x 6 windows each (SPEC v2 H6).
  expect_equal(nrow(w), 24L)
  by_bin <- split(w, w$rt_segment_id)
  expect_equal(length(by_bin), 4L)
  expect_true(all(vapply(by_bin, nrow, integer(1)) == 6L))

  for (b in by_bin) {
    b <- b[order(b$mz_start), , drop = FALSE]
    # Contiguous tiling within the bin: no gaps / overlaps.
    expect_equal(b$mz_start[-1], b$mz_end[-nrow(b)], tolerance = 1e-6)
    # Width floor honored (min_width_da).
    expect_true(all(b$window_width >= 2 - 1e-6))
  }

  # The integer-width multiset per bin is deterministic even though which window
  # carries each +/-1 Da leftover is not (see file header). Verified stable
  # across the committed baseline and independent macOS/Linux CI runners.
  int_widths <- lapply(by_bin, function(b) sort(as.integer(round(b$window_width))))
  expect_equal(int_widths[["1"]], c(83L, 84L, 84L, 84L, 84L, 84L))
  expect_equal(int_widths[["2"]], c(85L, 86L, 86L, 86L, 86L, 86L))
  expect_equal(int_widths[["3"]], c(87L, 87L, 88L, 88L, 88L, 88L))
  expect_equal(int_widths[["4"]], c(89L, 89L, 90L, 90L, 90L, 90L))
})
