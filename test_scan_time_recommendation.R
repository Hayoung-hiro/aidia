# test_scan_time_recommendation.R
# Test scan_time optimization for different DPPP strategies

library(arrow)
library(dplyr)

source("R/dppp_analyzer_enhanced.R")

cat("==============================================\n")
cat("   Scan Time Optimization Test\n")
cat("==============================================\n")

# Load data
cat("\n[1] Loading data...\n")
data <- read_parquet("rawfile/report.parquet")
cat(sprintf("✓ Loaded %d precursors\n", nrow(data)))

# Current baseline
cat("\n[2] Current baseline (scan_time = 2.0 sec)...\n")
baseline <- analyze_dppp_distribution(
  data,
  scan_time = 2.0,
  target_dppp = 1.25,
  dppp_tolerance = 0.1
)

cat("\n==============================================\n")
cat("   STRATEGY 1: ID-Focused (DPPP = 1.5)\n")
cat("==============================================\n")

# Strategy 1: ID-focused (DPPP = 1.5)
cat("\n[3] Calculating optimal scan_time for DPPP = 1.5...\n")
strategy1 <- calculate_optimal_scan_time(
  data,
  target_dppp = 1.5,
  target_satisfaction_ratio = 0.80,
  dppp_tolerance = 0.15,  # Wider tolerance for feasibility
  scan_time_range = c(6.0, 12.0),  # Longer scan times needed
  n_steps = 50
)

cat("\n--- Strategy 1 Summary ---\n")
cat(sprintf("Target DPPP: 1.5 (ID-focused)\n"))
cat(sprintf("Recommended scan_time: %.2f seconds\n", strategy1$optimal_scan_time))
cat(sprintf("Expected DPPP satisfaction: %.1f%%\n", strategy1$achieved_satisfaction * 100))
cat(sprintf("Expected mean DPPP: %.2f\n", strategy1$achieved_dppp))
cat(sprintf("Window count impact: %.0f%% vs baseline\n",
            (strategy1$window_count_ratio - 1) * 100))
cat(sprintf("Cycle time increase: %.2fx\n", strategy1$optimal_scan_time / 2.0))

cat("\n==============================================\n")
cat("   STRATEGY 2: Quant-Focused (DPPP = 7.0)\n")
cat("==============================================\n")

# Strategy 2: Quantification-focused (DPPP = 7.0)
cat("\n[4] Calculating optimal scan_time for DPPP = 7.0...\n")
strategy2 <- calculate_optimal_scan_time(
  data,
  target_dppp = 7.0,
  target_satisfaction_ratio = 0.80,
  dppp_tolerance = 0.7,  # 10% tolerance
  scan_time_range = c(1.0, 3.0),  # Shorter scan times
  n_steps = 50
)

cat("\n--- Strategy 2 Summary ---\n")
cat(sprintf("Target DPPP: 7.0 (Quant-focused)\n"))
cat(sprintf("Recommended scan_time: %.2f seconds\n", strategy2$optimal_scan_time))
cat(sprintf("Expected DPPP satisfaction: %.1f%%\n", strategy2$achieved_satisfaction * 100))
cat(sprintf("Expected mean DPPP: %.2f\n", strategy2$achieved_dppp))
cat(sprintf("Window count impact: %.0f%% vs baseline\n",
            (strategy2$window_count_ratio - 1) * 100))
cat(sprintf("Cycle time change: %.2fx\n", strategy2$optimal_scan_time / 2.0))

cat("\n==============================================\n")
cat("   COMPARISON TABLE\n")
cat("==============================================\n")

comparison <- data.frame(
  Strategy = c("Current (baseline)", "ID-focused", "Quant-focused"),
  Target_DPPP = c(1.25, 1.5, 7.0),
  Scan_Time = c(2.0, strategy1$optimal_scan_time, strategy2$optimal_scan_time),
  Achieved_DPPP = c(baseline$stats$mean, strategy1$achieved_dppp, strategy2$achieved_dppp),
  Satisfaction = c(
    baseline$satisfaction$satisfaction_ratio * 100,
    strategy1$achieved_satisfaction * 100,
    strategy2$achieved_satisfaction * 100
  ),
  Window_Count_Ratio = c(1.0, strategy1$window_count_ratio, strategy2$window_count_ratio),
  Cycle_Time_Ratio = c(1.0, strategy1$optimal_scan_time / 2.0, strategy2$optimal_scan_time / 2.0)
)

print(comparison)

cat("\n==============================================\n")
cat("   DETAILED ANALYSIS\n")
cat("==============================================\n")

# Calculate FWHM statistics for interpretation
fwhm_stats <- data %>%
  filter(!is.na(FWHM), FWHM > 0) %>%
  summarise(
    mean_fwhm_min = mean(FWHM),
    median_fwhm_min = median(FWHM),
    mean_fwhm_sec = mean(FWHM) * 60,
    median_fwhm_sec = median(FWHM) * 60
  )

cat("\n--- FWHM Statistics ---\n")
cat(sprintf("Mean FWHM: %.3f min (%.1f sec)\n",
            fwhm_stats$mean_fwhm_min, fwhm_stats$mean_fwhm_sec))
cat(sprintf("Median FWHM: %.3f min (%.1f sec)\n",
            fwhm_stats$median_fwhm_min, fwhm_stats$median_fwhm_sec))

# Verify DPPP formula
cat("\n--- DPPP Calculation Verification ---\n")
cat("Formula: DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds\n\n")

for (i in 1:nrow(comparison)) {
  peak_width <- 1.7 * fwhm_stats$mean_fwhm_sec
  calculated_dppp <- peak_width / comparison$Scan_Time[i]

  cat(sprintf("%s:\n", comparison$Strategy[i]))
  cat(sprintf("  Peak width: 1.7 × %.1f = %.1f sec\n",
              fwhm_stats$mean_fwhm_sec, peak_width))
  cat(sprintf("  Cycle time: %.2f sec\n", comparison$Scan_Time[i]))
  cat(sprintf("  Calculated DPPP: %.1f / %.2f = %.2f\n",
              peak_width, comparison$Scan_Time[i], calculated_dppp))
  cat(sprintf("  Observed DPPP: %.2f\n", comparison$Achieved_DPPP[i]))
  cat(sprintf("  Difference: %.2f%%\n\n",
              abs(calculated_dppp - comparison$Achieved_DPPP[i]) / calculated_dppp * 100))
}

cat("==============================================\n")
cat("   PRACTICAL RECOMMENDATIONS\n")
cat("==============================================\n")

cat("\n1. ID-FOCUSED STRATEGY (DPPP = 1.5):\n")
cat(sprintf("   → Use scan_time = %.2f sec\n", strategy1$optimal_scan_time))
cat(sprintf("   → Expect ~%.0f%% more windows than current\n",
            (strategy1$window_count_ratio - 1) * 100))
cat("   → Pros: Better selectivity, lower co-isolation\n")
cat("   → Cons: Longer cycle time, fewer data points per peak\n")
cat("   → Best for: Discovery proteomics, low-abundance targets\n")

cat("\n2. QUANT-FOCUSED STRATEGY (DPPP = 7.0):\n")
cat(sprintf("   → Use scan_time = %.2f sec\n", strategy2$optimal_scan_time))
cat(sprintf("   → Expect ~%.0f%% window count change\n",
            (strategy2$window_count_ratio - 1) * 100))
cat("   → Pros: More data points, better quantification accuracy\n")
cat("   → Cons: More co-isolation, potential interference\n")
cat("   → Best for: Targeted quantification, high-abundance proteins\n")

cat("\n3. CURRENT BASELINE (DPPP = 7.23):\n")
cat("   → Current scan_time = 2.0 sec is close to quant-focused\n")
cat("   → Already optimized for quantification accuracy\n")
cat("   → If more IDs needed, switch to Strategy 1\n")

cat("\n==============================================\n")
cat("   VISUALIZATION\n")
cat("==============================================\n")

# Create visualizations
if (!dir.exists("test_output")) {
  dir.create("test_output", recursive = TRUE)
}

# Plot satisfaction curves for both strategies
library(ggplot2)

# Combine curves
curve1 <- strategy1$scan_time_curve %>%
  mutate(Strategy = "ID-focused (DPPP=1.5)")

curve2 <- strategy2$scan_time_curve %>%
  mutate(Strategy = "Quant-focused (DPPP=7.0)")

combined_curves <- bind_rows(curve1, curve2)

p_curves <- ggplot(combined_curves, aes(x = scan_time, y = satisfaction_ratio, color = Strategy)) +
  geom_line(size = 1.2) +
  geom_point(alpha = 0.3) +
  geom_vline(xintercept = strategy1$optimal_scan_time, color = "#E74C3C",
             linetype = "dashed", alpha = 0.7) +
  geom_vline(xintercept = strategy2$optimal_scan_time, color = "#3498DB",
             linetype = "dashed", alpha = 0.7) +
  geom_vline(xintercept = 2.0, color = "black", linetype = "dotted", alpha = 0.5) +
  scale_color_manual(values = c("ID-focused (DPPP=1.5)" = "#E74C3C",
                                 "Quant-focused (DPPP=7.0)" = "#3498DB")) +
  labs(
    title = "Scan Time Optimization for Different Strategies",
    subtitle = sprintf("ID-focused: %.2f sec | Quant-focused: %.2f sec | Current: 2.0 sec",
                      strategy1$optimal_scan_time, strategy2$optimal_scan_time),
    x = "Scan Time (seconds)",
    y = "DPPP Satisfaction Ratio"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 10),
    legend.position = "bottom"
  ) +
  scale_y_continuous(labels = scales::percent) +
  annotate("text", x = 2.0, y = 0.05, label = "Current", angle = 90, vjust = -0.5)

ggsave(
  "test_output/scan_time_strategy_comparison.png",
  p_curves,
  width = 12,
  height = 8,
  dpi = 300
)

cat("\n✓ Saved: test_output/scan_time_strategy_comparison.png\n")

cat("\n==============================================\n")
cat("   TEST COMPLETED\n")
cat("==============================================\n")
