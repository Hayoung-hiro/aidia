.intent_env <- function() {
  env <- new.env(parent = environment())
  for (name in getNamespaceExports("shiny")) env[[name]] <- getExportedValue("shiny", name)
  for (file in c("server_navigation.R", "server_optimization.R", "optimization_workflow.R", "server_live_preview.R"))
    sys.source(test_path("..", "..", "inst", "shiny_app", file), env)
  env
}

test_that("Greedy span uses the resolved count and preserves canonical results", {
  env <- .intent_env()
  set.seed(142)
  data <- structure(list(data = tibble::tibble(Precursor.Mz = runif(1000, 420, 950),
    RT.Apex = runif(1000, 0, 20), FWHM = rep(4, 1000))), class = c("ValidatedData", "list"))
  plan <- structure(list(window_count_per_bin = 40L,
    instrument = list(preset = "test", cycle_mode = "sequential", ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    scan_time = list(t_scan_ms = 50), required_cycle_time_sec = 2), class = c("OptimizationPlan", "list"))
  env$plan_optimization <- function(...) plan
  input <- c(do.call(c, unname(env$.shiny_setup_defaults("exploris"))),
    list(instrument = "exploris", ms1_it_auto = TRUE, ms2_it_auto = TRUE))
  input$mz_strategy <- "greedy"
  input$greedy_range_width <- 100
  input$auto_windows <- FALSE
  input$manual_n_windows <- 50L
  input$greedy_apply_smoothing <- FALSE
  run <- function(x) {
    invisible(capture.output(value <- suppressWarnings(env$.shiny_compute_windows(x, data))))
    value
  }
  actual <- run(input)
  expect_equal(actual$windows$parameters$min_width_da, 2)
  expect_equal(actual$windows$parameters$n_windows_per_bin, 50L)
  expect_equal(actual$windows$mz_optimization$mz_ranges$mz_width, rep(100, nrow(actual$windows$mz_optimization$mz_ranges)))
  legacy <- input
  legacy$greedy_range_width <- NULL
  legacy$min_isolation_width <- 2
  previous <- run(legacy)$windows
  expect_equal(actual$windows$windows, previous$windows)
  expect_equal(actual$windows$parameters, previous$parameters)
  expect_equal(actual$windows$mz_optimization, previous$mz_optimization)
  expect_equal(actual$windows$statistics, previous$statistics)
  input$auto_windows <- TRUE
  automatic <- run(input)
  expect_equal(automatic$windows$parameters$min_width_da, 2.5)
  expect_equal(automatic$windows$parameters$n_windows_per_bin, 40L)
  expect_error(env$.shiny_greedy_width(30, 50, 80), "at least 50.0 m/z")
  expect_error(env$.shiny_greedy_width(500, 50, 10), "Increase Max width")
  expect_error(env$.shiny_greedy_width(NULL, 50, 80), "positive Total m/z span")
  error <- tryCatch(env$.shiny_greedy_width(30, 50, 80), error = identity)
  expect_equal(error$field, "greedy_range_width")
  error <- tryCatch(env$.shiny_greedy_width(500, 50, 10), error = identity)
  expect_equal(error$field, "max_isolation_width")
  input$mz_strategy <- "kde"
  input$min_isolation_width <- 12
  expect_length(env$.shiny_setup_issues(input), 0)
  expect_equal(run(input)$windows$parameters$min_width_da, 12)
})

test_that("Quantile tail percentages preserve asymmetric cutoffs", {
  env <- .intent_env()
  current <- env$.shiny_strategy_configs(list(quantile_exclude_low = 12, quantile_exclude_high = 7))
  legacy <- env$.shiny_strategy_configs(list(quantile_lower = 0.12, quantile_upper = 0.93))
  expect_equal(current, legacy)
})

test_that("navigation explains missing uploads and allows prepared data", {
  env <- .intent_env()
  destination <- NULL
  env$updateTabItems <- function(session, inputId, selected) destination <<- selected
  server <- function(input, output, session) {
    rv <- reactiveValues(data_loaded = FALSE, validated_data = NULL, data_error = NULL,
      optimization_complete = FALSE)
    env$server_navigation(input, output, session, rv, function() list(cycle_time_sec = 1))
  }
  shiny::testServer(server, {
    session$setInputs(instrument = "astral", current_window_count = 100, astral_ms2_it = 3)
    session$setInputs(btn_to_setup = 1)
    expect_equal(destination, "data")
    expect_match(output$prepare_navigation_feedback$html, "highlighted field")
    expect_match(env$.shiny_prepare_issues(input, FALSE, list())[["parquet_file"]], "Upload a report.parquet")
    session$setInputs(workflow_navigate = "setup")
    expect_equal(destination, "data")
    rv$data_error <- "Invalid parquet header"
    session$flushReact()
    expect_match(env$.shiny_prepare_issues(input, FALSE, list(), rv$data_error)[["parquet_file"]], "Invalid parquet header")
    rv$data_loaded <- TRUE
    rv$data_error <- NULL
    session$setInputs(btn_to_setup = 2)
    expect_equal(destination, "setup")
    session$setInputs(astral_ms2_it = NULL, btn_to_setup = 3)
    expect_equal(destination, "data")
    expect_match(env$.shiny_prepare_issues(input, TRUE, list())[["astral_ms2_it"]], "MS2 injection time")
  })
})

test_that("cleared and incompatible setup controls explain how to recover", {
  env <- .intent_env()
  input <- do.call(c, unname(env$.shiny_setup_defaults("exploris")))
  expect_length(env$.shiny_setup_issues(input), 0)
  input$target_dppp <- NULL
  expect_match(env$.shiny_setup_issues(input), "Points / peak")
  input$target_dppp <- 7
  input$mz_strategy <- "greedy"
  input$auto_windows <- FALSE
  input$manual_n_windows <- 50
  input$greedy_range_width <- 30
  expect_match(env$.shiny_setup_issues(input), "at least 50.0 m/z")
  expect_named(env$.shiny_setup_issues(input), "greedy_range_width")
  input$mz_strategy <- "kde"
  input$min_isolation_width <- 0.5
  expect_named(env$.shiny_setup_issues(input), "min_isolation_width")
  input$min_isolation_width <- input$max_isolation_width
  expect_match(env$.shiny_setup_issues(input)[["min_isolation_width"]], "below Max width")
})
