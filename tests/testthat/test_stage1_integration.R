# test_stage1_integration.R - Integration Tests for Stage 1 with Replicate Handling
# DIA Window Optimizer v2.0 - TDD Approach
#
# Following Kent Beck's TDD: RED → GREEN → REFACTOR

library(testthat)
library(dplyr)
library(tibble)
library(arrow)

# Source required modules
if (file.exists("R/stage1_data_validation.R")) {
  source("R/stage1_data_validation.R")
  source("R/replicate_utils.R")
} else if (file.exists("../../R/stage1_data_validation.R")) {
  source("../../R/stage1_data_validation.R")
  source("../../R/replicate_utils.R")
} else {
  stop("Cannot find R/stage1_data_validation.R")
}

# ============================================================================
# Helper: Create Test Fixture with 3 Technical Replicates
# ============================================================================

create_replicate_test_data <- function(n_precursors = 100) {
  # Create 3 technical replicates with slight variations
  runs <- c("Run1", "Run2", "Run3")

  data_list <- lapply(1:3, function(run_idx) {
    tibble(
      Run = runs[run_idx],
      Precursor.Id = paste0("Precursor_", 1:n_precursors),
      RT.Start = rnorm(n_precursors, mean = 50, sd = 10) + rnorm(n_precursors, 0, 0.1),
      Precursor.Mz = rnorm(n_precursors, mean = 600, sd = 100) + rnorm(n_precursors, 0, 0.5),
      FWHM = abs(rnorm(n_precursors, mean = 0.5, sd = 0.1)) + abs(rnorm(n_precursors, 0, 0.02)),
      Q.Value = runif(n_precursors, 0, 0.001),  # High quality
      PG.Q.Value = runif(n_precursors, 0, 0.001)
    )
  })

  bind_rows(data_list)
}

# ============================================================================
# Task 2.2.1: Stage 1 Integration - RED Phase
# ============================================================================

test_that("create_validated_dataset handles replicates when enabled", {
  # Arrange - Create temporary parquet file with 3 replicates
  test_data <- create_replicate_test_data(n_precursors = 50)
  temp_file <- tempfile(fileext = ".parquet")
  write_parquet(test_data, temp_file)

  # Act
  result <- create_validated_dataset(
    proteome_file = temp_file,
    enable_replicate_consensus = TRUE,
    max_cv_percent = 20,
    apply_quality_filters = FALSE  # Skip quality filters for test
  )

  # Assert - Check ValidatedData structure
  expect_s3_class(result, "ValidatedData")
  expect_true("data" %in% names(result))
  expect_true("metadata" %in% names(result))

  # Assert - Check replicate metadata
  expect_true("n_runs" %in% names(result$metadata))
  expect_equal(result$metadata$n_runs, 3)
  expect_true("mean_fwhm_cv_pct" %in% names(result$metadata))
  expect_gt(result$metadata$n_runs, 1)

  # Assert - Check data has CV columns
  expect_true("RT_CV_pct" %in% colnames(result$data))
  expect_true("n_replicates" %in% colnames(result$data))
  expect_true("FWHM_CV_pct" %in% colnames(result$data))

  # Assert - Check consensus worked (should have ~50 precursors, not 150)
  expect_lt(nrow(result$data), 60)  # Should be close to 50, not 150
  expect_gt(nrow(result$data), 20)  # Some may be filtered by CV (can be aggressive)

  # Cleanup
  unlink(temp_file)
})

test_that("create_validated_dataset works with single run (no replication)", {
  # Arrange - Create temporary parquet file with single run
  test_data <- tibble(
    Run = "Run1",
    Precursor.Id = paste0("Precursor_", 1:50),
    RT.Start = rnorm(50, mean = 50, sd = 10),
    Precursor.Mz = rnorm(50, mean = 600, sd = 100),
    FWHM = abs(rnorm(50, mean = 0.5, sd = 0.1)),
    Q.Value = runif(50, 0, 0.001),
    PG.Q.Value = runif(50, 0, 0.001)
  )
  temp_file <- tempfile(fileext = ".parquet")
  write_parquet(test_data, temp_file)

  # Act
  result <- create_validated_dataset(
    proteome_file = temp_file,
    enable_replicate_consensus = TRUE,
    apply_quality_filters = FALSE
  )

  # Assert
  expect_s3_class(result, "ValidatedData")
  expect_equal(result$metadata$n_runs, 1)

  # Single run should not have CV columns
  expect_false("RT_CV_pct" %in% colnames(result$data))

  # Cleanup
  unlink(temp_file)
})

test_that("create_validated_dataset can disable replicate handling", {
  # Arrange
  test_data <- create_replicate_test_data(n_precursors = 50)
  temp_file <- tempfile(fileext = ".parquet")
  write_parquet(test_data, temp_file)

  # Act
  result <- create_validated_dataset(
    proteome_file = temp_file,
    enable_replicate_consensus = FALSE,  # Disabled
    apply_quality_filters = FALSE
  )

  # Assert - Should keep all 150 rows (50 precursors × 3 runs)
  expect_equal(nrow(result$data), 150)
  expect_false("RT_CV_pct" %in% colnames(result$data))

  # Cleanup
  unlink(temp_file)
})
