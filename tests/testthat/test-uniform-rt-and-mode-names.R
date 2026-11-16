.uniform_fixture <- function(rt) {
  data.frame(RT.Apex = rt, Precursor.Mz = seq(410, 490, length.out = length(rt)),
             FWHM = 4)
}

test_that("requested Uniform counts use integer minutes and extend only the last group", {
  partition <- .uniform_rt_partition(c(3.25, 46.25), 5)
  expect_equal(diff(partition$breaks), c(8, 8, 8, 8, 11))
  expect_equal(range(partition$breaks), c(3.25, 46.25))
  # Duration-only binning would create nine groups here; the requested count is five.
  data <- .uniform_fixture(seq(1.5, 10.5, by = .01))
  result <- perform_rt_binning_internal(data, 99, rt_group_count = 5,
    edge_void_buffer_min = 0, edge_wash_min_precursors = 0)
  expect_equal(result$n_bins, 5)
  expect_equal(diff(result$rt_breaks), c(1, 1, 1, 1, 5))
  expect_equal(sum(result$stats$n_precursors), nrow(data))
  expect_false(anyNA(result$data$rt_group))
  expect_equal(unique(result$data$rt_group[data$RT.Apex > 5.5]), 5)
  expect_equal(.uniform_rt_partition(c(.1, 10.1), 5)$width, 2)
  expect_equal(.uniform_rt_partition(c(2, 2.5), 1)$breaks, c(2, 2.5))
  expect_equal(.uniform_rt_partition(c(2, 2), 1)$breaks, c(2, 3))
  for (count in list(NULL, 0, -1, 1.5, NA_real_, Inf, c(1, 2)))
    expect_error(.uniform_rt_partition(c(0, 10), count), "positive whole number")
  expect_error(.uniform_rt_partition(c(0, 3.2), 5), "at most 3")
})

test_that("count-based partitions are saved and reproduce optimized RT assignments", {
  vd <- structure(list(data = .uniform_fixture(seq(0, 9, by = .01))),
                  class = c("ValidatedData", "list"))
  plan <- structure(list(window_count_per_bin = 4L,
    instrument = list(preset = "test", cycle_mode = "sequential", ms1_time_sec = .5, ms2_time_sec = .05),
    scan_time = list(t_scan_ms = 50), required_cycle_time_sec = 2), class = c("OptimizationPlan", "list"))
  invisible(capture.output(result <- optimize_windows(vd, plan,
    strategy_config = quantile_config(apply_smoothing = FALSE), rt_group_count = 5,
    edge_void_buffer_min = 0, edge_wash_min_precursors = 0, fz_offset = 0)))
  expect_equal(result$rt_binning$n_bins, 5)
  expect_equal(result$parameters$rt_group_count, 5)
  expect_equal(result$parameters$rt_bin_width_min, 1)
  reconstructed <- perform_rt_binning_internal(vd$data, result$parameters$rt_bin_width_min,
    rt_group_count = result$parameters$rt_group_count, edge_void_buffer_min = 0, edge_wash_min_precursors = 0)
  expect_equal(result$rt_binning$rt_stats, reconstructed$stats)
  invisible(capture.output(comparison <- build_strategy_comparison(result, vd, plan)))
  for (strategy in names(comparison)) {
    expect_equal(comparison[[strategy]]$parameters$rt_group_count, 5, info = strategy)
    expect_equal(comparison[[strategy]]$rt_binning$rt_stats, reconstructed$stats, info = strategy)
  }
})

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
