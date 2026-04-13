# Pass 1: Section 5 — Strategy Comparison
# Plots: 15 Comparison table, 16 Width ridge, 17 Boundary grid,
#        18 m/z excluded, 19 Strategy width profile
# Requires: Stage 1 + 2 + 3 (all 5 strategies)
# Run: source("tests/manual/pass1_s5_comparison.R")

devtools::load_all()

outdir <- "output_report_test/pass1/S5_Comparison"
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

cat("=== Stage 1 + 2 ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(validated, instrument_preset = "astral", target_dppp = 7.0)

cat("\n=== Stage 3: All 5 strategies ===\n")
strategies <- STRATEGY_PREFERRED_ORDER
windows_list <- list()
for (s in strategies) {
  cat(sprintf("  Optimizing: %s\n", s))
  windows_list[[s]] <- optimize_windows(
    validated, plan,
    mz_strategy = s,
    window_mode = "density",
    rt_bin_width_min = 5
  )
}

cat("\n=== S5: Strategy Comparison ===\n")

# 15. Strategy Comparison Table (plot8d)
cat("[S5-15] Comparison Table\n")
p <- plot_strategy_comparison_table(windows_list)
png(file.path(outdir, "S5_15_comparison_table.png"),
    width = 1400, height = 700, res = 150)
grid::grid.draw(p)
dev.off()

# 16. Width Ridge Plot (plot8a)
cat("[S5-16] Width Ridge\n")
p <- plot_strategy_width_ridge(windows_list, validated)
ggsave(file.path(outdir, "S5_16_width_ridge.png"), p,
       width = 10, height = 7, dpi = 200, bg = "white")

# 17. Boundary Grid Heatmap (plot2c)
cat("[S5-17] Boundary Grid Heatmap\n")
p <- plot_density_with_mz_ranges_grid(windows_list, validated)
png(file.path(outdir, "S5_17_boundary_grid.png"),
    width = 1600, height = 1200, res = 150)
grid::grid.draw(p)
dev.off()

# 18. m/z Excluded Regions (plot4 — greedy as representative)
cat("[S5-18] m/z Excluded Regions\n")
p <- plot_mz_distribution_with_exclusions(windows_list[["greedy"]], validated,
                                           max_bins_to_show = 6)
png(file.path(outdir, "S5_18_mz_excluded.png"),
    width = 1600, height = 1000, res = 150)
grid::grid.draw(p)
dev.off()

# 19. Strategy Width Profile (plot5)
cat("[S5-19] Strategy Width Profile\n")
p <- plot_strategy_width_profile(windows_list, validated)
ggsave(file.path(outdir, "S5_19_strategy_width_profile.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

cat("\n=== S5 Done ===\n")
cat(paste(" ", list.files(outdir, pattern = "S5_")), sep = "\n")
