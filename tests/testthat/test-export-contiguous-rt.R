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
