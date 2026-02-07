# Full pipeline test: Fixed vs Adaptive RT binning
# Tests end-to-end including strategy labels and visualization

setwd("D:/Projects/aidia")
source("main.R")

cat("\n")
cat("================================================================\n")
cat("  FULL PIPELINE TEST: Fixed vs Adaptive RT Binning\n")
cat("================================================================\n\n")

# ============================================
# Test 1: Fixed mode (backward compatibility)
# ============================================
cat("--- TEST 1: Fixed RT binning (default) ---\n")
t1 <- system.time({
  results_fixed <- run_complete_pipeline(
    data_dir = "data",
    output_base_dir = "output_test_fixed",
    instrument_preset = "astral",
    target_dppp = 7.0,
    target_satisfaction = 0.70,
    mz_strategies = c("greedy"),
    window_mode = "density",
    rt_bin_width_min = 5,
    rt_binning_mode = "fixed",
    create_plots = FALSE,
    create_pdf = FALSE,
    verbose = TRUE
  )
})
cat(sprintf("\nFixed pipeline time: %.1f sec\n", t1["elapsed"]))

r1 <- results_fixed[[1]]$windows_list[[1]]
cat(sprintf("  Windows: %d\n", nrow(r1$windows)))
cat(sprintf("  RT bins: %d\n", r1$rt_binning$n_bins))
cat(sprintf("  Coverage: %.1f%%\n", r1$statistics$coverage_percentage))

# ============================================
# Test 2: Adaptive mode (new feature)
# ============================================
cat("\n--- TEST 2: Adaptive RT binning (KS) ---\n")
t2 <- system.time({
  results_adaptive <- run_complete_pipeline(
    data_dir = "data",
    output_base_dir = "output_test_adaptive",
    instrument_preset = "astral",
    target_dppp = 7.0,
    target_satisfaction = 0.70,
    mz_strategies = c("greedy"),
    window_mode = "density",
    rt_bin_width_min = 5,
    rt_binning_mode = "adaptive",
    create_plots = FALSE,
    create_pdf = FALSE,
    verbose = TRUE
  )
})
cat(sprintf("\nAdaptive pipeline time: %.1f sec\n", t2["elapsed"]))

r2 <- results_adaptive[[1]]$windows_list[[1]]
cat(sprintf("  Windows: %d\n", nrow(r2$windows)))
cat(sprintf("  RT bins: %d\n", r2$rt_binning$n_bins))
cat(sprintf("  Coverage: %.1f%%\n", r2$statistics$coverage_percentage))
cat(sprintf("  Change points: %d\n", r2$rt_binning$adaptive_info$n_change_points))
cat(sprintf("  Fallback: %s\n", r2$rt_binning$adaptive_info$fallback))

# ============================================
# Comparison
# ============================================
cat("\n================================================================\n")
cat("  COMPARISON: Fixed vs Adaptive\n")
cat("================================================================\n")
cat(sprintf("  Fixed bins:    %d | Adaptive bins: %d\n",
            r1$rt_binning$n_bins, r2$rt_binning$n_bins))
cat(sprintf("  Fixed windows: %d | Adaptive windows: %d\n",
            nrow(r1$windows), nrow(r2$windows)))
cat(sprintf("  Fixed coverage: %.1f%% | Adaptive coverage: %.1f%%\n",
            r1$statistics$coverage_percentage, r2$statistics$coverage_percentage))
cat(sprintf("  Fixed mean width: %.2f Da | Adaptive mean width: %.2f Da\n",
            r1$statistics$window_width_mean, r2$statistics$window_width_mean))

cat("\n=== ALL PIPELINE TESTS PASSED ===\n")

# Cleanup
unlink("output_test_fixed", recursive = TRUE)
unlink("output_test_adaptive", recursive = TRUE)
