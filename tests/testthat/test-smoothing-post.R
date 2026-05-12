# test-smoothing-post.R
#
# Verify apply_smoothing() S3 post-processor:
#   - greedy/quantile/outlier perform actual smoothing (when flag enabled)
#   - kde/coverage are no-op (return mz_ranges unchanged)
#   - method dispatch is wired correctly


# Helper: build a synthetic mz_ranges data frame with deliberately jagged
# boundaries that smoothing would visibly affect.
make_jagged_mz_ranges <- function(n_bins = 10) {
  set.seed(123)
  data.frame(
    rt_segment_id = 1:n_bins,
    rt_start = seq(0, by = 5, length.out = n_bins),
    rt_end = seq(0, by = 5, length.out = n_bins) + 5,
    mz_min = 400 + runif(n_bins, -20, 20),       # noisy
    mz_max = 800 + runif(n_bins, -20, 20),       # noisy
    mz_width = NA_real_,
    n_precursors_covered = rep(100, n_bins),
    coverage_ratio = rep(0.9, n_bins)
  ) |>
    transform(mz_width = mz_max - mz_min)
}

make_precursor_data <- function(n = 500) {
  data.frame(
    Precursor.Mz = runif(n, 400, 1000),
    RT.Apex = runif(n, 0, 50),
    rt_group = sample(1:10, n, replace = TRUE)
  )
}


# ---------------------------------------------------------------------------
# Method registration
# ---------------------------------------------------------------------------

test_that("apply_smoothing has methods for all 5 strategy_config subclasses", {
  for (cls in c("greedy_config", "kde_config", "quantile_config",
                "coverage_config", "outlier_config")) {
    m <- utils::getS3method("apply_smoothing", cls, optional = TRUE)
    expect_true(!is.null(m), info = sprintf("apply_smoothing.%s missing", cls))
  }
})


# ---------------------------------------------------------------------------
# No-op methods (kde, coverage)
# ---------------------------------------------------------------------------

test_that("apply_smoothing.kde_config is a no-op", {
  mz <- make_jagged_mz_ranges(10)
  pd <- make_precursor_data()
  result <- apply_smoothing(kde_config(), mz, pd)
  expect_identical(result, mz)
})

test_that("apply_smoothing.coverage_config is a no-op", {
  mz <- make_jagged_mz_ranges(10)
  pd <- make_precursor_data()
  result <- apply_smoothing(coverage_config(), mz, pd)
  expect_identical(result, mz)
})


# ---------------------------------------------------------------------------
# Active methods: greedy / quantile / outlier
# ---------------------------------------------------------------------------

test_that("apply_smoothing.greedy_config smooths boundaries when enabled", {
  mz <- make_jagged_mz_ranges(10)
  pd <- make_precursor_data()
  cfg <- greedy_config(apply_smoothing = TRUE)

  invisible(capture.output(
    smoothed <- apply_smoothing(cfg, mz, pd,
                                 n_windows_per_bin = 5, min_width_da = 2)
  ))

  # Smoothing should reduce variance of boundary positions across bins
  expect_lt(sd(smoothed$mz_min), sd(mz$mz_min))
  expect_lt(sd(smoothed$mz_max), sd(mz$mz_max))
})

test_that("apply_smoothing.greedy_config respects apply_smoothing=FALSE flag", {
  mz <- make_jagged_mz_ranges(10)
  pd <- make_precursor_data()
  cfg <- greedy_config(apply_smoothing = FALSE)
  result <- apply_smoothing(cfg, mz, pd, n_windows_per_bin = 5, min_width_da = 2)
  expect_identical(result, mz)
})

test_that("apply_smoothing.quantile_config smooths when flag is TRUE", {
  mz <- make_jagged_mz_ranges(10)
  pd <- make_precursor_data()
  cfg <- quantile_config(apply_smoothing = TRUE)

  invisible(capture.output(
    smoothed <- apply_smoothing(cfg, mz, pd)
  ))
  expect_lt(sd(smoothed$mz_min), sd(mz$mz_min))
})

test_that("apply_smoothing.quantile_config is no-op when flag is FALSE", {
  mz <- make_jagged_mz_ranges(10)
  pd <- make_precursor_data()
  cfg <- quantile_config(apply_smoothing = FALSE)
  result <- apply_smoothing(cfg, mz, pd)
  expect_identical(result, mz)
})

test_that("apply_smoothing.outlier_config smooths when flag is TRUE", {
  mz <- make_jagged_mz_ranges(10)
  pd <- make_precursor_data()
  cfg <- outlier_config(apply_smoothing = TRUE)

  invisible(capture.output(
    smoothed <- apply_smoothing(cfg, mz, pd)
  ))
  expect_lt(sd(smoothed$mz_min), sd(mz$mz_min))
})


# ---------------------------------------------------------------------------
# Greedy width invariant: smoothing must not violate fixed-width constraint
# ---------------------------------------------------------------------------

test_that("greedy smoothing preserves the fixed mz_range_per_cycle width", {
  mz <- make_jagged_mz_ranges(10)
  pd <- make_precursor_data()
  cfg <- greedy_config(apply_smoothing = TRUE)
  n_windows <- 5
  min_w <- 2
  expected_range <- n_windows * min_w  # 10 Da

  # Override mz_ranges to have ~ expected width before smoothing
  mz$mz_max <- mz$mz_min + expected_range + rnorm(10, sd = 0.1)
  mz$mz_width <- mz$mz_max - mz$mz_min

  invisible(capture.output(
    smoothed <- apply_smoothing(cfg, mz, pd,
                                 n_windows_per_bin = n_windows,
                                 min_width_da = min_w)
  ))

  # All widths must remain >= 95% of expected_range (allow ~ epsilon)
  expect_true(all(smoothed$mz_width >= expected_range * 0.94),
              info = "greedy width constraint violated after smoothing")
})


# ---------------------------------------------------------------------------
# Few-bin guard
# ---------------------------------------------------------------------------

test_that("apply_smoothing skips when fewer than 3 RT bins", {
  mz <- make_jagged_mz_ranges(2)
  pd <- make_precursor_data()

  for (name in c("greedy", "quantile", "outlier")) {
    cfg <- do.call(paste0(name, "_config"), list(apply_smoothing = TRUE))
    invisible(capture.output(
      result <- apply_smoothing(cfg, mz, pd,
                                 n_windows_per_bin = 5, min_width_da = 2)
    ))
    expect_identical(result$mz_min, mz$mz_min,
                     info = sprintf("strategy %s should skip with < 3 bins", name))
  }
})
