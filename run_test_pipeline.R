#!/usr/bin/env Rscript
# Run test pipeline with YAML configuration

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║     DIA Window Optimizer - Pipeline Test (YAML Config)        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

start_time <- Sys.time()

# Source pipeline
source("run_with_config.R")

# Run optimization
cat("Starting optimization pipeline...\n\n")

tryCatch({
  results <- run_optimization("config/test_quick.yaml")

  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║              ✅ PIPELINE TEST SUCCESSFUL                       ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  cat(sprintf("Total time: %.1f seconds\n", elapsed))
  cat(sprintf("Output directory: %s\n", "results_yaml_test"))
  cat("\n")

}, error = function(e) {
  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║              ❌ PIPELINE TEST FAILED                           ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  cat(sprintf("Error: %s\n", e$message))
  cat("\nTraceback:\n")
  print(e)

  quit(status = 1)
})
