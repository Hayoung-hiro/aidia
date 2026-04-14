# test_round4_pdf.R — Test full pipeline with PDF generation
# Run: Rscript tests/manual/test_round4_pdf.R

devtools::load_all()

cat("=== Loading data ===\n")
vd <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(vd,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)
wins <- optimize_windows(vd, plan,
  mz_strategy = "greedy",
  window_mode = "density"
)

cat("\n=== Generate Visualizations (with PDF) ===\n")
viz <- generate_visualizations(vd, plan, wins,
  output_dir = "output/",
  create_pdf = TRUE,
  create_individual_plots = FALSE
)

cat("\n=== Results ===\n")
cat("Total plots:", length(viz$plots), "\n")
cat("PDF:", viz$report_files$pdf_report, "\n")

# Check key plot names exist
expected_keys <- c(
  "plot1b_dppp_satisfaction_combined",
  "s5_04_width_profile",
  "s3_02_load_balance",
  "s4_02_edge_proximity",
  "s5_03_heatmap_boundary"
)
for (k in expected_keys) {
  status <- if (k %in% names(viz$plots)) "OK" else "MISSING"
  cat(sprintf("  %s: %s\n", k, status))
}

# Verify no old keys
old_keys <- c("plot6_satisfaction_curve", "plot10_representative_bin",
              "plot1b_dppp_comparison_enhanced", "plot5_coverage_map_2x2",
              "plot5b_strategy_boundary_comparison", "plot8b_strategy_width_boxplot",
              "plot8c_strategy_width_cdf", "plot18_strategy_radar")
for (k in old_keys) {
  if (k %in% names(viz$plots)) cat(sprintf("  WARNING: old key still present: %s\n", k))
}

cat("\n=== Done ===\n")
