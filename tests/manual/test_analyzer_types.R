# test_analyzer_types.R - Test Analyzer-Specific Scan Time Calculations
# Tests: Orbitrap, Astral (MR-TOF), TOF analyzer types
# Date: 2026-01-29

cat("\n")
cat("===========================================================================\n")
cat("   ANALYZER TYPE SCAN TIME CALCULATION TESTS\n")
cat("===========================================================================\n\n")

# Load dependencies
source("R/instrument_utils.R")

passed <- 0
failed <- 0

# =============================================================================
# Test 1: Orbitrap Transient Time Mapping (Existing behavior)
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 1: Orbitrap Transient Time Mapping\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

orbitrap_tests <- list(
  list(resolution = 7500,   expected = 16),
  list(resolution = 15000,  expected = 32),
  list(resolution = 30000,  expected = 64),
  list(resolution = 60000,  expected = 128),
  list(resolution = 120000, expected = 256),
  list(resolution = 480000, expected = 1024)
)

for (tc in orbitrap_tests) {
  result <- get_transient_time(tc$resolution, "orbitrap")
  status <- if (result == tc$expected) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
  cat(sprintf("  [%s] %gK resolution: T_transient = %.0f ms (expected: %.0f)\n",
              status, tc$resolution / 1000, result, tc$expected))
}
cat("\n")

# =============================================================================
# Test 2: Astral Detection Time (Fixed)
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 2: Astral Detection Time (Fixed at 2.5 ms)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# Astral has fixed detection time regardless of resolution setting
astral_tests <- list(
  list(resolution = 80000,  expected = 2.5),
  list(resolution = 30000,  expected = 2.5),  # Still 2.5 ms
  list(resolution = 120000, expected = 2.5)   # Still 2.5 ms
)

for (tc in astral_tests) {
  result <- get_transient_time(tc$resolution, "astral")
  status <- if (result == tc$expected) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
  cat(sprintf("  [%s] Astral (res=%gK): Detection time = %.1f ms (expected: %.1f)\n",
              status, tc$resolution / 1000, result, tc$expected))
}
cat("\n")

# =============================================================================
# Test 3: TOF Returns NA
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 3: TOF Returns NA (no transient time concept)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

result <- get_transient_time(30000, "tof")
status <- if (is.na(result)) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
cat(sprintf("  [%s] TOF analyzer: get_transient_time() = NA\n", status))
cat("\n")

# =============================================================================
# Test 4: Orbitrap Scan Time Calculation
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 4: Orbitrap Scan Time Calculation (t_scan = max(T, IT) + δ)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# 30K resolution, 50ms IT → t_scan = max(64, 50) + 12.8 = 76.8 ms
result <- calculate_ms2_scan_time(30000, 50, analyzer = "orbitrap")
expected_t_scan <- 76.8  # max(64, 50) + 12.8
status <- if (abs(result$t_scan_ms - expected_t_scan) < 0.1) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
cat(sprintf("  [%s] 30K, IT=50ms: t_scan = %.1f ms (expected: %.1f), factor = %s\n",
            status, result$t_scan_ms, expected_t_scan, result$limiting_factor))

# 30K resolution, 80ms IT → t_scan = max(64, 80) + 12.8 = 92.8 ms
result <- calculate_ms2_scan_time(30000, 80, analyzer = "orbitrap")
expected_t_scan <- 92.8  # max(64, 80) + 12.8
status <- if (abs(result$t_scan_ms - expected_t_scan) < 0.1) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
cat(sprintf("  [%s] 30K, IT=80ms: t_scan = %.1f ms (expected: %.1f), factor = %s\n",
            status, result$t_scan_ms, expected_t_scan, result$limiting_factor))

# 7.5K resolution, 16ms IT → balanced mode
result <- calculate_ms2_scan_time(7500, 16, analyzer = "orbitrap")
status <- if (result$limiting_factor == "balanced") { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
cat(sprintf("  [%s] 7.5K, IT=16ms: t_scan = %.1f ms, factor = %s (expected: balanced)\n",
            status, result$t_scan_ms, result$limiting_factor))
cat("\n")

# =============================================================================
# Test 5: Astral Scan Time Calculation
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 5: Astral Scan Time Calculation (MR-TOF)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# Astral with 3ms IT → t_scan = max(2.5, 3.0) + 2.0 = 5.0 ms → 200 Hz
result <- calculate_ms2_scan_time(80000, 3.0, analyzer = "astral")
expected_t_scan <- 5.0  # max(2.5, 3.0) + 2.0
expected_rate <- 200    # 1000 / 5.0
status <- if (abs(result$t_scan_ms - expected_t_scan) < 0.1) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
cat(sprintf("  [%s] Astral, IT=3ms: t_scan = %.1f ms → %.0f Hz (expected: %.1f ms)\n",
            status, result$t_scan_ms, result$scan_rate_hz, expected_t_scan))

# Astral with 20ms IT → t_scan = max(2.5, 20) + 2.0 = 22.0 ms → ~45 Hz
result <- calculate_ms2_scan_time(80000, 20.0, analyzer = "astral")
expected_t_scan <- 22.0  # max(2.5, 20.0) + 2.0
status <- if (abs(result$t_scan_ms - expected_t_scan) < 0.1) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
cat(sprintf("  [%s] Astral, IT=20ms: t_scan = %.1f ms → %.0f Hz (expected: %.1f ms)\n",
            status, result$t_scan_ms, result$scan_rate_hz, expected_t_scan))

# Astral limiting factor should be "sensitivity" when IT > detection time
status <- if (result$limiting_factor == "sensitivity") { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
cat(sprintf("  [%s] Astral factor when IT > detection: %s (expected: sensitivity)\n",
            status, result$limiting_factor))
cat("\n")

# =============================================================================
# Test 6: TOF Scan Time Calculation
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 6: TOF Scan Time Calculation (IT + overhead)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# TOF with 2ms IT → t_scan = 2.0 + 5.0 = 7.0 ms
result <- calculate_ms2_scan_time(NULL, 2.0, analyzer = "tof")
expected_t_scan <- 7.0  # 2.0 + 5.0 (minimum overhead)
status <- if (abs(result$t_scan_ms - expected_t_scan) < 0.1) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
cat(sprintf("  [%s] TOF, IT=2ms: t_scan = %.1f ms (expected: %.1f)\n",
            status, result$t_scan_ms, expected_t_scan))

# TOF should always report sensitivity-limited
status <- if (result$limiting_factor == "sensitivity") { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
cat(sprintf("  [%s] TOF limiting factor: %s (expected: sensitivity)\n",
            status, result$limiting_factor))
cat("\n")

# =============================================================================
# Test 7: Instrument Config Loading (Astral)
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 7: Astral Instrument Config Loading\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

config <- tryCatch({
  get_instrument_config("astral")
}, error = function(e) {
  cat(sprintf("  [FAIL] Error loading astral config: %s\n", e$message))
  failed <<- failed + 1
  NULL
})

if (!is.null(config)) {
  # Check analyzer_type is "astral"
  status <- if (config$analyzer_type == "astral") { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
  cat(sprintf("  [%s] analyzer_type = '%s' (expected: 'astral')\n",
              status, config$analyzer_type))

  # Check resolution is 80000
  status <- if (config$ms2_resolution == 80000) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
  cat(sprintf("  [%s] ms2_resolution = %g (expected: 80000)\n",
              status, config$ms2_resolution))

  # Check max_scan_rate is 200
  status <- if (config$max_scan_rate == 200) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
  cat(sprintf("  [%s] max_scan_rate = %.0f Hz (expected: 200)\n",
              status, config$max_scan_rate))
}
cat("\n")

# =============================================================================
# Test 8: Astral Sensitive Mode Config
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 8: Astral Sensitive Mode Config\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

config <- tryCatch({
  get_instrument_config("astral_sensitive")
}, error = function(e) {
  cat(sprintf("  [FAIL] Error loading astral_sensitive config: %s\n", e$message))
  failed <<- failed + 1
  NULL
})

if (!is.null(config)) {
  # Check ms2_time is 20ms for sensitivity mode
  status <- if (config$ms2_time == 20) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
  cat(sprintf("  [%s] ms2_time = %.0f ms (expected: 20)\n",
              status, config$ms2_time))

  # Check max_scan_rate is 25 Hz
  status <- if (config$max_scan_rate == 25) { passed <<- passed + 1; "PASS" } else { failed <<- failed + 1; "FAIL" }
  cat(sprintf("  [%s] max_scan_rate = %.0f Hz (expected: 25)\n",
              status, config$max_scan_rate))
}
cat("\n")

# =============================================================================
# Test 9: Efficiency Mode (Auto vs Custom)
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 9: Efficiency Mode (Auto vs Custom)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# Auto mode (IT = T_transient) should report 100% efficiency
result <- calculate_ms2_scan_time(30000, 64, analyzer = "orbitrap", verbose = FALSE)
status <- if (result$efficiency_pct == 100 && result$efficiency_mode == "auto") {
  passed <<- passed + 1; "PASS"
} else {
  failed <<- failed + 1; "FAIL"
}
cat(sprintf("  [%s] Auto mode (IT=64ms, T_trans=64ms): efficiency=%.0f%%, mode=%s\n",
            status, result$efficiency_pct, result$efficiency_mode))

# Custom mode (IT > T_transient) should report reduced efficiency
result <- calculate_ms2_scan_time(30000, 100, analyzer = "orbitrap", verbose = FALSE)
expected_optimal <- 64 + 12.8  # T_transient + overhead = 76.8 ms
expected_actual <- 100 + 12.8  # IT + overhead = 112.8 ms
expected_efficiency <- round((expected_optimal / expected_actual) * 100, 1)
status <- if (abs(result$efficiency_pct - expected_efficiency) < 1.0 && result$efficiency_mode == "custom") {
  passed <<- passed + 1; "PASS"
} else {
  failed <<- failed + 1; "FAIL"
}
cat(sprintf("  [%s] Custom mode (IT=100ms > T_trans=64ms): efficiency=%.1f%% (expected: ~%.1f%%)\n",
            status, result$efficiency_pct, expected_efficiency))

# Resolution-limited should also be 100% efficiency
result <- calculate_ms2_scan_time(30000, 50, analyzer = "orbitrap", verbose = FALSE)
status <- if (result$efficiency_pct == 100 && result$limiting_factor == "resolution") {
  passed <<- passed + 1; "PASS"
} else {
  failed <<- failed + 1; "FAIL"
}
cat(sprintf("  [%s] Resolution-limited (IT=50ms < T_trans=64ms): efficiency=%.0f%%, factor=%s\n",
            status, result$efficiency_pct, result$limiting_factor))
cat("\n")

# =============================================================================
# Test 10: Efficiency Report Generation
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 10: Efficiency Report Generation\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# Generate report for custom IT scenario
report <- generate_efficiency_report(30000, 100, "orbitrap", language = "en")
status <- if (!is.null(report) && !is.null(report$summary) && !report$is_optimal) {
  passed <<- passed + 1; "PASS"
} else {
  failed <<- failed + 1; "FAIL"
}
cat(sprintf("  [%s] Report generated for custom IT (100ms): is_optimal=%s\n",
            status, report$is_optimal))

# Generate report for optimal scenario
report <- generate_efficiency_report(7500, 16, "orbitrap", language = "en")
status <- if (!is.null(report) && report$is_optimal && report$efficiency_pct == 100) {
  passed <<- passed + 1; "PASS"
} else {
  failed <<- failed + 1; "FAIL"
}
cat(sprintf("  [%s] Report generated for optimal IT (16ms = T_trans): is_optimal=%s, eff=%.0f%%\n",
            status, report$is_optimal, report$efficiency_pct))
cat("\n")

# =============================================================================
# Test 11: Astral Efficiency Modes
# =============================================================================
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Test 11: Astral Efficiency Modes\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

# Astral at max speed (IT <= 3ms) should be 100% efficient
result <- calculate_ms2_scan_time(80000, 3.0, analyzer = "astral", verbose = FALSE)
status <- if (result$efficiency_pct == 100 && result$limiting_factor == "parallel") {
  passed <<- passed + 1; "PASS"
} else {
  failed <<- failed + 1; "FAIL"
}
cat(sprintf("  [%s] Astral parallel (IT=3ms): t_scan=%.1f ms, eff=%.0f%%, factor=%s\n",
            status, result$t_scan_ms, result$efficiency_pct, result$limiting_factor))

# Astral sensitivity mode (IT > 3ms) should show reduced efficiency
result <- calculate_ms2_scan_time(80000, 10.0, analyzer = "astral", verbose = FALSE)
expected_eff <- round((5.0 / result$t_scan_ms) * 100, 1)
status <- if (abs(result$efficiency_pct - expected_eff) < 1.0 && result$limiting_factor == "sensitivity") {
  passed <<- passed + 1; "PASS"
} else {
  failed <<- failed + 1; "FAIL"
}
cat(sprintf("  [%s] Astral sensitivity (IT=10ms): t_scan=%.1f ms, eff=%.1f%%, factor=%s\n",
            status, result$t_scan_ms, result$efficiency_pct, result$limiting_factor))
cat("\n")

# =============================================================================
# Summary
# =============================================================================
cat("===========================================================================\n")
cat("                           TEST SUMMARY\n")
cat("===========================================================================\n\n")

total <- passed + failed
cat(sprintf("  Passed: %d / %d (%.0f%%)\n", passed, total, 100 * passed / total))
cat(sprintf("  Failed: %d / %d\n", failed, total))

if (failed == 0) {
  cat("\n✅ ALL TESTS PASSED - Analyzer types and efficiency modes working correctly!\n\n")
} else {
  cat("\n❌ SOME TESTS FAILED - Review errors above\n\n")
}
