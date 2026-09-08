.fz_zoom_fixture <- function(charges) {
  n <- length(charges)
  list(
    windows = list(windows = data.frame(
      rt_segment_id = c(1L, 1L), mz_start = c(495, 500.25),
      mz_end = c(500.25, 505)
    )),
    data = list(data = data.frame(
      Precursor.Mz = rep(seq(498.5, 502, length.out = 5), length.out = n),
      Precursor.Charge = charges
    ))
  )
}

.fz_zoom_quiet <- function(expr) {
  invisible(capture.output(value <- expr))
  value
}

.fz_zoom_build <- function(fixture) {
  ggplot2::ggplot_build(.fz_zoom_quiet(plot_fz_zoom(
    fixture$windows, fixture$data
  )))
}

test_that("FZ zoom retains supported charges and shares the actual boundary", {
  fixture <- .fz_zoom_fixture(c(rep(3L, 5), rep(2L, 10), rep(4L, 4), NA))
  built <- .fz_zoom_build(fixture)
  expect_equal(as.character(built$layout$layout$charge_f), c("2", "3"))
  lines <- Filter(function(layer) "xintercept" %in% names(layer), built$data)
  expect_length(lines, 2)
  for (line in lines) expect_equal(length(unique(line$PANEL)), 2)
  expect_equal(unique(lines[[1]]$xintercept), 500)
  expect_equal(unique(lines[[2]]$xintercept), 500.25)
  # Render as well as build: PDF/report rendering can fail after ggplot_build.
  expect_s3_class(ggplot2::ggplot_gtable(built), "gtable")
})

test_that("absent, single, sparse and unknown charges preserve the combined panel", {
  absent <- .fz_zoom_fixture(rep(2L, 10))
  absent$data$data$Precursor.Charge <- NULL
  variants <- list(
    absent,
    .fz_zoom_fixture(rep(2L, 10)),
    .fz_zoom_fixture(c(rep(2L, 5), rep(3L, 4))),
    .fz_zoom_fixture(rep(NA_integer_, 10))
  )
  for (fixture in variants) {
    built <- .fz_zoom_build(fixture)
    expect_equal(nrow(built$layout$layout), 1L)
    expect_equal(sum(built$data[[2]]$count), nrow(fixture$data$data))
  }
})

test_that("charge labels survive factor input and invalid charge values are ignored", {
  numeric <- .fz_zoom_fixture(rep(c(2L, 3L), each = 5))
  factored <- numeric
  factored$data$data$Precursor.Charge <- factor(
    factored$data$data$Precursor.Charge, levels = c(3, 2)
  )
  expect_equal(.fz_zoom_build(factored)$layout$layout$charge_f,
               .fz_zoom_build(numeric)$layout$layout$charge_f)
  invalid <- .fz_zoom_fixture(rep(c(0, -1, 2.5, 2, 3), each = 5))
  built <- .fz_zoom_build(invalid)
  expect_equal(as.character(built$layout$layout$charge_f), c("2", "3"))
})

test_that("a narrow zoom without any band centers can still render", {
  fixture <- .fz_zoom_fixture(rep(c(2L, 3L), each = 5))
  fixture$data$data$Precursor.Mz <- 500.25
  plot <- .fz_zoom_quiet(plot_fz_zoom(
    fixture$windows, fixture$data, zoom_range_da = 0.001
  ))
  expect_s3_class(ggplot2::ggplotGrob(plot), "gtable")
})

test_that("staggered zoom uses cycle one and insufficient data still renders", {
  fixture <- .fz_zoom_fixture(rep(c(2L, 3L), each = 5))
  fixture$windows$windows$cycle <- 1L
  second <- fixture$windows$windows
  second$cycle <- 2L
  second$mz_start <- second$mz_start + 1
  second$mz_end <- second$mz_end + 1
  fixture$windows$windows <- rbind(second, fixture$windows$windows)
  built <- .fz_zoom_build(fixture)
  lines <- Filter(function(layer) "xintercept" %in% names(layer), built$data)
  expect_equal(unique(lines[[2]]$xintercept), 500.25)
  fixture$data$data <- fixture$data$data[1:4, ]
  expect_s3_class(ggplot2::ggplot_gtable(.fz_zoom_build(fixture)), "gtable")
  fixture$windows$windows <- fixture$windows$windows[3, , drop = FALSE]
  expect_s3_class(ggplot2::ggplot_gtable(.fz_zoom_build(fixture)), "gtable")
})

test_that("charge facets integrate with current optimization, registry and PDF export", {
  data <- as_ValidatedData(data.frame(
    Precursor.Id = paste0("p", seq_len(900)),
    Precursor.Mz = rep(seq(480, 520, length.out = 300), 3),
    Precursor.Charge = rep(2:4, each = 300),
    RT.Apex = rep(seq(1, 9, length.out = 300), 3), FWHM = 6
  ))
  plan <- .fz_zoom_quiet(plan_optimization(data, instrument_preset = "astral"))
  entry <- Filter(function(x) identical(x[["key"]], "app_a_fz_zoom"),
                  PLOT_REGISTRY)[[1]]
  output <- withr::local_tempdir()
  for (mode in c("fixed", "density", "staggered")) {
    windows <- .fz_zoom_quiet(optimize_windows(
      data, plan, strategy_config = quantile_config(apply_smoothing = FALSE),
      window_mode = mode, n_windows_override = 10L, fz_offset = 0.25,
      mz_range_min = 475, mz_range_max = 525, min_width_da = 1,
      rt_bin_width_min = 10
    ))
    before <- windows
    plot <- .fz_zoom_quiet(entry$generate(list(
      optimized_windows = windows, validated_data = data, fz_offset = 0.25
    )))
    expect_equal(nrow(ggplot2::ggplot_build(plot)$layout$layout), 3L, info = mode)
    expect_identical(windows, before)
    files <- .fz_zoom_quiet(export_individual_plots(
      setNames(list(plot), paste0("fz_", mode)), output, format = "pdf"
    ))
    expect_length(files, 1)
    expect_true(all(file.exists(files)))
    expect_gt(file.info(files)$size, 1000)
  }
})
