# Test: Cycle Time Calculation from Experiment Config
# =============================================================================

cat("\n=============================================================================
  Test: Cycle Time Calculation from Experiment Config
=============================================================================\n\n")

# Load package (functions available via namespace)
library(aidia)

# Helper: Print test header with consistent formatting
print_test_header <- function(test_num, description) {
  title <- sprintf("Test %d: %s", test_num, description)
  cat(title, "\n")
  cat(strrep("\u2500", nchar(title)), "\n")  # Unicode horizontal line
}

# Helper: Print test result with checkmarks
print_test_result <- function(result) {
  cat(sprintf("\n\u2713 Result: Cycle Time = %.3f sec\n", result$cycle_time_sec))
  cat(sprintf("\u2713 MS2 Efficiency: %.1f%% (%s)\n\n", result$ms2$efficiency_pct, result$ms2$efficiency_mode))
}

print_test_header(1, "Exploris 480 (MS2 15K, Auto IT, 40 windows)")

config1 <- list(
  instrument = list(preset = "exploris"),
  ms1 = list(resolution = 60000, max_injection_time_ms = 50),
  ms2 = list(resolution = 15000, max_injection_time_ms = "auto"),
  dia_windows = list(window_count = 40)
)

result1 <- calculate_cycle_time_from_experiment(config1, verbose = TRUE, language = "ko")
print_test_result(result1)

print_test_header(2, "Exploris 480 (MS2 15K, Custom IT=50ms, 40 windows)")

config2 <- list(
  instrument = list(preset = "exploris"),
  ms1 = list(resolution = 60000, max_injection_time_ms = 50),
  ms2 = list(resolution = 15000, max_injection_time_ms = 50),  # Custom: longer than transient
  dia_windows = list(window_count = 40)
)

result2 <- calculate_cycle_time_from_experiment(config2, verbose = TRUE, language = "ko")
print_test_result(result2)

print_test_header(3, "Astral (Parallel Mode, 3ms IT, 100 windows)")

config3 <- list(
  instrument = list(preset = "astral"),
  ms1 = list(resolution = 120000, max_injection_time_ms = 50),  # MS1 on Orbitrap
  ms2 = list(resolution = 80000, max_injection_time_ms = 3.0),   # MS2 on Astral
  dia_windows = list(window_count = 100)
)

result3 <- calculate_cycle_time_from_experiment(config3, verbose = TRUE, language = "ko")
print_test_result(result3)

# =============================================================================
# Summary Comparison
# =============================================================================
cat("\n")
cat("\u2554", strrep("\u2550", 68), "\u2557\n", sep = "")
cat("\u2551                      Summary Comparison                            \u2551\n")
cat("\u2560", strrep("\u2550", 68), "\u2563\n", sep = "")

# Format string for consistent table rows
row_fmt <- "\u2551 %-27s %7.3f sec  (%3.0f%% efficiency)    \u2551\n"
cat(sprintf(row_fmt, "Test 1 (Exploris Auto IT):", result1$cycle_time_sec, result1$ms2$efficiency_pct))
cat(sprintf(row_fmt, "Test 2 (Exploris Custom IT):", result2$cycle_time_sec, result2$ms2$efficiency_pct))
cat(sprintf(row_fmt, "Test 3 (Astral Parallel):", result3$cycle_time_sec, result3$ms2$efficiency_pct))

cat("\u255a", strrep("\u2550", 68), "\u255d\n", sep = "")

cat("\n\u2705 All tests completed successfully!\n\n")
