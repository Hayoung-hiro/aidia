ms1_fixture <- function(n = 120L, run = "scout") {
  rt <- seq(1, 9, length.out = n)
  data.frame(run_name = run, feature_id = seq_len(n) - 1L,
    feature_uid = paste0(run, "#F", seq_len(n) - 1L),
    mz = c(seq(401, 450, length.out = n / 2), seq(451, 590, length.out = n / 2)),
    rt_start = rt - 0.1, rt_apex = rt, rt_end = rt + 0.3,
    rt_unit = "minute", fwhm = 0.12,
    fwhm_source = rep(c("alpharaw_summed_isotope_trace", "substituted_half_start_end"), length.out = n),
    charge = 2, intensity_apex = 100, intensity_sum = 1000, n_isotopes = 3, n_scans = 8)
}

id_fixture <- function(n = 120L, run = "scout") {
  f <- ms1_fixture(n, run)
  data.frame(Run = run, Precursor.Id = paste0("pep", seq_len(n)),
    Protein.Group = "protein", Precursor.Mz = rev(f$mz),
    RT.Start = f$rt_start, RT.Stop = f$rt_end, FWHM = 0.2,
    Q.Value = 0.001, PG.Q.Value = 0.001)
}

read_id_fixture <- function(data = id_fixture(), ...) {
  path <- tempfile(fileext = ".parquet")
  on.exit(unlink(path))
  arrow::write_parquet(data, path)
  create_validated_dataset(path, apply_quality_filters = FALSE, ...)
}

test_that("MS1 parquet input preserves apex, keys, provenance and original columns", {
  f <- ms1_fixture()
  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(f, path)
  x <- create_ms1_feature_dataset(path, provenance = list(extractor_commit = "abc"))
  expect_s3_class(x, "ValidatedData")
  expect_silent(validate_ValidatedData(x))
  expect_equal(x$data[names(f)], tibble::as_tibble(f))
  expect_equal(x$data$RT.Apex, f$rt_apex)
  expect_false(isTRUE(all.equal(x$data$RT.Apex, (f$rt_start + f$rt_end) / 2)))
  expect_identical(x$data$Feature.Key, f$feature_uid)
  expect_false(any(c("Precursor.Id", "Protein.Group", "Q.Value") %in% names(x$data)))
  expect_identical(x$metadata$feature_provenance$extraction$extractor_commit, "abc")
  expect_identical(x$metadata$source_runs, "scout")
  expect_identical(x$metadata$fwhm_unit, "minutes")
})

test_that("explicit units survive conversion, subsetting and broad FWHM", {
  f <- ms1_fixture()
  f$fwhm <- 1.5
  minutes <- create_ms1_feature_dataset(f)
  for (name in c("rt_start", "rt_apex", "rt_end", "fwhm")) f[[name]] <- f[[name]] * 60
  f$rt_unit <- "second"
  seconds <- create_ms1_feature_dataset(f)
  canonical <- c("RT.Start", "RT.Apex", "RT.Stop", "FWHM")
  expect_equal(seconds$data[canonical], minutes$data[canonical])
  expect_equal(get_fwhm_values(seconds), rep(90, nrow(f)))
  expect_equal(compute_data_summary(seconds)$fwhm_median_sec, 90)
  expect_equal(quick_dppp_preview(seconds)$fwhm_stats$median, 90)
  plan <- list(diagnosis = list(current_cycle_time_sec = 2),
    required_cycle_time_sec = 2, parameters = list(target_dppp = 4))
  expect_equal(extract_dppp_inputs(plan, seconds)$fwhm_data$FWHM_sec, rep(90, nrow(f)))
  expect_equal(plot_fwhm_distribution(seconds)$data$fwhm_sec, rep(90, nrow(f)))
  td <- calculate_precursor_temporal_density(c(500, 500), c(1, 2), c(1.5, 1.5),
    400, 600, 0, 3, fwhm_unit = "minutes")
  expect_equal(td$density_max, 2)
  f$fwhm <- 0.2
  expect_equal(get_fwhm_values(create_ms1_feature_dataset(f)), rep(0.2, nrow(f)))
})

test_that("missing, invalid, ambiguous and non-feature rows fail explicitly", {
  f <- ms1_fixture()
  for (name in c("mz", "rt_apex", "rt_start", "rt_end", "rt_unit", "fwhm", "fwhm_source")) {
    bad <- f
    bad[[name]] <- NULL
    expect_error(create_ms1_feature_dataset(bad), name, fixed = TRUE)
  }
  for (name in c("mz", "rt_apex", "rt_start", "rt_end", "fwhm")) {
    for (value in c(NA_real_, NaN, Inf)) {
      bad <- f
      bad[[name]][1] <- value
      expect_error(create_ms1_feature_dataset(bad), "finite")
    }
  }
  bad <- f; bad$rt_end[1] <- bad$rt_start[1]
  expect_error(create_ms1_feature_dataset(bad), "RT boundaries")
  bad <- f; bad$rt_apex[1] <- bad$rt_end[1] + 1
  expect_error(create_ms1_feature_dataset(bad), "RT boundaries")
  bad <- f; bad$fwhm[1] <- 0
  expect_error(create_ms1_feature_dataset(bad), "positive")
  bad <- f; bad$rt_unit <- "unknown"
  expect_error(create_ms1_feature_dataset(bad), "rt_unit")
  bad$rt_unit <- c("second", rep("minute", nrow(bad) - 1))
  expect_error(create_ms1_feature_dataset(bad), "consistent")
  bad <- f; bad$feature_id[2] <- bad$feature_id[1]
  expect_error(create_ms1_feature_dataset(bad), "unique")
  bad <- f; bad$feature_uid[1] <- "wrong"
  expect_error(create_ms1_feature_dataset(bad), "agree")
  bad <- f; bad$feature_id <- NULL; bad$feature_uid[2] <- bad$feature_uid[1]
  expect_error(create_ms1_feature_dataset(bad), "Duplicate")
  bad <- f; bad$scan_uid <- "scan1"
  expect_error(create_ms1_feature_dataset(bad), "feature-level")
  bad <- f; bad$charge[1] <- 1.5
  expect_error(create_ms1_feature_dataset(bad), "positive integers")
  expect_error(create_ms1_feature_dataset(f[FALSE, ]), "non-empty")
  f$feature_uid <- NULL
  expect_equal(create_ms1_feature_dataset(f)$data$Feature.Key, paste0("scout#F", f$feature_id))
})

test_that("runs are selected exactly and never matched by feature_id", {
  f <- rbind(ms1_fixture(run = "scout"), ms1_fixture(run = "scout2"))
  pooled <- create_ms1_feature_dataset(f)
  expect_equal(nrow(pooled$data), 240)
  expect_equal(pooled$metadata$n_runs, 2)
  expect_error(create_ms1_feature_dataset(f, "scou"), "absent")
  a <- create_ms1_feature_dataset(f, "scout")
  b <- create_ms1_feature_dataset(f, "scout2")
  expect_length(intersect(a$data$Feature.Key, b$data$Feature.Key), 0)
  expect_equal(nrow(a$data), 120)
  expect_equal(create_ms1_feature_dataset(f, c("scout", "scout2"))$data, pooled$data)
})

test_that("legacy ID validation keeps midpoint, identities and default consensus", {
  f <- id_fixture()
  single <- read_id_fixture(f)
  expect_equal(single$data$RT.Apex, (f$RT.Start + f$RT.Stop) / 2)
  expect_identical(single$data$Precursor.Id, f$Precursor.Id)
  expect_identical(single$data$Protein.Group, f$Protein.Group)
  multi <- rbind(f, id_fixture(run = "scout2"))
  consensus <- read_id_fixture(multi)
  expect_equal(nrow(consensus$data), nrow(f))
  expect_equal(consensus$metadata$n_runs, 2)
  selected <- read_id_fixture(multi, run_name = "scout")
  expect_equal(selected$data, single$data)
  expect_identical(selected$metadata$source_runs, "scout")
  expect_error(read_id_fixture(multi, run_name = "scou"), "absent")
})

test_that("MS1 data flows through existing planning, windows, density plot and export", {
  ms1 <- create_ms1_feature_dataset(ms1_fixture())
  plan <- plan_optimization(ms1, current_cycle_time = 2, instrument_preset = "exploris",
                            target_dppp = 4, target_satisfaction = 0.8)
  plan$window_count_per_bin <- 8L
  windows <- optimize_windows(ms1, plan, strategy_config = quantile_config(apply_smoothing = FALSE),
    rt_bin_width_min = 5, mz_range_min = 400, mz_range_max = 600, fz_offset = 0)
  expect_silent(validate_OptimizedWindows(windows))
  file <- withr::local_tempfile(fileext = ".csv")
  export_windows_to_csv(windows, file, ms1)
  expect_equal(ncol(read.csv(file)), 8)
  expect_gt(nrow(read.csv(file)), 0)
})

test_that("fixed comparison preserves budget, empty bins, common evaluation and export geometry", {
  id <- read_id_fixture()
  ms1 <- create_ms1_feature_dataset(ms1_fixture())
  plan <- plan_optimization(id, current_cycle_time = 2, instrument_preset = "exploris",
                            target_dppp = 4, target_satisfaction = 0.8)
  # Explicit test reference: an intentionally under-sampled budget.
  plan$window_count_per_bin <- 4L
  plan$actual_cycle_time_sec <- 10
  original <- plan
  context <- list(sample = "fixture", lc_condition = "same run", settings_source = "test reference")
  result <- compare_input_maps(id, ms1, plan, c(0, 5, 10, 15), c(400, 600), context)
  expect_identical(result$reference_plan, original)
  expect_identical(plan, original)
  for (design in result$designs) {
    expect_equal(as.integer(table(design$windows$rt_segment_id)), rep(4L, 3))
    expect_equal(as.numeric(tapply(design$windows$mz_start, design$windows$rt_segment_id, min)),
                 rep(400, 3))
    expect_equal(max(design$windows$rt_end), 15)
  }
  expect_true(any(result$design_differences$delta_center_da != 0))
  expect_true(all(result$satisfaction$cycle_time_sec == 10))
  expect_true(all(!result$satisfaction$meets_target))
  expect_equal(result$satisfaction$n_total[result$satisfaction$fwhm_source == "all sources"], rep(120, 3))
  expect_true(all(result$inclusion$covered))
  for (design in names(result$designs)) {
    w <- result$designs[[design]]$windows
    brute <- vapply(seq_len(nrow(w)), function(i) {
      d <- ms1$data
      sum(d$RT.Apex >= w$rt_start[i] & d$RT.Apex < w$rt_end[i] &
          d$Precursor.Mz >= w$mz_start[i] & d$Precursor.Mz < w$mz_end[i])
    }, integer(1))
    expect_equal(result$window_loads$n_evaluation_features[result$window_loads$design == design], brute)
  }
  out <- withr::local_tempdir()
  export_input_map_comparison(result, out)
  csv <- read.csv(file.path(out, "ms1_method.csv"), check.names = FALSE)
  expect_equal(csv[["t start (min)"]], result$designs$ms1$windows$rt_start)
  expect_equal(csv[["m/z"]] - csv[["Isolation Window (m/z)"]] / 2,
               result$designs$ms1$windows$mz_start)
  expect_equal(readRDS(file.path(out, "comparison.rds")), result)
  expect_error(export_input_map_comparison(result, out), "never overwritten")
  expect_error(compare_input_maps(id, create_ms1_feature_dataset(ms1_fixture(run = "other")),
    plan, c(0, 10), c(400, 600), context), "same source run set")
  expect_error(compare_input_maps(id, ms1, plan, c(0, 10.001), c(400, 600), context), "precision")
  expect_error(compare_input_maps(id, ms1, plan, c(0, 10), c(400, 402), context), "fixed count")
})

test_that("comparison includes outer edges once and reports out-of-scope and empty denominators", {
  f <- ms1_fixture()
  f$rt_apex[1:3] <- c(0, 5, 10)
  f$rt_start[1:3] <- pmax(0, f$rt_apex[1:3] - 0.1)
  f$rt_end[1:3] <- f$rt_apex[1:3] + 0.2
  f$mz[1:4] <- c(400, 500, 600, 601)
  ms1 <- create_ms1_feature_dataset(f)
  id <- read_id_fixture()
  plan <- plan_optimization(id, current_cycle_time = 2, instrument_preset = "exploris",
    target_dppp = 4, target_satisfaction = 0.8, ms2_resolution = 30000)
  plan$window_count_per_bin <- 4L
  ctx <- list(sample = "test", lc_condition = "test", settings_source = "test reference")
  result <- compare_input_maps(id, ms1, plan, c(0, 5, 10), c(400, 600), ctx)
  rows <- subset(result$inclusion, evaluation_map == "evaluation_ms1")
  expect_equal(sum(!rows$covered), 2) # The same out-of-scope row in each design.
  expect_equal(aggregate(n_evaluation_features ~ design, result$window_loads, sum)$n_evaluation_features,
               rep(119, 2))
  empty <- compare_input_maps(id, ms1, plan, c(11, 12), c(400, 600), ctx)
  expect_equal(empty$satisfaction$n_total, rep(0, 3))
  expect_true(all(is.na(empty$satisfaction$predicted_satisfaction)))
  expect_true(all(empty$window_loads$n_evaluation_features == 0))
})

test_that("Shiny loads the selected input mode and invalidates incompatible results", {
  env <- new.env(parent = environment())
  for (pkg in c("shiny", "bs4Dash")) {
    for (name in getNamespaceExports(pkg)) env[[name]] <- getExportedValue(pkg, name)
  }
  for (file in c("diann_input_options.R", "server_feature_uploads.R", "server_data.R"))
    sys.source(system.file("shiny_app", file, package = "aidia", mustWork = TRUE), env)
  feature_path <- withr::local_tempfile(fileext = ".parquet")
  id_path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(ms1_fixture(), feature_path)
  arrow::write_parquet(id_fixture(), id_path)
  upload <- function(path) data.frame(name = basename(path), size = file.info(path)$size,
                                     type = "application/octet-stream", datapath = path)
  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(data_loaded = FALSE, optimization_complete = FALSE)
    env$server_data(input, output, session, rv, function() NULL)
  }
  shiny::testServer(server, {
    session$setInputs(target_dppp = 4, target_satisfaction = 80, input_type = "ms1_features",
                     ms1_files = upload(feature_path))
    expect_false(rv$data_loaded)
    session$setInputs(compute_features = 1)
    expect_true(rv$data_loaded)
    expect_equal(rv$validated_data$data$RT.Apex, ms1_fixture()$rt_apex)
    rv$optimization_complete <- TRUE
    session$setInputs(input_type = "diann")
    expect_false(rv$data_loaded)
    expect_false(rv$optimization_complete)
    expect_null(rv$validated_data)
    session$setInputs(parquet_file = upload(id_path))
    expect_false(rv$data_loaded)
    session$setInputs(compute_diann = 1)
    expect_true(rv$data_loaded)
    expect_true("Protein.Group" %in% names(rv$validated_data$data))
  })
})
