# test-strategy-dispatch.R
#
# Verify the S3 dispatch wiring introduced in v0.4.1:
#   - Each *_config() constructor stamps the correct class hierarchy
#   - optimize_mz_ranges() dispatches to the right method (direct or inherited)
#   - GLOBAL strategies (greedy, kde) override the top-level method
#   - LOCAL strategies (quantile, coverage, outlier) inherit per-bin iteration


# ---------------------------------------------------------------------------
# Class hierarchy
# ---------------------------------------------------------------------------

test_that("greedy_config has GLOBAL hierarchy", {
  cfg <- greedy_config()
  expect_s3_class(cfg, "greedy_config")
  expect_s3_class(cfg, "global_strategy_config")
  expect_s3_class(cfg, "strategy_config")
  expect_false(inherits(cfg, "local_strategy_config"))
})

test_that("kde_config has GLOBAL hierarchy", {
  cfg <- kde_config()
  expect_s3_class(cfg, "kde_config")
  expect_s3_class(cfg, "global_strategy_config")
  expect_s3_class(cfg, "strategy_config")
  expect_false(inherits(cfg, "local_strategy_config"))
})

test_that("quantile_config has LOCAL hierarchy", {
  cfg <- quantile_config()
  expect_s3_class(cfg, "quantile_config")
  expect_s3_class(cfg, "local_strategy_config")
  expect_s3_class(cfg, "strategy_config")
  expect_false(inherits(cfg, "global_strategy_config"))
})

test_that("coverage_config has LOCAL hierarchy", {
  cfg <- coverage_config()
  expect_s3_class(cfg, "coverage_config")
  expect_s3_class(cfg, "local_strategy_config")
  expect_s3_class(cfg, "strategy_config")
})

test_that("outlier_config has LOCAL hierarchy", {
  cfg <- outlier_config()
  expect_s3_class(cfg, "outlier_config")
  expect_s3_class(cfg, "local_strategy_config")
  expect_s3_class(cfg, "strategy_config")
})


# ---------------------------------------------------------------------------
# Method dispatch resolution
# ---------------------------------------------------------------------------

test_that("optimize_mz_ranges dispatches greedy to its own method", {
  m <- utils::getS3method("optimize_mz_ranges", "greedy_config", optional = TRUE)
  expect_true(!is.null(m))
})

test_that("optimize_mz_ranges dispatches kde to its own method", {
  m <- utils::getS3method("optimize_mz_ranges", "kde_config", optional = TRUE)
  expect_true(!is.null(m))
})

test_that("optimize_mz_ranges does NOT define per-strategy methods for LOCAL configs", {
  # LOCAL strategies should inherit via local_strategy_config parent
  for (cls in c("quantile_config", "coverage_config", "outlier_config")) {
    m <- utils::getS3method("optimize_mz_ranges", cls, optional = TRUE)
    expect_null(m, info = sprintf("class '%s' should inherit, not override", cls))
  }
  # Parent method must exist
  parent <- utils::getS3method("optimize_mz_ranges", "local_strategy_config", optional = TRUE)
  expect_true(!is.null(parent))
})

test_that("compute_mz_range_for_bin has methods for all 3 LOCAL configs", {
  for (cls in c("quantile_config", "coverage_config", "outlier_config")) {
    m <- utils::getS3method("compute_mz_range_for_bin", cls, optional = TRUE)
    expect_true(!is.null(m), info = sprintf("method for '%s' missing", cls))
  }
})


# ---------------------------------------------------------------------------
# Functional dispatch (smoke: minimal synthetic data)
# ---------------------------------------------------------------------------

test_that("optimize_mz_ranges produces a valid result for each strategy", {
  # Minimal synthetic data: 50 precursors across 2 RT bins
  set.seed(42)
  precursor_data <- data.frame(
    Precursor.Mz = runif(50, 400, 1200),
    RT.Apex = c(rep(10, 25), rep(20, 25)),
    rt_group = c(rep(1, 25), rep(2, 25))
  )
  rt_stats <- data.frame(
    rt_segment_id = 1:2,
    rt_start = c(7.5, 17.5),
    rt_end = c(12.5, 22.5),
    n_precursors = c(25, 25)
  )

  for (name in c("greedy", "kde", "quantile", "coverage", "outlier")) {
    cfg <- do.call(paste0(name, "_config"), list())
    invisible(capture.output({
      result <- optimize_mz_ranges(
        cfg, precursor_data, rt_stats,
        n_windows_per_bin = 5, min_width_da = 2
      )
    }))
    label <- sprintf("[strategy: %s]", name)
    expect_s3_class(result, "data.frame")
    expect_equal(nrow(result), 2L, info = label)
    expect_true(all(c("mz_min", "mz_max", "mz_width", "coverage_ratio") %in% names(result)),
                info = label)
    expect_true(all(result$mz_max > result$mz_min), info = label)
  }
})

test_that("optimize_mz_ranges.default errors on non-strategy_config input", {
  expect_error(
    optimize_mz_ranges(list(some = "thing"), data.frame(), data.frame()),
    "strategy_config"
  )
})
