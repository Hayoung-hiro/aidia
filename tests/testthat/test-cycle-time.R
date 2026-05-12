# test-cycle-time.R
#
# Unit tests at the external interface of R/cycle_time.R.
# Verifies that the exported entry points behave as documented after the
# v0.4.1 split from instrument_utils.R. Sync-related tests are in
# test-duty-cycle-sync.R; this file focuses on scan/cycle time math.


# ---------------------------------------------------------------------------
# get_transient_time()
# ---------------------------------------------------------------------------

test_that("get_transient_time returns exact match for known Orbitrap resolutions", {
  expect_equal(get_transient_time(30000, "orbitrap"), 64)
  expect_equal(get_transient_time(15000, "orbitrap"), 32)
  expect_equal(get_transient_time(120000, "orbitrap"), 256)
  expect_equal(get_transient_time(240000, "orbitrap"), 512)
})

test_that("get_transient_time interpolates non-standard Orbitrap resolution", {
  # 22500 sits between 15000 (32 ms) and 30000 (64 ms) -> ~46.5 ms in log-log
  res <- get_transient_time(22500, "orbitrap")
  expect_gt(res, 32)
  expect_lt(res, 64)
})

test_that("get_transient_time returns fixed Astral detection time", {
  expect_equal(get_transient_time(80000, "astral"), 2.5)
  # Astral ignores resolution argument (fixed detection time)
  expect_equal(get_transient_time(120000, "astral"), 2.5)
})

test_that("get_transient_time returns NA for TOF analyzer", {
  expect_true(is.na(get_transient_time(30000, "tof")))
})

test_that("get_transient_time warns and clamps for out-of-range resolution", {
  expect_warning(res_low <- get_transient_time(1000, "orbitrap"), "below minimum")
  expect_equal(res_low, 16)  # clamped to minimum

  expect_warning(res_high <- get_transient_time(1000000, "orbitrap"), "above maximum")
  expect_equal(res_high, 1024)  # clamped to maximum
})


# ---------------------------------------------------------------------------
# calculate_cycle_time_from_experiment()
# ---------------------------------------------------------------------------

test_that("sequential cycle time = MS1 + n * MS2", {
  # Exploris-like setup at 60K MS1 / 15K MS2, 40 windows
  config <- list(
    instrument = list(preset = "exploris"),
    ms1 = list(resolution = 60000, max_injection_time_ms = 50),
    ms2 = list(resolution = 15000, max_injection_time_ms = "auto"),
    dia_windows = list(window_count = 40)
  )

  result <- calculate_cycle_time_from_experiment(config, verbose = FALSE)

  expect_true(is.list(result))
  expect_named(result, c("cycle_time_sec", "cycle_time_ms", "ms1", "ms2",
                         "window_count", "ms2_total_time_ms", "instrument",
                         "theoretical_ms2_rate_hz", "effective_windows_per_sec",
                         "current_cycle_time"))

  # Sequential: cycle = MS1_scan_time + n * MS2_scan_time
  expected_cycle <- result$ms1$scan_time_ms + 40 * result$ms2$scan_time_ms
  expect_equal(result$cycle_time_ms, expected_cycle, tolerance = 1e-6)
  expect_equal(result$cycle_time_sec, expected_cycle / 1000, tolerance = 1e-6)
})

test_that("parallel cycle time = max(MS1, n * MS2)", {
  # Astral at 240K MS1 / 80K MS2, 102 windows (near sync-optimal)
  config <- list(
    instrument = list(preset = "astral"),
    ms1 = list(resolution = 240000, max_injection_time_ms = "auto"),
    ms2 = list(resolution = 80000, max_injection_time_ms = 3.0),
    dia_windows = list(window_count = 102)
  )

  result <- calculate_cycle_time_from_experiment(config, verbose = FALSE)

  expect_equal(result$instrument$cycle_calculation, "parallel")

  # Parallel: cycle = max(MS1_scan_time, total_MS2_time)
  expected_cycle <- max(result$ms1$scan_time_ms, result$ms2_total_time_ms)
  expect_equal(result$cycle_time_ms, expected_cycle, tolerance = 1e-6)
})

test_that("auto MS2 IT resolves to T_transient on Orbitrap", {
  config <- list(
    instrument = list(preset = "exploris"),
    ms1 = list(resolution = 60000, max_injection_time_ms = 50),
    ms2 = list(resolution = 30000, max_injection_time_ms = "auto"),
    dia_windows = list(window_count = 30)
  )

  result <- calculate_cycle_time_from_experiment(config, verbose = FALSE)

  # 30K resolution -> T_transient = 64 ms -> auto IT = 64 ms (sweet spot)
  expect_equal(result$ms2$injection_time_ms, 64)
  expect_equal(result$ms2$limiting_factor, "balanced")
  expect_equal(result$ms2$efficiency_mode, "auto")
})

test_that("returns instrument and window_count fields verbatim", {
  config <- list(
    instrument = list(preset = "qexactive_hfx"),
    ms1 = list(resolution = 60000, max_injection_time_ms = 50),
    ms2 = list(resolution = 15000, max_injection_time_ms = 22),
    dia_windows = list(window_count = 25)
  )

  result <- calculate_cycle_time_from_experiment(config, verbose = FALSE)

  expect_equal(result$window_count, 25)
  expect_equal(result$instrument$preset, "qexactive_hfx")
})
