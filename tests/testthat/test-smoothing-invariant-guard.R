# test-smoothing-invariant-guard.R
#
# PLAN-smoothing-invariant-guard: smoothing mz_min / mz_max independently can
# yield bins with mz_min >= mz_max (crossed) or width below the absolute floor
# ABSOLUTE_MIN_WIDTH_DA. The shared guard .repair_mz_ranges() restores ONLY such
# bins to their raw (pre-smoothing) boundaries. quantile/outlier are the real
# targets; greedy is a mathematical no-op (fixed-width re-centering keeps
# width = n_windows_per_bin * min_width_da >> floor).

# ---------------------------------------------------------------------------
# Local fixtures
# ---------------------------------------------------------------------------

make_guard_mz_ranges <- function(n_bins = 12, seed = 42) {
  set.seed(seed)
  mz_min <- 480 + runif(n_bins, -12, 12)
  # +30 base keeps every raw bin valid (width in [24, 36]); the separate jitter
  # on mz_max makes min/max jagged independently.
  mz_max <- mz_min + 30 + runif(n_bins, -6, 6)
  data.frame(
    rt_segment_id = seq_len(n_bins),
    rt_start = seq(0, by = 5, length.out = n_bins),
    rt_end   = seq(0, by = 5, length.out = n_bins) + 5,
    mz_min   = mz_min,
    mz_max   = mz_max,
    mz_width = mz_max - mz_min,
    n_precursors_covered = rep(50, n_bins),
    coverage_ratio = rep(0.9, n_bins)
  )
}

make_guard_precursors <- function(n = 400, seed = 7) {
  set.seed(seed)
  data.frame(
    Precursor.Mz = runif(n, 450, 540),
    RT.Apex = runif(n, 0, 60)
  )
}

# ---------------------------------------------------------------------------
# Unit: .repair_mz_ranges restoration logic (deterministic)
# ---------------------------------------------------------------------------

test_that(".repair_mz_ranges restores crossed / sub-floor bins from raw", {
  raw <- data.frame(mz_min = c(400, 500, 600, 700),
                    mz_max = c(410, 510, 610, 710),
                    mz_width = c(10, 10, 10, 10))
  # row 2: crossed (mz_min > mz_max); row 3: sub-floor width 0.5 < 1.0
  smoothed <- data.frame(mz_min = c(401, 512, 605.0, 701),
                         mz_max = c(409, 508, 605.5, 709),
                         mz_width = c(8, -4, 0.5, 8))

  repaired <- .repair_mz_ranges(smoothed, raw, ABSOLUTE_MIN_WIDTH_DA)

  expect_equal(attr(repaired, "n_repaired"), 2L)
  # bad rows restored to raw
  expect_equal(repaired$mz_min[c(2, 3)], raw$mz_min[c(2, 3)])
  expect_equal(repaired$mz_max[c(2, 3)], raw$mz_max[c(2, 3)])
  expect_equal(repaired$mz_width[c(2, 3)], raw$mz_width[c(2, 3)])
  # good rows keep smoothed values
  expect_equal(repaired$mz_min[c(1, 4)], smoothed$mz_min[c(1, 4)])
  expect_equal(repaired$mz_max[c(1, 4)], smoothed$mz_max[c(1, 4)])
  # invariant holds everywhere after repair
  expect_true(all(repaired$mz_min < repaired$mz_max))
  expect_true(all(repaired$mz_max - repaired$mz_min >= ABSOLUTE_MIN_WIDTH_DA))
})

test_that(".repair_mz_ranges is a no-op (n_repaired=0) on valid input", {
  raw <- data.frame(mz_min = c(400, 500, 600),
                    mz_max = c(410, 510, 610),
                    mz_width = c(10, 10, 10))
  smoothed <- data.frame(mz_min = c(401, 501, 601),
                         mz_max = c(409, 509, 609),
                         mz_width = c(8, 8, 8))

  repaired <- .repair_mz_ranges(smoothed, raw, ABSOLUTE_MIN_WIDTH_DA)

  expect_equal(attr(repaired, "n_repaired"), 0L)
  expect_equal(repaired[c("mz_min", "mz_max", "mz_width")],
               smoothed[c("mz_min", "mz_max", "mz_width")])
})

# ---------------------------------------------------------------------------
# Integration: quantile — invariant holds end-to-end (guard wired)
# ---------------------------------------------------------------------------

test_that("quantile smoothing yields valid boundaries (guard integrated)", {
  mz <- make_guard_mz_ranges(12)
  pd <- make_guard_precursors()
  cfg <- quantile_config(apply_smoothing = TRUE)

  invisible(capture.output(
    smoothed <- suppressWarnings(apply_smoothing(cfg, mz, pd))
  ))

  # Post-guard, no bin may violate the absolute invariant.
  expect_true(all(smoothed$mz_min < smoothed$mz_max),
              info = "a crossed bin survived smoothing")
  expect_true(all(smoothed$mz_max - smoothed$mz_min >= ABSOLUTE_MIN_WIDTH_DA),
              info = "a sub-floor-width bin survived smoothing")
})

# ---------------------------------------------------------------------------
# Integration: greedy — zero repairs, byte-identical (guard is a no-op)
# ---------------------------------------------------------------------------

test_that("greedy smoothing triggers zero repairs and stays byte-identical", {
  mz <- make_guard_mz_ranges(10)
  pd <- make_guard_precursors()
  cfg <- greedy_config(apply_smoothing = TRUE)

  invisible(capture.output(
    smoothed <- suppressWarnings(
      apply_smoothing(cfg, mz, pd, n_windows_per_bin = 10, min_width_da = 2)
    )
  ))

  # n_repaired == 0 proves the guard restored nothing -> greedy output is
  # unchanged (byte-identical) vs. the pre-guard implementation.
  expect_equal(attr(smoothed, "n_repaired"), 0L)
  expect_true(all(smoothed$mz_min < smoothed$mz_max))
  expect_true(all(smoothed$mz_max - smoothed$mz_min >= ABSOLUTE_MIN_WIDTH_DA))
})
