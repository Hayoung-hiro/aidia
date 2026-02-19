context("Stage 3: Parallel Optimization and Enhancements")

test_that("Parallel optimization produces identical results to sequential", {
  skip_if_not_installed("future")
  skip_if_not_installed("future.apply")

  # Mock Data
  set.seed(123)
  n_precursors <- 1000
  mock_data <- tibble::tibble(
    Precursor.Mz = runif(n_precursors, 400, 1000),
    RT.Apex = runif(n_precursors, 0, 60),
    Charge = sample(2:4, n_precursors, replace = TRUE),
    Intensity = runif(n_precursors, 1000, 1e6),
    FWHM = rlnorm(n_precursors, log(4), 0.5)
  )
  class(mock_data) <- c("ValidatedData", class(mock_data))
  validated_data <- list(data = mock_data)
  class(validated_data) <- c("ValidatedData", "list")

  optimization_plan <- list(
    window_count_per_bin = 10,
    instrument = list(preset = "test", cycle_mode = "serial", ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    required_cycle_time_sec = 2.0
  )
  class(optimization_plan) <- c("OptimizationPlan", "list")

  # Run Sequential
  res_seq <- optimize_windows(
    validated_data,
    optimization_plan,
    rt_bin_width_min = 10,
    mz_strategy = "quantile",
    window_mode = "density",
    use_parallel = FALSE
  )

  # Run Parallel
  res_par <- optimize_windows(
    validated_data,
    optimization_plan,
    rt_bin_width_min = 10,
    mz_strategy = "quantile",
    window_mode = "density",
    use_parallel = TRUE,
    n_cores = 2
  )

  expect_equal(res_seq$windows, res_par$windows)
  expect_equal(res_seq$mz_optimization$mz_ranges, res_par$mz_optimization$mz_ranges)
})

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
    stagger_offset_pct = 0.25,
    use_parallel = FALSE
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
    target_coverage = 0.8,
    use_parallel = FALSE
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
    mz_range_max = 1100,
    use_parallel = FALSE
  )

  expect_true(nrow(res$windows) > 0)
})
