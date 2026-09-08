.delivery_fixture <- function() {
  windows <- data.frame(
    rt_segment_id = rep(1:2, each = 2), rt_start = rep(c(10, 20), each = 2),
    rt_end = rep(c(18, 30), each = 2), mz_start = rep(c(400, 450), 2),
    mz_end = rep(c(450, 500), 2), mz_center = rep(c(425, 475), 2), window_width = 50
  )
  list(
    ow = structure(list(windows = windows,
      parameters = list(mz_strategy = "quantile", window_mode = "density",
                        rt_binning_mode = "adaptive", rt_bin_width_min = 4),
      metadata = list(instrument_preset = "exploris")), class = "OptimizedWindows"),
    vd = structure(list(data = data.frame(RT.Apex = c(15, 25),
                                          Precursor.Mz = c(450, 500))), class = "ValidatedData")
  )
}

.delivery_quiet <- function(expr) {
  invisible(capture.output(value <- expr))
  value
}

test_that("directory, ZIP and individual delivery write identical formats and RT options", {
  f <- .delivery_fixture()
  root <- withr::local_tempdir()
  cwd <- getwd()
  directory <- .delivery_quiet(export_method_bundle(
    f$ow, file.path(root, "directory"), f$vd,
    fill_void = TRUE, acquisition_start_min = 2, acquisition_end_min = 40
  ))
  archive <- file.path(root, "methods.zip")
  .delivery_quiet(export_method_bundle(f$ow, archive, f$vd, delivery = "zip",
    fill_void = TRUE, acquisition_start_min = 2, acquisition_end_min = 40))
  expect_identical(getwd(), cwd)
  expect_setequal(utils::unzip(archive, list = TRUE)$Name,
                  c("thermo.csv", "center_mass.csv", "mz_range.csv"))
  utils::unzip(archive, exdir = file.path(root, "unzipped"))
  for (format in names(directory)) {
    single <- file.path(root, paste0(format, "-single.csv"))
    .delivery_quiet(export_method_formats(f$ow, setNames(single, format), f$vd,
      fill_void = TRUE, acquisition_start_min = 2, acquisition_end_min = 40))
    expect_identical(readLines(single), readLines(directory[[format]]))
    expect_identical(readLines(file.path(root, "unzipped", paste0(format, ".csv"))),
                     readLines(directory[[format]]))
  }
  thermo <- read.csv(directory[["thermo"]], check.names = FALSE)
  expect_equal(thermo[["t start (min)"]], c(2, 2, 19, 19))
  expect_equal(thermo[["t stop (min)"]], c(19, 19, 40, 40))
  # Reusing a destination replaces the archive instead of retaining old formats.
  .delivery_quiet(export_method_bundle(f$ow, archive, delivery = "zip",
                                       formats = "center_mass"))
  expect_equal(utils::unzip(archive, list = TRUE)$Name, "center_mass.csv")
})

test_that("delivery validates formats before writing and restores cwd on ZIP failure", {
  f <- .delivery_fixture()
  root <- withr::local_tempdir()
  output <- file.path(root, "bad")
  expect_error(export_method_bundle(f$ow, output, f$vd, formats = c("thermo", "bad")),
               "unique names")
  expect_false(dir.exists(output))
  cwd <- getwd()
  archive <- file.path(root, "existing.zip")
  writeLines("existing archive", archive)
  local_mocked_bindings(zip = function(...) 1L, .package = "utils")
  expect_error(.delivery_quiet(export_method_bundle(f$ow, archive, f$vd, delivery = "zip")),
               "ZIP creation failed")
  expect_identical(getwd(), cwd)
  expect_equal(readLines(archive), "existing archive")
})

test_that("Shiny downloads use completed naming and the same live export choices", {
  f <- .delivery_fixture()
  env <- new.env(parent = environment())
  env$renderUI <- function(expr) NULL
  env$downloadHandler <- function(filename, content) list(filename = filename, content = content)
  env$req <- shiny::req
  env$showNotification <- env$removeNotification <- function(...) NULL
  sys.source(test_path("..", "..", "inst", "shiny_app", "server_downloads.R"), env)
  input <- list2env(list(instrument = "astral", mz_strategy = "greedy",
    window_mode = "fixed", rt_binning_mode = "fixed", sample_name = "sample",
    export_format = "thermo", fill_void = TRUE, acquisition_end_min = 40))
  output <- new.env()
  rv <- list(optimized_windows = f$ow, validated_data = f$vd,
             optimization_plan = structure(list(), class = "OptimizationPlan"))
  env$server_downloads(input, output, NULL, rv)
  expect_equal(output$download_method$filename(),
               format_result_filename(f$ow, prefix = "sample"))
  input$mz_strategy <- "kde"
  input$instrument <- "fusion_lumos"
  expect_equal(output$download_pdf$filename(),
               format_result_filename(f$ow, type = "report", ext = "pdf", prefix = "sample"))
  root <- withr::local_tempdir()
  single <- file.path(root, "single.csv")
  archive <- file.path(root, "bundle.zip")
  .delivery_quiet(output$download_method$content(single))
  .delivery_quiet(output$download_batch_zip$content(archive))
  utils::unzip(archive, exdir = file.path(root, "unzipped"))
  expect_identical(readLines(single), readLines(file.path(root, "unzipped", "thermo.csv")))
  expect_equal(max(read.csv(single, check.names = FALSE)[["t stop (min)"]]), 40)
})
