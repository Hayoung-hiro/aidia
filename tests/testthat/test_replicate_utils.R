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
# Task 2.1.2: geometric_cv() - RED Phase
# ============================================================================

test_that("geometric_cv calculates correctly for log-normal data", {
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
