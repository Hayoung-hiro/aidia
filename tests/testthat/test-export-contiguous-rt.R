# test-export-contiguous-rt.R
#
# Contiguous RT-schedule export (spec 2026-06-12):
# export must tile [acquisition_start, acquisition_end] with zero gap/overlap/void
# and emit the native `t start (min)` / `t stop (min)` format.

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

test_that(".compute_contiguous_rt_schedule tiles segments via midpoints", {
  win <- make_win_3seg()
  sched <- .compute_contiguous_rt_schedule(
    win, acquisition_start_min = 0, acquisition_end_min = 50
  )

  # B = [start, mid12, mid23, end]
  expect_equal(sched$breaks, c(0, 19, 29, 50))
  expect_true(all(diff(sched$breaks) > 0))      # strictly increasing

  # per-window t_start / t_stop, aligned to input row order
  expect_equal(sched$t_start, rep(c(0, 19, 29), each = 2))
  expect_equal(sched$t_stop,  rep(c(19, 29, 50), each = 2))
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

# --- export-level format + continuity -----------------------------------------

test_that("export writes t start/t stop columns that tile contiguously", {
  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")

  export_windows_to_csv(ow, out, vd, acquisition_end_min = 50)
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

test_that("export sets Adduct to '(no adduct)'", {
  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")
  export_windows_to_csv(ow, out, vd, acquisition_end_min = 50)
  df <- utils::read.csv(out, check.names = FALSE)
  expect_true(all(df$Adduct == "(no adduct)"))
})

test_that("CSV header matches mass_list_example.csv exactly", {
  example_path <- testthat::test_path("..", "..", "mass_list_example.csv")
  skip_if_not(file.exists(example_path), "mass_list_example.csv not present")
  expected_header <- strsplit(readLines(example_path, n = 1), ",")[[1]]

  ow <- make_ow_3seg(); vd <- make_vd_stub()
  out <- tempfile(fileext = ".csv")
  export_windows_to_csv(ow, out, vd, acquisition_end_min = 50)
  actual_header <- strsplit(readLines(out, n = 1), ",")[[1]]

  expect_equal(actual_header, expected_header)
})
