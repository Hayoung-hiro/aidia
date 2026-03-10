# test-temporal-density.R
# Unit tests for calculate_precursor_temporal_density()

test_that("identical RT.Apex precursors give density_max = n", {
  # 3 precursors at the same RT, same window
  result <- calculate_precursor_temporal_density(
    precursor_mz    = c(410, 415, 420),
    precursor_rt    = c(3.5, 3.5, 3.5),     # identical RT
    precursor_fwhm  = c(0.1, 0.1, 0.1),     # minutes (will be auto-detected)
    window_mz_start = 400,
    window_mz_end   = 430,
    window_rt_start = 3.0,
    window_rt_end   = 4.0
  )

  expect_equal(nrow(result), 1)
  expect_equal(result$density_max, 3)
  expect_equal(result$n_precursors, 3)
})

test_that("non-overlapping FWHM precursors give density_max = 1", {
  # 3 precursors well separated in RT, no overlap
  result <- calculate_precursor_temporal_density(
    precursor_mz    = c(410, 415, 420),
    precursor_rt    = c(3.0, 5.0, 7.0),     # well separated
    precursor_fwhm  = c(6, 6, 6),           # 6 seconds = 0.1 min FWHM
    window_mz_start = 400,
    window_mz_end   = 430,
    window_rt_start = 2.0,
    window_rt_end   = 8.0
  )

  expect_equal(nrow(result), 1)
  expect_equal(result$density_max, 1)
  expect_equal(result$n_precursors, 3)
})

test_that("empty window gives density_max = 0", {
  result <- calculate_precursor_temporal_density(
    precursor_mz    = c(600, 700, 800),       # outside window
    precursor_rt    = c(3.5, 3.5, 3.5),
    precursor_fwhm  = c(0.1, 0.1, 0.1),
    window_mz_start = 400,
    window_mz_end   = 430,
    window_rt_start = 3.0,
    window_rt_end   = 4.0
  )

  expect_equal(nrow(result), 1)
  expect_equal(result$density_max, 0)
  expect_equal(result$density_mean, 0)
  expect_equal(result$n_precursors, 0)
})

test_that("single precursor gives density_max = 1", {
  result <- calculate_precursor_temporal_density(
    precursor_mz    = 410,
    precursor_rt    = 3.5,
    precursor_fwhm  = 0.1,
    window_mz_start = 400,
    window_mz_end   = 430,
    window_rt_start = 3.0,
    window_rt_end   = 4.0
  )

  expect_equal(result$density_max, 1)
  expect_equal(result$n_precursors, 1)
})

test_that("partial overlap gives intermediate density", {
  # 2 precursors with overlapping FWHM
  result <- calculate_precursor_temporal_density(
    precursor_mz    = c(410, 415),
    precursor_rt    = c(3.5, 3.55),          # slight offset
    precursor_fwhm  = c(0.08, 0.08),         # minutes
    window_mz_start = 400,
    window_mz_end   = 430,
    window_rt_start = 3.0,
    window_rt_end   = 4.0
  )

  # They overlap (3.5 +/- 0.08 and 3.55 +/- 0.08 intersect)
  expect_equal(result$density_max, 2)
  expect_gt(result$density_mean, 0)
})

test_that("multiple windows return correct number of rows", {
  result <- calculate_precursor_temporal_density(
    precursor_mz    = c(410, 510, 610),
    precursor_rt    = c(3.5, 3.5, 3.5),
    precursor_fwhm  = c(0.1, 0.1, 0.1),
    window_mz_start = c(400, 500, 600),
    window_mz_end   = c(450, 550, 650),
    window_rt_start = c(3.0, 3.0, 3.0),
    window_rt_end   = c(4.0, 4.0, 4.0)
  )

  expect_equal(nrow(result), 3)
  expect_true(all(result$density_max == 1))
  expect_true(all(result$n_precursors == 1))
})

test_that("density_mean is time-weighted correctly", {
  # 1 precursor eluting for 0.2 min (FWHM=0.1, +-1*FWHM = 0.2 span)
  # Window span = 1.0 min
  # density_mean should be approximately 0.2/1.0 = 0.2
  result <- calculate_precursor_temporal_density(
    precursor_mz    = 410,
    precursor_rt    = 3.5,
    precursor_fwhm  = 0.1,               # minutes
    window_mz_start = 400,
    window_mz_end   = 430,
    window_rt_start = 3.0,
    window_rt_end   = 4.0
  )

  expect_equal(result$density_max, 1)
  # density_mean = 1 * 0.2 / 1.0 = 0.2
  expect_equal(result$density_mean, 0.2, tolerance = 0.01)
})
