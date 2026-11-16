.native_fixture <- function() {
  path <- tempfile(fileext = ".meth")
  writeBin(charToRaw("test template"), path)
  scan <- list(resolution = 60000, max_it_mode = "Custom", max_it_ms = 60,
               agc_percent = 250, agc_absolute = 2500000)
  context <- structure(list(template_path = normalizePath(path, winslash = "/"),
    filename = "input.meth", sha256 = paste(rep("a", 64), collapse = ""),
    instrument = "exploris", model = "Orbitrap Exploris 480", native_write = TRUE,
    duration_min = 50, ms1 = scan,
    ms2 = modifyList(scan, list(resolution = 30000, max_it_mode = "Auto", agc_percent = 500)),
    ms1_scans_per_cycle = 1L, window_count = 28L, mz_min = 395, mz_max = 955),
    class = c("ThermoMethodContext", "list"))
  windows <- data.frame(rt_segment_id = rep(1:2, each = 2),
    rt_start = c(5, 5, 16, 16), rt_end = c(14, 14, 25, 25),
    mz_start = c(400, 420, 410, 440), mz_end = c(420, 460, 440, 500))
  result <- structure(list(windows = windows, parameters = list(),
    metadata = list(instrument_preset = "exploris")), class = "OptimizedWindows")
  list(method = context, result = result)
}

.astral_native_fixture <- function() {
  f <- .native_fixture()
  f$method$instrument <- f$result$metadata$instrument_preset <- "astral_zoom"
  f$method$model <- "Orbitrap Astral Zoom"
  f$method$duration_min <- 30
  f$method$ms1 <- list(resolution = 240000, max_it_mode = "Custom", max_it_ms = 10,
    agc_percent = 500, agc_absolute = 5000000)
  f$method$ms2 <- list(resolution = NULL, max_it_mode = "Custom", max_it_ms = 5,
    agc_percent = 500, agc_absolute = 50000)
  f$method$window_count <- 300L
  f
}

test_that("Astral export uses parallel controls and preserves a physical MS1 experiment", {
  f <- .astral_native_fixture()
  withr::defer(unlink(f$method$template_path))
  settings <- list(instrument = "astral_zoom", astral_ms1_resolution = "120000",
    astral_ms2_it = 6, ms1_it_auto = FALSE, ms1_it_custom = 12,
    ms1_agc = 400, ms2_agc = 600, ms1_scans_per_cycle = 0,
    ms1_resolution = 60000, ms2_resolution = 15000, ms2_it_auto = TRUE, ms2_it_custom = 99)
  request <- .prepare_native_request(f$result, f$method, settings)
  expect_equal(request$acquisition$ms1$resolution, 120000)
  expect_equal(request$acquisition$ms1$max_it_ms, 12)
  expect_equal(request$acquisition$ms1$agc_percent, 400)
  expect_null(request$acquisition$ms2$resolution)
  expect_equal(request$acquisition$ms2$max_it_mode, "Custom")
  expect_equal(request$acquisition$ms2$max_it_ms, 6)
  expect_equal(request$acquisition$ms2$agc_percent, 600)
  expect_equal(request$acquisition$ms1_scans_per_cycle, 1L)
  expect_identical(.thermo_acquisition(f$method)$ms2, f$method$ms2)
  settings$instrument <- "exploris"
  expect_error(.prepare_native_request(f$result, f$method, settings), "instrument")
})

test_that("Astral upload fills the active Shiny controls without an MS2 resolution", {
  f <- .astral_native_fixture()
  withr::defer(unlink(f$method$template_path))
  env <- new.env(parent = environment())
  for (name in getNamespaceExports("shiny")) env[[name]] <- getExportedValue("shiny", name)
  sys.source(system.file("shiny_app", "server_method.R", package = "aidia", mustWork = TRUE), env)
  updates <- list()
  env$updateNumericInput <- env$updateCheckboxInput <- env$updateSliderInput <-
    function(session, inputId, value, ...) updates[[inputId]] <<- value
  env$updateSelectInput <- function(session, inputId, selected, ...) updates[[inputId]] <<- selected
  env$inspect_thermo_method <- function(path) { x <- f$method; x$template_path <- path; x }
  env$showNotification <- env$removeNotification <- function(...) NULL
  shiny::testServer(function(input, output, session) {
    rv <- shiny::reactiveValues(confirmed_run = NULL)
    env$server_method(input, output, session, rv)
  }, {
    session$setInputs(method_file = data.frame(name = "misleading_exploris.meth", size = 12,
      datapath = f$method$template_path))
    expect_equal(updates$instrument, "astral_zoom")
    expect_equal(updates$astral_ms1_resolution, "240000")
    expect_equal(updates$astral_ms2_it, 5)
    expect_equal(updates$ms1_it_custom, 10)
    expect_false(updates$ms1_it_auto)
    expect_equal(updates$ms1_agc, 500)
    expect_equal(updates$ms2_agc, 500)
    expect_null(updates$ms2_resolution)
    expect_equal(updates$current_window_count, 300)
  })
})

test_that("installed Astral Zoom runtime delivers scheduled tMS2 from DIA and tMS2 templates", {
  path <- Sys.getenv("AIDIA_TEST_ASTRAL_METHOD")
  skip_if(!nzchar(path), "Set AIDIA_TEST_ASTRAL_METHOD to the Astral Zoom 30-minute DIA fixture.")
  context <- inspect_thermo_method(path)
  expect_equal(context$instrument, "astral_zoom")
  expect_equal(context$ms2_scan_type, "DIA")
  expect_equal(context$native_output_scan_type, "tMS2")
  expect_equal(context$model, "Orbitrap Astral Zoom")
  expect_equal(context$ms1$resolution, 240000)
  expect_null(context$ms2$resolution)
  expect_equal(context$ms2$max_it_ms, 5)
  expect_equal(context$window_count, 300)
  expect_equal(context$time_mode, "Unscheduled")
  expect_equal(context$rows$start, rep(0, 300))
  expect_equal(context$rows$end, rep(30, 300))
  expect_equal(context$mz_min, 380.4228)
  expect_equal(context$expected_peak_width_sec, 6)
  f <- .astral_native_fixture()
  withr::defer(unlink(f$method$template_path))
  output <- withr::local_tempfile(fileext = ".meth")
  settings <- list(instrument = "astral_zoom", astral_ms1_resolution = "120000",
    astral_ms2_it = 6, ms1_it_auto = FALSE, ms1_it_custom = 12,
    ms1_agc = 400, ms2_agc = 600, ms1_scans_per_cycle = 0)
  export_thermo_method(f$result, output, context, settings, fill_void = TRUE, charge_state = 0L)
  readback <- inspect_thermo_method(output)
  expect_equal(readback$instrument, "astral_zoom")
  expect_equal(readback$ms1$resolution, 120000)
  expect_equal(readback$ms1$agc_percent, 400)
  expect_equal(readback$ms1$max_it_ms, 12)
  expect_equal(readback$ms2$agc_percent, 600)
  expect_equal(readback$ms2$max_it_ms, 6)
  expect_null(readback$ms2$resolution)
  expect_equal(readback$expected_peak_width_sec, context$expected_peak_width_sec)
  expect_equal(readback$time_mode, "StartEndTime")
  expect_equal(readback$ms2_scan_type, "tMS2")
  expect_equal(readback$ms2_experiment_name, "tMS2")
  expect_equal(readback$ms2_experiment_count, 1)
  expect_equal(readback$dia_experiment_count, 0)
  expect_setequal(readback$editor_columns, c("CompoundName", "Formula", "AdductPositive",
    "MoverZ", "Z", "StartTime", "EndTime", "IsolationWindow"))
  expect_equal(readback$rows$width, c(20, 40, 30, 60))
  expect_equal(readback$rows$start, c(0, 0, 15, 15))
  expect_equal(readback$rows$end, c(15, 15, 30, 30))
  expect_equal(readback$rows$charge, rep(0, 4))
  fractional <- f$result
  fractional$windows$rt_start <- c(0, 0, 6.68, 6.68)
  fractional$windows$rt_end <- c(6.68, 6.68, 30, 30)
  export_thermo_method(fractional, output, context, settings, charge_state = 0L)
  fractional_readback <- inspect_thermo_method(output)
  expect_equal(fractional_readback$rows$start, fractional$windows$rt_start, tolerance = 1e-9)
  expect_equal(fractional_readback$rows$end, fractional$windows$rt_end, tolerance = 1e-9)
  invalid <- .prepare_native_request(fractional, context, settings, charge_state = 0L)
  invalid$windows$end[3:4] <- 31
  invalid$output <- withr::local_tempfile(fileext = ".meth")
  expect_error(.thermo_helper_call(invalid), "acquisition bounds")
  f$result$windows <- rbind(transform(f$result$windows, cycle = 2L),
    transform(f$result$windows, cycle = 1L))
  f$result$windows$mz_start <- rep(c(400.1234, 402.1243, 410.4123, 414.4141), 2)
  f$result$windows$mz_end <- f$result$windows$mz_start + rep(c(2.0009, 5.0023, 4.0018, 6.0027), 2)
  expected <- .prepare_native_request(f$result, context, settings)$windows
  export_thermo_method(f$result, output, context, settings, charge_state = 0L)
  staggered <- inspect_thermo_method(output)
  expect_equal(staggered$loop_control, "Count")
  expect_equal(staggered$loop_count, 2)
  expect_equal(staggered$rows$width, expected$width, tolerance = 1e-9)
  expect_equal(staggered$rows$mz, expected$mz, tolerance = 1e-9)
  expect_equal(staggered$rows$compound, expected$compound)
  expect_equal(staggered$ms2_scan_type, "tMS2")
  expect_equal(staggered$ms2_experiment_count, 1)
  expect_equal(staggered$rows$start, expected$start)
  expect_equal(staggered$rows$end, expected$end)
  charged_output <- withr::local_tempfile(fileext = ".meth")
  export_thermo_method(f$result, charged_output, context, settings, charge_state = 2L)
  expect_equal(inspect_thermo_method(charged_output)$rows$charge, rep(2, 8))
  # Re-export from the resulting tMS2 template, preserving all RT groups in one list.
  second_output <- withr::local_tempfile(fileext = ".meth")
  export_thermo_method(f$result, second_output, staggered, settings, charge_state = 0L)
  second_readback <- inspect_thermo_method(second_output)
  expect_equal(second_readback$ms2_experiment_count, 1)
  expect_equal(second_readback$ms2_experiment_name, "tMS2")
  expect_equal(second_readback$time_mode, "StartEndTime")
  expect_equal(second_readback$rows$mz, expected$mz, tolerance = 1e-9)
  expect_equal(inspect_thermo_method(path)$sha256, context$sha256)
  withr::local_options(aidia.thermo.runtime = 'C:/Program Files/Thermo Scientific/Instruments/Exploris/5.1')
  expect_error(inspect_thermo_method(path), "Astral Workstation 2.2 SP1", fixed = TRUE)
})

test_that("Astral segmented DIA templates consolidate into one scheduled tMS2 experiment", {
  path <- Sys.getenv("AIDIA_TEST_ASTRAL_SEGMENTED_METHOD")
  skip_if(!nzchar(path), "Set AIDIA_TEST_ASTRAL_SEGMENTED_METHOD to a segmented Astral DIA fixture.")
  context <- inspect_thermo_method(path)
  expect_equal(context$ms2_scan_type, "DIA")
  expect_gt(context$dia_experiment_count, 1)
  windows <- data.frame(rt_start = context$rows$start, rt_end = context$rows$end,
    mz_start = context$rows$mz - context$rows$width / 2,
    mz_end = context$rows$mz + context$rows$width / 2)
  windows$rt_segment_id <- match(windows$rt_start, unique(windows$rt_start))
  result <- structure(list(windows = windows, parameters = list(),
    metadata = list(instrument_preset = "astral_zoom")), class = "OptimizedWindows")
  output <- withr::local_tempfile(fileext = ".meth")
  export_thermo_method(result, output, context, charge_state = 0L)
  actual <- inspect_thermo_method(output)
  expect_equal(actual$ms2_scan_type, "tMS2")
  expect_equal(actual$ms2_experiment_name, "tMS2")
  expect_equal(actual$ms2_experiment_count, 1)
  expect_equal(actual$time_mode, "StartEndTime")
  expect_equal(actual$rows$mz, context$rows$mz, tolerance = 1e-9)
  expect_equal(actual$rows$width, context$rows$width, tolerance = 1e-9)
  expect_equal(actual$rows$start, context$rows$start, tolerance = 1e-9)
  expect_equal(actual$rows$end, context$rows$end, tolerance = 1e-9)
  expect_equal(actual$ms1, context$ms1)
  expect_equal(actual$ms2, context$ms2)
  expect_equal(actual$expected_peak_width_sec, context$expected_peak_width_sec)
  expect_equal(inspect_thermo_method(path)$sha256, context$sha256)
})

test_that("Astral import rejects columns the installed Method Editor cannot load", {
  path <- Sys.getenv("AIDIA_TEST_ASTRAL_BAD_METHOD")
  skip_if(!nzchar(path), "Set AIDIA_TEST_ASTRAL_BAD_METHOD to the pre-fix DIA column regression fixture.")
  expect_error(inspect_thermo_method(path), "DIA.*unsupported.*CompoundName")
})

test_that("native templates preserve fragment ranges and reject unmodeled row overrides", {
  path <- Sys.getenv("AIDIA_TEST_ASTRAL_METHOD")
  skip_if(!nzchar(path), "Set AIDIA_TEST_ASTRAL_METHOD for vendor integration.")
  skip_if(.Platform$OS.type != "windows")
  compiler <- file.path(Sys.getenv("WINDIR"), "Microsoft.NET", "Framework64", "v4.0.30319", "csc.exe")
  skip_if_not(file.exists(compiler), "Fixture builder requires the .NET Framework compiler.")
  directory <- withr::local_tempdir()
  source <- file.path(directory, "source.meth")
  context <- inspect_thermo_method(path)
  f <- .astral_native_fixture()
  withr::defer(unlink(f$method$template_path))
  export_thermo_method(f$result, source, context, charge_state = 0L)
  executable <- file.path(directory, "variants.exe")
  build <- system2(compiler, shQuote(c("/nologo", "/target:exe", "/platform:x64", "/r:System.Core.dll",
    paste0("/out:", executable), normalizePath(test_path("fixtures", "ThermoMethodVariants.cs"), winslash = "\\"))),
    stdout = TRUE, stderr = TRUE)
  expect_null(attr(build, "status"), info = paste(build, collapse = "\n"))
  runtime <- getOption("aidia.thermo.runtime", file.path(Sys.getenv("ProgramFiles"),
    "Thermo Scientific", "Instruments", "Astral", "2.2"))
  generated <- system2(executable, shQuote(c(file.path(runtime, "System", "Programs", "dependencies", "tng"),
    source, directory)), stdout = TRUE, stderr = TRUE)
  expect_null(attr(generated, "status"), info = paste(generated, collapse = "\n"))
  expect_error(inspect_thermo_method(file.path(directory, "row-it.meth")), "per-row.*MaxITTime")
  expect_error(inspect_thermo_method(file.path(directory, "row-agc.meth")), "per-row.*AgcTarget")
  varying <- inspect_thermo_method(file.path(directory, "mixed-fragments.meth"))
  output <- file.path(directory, "result.meth")
  expect_error(export_thermo_method(f$result, output, varying, charge_state = 0L), "differing per-row acquisition")
  expect_false(file.exists(output))
  uniform <- inspect_thermo_method(file.path(directory, "uniform-fragments.meth"))
  export_thermo_method(f$result, output, uniform, charge_state = 0L)
  expect_true("FirstLastMass" %in% inspect_thermo_method(output)$editor_columns)
  verified <- system2(executable, shQuote(c(file.path(runtime, "System", "Programs", "dependencies", "tng"),
    output, "--verify-fragments")), stdout = TRUE, stderr = TRUE)
  expect_null(attr(verified, "status"), info = paste(verified, collapse = "\n"))
})

test_that("import counts concurrent scheduled windows and treats adjacent RT bounds as one transition", {
  path <- Sys.getenv("AIDIA_TEST_ASTRAL_METHOD")
  skip_if(!nzchar(path), "Set AIDIA_TEST_ASTRAL_METHOD for vendor integration.")
  context <- inspect_thermo_method(path)
  f <- .astral_native_fixture()
  withr::defer(unlink(f$method$template_path))
  request <- .prepare_native_request(f$result, context, charge_state = 0L)
  request$windows$start <- c(0, 5, 10, 15)
  request$windows$end <- c(10, 15, 20, 20)
  request$output <- withr::local_tempfile(fileext = ".meth")
  .thermo_helper_call(request)
  actual <- inspect_thermo_method(request$output)
  expect_equal(actual$window_count, 2)
  expect_equal(actual$rows$start, request$windows$start)
  expect_equal(actual$rows$end, request$windows$end)
})

test_that("Astral timing uses imported MS1 IT and the parallel acquisition model", {
  env <- new.env(parent = environment())
  for (name in getNamespaceExports("shiny")) env[[name]] <- getExportedValue("shiny", name)
  sys.source(system.file("shiny_app", "server_instrument.R", package = "aidia", mustWork = TRUE), env)
  shiny::testServer(function(input, output, session) {
    rv <- shiny::reactiveValues(data_loaded = FALSE)
    cycle <- env$server_instrument(input, output, session, rv)
  }, {
    session$setInputs(instrument = "astral_zoom", astral_ms1_resolution = "120000",
      astral_ms2_it = 6, current_window_count = 300, ms1_it_auto = FALSE, ms1_it_custom = 400)
    expect_equal(cycle()$ms1$resolution, 120000)
    expect_equal(cycle()$ms1$injection_time_ms, 400)
    expect_equal(cycle()$ms1$scans_per_cycle, 0)
    expect_equal(cycle()$instrument$cycle_calculation, "parallel")
    session$setInputs(ms1_it_custom = 10)
    expect_equal(cycle()$ms1$injection_time_ms, 10)
  })
})

test_that("native export shares delivered geometry and uses confirmed acquisition settings", {
  f <- .native_fixture()
  withr::defer(unlink(f$method$template_path))
  settings <- list(instrument = "exploris", ms1_resolution = "120000", ms1_agc = 300,
    ms1_it_auto = FALSE, ms1_it_custom = 70, ms2_resolution = "15000",
    ms2_it_auto = TRUE, ms2_agc = 600, ms1_scans_per_cycle = 1L)
  request <- .prepare_native_request(f$result, f$method, settings, fill_void = TRUE, charge_state = 0L)
  expected <- .prepare_thermo_windows(f$result$windows, fill_void = TRUE, acquisition_end_min = 50)
  expect_equal(request$windows$mz, expected$mz_center)
  expect_equal(request$windows$width, expected$window_width)
  expect_equal(request$windows$start, expected$rt_start)
  expect_equal(request$windows$end, expected$rt_end)
  expect_equal(request$windows$charge, rep(0L, 4))
  expect_equal(request$acquisition$ms1$resolution, 120000)
  expect_equal(request$acquisition$ms1$agc_percent, 300)
  expect_equal(request$acquisition$ms2$max_it_mode, "Auto")
  expect_equal(request$template_sha256, f$method$sha256)
  expect_equal(request$loop_count, 0L)
  f$result$windows$rt_end[4] <- 60
  expect_error(.prepare_native_request(f$result, f$method), "template duration")
})

test_that("native export refuses ambiguous staggered loops and mismatched instruments", {
  f <- .native_fixture()
  withr::defer(unlink(f$method$template_path))
  w <- f$result$windows
  f$result$windows <- rbind(transform(w, cycle = 2L), transform(w, cycle = 1L))
  req <- .prepare_native_request(f$result, f$method)
  expect_equal(req$loop_count, 2L)
  expect_equal(req$windows$compound[1:4], c("C1_RT1_W01", "C1_RT1_W02", "C2_RT1_W01", "C2_RT1_W02"))
  f$result$windows <- f$result$windows[-1, ]
  expect_error(.prepare_native_request(f$result, f$method), "same window count")
  f$result$metadata$instrument_preset <- "astral"
  expect_error(.prepare_native_request(f$result, f$method), "instrument")
})

test_that("a longer report explains native duration mismatch without clipping windows", {
  f <- .native_fixture()
  withr::defer(unlink(f$method$template_path))
  f$method$duration_min <- 80
  f$result$windows$rt_end[3:4] <- 132.36
  local_mocked_bindings(.thermo_helper_call = function(...) stop("helper must not be called"))
  expect_error(export_thermo_method(f$result, tempfile(), f$method),
    "132\\.36 min.*template duration.*80\\.00 min.*2 windows")
  expect_error(export_thermo_method(f$result, tempfile(), f$method, fill_void = TRUE, charge_state = 0L),
    "before the last segment end")
  expect_equal(max(.prepare_thermo_windows(f$result$windows)$rt_end), 132.36)
  # A window ending exactly at the template boundary is allowed.
  f$result$windows$rt_end[3:4] <- 80
  expect_equal(max(.prepare_native_request(f$result, f$method)$windows$end), 80)
})

test_that("only validated helper output replaces a destination and the template is protected", {
  f <- .native_fixture()
  withr::defer(unlink(f$method$template_path))
  out <- withr::local_tempfile(fileext = ".meth")
  writeLines("previous output", out)
  local_mocked_bindings(.thermo_helper_call = function(request) stop("validation failed"))
  expect_error(export_thermo_method(f$result, out, f$method), "validation failed")
  expect_equal(readLines(out), "previous output")
  expect_error(export_thermo_method(f$result, f$method$template_path, f$method), "cannot be overwritten")
  local_mocked_bindings(.thermo_helper_call = function(request) {
    writeLines("validated method", request$output)
    list(validated = TRUE, non_ms_streams_preserved = TRUE)
  })
  expect_identical(export_thermo_method(f$result, out, f$method), out)
  expect_equal(readLines(out), "validated method")
})

test_that("optional method upload fills controls and retains confirmed template snapshots", {
  f <- .native_fixture()
  withr::defer(unlink(f$method$template_path))
  env <- new.env(parent = environment())
  for (name in getNamespaceExports("shiny")) env[[name]] <- getExportedValue("shiny", name)
  sys.source(system.file("shiny_app", "server_method.R", package = "aidia", mustWork = TRUE), env)
  updates <- list()
  clear_updates <- function() updates <<- list()
  env$updateNumericInput <- env$updateCheckboxInput <- function(session, inputId, value, ...) updates[[inputId]] <<- value
  env$updateSelectInput <- function(session, inputId, selected, ...) updates[[inputId]] <<- selected
  env$inspect_thermo_method <- function(path) { x <- f$method; x$template_path <- path; x }
  env$showNotification <- env$removeNotification <- function(...) NULL
  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(confirmed_run = NULL)
    env$server_method(input, output, session, rv)
  }
  shiny::testServer(server, {
    session$flushReact()
    expect_null(updates$acquisition_end_min)
    expect_null(updates$fill_void)
    expect_null(updates$export_charge_state)
    session$setInputs(method_file = data.frame(name = "original.meth", size = 12, datapath = f$method$template_path))
    expect_equal(updates$instrument, "exploris")
    expect_equal(updates$ms1_resolution, "60000")
    expect_equal(updates$ms1_it_custom, 60)
    expect_false(updates$ms1_it_auto)
    expect_true(updates$ms2_it_auto)
    expect_equal(updates$ms1_agc, 250)
    expect_equal(updates$ms2_agc, 500)
    expect_null(updates$fill_void)
    expect_null(updates$export_charge_state)
    rv$validated_data <- list(data = data.frame(RT.Apex = c(15.36, 132.36)))
    session$flushReact()
    expect_match(output$method_import_status$html, "132.36 min; this template ends at 50.00 min", fixed = TRUE)
    old <- rv$method_context
    rv$confirmed_run <- list(method = old)
    session$flushReact()
    expect_equal(updates$export_format, "native")
    expect_equal(updates$acquisition_end_min, old$duration_min)
    expect_true(updates$fill_void)
    expect_equal(updates$export_charge_state, 0L)
    # User-selected export options survive reconfirmation of the same template.
    session$setInputs(fill_void = FALSE, acquisition_end_min = 45, export_charge_state = 3)
    clear_updates()
    rv$confirmed_run <- list(method = old, revision = 2L)
    session$flushReact()
    expect_null(updates$acquisition_end_min)
    expect_null(updates$fill_void)
    expect_null(updates$export_charge_state)
    f$method$duration_min <- old$duration_min + 10
    f$method$sha256 <- paste(rep("b", 64), collapse = "")
    env$inspect_thermo_method <- function(path) { x <- f$method; x$template_path <- path; x }
    session$setInputs(method_file = data.frame(name = "new.meth", size = 12, datapath = f$method$template_path))
    expect_false(identical(old$template_path, rv$method_context$template_path))
    expect_identical(rv$confirmed_run$method, old)
    expect_true(file.exists(old$template_path))
    expect_null(updates$acquisition_end_min)
    expect_null(updates$fill_void)
    expect_null(updates$export_charge_state)
    next_method <- rv$method_context
    env$inspect_thermo_method <- function(...) stop("unsupported method")
    session$setInputs(method_file = data.frame(name = "bad.meth", size = 12, datapath = f$method$template_path))
    expect_null(rv$method_context)
    expect_match(rv$method_error, "unsupported")
    expect_identical(rv$confirmed_run$method, old)
    expect_null(updates$export_charge_state)
    rv$confirmed_run <- list(method = next_method)
    session$flushReact()
    expect_equal(updates$acquisition_end_min, next_method$duration_min)
    expect_true(updates$fill_void)
    expect_equal(updates$export_charge_state, 0L)
    rv$confirmed_run <- list(method = NULL)
    session$flushReact()
    expect_true(is.na(updates$acquisition_end_min))
    expect_false(updates$fill_void)
    expect_equal(updates$export_charge_state, 1L)
    expect_equal(updates$export_format, "thermo")
  })
})

test_that("local Thermo integration replaces rows and preserves saved acquisition settings", {
  source <- Sys.getenv("AIDIA_TEST_METHOD")
  skip_if(!nzchar(source), "Set AIDIA_TEST_METHOD to an Exploris 480 method for vendor integration.")
  skip_if(.Platform$OS.type != "windows")
  context <- inspect_thermo_method(source)
  f <- .native_fixture()
  withr::defer(unlink(f$method$template_path))
  output <- withr::local_tempfile(fileext = ".meth")
  settings <- list(instrument = "exploris", ms1_resolution = 120000, ms1_agc = 300,
    ms1_it_auto = FALSE, ms1_it_custom = 70, ms2_resolution = 15000,
    ms2_it_auto = FALSE, ms2_it_custom = 30, ms2_agc = 600, ms1_scans_per_cycle = 1L)
  export_thermo_method(f$result, output, context, settings)
  readback <- inspect_thermo_method(output)
  expect_equal(nrow(readback$rows), 4L)
  expect_equal(readback$rows$width, c(20, 40, 30, 60))
  expect_equal(readback$rows$start, c(5, 5, 15, 15))
  expect_equal(readback$time_mode, "StartEndTime")
  expect_equal(readback$ms1$resolution, 120000)
  expect_equal(readback$ms1$agc_percent, 300)
  expect_equal(readback$ms1$max_it_ms, 70)
  expect_equal(readback$ms2$resolution, 15000)
  expect_equal(readback$ms2$agc_percent, 600)
  expect_equal(readback$ms2$max_it_mode, "Custom")
  expect_equal(readback$ms2$max_it_ms, 30)
  f$result$windows <- rbind(transform(f$result$windows, cycle = 2L),
                            transform(f$result$windows, cycle = 1L))
  export_thermo_method(f$result, output, context, settings)
  staggered <- inspect_thermo_method(output)
  expect_equal(staggered$loop_control, "Count")
  expect_equal(staggered$loop_count, 2)
  expect_equal(nrow(staggered$rows), 8L)
  expect_equal(staggered$rows$compound[1:4], c("C1_RT1_W01", "C1_RT1_W02", "C2_RT1_W01", "C2_RT1_W02"))
  # Exercise four-decimal FZ widths through the actual vendor save/reopen path.
  # The Method Editor table can display 3 while the stored width is 3.0013.
  f$result$windows$mz_start <- rep(c(361.4142, 364.4155, 400.1234, 402.1243), 2)
  f$result$windows$mz_end <- f$result$windows$mz_start + rep(c(3.0013, 3.0014, 2.0009, 5.0023), 2)
  expected <- .prepare_native_request(f$result, context, settings)$windows
  export_thermo_method(f$result, output, context, settings)
  fractional <- inspect_thermo_method(output)
  expect_equal(fractional$rows$width, expected$width, tolerance = 1e-9)
  expect_equal(fractional$rows$mz, expected$mz, tolerance = 1e-9)
  expect_equal(fractional$rows$compound, expected$compound)
  expect_equal(fractional$loop_count, 2)
  # A template-backed Shiny result defaults to unspecified charge and full run.
  # Verify actual vendor validation, serialization, and reopen accept zero.
  export_thermo_method(f$result, output, context, settings, fill_void = TRUE, charge_state = 0L)
  zero_charge <- inspect_thermo_method(output)
  expect_equal(zero_charge$rows$charge, rep(0, 8))
  expect_equal(min(zero_charge$rows$start), 0)
  expect_equal(max(zero_charge$rows$end), context$duration_min)
  expect_equal(zero_charge$duration_min, context$duration_min)
  expect_equal(zero_charge$rows$width, fractional$rows$width, tolerance = 1e-9)
  expect_equal(zero_charge$rows$mz, fractional$rows$mz, tolerance = 1e-9)
  expect_equal(zero_charge$loop_count, 2)
  context$sha256 <- paste(rep("0", 64), collapse = "")
  expect_error(export_thermo_method(f$result, output, context), "template changed")
})

test_that("a different template invalidates a preview even with the same acquisition values", {
  env <- new.env(parent = environment())
  sys.source(system.file("shiny_app", "server_live_preview.R", package = "aidia", mustWork = TRUE), env)
  request <- list(data_version = 1L, settings = list(instrument = "exploris"),
                  cycle = list(cycle_time_sec = 1), method = list(sha256 = "first"))
  changed <- request
  changed$method$sha256 <- "second"
  expect_false(env$.shiny_same_request(request, changed))
  expect_true(env$.shiny_same_request(request, request))
})

test_that("native Shiny download uses the confirmed template and settings, not current controls", {
  f <- .native_fixture()
  withr::defer(unlink(f$method$template_path))
  env <- new.env(parent = environment())
  env$renderUI <- function(expr) NULL
  env$downloadHandler <- function(filename, content) list(filename = filename, content = content)
  env$req <- shiny::req
  env$showNotification <- function(...) NULL
  received <- NULL
  env$export_thermo_method <- function(...) { received <<- list(...); invisible(NULL) }
  sys.source(system.file("shiny_app", "server_downloads.R", package = "aidia", mustWork = TRUE), env)
  input <- list2env(list(export_format = "native", instrument = "astral", ms1_agc = 900,
                sample_name = "", condition = "", fill_void = TRUE,
                acquisition_end_min = 50, export_charge_state = 0L))
  rv <- list(optimized_windows = f$result, method_context = list(filename = "new.meth"),
    confirmed_run = list(method = f$method, settings = list(instrument = "exploris", ms1_agc = 250)))
  output <- new.env()
  env$server_downloads(input, output, NULL, rv)
  expect_match(output$download_method$filename(), "\\.meth$")
  output$download_method$content(tempfile())
  expect_identical(received$method, f$method)
  expect_equal(received$settings$ms1_agc, 250)
  expect_equal(received$settings$instrument, "exploris")
  expect_true(received$fill_void)
  expect_equal(received$acquisition_end_min, 50)
  expect_equal(received$charge_state, 0L)
  input$export_charge_state <- 3L
  output$download_method$content(tempfile())
  expect_equal(received$charge_state, 3L)
})

test_that("configured Zoom RT settings and reference bytes survive window export", {
  paths <- Sys.getenv(c("AIDIA_TEST_ADAPTIVE_TEMPLATE", "AIDIA_TEST_RT_CAPTURE_TEMPLATE"))
  skip_if(any(!nzchar(paths)), "Set configured Zoom Adaptive RT and reference-capture template fixtures.")
  f <- .astral_native_fixture()
  withr::defer(unlink(f$method$template_path))
  for (path in paths) {
    method <- inspect_thermo_method(path)
    expect_true(method$adaptive_rt$mode %in% c("adaptive", "acquire_reference"))
    output <- withr::local_tempfile(fileext = ".meth")
    export_thermo_method(f$result, output, method)
    actual <- inspect_thermo_method(output)
    expect_equal(actual$adaptive_rt, method$adaptive_rt)
    expected <- .prepare_native_request(f$result, method)$windows
    expect_equal(actual$rows$mz, expected$mz)
    expect_equal(actual$rows$width, expected$width)
    expect_equal(actual$rows$start, expected$start)
    expect_equal(actual$rows$end, expected$end)
    expect_equal(inspect_thermo_method(path)$sha256, method$sha256)
    # Old mutation requests must not silently report success while preserving settings.
    request <- .prepare_native_request(f$result, method)
    request$adaptive_rt <- list(mode = "off")
    request$output <- withr::local_tempfile(fileext = ".meth")
    expect_error(.thermo_helper_call(request), "Configure Adaptive RT in the instrument Method Editor")
    expect_false(file.exists(request$output))
  }
})

test_that("the optional RT guide follows the confirmed Zoom template", {
  f <- .astral_native_fixture()
  withr::defer(unlink(f$method$template_path))
  env <- new.env(parent = environment())
  for (name in getNamespaceExports("shiny")) env[[name]] <- getExportedValue("shiny", name)
  sys.source(system.file("shiny_app", "server_method.R", package = "aidia", mustWork = TRUE), env)
  shiny::testServer(function(input, output, session) {
    rv <- shiny::reactiveValues(confirmed_run = NULL)
    env$server_method(input, output, session, rv)
  }, {
    expect_equal(output$adaptive_rt_available, "false")
    rv$confirmed_run <- list(method = f$method)
    session$flushReact()
    expect_equal(output$adaptive_rt_available, "true")
    draft <- f$method
    draft$instrument <- "exploris"
    rv$method_context <- draft
    session$flushReact()
    expect_equal(output$adaptive_rt_available, "true")
    rv$confirmed_run <- list(method = draft)
    session$flushReact()
    expect_equal(output$adaptive_rt_available, "false")
    rv$confirmed_run <- list(method = NULL)
    session$flushReact()
    expect_equal(output$adaptive_rt_available, "false")
  })
})
