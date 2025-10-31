# Test script for current_cycle_time configuration
# Tests both auto-detection and user-specified cycle time

source("run_with_config.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   TEST: Current Cycle Time Configuration                      ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Test 1: Auto-detection (null cycle time)
cat("═══════════════════════════════════════════════════════════════\n")
cat("Test 1: Auto-detection (current_cycle_time = null)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

result1 <- run_optimization("config/optimization_config.json")

cat("\n\n")

# Test 2: User-specified cycle time
cat("═══════════════════════════════════════════════════════════════\n")
cat("Test 2: User-specified (current_cycle_time = 1.5 sec)\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

result2 <- run_optimization("config/example_with_cycle_time.json")

cat("\n\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   TEST COMPLETE                                                ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Summary:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("✅ Test 1: Auto-detection mode tested\n")
cat("✅ Test 2: User-specified cycle time (1.5 sec) tested\n")
cat("\n")
cat("Output directories:\n")
cat("  - results_fusion_lumos_min10_sat70_json/ (auto-detected)\n")
cat("  - output_custom_cycle_time_1.5sec/ (user-specified)\n")
cat("\n")
