# dynamicDIA_example.R - Example usage and testing for dynamicDIA

# Load the main functions
source("dynamicDIA.R")

# ============================================================================
# Example Usage Functions
# ============================================================================

#' Example workflow using sample data
#'
#' @param use_sample_data Whether to use built-in sample data
#' @return Results from dynamic DIA method generation
example_dynamic_dia_workflow <- function(use_sample_data = TRUE) {

  cat("🧪 Dynamic DIA Example Workflow\n")
  cat("================================\n\n")

  # Check dependencies
  check_dependencies()

  if (use_sample_data) {
    # Create sample peptide data
    cat("📊 Creating sample peptide data...\n")
    peptide_data <- create_sample_peptide_data()
    cat(sprintf("   • Generated %d peptides\n", nrow(peptide_data)))
    cat(sprintf("   • RT range: %.1f - %.1f min\n", min(peptide_data$rt), max(peptide_data$rt)))
    cat(sprintf("   • m/z range: %.1f - %.1f\n\n", min(peptide_data$mz), max(peptide_data$mz)))
  } else {
    # Load real data (user should provide file path)
    data_file <- file.choose()
    peptide_data <- read_csv(data_file)
    cat(sprintf("📂 Loaded %d peptides from %s\n\n", nrow(peptide_data), basename(data_file)))
  }

  # Generate dynamic DIA method
  results <- generate_dynamic_dia_method(
    peptide_data = peptide_data,
    isolation_width_th = 8,
    instrument_speed_hz = 14.6,
    cycle_time_sec = 2.5,
    smoothing_method = "savgol",
    output_file = "example_scheduled_dia_method.csv"
  )

  cat("\n🔍 Comparison of smoothing methods:\n")
  compare_smoothing_methods(peptide_data)

  return(results)
}

#' Create sample peptide data for testing
#'
#' @param n_peptides Number of peptides to generate
#' @return Data frame with rt and mz columns
create_sample_peptide_data <- function(n_peptides = 2000) {

  set.seed(42)  # For reproducible results

  # Generate RT values with realistic distribution
  rt_values <- c(
    rnorm(n_peptides * 0.3, mean = 25, sd = 5),   # Early elution
    rnorm(n_peptides * 0.4, mean = 45, sd = 8),   # Main peak
    rnorm(n_peptides * 0.3, mean = 70, sd = 6)    # Late elution
  )

  # Generate m/z values with realistic distribution
  mz_values <- c(
    rnorm(n_peptides * 0.2, mean = 450, sd = 30),   # Low m/z
    rnorm(n_peptides * 0.6, mean = 650, sd = 100),  # Mid m/z
    rnorm(n_peptides * 0.2, mean = 850, sd = 50)    # High m/z
  )

  # Ensure we have the right number of peptides
  rt_values <- rt_values[1:n_peptides]
  mz_values <- mz_values[1:n_peptides]

  # Filter to realistic ranges
  valid_indices <- rt_values > 10 & rt_values < 90 & mz_values > 300 & mz_values < 1200
  rt_values <- rt_values[valid_indices]
  mz_values <- mz_values[valid_indices]

  return(data.frame(
    rt = rt_values,
    mz = mz_values
  ))
}

#' Compare different smoothing methods
#'
#' @param peptide_data Sample peptide data
#' @return Comparison results
compare_smoothing_methods <- function(peptide_data) {

  smoothing_methods <- c("savgol", "movav", "gaussian")

  # Create histogram once
  hist_result <- create_peptide_histogram(peptide_data)

  comparison_results <- list()

  for (method in smoothing_methods) {
    cat(sprintf("   Testing %s smoothing...\n", method))

    start_time <- Sys.time()

    optimization_result <- compute_precursor_locations(
      isolation_width_th = 8,
      instrument_speed_hz = 14.6,
      cycle_time_sec = 2.5,
      hist = hist_result$hist,
      mz_axis = hist_result$mz_axis,
      smoothing_method = method
    )

    end_time <- Sys.time()
    execution_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

    comparison_results[[method]] <- list(
      total_peptides = optimization_result$total_peptides,
      execution_time = execution_time,
      mz_range = max(optimization_result$high_mz_values) - min(optimization_result$low_mz_values)
    )

    cat(sprintf("     • Peptides covered: %d\n", optimization_result$total_peptides))
    cat(sprintf("     • Execution time: %.3f seconds\n", execution_time))
  }

  return(comparison_results)
}

# ============================================================================
# Testing Functions
# ============================================================================

#' Run comprehensive tests for dynamicDIA functions
#'
#' @return Test results summary
run_dynamicdia_tests <- function() {

  cat("🧪 Running dynamicDIA Tests\n")
  cat("===========================\n\n")

  test_results <- list()

  # Test 1: Basic functionality
  cat("Test 1: Basic functionality...\n")
  test_results$basic <- test_basic_functionality()

  # Test 2: Edge cases
  cat("Test 2: Edge cases...\n")
  test_results$edge_cases <- test_edge_cases()

  # Test 3: Performance
  cat("Test 3: Performance...\n")
  test_results$performance <- test_performance()

  # Test 4: Smoothing methods
  cat("Test 4: Smoothing methods...\n")
  test_results$smoothing <- test_smoothing_methods()

  # Summary
  cat("\n📋 Test Summary:\n")
  passed_tests <- sum(sapply(test_results, function(x) x$passed))
  total_tests <- length(test_results)
  cat(sprintf("   • Passed: %d/%d tests\n", passed_tests, total_tests))

  if (passed_tests == total_tests) {
    cat("   ✅ All tests passed!\n")
  } else {
    cat("   ❌ Some tests failed. Check individual results.\n")
  }

  return(test_results)
}

#' Test basic functionality
test_basic_functionality <- function() {

  tryCatch({
    # Create small sample data
    peptide_data <- create_sample_peptide_data(n_peptides = 100)

    # Run basic workflow
    results <- generate_dynamic_dia_method(
      peptide_data = peptide_data,
      output_file = "test_method.csv"
    )

    # Check results structure
    required_elements <- c("histogram", "optimization", "scheduled_scans", "parameters")
    has_all_elements <- all(required_elements %in% names(results))

    # Check if file was created
    file_created <- file.exists("test_method.csv")

    # Clean up
    if (file_created) file.remove("test_method.csv")

    list(passed = has_all_elements && file_created, details = "Basic workflow successful")

  }, error = function(e) {
    list(passed = FALSE, details = paste("Error:", e$message))
  })
}

#' Test edge cases
test_edge_cases <- function() {

  tryCatch({
    # Test with minimal data
    minimal_data <- data.frame(rt = c(20, 30, 40), mz = c(500, 600, 700))

    results <- generate_dynamic_dia_method(
      peptide_data = minimal_data,
      rt_bin_size_min = 5,
      mz_bin_size = 50
    )

    # Test with single RT bin
    single_rt_data <- data.frame(rt = rep(25, 10), mz = seq(400, 800, length.out = 10))

    results2 <- generate_dynamic_dia_method(
      peptide_data = single_rt_data,
      rt_bin_size_min = 10,
      mz_bin_size = 25
    )

    list(passed = TRUE, details = "Edge cases handled correctly")

  }, error = function(e) {
    list(passed = FALSE, details = paste("Edge case error:", e$message))
  })
}

#' Test performance with larger datasets
test_performance <- function() {

  tryCatch({
    # Test with larger dataset
    start_time <- Sys.time()

    large_peptide_data <- create_sample_peptide_data(n_peptides = 5000)

    results <- generate_dynamic_dia_method(
      peptide_data = large_peptide_data,
      smoothing_method = "savgol"
    )

    end_time <- Sys.time()
    execution_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

    # Performance should be reasonable (< 30 seconds for 5000 peptides)
    performance_ok <- execution_time < 30

    list(
      passed = performance_ok,
      details = sprintf("Processed 5000 peptides in %.2f seconds", execution_time)
    )

  }, error = function(e) {
    list(passed = FALSE, details = paste("Performance test error:", e$message))
  })
}

#' Test different smoothing methods
test_smoothing_methods <- function() {

  tryCatch({
    peptide_data <- create_sample_peptide_data(n_peptides = 500)
    smoothing_methods <- c("savgol", "movav", "gaussian")

    all_methods_work <- TRUE

    for (method in smoothing_methods) {
      result <- generate_dynamic_dia_method(
        peptide_data = peptide_data,
        smoothing_method = method
      )

      if (is.null(result) || result$optimization$total_peptides <= 0) {
        all_methods_work <- FALSE
        break
      }
    }

    list(
      passed = all_methods_work,
      details = paste("Tested smoothing methods:", paste(smoothing_methods, collapse = ", "))
    )

  }, error = function(e) {
    list(passed = FALSE, details = paste("Smoothing test error:", e$message))
  })
}

# ============================================================================
# Utility Functions for Examples
# ============================================================================

#' Print method summary in a nice format
#'
#' @param results Results from generate_dynamic_dia_method
print_method_summary <- function(results) {

  cat("\n📊 Dynamic DIA Method Summary\n")
  cat("==============================\n")
  cat(sprintf("Isolation Width: %d Th\n", results$parameters$isolation_width_th))
  cat(sprintf("Instrument Speed: %.1f Hz\n", results$parameters$instrument_speed_hz))
  cat(sprintf("Cycle Time: %.1f seconds\n", results$parameters$cycle_time_sec))
  cat(sprintf("Smoothing Method: %s\n", results$parameters$smoothing_method))
  cat("\n")
  cat(sprintf("Total Peptides Covered: %d\n", results$optimization$total_peptides))
  cat(sprintf("Number of Time Segments: %d\n", length(results$scheduled_scans)))
  cat(sprintf("RT Range: %.1f - %.1f min\n",
              min(results$histogram$rt_axis), max(results$histogram$rt_axis)))
  cat(sprintf("m/z Range: %.1f - %.1f\n",
              min(results$optimization$low_mz_values),
              max(results$optimization$high_mz_values)))
}

# ============================================================================
# Quick Start Function
# ============================================================================

#' Quick start function for new users
#'
#' @param data_file Path to peptide data file (optional)
quick_start <- function(data_file = NULL) {

  cat("🚀 Quick Start: Dynamic DIA Method Generation\n")
  cat("==============================================\n\n")

  cat("This function will:\n")
  cat("1. Check and install required packages\n")
  cat("2. Load or create sample peptide data\n")
  cat("3. Generate an optimized DIA method\n")
  cat("4. Save the method to a CSV file\n")
  cat("5. Display a summary of results\n\n")

  # Run the example workflow
  if (is.null(data_file)) {
    results <- example_dynamic_dia_workflow(use_sample_data = TRUE)
  } else {
    peptide_data <- read_csv(data_file)
    results <- generate_dynamic_dia_method(
      peptide_data = peptide_data,
      output_file = "my_dynamic_dia_method.csv"
    )
  }

  # Print summary
  print_method_summary(results)

  cat("\n✅ Quick start complete!\n")
  cat("Check 'example_scheduled_dia_method.csv' for the generated method.\n")

  return(results)
}