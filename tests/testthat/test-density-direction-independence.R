# test-density-direction-independence.R
#
# Property guard for the de-biased density generator. The Phase 2 boundary
# adjustment and Phase 3 width smoother in generate_variable_windows_internal()
# were rewritten as Jacobi sweeps with symmetric stencils (freeze the sweep's
# read state, commit all updates simultaneously). The shape they emit is
# therefore a pure function of frozen neighbor state, which makes it:
#   - invariant to the ORDER precursors arrive in (they are sorted internally
#     and only counted, so a permuted input must give an identical result), and
#   - symmetric under MIRRORING the input about the bin center (reflecting the
#     precursors must reflect the window layout, not reshape it).
# A left/right-biased generator (the previous Gauss-Seidel sweep + left-only
# smoother) fails the mirror property; this test locks the fix in place.
#
# fz_offset = 0 keeps window widths integer-valued so the multiset comparisons
# are exact. The cover span (mz_min, mz_max) is passed identically to both the
# forward and mirrored calls, so edge-expansion and integer digitization are
# byte-identical between them; only the density SHAPE differs, and that shape is
# mirror-symmetric by construction.

test_that("density generator is invariant to precursor input order", {
  set.seed(4242)
  fails <- character(0)
  for (i in 1:40) {
    N       <- sample(3:12, 1)
    mz_min  <- 400
    mz_max  <- mz_min + sample(300:800, 1)
    # Skewed (non-uniform) density so a directional bias would actually show.
    npr     <- sample((4 * N):(4 * N + 400), 1)
    pmz     <- c(
      rbeta(npr, 2, 5) * (mz_max - mz_min) + mz_min,
      runif(npr %/% 3, mz_min, mz_max)
    )
    min_w   <- 2; max_w <- 60

    a <- suppressWarnings(suppressMessages(generate_variable_windows_internal(
      pmz, mz_min, mz_max, N, min_w, max_w, fz_offset = 0)))
    b <- suppressWarnings(suppressMessages(generate_variable_windows_internal(
      sample(pmz), mz_min, mz_max, N, min_w, max_w, fz_offset = 0)))

    if (!isTRUE(all.equal(a$window_width, b$window_width))) {
      fails <- c(fails, sprintf("perm N=%d span=%d", N, mz_max - mz_min))
    }
  }
  expect_equal(length(fails), 0, info = paste(utils::head(fails, 5), collapse = " ; "))
})

test_that("density generator is symmetric under input mirroring", {
  set.seed(9191)
  multiset_fails <- character(0)
  for (i in 1:40) {
    N       <- sample(3:12, 1)
    mz_min  <- 400
    mz_max  <- mz_min + sample(300:800, 1)
    npr     <- sample((4 * N):(4 * N + 400), 1)
    # Deliberately asymmetric density: mass piled toward the low-m/z edge.
    pmz     <- rbeta(npr, 2, 6) * (mz_max - mz_min) + mz_min
    min_w   <- 2; max_w <- 60

    mirror  <- function(x) mz_min + mz_max - x

    a <- suppressWarnings(suppressMessages(generate_variable_windows_internal(
      pmz, mz_min, mz_max, N, min_w, max_w, fz_offset = 0)))
    b <- suppressWarnings(suppressMessages(generate_variable_windows_internal(
      mirror(pmz), mz_min, mz_max, N, min_w, max_w, fz_offset = 0)))

    # Mirror-invariant multiset: reflecting the input must not change WHICH
    # widths appear, only their order. A left/right-biased generator (the former
    # Gauss-Seidel sweep + left-only smoother) systematically widens one side, so
    # its mirrored multiset drifts; the symmetric Jacobi stencils keep it fixed.
    if (!isTRUE(all.equal(sort(a$window_width), sort(b$window_width)))) {
      multiset_fails <- c(multiset_fails,
                          sprintf("N=%d span=%d", N, mz_max - mz_min))
    }
    # NOTE: we do NOT assert the exact positional map a == rev(b). The symmetric
    # SHAPE is mirror-exact, but the shared (untouched) integer digitization tail
    # assigns each +/-1 Da largest-remainder leftover by a tie-break that is not
    # positionally reflection-symmetric (e.g. 131,131,131,131,130,131 mirrors to
    # 131,130,131,131,131,131 -- same multiset, leftover in a mirrored slot).
    # That non-determinism is a documented property of the digitization tail (see
    # test-width-semantics-split.R header), not of the direction-bias fix.
  }
  expect_equal(length(multiset_fails), 0,
               info = paste(utils::head(multiset_fails, 5), collapse = " ; "))
})
