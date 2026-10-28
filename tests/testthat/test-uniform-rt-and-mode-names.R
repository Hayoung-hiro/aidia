.uniform_fixture <- function(rt) {
  data.frame(RT.Apex = rt, Precursor.Mz = seq(410, 490, length.out = length(rt)),
             FWHM = 4)
}

test_that("Uniform absorbs a partial final interval regardless of tail population", {
  data <- .uniform_fixture(c(seq(3, 26, by = 0.5), rep(25.9, 100)))
  result <- perform_rt_binning_internal(data, 5, rt_binning_mode = "uniform",
    edge_void_buffer_min = 0, edge_wash_min_precursors = 0)
  expect_equal(result$rt_breaks, c(3, 8, 13, 18, 26))
  expect_equal(result$n_bins, 4)
  expect_equal(sum(result$stats$n_precursors), nrow(data))
  expect_false(anyNA(result$data$rt_group))
  expect_equal(unique(result$data$rt_group[data$RT.Apex > 18]), 4)
})

test_that("Uniform keeps exact multiples and handles short and single-point spans", {
  cases <- list(
    list(rt = c(3, 8, 13, 18, 23), width = 5, breaks = c(3, 8, 13, 18, 23)),
    list(rt = c(3, 5), width = 5, breaks = c(3, 5)),
    list(rt = c(3, 3), width = 5, breaks = c(3, 8)),
    list(rt = c(0.1, 0.4), width = 0.1, breaks = c(0.1, 0.2, 0.3, 0.4)),
    list(rt = c(0.1, 0.41), width = 0.1, breaks = c(0.1, 0.2, 0.3, 0.41))
  )
  for (case in cases) {
    result <- perform_fixed_rt_binning_internal(.uniform_fixture(case$rt), case$width)
    expect_equal(result$rt_breaks, case$breaks)
    expect_false(anyNA(result$data$rt_group))
  }
})

test_that("Uniform validates duration and auto estimates include the merged tail", {
  for (width in c(0, -1, NA, Inf)) {
    expect_error(perform_fixed_rt_binning_internal(.uniform_fixture(c(0, 23)), width),
                 "rt_bin_width_min")
  }
  auto <- calculate_auto_rt_bin_width(c(0, 23), "greedy")
  result <- perform_fixed_rt_binning_internal(.uniform_fixture(seq(0, 23, by = 0.1)),
                                             auto$bin_width)
  expect_equal(auto$n_bins, result$n_bins)
})

test_that("Equal and Uniform accept fixed aliases and store canonical modes", {
  vd <- structure(list(data = .uniform_fixture(seq(0, 23, by = 0.25))),
                  class = c("ValidatedData", "list"))
  plan <- structure(list(window_count_per_bin = 4L,
    instrument = list(preset = "test", cycle_mode = "sequential",
                      ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    scan_time = list(t_scan_ms = 50), required_cycle_time_sec = 2),
    class = c("OptimizationPlan", "list"))
  run <- function(window, rt) {
    invisible(capture.output(result <- optimize_windows(vd, plan,
      strategy_config = quantile_config(apply_smoothing = FALSE),
      window_mode = window, rt_binning_mode = rt, rt_bin_width_min = 5,
      edge_void_buffer_min = 0, edge_wash_min_precursors = 0, fz_offset = 0)))
    result
  }
  current <- run("equal", "uniform")
  legacy <- run("fixed", "fixed")
  expect_equal(current$windows, legacy$windows)
  expect_identical(legacy$parameters$window_mode, "equal")
  expect_identical(legacy$parameters$rt_binning_mode, "uniform")
  expect_equal(current$rt_binning$n_bins, 4)
  expect_error(run("unknown", "uniform"), "window_mode must be")
  expect_error(run("equal", "unknown"), "rt_binning_mode must be")
})

test_that("legacy results use Equal and Uniform labels and duration in filenames", {
  expect_equal(format_window_mode(c("fixed", "equal", "density", "staggered")),
               c("Equal", "Equal", "Density", "Staggered"))
  expect_equal(format_rt_mode(c("fixed", "custom", "uniform", "adaptive")),
               c("Uniform", "Uniform", "Uniform", "Adaptive"))
  filename <- function(window, rt, width) format_output_filename(
    "method", "astral", "greedy", window, rt, rt_bin_width_min = width,
    date = "20261027")
  expect_equal(filename("fixed", "fixed", 5), filename("equal", "uniform", 5))
  expect_match(filename("equal", "uniform", 5), "Equal_Uniform5min")
  expect_false(identical(filename("equal", "uniform", 5),
                         filename("equal", "uniform", 4)))
})
