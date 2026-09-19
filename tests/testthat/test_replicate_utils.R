# test_replicate_utils.R - Unit Tests for Replicate Handling Utilities
# DIA Window Optimizer v2.0 - TDD Approach
#
# Following Kent Beck's TDD: RED → GREEN → REFACTOR

# ============================================================================
# Task 2.1.1: identify_replicate_groups() - RED Phase
# ============================================================================

test_that("identify_replicate_groups counts replicates correctly", {
  # Arrange
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P1", "P2", "P2", "P3"),
    Run = c("R1", "R2", "R3", "R1", "R2", "R1"),
    RT.Start = c(10.5, 10.6, 10.4, 20.3, 20.5, 30.2)
  )

  # Act
  result <- identify_replicate_groups(test_data)

  # Assert
  expect_equal(result$n_precursors_unique, 3)
  expect_equal(as.numeric(result$replicate_counts["P1"]), 3)
  expect_equal(as.numeric(result$replicate_counts["P2"]), 2)
  expect_equal(as.numeric(result$replicate_counts["P3"]), 1)
  expect_equal(result$n_singleton, 1)  # P3
  expect_equal(result$n_replicated, 2)  # P1, P2
})

test_that("identify_replicate_groups fails with missing Precursor.Id", {
  # Arrange
  test_data <- tibble(
    Run = c("R1", "R2"),
    RT.Start = c(10.0, 10.1)
  )

  # Act & Assert
  expect_error(
    identify_replicate_groups(test_data),
    "Missing column: Precursor.Id"
  )
})

test_that("identify_replicate_groups fails with missing Run column", {
  # Arrange
  test_data <- tibble(
    Precursor.Id = c("P1", "P1"),
    RT.Start = c(10.0, 10.1)
  )

  # Act & Assert
  expect_error(
    identify_replicate_groups(test_data),
    "Missing column: Run"
  )
})

# ============================================================================
# Task 2.1.2: CV Calculation Functions - RED Phase (CORRECTED)
# ============================================================================

test_that("base_cv calculates correctly for linear-scale data (RT, FWHM)", {
  # Arrange
  # Known values: c(10.0, 10.2, 10.1)
  # mean = 10.1, sd ≈ 0.1
  # Base CV = (0.1 / 10.1) * 100 ≈ 0.99%
  values <- c(10.0, 10.2, 10.1)

  # Act
  result <- base_cv(values)

  # Assert
  expect_type(result, "double")
  expect_gt(result, 0)
  expect_lt(result, 2)  # Should be ~1% for this data
})

test_that("base_cv returns NA for n<2", {
  # Act & Assert
  expect_true(is.na(base_cv(c(10.0))))
  expect_true(is.na(base_cv(numeric(0))))
})

test_that("base_cv handles NA values correctly", {
  # Arrange
  values_with_na <- c(10.0, NA, 10.2, 10.1)

  # Act
  result <- base_cv(values_with_na)

  # Assert
  expect_type(result, "double")
  expect_false(is.na(result))  # Should remove NA and calculate
  expect_gt(result, 0)
})

test_that("geometric_cv calculates correctly for log-normal data (intensity)", {
  # Arrange
  # Known values: log(10.0), log(10.2), log(10.1)
  # sd(log(x)) ≈ 0.00995
  # Geometric CV ≈ sqrt(exp(0.00995^2) - 1) * 100 ≈ 1.0%
  values <- c(10.0, 10.2, 10.1)

  # Act
  result <- geometric_cv(values)

  # Assert
  expect_type(result, "double")
  expect_gt(result, 0)
  expect_lt(result, 5)  # Should be ~1% for this data
})

test_that("geometric_cv returns NA for n<2", {
  # Act & Assert
  expect_true(is.na(geometric_cv(c(10.0))))
  expect_true(is.na(geometric_cv(numeric(0))))
})

test_that("geometric_cv handles NA values correctly", {
  # Arrange
  values_with_na <- c(10.0, NA, 10.2, 10.1)

  # Act
  result <- geometric_cv(values_with_na)

  # Assert
  expect_type(result, "double")
  expect_false(is.na(result))  # Should remove NA and calculate
  expect_gt(result, 0)
})

# ============================================================================
# Task 2.1.3: calculate_consensus_dataset() - RED Phase
# ============================================================================

test_that("calculate_consensus_dataset handles replicates with intensity", {
  # Arrange
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P1", "P2", "P3"),
    Run = c("R1", "R2", "R3", "R1", "R1"),
    RT.Start = c(10.0, 10.2, 10.1, 20.0, 30.0),
    Precursor.Mz = c(400, 401, 400.5, 500, 600),
    FWHM = c(0.5, 0.55, 0.52, 0.6, 0.45),
    Precursor.Quantity = c(1e5, 1.1e5, 1.05e5, 2e5, 3e5)  # Added intensity
  )

  # Act - explicit min_replicates = 1 keeps singletons
  result <- calculate_consensus_dataset(test_data, min_replicates = 1)

  # Assert - P1 (n=3)
  p1 <- result %>% filter(Precursor.Id == "P1")
  expect_equal(nrow(p1), 1)
  expect_equal(p1$RT.Start, 10.1)  # median of 10.0, 10.1, 10.2
  expect_equal(p1$n_replicates, 3)
  expect_false(is.na(p1$RT_CV_pct))  # Base CV for RT
  expect_false(is.na(p1$FWHM_CV_pct))  # Base CV for FWHM
  expect_false(is.na(p1$Intensity_CV_pct))  # Geometric CV for intensity
  expect_true("Precursor.Quantity" %in% colnames(result))  # Intensity preserved

  # Assert - P3 (n=1, singleton)
  p3 <- result %>% filter(Precursor.Id == "P3")
  expect_equal(nrow(p3), 1)
  expect_equal(p3$RT.Start, 30.0)  # original value
  expect_equal(p3$n_replicates, 1)
  expect_true(is.na(p3$RT_CV_pct))  # Singleton CV = NA
  expect_true(is.na(p3$Intensity_CV_pct))  # Singleton intensity CV = NA
})

test_that("calculate_consensus_dataset keeps high intensity CV precursors", {
  # Arrange - P2 has a 5x intensity spread (low-signal-like behaviour)
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P2", "P2"),
    Run = c("R1", "R2", "R1", "R2"),
    RT.Start = c(10.0, 10.1, 20.0, 20.1),
    Precursor.Mz = c(400, 401, 500, 501),
    FWHM = c(0.5, 0.52, 0.5, 0.52),
    Precursor.Quantity = c(1e5, 1.05e5, 1e5, 5e5)
  )

  # Act
  result <- calculate_consensus_dataset(test_data)

  # Assert - intensity CV is reported as QC but never used as a filter
  expect_setequal(result$Precursor.Id, c("P1", "P2"))
  expect_gt(result$Intensity_CV_pct[result$Precursor.Id == "P2"], 30)
})

test_that("resolve_min_replicates scales with run count", {
  expect_equal(resolve_min_replicates(1), 1)
  expect_equal(resolve_min_replicates(2), 1)
  expect_equal(resolve_min_replicates(3), 2)
  expect_equal(resolve_min_replicates(4), 2)
  expect_equal(resolve_min_replicates(5), 3)
  # Explicit value wins over the run-count rule
  expect_equal(resolve_min_replicates(3, min_replicates = 1), 1)
  expect_error(resolve_min_replicates(3, min_replicates = 4), "min_replicates")
  expect_error(resolve_min_replicates(3, min_replicates = 0), "min_replicates")
})

test_that("calculate_consensus_dataset links min_replicates to run count by default", {
  # Arrange - 3 runs: P1 in 3, P2 in 2, P3 in 1
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P1", "P2", "P2", "P3"),
    Run = c("R1", "R2", "R3", "R1", "R2", "R3"),
    RT.Start = c(10.0, 10.2, 10.1, 20.0, 20.1, 30.0),
    Precursor.Mz = c(400, 400, 400, 500, 500, 600),
    FWHM = c(0.5, 0.55, 0.52, 0.6, 0.6, 0.45)
  )

  # Act
  result <- calculate_consensus_dataset(test_data)
  meta <- attr(result, "metadata")

  # Assert - 3 runs -> detected in >= 2 runs
  expect_setequal(result$Precursor.Id, c("P1", "P2"))
  expect_equal(meta$min_replicates, 2)
  expect_equal(meta$n_filtered_replicates, 1)
})

test_that("calculate_consensus_dataset works without intensity column", {
  # Arrange - Data without Precursor.Quantity
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P2"),
    Run = c("R1", "R2", "R1"),
    RT.Start = c(10.0, 10.1, 20.0),
    Precursor.Mz = c(400, 401, 500),
    FWHM = c(0.5, 0.52, 0.6)
  )

  # Act
  result <- calculate_consensus_dataset(test_data)

  # Assert - Should work without intensity filtering
  expect_equal(nrow(result), 2)  # P1 and P2
  expect_false("Intensity_CV_pct" %in% colnames(result))  # No intensity CV column
})

