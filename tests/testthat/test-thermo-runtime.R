.runtime_test_compiler <- function() {
  skip_if(.Platform$OS.type != "windows")
  compiler <- file.path(Sys.getenv("WINDIR"), "Microsoft.NET", "Framework64", "v4.0.30319", "csc.exe")
  skip_if_not(file.exists(compiler), "Runtime fixtures require the .NET Framework compiler.")
  compiler
}

.compile_runtime_probe <- function(directory) {
  executable <- file.path(directory, "probe.exe")
  build <- system2(.runtime_test_compiler(), shQuote(c("/nologo", "/target:exe", "/platform:x64",
    "/r:System.Web.Extensions.dll",
    paste0("/out:", executable), normalizePath(test_path("fixtures", "ThermoRuntimeProbe.cs"), winslash = "\\"))),
    stdout = TRUE, stderr = TRUE)
  expect_null(attr(build, "status"), info = paste(build, collapse = "\n"))
  executable
}

.call_runtime_probe <- function(executable, defaults, request, profiles = NULL) {
  input <- withr::local_tempfile(fileext = ".json")
  output <- withr::local_tempfile(fileext = ".json")
  request$runtime_config_path <- file.path(dirname(executable), "instruments.json")
  jsonlite::write_json(request, input, auto_unbox = TRUE, dataframe = "rows", null = "null", digits = NA)
  log <- system2(executable, shQuote(c(system.file("thermo", "aidia-thermo-method.exe", package = "aidia"),
    defaults, input, output, profiles)), stdout = TRUE, stderr = TRUE)
  expect_null(attr(log, "status"), info = paste(log, collapse = "\n"))
  response <- jsonlite::read_json(output, simplifyVector = TRUE)
  expect_true(response$ok, info = response$error)
  response$result
}

.make_runtime_assembly <- function(path, version, compiler) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  source <- withr::local_tempfile(fileext = ".cs")
  writeLines(sprintf('using System.Reflection; [assembly: AssemblyFileVersion("%s")] public class Fixture {}', version), source)
  build <- system2(compiler, shQuote(c("/nologo", "/target:library", paste0("/out:", chartr("/", "\\", path)),
    normalizePath(source, winslash = "\\", mustWork = TRUE))), stdout = TRUE, stderr = TRUE)
  expect_null(attr(build, "status"), info = paste(build, collapse = "\n"))
}

test_that("every Thermo preset has the shared runtime path setting", {
  configs <- load_instruments_config()
  thermo <- Filter(function(config) startsWith(config$name, "Thermo "), configs)
  expect_true(all(c("eclipse", "fusion_lumos") %in% names(thermo)))
  for (config in thermo) {
    expect_type(config$thermo_runtime_path, "character")
    expect_length(config$thermo_runtime_path, 1)
    expect_false(is.na(config$thermo_runtime_path))
  }
})

test_that("R runtime discovery uses the existing instrument configuration file", {
  skip_if(.Platform$OS.type != "windows")
  withr::local_options(aidia.thermo.runtime = NULL)
  status <- thermo_method_status()
  path <- system.file("config", "instruments.json", package = "aidia", mustWork = TRUE)
  expect_equal(normalizePath(status$config_path, winslash = "/"), normalizePath(path, winslash = "/"))
  expect_setequal(status$runtimes$instrument, c("exploris", "astral_zoom"))
  expect_type(get_instrument_config("exploris")$thermo_runtime_path, "character")
  expect_type(get_instrument_config("astral_zoom")$thermo_runtime_path, "character")
})

test_that("runtime discovery prefers valid defaults and validates per-instrument configuration", {
  compiler <- .runtime_test_compiler()
  directory <- withr::local_tempdir()
  executable <- .compile_runtime_probe(directory)
  defaults <- file.path(directory, "default installations")
  config <- file.path(directory, "instruments.json")
  paths <- list(exploris = file.path(directory, "custom installations", "Exploris", "5.1"),
    astral_zoom = file.path(directory, "custom installations", "Astral", "2.2"))
  dll <- file.path("System", "Programs", "dependencies", "tng", "Thermo.TNG.Merkur.MethodXML.dll")
  launcher <- file.path("System", "Programs", "Thermo.Exploris.Method.EditorLauncher.exe")
  make_assembly <- function(path, version) .make_runtime_assembly(path, version, compiler)
  make_assembly(file.path(paths$exploris, dll), "5.0.4564.7")
  make_assembly(file.path(paths$exploris, launcher), "5.1.761.17")
  make_assembly(file.path(paths$astral_zoom, dll), "5.0.4647.12")
  make_assembly(file.path(paths$astral_zoom, launcher), "2.2.821.21")
  probe <- function(...) .call_runtime_probe(executable, defaults, list(action = "probe", ...))
  write_config <- function(value) jsonlite::write_json(lapply(value, function(path) list(name = "Fixture instrument",
    ms1_time = 5, thermo_runtime_path = path)),
    config, auto_unbox = TRUE, null = "null")
  same_path <- function(actual, expected) expect_equal(
    unname(normalizePath(actual, winslash = "/", mustWork = FALSE)), unname(normalizePath(expected, winslash = "/", mustWork = FALSE)))

  missing <- probe()
  expect_false(missing$available)
  same_path(missing$config_path, config)
  expect_true(all(grepl(basename(config), missing$runtimes$reason, fixed = TRUE)))
  expect_match(missing$runtimes$reason[1], "exploris.*installation root folder")
  expect_false(file.exists(config))

  write_config(paths[c("astral_zoom", "exploris")])
  configured <- probe()
  expect_true(all(configured$runtimes$available))
  same_path(configured$runtimes$path, file.path(unlist(paths), "System", "Programs", "dependencies", "tng"))

  default_exploris <- file.path(defaults, "Thermo Scientific", "Instruments", "Exploris", "5.1")
  for (file in c(dll, launcher)) {
    destination <- file.path(default_exploris, file)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(file.path(paths$exploris, file), destination))
  }
  preferred <- probe()
  same_path(preferred$runtimes$path[1], file.path(default_exploris, "System", "Programs", "dependencies", "tng"))
  same_path(preferred$runtimes$path[2], configured$runtimes$path[2])

  writeLines("{invalid json", config)
  malformed <- probe()
  expect_true(malformed$runtimes$available[1]) # A valid default does not consult the config.
  expect_false(malformed$runtimes$available[2])
  expect_match(malformed$runtimes$reason[2], "Cannot read Thermo configuration")

  # A different build at the default location may use a verified custom install.
  stopifnot(file.copy(file.path(paths$astral_zoom, dll), file.path(default_exploris, dll), overwrite = TRUE))
  write_config(paths)
  fallback <- probe()
  same_path(fallback$runtimes$path, configured$runtimes$path)
  stopifnot(file.copy(file.path(paths$astral_zoom, dll), file.path(paths$exploris, dll), overwrite = TRUE))
  incompatible <- probe()
  expect_false(incompatible$runtimes$available[1])
  expect_match(incompatible$runtimes$reason[1], "not been validated")
  expect_true(incompatible$runtimes$available[2])

  for (case in list(list(value = list(astral_zoom = 42), error = "path string"),
      list(value = list(astral_zoom = "relative/path"), error = "absolute installation path"),
      list(value = list(astral_zoom = "C:relative"), error = "absolute installation path"),
      list(value = list(astral_zoom = "\\relative"), error = "absolute installation path"))) {
    write_config(case$value)
    expect_match(probe()$runtimes$reason[2], case$error)
  }
  writeLines("[]", config)
  expect_match(probe()$runtimes$reason[2], "Expected the instruments.json configuration object", fixed = TRUE)
  writeLines('{"astral_zoom": "not an object"}', config)
  expect_match(probe()$runtimes$reason[2], "instrument configuration object")
  write_config(list(astral_zoom = ""))
  expect_false(probe()$available)
  withr::local_envvar(AIDIA_TEST_THERMO_ROOT = paths$astral_zoom)
  write_config(list(astral_zoom = "%AIDIA_TEST_THERMO_ROOT%"))
  expect_identical(probe()$runtimes$available, c(FALSE, TRUE))

  # An explicit legacy override remains authoritative and is still version gated.
  writeLines("{invalid json", config)
  overridden <- probe(runtime_path = paths$astral_zoom)
  expect_identical(overridden$runtimes$available, c(FALSE, TRUE))
  expect_false(grepl("Cannot read Thermo configuration", overridden$runtimes$reason[1], fixed = TRUE))
})

test_that("future model profiles share discovery across different DLL and launcher layouts", {
  compiler <- .runtime_test_compiler()
  directory <- withr::local_tempdir()
  executable <- .compile_runtime_probe(directory)
  defaults <- file.path(directory, "default installations")
  profile_file <- file.path(directory, "fixture-profiles.json")
  profiles <- list(
    list(Instrument = "eclipse", Model = "Fixture Eclipse", RuntimeName = "Fixture Tribrid Eclipse",
      Build = "1.2.3.4", DllVersion = "2.3.4.5", InstallDirectory = "FixtureVendor/Eclipse/1",
      ImplementationFile = "Runtime/Fixture.Calcium.dll", LauncherFile = "Editor/Eclipse.Editor.exe"),
    list(Instrument = "fusion_lumos", Model = "Fixture Lumos", RuntimeName = "Fixture Tribrid Lumos",
      Build = "3.4.5.6", DllVersion = "4.5.6.7", InstallDirectory = "FixtureVendor/Lumos/2",
      ImplementationFile = "bin/Fixture.Lumos.dll", LauncherFile = "Launch/Lumos.exe"))
  jsonlite::write_json(profiles, profile_file, auto_unbox = TRUE)
  config <- file.path(directory, "instruments.json")
  paths <- list(eclipse = file.path(directory, "custom Eclipse"), fusion_lumos = file.path(directory, "custom Lumos"))
  for (profile in profiles) {
    root <- paths[[profile$Instrument]]
    .make_runtime_assembly(file.path(root, profile$ImplementationFile), profile$DllVersion, compiler)
    .make_runtime_assembly(file.path(root, profile$LauncherFile), profile$Build, compiler)
  }
  settings <- lapply(paths, function(path) list(thermo_runtime_path = path))
  write_config <- function() jsonlite::write_json(settings, config, auto_unbox = TRUE)
  write_config()
  probe <- function() .call_runtime_probe(executable, defaults, list(action = "probe"), profile_file)
  configured <- probe()
  expect_setequal(configured$runtimes$instrument, names(paths))
  expect_true(all(configured$runtimes$available))
  expect_equal(normalizePath(configured$runtimes$path, winslash = "/"),
    normalizePath(c(file.path(paths$eclipse, "Runtime"), file.path(paths$fusion_lumos, "bin")), winslash = "/"))

  default_eclipse <- file.path(defaults, profiles[[1]]$InstallDirectory)
  for (file in unlist(profiles[[1]][c("ImplementationFile", "LauncherFile")])) {
    destination <- file.path(default_eclipse, file)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(file.path(paths$eclipse, file), destination))
  }
  settings$eclipse$thermo_runtime_path <- file.path(directory, "missing custom installation")
  write_config()
  preferred <- probe()
  expect_true(all(preferred$runtimes$available))
  expect_equal(normalizePath(preferred$runtimes$path[1], winslash = "/"),
    normalizePath(file.path(default_eclipse, "Runtime"), winslash = "/"))

  settings$fusion_lumos$thermo_runtime_path <- file.path(directory, "missing Lumos")
  write_config()
  missing <- probe()
  expect_true(missing$runtimes$available[1])
  expect_false(missing$runtimes$available[2])
  expect_match(missing$runtimes$reason[2], "fusion_lumos.thermo_runtime_path", fixed = TRUE)
  expect_match(missing$runtimes$reason[2], "Fixture.Lumos.dll", fixed = TRUE)

  settings$fusion_lumos$thermo_runtime_path <- paths$fusion_lumos
  write_config()
  stopifnot(file.copy(file.path(paths$eclipse, profiles[[1]]$LauncherFile),
    file.path(paths$fusion_lumos, profiles[[2]]$LauncherFile), overwrite = TRUE))
  wrong_launcher <- probe()
  expect_true(wrong_launcher$runtimes$available[1])
  expect_false(wrong_launcher$runtimes$available[2])
  expect_match(wrong_launcher$runtimes$reason[2], "Check the launcher")

  # The real helper does not advertise a new native adapter just because the
  # settings file contains paths for that instrument.
  original <- .call_runtime_probe(executable, defaults, list(action = "probe"))
  expect_setequal(original$runtimes$instrument, c("exploris", "astral_zoom"))
  expect_false(original$available)
})

test_that("configured installed runtimes inspect and write native methods without default locations", {
  .runtime_test_compiler()
  fixtures <- c(exploris = Sys.getenv("AIDIA_TEST_METHOD"), astral_zoom = Sys.getenv("AIDIA_TEST_ASTRAL_METHOD"))
  skip_if(any(!nzchar(fixtures)), "Set both native method fixtures for configured-path integration.")
  directory <- withr::local_tempdir()
  executable <- .compile_runtime_probe(directory)
  config <- file.path(directory, "instruments.json")
  root <- file.path(Sys.getenv("ProgramFiles"), "Thermo Scientific", "Instruments")
  jsonlite::write_json(list(exploris = list(thermo_runtime_path = file.path(root, "Exploris", "5.1")),
    astral_zoom = list(thermo_runtime_path = file.path(root, "Astral", "2.2"))), config, auto_unbox = TRUE)
  call <- function(request) .call_runtime_probe(executable, file.path(directory, "absent defaults"), request)
  for (instrument in names(fixtures)) {
    source <- file.path(directory, paste0(instrument, ".meth"))
    stopifnot(file.copy(fixtures[[instrument]], source))
    context <- call(list(action = "inspect", template = source))
    expect_identical(context$instrument, instrument)
    output <- file.path(directory, paste0(instrument, "-output.meth"))
    result <- call(list(action = "write", template = source, template_sha256 = context$sha256,
      acquisition = context[c("ms1", "ms2", "ms1_scans_per_cycle")], loop_count = 0L,
      windows = head(context$rows, 2), output = output))
    expect_true(result$validated)
    expect_true(result$non_ms_streams_preserved)
    expect_equal(nrow(call(list(action = "inspect", template = output))$rows), 2)
  }
})
