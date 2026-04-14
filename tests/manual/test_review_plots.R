# test_review_plots.R — Generate plots for visual review
# Run: Rscript tests/manual/test_review_plots.R

devtools::load_all()

outdir <- "output_review"
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

cat("=== Stage 1: Data Validation ===\n")
vd <- create_validated_dataset("data/30min_report.parquet")

cat("\n=== Stage 2: Optimization Planning ===\n")
plan <- plan_optimization(vd,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)

cat("\n=== Stage 3: Window Optimization ===\n")
wins <- optimize_windows(vd, plan,
  mz_strategy = "greedy",
  window_mode = "density"
)

cat("\nWindows:", nrow(wins$windows), "\n")
cat("RT bins:", length(unique(wins$windows$rt_segment_id)), "\n")

cat("\n=== Stage 4: Generating Plots ===\n")
plots <- generate_visualizations(vd, plan, wins)
cat("Generated", length(plots), "plots\n")

# Export individual plots for review
plot_keys <- c(
  "s1_02_fwhm_distribution",
  "s1_01_density_heatmap",
  "app_a_charge_state",
  "plot1b_dppp_satisfaction_combined",
  "s3_03_heatmap_boundary",
  "s3_04_width_profile",
  "s2_04_load_balance",
  "s2_01_impact_summary",
  "app_a_edge_proximity"
)

for (key in plot_keys) {
  if (key %in% names(plots)) {
    outfile <- file.path(outdir, paste0(key, ".png"))
    tryCatch({
      if (inherits(plots[[key]], "grob") || inherits(plots[[key]], "gtable")) {
        png(outfile, width = 1600, height = 1000, res = 120)
        grid::grid.draw(plots[[key]])
        dev.off()
      } else {
        ggplot2::ggsave(outfile, plots[[key]], width = 16, height = 10, dpi = 120, bg = "white")
      }
      cat("  OK", key, "\n")
    }, error = function(e) {
      cat("  FAIL", key, ":", e$message, "\n")
    })
  } else {
    cat("  SKIP", key, "(not in plots)\n")
  }
}

# Generate PDF report
cat("\n=== PDF Report ===\n")
pdf_path <- file.path(outdir, "report_review.pdf")
tryCatch({
  create_pdf_report(plots, vd, plan, wins, pdf_path)
  cat("PDF saved:", pdf_path, "\n")
}, error = function(e) {
  cat("PDF FAIL:", e$message, "\n")
})

cat("\n=== Done. Check output_review/ for plots ===\n")
