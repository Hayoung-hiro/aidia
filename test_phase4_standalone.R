# test_phase4_standalone.R - Standalone Phase 4 Visualization Test
#
# Purpose: Test Phase 4 visualization with completely mocked data
# No dependencies on Phase 1-3 implementations

cat("============================================================\n")
cat("Phase 4 Standalone Visualization Test\n")
cat("============================================================\n\n")

# Load only essential libraries
library(dplyr)
library(ggplot2)

# Source only Phase 4
cat("Loading Phase 4 visualization module...\n")
source("R/stage4_visualization.R")
cat("✓ Phase 4 loaded\n\n")

# =============================================================================
# Create Complete Mock Data for All Phase Outputs
# =============================================================================

cat("Creating mock data for all phases...\n\n")

set.seed(42)  # Reproducible results

n_precursors <- 5000
n_rt_bins <- 20
n_windows_per_bin <- 200

# === Mock Phase 1: ValidatedData ===
cat("  ✓ Creating ValidatedData (Phase 1)...\n")

validated_data <- structure(
  list(
    data = data.frame(
      RT.Start = runif(n_precursors, 10, 110),
      Precursor.Mz = rnorm(n_precursors, 500, 50),
      FWHM = rnorm(n_precursors, 0.3, 0.1),
      rt_group = sample(1:n_rt_bins, n_precursors, replace = TRUE)
    ) %>%
      filter(FWHM > 0.1, FWHM < 1.0, Precursor.Mz >= 400, Precursor.Mz <= 600),

    metadata = list(
      n_precursors = n_precursors,
      rt_range = c(10, 110),
      mz_range = c(400, 600)
    )
  ),
  class = c("ValidatedData", "list")
)

# === Mock Phase 2: DiagnosisResult ===
cat("  ✓ Creating DiagnosisResult (Phase 2)...\n")

fwhm_sec <- validated_data$data$FWHM * 60
current_cycle_time <- 2.0
dppp_values <- (1.7 * fwhm_sec) / current_cycle_time

diagnosis_result <- structure(
  list(
    current_status = list(
      current_cycle_time = current_cycle_time,
      dppp_distribution = dppp_values,
      dppp_stats = list(
        mean = mean(dppp_values),
        median = median(dppp_values),
        sd = sd(dppp_values),
        min = min(dppp_values),
        max = max(dppp_values)
      ),
      satisfaction_ratio = sum(dppp_values >= 7.5) / length(dppp_values),
      n_satisfied = sum(dppp_values >= 7.5),
      n_total = length(dppp_values)
    ),

    recommendation = list(
      optimal_cycle_time = 2.5,  # Recommended cycle time
      expected_satisfaction = 0.85
    )
  ),
  class = c("DiagnosisResult", "list")
)

# === Mock Phase 3A: WindowCountResult ===
cat("  ✓ Creating WindowCountResult (Phase 3A)...\n")

window_count_result <- structure(
  list(
    window_count = list(
      actual_window_count = n_windows_per_bin,
      mode = "optimize"
    )
  ),
  class = c("WindowCountResult", "list")
)

# === Mock Phase 3B: RTBinningResult ===
cat("  ✓ Creating RTBinningResult (Phase 3B)...\n")

rt_breaks <- seq(10, 110, length.out = n_rt_bins + 1)
rt_group_stats <- data.frame(
  rt_group = 1:n_rt_bins,
  rt_start = rt_breaks[-length(rt_breaks)],
  rt_end = rt_breaks[-1],
  n_precursors = as.vector(table(factor(validated_data$data$rt_group, levels = 1:n_rt_bins)))
)

rt_binning_result <- structure(
  list(
    data = validated_data,
    rt_group_stats = rt_group_stats,
    method = "time_unit"
  ),
  class = c("RTBinningResult", "list")
)

# === Mock Phase 3C: MzRangeResult ===
cat("  ✓ Creating MzRangeResult (Phase 3C)...\n")

mz_boundaries <- rt_group_stats %>%
  mutate(
    mz_min = 400 + rnorm(n_rt_bins, 0, 5),
    mz_max = 600 + rnorm(n_rt_bins, 0, 5)
  ) %>%
  mutate(
    mz_min = pmax(380, mz_min),
    mz_max = pmin(620, mz_max)
  )

mz_range_result <- structure(
  list(
    mz_boundaries = mz_boundaries,
    strategy = "smoothing",
    metadata = list(method = "savgol")
  ),
  class = c("MzRangeResult", "list")
)

# === Mock Phase 3D: WindowGenerationResult ===
cat("  ✓ Creating WindowGenerationResult (Phase 3D)...\n")

# Generate windows for each RT bin
windows_list <- list()
window_id <- 1

for (bin_id in 1:n_rt_bins) {
  mz_min <- mz_boundaries$mz_min[bin_id]
  mz_max <- mz_boundaries$mz_max[bin_id]
  mz_range <- mz_max - mz_min

  # Variable width windows (density-based simulation)
  for (w in 1:n_windows_per_bin) {
    width <- runif(1, 2, 10)  # Variable widths
    mz_start <- mz_min + (w - 1) * (mz_range / n_windows_per_bin)
    mz_end <- min(mz_start + width, mz_max)

    windows_list[[window_id]] <- data.frame(
      window_id = window_id,
      rt_bin_id = bin_id,
      mz_start = mz_start,
      mz_end = mz_end,
      mz_center = (mz_start + mz_end) / 2,
      window_width = mz_end - mz_start
    )

    window_id <- window_id + 1
  }
}

windows_df <- bind_rows(windows_list)

windows_result <- structure(
  list(
    windows = windows_df,

    metadata = list(
      method = "variable",
      total_windows = nrow(windows_df),
      n_rt_bins = n_rt_bins,
      mean_width = mean(windows_df$window_width),
      timestamp = Sys.time()
    ),

    statistics = list(
      windows_per_bin = table(windows_df$rt_bin_id),
      width_distribution = summary(windows_df$window_width)
    )
  ),
  class = c("WindowGenerationResult", "list")
)

cat("\n")
cat("═══════════════════════════════════════════════\n")
cat("Mock Data Summary:\n")
cat("═══════════════════════════════════════════════\n")
cat(sprintf("Precursors: %s\n", format(nrow(validated_data$data), big.mark = ",")))
cat(sprintf("RT bins: %d\n", n_rt_bins))
cat(sprintf("Total windows: %s\n", format(nrow(windows_df), big.mark = ",")))
cat(sprintf("Windows per bin: %d (avg)\n", n_windows_per_bin))
cat(sprintf("Current cycle time: %.2f sec\n", current_cycle_time))
cat(sprintf("DPPP satisfaction: %.1f%%\n", diagnosis_result$current_status$satisfaction_ratio * 100))
cat("═══════════════════════════════════════════════\n\n")

# =============================================================================
# Generate Visualizations
# =============================================================================

cat("Generating visualizations...\n\n")

viz_result <- generate_all_visualizations(
  validated_data = validated_data,
  diagnosis_result = diagnosis_result,
  window_count_result = window_count_result,
  rt_binning_result = rt_binning_result,
  mz_range_result = mz_range_result,
  windows_result = windows_result,
  target_dppp = 7.5,
  output_dir = "output/plots",
  save_individual = TRUE,
  dpi = 300
)

# =============================================================================
# Display Results
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("Visualization Generation Complete!\n")
cat("═══════════════════════════════════════════════\n\n")

cat("Generated Plots:\n")
for (i in 1:length(viz_result$plots)) {
  cat(sprintf("  %d. %s\n", i, names(viz_result$plots)[i]))
}

cat("\nOutput Files:\n")
for (file in viz_result$report_files$individual_plots) {
  cat(sprintf("  ✓ %s\n", file))
}

cat("\nSummary Statistics:\n")
cat(sprintf("  Target DPPP: %.1f\n", viz_result$summary_statistics$optimization_metrics$target_dppp))
cat(sprintf("  Current satisfaction: %.1f%%\n",
    viz_result$summary_statistics$optimization_metrics$current_satisfaction * 100))
cat(sprintf("  Recommended cycle time: %.2f sec\n",
    viz_result$summary_statistics$optimization_metrics$recommended_cycle_time))
cat(sprintf("  Total windows: %s\n",
    format(viz_result$summary_statistics$optimization_metrics$total_windows, big.mark = ",")))
cat(sprintf("  Mean window width: %.2f Da\n",
    viz_result$summary_statistics$performance_metrics$mean_window_width))
cat(sprintf("  Window width CV: %.1f%%\n",
    viz_result$summary_statistics$performance_metrics$window_width_cv))

cat(sprintf("\nGeneration Time: %.2f seconds\n", viz_result$metadata$plot_generation_time))

cat("\n═══════════════════════════════════════════════\n")
cat("✅ Phase 4 Standalone Test Complete!\n")
cat("═══════════════════════════════════════════════\n")
