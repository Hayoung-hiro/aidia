# Regression coverage for #19: the final integer/FZ windows must retain useful
# density adaptation, not merely satisfy count/contiguity/mirror invariants.

.density_skewed_mz <- function(n = 10L) {
  c(seq(400.01, 400 + 2 * n * 0.2, length.out = 9 * n),
    seq(400 + 2 * n * 0.21, 400 + 2 * n - 0.01, length.out = n))
}

# Independent reference accounting on the delivered geometry. Shared edges are
# half-open; the last window includes its top edge, as in Stage 3 accounting.
.density_counts <- function(mz, windows) {
  vapply(seq_len(nrow(windows)), function(i) {
    sum(mz >= windows$mz_start[i] &
          (mz < windows$mz_end[i] |
             (i == nrow(windows) & mz == windows$mz_end[i])))
  }, integer(1))
}

test_that("density retains adaptation after integerization and FZ placement", {
  for (n in c(10L, 40L)) {
    mz <- .density_skewed_mz(n)
    for (fz in c(0, 0.25)) {
      dense <- generate_variable_windows_internal(mz, 400, 400 + 2 * n, n, 1, 80,
                                                  fz_offset = fz)
      equal <- generate_fixed_windows_internal(400, 400 + 2 * n, n, 1, 80,
                                               fz_offset = fz)
      dense_counts <- .density_counts(mz, dense)
      equal_counts <- .density_counts(mz, equal)
      expect_equal(sum(dense_counts), sum(equal_counts))
      expect_true(stats::sd(dense_counts) < stats::sd(equal_counts),
                  info = paste("N", n, "FZ", fz))
      expect_false(isTRUE(all.equal(dense$mz_start, equal$mz_start)))
      expect_equal(nrow(dense), n)
      expect_equal(dense$mz_start[-1], head(dense$mz_end, -1))
      expect_true(all(dense$window_width >= 1))
    }
  }
})

test_that("smoothing does not erase the minimal two-window density shape", {
  mz <- c(401, 402, 402.5, 419)
  dense <- generate_variable_windows_internal(mz, 400, 420, 2, 1, 80)
  expect_lt(dense$window_width[1], dense$window_width[2])
  expect_equal(sum(dense$window_width), 20)
})

test_that("smoothing never worsens the delivered load relative to its unsmoothed candidate", {
  set.seed(19019)
  improvements <- 0L
  for (i in seq_len(20)) {
    n <- sample(c(4L, 10L, 40L), 1)
    span <- sample(c(2, 5, 10), 1) * n
    mz <- 400 + span * rbeta(500, 2, 6)
    for (fz in c(0, 0.25)) {
      dense <- generate_variable_windows_internal(mz, 400, 400 + span, n, 1, 80,
                                                  fz_offset = fz)
      unsmoothed <- generate_variable_windows_internal(mz, 400, 400 + span, n, 1, 80,
                                                       max_change_ratio = 0,
                                                       fz_offset = fz)
      counts <- .density_counts(mz, dense)
      raw_counts <- .density_counts(mz, unsmoothed)
      expect_equal(sum(counts), sum(raw_counts))
      expect_lte(sum(as.double(counts)^2), sum(as.double(raw_counts)^2))
      improvements <- improvements + as.integer(
        sum(as.double(counts)^2) < sum(as.double(raw_counts)^2))
    }
  }
  # Keep useful smoothing: unconditionally returning the raw partition must not
  # pass this guard merely because it can never worsen its own score.
  expect_gt(improvements, 0L)
})

test_that("a boundary uses the available slack when the nominal step exceeds max width", {
  mz <- c(seq(400.01, 520, length.out = 900),
          seq(526, 999.99, length.out = 100))
  # Initial width 75, step 7.5, max 80: a 5 Da move is feasible. One iteration
  # with smoothing disabled isolates the actual boundary update from its tail.
  dense <- generate_variable_windows_internal(mz, 400, 1000, 8, 2, 80,
                                              max_iterations = 1,
                                              max_change_ratio = 0)
  equal <- generate_fixed_windows_internal(400, 1000, 8, 2, 80)
  expect_lt(dense$window_width[1], 75)
  expect_true(all(dense$window_width <= 80))
  expect_lt(stats::sd(.density_counts(mz, dense)),
            stats::sd(.density_counts(mz, equal)))
  expect_equal(dense$mz_start[-1], head(dense$mz_end, -1))
})

test_that("uniform density and a fully constrained range may remain equal-width", {
  uniform <- seq(400.05, 419.95, by = 0.1)
  dense <- generate_variable_windows_internal(uniform, 400, 420, 10, 1, 80)
  expect_equal(dense$window_width, rep(2, 10))
  constrained <- generate_variable_windows_internal(.density_skewed_mz(),
                                                     400, 420, 10, 2, 80)
  expect_equal(constrained$window_width, rep(2, 10))
})

test_that("integer remainder ties preserve the width multiset under reflection", {
  # Equal fractional remainders on different target widths used to allocate by
  # position: c(1.5, 2.5) -> c(2, 2), but its reflection -> c(3, 1).
  raw <- c(1.5, 2.5)
  forward <- redistribute_integer_widths(4, 2, raw, 1)
  reflected <- redistribute_integer_widths(4, 2, rev(raw), 1)
  expect_equal(sort(forward), sort(reflected))
  expect_equal(sum(forward), 4)
})

test_that("adaptive narrow partitions retain reflection symmetry after candidate selection", {
  # The older mirror test mostly uses spans wider than N * max_width, which
  # makes uniform partitions common and hides integer tie/selection asymmetry.
  set.seed(191919)
  failures <- character()
  for (i in seq_len(160)) {
    n <- sample(3:30, 1)
    span <- n * sample(2:20, 1)
    mz <- 400 + span * rbeta(200, 2, 6)
    forward <- generate_variable_windows_internal(mz, 400, 400 + span, n, 1, 80)
    reflected <- generate_variable_windows_internal(800 + span - mz,
                                                      400, 400 + span, n, 1, 80)
    if (!isTRUE(all.equal(sort(forward$window_width), sort(reflected$window_width)))) {
      failures <- c(failures, paste("case", i, "N", n, "span", span))
    }
  }
  expect_equal(length(failures), 0, info = paste(failures, collapse = "; "))
})

test_that("Stage 3 Greedy density improves final load balance with range smoothing off", {
  n <- 40L
  mz <- .density_skewed_mz(n)
  vd <- structure(list(data = tibble::tibble(Precursor.Mz = mz, RT.Apex = 2, FWHM = 4)),
                  class = c("ValidatedData", "list"))
  plan <- structure(list(
    window_count_per_bin = n,
    instrument = list(preset = "test", cycle_mode = "sequential",
                      ms1_time_sec = 0.5, ms2_time_sec = 0.05),
    scan_time = list(t_scan_ms = 50), required_cycle_time_sec = 2
  ), class = c("OptimizationPlan", "list"))
  for (fz in c(0, 0.25)) {
    results <- list()
    for (mode in c("density", "fixed")) {
      invisible(capture.output(results[[mode]] <- optimize_windows(
        vd, plan, strategy_config = greedy_config(apply_smoothing = FALSE),
        window_mode = mode, min_width_da = 2, max_width_da = 80,
        fz_offset = fz, mz_range_min = 400, mz_range_max = 1000
      )))
    }
    dense <- results$density$windows
    equal <- results$fixed$windows
    expect_equal(nrow(dense), n)
    expect_equal(sum(dense$n_precursors), sum(equal$n_precursors))
    expect_equal(dense$n_precursors, .density_counts(mz, dense))
    expect_lt(stats::sd(dense$n_precursors), stats::sd(equal$n_precursors))
    expect_false(isTRUE(all.equal(dense$mz_start, equal$mz_start)))
  }
})
