# compare_instruments.R - Compare Astral vs Orbitrap Results

cat("═══════════════════════════════════════════════════════════════\n")
cat("  Instrument Comparison: Astral vs Orbitrap\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

library(jsonlite)

# Load results
astral <- fromJSON("final_test/summary_report.json")
orbitrap <- fromJSON("final_test_orbitrap/summary_report.json")

cat("╔═══════════════════════════════════════════════════════════════╗\n")
cat("║                   INSTRUMENT COMPARISON                       ║\n")
cat("╚═══════════════════════════════════════════════════════════════╝\n\n")

cat("─── INPUT DATA ───\n")
cat(sprintf("Precursors:       %d (both)\n", astral$stage1$n_precursors))
cat(sprintf("RT range:         %.1f - %.1f min (both)\n",
            astral$stage1$rt_range[1], astral$stage1$rt_range[2]))
cat(sprintf("m/z range:        %.1f - %.1f Da (both)\n",
            astral$stage1$mz_range[1], astral$stage1$mz_range[2]))

cat("\n─── STAGE 2: DPPP DIAGNOSIS ───\n")
cat(sprintf("%-30s | %10s | %10s\n", "Metric", "Astral", "Orbitrap"))
cat("─────────────────────────────────────────────────────────────────\n")
cat(sprintf("%-30s | %9.1f%% | %9.1f%%\n", "Satisfaction Ratio",
            astral$stage2$satisfaction_ratio * 100,
            orbitrap$stage2$satisfaction_ratio * 100))
cat(sprintf("%-30s | %8.3f s | %8.3f s\n", "Current Cycle Time",
            astral$stage2$current_cycle_time_sec,
            orbitrap$stage2$current_cycle_time_sec))
cat(sprintf("%-30s | %8.3f s | %8.3f s\n", "Required Cycle Time",
            astral$stage2$required_cycle_time_sec,
            orbitrap$stage2$required_cycle_time_sec))

cat("\n─── STAGE 3A: WINDOW COUNT ───\n")
cat(sprintf("%-30s | %10s | %10s\n", "Metric", "Astral", "Orbitrap"))
cat("─────────────────────────────────────────────────────────────────\n")
cat(sprintf("%-30s | %10d | %10d\n", "Windows per RT bin",
            astral$stage3a$n_windows,
            orbitrap$stage3a$n_windows))
cat(sprintf("%-30s | %8.3f s | %8.3f s\n", "Calculated Cycle Time",
            astral$stage3a$calculated_cycle_time_sec,
            orbitrap$stage3a$calculated_cycle_time_sec))
cat(sprintf("%-30s | %8.3f s | %8.3f s\n", "Target Cycle Time",
            astral$stage3a$target_cycle_time_sec,
            orbitrap$stage3a$target_cycle_time_sec))
cat(sprintf("%-30s | %10s | %10s\n", "Feasibility",
            ifelse(astral$stage3a$is_feasible, "✅ Pass", "❌ Fail"),
            ifelse(orbitrap$stage3a$is_feasible, "✅ Pass", "❌ Fail")))

cat("\n─── STAGE 3B: RT BINNING ───\n")
cat(sprintf("%-30s | %10s | %10s\n", "Metric", "Astral", "Orbitrap"))
cat("─────────────────────────────────────────────────────────────────\n")
cat(sprintf("%-30s | %10d | %10d\n", "Number of RT bins",
            astral$stage3b$n_segments,
            orbitrap$stage3b$n_segments))
cat(sprintf("%-30s | %10.0f | %10.0f\n", "Mean Precursors/bin",
            astral$stage3b$mean_precursors,
            orbitrap$stage3b$mean_precursors))

cat("\n─── STAGE 3C: m/z RANGE OPTIMIZATION ───\n")
cat(sprintf("%-15s | %10s | %10s | %10s | %10s\n",
            "Strategy", "Mean Width", "Coverage", "Range Red.", "Better For"))
cat("────────────────────────────────────────────────────────────────────\n")

strategies <- c("coverage", "quantile", "outlier", "smoothing")
for (i in seq_along(strategies)) {
  astral_s <- astral$stage3c[[i]]
  orbitrap_s <- orbitrap$stage3c[[i]]

  width_diff <- astral_s$mean_width - orbitrap_s$mean_width
  coverage_diff <- astral_s$mean_coverage - orbitrap_s$mean_coverage
  reduction_diff <- astral_s$range_reduction - orbitrap_s$range_reduction

  better <- ifelse(abs(width_diff) < 5, "Similar",
                   ifelse(width_diff < 0, "Astral", "Orbitrap"))

  cat(sprintf("%-15s | Astral\n", tools::toTitleCase(strategies[i])))
  cat(sprintf("%-15s | %8.1f Da | %9.1f%% | %9.1f%% |\n", "",
              astral_s$mean_width,
              astral_s$mean_coverage * 100,
              astral_s$range_reduction * 100))

  cat(sprintf("%-15s | Orbitrap\n", ""))
  cat(sprintf("%-15s | %8.1f Da | %9.1f%% | %9.1f%% | %10s\n", "",
              orbitrap_s$mean_width,
              orbitrap_s$mean_coverage * 100,
              orbitrap_s$range_reduction * 100,
              better))
  cat("────────────────────────────────────────────────────────────────────\n")
}

cat("\n─── STAGE 3D: WINDOW GENERATION (Variable Mode) ───\n")
cat(sprintf("%-15s | %10s | %10s | %10s | %10s\n",
            "Strategy", "Total Win.", "Coverage", "Mean Width", "Better For"))
cat("────────────────────────────────────────────────────────────────────\n")

for (i in seq_along(strategies)) {
  astral_s <- astral$stage3d[[i]][[2]]  # Variable mode is 2nd
  orbitrap_s <- orbitrap$stage3d[[i]][[2]]

  window_diff <- astral_s$n_windows - orbitrap_s$n_windows
  coverage_diff <- astral_s$coverage - orbitrap_s$coverage

  better <- ifelse(abs(coverage_diff) < 0.01, "Similar",
                   ifelse(coverage_diff > 0, "Astral", "Orbitrap"))

  cat(sprintf("%-15s | Astral\n", tools::toTitleCase(strategies[i])))
  cat(sprintf("%-15s | %10d | %9.1f%% | %8.1f Da |\n", "",
              astral_s$n_windows,
              astral_s$coverage * 100,
              astral_s$mean_width))

  cat(sprintf("%-15s | Orbitrap\n", ""))
  cat(sprintf("%-15s | %10d | %9.1f%% | %8.1f Da | %10s\n", "",
              orbitrap_s$n_windows,
              orbitrap_s$coverage * 100,
              orbitrap_s$mean_width,
              better))
  cat("────────────────────────────────────────────────────────────────────\n")
}

cat("\n─── PERFORMANCE TIMING ───\n")
cat(sprintf("%-20s | %10s | %10s | %10s\n", "Stage", "Astral", "Orbitrap", "Difference"))
cat("────────────────────────────────────────────────────────────────────\n")
cat(sprintf("%-20s | %8.2f s | %8.2f s | %9.2f s\n", "Stage 1",
            astral$timing$stage1_sec, orbitrap$timing$stage1_sec,
            orbitrap$timing$stage1_sec - astral$timing$stage1_sec))
cat(sprintf("%-20s | %8.2f s | %8.2f s | %9.2f s\n", "Stage 2",
            astral$timing$stage2_sec, orbitrap$timing$stage2_sec,
            orbitrap$timing$stage2_sec - astral$timing$stage2_sec))
cat(sprintf("%-20s | %8.2f s | %8.2f s | %9.2f s\n", "Stage 3A",
            astral$timing$stage3a_sec, orbitrap$timing$stage3a_sec,
            orbitrap$timing$stage3a_sec - astral$timing$stage3a_sec))
cat(sprintf("%-20s | %8.2f s | %8.2f s | %9.2f s\n", "Stage 3B",
            astral$timing$stage3b_sec, orbitrap$timing$stage3b_sec,
            orbitrap$timing$stage3b_sec - astral$timing$stage3b_sec))
cat(sprintf("%-20s | %8.2f s | %8.2f s | %9.2f s\n", "Stage 3C",
            astral$timing$stage3c_sec, orbitrap$timing$stage3c_sec,
            orbitrap$timing$stage3c_sec - astral$timing$stage3c_sec))
cat(sprintf("%-20s | %8.2f s | %8.2f s | %9.2f s\n", "Stage 3D",
            astral$timing$stage3d_sec, orbitrap$timing$stage3d_sec,
            orbitrap$timing$stage3d_sec - astral$timing$stage3d_sec))
cat("────────────────────────────────────────────────────────────────────\n")
cat(sprintf("%-20s | %8.2f s | %8.2f s | %9.2f s\n", "TOTAL",
            astral$timing$total_sec, orbitrap$timing$total_sec,
            orbitrap$timing$total_sec - astral$timing$total_sec))

cat("\n╔═══════════════════════════════════════════════════════════════╗\n")
cat("║                    KEY DIFFERENCES                            ║\n")
cat("╚═══════════════════════════════════════════════════════════════╝\n\n")

cat("🔬 INSTRUMENT CHARACTERISTICS:\n")
cat("  Astral:\n")
cat("    - Parallel acquisition (MS2 during MS1)\n")
cat(sprintf("    - %d windows per RT bin\n", astral$stage3a$n_windows))
cat(sprintf("    - Cycle time: %.3f sec\n", astral$stage3a$calculated_cycle_time_sec))
cat(sprintf("    - Total windows: %d\n", astral$stage3d[[1]][[2]]$n_windows))
cat("\n")
cat("  Orbitrap:\n")
cat("    - Sequential acquisition (MS1 then MS2)\n")
cat(sprintf("    - %d windows per RT bin\n", orbitrap$stage3a$n_windows))
cat(sprintf("    - Cycle time: %.3f sec\n", orbitrap$stage3a$calculated_cycle_time_sec))
cat(sprintf("    - Total windows: %d\n", orbitrap$stage3d[[1]][[2]]$n_windows))

window_diff_pct <- ((astral$stage3a$n_windows - orbitrap$stage3a$n_windows) /
                    orbitrap$stage3a$n_windows) * 100

cat(sprintf("\n💡 WINDOW COUNT: Astral has %.0f%% more windows per RT bin\n", window_diff_pct))
cat("   → More windows = narrower windows = better MS2 specificity\n")

cat("\n⚡ CYCLE TIME:\n")
cat(sprintf("   Astral:    %.3f sec (%.0f%% faster)\n",
            astral$stage3a$calculated_cycle_time_sec,
            (1 - astral$stage3a$calculated_cycle_time_sec / orbitrap$stage3a$calculated_cycle_time_sec) * 100))
cat(sprintf("   Orbitrap:  %.3f sec\n", orbitrap$stage3a$calculated_cycle_time_sec))

cat("\n📊 COVERAGE (Smoothing + Variable Mode):\n")
astral_cov <- astral$stage3d[[4]][[2]]$coverage * 100
orbitrap_cov <- orbitrap$stage3d[[4]][[2]]$coverage * 100
cat(sprintf("   Astral:    %.1f%%\n", astral_cov))
cat(sprintf("   Orbitrap:  %.1f%%\n", orbitrap_cov))
if (abs(astral_cov - orbitrap_cov) < 1) {
  cat("   → Similar coverage despite different window counts\n")
}

cat("\n✨ RECOMMENDED CONFIGURATION:\n")
cat("  Both Instruments:\n")
cat("    - Strategy: Smoothing (continuous)\n")
cat("    - Mode: Variable (density-based)\n")
cat("    - RT bins: 5-minute intervals\n")
cat(sprintf("    - Astral: %d windows/bin × %d bins = %d total windows\n",
            astral$stage3a$n_windows, astral$stage3b$n_segments,
            astral$stage3d[[4]][[2]]$n_windows))
cat(sprintf("    - Orbitrap: %d windows/bin × %d bins = %d total windows\n",
            orbitrap$stage3a$n_windows, orbitrap$stage3b$n_segments,
            orbitrap$stage3d[[4]][[2]]$n_windows))

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("✅ COMPARISON COMPLETE\n")
cat("═══════════════════════════════════════════════════════════════\n")
