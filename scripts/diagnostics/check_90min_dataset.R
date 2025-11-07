# Check 90min_report.parquet characteristics

library(arrow)
library(dplyr)

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          90min Dataset Characteristics                        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load raw data
data <- read_parquet('data/90min_report.parquet')

cat(sprintf("Total rows: %s\n", format(nrow(data), big.mark = ",")))
cat(sprintf("Total columns: %d\n\n", ncol(data)))

# Check FWHM
if ('FWHM' %in% colnames(data)) {
  fwhm_min <- data$FWHM
  fwhm_sec <- fwhm_min * 60

  cat("FWHM distribution (seconds):\n")
  cat(sprintf("  Mean: %.2f sec\n", mean(fwhm_sec, na.rm = TRUE)))
  cat(sprintf("  Median: %.2f sec\n", median(fwhm_sec, na.rm = TRUE)))
  cat(sprintf("  SD: %.2f sec\n", sd(fwhm_sec, na.rm = TRUE)))
  cat(sprintf("  Range: %.2f - %.2f sec\n\n",
              min(fwhm_sec, na.rm = TRUE),
              max(fwhm_sec, na.rm = TRUE)))

  # Test DPPP at different cycle times
  test_cycle_times <- c(1.18, 1.2, 2.0)
  target_dppp <- 7.0

  cat("═══════════════════════════════════════════════════════════════\n")
  cat("DPPP Satisfaction at Different Cycle Times:\n")
  cat("═══════════════════════════════════════════════════════════════\n\n")

  for (ct in test_cycle_times) {
    dppp <- (fwhm_sec * 1.7) / ct
    satisfaction <- mean(dppp >= target_dppp, na.rm = TRUE)
    n_satisfied <- sum(dppp >= target_dppp, na.rm = TRUE)

    cat(sprintf("Cycle time: %.2f sec\n", ct))
    cat(sprintf("  Mean DPPP: %.2f\n", mean(dppp, na.rm = TRUE)))
    cat(sprintf("  Median DPPP: %.2f\n", median(dppp, na.rm = TRUE)))
    cat(sprintf("  Satisfaction: %.1f%% (%s / %s)\n\n",
                satisfaction * 100,
                format(n_satisfied, big.mark = ","),
                format(length(fwhm_sec), big.mark = ",")))
  }

  # Find cycle time for 70% satisfaction
  cat("═══════════════════════════════════════════════════════════════\n")
  cat("Finding Cycle Time for 70% Satisfaction:\n")
  cat("═══════════════════════════════════════════════════════════════\n\n")

  critical_percentile <- 0.30
  fwhm_critical <- quantile(fwhm_sec, critical_percentile, names = FALSE)
  required_cycle_time <- (fwhm_critical * 1.7) / target_dppp
  required_cycle_time_rounded <- round(required_cycle_time, 2)

  cat(sprintf("FWHM at 30%% percentile: %.2f sec\n", fwhm_critical))
  cat(sprintf("Required cycle time: %.2f sec\n", required_cycle_time_rounded))

  # Verify
  dppp_verify <- (fwhm_sec * 1.7) / required_cycle_time_rounded
  satisfaction_verify <- mean(dppp_verify >= target_dppp, na.rm = TRUE)

  cat(sprintf("Actual satisfaction at %.2f sec: %.1f%%\n\n",
              required_cycle_time_rounded,
              satisfaction_verify * 100))

} else {
  cat("ERROR: FWHM column not found!\n")
}
