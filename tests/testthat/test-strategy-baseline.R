# test-strategy-baseline.R
#
# Regression test against pre-refactor baseline outputs (v0.4.1 split).
# Baseline was captured on real 30min_report.parquet data with all 5
# strategies; this test re-runs each strategy through the new S3 dispatch
# path and asserts identical (or near-identical) results.
#
# Baseline file: tests/testthat/fixtures/strategy_baseline.rds
# Skipped automatically when the source parquet is not available
# (e.g. CI environments without the proprietary fixture).


.baseline_inputs_available <- function() {
  parquet_path <- "../../data/30min_report.parquet"
  baseline_path <- testthat::test_path("fixtures", "strategy_baseline.rds")
  file.exists(parquet_path) && file.exists(baseline_path)
}


test_that("all 5 strategies match pre-refactor baseline within tolerance", {
  skip_if_not(.baseline_inputs_available(),
              "Skipping: data/30min_report.parquet or baseline RDS missing")

  baseline <- readRDS(testthat::test_path("fixtures", "strategy_baseline.rds"))

  # Stage 1+2 setup (shared)
  invisible(capture.output({
    validated <- create_validated_dataset(
      proteome_file = "../../data/30min_report.parquet",
      enable_replicate_consensus = FALSE
    )
    plan <- plan_optimization(
      validated_data = validated,
      instrument_preset = "astral",
      target_dppp = 7.0,
      target_satisfaction = 0.70
    )
  }))

  strategies <- list(
    greedy   = greedy_config(),
    kde      = kde_config(),
    quantile = quantile_config(),
    coverage = coverage_config(),
    outlier  = outlier_config()
  )

  for (name in names(strategies)) {
    invisible(capture.output(
      res <- optimize_windows(
        validated_data = validated,
        optimization_plan = plan,
        strategy_config = strategies[[name]],
        window_mode = "density"
      )
    ))

    b <- baseline[[name]]

    # Discrete: must match exactly
    expect_equal(nrow(res$windows), b$n_windows,
                 info = sprintf("strategy %s: n_windows", name))

    # Continuous: small floating-point drift tolerated
    expect_equal(res$statistics$coverage_percentage,
                 b$coverage_pct,
                 tolerance = 0.05,
                 info = sprintf("strategy %s: coverage_percentage", name))
    expect_equal(res$statistics$window_width_mean,
                 b$window_width_mean,
                 tolerance = 0.05,
                 info = sprintf("strategy %s: mean width", name))
  }
})
