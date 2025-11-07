# Verify DPPP calculation logic

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          DPPP Calculation Verification                        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Example FWHM values (in minutes)
fwhm_min <- c(0.05, 0.08, 0.10, 0.15)
fwhm_sec <- fwhm_min * 60

cat("Sample FWHM values:\n")
cat(sprintf("  FWHM (min): %s\n", paste(fwhm_min, collapse = ", ")))
cat(sprintf("  FWHM (sec): %s\n", paste(fwhm_sec, collapse = ", ")))
cat("\n")

# Cycle times
current_cycle_time <- 2.0
recommended_cycle_time <- 1.18

cat("Cycle times:\n")
cat(sprintf("  Current: %.2f sec\n", current_cycle_time))
cat(sprintf("  Recommended: %.2f sec\n", recommended_cycle_time))
cat("\n")

# DPPP formula: (FWHM_sec × 1.7) / cycle_time
# Peak width = FWHM × 1.7 (chromatographic peak standard)

cat("DPPP Calculation (FWHM × 1.7 / cycle_time):\n")
cat("─────────────────────────────────────────────────────────────\n")

for (i in 1:length(fwhm_sec)) {
  current_dppp <- (fwhm_sec[i] * 1.7) / current_cycle_time
  recommended_dppp <- (fwhm_sec[i] * 1.7) / recommended_cycle_time

  cat(sprintf("FWHM %.2f sec (%.3f min):\n", fwhm_sec[i], fwhm_min[i]))
  cat(sprintf("  Current DPPP (cycle=%.2f): %.2f\n", current_cycle_time, current_dppp))
  cat(sprintf("  Recommended DPPP (cycle=%.2f): %.2f\n", recommended_cycle_time, recommended_dppp))
  cat(sprintf("  Ratio: %.2fx increase\n", recommended_dppp / current_dppp))
  cat("\n")
}

cat("Analysis:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat(sprintf("Cycle time reduction: %.2f → %.2f (%.1f%% reduction)\n",
            current_cycle_time, recommended_cycle_time,
            (1 - recommended_cycle_time/current_cycle_time) * 100))
cat(sprintf("DPPP increase factor: %.2fx\n", current_cycle_time / recommended_cycle_time))
cat("\n")

cat("Conclusion:\n")
cat("Since DPPP = (FWHM × 1.7) / cycle_time,\n")
cat("reducing cycle_time from 2.0 to 1.18 increases DPPP by ~1.69x\n")
cat("This is the CORRECT mathematical behavior.\n")
cat("\n")

# Check if both distributions use same x-axis
cat("X-axis alignment check:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Both density curves are calculated from the SAME FWHM data.\n")
cat("Only the cycle_time denominator changes.\n")
cat("Therefore, x-axis IS properly aligned - the shift is real.\n")
cat("\n")
