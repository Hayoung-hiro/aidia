#!/usr/bin/env Rscript
# Production Test - Complete Pipeline with Full Visualization

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║        DIA Window Optimizer - Production Test                 ║\n")
cat("║        Full Dataset + All Strategies + Visualization          ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

start_time <- Sys.time()

# Source pipeline
source("run_with_config.R")

# Configuration
config_file <- "config/production_test.yaml"

cat(sprintf("Configuration: %s\n", config_file))
cat("Expected output:\n")
cat("  - 3 gradients (30min, 60min, 90min)\n")
cat("  - 4 strategies per gradient (quantile, smoothing, outlier, coverage)\n")
cat("  - 24 plots per gradient\n")
cat("  - 1 PDF report per gradient\n")
cat("  - 1 summary CSV\n")
cat("\nTotal: 12 method files + 72 plots + 3 PDFs\n")
cat("\n")

# Run optimization
cat("═══════════════════════════════════════════════════════════════\n")
cat("Starting production test...\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

tryCatch({
  results <- run_optimization(config_file)

  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "mins"))

  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║           ✅ PRODUCTION TEST SUCCESSFUL                        ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  cat(sprintf("Total time: %.1f minutes\n", elapsed))
  cat(sprintf("Output directory: results_production_test/\n"))
  cat("\n")

  # Count output files
  output_dir <- "results_production_test"
  if (dir.exists(output_dir)) {
    csv_files <- list.files(output_dir, pattern = "\\.csv$", recursive = TRUE)
    png_files <- list.files(output_dir, pattern = "\\.png$", recursive = TRUE)
    pdf_files <- list.files(output_dir, pattern = "\\.pdf$", recursive = TRUE)

    cat("Generated files:\n")
    cat(sprintf("  - Method CSVs: %d\n", length(csv_files) - 1))  # -1 for summary
    cat(sprintf("  - Plots (PNG): %d\n", length(png_files)))
    cat(sprintf("  - Reports (PDF): %d\n", length(pdf_files)))
    cat(sprintf("  - Summary CSV: 1\n"))
    cat("\n")
  }

  cat("Next steps:\n")
  cat("  1. Review plots in results_production_test/[gradient]/\n")
  cat("  2. Compare strategies using batch_processing_summary.csv\n")
  cat("  3. Select optimal strategy for your priorities\n")
  cat("  4. Import *_method.csv to Thermo Orbitrap\n")
  cat("\n")

}, error = function(e) {
  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║           ❌ PRODUCTION TEST FAILED                            ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  cat(sprintf("Error: %s\n", e$message))
  cat("\nTraceback:\n")
  print(e)

  quit(status = 1)
})
