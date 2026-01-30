# Test: Cycle Time Calculation from Experiment Config
# =============================================================================

cat("\n")
cat("=============================================================================\n")
cat("  Test: Cycle Time Calculation from Experiment Config\n")
cat("=============================================================================\n\n")

# Load dependencies
source("R/instrument_utils.R")

# =============================================================================
# Test 1: Exploris with Auto IT
# =============================================================================
cat("Test 1: Exploris 480 (MS2 15K, Auto IT, 40 windows)\n")
cat("─────────────────────────────────────────────────────\n")

config1 <- list(
  instrument = list(preset = "exploris"),
  ms1 = list(resolution = 60000, max_injection_time_ms = 50),
  ms2 = list(resolution = 15000, max_injection_time_ms = "auto"),
  dia_windows = list(window_count = 40)
)

result1 <- calculate_cycle_time_from_experiment(config1, verbose = TRUE, language = "ko")

cat(sprintf("\n✓ Result: Cycle Time = %.3f sec\n", result1$cycle_time_sec))
cat(sprintf("✓ MS2 Efficiency: %.1f%% (%s)\n\n", result1$ms2$efficiency_pct, result1$ms2$efficiency_mode))

# =============================================================================
# Test 2: Exploris with Custom IT (longer for sensitivity)
# =============================================================================
cat("\nTest 2: Exploris 480 (MS2 15K, Custom IT=50ms, 40 windows)\n")
cat("─────────────────────────────────────────────────────────────\n")

config2 <- list(
  instrument = list(preset = "exploris"),
  ms1 = list(resolution = 60000, max_injection_time_ms = 50),
  ms2 = list(resolution = 15000, max_injection_time_ms = 50),  # Custom: longer than transient
  dia_windows = list(window_count = 40)
)

result2 <- calculate_cycle_time_from_experiment(config2, verbose = TRUE, language = "ko")

cat(sprintf("\n✓ Result: Cycle Time = %.3f sec\n", result2$cycle_time_sec))
cat(sprintf("✓ MS2 Efficiency: %.1f%% (%s)\n\n", result2$ms2$efficiency_pct, result2$ms2$efficiency_mode))

# =============================================================================
# Test 3: Astral (Parallel Architecture)
# =============================================================================
cat("\nTest 3: Astral (Parallel Mode, 3ms IT, 100 windows)\n")
cat("───────────────────────────────────────────────────────\n")

config3 <- list(
  instrument = list(preset = "astral"),
  ms1 = list(resolution = 120000, max_injection_time_ms = 50),  # MS1 on Orbitrap
  ms2 = list(resolution = 80000, max_injection_time_ms = 3.0),   # MS2 on Astral
  dia_windows = list(window_count = 100)
)

result3 <- calculate_cycle_time_from_experiment(config3, verbose = TRUE, language = "ko")

cat(sprintf("\n✓ Result: Cycle Time = %.3f sec\n", result3$cycle_time_sec))
cat(sprintf("✓ MS2 Efficiency: %.1f%% (%s)\n\n", result3$ms2$efficiency_pct, result3$ms2$efficiency_mode))

# =============================================================================
# Summary Comparison
# =============================================================================
cat("\n")
cat("╔════════════════════════════════════════════════════════════════════╗\n")
cat("║                      Summary Comparison                            ║\n")
cat("╠════════════════════════════════════════════════════════════════════╣\n")
cat(sprintf("║ Test 1 (Exploris Auto IT):    %7.3f sec  (%3.0f%% efficiency)    ║\n",
            result1$cycle_time_sec, result1$ms2$efficiency_pct))
cat(sprintf("║ Test 2 (Exploris Custom IT):  %7.3f sec  (%3.0f%% efficiency)    ║\n",
            result2$cycle_time_sec, result2$ms2$efficiency_pct))
cat(sprintf("║ Test 3 (Astral Parallel):     %7.3f sec  (%3.0f%% efficiency)    ║\n",
            result3$cycle_time_sec, result3$ms2$efficiency_pct))
cat("╚════════════════════════════════════════════════════════════════════╝\n")

cat("\n✅ All tests completed successfully!\n\n")
