# test_pdf_verification.R — Verify PDF generation with all 7 code quality fixes
# Run: Rscript tests/manual/test_pdf_verification.R

devtools::load_all()

cat("=== Stage 1: Validation ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")

cat("=== Stage 2: Planning ===\n")
plan <- plan_optimization(
  validated,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)

cat("=== Stage 3: Optimization ===\n")
windows <- optimize_windows(
  validated, plan,
  mz_strategy = "greedy",
  window_mode = "density"
)

cat("=== Stage 4: Visualization + PDF ===\n")
viz <- generate_visualizations(
  validated, plan, windows,
  output_dir = "output_test_pdf",
  create_pdf = TRUE,
  create_individual_plots = FALSE
)

cat("\n=== DONE ===\n")
cat("PDF:", viz$report_files$pdf_report, "\n")
cat("Total plots:", length(viz$plots), "\n")

# Verify new plot key naming
keys <- names(viz$plots)
legacy_keys <- grep("^plot[0-9]", keys, value = TRUE)
new_s_keys <- grep("^s[0-9]_", keys, value = TRUE)
app_keys <- grep("^app_", keys, value = TRUE)

cat("\nPlot key audit:\n")
cat("  New s{n}_ keys:", length(new_s_keys), "\n")
cat("  New app_ keys:", length(app_keys), "\n")
cat("  Legacy plot{n}_ keys:", length(legacy_keys), "\n")
if (length(legacy_keys) > 0) {
  cat("  WARNING: remaining legacy keys:", paste(legacy_keys, collapse = ", "), "\n")
} else {
  cat("  OK: All keys use new naming convention\n")
}

# Verify compute_data_summary works
cat("\ncompute_data_summary() test:\n")
s <- compute_data_summary(validated)
cat(sprintf("  Precursors: %d | m/z: %.1f-%.1f | RT: %.1f-%.1f | FWHM: %.1f sec\n",
            s$n_final, s$mz_min, s$mz_max, s$rt_min, s$rt_max, s$fwhm_median_sec))
