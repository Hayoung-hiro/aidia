# =============================================================================
# Stage 4 Plot Review and Diagnosis
# =============================================================================
# Purpose: Review each plot, identify issues, and document required fixes
# =============================================================================

library(arrow)
library(dplyr)
library(ggplot2)

# Source modules
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/visualization.R")
source("R/config_loader.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          Stage 4 Plot Review & Diagnosis                      ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load test configuration
config <- load_optimization_config("config/test_config.json")

# Run pipeline to get all stage outputs
cat("Step 1: Running pipeline to get data...\n")
cat("─────────────────────────────────────────────────────────────\n")

validated_data <- create_validated_dataset(
  proteome_file = "data/30min_report.parquet",
  apply_quality_filters = TRUE
)

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 1.2,
  instrument_preset = config$instrument$preset,
  target_dppp = config$dppp_parameters$target_dppp,
  target_satisfaction = config$dppp_parameters$target_satisfaction,
  dppp_tolerance = 0.0,
  load_factor = config$scan_settings$load_factor,
  ms1_scans_per_cycle = config$scan_settings$ms1_scans_per_cycle
)

windows_result <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = config$rt_binning$rt_bin_width_min,
  mz_strategy = "quantile",
  window_mode = "fixed",
  target_coverage = 0.95,
  min_width_da = config$window_generation$min_width_da,
  max_width_da = config$window_generation$max_width_da
)

cat(sprintf("✅ Pipeline data ready: %s precursors, %d windows\n\n",
            format(nrow(validated_data$data), big.mark = ","),
            nrow(windows_result$windows)))

# =============================================================================
# Review Each Plot
# =============================================================================

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    PLOT REVIEW                                 ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# -----------------------------------------------------------------------------
# Plot 1: DPPP Density Heatmap
# -----------------------------------------------------------------------------
cat("[1/8] DPPP Density Heatmap\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Purpose: Show DPPP distribution across RT × m/z space\n")
cat("Expected: 2D heatmap with DPPP values, target line overlay\n\n")

cat("Data structure check:\n")
cat(sprintf("  - Precursors: %s\n", format(nrow(validated_data$data), big.mark = ",")))
cat(sprintf("  - RT range: %.1f - %.1f min\n",
            min(validated_data$data$RT.Start),
            max(validated_data$data$RT.Start)))
cat(sprintf("  - m/z range: %.1f - %.1f\n",
            min(validated_data$data$Precursor.Mz),
            max(validated_data$data$Precursor.Mz)))
cat(sprintf("  - Target DPPP: %.1f\n", optimization_plan$target_dppp))
cat(sprintf("  - Actual cycle time: %.3f sec\n", optimization_plan$actual_cycle_time_sec))

# Calculate DPPP for a few samples
sample_dppp <- validated_data$data %>%
  head(5) %>%
  mutate(dppp = (FWHM * 60 * 1.7) / optimization_plan$actual_cycle_time_sec) %>%
  select(RT.Start, Precursor.Mz, FWHM, dppp)

cat("\nSample DPPP calculations:\n")
print(sample_dppp)
cat("\n")

# -----------------------------------------------------------------------------
# Plot 2: RT Window Size Distribution
# -----------------------------------------------------------------------------
cat("[2/8] RT Window Size Distribution\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Purpose: Show how many windows are allocated to each RT segment\n")
cat("Expected: Bar chart with window counts per RT bin\n\n")

cat("Data structure check:\n")
rt_summary <- windows_result$windows %>%
  group_by(rt_segment_id) %>%
  summarise(
    n_windows = n(),
    rt_start = first(rt_start),
    rt_end = first(rt_end)
  )
print(rt_summary)
cat("\n")

# -----------------------------------------------------------------------------
# Plot 3: RT × m/z Density Heatmap
# -----------------------------------------------------------------------------
cat("[3/8] RT × m/z Density Heatmap\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Purpose: Show precursor density distribution across RT × m/z space\n")
cat("Expected: 2D heatmap showing where precursors are concentrated\n\n")

cat("Data structure check:\n")
cat(sprintf("  - Total precursors: %s\n", format(nrow(validated_data$data), big.mark = ",")))
cat(sprintf("  - RT span: %.1f min\n",
            max(validated_data$data$RT.Start) - min(validated_data$data$RT.Start)))
cat(sprintf("  - m/z span: %.1f Da\n",
            max(validated_data$data$Precursor.Mz) - min(validated_data$data$Precursor.Mz)))
cat("\n")

# -----------------------------------------------------------------------------
# Plot 4: m/z Normalized Density
# -----------------------------------------------------------------------------
cat("[4/8] m/z Normalized Density\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Purpose: Show m/z density normalized across RT\n")
cat("Expected: Line plots showing density per RT segment with window overlays\n\n")

cat("Data structure check:\n")
cat(sprintf("  - RT segments: %d\n", length(unique(windows_result$windows$rt_segment_id))))
cat(sprintf("  - Windows per segment:\n"))
windows_per_seg <- windows_result$windows %>%
  count(rt_segment_id)
print(windows_per_seg)
cat("\n")

# -----------------------------------------------------------------------------
# Plot 5: Window Width Distribution
# -----------------------------------------------------------------------------
cat("[5/8] Window Width Distribution\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Purpose: Show distribution of window widths across m/z\n")
cat("Expected: Scatter plot with window width vs. m/z center\n\n")

cat("Window width statistics:\n")
width_stats <- windows_result$windows %>%
  summarise(
    mean_width = mean(window_width),
    sd_width = sd(window_width),
    min_width = min(window_width),
    max_width = max(window_width)
  )
print(width_stats)
cat("\n")

# -----------------------------------------------------------------------------
# Plot 6: Precursor Coverage Map
# -----------------------------------------------------------------------------
cat("[6/8] Precursor Coverage Map\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Purpose: Show which precursors are covered by windows\n")
cat("Expected: Scatter plot of precursors colored by coverage status\n\n")

cat("⚠️  WARNING: This plot is 1.5MB - may be too detailed\n")
cat("Coverage calculation is expensive for large datasets\n\n")

# Check if windows have window_id field
cat("Window structure check:\n")
cat("Columns:", paste(names(windows_result$windows), collapse = ", "), "\n")
cat("\n")

# -----------------------------------------------------------------------------
# Plot 7: Window Efficiency
# -----------------------------------------------------------------------------
cat("[7/8] Window Efficiency\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Purpose: Show how many precursors are in each window\n")
cat("Expected: Histogram or boxplot of precursors per window\n\n")

cat("Efficiency statistics:\n")
cat(sprintf("  - Total windows: %d\n", nrow(windows_result$windows)))
cat(sprintf("  - Mean precursors/window: %.1f\n",
            windows_result$statistics$mean_precursors_per_window))
cat(sprintf("  - CV: %.2f\n", windows_result$statistics$cv_precursors))
cat("\n")

# -----------------------------------------------------------------------------
# Plot 8: DPPP Achievement Heatmap
# -----------------------------------------------------------------------------
cat("[8/8] DPPP Achievement Heatmap\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("Purpose: Show which windows achieve target DPPP\n")
cat("Expected: Heatmap of windows colored by DPPP achievement\n\n")

cat("⚠️  WARNING: Test output showed NA conversion warnings\n")
cat("Issue: window_id may not be in the correct format for numeric conversion\n\n")

cat("Window ID format check:\n")
if ("window_id" %in% names(windows_result$windows)) {
  cat("Sample window IDs:\n")
  print(head(windows_result$windows$window_id, 10))
} else {
  cat("❌ window_id column not found!\n")
}
cat("\n")

# =============================================================================
# Summary of Issues
# =============================================================================

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    IDENTIFIED ISSUES                           ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("1. Plot 6 (Coverage Map): 1.5MB file size - too detailed\n")
cat("   → Consider: Binning, sampling, or alternative visualization\n\n")

cat("2. Plot 8 (Achievement Heatmap): window_id conversion warnings\n")
cat("   → Issue: Converting character window_id to integer fails\n")
cat("   → Fix: Use factor levels or keep as character\n\n")

cat("3. General: 34 tiles removed from heatmap (missing values)\n")
cat("   → May indicate sparse data or incorrect binning\n\n")

cat("4. min/max warnings: NA values in distance calculations\n")
cat("   → Need to handle missing values gracefully\n\n")

cat("═══════════════════════════════════════════════════════════════\n")
cat("Next: Review actual plot images and identify visual issues\n")
cat("═══════════════════════════════════════════════════════════════\n\n")
