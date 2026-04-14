# test_round4_plots.R — Test Round 4 plot changes
# Run: Rscript tests/manual/test_round4_plots.R

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

outdir <- "output_review"
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

# Test 1: Combined DPPP + Satisfaction
cat("\n=== Test 1B+6: DPPP & Satisfaction Combined ===\n")
tryCatch({
  p <- plot_dppp_satisfaction_combined(plan, vd)
  cat("  Class:", paste(class(p), collapse = ", "), "\n")

  png(file.path(outdir, "plot1b_dppp_satisfaction_combined.png"),
      width = 1600, height = 1200, res = 120)
  grid::grid.draw(p)
  dev.off()
  cat("  OK saved\n")
}, error = function(e) {
  cat("  FAIL:", e$message, "\n")
})

# Test 2: Load Balance with outlier band
cat("\n=== Test Plot 16: Load Balance ===\n")
tryCatch({
  p16 <- plot_precursor_load_balance(wins, vd)
  ggplot2::ggsave(file.path(outdir, "plot16_load_balance.png"),
                  p16, width = 16, height = 10, dpi = 120, bg = "white")
  cat("  OK saved\n")
}, error = function(e) {
  cat("  FAIL:", e$message, "\n")
})

# Test 3: Strategy Width Profile (need 2 strategies)
cat("\n=== Test: Strategy Width Profile ===\n")
tryCatch({
  wins_q <- optimize_windows(vd, plan, mz_strategy = "quantile", window_mode = "density")
  wl <- list(greedy = wins, quantile = wins_q)
  p5 <- plot_strategy_width_profile(wl, vd)
  ggplot2::ggsave(file.path(outdir, "s5_04_width_profile.png"),
                  p5, width = 16, height = 10, dpi = 120, bg = "white")
  cat("  OK saved\n")
}, error = function(e) {
  cat("  FAIL:", e$message, "\n")
})

cat("\n=== Done ===\n")
