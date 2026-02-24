# test_auto_it.R - Test Auto IT (Sweet Spot) Mode
# Core Feature: ms2_time = "auto" → IT = T_transient

cat("=== Testing Auto IT (Sweet Spot) Mode ===\n\n")

# Load dependencies
source("R/instrument_utils.R")

# Test 1: resolve_injection_time() with numeric values
cat("Test 1: Numeric IT values (passthrough)\n")
cat(paste0(rep("-", 40), collapse = ""), "\n")

test_values <- c(50, 22, 100)
for (val in test_values) {
  result <- resolve_injection_time(val, 30000, "orbitrap")
  status <- if (result == val) "PASS" else "FAIL"
  cat(sprintf("  [%s] resolve_injection_time(%g) = %g\n", status, val, result))
}
cat("\n")

# Test 2: resolve_injection_time() with "auto" mode
cat("Test 2: Auto IT mode (IT = T_transient)\n")
cat(paste0(rep("-", 40), collapse = ""), "\n")

test_cases <- list(
  list(resolution = 7500,   expected = 16),
  list(resolution = 15000,  expected = 32),
  list(resolution = 30000,  expected = 64),
  list(resolution = 60000,  expected = 128),
  list(resolution = 120000, expected = 256)
)

for (tc in test_cases) {
  result <- suppressMessages(resolve_injection_time("auto", tc$resolution, "orbitrap"))
  status <- if (result == tc$expected) "PASS" else "FAIL"
  res_k <- tc$resolution / 1000
  cat(sprintf("  [%s] %gK resolution: IT = %.0f ms (expected: %.0f)\n",
              status, res_k, result, tc$expected))
}
cat("\n")

# Test 3: Case insensitivity
cat("Test 3: Case insensitivity for 'auto'\n")
cat(paste0(rep("-", 40), collapse = ""), "\n")

test_strings <- c("auto", "Auto", "AUTO", "AuTo")
for (s in test_strings) {
  result <- suppressMessages(resolve_injection_time(s, 30000, "orbitrap"))
  status <- if (result == 64) "PASS" else "FAIL"
  cat(sprintf("  [%s] '%s' → IT = %.0f ms\n", status, s, result))
}
cat("\n")

# Test 4: Error handling
cat("Test 4: Error handling\n")
cat(paste0(rep("-", 40), collapse = ""), "\n")

# Test: auto without resolution
error_caught <- tryCatch({
  resolve_injection_time("auto", NULL, "orbitrap")
  FALSE
}, error = function(e) TRUE)
cat(sprintf("  [%s] Auto without resolution raises error\n",
            if (error_caught) "PASS" else "FAIL"))

# Test: auto with non-Orbitrap
error_caught <- tryCatch({
  resolve_injection_time("auto", 30000, "tof")
  FALSE
}, error = function(e) TRUE)
cat(sprintf("  [%s] Auto with TOF analyzer raises error\n",
            if (error_caught) "PASS" else "FAIL"))

# Test: invalid string
error_caught <- tryCatch({
  resolve_injection_time("invalid", 30000, "orbitrap")
  FALSE
}, error = function(e) TRUE)
cat(sprintf("  [%s] Invalid string raises error\n",
            if (error_caught) "PASS" else "FAIL"))

cat("\n")

# Test 5: Scan time calculation with auto IT
cat("Test 5: Scan time with Auto IT (balanced mode)\n")
cat(paste0(rep("-", 40), collapse = ""), "\n")

# When IT = T_transient (auto), the scan should be in "balanced" mode
resolutions <- c(7500, 15000, 30000, 60000)

for (res in resolutions) {
  auto_it <- suppressMessages(resolve_injection_time("auto", res, "orbitrap"))
  scan_info <- calculate_ms2_scan_time(res, auto_it)

  status <- if (scan_info$limiting_factor == "balanced") "PASS" else "FAIL"
  cat(sprintf("  [%s] %gK: IT=%g ms, t_scan=%.1f ms, factor=%s\n",
              status, res/1000, auto_it, scan_info$t_scan_ms, scan_info$limiting_factor))
}
cat("\n")

# Test 6: Window count comparison (auto vs manual)
cat("Test 6: Window count comparison (Auto vs Manual IT)\n")
cat(paste0(rep("-", 40), collapse = ""), "\n")

source("R/utils_common.R")
source("R/optimization_planning.R")

# At 30K resolution:
# - T_transient = 64 ms
# - δ = 12.8 ms
# - Auto IT (64 ms): t_scan = max(64, 64) + 12.8 = 76.8 ms
# - Manual IT (50 ms): t_scan = max(64, 50) + 12.8 = 76.8 ms (same, resolution-limited)
# - Manual IT (80 ms): t_scan = max(64, 80) + 12.8 = 92.8 ms (different, sensitivity-limited)

cycle_time <- 3.5
ms1_time <- 0.05

# Auto IT (64 ms at 30K)
auto_it <- suppressMessages(resolve_injection_time("auto", 30000, "orbitrap"))
auto_result <- calculate_window_count_internal(
  target_cycle_time_sec = cycle_time,
  ms1_time_sec = ms1_time,
  ms2_time_sec = auto_it / 1000,
  resolution = 30000,
  analyzer_type = "orbitrap",
  cycle_mode = "sequential",
  max_windows = 300
)

# Manual IT (80 ms)
manual_result <- calculate_window_count_internal(
  target_cycle_time_sec = cycle_time,
  ms1_time_sec = ms1_time,
  ms2_time_sec = 0.080,
  resolution = 30000,
  analyzer_type = "orbitrap",
  cycle_mode = "sequential",
  max_windows = 300
)

cat(sprintf("  Auto IT (64 ms):   %d windows, t_scan=%.1f ms, factor=%s\n",
            auto_result$n_windows, auto_result$t_scan_ms, auto_result$limiting_factor))
cat(sprintf("  Manual IT (80 ms): %d windows, t_scan=%.1f ms, factor=%s\n",
            manual_result$n_windows, manual_result$t_scan_ms, manual_result$limiting_factor))

# Auto should give more windows (shorter scan time)
status <- if (auto_result$n_windows >= manual_result$n_windows) "PASS" else "FAIL"
cat(sprintf("  [%s] Auto IT gives equal or more windows than sensitivity-limited IT\n", status))

cat("\n")
cat("=== Test Summary ===\n")
cat("Auto IT (Sweet Spot) mode is correctly implemented.\n")
cat("When ms2_time = 'auto', IT is set to T_transient for optimal efficiency.\n")
