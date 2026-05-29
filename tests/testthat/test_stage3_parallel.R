context("Stage 3: Window Modes and Edge Cases")

test_that("Staggered mode respects offset and boundary-array integrity", {
  # Mock Data
  set.seed(123)
  validated_data <- list(data = tibble::tibble(
    Precursor.Mz = runif(100, 400, 1000),
    RT.Apex = runif(100, 0, 20),
    FWHM = rep(4, 100)
  ))
  class(validated_data) <- c("ValidatedData", "list")
  optimization_plan <- list(
    window_count_per_bin = 5,
    instrument = list(preset = "test", cycle_mode = "sequential", ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    scan_time = list(t_scan_ms = 50),
    required_cycle_time_sec = 2.0
  )
  class(optimization_plan) <- c("OptimizationPlan", "list")

  res <- optimize_windows(
    validated_data,
    optimization_plan,
    rt_bin_width_min = 5,
    window_mode = "staggered",
    fz_offset = 0.25
  )

  wins <- res$windows
  expect_true(nrow(wins) > 0)

  # Staggered must have cycle column with values {1, 2}
  expect_true("cycle" %in% colnames(wins))
  expect_true(all(wins$cycle %in% c(1L, 2L)))

  # All windows must have positive width
  expect_true(all(wins$window_width > 0))

  # 100% boundaries at FZ when fz_offset > 0
  optimal_increment <- 1.00045475
  ptm_c <- 0.25
  is_at_fz <- function(mz_val) {
    shifted <- mz_val - ptm_c
    remainder <- shifted %% optimal_increment
    remainder < 0.01 || (optimal_increment - remainder) < 0.01
  }
  all_boundaries <- c(wins$mz_start, wins$mz_end)
  at_fz <- vapply(all_boundaries, is_at_fz, logical(1))
  expect_equal(mean(at_fz), 1.0)

  # Boundary-array integrity: mz_start[j] == mz_end[j-1] within each RT bin + cycle
  for (rt_id in unique(wins$rt_segment_id)) {
    for (cyc in c(1L, 2L)) {
      cyc_w <- wins[wins$rt_segment_id == rt_id & wins$cycle == cyc, ]
      cyc_w <- cyc_w[order(cyc_w$mz_start), ]
      if (nrow(cyc_w) > 1) {
        for (j in 2:nrow(cyc_w)) {
          expect_identical(cyc_w$mz_start[j], cyc_w$mz_end[j - 1])
        }
      }
    }
  }
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
    instrument = list(preset = "test", cycle_mode = "sequential", ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    scan_time = list(t_scan_ms = 50),
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
    instrument = list(preset = "test", cycle_mode = "sequential", ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    scan_time = list(t_scan_ms = 50),
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
