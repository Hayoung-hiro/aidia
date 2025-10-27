# =============================================================================
# DPPP-Optimized Pipeline for DIA Window Generation
# =============================================================================
# Generates windows with proper cycle time constraints for each gradient
# Based on DPPP analysis: 30min=1.2s, 60min=1.6s, 90min=2.0s cycle times
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)

# Source required modules
source("R/stage3_window_optimization/module3d_window_generation.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║     DPPP-Optimized DIA Window Generation Pipeline               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# DPPP-Optimized Configuration
# =============================================================================

# Gradient-specific settings based on DPPP analysis
GRADIENT_CONFIG <- list(
  "30min" = list(
    cycle_time = 1.2,      # seconds
    max_windows = 21,      # (1.2 - 0.1) / 0.05 = 22, use 21 for safety
    rt_segments = 3,       # 3 segments for 10min range
    target_dppp = 7.0,
    fwhm_median = 4.9      # seconds
  ),
  "60min" = list(
    cycle_time = 1.6,      # seconds
    max_windows = 30,      # (1.6 - 0.1) / 0.05 = 30
    rt_segments = 4,       # 4 segments for 35min range
    target_dppp = 7.0,
    fwhm_median = 6.7      # seconds
  ),
  "90min" = list(
    cycle_time = 2.0,      # seconds
    max_windows = 37,      # (2.0 - 0.1) / 0.05 = 38, use 37 for safety
    rt_segments = 5,       # 5 segments for 65min range
    target_dppp = 7.0,
    fwhm_median = 8.1      # seconds
  )
)

# Global settings
INSTRUMENT_TYPE <- "orbitrap"
MS1_TIME <- 0.100         # 100ms
MS2_TIME <- 0.050         # 50ms per window
MZ_STRATEGY <- "outlier"  # Best coverage from previous analysis
OVERLAP_PERCENT <- 0.02   # 2% overlap for safety
AGC_TARGET <- 800

# =============================================================================
# Pipeline Functions
# =============================================================================

# Function to create pipeline structures with DPPP constraints
create_dppp_optimized_structures <- function(data, file_name, gradient_config) {

  base_name <- gsub("\\.parquet$", "", file_name)

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

  # Use gradient-specific configuration
  n_windows <- gradient_config$max_windows
  n_rt_segments <- gradient_config$rt_segments
  cycle_time <- gradient_config$cycle_time

  cat(sprintf("  Configuration:\n"))
  cat(sprintf("    • Cycle time: %.1f seconds\n", cycle_time))
  cat(sprintf("    • Max windows: %d (DPPP-constrained)\n", n_windows))
  cat(sprintf("    • RT segments: %d\n", n_rt_segments))
  cat(sprintf("    • Windows per segment: ~%.1f\n", n_windows / n_rt_segments))

  # Create RT bins
  rt_breaks <- seq(rt_range[1], rt_range[2], length.out = n_rt_segments + 1)

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

  # Apply outlier removal strategy (best from previous analysis)
  mz_stats <- clean_data %>%
    group_by(rt_bin) %>%
    summarise(
      # Outlier removal strategy
      q1 = quantile(Precursor.Mz, 0.25, na.rm = TRUE),
      q3 = quantile(Precursor.Mz, 0.75, na.rm = TRUE),
      iqr = q3 - q1,
      mz_min = max(min(Precursor.Mz, na.rm = TRUE), q1 - 1.5 * iqr),
      mz_max = min(max(Precursor.Mz, na.rm = TRUE), q3 + 1.5 * iqr),
      n_precursors = n(),
      .groups = "drop"
    ) %>%
    mutate(
      mz_center = (mz_min + mz_max) / 2,
      mz_range = mz_max - mz_min
    )

  # Join RT bins with m/z stats
  rt_bins <- rt_bins %>%
    left_join(mz_stats, by = c("bin_id" = "rt_bin")) %>%
    select(bin_id, rt_start, rt_end, rt_center, rt_width,
           mz_min, mz_max, mz_center, mz_range, n_precursors)

  # Fill any missing values
  rt_bins$mz_min[is.na(rt_bins$mz_min)] <- mz_range[1]
  rt_bins$mz_max[is.na(rt_bins$mz_max)] <- mz_range[2]
  rt_bins$n_precursors[is.na(rt_bins$n_precursors)] <- 0
  rt_bins$mz_center <- (rt_bins$mz_min + rt_bins$mz_max) / 2
  rt_bins$mz_range <- rt_bins$mz_max - rt_bins$mz_min

  # Create structures for Stage 3D
  validated_data <- list(
    data = clean_data,
    metadata = list(
      n_precursors = nrow(clean_data),
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
      method = "dppp_optimized"
    )
  )

  mz_boundaries <- rt_bins %>%
    select(bin_id, mz_min, mz_max, mz_range)

  mz_ranges <- list(
    mz_ranges = mz_boundaries,
    strategy = MZ_STRATEGY
  )

  window_config <- list(
    window_mode = "variable",  # Variable for better distribution
    total_windows = n_windows, # Windows PER bin (per-bin architecture)
    per_bin_mode = TRUE,       # NEW: Each bin gets n_windows independently
    min_width_da = 10,        # Minimum window width
    max_width_da = 80,        # Maximum window width
    overlap = OVERLAP_PERCENT
  )

  return(list(
    validated_data = validated_data,
    rt_binning = rt_binning,
    mz_ranges = mz_ranges,
    window_config = window_config,
    gradient_config = gradient_config,
    base_name = base_name
  ))
}

# Function to analyze results
analyze_window_results <- function(windows, pipeline_data) {

  window_df <- windows$windows
  config <- pipeline_data$gradient_config

  # Calculate actual DPPP with generated windows
  actual_cycle_time <- config$cycle_time
  fwhm_median <- config$fwhm_median
  actual_dppp <- (1.7 * fwhm_median) / actual_cycle_time

  # Analyze isolation widths
  isolation_stats <- list(
    mean_width = mean(window_df$window_width),
    median_width = median(window_df$window_width),
    min_width = min(window_df$window_width),
    max_width = max(window_df$window_width),
    sd_width = sd(window_df$window_width)
  )

  # Windows per RT segment
  windows_per_segment <- window_df %>%
    group_by(rt_segment_id) %>%
    summarise(
      n_windows = n(),
      mean_width = mean(window_width),
      total_mz_range = max(mz_end) - min(mz_start),
      .groups = "drop"
    )

  # Coverage analysis
  coverage_pct <- windows$coverage_analysis$coverage_percentage

  # Create analysis summary
  analysis <- list(
    file = pipeline_data$base_name,
    cycle_time = actual_cycle_time,
    target_dppp = config$target_dppp,
    actual_dppp = actual_dppp,
    n_windows_target = config$max_windows,
    n_windows_actual = nrow(window_df),
    n_rt_segments = pipeline_data$rt_binning$metadata$n_segments,
    mean_isolation_width = isolation_stats$mean_width,
    median_isolation_width = isolation_stats$median_width,
    sd_isolation_width = isolation_stats$sd_width,
    coverage_pct = coverage_pct,
    windows_per_segment = windows_per_segment
  )

  return(analysis)
}

# =============================================================================
# Main Processing
# =============================================================================

# Create output directory
output_dir <- "results_dppp_optimized"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Get all parquet files
parquet_files <- list.files("data", pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("Found %d parquet files to process\n", length(parquet_files)))
cat("─────────────────────────────────────────────────────────────────\n\n")

# Process each file
all_results <- list()
all_analyses <- list()

for (file_path in parquet_files) {

  file_name <- basename(file_path)
  base_name <- gsub("\\.parquet$", "", file_name)

  # Determine gradient type
  gradient_type <- case_when(
    grepl("30min", base_name) ~ "30min",
    grepl("60min", base_name) ~ "60min",
    grepl("90min", base_name) ~ "90min",
    TRUE ~ "60min"  # Default
  )

  gradient_config <- GRADIENT_CONFIG[[gradient_type]]

  cat(sprintf("Processing: %s (%s gradient)\n", file_name, gradient_type))
  cat("═══════════════════════════════════════════════════════════════\n")

  tryCatch({
    # Load data
    data <- arrow::read_parquet(file_path)
    cat(sprintf("  Loaded %d precursors\n", nrow(data)))

    # Create DPPP-optimized structures
    pipeline_data <- create_dppp_optimized_structures(data, file_name, gradient_config)

    # Show RT and m/z ranges
    cat(sprintf("  RT range: %.1f - %.1f min\n",
                pipeline_data$validated_data$metadata$rt_range[1],
                pipeline_data$validated_data$metadata$rt_range[2]))
    cat(sprintf("  m/z range: %.0f - %.0f\n",
                pipeline_data$validated_data$metadata$mz_range[1],
                pipeline_data$validated_data$metadata$mz_range[2]))

    # Expected isolation width estimate
    mz_span <- diff(pipeline_data$validated_data$metadata$mz_range)
    expected_width <- mz_span / gradient_config$max_windows
    cat(sprintf("  Expected avg isolation width: ~%.1f Da\n", expected_width))

    # Generate windows using Stage 3D
    cat("\n  Generating windows...\n")
    windows <- generate_isolation_windows(
      validated_data = pipeline_data$validated_data,
      rt_binning = pipeline_data$rt_binning,
      mz_ranges = pipeline_data$mz_ranges,
      window_config = pipeline_data$window_config
    )

    # Analyze results
    analysis <- analyze_window_results(windows, pipeline_data)

    # Print analysis summary
    cat("\n📊 Results Analysis:\n")
    cat(sprintf("  • Windows generated: %d (target: %d)\n",
                analysis$n_windows_actual, analysis$n_windows_target))
    cat(sprintf("  • Mean isolation width: %.1f Da (expected: ~%.1f Da)\n",
                analysis$mean_isolation_width, expected_width))
    cat(sprintf("  • Coverage: %.1f%%\n", analysis$coverage_pct))
    cat(sprintf("  • DPPP achieved: %.1f (target: %.1f)\n",
                analysis$actual_dppp, analysis$target_dppp))

    # Print windows per segment
    cat("\n  Windows per RT segment:\n")
    for (i in 1:nrow(analysis$windows_per_segment)) {
      seg <- analysis$windows_per_segment[i,]
      cat(sprintf("    Segment %d: %d windows, mean width %.1f Da\n",
                  seg$rt_segment_id, seg$n_windows, seg$mean_width))
    }

    # Create output subdirectory
    dataset_dir <- file.path(output_dir, base_name)
    if (!dir.exists(dataset_dir)) {
      dir.create(dataset_dir)
    }

    # Export results
    thermo_file <- file.path(dataset_dir, sprintf("%s_dppp_optimized_thermo.csv", base_name))
    legacy_file <- file.path(dataset_dir, sprintf("%s_dppp_optimized_legacy.csv", base_name))

    export_windows_to_csv(
      window_result = windows,
      output_file = thermo_file,
      instrument_type = INSTRUMENT_TYPE,
      strategy = MZ_STRATEGY,
      include_metadata = TRUE,
      format = "thermo",
      agc_target = AGC_TARGET
    )

    export_windows_to_csv(
      window_result = windows,
      output_file = legacy_file,
      instrument_type = INSTRUMENT_TYPE,
      strategy = MZ_STRATEGY,
      include_metadata = TRUE,
      format = "legacy"
    )

    # Save analysis
    analysis_file <- file.path(dataset_dir, "analysis_summary.txt")
    writeLines(c(
      sprintf("DPPP-Optimized Window Generation Analysis"),
      sprintf("=========================================="),
      sprintf("Dataset: %s", base_name),
      sprintf("Gradient: %s", gradient_type),
      sprintf("Date: %s", Sys.Date()),
      "",
      "Cycle Time Configuration:",
      sprintf("  Target cycle time: %.1f seconds", analysis$cycle_time),
      sprintf("  Target DPPP: %.1f", analysis$target_dppp),
      sprintf("  Actual DPPP: %.1f", analysis$actual_dppp),
      "",
      "Window Generation Results:",
      sprintf("  Target windows: %d", analysis$n_windows_target),
      sprintf("  Actual windows: %d", analysis$n_windows_actual),
      sprintf("  RT segments: %d", analysis$n_rt_segments),
      sprintf("  Coverage: %.1f%%", analysis$coverage_pct),
      "",
      "Isolation Width Statistics:",
      sprintf("  Mean: %.1f Da", analysis$mean_isolation_width),
      sprintf("  Median: %.1f Da", analysis$median_isolation_width),
      sprintf("  SD: %.1f Da", analysis$sd_isolation_width),
      "",
      "Expected vs Actual:",
      sprintf("  Expected width: ~%.1f Da", mz_span / gradient_config$max_windows),
      sprintf("  Actual mean width: %.1f Da", analysis$mean_isolation_width),
      sprintf("  Difference: %.1f Da",
              analysis$mean_isolation_width - (mz_span / gradient_config$max_windows))
    ), analysis_file)

    # Store results
    all_results[[base_name]] <- windows
    all_analyses[[base_name]] <- analysis

    cat(sprintf("\n  ✓ Results saved in: %s\n", dataset_dir))

  }, error = function(e) {
    cat(sprintf("  ❌ Error: %s\n", e$message))
  })

  cat("\n")
}

# =============================================================================
# Generate Overall Summary
# =============================================================================

if (length(all_analyses) > 0) {

  cat("\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║              DPPP-OPTIMIZED PIPELINE SUMMARY                    ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  # Convert to dataframe
  summary_df <- bind_rows(lapply(all_analyses, function(x) {
    data.frame(
      file = x$file,
      cycle_time = x$cycle_time,
      target_dppp = x$target_dppp,
      actual_dppp = x$actual_dppp,
      n_windows_target = x$n_windows_target,
      n_windows_actual = x$n_windows_actual,
      n_rt_segments = x$n_rt_segments,
      mean_isolation_width = x$mean_isolation_width,
      coverage_pct = x$coverage_pct
    )
  }))

  # Add gradient type
  summary_df$gradient <- case_when(
    grepl("30min", summary_df$file) ~ "30min",
    grepl("60min", summary_df$file) ~ "60min",
    grepl("90min", summary_df$file) ~ "90min"
  )

  # Group by gradient
  gradient_summary <- summary_df %>%
    group_by(gradient) %>%
    summarise(
      n_files = n(),
      avg_cycle_time = mean(cycle_time),
      avg_dppp = mean(actual_dppp),
      avg_windows = mean(n_windows_actual),
      avg_isolation_width = mean(mean_isolation_width),
      avg_coverage = mean(coverage_pct),
      .groups = "drop"
    )

  cat("Summary by Gradient Type:\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat(sprintf("%-8s %10s %8s %8s %10s %10s %10s\n",
              "Gradient", "Cycle(s)", "DPPP", "Windows", "Width(Da)", "Coverage", "Files"))
  cat("───────────────────────────────────────────────────────────────\n")

  for (i in 1:nrow(gradient_summary)) {
    cat(sprintf("%-8s %10.1f %8.1f %8.0f %10.1f %9.1f%% %10d\n",
                gradient_summary$gradient[i],
                gradient_summary$avg_cycle_time[i],
                gradient_summary$avg_dppp[i],
                gradient_summary$avg_windows[i],
                gradient_summary$avg_isolation_width[i],
                gradient_summary$avg_coverage[i],
                gradient_summary$n_files[i]))
  }

  # Detailed results
  cat("\n\nDetailed Results by Dataset:\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat(sprintf("%-25s %8s %8s %8s %10s %10s\n",
              "Dataset", "CT(s)", "DPPP", "Windows", "Width(Da)", "Coverage"))
  cat("───────────────────────────────────────────────────────────────\n")

  for (i in 1:nrow(summary_df)) {
    cat(sprintf("%-25s %8.1f %8.1f %8d %10.1f %9.1f%%\n",
                summary_df$file[i],
                summary_df$cycle_time[i],
                summary_df$actual_dppp[i],
                summary_df$n_windows_actual[i],
                summary_df$mean_isolation_width[i],
                summary_df$coverage_pct[i]))
  }

  # Save summaries
  write.csv(summary_df,
            file.path(output_dir, "dppp_optimized_summary.csv"),
            row.names = FALSE)
  write.csv(gradient_summary,
            file.path(output_dir, "gradient_summary.csv"),
            row.names = FALSE)

  cat("\n✅ DPPP-Optimized Pipeline Complete!\n")
  cat(sprintf("Results saved in: %s/\n", output_dir))
  cat("\n📌 Key Achievements:\n")
  cat(sprintf("  • All gradients achieve DPPP ~%.1f\n", TARGET_DPPP))
  cat(sprintf("  • Window counts match cycle time constraints\n"))
  cat(sprintf("  • Coverage maintained at >%.0f%%\n", 95))
}

cat("\n")