# =============================================================================
# Complete Pipeline Test with User Specifications
# =============================================================================
# Processes each dataset with all 4 m/z strategies in separate folders
# User specs: Orbitrap, 100ms MS1, 50ms MS2, DPPP 7.0, 70% satisfaction,
#            5min RT segments, no overlap
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)

# Source required modules
source("R/stage3_window_optimization/module3d_window_generation.R")

# Load user configuration
source("user_config_custom.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║  DIA Window Optimizer - Complete Test (User Specifications)     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Configuration Summary:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat(sprintf("  Instrument:        %s\n", INSTRUMENT_TYPE))
cat(sprintf("  MS1/MS2 time:      %.0fms / %.0fms\n", MS1_TIME*1000, MS2_TIME*1000))
cat(sprintf("  Target DPPP:       %.1f (%.0f%% satisfaction)\n", TARGET_DPPP, SATISFACTION_TARGET*100))
cat(sprintf("  RT segments:       5 minutes each\n"))
cat(sprintf("  Window overlap:    None\n"))
cat(sprintf("  m/z strategies:    All 4 (quantile, smoothing, coverage, outlier)\n"))
cat("─────────────────────────────────────────────────────────────────\n\n")

# Function to calculate actual RT segments based on 5-minute intervals
calculate_rt_segments <- function(rt_range) {
  gradient_length <- rt_range[2] - rt_range[1]
  # 5분 단위로 segment 수 계산
  n_segments <- ceiling(gradient_length / 5)
  return(n_segments)
}

# Function to create pipeline structures
create_pipeline_structures <- function(data, gradient_type, strategy, config) {

  # Clean column names
  if ("RT" %in% names(data)) data$RT.Start <- data$RT
  if ("Precursor.mz" %in% names(data)) data$Precursor.Mz <- data$Precursor.mz
  if ("PrecursorMz" %in% names(data)) data$Precursor.Mz <- data$PrecursorMz

  # Filter valid data
  clean_data <- data %>%
    filter(!is.na(RT.Start), !is.na(Precursor.Mz)) %>%
    filter(RT.Start > 0, Precursor.Mz > 0)

  # Get ranges
  rt_range <- range(clean_data$RT.Start, na.rm = TRUE)
  mz_range <- range(clean_data$Precursor.Mz, na.rm = TRUE)

  # Calculate RT segments (5분 단위)
  n_rt_segments <- calculate_rt_segments(rt_range)

  # Calculate appropriate window count
  # 각 RT segment당 약 6-8개 window
  n_windows <- n_rt_segments * 6

  cat(sprintf("    RT range: %.1f-%.1f min → %d segments (5min each) → %d windows\n",
              rt_range[1], rt_range[2], n_rt_segments, n_windows))

  # Create RT bins (5분 간격, overlap 없음)
  rt_breaks <- seq(rt_range[1], rt_range[2], by = 5)
  if (length(rt_breaks) < n_rt_segments + 1) {
    rt_breaks <- c(rt_breaks, rt_range[2])
  }
  rt_breaks <- rt_breaks[1:(n_rt_segments + 1)]

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
  clean_data <- clean_data %>% filter(!is.na(rt_bin))

  # Apply different strategies for m/z range
  mz_stats <- clean_data %>%
    group_by(rt_bin) %>%
    summarise(
      # Quantile strategy
      mz_min_quantile = quantile(Precursor.Mz, 0.01, na.rm = TRUE),
      mz_max_quantile = quantile(Precursor.Mz, 0.99, na.rm = TRUE),

      # Coverage strategy (wider range)
      mz_min_coverage = quantile(Precursor.Mz, 0.001, na.rm = TRUE),
      mz_max_coverage = quantile(Precursor.Mz, 0.999, na.rm = TRUE),

      # Outlier removal strategy
      q1 = quantile(Precursor.Mz, 0.25, na.rm = TRUE),
      q3 = quantile(Precursor.Mz, 0.75, na.rm = TRUE),
      iqr = q3 - q1,
      mz_min_outlier = max(min(Precursor.Mz, na.rm = TRUE), q1 - 1.5 * iqr),
      mz_max_outlier = min(max(Precursor.Mz, na.rm = TRUE), q3 + 1.5 * iqr),

      n_precursors = n(),
      .groups = "drop"
    )

  # Join RT bins with m/z stats
  rt_bins <- rt_bins %>%
    left_join(mz_stats, by = c("bin_id" = "rt_bin"))

  # Select m/z range based on strategy
  if (strategy == "quantile") {
    rt_bins$mz_min <- rt_bins$mz_min_quantile
    rt_bins$mz_max <- rt_bins$mz_max_quantile
  } else if (strategy == "coverage") {
    rt_bins$mz_min <- rt_bins$mz_min_coverage
    rt_bins$mz_max <- rt_bins$mz_max_coverage
  } else if (strategy == "outlier") {
    rt_bins$mz_min <- rt_bins$mz_min_outlier
    rt_bins$mz_max <- rt_bins$mz_max_outlier
  } else if (strategy == "smoothing") {
    # Use quantile as base, then apply smoothing
    rt_bins$mz_min <- rt_bins$mz_min_quantile
    rt_bins$mz_max <- rt_bins$mz_max_quantile

    if (nrow(rt_bins) > 2) {
      # Apply moving average smoothing
      window_size <- min(3, nrow(rt_bins))
      rt_bins$mz_min <- as.numeric(stats::filter(rt_bins$mz_min,
                                                  rep(1/window_size, window_size),
                                                  sides = 2))
      rt_bins$mz_max <- as.numeric(stats::filter(rt_bins$mz_max,
                                                  rep(1/window_size, window_size),
                                                  sides = 2))
      # Fill NAs at edges
      rt_bins$mz_min[is.na(rt_bins$mz_min)] <- rt_bins$mz_min_quantile[is.na(rt_bins$mz_min)]
      rt_bins$mz_max[is.na(rt_bins$mz_max)] <- rt_bins$mz_max_quantile[is.na(rt_bins$mz_max)]
    }
  }

  # Fill any missing values
  rt_bins$mz_min[is.na(rt_bins$mz_min)] <- mz_range[1]
  rt_bins$mz_max[is.na(rt_bins$mz_max)] <- mz_range[2]
  rt_bins$n_precursors[is.na(rt_bins$n_precursors)] <- 0

  # Calculate m/z range
  rt_bins$mz_range <- rt_bins$mz_max - rt_bins$mz_min

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
    bins = rt_bins %>%
      select(bin_id, rt_start, rt_end, rt_center, rt_width,
             mz_min, mz_max, mz_range, n_precursors),
    metadata = list(
      n_segments = n_rt_segments,
      method = "5min_fixed",
      overlap = 0
    )
  )

  mz_boundaries <- rt_bins %>%
    select(bin_id, mz_min, mz_max, mz_range)

  mz_ranges <- list(
    mz_ranges = mz_boundaries,
    strategy = strategy
  )

  window_config <- list(
    window_mode = config$window_mode,
    total_windows = n_windows,
    min_width_da = config$min_width,
    max_width_da = config$max_width,
    overlap = 0  # No overlap
  )

  return(list(
    validated_data = validated_data,
    rt_binning = rt_binning,
    mz_ranges = mz_ranges,
    window_config = window_config
  ))
}

# Process single file with single strategy
process_file_strategy <- function(file_path, strategy, config) {

  file_name <- basename(file_path)
  base_name <- gsub("\\.parquet$", "", file_name)

  # Determine gradient type
  gradient_type <- case_when(
    grepl("30min", base_name) ~ "30min",
    grepl("60min", base_name) ~ "60min",
    grepl("90min", base_name) ~ "90min",
    TRUE ~ "60min"
  )

  # Create output directory for this dataset and strategy
  output_dir <- file.path(config$base_output_dir, base_name, strategy)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  cat(sprintf("  Strategy: %s\n", strategy))

  tryCatch({
    # Load data
    data <- arrow::read_parquet(file_path)

    # Create pipeline structures
    pipeline_data <- create_pipeline_structures(data, gradient_type, strategy, config)

    # Generate windows using Stage 3D
    windows <- generate_isolation_windows(
      validated_data = pipeline_data$validated_data,
      rt_binning = pipeline_data$rt_binning,
      mz_ranges = pipeline_data$mz_ranges,
      window_config = pipeline_data$window_config
    )

    # Export results
    thermo_file <- file.path(output_dir, sprintf("%s_%s_thermo.csv", base_name, strategy))
    legacy_file <- file.path(output_dir, sprintf("%s_%s_legacy.csv", base_name, strategy))

    # Thermo format
    export_windows_to_csv(
      window_result = windows,
      output_file = thermo_file,
      instrument_type = config$instrument_type,
      strategy = strategy,
      include_metadata = TRUE,
      format = "thermo",
      agc_target = config$agc_target
    )

    # Legacy format
    export_windows_to_csv(
      window_result = windows,
      output_file = legacy_file,
      instrument_type = config$instrument_type,
      strategy = strategy,
      include_metadata = TRUE,
      format = "legacy"
    )

    # Save configuration
    config_file <- file.path(output_dir, "config.txt")
    writeLines(c(
      sprintf("Dataset: %s", base_name),
      sprintf("Strategy: %s", strategy),
      sprintf("Date: %s", Sys.Date()),
      "",
      "Parameters:",
      sprintf("  Instrument: %s", config$instrument_type),
      sprintf("  MS1/MS2: %.0f/%.0f ms", config$ms1_time*1000, config$ms2_time*1000),
      sprintf("  Target DPPP: %.1f", config$target_dppp),
      sprintf("  Satisfaction: %.0f%%", config$satisfaction_target * 100),
      sprintf("  Window mode: %s", config$window_mode),
      sprintf("  Overlap: %.0f%%", config$overlap_percent * 100),
      "",
      "Results:",
      sprintf("  Windows: %d", nrow(windows$windows)),
      sprintf("  Coverage: %.1f%%", windows$coverage_analysis$coverage_percentage),
      sprintf("  Mean width: %.1f Da", mean(windows$windows$window_width)),
      sprintf("  RT segments: %d", nrow(pipeline_data$rt_binning$bins))
    ), config_file)

    cat(sprintf("    ✓ Generated %d windows, %.1f%% coverage\n",
                nrow(windows$windows),
                windows$coverage_analysis$coverage_percentage))

    return(list(
      file = base_name,
      strategy = strategy,
      n_windows = nrow(windows$windows),
      coverage = windows$coverage_analysis$coverage_percentage,
      mean_width = mean(windows$windows$window_width)
    ))

  }, error = function(e) {
    cat(sprintf("    ❌ Error: %s\n", e$message))
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
  window_mode = WINDOW_MODE,
  overlap_percent = OVERLAP_PERCENT,
  min_width = MIN_WIDTH,
  max_width = MAX_WIDTH,
  rt_overlap = RT_OVERLAP,
  agc_target = AGC_TARGET,
  base_output_dir = BASE_OUTPUT_DIR
)

# Get all parquet files
parquet_files <- list.files("data", pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("\nFound %d parquet files to process\n", length(parquet_files)))
cat(sprintf("Will test %d m/z strategies for each file\n", length(MZ_STRATEGIES)))
cat(sprintf("Total combinations: %d\n\n", length(parquet_files) * length(MZ_STRATEGIES)))

# Process each file with each strategy
all_results <- list()
file_counter <- 1

for (file in parquet_files) {
  file_name <- basename(file)
  base_name <- gsub("\\.parquet$", "", file_name)

  cat(sprintf("\n[%d/%d] Processing: %s\n",
              file_counter, length(parquet_files), file_name))
  cat("═══════════════════════════════════════════════════════\n")

  # Load data once
  data <- arrow::read_parquet(file)
  cat(sprintf("  Loaded %d precursors\n", nrow(data)))

  # Process with each strategy
  for (strategy in MZ_STRATEGIES) {
    result <- process_file_strategy(file, strategy, config)
    if (!is.null(result)) {
      result_key <- sprintf("%s_%s", base_name, strategy)
      all_results[[result_key]] <- result
    }
  }

  file_counter <- file_counter + 1
}

# =============================================================================
# Generate Summary Report
# =============================================================================

if (length(all_results) > 0) {

  cat("\n\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║                    PROCESSING SUMMARY                           ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  summary_df <- bind_rows(all_results)

  # Summary by strategy
  cat("Performance by m/z Strategy:\n")
  cat("─────────────────────────────────────────────────────────────────\n")

  strategy_summary <- summary_df %>%
    group_by(strategy) %>%
    summarise(
      n_files = n(),
      avg_windows = mean(n_windows),
      avg_coverage = mean(coverage),
      avg_width = mean(mean_width),
      .groups = "drop"
    ) %>%
    arrange(desc(avg_coverage))

  cat(sprintf("%-12s %8s %12s %10s %12s\n",
              "Strategy", "Files", "Avg Windows", "Coverage", "Avg Width"))
  cat("─────────────────────────────────────────────────────────────────\n")

  for (i in 1:nrow(strategy_summary)) {
    cat(sprintf("%-12s %8d %12.0f %9.1f%% %11.1f Da\n",
                strategy_summary$strategy[i],
                strategy_summary$n_files[i],
                strategy_summary$avg_windows[i],
                strategy_summary$avg_coverage[i],
                strategy_summary$avg_width[i]))
  }

  # Best strategy selection
  best_strategy <- strategy_summary$strategy[1]
  cat(sprintf("\n✓ Best strategy by coverage: %s (%.1f%%)\n",
              best_strategy,
              strategy_summary$avg_coverage[1]))

  # Detailed results table
  cat("\n\nDetailed Results (Top 10 by coverage):\n")
  cat("─────────────────────────────────────────────────────────────────\n")

  top_results <- summary_df %>%
    arrange(desc(coverage)) %>%
    head(10)

  cat(sprintf("%-30s %-10s %8s %8s %10s\n",
              "File", "Strategy", "Windows", "Coverage", "Width"))
  cat("─────────────────────────────────────────────────────────────────\n")

  for (i in 1:nrow(top_results)) {
    cat(sprintf("%-30s %-10s %8d %7.1f%% %9.1f Da\n",
                top_results$file[i],
                top_results$strategy[i],
                top_results$n_windows[i],
                top_results$coverage[i],
                top_results$mean_width[i]))
  }

  # Save summary
  summary_file <- file.path(BASE_OUTPUT_DIR, "complete_summary.csv")
  write.csv(summary_df, summary_file, row.names = FALSE)
  cat(sprintf("\n✓ Complete summary saved to: %s\n", summary_file))

  # Save strategy comparison
  strategy_file <- file.path(BASE_OUTPUT_DIR, "strategy_comparison.csv")
  write.csv(strategy_summary, strategy_file, row.names = FALSE)
  cat(sprintf("✓ Strategy comparison saved to: %s\n", strategy_file))

  cat("\n✅ All processing complete!\n")
  cat(sprintf("\nResults saved in: %s/\n", BASE_OUTPUT_DIR))
  cat("Structure:\n")
  cat("  └── [dataset_name]/\n")
  cat("      ├── quantile/\n")
  cat("      ├── smoothing/\n")
  cat("      ├── coverage/\n")
  cat("      └── outlier/\n")
  cat("\nEach folder contains:\n")
  cat("  • *_thermo.csv - Thermo Fusion Lumos format\n")
  cat("  • *_legacy.csv - Legacy analysis format\n")
  cat("  • config.txt - Configuration used\n")

} else {
  cat("\n❌ No files were successfully processed.\n")
}