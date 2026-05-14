# Quick test for main.R with 30min file only
source("main.R")

# Test with 30min file only
results <- run_complete_pipeline(
  data_dir = "data",
  output_base_dir = "output_test",
  instrument_preset = "fusion_lumos",
  target_dppp = 7.0,
  target_satisfaction = 0.70,
  mz_strategies = c("quantile", "smoothing", "outlier", "coverage"),
  window_mode = "density",
  rt_bin_width_min = 5,
  create_plots = TRUE,
  create_pdf = TRUE,
  verbose = TRUE
)

cat("\n✅ Test complete!\n")
cat(sprintf("Output directory: output_test/\n"))
