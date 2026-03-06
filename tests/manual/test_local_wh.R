# test_local_wh.R - Validate WH on LOCAL strategies (quantile, outlier)
# Run: source("tests/manual/test_local_wh.R")

devtools::load_all(quiet = TRUE)

cat("\n", rep("=", 60), "\n", sep = "")
cat("LOCAL Strategy: SG vs Whittaker Validation\n")
cat(rep("=", 60), "\n\n")

# =====================================================================
# Data preparation
# =====================================================================
data_path <- "C:/Users/Odyssey/Desktop/1sample/report.parquet"
validated <- create_validated_dataset(data_path)
plan <- plan_optimization(validated, instrument_preset = "astral", target_dppp = 7.0)

# =====================================================================
# Helper: run strategy + bootstrap, return summary
# =====================================================================
run_test <- function(label, config, n_boot = 200) {
  cat(sprintf("\n--- %s ---\n", label))

  # Optimization result
  t <- system.time({
    result <- optimize_windows(validated, plan, strategy_config = config, window_mode = "density")
  })

  stats <- result$statistics
  mz <- result$mz_optimization$mz_ranges

  # Boundary roughness
  roughness_min <- sd(diff(mz$mz_min))
  roughness_max <- sd(diff(mz$mz_max))

  # Bootstrap CI
  ci <- bootstrap_boundary_ci(
    validated, plan, strategy_config = config,
    n_boot = n_boot, ci_level = 0.95, seed = 42, verbose = FALSE
  )

  list(
    label = label,
    coverage = stats$coverage_percentage,
    width_mean = stats$window_width_mean,
    prec_cv = stats$cv_precursors,
    roughness_min = roughness_min,
    roughness_max = roughness_max,
    ci_min = mean(ci$ci_data$mz_min_ci_width),
    ci_max = mean(ci$ci_data$mz_max_ci_width),
    ci_total = mean(ci$ci_data$mz_min_ci_width + ci$ci_data$mz_max_ci_width),
    ci_obj = ci,
    time = t["elapsed"]
  )
}

# =====================================================================
# Test 1: Quantile + SG vs Quantile + WH
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("TEST 1: Quantile Strategy\n")
cat(rep("=", 60), "\n")

q_sg <- run_test("Quantile + SG", quantile_config(
  apply_smoothing = TRUE, smoothing_method = "sg"
))

q_wh <- run_test("Quantile + WH", quantile_config(
  apply_smoothing = TRUE, smoothing_method = "whittaker", whittaker_lambda = 10
))

# =====================================================================
# Test 2: Outlier + SG vs Outlier + WH
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("TEST 2: Outlier Strategy\n")
cat(rep("=", 60), "\n")

o_sg <- run_test("Outlier + SG", outlier_config(
  apply_smoothing = TRUE, smoothing_method = "sg"
))

o_wh <- run_test("Outlier + WH", outlier_config(
  apply_smoothing = TRUE, smoothing_method = "whittaker", whittaker_lambda = 10
))

# =====================================================================
# Test 3: Greedy (reference, already validated)
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("TEST 3: Greedy Strategy (reference)\n")
cat(rep("=", 60), "\n")

g_sg <- run_test("Greedy + SG", greedy_config(
  apply_smoothing = TRUE, smoothing_method = "sg"
))

g_wh <- run_test("Greedy + WH", greedy_config(
  apply_smoothing = TRUE, smoothing_method = "whittaker", whittaker_lambda = 10
))

# =====================================================================
# Comparison Table
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("COMPARISON TABLE\n")
cat(rep("=", 60), "\n\n")

all_results <- list(q_sg, q_wh, o_sg, o_wh, g_sg, g_wh)

cat("| Method               | Cov(%) | Width | Prec CV | Rough min | Rough max | CI min | CI max | CI total |\n")
cat("|----------------------|-------:|------:|--------:|----------:|----------:|-------:|-------:|---------:|\n")

for (r in all_results) {
  cat(sprintf("| %-20s | %5.1f%% | %5.1f | %7.3f | %9.2f | %9.2f | %6.1f | %6.1f | %8.1f |\n",
              r$label, r$coverage, r$width_mean, r$prec_cv,
              r$roughness_min, r$roughness_max,
              r$ci_min, r$ci_max, r$ci_total))
}

# =====================================================================
# Improvement Summary
# =====================================================================
cat("\n--- Improvement (WH vs SG) ---\n")

fmt_delta <- function(label, sg, wh) {
  cat(sprintf("  %s:\n", label))
  cat(sprintf("    Roughness min: %.2f -> %.2f (%+.1f%%)\n",
              sg$roughness_min, wh$roughness_min,
              (wh$roughness_min - sg$roughness_min) / sg$roughness_min * 100))
  cat(sprintf("    Roughness max: %.2f -> %.2f (%+.1f%%)\n",
              sg$roughness_max, wh$roughness_max,
              (wh$roughness_max - sg$roughness_max) / sg$roughness_max * 100))
  cat(sprintf("    CI total:      %.1f -> %.1f (%+.1f%%)\n",
              sg$ci_total, wh$ci_total,
              (wh$ci_total - sg$ci_total) / sg$ci_total * 100))
  cat(sprintf("    Coverage:      %.1f%% -> %.1f%% (%+.1f%%)\n",
              sg$coverage, wh$coverage,
              wh$coverage - sg$coverage))
}

fmt_delta("Quantile", q_sg, q_wh)
fmt_delta("Outlier", o_sg, o_wh)
fmt_delta("Greedy", g_sg, g_wh)

# =====================================================================
# Visualization: CI comparison per strategy
# =====================================================================
cat("\n--- Generating plots ---\n")

output_dir <- "output_bootstrap_ci"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

p_q <- plot_boundary_ci_comparison(q_sg$ci_obj, q_wh$ci_obj,
                                    label_a = "Quantile+SG", label_b = "Quantile+WH")
p_o <- plot_boundary_ci_comparison(o_sg$ci_obj, o_wh$ci_obj,
                                    label_a = "Outlier+SG", label_b = "Outlier+WH")

ggsave(file.path(output_dir, "ci_quantile_sg_vs_wh.png"), p_q, width = 10, height = 6, dpi = 150)
ggsave(file.path(output_dir, "ci_outlier_sg_vs_wh.png"), p_o, width = 10, height = 6, dpi = 150)

cat(sprintf("Plots saved to %s/\n", output_dir))

cat("\n", rep("=", 60), "\n", sep = "")
cat("LOCAL strategy validation complete.\n")
