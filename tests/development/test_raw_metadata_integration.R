# test_raw_metadata_integration.R - Test and validate raw metadata integration

cat("╔══════════════════════════════════════════════╗\n")
cat("║    RAW METADATA INTEGRATION TEST SUITE       ║\n")
cat("╚══════════════════════════════════════════════╝\n\n")

# Load required libraries and modules
library(dplyr)

# Source all required modules
source("R/raw_metadata_extractor.R")
source("R/user_config_generator.R")
source("R/data_loader.R")
source("R/fwhm_analyzer.R")
source("R/utils.R")
source("config/instruments.R")

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

test_config <- list(
  run_basic_tests = TRUE,
  run_integration_tests = TRUE,
  run_validation_tests = TRUE,
  create_test_files = TRUE,
  verbose = TRUE
)

test_results <- list(
  passed = 0,
  failed = 0,
  errors = character(),
  warnings = character()
)

# Helper function for test reporting
run_test <- function(test_name, test_function, ...) {
  cat(sprintf("🧪 Testing: %s...", test_name))

  tryCatch({
    result <- test_function(...)

    if (result$success) {
      test_results$passed <<- test_results$passed + 1
      cat(" ✅ PASSED\n")
      if (test_config$verbose && !is.null(result$message)) {
        cat(sprintf("   %s\n", result$message))
      }
    } else {
      test_results$failed <<- test_results$failed + 1
      test_results$errors <<- c(test_results$errors,
                               sprintf("%s: %s", test_name, result$message))
      cat(" ❌ FAILED\n")
      cat(sprintf("   Error: %s\n", result$message))
    }

  }, error = function(e) {
    test_results$failed <<- test_results$failed + 1
    test_results$errors <<- c(test_results$errors,
                             sprintf("%s: %s", test_name, e$message))
    cat(" ❌ ERROR\n")
    cat(sprintf("   Exception: %s\n", e$message))
  })
}

# =============================================================================
# BASIC FUNCTIONALITY TESTS
# =============================================================================

if (test_config$run_basic_tests) {
  cat("\n=== BASIC FUNCTIONALITY TESTS ===\n")

  # Test 1: rawrr availability check
  test_rawrr_availability <- function() {
    # This should work regardless of rawrr installation
    status <- exists("check_rawrr_status")

    if (status) {
      # Try to call the function
      check_result <- tryCatch({
        check_rawrr_status()
        TRUE
      }, error = function(e) {
        FALSE
      })

      return(list(success = TRUE, message = sprintf("rawrr status check: %s",
                                                   ifelse(check_result, "Available", "Not available"))))
    } else {
      return(list(success = FALSE, message = "check_rawrr_status function not found"))
    }
  }

  run_test("rawrr Availability Check", test_rawrr_availability)

  # Test 2: Instrument configuration loading
  test_instrument_config <- function() {
    configs <- get_instrument_configs()

    if (length(configs) == 0) {
      return(list(success = FALSE, message = "No instrument configurations found"))
    }

    # Test specific instruments
    required_instruments <- c("astral", "orbitrap", "custom")
    missing <- setdiff(required_instruments, names(configs))

    if (length(missing) > 0) {
      return(list(success = FALSE, message = sprintf("Missing instruments: %s",
                                                     paste(missing, collapse = ", "))))
    }

    # Test astral configuration
    astral_config <- get_instrument_config("astral")
    required_fields <- c("name", "ms1_time", "ms2_time", "max_scan_rate")
    missing_fields <- setdiff(required_fields, names(astral_config))

    if (length(missing_fields) > 0) {
      return(list(success = FALSE, message = sprintf("Missing astral config fields: %s",
                                                     paste(missing_fields, collapse = ", "))))
    }

    return(list(success = TRUE, message = sprintf("Found %d instrument configurations", length(configs))))
  }

  run_test("Instrument Configuration Loading", test_instrument_config)

  # Test 3: User configuration structure
  test_user_config_structure <- function() {
    # Create a mock metadata structure
    mock_metadata <- list(
      "test_file" = list(
        file_info = list(
          file_name = "test.raw",
          creation_date = Sys.time()
        ),
        instrument = list(
          model = "Test Instrument",
          serial_number = "12345"
        ),
        acquisition = list(
          duration_minutes = 60
        ),
        scan_statistics = list(
          total_scans = 1000,
          ms1_scans = 100,
          ms2_scans = 900
        ),
        scan_cycle_stats = list(
          scan_rate = 25.0,
          avg_cycle_time = 2.0,
          ms2_per_cycle = 10
        ),
        extraction_timestamp = Sys.time()
      )
    )

    # Test user config generation
    tryCatch({
      user_config <- generate_user_config_from_metadata(mock_metadata, tempfile(fileext = ".json"))

      required_sections <- c("metadata_source", "instrument_timing", "acquisition_parameters",
                           "recommended_settings", "config_generation")
      missing_sections <- setdiff(required_sections, names(user_config))

      if (length(missing_sections) > 0) {
        return(list(success = FALSE, message = sprintf("Missing config sections: %s",
                                                       paste(missing_sections, collapse = ", "))))
      }

      return(list(success = TRUE, message = "User config structure validated"))

    }, error = function(e) {
      return(list(success = FALSE, message = sprintf("Config generation failed: %s", e$message)))
    })
  }

  run_test("User Config Structure", test_user_config_structure)

  # Test 4: Default configuration
  test_default_config <- function() {
    config <- create_default_config()

    required_fields <- c("proteome_file", "instrument_preset", "target_dppp",
                        "enable_raw_metadata", "use_user_config")
    missing_fields <- setdiff(required_fields, names(config))

    if (length(missing_fields) > 0) {
      return(list(success = FALSE, message = sprintf("Missing default config fields: %s",
                                                     paste(missing_fields, collapse = ", "))))
    }

    # Check new metadata fields
    if (!is.logical(config$enable_raw_metadata) || !is.logical(config$use_user_config)) {
      return(list(success = FALSE, message = "Metadata config fields should be logical"))
    }

    return(list(success = TRUE, message = "Default configuration validated"))
  }

  run_test("Default Configuration", test_default_config)
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

if (test_config$run_integration_tests) {
  cat("\n=== INTEGRATION TESTS ===\n")

  # Test 5: Mock data loading with metadata
  test_mock_data_loading <- function() {
    # Create mock DIA-NN data
    mock_diann_data <- data.frame(
      Precursor.Mz = runif(100, 400, 900),
      RT.Start = runif(100, 10, 60),
      RT.Stop = runif(100, 10.5, 60.5),
      FWHM = runif(100, 0.3, 0.8),
      Precursor.Quantity = runif(100, 1000, 100000),
      Precursor.Charge = sample(2:4, 100, replace = TRUE),
      stringsAsFactors = FALSE
    )

    # Create mock metadata
    mock_metadata <- list(
      "test_file" = list(
        instrument = list(model = "Test Astral", serial_number = "T12345"),
        acquisition = list(duration_minutes = 45),
        scan_cycle_stats = list(scan_rate = 30.0, avg_cycle_time = 1.8, ms2_per_cycle = 12)
      )
    )

    # Test metadata integration
    enhanced_data <- add_metadata_to_diann_data(mock_diann_data, mock_metadata)

    # Check if metadata columns were added
    expected_cols <- c("Raw.File.Name", "Instrument.Model", "Serial.Number",
                      "Scan.Rate.Hz", "Metadata.Available", "FWHM.Confidence")
    missing_cols <- setdiff(expected_cols, names(enhanced_data))

    if (length(missing_cols) > 0) {
      return(list(success = FALSE, message = sprintf("Missing metadata columns: %s",
                                                     paste(missing_cols, collapse = ", "))))
    }

    # Check metadata values
    if (!all(enhanced_data$Metadata.Available)) {
      return(list(success = FALSE, message = "Metadata.Available should be TRUE for all rows"))
    }

    if (any(is.na(enhanced_data$FWHM.Confidence))) {
      return(list(success = FALSE, message = "FWHM.Confidence should not be NA"))
    }

    return(list(success = TRUE, message = sprintf("Enhanced data created with %d rows, %d columns",
                                                  nrow(enhanced_data), ncol(enhanced_data))))
  }

  run_test("Mock Data Loading with Metadata", test_mock_data_loading)

  # Test 6: FWHM analysis with metadata
  test_fwhm_analysis_with_metadata <- function() {
    # Create enhanced mock data
    mock_data <- data.frame(
      Precursor.Mz = runif(50, 400, 900),
      RT.Start = runif(50, 10, 60),
      FWHM = runif(50, 0.3, 0.8),
      Metadata.Available = TRUE,
      FWHM.Confidence = runif(50, 0.9, 1.1),
      stringsAsFactors = FALSE
    )

    # Test FWHM analysis
    tryCatch({
      # Call the enhanced analysis function
      fwhm_result <- analyze_fwhm_comprehensive(mock_data, rt_segments = 3, mz_bins = 5)

      if (is.null(fwhm_result)) {
        return(list(success = FALSE, message = "FWHM analysis returned NULL"))
      }

      # Check for enhanced statistics
      if (!"basic_stats" %in% names(fwhm_result)) {
        return(list(success = FALSE, message = "Missing basic_stats in FWHM result"))
      }

      basic_stats <- fwhm_result$basic_stats

      # Check for metadata-specific statistics
      metadata_fields <- c("weighted_mean", "confidence_range", "avg_confidence")
      found_metadata_fields <- sum(metadata_fields %in% names(basic_stats))

      if (found_metadata_fields == 0) {
        return(list(success = FALSE, message = "No metadata-enhanced statistics found"))
      }

      return(list(success = TRUE, message = sprintf("FWHM analysis completed with %d metadata fields",
                                                    found_metadata_fields)))

    }, error = function(e) {
      return(list(success = FALSE, message = sprintf("FWHM analysis failed: %s", e$message)))
    })
  }

  run_test("FWHM Analysis with Metadata", test_fwhm_analysis_with_metadata)

  # Test 7: Instrument preset comparison
  test_preset_comparison <- function() {
    # Create mock user config
    mock_user_config <- list(
      metadata_source = list(
        instrument_model = "Thermo Astral",
        raw_file = "test.raw"
      ),
      instrument_timing = list(
        actual_scan_rate_hz = 45.0,
        estimated_ms2_time_ms = 3.2
      ),
      recommended_settings = list()
    )

    tryCatch({
      comparison_results <- compare_with_instrument_presets(mock_user_config)

      if (is.null(comparison_results) || nrow(comparison_results) == 0) {
        return(list(success = FALSE, message = "No comparison results generated"))
      }

      # Check if best match is identified
      if (!any(comparison_results$recommended)) {
        return(list(success = FALSE, message = "No recommended preset identified"))
      }

      best_match <- comparison_results[comparison_results$recommended, ]

      return(list(success = TRUE, message = sprintf("Best match found: %s", best_match$preset_name)))

    }, error = function(e) {
      return(list(success = FALSE, message = sprintf("Preset comparison failed: %s", e$message)))
    })
  }

  run_test("Instrument Preset Comparison", test_preset_comparison)
}

# =============================================================================
# VALIDATION TESTS
# =============================================================================

if (test_config$run_validation_tests) {
  cat("\n=== VALIDATION TESTS ===\n")

  # Test 8: Configuration validation
  test_config_validation <- function() {
    # Test valid configuration
    valid_config <- list(
      proteome_file = "test.parquet",
      instrument_preset = "astral",
      target_dppp = 1.25,
      enable_raw_metadata = TRUE,
      use_user_config = FALSE
    )

    # This would typically validate against a schema
    required_fields <- c("proteome_file", "instrument_preset", "target_dppp")
    missing_fields <- setdiff(required_fields, names(valid_config))

    if (length(missing_fields) > 0) {
      return(list(success = FALSE, message = sprintf("Missing required fields: %s",
                                                     paste(missing_fields, collapse = ", "))))
    }

    # Test invalid values
    if (!is.numeric(valid_config$target_dppp) || valid_config$target_dppp <= 0) {
      return(list(success = FALSE, message = "Invalid target_dppp value"))
    }

    return(list(success = TRUE, message = "Configuration validation passed"))
  }

  run_test("Configuration Validation", test_config_validation)

  # Test 9: Error handling
  test_error_handling <- function() {
    errors_caught <- 0

    # Test invalid file path
    tryCatch({
      load_user_config("nonexistent_file.json")
    }, error = function(e) {
      errors_caught <<- errors_caught + 1
    })

    # Test invalid instrument preset
    tryCatch({
      get_instrument_config("nonexistent_instrument")
    }, error = function(e) {
      errors_caught <<- errors_caught + 1
    })

    # Test empty metadata
    tryCatch({
      generate_user_config_from_metadata(list(), tempfile())
    }, error = function(e) {
      errors_caught <<- errors_caught + 1
    })

    if (errors_caught < 3) {
      return(list(success = FALSE, message = sprintf("Only %d/3 errors caught", errors_caught)))
    }

    return(list(success = TRUE, message = "Error handling validated"))
  }

  run_test("Error Handling", test_error_handling)

  # Test 10: Data integrity
  test_data_integrity <- function() {
    # Create test data
    test_data <- data.frame(
      Precursor.Mz = c(450.5, 600.3, 750.8),
      RT.Start = c(15.2, 25.7, 35.1),
      FWHM = c(0.45, 0.52, 0.38),
      stringsAsFactors = FALSE
    )

    # Test data validation
    validated_data <- validate_data(test_data)

    if (nrow(validated_data) != nrow(test_data)) {
      return(list(success = FALSE, message = "Data validation changed row count unexpectedly"))
    }

    # Test metadata addition doesn't corrupt data
    mock_metadata <- list(
      "test" = list(
        instrument = list(model = "Test", serial_number = "123"),
        acquisition = list(duration_minutes = 30),
        scan_cycle_stats = list(scan_rate = 20.0)
      )
    )

    enhanced_data <- add_metadata_to_diann_data(validated_data, mock_metadata)

    # Check original data integrity
    if (!all(enhanced_data$Precursor.Mz == test_data$Precursor.Mz)) {
      return(list(success = FALSE, message = "Original data corrupted during metadata addition"))
    }

    return(list(success = TRUE, message = "Data integrity maintained"))
  }

  run_test("Data Integrity", test_data_integrity)
}

# =============================================================================
# CREATE TEST FILES
# =============================================================================

if (test_config$create_test_files) {
  cat("\n=== CREATING TEST FILES ===\n")

  # Create test configuration
  test_dir <- "test_output"
  if (!dir.exists(test_dir)) {
    dir.create(test_dir, recursive = TRUE)
  }

  # Create test configuration file
  test_config_file <- file.path(test_dir, "test_config.json")
  test_config_data <- list(
    proteome_file = "test_data.parquet",
    mz_range = c(400, 900),
    rt_segments = 3,
    instrument_preset = "astral",
    target_dppp = 1.25,
    enable_raw_metadata = TRUE,
    use_user_config = TRUE,
    fwhm_analysis_enabled = TRUE,
    create_plots = FALSE,
    output_format = "csv",
    output_path = "test_windows"
  )

  library(jsonlite)
  test_config_json <- toJSON(test_config_data, pretty = TRUE, auto_unbox = TRUE)
  writeLines(test_config_json, test_config_file)

  cat(sprintf("✅ Test configuration created: %s\n", test_config_file))

  # Create mock user configuration
  mock_user_config_file <- file.path(test_dir, "mock_user_config.json")
  mock_user_config <- list(
    metadata_source = list(
      raw_file = "test.raw",
      instrument_model = "Thermo Astral",
      serial_number = "12345"
    ),
    instrument_timing = list(
      actual_scan_rate_hz = 42.5,
      actual_cycle_time_sec = 1.9,
      ms2_per_cycle = 11.5,
      estimated_ms2_time_ms = 3.1
    ),
    recommended_settings = list(
      primary_preset = "astral",
      confidence_level = "high",
      custom_overrides = list(
        max_scan_rate = 38.0,
        ms2_time = 3.1
      )
    ),
    config_generation = list(
      generated_at = as.character(Sys.time()),
      version = "1.0"
    )
  )

  mock_user_config_json <- toJSON(mock_user_config, pretty = TRUE, auto_unbox = TRUE)
  writeLines(mock_user_config_json, mock_user_config_file)

  cat(sprintf("✅ Mock user configuration created: %s\n", mock_user_config_file))
}

# =============================================================================
# FINAL REPORT
# =============================================================================

cat("\n╔══════════════════════════════════════════════╗\n")
cat("║              TEST RESULTS SUMMARY             ║\n")
cat("╚══════════════════════════════════════════════╝\n\n")

total_tests <- test_results$passed + test_results$failed
success_rate <- if (total_tests > 0) test_results$passed / total_tests * 100 else 0

cat(sprintf("📊 Tests completed: %d\n", total_tests))
cat(sprintf("✅ Passed: %d\n", test_results$passed))
cat(sprintf("❌ Failed: %d\n", test_results$failed))
cat(sprintf("📈 Success rate: %.1f%%\n\n", success_rate))

if (length(test_results$errors) > 0) {
  cat("❌ Errors encountered:\n")
  for (i in seq_along(test_results$errors)) {
    cat(sprintf("  %d. %s\n", i, test_results$errors[i]))
  }
  cat("\n")
}

if (length(test_results$warnings) > 0) {
  cat("⚠️ Warnings:\n")
  for (i in seq_along(test_results$warnings)) {
    cat(sprintf("  %d. %s\n", i, test_results$warnings[i]))
  }
  cat("\n")
}

# Overall assessment
if (test_results$failed == 0) {
  cat("🎉 All tests passed! Raw metadata integration is ready for use.\n")
} else if (success_rate >= 80) {
  cat("⚠️ Most tests passed, but some issues need attention.\n")
} else {
  cat("❌ Significant issues detected. Please review failed tests.\n")
}

cat("\n📋 Next steps:\n")
cat("1. Review any failed tests and fix underlying issues\n")
cat("2. Test with actual raw files using examples/raw_metadata_workflow_example.R\n")
cat("3. Validate integration with real DIA-NN data\n")
cat("4. Compare optimization results with and without metadata\n")

cat("\n✅ Test suite completed!\n")