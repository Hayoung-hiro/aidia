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
  "plot5_strategy_boundary_comparison",
  "plot16_load_balance",
  "plot17_edge_proximity",
  "plot2c_heatmap_with_mz_range"
)
for (k in expected_keys) {
  status <- if (k %in% names(viz$plots)) "OK" else "MISSING"
  cat(sprintf("  %s: %s\n", k, status))
}

# Verify no old keys
old_keys <- c("plot6_satisfaction_curve", "plot10_representative_bin",
              "plot1b_dppp_comparison_enhanced", "plot5_coverage_map_2x2")
for (k in old_keys) {
  if (k %in% names(viz$plots)) cat(sprintf("  WARNING: old key still present: %s\n", k))
}

cat("\n=== Done ===\n")
