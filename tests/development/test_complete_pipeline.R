# =============================================================================
# Complete Pipeline Test with Real Data
# =============================================================================
# This script processes each parquet file through the complete pipeline
# and saves results in separate folders for each dataset
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)

# Source required modules
source("R/stage3_window_optimization/module3d_window_generation.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║  DIA Window Optimizer - Complete Pipeline Test                  ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# USER CONFIGURATION - PLEASE MODIFY THESE PARAMETERS
# =============================================================================

# Instrument Configuration
INSTRUMENT_TYPE <- "orbitrap"    # "astral", "exploris", "orbitrap", "timstof"
MS1_TIME <- 0.05                 # seconds
MS2_TIME <- 0.02                 # seconds per window

# DPPP Target Settings
TARGET_DPPP <- 7.0               # 7.0 for Quant, 1.5 for ID, 4.0 for Balanced
DPPP_TOLERANCE <- 0.5            # ± tolerance
SATISFACTION_TARGET <- 0.85      # 85% of precursors should meet target

# Window Generation Parameters
WINDOW_COUNTS <- list(
  "30min" = 40,                   # Windows for 30min gradient
  "60min" = 60,                   # Windows for 60min gradient
  "90min" = 80                    # Windows for 90min gradient
)
WINDOW_MODE <- "variable"        # "fixed" or "variable"
OVERLAP_PERCENT <- 0.05          # 5% overlap
MIN_WIDTH <- 2                   # Minimum window width (Da)
MAX_WIDTH <- 80                  # Maximum window width (Da)

# RT Segmentation Strategy
RT_SEGMENTS <- list(
  "30min" = 3,                    # 3 RT segments for 30min
  "60min" = 4,                    # 4 RT segments for 60min
  "90min" = 5                     # 5 RT segments for 90min
)
RT_OVERLAP <- 0.5                # 0.5 min overlap between RT segments

# m/z Range Optimization
MZ_STRATEGY <- "smoothing"       # "quantile", "smoothing", "coverage", "outlier"

# AGC Target
AGC_TARGET <- 800                # Normalized AGC Target (%)

# Output Configuration
BASE_OUTPUT_DIR <- "results_complete_pipeline"

# =============================================================================
# Pipeline Functions
# =============================================================================

# Function to create mock structures from real data
create_pipeline_structures <- function(data, gradient_type, config) {

  # Basic validation and cleaning
  required_cols <- c("RT.Start", "Precursor.Mz")
  if (!all(required_cols %in% names(data))) {
    # Try alternative column names
    if ("RT" %in% names(data)) data$RT.Start <- data$RT
    if ("Precursor.mz" %in% names(data)) data$Precursor.Mz <- data$Precursor.mz
    if ("PrecursorMz" %in% names(data)) data$Precursor.Mz <- data$PrecursorMz
  }

  # Filter valid data
  clean_data <- data %>%
    filter(!is.na(RT.Start), !is.na(Precursor.Mz)) %>%
    filter(RT.Start > 0, Precursor.Mz > 0)

  # Get ranges
  rt_range <- range(clean_data$RT.Start, na.rm = TRUE)
  mz_range <- range(clean_data$Precursor.Mz, na.rm = TRUE)

  # Get configuration for this gradient
  n_windows <- config$window_counts[[gradient_type]]
  n_rt_segments <- config$rt_segments[[gradient_type]]

  # Create RT bins
  rt_breaks <- seq(rt_range[1], rt_range[2], length.out = n_rt_segments + 1)

  # Add overlap
  if (config$rt_overlap > 0 && n_rt_segments > 1) {
    for (i in 2:n_rt_segments) {
      rt_breaks[i] <- rt_breaks[i] - config$rt_overlap/2
    }
  }

  rt_bins <- tibble(
    bin_id = 1:n_rt_segments,
    rt_start = rt_breaks[1:n_rt_segments],
    rt_end = rt_breaks[2:(n_rt_segments + 1)],
    rt_center = (rt_breaks[1:n_rt_segments] + rt_breaks[2:(n_rt_segments + 1)]) / 2,
    rt_width = rt_breaks[2:(n_rt_segments + 1)] - rt_breaks[1:n_rt_segments]
  )

  # Calculate m/z statistics per RT bin
  clean_data$rt_bin <- cut(clean_data$RT.Start, breaks = rt_breaks,
                           labels = FALSE, include.lowest = TRUE)

  # Handle NA values from cut
  clean_data <- clean_data %>%
    filter(!is.na(rt_bin))

  mz_stats <- clean_data %>%
    group_by(rt_bin) %>%
    summarise(
      mz_min = quantile(Precursor.Mz, 0.01, na.rm = TRUE),
      mz_max = quantile(Precursor.Mz, 0.99, na.rm = TRUE),
      n_precursors = n(),
      .groups = "drop"
    ) %>%
    mutate(
      mz_center = (mz_min + mz_max) / 2,
      mz_range = mz_max - mz_min
    )

  # Join RT bins with m/z stats
  rt_bins <- rt_bins %>%
    left_join(mz_stats, by = c("bin_id" = "rt_bin"))

  # Fill any missing m/z values
  rt_bins$mz_min[is.na(rt_bins$mz_min)] <- mz_range[1]
  rt_bins$mz_max[is.na(rt_bins$mz_max)] <- mz_range[2]
  rt_bins$n_precursors[is.na(rt_bins$n_precursors)] <- 0

  # Apply smoothing if requested
  if (config$mz_strategy == "smoothing" && nrow(rt_bins) > 2) {
    # Simple moving average smoothing
    window_size <- min(3, nrow(rt_bins))
    rt_bins$mz_min_smooth <- stats::filter(rt_bins$mz_min,
                                           rep(1/window_size, window_size),
                                           sides = 2)
    rt_bins$mz_max_smooth <- stats::filter(rt_bins$mz_max,
                                           rep(1/window_size, window_size),
                                           sides = 2)
    # Fill NAs from filter edges
    rt_bins$mz_min_smooth[is.na(rt_bins$mz_min_smooth)] <- rt_bins$mz_min[is.na(rt_bins$mz_min_smooth)]
    rt_bins$mz_max_smooth[is.na(rt_bins$mz_max_smooth)] <- rt_bins$mz_max[is.na(rt_bins$mz_max_smooth)]

    rt_bins$mz_min <- rt_bins$mz_min_smooth
    rt_bins$mz_max <- rt_bins$mz_max_smooth
  }

  # Create structures for Stage 3D
  validated_data <- list(
    data = clean_data,
    metadata = list(
      n_precursors = nrow(clean_data),
      rt_range = rt_range,
      mz_range = mz_range,
      gradient_type = gradient_type
    )
  )

  rt_binning <- list(
    bins = rt_bins,
    metadata = list(
      n_segments = n_rt_segments,
      method = "time_based",
      overlap = config$rt_overlap
    )
  )

  mz_boundaries <- rt_bins %>%
    select(bin_id, mz_min, mz_max, mz_range)

  mz_ranges <- list(
    mz_ranges = mz_boundaries,
    strategy = config$mz_strategy
  )

  window_config <- list(
    window_mode = config$window_mode,
    total_windows = n_windows,
    min_width_da = config$min_width,
    max_width_da = config$max_width,
    overlap = config$overlap_percent
  )

  return(list(
    validated_data = validated_data,
    rt_binning = rt_binning,
    mz_ranges = mz_ranges,
    window_config = window_config
  ))
}

# Process single file
process_single_file <- function(file_path, config) {

  file_name <- basename(file_path)
  base_name <- gsub("\\.parquet$", "", file_name)

  # Determine gradient type
  gradient_type <- case_when(
    grepl("30min", base_name) ~ "30min",
    grepl("60min", base_name) ~ "60min",
    grepl("90min", base_name) ~ "90min",
    TRUE ~ "60min"  # Default
  )

  # Create output directory for this dataset
  output_dir <- file.path(config$base_output_dir, base_name)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  cat(sprintf("\n═══════════════════════════════════════════\n"))
  cat(sprintf("Processing: %s\n", file_name))
  cat(sprintf("Output directory: %s\n", output_dir))
  cat(sprintf("═══════════════════════════════════════════\n"))

  tryCatch({
    # Load data
    data <- arrow::read_parquet(file_path)
    cat(sprintf("  Loaded %d rows\n", nrow(data)))

    # Create pipeline structures
    pipeline_data <- create_pipeline_structures(data, gradient_type, config)

    cat(sprintf("  RT range: %.1f - %.1f min\n",
                pipeline_data$validated_data$metadata$rt_range[1],
                pipeline_data$validated_data$metadata$rt_range[2]))
    cat(sprintf("  m/z range: %.0f - %.0f\n",
                pipeline_data$validated_data$metadata$mz_range[1],
                pipeline_data$validated_data$metadata$mz_range[2]))
    cat(sprintf("  Configuration: %d windows in %d RT segments\n",
                pipeline_data$window_config$total_windows,
                nrow(pipeline_data$rt_binning$bins)))

    # Generate windows using Stage 3D
    windows <- generate_isolation_windows(
      validated_data = pipeline_data$validated_data,
      rt_binning = pipeline_data$rt_binning,
      mz_ranges = pipeline_data$mz_ranges,
      window_config = pipeline_data$window_config
    )

    # Export results in both formats
    thermo_file <- file.path(output_dir, sprintf("%s_windows_thermo.csv", base_name))
    legacy_file <- file.path(output_dir, sprintf("%s_windows_legacy.csv", base_name))

    # Thermo format
    export_windows_to_csv(
      window_result = windows,
      output_file = thermo_file,
      instrument_type = config$instrument_type,
      strategy = config$mz_strategy,
      include_metadata = TRUE,
      format = "thermo",
      agc_target = config$agc_target
    )

    # Legacy format
    export_windows_to_csv(
      window_result = windows,
      output_file = legacy_file,
      instrument_type = config$instrument_type,
      strategy = config$mz_strategy,
      include_metadata = TRUE,
      format = "legacy"
    )

    # Save configuration used
    config_file <- file.path(output_dir, "configuration.txt")
    writeLines(c(
      "DIA Window Optimization Configuration",
      "=====================================",
      sprintf("Date: %s", Sys.Date()),
      sprintf("File: %s", file_name),
      sprintf("Gradient: %s", gradient_type),
      "",
      "Instrument Settings:",
      sprintf("  Type: %s", config$instrument_type),
      sprintf("  MS1 time: %.3f sec", config$ms1_time),
      sprintf("  MS2 time: %.3f sec", config$ms2_time),
      "",
      "DPPP Settings:",
      sprintf("  Target: %.1f", config$target_dppp),
      sprintf("  Tolerance: ±%.1f", config$dppp_tolerance),
      sprintf("  Satisfaction target: %.0f%%", config$satisfaction_target * 100),
      "",
      "Window Generation:",
      sprintf("  Total windows: %d", pipeline_data$window_config$total_windows),
      sprintf("  Mode: %s", config$window_mode),
      sprintf("  Overlap: %.0f%%", config$overlap_percent * 100),
      sprintf("  Width range: %.0f-%.0f Da", config$min_width, config$max_width),
      "",
      "RT Segmentation:",
      sprintf("  Segments: %d", nrow(pipeline_data$rt_binning$bins)),
      sprintf("  Overlap: %.1f min", config$rt_overlap),
      "",
      "m/z Optimization:",
      sprintf("  Strategy: %s", config$mz_strategy),
      "",
      "Results:",
      sprintf("  Windows generated: %d", nrow(windows$windows)),
      sprintf("  Coverage: %.1f%%", windows$coverage_analysis$coverage_percentage),
      sprintf("  Mean width: %.1f Da", mean(windows$windows$window_width)),
      sprintf("  Precursors/window: %.0f", windows$statistics$mean_precursors_per_window)
    ), config_file)

    cat(sprintf("  ✓ Configuration saved\n"))

    # Return summary
    return(list(
      file = base_name,
      gradient = gradient_type,
      n_precursors = nrow(pipeline_data$validated_data$data),
      n_windows_target = pipeline_data$window_config$total_windows,
      n_windows_actual = nrow(windows$windows),
      coverage = windows$coverage_analysis$coverage_percentage,
      mean_width = mean(windows$windows$window_width),
      output_dir = output_dir
    ))

  }, error = function(e) {
    cat(sprintf("  ❌ Error: %s\n", e$message))
    return(NULL)
  })
}

# =============================================================================
# Main Processing
# =============================================================================

# Create configuration object
config <- list(
  instrument_type = INSTRUMENT_TYPE,
  ms1_time = MS1_TIME,
  ms2_time = MS2_TIME,
  target_dppp = TARGET_DPPP,
  dppp_tolerance = DPPP_TOLERANCE,
  satisfaction_target = SATISFACTION_TARGET,
  window_counts = WINDOW_COUNTS,
  window_mode = WINDOW_MODE,
  overlap_percent = OVERLAP_PERCENT,
  min_width = MIN_WIDTH,
  max_width = MAX_WIDTH,
  rt_segments = RT_SEGMENTS,
  rt_overlap = RT_OVERLAP,
  mz_strategy = MZ_STRATEGY,
  agc_target = AGC_TARGET,
  base_output_dir = BASE_OUTPUT_DIR
)

# Get all parquet files
parquet_files <- list.files("data", pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("\nFound %d parquet files to process\n", length(parquet_files)))

# Process each file
results <- list()
for (file in parquet_files) {
  result <- process_single_file(file, config)
  if (!is.null(result)) {
    results[[result$file]] <- result
  }
}

# =============================================================================
# Generate Summary Report
# =============================================================================

if (length(results) > 0) {

  cat("\n\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║                    PROCESSING SUMMARY                           ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  summary_df <- bind_rows(results)

  # Print summary table
  cat("Results by File:\n")
  cat("─────────────────────────────────────────────────────────────────────\n")
  cat(sprintf("%-25s %8s %10s %8s/%8s %8s %10s\n",
              "File", "Gradient", "Precursors", "Target", "Actual", "Coverage", "Mean Width"))
  cat("─────────────────────────────────────────────────────────────────────\n")

  for (i in 1:nrow(summary_df)) {
    cat(sprintf("%-25s %8s %10d %8d/%8d %7.1f%% %9.1f Da\n",
                summary_df$file[i],
                summary_df$gradient[i],
                summary_df$n_precursors[i],
                summary_df$n_windows_target[i],
                summary_df$n_windows_actual[i],
                summary_df$coverage[i],
                summary_df$mean_width[i]))
  }

  # Summary by gradient
  cat("\n\nSummary by Gradient:\n")
  cat("─────────────────────────────────────────────────────────────────────\n")

  gradient_summary <- summary_df %>%
    group_by(gradient) %>%
    summarise(
      n_files = n(),
      avg_precursors = mean(n_precursors),
      avg_coverage = mean(coverage),
      avg_width = mean(mean_width),
      .groups = "drop"
    )

  for (i in 1:nrow(gradient_summary)) {
    cat(sprintf("%s gradient:\n", gradient_summary$gradient[i]))
    cat(sprintf("  Files: %d\n", gradient_summary$n_files[i]))
    cat(sprintf("  Avg precursors: %.0f\n", gradient_summary$avg_precursors[i]))
    cat(sprintf("  Avg coverage: %.1f%%\n", gradient_summary$avg_coverage[i]))
    cat(sprintf("  Avg window width: %.1f Da\n", gradient_summary$avg_width[i]))
    cat("\n")
  }

  # Save overall summary
  summary_file <- file.path(BASE_OUTPUT_DIR, "overall_summary.csv")
  write.csv(summary_df, summary_file, row.names = FALSE)
  cat(sprintf("Overall summary saved to: %s\n", summary_file))

  cat("\n✅ All processing complete!\n")
  cat(sprintf("\nResults saved in: %s/\n", BASE_OUTPUT_DIR))
  cat("Each dataset has its own folder containing:\n")
  cat("  • *_windows_thermo.csv - Thermo Fusion Lumos format\n")
  cat("  • *_windows_legacy.csv - Legacy analysis format\n")
  cat("  • configuration.txt - Settings used for this dataset\n")

} else {
  cat("\n❌ No files were successfully processed.\n")
}