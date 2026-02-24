# test_stage1_real_data.R - Real Data Functional Test for Stage 1
# DIA Window Optimizer v2.0
#
# Purpose: Test Stage 1 with actual DIA-NN data files
# Tests: Single run, technical replicates, different gradient lengths

library(dplyr)
library(tibble)
library(arrow)

# Source Stage 1 modules
source("R/data_validation.R")
source("R/replicate_utils.R")
source("R/column_selection.R")
source("R/quality_validation.R")

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   STAGE 1 REAL DATA FUNCTIONAL TEST                                  ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n\n")

# ============================================================================
# Test 1: 30min Gradient (Single Run)
# ============================================================================

cat("\n" )
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 1: 30min Gradient (Single Run)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

test1_result <- tryCatch({
  result <- create_validated_dataset(
    proteome_file = "data/30min_report.parquet",
    enable_replicate_consensus = FALSE,  # Single run
    quality_threshold = 0.7
  )

  cat("\n✓ TEST 1 PASSED\n")
  cat(sprintf("  - Precursors: %d\n", result$metadata$n_precursors))
  cat(sprintf("  - Columns: %d (from %d, reduced %d%%)\n",
              result$metadata$n_columns,
              result$metadata$column_selection$n_columns_before,
              round(100 * result$metadata$column_selection$n_removed /
                    result$metadata$column_selection$n_columns_before)))
  cat(sprintf("  - RT range: %.2f - %.2f min\n",
              result$metadata$rt_range[1], result$metadata$rt_range[2]))
  cat(sprintf("  - m/z range: %.1f - %.1f Da\n",
              result$metadata$mz_range[1], result$metadata$mz_range[2]))
  cat(sprintf("  - Quality score: %.3f\n", result$validation_status$quality_score))
  cat(sprintf("  - Processing time: %.2f sec\n", result$metadata$processing_time_sec))

  result

}, error = function(e) {
  cat("\n✗ TEST 1 FAILED\n")
  cat(sprintf("  Error: %s\n", e$message))
  NULL
})


# ============================================================================
# Test 2: 60min Gradient (Single Run)
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 2: 60min Gradient (Single Run)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

test2_result <- tryCatch({
  result <- create_validated_dataset(
    proteome_file = "data/60min_report.parquet",
    enable_replicate_consensus = FALSE,
    quality_threshold = 0.7
  )

  cat("\n✓ TEST 2 PASSED\n")
  cat(sprintf("  - Precursors: %d\n", result$metadata$n_precursors))
  cat(sprintf("  - Columns: %d (reduced %d%%)\n",
              result$metadata$n_columns,
              round(100 * result$metadata$column_selection$n_removed /
                    result$metadata$column_selection$n_columns_before)))
  cat(sprintf("  - RT range: %.2f - %.2f min\n",
              result$metadata$rt_range[1], result$metadata$rt_range[2]))
  cat(sprintf("  - Quality score: %.3f\n", result$validation_status$quality_score))
  cat(sprintf("  - Processing time: %.2f sec\n", result$metadata$processing_time_sec))

  result

}, error = function(e) {
  cat("\n✗ TEST 2 FAILED\n")
  cat(sprintf("  Error: %s\n", e$message))
  NULL
})


# ============================================================================
# Test 3: 90min Gradient (Single Run)
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 3: 90min Gradient (Single Run)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

test3_result <- tryCatch({
  result <- create_validated_dataset(
    proteome_file = "data/90min_report.parquet",
    enable_replicate_consensus = FALSE,
    quality_threshold = 0.7
  )

  cat("\n✓ TEST 3 PASSED\n")
  cat(sprintf("  - Precursors: %d\n", result$metadata$n_precursors))
  cat(sprintf("  - Columns: %d (reduced %d%%)\n",
              result$metadata$n_columns,
              round(100 * result$metadata$column_selection$n_removed /
                    result$metadata$column_selection$n_columns_before)))
  cat(sprintf("  - RT range: %.2f - %.2f min\n",
              result$metadata$rt_range[1], result$metadata$rt_range[2]))
  cat(sprintf("  - Quality score: %.3f\n", result$validation_status$quality_score))
  cat(sprintf("  - Processing time: %.2f sec\n", result$metadata$processing_time_sec))

  result

}, error = function(e) {
  cat("\n✗ TEST 3 FAILED\n")
  cat(sprintf("  Error: %s\n", e$message))
  NULL
})


# ============================================================================
# Test 4: 30min Technical Replicates (3 Runs with Consensus)
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 4: 30min Technical Replicates (3 Runs)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# Check if replicate files exist
replicate_files <- c(
  "data/bak/30min_report_01.parquet",
  "data/bak/30min_report_02.parquet",
  "data/bak/30min_report_03.parquet"
)

all_exist <- all(file.exists(replicate_files))

if (all_exist) {
  test4_result <- tryCatch({
    # Load and combine 3 replicates
    data_list <- lapply(1:3, function(i) {
      data <- read_parquet(replicate_files[i])
      data$Run <- paste0("Run", i)
      data
    })

    combined_data <- bind_rows(data_list)

    # Write combined file
    temp_file <- tempfile(fileext = ".parquet")
    write_parquet(combined_data, temp_file)

    # Test with consensus
    result <- create_validated_dataset(
      proteome_file = temp_file,
      enable_replicate_consensus = TRUE,
      max_intensity_cv_percent = 30,
      quality_threshold = 0.7
    )

    cat("\n✓ TEST 4 PASSED\n")
    cat(sprintf("  - Runs detected: %d\n", result$metadata$n_runs))
    cat(sprintf("  - Precursors before consensus: %d\n",
                result$metadata$n_precursors_before %||% nrow(combined_data)))
    cat(sprintf("  - Precursors after consensus: %d\n", result$metadata$n_precursors))
    cat(sprintf("  - Filtered by CV: %d (%.1f%%)\n",
                result$metadata$n_filtered_cv %||% 0,
                100 * (result$metadata$n_filtered_cv %||% 0) /
                  (result$metadata$n_precursors_before %||% 1)))
    cat(sprintf("  - Columns: %d (reduced %d%%)\n",
                result$metadata$n_columns,
                round(100 * result$metadata$column_selection$n_removed /
                      result$metadata$column_selection$n_columns_before)))

    # Check QC columns present
    has_qc_columns <- all(c("n_replicates", "RT_CV_pct", "FWHM_CV_pct", "Intensity_CV_pct") %in%
                          colnames(result$data))
    cat(sprintf("  - QC columns present: %s\n", ifelse(has_qc_columns, "✓", "✗")))

    cat(sprintf("  - Quality score: %.3f\n", result$validation_status$quality_score))
    cat(sprintf("  - Processing time: %.2f sec\n", result$metadata$processing_time_sec))

    # Cleanup
    unlink(temp_file)

    result

  }, error = function(e) {
    cat("\n✗ TEST 4 FAILED\n")
    cat(sprintf("  Error: %s\n", e$message))
    NULL
  })
} else {
  cat("\n⊘ TEST 4 SKIPPED (replicate files not found)\n")
  test4_result <- NULL
}


# ============================================================================
# Test 5: Column Selection Verification
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 5: Column Selection Verification\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

if (!is.null(test1_result)) {
  cat("\nChecking essential columns in single run data:\n")

  essential_expected <- c("Precursor.Id", "RT.Start", "Precursor.Mz", "FWHM", "Protein.Group")
  essential_present <- essential_expected %in% colnames(test1_result$data)

  for (i in seq_along(essential_expected)) {
    status <- ifelse(essential_present[i], "✓", "✗")
    cat(sprintf("  %s %s\n", status, essential_expected[i]))
  }

  all_essential_present <- all(essential_present)

  if (all_essential_present) {
    cat("\n✓ TEST 5 PASSED - All essential columns present\n")
  } else {
    cat("\n✗ TEST 5 FAILED - Missing essential columns\n")
  }
} else {
  cat("\n⊘ TEST 5 SKIPPED (Test 1 failed)\n")
}


# ============================================================================
# Test 6: Quality Validation Details
# ============================================================================

cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("TEST 6: Quality Validation Details\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

if (!is.null(test1_result)) {
  cat("\nQuality validation components:\n")

  details <- test1_result$validation_status$quality_details

  # FWHM outliers
  cat(sprintf("  FWHM outliers: %.1f%% (%d / %d)\n",
              details$fwhm_outliers$pct_outliers * 100,
              details$fwhm_outliers$n_outliers,
              test1_result$metadata$n_precursors))

  # RT issues
  cat(sprintf("  RT issues: %.1f%% (%d negative, %d NA)\n",
              details$rt_issues$pct_issues * 100,
              details$rt_issues$n_negative,
              details$rt_issues$n_na))

  # m/z issues
  cat(sprintf("  m/z issues: %.1f%% (%d invalid)\n",
              details$mz_issues$pct_invalid * 100,
              details$mz_issues$n_invalid))

  # Overall
  cat(sprintf("\n  Overall quality score: %.3f\n",
              test1_result$validation_status$quality_score))
  cat(sprintf("  Status: %s\n",
              ifelse(test1_result$validation_status$all_passed,
                     "✓ PASSED", "✗ FAILED")))

  cat("\n✓ TEST 6 COMPLETED\n")
} else {
  cat("\n⊘ TEST 6 SKIPPED (Test 1 failed)\n")
}


# ============================================================================
# Summary
# ============================================================================

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   TEST SUMMARY                                                        ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n\n")

test_results <- c(
  test1 = !is.null(test1_result),
  test2 = !is.null(test2_result),
  test3 = !is.null(test3_result),
  test4 = !is.null(test4_result),
  test5 = !is.null(test1_result) && all(essential_expected %in% colnames(test1_result$data)),
  test6 = !is.null(test1_result)
)

for (i in seq_along(test_results)) {
  test_name <- names(test_results)[i]
  status <- ifelse(test_results[i], "✓ PASS", "✗ FAIL")

  test_desc <- switch(test_name,
    test1 = "30min single run",
    test2 = "60min single run",
    test3 = "90min single run",
    test4 = "30min replicates (3 runs)",
    test5 = "Column selection",
    test6 = "Quality validation"
  )

  cat(sprintf("  %s  Test %d: %s\n", status, i, test_desc))
}

passed <- sum(test_results, na.rm = TRUE)
total <- length(test_results)

cat(sprintf("\nOverall: %d/%d tests passed (%.0f%%)\n", passed, total, 100 * passed / total))

if (passed == total) {
  cat("\n🎉 ALL TESTS PASSED - Stage 1 is working correctly!\n\n")
} else {
  cat("\n⚠️  SOME TESTS FAILED - Review errors above\n\n")
}

# Return summary invisibly
invisible(list(
  test1 = test1_result,
  test2 = test2_result,
  test3 = test3_result,
  test4 = test4_result,
  passed = passed,
  total = total
))
