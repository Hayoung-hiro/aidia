# Pass 1: Section 4 — Optimization Validation
# Plots: 12 Impact dashboard, 13 Edge proximity, 14 FZ zoom
# Requires: Stage 1 + 2 + 3 (greedy)
# Run: source("tests/manual/pass1_s4_validation.R")

devtools::load_all()

outdir <- "output_report_test/pass1/S4_Validation"
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

cat("=== Stage 1 + 2 + 3 ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(validated, instrument_preset = "astral", target_dppp = 7.0)
windows <- optimize_windows(validated, plan,
                            strategy_config = greedy_config(),
                            window_mode = "density",
                            rt_bin_width_min = 5)

cat("\n=== S4: Optimization Validation ===\n")

# 12. Impact Dashboard
cat("[S4-12] Impact Dashboard\n")
p <- plot_optimization_impact(plan, windows, validated)
png(file.path(outdir, "S4_12_impact.png"),
    width = 1400, height = 900, res = 150)
grid::grid.draw(p)
dev.off()

# 13. Edge Proximity
cat("[S4-13] Edge Proximity\n")
p <- plot_edge_proximity(windows, validated)
ggsave(file.path(outdir, "S4_13_edge_proximity.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# 14. FZ Zoom (always-on)
cat("[S4-14] FZ Zoom\n")
fz_offset <- windows$parameters$fz_offset %||% 0.25
p <- plot_fz_zoom(windows, validated, fz_offset = fz_offset)
ggsave(file.path(outdir, "S4_14_fz_zoom.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

cat("\n=== S4 Done ===\n")
cat(paste(" ", list.files(outdir, pattern = "S4_")), sep = "\n")
