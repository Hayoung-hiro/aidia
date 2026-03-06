# Export key round 4 plots as individual PNGs for review
devtools::load_all()

vd <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(vd, instrument_preset = "astral", target_dppp = 7.0, target_satisfaction = 0.70)
wins <- optimize_windows(vd, plan, mz_strategy = "greedy", window_mode = "density")

outdir <- "output_review"
dir.create(outdir, showWarnings = FALSE)

# 1. Combined DPPP + Satisfaction
p <- plot_dppp_satisfaction_combined(plan, vd)
png(file.path(outdir, "r4_combined_dppp_sat.png"), width = 1600, height = 1200, res = 120)
grid::grid.draw(p)
dev.off()
cat("OK: combined DPPP + satisfaction\n")

# 2. Load balance with outlier band
p16 <- plot_precursor_load_balance(wins, vd)
ggplot2::ggsave(file.path(outdir, "r4_load_balance.png"), p16, width = 16, height = 10, dpi = 120, bg = "white")
cat("OK: load balance\n")

# 3. Edge proximity
p17 <- plot_edge_proximity(wins, vd)
ggplot2::ggsave(file.path(outdir, "r4_edge_proximity.png"), p17, width = 16, height = 10, dpi = 120, bg = "white")
cat("OK: edge proximity\n")

# 4. Per-strategy heatmap (Plot 2C) - just greedy for test
p2c <- plot_density_with_mz_range(wins, vd)
ggplot2::ggsave(file.path(outdir, "r4_heatmap_mz_range.png"), p2c, width = 12, height = 8, dpi = 120, bg = "white")
cat("OK: heatmap with mz range\n")

cat("\nAll exports done\n")
