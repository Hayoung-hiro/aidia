# test_improved.R - Test the improved DPPP implementation

# Set working directory to project root
setwd("D:/Projects/dia_window_optimizer")

# Source the improved implementation
source("main.R")

# Test with reference parameters that match the original
cat("Testing Improved DIA Window Optimizer (Reference Implementation)\n")
cat("================================================================\n\n")

# Test with parameters matching the reference implementation
result <- main_optimization(
  proteome_file = "D:/Projects/DPPP_Window_isolation/DIANN-Output/report.parquet",
  instrument_preset = "astral",
  target_dppp = 1.5,  # Match reference
  rt_segments = 1,    # Match reference (single segment)
  window_mode = "dynamic",
  overlap_mode = "fixed",
  overlap_value = 1,  # Match reference overlap
  ms1_time = 350,     # Match reference MS1 time
  ms2_time = 100,     # Match reference MS2 time
  fixed_window = FALSE,
  lower_percentile = 0.05,
  max_window_width = 200,  # Match reference
  create_plots = FALSE  # Skip plots for faster testing
)

# Compare with reference results
cat("\n\n=== COMPARISON WITH REFERENCE ===\n")
cat("Reference windows: ~30-40 (estimated from file)\n")
cat(sprintf("Our windows: %d\n", result$windows$n_windows))
cat(sprintf("Target DPPP: %.2f\n", result$config$target_dppp))
cat(sprintf("Achieved DPPP: %.2f\n", result$windows$dppp))
cat(sprintf("Cycle time: %.1f ms\n", result$windows$cycle_time * 1000))
cat(sprintf("Scan rate: %.1f Hz\n", result$windows$scan_rate))

# Check window characteristics
if (!is.null(result$windows$windows)) {
  window_widths <- result$windows$windows$window_width
  cat(sprintf("\nWindow width range: %.1f - %.1f Da\n", 
              min(window_widths), max(window_widths)))
  cat(sprintf("Mean window width: %.1f Da\n", mean(window_widths)))
}

cat("\n=== IMPROVEMENT VERIFICATION ===\n")

# Expected improvements:
# 1. Proper DPPP-based calculation
# 2. Quantile-based distribution
# 3. Lower window count (should be ~24 for target DPPP 1.5)
# 4. Variable window widths based on density

expected_windows <- floor(((3.1 / 1.5) * 1000 - 350) / 100)  # Rough estimate
cat(sprintf("Expected windows (rough): %d\n", expected_windows))
cat(sprintf("Actual windows: %d\n", result$windows$n_windows))

if (abs(result$windows$n_windows - expected_windows) < 10) {
  cat("✅ Window count is in expected range\n")
} else {
  cat("❌ Window count differs significantly from expected\n")
}

if (result$windows$dppp > 1.0 && result$windows$dppp < 3.0) {
  cat("✅ DPPP is in reasonable range\n")
} else {
  cat("❌ DPPP is outside reasonable range\n")
}

cat("\n=== TEST COMPLETE ===\n")