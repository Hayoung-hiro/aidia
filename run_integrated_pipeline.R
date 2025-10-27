# =============================================================================
# Integrated DIA Window Generation Pipeline
# =============================================================================
# Integrates 3 technical replicates per gradient to create unified methods
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)

# Source required modules
source("R/stage3_window_optimization/module3d_window_generation.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Integrated DIA Window Generation Pipeline                    ║\n")
cat("║   Technical Replicates → Unified Methods per Gradient         ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Configuration
# =============================================================================

# Gradient-specific settings
GRADIENT_CONFIG <- list(
  "30min" = list(
    cycle_time = 1.2,
    max_windows = 21,      # Windows PER segment
    rt_segments = 3,
    target_dppp = 7.0,
    fwhm_median = 4.9
  ),
  "60min" = list(
    cycle_time = 1.6,
    max_windows = 30,      # Windows PER segment
    rt_segments = 4,
    target_dppp = 7.0,
    fwhm_median = 6.7
  ),
  "90min" = list(
    cycle_time = 2.0,
    max_windows = 37,      # Windows PER segment
    rt_segments = 5,
    target_dppp = 7.0,
    fwhm_median = 8.1
  )
)

# Global settings
INSTRUMENT_TYPE <- "orbitrap"
MS1_TIME <- 0.100
MS2_TIME <- 0.050
OVERLAP_PERCENT <- 0.02
AGC_TARGET <- 800

# Default strategy and mode for final methods
DEFAULT_STRATEGY <- "smoothing"  # Narrower m/z ranges, 98% coverage
DEFAULT_MODE <- "variable"       # Density-based allocation

# =============================================================================
# Functions
# =============================================================================

#' Integrate multiple technical replicates into unified dataset
integrate_replicates <- function(file_list) {

  cat(sprintf("  Integrating %d technical replicates...\n", length(file_list)))

  all_data <- list()

  for (i in seq_along(file_list)) {
    file <- file_list[i]
    data <- read_parquet(file.path("data", file))

    # Clean column names
    if ("RT" %in% names(data)) data$RT.Start <- data$RT
    if ("Precursor.mz" %in% names(data)) data$Precursor.Mz <- data$Precursor.mz
    if ("PrecursorMz" %in% names(data)) data$Precursor.Mz <- data$PrecursorMz

    # Filter valid data
    clean_data <- data %>%
      filter(!is.na(RT.Start), !is.na(Precursor.Mz)) %>%
      filter(RT.Start > 0, Precursor.Mz > 0) %>%
      mutate(replicate = i)

    all_data[[i]] <- clean_data
    cat(sprintf("    Replicate %d: %d precursors\n", i, nrow(clean_data)))
  }

  # Combine all replicates
  integrated_data <- bind_rows(all_data)

  cat(sprintf("  ✓ Integrated total: %d precursors\n", nrow(integrated_data)))
  cat(sprintf("    Unique precursors: %d\n",
              length(unique(paste(integrated_data$RT.Start, integrated_data$Precursor.Mz)))))

  return(integrated_data)
}

#' Create pipeline structures with integrated data
create_integrated_structures <- function(integrated_data, gradient_name, gradient_config) {

  # Get ranges
  rt_range <- range(integrated_data$RT.Start, na.rm = TRUE)
  mz_range <- range(integrated_data$Precursor.Mz, na.rm = TRUE)

  # Use gradient-specific configuration
  n_windows <- gradient_config$max_windows
  n_rt_segments <- gradient_config$rt_segments
  cycle_time <- gradient_config$cycle_time

  cat(sprintf("\n  Configuration for %s gradient:\n", gradient_name))
  cat(sprintf("    • Cycle time: %.1f seconds\n", cycle_time))
  cat(sprintf("    • Windows per segment: %d\n", n_windows))
  cat(sprintf("    • RT segments: %d\n", n_rt_segments))
  cat(sprintf("    • Expected total windows: %d\n", n_rt_segments * n_windows))

  # Create RT bins
  rt_breaks <- seq(rt_range[1], rt_range[2], length.out = n_rt_segments + 1)

  rt_bins <- tibble(
    bin_id = 1:n_rt_segments,
    rt_start = rt_breaks[1:n_rt_segments],
    rt_end = rt_breaks[2:(n_rt_segments + 1)],
    rt_center = (rt_breaks[1:n_rt_segments] + rt_breaks[2:(n_rt_segments + 1)]) / 2,
    rt_width = rt_breaks[2:(n_rt_segments + 1)] - rt_breaks[1:n_rt_segments]
  )

  # Assign precursors to RT bins
  integrated_data$rt_bin <- cut(integrated_data$RT.Start, breaks = rt_breaks,
                                 labels = FALSE, include.lowest = TRUE)
  integrated_data <- integrated_data %>% filter(!is.na(rt_bin))

  # Calculate m/z ranges using DEFAULT_STRATEGY
  if (DEFAULT_STRATEGY == "smoothing") {
    mz_stats <- integrated_data %>%
      group_by(rt_bin) %>%
      summarise(
        mz_min = quantile(Precursor.Mz, 0.01, na.rm = TRUE),
        mz_max = quantile(Precursor.Mz, 0.99, na.rm = TRUE),
        n_precursors = n(),
        n_replicates = n_distinct(replicate),
        .groups = "drop"
      )
  } else if (DEFAULT_STRATEGY == "outlier") {
    mz_stats <- integrated_data %>%
      group_by(rt_bin) %>%
      summarise(
        q1 = quantile(Precursor.Mz, 0.25, na.rm = TRUE),
        q3 = quantile(Precursor.Mz, 0.75, na.rm = TRUE),
        iqr = q3 - q1,
        mz_min = max(min(Precursor.Mz, na.rm = TRUE), q1 - 1.5 * iqr),
        mz_max = min(max(Precursor.Mz, na.rm = TRUE), q3 + 1.5 * iqr),
        n_precursors = n(),
        n_replicates = n_distinct(replicate),
        .groups = "drop"
      ) %>%
      select(rt_bin, mz_min, mz_max, n_precursors, n_replicates)
  } else if (DEFAULT_STRATEGY == "quantile") {
    mz_stats <- integrated_data %>%
      group_by(rt_bin) %>%
      summarise(
        mz_min = quantile(Precursor.Mz, 0.001, na.rm = TRUE),
        mz_max = quantile(Precursor.Mz, 0.999, na.rm = TRUE),
        n_precursors = n(),
        n_replicates = n_distinct(replicate),
        .groups = "drop"
      )
  } else if (DEFAULT_STRATEGY == "coverage") {
    mz_stats <- integrated_data %>%
      group_by(rt_bin) %>%
      summarise(
        mz_min = min(Precursor.Mz, na.rm = TRUE),
        mz_max = max(Precursor.Mz, na.rm = TRUE),
        n_precursors = n(),
        n_replicates = n_distinct(replicate),
        .groups = "drop"
      )
  }

  mz_stats <- mz_stats %>%
    mutate(
      bin_id = rt_bin,
      mz_center = (mz_min + mz_max) / 2,
      mz_range = mz_max - mz_min
    ) %>%
    select(bin_id, mz_min, mz_max, mz_center, mz_range, n_precursors, n_replicates)

  # Print m/z ranges
  cat(sprintf("\n  m/z Ranges (%s strategy):\n", DEFAULT_STRATEGY))
  for (i in 1:nrow(mz_stats)) {
    cat(sprintf("    Segment %d: %.1f - %.1f Da (range: %.1f Da, n=%d, reps=%d)\n",
                mz_stats$bin_id[i], mz_stats$mz_min[i], mz_stats$mz_max[i],
                mz_stats$mz_range[i], mz_stats$n_precursors[i], mz_stats$n_replicates[i]))
  }

  # Create validated_data structure
  validated_data <- list(
    data = integrated_data,
    metadata = list(
      n_precursors = nrow(integrated_data),
      n_unique_precursors = length(unique(paste(integrated_data$RT.Start, integrated_data$Precursor.Mz))),
      rt_range = rt_range,
      mz_range = mz_range,
      cycle_time = cycle_time,
      target_dppp = gradient_config$target_dppp
    )
  )

  rt_binning <- list(
    bins = rt_bins,
    metadata = list(
      n_segments = n_rt_segments,
      method = "time_based_integrated"
    )
  )

  mz_ranges <- list(
    mz_ranges = mz_stats,
    strategy = DEFAULT_STRATEGY
  )

  return(list(
    validated_data = validated_data,
    rt_binning = rt_binning,
    mz_ranges = mz_ranges,
    gradient_config = gradient_config,
    gradient_name = gradient_name
  ))
}

#' Generate windows for integrated data
generate_integrated_windows <- function(structures) {

  # Prepare window config
  window_config <- list(
    window_mode = DEFAULT_MODE,
    total_windows = structures$gradient_config$max_windows,
    per_bin_mode = TRUE,  # Per-bin architecture
    min_width_da = 10,
    max_width_da = 80,
    overlap = OVERLAP_PERCENT
  )

  cat(sprintf("\n  Generating windows (%s mode)...\n", DEFAULT_MODE))

  # Generate windows
  windows_result <- generate_isolation_windows(
    validated_data = structures$validated_data,
    rt_binning = structures$rt_binning,
    mz_ranges = structures$mz_ranges,
    window_config = window_config
  )

  return(windows_result)
}

# =============================================================================
# Main Processing
# =============================================================================

# Create output directory
output_dir <- "results_integrated"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Get all parquet files
parquet_files <- list.files("data", pattern = "\\.parquet$", full.names = FALSE)

# Group files by gradient type
files_by_gradient <- list(
  "30min" = parquet_files[grepl("30min", parquet_files)],
  "60min" = parquet_files[grepl("60min", parquet_files)],
  "90min" = parquet_files[grepl("90min", parquet_files)]
)

cat(sprintf("Found parquet files:\n"))
for (gradient in names(files_by_gradient)) {
  cat(sprintf("  %s: %d replicates\n", gradient, length(files_by_gradient[[gradient]])))
}
cat("\n")

# Results storage
all_results <- list()

# Process each gradient
for (gradient_name in names(files_by_gradient)) {

  cat("\n═══════════════════════════════════════════════════════════════\n")
  cat(sprintf("Processing: %s Gradient\n", toupper(gradient_name)))
  cat("═══════════════════════════════════════════════════════════════\n")

  file_list <- files_by_gradient[[gradient_name]]
  gradient_config <- GRADIENT_CONFIG[[gradient_name]]

  if (length(file_list) == 0) {
    cat(sprintf("  ⚠️  No files found for %s gradient, skipping...\n", gradient_name))
    next
  }

  # Integrate replicates
  integrated_data <- integrate_replicates(file_list)

  # Create structures
  structures <- create_integrated_structures(integrated_data, gradient_name, gradient_config)

  # Generate windows
  windows_result <- generate_integrated_windows(structures)

  # Calculate statistics
  windows_df <- windows_result$windows
  expected_total <- gradient_config$rt_segments * gradient_config$max_windows
  actual_total <- nrow(windows_df)
  deviation_pct <- (actual_total - expected_total) / expected_total * 100

  cat(sprintf("\n  📊 Results Summary:\n"))
  cat(sprintf("    • Expected windows: %d\n", expected_total))
  cat(sprintf("    • Actual windows: %d\n", actual_total))
  cat(sprintf("    • Deviation: %.1f%%\n", deviation_pct))
  cat(sprintf("    • Mean window width: %.1f Da\n", mean(windows_df$window_width)))
  cat(sprintf("    • Coverage: %.1f%%\n", windows_result$coverage_analysis$coverage_percentage))

  # Windows per segment
  windows_per_segment <- windows_df %>%
    group_by(rt_segment_id) %>%
    summarise(
      n_windows = n(),
      mean_width = mean(window_width),
      min_width = min(window_width),
      max_width = max(window_width),
      .groups = "drop"
    )

  cat(sprintf("\n  Windows per RT segment:\n"))
  for (i in 1:nrow(windows_per_segment)) {
    cat(sprintf("    Segment %d: %d windows (width: %.1f ± %.1f Da)\n",
                i, windows_per_segment$n_windows[i],
                windows_per_segment$mean_width[i],
                sd(windows_df$window_width[windows_df$rt_segment_id == i])))
  }

  # Export to CSV (both formats)
  method_name <- sprintf("%s_integrated", gradient_name)

  thermo_file <- file.path(output_dir, sprintf("%s_%s_%s_thermo.csv",
                                                method_name, DEFAULT_STRATEGY, DEFAULT_MODE))
  legacy_file <- file.path(output_dir, sprintf("%s_%s_%s_legacy.csv",
                                                method_name, DEFAULT_STRATEGY, DEFAULT_MODE))

  export_windows_to_csv(
    window_result = windows_result,
    output_file = thermo_file,
    instrument_type = INSTRUMENT_TYPE,
    strategy = DEFAULT_STRATEGY,
    include_metadata = TRUE,
    format = "thermo",
    agc_target = AGC_TARGET
  )

  export_windows_to_csv(
    window_result = windows_result,
    output_file = legacy_file,
    instrument_type = INSTRUMENT_TYPE,
    strategy = DEFAULT_STRATEGY,
    include_metadata = TRUE,
    format = "legacy",
    agc_target = AGC_TARGET
  )

  cat(sprintf("\n  ✅ Exported methods:\n"))
  cat(sprintf("    • %s\n", basename(thermo_file)))
  cat(sprintf("    • %s\n", basename(legacy_file)))

  # Store results
  all_results[[gradient_name]] <- list(
    gradient = gradient_name,
    n_replicates = length(file_list),
    n_total_precursors = nrow(integrated_data),
    n_unique_precursors = structures$validated_data$metadata$n_unique_precursors,
    rt_segments = gradient_config$rt_segments,
    windows_per_segment = gradient_config$max_windows,
    expected_total = expected_total,
    actual_total = actual_total,
    deviation_pct = deviation_pct,
    mean_width = mean(windows_df$window_width),
    coverage_pct = windows_result$coverage_analysis$coverage_percentage,
    windows_per_segment_detail = windows_per_segment
  )
}

# =============================================================================
# Generate Summary Report
# =============================================================================

cat("\n\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                  INTEGRATED METHODS SUMMARY                     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Create summary table
summary_rows <- list()
for (gradient_name in names(all_results)) {
  result <- all_results[[gradient_name]]

  summary_rows[[length(summary_rows) + 1]] <- data.frame(
    Gradient = gradient_name,
    Replicates = result$n_replicates,
    Total_Precursors = result$n_total_precursors,
    Unique_Precursors = result$n_unique_precursors,
    RT_Segments = result$rt_segments,
    Windows_Per_Segment = result$windows_per_segment,
    Expected_Total = result$expected_total,
    Actual_Total = result$actual_total,
    Deviation_Pct = sprintf("%.1f%%", result$deviation_pct),
    Mean_Width_Da = sprintf("%.1f", result$mean_width),
    Coverage_Pct = sprintf("%.1f%%", result$coverage_pct),
    Strategy = DEFAULT_STRATEGY,
    Mode = DEFAULT_MODE,
    stringsAsFactors = FALSE
  )
}

summary_df <- bind_rows(summary_rows)

cat("Integration Summary:\n")
cat("═══════════════════════════════════════════════════════════════\n")
print(summary_df, row.names = FALSE)
cat("\n")

# Save summary to CSV
summary_file <- file.path(output_dir, "integrated_methods_summary.csv")
write.csv(summary_df, summary_file, row.names = FALSE)
cat(sprintf("✅ Summary saved to: %s\n\n", summary_file))

cat("═══════════════════════════════════════════════════════════════\n")
cat("✅ INTEGRATED PIPELINE COMPLETE!\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat(sprintf("  Methods generated: %d\n", length(all_results)))
cat(sprintf("  Strategy: %s\n", DEFAULT_STRATEGY))
cat(sprintf("  Mode: %s\n", DEFAULT_MODE))
cat(sprintf("  Output directory: %s/\n\n", output_dir))

cat("📁 Generated method files:\n")
for (gradient_name in names(all_results)) {
  method_name <- sprintf("%s_integrated", gradient_name)
  cat(sprintf("  • %s_%s_%s_thermo.csv\n", method_name, DEFAULT_STRATEGY, DEFAULT_MODE))
  cat(sprintf("  • %s_%s_%s_legacy.csv\n", method_name, DEFAULT_STRATEGY, DEFAULT_MODE))
}
cat("\n")
