# test_final_workflow.R - Complete workflow test with real data

cat("═══════════════════════════════════════════════════════════════\n")
cat("  DIA Window Optimizer - Final Workflow Test\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# Load required libraries
suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(ggplot2)
  library(arrow)
})

# Source all required modules
cat("Loading modules...\n")
source("R/stage1_data_validation.R")
source("R/stage2_dppp_diagnosis.R")
source("R/stage3_window_optimization/module3a_window_count.R")
source("R/stage3_window_optimization/module3b_rt_binning.R")
source("R/stage3_window_optimization/module3c_mz_range_optimization.R")
source("R/stage3_window_optimization/module3d_window_generation.R")
cat("✅ All modules loaded\n\n")

# Configuration
OUTPUT_DIR <- "final_test_orbitrap"
INPUT_FILE <- "rawfile/report.parquet"

cat("Configuration:\n")
cat(sprintf("  Input file: %s\n", INPUT_FILE))
cat(sprintf("  Output directory: %s\n", OUTPUT_DIR))
cat("\n")

# Check input file exists
if (!file.exists(INPUT_FILE)) {
  stop(sprintf("❌ Input file not found: %s", INPUT_FILE))
}

#═══════════════════════════════════════════════════════════════
# Stage 1: Data Validation
#═══════════════════════════════════════════════════════════════
cat("─────────────────────────────────────────────────────────────\n")
cat("Stage 1: Data Validation\n")
cat("─────────────────────────────────────────────────────────────\n")

stage1_start <- Sys.time()

validated_data <- create_validated_dataset(
  proteome_file = INPUT_FILE,
  rt_range = NULL,  # Use full RT range
  mz_range = NULL,  # Use full m/z range
  enable_raw_metadata = FALSE,
  quality_threshold = 0.8,
  apply_quality_filters = TRUE
)

stage1_end <- Sys.time()
stage1_time <- as.numeric(difftime(stage1_end, stage1_start, units = "secs"))

cat(sprintf("\n✅ Stage 1 complete (%.2f sec)\n", stage1_time))
cat(sprintf("   Precursors: %d\n", validated_data$metadata$n_precursors))
cat(sprintf("   RT range: %.2f - %.2f min\n",
            validated_data$metadata$rt_range[1],
            validated_data$metadata$rt_range[2]))
cat(sprintf("   m/z range: %.2f - %.2f\n",
            validated_data$metadata$mz_range[1],
            validated_data$metadata$mz_range[2]))

# Save Stage 1 output
saveRDS(validated_data, file.path(OUTPUT_DIR, "stage1_validated_data.rds"))
cat(sprintf("   Saved: %s\n", file.path(OUTPUT_DIR, "stage1_validated_data.rds")))

#═══════════════════════════════════════════════════════════════
# Stage 2: DPPP Diagnosis
#═══════════════════════════════════════════════════════════════
cat("\n─────────────────────────────────────────────────────────────\n")
cat("Stage 2: DPPP Diagnosis\n")
cat("─────────────────────────────────────────────────────────────\n")

stage2_start <- Sys.time()

# Calculate current cycle time from mean FWHM
# For Astral: assuming 25 windows currently
current_cycle_time <- validated_data$metadata$fwhm_stats$mean / 7.0  # DPPP formula

diagnosis <- diagnose_dppp_status(
  validated_data = validated_data,
  current_cycle_time = current_cycle_time,
  target_dppp = 7.0,
  target_satisfaction = 0.85,
  dppp_tolerance = 0.5
)

stage2_end <- Sys.time()
stage2_time <- as.numeric(difftime(stage2_end, stage2_start, units = "secs"))

cat(sprintf("\n✅ Stage 2 complete (%.2f sec)\n", stage2_time))
cat(sprintf("   Current satisfaction ratio: %.1f%%\n",
            diagnosis$current_state$satisfaction_ratio * 100))
cat(sprintf("   Required cycle time: %.3f sec\n",
            diagnosis$recommendation$required_cycle_time_sec))
cat(sprintf("   Adjustment needed: %s\n",
            ifelse(diagnosis$recommendation$needs_adjustment,
                   diagnosis$recommendation$adjustment_direction,
                   "NO")))

# Save Stage 2 output
saveRDS(diagnosis, file.path(OUTPUT_DIR, "stage2_diagnosis.rds"))
cat(sprintf("   Saved: %s\n", file.path(OUTPUT_DIR, "stage2_diagnosis.rds")))

#═══════════════════════════════════════════════════════════════
# Stage 3A: Window Count Determination
#═══════════════════════════════════════════════════════════════
cat("\n─────────────────────────────────────────────────────────────\n")
cat("Stage 3A: Window Count Determination\n")
cat("─────────────────────────────────────────────────────────────\n")

stage3a_start <- Sys.time()

window_count_result <- determine_window_count(
  diagnosis = diagnosis,
  target_cycle_time_sec = diagnosis$recommendation$required_cycle_time_sec,
  instrument_preset = "orbitrap"
)

stage3a_end <- Sys.time()
stage3a_time <- as.numeric(difftime(stage3a_end, stage3a_start, units = "secs"))

cat(sprintf("\n✅ Stage 3A complete (%.2f sec)\n", stage3a_time))
cat(sprintf("   Window count: %d\n", window_count_result$window_count))
cat(sprintf("   Calculated cycle time: %.3f sec\n", window_count_result$calculated_cycle_time_sec))
cat(sprintf("   Target cycle time: %.3f sec\n", window_count_result$target_cycle_time_sec))
cat(sprintf("   Feasibility: %s\n",
            ifelse(window_count_result$feasibility_checks$cycle_time_check$is_feasible,
                   "✅ Feasible", "❌ Not feasible")))

# Save Stage 3A output
saveRDS(window_count_result, file.path(OUTPUT_DIR, "stage3a_window_count.rds"))
cat(sprintf("   Saved: %s\n", file.path(OUTPUT_DIR, "stage3a_window_count.rds")))

#═══════════════════════════════════════════════════════════════
# Stage 3B: RT Binning
#═══════════════════════════════════════════════════════════════
cat("\n─────────────────────────────────────────────────────────────\n")
cat("Stage 3B: RT Binning\n")
cat("─────────────────────────────────────────────────────────────\n")

stage3b_start <- Sys.time()

rt_binning_result <- perform_rt_binning(
  validated_data = validated_data,
  rt_bin_width_min = 5  # 5-minute bins
)

stage3b_end <- Sys.time()
stage3b_time <- as.numeric(difftime(stage3b_end, stage3b_start, units = "secs"))

cat(sprintf("\n✅ Stage 3B complete (%.2f sec)\n", stage3b_time))
cat(sprintf("   RT bins: %d\n", rt_binning_result$insights$n_segments))
cat(sprintf("   Precursors per bin: %.0f (min: %d, max: %d)\n",
            rt_binning_result$insights$mean_precursors_per_segment,
            rt_binning_result$insights$min_precursors_per_segment,
            rt_binning_result$insights$max_precursors_per_segment))

# Save Stage 3B output
saveRDS(rt_binning_result, file.path(OUTPUT_DIR, "stage3b_rt_binning.rds"))
cat(sprintf("   Saved: %s\n", file.path(OUTPUT_DIR, "stage3b_rt_binning.rds")))

# Save RT binning plot
rt_plot <- visualize_rt_binning(rt_binning_result)
ggsave(
  filename = file.path(OUTPUT_DIR, "stage3b_rt_binning_plot.png"),
  plot = rt_plot,
  width = 12, height = 8, dpi = 300
)
cat(sprintf("   Saved: %s\n", file.path(OUTPUT_DIR, "stage3b_rt_binning_plot.png")))

#═══════════════════════════════════════════════════════════════
# Stage 3C: m/z Range Optimization
#═══════════════════════════════════════════════════════════════
cat("\n─────────────────────────────────────────────────────────────\n")
cat("Stage 3C: m/z Range Optimization (All 4 Strategies)\n")
cat("─────────────────────────────────────────────────────────────\n")

stage3c_start <- Sys.time()

strategies <- c("coverage", "quantile", "outlier", "smoothing")
mz_results <- list()

for (strategy in strategies) {
  cat(sprintf("\nTesting strategy: %s\n", strategy))

  mz_result <- optimize_mz_ranges(
    rt_binning_result = rt_binning_result,
    strategy = strategy,
    target_coverage = 0.95,
    quantile_lower = 0.05,
    quantile_upper = 0.95,
    outlier_threshold = 3.0,
    smoothing_window_size = 7,
    continuous_smooth = (strategy == "smoothing")
  )

  mz_results[[strategy]] <- mz_result

  cat(sprintf("  Mean width: %.1f Da\n", mz_result$insights$mean_width))
  cat(sprintf("  Mean coverage: %.1f%%\n", mz_result$insights$mean_coverage * 100))
  cat(sprintf("  Range reduction: %.1f%%\n", mz_result$insights$range_reduction * 100))

  # Save individual strategy result
  saveRDS(mz_result, file.path(OUTPUT_DIR, sprintf("stage3c_mz_%s.rds", strategy)))
}

stage3c_end <- Sys.time()
stage3c_time <- as.numeric(difftime(stage3c_end, stage3c_start, units = "secs"))

cat(sprintf("\n✅ Stage 3C complete (%.2f sec)\n", stage3c_time))
cat("   Tested 4 strategies: coverage, quantile, outlier, smoothing\n")

#═══════════════════════════════════════════════════════════════
# Stage 3D: Window Generation (All 3 Modes)
#═══════════════════════════════════════════════════════════════
cat("\n─────────────────────────────────────────────────────────────\n")
cat("Stage 3D: Window Generation (All Modes, All Strategies)\n")
cat("─────────────────────────────────────────────────────────────\n")

stage3d_start <- Sys.time()

window_modes <- c("fixed", "variable")
window_results <- list()

for (strategy in strategies) {
  window_results[[strategy]] <- list()

  cat(sprintf("\nStrategy: %s\n", strategy))

  for (mode in window_modes) {
    cat(sprintf("  Mode: %s\n", mode))

    window_result <- generate_isolation_windows(
      rt_binning_result = rt_binning_result,
      mz_range_result = mz_results[[strategy]],
      window_type = mode,
      n_windows = window_count_result$window_count
    )

    window_results[[strategy]][[mode]] <- window_result

    cat(sprintf("    Windows: %d (expected: %d per bin × %d bins = %d)\n",
                nrow(window_result$windows),
                window_count_result$window_count,
                rt_binning_result$insights$n_segments,
                window_count_result$window_count * rt_binning_result$insights$n_segments))
    cat(sprintf("    Mean width: %.2f Da\n", window_result$insights$mean_window_width))
    cat(sprintf("    Coverage: %.1f%%\n", window_result$insights$coverage_ratio * 100))

    # Save window result
    saveRDS(
      window_result,
      file.path(OUTPUT_DIR, sprintf("stage3d_windows_%s_%s.rds", strategy, mode))
    )

    # Export to CSV
    csv_file <- file.path(OUTPUT_DIR, sprintf("windows_%s_%s.csv", strategy, mode))

    # Determine instrument type from OUTPUT_DIR
    instrument_type <- if (grepl("orbitrap", OUTPUT_DIR)) {
      "orbitrap"
    } else if (grepl("astral", OUTPUT_DIR)) {
      "astral"
    } else {
      window_count_result$instrument_config$instrument_type  # fallback to actual config
    }

    export_windows_to_csv(
      window_result = window_result,
      output_file = csv_file,
      instrument_type = instrument_type,
      strategy = strategy
    )
    cat(sprintf("    Saved CSV: %s\n", csv_file))
  }
}

stage3d_end <- Sys.time()
stage3d_time <- as.numeric(difftime(stage3d_end, stage3d_start, units = "secs"))

cat(sprintf("\n✅ Stage 3D complete (%.2f sec)\n", stage3d_time))
cat(sprintf("   Generated windows for 4 strategies × 2 modes = 8 configurations\n"))

#═══════════════════════════════════════════════════════════════
# Summary and Comparison
#═══════════════════════════════════════════════════════════════
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Performance Comparison\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Strategy Performance (Variable Mode):\n")
cat("Strategy          | Mean Width | Coverage | Range Reduction | Windows\n")
cat("------------------|------------|----------|-----------------|--------\n")

for (strategy in strategies) {
  result <- window_results[[strategy]][["variable"]]
  cat(sprintf("%-17s | %7.1f Da | %7.1f%% | %14.1f%% | %7d\n",
              tools::toTitleCase(strategy),
              result$insights$mean_window_width,
              result$insights$coverage_ratio * 100,
              mz_results[[strategy]]$insights$range_reduction * 100,
              nrow(result$windows)))
}

cat("\n")
cat("Window Mode Comparison (Smoothing Strategy):\n")
cat("Mode       | Mean Width | Coverage | CV (Width) | Windows\n")
cat("-----------|------------|----------|------------|--------\n")

for (mode in window_modes) {
  result <- window_results[["smoothing"]][[mode]]
  cat(sprintf("%-10s | %7.1f Da | %7.1f%% | %9.3f | %7d\n",
              tools::toTitleCase(mode),
              result$insights$mean_window_width,
              result$insights$coverage_ratio * 100,
              result$insights$cv_window_width,
              nrow(result$windows)))
}

#═══════════════════════════════════════════════════════════════
# Timing Summary
#═══════════════════════════════════════════════════════════════
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Timing Summary\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

total_time <- stage1_time + stage2_time + stage3a_time +
              stage3b_time + stage3c_time + stage3d_time

cat(sprintf("Stage 1 (Data Validation):      %7.2f sec (%5.1f%%)\n",
            stage1_time, stage1_time/total_time*100))
cat(sprintf("Stage 2 (DPPP Diagnosis):        %7.2f sec (%5.1f%%)\n",
            stage2_time, stage2_time/total_time*100))
cat(sprintf("Stage 3A (Window Count):         %7.2f sec (%5.1f%%)\n",
            stage3a_time, stage3a_time/total_time*100))
cat(sprintf("Stage 3B (RT Binning):           %7.2f sec (%5.1f%%)\n",
            stage3b_time, stage3b_time/total_time*100))
cat(sprintf("Stage 3C (m/z Optimization):     %7.2f sec (%5.1f%%)\n",
            stage3c_time, stage3c_time/total_time*100))
cat(sprintf("Stage 3D (Window Generation):    %7.2f sec (%5.1f%%)\n",
            stage3d_time, stage3d_time/total_time*100))
cat(sprintf("─────────────────────────────────────────────────────\n"))
cat(sprintf("Total:                           %7.2f sec\n", total_time))

#═══════════════════════════════════════════════════════════════
# Save Summary Report
#═══════════════════════════════════════════════════════════════
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Saving Summary Report\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

summary_report <- list(
  timestamp = Sys.time(),
  input_file = INPUT_FILE,
  stage1 = list(
    n_precursors = validated_data$metadata$n_precursors,
    rt_range = validated_data$metadata$rt_range,
    mz_range = validated_data$metadata$mz_range,
    time_sec = stage1_time
  ),
  stage2 = list(
    target_dppp = 7.0,
    satisfaction_ratio = diagnosis$current_state$satisfaction_ratio,
    required_cycle_time_sec = diagnosis$recommendation$required_cycle_time_sec,
    current_cycle_time_sec = diagnosis$recommendation$current_cycle_time_sec,
    needs_adjustment = diagnosis$recommendation$needs_adjustment,
    time_sec = stage2_time
  ),
  stage3a = list(
    n_windows = window_count_result$window_count,
    calculated_cycle_time_sec = window_count_result$calculated_cycle_time_sec,
    target_cycle_time_sec = window_count_result$target_cycle_time_sec,
    is_feasible = window_count_result$feasibility_checks$cycle_time_check$is_feasible,
    time_sec = stage3a_time
  ),
  stage3b = list(
    n_segments = rt_binning_result$insights$n_segments,
    mean_precursors = rt_binning_result$insights$mean_precursors_per_segment,
    time_sec = stage3b_time
  ),
  stage3c = lapply(strategies, function(s) {
    list(
      strategy = s,
      mean_width = mz_results[[s]]$insights$mean_width,
      mean_coverage = mz_results[[s]]$insights$mean_coverage,
      range_reduction = mz_results[[s]]$insights$range_reduction
    )
  }),
  stage3d = lapply(strategies, function(s) {
    lapply(window_modes, function(m) {
      list(
        strategy = s,
        mode = m,
        n_windows = nrow(window_results[[s]][[m]]$windows),
        mean_width = window_results[[s]][[m]]$insights$mean_window_width,
        coverage = window_results[[s]][[m]]$insights$coverage_ratio
      )
    })
  }),
  timing = list(
    stage1_sec = stage1_time,
    stage2_sec = stage2_time,
    stage3a_sec = stage3a_time,
    stage3b_sec = stage3b_time,
    stage3c_sec = stage3c_time,
    stage3d_sec = stage3d_time,
    total_sec = total_time
  )
)

saveRDS(summary_report, file.path(OUTPUT_DIR, "summary_report.rds"))
cat(sprintf("✅ Saved: %s\n", file.path(OUTPUT_DIR, "summary_report.rds")))

# Save as JSON for easy reading
library(jsonlite)
write_json(
  summary_report,
  file.path(OUTPUT_DIR, "summary_report.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)
cat(sprintf("✅ Saved: %s\n", file.path(OUTPUT_DIR, "summary_report.json")))

#═══════════════════════════════════════════════════════════════
# Final Output Summary
#═══════════════════════════════════════════════════════════════
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Final Output Summary\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

output_files <- list.files(OUTPUT_DIR, full.names = FALSE)
cat(sprintf("Total files generated: %d\n\n", length(output_files)))

cat("RDS files (stage outputs):\n")
rds_files <- grep("\\.rds$", output_files, value = TRUE)
for (f in rds_files) {
  cat(sprintf("  - %s\n", f))
}

cat("\nCSV files (method files):\n")
csv_files <- grep("\\.csv$", output_files, value = TRUE)
for (f in csv_files) {
  cat(sprintf("  - %s\n", f))
}

cat("\nVisualization files:\n")
plot_files <- grep("\\.(png|pdf)$", output_files, value = TRUE)
for (f in plot_files) {
  cat(sprintf("  - %s\n", f))
}

cat("\nReport files:\n")
report_files <- grep("\\.json$", output_files, value = TRUE)
for (f in report_files) {
  cat(sprintf("  - %s\n", f))
}

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("✅ COMPLETE WORKFLOW TEST FINISHED SUCCESSFULLY\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat(sprintf("All results saved to: %s/\n", OUTPUT_DIR))
cat("\nRecommended configuration:\n")
cat("  - Strategy: Smoothing (continuous)\n")
cat("  - Mode: Variable (density-based)\n")
cat(sprintf("  - Window count: %d per RT bin\n", window_count_result$window_count))
cat(sprintf("  - RT bins: %d (5-minute intervals)\n", rt_binning_result$insights$n_segments))
cat(sprintf("  - Total windows: %d\n",
            window_count_result$window_count * rt_binning_result$insights$n_segments))
cat(sprintf("  - Coverage: %.1f%%\n",
            window_results[["smoothing"]][["variable"]]$insights$coverage_ratio * 100))
cat("\n")
