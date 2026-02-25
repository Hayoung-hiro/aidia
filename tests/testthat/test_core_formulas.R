# test_core_formulas.R - Characterization Tests for Core Mathematical Functions
# AIDIA v0.1.0 - Safety net for refactoring (P0.1)
#
# Tests: calculate_dppp(), ensure_fwhm_seconds(), estimate_window_count_preview(),
#        calculate_satisfaction_ratio(), PEAK_WIDTH_FACTOR constant

# =============================================================================
# calculate_dppp() - DPPP = 1.7 * FWHM_sec / cycle_time_sec
# =============================================================================

test_that("calculate_dppp returns correct value for known inputs", {
  # DPPP = 1.7 * FWHM / cycle_time
  expect_equal(calculate_dppp(12, 2), 10.2)
  expect_equal(calculate_dppp(20, 2), 17.0)
  expect_equal(calculate_dppp(10, 5), 3.4)
})

test_that("calculate_dppp handles vector input for fwhm", {
  result <- calculate_dppp(c(10, 20), 2)
  expect_equal(result, c(8.5, 17.0))
  expect_length(result, 2)
})

test_that("calculate_dppp errors on zero cycle time", {
  expect_error(calculate_dppp(12, 0), "cannot be zero")
})

test_that("calculate_dppp errors on negative cycle time", {
  expect_error(calculate_dppp(12, -1))
})

test_that("calculate_dppp uses PEAK_WIDTH_FACTOR constant (1.7)", {
  expect_equal(PEAK_WIDTH_FACTOR, 1.7)
  # Verify the formula: PEAK_WIDTH_FACTOR * fwhm / cycle_time
  expect_equal(calculate_dppp(10, 1), PEAK_WIDTH_FACTOR * 10)
})

# =============================================================================
# ensure_fwhm_seconds() - Auto-detect minutes vs seconds, convert
# =============================================================================

test_that("ensure_fwhm_seconds converts minutes to seconds when median < 1", {
  # Typical DIA-NN output in minutes (e.g., 0.2 min = 12 sec)
  fwhm_min <- c(0.2, 0.3, 0.25)
  result <- ensure_fwhm_seconds(fwhm_min)
  expect_equal(result, c(12, 18, 15))
})

test_that("ensure_fwhm_seconds keeps seconds unchanged when median >= 1", {
  fwhm_sec <- c(12, 18, 15)
  result <- ensure_fwhm_seconds(fwhm_sec)
  expect_equal(result, c(12, 18, 15))
})

test_that("ensure_fwhm_seconds handles NA values without error", {
  fwhm_with_na <- c(0.2, NA, 0.3, NA, 0.25)
  result <- ensure_fwhm_seconds(fwhm_with_na)
  # Non-NA values converted, NAs preserved
  expect_equal(result[1], 12)
  expect_equal(result[3], 18)
  expect_true(is.na(result[2]))
  expect_true(is.na(result[4]))
})

test_that("ensure_fwhm_seconds handles all-NA input", {
  result <- ensure_fwhm_seconds(c(NA, NA, NA))
  expect_true(all(is.na(result)))
})

test_that("ensure_fwhm_seconds handles single value", {
  expect_equal(ensure_fwhm_seconds(0.5), 30)  # minutes -> seconds
  expect_equal(ensure_fwhm_seconds(15), 15)    # already seconds
})

test_that("ensure_fwhm_seconds boundary: median exactly 1 stays as-is", {
  # median = 1.0 -> treated as seconds (not converted)
  fwhm <- c(0.5, 1.0, 1.5)  # median = 1.0
  result <- ensure_fwhm_seconds(fwhm)
  expect_equal(result, c(0.5, 1.0, 1.5))
})

# =============================================================================
# estimate_window_count_preview() - Quick window count from FWHM/DPPP/MS2
# =============================================================================

test_that("estimate_window_count_preview computes correctly", {
  # n = floor(1.7 * fwhm / (dppp * ms2_time))
  # 1.7 * 12 / (7.0 * 0.064) = 20.4 / 0.448 = 45.5 -> floor = 45
  result <- estimate_window_count_preview(12, 7.0, 0.064)
  expect_equal(result, 45)
})

test_that("estimate_window_count_preview respects min_windows", {
  # Very short FWHM -> few windows, but min_windows kicks in
  result <- estimate_window_count_preview(1, 7.0, 0.5, min_windows = 10)
  expect_true(result >= 10)
})

test_that("estimate_window_count_preview respects max_windows", {
  # Very long FWHM + fast scan -> many windows, but max_windows caps
  result <- estimate_window_count_preview(30, 1.5, 0.003, max_windows = 200)
  expect_true(result <= 200)
})

test_that("estimate_window_count_preview returns integer", {
  result <- estimate_window_count_preview(12, 7.0, 0.064)
  expect_equal(result, floor(result))
})

# =============================================================================
# calculate_satisfaction_ratio() - Fraction of values meeting target
# =============================================================================

test_that("calculate_satisfaction_ratio counts values above target", {
  values <- c(5, 7, 8, 10, 12)
  result <- calculate_satisfaction_ratio(values, target = 7)
  # Returns list with $satisfaction_ratio, $n_satisfied, $n_total
  expect_equal(result$satisfaction_ratio, 0.8)
  expect_equal(result$n_satisfied, 4)
  expect_equal(result$n_total, 5)
})

test_that("calculate_satisfaction_ratio handles all meeting target", {
  values <- c(10, 12, 15)
  result <- calculate_satisfaction_ratio(values, target = 5)
  expect_equal(result$satisfaction_ratio, 1.0)
})

test_that("calculate_satisfaction_ratio handles none meeting target", {
  values <- c(1, 2, 3)
  result <- calculate_satisfaction_ratio(values, target = 10)
  expect_equal(result$satisfaction_ratio, 0.0)
})

test_that("calculate_satisfaction_ratio supports within direction", {
  values <- c(5, 7, 8, 10, 12)
  result <- calculate_satisfaction_ratio(values, target = 8, tolerance = 2,
                                         direction = "within")
  # within [6, 10]: 7, 8, 10 -> 3/5 = 0.6
  expect_equal(result$satisfaction_ratio, 0.6)
})
