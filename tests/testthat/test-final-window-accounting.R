.accounting_fixture <- function(mz = c(449, 451), overlap = 20, mode = "fixed") {
  data <- data.frame(Precursor.Mz = mz, RT.Apex = rep(5, length(mz)),
                     FWHM = rep(1, length(mz)))
  windows <- generate_windows_internal(
    data, data.frame(rt_start = 0, rt_end = 10),
    data.frame(rt_segment_id = 1, mz_min = 400, mz_max = 500),
    n_windows_per_bin = 2, window_mode = mode, min_width_da = 1,
    max_width_da = 100, overlap_percentage = overlap, fz_offset = 0
  )
  list(data = data, windows = windows)
}

test_that("overlap counts final geometry and coverage counts observations once", {
  f <- .accounting_fixture()
  expect_equal(f$windows$mz_start, c(400, 445))
  expect_equal(f$windows$mz_end, c(455, 500))
  expect_equal(f$windows$n_precursors, c(2, 2))
  stats <- calculate_window_statistics_internal(f$windows, f$data)
  expect_equal(stats$covered_precursors, 2)
  expect_equal(stats$coverage_percentage, 100)
  expect_equal(stats$mean_precursors_per_window, 2)
  # A stale count from an external/saved window table cannot affect accounting.
  f$windows$n_precursors <- 999
  expect_identical(calculate_window_statistics_internal(f$windows, f$data), stats)
})

test_that("generation, evaluation and comparison export agree at the top edge", {
  f <- .accounting_fixture(mz = c(500, NA), overlap = 0)
  stats <- calculate_window_statistics_internal(f$windows, f$data)
  expect_equal(f$windows$n_precursors, c(0, 1))
  expect_equal(stats$covered_precursors, 1)
  expect_equal(stats$coverage_percentage, 50)
  vd <- structure(list(data = f$data, metadata = list(fwhm_unit = "seconds")),
                  class = "ValidatedData")
  ow <- structure(list(windows = f$windows, statistics = stats,
                       parameters = list(min_width_da = 1, max_width_da = 100)),
                  class = "OptimizedWindows")
  plan <- structure(list(actual_cycle_time_sec = 0.5,
                         parameters = list(target_dppp = 1)), class = "OptimizationPlan")
  evaluation <- evaluate_windows(ow, vd, plan)
  expect_equal(evaluation$per_window$n_precursors, f$windows$n_precursors)
  expect_equal(evaluation$overall$coverage_pct, stats$coverage_percentage)
  directory <- withr::local_tempdir()
  invisible(capture.output(export_batch_comparison(
    list(first = ow, second = ow), vd, directory, formats = "center_mass"
  )))
  csv <- read.csv(file.path(directory, "comparison.csv"))
  expect_equal(csv$coverage_pct, c(50, 50))
  expect_equal(csv$mean_precursors, c(0.5, 0.5))
})

test_that("accounting preserves merged-bin labels and uses half-open RT without labels", {
  windows <- tibble::tibble(rt_segment_id = c(1, 2), rt_start = c(0, 10),
                        rt_end = c(10, 20), mz_start = 400, mz_end = 500,
                        window_width = 100)
  data <- tibble::tibble(RT.Apex = c(10, 20, NA, 15),
                     Precursor.Mz = c(450, 500, 450, NA),
                     rt_group = c(1, NA, 2, 2))
  counted <- calculate_precursors_per_window(windows, data)
  expect_equal(counted$n_precursors, c(1, 1))
  expect_equal(calculate_window_statistics_internal(windows, data)$covered_precursors, 2)
  data$rt_group <- NULL
  expect_equal(calculate_precursors_per_window(windows, data)$n_precursors, c(0, 2))
  expect_equal(count_precursors_in_2d_windows(numeric(), numeric(), numeric(),
                                             numeric(), numeric(), numeric()), integer())
})

test_that("optional RT labels do not warn for ungrouped input tibbles", {
  windows <- tibble::tibble(
    rt_start = c(0, 2, 4), rt_end = c(2, 4, 6), rt_segment_id = 1:3,
    mz_start = c(400, 600, 900), mz_end = c(430, 630, 930), window_width = 30
  )
  data <- tibble::tibble(
    Precursor.Mz = c(410, 420, 610, 620, 910, 920),
    RT.Apex = rep(c(1, 3, 5), each = 2), FWHM = 6
  )
  expect_no_warning(counted <- calculate_precursors_per_window(windows, data))
  expect_equal(counted$n_precursors, c(2, 2, 2))
  expect_no_warning(stats <- calculate_window_statistics_internal(windows, data))
  expect_equal(stats$covered_precursors, 6)
  expect_equal(stats$coverage_percentage, 100)

  vd <- structure(list(data = data), class = "ValidatedData")
  expect_no_warning(plot <- plot_precursors_per_window(
    list(windows = windows), vd,
    list(original_method = fixed_method_config(40))
  ))
  expect_equal(plot$data$n_precursors, c(2, 2, 2))
  expect_match(plot$labels$subtitle, "original fixed: 40 windows/cycle")

  # Explicit precursor labels alone cannot select the group-matching path.
  windows$rt_segment_id <- NULL
  data$rt_group <- c(3, 3, 1, 1, 2, 2)
  expect_no_warning(counted <- calculate_precursors_per_window(windows, data))
  expect_equal(counted$n_precursors, c(2, 2, 2))
  expect_no_warning(stats <- calculate_window_statistics_internal(windows, data))
  expect_equal(stats$covered_precursors, 6)
})

test_that("staggered cycles count repeated isolation but deduplicate coverage", {
  f <- .accounting_fixture(mz = c(425, 450, 475, 500), overlap = 0, mode = "staggered")
  stats <- calculate_window_statistics_internal(f$windows, f$data)
  expect_equal(stats$covered_precursors, 4)
  expect_gt(sum(f$windows$n_precursors), stats$covered_precursors)
  expect_equal(calculate_precursors_per_window(f$windows, f$data)$n_precursors,
               f$windows$n_precursors)
})

test_that("accounting matches a brute-force oracle for gaps, ties and overlaps", {
  set.seed(821)
  for (i in seq_len(20)) {
    start <- sample(400:490, 12, replace = TRUE)
    end <- start + sample(1:30, 12, replace = TRUE)
    windows <- data.frame(rt_start = rep(c(0, 5, 10), each = 4),
                          rt_end = rep(c(7, 10, 15), each = 4),
                          mz_start = start, mz_end = end, window_width = end - start)
    data <- data.frame(RT.Apex = sample(c(0:15, NA), 80, replace = TRUE),
                       Precursor.Mz = sample(c(400:520, NA), 80, replace = TRUE))
    hits <- vapply(seq_len(nrow(windows)), function(w) {
      same_rt <- windows$rt_start == windows$rt_start[w] & windows$rt_end == windows$rt_end[w]
      top_mz <- max(windows$mz_end[same_rt])
      hit <- data$RT.Apex >= windows$rt_start[w] &
        (data$RT.Apex < windows$rt_end[w] |
           (windows$rt_end[w] == 15 & data$RT.Apex == 15)) &
        data$Precursor.Mz >= windows$mz_start[w] &
        (data$Precursor.Mz < windows$mz_end[w] |
           (windows$mz_end[w] == top_mz & data$Precursor.Mz == top_mz))
      hit[is.na(hit)] <- FALSE
      hit
    }, logical(nrow(data)))
    actual <- calculate_precursors_per_window(windows, data)
    stats <- calculate_window_statistics_internal(windows, data)
    expect_equal(actual$n_precursors, as.numeric(colSums(hits)))
    expect_equal(stats$covered_precursors, sum(rowSums(hits) > 0))
  }
})
