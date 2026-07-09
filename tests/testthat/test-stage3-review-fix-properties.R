# test-stage3-review-fix-properties.R
#
# Property-based / fuzz guards for the two adversarial-review fixes (a45d1c5):
#   Fix 1: fractional min_width_da -> integer floor (redistribute + flagship)
#   Fix 2: bin_membership NA -> FALSE
# Seeded so it is deterministic. Each block accumulates invariant violations
# across many random inputs and asserts zero. (A larger unseeded sweep -- 26k
# iters, 0 failures -- was run manually; this is the CI-sized guard.)

# ---------------------------------------------------------------------------
# Fix 1a: redistribute_integer_widths tolerates fractional floors
# ---------------------------------------------------------------------------

test_that("redistribute_integer_widths holds all invariants over random inputs (fractional floors)", {
  set.seed(101)
  fails <- character(0)
  for (i in 1:2500) {
    N <- sample(1:30, 1)
    floor_da <- sample(c(runif(1, 0.3, 10), sample(1:8, 1)), 1)   # fractional + integer
    cf <- ceiling(floor_da)
    raw <- switch(sample(1:5, 1),
      runif(N, 0.1, 10),
      c(runif(1, 50, 100), runif(max(N - 1, 0), 0.1, 2)),
      rep(1, N),
      rep(0, N),
      { v <- runif(N, 0.1, 10); if (N > 1) v[sample(N, 1)] <- NA; v })
    W <- if (sample(c(TRUE, FALSE), 1)) N * cf + sample(0:60, 1)
         else if (N * cf > 1) sample(seq_len(N * cf - 1), 1) else N * cf
    res <- tryCatch(redistribute_integer_widths(W, N, raw, floor_da),
                    error = function(e) "ERR")
    if (identical(res, "ERR")) { fails <- c(fails, sprintf("crash W=%g N=%d floor=%.3f", W, N, floor_da)); next }
    if (N * cf > W) {
      if (!is.null(res)) fails <- c(fails, "infeasible not NULL")
    } else {
      if (length(res) != N) fails <- c(fails, "length")
      if (!isTRUE(sum(res) == W)) fails <- c(fails, "sum")
      if (!all(res >= cf)) fails <- c(fails, "floor")
      if (!all(res == round(res))) fails <- c(fails, "integer")
    }
  }
  expect_equal(length(fails), 0, info = paste(utils::head(fails, 5), collapse = " ; "))
})

# ---------------------------------------------------------------------------
# Fix 1b: generate_variable_windows_internal end-to-end, fractional min_width
# ---------------------------------------------------------------------------

test_that("digitization holds count/floor/contiguity over random fractional min_width", {
  set.seed(202)
  fails <- character(0)
  for (i in 1:250) {
    N <- sample(1:18, 1)
    min_w <- sample(c(runif(1, 1, 8), sample(1:6, 1)), 1)
    max_w <- min_w + runif(1, 5, 200)
    mz_min <- runif(1, 350, 1100)
    mz_max <- mz_min + runif(1, max(min_w, 1), 400)
    npr <- sample((2 * N + 5):(2 * N + 300), 1)
    pmz <- runif(npr, mz_min, mz_max)
    fzo <- sample(c(0, 0.25), 1)
    w <- tryCatch(
      suppressWarnings(suppressMessages(generate_variable_windows_internal(
        precursor_mz = pmz, mz_min = mz_min, mz_max = mz_max, n_windows = N,
        min_width_da = min_w, max_width_da = max_w, fz_offset = fzo))),
      error = function(e) structure(list(), err = conditionMessage(e)))
    if (!is.null(attr(w, "err"))) { fails <- c(fails, paste("crash", attr(w, "err"))); next }
    if (nrow(w) != N) fails <- c(fails, "countN")
    if (!all(w$window_width >= min_w - 1e-6)) fails <- c(fails, "floor")
    if (nrow(w) > 1 && !isTRUE(all(abs(w$mz_start[-1] - w$mz_end[-nrow(w)]) < 1e-6)))
      fails <- c(fails, "contiguity")
    if (fzo == 0 &&
        !(w$mz_start[1] <= floor(mz_min) + 1e-9 && w$mz_end[nrow(w)] >= ceiling(mz_max) - 1e-9))
      fails <- c(fails, "coverage")
  }
  expect_equal(length(fails), 0, info = paste(utils::head(fails, 5), collapse = " ; "))
})

# ---------------------------------------------------------------------------
# Fix 2: bin_membership never returns NA and matches the filter reference
# ---------------------------------------------------------------------------

test_that("bin_membership normalizes NA over random inputs (both branches)", {
  set.seed(303)
  fails <- character(0)
  for (i in 1:2500) {
    n <- sample(1:50, 1)
    rt_start <- runif(1, 0, 30); rt_end <- rt_start + runif(1, 1, 30)
    seg <- sample(1:12, 1)
    if (sample(c(TRUE, FALSE), 1)) {
      g <- sample(1:12, n, replace = TRUE); g[runif(n) < 0.2] <- NA
      pd <- data.frame(rt_group = g, RT.Apex = runif(n, 0, 60))
      expected <- !is.na(g) & (g == seg)
    } else {
      a <- runif(n, 0, 60); a[runif(n) < 0.2] <- NA
      pd <- data.frame(RT.Apex = a)
      expected <- !is.na(a) & (a >= rt_start & a <= rt_end)
    }
    m <- tryCatch(bin_membership(pd, rt_start, rt_end, seg), error = function(e) "ERR")
    if (identical(m, "ERR")) { fails <- c(fails, "crash"); next }
    if (any(is.na(m))) fails <- c(fails, "NA present")
    if (length(m) != n) fails <- c(fails, "length")
    if (!is.logical(m)) fails <- c(fails, "not logical")
    if (n > 0 && !isTRUE(all(m == expected))) fails <- c(fails, "mismatch")
  }
  expect_equal(length(fails), 0, info = paste(utils::head(fails, 5), collapse = " ; "))
})

test_that(".recalculate_coverage is finite with NA-laden membership data", {
  set.seed(404)
  fails <- character(0)
  for (i in 1:60) {
    nb <- sample(2:6, 1)
    rs <- seq(0, by = 10, length.out = nb); re <- rs + 10
    npr <- sample(50:300, 1)
    g <- sample(seq_len(nb), npr, replace = TRUE); g[runif(npr) < 0.15] <- NA
    ap <- runif(npr, 0, nb * 10); ap[runif(npr) < 0.15] <- NA
    pd <- data.frame(Precursor.Mz = runif(npr, 400, 1000), RT.Apex = ap, rt_group = g)
    mzr <- data.frame(rt_segment_id = seq_len(nb), rt_start = rs, rt_end = re,
                      mz_min = rep(400, nb), mz_max = rep(1000, nb), mz_width = rep(600, nb),
                      n_precursors_covered = rep(NA_real_, nb), coverage_ratio = rep(NA_real_, nb))
    rec <- tryCatch(.recalculate_coverage(mzr, pd), error = function(e) "ERR")
    if (identical(rec, "ERR")) { fails <- c(fails, "crash"); next }
    if (!all(is.finite(rec$n_precursors_covered))) fails <- c(fails, "non-finite covered")
    if (any(is.nan(rec$coverage_ratio))) fails <- c(fails, "NaN ratio")
  }
  expect_equal(length(fails), 0, info = paste(utils::head(fails, 5), collapse = " ; "))
})
