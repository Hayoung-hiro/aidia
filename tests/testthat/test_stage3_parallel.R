context("Stage 3: Window Modes and Edge Cases")

test_that("Staggered mode respects offset", {
  # Mock Data
  validated_data <- list(data = tibble::tibble(
    Precursor.Mz = runif(100, 400, 1000),
    RT.Apex = runif(100, 0, 20),
    FWHM = rep(4, 100)
  ))
  class(validated_data) <- c("ValidatedData", "list")
  optimization_plan <- list(
    window_count_per_bin = 5,
    instrument = list(preset = "test", cycle_mode = "serial", ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    required_cycle_time_sec = 2.0
  )
  class(optimization_plan) <- c("OptimizationPlan", "list")

  res <- optimize_windows(
    validated_data,
    optimization_plan,
    rt_bin_width_min = 5,
    window_mode = "staggered",
    stagger_offset_pct = 0.25
  )

  expect_true(nrow(res$windows) > 0)
})

test_that("Centered coverage strategy runs", {
  # Mock Data
  set.seed(42)
  validated_data <- list(data = tibble::tibble(
    Precursor.Mz = rnorm(1000, 600, 50),
    RT.Apex = runif(1000, 0, 20),
    FWHM = rep(4, 1000)
  ))
  class(validated_data) <- c("ValidatedData", "list")
  optimization_plan <- list(
    window_count_per_bin = 5,
    instrument = list(preset = "test", cycle_mode = "serial", ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    required_cycle_time_sec = 2.0
  )
  class(optimization_plan) <- c("OptimizationPlan", "list")

  res <- optimize_windows(
    validated_data,
    optimization_plan,
    mz_strategy = "coverage",
    coverage_mode = "centered",
    target_coverage = 0.8
  )

  expect_true(nrow(res$windows) > 0)
})

test_that("mz_range_min/mz_range_max used for empty bins", {
  # Create data with RT bins that will have empty bins
  set.seed(99)
  validated_data <- list(data = tibble::tibble(
    Precursor.Mz = runif(50, 500, 900),
    RT.Apex = c(runif(50, 5, 10)),  # All in one RT region
    FWHM = rep(4, 50)
  ))
  class(validated_data) <- c("ValidatedData", "list")
  optimization_plan <- list(
    window_count_per_bin = 5,
    instrument = list(preset = "test", cycle_mode = "serial", ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    required_cycle_time_sec = 2.0
  )
  class(optimization_plan) <- c("OptimizationPlan", "list")

  res <- optimize_windows(
    validated_data,
    optimization_plan,
    mz_range_min = 350,
    mz_range_max = 1100
  )

  expect_true(nrow(res$windows) > 0)
})
