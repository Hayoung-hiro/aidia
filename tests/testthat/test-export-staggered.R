# test-export-staggered.R
#
# Regression: export_windows_to_csv() must not crash on staggered windows.
#
# Bug (v0.4.1): the Compound column was built with a bare
#   `if (is_staggered) ...` inside mutate(). Staggered windows carry an
#   `is_staggered` *column* (window_generation.R), which shadows the length-1
#   scalar inside the dplyr data mask, so if() received a vector and failed
#   with "the condition has length > 1". Non-staggered windows have no such
#   column, so only staggered export was affected.


make_staggered_windows <- function() {
  win <- generate_staggered_windows_internal(
    mz_min = 400, mz_max = 500, n_windows = 5,
    min_width_da = 4, max_width_da = 80, rt_bin_index = 1, fz_offset = 0.25
  )
  win$rt_segment_id <- 1L
  win$rt_start <- 0
  win$rt_end <- 30
  win
}

make_validated_stub <- function(n = 200) {
  prec <- data.frame(
    Precursor.Mz = seq(400, 500, length.out = n),
    RT.Apex = seq(0, 30, length.out = n)
  )
  structure(list(data = prec), class = "ValidatedData")
}


test_that("staggered windows carry an is_staggered column (precondition)", {
  win <- make_staggered_windows()
  expect_true("is_staggered" %in% colnames(win))
  expect_true("cycle" %in% colnames(win))
})

test_that("export_windows_to_csv does not crash on staggered windows", {
  win <- make_staggered_windows()
  ow <- structure(list(windows = win, parameters = list(fz_offset = 0.25)),
                  class = "OptimizedWindows")
  vd <- make_validated_stub()
  out <- tempfile(fileext = ".csv")

  expect_no_error(
    export_windows_to_csv(ow, out, vd)
  )

  df <- utils::read.csv(out, check.names = FALSE)
  # Compound should use the staggered C/RT/W naming, not row numbers
  expect_true(all(grepl("^C[0-9]+_RT[0-9]+_W[0-9]+$", df$Compound)))
  expect_equal(nrow(df), nrow(win))
})

test_that("z column defaults to 1 (Xcalibur drops z = 0 on import) and is configurable", {
  win <- make_staggered_windows()
  ow <- structure(list(windows = win, parameters = list(fz_offset = 0.25)),
                  class = "OptimizedWindows")
  vd <- make_validated_stub()

  out1 <- tempfile(fileext = ".csv")
  export_windows_to_csv(ow, out1, vd)
  expect_equal(unique(utils::read.csv(out1, check.names = FALSE)$z), 1)

  out0 <- tempfile(fileext = ".csv")
  export_windows_to_csv(ow, out0, vd, charge_state = 0L)
  expect_equal(unique(utils::read.csv(out0, check.names = FALSE)$z), 0)
})

test_that("staggered honors fz_offset = 0 (clean integer boundaries, like fixed/density)", {
  st0 <- generate_staggered_windows_internal(400, 500, 5, 4, 80, 1, fz_offset = 0)
  expect_true(all(st0$mz_start %% 1 == 0))
  expect_true(all(st0$mz_end %% 1 == 0))

  # fz_offset > 0 still shifts boundaries into the forbidden zone (decimals)
  st <- generate_staggered_windows_internal(400, 500, 5, 4, 80, 1, fz_offset = 0.25)
  expect_true(any(st$mz_start %% 1 != 0))
})

test_that("staggered preserves the 50% cycle offset with and without FZ", {
  half_offset <- function(w) {
    c1 <- sort(unique(c(w$mz_start[w$cycle == 1], w$mz_end[w$cycle == 1])))
    c2 <- sort(unique(c(w$mz_start[w$cycle == 2], w$mz_end[w$cycle == 2])))
    mean(c2[seq_len(4)] - c1[seq_len(4)])
  }
  st0 <- generate_staggered_windows_internal(400, 500, 5, 4, 80, 1, fz_offset = 0)
  st  <- generate_staggered_windows_internal(400, 500, 5, 4, 80, 1, fz_offset = 0.25)
  # nominal width = 20 -> half = 10; FZ applies a shared ~1.0005x warp to both cycles
  expect_equal(half_offset(st0), 10, tolerance = 0.05)
  expect_equal(half_offset(st),  10, tolerance = 0.05)
})

test_that("staggered mode ignores overlap (would break demultiplexing)", {
  rt_stats  <- data.frame(rt_segment_id = 1L, rt_start = 0, rt_end = 30)
  mz_ranges <- data.frame(rt_segment_id = 1L, mz_min = 400, mz_max = 500)
  prec      <- data.frame(Precursor.Mz = seq(400, 500, length.out = 200), RT.Apex = 15)

  expect_warning(
    w <- generate_windows_internal(
      prec, rt_stats, mz_ranges,
      n_windows_per_bin = 5, window_mode = "staggered",
      min_width_da = 4, max_width_da = 80,
      overlap_percentage = 20, fz_offset = 0.25
    ),
    "ignored in staggered mode"
  )
  # Boundaries stay contiguous within each cycle (overlap not applied)
  expect_true("cycle" %in% colnames(w))
})

test_that("non-staggered export still numbers compounds sequentially", {
  win <- data.frame(
    rt_segment_id = 1L,
    mz_start = c(400, 410, 420),
    mz_end   = c(410, 420, 430),
    mz_center = c(405, 415, 425),
    window_width = 10,
    rt_start = 0, rt_end = 30
  )
  ow <- structure(list(windows = win, parameters = list()),
                  class = "OptimizedWindows")
  vd <- make_validated_stub()
  out <- tempfile(fileext = ".csv")

  expect_no_error(export_windows_to_csv(ow, out, vd))
  df <- utils::read.csv(out, check.names = FALSE)
  expect_equal(as.character(df$Compound), as.character(seq_len(nrow(win))))
})
