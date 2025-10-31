# =============================================================================
# Simplified Real Data Test: Generate 8 Isolation Windows
# =============================================================================
# Direct implementation bypassing unimplemented stages
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)

# Source Stage 3D (the module we just updated)
source("R/stage3_window_optimization/module3d_window_generation.R")

# Configuration
WINDOW_COUNT <- 8
OUTPUT_DIR <- "results_8windows"

# Create output directory
if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
}

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║  8-Window Generation Test (Simplified)                          ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Function to create mock stages output from real data
create_mock_pipeline_data <- function(data, n_windows = 8) {

  # Basic data validation
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

  # Get data ranges
  rt_range <- range(clean_data$RT.Start, na.rm = TRUE)
  mz_range <- range(clean_data$Precursor.Mz, na.rm = TRUE)

  # Determine RT segments based on gradient length
  gradient_length <- rt_range[2] - rt_range[1]
  n_rt_segments <- case_when(
    gradient_length <= 35 ~ 2,  # 30min
    gradient_length <= 65 ~ 3,  # 60min
    TRUE ~ 4                     # 90min
  )

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

  # Fill any missing m/z values with overall range
  rt_bins$mz_min[is.na(rt_bins$mz_min)] <- mz_range[1]
  rt_bins$mz_max[is.na(rt_bins$mz_max)] <- mz_range[2]
  rt_bins$mz_center[is.na(rt_bins$mz_center)] <- mean(mz_range)
  rt_bins$mz_range[is.na(rt_bins$mz_range)] <- diff(mz_range)

  # Create mock structures needed by Stage 3D
  validated_data <- list(
    data = clean_data,
    metadata = list(
      n_precursors = nrow(clean_data),
      rt_range = rt_range,
      mz_range = mz_range
    )
  )

  rt_binning <- list(
    bins = rt_bins,
    metadata = list(
      n_segments = n_rt_segments,
      method = "time_based"
    )
  )

  # Create mz boundaries with proper column names
  mz_boundaries <- rt_bins %>%
    select(bin_id, mz_min, mz_max, mz_range)

  mz_optimization <- list(
    strategy = "smoothing",
    rt_bins = rt_bins,
    boundaries = mz_boundaries
  )

  window_count <- list(
    window_count = n_windows,
    windows_per_segment = round(n_windows / n_rt_segments, 1)
  )

  return(list(
    validated_data = validated_data,
    rt_binning = rt_binning,
    mz_optimization = mz_optimization,
    window_count = window_count
  ))
}

# Process each parquet file
parquet_files <- list.files("data", pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("Found %d parquet files\n\n", length(parquet_files)))

results_summary <- list()

for (file_path in parquet_files) {

  file_name <- basename(file_path)
  base_name <- gsub("\\.parquet$", "", file_name)

  cat(sprintf("═══════════════════════════════════════════\n"))
  cat(sprintf("Processing: %s\n", file_name))
  cat(sprintf("═══════════════════════════════════════════\n"))

  tryCatch({
    # Load data
    data <- arrow::read_parquet(file_path)
    cat(sprintf("  Loaded %d rows\n", nrow(data)))

    # Create mock pipeline data
    pipeline_data <- create_mock_pipeline_data(data, n_windows = WINDOW_COUNT)

    cat(sprintf("  RT range: %.1f - %.1f min\n",
                pipeline_data$validated_data$metadata$rt_range[1],
                pipeline_data$validated_data$metadata$rt_range[2]))
    cat(sprintf("  m/z range: %.0f - %.0f\n",
                pipeline_data$validated_data$metadata$mz_range[1],
                pipeline_data$validated_data$metadata$mz_range[2]))
    cat(sprintf("  RT segments: %d\n", nrow(pipeline_data$rt_binning$bins)))

    # Generate windows using Stage 3D
    # Create window configuration
    window_config <- list(
      window_mode = "variable",  # "fixed" or "variable"
      total_windows = WINDOW_COUNT,
      min_width_da = 2,
      max_width_da = 80,
      overlap = 0.05  # 5% overlap
    )

    # Create mz_ranges structure expected by the function
    mz_ranges <- list(
      mz_ranges = pipeline_data$mz_optimization$boundaries  # Old structure format
    )

    windows <- generate_isolation_windows(
      validated_data = pipeline_data$validated_data,
      rt_binning = pipeline_data$rt_binning,
      mz_ranges = mz_ranges,
      window_config = window_config
    )

    cat(sprintf("  Generated %d windows\n", nrow(windows$windows)))
    cat(sprintf("  Coverage: %.1f%%\n", windows$coverage_analysis$coverage_percentage))

    # Export in both formats
    thermo_file <- file.path(OUTPUT_DIR, sprintf("%s_8windows_thermo.csv", base_name))
    legacy_file <- file.path(OUTPUT_DIR, sprintf("%s_8windows_legacy.csv", base_name))

    # Thermo format
    export_windows_to_csv(
      window_result = windows,
      output_file = thermo_file,
      instrument_type = "orbitrap",
      strategy = "smoothing",
      include_metadata = TRUE,
      format = "thermo",
      agc_target = 800
    )

    # Legacy format
    export_windows_to_csv(
      window_result = windows,
      output_file = legacy_file,
      instrument_type = "orbitrap",
      strategy = "smoothing",
      include_metadata = TRUE,
      format = "legacy"
    )

    # Store summary
    results_summary[[base_name]] <- list(
      file = base_name,
      n_precursors = nrow(pipeline_data$validated_data$data),
      n_windows = nrow(windows$windows),
      coverage = windows$coverage_analysis$coverage_percentage,
      mean_width = mean(windows$windows$window_width),
      rt_segments = nrow(pipeline_data$rt_binning$bins)
    )

    cat(sprintf("  ✓ Saved: %s\n", basename(thermo_file)))
    cat(sprintf("  ✓ Saved: %s\n\n", basename(legacy_file)))

  }, error = function(e) {
    cat(sprintf("  ❌ Error: %s\n\n", e$message))
  })
}

# Print summary
cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                         SUMMARY                                 ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

if (length(results_summary) > 0) {
  summary_df <- bind_rows(results_summary)

  cat(sprintf("%-25s %10s %8s %8s %10s\n",
              "File", "Precursors", "Windows", "Coverage", "Mean Width"))
  cat("─────────────────────────────────────────────────────────────────\n")

  for (i in 1:nrow(summary_df)) {
    cat(sprintf("%-25s %10d %8d %7.1f%% %9.1f Da\n",
                summary_df$file[i],
                summary_df$n_precursors[i],
                summary_df$n_windows[i],
                summary_df$coverage[i],
                summary_df$mean_width[i]))
  }

  # Save summary
  write.csv(summary_df, file.path(OUTPUT_DIR, "summary.csv"), row.names = FALSE)
  cat("\n✓ Summary saved to: results_8windows/summary.csv\n")
}

cat("\n✅ Processing complete!\n")
cat("\nOutput files in: results_8windows/\n")
cat("  • *_thermo.csv: Thermo Fusion Lumos format (instrument-ready)\n")
cat("  • *_legacy.csv: Legacy format (for analysis)\n\n")