.comparison_fixture <- function() {
  set.seed(142)
  list(
    data = structure(list(data = tibble::tibble(
      Precursor.Mz = runif(400, 420, 950),
      RT.Apex = runif(400, 0, 20), FWHM = rep(4, 400)
    )), class = c("ValidatedData", "list")),
    plan = structure(list(
      window_count_per_bin = 8L,
      instrument = list(preset = "test", cycle_mode = "sequential",
                        ms1_time_sec = 0.5, ms2_time_sec = 0.05),
      scan_time = list(t_scan_ms = 50), required_cycle_time_sec = 2
    ), class = c("OptimizationPlan", "list"))
  )
}

.comparison_quiet <- function(expr) {
  invisible(capture.output(value <- suppressWarnings(expr)))
  value
}

test_that("comparison reuses execution-time settings for all five strategies", {
  # Use the actual Shiny input conversion, including controls for strategies
  # other than the selected one. The rest is real Stage 3 computation.
  shiny_env <- new.env(parent = environment())
  sys.source(test_path("..", "..", "inst", "shiny_app", "server_optimization.R"),
             envir = shiny_env)
  input <- list(auto_windows = FALSE, manual_n_windows = 17L,
                greedy_mz_step = 1.5, greedy_apply_smoothing = FALSE,
                quantile_lower = 0.12, quantile_upper = 0.88,
                quantile_apply_smoothing = FALSE, target_coverage = 73,
                outlier_threshold = 1.6, outlier_apply_smoothing = FALSE,
                kde_density_threshold = 23, kde_min_coverage = 67)
  configs <- shiny_env$.shiny_strategy_configs(input)
  fixture <- .comparison_fixture()
  common <- list(
    n_windows_override = 17L, window_mode = "density",
    rt_bin_width_min = 4, rt_binning_mode = "adaptive",
    cpd_min_bin_width = 2, cpd_max_bin_width = 8,
    cpd_min_precursors_per_bin = 25, cpd_significance_level = 0.1,
    edge_void_buffer_min = 0.7, edge_wash_min_precursors = 15,
    min_width_da = 6, max_width_da = 30, mz_range_min = 410,
    mz_range_max = 980, overlap_percentage = 0, width_grid_step = NULL,
    fz_offset = 0.18
  )
  run <- function(config, all_configs = configs) {
    .comparison_quiet(do.call(optimize_windows, c(list(
      validated_data = fixture$data, optimization_plan = fixture$plan,
      strategy_config = config, comparison_strategy_configs = all_configs
    ), common)))
  }
  selected <- run(configs$quantile)
  # Simulate subsequent edits to the screen. They must not affect the report.
  input$manual_n_windows <- 40L
  input$quantile_lower <- 0.25
  input$target_coverage <- 99
  input$greedy_mz_step <- 3
  input$outlier_threshold <- 4
  input$kde_density_threshold <- 50
  later_configs <- shiny_env$.shiny_strategy_configs(input)
  expect_false(identical(later_configs, selected$parameters$strategy_configs))

  notified <- character()
  results <- .comparison_quiet(build_strategy_comparison(
    selected, fixture$data, fixture$plan,
    notify_fn = function(strategy, i) {
      notified <<- c(notified, paste(strategy, i))
    }
  ))
  expect_named(results, STRATEGY_PREFERRED_ORDER)
  expect_identical(results$quantile, selected)
  expect_equal(notified, c("greedy 1", "kde 2", "coverage 4", "outlier 5"))
  for (strategy in names(results)) {
    actual <- results[[strategy]]
    expected <- run(configs[[strategy]])
    expect_equal(actual$windows, expected$windows, info = strategy)
    expect_equal(actual$rt_binning, selected$rt_binning, info = strategy)
    expect_equal(actual$parameters$min_width_da, 6)
    expect_equal(actual$parameters$max_width_da, 30)
    expect_equal(actual$parameters$n_windows_per_bin, 17L)
    expect_true(all(table(actual$windows$rt_segment_id) == 17L))
    # NULL disables the width grid and must survive list subsetting/replay.
    expect_true("width_grid_step" %in% names(actual$parameters))
    expect_null(actual$parameters$width_grid_step)
    expect_identical(actual$parameters$strategy_configs[[strategy]], configs[[strategy]])
  }
})

test_that("automatic count is fixed to the completed acquisition budget", {
  fixture <- .comparison_fixture()
  selected <- .comparison_quiet(optimize_windows(
    fixture$data, fixture$plan, strategy_config = quantile_config()
  ))
  result <- .comparison_quiet(build_strategy_comparison(
    selected, fixture$data, fixture$plan, strategies = c("outlier", "greedy", "quantile")
  ))
  expect_named(result, c("outlier", "greedy", "quantile"))
  expect_identical(result$quantile, selected)
  expect_equal(result$greedy$parameters$n_windows_per_bin, 8L)
  expect_equal(result$outlier$parameters$n_windows_per_bin, 8L)
  expect_true(all(table(result$greedy$windows$rt_segment_id) == 8L))
})

test_that("comparison rejects incomplete old settings instead of guessing defaults", {
  fixture <- .comparison_fixture()
  selected <- .comparison_quiet(optimize_windows(
    fixture$data, fixture$plan, strategy_config = quantile_config()
  ))
  incomplete <- selected
  incomplete$parameters$cpd_significance_level <- NULL
  expect_error(build_strategy_comparison(incomplete, fixture$data, fixture$plan),
               "cpd_significance_level.*Run optimize_windows")
  legacy <- selected
  legacy$parameters$strategy_configs <- NULL
  expect_no_error(validate_OptimizedWindows(legacy))
  expect_error(build_strategy_comparison(legacy, fixture$data, fixture$plan),
               "strategy_configs.*Run optimize_windows")
  expect_error(build_strategy_comparison(selected, fixture$data, fixture$plan,
                                         strategies = c("greedy", "greedy")),
               "unique supported")
})

test_that("Shiny captures hidden strategy controls and publishes a matched run", {
  fixture <- .comparison_fixture()
  fixture$plan$timing <- list(t_scan_ms = 50)
  fixture$plan$current_cycle_time_sec <- 2
  env <- new.env(parent = environment())
  # Exercise the actual run-button event. Numerical behavior is covered above.
  for (name in getNamespaceExports("shiny")) env[[name]] <- getExportedValue("shiny", name)
  env$renderValueBox <- bs4Dash::renderValueBox
  sys.source(test_path("..", "..", "inst", "shiny_app", "server_optimization.R"), env)
  captured <- NULL
  fail_optimization <- FALSE
  env$plan_optimization <- function(...) fixture$plan
  env$optimize_windows <- function(...) {
    if (fail_optimization) stop("deliberate Stage 3 failure")
    captured <<- list(...)
    list(windows = data.frame(mz_start = 400), marker = "completed")
  }
  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(
      validated_data = fixture$data, data_loaded = TRUE,
      optimization_complete = FALSE, optimized_windows = NULL,
      optimization_plan = NULL
    )
    env$server_optimization(input, output, session, rv, function() NULL)
  }
  .comparison_quiet(shiny::testServer(server, {
    session$setInputs(instrument = "exploris", target_dppp = 7,
                      target_satisfaction = 70, mz_strategy = "quantile",
                      rt_binning_mode = "custom", rt_bin_width = 4,
                      auto_windows = FALSE, manual_n_windows = 17,
                      greedy_mz_step = 1.5, target_coverage = 73,
                      outlier_threshold = 1.6, kde_density_threshold = 23,
                      kde_min_coverage = 67, quantile_lower = 0.12,
                      quantile_upper = 0.88, min_isolation_width = 6,
                      max_isolation_width = 30, run_optimization = 1)
    expect_true(rv$optimization_complete)
    expect_equal(captured$comparison_strategy_configs$coverage$target_coverage, 0.73)
    expect_equal(captured$comparison_strategy_configs$greedy$mz_step, 1.5)
    expect_equal(captured$comparison_strategy_configs$kde$kde_density_threshold, 0.23)
    expect_equal(captured$comparison_strategy_configs$outlier$outlier_threshold, 1.6)
    expect_identical(captured$strategy_config,
                     captured$comparison_strategy_configs$quantile)
    expect_equal(captured$n_windows_override, 17L)
    old_plan <- rv$optimization_plan
    old_windows <- rv$optimized_windows
    session$setInputs(target_coverage = 99, kde_density_threshold = 50)
    expect_equal(captured$comparison_strategy_configs$coverage$target_coverage, 0.73)
    fail_optimization <<- TRUE
    fixture$plan$window_count_per_bin <<- 99L
    session$setInputs(run_optimization = 2)
    expect_false(rv$optimization_complete)
    expect_identical(rv$optimization_plan, old_plan)
    expect_identical(rv$optimized_windows, old_windows)
  }))
})

test_that("batch comparison preserves strategy order, settings, and CSV delivery", {
  main_path <- test_path("..", "..", "main.R")
  skip_if_not(file.exists(main_path), "main.R is only available in the source tree")
  env <- new.env(parent = environment())
  .comparison_quiet(sys.source(main_path, env))
  fixture <- .comparison_fixture()
  precursors <- fixture$data$data
  precursors$RT.Start <- precursors$RT.Apex - 0.05
  precursors$RT.Stop <- precursors$RT.Apex + 0.05
  precursors$FWHM <- 0.1
  precursors$Run <- "run1"
  precursors$Precursor.Id <- paste0("precursor", seq_len(nrow(precursors)))
  precursors$Protein.Group <- "protein1"
  precursors$Q.Value <- precursors$PG.Q.Value <- 0.001
  directory <- withr::local_tempdir()
  arrow::write_parquet(precursors, file.path(directory, "20min_report.parquet"))
  results <- .comparison_quiet(env$run_complete_pipeline(
    data_dir = directory, output_base_dir = file.path(directory, "output"),
    instrument_preset = "exploris", current_cycle_time = 2,
    mz_strategies = c("coverage", "quantile", "greedy"),
    create_plots = FALSE, create_pdf = FALSE, verbose = FALSE
  ))
  windows <- results[[1]]$windows_list
  expect_named(windows, c("coverage", "quantile", "greedy"))
  for (result in windows) {
    expect_equal(result$parameters$max_width_da, 100)
    expect_equal(result$parameters$strategy_configs$coverage$target_coverage, 0.95)
    expect_false(result$parameters$strategy_configs$quantile$quantile_apply_smoothing)
    expect_equal(result$parameters$strategy_configs$greedy$smoothing_window, 3)
  }
  files <- list.files(file.path(directory, "output"), pattern = "^method.*csv$",
                      recursive = TRUE, full.names = TRUE)
  expect_length(files, 3L)
  expect_true(all(vapply(files, function(file) ncol(read.csv(file)) == 8L, logical(1))))
})
