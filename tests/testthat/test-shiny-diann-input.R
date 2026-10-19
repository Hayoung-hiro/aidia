.diann_ui_env <- function() {
  env <- new.env(parent = environment())
  for (pkg in c("shiny", "bs4Dash")) {
    for (name in getNamespaceExports(pkg)) env[[name]] <- getExportedValue(pkg, name)
  }
  for (file in c("diann_input_options.R", "server_feature_uploads.R", "server_data.R"))
    sys.source(system.file("shiny_app", file, package = "aidia", mustWork = TRUE), env)
  env
}

.diann_upload_fixture <- function() {
  dplyr::bind_rows(lapply(seq_len(3), function(i) {
    ids <- seq_len(c(120, 80, 40)[i])
    data.frame(Run = LETTERS[i], Precursor.Id = paste0("pep", ids), Protein.Group = "protein",
      Precursor.Mz = 400 + ids, RT.Start = ids / 15 + .02 * i,
      RT.Stop = ids / 15 + .2 + .02 * i, FWHM = .15,
      Q.Value = ifelse(ids == 1, .02, .001),
      Lib.Q.Value = ifelse(ids == 2, .02, .001),
      Global.Q.Value = ifelse(ids == 3, .02, .001),
      PG.Q.Value = ifelse(ids == 4, .07, .001), Channel.Q.Value = ifelse(ids == 5, .03, .001))
  }))
}

test_that("DIA-NN UI defaults reproduce existing Stage 1 and validate user controls", {
  env <- .diann_ui_env()
  args <- env$.shiny_diann_arguments(list())
  expect_true(args$enable_replicate_consensus)
  expect_null(args$min_replicates)
  expect_true(args$apply_quality_filters)
  defaults <- formals(aidia:::filter_diann_quality)
  for (key in setdiff(names(args), c("enable_replicate_consensus", "min_replicates", "apply_quality_filters")))
    expect_equal(args[[key]], eval(defaults[[key]]))
  expect_error(env$.shiny_diann_arguments(list(diann_min_runs = 1.5)), "whole number")
  expect_error(env$.shiny_diann_arguments(list(diann_q_value = NA_real_)), "between 0 and 1")
  expect_error(env$.shiny_diann_arguments(list(diann_pg_q_value = 1.1)), "between 0 and 1")
  expect_null(env$.shiny_diann_arguments(list(diann_aggregation = "pooled", diann_min_runs = NA_real_))$min_replicates)
  expect_false(env$.shiny_diann_arguments(list(diann_quality_filters = FALSE, diann_q_value = NA_real_))$apply_quality_filters)
  expect_match(paste(env$.shiny_diann_filter_summary(args), collapse = "; "), "Protein-group Q <= 0.05", fixed = TRUE)
  expect_equal(env$.shiny_diann_filter_summary(list(apply_quality_filters = FALSE)), "Q-value filters: off")
})

test_that("local file access defaults to loopback launches and restores the previous option", {
  withr::local_options(aidia.shiny.local_files = NULL)
  testthat::local_mocked_bindings(runApp = function(...) getOption("aidia.shiny.local_files"),
    .package = "shiny")
  expect_true(run_aidia_app(host = "127.0.0.1"))
  expect_null(getOption("aidia.shiny.local_files"))
  expect_false(run_aidia_app(host = "0.0.0.0"))
  withr::local_options(aidia.shiny.local_files = FALSE)
  expect_false(run_aidia_app(host = "127.0.0.1"))
})

test_that("DIA-NN Compute respects consensus, minimum runs and quality filters", {
  env <- .diann_ui_env()
  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(.diann_upload_fixture(), path)
  original <- create_validated_dataset(path)
  upload <- data.frame(name = "report.parquet", size = file.info(path)$size, datapath = path)
  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(data_loaded = FALSE, optimization_complete = FALSE)
    env$server_data(input, output, session, rv, function() NULL)
  }
  shiny::testServer(server, {
    session$setInputs(input_type = "diann", target_dppp = 4, target_satisfaction = 80,
      parquet_file = upload)
    expect_false(rv$data_loaded)
    expect_match(output$diann_upload_queue$html, "A, B, C")
    session$setInputs(compute_diann = 1)
    expect_true(rv$data_loaded)
    expect_equal(rv$validated_data$data, original$data)
    expect_equal(nrow(rv$validated_data$data), 76)
    expect_match(output$input_scope_summary$html, "at least 2 runs")
    session$setInputs(diann_min_runs = 3)
    expect_false(rv$data_loaded)
    session$setInputs(compute_diann = 2)
    expect_equal(nrow(rv$validated_data$data), 36)
    session$setInputs(diann_min_runs = 1)
    session$setInputs(compute_diann = 3)
    expect_equal(nrow(rv$validated_data$data), 116)
    session$setInputs(diann_min_runs = 4)
    session$setInputs(compute_diann = 4)
    expect_false(rv$data_loaded)
    expect_null(rv$validated_data)
    expect_true(nzchar(rv$data_error))
    session$setInputs(diann_aggregation = "pooled")
    session$setInputs(compute_diann = 5)
    expect_equal(nrow(rv$validated_data$data), 228)
    expect_match(output$input_scope_summary$html, "no cross-run aggregation")
    session$setInputs(diann_quality_filters = FALSE)
    expect_false(rv$data_loaded)
    session$setInputs(compute_diann = 6)
    expect_equal(nrow(rv$validated_data$data), 240)
    session$setInputs(diann_quality_filters = TRUE, diann_q_value = .05)
    session$setInputs(compute_diann = 7)
    expect_equal(nrow(rv$validated_data$data), 231)
    session$setInputs(diann_global_filters = FALSE)
    session$setInputs(compute_diann = 8)
    expect_equal(nrow(rv$validated_data$data), 234)
    session$setInputs(diann_channel_filter = TRUE)
    session$setInputs(compute_diann = 9)
    expect_equal(nrow(rv$validated_data$data), 231)
    session$setInputs(diann_pg_q_value = .1)
    session$setInputs(compute_diann = 10)
    expect_equal(nrow(rv$validated_data$data), 234)
    session$setInputs(clear_diann_files = 1)
    expect_false(rv$data_loaded)
    expect_match(output$diann_upload_queue$html, "0 file\\(s\\)")
    expect_true(file.exists(path))
  })
})

test_that("local source paths and run labels distinguish identical filenames without early compute", {
  withr::local_options(aidia.shiny.local_files = TRUE)
  env <- .diann_ui_env()
  root <- withr::local_tempdir(pattern = "path with spaces-")
  paths <- file.path(root, c("first run", "second run"), "features.parquet")
  for (i in seq_along(paths)) {
    dir.create(dirname(paths[i]))
    arrow::write_parquet(data.frame(run_name = c("run_01", "run_02")[i]), paths[i])
  }
  expect_error(env$.shiny_local_uploads("features.parquet"), "full paths")
  uploads <- env$.shiny_local_uploads(paste(sprintf('"%s"', paths), collapse = "\n"))
  expect_equal(uploads$source_path, normalizePath(paths, winslash = "/"))
  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(data_loaded = FALSE, optimization_complete = FALSE)
    env$server_data(input, output, session, rv, function() NULL)
  }
  shiny::testServer(server, {
    session$setInputs(input_type = "ms1_features", ms1_local_paths = paste(paths, collapse = "\n"), add_ms1_paths = 1)
    expect_false(rv$data_loaded)
    expect_null(rv$validated_data)
    expect_match(output$feature_upload_queue$html, "first run/features.parquet", fixed = TRUE)
    expect_match(output$feature_upload_queue$html, "second run/features.parquet", fixed = TRUE)
    expect_match(output$feature_upload_queue$html, "run_01", fixed = TRUE)
    expect_match(output$feature_upload_queue$html, "run_02", fixed = TRUE)
    session$setInputs(clear_feature_files = 1)
    expect_true(all(file.exists(paths)))
    session$setInputs(input_type = "diann", diann_local_paths = paste(paths, collapse = "\n"), add_diann_paths = 1)
    expect_match(output$diann_upload_queue$html, "0 file\\(s\\)")
  })
})
