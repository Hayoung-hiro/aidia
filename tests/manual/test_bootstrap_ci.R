# test_bootstrap_ci.R - Bootstrap CI for m/z boundaries
# Run: source("tests/manual/test_bootstrap_ci.R")

devtools::load_all(quiet = TRUE)

cat("\n", rep("=", 60), "\n", sep = "")
cat("Bootstrap Boundary CI Test (Real Data)\n")
cat(rep("=", 60), "\n\n")

# =====================================================================
# Data preparation (Stages 1-2)
# =====================================================================
data_path <- "C:/Users/Odyssey/Desktop/1sample/report.parquet"

cat("--- Stage 1: Data Validation ---\n")
validated <- create_validated_dataset(data_path)

cat("\n--- Stage 2: Optimization Planning ---\n")
plan <- plan_optimization(
  validated,
  instrument_preset = "astral",
  target_dppp = 7.0
)

# =====================================================================
# Test 1: Greedy + SG (default) — Bootstrap CI
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("TEST 1: Greedy + SG Bootstrap CI\n")
cat(rep("=", 60), "\n")

ci_sg <- bootstrap_boundary_ci(
  validated, plan,
  strategy_config = greedy_config(
    apply_smoothing = TRUE,
    smoothing_method = "sg"
  ),
  n_boot = 200,
  ci_level = 0.95,
  seed = 42
)
print(ci_sg)

# =====================================================================
# Test 2: Greedy + Whittaker — Bootstrap CI
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("TEST 2: Greedy + Whittaker Bootstrap CI\n")
cat(rep("=", 60), "\n")

ci_wh <- bootstrap_boundary_ci(
  validated, plan,
  strategy_config = greedy_config(
    apply_smoothing = TRUE,
    smoothing_method = "whittaker",
    whittaker_lambda = 10
  ),
  n_boot = 200,
  ci_level = 0.95,
  seed = 42
)
print(ci_wh)

# =====================================================================
# Test 3: Quantile + SG smoothing — Bootstrap CI (LOCAL strategy)
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("TEST 3: Quantile + SG Bootstrap CI (LOCAL strategy)\n")
cat(rep("=", 60), "\n")

ci_q <- bootstrap_boundary_ci(
  validated, plan,
  strategy_config = quantile_config(
    apply_smoothing = TRUE,
    smoothing_method = "sg"
  ),
  n_boot = 200,
  ci_level = 0.95,
  seed = 42
)
print(ci_q)

# =====================================================================
# Comparison Summary
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("COMPARISON SUMMARY\n")
cat(rep("=", 60), "\n\n")

cat("| Method             | mz_min CI (Da) | mz_max CI (Da) | Total CI (Da) |\n")
cat("|--------------------|--------------:|--------------:|--------------:|\n")

fmt_row <- function(label, ci) {
  d <- ci$ci_data
  cat(sprintf("| %-18s | %13.1f | %13.1f | %13.1f |\n",
              label,
              mean(d$mz_min_ci_width),
              mean(d$mz_max_ci_width),
              mean(d$mz_min_ci_width + d$mz_max_ci_width)))
}

fmt_row("Greedy + SG", ci_sg)
fmt_row("Greedy + Whittaker", ci_wh)
fmt_row("Quantile + SG", ci_q)

# =====================================================================
# Visualization
# =====================================================================
cat("\n--- Generating plots ---\n")

# Plot 1: CI on density heatmap (SG)
p1 <- plot_boundary_ci(ci_sg, validated)

# Plot 2: CI on density heatmap (Whittaker)
p2 <- plot_boundary_ci(ci_wh, validated)

# Plot 3: CI width bar chart (SG)
p3 <- plot_boundary_ci_width(ci_sg)

# Plot 4: SG vs Whittaker comparison
p4 <- plot_boundary_ci_comparison(ci_sg, ci_wh, label_a = "SG", label_b = "Whittaker")

# Save plots
output_dir <- "output_bootstrap_ci"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

ggsave(file.path(output_dir, "ci_density_sg.png"), p1, width = 10, height = 7, dpi = 150)
ggsave(file.path(output_dir, "ci_density_wh.png"), p2, width = 10, height = 7, dpi = 150)
ggsave(file.path(output_dir, "ci_width_bars.png"), p3, width = 10, height = 6, dpi = 150)
ggsave(file.path(output_dir, "ci_comparison.png"), p4, width = 10, height = 6, dpi = 150)

cat(sprintf("\nPlots saved to %s/\n", output_dir))

cat("\n", rep("=", 60), "\n", sep = "")
cat("Bootstrap CI test complete.\n")
