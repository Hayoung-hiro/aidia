# test-rtbin-filter-perf.R
#
# PLAN-rtbin-filter-perf (#9): the per-RT-bin `filter(rt_group == i)` rescans in
# the three mz_optimization.R strategies (LOCAL parent, greedy, KDE) were
# replaced by a single split() before the loop plus CHARACTER-key indexing.
# Pure performance change -> window boundaries and counts must be identical.
#
# Guarantees pinned here:
#   (1) the selection idiom is equivalent for every bin (incl. empty ones), and
#       character-key indexing is REQUIRED (positional would mismap for n>=10);
#   (2) the real optimizers run crash-free with empty bins, emit the fallback
#       row unchanged, map each bin correctly, and (LOCAL) report covered counts
#       identical to a filter()-based reference.

# ---------------------------------------------------------------------------
# (1) split()[[as.character(i)]] %||% pd[0, ]  ==  filter(rt_group == i)
# ---------------------------------------------------------------------------

test_that("split + character-key indexing reproduces filter(rt_group == i) for every bin", {
  set.seed(9)
  n_bins <- 12                                   # >= 10 so split keys sort lexically
  counts <- c(3, 5, 2, 0, 7, 4, 6, 1, 8, 0, 5, 3)   # bins 4 and 10 empty
  rt_group <- rep(seq_len(n_bins), times = counts)
  pd <- data.frame(
    Precursor.Mz = runif(sum(counts), 400, 1200),
    rt_group     = rt_group
  )
  pd <- pd[sample(nrow(pd)), , drop = FALSE]      # non-trivial order; split must preserve it

  bins <- split(pd, pd$rt_group)

  for (i in seq_len(n_bins)) {
    ref <- dplyr::filter(pd, rt_group == i)                 # BEFORE idiom
    got <- bins[[as.character(i)]] %||% pd[0, ]             # AFTER idiom
    expect_equal(nrow(got), nrow(ref), info = sprintf("bin %d row count", i))
    for (col in names(pd)) {                                # same rows, same order
      expect_equal(got[[col]], ref[[col]], ignore_attr = TRUE,
                   info = sprintf("bin %d column %s", i, col))
    }
  }
})

test_that("character-key indexing maps by label and is gap-safe (positional would not)", {
  # rt_group is integer, so split() names groups by numeric-sorted value. The
  # loop indexes by as.character(i): for a present bin it returns that bin's
  # rows (== filter(rt_group == i)); for an absent bin (a gap) it returns NULL,
  # which the %||% fallback turns into a 0-row frame. Positional bins[[i]] would
  # instead return whatever list element sits at position i -- the wrong bin.
  pd <- data.frame(
    Precursor.Mz = runif(40, 400, 1200),
    rt_group     = rep(c(1, 2, 4, 5), each = 10)   # bin 3 absent (a gap)
  )
  bins <- split(pd, pd$rt_group)

  # present bins map correctly by character key
  for (i in c(1, 2, 4, 5)) {
    expect_equal(bins[[as.character(i)]]$Precursor.Mz,
                 dplyr::filter(pd, rt_group == i)$Precursor.Mz,
                 info = sprintf("bin %d", i))
  }
  # absent bin 3 -> NULL -> %||% fallback (0-row frame)
  expect_null(bins[[as.character(3)]])
  # positional would mismap: the 3rd list element is bin "4", not "3"
  expect_equal(names(bins)[3], "4")
})

# ---------------------------------------------------------------------------
# (2) Real optimizers: empty bin -> crash-free fallback; correct bin mapping
# ---------------------------------------------------------------------------

test_that("optimize_mz_ranges handles empty bins and preserves per-bin mapping", {
  set.seed(909)
  n_bins  <- 12
  counts  <- c(30, 40, 25, 0, 50, 35, 45, 20, 60, 0, 40, 30)   # bins 4, 10 empty
  centers <- seq(500, 1100, length.out = n_bins)                # ~54.5 Da apart
  rt_group <- rep(seq_len(n_bins), times = counts)
  pd <- data.frame(
    Precursor.Mz = rnorm(sum(counts), mean = centers[rt_group], sd = 15),
    RT.Apex      = rt_group * 10,
    rt_group     = rt_group
  )
  pd <- pd[sample(nrow(pd)), , drop = FALSE]

  rt_stats <- data.frame(
    rt_segment_id = seq_len(n_bins),
    rt_start      = (seq_len(n_bins) - 1) * 10 + 5,
    rt_end        = seq_len(n_bins) * 10 + 5,
    n_precursors  = counts
  )

  empty_bins <- which(counts == 0)                         # 4, 10
  filled     <- setdiff(seq_len(n_bins), empty_bins)

  for (name in c("greedy", "kde", "quantile", "coverage", "outlier")) {
    cfg    <- do.call(paste0(name, "_config"), list())
    result <- NULL
    invisible(capture.output(
      result <- suppressWarnings(
        optimize_mz_ranges(cfg, pd, rt_stats,
                           n_windows_per_bin = 5, min_width_da = 2)
      )
    ))
    label <- sprintf("[strategy: %s]", name)

    # crash-free, one row per bin, in bin order
    expect_s3_class(result, "data.frame")
    expect_equal(nrow(result), n_bins, info = label)
    expect_equal(result$rt_segment_id, seq_len(n_bins), info = label)

    # empty bins get the fallback row unchanged
    expect_true(all(result$n_precursors_covered[empty_bins] == 0), info = label)
    expect_true(all(is.na(result$coverage_ratio[empty_bins])), info = label)

    # filled bins mapped to the correct cluster (mis-map would land ~54.5 Da off)
    mz_center <- (result$mz_min + result$mz_max) / 2
    expect_true(all(abs(mz_center[filled] - centers[filled]) < 25), info = label)

    # LOCAL strategies count covered as sum(mz within [mz_min, mz_max]); compare
    # to a filter()-based reference -> before/after count identity, boundary-safe.
    if (name %in% c("quantile", "coverage", "outlier")) {
      ref_covered <- vapply(filled, function(i) {
        mz <- dplyr::filter(pd, rt_group == i)$Precursor.Mz
        sum(mz >= result$mz_min[i] & mz <= result$mz_max[i])
      }, numeric(1))
      expect_equal(result$n_precursors_covered[filled], ref_covered, info = label)
    }
  }
})
