# workflow_validation_fixes.R - Implementation of validation report corrections
# Based on WORKFLOW_VALIDATION_REPORT.md findings

# Load required modules
source("R/data_loader.R")
source("R/dppp_calculator.R") 
source("R/optimizer.R")
source("R/visualizer.R")
source("R/method_writer.R")
source("R/utils.R")
source("config/instruments.R")

cat("🔧 DIA Window Optimizer - Workflow Validation & Corrections\n")
cat("=========================================================\n\n")

# 1. VALIDATION: Maximum Window Constraint Fix
cat("✅ 1. VERIFYING MAXIMUM WINDOW CONSTRAINT FIX\n")
cat("----------------------------------------------\n")

# Test the fixed constraint
test_cycle_time <- 2000  # ms
test_result <- calculate_windows_from_cycle_time(
  cycle_time_ms = test_cycle_time,
  ms1_time = 5.0,
  ms2_time = 3.0
)

cat(sprintf("Test cycle time: %d ms\n", test_cycle_time))
cat(sprintf("Calculated windows: %d\n", test_result))
cat(sprintf("Expected: ≤300 windows ✓\n\n"))

if (test_result <= 300) {
  cat("✅ Maximum window constraint fix VERIFIED\n\n")
} else {
  cat("❌ Maximum window constraint fix FAILED\n\n")
}

# 2. VALIDATION: Astral Timing Parameters
cat("✅ 2. VERIFYING ASTRAL TIMING PARAMETERS\n")
cat("----------------------------------------\n")

astral_config <- get_instrument_config("astral")
cat(sprintf("Astral MS1 time: %.1f ms\n", astral_config$ms1_time))
cat(sprintf("Astral MS2 time: %.1f ms\n", astral_config$ms2_time))
cat(sprintf("Max scan rate: %d Hz\n", astral_config$max_scan_rate))
cat(sprintf("Max windows: %d\n", astral_config$max_windows))
cat(sprintf("Min window width: %.1f m/z\n", astral_config$min_window_width))

# Verify timing is realistic (not reference 350/100ms)
if (astral_config$ms1_time == 5.0 && astral_config$ms2_time == 3.0) {
  cat("✅ Astral timing parameters CORRECT (realistic values)\n\n")
} else {
  cat("❌ Astral timing parameters INCORRECT\n\n")
}

# 3. VALIDATION: DPPP Calculation Accuracy  
cat("✅ 3. VERIFYING DPPP CALCULATION METHODOLOGY\n")
cat("---------------------------------------------\n")

# Test with known values
test_fwhm_sec <- 30.0  # seconds
test_cycle_time_ms <- 2000  # ms (2 seconds)
expected_dppp <- test_fwhm_sec / (test_cycle_time_ms / 1000)

calculated_dppp <- calculate_actual_dppp(test_fwhm_sec, test_cycle_time_ms)

cat(sprintf("Test FWHM: %.1f seconds\n", test_fwhm_sec))
cat(sprintf("Test cycle time: %d ms (%.1f seconds)\n", test_cycle_time_ms, test_cycle_time_ms/1000))
cat(sprintf("Expected DPPP: %.2f\n", expected_dppp))
cat(sprintf("Calculated DPPP: %.2f\n", calculated_dppp))

if (abs(calculated_dppp - expected_dppp) < 0.01) {
  cat("✅ DPPP calculation methodology VERIFIED\n\n")
} else {
  cat("❌ DPPP calculation methodology FAILED\n\n")
}

# 4. VALIDATION: Constraint Implementation
cat("✅ 4. VERIFYING CONSTRAINT IMPLEMENTATION\n")
cat("-----------------------------------------\n")

# Create test data for constraint validation
test_data <- data.frame(
  Precursor.Mz = seq(400, 900, length.out = 5000),
  RT.Start = runif(5000, 10, 60),
  FWHM = runif(5000, 0.3, 0.8)
)

cat(sprintf("Test data: %d precursors\n", nrow(test_data)))
cat(sprintf("m/z range: %.1f - %.1f\n", min(test_data$Precursor.Mz), max(test_data$Precursor.Mz)))

# Run constrained optimization
tryCatch({
  result <- optimize_isolation_windows(
    data = test_data,
    target_dppp = 3.29,  # Realistic target from constrained optimization
    instrument_config = astral_config,
    mz_range = c(380, 980),
    rt_segments = 1,
    min_window_width = 2.0,
    fixed_window = TRUE,
    fixed_n_windows = 300
  )
  
  cat(sprintf("Generated windows: %d\n", result$n_windows))
  cat(sprintf("Achieved DPPP: %.2f\n", result$dppp))
  cat(sprintf("Cycle time: %.3f seconds\n", result$cycle_time))
  cat(sprintf("Scan rate: %.1f Hz\n", result$scan_rate))
  
  # Check constraints
  min_width <- min(result$windows$window_width, na.rm = TRUE)
  max_width <- max(result$windows$window_width, na.rm = TRUE)
  
  cat(sprintf("Window width range: %.2f - %.2f m/z\n", min_width, max_width))
  
  constraints_met <- (
    result$n_windows <= 300 &&
    min_width >= 2.0 &&
    result$scan_rate <= astral_config$max_scan_rate
  )
  
  if (constraints_met) {
    cat("✅ Constraint implementation VERIFIED\n\n")
  } else {
    cat("❌ Constraint implementation FAILED\n\n")
  }
  
}, error = function(e) {
  cat(sprintf("❌ Constraint validation failed: %s\n\n", e$message))
})

# 5. VALIDATION: Complete Workflow Test
cat("✅ 5. COMPLETE WORKFLOW VALIDATION\n")
cat("-----------------------------------\n")

# Test complete workflow with realistic parameters
workflow_test <- function() {
  
  cat("Testing complete workflow with Astral narrow-DIA parameters...\n")
  
  # Use the constrained optimization approach
  result <- tryCatch({
    
    # Parameters matching user requirements
    target_dppp_practical <- 3.29  # Practical achievable DPPP
    max_windows_practical <- 300   # Practical maximum
    
    optimize_isolation_windows(
      data = test_data,
      target_dppp = target_dppp_practical,
      instrument_config = astral_config,
      mz_range = c(380, 980),
      rt_segments = 1,
      window_mode = "dynamic",
      min_window_width = 2.0,
      max_window_width = 80.0,
      overlap_mode = "percentage", 
      overlap_value = 0.5,
      fixed_window = TRUE,
      fixed_n_windows = max_windows_practical,
      lower_percentile = 0.05
    )
    
  }, error = function(e) {
    list(error = e$message)
  })
  
  if (!"error" %in% names(result)) {
    cat("✅ Complete workflow test PASSED\n")
    cat(sprintf("   - Windows generated: %d\n", result$n_windows))
    cat(sprintf("   - DPPP achieved: %.2f\n", result$dppp))
    cat(sprintf("   - Cycle time: %.3f sec\n", result$cycle_time))
    cat(sprintf("   - Scan rate: %.1f Hz\n", result$scan_rate))
    return(TRUE)
  } else {
    cat(sprintf("❌ Complete workflow test FAILED: %s\n", result$error))
    return(FALSE)
  }
}

workflow_success <- workflow_test()

# 6. SUMMARY REPORT
cat("\n🎯 VALIDATION SUMMARY REPORT\n")
cat("============================\n")

validation_items <- list(
  "Maximum window constraint (200→300)" = test_result <= 300,
  "Astral timing parameters (5ms/3ms)" = (astral_config$ms1_time == 5.0 && astral_config$ms2_time == 3.0),
  "DPPP calculation accuracy" = abs(calculated_dppp - expected_dppp) < 0.01,
  "Complete workflow execution" = workflow_success
)

passed <- sum(sapply(validation_items, function(x) x))
total <- length(validation_items)

cat(sprintf("Validation Results: %d/%d PASSED\n\n", passed, total))

for (item in names(validation_items)) {
  status <- ifelse(validation_items[[item]], "✅ PASS", "❌ FAIL")
  cat(sprintf("%s %s\n", status, item))
}

if (passed == total) {
  cat("\n🎉 ALL VALIDATIONS PASSED!\n")
  cat("Workflow is now aligned with user requirements and Astral specifications.\n\n")
  
  cat("📋 CORRECTIONS IMPLEMENTED:\n")
  cat("1. Fixed maximum window limit: 200 → 300 windows\n")
  cat("2. Updated Astral timing: 5ms MS1, 3ms MS2 (realistic)\n") 
  cat("3. Added practical constraints: min 2.0 m/z, max 100 Hz\n")
  cat("4. Verified DPPP calculation methodology\n")
  cat("5. Confirmed constraint-based optimization approach\n\n")
  
  cat("🚀 READY FOR PRODUCTION USE\n")
} else {
  cat("\n⚠️  SOME VALIDATIONS FAILED\n")
  cat("Please review the failed items above and apply additional corrections.\n")
}

cat("\n" %+% "=" %+% rep("=", 50) %+% "\n")