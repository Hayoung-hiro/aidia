# debug_smoothing.R - Debug intermediate values in smoothing strategy

library(dplyr)
library(arrow)

# Source files
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")

# Load data
validated_data <- create_validated_dataset(
  proteome_file = "data/30min_report.parquet",
  enable_replicate_consensus = FALSE
)

# Create plan
plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 3.5,
  target_dppp = 7.0,
  instrument_preset = "astral"
)

# Extract precursor data
precursor_data <- validated_data$data

cat("\n=== Precursor Data Structure ===\n")
cat("Columns:", paste(colnames(precursor_data), collapse = ", "), "\n")
cat("Rows:", nrow(precursor_data), "\n")

# Perform RT binning
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

cat("\n=== After RT Binning ===\n")
cat("rt_group values:", unique(precursor_data$rt_group), "\n")
cat("rt_group column exists:", "rt_group" %in% colnames(precursor_data), "\n")

# RT stats
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

cat("\n=== Test Filter Methods ===\n")

# Method 1: filter by rt_group (original)
cat("\nMethod 1: filter(rt_group == 1)\n")
bin1_method1 <- precursor_data %>% filter(rt_group == 1)
cat("  Rows:", nrow(bin1_method1), "\n")

# Method 2: filter by RT range
cat("\nMethod 2: filter(RT.Start >= rt_start & RT.Start <= rt_end)\n")
rt_start_1 <- rt_stats$rt_start[1]
rt_end_1 <- rt_stats$rt_end[1]
bin1_method2 <- precursor_data %>%
  filter(RT.Start >= rt_start_1 & RT.Start <= rt_end_1)
cat("  RT range: [", rt_start_1, ",", rt_end_1, "]\n")
cat("  Rows:", nrow(bin1_method2), "\n")

# Method 3: Check if rt_group column exists
cat("\nMethod 3: Conditional check\n")
if ("rt_group" %in% colnames(precursor_data)) {
  bin1_method3 <- precursor_data %>% filter(rt_group == 1)
  cat("  rt_group exists → filter(rt_group == 1)\n")
  cat("  Rows:", nrow(bin1_method3), "\n")
} else {
  bin1_method3 <- precursor_data %>%
    filter(RT.Start >= rt_start_1 & RT.Start <= rt_end_1)
  cat("  rt_group NOT exists → filter by RT range\n")
  cat("  Rows:", nrow(bin1_method3), "\n")
}

cat("\n=== Summary ===\n")
cat("All three methods should return SAME number of rows\n")
cat("Method 1:", nrow(bin1_method1), "\n")
cat("Method 2:", nrow(bin1_method2), "\n")
cat("Method 3:", nrow(bin1_method3), "\n")
