# =============================================================================
# Real Data Test: Generate 8 Isolation Windows for Each Parquet File
# =============================================================================
# This script processes all parquet files in the data directory and generates
# 8 optimized isolation windows for each, suitable for Thermo instruments
# =============================================================================

# Load required libraries
library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)

# Source all required modules
cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║  DIA Window Optimizer - Real Data Test (8 Windows)              ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Source modules
source("R/stage1_data_validation.R")
source("R/stage2_dppp_diagnosis.R")

# Source mock implementations for Stage 3A-3C
source("R/mock_stage3_modules.R")

# Source actual Stage 3D
source("R/stage3_window_optimization/module3d_window_generation.R")

# Configuration for 8 windows
WINDOW_COUNT <- 8
SCAN_TIME <- 0.02  # 20ms per window (typical for Orbitrap)
TARGET_DPPP <- 7.0  # Quantification-optimized

# Function to process a single parquet file
process_parquet_file <- function(file_path, output_dir = "results_8windows") {

  # Extract file info
  file_name <- basename(file_path)
  base_name <- gsub("\\.parquet$", "", file_name)

  cat(sprintf("\n═══════════════════════════════════════════════════════\n"))
  cat(sprintf(" Processing: %s\n", file_name))
  cat(sprintf("═══════════════════════════════════════════════════════\n\n"))

  # Create output directory if needed
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  tryCatch({
    # =========================================================================
    # Stage 1: Data Validation
    # =========================================================================
    cat("📊 Stage 1: Loading and validating data...\n")

    # Load parquet file
    raw_data <- arrow::read_parquet(file_path)

    # Validate data
    validated_data <- validate_diann_data(
      data = raw_data,
      check_columns = TRUE,
      remove_outliers = TRUE,
      min_fwhm = 0.1,
      max_fwhm = 100
    )

    cat(sprintf("   ✓ Loaded %d precursors\n", nrow(validated_data$data)))
    cat(sprintf("   ✓ RT range: %.1f - %.1f min\n",
                validated_data$metadata$rt_range[1],
                validated_data$metadata$rt_range[2]))
    cat(sprintf("   ✓ m/z range: %.1f - %.1f\n",
                validated_data$metadata$mz_range[1],
                validated_data$metadata$mz_range[2]))

    # =========================================================================
    # Stage 2: DPPP Diagnosis
    # =========================================================================
    cat("\n📈 Stage 2: DPPP diagnosis...\n")

    # Calculate cycle time for 8 windows
    cycle_time <- ifelse(
      grepl("astral", tolower(base_name)),
      0.1 + (WINDOW_COUNT * 0.015),  # Astral: parallel acquisition
      0.05 + (WINDOW_COUNT * SCAN_TIME)  # Orbitrap: sequential
    )

    diagnosis <- diagnose_dppp_status(
      validated_data = validated_data,
      scan_time = SCAN_TIME,
      target_dppp = TARGET_DPPP,
      instrument_type = "orbitrap"
    )

    cat(sprintf("   ✓ Current median DPPP: %.2f\n",
                diagnosis$current_state$dppp_stats$median))
    cat(sprintf("   ✓ Target DPPP: %.1f (Quant mode)\n", TARGET_DPPP))
    cat(sprintf("   ✓ Satisfaction ratio: %.1f%%\n",
                diagnosis$current_state$satisfaction_ratio * 100))

    # =========================================================================
    # Stage 3A: Window Count (Fixed at 8)
    # =========================================================================
    cat("\n🔢 Stage 3A: Window count determination...\n")

    window_count_result <- mock_determine_window_count(
      diagnosis = diagnosis,
      scan_time = SCAN_TIME,
      instrument_type = "orbitrap",
      override_count = WINDOW_COUNT  # Force 8 windows
    )

    cat(sprintf("   ✓ Window count: %d (fixed)\n", WINDOW_COUNT))
    cat(sprintf("   ✓ Cycle time: %.2f sec\n", cycle_time))

    # =========================================================================
    # Stage 3B: RT Binning
    # =========================================================================
    cat("\n⏱️ Stage 3B: RT binning...\n")

    # For 8 windows, we'll use 2-4 RT segments depending on gradient length
    rt_range <- validated_data$metadata$rt_range
    gradient_length <- rt_range[2] - rt_range[1]

    n_rt_segments <- case_when(
      gradient_length <= 35 ~ 2,  # 30min: 2 segments
      gradient_length <= 65 ~ 3,  # 60min: 3 segments
      TRUE ~ 4                     # 90min: 4 segments
    )

    rt_binning <- mock_segment_rt(
      validated_data = validated_data,
      window_count = window_count_result,
      n_segments = n_rt_segments,
      overlap = 0.1  # 10% RT overlap
    )

    cat(sprintf("   ✓ RT segments: %d\n", n_rt_segments))
    cat(sprintf("   ✓ Windows per segment: %.1f\n", WINDOW_COUNT / n_rt_segments))

    # =========================================================================
    # Stage 3C: m/z Range Optimization
    # =========================================================================
    cat("\n🎯 Stage 3C: m/z range optimization...\n")

    # Use smoothing strategy for consistent m/z ranges
    mz_optimization <- mock_optimize_mz_ranges(
      rt_binning = rt_binning,
      validated_data = validated_data,
      strategy = "smoothing",
      smoothing_method = "savgol"
    )

    cat(sprintf("   ✓ Strategy: Smoothing (Savitzky-Golay)\n"))
    cat(sprintf("   ✓ m/z ranges optimized for %d RT bins\n",
                length(unique(rt_binning$bins$bin_id))))

    # =========================================================================
    # Stage 3D: Window Generation
    # =========================================================================
    cat("\n🪟 Stage 3D: Generating isolation windows...\n")

    # Generate windows with Variable mode for better coverage
    windows <- generate_isolation_windows(
      mz_optimization = mz_optimization,
      window_count = window_count_result,
      rt_binning = rt_binning,
      validated_data = validated_data,
      window_type = "variable",  # Variable for optimal density distribution
      overlap = 0.05  # 5% m/z overlap
    )

    cat(sprintf("   ✓ Generated %d windows\n", nrow(windows$windows)))
    cat(sprintf("   ✓ Coverage: %.1f%%\n", windows$coverage_analysis$coverage_percentage))
    cat(sprintf("   ✓ Mean precursors/window: %.0f\n",
                windows$statistics$mean_precursors_per_window))

    # =========================================================================
    # Export Results
    # =========================================================================
    cat("\n💾 Exporting results...\n")

    # Export in Thermo format
    thermo_file <- file.path(output_dir, sprintf("%s_8windows_thermo.csv", base_name))
    export_windows_to_csv(
      window_result = windows,
      output_file = thermo_file,
      instrument_type = "orbitrap",
      strategy = "smoothing",
      include_metadata = TRUE,
      format = "thermo",
      agc_target = 800
    )

    # Also export in legacy format for analysis
    legacy_file <- file.path(output_dir, sprintf("%s_8windows_legacy.csv", base_name))
    export_windows_to_csv(
      window_result = windows,
      output_file = legacy_file,
      instrument_type = "orbitrap",
      strategy = "smoothing",
      include_metadata = TRUE,
      format = "legacy"
    )

    cat(sprintf("   ✓ Thermo format: %s\n", thermo_file))
    cat(sprintf("   ✓ Legacy format: %s\n", legacy_file))

    # Return results for summary
    return(list(
      file = base_name,
      n_precursors = nrow(validated_data$data),
      rt_range = validated_data$metadata$rt_range,
      mz_range = validated_data$metadata$mz_range,
      n_windows = nrow(windows$windows),
      coverage = windows$coverage_analysis$coverage_percentage,
      mean_precursors = windows$statistics$mean_precursors_per_window,
      cv_precursors = windows$statistics$cv_precursors,
      dppp_median = diagnosis$current_state$dppp_stats$median,
      satisfaction = diagnosis$current_state$satisfaction_ratio
    ))

  }, error = function(e) {
    cat(sprintf("\n❌ Error processing %s: %s\n", file_name, e$message))
    return(NULL)
  })
}

# ============================================================================
# Main Processing
# ============================================================================

# Get all parquet files
parquet_files <- list.files("data", pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("\nFound %d parquet files to process\n", length(parquet_files)))

# Process each file
results <- list()
for (file in parquet_files) {
  result <- process_parquet_file(file)
  if (!is.null(result)) {
    results[[result$file]] <- result
  }
}

# ============================================================================
# Generate Summary Report
# ============================================================================

cat("\n\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    PROCESSING SUMMARY                           ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Create summary table
summary_df <- bind_rows(results) %>%
  mutate(
    gradient = case_when(
      grepl("30min", file) ~ "30min",
      grepl("60min", file) ~ "60min",
      grepl("90min", file) ~ "90min"
    ),
    replicate = as.numeric(gsub(".*_0([1-3])", "\\1", file))
  ) %>%
  arrange(gradient, replicate)

# Print summary table
cat("File Summary:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat(sprintf("%-20s %8s %10s %8s %8s %8s\n",
            "File", "Gradient", "Precursors", "Windows", "Coverage", "DPPP"))
cat("─────────────────────────────────────────────────────────────────\n")

for (i in 1:nrow(summary_df)) {
  cat(sprintf("%-20s %8s %10d %8d %7.1f%% %8.2f\n",
              summary_df$file[i],
              summary_df$gradient[i],
              summary_df$n_precursors[i],
              summary_df$n_windows[i],
              summary_df$coverage[i],
              summary_df$dppp_median[i]))
}

cat("─────────────────────────────────────────────────────────────────\n")

# Summary statistics by gradient
cat("\n\nStatistics by Gradient Length:\n")
cat("─────────────────────────────────────────────────────────────────\n")

gradient_summary <- summary_df %>%
  group_by(gradient) %>%
  summarise(
    n_files = n(),
    avg_precursors = mean(n_precursors),
    avg_coverage = mean(coverage),
    avg_satisfaction = mean(satisfaction) * 100,
    .groups = "drop"
  )

for (i in 1:nrow(gradient_summary)) {
  cat(sprintf("%s gradient:\n", gradient_summary$gradient[i]))
  cat(sprintf("  • Files processed: %d\n", gradient_summary$n_files[i]))
  cat(sprintf("  • Avg precursors: %.0f\n", gradient_summary$avg_precursors[i]))
  cat(sprintf("  • Avg coverage: %.1f%%\n", gradient_summary$avg_coverage[i]))
  cat(sprintf("  • Avg DPPP satisfaction: %.1f%%\n", gradient_summary$avg_satisfaction[i]))
  cat("\n")
}

# Save summary to CSV
summary_file <- "results_8windows/processing_summary.csv"
write.csv(summary_df, summary_file, row.names = FALSE)
cat(sprintf("\nSummary saved to: %s\n", summary_file))

cat("\n✅ All processing complete!\n")
cat("\nResults location: results_8windows/\n")
cat("  • *_thermo.csv files: Ready for instrument import\n")
cat("  • *_legacy.csv files: For analysis and visualization\n")
cat("  • processing_summary.csv: Complete statistics\n\n")