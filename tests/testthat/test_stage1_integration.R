# test_stage1_integration.R - Integration Tests for Stage 1 with Replicate Handling
# DIA Window Optimizer v2.0 - TDD Approach
#
# Following Kent Beck's TDD: RED → GREEN → REFACTOR

library(testthat)
library(arrow)

# ============================================================================
# Helper: Create Test Fixture with 3 Technical Replicates
# ============================================================================

create_replicate_test_data <- function(n_precursors = 100) {
  # Create 3 technical replicates with slight variations
  runs <- c("Run1", "Run2", "Run3")

  data_list <- lapply(1:3, function(run_idx) {
    base_intensity <- 10^rnorm(n_precursors, mean = 7, sd = 1.5)  # Log-normal distributed intensity
    tibble(
      Run = runs[run_idx],
      Precursor.Id = paste0("Precursor_", 1:n_precursors),
      RT.Start = rnorm(n_precursors, mean = 50, sd = 10) + rnorm(n_precursors, 0, 0.1),
      RT.Stop = rnorm(n_precursors, mean = 50, sd = 10) + abs(rnorm(n_precursors, 1, 0.2)),
      Precursor.Mz = rnorm(n_precursors, mean = 600, sd = 100) + rnorm(n_precursors, 0, 0.5),
      FWHM = abs(rnorm(n_precursors, mean = 0.5, sd = 0.1)) + abs(rnorm(n_precursors, 0, 0.02)),
      Precursor.Quantity = base_intensity * exp(rnorm(n_precursors, 0, 0.15)),  # Add intensity with variation
      Protein.Group = paste0("ProteinGroup_", sample(1:50, n_precursors, replace = TRUE)),  # Add Protein.Group
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
  # Arrange - Create temporary parquet file with 3 replicates (with intensity)
  test_data <- create_replicate_test_data(n_precursors = 50)
  # Add Precursor.Quantity column
  test_data <- test_data %>%
    mutate(Precursor.Quantity = abs(rnorm(n(), mean = 1e5, sd = 2e4)))

  temp_file <- tempfile(fileext = ".parquet")
  write_parquet(test_data, temp_file)

  # Act
  result <- create_validated_dataset(
    proteome_file = temp_file,
    enable_replicate_consensus = TRUE,
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
  expect_true("Intensity_CV_pct" %in% colnames(result$data))  # New: intensity CV
  expect_true("Precursor.Quantity" %in% colnames(result$data))  # Intensity preserved

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
    RT.Stop = rnorm(50, mean = 50, sd = 10) + abs(rnorm(50, 1, 0.2)),
    Precursor.Mz = rnorm(50, mean = 600, sd = 100),
    FWHM = abs(rnorm(50, mean = 0.5, sd = 0.1)),
    Protein.Group = paste0("ProteinGroup_", sample(1:20, 50, replace = TRUE)),  # Add Protein.Group
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

# ============================================================================
# Run-aware deduplication
# ============================================================================

test_that("validate_data dedup is run-aware", {
  # Arrange - P1 has an identical (Precursor.Mz, RT.Start) in R1 and R2;
  # R3 additionally carries a true within-run duplicate row.
  test_data <- tibble::tibble(
    Precursor.Id = c("P1", "P1", "P1", "P1"),
    Run          = c("R1", "R2", "R3", "R3"),
    Precursor.Mz = c(523.774, 523.774, 523.774, 523.774),
    RT.Start     = c(41.25, 41.25, 41.31, 41.31),
    FWHM         = c(0.10, 0.11, 0.10, 0.10)
  )

  # Act
  result <- validate_data(test_data, apply_quality_filters = FALSE)

  # Assert - cross-run coincidence is kept, within-run duplicate is removed
  expect_equal(nrow(result), 3)
  expect_setequal(result$Run, c("R1", "R2", "R3"))
})

test_that("validate_data dedup works without a Run column", {
  test_data <- tibble::tibble(
    Precursor.Id = c("P1", "P1", "P2"),
    Precursor.Mz = c(400, 400, 500),
    RT.Start     = c(10, 10, 20),
    FWHM         = c(0.1, 0.1, 0.1)
  )

  result <- validate_data(test_data, apply_quality_filters = FALSE)

  expect_equal(nrow(result), 2)
})
