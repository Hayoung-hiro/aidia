# test_plot4_mz_range.R
# Test Plot 4: m/z Range Optimization (Original vs Optimized)

library(dplyr)
library(ggplot2)
library(tidyr)
library(arrow)

# Load modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/plot4_mz_range_optimization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║      Test Plot 4: m/z Range Optimization (Original vs Opt)    ║\n")
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
  mz_strategy = "quantile",  # Using quantile strategy (P5-P95)
  window_mode = "density",
  quantile_lower = 0.05,
  quantile_upper = 0.95
)
cat(sprintf("✅ %d windows across %d RT bins\n", nrow(optimized_windows$windows),
            optimized_windows$rt_binning$n_bins))
cat(sprintf("   m/z optimization: %s strategy\n",
            optimized_windows$mz_optimization$strategy))
cat(sprintf("   Mean m/z width: %.1f Da\n",
            optimized_windows$mz_optimization$mean_width))
cat(sprintf("   Mean coverage: %.1f%%\n\n",
            optimized_windows$mz_optimization$mean_coverage * 100))

# Generate Plot 4
cat("Generating Plot 4: m/z Range Optimization...\n")
plot4 <- plot_mz_range_optimization(optimized_windows, validated_data)

# Save plot
output_dir <- "test_plots/"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

output_file <- file.path(output_dir, "plot4_mz_range_optimization.png")

ggsave(
  output_file,
  plot4,
  width = 12,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size <- file.info(output_file)$size / 1024

cat("\n✅ Plot 4 generated successfully!\n")
cat(sprintf("   File: %s\n", output_file))
cat(sprintf("   Size: %.1f KB\n", file_size))
cat(sprintf("   Dimensions: 12 × 7 inches @ 300 DPI\n"))

cat("\n📊 Plot 4 Details:\n")
cat("   - Type: Side-by-side bar chart\n")
cat("   - X-axis: RT segment ID + range\n")
cat("   - Y-axis: m/z range width (Da)\n")
cat("   - Bars:\n")
cat("     • Gray: Original m/z range (full min-max)\n")
cat("     • Blue: Optimized m/z range (quantile 5%-95%)\n")
cat("   - Labels: Coverage % on top of optimized bars\n")
cat(sprintf("   - RT bins: %d\n", optimized_windows$rt_binning$n_bins))
cat("\n")
cat("✅ Shows m/z range reduction from Stage 3C optimization\n")
cat("\n")
