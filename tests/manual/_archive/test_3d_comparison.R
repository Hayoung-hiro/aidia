# Test: Compare 3D surface renderers (plot3D vs rayshader)
# Run: source("tests/manual/test_3d_comparison.R")

devtools::load_all()

outdir <- "output_report_test"
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

cat("=== Loading data ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")

# --- 1. plot3D renderer ---
cat("\n[1] plot3D::persp3D\n")
png(file.path(outdir, "S1_3d_plot3D.png"),
    width = 1400, height = 1000, res = 150)
plot_rt_mz_density_surface(validated, renderer = "plot3D", theta = 40, phi = 25)
dev.off()
cat("  -> S1_3d_plot3D.png\n")

# --- 2. rayshader renderer ---
if (requireNamespace("rayshader", quietly = TRUE)) {
  cat("[2] rayshader\n")
  plot_rt_mz_density_surface(
    validated, renderer = "rayshader", theta = 40, phi = 25,
    output_file = file.path(outdir, "S1_3d_rayshader.png")
  )
} else {
  cat("[2] rayshader not available, skipping\n")
}

# --- 3. 2D contour for reference ---
cat("[3] 2D Contour (reference)\n")
p <- plot_rt_mz_density_heatmap(validated)
ggsave(file.path(outdir, "S1_2d_contour_ref.png"), p,
       width = 10, height = 7, dpi = 200, bg = "white")
cat("  -> S1_2d_contour_ref.png\n")

cat("\n=== Done! Compare the 3 images in output_report_test/ ===\n")
