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

# ---------------------------------------------------------------------------
# H1: empty interior RT bin left non-contiguous cut() labels (e.g. {1,6}),
# desynchronizing the positional-index vs `rt_group == i` consumers. After
# densification, labels must be contiguous 1..n and every occupied bin's
# precursors must be reachable by its row index.
# ---------------------------------------------------------------------------

test_that("empty interior RT bin yields contiguous, correctly-mapped labels", {
  # Breaks at 1,6,11,16,21,26,31; only bins 1 and 6 are occupied.
  df <- data.frame(
    RT.Apex      = c(1, 2, 30, 31),
    Precursor.Mz = c(500, 510, 700, 710)
  )

  res <- perform_fixed_rt_binning_internal(df, rt_bin_width_min = 5)

  # Two occupied bins, labelled contiguously 1..2 (not {1, 6}).
  expect_equal(res$n_bins, 2)
  expect_equal(res$stats$rt_segment_id, 1:2)
  expect_setequal(unique(res$data$rt_group), 1:2)

  # The late-eluting precursors (RT 30-31) are reachable via row index 2 and
  # its stats row describes their RT span (not an empty-bin fallback).
  expect_equal(sum(res$data$rt_group == 2), 2)
  late <- res$stats[res$stats$rt_segment_id == 2, ]
  expect_equal(late$n_precursors, 2)
  expect_equal(late$rt_start, 30)
  expect_equal(late$rt_end, 31)
})

# ---------------------------------------------------------------------------
# H4: count_precursors_in_windows() used cut() (one bin per precursor), which
# cannot represent the overlapping windows staggered mode produces. Independent
# per-window counting must count an overlap-region precursor in both windows,
# while still counting a shared tiling boundary exactly once.
# ---------------------------------------------------------------------------

test_that("count_precursors_in_windows counts overlap-region precursor in both windows", {
  # Two overlapping windows [400,450) and [425,475); 430 is in both.
  counts <- count_precursors_in_windows(c(430), c(400, 425), c(450, 475))
  expect_equal(counts, c(1, 1))
})

test_that("count_precursors_in_windows counts a shared tiling boundary once", {
  # Contiguous [400,500) and [500,600); 500 belongs to the second window only.
  counts <- count_precursors_in_windows(c(450, 500, 550), c(400, 500), c(500, 600))
  expect_equal(counts, c(1, 2))
})

test_that("count_precursors_in_windows keeps the precursor at the maximum end", {
  counts <- count_precursors_in_windows(c(600), c(400, 500), c(500, 600))
  expect_equal(counts, c(0, 1))
})

# ---------------------------------------------------------------------------
# M5: count_precursors_in_2d_windows() used a closed m/z interval [start,end],
# double-counting a precursor on a shared tiling boundary. Half-open [start,end)
# attributes it to exactly one window.
# ---------------------------------------------------------------------------

test_that("count_precursors_in_2d_windows counts a shared m/z boundary once", {
  counts <- count_precursors_in_2d_windows(
    precursor_rt    = 15,
    precursor_mz    = 500,          # exactly on the 500 boundary
    window_rt_start = c(10, 10),
    window_rt_end   = c(20, 20),
    window_mz_start = c(400, 500),
    window_mz_end   = c(500, 600)
  )
  expect_equal(counts, c(0, 1))
  expect_equal(sum(counts), 1)
})

test_that("count_precursors_in_2d_windows keeps a precursor on the top m/z edge", {
  # Regression: the half-open change must not drop the precursor at the last
  # window's (closed) upper bound -- matches the 1D counter's max-end behaviour.
  counts <- count_precursors_in_2d_windows(
    precursor_rt    = 15,
    precursor_mz    = 600,          # exactly on the overall max end
    window_rt_start = c(10, 10),
    window_rt_end   = c(20, 20),
    window_mz_start = c(400, 500),
    window_mz_end   = c(500, 600)
  )
  expect_equal(counts, c(0, 1))
})

test_that("window counters tolerate NA precursor m/z (no crash)", {
  expect_no_error(c1 <- count_precursors_in_windows(c(450, NA, 500), c(400, 500), c(500, 600)))
  expect_equal(c1, c(1, 1))
  expect_no_error(
    c2 <- count_precursors_in_2d_windows(c(15, 15), c(450, NA), c(10, 10), c(20, 20),
                                         c(400, 500), c(500, 600))
  )
  expect_equal(c2, c(1, 0))
})

# ---------------------------------------------------------------------------
# M2: calculate_satisfaction_ratio reported a ratio over non-NA values but an
# n_total over ALL values, so n_satisfied / n_total disagreed with the ratio
# whenever DPPP contained NAs (e.g. from a missing FWHM).
# ---------------------------------------------------------------------------

test_that("calculate_satisfaction_ratio keeps ratio, n_satisfied, n_total consistent", {
  r <- calculate_satisfaction_ratio(c(10, 20, NA), target = 15, direction = "greater")
  expect_equal(r$n_total, 2)                        # NA excluded from denominator
  expect_equal(r$n_satisfied, 1)
  expect_equal(r$satisfaction_ratio, 0.5)
  expect_equal(r$satisfaction_ratio, r$n_satisfied / r$n_total)
})

test_that("calculate_satisfaction_ratio unchanged without NAs, safe when all NA", {
  r <- calculate_satisfaction_ratio(c(10, 20, 30), target = 15, direction = "greater")
  expect_equal(r$n_total, 3)
  expect_equal(r$satisfaction_ratio, 2 / 3)

  r_na <- calculate_satisfaction_ratio(c(NA_real_, NA_real_), target = 15)
  expect_equal(r_na$n_total, 0)
  expect_true(is.na(r_na$satisfaction_ratio))
})
