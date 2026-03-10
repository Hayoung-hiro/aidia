# test-duty-cycle-sync.R
# Unit tests for duty cycle sync functions

test_that("perfect sync gives ~100% duty cycle", {
  # MS1 = 256 ms, MS2 = 5 ms/scan, 51 windows = 255 ms total
  sync <- calculate_duty_cycle_sync(
    ms1_time_ms = 256,
    ms2_scan_time_ms = 5.0,
    n_windows = 51
  )

  expect_gt(sync$duty_cycle_pct, 99)
  expect_equal(sync$sync_status, "synced")
  expect_lte(sync$ms1_idle_ms, 1)
  expect_lte(sync$ms2_idle_ms, 1)
})

test_that("MS2 idle when fewer windows than sync-optimal", {
  # MS1 = 256 ms, MS2 = 5 ms/scan, 40 windows = 200 ms → MS2 idle 56 ms

  sync <- calculate_duty_cycle_sync(
    ms1_time_ms = 256,
    ms2_scan_time_ms = 5.0,
    n_windows = 40
  )

  expect_equal(sync$ms2_idle_ms, 56)
  expect_equal(sync$ms1_idle_ms, 0)
  expect_equal(sync$sync_status, "ms2_idle")
  expect_lt(sync$duty_cycle_pct, 100)
})

test_that("MS1 idle when more windows than sync-optimal", {
  # MS1 = 256 ms, MS2 = 5 ms/scan, 60 windows = 300 ms → MS1 idle 44 ms
  sync <- calculate_duty_cycle_sync(
    ms1_time_ms = 256,
    ms2_scan_time_ms = 5.0,
    n_windows = 60
  )

  expect_equal(sync$ms1_idle_ms, 44)
  expect_equal(sync$ms2_idle_ms, 0)
  expect_equal(sync$sync_status, "ms1_idle")
})

test_that("sync-optimal window count is correct", {
  # floor(256 / 5.0) = 51
  n <- calculate_sync_optimal_windows(ms1_time_ms = 256, ms2_scan_time_ms = 5.0)
  expect_equal(n, 51L)

  # floor(128 / 5.0) = 25
  n2 <- calculate_sync_optimal_windows(ms1_time_ms = 128, ms2_scan_time_ms = 5.0)
  expect_equal(n2, 25L)
})

test_that("zero ms2_scan_time returns 1", {
  n <- calculate_sync_optimal_windows(ms1_time_ms = 256, ms2_scan_time_ms = 0)
  expect_equal(n, 1L)
})

test_that("cycle_time_ms is max of MS1 and total MS2", {
  # MS2 dominates: 60 x 5 = 300 > 256
  sync <- calculate_duty_cycle_sync(
    ms1_time_ms = 256,
    ms2_scan_time_ms = 5.0,
    n_windows = 60
  )
  expect_equal(sync$cycle_time_ms, 300)

  # MS1 dominates: 20 x 5 = 100 < 256
  sync2 <- calculate_duty_cycle_sync(
    ms1_time_ms = 256,
    ms2_scan_time_ms = 5.0,
    n_windows = 20
  )
  expect_equal(sync2$cycle_time_ms, 256)
})

test_that("instrument width recommendations have defaults", {
  # With explicit values
  config <- list(recommended_min_width_da = 5, recommended_max_width_da = 100)
  recs <- get_instrument_width_recommendations(config)
  expect_equal(recs$min_width_da, 5)
  expect_equal(recs$max_width_da, 100)

  # Without values (fallback)
  recs2 <- get_instrument_width_recommendations(list())
  expect_equal(recs2$min_width_da, 2)
  expect_equal(recs2$max_width_da, 80)
})
