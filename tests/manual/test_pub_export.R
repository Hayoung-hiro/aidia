# test_pub_export.R — Test publication figure export
#
# Usage: source this file in an R session with data already loaded, or run:
#   Rscript tests/manual/test_pub_export.R
#
# Requires: data/30min_report.parquet

cat("=== Publication Export Test ===\n\n")

# Load package
devtools::load_all(".")

# --- Stage 1-3 ---
cat("Stage 1: Data validation...\n")
validated <- create_validated_dataset("data/30min_report.parquet")

cat("Stage 2: Optimization planning...\n")
plan <- plan_optimization(
  validated,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)

cat("Stage 3: Window optimization...\n")
windows <- optimize_windows(
  validated, plan,
  mz_strategy = "greedy",
  window_mode = "density"
)

# --- Stage 4: Generate plots (no PDF, no individual export) ---
cat("Stage 4: Generating plots...\n")
results <- generate_visualizations(
  validated, plan, windows,
  output_dir = "output_review",
  create_pdf = FALSE,
  create_individual_plots = FALSE
)

cat("\nGenerated", length(results$plots), "plots\n")

# --- Publication Export: Report mode (standard ggsave for review) ---
cat("\n=== Report Mode Export (10x7, 300 DPI, PNG) ===\n")

# Select representative plots from each section
selected_plots <- c(
  "s1_01_density_heatmap",
  "s1_02_fwhm_distribution",
  "s1_03_mz_density",
  "s2_01_impact_summary",
  "s2_02_window_layout",
  "s2_04_load_balance",
  "s2_05_precursor_distribution",
  "s3_02_strategy_ridge",
  "app_a_edge_proximity",
  "app_a_fz_validation"
)

# Filter to only plots that exist
available <- intersect(selected_plots, names(results$plots))
cat("Exporting", length(available), "selected plots in report mode...\n")

dir.create("output_review/report", showWarnings = FALSE, recursive = TRUE)
for (name in available) {
  p <- results$plots[[name]]
  tryCatch({
    ggplot2::ggsave(
      file.path("output_review/report", paste0(name, ".png")),
      plot = p, width = 10, height = 7, dpi = 300, bg = "white"
    )
    cat("  OK", name, "\n")
  }, error = function(e) {
    cat("  FAIL", name, ":", e$message, "\n")
  })
}

# --- Publication Export: JPR single column ---
cat("\n=== Publication Mode Export (JPR single, PDF, 600 DPI) ===\n")

export_publication_figures(
  results$plots,
  selected = available,
  output_dir = "output_review/pub_jpr",
  journal = "jpr",
  column = "single",
  format = "pdf"
)

# --- Publication Export: Nature Methods double column ---
cat("\n=== Publication Mode Export (Nature Methods double, PDF) ===\n")

export_publication_figures(
  results$plots,
  selected = available,
  output_dir = "output_review/pub_nature",
  journal = "nature_methods",
  column = "double",
  format = "pdf"
)

cat("\n=== All exports complete ===\n")
cat("Review outputs in:\n")
cat("  output_review/report/   (report mode PNG)\n")
cat("  output_review/pub_jpr/  (JPR single column PDF)\n")
cat("  output_review/pub_nature/ (Nature Methods double column PDF)\n")
