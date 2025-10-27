# =============================================================================
# Comprehensive DIA Window Generation Pipeline
# =============================================================================
# Generates windows with 4 m/z strategies × 2 window modes = 8 combinations
# per dataset
# =============================================================================

library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)

# Source required modules
source("R/stage3_window_optimization/module3d_window_generation.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Comprehensive DIA Window Generation Pipeline                 ║\n")
cat("║   4 m/z Strategies × 2 Window Modes = 8 Combinations          ║\n")
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

# Strategy and mode combinations
MZ_STRATEGIES <- c("quantile", "smoothing", "outlier", "coverage")
WINDOW_MODES <- c("fixed", "variable")

# =============================================================================
# Functions
# =============================================================================

#' Create pipeline structures with multiple m/z strategies
create_comprehensive_structures <- function(data, file_name, gradient_config) {

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
  clean_data$rt_bin <- cut(clean_data$RT.Start, breaks = rt_breaks,
                            labels = FALSE, include.lowest = TRUE)
  clean_data <- clean_data %>% filter(!is.na(rt_bin))

  # Calculate m/z ranges using 4 strategies
  mz_strategies_data <- list()

  for (strategy in MZ_STRATEGIES) {
    if (strategy == "quantile") {
      mz_stats <- clean_data %>%
        group_by(rt_bin) %>%
        summarise(
          mz_min = quantile(Precursor.Mz, 0.001, na.rm = TRUE),
          mz_max = quantile(Precursor.Mz, 0.999, na.rm = TRUE),
          n_precursors = n(),
          .groups = "drop"
        )
    } else if (strategy == "outlier") {
      mz_stats <- clean_data %>%
        group_by(rt_bin) %>%
        summarise(
          q1 = quantile(Precursor.Mz, 0.25, na.rm = TRUE),
          q3 = quantile(Precursor.Mz, 0.75, na.rm = TRUE),
          iqr = q3 - q1,
          mz_min = max(min(Precursor.Mz, na.rm = TRUE), q1 - 1.5 * iqr),
          mz_max = min(max(Precursor.Mz, na.rm = TRUE), q3 + 1.5 * iqr),
          n_precursors = n(),
          .groups = "drop"
        ) %>%
        select(rt_bin, mz_min, mz_max, n_precursors)
    } else if (strategy == "smoothing") {
      mz_stats <- clean_data %>%
        group_by(rt_bin) %>%
        summarise(
          mz_min = quantile(Precursor.Mz, 0.01, na.rm = TRUE),
          mz_max = quantile(Precursor.Mz, 0.99, na.rm = TRUE),
          n_precursors = n(),
          .groups = "drop"
        )
    } else if (strategy == "coverage") {
      mz_stats <- clean_data %>%
        group_by(rt_bin) %>%
        summarise(
          mz_min = min(Precursor.Mz, na.rm = TRUE),
          mz_max = max(Precursor.Mz, na.rm = TRUE),
          n_precursors = n(),
          .groups = "drop"
        )
    }

    mz_stats <- mz_stats %>%
      mutate(
        bin_id = rt_bin,
        mz_center = (mz_min + mz_max) / 2,
        mz_range = mz_max - mz_min
      ) %>%
      select(bin_id, mz_min, mz_max, mz_center, mz_range, n_precursors)

    mz_strategies_data[[strategy]] <- mz_stats
  }

  # Create validated_data structure
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
      method = "time_based"
    )
  )

  return(list(
    validated_data = validated_data,
    rt_binning = rt_binning,
    mz_strategies = mz_strategies_data,
    gradient_config = gradient_config,
    base_name = base_name
  ))
}

#' Generate windows for one strategy-mode combination
generate_windows_combination <- function(structures, strategy, mode) {

  # Prepare m/z ranges
  mz_ranges <- list(
    mz_ranges = structures$mz_strategies[[strategy]],
    strategy = strategy
  )

  # Prepare window config
  window_config <- list(
    window_mode = mode,
    total_windows = structures$gradient_config$max_windows,
    per_bin_mode = TRUE,  # Per-bin architecture
    min_width_da = 10,
    max_width_da = 80,
    overlap = OVERLAP_PERCENT
  )

  # Generate windows
  windows_result <- generate_isolation_windows(
    validated_data = structures$validated_data,
    rt_binning = structures$rt_binning,
    mz_ranges = mz_ranges,
    window_config = window_config
  )

  return(windows_result)
}

# =============================================================================
# Main Processing
# =============================================================================

# Create output directory
output_dir <- "results_comprehensive"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Get all parquet files
parquet_files <- list.files("data", pattern = "\\.parquet$", full.names = FALSE)
cat(sprintf("Found %d parquet files to process\n", length(parquet_files)))
cat("═══════════════════════════════════════════════════════════════\n\n")

# Results summary
all_results <- list()

# Process each file
for (file in parquet_files) {

  # Determine gradient type
  gradient_type <- if (grepl("30min", file)) "30min" else if (grepl("60min", file)) "60min" else "90min"
  gradient_config <- GRADIENT_CONFIG[[gradient_type]]

  cat(sprintf("\n═══════════════════════════════════════════════════════════════\n"))
  cat(sprintf("Processing: %s (%s gradient)\n", file, gradient_type))
  cat(sprintf("═══════════════════════════════════════════════════════════════\n"))

  # Load data
  data <- read_parquet(file.path("data", file))
  cat(sprintf("  Loaded %d precursors\n\n", nrow(data)))

  # Create structures with all strategies
  structures <- create_comprehensive_structures(data, file, gradient_config)

  # Create output directory for this file
  file_output_dir <- file.path(output_dir, structures$base_name)
  if (!dir.exists(file_output_dir)) {
    dir.create(file_output_dir, recursive = TRUE)
  }

  # Generate windows for all combinations
  file_results <- list()

  for (strategy in MZ_STRATEGIES) {
    for (mode in WINDOW_MODES) {

      combo_name <- sprintf("%s_%s", strategy, mode)
      cat(sprintf("\n--- Strategy: %s | Mode: %s ---\n", toupper(strategy), toupper(mode)))

      # Generate windows
      windows_result <- generate_windows_combination(structures, strategy, mode)

      # Store results
      file_results[[combo_name]] <- list(
        strategy = strategy,
        mode = mode,
        n_windows = nrow(windows_result$windows),
        mean_width = mean(windows_result$windows$window_width),
        coverage = windows_result$coverage_analysis$coverage_percentage
      )

      # Export to CSV (both formats)
      thermo_file <- file.path(file_output_dir,
                               sprintf("%s_%s_%s_thermo.csv", structures$base_name, strategy, mode))
      legacy_file <- file.path(file_output_dir,
                               sprintf("%s_%s_%s_legacy.csv", structures$base_name, strategy, mode))

      export_windows_to_csv(
        window_result = windows_result,
        output_file = thermo_file,
        instrument_type = INSTRUMENT_TYPE,
        strategy = strategy,
        include_metadata = TRUE,
        format = "thermo",
        agc_target = AGC_TARGET
      )

      export_windows_to_csv(
        window_result = windows_result,
        output_file = legacy_file,
        instrument_type = INSTRUMENT_TYPE,
        strategy = strategy,
        include_metadata = TRUE,
        format = "legacy",
        agc_target = AGC_TARGET
      )

      cat(sprintf("  ✓ Generated %d windows (mean width: %.1f Da, coverage: %.1f%%)\n",
                  nrow(windows_result$windows),
                  mean(windows_result$windows$window_width),
                  windows_result$coverage_analysis$coverage_percentage))
      cat(sprintf("  ✓ Exported: %s\n", basename(thermo_file)))
      cat(sprintf("  ✓ Exported: %s\n", basename(legacy_file)))
    }
  }

  # Save summary for this file
  all_results[[structures$base_name]] <- list(
    gradient = gradient_type,
    n_precursors = structures$validated_data$metadata$n_precursors,
    rt_segments = structures$rt_binning$metadata$n_segments,
    target_windows_per_segment = gradient_config$max_windows,
    results = file_results
  )
}

# =============================================================================
# Generate Summary Report
# =============================================================================

cat("\n\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    COMPREHENSIVE SUMMARY                        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Create summary table
summary_rows <- list()
for (file_name in names(all_results)) {
  result <- all_results[[file_name]]

  for (combo_name in names(result$results)) {
    combo <- result$results[[combo_name]]

    expected_total <- result$rt_segments * result$target_windows_per_segment
    deviation <- (combo$n_windows - expected_total) / expected_total * 100

    summary_rows[[length(summary_rows) + 1]] <- data.frame(
      Dataset = file_name,
      Gradient = result$gradient,
      Strategy = combo$strategy,
      Mode = combo$mode,
      RT_Segs = result$rt_segments,
      Target_Per_Seg = result$target_windows_per_segment,
      Expected_Total = expected_total,
      Actual_Total = combo$n_windows,
      Deviation_Pct = sprintf("%.1f%%", deviation),
      Mean_Width_Da = sprintf("%.1f", combo$mean_width),
      Coverage_Pct = sprintf("%.1f%%", combo$coverage),
      stringsAsFactors = FALSE
    )
  }
}

summary_df <- bind_rows(summary_rows)

# Print summary by gradient
for (grad in c("30min", "60min", "90min")) {
  grad_data <- summary_df %>% filter(Gradient == grad)

  if (nrow(grad_data) == 0) next

  cat(sprintf("\n%s Gradient Results:\n", grad))
  cat("═══════════════════════════════════════════════════════════════\n")
  print(grad_data %>% select(Dataset, Strategy, Mode, Expected_Total, Actual_Total,
                             Deviation_Pct, Mean_Width_Da, Coverage_Pct))
  cat("\n")
}

# Save summary to CSV
summary_file <- file.path(output_dir, "comprehensive_summary.csv")
write.csv(summary_df, summary_file, row.names = FALSE)
cat(sprintf("✅ Summary saved to: %s\n\n", summary_file))

cat("✅ Comprehensive pipeline complete!\n")
cat(sprintf("   Total datasets: %d\n", length(all_results)))
cat(sprintf("   Total combinations: %d\n", nrow(summary_df)))
cat(sprintf("   Output directory: %s\n\n", output_dir))
