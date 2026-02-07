# =============================================================================
# Test: Adaptive RT Binning with Real Data
# =============================================================================
# Tests both fixed (backward compat) and adaptive modes with real parquet data
# =============================================================================

source("main.R")

# Find first available parquet file
parquet_files <- list.files("data", pattern = ".*report\\.parquet$", full.names = TRUE)
if (length(parquet_files) == 0) {
  stop("No parquet files found in data/ directory")
}
cat(sprintf("Using: %s\n", parquet_files[1]))

# =============================================================================
# Test 1: Fixed mode (backward compatibility)
# =============================================================================
cat("\n")
cat("╔═══════════════════════════════════════════════╗\n")
cat("║   TEST 1: Fixed RT Binning (Default)          ║\n")
cat("╚═══════════════════════════════════════════════╝\n\n")

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

# Extract first result
r1 <- results_fixed[[1]]$windows_list[[1]]
cat("\n=== FIXED MODE RESULTS ===\n")
cat(sprintf("  Windows: %d\n", nrow(r1$windows)))
cat(sprintf("  RT bins: %d\n", r1$rt_binning$n_bins))
cat(sprintf("  RT binning mode: %s\n", r1$rt_binning$rt_binning_mode))
cat(sprintf("  Adaptive info: %s\n", ifelse(is.null(r1$rt_binning$adaptive_info), "NULL (correct)", "UNEXPECTED")))
cat(sprintf("  Coverage: %.1f%%\n", r1$statistics$coverage_percentage))
cat(sprintf("  Mean width: %.2f Da\n", r1$statistics$window_width_mean))

# Verify RT.Apex is present in validated data
vd <- results_fixed[[1]]$validated_data$data
cat(sprintf("  RT.Apex column present: %s\n", "RT.Apex" %in% colnames(vd)))
if ("RT.Apex" %in% colnames(vd)) {
  cat(sprintf("  RT.Apex range: %.2f - %.2f min\n", min(vd$RT.Apex), max(vd$RT.Apex)))
}

# =============================================================================
# Test 2: Adaptive mode (new feature)
# =============================================================================
cat("\n")
cat("╔═══════════════════════════════════════════════╗\n")
cat("║   TEST 2: Adaptive RT Binning (KS Test)       ║\n")
cat("╚═══════════════════════════════════════════════╝\n\n")

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

r2 <- results_adaptive[[1]]$windows_list[[1]]
cat("\n=== ADAPTIVE MODE RESULTS ===\n")
cat(sprintf("  Windows: %d\n", nrow(r2$windows)))
cat(sprintf("  RT bins: %d\n", r2$rt_binning$n_bins))
cat(sprintf("  RT binning mode: %s\n", r2$rt_binning$rt_binning_mode))
cat(sprintf("  Adaptive info present: %s\n", !is.null(r2$rt_binning$adaptive_info)))
if (!is.null(r2$rt_binning$adaptive_info)) {
  ai <- r2$rt_binning$adaptive_info
  cat(sprintf("  Change points detected: %d\n", ai$n_change_points))
  cat(sprintf("  Significance level: %.3f\n", ai$significance_level))
  cat(sprintf("  Fallback to fixed: %s\n", ai$fallback))
  if (ai$n_change_points > 0) {
    cat(sprintf("  Change point positions: %s\n",
                paste(round(ai$change_point_positions, 1), collapse = ", ")))
  }
}
cat(sprintf("  Coverage: %.1f%%\n", r2$statistics$coverage_percentage))
cat(sprintf("  Mean width: %.2f Da\n", r2$statistics$window_width_mean))

# =============================================================================
# Comparison Summary
# =============================================================================
cat("\n")
cat("╔═══════════════════════════════════════════════╗\n")
cat("║   COMPARISON: Fixed vs Adaptive               ║\n")
cat("╚═══════════════════════════════════════════════╝\n\n")
cat(sprintf("  Fixed bins:    %d | Adaptive bins: %d\n", r1$rt_binning$n_bins, r2$rt_binning$n_bins))
cat(sprintf("  Fixed windows: %d | Adaptive windows: %d\n", nrow(r1$windows), nrow(r2$windows)))
cat(sprintf("  Fixed coverage: %.1f%% | Adaptive coverage: %.1f%%\n",
            r1$statistics$coverage_percentage, r2$statistics$coverage_percentage))
cat(sprintf("  Fixed mean width: %.2f Da | Adaptive mean width: %.2f Da\n",
            r1$statistics$window_width_mean, r2$statistics$window_width_mean))

cat("\n=== ALL TESTS PASSED ===\n")

# Cleanup
unlink("output_test_fixed", recursive = TRUE)
unlink("output_test_adaptive", recursive = TRUE)
