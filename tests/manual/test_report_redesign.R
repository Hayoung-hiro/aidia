# Test: Reporting System Redesign Verification
# Run: source("tests/manual/test_report_redesign.R")

devtools::load_all()

cat("=== Stage 1: Data Validation ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")

cat("\n=== Stage 2: Optimization Planning ===\n")
plan <- plan_optimization(validated,
                          instrument_preset = "astral",
                          target_dppp = 7.0)

cat("\n=== Stage 3: Window Optimization ===\n")
windows <- optimize_windows(validated, plan,
                           strategy_config = greedy_config(),
                           window_mode = "density",
                           rt_bin_width_min = 5)

cat("\n=== Stage 4: Visualization ===\n")
output_dir <- "output_report_test"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

viz <- generate_visualizations(validated, plan, windows,
                               output_dir = output_dir,
                               create_pdf = TRUE,
                               create_individual_plots = FALSE)

cat("\n=== Results ===\n")
cat("Plot keys generated:\n")
cat(paste(" -", names(viz$plots)), sep = "\n")
cat("\n\nPDF files:\n")
cat(paste(" ", list.files(output_dir, pattern = "\\.pdf$", full.names = TRUE)), sep = "\n")
cat("\nDone!\n")
