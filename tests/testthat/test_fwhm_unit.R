# test_fwhm_unit.R - Explicit FWHM unit conversion (issue #8)
#
# Verifies ensure_fwhm_seconds() converts by explicit source unit instead of
# guessing, that the legacy median<1 heuristic remains a (silent) backward-
# compatible fallback, and that a single run-global unit prevents per-subset
# unit flips.

# -----------------------------------------------------------------------------
# Explicit unit = "minutes"  (DIA-NN source-fixed unit)
# -----------------------------------------------------------------------------

test_that("unit='minutes' multiplies by 60 (narrow peaks, median < 1)", {
  fwhm_min <- c(0.2, 0.3, 0.4)             # median 0.3 min
  result <- ensure_fwhm_seconds(fwhm_min, unit = "minutes")
  expect_equal(result, c(12, 18, 24))       # exact seconds
})

test_that("unit='minutes' converts broad peaks the heuristic would miss", {
  # Broad peaks: median 1.2 min (>= 1). Explicit unit -> correct 72 s.
  fwhm_broad <- c(1.0, 1.2, 1.4)
  expect_equal(
    ensure_fwhm_seconds(fwhm_broad, unit = "minutes"),
    c(60, 72, 84)
  )
  # Regression witness: the legacy heuristic (no unit, median 1.2 >= 1) leaves
  # these as-is -- 1.2 s, the 60x under-conversion bug the explicit unit avoids.
  expect_equal(ensure_fwhm_seconds(fwhm_broad), c(1.0, 1.2, 1.4))
})

# -----------------------------------------------------------------------------
# Explicit unit = "seconds"  (already in seconds; leave untouched)
# -----------------------------------------------------------------------------

test_that("unit='seconds' leaves sub-second peaks unchanged", {
  fwhm_sub <- c(0.4, 0.5, 0.6)             # median 0.5 s
  expect_equal(ensure_fwhm_seconds(fwhm_sub, unit = "seconds"), fwhm_sub)
  # Regression witness: the legacy heuristic (no unit, median 0.5 < 1) would
  # 60x these to 30 s -- avoided by the explicit unit.
  expect_equal(ensure_fwhm_seconds(fwhm_sub), c(24, 30, 36))
})

# -----------------------------------------------------------------------------
# unit = NULL  -> silent backward-compatible heuristic
# -----------------------------------------------------------------------------

test_that("unit=NULL applies the legacy median heuristic silently", {
  fwhm_min <- c(0.2, 0.3, 0.4)
  expect_warning(result <- ensure_fwhm_seconds(fwhm_min), regexp = NA)
  expect_equal(result, c(12, 18, 24))       # heuristic still multiplies by 60
})

test_that("no code path warns (explicit or fallback)", {
  expect_warning(ensure_fwhm_seconds(c(0.2, 0.3), unit = "minutes"), regexp = NA)
  expect_warning(ensure_fwhm_seconds(c(12, 18),  unit = "seconds"), regexp = NA)
  expect_warning(ensure_fwhm_seconds(c(0.2, 0.3)), regexp = NA)
})

test_that("invalid unit is rejected", {
  expect_error(ensure_fwhm_seconds(c(0.2, 0.3), unit = "hours"))
})

# -----------------------------------------------------------------------------
# Run-global unit prevents per-subset flips (the core #8 bug)
# -----------------------------------------------------------------------------

test_that("one run-global unit keeps subsets consistent", {
  # Same run, minutes. One subset's median >= 1, another's < 1. The legacy
  # per-subset heuristic would convert them inconsistently; a single explicit
  # unit converts every subset identically (x60).
  narrow <- c(0.2, 0.3, 0.4)               # median 0.3 (< 1)
  broad  <- c(1.1, 1.3, 1.5)               # median 1.3 (>= 1)
  unit <- "minutes"                         # resolved once, upstream
  expect_equal(ensure_fwhm_seconds(narrow, unit = unit), c(12, 18, 24))
  expect_equal(ensure_fwhm_seconds(broad,  unit = unit), c(66, 78, 90))
})

# -----------------------------------------------------------------------------
# NA / empty handling under explicit unit
# -----------------------------------------------------------------------------

test_that("explicit unit preserves NA and empty input", {
  expect_equal(
    ensure_fwhm_seconds(c(0.2, NA, 0.4), unit = "minutes"),
    c(12, NA, 24)
  )
  expect_equal(
    ensure_fwhm_seconds(numeric(0), unit = "minutes"),
    numeric(0)
  )
})
