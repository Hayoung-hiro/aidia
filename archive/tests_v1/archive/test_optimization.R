# test_optimization.R - Test script for DIA Window Optimizer

# Set working directory to project root
setwd("D:/Projects/dia_window_optimizer")

# Source the main script
source("main.R")

# Test with the provided parquet file
cat("Testing DIA Window Optimizer with provided data\n")
cat("================================================\n\n")

# Option 1: Use the example configuration file
cat("Running optimization with configuration file...\n")

result <- main_optimization(
  config_file = "examples/example_config.json"
)

# Option 2: Direct parameters (uncomment to test)
# result <- quick_optimize(
#   proteome_file = "D:/Projects/DPPP_Window_isolation/DIANN-Output/report.parquet",
#   instrument = "astral",
#   target_dppp = 1.25
# )

# Print summary
cat("\n\n=== OPTIMIZATION SUMMARY ===\n")
cat(sprintf("Windows generated: %d\n", result$windows$n_windows))
cat(sprintf("Achieved DPPP: %.2f\n", result$windows$dppp))
cat(sprintf("Scan rate: %.1f Hz\n", result$windows$scan_rate))
cat(sprintf("Coverage: %.1f%%\n", result$windows$validation$coverage_pct))

# Check if there are any warnings
if (length(result$windows$validation$warnings) > 0) {
  cat("\nWarnings:\n")
  for (warning in result$windows$validation$warnings) {
    cat(sprintf("  - %s\n", warning))
  }
}

cat("\nFiles created:\n")
cat(sprintf("  - Method file: %s.csv\n", result$config$output_path))
cat(sprintf("  - Configuration: %s_config.json\n", result$config$output_path))
if (result$config$create_plots) {
  cat(sprintf("  - Report plots: %s\n", result$config$plot_output))
}

cat("\n=== TEST COMPLETE ===\n")