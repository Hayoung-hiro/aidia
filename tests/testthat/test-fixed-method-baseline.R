.fixed_reference_fixture <- function() {
  list(
    data = structure(list(data = data.frame(
      Precursor.Mz = c(410, 420, 610, 620, 910, 920),
      RT.Apex = rep(c(1, 3, 5), each = 2), FWHM = rep(6, 6)
    )), class = c("ValidatedData", "list")),
    plan = list(original_method = fixed_method_config(40),
                diagnosis = list(current_cycle_time_sec = 10),
                instrument = list(ms2_scan_time_ms = 10)),
    result = list(windows = data.frame(
      rt_start = c(0, 2, 4), rt_end = c(2, 4, 6),
      rt_segment_id = 1:3, mz_start = c(400, 600, 900),
      mz_end = c(430, 630, 930), window_width = 30
    ))
  )
}

test_that("reference keeps original range and count across changing RT distributions", {
  f <- .fixed_reference_fixture()
  baseline <- evaluate_fixed_method_baseline(f$data, f$plan, f$result)
  expect_equal(baseline$n_per_bin, 40L)
  expect_equal(baseline$window_width, 15)
  expect_equal(nrow(baseline$windows), 120L)
  expect_equal(baseline$coverage_pct, 100)
  for (bin in 1:3) {
    windows <- subset(baseline$windows, rt_segment_id == bin)
    expect_equal(windows$mz_start, seq(400, 985, by = 15))
    expect_equal(windows$mz_end, seq(415, 1000, by = 15))
    expect_equal(windows$window_width, rep(15, 40))
  }
  expect_identical(.compute_baseline_density(f$data, f$plan, f$result), baseline)
})

test_that("saved original method survives serialization and overrides later plan edits", {
  f <- .fixed_reference_fixture()
  f$result$parameters$original_method <- fixed_method_config(30, 450, 1050)
  f$result <- unserialize(serialize(f$result, NULL))
  baseline <- evaluate_fixed_method_baseline(f$data, f$plan, f$result)
  expect_equal(baseline$n_per_bin, 30L)
  expect_equal(baseline$window_width, 20)
  expect_equal(range(c(baseline$windows$mz_start, baseline$windows$mz_end)), c(450, 1050))
  expect_equal(baseline$coverage_pct, 100 * 4 / 6)
  f$plan$original_method <- fixed_method_config(100, 300, 1200)
  expect_identical(evaluate_fixed_method_baseline(f$data, f$plan, f$result), baseline)
})

test_that("missing original settings do not fabricate a reference", {
  f <- .fixed_reference_fixture()
  f$plan$original_method <- NULL
  expect_null(evaluate_fixed_method_baseline(f$data, f$plan, f$result))
  expect_null(.fixed_baseline_windows(f$plan, f$result))
})

test_that("invalid reference input is rejected", {
  for (n in list(NA_real_, Inf, 0, -1, 1.5, numeric(), c(1, 2))) {
    expect_error(fixed_method_config(n), "positive integer")
  }
  for (limits in list(c(1000, 400), c(400, 400), c(NA, 1000),
                      c(400, Inf), c(-1, 1000))) {
    expect_error(fixed_method_config(40, limits[1], limits[2]), "m/z range")
  }
})

test_that("existing comparison plots use the original reference and handle zero baseline", {
  f <- .fixed_reference_fixture()
  baseline <- evaluate_fixed_method_baseline(f$data, f$plan, f$result)
  evaluation <- list(per_window = transform(f$result$windows, temporal_density_max = 2))
  plot <- plot_temporal_density(evaluation, baseline)
  expect_match(plot$labels$subtitle, "Original fixed \\(40 windows/cycle, m/z 400-1000\\)")
  expect_match(plot$labels$subtitle, "reference median is zero")
  expect_false(grepl("NaN|Inf", plot$labels$subtitle))
  expect_no_error(ggplot2::ggplot_build(plot))
  load <- plot_precursor_load_balance(f$result, f$data, f$plan)
  expect_match(load$labels$subtitle, "Original fixed \\(40 windows/cycle\\)")
  expect_no_error(ggplot2::ggplot_build(load))
  counts <- plot_precursors_per_window(f$result, f$data, f$plan)
  expect_match(counts$labels$subtitle, "original fixed: 40 windows/cycle")
  expect_no_error(ggplot2::ggplot_build(counts))
})
