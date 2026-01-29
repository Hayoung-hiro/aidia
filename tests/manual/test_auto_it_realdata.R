# test_auto_it_realdata.R - Test Auto IT with Real Data
# Compare Auto IT (default) vs Custom IT (user-defined)
# Since v2.2: All Orbitrap presets use Auto IT by default

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   AUTO IT (SWEET SPOT) vs CUSTOM IT - REAL DATA TEST                  ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n\n")

library(dplyr)
library(tibble)

# Source modules
source("R/stage1_data_validation.R")
source("R/replicate_utils.R")
source("R/column_selection_simple.R")
source("R/quality_validation.R")
source("R/stage2_optimization_planning.R")
source("R/instrument_utils.R")

# ============================================================================
# Test: Compare exploris Auto IT (default) vs Custom IT (user-defined 50ms)
# ============================================================================

cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("Comparison: Auto IT (default) vs Custom IT (50ms, user-defined)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")

# Load 60min data
cat("Loading 60min gradient data...\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/60min_report.parquet",
  enable_replicate_consensus = FALSE,
  quality_threshold = 0.7
)

cat("\n")
cat("┌──────────────────────────────────────────────────────────────────────┐\n")
cat("│  TEST A: exploris with Auto IT (default, IT = T_transient = 16ms)   │\n")
cat("└──────────────────────────────────────────────────────────────────────┘\n")

plan_auto <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.5,
  instrument_preset = "exploris",
  target_dppp = 4.0,
  target_satisfaction = 0.85,
  load_factor = 0.8
)

cat("\n")
cat("┌──────────────────────────────────────────────────────────────────────┐\n")
cat("│  TEST B: exploris with Custom IT (50ms, user-defined)               │\n")
cat("└──────────────────────────────────────────────────────────────────────┘\n")

# Create a custom config with 50ms IT
# This simulates what happens when user edits instruments.json
plan_custom <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.5,
  instrument_preset = "exploris",
  target_dppp = 4.0,
  target_satisfaction = 0.85,
  load_factor = 0.8,
  ms2_time_override = 0.050  # 50ms custom IT
)

# ============================================================================
# Comparison Summary
# ============================================================================

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
cat("║   COMPARISON RESULTS                                                  ║\n")
cat("╚═══════════════════════════════════════════════════════════════════════╝\n\n")

# Calculate scan times
auto_it <- suppressMessages(resolve_injection_time("auto", 7500, "orbitrap"))
auto_scan <- calculate_ms2_scan_time(7500, auto_it)
custom_scan <- calculate_ms2_scan_time(7500, 50)

cat("                    Auto IT (16ms)      Custom IT (50ms)\n")
cat("────────────────────────────────────────────────────────────────────────\n")
cat(sprintf("  Window Count:           %d                %d\n",
            plan_auto$window_count_per_bin,
            plan_custom$window_count_per_bin))
cat(sprintf("  T_transient:            %.0f ms              %.0f ms\n",
            auto_scan$transient_ms, custom_scan$transient_ms))
cat(sprintf("  IT (Injection Time):    %.0f ms              %.0f ms\n",
            auto_it, 50))
cat(sprintf("  t_scan (total):         %.1f ms             %.1f ms\n",
            auto_scan$t_scan_ms, custom_scan$t_scan_ms))
cat(sprintf("  Limiting Factor:        %-10s         %s\n",
            auto_scan$limiting_factor, custom_scan$limiting_factor))
cat(sprintf("  Efficiency:             100.0%%             %.1f%%\n",
            custom_scan$efficiency_pct))

cat("────────────────────────────────────────────────────────────────────────\n")

# Analysis
window_diff <- plan_auto$window_count_per_bin - plan_custom$window_count_per_bin
time_diff <- custom_scan$t_scan_ms - auto_scan$t_scan_ms

cat("\n")
cat("📊 Analysis:\n")
cat(sprintf("   - Auto IT gives %d more windows per RT bin\n", window_diff))
cat(sprintf("   - Custom IT (50ms) adds %.1f ms per scan (%.1f%% slower)\n",
            time_diff, (time_diff / auto_scan$t_scan_ms) * 100))
cat("   - Auto IT mode: balanced (IT = T_transient = 16ms) - 100% efficiency\n")
cat(sprintf("   - Custom IT mode: sensitivity-limited (IT > T_transient) - %.1f%% efficiency\n",
            custom_scan$efficiency_pct))

cat("\n")
cat("💡 Tip: Custom IT is useful when you need longer ion accumulation\n")
cat("        for low-abundance samples, but reduces window count.\n")
cat("\n")
cat("✅ Auto IT vs Custom IT comparison completed successfully!\n\n")
