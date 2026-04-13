# Pass 1: Section 1 — Input Data Profile
# Plots: 01a 2D heatmap, 01b 3D surface, 02 FWHM, 03 Data Summary
# Requires: Stage 1 + 2
# Run: source("tests/manual/pass1_s1_input.R")

devtools::load_all()

outdir <- "output_report_test/pass1/S1_Input"
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

cat("=== Stage 1 + 2 ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(validated, instrument_preset = "astral", target_dppp = 7.0)

cat("\n=== S1: Input Data Profile ===\n")

# 01. Precursor Density Heatmap (KDE, matches S5 boundary grid style)
cat("[S1-01] Density Heatmap\n")
p <- plot_rt_mz_density_heatmap(validated)
ggsave(file.path(outdir, "S1_01_heatmap.png"), p,
       width = 10, height = 7, dpi = 200, bg = "white")

# 02. FWHM Distribution
cat("[S1-02] FWHM Distribution\n")
p <- plot_fwhm_distribution(validated, plan)
ggsave(file.path(outdir, "S1_02_fwhm.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# 03. Data Summary Table
cat("[S1-03] Data Summary Table\n")
png(file.path(outdir, "S1_03_data_summary.png"),
    width = 1200, height = 800, res = 150)
.draw_data_quality_summary(validated)
dev.off()

cat("\n=== S1 Done ===\n")
cat(paste(" ", list.files(outdir, pattern = "S1_")), sep = "\n")
