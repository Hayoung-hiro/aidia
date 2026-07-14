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

test_that("Jacobi sweep does not over-squeeze a dense narrow window (monotonicity guard)", {
  # Reproduction of the crossing artifact the Phase 2 monotonicity guard fixes.
  #
  # Each boundary's min-width check in Phase 2 reads only the FROZEN neighbor
  # positions, so two adjacent boundaries can both move inward toward a dense,
  # narrow cluster in the same Jacobi sweep and collapse the gap between them to
  # (or below) zero -- a crossing the former in-place Gauss-Seidel sweep could
  # not produce. The zero-width intermediate is floored by the Phase 3 smoother,
  # which pushes a neighbor's width PAST the (soft) max_width_da ceiling even
  # though the bin has no width pressure (span 134 << N * max_width = 200). The
  # guard reverts any sweep that crosses, keeping the last valid layout.
  #
  # This exact scenario yields a window of width 26 > max_width_da = 25 WITHOUT
  # the guard, and <= 25 WITH it. Because the bin is not width-constrained, no
  # window needs to exceed the ceiling, so a spurious >max_width window is a real
  # artifact rather than the documented "max_width is soft for genuinely wide
  # bins" case.
  set.seed(3)
  mz_min <- 0; mz_max <- 134; N <- 8; min_w <- 1; max_w <- 25
  precursor_mz <- c(
    rnorm(sample(200:400, 1), runif(1, 55, 80), runif(1, 0.4, 1.5)),  # dense spike
    seq(2, mz_max - 2, length.out = 18)                               # sparse background
  )
  precursor_mz <- precursor_mz[precursor_mz > mz_min & precursor_mz < mz_max]

  w <- suppressWarnings(suppressMessages(generate_variable_windows_internal(
    precursor_mz, mz_min, mz_max, N, min_w, max_w, fz_offset = 0)))

  # Guard-specific: an unconstrained bin must not exceed the soft width ceiling.
  expect_true(all(w$window_width <= max_w + 1e-9),
              info = sprintf("widths: %s", paste(round(w$window_width, 2), collapse = ",")))
  # Invariants still hold.
  expect_equal(nrow(w), N)
  expect_true(all(w$window_width >= min_w - 1e-9))
  expect_equal(w$mz_start[-1], head(w$mz_end, -1))                    # contiguous
  # Direction-independence is preserved through the guard (symmetric revert).
  wm <- suppressWarnings(suppressMessages(generate_variable_windows_internal(
    mz_max - precursor_mz, mz_min, mz_max, N, min_w, max_w, fz_offset = 0)))
  expect_equal(sort(w$window_width), sort(wm$window_width))
})
