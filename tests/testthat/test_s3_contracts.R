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
      cycle_mode = "sequential"
    ),
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
