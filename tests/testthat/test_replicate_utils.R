# test_replicate_utils.R - Unit Tests for Replicate Handling Utilities
# DIA Window Optimizer v2.0 - TDD Approach
#
# Following Kent Beck's TDD: RED → GREEN → REFACTOR

library(testthat)
library(dplyr)
library(tibble)

# Source the module under test (handle different working directories)
if (file.exists("R/replicate_utils.R")) {
  source("R/replicate_utils.R")
} else if (file.exists("../../R/replicate_utils.R")) {
  source("../../R/replicate_utils.R")
} else {
  stop("Cannot find R/replicate_utils.R - check working directory")
}

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

  # Act
  result <- calculate_consensus_dataset(test_data)

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

test_that("calculate_consensus_dataset filters high intensity CV precursors", {
  # Arrange - Create data with high intensity CV for P2
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P2", "P2"),
    Run = c("R1", "R2", "R1", "R2"),
    RT.Start = c(10.0, 10.1, 20.0, 20.1),
    Precursor.Mz = c(400, 401, 500, 501),
    FWHM = c(0.5, 0.52, 0.5, 0.52),
    Precursor.Quantity = c(1e5, 1.05e5, 1e5, 5e5)  # P2 has huge intensity variation (5x difference)
  )

  # Act - Use max_intensity_cv_percent parameter
  result <- calculate_consensus_dataset(test_data, max_intensity_cv_percent = 30)

  # Assert - P2 should be filtered out due to high intensity CV
  expect_equal(nrow(result), 1)  # Only P1 remains
  expect_true("P1" %in% result$Precursor.Id)
  expect_false("P2" %in% result$Precursor.Id)
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

test_that("calculate_consensus_dataset keeps singletons regardless of CV threshold", {
  # Arrange
  test_data <- tibble(
    Precursor.Id = c("P1", "P1", "P2"),
    Run = c("R1", "R2", "R1"),
    RT.Start = c(10.0, 50.0, 30.0),  # P1 has huge CV
    Precursor.Mz = c(400, 401, 600),
    FWHM = c(0.5, 50.0, 0.45),  # P1 has huge CV
    Precursor.Quantity = c(1e5, 5e6, 3e5)  # P1 has huge intensity CV (50x difference)
  )

  # Act - Very strict intensity CV threshold
  result <- calculate_consensus_dataset(test_data, max_intensity_cv_percent = 5)

  # Assert - P2 (singleton) should be kept despite strict threshold
  p2 <- result %>% filter(Precursor.Id == "P2")
  expect_equal(nrow(p2), 1)
  expect_equal(p2$n_replicates, 1)
})
