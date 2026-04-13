# Pass 1: Section 3 — Optimized Window Layout
# Plots: 08 Load balance, 09 m/z density, 10 Width overlay, 11 Index bars
# S3_07 Tiling removed (redundant with S1 heatmap + S3_11; gap check in S3_11 subtitle)
# Requires: Stage 1 + 2 + 3 (greedy)
# Run: source("tests/manual/pass1_s3_layout.R")

devtools::load_all()

outdir <- "output_report_test/pass1/S3_Layout"
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

cat("=== Stage 1 + 2 + 3 ===\n")
validated <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(validated, instrument_preset = "astral", target_dppp = 7.0)
windows <- optimize_windows(validated, plan,
                            strategy_config = greedy_config(),
                            window_mode = "density",
                            rt_bin_width_min = 5)

cat("\n=== S3: Optimized Window Layout ===\n")

# 08. Precursor Load Balance
cat("[S3-08] Precursor Load Balance\n")
p <- plot_precursor_load_balance(windows, validated)
ggsave(file.path(outdir, "S3_08_load_balance.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# 09. m/z Density Profiles
cat("[S3-09] m/z Density Profiles\n")
p <- plot_mz_normalized_density(windows, validated)
ggsave(file.path(outdir, "S3_09_mz_density.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# 10. Window m/z Range Across Gradient
cat("[S3-10] Window m/z Range Across Gradient\n")
p <- plot_window_width_distribution(windows, validated)
ggsave(file.path(outdir, "S3_10_mz_range.png"), p,
       width = 10, height = 6, dpi = 200, bg = "white")

# 11. Window Index Width Bars (plot7b)
cat("[S3-11] Window Index Width Bars\n")
p <- plot_cumulative_window_count(windows, validated, max_segments_to_show = 6)
png(file.path(outdir, "S3_11_window_index_bars.png"),
    width = 1600, height = 1000, res = 150)
grid::grid.draw(p)
dev.off()

cat("\n=== S3 Done ===\n")
cat(paste(" ", list.files(outdir, pattern = "S3_")), sep = "\n")
