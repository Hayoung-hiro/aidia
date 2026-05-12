# Pass 1: Section 5 — Strategy Comparison
# Plots: s5_01 Table, s5_02 Ridge, s5_03 Boundary Grid, s5_04 Width Profile
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

# S5-01: Strategy Comparison Table
cat("[S5-01] Comparison Table\n")
p <- plot_strategy_comparison_table(windows_list)
png(file.path(outdir, "s5_01_strategy_table.png"),
    width = 1400, height = 700, res = 150)
grid::grid.draw(p)
dev.off()

# S5-02: Width Ridge Plot
cat("[S5-02] Width Ridge\n")
p <- plot_strategy_width_ridge(windows_list, validated)
ggsave(file.path(outdir, "s5_02_strategy_ridge.png"), p,
       width = 10, height = 7, dpi = 200, bg = "white")

# S5-03: Boundary Grid Heatmap
cat("[S5-03] Boundary Grid Heatmap\n")
p <- plot_density_with_mz_ranges_grid(windows_list, validated)
png(file.path(outdir, "s5_03_heatmap_boundary.png"),
    width = 1600, height = 1200, res = 150)
grid::grid.draw(p)
dev.off()

# S5-04: Strategy Width Profile
cat("[S5-04] Strategy Width Profile\n")
p <- plot_strategy_width_profile(windows_list, validated)
ggsave(file.path(outdir, "s5_04_width_profile.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

cat("\n=== S5 Done ===\n")
cat(paste(" ", list.files(outdir, pattern = "s5_")), sep = "\n")
