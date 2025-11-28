# Test Script: Refactored Module Loading and Integration
# Purpose: Verify all refactored modules load correctly and function as expected
# Version: 1.0
# Date: 2025-11-28

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Refactored Module Loading Test Suite                        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Set up test environment
setwd("d:/Projects/dia_window_optimizer")
test_results <- list()
errors <- list()

# =============================================================================
# Test 1: Load Core Dependencies
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 1: Loading Core Dependencies\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

required_packages <- c("arrow", "dplyr", "ggplot2", "yaml", "tidyr",
                       "viridis", "scales", "prospectr", "ggridges", "gridExtra")

for (pkg in required_packages) {
  tryCatch({
    suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    cat(sprintf("  ✅ %s loaded\n", pkg))
    test_results[["packages"]][[pkg]] <- "PASS"
  }, error = function(e) {
    cat(sprintf("  ❌ %s failed: %s\n", pkg, e$message))
    test_results[["packages"]][[pkg]] <- "FAIL"
    errors[[paste0("package_", pkg)]] <- e$message
  })
}

# =============================================================================
# Test 2: Load S3 Classes (Central Definition)
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 2: Loading S3 Class Definitions\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

tryCatch({
  source("R/s3_classes.R")
  cat("  ✅ S3 classes loaded (R/s3_classes.R)\n")

  # Verify class constructors exist
  constructors <- c("new_ValidatedData", "new_OptimizationPlan",
                    "new_OptimizedWindows", "new_VisualizationResult")
  for (constructor in constructors) {
    if (exists(constructor)) {
      cat(sprintf("    ✓ %s() available\n", constructor))
    } else {
      cat(sprintf("    ✗ %s() missing\n", constructor))
      errors[[paste0("constructor_", constructor)]] <- "Function not found"
    }
  }

  test_results[["s3_classes"]] <- "PASS"
}, error = function(e) {
  cat(sprintf("  ❌ S3 classes failed: %s\n", e$message))
  test_results[["s3_classes"]] <- "FAIL"
  errors[["s3_classes"]] <- e$message
})

# =============================================================================
# Test 3: Load Common Utilities
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 3: Loading Common Utilities\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

tryCatch({
  source("R/utils_common.R")
  cat("  ✅ Common utilities loaded (R/utils_common.R)\n")

  # Verify key functions
  key_functions <- c("print_header", "calculate_dppp", "calculate_summary_stats",
                     "count_precursors_in_windows")
  for (func in key_functions) {
    if (exists(func)) {
      cat(sprintf("    ✓ %s() available\n", func))
    } else {
      cat(sprintf("    ✗ %s() missing\n", func))
      errors[[paste0("utils_", func)]] <- "Function not found"
    }
  }

  test_results[["utils_common"]] <- "PASS"
}, error = function(e) {
  cat(sprintf("  ❌ Common utilities failed: %s\n", e$message))
  test_results[["utils_common"]] <- "FAIL"
  errors[["utils_common"]] <- e$message
})

# =============================================================================
# Test 4: Load Smoothing Utilities (with fallback)
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 4: Loading Smoothing Utilities\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

tryCatch({
  source("R/smoothing_utils.R")
  cat("  ✅ Smoothing utilities loaded (R/smoothing_utils.R)\n")

  # Verify smoothing functions
  smoothing_functions <- c("smooth_savgol", "smooth_mz_boundaries")
  for (func in smoothing_functions) {
    if (exists(func)) {
      cat(sprintf("    ✓ %s() available\n", func))
    } else {
      cat(sprintf("    ✗ %s() missing\n", func))
      errors[[paste0("smoothing_", func)]] <- "Function not found"
    }
  }

  test_results[["smoothing_utils"]] <- "PASS"
}, error = function(e) {
  cat(sprintf("  ❌ Smoothing utilities failed: %s\n", e$message))
  test_results[["smoothing_utils"]] <- "FAIL"
  errors[["smoothing_utils"]] <- e$message
})

# =============================================================================
# Test 5: Load Stage 1 (Data Validation)
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 5: Loading Stage 1 (Data Validation)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

tryCatch({
  source("R/stage1_data_validation.R")
  cat("  ✅ Stage 1 loaded (R/stage1_data_validation.R)\n")

  if (exists("create_validated_dataset")) {
    cat("    ✓ create_validated_dataset() available\n")
  } else {
    cat("    ✗ create_validated_dataset() missing\n")
    errors[["stage1_main"]] <- "Main function not found"
  }

  test_results[["stage1"]] <- "PASS"
}, error = function(e) {
  cat(sprintf("  ❌ Stage 1 failed: %s\n", e$message))
  test_results[["stage1"]] <- "FAIL"
  errors[["stage1"]] <- e$message
})

# =============================================================================
# Test 6: Load Stage 2 (Optimization Planning)
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 6: Loading Stage 2 (Optimization Planning)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

tryCatch({
  source("R/stage2_optimization_planning.R")
  cat("  ✅ Stage 2 loaded (R/stage2_optimization_planning.R)\n")

  if (exists("plan_optimization")) {
    cat("    ✓ plan_optimization() available\n")
  } else {
    cat("    ✗ plan_optimization() missing\n")
    errors[["stage2_main"]] <- "Main function not found"
  }

  test_results[["stage2"]] <- "PASS"
}, error = function(e) {
  cat(sprintf("  ❌ Stage 2 failed: %s\n", e$message))
  test_results[["stage2"]] <- "FAIL"
  errors[["stage2"]] <- e$message
})

# =============================================================================
# Test 7: Load Stage 3 Modules
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 7: Loading Stage 3 Modules (Modularized)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

stage3_modules <- c(
  "R/stage3/stage3_rt_binning.R",
  "R/stage3/stage3_mz_optimization.R",
  "R/stage3/stage3_window_generation.R",
  "R/stage3/stage3_statistics.R",
  "R/stage3/stage3_export.R"
)

for (module in stage3_modules) {
  tryCatch({
    source(module)
    module_name <- basename(module)
    cat(sprintf("  ✅ %s loaded\n", module_name))
    test_results[["stage3_modules"]][[module_name]] <- "PASS"
  }, error = function(e) {
    cat(sprintf("  ❌ %s failed: %s\n", basename(module), e$message))
    test_results[["stage3_modules"]][[basename(module)]] <- "FAIL"
    errors[[paste0("stage3_", basename(module))]] <- e$message
  })
}

# Load main Stage 3 file
cat("\n")
tryCatch({
  source("R/stage3_window_optimization.R")
  cat("  ✅ Stage 3 main file loaded (R/stage3_window_optimization.R)\n")

  if (exists("optimize_windows")) {
    cat("    ✓ optimize_windows() available\n")
  } else {
    cat("    ✗ optimize_windows() missing\n")
    errors[["stage3_main"]] <- "Main function not found"
  }

  test_results[["stage3_main"]] <- "PASS"
}, error = function(e) {
  cat(sprintf("  ❌ Stage 3 main failed: %s\n", e$message))
  test_results[["stage3_main"]] <- "FAIL"
  errors[["stage3_main"]] <- e$message
})

# =============================================================================
# Test 8: Load Plot Modules
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 8: Loading Plot Modules (Modularized)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

plot_modules <- c(
  "R/plots/plot_dppp.R",
  "R/plots/plot_density.R",
  "R/plots/plot_histogram.R",
  "R/plots/plot_coverage.R",
  "R/plots/plot_satisfaction.R",
  "R/plots/plot_window.R"
)

for (module in plot_modules) {
  tryCatch({
    source(module)
    module_name <- basename(module)
    cat(sprintf("  ✅ %s loaded\n", module_name))
    test_results[["plot_modules"]][[module_name]] <- "PASS"
  }, error = function(e) {
    cat(sprintf("  ❌ %s failed: %s\n", basename(module), e$message))
    test_results[["plot_modules"]][[basename(module)]] <- "FAIL"
    errors[[paste0("plot_", basename(module))]] <- e$message
  })
}

# =============================================================================
# Test 9: Load Stage 4 (Visualization)
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 9: Loading Stage 4 (Visualization)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

tryCatch({
  source("R/stage4_visualization.R")
  cat("  ✅ Stage 4 loaded (R/stage4_visualization.R)\n")

  if (exists("generate_visualizations")) {
    cat("    ✓ generate_visualizations() available\n")
  } else {
    cat("    ✗ generate_visualizations() missing\n")
    errors[["stage4_main"]] <- "Main function not found"
  }

  test_results[["stage4"]] <- "PASS"
}, error = function(e) {
  cat(sprintf("  ❌ Stage 4 failed: %s\n", e$message))
  test_results[["stage4"]] <- "FAIL"
  errors[["stage4"]] <- e$message
})

# =============================================================================
# Test 10: Load Stage 4 Export
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 10: Loading Stage 4 Export Module\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

tryCatch({
  source("R/stage4_export.R")
  cat("  ✅ Stage 4 Export loaded (R/stage4_export.R)\n")

  export_functions <- c("create_pdf_report", "export_method_file")
  for (func in export_functions) {
    if (exists(func)) {
      cat(sprintf("    ✓ %s() available\n", func))
    } else {
      cat(sprintf("    ✗ %s() missing\n", func))
      errors[[paste0("export_", func)]] <- "Function not found"
    }
  }

  test_results[["stage4_export"]] <- "PASS"
}, error = function(e) {
  cat(sprintf("  ❌ Stage 4 Export failed: %s\n", e$message))
  test_results[["stage4_export"]] <- "FAIL"
  errors[["stage4_export"]] <- e$message
})

# =============================================================================
# Test 11: Load Configuration Loader
# =============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Test 11: Loading Configuration Loader\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

tryCatch({
  source("R/config_loader.R")
  cat("  ✅ Config loader loaded (R/config_loader.R)\n")

  if (exists("load_optimization_config")) {
    cat("    ✓ load_optimization_config() available\n")
  } else {
    cat("    ✗ load_optimization_config() missing\n")
    errors[["config_main"]] <- "Main function not found"
  }

  test_results[["config_loader"]] <- "PASS"
}, error = function(e) {
  cat(sprintf("  ❌ Config loader failed: %s\n", e$message))
  test_results[["config_loader"]] <- "FAIL"
  errors[["config_loader"]] <- e$message
})

# =============================================================================
# Summary Report
# =============================================================================

cat("\n\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║               MODULE LOADING TEST SUMMARY                      ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Count results
total_tests <- length(unlist(test_results))
passed_tests <- sum(unlist(test_results) == "PASS")
failed_tests <- sum(unlist(test_results) == "FAIL")

cat(sprintf("Total tests: %d\n", total_tests))
cat(sprintf("✅ Passed: %d\n", passed_tests))
cat(sprintf("❌ Failed: %d\n", failed_tests))
cat(sprintf("Success rate: %.1f%%\n\n", (passed_tests / total_tests) * 100))

# List failures if any
if (failed_tests > 0) {
  cat("Failed tests:\n")
  for (test_name in names(test_results)) {
    result <- test_results[[test_name]]
    if (is.list(result)) {
      for (subtest in names(result)) {
        if (result[[subtest]] == "FAIL") {
          cat(sprintf("  ❌ %s: %s\n", test_name, subtest))
          if (!is.null(errors[[paste0(test_name, "_", subtest)]])) {
            cat(sprintf("     Error: %s\n", errors[[paste0(test_name, "_", subtest)]]))
          }
        }
      }
    } else if (result == "FAIL") {
      cat(sprintf("  ❌ %s\n", test_name))
      if (!is.null(errors[[test_name]])) {
        cat(sprintf("     Error: %s\n", errors[[test_name]]))
      }
    }
  }
  cat("\n")
}

# Overall result
if (failed_tests == 0) {
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║          ✅ ALL MODULES LOADED SUCCESSFULLY                     ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n")
  cat("\nReady to proceed with functional testing!\n\n")
} else {
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║          ⚠️  SOME MODULES FAILED TO LOAD                        ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n")
  cat("\nPlease fix the errors above before proceeding.\n\n")
}

# Save results
saveRDS(list(
  test_results = test_results,
  errors = errors,
  summary = list(
    total = total_tests,
    passed = passed_tests,
    failed = failed_tests,
    success_rate = (passed_tests / total_tests) * 100
  )
), "tests/manual/module_loading_results.rds")

cat("Results saved to: tests/manual/module_loading_results.rds\n\n")
