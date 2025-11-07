# Check raw FWHM data from 30min_report.parquet

library(arrow)
library(dplyr)

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          Raw FWHM Data Analysis                               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load raw data (NO quality filters)
data <- read_parquet('data/30min_report.parquet')

cat(sprintf("Total rows: %s\n", format(nrow(data), big.mark = ",")))
cat(sprintf("Total columns: %d\n\n", ncol(data)))

# Check FWHM
if ('FWHM' %in% colnames(data)) {
  fwhm_min <- data$FWHM
  fwhm_sec <- fwhm_min * 60

  cat("FWHM distribution (minutes):\n")
  cat(sprintf("  Mean: %.4f min\n", mean(fwhm_min, na.rm = TRUE)))
  cat(sprintf("  Median: %.4f min\n", median(fwhm_min, na.rm = TRUE)))
  cat(sprintf("  SD: %.4f min\n", sd(fwhm_min, na.rm = TRUE)))
  cat(sprintf("  Range: %.4f - %.4f min\n\n",
              min(fwhm_min, na.rm = TRUE),
              max(fwhm_min, na.rm = TRUE)))

  # Test DPPP at 2.0 sec
  dppp_2sec <- (fwhm_sec * 1.7) / 2.0
  n_satisfied_2sec <- sum(dppp_2sec >= 7.0, na.rm = TRUE)
  satisfaction_2sec <- mean(dppp_2sec >= 7.0, na.rm = TRUE)

  cat("═══════════════════════════════════════════════════════════════\n")
  cat("DPPP at cycle_time = 2.0 sec (NO quality filters):\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat(sprintf("  Mean DPPP: %.2f\n", mean(dppp_2sec, na.rm = TRUE)))
  cat(sprintf("  Median DPPP: %.2f\n", median(dppp_2sec, na.rm = TRUE)))
  cat(sprintf("  Satisfaction (>= 7.0): %.1f%% (%d / %d)\n\n",
              satisfaction_2sec * 100,
              n_satisfied_2sec,
              length(dppp_2sec)))

  # Test DPPP at 1.2 sec
  dppp_1.2sec <- (fwhm_sec * 1.7) / 1.2
  n_satisfied_1.2sec <- sum(dppp_1.2sec >= 7.0, na.rm = TRUE)
  satisfaction_1.2sec <- mean(dppp_1.2sec >= 7.0, na.rm = TRUE)

  cat("DPPP at cycle_time = 1.2 sec:\n")
  cat(sprintf("  Mean DPPP: %.2f\n", mean(dppp_1.2sec, na.rm = TRUE)))
  cat(sprintf("  Median DPPP: %.2f\n", median(dppp_1.2sec, na.rm = TRUE)))
  cat(sprintf("  Satisfaction (>= 7.0): %.1f%% (%d / %d)\n\n",
              satisfaction_1.2sec * 100,
              n_satisfied_1.2sec,
              length(dppp_1.2sec)))

  cat("═══════════════════════════════════════════════════════════════\n")
  cat("Conclusion:\n")
  cat("═══════════════════════════════════════════════════════════════\n")

  if (satisfaction_2sec * 100 > 40) {
    cat("✅ This dataset DOES match your description:\n")
    cat(sprintf("   2.0 sec → %.1f%% satisfaction (expected ~44%%)\n",
                satisfaction_2sec * 100))
    cat(sprintf("   1.2 sec → %.1f%% satisfaction (expected ~70%%)\n",
                satisfaction_1.2sec * 100))
  } else {
    cat("❌ This dataset does NOT match your description:\n")
    cat(sprintf("   2.0 sec → %.1f%% satisfaction (expected ~44%%)\n",
                satisfaction_2sec * 100))
    cat("   Quality filters may be affecting the results.\n")
  }

} else {
  cat("ERROR: FWHM column not found!\n")
}

cat("\n")
