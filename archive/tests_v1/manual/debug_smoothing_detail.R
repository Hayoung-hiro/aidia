# debug_smoothing_detail.R - Debug smoothing_internal function directly

library(dplyr)
library(arrow)

# Source files
source("R/utils_common.R")
source("R/stage1_data_validation.R")

# Load data
validated_data <- create_validated_dataset(
  proteome_file = "data/30min_report.parquet",
  enable_replicate_consensus = FALSE
)

precursor_data <- validated_data$data

# RT binning
rt_bin_width_min <- 5
rt_range <- range(precursor_data$RT.Start, na.rm = TRUE)
rt_breaks <- seq(from = rt_range[1], to = rt_range[2], by = rt_bin_width_min)
if (tail(rt_breaks, 1) < rt_range[2]) {
  rt_breaks <- c(rt_breaks, rt_range[2])
}

precursor_data$rt_group <- cut(
  precursor_data$RT.Start,
  breaks = rt_breaks,
  labels = FALSE,
  include.lowest = TRUE
)

rt_stats <- precursor_data %>%
  group_by(rt_group) %>%
  summarise(
    rt_start = min(RT.Start, na.rm = TRUE),
    rt_end = max(RT.Start, na.rm = TRUE),
    n_precursors = n(),
    .groups = 'drop'
  ) %>%
  mutate(rt_segment_id = rt_group)

cat("\n=== RT Stats ===\n")
print(rt_stats)

# Load smoothing utilities
source("R/smoothing_utils.R")

# Parameters
quantile_lower <- 0.05
quantile_upper <- 0.95
smoothing_window <- 7
polynomial_order <- 3

n_bins <- nrow(rt_stats)

cat("\n=== Parameters ===\n")
cat("n_bins:", n_bins, "\n")
cat("quantile_lower:", quantile_lower, "\n")
cat("quantile_upper:", quantile_upper, "\n")

# Get full RT range
rt_min <- min(precursor_data$RT.Start, na.rm = TRUE)
rt_max <- max(precursor_data$RT.Start, na.rm = TRUE)
rt_range_span <- rt_max - rt_min

cat("\nRT range:", rt_min, "-", rt_max, "(span:", rt_range_span, "min)\n")

# Fine RT sampling
rt_sampling_interval <- 0.5
rt_window_halfwidth <- max(1.0, rt_range_span / 20)

rt_points <- seq(rt_min, rt_max, by = rt_sampling_interval)
n_rt_points <- length(rt_points)

cat("RT sampling: ", n_rt_points, "points, interval:", rt_sampling_interval, "min\n")
cat("Sliding window: ±", rt_window_halfwidth, "min\n")

# Calculate m/z at each RT point
mz_min_raw <- numeric(n_rt_points)
mz_max_raw <- numeric(n_rt_points)

for (i in 1:n_rt_points) {
  rt_center <- rt_points[i]
  rt_lower <- rt_center - rt_window_halfwidth
  rt_upper <- rt_center + rt_window_halfwidth

  window_precursors <- precursor_data %>%
    filter(RT.Start >= rt_lower & RT.Start <= rt_upper)

  if (nrow(window_precursors) > 0) {
    mz_values <- window_precursors$Precursor.Mz
    mz_min_raw[i] <- quantile(mz_values, quantile_lower, na.rm = TRUE, names = FALSE)
    mz_max_raw[i] <- quantile(mz_values, quantile_upper, na.rm = TRUE, names = FALSE)
  } else {
    mz_min_raw[i] <- 400
    mz_max_raw[i] <- 1200
  }
}

cat("\nCalculated m/z at", n_rt_points, "RT points\n")
cat("m/z_min range:", min(mz_min_raw), "-", max(mz_min_raw), "Da\n")
cat("m/z_max range:", min(mz_max_raw), "-", max(mz_max_raw), "Da\n")

# Smoothing
adaptive_window <- min(smoothing_window, floor(n_rt_points * 0.7))
if (adaptive_window %% 2 == 0) adaptive_window <- adaptive_window + 1
adaptive_window <- max(3, adaptive_window)
adaptive_poly <- min(polynomial_order, adaptive_window - 2)

cat("\nSmoothing: window=", adaptive_window, ", poly_order=", adaptive_poly, "\n")

mz_min_smooth <- smooth_savgol(mz_min_raw, window_size = adaptive_window, poly_order = adaptive_poly)
mz_max_smooth <- smooth_savgol(mz_max_raw, window_size = adaptive_window, poly_order = adaptive_poly)

cat("Smoothing successful\n")

# Assign to RT bins
cat("\n=== Assigning to RT bins ===\n")

mz_ranges_list <- vector("list", n_bins)

for (i in 1:n_bins) {
  rt_bin_start <- rt_stats$rt_start[i]
  rt_bin_end <- rt_stats$rt_end[i]
  rt_bin_center <- (rt_bin_start + rt_bin_end) / 2

  cat(sprintf("\nBin %d: RT [%.2f, %.2f], center = %.2f\n",
              i, rt_bin_start, rt_bin_end, rt_bin_center))

  # Interpolate
  interpolate_at_rt <- function(rt_points, values, target_rt) {
    if (target_rt <= rt_points[1]) return(values[1])
    if (target_rt >= rt_points[length(rt_points)]) return(values[length(values)])

    idx_upper <- which(rt_points >= target_rt)[1]
    idx_lower <- idx_upper - 1

    rt_lower <- rt_points[idx_lower]
    rt_upper <- rt_points[idx_upper]
    val_lower <- values[idx_lower]
    val_upper <- values[idx_upper]

    fraction <- (target_rt - rt_lower) / (rt_upper - rt_lower)
    interpolated <- val_lower + fraction * (val_upper - val_lower)

    return(interpolated)
  }

  mz_min <- interpolate_at_rt(rt_points, mz_min_smooth, rt_bin_center)
  mz_max <- interpolate_at_rt(rt_points, mz_max_smooth, rt_bin_center)

  cat(sprintf("  Interpolated m/z: [%.1f, %.1f] (width: %.1f Da)\n",
              mz_min, mz_max, mz_max - mz_min))

  # Calculate coverage
  bin_data <- precursor_data %>%
    filter(RT.Start >= rt_bin_start & RT.Start <= rt_bin_end)

  cat(sprintf("  Bin data: %d precursors\n", nrow(bin_data)))

  if (nrow(bin_data) > 0) {
    mz_values <- bin_data$Precursor.Mz
    covered <- sum(mz_values >= mz_min & mz_values <= mz_max)
    coverage_ratio <- covered / length(mz_values)

    cat(sprintf("  Coverage: %d / %d = %.2f%%\n", covered, length(mz_values), coverage_ratio * 100))
  } else {
    covered <- 0
    coverage_ratio <- NA
  }

  mz_ranges_list[[i]] <- data.frame(
    rt_segment_id = i,
    rt_start = rt_bin_start,
    rt_end = rt_bin_end,
    mz_min = mz_min,
    mz_max = mz_max,
    mz_width = mz_max - mz_min,
    n_precursors_covered = covered,
    coverage_ratio = coverage_ratio
  )

  cat("  Created data.frame with", nrow(mz_ranges_list[[i]]), "rows\n")
}

cat("\n=== Combining with bind_rows ===\n")
cat("List length:", length(mz_ranges_list), "\n")
cat("List contents:\n")
for (i in 1:length(mz_ranges_list)) {
  cat(sprintf("  [[%d]]: %d rows, %d cols\n", i, nrow(mz_ranges_list[[i]]), ncol(mz_ranges_list[[i]])))
}

mz_ranges <- bind_rows(mz_ranges_list)

cat("\n=== Final mz_ranges ===\n")
cat("Rows:", nrow(mz_ranges), "\n")
cat("Columns:", paste(colnames(mz_ranges), collapse = ", "), "\n")
print(mz_ranges)

cat("\n=== Statistics ===\n")
cat("Mean m/z width:", mean(mz_ranges$mz_width, na.rm = TRUE), "Da\n")
cat("Mean coverage:", mean(mz_ranges$coverage_ratio, na.rm = TRUE) * 100, "%\n")
