# Find cycle time that achieves 70% satisfaction

library(arrow)
library(dplyr)

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║     Find Cycle Time for 70% Satisfaction                     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load raw data
data <- read_parquet('data/30min_report.parquet')
fwhm_min <- data$FWHM
fwhm_sec <- fwhm_min * 60

cat(sprintf("Total precursors: %s\n", format(length(fwhm_sec), big.mark = ",")))
cat(sprintf("Mean FWHM: %.2f sec\n", mean(fwhm_sec, na.rm = TRUE)))
cat(sprintf("Median FWHM: %.2f sec\n\n", median(fwhm_sec, na.rm = TRUE)))

# Target parameters
target_dppp <- 7.0
target_satisfaction <- 0.70

# Calculate required cycle time using quantile method
# We need the FWHM at (1 - target_satisfaction) percentile
critical_percentile <- 1 - target_satisfaction  # 0.30 = 30th percentile
fwhm_critical <- quantile(fwhm_sec, critical_percentile, names = FALSE)

# Required cycle time: (FWHM_critical × 1.7) / target_dppp
required_cycle_time <- (fwhm_critical * 1.7) / target_dppp

cat("═══════════════════════════════════════════════════════════════\n")
cat("Calculation Method: Quantile-based\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat(sprintf("Target satisfaction: %.0f%%\n", target_satisfaction * 100))
cat(sprintf("Target DPPP: %.1f\n", target_dppp))
cat(sprintf("Critical percentile: %.0f%% (1 - %.2f)\n",
            critical_percentile * 100, target_satisfaction))
cat(sprintf("FWHM at %.0f%% percentile: %.2f sec\n",
            critical_percentile * 100, fwhm_critical))
cat("\n")
cat(sprintf("Required cycle time = (%.2f × 1.7) / %.1f = %.3f sec\n",
            fwhm_critical, target_dppp, required_cycle_time))
cat("\n")

# Round to 2 decimal places (instrument precision)
required_cycle_time_rounded <- round(required_cycle_time, 2)
cat(sprintf("Rounded (instrument precision): %.2f sec\n\n", required_cycle_time_rounded))

# Verify the calculation
cat("═══════════════════════════════════════════════════════════════\n")
cat("Verification:\n")
cat("═══════════════════════════════════════════════════════════════\n")

cycle_times <- seq(0.8, 1.4, by = 0.05)
results <- data.frame()

for (ct in cycle_times) {
  dppp <- (fwhm_sec * 1.7) / ct
  satisfaction <- mean(dppp >= target_dppp, na.rm = TRUE)
  n_satisfied <- sum(dppp >= target_dppp, na.rm = TRUE)

  results <- rbind(results, data.frame(
    cycle_time = ct,
    satisfaction_pct = satisfaction * 100,
    n_satisfied = n_satisfied,
    mean_dppp = mean(dppp, na.rm = TRUE),
    median_dppp = median(dppp, na.rm = TRUE)
  ))

  # Print only values near 70%
  if (abs(satisfaction - 0.70) < 0.10) {
    cat(sprintf("Cycle time: %.2f sec → Satisfaction: %.1f%% (%d / %d)\n",
                ct, satisfaction * 100, n_satisfied, length(fwhm_sec)))
  }
}

cat("\n")

# Find closest to 70%
diff <- abs(results$satisfaction_pct - 70)
best_idx <- which.min(diff)
best_cycle_time <- results$cycle_time[best_idx]
best_satisfaction <- results$satisfaction_pct[best_idx]

cat("═══════════════════════════════════════════════════════════════\n")
cat("Result:\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat(sprintf("✅ Required cycle time: %.2f sec\n", required_cycle_time_rounded))
cat(sprintf("✅ Actual satisfaction: %.1f%%\n", best_satisfaction))
cat(sprintf("✅ Closest match: %.2f sec → %.1f%%\n\n",
            best_cycle_time, best_satisfaction))

# Show full table
cat("Full scan of cycle times:\n")
cat("─────────────────────────────────────────────────────────────\n")
print(results, row.names = FALSE)
cat("\n")
