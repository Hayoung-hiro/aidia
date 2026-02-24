# test_plot3_only.R
# Test Plot 3: m/z Density Overlay (RT Segments)

library(dplyr)
library(ggplot2)
library(arrow)
library(viridis)

# Load modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/visualization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║         Test Plot 3: m/z Density Overlay (RT Segments)         ║\n")
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
cat(sprintf("✅ Required cycle time: %.2f sec\n\n", optimization_plan$required_cycle_time_sec))

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

# Generate Plot 3
cat("Generating Plot 3: m/z Density Overlay...\n")
plot3 <- plot_mz_normalized_density(optimized_windows, validated_data)

# Save plot
output_dir <- "test_plots/"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

output_file <- file.path(output_dir, "plot3_mz_density_overlay_test.png")

ggsave(
  output_file,
  plot3,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size <- file.info(output_file)$size / 1024

cat("\n✅ Plot 3 generated successfully!\n")
cat(sprintf("   File: %s\n", output_file))
cat(sprintf("   Size: %.1f KB\n", file_size))
cat(sprintf("   Dimensions: 10 × 7 inches @ 300 DPI\n"))

cat("\n📊 Plot 3 Details:\n")
cat("   - Type: Overlay density plot (multiple colored lines)\n")
cat("   - X-axis: Precursor m/z (Da)\n")
cat("   - Y-axis: Normalized density (0-1)\n")
cat("   - Lines: One per RT segment (colored)\n")
cat("   - Color scale: viridis turbo\n")
cat(sprintf("   - RT segments shown: ~6 (sampled from %d total)\n",
            optimized_windows$rt_binning$n_bins))
cat("\n")
cat("✅ User feedback: 'overlay가 더 명확해보여' - Already implemented!\n")
cat("\n")
