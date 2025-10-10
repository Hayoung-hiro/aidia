# test_fwhm_visualization.R - Test RT-dependent FWHM patterns

library(arrow)
library(dplyr)
library(ggplot2)

source("R/fwhm_visualization.R")

cat("==============================================\n")
cat("   RT-Dependent FWHM Analysis\n")
cat("==============================================\n")

# Load data
cat("\n[1] Loading data...\n")
data <- read_parquet("rawfile/report.parquet")
cat(sprintf("✓ Loaded %d precursors\n", nrow(data)))

# Basic statistics
cat("\n[2] FWHM Statistics...\n")
fwhm_stats <- data %>%
  filter(!is.na(FWHM), FWHM > 0) %>%
  summarise(
    n = n(),
    mean_fwhm_min = mean(FWHM),
    median_fwhm_min = median(FWHM),
    sd_fwhm_min = sd(FWHM),
    min_fwhm_min = min(FWHM),
    max_fwhm_min = max(FWHM),
    mean_fwhm_sec = mean(FWHM) * 60,
    median_fwhm_sec = median(FWHM) * 60
  )

print(fwhm_stats)

cat("\n--- DPPP Relationship ---\n")
cat("For current scan_time = 2.0 sec:\n")
peak_width <- 1.7 * fwhm_stats$mean_fwhm_sec
dppp_current <- peak_width / 2.0
cat(sprintf("  Mean peak width: 1.7 × %.1f = %.1f sec\n",
            fwhm_stats$mean_fwhm_sec, peak_width))
cat(sprintf("  Mean DPPP: %.1f / 2.0 = %.2f\n", peak_width, dppp_current))
cat(sprintf("\n  CORRECT interpretation:\n"))
cat(sprintf("  - Large FWHM (%.1f sec) → Large peak width (%.1f sec)\n",
            fwhm_stats$max_fwhm_min * 60, 1.7 * fwhm_stats$max_fwhm_min * 60))
cat(sprintf("  - → HIGH DPPP (%.1f data points per peak)\n",
            (1.7 * fwhm_stats$max_fwhm_min * 60) / 2.0))
cat(sprintf("  - → Already sufficient sampling!\n"))

cat(sprintf("\n  - Small FWHM (%.1f sec) → Small peak width (%.1f sec)\n",
            fwhm_stats$min_fwhm_min * 60, 1.7 * fwhm_stats$min_fwhm_min * 60))
cat(sprintf("  - → LOW DPPP (%.1f data points per peak)\n",
            (1.7 * fwhm_stats$min_fwhm_min * 60) / 2.0))
cat(sprintf("  - → Risk of under-sampling!\n"))

# Create output directory
if (!dir.exists("test_output")) {
  dir.create("test_output", recursive = TRUE)
}

cat("\n==============================================\n")
cat("   Creating Visualizations\n")
cat("==============================================\n")

# Plot 1: RT vs FWHM scatter
cat("\n[3] Creating RT vs FWHM scatter plot...\n")
p1 <- plot_rt_vs_fwhm_scatter(data, sample_size = 100000, n_segments = 5)
ggsave(
  "test_output/fwhm_rt_scatter.png",
  p1,
  width = 12,
  height = 8,
  dpi = 300
)
cat("✓ Saved: test_output/fwhm_rt_scatter.png\n")

# Plot 2: FWHM by segments
cat("\n[4] Creating FWHM distribution by segments...\n")
p2 <- plot_fwhm_by_rt_segments(data, n_segments = 5)
ggsave(
  "test_output/fwhm_by_segments.png",
  p2,
  width = 12,
  height = 8,
  dpi = 300
)
cat("✓ Saved: test_output/fwhm_by_segments.png\n")

# Plot 3: FWHM trend
cat("\n[5] Creating FWHM trend with statistics...\n")
p3 <- plot_fwhm_trend_summary(data, rt_bins = 30)
ggsave(
  "test_output/fwhm_trend_summary.png",
  p3,
  width = 12,
  height = 8,
  dpi = 300
)
cat("✓ Saved: test_output/fwhm_trend_summary.png\n")

# Plot 4: FWHM variability
cat("\n[6] Creating FWHM variability analysis...\n")
p4 <- plot_fwhm_cv_by_rt(data, rt_bins = 20)
ggsave(
  "test_output/fwhm_cv_by_rt.png",
  p4,
  width = 12,
  height = 8,
  dpi = 300
)
cat("✓ Saved: test_output/fwhm_cv_by_rt.png\n")

# Comprehensive report
cat("\n[7] Creating comprehensive PDF report...\n")
plots <- create_fwhm_analysis_report(
  data,
  n_segments = 5,
  output_file = "test_output/fwhm_comprehensive_report.pdf"
)

cat("\n==============================================\n")
cat("   RT-Segment Analysis\n")
cat("==============================================\n")

# Analyze FWHM by segments
rt_analysis <- data %>%
  filter(!is.na(RT.Start), !is.na(FWHM), FWHM > 0) %>%
  mutate(
    FWHM_seconds = FWHM * 60,
    RT_segment = cut(RT.Start, breaks = 5, labels = 1:5)
  ) %>%
  group_by(RT_segment) %>%
  summarise(
    RT_min = min(RT.Start),
    RT_max = max(RT.Start),
    n_precursors = n(),
    mean_FWHM_sec = mean(FWHM_seconds),
    median_FWHM_sec = median(FWHM_seconds),
    sd_FWHM_sec = sd(FWHM_seconds),
    CV_percent = (sd_FWHM_sec / mean_FWHM_sec) * 100,
    # Calculate expected DPPP for scan_time=2.0
    expected_DPPP = (1.7 * mean_FWHM_sec) / 2.0,
    .groups = 'drop'
  )

cat("\nFWHM and DPPP by RT Segment (scan_time = 2.0 sec):\n")
print(rt_analysis)

cat("\n=== Key Findings ===\n")
early_segment <- rt_analysis %>% slice(1)
late_segment <- rt_analysis %>% slice(n())

cat(sprintf("\nEarly RT (%.1f-%.1f min):\n", early_segment$RT_min, early_segment$RT_max))
cat(sprintf("  Mean FWHM: %.2f sec\n", early_segment$mean_FWHM_sec))
cat(sprintf("  Expected DPPP: %.2f\n", early_segment$expected_DPPP))
if (early_segment$expected_DPPP > 5) {
  cat("  → Large FWHM → HIGH DPPP → Over-sampling\n")
  cat("  → Could use FEWER windows or LONGER scan_time\n")
} else {
  cat("  → Small FWHM → LOW DPPP → Under-sampling\n")
  cat("  → Need MORE windows or SHORTER scan_time\n")
}

cat(sprintf("\nLate RT (%.1f-%.1f min):\n", late_segment$RT_min, late_segment$RT_max))
cat(sprintf("  Mean FWHM: %.2f sec\n", late_segment$mean_FWHM_sec))
cat(sprintf("  Expected DPPP: %.2f\n", late_segment$expected_DPPP))
if (late_segment$expected_DPPP > 5) {
  cat("  → Large FWHM → HIGH DPPP → Over-sampling\n")
  cat("  → Could use FEWER windows or LONGER scan_time\n")
} else {
  cat("  → Small FWHM → LOW DPPP → Under-sampling\n")
  cat("  → Need MORE windows or SHORTER scan_time\n")
}

cat(sprintf("\nFWHM Change: %.2f sec → %.2f sec (%.1f%% change)\n",
            early_segment$mean_FWHM_sec,
            late_segment$mean_FWHM_sec,
            ((late_segment$mean_FWHM_sec - early_segment$mean_FWHM_sec) /
             early_segment$mean_FWHM_sec) * 100))

cat(sprintf("DPPP Change: %.2f → %.2f (%.1f%% change)\n",
            early_segment$expected_DPPP,
            late_segment$expected_DPPP,
            ((late_segment$expected_DPPP - early_segment$expected_DPPP) /
             early_segment$expected_DPPP) * 100))

cat("\n==============================================\n")
cat("   TEST COMPLETED\n")
cat("==============================================\n")
cat("\nGenerated files:\n")
cat("  - test_output/fwhm_rt_scatter.png\n")
cat("  - test_output/fwhm_by_segments.png\n")
cat("  - test_output/fwhm_trend_summary.png\n")
cat("  - test_output/fwhm_cv_by_rt.png\n")
cat("  - test_output/fwhm_comprehensive_report.pdf\n")
