# DPPP Threshold Analysis
# Analyze the impact of requiring DPPP >= 7 for 70% of data

# Load the existing analysis
source("analyze_report.R")

cat("\n=== DPPP Threshold Analysis ===\n")

# Current DPPP distribution analysis
dppp_values <- data$DPPP
total_precursors <- length(dppp_values)

# Calculate current percentages for different DPPP thresholds
thresholds <- c(5, 6, 7, 8, 9, 10)
current_stats <- data.frame(
  DPPP_Threshold = thresholds,
  Count_Above = sapply(thresholds, function(x) sum(dppp_values >= x, na.rm = TRUE)),
  Percentage_Above = sapply(thresholds, function(x) 100 * mean(dppp_values >= x, na.rm = TRUE))
)

print("Current DPPP Distribution:")
print(current_stats)

# Analyze what would happen with DPPP >= 7 target of 70%
target_dppp <- 7
target_percentage <- 70

current_above_7 <- mean(dppp_values >= target_dppp, na.rm = TRUE) * 100
cat(sprintf("\nCurrent status: %.1f%% of precursors have DPPP >= %d\n",
            current_above_7, target_dppp))
cat(sprintf("Target goal: %.1f%% of precursors have DPPP >= %d\n",
            target_percentage, target_dppp))

# What scan time would be needed to achieve 70% above DPPP 7?
# DPPP = (1.7 × FWHM) / cycle_time
# cycle_time = (1.7 × FWHM) / DPPP

# Find the FWHM value at 30th percentile (to get 70% above DPPP 7)
fwhm_30th_percentile <- quantile(data$FWHM, 0.30, na.rm = TRUE)
required_cycle_time_min <- (1.7 * fwhm_30th_percentile) / target_dppp
required_cycle_time_sec <- required_cycle_time_min * 60

cat(sprintf("\nTo achieve 70%% with DPPP >= 7:\n"))
cat(sprintf("Required cycle time: %.3f minutes (%.2f seconds)\n",
            required_cycle_time_min, required_cycle_time_sec))
cat(sprintf("Current cycle time: %.3f minutes (%.1f seconds)\n",
            scan_time_min, scan_time_sec))

# Calculate what percentage would have DPPP >= 7 with different scan times
scan_times_sec <- c(1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4)
optimization_results <- data.frame(
  Scan_Time_Sec = scan_times_sec,
  Cycle_Time_Min = scan_times_sec / 60,
  DPPP_Median = sapply(scan_times_sec, function(t) {
    median((1.7 * data$FWHM) / (t/60), na.rm = TRUE)
  }),
  Percent_Above_DPPP7 = sapply(scan_times_sec, function(t) {
    dppp_calc <- (1.7 * data$FWHM) / (t/60)
    100 * mean(dppp_calc >= 7, na.rm = TRUE)
  }),
  Percent_Above_DPPP5 = sapply(scan_times_sec, function(t) {
    dppp_calc <- (1.7 * data$FWHM) / (t/60)
    100 * mean(dppp_calc >= 5, na.rm = TRUE)
  })
)

cat("\n=== Scan Time Optimization Analysis ===\n")
print(optimization_results)

# Find optimal scan time for 70% above DPPP 7
optimal_idx <- which.min(abs(optimization_results$Percent_Above_DPPP7 - 70))
optimal_scan_time <- optimization_results$Scan_Time_Sec[optimal_idx]
optimal_percentage <- optimization_results$Percent_Above_DPPP7[optimal_idx]

cat(sprintf("\nOptimal scan time for ~70%% above DPPP 7: %.1f seconds\n", optimal_scan_time))
cat(sprintf("This would achieve: %.1f%% above DPPP 7\n", optimal_percentage))

# Quality assessment
cat("\n=== Quality Impact Assessment ===\n")

# With optimal scan time
optimal_dppp <- (1.7 * data$FWHM) / (optimal_scan_time/60)
optimal_median_dppp <- median(optimal_dppp, na.rm = TRUE)
optimal_mean_dppp <- mean(optimal_dppp, na.rm = TRUE)

cat(sprintf("With %.1f second scan time:\n", optimal_scan_time))
cat(sprintf("  Median DPPP: %.2f\n", optimal_median_dppp))
cat(sprintf("  Mean DPPP: %.2f\n", optimal_mean_dppp))
cat(sprintf("  %% above DPPP 7: %.1f%%\n", 100 * mean(optimal_dppp >= 7, na.rm = TRUE)))
cat(sprintf("  %% above DPPP 5: %.1f%%\n", 100 * mean(optimal_dppp >= 5, na.rm = TRUE)))

# Literature/practical considerations
cat("\n=== Practical Considerations ===\n")
cat("DPPP Quality Guidelines:\n")
cat("  DPPP < 3:  Poor quantification, high CV\n")
cat("  DPPP 3-5:  Acceptable for qualitative analysis\n")
cat("  DPPP 5-8:  Good quantification, moderate CV\n")
cat("  DPPP 7-10: Excellent quantification, low CV\n")
cat("  DPPP >10:  Oversampling, diminishing returns\n")

cat(sprintf("\nCurrent approach (%.1f sec): Balanced quality/throughput\n", scan_time_sec))
cat(sprintf("Proposed approach (%.1f sec): Higher quality, lower throughput\n", optimal_scan_time))

# Throughput impact
throughput_ratio <- scan_time_sec / optimal_scan_time
cat(sprintf("\nThroughput impact: %.1fx slower acquisition\n", 1/throughput_ratio))
cat(sprintf("Quality improvement: %.1f%% -> %.1f%% above DPPP 7\n",
            current_above_7, optimal_percentage))

# Create comparison plot
library(ggplot2)

comparison_data <- data.frame(
  Approach = rep(c("Current (2.0s)", sprintf("Proposed (%.1fs)", optimal_scan_time)), each = nrow(data)),
  DPPP = c(data$DPPP, optimal_dppp)
)

p_comparison <- ggplot(comparison_data, aes(x = DPPP, fill = Approach)) +
  geom_density(alpha = 0.6) +
  geom_vline(xintercept = 7, color = "red", linetype = "dashed", size = 1) +
  geom_vline(xintercept = 5, color = "orange", linetype = "dotted", size = 1) +

  labs(
    title = "DPPP Distribution Comparison: Current vs Proposed Scan Time",
    subtitle = sprintf("Target: 70%% above DPPP 7 (red line) | Current: %.1f%% vs Proposed: %.1f%%",
                      current_above_7, optimal_percentage),
    x = "DPPP (Data Points Per Peak)",
    y = "Density",
    fill = "Scan Time Approach"
  ) +

  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11),
    legend.position = "top"
  ) +

  scale_fill_manual(values = c("steelblue", "darkgreen")) +
  xlim(0, 20)

ggsave("dppp_comparison_analysis.png", p_comparison, width = 12, height = 8, dpi = 300)
cat("\nComparison plot saved as: dppp_comparison_analysis.png\n")