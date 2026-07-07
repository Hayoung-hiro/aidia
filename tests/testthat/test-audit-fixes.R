# test-audit-fixes.R
#
# Regression tests for codebase-audit fixes. Each test documents the failing
# input that the fix addresses.

# ---------------------------------------------------------------------------
# H2: estimate_cycle_time() crashed on "unknown" gradient (as.numeric -> NA ->
# `if (NA <= 30)` error). The default run_complete_pipeline() path reaches this
# via extract_gradient_name() on filenames without a "<n>min" token.
# ---------------------------------------------------------------------------

test_that("estimate_cycle_time handles unknown gradient without crashing", {
  expect_no_error(ct <- estimate_cycle_time("unknown"))
  expect_equal(ct, 2.0)                 # conservative long-gradient default
})

test_that("estimate_cycle_time still buckets known gradients", {
  expect_equal(estimate_cycle_time("30min"), 1.2)
  expect_equal(estimate_cycle_time("60min"), 1.6)
  expect_equal(estimate_cycle_time("120min"), 2.0)
})

# ---------------------------------------------------------------------------
# H3: outlier strategy returned Inf/-Inf for a single-precursor bin because
# sd() = NA propagated through the inlier mask. Should return the raw value.
# ---------------------------------------------------------------------------

test_that("outlier strategy handles single-precursor bin (no Inf/-Inf)", {
  bounds <- compute_mz_range_for_bin(outlier_config(), data.frame(Precursor.Mz = 550.0))
  expect_true(is.finite(bounds$mz_min))
  expect_true(is.finite(bounds$mz_max))
  expect_equal(bounds$mz_min, 550.0)
  expect_equal(bounds$mz_max, 550.0)
})

test_that("outlier strategy handles all-identical m/z bin", {
  bounds <- compute_mz_range_for_bin(outlier_config(), data.frame(Precursor.Mz = rep(600.0, 5)))
  expect_true(is.finite(bounds$mz_min) && is.finite(bounds$mz_max))
  expect_equal(bounds$mz_min, 600.0)
  expect_equal(bounds$mz_max, 600.0)
})

# ---------------------------------------------------------------------------
# M1: print_*() used rep(" ", indent) (a length-`indent` vector), so sprintf
# recycled the message `indent` times (default 2 -> printed twice) and
# indent = 0 dropped the line entirely. strrep() produces a single string.
# ---------------------------------------------------------------------------

test_that("print helpers emit exactly one line at default indent", {
  expect_equal(length(capture.output(print_success("done"))), 1)
  expect_equal(length(capture.output(print_warning("careful"))), 1)
  expect_equal(length(capture.output(print_info("note"))), 1)
})

test_that("print helpers emit one line (not zero) at indent = 0", {
  expect_equal(length(capture.output(print_info("note", indent = 0))), 1)
  expect_match(capture.output(print_info("note", indent = 0)), "note")
})
