# test_sg_vs_whittaker.R - Compare SG vs Whittaker-Henderson on real data
# Run: source("tests/manual/test_sg_vs_whittaker.R")

devtools::load_all(quiet = TRUE)

cat("\n", rep("=", 60), "\n", sep = "")
cat("SG vs Whittaker-Henderson Comparison (Real Data)\n")
cat(rep("=", 60), "\n\n")

# =====================================================================
# Stage 1 + 2: Shared data preparation
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
# Stage 3: Run with GREEDY + SG (default)
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("RUN A: Greedy + Savitzky-Golay (default)\n")
cat(rep("=", 60), "\n")

t_sg <- system.time({
  result_sg <- optimize_windows(
    validated, plan,
    strategy_config = greedy_config(
      apply_smoothing = TRUE,
      smoothing_method = "sg"
    ),
    window_mode = "density"
  )
})

# =====================================================================
# Stage 3: Run with GREEDY + Whittaker
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("RUN B: Greedy + Whittaker-Henderson (experimental)\n")
cat(rep("=", 60), "\n")

t_wh <- system.time({
  result_wh <- optimize_windows(
    validated, plan,
    strategy_config = greedy_config(
      apply_smoothing = TRUE,
      smoothing_method = "whittaker",
      whittaker_lambda = 10
    ),
    window_mode = "density"
  )
})

# =====================================================================
# Comparison
# =====================================================================
cat("\n", rep("=", 60), "\n", sep = "")
cat("COMPARISON: SG vs Whittaker-Henderson\n")
cat(rep("=", 60), "\n\n")

# Extract m/z ranges
mz_sg <- result_sg$mz_optimization$mz_ranges
mz_wh <- result_wh$mz_optimization$mz_ranges

# Statistics
stats_sg <- result_sg$statistics
stats_wh <- result_wh$statistics

cat("| Metric                    |       SG |       WH |    Diff |\n")
cat("|---------------------------|----------|----------|--------|\n")
cat(sprintf("| Coverage (%%)              | %8.2f | %8.2f | %+6.2f |\n",
            stats_sg$coverage_percentage, stats_wh$coverage_percentage,
            stats_wh$coverage_percentage - stats_sg$coverage_percentage))
cat(sprintf("| Window width mean (Da)    | %8.2f | %8.2f | %+6.2f |\n",
            stats_sg$window_width_mean, stats_wh$window_width_mean,
            stats_wh$window_width_mean - stats_sg$window_width_mean))
cat(sprintf("| Window width SD (Da)      | %8.2f | %8.2f | %+6.2f |\n",
            stats_sg$window_width_sd, stats_wh$window_width_sd,
            stats_wh$window_width_sd - stats_sg$window_width_sd))
cat(sprintf("| Precursors/window mean    | %8.1f | %8.1f | %+6.1f |\n",
            stats_sg$mean_precursors_per_window, stats_wh$mean_precursors_per_window,
            stats_wh$mean_precursors_per_window - stats_sg$mean_precursors_per_window))
cat(sprintf("| Precursors/window CV      | %8.3f | %8.3f | %+6.3f |\n",
            stats_sg$cv_precursors, stats_wh$cv_precursors,
            stats_wh$cv_precursors - stats_sg$cv_precursors))
cat(sprintf("| Processing time (sec)     | %8.2f | %8.2f |        |\n",
            t_sg["elapsed"], t_wh["elapsed"]))

# Per-bin boundary comparison
cat("\n--- Per-RT-bin m/z boundary differences ---\n")
mz_min_diff <- mz_wh$mz_min - mz_sg$mz_min
mz_max_diff <- mz_wh$mz_max - mz_sg$mz_max
cat(sprintf("  mz_min shift: mean=%.1f Da, max=%.1f Da, SD=%.1f Da\n",
            mean(mz_min_diff), max(abs(mz_min_diff)), sd(mz_min_diff)))
cat(sprintf("  mz_max shift: mean=%.1f Da, max=%.1f Da, SD=%.1f Da\n",
            mean(mz_max_diff), max(abs(mz_max_diff)), sd(mz_max_diff)))

# Boundary smoothness: SD of first differences (lower = smoother)
sg_min_roughness <- sd(diff(mz_sg$mz_min))
wh_min_roughness <- sd(diff(mz_wh$mz_min))
sg_max_roughness <- sd(diff(mz_sg$mz_max))
wh_max_roughness <- sd(diff(mz_wh$mz_max))

cat("\n--- Boundary smoothness (SD of bin-to-bin changes, lower = smoother) ---\n")
cat(sprintf("  mz_min roughness: SG=%.2f, WH=%.2f (%+.1f%%)\n",
            sg_min_roughness, wh_min_roughness,
            100 * (wh_min_roughness - sg_min_roughness) / sg_min_roughness))
cat(sprintf("  mz_max roughness: SG=%.2f, WH=%.2f (%+.1f%%)\n",
            sg_max_roughness, wh_max_roughness,
            100 * (wh_max_roughness - sg_max_roughness) / sg_max_roughness))

# Edge bin handling
cat("\n--- Edge bin comparison (first/last 2 bins) ---\n")
n <- nrow(mz_sg)
for (i in c(1, 2, n - 1, n)) {
  cat(sprintf("  Bin %2d: SG=[%.0f-%.0f] WH=[%.0f-%.0f] n_prec=%d\n",
              i, mz_sg$mz_min[i], mz_sg$mz_max[i],
              mz_wh$mz_min[i], mz_wh$mz_max[i],
              mz_sg$n_precursors_covered[i]))
}

# Lambda sensitivity (quick)
cat("\n--- Lambda sensitivity (coverage %) ---\n")
for (lam in c(1, 5, 10, 50, 100)) {
  r <- optimize_windows(
    validated, plan,
    strategy_config = greedy_config(
      apply_smoothing = TRUE,
      smoothing_method = "whittaker",
      whittaker_lambda = lam
    ),
    window_mode = "density"
  )
  cat(sprintf("  lambda=%4d: coverage=%.2f%%, width_cv=%.3f, prec_cv=%.3f\n",
              lam, r$statistics$coverage_percentage,
              r$statistics$window_width_cv,
              r$statistics$cv_precursors))
}

cat("\n", rep("=", 60), "\n", sep = "")
cat("Comparison complete.\n")
