# generate_strategy_previews.R - Pre-generate strategy preview images for Shiny
# Run: source("tests/manual/generate_strategy_previews.R")
#
# Generates 5 strategy preview PNGs with 2D density + boundaries + CI ribbons.
# Output: inst/shiny_app/www/strategy_previews/*.png

devtools::load_all(quiet = TRUE)

cat("\n", rep("=", 60), "\n", sep = "")
cat("Generating Strategy Preview Images\n")
cat(rep("=", 60), "\n\n")

# =====================================================================
# Data preparation
# =====================================================================
data_path <- "C:/Users/Odyssey/Desktop/1sample/report.parquet"
validated <- create_validated_dataset(data_path)
plan <- plan_optimization(validated, instrument_preset = "astral", target_dppp = 7.0)

output_dir <- "inst/shiny_app/www/strategy_previews"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# =====================================================================
# Strategy configs — smoothing-enabled strategies use WH (default)
# =====================================================================
strategy_configs <- list(
  greedy = greedy_config(apply_smoothing = TRUE),
  kde = kde_config(),
  quantile = quantile_config(apply_smoothing = TRUE),
  coverage = coverage_config(),
  outlier = outlier_config(apply_smoothing = TRUE)
)

n_boot <- 200

# =====================================================================
# Generate previews
# =====================================================================
for (strategy_name in names(strategy_configs)) {
  config <- strategy_configs[[strategy_name]]
  label <- format_strategy_label(strategy_name)

  cat(sprintf("\n--- %s ---\n", label))

  # Run bootstrap CI
  cat("  Computing bootstrap CI...\n")
  ci <- bootstrap_boundary_ci(
    validated, plan,
    strategy_config = config,
    n_boot = n_boot,
    ci_level = 0.95,
    seed = 42,
    verbose = FALSE
  )

  cat(sprintf("  CI width: lower=%.1f Da, upper=%.1f Da\n",
              mean(ci$ci_data$mz_min_ci_width),
              mean(ci$ci_data$mz_max_ci_width)))

  # Generate plot
  p <- plot_boundary_ci(ci, validated)

  # Save
  out_path <- file.path(output_dir, sprintf("preview_%s.png", strategy_name))
  ggsave(out_path, p, width = 9, height = 6, dpi = 150, bg = "white")
  cat(sprintf("  Saved: %s\n", out_path))
}

# =====================================================================
# Also generate a compact comparison overview
# =====================================================================
cat("\n--- Generating comparison overview ---\n")

# Run optimization for all strategies to get boundary data
windows_list <- list()
for (strategy_name in names(strategy_configs)) {
  config <- strategy_configs[[strategy_name]]
  cat(sprintf("  Running %s...\n", strategy_name))
  invisible(capture.output(
    windows_list[[strategy_name]] <- optimize_windows(
      validated, plan,
      strategy_config = config,
      window_mode = "density"
    )
  ))
}

# Strategy width profile (overlay)
p_width <- plot_strategy_width_profile(windows_list, validated)
ggsave(file.path(output_dir, "preview_width_profile.png"), p_width,
       width = 10, height = 6, dpi = 150, bg = "white")

cat(sprintf("\nAll previews saved to %s/\n", output_dir))

# List generated files
cat("\nGenerated files:\n")
for (f in list.files(output_dir, pattern = "\\.png$")) {
  fpath <- file.path(output_dir, f)
  cat(sprintf("  %s (%.0f KB)\n", f, file.size(fpath) / 1024))
}

cat("\n", rep("=", 60), "\n", sep = "")
cat("Strategy preview generation complete.\n")
