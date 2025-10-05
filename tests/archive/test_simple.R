# Simple test script
setwd("D:/Projects/dia_window_optimizer")
source("main.R")

# Run with direct parameters
result <- quick_optimize(
  proteome_file = "D:/Projects/DPPP_Window_isolation/DIANN-Output/report.parquet",
  instrument = "astral",
  target_dppp = 1.25
)

# Print summary
cat("\n=== RESULTS ===\n")
cat(sprintf("Windows: %d\n", result$windows$n_windows))
cat(sprintf("DPPP: %.2f\n", result$windows$dppp))
cat(sprintf("Coverage: %.1f%%\n", result$windows$validation$coverage_pct))