# test-rt-membership-unify.R
#
# PLAN-rt-membership-unify: precursor -> RT bin membership is now a single
# shared rule, bin_membership() (rt_group when present, else RT.Apex range),
# consumed by generation, smoothing coverage recomputation, evaluation and
# plotting. These tests pin the two acceptance criteria:
#   (a) fixed binning coverage is invariant to the rule (rt_group is derived
#       from the same contiguous RT cut, so both branches coincide);
#   (b) for adaptive+merge data (rt_group NOT aligned with RT.Apex range),
#       smoothing coverage counts equal the generation membership counts,
#       whereas the old RT-range rule would have diverged.

# ---------------------------------------------------------------------------
# (a) Fixed binning: coverage identical with vs. without rt_group
# ---------------------------------------------------------------------------

test_that("fixed binning coverage is invariant to the membership rule", {
  set.seed(101)
  n_bins   <- 5
  rt_start <- seq(0, by = 10, length.out = n_bins)   # 0,10,20,30,40
  rt_end   <- rt_start + 10                            # 10,20,30,40,50
  per_bin  <- 40

  # Fixed binning: each precursor's rt_group is exactly the contiguous RT bin
  # its (interior) RT.Apex falls into -> the two rules must agree.
  bin_of <- rep(seq_len(n_bins), each = per_bin)
  pd <- data.frame(
    Precursor.Mz = runif(n_bins * per_bin, 400, 1000),
    RT.Apex      = rt_start[bin_of] + runif(n_bins * per_bin, 1, 9),  # interior
    rt_group     = bin_of
  )

  mz_ranges <- data.frame(
    rt_segment_id        = seq_len(n_bins),
    rt_start             = rt_start,
    rt_end               = rt_end,
    mz_min               = rep(500, n_bins),
    mz_max               = rep(900, n_bins),
    mz_width             = rep(400, n_bins),
    n_precursors_covered = rep(NA_real_, n_bins),
    coverage_ratio       = rep(NA_real_, n_bins)
  )

  cov_with    <- suppressWarnings(.recalculate_coverage(mz_ranges, pd))
  cov_without <- suppressWarnings(
    .recalculate_coverage(mz_ranges, pd[, c("Precursor.Mz", "RT.Apex")])
  )

  expect_equal(cov_with$n_precursors_covered, cov_without$n_precursors_covered)
  expect_equal(cov_with$coverage_ratio,       cov_without$coverage_ratio)
})

# ---------------------------------------------------------------------------
# (b) Adaptive+merge: smoothing coverage count == generation membership count
# ---------------------------------------------------------------------------

test_that("adaptive+merge smoothing coverage matches generation membership", {
  set.seed(202)
  n_bins   <- 4
  rt_start <- seq(0, by = 10, length.out = n_bins)   # 0,10,20,30
  rt_end   <- rt_start + 10
  n        <- 200

  # adaptive+merge: rt_group is the assigned bin label and is deliberately
  # NOT aligned with RT.Apex (all RT.Apex fall inside bin 1's range, but the
  # labels spread across all bins) -- the regime where the old two rules split.
  pd <- data.frame(
    Precursor.Mz = runif(n, 400, 1000),
    RT.Apex      = runif(n, 1, 9),                    # all inside bin 1's range
    rt_group     = rep(seq_len(n_bins), length.out = n)
  )

  # mz range spans the full precursor m/z so every member counts as covered:
  # n_precursors_covered[i] == number of precursors that belong to bin i.
  mz_ranges <- data.frame(
    rt_segment_id        = seq_len(n_bins),
    rt_start             = rt_start,
    rt_end               = rt_end,
    mz_min               = rep(300, n_bins),
    mz_max               = rep(1100, n_bins),
    mz_width             = rep(800, n_bins),
    n_precursors_covered = rep(NA_real_, n_bins),
    coverage_ratio       = rep(NA_real_, n_bins)
  )

  rec <- suppressWarnings(.recalculate_coverage(mz_ranges, pd))

  # Generation membership via the same shared helper (rt_group branch).
  gen_counts <- vapply(seq_len(n_bins), function(i) {
    sum(bin_membership(pd, rt_start[i], rt_end[i], i))
  }, numeric(1))

  # Smoothing coverage now equals generation membership (the fix).
  expect_equal(rec$n_precursors_covered, gen_counts)

  # And the old RT-range rule WOULD have diverged (nearly all in bin 1),
  # proving the test is non-trivial.
  rtrange_counts <- vapply(seq_len(n_bins), function(i) {
    sum(pd$RT.Apex >= rt_start[i] & pd$RT.Apex <= rt_end[i])
  }, numeric(1))
  expect_false(isTRUE(all.equal(rec$n_precursors_covered, rtrange_counts)))
})

# ---------------------------------------------------------------------------
# NA normalization (reviewer fix): missing rt_group / RT.Apex -> FALSE, so
# direct logical-index consumers (window_evaluation) match dplyr::filter.
# ---------------------------------------------------------------------------

test_that("bin_membership normalizes NA to FALSE (both branches)", {
  # rt_group branch: NA rt_group -> FALSE, not NA
  pd <- data.frame(rt_group = c(1L, NA, 2L, 1L))
  m <- bin_membership(pd, 0, 10, 1L)
  expect_equal(m, c(TRUE, FALSE, FALSE, TRUE))
  expect_false(any(is.na(m)))
  # RT.Apex range branch: NA RT.Apex -> FALSE
  pd2 <- data.frame(RT.Apex = c(1, NA, 5, 20))
  m2 <- bin_membership(pd2, 0, 10, 1L)
  expect_equal(m2, c(TRUE, FALSE, TRUE, FALSE))
  expect_false(any(is.na(m2)))
})
