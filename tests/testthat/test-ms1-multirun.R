multi_feature_fixture <- function(run, offset = 0, seconds = FALSE) {
  rt <- seq(1, 9, length.out = 120) + offset
  d <- data.frame(run_name = run, feature_id = seq_len(120),
    mz = seq(401, 590, length.out = 120), rt_start = rt - .1,
    rt_apex = rt, rt_end = rt + .2, rt_unit = "minute", fwhm = .12,
    fwhm_source = "alpharaw_summed_isotope_trace", charge = 2,
    export_id = "joint-export", feature_group_id = paste0("group", seq_len(120)))
  if (seconds) {
    d[c("rt_start", "rt_apex", "rt_end", "fwhm")] <- d[c("rt_start", "rt_apex", "rt_end", "fwhm")] * 60
    d$rt_unit <- "second"
  }
  d
}

test_that("joint export files and combined parquet yield identical consensus", {
  a <- multi_feature_fixture("sampleA_30min", 0)
  b <- multi_feature_fixture("sampleB_60min", .04, seconds = TRUE)
  c <- multi_feature_fixture("third", .08)[-1, ]
  # Labels are deliberately incompatible: suitability is advisory, not a gate.
  paths <- vapply(seq_len(3), function(i) tempfile(fileext = ".parquet"), character(1))
  on.exit(unlink(paths))
  for (i in seq_len(3)) arrow::write_parquet(list(a, b, c)[[i]], paths[i])
  x <- create_ms1_feature_dataset(paths)
  combined <- create_ms1_feature_dataset(dplyr::bind_rows(a, b, c))
  expect_equal(x$data, combined$data)
  expect_equal(x$metadata$n_runs, 3)
  expect_equal(x$metadata$min_replicates, 2)
  expect_equal(x$metadata$n_input_features, 359)
  expect_equal(nrow(x$data), 120)
  expect_equal(x$data$RT.Apex[x$data$feature_group_id == "group1"], 1.02)
  expect_equal(unique(x$data$FWHM), .12)
  expect_equal(nrow(x$feature_observations), 359)
  expect_silent(validate_ValidatedData(x))
  strict <- create_ms1_feature_dataset(paths, min_replicates = 3)
  expect_equal(nrow(strict$data), 119)
  selected <- create_ms1_feature_dataset(paths, run_name = c("sampleA_30min", "third"))
  expect_equal(selected$metadata$n_runs, 2)
  expect_equal(selected$metadata$min_replicates, 1)
  expect_false(any(c("Precursor.Id", "Protein.Group") %in% names(x$data)))
})

test_that("pooling preserves detections and duplicate uploads never count twice", {
  f <- dplyr::bind_rows(multi_feature_fixture("A"), multi_feature_fixture("B"))
  f$feature_group_id <- f$export_id <- NULL
  x <- create_ms1_feature_dataset(f)
  expect_equal(nrow(x$data), 240)
  expect_equal(length(unique(x$data$Feature.Key)), 240)
  expect_equal(x$metadata$feature_aggregation, "pooled")
  expect_error(create_ms1_feature_dataset(rbind(f, f)), "unique|Duplicate")
  expect_error(create_ms1_feature_dataset(f, aggregation = "consensus"), "export_id")
  f <- dplyr::bind_rows(multi_feature_fixture("A"), multi_feature_fixture("B"))
  f$export_id[f$run_name == "B"] <- "independent-export"
  expect_error(create_ms1_feature_dataset(f), "joint alphaextract export_id")
  expect_equal(nrow(create_ms1_feature_dataset(f, aggregation = "pooled")$data), 240)
  f$export_id <- "joint-export"
  f$feature_group_id[2] <- f$feature_group_id[1]
  expect_error(create_ms1_feature_dataset(f), "at most one")
})

test_that("aligned coordinates preserve native widths and consensus contract", {
  a <- multi_feature_fixture("A")
  b <- multi_feature_fixture("B", .5)
  a$rt_shift_min <- 0
  b$rt_shift_min <- -.5
  x <- create_ms1_feature_dataset(rbind(a, b))
  expect_equal(x$data$RT.Apex[match(a$feature_group_id, x$data$feature_group_id)], a$rt_apex)
  expect_equal(unique(x$data$FWHM), .12)
  bad <- x; bad$data$RT.Apex[1] <- bad$data$RT.Apex[1] + .1
  expect_error(validate_ValidatedData(bad), "consensus")
  bad <- x; bad$feature_observations <- NULL
  expect_error(validate_ValidatedData(bad), "feature_observations")
})

test_that("multi-run comparison freezes the plan and evaluates all detections", {
  features <- rbind(multi_feature_fixture("A"), multi_feature_fixture("B", .02))
  path <- withr::local_tempfile(fileext = ".parquet")
  ids <- data.frame(Run = features$run_name, Precursor.Id = features$feature_group_id,
    Protein.Group = "protein", Precursor.Mz = features$mz, RT.Start = features$rt_start,
    RT.Stop = features$rt_end, FWHM = features$fwhm)
  arrow::write_parquet(ids, path)
  id <- create_validated_dataset(path, run_name = c("B", "A"), apply_quality_filters = FALSE)
  expect_equal(id$metadata$n_runs, 2)
  expect_equal(nrow(id$data), 120)
  expect_error(create_validated_dataset(path, run_name = c("A", "missing")), "absent")
  ms1 <- create_ms1_feature_dataset(features)
  evaluation <- create_ms1_feature_dataset(features, aggregation = "pooled")
  plan <- plan_optimization(id, current_cycle_time = 2, instrument_preset = "exploris",
    target_dppp = 4, target_satisfaction = .8)
  plan$window_count_per_bin <- 8L
  context <- list(sample = "same selected runs", lc_condition = "user-selected batch",
    settings_source = "fixture reference")
  x <- compare_input_maps(id, ms1, plan, c(0, 5, 10), c(400, 600), context,
    evaluation_data = evaluation)
  expect_identical(x$reference_plan, plan)
  expect_equal(x$settings$n_windows_per_bin, 8)
  expect_equal(x$input_counts$n_runs, rep(2, 3))
  expect_equal(x$input_counts$n_input, c(120, 120, 240))
  expect_equal(sum(x$window_loads$n_evaluation_features[x$window_loads$design == "id"]), 240)
  expect_error(compare_input_maps(id, create_ms1_feature_dataset(features, "A"), plan,
    c(0, 5, 10), c(400, 600), context), "same source run set")
})

test_that("multi-run Shiny upload applies selected aggregation and shows run scope", {
  env <- new.env(parent = environment())
  for (pkg in c("shiny", "bs4Dash")) {
    for (name in getNamespaceExports(pkg)) env[[name]] <- getExportedValue(pkg, name)
  }
  for (file in c("diann_input_options.R", "server_feature_uploads.R", "server_data.R"))
    sys.source(system.file("shiny_app", file, package = "aidia", mustWork = TRUE), env)
  paths <- vapply(1:2, function(i) tempfile(fileext = ".parquet"), character(1))
  on.exit(unlink(paths))
  arrow::write_parquet(multi_feature_fixture("A"), paths[1])
  arrow::write_parquet(multi_feature_fixture("B", .02), paths[2])
  upload <- data.frame(name = rep("features.parquet", 2), size = file.info(paths)$size,
    type = "application/octet-stream", datapath = paths)
  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(data_loaded = FALSE, optimization_complete = FALSE)
    env$server_data(input, output, session, rv, function() NULL)
  }
  shiny::testServer(server, {
    session$setInputs(target_dppp = 4, target_satisfaction = 80, input_type = "ms1_features",
      ms1_aggregation = "auto", ms1_min_runs = 0, ms1_files = upload)
    expect_false(rv$data_loaded)
    session$setInputs(compute_features = 1)
    expect_true(rv$data_loaded)
    expect_equal(nrow(rv$validated_data$data), 120)
    expect_match(output$input_scope_summary$html, "2 run")
    rv$optimization_complete <- TRUE
    session$setInputs(ms1_aggregation = "pooled")
    expect_false(rv$data_loaded)
    expect_false(rv$optimization_complete)
    expect_null(rv$validated_data)
    session$setInputs(compute_features = 2)
    expect_true(rv$data_loaded)
    expect_equal(nrow(rv$validated_data$data), 240)
    session$setInputs(input_type = "diann")
    expect_false(rv$data_loaded)
    expect_null(rv$data_error)
  })
})

test_that("MS1 selections accumulate safely until Compute and can be removed or reset", {
  env <- new.env(parent = environment())
  for (pkg in c("shiny", "bs4Dash")) {
    for (name in getNamespaceExports(pkg)) env[[name]] <- getExportedValue(pkg, name)
  }
  for (file in c("diann_input_options.R", "server_feature_uploads.R", "server_data.R"))
    sys.source(system.file("shiny_app", file, package = "aidia", mustWork = TRUE), env)
  root <- withr::local_tempdir()
  paths <- file.path(root, 1:3, "features.parquet")
  for (i in seq_along(paths)) {
    dir.create(dirname(paths[i]))
    arrow::write_parquet(multi_feature_fixture(LETTERS[i], .02 * i), paths[i])
  }
  duplicate <- file.path(root, "duplicate.parquet")
  file.copy(paths[1], duplicate)
  malformed <- file.path(root, "invalid.parquet")
  arrow::write_parquet(data.frame(unrelated = 1), malformed)
  upload <- function(path) data.frame(name = basename(path), size = file.info(path)$size,
    type = "application/octet-stream", datapath = path)
  retained <- new.env()
  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(data_loaded = FALSE, optimization_complete = FALSE)
    env$server_data(input, output, session, rv, function() NULL)
  }
  shiny::testServer(server, {
    session$setInputs(target_dppp = 4, target_satisfaction = 80, input_type = "ms1_features",
      ms1_aggregation = "auto", ms1_min_runs = 0)
    session$setInputs(compute_features = 1)
    expect_false(rv$data_loaded)
    for (i in seq_along(paths)) {
      session$setInputs(ms1_files = upload(paths[i]))
      expect_false(rv$data_loaded)
      expect_null(rv$validated_data)
      expect_match(output$feature_upload_queue$html, sprintf("%d file\\(s\\)", i))
      # Simulate Shiny discarding each previous upload's temporary file.
      unlink(paths[i])
    }
    session$setInputs(ms1_files = upload(duplicate))
    expect_match(output$feature_upload_queue$html, "3 file\\(s\\)")
    session$setInputs(compute_features = 2)
    expect_true(rv$data_loaded)
    expect_equal(rv$validated_data$metadata$source_runs, LETTERS[1:3])
    expect_equal(rv$validated_data$metadata$min_replicates, 2)
    expect_equal(nrow(rv$data_files), 3)
    expect_match(output$sidebar_data_summary$html, "3 file\\(s\\), 3 run\\(s\\)")
    staged <- rv$data_files$datapath
    retained$dir <- dirname(staged[1])
    expect_true(all(file.exists(staged)))
    rv$optimization_complete <- TRUE
    rv$confirmed_run <- list(test = TRUE)
    session$setInputs(remove_feature_file = "2")
    expect_false(file.exists(staged[2]))
    expect_false(rv$data_loaded)
    expect_false(rv$optimization_complete)
    expect_null(rv$confirmed_run)
    expect_null(rv$dppp_preview)
    session$setInputs(compute_features = 3)
    expect_equal(rv$validated_data$metadata$source_runs, c("A", "C"))
    session$setInputs(ms1_min_runs = 3)
    expect_false(rv$data_loaded)
    session$setInputs(compute_features = 4)
    expect_false(rv$data_loaded)
    expect_true(nzchar(rv$data_error))
    session$setInputs(ms1_min_runs = 0, ms1_files = upload(malformed))
    session$setInputs(compute_features = 5)
    expect_false(rv$data_loaded)
    expect_null(rv$validated_data)
    expect_true(nzchar(rv$data_error))
    session$setInputs(remove_feature_file = "4")
    session$setInputs(compute_features = 7)
    expect_true(rv$data_loaded)
    session$setInputs(clear_feature_files = 1)
    expect_false(rv$data_loaded)
    expect_match(output$feature_upload_queue$html, "0 file\\(s\\)")
    expect_false(any(file.exists(staged)))
    expect_true(file.exists(duplicate))
    session$setInputs(ms1_files = upload(duplicate))
    session$setInputs(compute_features = 9)
    expect_true(rv$data_loaded)
    session$setInputs(btn_new_analysis = 1)
    expect_false(rv$data_loaded)
    expect_match(output$feature_upload_queue$html, "0 file\\(s\\)")
    # Leave a file queued to verify cleanup on session end, too.
    session$setInputs(ms1_files = upload(duplicate))
    expect_length(list.files(retained$dir), 1)
  })
  expect_false(dir.exists(retained$dir))
  expect_true(file.exists(duplicate))
})
