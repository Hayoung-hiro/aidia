distribution_file <- function(...) test_path("..", "..", "tools", "distribution", ...)

test_that("bundle dependencies follow DESCRIPTION and enforce versions", {
  path <- distribution_file("bundle", "scripts", "common.R")
  skip_if_not(file.exists(path), "Distribution tooling is tested from the source checkout.")
  env <- new.env(parent = baseenv())
  sys.source(path, env)
  description <- read.dcf(textConnection(paste(
    "Package: fixture", "Depends: R (>= 4.5.0)", "Imports: shiny (>= 1.8.1), jsonlite",
    "Suggests: patchwork (>= 1.2.0)", sep = "\n")))
  requirements <- env$bundle_requirements(description)
  installed <- rbind(c(Package = "shiny", Version = "1.7.0"),
                     c(Package = "jsonlite", Version = "1.8.0"),
                     c(Package = "jsonlite", Version = "0.1.0"))
  expect_setequal(env$bundle_missing(requirements, installed), c("shiny", "patchwork"))
  installed[1, "Version"] <- "1.8.1"
  expect_identical(env$bundle_missing(requirements, installed), "patchwork")
  actual <- env$bundle_requirements(read.dcf(test_path("..", "..", "DESCRIPTION")))
  expect_true(all(c("future", "promises", "shiny", "arrow", "patchwork") %in% actual$package))
})

test_that("bundle upgrades preserve only supported runtime path fields", {
  path <- distribution_file("bundle", "scripts", "common.R")
  skip_if_not(file.exists(path), "Distribution tooling is tested from the source checkout.")
  env <- new.env(parent = baseenv())
  sys.source(path, env)
  previous <- list(exploris = list(thermo_runtime_path = "D:/Custom/Exploris/5.1", ms2_time = 999),
                   eclipse = list(thermo_runtime_path = "E:/Tribrid"),
                   removed = list(thermo_runtime_path = "X:/old"))
  current <- list(exploris = list(thermo_runtime_path = "", ms2_time = 32),
                  eclipse = list(thermo_runtime_path = ""),
                  astral_zoom = list(thermo_runtime_path = ""))
  updated <- env$bundle_restore_paths(previous, current)
  expect_equal(updated$exploris$thermo_runtime_path, "D:/Custom/Exploris/5.1")
  expect_equal(updated$eclipse$thermo_runtime_path, "E:/Tribrid")
  expect_equal(updated$exploris$ms2_time, 32)
  expect_identical(names(updated), names(current))
  expect_equal(updated$astral_zoom$thermo_runtime_path, "")
})

test_that("bundle chooses a binary only for its matching R minor release", {
  path <- distribution_file("bundle", "scripts", "common.R")
  skip_if_not(file.exists(path), "Distribution tooling is tested from the source checkout.")
  env <- new.env(parent = baseenv())
  sys.source(path, env)
  directory <- withr::local_tempdir()
  writeLines(c("R-Minor: 4.5", "Binary: aidia_0.5.2.zip", "Source: aidia_0.5.2.tar.gz"),
             file.path(directory, "BUNDLE.dcf"))
  expect_equal(env$bundle_package(directory, "4.5")$type, "win.binary")
  expect_equal(env$bundle_package(directory, "4.6")$type, "source")
  expect_match(env$bundle_package(directory, "4.6")$path, "tar.gz$", fixed = FALSE)
})
