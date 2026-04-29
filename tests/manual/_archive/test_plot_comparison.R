# Test: Compare plot variants for reporting redesign
# Run: source("tests/manual/test_plot_comparison.R")
#
# Generates individual PNGs in output_report_test/ for visual comparison.
# No PDF generation — just individual plots.

devtools::load_all()

outdir <- "output_report_test"
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

cat("=== Loading data ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(validated, instrument_preset = "astral", target_dppp = 7.0)

cat("\n=== Generating comparison plots ===\n")

# --- 1A. Heatmap: 2D with contour ---
cat("\n[1A] 2D Heatmap + Contour\n")
p1a <- plot_rt_mz_density_heatmap(validated)
ggsave(file.path(outdir, "S1_heatmap_2d_contour.png"), p1a,
       width = 10, height = 7, dpi = 200, bg = "white")
cat("  -> S1_heatmap_2d_contour.png\n")

# --- 1B. Heatmap: 3D surface ---
cat("[1B] 3D Density Surface\n")
png(file.path(outdir, "S1_heatmap_3d_surface.png"),
    width = 1200, height = 800, res = 150)
plot_rt_mz_density_surface(validated)
dev.off()
cat("  -> S1_heatmap_3d_surface.png\n")

# --- 2. FWHM Distribution ---
cat("[2] FWHM Distribution\n")
p2 <- plot_fwhm_distribution(validated, plan)
ggsave(file.path(outdir, "S1_fwhm_distribution.png"), p2,
       width = 10, height = 6, dpi = 200, bg = "white")
cat("  -> S1_fwhm_distribution.png\n")

# --- 4. DPPP Diagnosis Table ---
cat("[4] DPPP Diagnosis Table\n")
p4 <- plot_dppp_diagnosis_table(plan, validated)
png(file.path(outdir, "S2_dppp_diagnosis_table.png"),
    width = 1200, height = 600, res = 150)
grid::grid.draw(p4)
dev.off()
cat("  -> S2_dppp_diagnosis_table.png\n")

# --- 5. Satisfaction Curve ---
cat("[5] Satisfaction Curve\n")
p5 <- plot_satisfaction_curve(plan, validated)
ggsave(file.path(outdir, "S2_satisfaction_curve.png"), p5,
       width = 10, height = 6, dpi = 200, bg = "white")
cat("  -> S2_satisfaction_curve.png\n")

cat("\n=== Done! Check output_report_test/ for PNGs ===\n")
