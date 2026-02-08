# =============================================================================
# Module Tracing Script for 30min_report_01.parquet
# =============================================================================
# Trace each module's input/output to verify data flow

library(arrow)
library(dplyr)

# Source all required modules
source("R/stage1_data_validation.R")
source("R/stage2_dppp_diagnosis.R")
source("R/stage3_window_optimization/module3a_window_count.R")
source("R/stage3_window_optimization/module3b_rt_binning.R")
source("R/stage3_window_optimization/module3c_mz_range_optimization.R")
source("R/stage3_window_optimization/module3d_window_generation.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          Module Tracing: 30min_report_01.parquet               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Load Data
# =============================================================================
cat("═══════════════════════════════════════════════════════════════\n")
cat("LOADING DATA\n")
cat("═══════════════════════════════════════════════════════════════\n")

data <- read_parquet("data/30min_report_01.parquet")

# Clean column names
if ("RT" %in% names(data)) data$RT.Start <- data$RT
if ("Precursor.mz" %in% names(data)) data$Precursor.Mz <- data$Precursor.mz

clean_data <- data %>%
  filter(!is.na(RT.Start), !is.na(Precursor.Mz), !is.na(FWHM)) %>%
  filter(RT.Start > 0, Precursor.Mz > 0, FWHM > 0)

cat(sprintf("✓ Loaded %d precursors\n", nrow(clean_data)))
cat(sprintf("  RT range: %.1f - %.1f min\n", min(clean_data$RT.Start), max(clean_data$RT.Start)))
cat(sprintf("  m/z range: %.1f - %.1f Da\n", min(clean_data$Precursor.Mz), max(clean_data$Precursor.Mz)))
cat(sprintf("  FWHM median: %.2f sec\n\n", median(clean_data$FWHM)))

# Create validated_data structure
validated_data <- list(
  data = clean_data,
  metadata = list(
    n_precursors = nrow(clean_data),
    rt_range = range(clean_data$RT.Start),
    mz_range = range(clean_data$Precursor.Mz),
    fwhm_median = median(clean_data$FWHM)
  )
)

# =============================================================================
# Module 3A: Window Count Determination
# =============================================================================
cat("═══════════════════════════════════════════════════════════════\n")
cat("MODULE 3A: WINDOW COUNT DETERMINATION\n")
cat("═══════════════════════════════════════════════════════════════\n")

# Configuration for 30min gradient
CYCLE_TIME <- 1.2  # seconds
TARGET_DPPP <- 7.0
INSTRUMENT_TYPE <- "orbitrap"
MS1_TIME <- 0.100
MS2_TIME <- 0.050

cat(sprintf("Input Configuration:\n"))
cat(sprintf("  • Cycle time: %.1f sec\n", CYCLE_TIME))
cat(sprintf("  • Target DPPP: %.1f\n", TARGET_DPPP))
cat(sprintf("  • Instrument: %s\n", INSTRUMENT_TYPE))
cat(sprintf("  • MS1 time: %.3f sec\n", MS1_TIME))
cat(sprintf("  • MS2 time: %.3f sec\n\n", MS2_TIME))

# Calculate max windows based on cycle time
max_windows <- floor((CYCLE_TIME - MS1_TIME) / MS2_TIME)

cat(sprintf("Output from Module 3A:\n"))
cat(sprintf("  ✓ Max windows: %d\n", max_windows))
cat(sprintf("    Formula: floor((%.1f - %.1f) / %.3f) = %d\n\n",
            CYCLE_TIME, MS1_TIME, MS2_TIME, max_windows))

# For this test, use 21 windows as target
TARGET_WINDOWS <- 21
cat(sprintf("  ✓ Target windows (for DPPP optimization): %d\n\n", TARGET_WINDOWS))

# =============================================================================
# Module 3B: RT Binning
# =============================================================================
cat("═══════════════════════════════════════════════════════════════\n")
cat("MODULE 3B: RT BINNING\n")
cat("═══════════════════════════════════════════════════════════════\n")

# Use time-based binning for 30min gradient
RT_SEGMENTS <- 3
rt_range <- validated_data$metadata$rt_range

cat(sprintf("Input Configuration:\n"))
cat(sprintf("  • RT range: %.1f - %.1f min\n", rt_range[1], rt_range[2]))
cat(sprintf("  • Target segments: %d\n\n", RT_SEGMENTS))

# Create RT bins
rt_breaks <- seq(rt_range[1], rt_range[2], length.out = RT_SEGMENTS + 1)

rt_bins <- tibble(
  bin_id = 1:RT_SEGMENTS,
  rt_start = rt_breaks[1:RT_SEGMENTS],
  rt_end = rt_breaks[2:(RT_SEGMENTS + 1)],
  rt_center = (rt_breaks[1:RT_SEGMENTS] + rt_breaks[2:(RT_SEGMENTS + 1)]) / 2,
  rt_width = rt_breaks[2:(RT_SEGMENTS + 1)] - rt_breaks[1:RT_SEGMENTS]
)

cat(sprintf("Output from Module 3B:\n"))
cat(sprintf("  ✓ Created %d RT segments:\n\n", nrow(rt_bins)))
for (i in 1:nrow(rt_bins)) {
  cat(sprintf("    Segment %d: %.1f - %.1f min (width: %.1f min)\n",
              rt_bins$bin_id[i], rt_bins$rt_start[i], rt_bins$rt_end[i], rt_bins$rt_width[i]))
}
cat("\n")

rt_binning <- list(
  bins = rt_bins,
  metadata = list(
    n_segments = RT_SEGMENTS,
    method = "time_based"
  )
)

# =============================================================================
# Module 3C: m/z Range Optimization
# =============================================================================
cat("═══════════════════════════════════════════════════════════════\n")
cat("MODULE 3C: M/Z RANGE OPTIMIZATION\n")
cat("═══════════════════════════════════════════════════════════════\n")

cat(sprintf("Input:\n"))
cat(sprintf("  • Precursors: %d\n", nrow(clean_data)))
cat(sprintf("  • RT segments: %d\n\n", nrow(rt_bins)))

# Assign precursors to RT bins
clean_data$rt_bin <- cut(clean_data$RT.Start, breaks = rt_breaks,
                          labels = FALSE, include.lowest = TRUE)
clean_data_binned <- clean_data %>% filter(!is.na(rt_bin))

# Apply 4 strategies
strategies <- c("quantile", "smoothing", "outlier", "coverage")

mz_results <- list()

for (strategy in strategies) {
  cat(sprintf("Strategy: %s\n", toupper(strategy)))
  cat("─────────────────────────────────────────────────────────────\n")

  if (strategy == "quantile") {
    # Simple quantile method
    mz_stats <- clean_data_binned %>%
      group_by(rt_bin) %>%
      summarise(
        mz_min = quantile(Precursor.Mz, 0.001, na.rm = TRUE),
        mz_max = quantile(Precursor.Mz, 0.999, na.rm = TRUE),
        n_precursors = n(),
        .groups = "drop"
      )
  } else if (strategy == "outlier") {
    # Outlier removal (IQR method)
    mz_stats <- clean_data_binned %>%
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
    # Simplified smoothing (no external dependencies)
    mz_stats <- clean_data_binned %>%
      group_by(rt_bin) %>%
      summarise(
        mz_min = quantile(Precursor.Mz, 0.01, na.rm = TRUE),
        mz_max = quantile(Precursor.Mz, 0.99, na.rm = TRUE),
        n_precursors = n(),
        .groups = "drop"
      )
  } else if (strategy == "coverage") {
    # Maximum coverage method
    mz_stats <- clean_data_binned %>%
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

  mz_results[[strategy]] <- mz_stats

  # Print results
  for (i in 1:nrow(mz_stats)) {
    cat(sprintf("  Segment %d: %.1f - %.1f Da (range: %.1f Da, n=%d)\n",
                mz_stats$bin_id[i], mz_stats$mz_min[i], mz_stats$mz_max[i],
                mz_stats$mz_range[i], mz_stats$n_precursors[i]))
  }
  cat("\n")
}

# Use outlier strategy (best from previous analysis)
SELECTED_STRATEGY <- "outlier"
mz_range_data <- mz_results[[SELECTED_STRATEGY]]

cat(sprintf("Output from Module 3C:\n"))
cat(sprintf("  ✓ Selected strategy: %s\n", SELECTED_STRATEGY))
cat(sprintf("  ✓ m/z ranges calculated for %d segments\n\n", nrow(mz_range_data)))

mz_ranges <- list(
  mz_ranges = mz_range_data,
  strategy = SELECTED_STRATEGY,
  all_strategies = mz_results
)

# =============================================================================
# Module 3D: Window Generation
# =============================================================================
cat("═══════════════════════════════════════════════════════════════\n")
cat("MODULE 3D: WINDOW GENERATION\n")
cat("═══════════════════════════════════════════════════════════════\n")

cat(sprintf("Input from previous modules:\n"))
cat(sprintf("  • Target windows (3A): %d\n", TARGET_WINDOWS))
cat(sprintf("  • RT segments (3B): %d\n", nrow(rt_bins)))
cat(sprintf("  • m/z ranges (3C): %s strategy\n\n", SELECTED_STRATEGY))

# NEW ARCHITECTURE: Each segment gets TARGET_WINDOWS windows
# Total windows = RT_SEGMENTS × TARGET_WINDOWS
windows_per_segment <- TARGET_WINDOWS
expected_total_windows <- RT_SEGMENTS * TARGET_WINDOWS

cat(sprintf("Window allocation (NEW per-bin architecture):\n"))
cat(sprintf("  • Windows per segment: %d\n", windows_per_segment))
cat(sprintf("  • Total segments: %d\n", RT_SEGMENTS))
cat(sprintf("  • Expected total: %d segments × %d windows = %d windows\n\n",
            RT_SEGMENTS, windows_per_segment, expected_total_windows))

# Now generate windows using Module 3D
# IMPORTANT: per_bin_mode = TRUE means total_windows is "per bin"
window_config <- list(
  window_mode = "variable",
  total_windows = TARGET_WINDOWS,  # This means 21 windows PER bin
  per_bin_mode = TRUE,             # NEW ARCHITECTURE: per-bin allocation
  min_width_da = 10,
  max_width_da = 80,
  overlap = 0.02
)

cat(sprintf("Window generation configuration:\n"))
cat(sprintf("  • Mode: %s\n", window_config$window_mode))
cat(sprintf("  • Windows per bin: %d (per_bin_mode = TRUE)\n", window_config$total_windows))
cat(sprintf("  • Min width: %.1f Da\n", window_config$min_width_da))
cat(sprintf("  • Max width: %.1f Da\n", window_config$max_width_da))
cat(sprintf("  • Overlap: %.1f%%\n\n", window_config$overlap * 100))

# Check what Module 3D will do per segment
cat(sprintf("Expected behavior per RT segment:\n"))
cat("─────────────────────────────────────────────────────────────\n")

for (i in 1:nrow(rt_bins)) {
  rt_bin <- rt_bins[i, ]
  mz_bin <- mz_range_data[mz_range_data$bin_id == i, ]

  mz_range_bin <- mz_bin$mz_max[1] - mz_bin$mz_min[1]
  n_windows_bin <- windows_per_segment  # Each bin gets same number

  # Get precursors for this bin
  bin_precursors <- clean_data_binned %>%
    filter(rt_bin == i)

  # Calculate ideal window width
  ideal_width <- mz_range_bin / n_windows_bin

  cat(sprintf("Segment %d:\n", i))
  cat(sprintf("  • RT: %.1f - %.1f min\n", rt_bin$rt_start, rt_bin$rt_end))
  cat(sprintf("  • m/z: %.1f - %.1f Da (range: %.1f Da)\n",
              mz_bin$mz_min[1], mz_bin$mz_max[1], mz_range_bin))
  cat(sprintf("  • Precursors: %d\n", nrow(bin_precursors)))
  cat(sprintf("  • Target windows: %d\n", n_windows_bin))
  cat(sprintf("  • Ideal window width: %.1f Da\n", ideal_width))

  # Check if ideal width violates constraints
  if (ideal_width < window_config$min_width_da) {
    actual_windows <- floor(mz_range_bin / window_config$min_width_da)
    cat(sprintf("  ⚠️  Ideal width (%.1f) < min_width_da (%.1f)\n",
                ideal_width, window_config$min_width_da))
    cat(sprintf("      → Will generate ~%d windows instead\n", actual_windows))
  } else if (ideal_width > window_config$max_width_da) {
    actual_windows <- ceiling(mz_range_bin / window_config$max_width_da)
    cat(sprintf("  ⚠️  Ideal width (%.1f) > max_width_da (%.1f)\n",
                ideal_width, window_config$max_width_da))
    cat(sprintf("      → Will generate ~%d windows instead\n", actual_windows))
  } else {
    cat(sprintf("  ✓ Ideal width within constraints\n"))
  }
  cat("\n")
}

# Actually call Module 3D
cat("Calling Module 3D generate_isolation_windows()...\n")
cat("─────────────────────────────────────────────────────────────\n\n")

windows_result <- generate_isolation_windows(
  validated_data = validated_data,
  rt_binning = rt_binning,
  mz_ranges = mz_ranges,
  window_config = window_config
)

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("FINAL RESULTS COMPARISON\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

windows_df <- windows_result$windows

# Count windows per segment
windows_per_seg <- windows_df %>%
  group_by(rt_segment_id) %>%
  summarise(
    n_windows = n(),
    mean_width = mean(window_width),
    min_width = min(window_width),
    max_width = max(window_width),
    .groups = "drop"
  )

cat(sprintf("Target vs Actual:\n"))
cat("─────────────────────────────────────────────────────────────\n")
cat(sprintf("%-10s %10s %10s %10s %15s\n", "Segment", "Target", "Actual", "Diff", "Avg Width (Da)"))
cat("─────────────────────────────────────────────────────────────\n")

total_target <- 0
total_actual <- 0

for (i in 1:nrow(windows_per_seg)) {
  target <- windows_per_segment  # Each segment gets same number in per-bin mode

  actual <- windows_per_seg$n_windows[i]
  diff <- actual - target
  avg_width <- windows_per_seg$mean_width[i]

  total_target <- total_target + target
  total_actual <- total_actual + actual

  cat(sprintf("%-10d %10d %10d %+10d %15.1f\n",
              i, target, actual, diff, avg_width))
}

cat("─────────────────────────────────────────────────────────────\n")
cat(sprintf("%-10s %10d %10d %+10d %15.1f\n",
            "TOTAL", total_target, total_actual, total_actual - total_target,
            mean(windows_df$window_width)))

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("SUMMARY\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat(sprintf("Module 3A output: %d windows per segment\n", TARGET_WINDOWS))
cat(sprintf("Module 3B output: %d RT segments\n", RT_SEGMENTS))
cat(sprintf("Module 3C output: %s strategy with %d m/z ranges\n", SELECTED_STRATEGY, nrow(mz_range_data)))
cat(sprintf("Module 3D output: %d windows (target: %d)\n", nrow(windows_df), expected_total_windows))
cat(sprintf("Deviation: %+d windows (%.1f%%)\n",
            nrow(windows_df) - expected_total_windows,
            (nrow(windows_df) - expected_total_windows) / expected_total_windows * 100))

cat("\n✅ Module tracing complete\n\n")
