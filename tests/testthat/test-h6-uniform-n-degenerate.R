# test-h6-uniform-n-degenerate.R
#
# H6 (uniform-N) for degenerate bins. Regression coverage for the SPEC v2
# follow-up: the legacy early guards in generate_variable_windows_internal()
# (sparse: n_precursors < 2N; narrow: max_possible_windows < 1) previously
# returned generate_fixed_windows_internal(), which caps width at max_width and
# could emit MORE than N windows for a sparse-and-very-wide bin -- inflating
# that bin's cycle time and breaking uniform-N. Both guards now route through
# digitize_windows_to_n(), so every density-mode bin yields exactly N windows.

library(testthat)

if (!exists("generate_variable_windows_internal")) {
  source("../../R/utils_common.R")
  source("../../R/window_generation.R")
}
if (!exists("ABSOLUTE_MIN_WIDTH_DA")) ABSOLUTE_MIN_WIDTH_DA <- 1.0

gen <- function(...) suppressWarnings(suppressMessages(
  generate_variable_windows_internal(...)))

# ---------------------------------------------------------------------------
# The headline regression: sparse AND very wide (range > N * max_width).
# Old path: ceiling(range / max_width) = ceiling(900/80) = 12 > N. New path:
# exactly N windows, each wider than max_width (S2 soft), so cycle time holds.
# ---------------------------------------------------------------------------
test_that("H6: sparse-and-very-wide bin yields exactly N (no overshoot)", {
  set.seed(101)
  n_windows <- 10
  precursor_mz <- runif(15, min = 400, max = 1300)  # 15 < 2N -> sparse guard
  windows <- gen(precursor_mz = precursor_mz, mz_min = 400, mz_max = 1300,
                 n_windows = n_windows, min_width_da = 2, max_width_da = 80,
                 fz_offset = 0)

  expect_equal(nrow(windows), n_windows)                 # exactly N, not 12
  expect_true(all(windows$window_width >= ABSOLUTE_MIN_WIDTH_DA - 1e-9))
  # Soft S2: the wide bin legitimately exceeds max_width rather than adding windows
  expect_true(max(windows$window_width) > 80)
  # A2 coverage + A3 contiguity preserved
  expect_true(min(windows$mz_start) <= floor(400))
  expect_true(max(windows$mz_end)  >= ceiling(1300))
  expect_equal(windows$mz_start[-1], windows$mz_end[-nrow(windows)])
})

test_that("H6: sparse-and-normal-width bin yields exactly N uniform windows", {
  set.seed(102)
  n_windows <- 10
  precursor_mz <- runif(15, min = 400, max = 600)   # sparse, normal width
  windows <- gen(precursor_mz = precursor_mz, mz_min = 400, mz_max = 600,
                 n_windows = n_windows, min_width_da = 5, max_width_da = 50,
                 fz_offset = 0)

  expect_equal(nrow(windows), n_windows)
  expect_equal(sum(windows$window_width), 200, tolerance = 1e-6)
  expect_true(all(windows$window_width == 20))          # uniform 200/10
})

test_that("H6: sparse-and-narrow bin edge-expands to exactly N", {
  set.seed(103)
  n_windows <- 10
  precursor_mz <- runif(5, min = 400, max = 410)    # sparse (5 < 20) + narrow
  windows <- gen(precursor_mz = precursor_mz, mz_min = 400, mz_max = 410,
                 n_windows = n_windows, min_width_da = 2, max_width_da = 50,
                 fz_offset = 0)

  expect_equal(nrow(windows), n_windows)                # A6-consistent: exactly N
  expect_true(min(windows$mz_start) <= floor(400))      # edge-expanded downward
  expect_true(max(windows$mz_end)  >= ceiling(410))     # covers original range
  expect_true(all(windows$window_width >= ABSOLUTE_MIN_WIDTH_DA - 1e-9))
})

test_that("H6: max_possible_windows < 1 guard yields exactly N (was 1 window)", {
  set.seed(104)
  n_windows <- 4
  # Dense enough to clear the sparse guard (50 >= 2N), but range < min_width so
  # the second guard (max_possible_windows = floor(10/20) = 0) fires.
  precursor_mz <- runif(50, min = 400, max = 410)
  windows <- gen(precursor_mz = precursor_mz, mz_min = 400, mz_max = 410,
                 n_windows = n_windows, min_width_da = 20, max_width_da = 50,
                 fz_offset = 0)

  expect_equal(nrow(windows), n_windows)                # exactly N, not 1
  expect_true(min(windows$mz_start) <= floor(400))
  expect_true(max(windows$mz_end)  >= ceiling(410))
  expect_true(all(windows$window_width >= ABSOLUTE_MIN_WIDTH_DA - 1e-9))
})

test_that("H6 never overshoots N across sparse range/width combinations", {
  set.seed(105)
  grid <- expand.grid(N = c(5, 10, 20),
                      span = c(20, 200, 1500),     # narrow / normal / very wide
                      max_w = c(40, 120))
  for (r in seq_len(nrow(grid))) {
    N <- grid$N[r]; span <- grid$span[r]; max_w <- grid$max_w[r]
    pz <- runif(max(1, N - 1), min = 400, max = 400 + span)  # always < 2N -> sparse
    w <- gen(precursor_mz = pz, mz_min = 400, mz_max = 400 + span,
             n_windows = N, min_width_da = 2, max_width_da = max_w, fz_offset = 0)
    expect_equal(nrow(w), N,
                 info = sprintf("N=%d span=%g max_w=%g -> %d rows",
                                N, span, max_w, nrow(w)))
    expect_true(all(w$window_width >= ABSOLUTE_MIN_WIDTH_DA - 1e-9))
    # contiguity holds in every combination
    expect_equal(w$mz_start[-1], w$mz_end[-nrow(w)])
  }
})

# ---------------------------------------------------------------------------
# Direct unit coverage of the extracted helper.
# ---------------------------------------------------------------------------
test_that("digitize_windows_to_n: wide cover yields N windows over max_width, never more", {
  w <- suppressMessages(digitize_windows_to_n(
    mz_min = 400, mz_max = 1300, n_windows = 10, raw_widths = rep(1, 10),
    min_width_da = 2, max_width_da = 80, fz_offset = 0))
  expect_equal(nrow(w), 10)                             # never ceiling(900/80)=12
  expect_true(all(w$window_width >= ABSOLUTE_MIN_WIDTH_DA - 1e-9))
  expect_true(max(w$window_width) > 80)                 # S2 soft ceiling exceeded
  expect_equal(w$mz_start[-1], w$mz_end[-nrow(w)])      # contiguous
})

test_that("digitize_windows_to_n: narrow cover edge-expands to N", {
  w <- suppressMessages(digitize_windows_to_n(
    mz_min = 400, mz_max = 405, n_windows = 8, raw_widths = rep(1, 8),
    min_width_da = 2, max_width_da = 50, fz_offset = 0))
  expect_equal(nrow(w), 8)
  expect_true(min(w$mz_start) <= 400 && max(w$mz_end) >= 405)
  expect_true(all(w$window_width >= ABSOLUTE_MIN_WIDTH_DA - 1e-9))
})

test_that("digitize_windows_to_n: mismatched raw_widths length falls back to uniform", {
  # Degenerate shape length != N must still produce exactly N valid windows.
  w <- suppressMessages(digitize_windows_to_n(
    mz_min = 400, mz_max = 600, n_windows = 10, raw_widths = c(3, 1, 2),
    min_width_da = 5, max_width_da = 50, fz_offset = 0))
  expect_equal(nrow(w), 10)
  expect_equal(sum(w$window_width), 200, tolerance = 1e-6)
  expect_true(all(w$window_width == 20))                # uniform fallback
})

cat("✅ test-h6-uniform-n-degenerate.R loaded - 8 tests defined\n")
