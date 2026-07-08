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

test_that("greedy+density window boundaries are byte-identical (halving path)", {
  vd   <- .wss_mock_validated(123)
  plan <- .wss_mock_plan(8)
  invisible(capture.output(
    res <- suppressWarnings(optimize_windows(
      validated_data    = vd,
      optimization_plan = plan,
      strategy_config   = greedy_config(apply_smoothing = TRUE),
      window_mode       = "density",
      min_width_da      = 3
    ))
  ))
  expect_snapshot_value(.wss_fingerprint(res), style = "json2")
})

test_that("quantile+density window boundaries are byte-identical (else path)", {
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
  expect_snapshot_value(.wss_fingerprint(res), style = "json2")
})
