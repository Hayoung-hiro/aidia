.live_env <- function() {
  env <- new.env(parent = environment())
  for (name in getNamespaceExports("shiny")) env[[name]] <- getExportedValue("shiny", name)
  env$updateTabItems <- function(...) NULL
  sys.source(test_path("..", "..", "inst", "shiny_app", "server_navigation.R"), env)
  sys.source(test_path("..", "..", "inst", "shiny_app", "optimization_workflow.R"), env)
  sys.source(test_path("..", "..", "inst", "shiny_app", "server_live_preview.R"), env)
  sys.source(test_path("..", "..", "inst", "shiny_app", "preview_display.R"), env)
  env
}

.live_fixture_run <- function(request, marker) {
  c(request[c("settings", "cycle", "data_version")], list(
    plan = list(window_count_per_bin = 40L),
    windows = list(marker = marker, windows = data.frame(mz_start = 400),
      rt_binning = list(rt_stats = data.frame(rt_segment_id = 1L, rt_start = 0, rt_end = 5))),
    profiles = list("1" = list(n = 10))
  ))
}

test_that("live preview coalesces edits, rejects stale results, and promotes exact snapshots", {
  env <- .live_env()
  sent <- list()
  env$updateSliderInput <- env$updateNumericInput <- function(session, inputId, value, ...) {
    sent[[inputId]] <<- value
  }
  env$updateCheckboxInput <- function(session, inputId, value, ...) sent[[inputId]] <<- value
  env$updateSelectInput <- function(session, inputId, selected, ...) sent[[inputId]] <<- selected
  server <- function(input, output, session) {
    rv <- reactiveValues(data_loaded = TRUE,
      validated_data = list(data = data.frame(Precursor.Mz = 400)),
      confirmed_run = NULL, optimization_complete = FALSE)
    task_state <- reactiveVal("initial")
    task_result <- reactiveVal(NULL)
    calls <- reactiveVal(list())
    task <- list(
      status = function() task_state(), result = function() task_result(),
      invoke = function(request) {
        calls(c(calls(), list(request)))
        task_state("running")
      })
    complete <- function(index, marker) {
      task_result(.live_fixture_run(calls()[[index]], marker))
      task_state("success")
      session$flushReact()
    }
    env$server_live_preview(input, output, session, rv, function() list(cycle_time_sec = 1), task = task)
  }
  shiny::testServer(server, {
    session$setInputs(instrument = "exploris", kde_density_threshold = 10,
      current_window_count = 40, ms1_it_auto = TRUE, ms2_it_auto = TRUE)
    session$elapse(500)
    expect_length(calls(), 1)
    session$setInputs(kde_density_threshold = 15)
    session$elapse(500)
    session$setInputs(kde_density_threshold = 25)
    session$elapse(500)
    expect_length(calls(), 1) # Running work does not queue every slider movement.
    complete(1, "stale")
    expect_null(rv$confirmed_run)
    expect_equal(rv$draft_state, "updating")
    expect_length(calls(), 2)
    expect_equal(calls()[[2]]$settings$kde_density_threshold, 25)
    complete(2, "latest")
    expect_equal(rv$draft_state, "ready")
    expect_false(rv$optimization_complete)
    session$setInputs(run_optimization = 1)
    expect_true(rv$optimization_complete)
    expect_identical(rv$optimized_windows$marker, "latest")
    confirmed <- rv$confirmed_run
    expect_equal(rv$draft_state, "confirmed")

    session$setInputs(kde_density_threshold = 30, target_dppp = 4, rt_bin_width = 8)
    session$elapse(500)
    expect_identical(rv$confirmed_run, confirmed)
    expect_identical(rv$optimized_windows, confirmed$windows)
    task_result(list(error = "Cannot generate windows", field = "min_isolation_width"))
    task_state("success")
    session$flushReact()
    expect_equal(rv$draft_state, "error")
    expect_true(rv$optimization_complete) # A draft error cannot revoke an export.
    expect_identical(rv$confirmed_run, confirmed)

    sent <<- list()
    call_count <- length(calls())
    session$setInputs(run_optimization = 99)
    expect_length(calls(), call_count) # A known field error focuses the control, without retrying it.
    session$setInputs(reset_windows = 1)
    expect_equal(sent$kde_density_threshold, 25)
    expect_false("target_dppp" %in% names(sent))
    expect_false("rt_bin_width" %in% names(sent))

    # A confirmation requested during computation is canceled by a subsequent edit.
    session$setInputs(kde_density_threshold = 20, run_optimization = 2)
    session$setInputs(kde_density_threshold = 15)
    session$elapse(500)
    complete(length(calls()), "old confirmation request")
    expect_identical(rv$confirmed_run, confirmed)
    complete(length(calls()), "new unconfirmed preview")
    expect_equal(rv$draft_state, "ready")
    expect_identical(rv$confirmed_run, confirmed)

    # With no intervening edit, confirmation during a task promotes that task.
    session$setInputs(kde_density_threshold = 20, run_optimization = 3)
    complete(length(calls()), "confirmed after waiting")
    expect_identical(rv$optimized_windows$marker, "confirmed after waiting")
    expect_equal(rv$draft_state, "confirmed")

    # Invalid edits must not silently fall back to defaults or revoke downloads.
    saved <- rv$confirmed_run
    count <- length(calls())
    session$setInputs(target_dppp = NULL, run_optimization = 4)
    session$elapse(500)
    expect_equal(rv$draft_state, "invalid")
    expect_match(output$setup_navigation_feedback$html, "highlighted settings")
    expect_length(calls(), count)
    expect_identical(rv$confirmed_run, saved)
    session$setInputs(target_dppp = 4)
    session$elapse(500)
    expect_equal(rv$draft_state, "confirmed")

    # New input data invalidates both the preview and confirmation association.
    rv$validated_data <- list(data = data.frame(Precursor.Mz = 500))
    session$flushReact()
    session$elapse(500)
    expect_null(rv$confirmed_run)
    sent <<- list()
    session$setInputs(reset_windows = 2)
    expect_equal(sent$kde_density_threshold, 10)
    expect_equal(sent$min_isolation_width,
                 get_instrument_width_recommendations(get_instrument_config("exploris"))$min_width_da)
    rv$data_loaded <- FALSE
    rv$validated_data <- NULL
    session$flushReact()
    complete(length(calls()), "previous upload")
    expect_equal(rv$draft_state, "empty")
    expect_null(rv$confirmed_run)
  })
})

test_that("KDE preview estimator exactly matches the existing selection estimator", {
  set.seed(7)
  mz <- c(rnorm(300, 550, 30), rnorm(80, 800, 40))
  expected <- density(mz, bw = "SJ", n = 512)
  actual <- .kde_density_profile(mz)
  expect_equal(actual$x, expected$x)
  expect_equal(actual$y, expected$y)
  sparse <- rep(500, 10) # SJ fallback path
  expect_equal(.kde_density_profile(sparse)$y, density(sparse, bw = "nrd0", n = 512)$y)
})

test_that("whole-run preview retains separate RT ranges and both staggered cycles", {
  env <- .live_env()
  windows <- data.frame(rt_segment_id = c(1L, 1L, 2L, 2L),
    rt_start = c(0, 0, 5, 5), rt_end = c(5, 5, 12, 12),
    mz_start = c(400, 420, 700, 720), mz_end = c(500, 520, 800, 820),
    window_width = 100, cycle = c(1L, 2L, 1L, 2L))
  ranges <- data.frame(rt_segment_id = 1:2, rt_start = c(0, 5), rt_end = c(5, 12),
                       mz_min = c(400, 700), mz_max = c(520, 820))
  profile <- list(n = 100, histogram = data.frame(mz = c(450, 750),
                    density = c(0.009, 0.001), width = 100), curve = NULL)
  run <- list(profiles = list("1" = list(n = 90), "2" = list(n = 10), all = profile),
    windows = list(windows = windows, mz_optimization = list(mz_ranges = ranges)))
  all <- env$.shiny_preview_slice(run, "all")
  expect_identical(all$windows, windows)
  expect_identical(all$range, ranges)
  expect_identical(all$profile, profile)
  expect_true(all$all)
  second <- env$.shiny_preview_slice(run, "2")
  expect_false(second$all)
  expect_equal(second$profile$n, 10)
  expect_equal(second$windows$rt_segment_id, c(2L, 2L))
  expect_equal(second$windows$cycle, c(1L, 2L))
  expect_true(env$.shiny_preview_slice(run, "deleted_group")$all)
})


test_that("RT-mz overview preserves the full report density and exact selection edges", {
  env <- .live_env()
  data <- list(data = data.frame(RT.Apex = seq(0, 12, length.out = 100),
    Precursor.Mz = 300 + ((seq_len(100) * 37) %% 600)))
  ranges <- data.frame(rt_start = c(0, 5), rt_end = c(5, 12),
    mz_min = c(400, 700), mz_max = c(520, 820), mz_width = 120, coverage_ratio = 0.8)
  windows <- list(mz_optimization = list(strategy = "kde", mz_ranges = ranges))
  plot <- env$.shiny_plot_overview(windows, data)
  built <- ggplot2::ggplot_build(plot)
  report <- ggplot2::ggplot_build(plot_density_with_mz_range(windows, data))
  expect_identical(plot$data, data$data)
  expect_equal(built$data[[1]], report$data[[1]])
  boundary <- tail(built$data, 1)[[1]]
  expect_equal(boundary$xmin, ranges$rt_start)
  expect_equal(boundary$xmax, ranges$rt_end)
  expect_equal(boundary$ymin, ranges$mz_min)
  expect_equal(boundary$ymax, ranges$mz_max)
  expect_true(all(is.na(boundary$fill)))
  # A changed selection must not change the underlying data distribution.
  windows$mz_optimization$mz_ranges$mz_max <- c(500, 780)
  changed <- ggplot2::ggplot_build(env$.shiny_plot_overview(windows, data))
  expect_equal(changed$data[[1]], built$data[[1]])
  expect_equal(tail(changed$data, 1)[[1]]$ymax, c(500, 780))
})
