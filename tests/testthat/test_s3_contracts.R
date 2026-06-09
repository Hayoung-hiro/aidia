# test_s3_contracts.R - S3 Object Contract Tests
#
# Verifies that producer (optimization_planning.R) and consumers
# (plot_dppp.R, plot_satisfaction.R, export_plots.R) agree on the
# OptimizationPlan field schema. Catches silent breakage when fields
# are added/renamed in the producer but not updated in consumers.

# =============================================================================
# OptimizationPlan: field existence contract
# =============================================================================

test_that("OptimizationPlan validator catches missing diagnosis fields", {
  # Minimal valid skeleton — should pass
  plan <- structure(list(
    window_count_per_bin = 50,
    required_cycle_time_sec = 1.5,
    actual_cycle_time_sec = 1.5,
    diagnosis = list(
      current_cycle_time_sec = 3.0,
      current_ct_is_estimated = FALSE,
      current_satisfaction_ratio = 0.5,
      current_dppp_mean = 5.0,
      current_dppp_median = 4.8,
      current_dppp_sd = 1.2,
      n_satisfied = 100,
      n_total = 200
    ),
    feasibility = list(
      is_feasible = TRUE,
      cycle_time_ok = TRUE,
      scan_rate_ok = TRUE,
      window_range_ok = TRUE
    ),
    instrument = list(
      preset = "exploris",
      name = "Exploris 480",
      cycle_mode = "sequential",
      ms1_time_sec = 0.05,
      ms2_time_sec = 0.05
    ),
    scan_time = list(t_scan_ms = 50),
    parameters = list(
      target_dppp = 7.0,
      target_satisfaction = 0.85
    )
  ), class = c("OptimizationPlan", "list"))

  expect_silent(validate_OptimizationPlan(plan))
})

test_that("OptimizationPlan validator rejects missing current_ct_is_estimated", {
  plan <- structure(list(
    window_count_per_bin = 50,
    required_cycle_time_sec = 1.5,
    actual_cycle_time_sec = 1.5,
    diagnosis = list(
      current_cycle_time_sec = 3.0,
      # current_ct_is_estimated intentionally omitted
      current_satisfaction_ratio = 0.5,
      current_dppp_mean = 5.0,
      current_dppp_median = 4.8,
      current_dppp_sd = 1.2,
      n_satisfied = 100,
      n_total = 200
    ),
    feasibility = list(is_feasible = TRUE, cycle_time_ok = TRUE,
                       scan_rate_ok = TRUE, window_range_ok = TRUE),
    instrument = list(preset = "exploris", name = "Exploris 480",
                      cycle_mode = "sequential"),
    scan_time = list(t_scan_ms = 50),
    parameters = list(target_dppp = 7.0, target_satisfaction = 0.85)
  ), class = c("OptimizationPlan", "list"))

  expect_error(validate_OptimizationPlan(plan), "current_ct_is_estimated")
})

test_that("OptimizationPlan validator rejects missing feasibility sub-fields", {
  plan <- structure(list(
    window_count_per_bin = 50,
    required_cycle_time_sec = 1.5,
    actual_cycle_time_sec = 1.5,
    diagnosis = list(
      current_cycle_time_sec = 3.0, current_ct_is_estimated = TRUE,
      current_satisfaction_ratio = 0.5, current_dppp_mean = 5.0,
      current_dppp_median = 4.8, current_dppp_sd = 1.2,
      n_satisfied = 100, n_total = 200
    ),
    feasibility = list(is_feasible = TRUE),  # missing sub-checks
    instrument = list(preset = "exploris", name = "Exploris 480",
                      cycle_mode = "sequential"),
    scan_time = list(t_scan_ms = 50),
    parameters = list(target_dppp = 7.0, target_satisfaction = 0.85)
  ), class = c("OptimizationPlan", "list"))

  expect_error(validate_OptimizationPlan(plan), "cycle_time_ok")
})

test_that("OptimizationPlan validator rejects missing instrument fields", {
  plan <- structure(list(
    window_count_per_bin = 50,
    required_cycle_time_sec = 1.5,
    actual_cycle_time_sec = 1.5,
    diagnosis = list(
      current_cycle_time_sec = 3.0, current_ct_is_estimated = FALSE,
      current_satisfaction_ratio = 0.5, current_dppp_mean = 5.0,
      current_dppp_median = 4.8, current_dppp_sd = 1.2,
      n_satisfied = 100, n_total = 200
    ),
    feasibility = list(is_feasible = TRUE, cycle_time_ok = TRUE,
                       scan_rate_ok = TRUE, window_range_ok = TRUE),
    instrument = list(preset = "exploris"),  # missing name, cycle_mode
    scan_time = list(t_scan_ms = 50),
    parameters = list(target_dppp = 7.0, target_satisfaction = 0.85)
  ), class = c("OptimizationPlan", "list"))

  expect_error(validate_OptimizationPlan(plan), "name")
})

# =============================================================================
# current_ct_is_estimated: producer-consumer contract
# =============================================================================

test_that("plan_optimization sets current_ct_is_estimated = TRUE when CT is NULL", {
  skip_if_not(file.exists("data/30min_report.parquet"),
              "Test data not available")

  v <- create_validated_dataset("data/30min_report.parquet")
  plan <- plan_optimization(v, instrument_preset = "astral", target_dppp = 7.0)

  expect_true(plan$diagnosis$current_ct_is_estimated)
})

test_that("plan_optimization sets current_ct_is_estimated = FALSE when CT is provided", {
  skip_if_not(file.exists("data/30min_report.parquet"),
              "Test data not available")

  v <- create_validated_dataset("data/30min_report.parquet")
  plan <- plan_optimization(v, instrument_preset = "astral", target_dppp = 7.0,
                            current_cycle_time = 2.5)

  expect_false(plan$diagnosis$current_ct_is_estimated)
  expect_equal(plan$diagnosis$current_cycle_time_sec, 2.5)
})

# =============================================================================
# boundary_ci: validator contract
# =============================================================================

make_valid_boundary_ci <- function() {
  structure(list(
    ci_data = data.frame(
      rt_segment_id = 1:2,
      mz_min_lower = c(400, 410), mz_min_upper = c(405, 415),
      mz_max_lower = c(900, 910), mz_max_upper = c(905, 915)
    ),
    boot_matrix_min = matrix(0, nrow = 2, ncol = 3),
    boot_matrix_max = matrix(0, nrow = 2, ncol = 3),
    observed = data.frame(mz_min = c(402, 412), mz_max = c(902, 912)),
    params = list(strategy = "greedy", n_boot = 3, ci_level = 0.95)
  ), class = c("boundary_ci", "list"))
}

test_that("validate_boundary_ci accepts a well-formed object", {
  expect_silent(validate_boundary_ci(make_valid_boundary_ci()))
})

test_that("validate_boundary_ci rejects a non-boundary_ci object", {
  expect_error(validate_boundary_ci(list(a = 1)), "boundary_ci")
})

test_that("validate_boundary_ci rejects a missing top-level field", {
  obj <- make_valid_boundary_ci()
  obj$params <- NULL
  expect_error(validate_boundary_ci(obj), "params")
})

test_that("validate_boundary_ci rejects missing params sub-fields", {
  obj <- make_valid_boundary_ci()
  obj$params$strategy <- NULL
  expect_error(validate_boundary_ci(obj), "strategy")
})

test_that("validate_boundary_ci rejects a non-data-frame ci_data", {
  obj <- make_valid_boundary_ci()
  obj$ci_data <- list(1, 2)
  expect_error(validate_boundary_ci(obj), "data frame")
})

# =============================================================================
# cycle_time constants: relocation preserves values (no numeric drift)
# =============================================================================

test_that("cycle_time constants retain expected values after relocation", {
  expect_equal(length(ORBITRAP_TRANSIENT_TIME_MS), 8)
  expect_equal(unname(ORBITRAP_TRANSIENT_TIME_MS["30000"]), 64)
  expect_equal(unname(ORBITRAP_TRANSIENT_TIME_MS["240000"]), 512)
  expect_equal(unname(ORBITRAP_TRANSIENT_TIME_MS["480000"]), 1024)
  expect_equal(ASTRAL_FIXED_RESOLUTION, 80000)
  expect_equal(ASTRAL_DETECTION_TIME_MS, 2.5)
  expect_equal(ASTRAL_MIN_CYCLE_TIME_MS, 5.0)
  expect_equal(ORBITRAP_240K_TRANSIENT_MS, 512)
  expect_equal(DEFAULT_MS1_OVERHEAD_MS, 10.0)
  expect_equal(DEFAULT_OVERHEAD_FACTOR, 0.20)
  expect_equal(MINIMUM_OVERHEAD_MS, 5.0)
})

# =============================================================================
# make_mz_range_row: shared result-row schema
# =============================================================================

test_that("make_mz_range_row produces the standard 8-column schema", {
  rt_stats <- data.frame(rt_start = c(0, 5), rt_end = c(5, 10))
  row <- make_mz_range_row(2, rt_stats, 400, 410,
                           n_covered = 7, coverage_ratio = 0.7)
  expect_equal(names(row), c("rt_segment_id", "rt_start", "rt_end", "mz_min",
                             "mz_max", "mz_width", "n_precursors_covered",
                             "coverage_ratio"))
  expect_equal(row$rt_segment_id, 2)
  expect_equal(row$rt_start, 5)
  expect_equal(row$mz_width, 10)
  expect_false("kde_peak_mz" %in% names(row))
})

test_that("make_mz_range_row appends kde_peak_mz only when supplied", {
  rt_stats <- data.frame(rt_start = c(0, 5), rt_end = c(5, 10))
  row_kde <- make_mz_range_row(1, rt_stats, 400, 410, n_covered = 7,
                               coverage_ratio = 0.7, kde_peak_mz = 405)
  expect_true("kde_peak_mz" %in% names(row_kde))
  expect_equal(row_kde$kde_peak_mz, 405)
})
