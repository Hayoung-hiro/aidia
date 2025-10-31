# Recalculate 70% satisfaction cycle time - CORRECT METHOD

library(arrow)
library(dplyr)

source("R/utils_common.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║     Correct Calculation: 70% Satisfaction Cycle Time          ║\n")
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

cat("═══════════════════════════════════════════════════════════════\n")
cat("Method 1: Using calculate_required_cycle_time logic from Stage 2\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# Find FWHM at (1 - target_satisfaction) percentile
# This is the FWHM value where 70% of precursors have LONGER FWHM
critical_percentile <- 1 - target_satisfaction  # 0.30
fwhm_critical <- quantile(fwhm_sec, critical_percentile, names = FALSE)

cat(sprintf("Target satisfaction: %.0f%%\n", target_satisfaction * 100))
cat(sprintf("Critical percentile: %.0f%% (shortest 30%% of FWHMs)\n",
            critical_percentile * 100))
cat(sprintf("FWHM at %.0f%% percentile: %.2f sec\n\n",
            critical_percentile * 100, fwhm_critical))

# Required cycle time calculation
# For 70% to achieve DPPP >= 7.0, we need cycle time such that
# even the 30th percentile FWHM achieves DPPP = 7.0
required_cycle_time <- (fwhm_critical * 1.7) / target_dppp

cat(sprintf("Required cycle time = (%.2f × 1.7) / %.1f\n", fwhm_critical, target_dppp))
cat(sprintf("                    = %.2f / %.1f\n", fwhm_critical * 1.7, target_dppp))
cat(sprintf("                    = %.3f sec\n\n", required_cycle_time))

# Round to instrument precision
required_cycle_time_rounded <- round(required_cycle_time, 2)
cat(sprintf("Rounded to instrument precision: %.2f sec\n\n", required_cycle_time_rounded))

cat("═══════════════════════════════════════════════════════════════\n")
cat("Method 2: Fine-grained search for exact 70%\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# Search with fine granularity
cycle_times <- seq(0.5, 2.0, by = 0.01)
results <- data.frame()

for (ct in cycle_times) {
  dppp <- (fwhm_sec * 1.7) / ct
  satisfaction <- mean(dppp >= target_dppp, na.rm = TRUE)

  results <- rbind(results, data.frame(
    cycle_time = ct,
    satisfaction_pct = satisfaction * 100
  ))
}

# Find closest to 70%
diff <- abs(results$satisfaction_pct - 70)
best_idx <- which.min(diff)
best_cycle_time <- results$cycle_time[best_idx]
best_satisfaction <- results$satisfaction_pct[best_idx]

cat(sprintf("Searching %d cycle time values from %.2f to %.2f sec...\n\n",
            nrow(results), min(cycle_times), max(cycle_times)))

cat(sprintf("✅ Best match: %.2f sec → %.2f%% satisfaction\n",
            best_cycle_time, best_satisfaction))
cat(sprintf("   Difference from target 70%%: %.2f%%\n\n",
            abs(best_satisfaction - 70)))

# Show values around 70%
cat("Cycle times near 70% satisfaction:\n")
cat("─────────────────────────────────────────────────────────────\n")
near_70 <- results[abs(results$satisfaction_pct - 70) < 5, ]
print(near_70, row.names = FALSE)
cat("\n")

cat("═══════════════════════════════════════════════════════════════\n")
cat("Verification with actual calculation:\n")
cat("═══════════════════════════════════════════════════════════════\n")

# Test the rounded required_cycle_time
dppp_at_required <- (fwhm_sec * 1.7) / required_cycle_time_rounded
satisfaction_at_required <- mean(dppp_at_required >= target_dppp, na.rm = TRUE)
n_satisfied <- sum(dppp_at_required >= target_dppp, na.rm = TRUE)

cat(sprintf("At cycle time = %.2f sec:\n", required_cycle_time_rounded))
cat(sprintf("  Mean DPPP: %.2f\n", mean(dppp_at_required, na.rm = TRUE)))
cat(sprintf("  Median DPPP: %.2f\n", median(dppp_at_required, na.rm = TRUE)))
cat(sprintf("  Satisfaction: %.2f%% (%d / %d precursors)\n\n",
            satisfaction_at_required * 100, n_satisfied, length(fwhm_sec)))

cat("═══════════════════════════════════════════════════════════════\n")
cat("CONCLUSION:\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat(sprintf("Required cycle time for 70%% satisfaction: %.2f sec\n",
            required_cycle_time_rounded))
cat(sprintf("Actual satisfaction achieved: %.2f%%\n\n",
            satisfaction_at_required * 100))
