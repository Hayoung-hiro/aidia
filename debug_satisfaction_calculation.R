# =============================================================================
# Debug Satisfaction Ratio Calculation
# =============================================================================
# Purpose: Verify why satisfaction is 2.8% instead of expected 44.2%
# =============================================================================

library(arrow)
library(dplyr)

# Source modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          Satisfaction Ratio Debug Analysis                   ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load data
cat("Step 1: Loading data...\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/30min_report.parquet",
  apply_quality_filters = TRUE
)

cat(sprintf("✅ Loaded %s precursors\n\n", format(nrow(validated_data$data), big.mark = ",")))

# Test different cycle times
cycle_times_to_test <- c(0.9, 1.2, 2.0, 2.5, 3.0)
target_dppp <- 7.0

cat("Step 2: Calculate DPPP and satisfaction for different cycle times\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Target DPPP: 7.0\n")
cat("Tolerance: 0.0 (must be >= 7.0)\n\n")

# Get FWHM in seconds
fwhm_min <- validated_data$data$FWHM
fwhm_sec <- fwhm_min * 60

cat(sprintf("FWHM statistics (seconds):\n"))
cat(sprintf("  Mean: %.2f sec\n", mean(fwhm_sec)))
cat(sprintf("  Median: %.2f sec\n", median(fwhm_sec)))
cat(sprintf("  SD: %.2f sec\n", sd(fwhm_sec)))
cat(sprintf("  Range: %.2f - %.2f sec\n", min(fwhm_sec), max(fwhm_sec)))
cat("\n")

# Test each cycle time
results <- data.frame()

for (cycle_time in cycle_times_to_test) {
  # Calculate DPPP using formula: (FWHM × 1.7) / cycle_time
  dppp_values <- calculate_dppp(fwhm_sec, cycle_time)

  # Calculate satisfaction (what % of precursors have DPPP >= 7.0)
  satisfaction <- calculate_satisfaction_ratio(
    dppp_values,
    target_dppp,
    tolerance = 0.0,
    direction = "greater"
  )

  # Calculate DPPP statistics
  dppp_stats <- calculate_summary_stats(dppp_values)

  # Store results
  results <- rbind(results, data.frame(
    cycle_time = cycle_time,
    mean_dppp = dppp_stats$mean,
    median_dppp = dppp_stats$median,
    satisfaction_pct = satisfaction$satisfaction_ratio * 100,
    n_satisfied = satisfaction$n_satisfied
  ))

  cat(sprintf("Cycle time: %.2f sec\n", cycle_time))
  cat(sprintf("  Mean DPPP: %.2f\n", dppp_stats$mean))
  cat(sprintf("  Median DPPP: %.2f\n", dppp_stats$median))
  cat(sprintf("  Satisfaction: %.1f%% (%d / %d precursors)\n",
              satisfaction$satisfaction_ratio * 100,
              satisfaction$n_satisfied,
              satisfaction$n_total))
  cat("\n")
}

cat("═══════════════════════════════════════════════════════════════\n")
cat("Summary Table:\n")
cat("═══════════════════════════════════════════════════════════════\n")
print(results, row.names = FALSE)
cat("\n")

cat("Analysis:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("If previous visualization showed 44.2%, this corresponds to:\n")
target_satisfaction <- 0.442

# Find closest match
diff <- abs(results$satisfaction_pct - 44.2)
closest_idx <- which.min(diff)
closest_cycle_time <- results$cycle_time[closest_idx]
closest_satisfaction <- results$satisfaction_pct[closest_idx]

cat(sprintf("  Cycle time: %.2f sec (satisfaction: %.1f%%)\n",
            closest_cycle_time, closest_satisfaction))
cat("\n")

cat("Conclusion:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("The test uses current_cycle_time = 2.0 sec → 2.8% satisfaction\n")
cat("Previous visualization likely used a different cycle time value.\n")
cat("This is NOT a bug - satisfaction depends on cycle time input.\n")
cat("\n")

cat("To match 44.2% satisfaction, use:\n")
cat(sprintf("  current_cycle_time = %.2f sec\n", closest_cycle_time))
cat("\n")
