# test_phase4_visualization.R - Test Phase 4 Visualization with Real/Mock Data
#
# Purpose: Generate and validate all 8 essential plots from Phase 4
# Generates visual outputs for interpretation and quality assessment

cat("============================================================\n")
cat("Testing Phase 4: Visualization & Reporting\n")
cat("============================================================\n\n")

# Load required libraries
library(dplyr)
library(ggplot2)
# library(gridExtra)  # Not needed for individual plots

# Source all modules
cat("Loading modules...\n")
source("R/data_loader.R")
source("R/stage1_data_validation.R")
source("R/stage2_dppp_diagnosis.R")
source("R/stage3_window_optimization/module3a_window_count.R")
source("R/stage3_window_optimization/module3b_rt_binning.R")
source("R/stage3_window_optimization/module3c_mz_range_optimization.R")
source("R/stage3_window_optimization/module3d_window_generation.R")
source("R/stage4_visualization.R")
source("R/rt_segmentation.R")
source("config/instruments.R")
cat("✓ All modules loaded\n\n")

# =============================================================================
# Option 1: Use real data if available
# =============================================================================

use_real_data <- file.exists("data/report.parquet")

if (use_real_data) {
  cat("Using REAL DATA from report.parquet\n\n")

  # ===== Phase 1: Data Validation =====
  cat("=== Phase 1: Data Validation ===\n")
  raw_data <- load_diann_data("data/report.parquet")

  # Filter to reasonable ranges for testing
  raw_data <- raw_data %>%
    filter(
      RT.Start >= 10,
      RT.Start <= 110,
      Precursor.Mz >= 400,
      Precursor.Mz <= 600,
      !is.na(FWHM),
      FWHM > 0
    )

  validated_data <- validate_diann_data(raw_data)
  cat(sprintf("✓ Validated %d precursors\n\n", nrow(validated_data$data)))

} else {
  cat("Using SYNTHETIC DATA (report.parquet not found)\n\n")

  # Create synthetic data
  n_precursors <- 5000

  # ===== Phase 1: Mock Data =====
  cat("=== Phase 1: Creating Mock Data ===\n")

  mock_data <- data.frame(
    RT.Start = runif(n_precursors, 10, 110),
    Precursor.Mz = rnorm(n_precursors, 500, 50),  # Centered at 500 Da
    FWHM = rnorm(n_precursors, 0.3, 0.1)  # ~0.3 min FWHM
  ) %>%
    filter(
      FWHM > 0.1,
      FWHM < 1.0,
      Precursor.Mz >= 400,
      Precursor.Mz <= 600
    )

  validated_data <- structure(
    list(
      data = mock_data,
      metadata = list(
        n_precursors = nrow(mock_data),
        rt_range = c(10, 110),
        mz_range = c(400, 600)
      )
    ),
    class = c("ValidatedData", "list")
  )

  cat(sprintf("✓ Created %d synthetic precursors\n\n", nrow(mock_data)))
}

# =============================================================================
# Phase 2: DPPP Diagnosis
# =============================================================================

cat("=== Phase 2: DPPP Diagnosis ===\n")

# Get instrument config (for Phase 3A)
instrument_config <- get_instrument_configs()$astral

# Diagnose current status
diagnosis <- diagnose_dppp_status(
  validated_data = validated_data,
  current_cycle_time = 2.0,  # Current 2-second cycle
  target_dppp = 7.5,
  target_satisfaction = 0.7
)

cat(sprintf("Current satisfaction: %.1f%%\n", diagnosis$current_status$satisfaction_ratio * 100))
cat(sprintf("Recommended cycle time: %.2f sec\n\n", diagnosis$recommendation$optimal_cycle_time))

# =============================================================================
# Phase 3A: Window Count Determination
# =============================================================================

cat("=== Phase 3A: Window Count Determination ===\n")

window_count_result <- determine_window_count(
  diagnosis_result = diagnosis,
  instrument_config = instrument_config,
  user_params = list(
    window_count_mode = "optimize",
    ms1_scans = 0  # Parallel mode for Astral
  )
)

n_windows <- window_count_result$window_count$actual_window_count
cat(sprintf("Determined window count: %d\n\n", n_windows))

# =============================================================================
# Phase 3B: RT Binning
# =============================================================================

cat("=== Phase 3B: RT Binning ===\n")

rt_binning_result <- segment_by_rt_bins(
  validated_data = validated_data,
  method = "time_unit",
  time_unit = 5,  # 5-minute bins
  min_precursors = 10
)

n_rt_bins <- max(rt_binning_result$data$data$rt_group, na.rm = TRUE)
cat(sprintf("Created %d RT bins\n\n", n_rt_bins))

# Update validated_data with rt_group
validated_data$data <- rt_binning_result$data$data

# =============================================================================
# Phase 3C: m/z Range Optimization
# =============================================================================

cat("=== Phase 3C: m/z Range Optimization ===\n")

mz_range_result <- optimize_mz_ranges(
  rt_binning_result = rt_binning_result,
  strategy = "smoothing",
  dynamic = TRUE,
  smoothing_method = "savgol",
  smoothing_window_size = 7
)

cat(sprintf("Optimized m/z ranges for %d RT segments\n\n", nrow(mz_range_result$mz_boundaries)))

# =============================================================================
# Phase 3D: Window Generation
# =============================================================================

cat("=== Phase 3D: Window Generation ===\n")

windows_result <- generate_isolation_windows(
  rt_binning_result = rt_binning_result,
  mz_range_result = mz_range_result,
  n_windows = n_windows,
  method = "variable",  # Density-based adaptive windows
  overlap_mode = "none",
  min_width_da = 2.0,
  max_width_da = 80.0
)

total_windows <- nrow(windows_result$windows)
cat(sprintf("Generated %d isolation windows\n\n", total_windows))

# =============================================================================
# Phase 4: Visualization
# =============================================================================

cat("=== Phase 4: Generating Visualizations ===\n\n")

# Generate all plots
viz_result <- generate_all_visualizations(
  validated_data = validated_data,
  diagnosis_result = diagnosis,
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
# Display plots for visual inspection
# =============================================================================

cat("\n=== Displaying Plots for Interpretation ===\n\n")

# Plot 1: DPPP Density
cat("Plot 1: DPPP Density Distribution\n")
cat("─────────────────────────────────────────\n")
cat("INTERPRETATION:\n")
cat("- Shows current DPPP distribution vs target threshold (7.5)\n")
cat("- Area to the RIGHT of yellow line = satisfied precursors\n")
cat("- Higher DPPP = better chromatographic sampling\n")
cat(sprintf("- Current satisfaction: %.1f%%\n\n",
    diagnosis$current_status$satisfaction_ratio * 100))

print(viz_result$plots$dppp_density)
cat("\nPress Enter to continue to next plot...")
readline()

# Plot 2: RT Window Allocation
cat("\n\nPlot 2: RT-dependent Window Allocation\n")
cat("─────────────────────────────────────────\n")
cat("INTERPRETATION:\n")
cat("- Purple bars = number of precursors per RT segment\n")
cat("- Yellow line = number of windows allocated per RT segment\n")
cat("- Windows should follow precursor density pattern\n")
cat(sprintf("- Average %.1f windows per RT segment\n\n",
    mean(table(windows_result$windows$rt_bin_id))))

print(viz_result$plots$rt_window_allocation)
cat("\nPress Enter to continue to next plot...")
readline()

# Plot 3: RT-m/z Heatmap
cat("\n\nPlot 3: RT-m/z Precursor Density Heatmap\n")
cat("─────────────────────────────────────────\n")
cat("INTERPRETATION:\n")
cat("- Shows WHERE precursors are distributed (RT × m/z space)\n")
cat("- Red/yellow = high density regions (require more windows)\n")
cat("- Blue/purple = low density regions\n")
cat("- Helps identify 'hotspots' for optimization\n\n")

print(viz_result$plots$rt_mz_density_heatmap)
cat("\nPress Enter to continue to next plot...")
readline()

# Plot 4: m/z Normalized Density
cat("\n\nPlot 4: m/z Normalized Density Profile\n")
cat("─────────────────────────────────────────\n")
cat("INTERPRETATION:\n")
cat("- Overall m/z distribution across ALL RT times\n")
cat("- Yellow curve = density envelope\n")
cat("- Vertical dashed lines = RT-dependent m/z boundaries\n")
cat("- Shows if m/z range optimization is working properly\n\n")

print(viz_result$plots$mz_normalized_density)
cat("\nPress Enter to continue to next plot...")
readline()

# Plot 5: Window Width Distribution
cat("\n\nPlot 5: Window Width Distribution\n")
cat("─────────────────────────────────────────\n")
cat("INTERPRETATION:\n")
cat("- Distribution of isolation window widths\n")
cat("- Fixed method = single peak (all same width)\n")
cat("- Variable method = spread distribution (adaptive)\n")
cat(sprintf("- Mean width: %.2f Da\n",
    mean(windows_result$windows$window_width, na.rm = TRUE)))
cat(sprintf("- CV = %.1f%% (lower = more uniform)\n\n",
    viz_result$summary_statistics$performance_metrics$window_width_cv))

print(viz_result$plots$window_width_distribution)
cat("\nPress Enter to continue to next plot...")
readline()

# Plot 6: Precursor Coverage
cat("\n\nPlot 6: Precursor Coverage Map\n")
cat("─────────────────────────────────────────\n")
cat("INTERPRETATION:\n")
cat("- Shows how many windows cover each precursor\n")
cat("- CRITICAL: All precursors should have coverage ≥ 1\n")
cat("- Red bar at 0 = uncovered precursors (BAD)\n")
cat("- Coverage > 1 = overlap (good for quantification)\n")

# Calculate coverage stats
precursor_coverage <- validated_data$data %>%
  rowwise() %>%
  mutate(
    coverage = sum(
      windows_result$windows$mz_start <= Precursor.Mz &
      windows_result$windows$mz_end >= Precursor.Mz &
      windows_result$windows$rt_bin_id == rt_group
    )
  )

uncovered <- sum(precursor_coverage$coverage == 0)
cat(sprintf("- Uncovered precursors: %d (%.2f%%)\n\n",
    uncovered, uncovered / nrow(precursor_coverage) * 100))

print(viz_result$plots$precursor_coverage_map)
cat("\nPress Enter to continue to next plot...")
readline()

# Plot 7: Window Efficiency
cat("\n\nPlot 7: Window Efficiency Analysis\n")
cat("─────────────────────────────────────────\n")
cat("INTERPRETATION:\n")
cat("- Shows distribution of 'precursors per window'\n")
cat("- Variable method should show UNIFORM distribution\n")
cat("- Fixed method may show high variability\n")
cat("- Low CV% = windows have similar precursor counts (GOOD)\n")

window_efficiency <- windows_result$windows %>%
  rowwise() %>%
  mutate(
    n_prec = sum(
      validated_data$data$Precursor.Mz >= mz_start &
      validated_data$data$Precursor.Mz <= mz_end &
      validated_data$data$rt_group == rt_bin_id
    )
  )

cat(sprintf("- Mean precursors/window: %.1f\n", mean(window_efficiency$n_prec)))
cat(sprintf("- CV = %.1f%%\n\n", sd(window_efficiency$n_prec) / mean(window_efficiency$n_prec) * 100))

print(viz_result$plots$window_efficiency)
cat("\nPress Enter to continue to final plot...")
readline()

# Plot 8: DPPP Achievement Heatmap
cat("\n\nPlot 8: DPPP Achievement Heatmap (Predicted)\n")
cat("─────────────────────────────────────────\n")
cat("INTERPRETATION:\n")
cat("- Predicts DPPP across RT × m/z space with recommended cycle time\n")
cat("- GREEN = meets target DPPP (GOOD)\n")
cat("- YELLOW = marginal\n")
cat("- RED = below target DPPP (needs attention)\n")
cat("- Black dashed line = target DPPP contour\n")
cat(sprintf("- Recommended cycle time: %.2f sec\n\n",
    diagnosis$recommendation$optimal_cycle_time))

print(viz_result$plots$dppp_achievement_heatmap)

cat("\n\n")
cat("═══════════════════════════════════════════════\n")
cat("Visualization Test Complete!\n")
cat("═══════════════════════════════════════════════\n")
cat(sprintf("Generated: %d plots\n", length(viz_result$plots)))
cat(sprintf("Output directory: %s\n", viz_result$metadata$output_directory))
cat(sprintf("Time elapsed: %.1f seconds\n", viz_result$metadata$plot_generation_time))
cat("═══════════════════════════════════════════════\n\n")

# Print summary statistics
cat("SUMMARY STATISTICS:\n")
cat("─────────────────────────────────────────\n")
cat(sprintf("Total precursors: %s\n",
    format(nrow(validated_data$data), big.mark = ",")))
cat(sprintf("Total windows: %s\n",
    format(total_windows, big.mark = ",")))
cat(sprintf("RT bins: %d\n", n_rt_bins))
cat(sprintf("Target DPPP: %.1f\n", 7.5))
cat(sprintf("Current satisfaction: %.1f%%\n",
    diagnosis$current_status$satisfaction_ratio * 100))
cat(sprintf("Recommended cycle time: %.2f sec\n",
    diagnosis$recommendation$optimal_cycle_time))
cat(sprintf("Mean window width: %.2f Da\n",
    viz_result$summary_statistics$performance_metrics$mean_window_width))
cat(sprintf("Window width CV: %.1f%%\n",
    viz_result$summary_statistics$performance_metrics$window_width_cv))
cat("═══════════════════════════════════════════════\n")
