.results_env <- function() {
  env <- new.env(parent = environment())
  sys.source(system.file("shiny_app", "results_comparison.R", package = "aidia", mustWork = TRUE), env)
  sys.source(system.file("shiny_app", "server_downloads.R", package = "aidia", mustWork = TRUE), env)
  env
}

.results_fixture <- function() {
  original <- fixed_method_config(3, 400, 1000)
  original$cycle_time_sec <- 3.4
  list(data = list(data = tibble::tibble(
    Precursor.Mz = c(410, 450, 600, 700, 1000, 1100),
    RT.Apex = c(0, 10, 10, 15, 20, 22), FWHM = c(2, 4, 6, 8, NA, 1)),
    metadata = list(fwhm_unit = "seconds")),
    run = list(plan = list(original_method = original, actual_cycle_time_sec = 99,
      parameters = list(target_dppp = 4)),
      windows = list(windows = data.frame(rt_start = c(0, 10), rt_end = c(10, 20),
        rt_segment_id = 1:2, mz_start = c(400, 600), mz_end = c(500, 1000),
        window_width = c(100, 400)),
        dppp_verification = list(actual_cycle_time_sec = 1.7))))
}

test_that("comparison geometry matches the delivered Thermo file across RT gaps", {
  env <- .results_env()
  f <- .results_fixture()
  f$run$windows$windows$rt_start <- c(10, 20)
  f$run$windows$windows$rt_end <- c(18, 30)
  w <- f$run$windows$windows
  f$run$windows$windows$mz_center <- (w$mz_start + w$mz_end) / 2
  class(f$run$windows) <- "OptimizedWindows"
  class(f$data) <- "ValidatedData"
  path <- withr::local_tempfile(fileext = ".csv")
  invisible(capture.output(export_windows_to_csv(f$run$windows, path, f$data)))
  delivered <- read.csv(path, check.names = FALSE)
  x <- env$.shiny_result_comparison(f$run, f$data)
  expect_equal(x$methods$Designed$rt_start, delivered[["t start (min)"]])
  expect_equal(x$methods$Designed$rt_end, delivered[["t stop (min)"]])
})

test_that("40-minute scan budgets use the report span and saved cycle counts", {
  env <- .results_env()
  f <- .results_fixture()
  f$data$data$RT.Apex <- c(0, 10, 15, 20, 30, 40)
  f$run$plan$original_method$n_windows <- 40
  f$run$plan$original_method$cycle_time_sec <- 2
  f$run$plan$original_method$timing <- list(ms1 = list(scans_per_cycle = 1))
  f$run$plan$instrument <- list(ms1_scans_per_cycle = 1, cycle_mode = "sequential")
  f$run$windows$dppp_verification <- list(actual_cycle_time_sec = 3, actual_windows_per_bin = 50)
  x <- env$.shiny_result_comparison(f$run, f$data)
  expect_equal(x$rt_span, c(0, 40))
  expect_equal(x$summary$cycle_count, c(1200, 800))
  expect_equal(x$summary$ms1_scans, c(1200, 800))
  expect_equal(x$summary$ms2_scans, c(48000, 40000))
  expect_equal(x$summary$windows_per_cycle, c(40, 50))
  expect_equal(x$summary$dppp, 1.7 * 4 / c(2, 3))
  f$data$data$FWHM <- f$data$data$FWHM / 60
  f$data$metadata$fwhm_unit <- "minutes"
  expect_equal(env$.shiny_result_comparison(f$run, f$data)$summary, x$summary)
  extended <- env$.shiny_result_comparison(f$run, f$data, list(fill_void=TRUE, acquisition_end_min=60))
  expect_equal(extended$summary$cycle_count, c(1200, 800))
  expect_equal(extended$rt_span, c(0, 40))
  expect_equal(max(extended$methods$Designed$rt_end), 60)
})

test_that("comparison plots share axes and the complete input background", {
  env <- .results_env()
  f <- .results_fixture()
  x <- env$.shiny_result_comparison(f$run, f$data)
  plot <- env$.shiny_plot_selection_comparison(x)
  expect_no_warning(built <- ggplot2::ggplot_build(plot))
  density <- split(built$data[[1]], built$data[[1]]$PANEL)
  expect_equal(density[[1]]$fill, density[[2]]$fill)
  expect_equal(density[[1]]$x, density[[2]]$x)
  expect_equal(density[[1]]$y, density[[2]]$y)
  expect_equal(sum(plot$layers[[1]]$data$Freq), 6)
  expect_equal(built$layout$panel_params[[1]]$x.range, built$layout$panel_params[[2]]$x.range)
  expect_equal(built$layout$panel_params[[1]]$y.range, built$layout$panel_params[[2]]$y.range)
  for (view in c("rt", "whole", "1")) {
    expect_no_warning(ggplot2::ggplotGrob(env$.shiny_plot_load_comparison(x, view)))
  }
})

test_that("unavailable estimates remain unknown instead of fabricated improvements", {
  env <- .results_env()
  f <- .results_fixture()
  f$run$plan$original_method$cycle_time_sec <- NULL
  f$data$data$FWHM <- NA_real_
  x <- env$.shiny_result_comparison(f$run, f$data)
  expect_true(all(is.na(x$summary$dppp)))
  expect_true(is.na(x$summary$cycle_count[1]))
  expect_match(env$.shiny_tradeoff_table(x)$Original[1], "Unavailable")
  f$run$plan$original_method <- NULL
  expect_error(env$.shiny_result_comparison(f$run, f$data), "not saved")
})

test_that("selection outlines preserve gaps while merging overlapping windows", {
  env <- .results_env()
  w <- data.frame(rt_start = 0, rt_end = 10,
    mz_start = c(400, 450, 600), mz_end = c(460, 500, 650))
  outlined <- env$.shiny_selection_outlines(w)
  expect_equal(outlined$mz_start, c(400, 600))
  expect_equal(outlined$mz_end, c(500, 650))
  w$mz_end[1] <- 450
  w$mz_start[2] <- 450.00005
  expect_equal(nrow(env$.shiny_selection_outlines(w)), 2L)
  w$mz_start[2] <- 450.02
  expect_equal(nrow(env$.shiny_selection_outlines(w)), 3L)
  x <- env$.shiny_result_comparison(.results_fixture()$run, .results_fixture()$data)
  expect_no_warning(ggplot2::ggplotGrob(env$.shiny_plot_selection_comparison(x, TRUE)))
})

test_that("draft controls cannot change confirmed comparison summaries", {
  env <- .results_env()
  f <- .results_fixture()
  shiny::testServer(function(input, output, session) {
    rv <- shiny::reactiveValues(confirmed_run = f$run, validated_data = f$data)
    env$server_results_comparison(input, output, session, rv)
  }, {
    before <- output$comparison_coverage
    sampling <- output$comparison_acquisition
    session$setInputs(target_dppp = 15, original_mz_min = 900, original_mz_max = 1500)
    expect_identical(output$comparison_coverage, before)
    expect_identical(output$comparison_acquisition, sampling)
    next_run <- f$run
    next_run$windows$dppp_verification$actual_cycle_time_sec <- 3
    rv$confirmed_run <- next_run
    session$flushReact()
    expect_false(identical(output$comparison_acquisition, sampling))
    expect_identical(output$comparison_coverage, before)
  })
})


test_that("run extension, rounding and the inspected geometry match CSV values", {
  env <- .results_env()
  f <- .results_fixture()
  f$run$windows$windows$rt_start <- c(10.003, 20.007)
  f$run$windows$windows$rt_end <- c(18.005, 30.001)
  f$run$windows$windows$mz_start <- c(400.123456, 600.567891)
  f$run$windows$windows$mz_center <- with(f$run$windows$windows, (mz_start + mz_end) / 2)
  class(f$run$windows) <- "OptimizedWindows"
  class(f$data) <- "ValidatedData"
  path <- withr::local_tempfile(fileext=".csv")
  for (fill in c(FALSE, TRUE)) {
    options <- list(fill_void=fill, acquisition_end_min=45)
    invisible(capture.output(export_windows_to_csv(f$run$windows, path, f$data,
      fill_void=fill, acquisition_end_min=45)))
    csv <- read.csv(path, check.names=FALSE)
    x <- env$.shiny_result_comparison(f$run, f$data, options)
    w <- x$methods$Designed
    expect_equal(w$rt_start, csv[["t start (min)"]])
    expect_equal(w$rt_end, csv[["t stop (min)"]])
    expect_equal(w$mz_start, csv[["m/z"]] - csv[["Isolation Window (m/z)"]] / 2)
    expect_equal(w$mz_end, csv[["m/z"]] + csv[["Isolation Window (m/z)"]] / 2)
    expect_equal(w$rt_end[1], w$rt_start[2])
    p <- env$.shiny_plot_selection_comparison(x, TRUE)
    expect_equal(p$layers[[2]]$data$rt_start[p$layers[[2]]$data$method == "Designed"], w$rt_start)
  }
  expect_error(env$.shiny_result_comparison(f$run, f$data,
    list(fill_void=TRUE, acquisition_end_min=15)), "before the last segment")
})

test_that("parallel mode is not presented as zero MS1 acquisition", {
  env <- .results_env()
  f <- .results_fixture()
  f$run$plan$instrument <- list(ms1_scans_per_cycle=0, cycle_mode="parallel")
  f$run$plan$original_method$timing <- list(ms1=list(scans_per_cycle=0))
  x <- env$.shiny_result_comparison(f$run, f$data)
  row <- env$.shiny_tradeoff_table(x)[4, ]
  expect_equal(row$Original, "Parallel")
  expect_equal(row$Designed, "Parallel")
  expect_true(all(is.na(x$summary$ms1_scans)))
})
