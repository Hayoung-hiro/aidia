# test_plot4_only.R
# Test Plot 4: RT Window Size Distribution

library(dplyr)
library(ggplot2)
library(arrow)

# Load modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║         Test Plot 4: RT Window Size Distribution              ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Stage 1: Load validated data
cat("Stage 1: Loading validated data...\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)
cat(sprintf("✅ %s precursors\n\n", format(nrow(validated_data$data), big.mark = ",")))

# Stage 2: Create optimization plan
cat("Stage 2: Creating optimization plan...\n")
optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,
  target_satisfaction = 0.70,
  target_dppp = 7.0,
  instrument_preset = "fusion_lumos"
)
cat(sprintf("✅ Window count: %d per RT bin\n\n", optimization_plan$n_windows))

# Stage 3: Generate optimized windows
cat("Stage 3: Generating optimized windows...\n")
optimized_windows <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "quantile",
  window_mode = "variable",
  quantile_lower = 0.05,
  quantile_upper = 0.95
)
cat(sprintf("✅ %d windows across %d RT bins\n\n",
            nrow(optimized_windows$windows),
            optimized_windows$rt_binning$n_bins))

# Generate Plot 4
cat("Generating Plot 4: RT Window Size Distribution...\n")
plot4 <- plot_rt_window_size(optimized_windows)

# Save plot
output_dir <- "test_plots/"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

output_file <- file.path(output_dir, "plot4_rt_window_size_test.png")

ggsave(
  output_file,
  plot4,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size <- file.info(output_file)$size / 1024

cat("\n✅ Plot 4 generated successfully!\n")
cat(sprintf("   File: %s\n", output_file))
cat(sprintf("   Size: %.1f KB\n", file_size))
cat(sprintf("   Dimensions: 10 × 7 inches @ 300 DPI\n"))

cat("\n📊 Plot 4 Details:\n")
cat("   - Type: Bar chart (window count per RT segment)\n")
cat("   - X-axis: Retention Time midpoint (min)\n")
cat("   - Y-axis: Number of Windows\n")
cat("   - Bars: Window count per RT bin (steelblue)\n")
cat("   - Labels: Count displayed on top of each bar\n")
cat(sprintf("   - RT bins: %d\n", optimized_windows$rt_binning$n_bins))
cat(sprintf("   - Total windows: %d\n", nrow(optimized_windows$windows)))
cat(sprintf("   - Mean windows per bin: %.1f\n",
            nrow(optimized_windows$windows) / optimized_windows$rt_binning$n_bins))
cat("\n")
