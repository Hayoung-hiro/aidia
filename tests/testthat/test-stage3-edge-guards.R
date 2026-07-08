# test-stage3-edge-guards.R
#
# Regression tests for PLAN-stage3-edge-guards: degenerate inputs (all-NA
# outlier bin, target = 0 coverage, non-RT.Apex fixed binning) must yield sane
# finite values instead of Inf/crash, and unworkable configs are rejected
# upfront (SPEC 2026-07-08 section 6). The single-precursor and all-identical
# outlier cases are already covered in test-audit-fixes.R and not duplicated.


# ---------------------------------------------------------------------------
# outlier: an all-NA (no finite value) bin must not leak Inf from
# min/max(numeric(0)); a bin with a single finite value among NAs still returns
# that finite value.
# ---------------------------------------------------------------------------

test_that("outlier strategy returns finite bounds when only one finite m/z remains", {
  bounds <- compute_mz_range_for_bin(
    outlier_config(), data.frame(Precursor.Mz = c(700.0, NA_real_))
  )
  expect_true(is.finite(bounds$mz_min) && is.finite(bounds$mz_max))
  expect_equal(bounds$mz_min, 700.0)
  expect_equal(bounds$mz_max, 700.0)
})

test_that("outlier strategy returns non-Inf bounds for an all-NA bin", {
  bounds <- compute_mz_range_for_bin(
    outlier_config(), data.frame(Precursor.Mz = c(NA_real_, NA_real_))
  )
  expect_false(isTRUE(is.infinite(bounds$mz_min)))
  expect_false(isTRUE(is.infinite(bounds$mz_max)))
})


# ---------------------------------------------------------------------------
# coverage: target_coverage = 0 gave n_target = 0, which made the
# narrowest-window search index mz_sorted[0] and return Inf. Clamp to >= 1.
# ---------------------------------------------------------------------------

test_that("coverage strategy tolerates target_coverage = 0 (narrowest)", {
  df <- data.frame(Precursor.Mz = c(500, 505, 510, 515, 520))
  expect_no_error(
    bounds <- compute_mz_range_for_bin(coverage_config(target = 0), df)
  )
  expect_true(is.finite(bounds$mz_min) && is.finite(bounds$mz_max))
  # n_target clamps to 1 -> narrowest single-precursor window (zero width).
  expect_equal(bounds$mz_min, bounds$mz_max)
})

test_that("coverage strategy tolerates target_coverage = 0 (centered)", {
  df <- data.frame(Precursor.Mz = c(500, 505, 510, 515, 520))
  expect_no_error(
    bounds <- compute_mz_range_for_bin(
      coverage_config(target = 0, mode = "centered"), df
    )
  )
  expect_true(is.finite(bounds$mz_min) && is.finite(bounds$mz_max))
})


# ---------------------------------------------------------------------------
# fixed RT binning: the dispatcher resolves an RT column (RT.Apex, else
# RT.Start) but the fixed path used to hardcode RT.Apex, silently breaking on
# data whose RT reference is a different column. It must honor rt_column.
# ---------------------------------------------------------------------------

test_that("fixed RT binning honors a non-RT.Apex rt_column", {
  # No RT.Apex column at all; the RT reference lives in RT.Start.
  df <- data.frame(
    RT.Start     = c(1, 2, 30, 31),
    Precursor.Mz = c(500, 510, 700, 710)
  )
  res <- perform_fixed_rt_binning_internal(
    df, rt_bin_width_min = 5, rt_column = "RT.Start"
  )
  expect_equal(res$n_bins, 2)
  expect_equal(res$stats$rt_start[1], 1)
  expect_equal(res$stats$rt_end[2], 31)
})

test_that("fixed RT binning still defaults to RT.Apex", {
  df <- data.frame(
    RT.Apex      = c(1, 2, 30, 31),
    Precursor.Mz = c(500, 510, 700, 710)
  )
  res <- perform_fixed_rt_binning_internal(df, rt_bin_width_min = 5)
  expect_equal(res$n_bins, 2)
})


# ---------------------------------------------------------------------------
# Config validation (SPEC section 6): reject unworkable settings upfront.
# Lightweight ValidatedData / OptimizationPlan stubs (cf. test-width-semantics-
# split.R) let us drive optimize_windows() without proprietary fixtures.
# ---------------------------------------------------------------------------

.edge_mock_validated <- function(seed = 1, n = 200) {
  set.seed(seed)
  vd <- list(data = data.frame(
    Precursor.Mz = runif(n, 400, 1000),
    RT.Apex      = runif(n, 0, 20),
    FWHM         = rep(4, n)
  ))
  class(vd) <- c("ValidatedData", "list")
  vd
}

.edge_mock_plan <- function(n_windows = 8) {
  plan <- list(
    window_count_per_bin    = n_windows,
    instrument              = list(preset = "test", cycle_mode = "sequential",
                                   ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    scan_time               = list(t_scan_ms = 50),
    required_cycle_time_sec = 2.0
  )
  class(plan) <- c("OptimizationPlan", "list")
  plan
}

test_that("optimize_windows rejects an instrument m/z range too small for N windows", {
  vd   <- .edge_mock_validated()
  plan <- .edge_mock_plan(n_windows = 8)
  expect_error(
    suppressWarnings(optimize_windows(
      validated_data    = vd,
      optimization_plan = plan,
      strategy_config   = greedy_config(),
      mz_range_min      = 400,
      mz_range_max      = 405            # span 5 Da < 8 windows * 1 Da floor
    )),
    "cannot fit"
  )
})

test_that("optimize_windows rejects min_width_da not below max_width_da", {
  vd   <- .edge_mock_validated()
  plan <- .edge_mock_plan(n_windows = 8)
  expect_error(
    suppressWarnings(optimize_windows(
      validated_data    = vd,
      optimization_plan = plan,
      strategy_config   = greedy_config(),
      min_width_da      = 80,
      max_width_da      = 80             # equal -> violates min < max
    )),
    "max_width_da"
  )
})

test_that("optimize_windows accepts a workable config (no upfront rejection)", {
  vd   <- .edge_mock_validated()
  plan <- .edge_mock_plan(n_windows = 8)
  invisible(capture.output(
    expect_no_error(
      res <- suppressWarnings(optimize_windows(
        validated_data    = vd,
        optimization_plan = plan,
        strategy_config   = greedy_config(),
        min_width_da      = 3,
        mz_range_min      = 400,
        mz_range_max      = 1200
      ))
    )
  ))
})
