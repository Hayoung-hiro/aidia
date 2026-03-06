# test_new_plots.R — Render revised plot versions
# Run: Rscript tests/manual/test_new_plots.R

devtools::load_all()

cat("=== Loading data ===\n")
vd <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(vd,
  instrument_preset = "astral",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)
wins_g <- optimize_windows(vd, plan, mz_strategy = "greedy", window_mode = "density")
wins_q <- optimize_windows(vd, plan, mz_strategy = "quantile", window_mode = "density")
wl <- list(greedy = wins_g, quantile = wins_q)

outdir <- "output_review"
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

# 1. Plot 1B: Acquisition Diagnosis Table
cat("\n=== Plot 1B: Diagnosis Table ===\n")
tryCatch({
  p1b <- plot_dppp_diagnosis_table(plan, vd)
  png(file.path(outdir, "NEW_plot1b_diagnosis_table.png"),
      width = 1600, height = 1000, res = 120)
  grid::grid.draw(p1b)
  dev.off()
  cat("  OK saved\n")
}, error = function(e) cat("  FAIL:", e$message, "\n"))

# 2. Plot 16: Window Utilization Distribution
cat("\n=== Plot 16: Window Utilization Distribution ===\n")
tryCatch({
  p16 <- plot_load_balance_stacked(wins_g, vd)
  ggplot2::ggsave(file.path(outdir, "NEW_plot16_window_utilization.png"),
                  p16, width = 16, height = 10, dpi = 120, bg = "white")
  cat("  OK saved\n")
}, error = function(e) cat("  FAIL:", e$message, "\n"))

# 3. Plot 4E: m/z Width Comparison (grouped bar — already exists)
cat("\n=== Plot 4E: m/z Width All Strategies ===\n")
tryCatch({
  p4e <- plot_mz_width_comparison_all_strategies(wl, vd)
  ggplot2::ggsave(file.path(outdir, "NEW_plot4e_mz_width_all_strategies.png"),
                  p4e, width = 16, height = 10, dpi = 120, bg = "white")
  cat("  OK saved\n")
}, error = function(e) cat("  FAIL:", e$message, "\n"))

cat("\n=== Done — check output_review/NEW_*.png ===\n")
