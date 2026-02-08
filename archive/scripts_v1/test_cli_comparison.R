# test_cli_comparison.R - Compare CLI and Shiny outputs
# Run with: Rscript test_cli_comparison.R

# Load package
devtools::load_all(".")

# Run Stage 1
cat("\n========== Stage 1: Data Validation ==========\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/30min_report.parquet",
  enable_replicate_consensus = TRUE,
  max_intensity_cv_percent = 30
)

cat("\n========== CLI Results ==========\n")
cat("Precursors:", nrow(validated_data$data), "\n")
cat("RT Range:", min(validated_data$data$RT.Start), "-", max(validated_data$data$RT.Start), "min\n")
cat("m/z Range:", min(validated_data$data$Precursor.Mz), "-", max(validated_data$data$Precursor.Mz), "\n")
cat("Median FWHM:", median(validated_data$data$FWHM, na.rm = TRUE), "sec\n")

# Run Stage 2
cat("\n========== Stage 2: Optimization Planning ==========\n")
plan <- plan_optimization(
  validated_data = validated_data,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)

cat("\n--- Optimization Plan ---\n")
cat("Required Cycle Time:", plan$required_cycle_time_sec, "sec\n")
cat("Recommended Windows:", plan$recommended_windows, "\n")

# Run Stage 3
cat("\n========== Stage 3: Window Optimization ==========\n")
windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = plan,
  mz_strategy = "quantile",
  window_mode = "variable"
)

cat("\n--- Optimized Windows ---\n")
cat("Total Windows:", nrow(windows$windows), "\n")
cat("RT Bins:", length(unique(windows$windows$rt_segment_id)), "\n")
cat("Mean Width:", mean(windows$windows$window_width), "Da\n")
cat("Coverage:", windows$statistics$coverage_percentage, "%\n")

# Save sample for comparison
write.csv(head(windows$windows, 10), "output_cli_sample.csv", row.names = FALSE)
cat("\nSample saved to output_cli_sample.csv\n")

cat("\n========== SUMMARY FOR COMPARISON ==========\n")
cat("Use these values to compare with Shiny app:\n")
cat("  - Precursors: ", nrow(validated_data$data), "\n")
cat("  - Total Windows: ", nrow(windows$windows), "\n")
cat("  - RT Bins: ", length(unique(windows$windows$rt_segment_id)), "\n")
cat("  - Mean Width: ", round(mean(windows$windows$window_width), 1), " Da\n")
cat("  - Coverage: ", round(windows$statistics$coverage_percentage, 1), "%\n")
cat("  - Recommended Cycle Time: ", round(plan$required_cycle_time_sec, 2), " sec\n")
