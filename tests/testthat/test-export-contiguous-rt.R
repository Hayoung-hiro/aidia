# test-export-contiguous-rt.R
#
# Contiguous RT-schedule export (spec 2026-06-12):
# Adjacent RT segments always tile contiguously (interior boundaries = midpoints,
# rounded once -> zero inter-segment gap/overlap) and the export emits the native
# `t start (min)` / `t stop (min)` format.
#
# The leading/trailing void fill is a TOGGLE (`fill_void`, default FALSE):
#   - fill_void = FALSE (default): first/last segment keep their measured
#     rt_start/rt_end; the void is NOT filled. Interior contiguity still holds.
#   - fill_void = TRUE: schedule edges extend to [acquisition_start, acquisition_end].

# --- fixtures -----------------------------------------------------------------

# 3 RT segments, 2 m/z windows each.
# seg1 rt 10-18, seg2 rt 20-28, seg3 rt 30-40.
# midpoints: (18+20)/2 = 19, (28+30)/2 = 29.
make_win_3seg <- function() {
  data.frame(
    rt_segment_id = rep(1:3, each = 2),
    mz_start  = rep(c(400, 450), 3),
    mz_end    = rep(c(450, 500), 3),
    mz_center = rep(c(425, 475), 3),
    window_width = 50,
    rt_start = rep(c(10, 20, 30), each = 2),
    rt_end   = rep(c(18, 28, 40), each = 2)
  )
}

# --- helper: boundary array ---------------------------------------------------

test_that(".compute_contiguous_rt_schedule fills void via midpoints + acquisition edges", {
  win <- make_win_3seg()
  sched <- .compute_contiguous_rt_schedule(
    win, acquisition_start_min = 0, acquisition_end_min = 50, fill_void = TRUE
  )

  # B = [start, mid12, mid23, end]
  expect_equal(sched$breaks, c(0, 19, 29, 50))
  expect_true(all(diff(sched$breaks) > 0))      # strictly increasing

  # per-window t_start / t_stop, aligned to input row order
  expect_equal(sched$t_start, rep(c(0, 19, 29), each = 2))
  expect_equal(sched$t_stop,  rep(c(19, 29, 50), each = 2))
})

test_that(".compute_contiguous_rt_schedule with fill_void = FALSE keeps measured edges", {
  win <- make_win_3seg()
  sched <- .compute_contiguous_rt_schedule(win, fill_void = FALSE)

  # edges = first rt_start (10) and last rt_end (40); interiors still midpoints
  expect_equal(sched$breaks, c(10, 19, 29, 40))
  expect_equal(sched$t_start, rep(c(10, 19, 29), each = 2))
  expect_equal(sched$t_stop,  rep(c(19, 29, 40), each = 2))
})

# --- ValidatedData stub for export-level tests --------------------------------

make_vd_stub <- function(n = 200) {
  prec <- data.frame(
    Precursor.Mz = seq(400, 500, length.out = n),
    RT.Apex      = seq(10, 40, length.out = n)
  )
  structure(list(data = prec), class = "ValidatedData")
}

make_ow_3seg <- function() {
  structure(list(windows = make_win_3seg(), parameters = list()),
            class = "OptimizedWindows")
}

# --- export format (always) ---------------------------------------------------

test_that("export sets Adduct to '(no adduct)'", {
  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")
  export_windows_to_csv(ow, out, vd)
  df <- utils::read.csv(out, check.names = FALSE)
  expect_true(all(df$Adduct == "(no adduct)"))
})

test_that("CSV header matches mass_list_example.csv exactly", {
  example_path <- testthat::test_path("..", "..", "mass_list_example.csv")
  skip_if_not(file.exists(example_path), "mass_list_example.csv not present")
  expected_header <- strsplit(readLines(example_path, n = 1), ",")[[1]]

  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")
  export_windows_to_csv(ow, out, vd)
  actual_header <- strsplit(readLines(out, n = 1), ",")[[1]]

  expect_equal(actual_header, expected_header)
})

# --- default behavior: fill_void = FALSE --------------------------------------

test_that("export default (fill_void = FALSE) keeps measured edges, interior still contiguous", {
  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")

  export_windows_to_csv(ow, out, vd)   # default: fill_void = FALSE
  df <- utils::read.csv(out, check.names = FALSE)

  ts <- df[["t start (min)"]]; te <- df[["t stop (min)"]]
  # first start = measured rt_start (10, NOT 0); last stop = measured rt_end (40, NOT 50)
  expect_equal(unique(ts), c(10, 19, 29))
  expect_equal(unique(te), c(19, 29, 40))
  # shared interior boundaries -> no gap/overlap between adjacent segments
  expect_equal(unique(ts)[-1], head(unique(te), -1))
})

test_that("export default ignores acquisition bounds (no NULL-end warning, no end<last error)", {
  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")

  expect_no_warning(export_windows_to_csv(ow, out, vd))                         # no NULL-end warning
  expect_no_error(export_windows_to_csv(ow, out, vd, acquisition_end_min = 35)) # 35 < 40 ignored when off
})

# --- fill_void = TRUE: tile [acquisition_start, acquisition_end] ---------------

test_that("fill_void = TRUE writes t start/t stop columns that tile to acquisition bounds", {
  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")

  export_windows_to_csv(ow, out, vd, fill_void = TRUE, acquisition_end_min = 50)
  df <- utils::read.csv(out, check.names = FALSE)

  expect_equal(
    colnames(df),
    c("Compound", "Formula", "Adduct", "m/z", "z",
      "t start (min)", "t stop (min)", "Isolation Window (m/z)")
  )

  ts <- df[["t start (min)"]]; te <- df[["t stop (min)"]]
  expect_equal(unique(ts), c(0, 19, 29))
  expect_equal(unique(te), c(19, 29, 50))
  expect_equal(min(ts), 0)        # first start == acquisition start
  expect_equal(max(te), 50)       # last stop  == acquisition end
  expect_true(all(ts == round(ts, 2)))   # 2-decimal fidelity
  expect_true(all(te == round(te, 2)))
})

# --- edge cases (spec section 5) ----------------------------------------------

test_that("fill_void = TRUE with NULL acquisition_end_min warns and falls back to last rt_end", {
  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")
  expect_warning(
    export_windows_to_csv(ow, out, vd, fill_void = TRUE),   # acquisition_end_min = NULL
    "acquisition_end_min not supplied"
  )
  df <- utils::read.csv(out, check.names = FALSE)
  expect_equal(max(df[["t stop (min)"]]), 40)   # last segment rt_end
})

test_that("fill_void = TRUE with acquisition_end_min before last segment end is an error", {
  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")
  expect_error(
    export_windows_to_csv(ow, out, vd, fill_void = TRUE, acquisition_end_min = 35),
    "before the last segment end"
  )
})

test_that("empty interior RT band is absorbed (no coverage hole)", {
  # Only seg1 (10-18) and seg3 (30-40); the 18-30 band has no precursors/segment.
  win <- data.frame(
    rt_segment_id = rep(c(1L, 3L), each = 2),
    mz_start  = rep(c(400, 450), 2),
    mz_end    = rep(c(450, 500), 2),
    mz_center = rep(c(425, 475), 2),
    window_width = 50,
    rt_start = rep(c(10, 30), each = 2),
    rt_end   = rep(c(18, 40), each = 2)
  )
  ow <- structure(list(windows = win, parameters = list()),
                  class = "OptimizedWindows")
  out <- tempfile(fileext = ".csv")
  export_windows_to_csv(ow, out, make_vd_stub(), fill_void = TRUE, acquisition_end_min = 50)
  df <- utils::read.csv(out, check.names = FALSE)

  # midpoint of 18 and 30 is 24; schedule must stay contiguous across the gap
  expect_equal(unique(df[["t start (min)"]]), c(0, 24))
  expect_equal(unique(df[["t stop (min)"]]),  c(24, 50))
})

test_that("single segment (k==1) with fill_void = TRUE spans the whole run", {
  win <- data.frame(
    rt_segment_id = 1L,
    mz_start = c(400, 450), mz_end = c(450, 500),
    mz_center = c(425, 475), window_width = 50,
    rt_start = 10, rt_end = 40
  )
  ow <- structure(list(windows = win, parameters = list()),
                  class = "OptimizedWindows")
  out <- tempfile(fileext = ".csv")
  export_windows_to_csv(ow, out, make_vd_stub(), fill_void = TRUE, acquisition_end_min = 50)
  df <- utils::read.csv(out, check.names = FALSE)
  expect_true(all(df[["t start (min)"]] == 0))
  expect_true(all(df[["t stop (min)"]]  == 50))
})

test_that("staggered cycles collapse to one RT segment", {
  win <- generate_staggered_windows_internal(
    mz_min = 400, mz_max = 500, n_windows = 5,
    min_width_da = 4, max_width_da = 80, rt_bin_index = 1, fz_offset = 0.25
  )
  win$rt_segment_id <- 1L
  win$rt_start <- 10
  win$rt_end   <- 40
  ow <- structure(list(windows = win, parameters = list(fz_offset = 0.25)),
                  class = "OptimizedWindows")
  out <- tempfile(fileext = ".csv")
  export_windows_to_csv(ow, out, make_vd_stub(), fill_void = TRUE, acquisition_end_min = 50)
  df <- utils::read.csv(out, check.names = FALSE)
  # both cycles share (rt_start, rt_end) -> distinct() yields one segment
  expect_equal(length(unique(df[["t start (min)"]])), 1L)
  expect_equal(length(unique(df[["t stop (min)"]])),  1L)
})

# --- batch exporters forward fill_void / acquisition bounds -------------------

test_that("export_method_files forwards fill_void + acquisition_end_min", {
  wl  <- list(greedy = make_ow_3seg())
  out <- tempfile()

  files <- export_method_files(
    wl, out, make_vd_stub(),
    strategies = "greedy",
    fill_void = TRUE, acquisition_end_min = 50
  )
  df <- utils::read.csv(files[["greedy"]], check.names = FALSE)

  # void-fill reached the batch path: last t stop == acquisition end (50),
  # first t start == acquisition start (0) -- not the measured 40 / 10.
  expect_equal(max(df[["t stop (min)"]]),  50)
  expect_equal(min(df[["t start (min)"]]), 0)
})

test_that("export_method_files default keeps measured edges (fill_void off)", {
  wl  <- list(greedy = make_ow_3seg())
  out <- tempfile()

  files <- export_method_files(wl, out, make_vd_stub(), strategies = "greedy")
  df <- utils::read.csv(files[["greedy"]], check.names = FALSE)

  expect_equal(min(df[["t start (min)"]]), 10)   # measured rt_start, not 0
  expect_equal(max(df[["t stop (min)"]]),  40)   # measured rt_end, not filled
})

test_that("export_batch_comparison forwards fill_void + acquisition_end_min", {
  wl  <- list(greedy = make_ow_3seg())
  out <- tempfile()

  export_batch_comparison(
    wl, make_vd_stub(), out,
    formats = "thermo", include_comparison = FALSE,
    fill_void = TRUE, acquisition_end_min = 50
  )

  thermo_files <- list.files(file.path(out, "thermo"), full.names = TRUE)
  expect_length(thermo_files, 1)
  df <- utils::read.csv(thermo_files[[1]], check.names = FALSE)
  expect_equal(max(df[["t stop (min)"]]),  50)
  expect_equal(min(df[["t start (min)"]]), 0)
})
