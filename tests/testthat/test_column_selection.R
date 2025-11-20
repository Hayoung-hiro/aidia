# test_column_selection.R - Tests for Column Selection System
# DIA Window Optimizer v2.0

library(testthat)
library(tibble)
library(dplyr)

# Source function
if (file.exists("R/column_selection.R")) {
  source("R/column_selection.R")
} else if (file.exists("../../R/column_selection.R")) {
  source("../../R/column_selection.R")
} else {
  stop("Cannot find column_selection.R")
}

# ============================================================================
# Test Data Creation
# ============================================================================

create_mock_validated_data <- function(n = 100) {
  tibble(
    Precursor.Id = paste0("P", 1:n),
    Run = sample(paste0("R", 1:3), n, replace = TRUE),
    RT.Start = runif(n, 10, 90),
    Precursor.Mz = runif(n, 400, 1200),
    FWHM = runif(n, 0.3, 0.8),
    Precursor.Quantity = abs(rnorm(n, mean = 1e5, sd = 2e4)),

    # QC columns (after consensus)
    n_replicates = sample(1:3, n, replace = TRUE),
    RT_CV_pct = runif(n, 0, 10),
    FWHM_CV_pct = runif(n, 0, 15),
    Intensity_CV_pct = runif(n, 0, 30),

    # Unused columns (should be removed)
    Q.Value = runif(n, 0, 0.01),
    PG.MaxLFQ = abs(rnorm(n, mean = 1e6, sd = 3e5)),
    Protein.Names = paste0("Protein_", 1:n),
    Genes = paste0("Gene_", 1:n)
  )
}

# ============================================================================
# Test: Constants
# ============================================================================

test_that("Essential columns constant is correct", {
  expect_equal(
    ESSENTIAL_COLUMNS,
    c("Precursor.Id", "RT.Start", "Precursor.Mz", "FWHM")
  )
})

test_that("QC columns constant is correct", {
  expected_qc <- c(
    "n_replicates", "RT_CV_pct", "Mz_CV_pct",
    "FWHM_CV_pct", "Intensity_CV_pct"
  )
  expect_equal(QC_COLUMNS, expected_qc)
})

# ============================================================================
# Test: get_columns_for_mode()
# ============================================================================

test_that("get_columns_for_mode returns minimal columns", {
  result <- get_columns_for_mode("minimal")

  expect_equal(result, ESSENTIAL_COLUMNS)
  expect_length(result, 4)
})

test_that("get_columns_for_mode returns standard columns", {
  mock_data <- create_mock_validated_data()

  result <- get_columns_for_mode(
    "standard",
    available_columns = colnames(mock_data)
  )

  # Should include essential + available QC columns
  expect_true(all(ESSENTIAL_COLUMNS %in% result))
  expect_true("n_replicates" %in% result)
  expect_true("RT_CV_pct" %in% result)
})

test_that("get_columns_for_mode returns all columns for full mode", {
  mock_data <- create_mock_validated_data()

  result <- get_columns_for_mode(
    "full",
    available_columns = colnames(mock_data)
  )

  expect_equal(result, colnames(mock_data))
})

test_that("get_columns_for_mode handles custom mode", {
  custom_cols <- c("Precursor.Charge", "Modified.Sequence")

  result <- get_columns_for_mode(
    "custom",
    additional_columns = custom_cols
  )

  # Should include essential + custom
  expect_true(all(ESSENTIAL_COLUMNS %in% result))
  expect_true(all(custom_cols %in% result))
})

test_that("get_columns_for_mode validates mode argument", {
  expect_error(
    get_columns_for_mode("invalid_mode"),
    "Invalid mode"
  )
})

# ============================================================================
# Test: select_essential_columns()
# ============================================================================

test_that("select_essential_columns works in minimal mode", {
  mock_data <- create_mock_validated_data(n = 50)

  result <- select_essential_columns(
    mock_data,
    mode = "minimal",
    verbose = FALSE
  )

  # Should have only 4 essential columns
  expect_equal(ncol(result), 5)  # 4 essential + Precursor.Quantity (preserve_intensity=TRUE)
  expect_true(all(ESSENTIAL_COLUMNS %in% colnames(result)))
  expect_equal(nrow(result), 50)
})

test_that("select_essential_columns works in standard mode", {
  mock_data <- create_mock_validated_data(n = 50)

  result <- select_essential_columns(
    mock_data,
    mode = "standard",
    verbose = FALSE
  )

  # Should have essential + QC + intensity
  expect_gt(ncol(result), 4)
  expect_true(all(ESSENTIAL_COLUMNS %in% colnames(result)))
  expect_true("n_replicates" %in% colnames(result))
  expect_true("Precursor.Quantity" %in% colnames(result))

  # Should NOT have unused columns
  expect_false("Q.Value" %in% colnames(result))
  expect_false("Protein.Names" %in% colnames(result))
})

test_that("select_essential_columns preserves intensity by default", {
  mock_data <- create_mock_validated_data(n = 50)

  result <- select_essential_columns(
    mock_data,
    mode = "minimal",
    preserve_intensity = TRUE,
    verbose = FALSE
  )

  expect_true("Precursor.Quantity" %in% colnames(result))
})

test_that("select_essential_columns can skip intensity", {
  mock_data <- create_mock_validated_data(n = 50)

  result <- select_essential_columns(
    mock_data,
    mode = "minimal",
    preserve_intensity = FALSE,
    verbose = FALSE
  )

  expect_false("Precursor.Quantity" %in% colnames(result))
  expect_equal(ncol(result), 4)  # Only essential
})

test_that("select_essential_columns handles missing essential columns", {
  mock_data <- create_mock_validated_data(n = 50) %>%
    select(-RT.Start)  # Remove essential column

  expect_error(
    select_essential_columns(mock_data, verbose = FALSE),
    "Missing essential columns"
  )
})

test_that("select_essential_columns works with custom mode", {
  mock_data <- create_mock_validated_data(n = 50) %>%
    mutate(Precursor.Charge = sample(2:4, 50, replace = TRUE))

  result <- select_essential_columns(
    mock_data,
    mode = "custom",
    additional_columns = c("Precursor.Charge"),
    verbose = FALSE
  )

  expect_true("Precursor.Charge" %in% colnames(result))
  expect_true(all(ESSENTIAL_COLUMNS %in% colnames(result)))
})

# ============================================================================
# Test: Validation Helpers
# ============================================================================

test_that("validate_column_presence works correctly", {
  mock_data <- create_mock_validated_data(n = 50)

  # Should pass for essential columns
  expect_true(
    validate_column_presence(
      mock_data,
      ESSENTIAL_COLUMNS,
      "test"
    )
  )

  # Should fail for missing columns
  expect_error(
    validate_column_presence(
      mock_data,
      c("RT.Start", "Missing.Column"),
      "test"
    ),
    "Missing required columns"
  )
})

test_that("check_optional_columns identifies available columns", {
  mock_data <- create_mock_validated_data(n = 50)

  optional <- c("Precursor.Quantity", "Protein.Names", "Missing.Column")

  result <- check_optional_columns(mock_data, optional)

  expect_equal(result, c("Precursor.Quantity", "Protein.Names"))
  expect_false("Missing.Column" %in% result)
})

# ============================================================================
# Test: Memory Estimation
# ============================================================================

test_that("estimate_memory calculates correctly", {
  mock_data <- tibble(
    col1 = 1:1000,
    col2 = 1:1000,
    col3 = 1:1000
  )

  # 1000 rows × 3 cols × 8 bytes = 24,000 bytes = 0.0229 MB
  result_mb <- estimate_memory(mock_data, unit = "MB")
  expect_gt(result_mb, 0.02)
  expect_lt(result_mb, 0.03)

  result_kb <- estimate_memory(mock_data, unit = "KB")
  expect_gt(result_kb, 23)
  expect_lt(result_kb, 24)
})

test_that("calculate_memory_savings works correctly", {
  data_before <- create_mock_validated_data(n = 100)  # 14 columns
  data_after <- data_before %>%
    select(all_of(c(ESSENTIAL_COLUMNS, "Precursor.Quantity")))  # 5 columns

  result <- calculate_memory_savings(data_before, data_after)

  expect_type(result, "list")
  expect_true("memory_before_mb" %in% names(result))
  expect_true("memory_after_mb" %in% names(result))
  expect_true("savings_mb" %in% names(result))
  expect_true("savings_pct" %in% names(result))

  # Should show significant savings
  expect_gt(result$memory_before_mb, result$memory_after_mb)
  expect_gt(result$savings_pct, 50)  # >50% reduction
})

# ============================================================================
# Test: Integration with Real-World Scenarios
# ============================================================================

test_that("Column selection supports PTM workflow", {
  # PTM workflow needs Modified.Sequence and Precursor.Charge
  mock_data <- create_mock_validated_data(n = 50) %>%
    mutate(
      Modified.Sequence = paste0("PEPTIDE_", 1:50),
      Precursor.Charge = sample(2:4, 50, replace = TRUE)
    )

  result <- select_essential_columns(
    mock_data,
    mode = "custom",
    additional_columns = c("Modified.Sequence", "Precursor.Charge"),
    verbose = FALSE
  )

  expect_true("Modified.Sequence" %in% colnames(result))
  expect_true("Precursor.Charge" %in% colnames(result))
  expect_true(all(ESSENTIAL_COLUMNS %in% colnames(result)))

  # Should NOT have unused columns
  expect_false("Protein.Names" %in% colnames(result))
})

test_that("Column selection handles missing optional columns gracefully", {
  # Data without QC columns (single run, no consensus)
  mock_data <- tibble(
    Precursor.Id = paste0("P", 1:50),
    RT.Start = runif(50, 10, 90),
    Precursor.Mz = runif(50, 400, 1200),
    FWHM = runif(50, 0.3, 0.8)
  )

  # Standard mode should work even without QC columns
  result <- select_essential_columns(
    mock_data,
    mode = "standard",
    verbose = FALSE
  )

  expect_equal(ncol(result), 4)  # Only essential (no intensity, no QC)
  expect_true(all(ESSENTIAL_COLUMNS %in% colnames(result)))
})
