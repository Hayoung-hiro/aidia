# Pass 1: Section 4 — Optimization Validation
# Order: Impact → Edge Proximity → Edge Spatial → Charge State → FZ Validation
# Appendix: FZ Zoom (micro view)
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

# 1. Impact Summary (overview: bars + table)
cat("[S4-12] Impact Summary\n")
p <- plot_optimization_impact(plan, windows, validated)
png(file.path(outdir, "S4_12_impact.png"),
    width = 1400, height = 900, res = 150)
grid::grid.draw(p)
dev.off()

# 2. Edge Proximity (histogram + staggered simulation)
cat("[S4-13a] Edge Proximity\n")
p <- plot_edge_proximity(windows, validated)
ggsave(file.path(outdir, "S4_13a_edge_proximity.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# 3. Edge Proximity Spatial (RT x m/z)
cat("[S4-13b] Edge Proximity Spatial\n")
p <- plot_edge_proximity_spatial(windows, validated)
ggsave(file.path(outdir, "S4_13b_edge_spatial.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# 4. Charge State Distribution
cat("[S4-16] Charge State Distribution\n")
p <- plot_charge_mz_distribution(windows, validated)
ggsave(file.path(outdir, "S4_16_charge_state.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# 5. FZ Validation (mass defect histogram)
cat("[S4-15] FZ Validation\n")
fz_offset <- windows$parameters$fz_offset %||% 0.25
p <- plot_fz_validation(validated, fz_offset = fz_offset)
ggsave(file.path(outdir, "S4_15_fz_validation.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# Appendix: FZ Zoom (micro view of specific boundary)
cat("[S4-App] FZ Zoom\n")
p <- plot_fz_zoom(windows, validated, fz_offset = fz_offset)
ggsave(file.path(outdir, "S4_App_fz_zoom.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

cat("\n=== S4 Done ===\n")
cat(paste(" ", list.files(outdir, pattern = "S4_")), sep = "\n")
