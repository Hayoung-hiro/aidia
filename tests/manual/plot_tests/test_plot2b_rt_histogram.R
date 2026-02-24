# test_plot_rt_histogram.R
# Test Plot 2B: RT Distribution Histogram (Supplementary to Density Heatmap)
#
# Purpose: Generate RT distribution histograms to complement the density heatmap

library(dplyr)
library(ggplot2)
library(arrow)

# Load modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/plot_rt_histogram.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Test Plot 2B: RT Distribution Histogram                     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Stage 1: Data Validation
# =============================================================================

cat("Stage 1: Loading validated data...\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)
cat(sprintf("✅ %s precursors\n\n", format(nrow(validated_data$data), big.mark = ",")))

# =============================================================================
# Plot 2B: RT Distribution Histogram (continuous)
# =============================================================================

cat("═══════════════════════════════════════════════════════════════\n")
cat("Generating Plot 2B: RT Distribution Histogram\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Creating histogram with 50 bins...\n")

plot2b <- plot_rt_histogram(
  validated_data = validated_data,
  bins = 50
)

output_dir <- "test_plots/"
output_file <- file.path(output_dir, "plot2b_rt_histogram.png")

ggsave(
  output_file,
  plot2b,
  width = 12,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size <- file.info(output_file)$size / 1024
cat(sprintf("✅ Saved: %s (%.1f KB)\n\n", basename(output_file), file_size))

# =============================================================================
# Plot 2B (alternative): Binned Bar Chart
# =============================================================================

cat("═══════════════════════════════════════════════════════════════\n")
cat("Generating Plot 2B (binned): RT Distribution Bar Chart\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Creating bar chart with 5-minute bins...\n")

plot2b_binned_5min <- plot_rt_histogram_binned(
  validated_data = validated_data,
  bin_width_min = 5
)

output_file_5min <- file.path(output_dir, "plot2b_rt_histogram_5min.png")

ggsave(
  output_file_5min,
  plot2b_binned_5min,
  width = 12,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size_5min <- file.info(output_file_5min)$size / 1024
cat(sprintf("✅ Saved: %s (%.1f KB)\n\n", basename(output_file_5min), file_size_5min))

# Alternative: 10-minute bins
cat("Creating bar chart with 10-minute bins...\n")

plot2b_binned_10min <- plot_rt_histogram_binned(
  validated_data = validated_data,
  bin_width_min = 10
)

output_file_10min <- file.path(output_dir, "plot2b_rt_histogram_10min.png")

ggsave(
  output_file_10min,
  plot2b_binned_10min,
  width = 12,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size_10min <- file.info(output_file_10min)$size / 1024
cat(sprintf("✅ Saved: %s (%.1f KB)\n\n", basename(output_file_10min), file_size_10min))

# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║           PLOT 2B TEST COMPLETE                                ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Generated Files:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat(sprintf("  ✅ plot2b_rt_histogram.png (%.1f KB)\n", file_size))
cat(sprintf("  ✅ plot2b_rt_histogram_5min.png (%.1f KB)\n", file_size_5min))
cat(sprintf("  ✅ plot2b_rt_histogram_10min.png (%.1f KB)\n", file_size_10min))

cat("\n")
cat("Output Directory:\n")
cat(sprintf("  %s\n", output_dir))

cat("\n")
cat("Plot Descriptions:\n")
cat("─────────────────────────────────────────────────────────────────\n")
cat("  Plot 2B (histogram): Continuous RT distribution\n")
cat("    - Blue bars: Precursor counts per bin\n")
cat("    - Yellow highlight: Peak elution region\n")
cat("    - Dashed line: Median RT\n")
cat("    - Dotted line: Mean RT\n")
cat("    - Shows: Temporal precursor elution pattern\n")
cat("\n")
cat("  Plot 2B (5-min bins): Discrete time intervals\n")
cat("    - Blue bars: Precursor counts per 5-min bin\n")
cat("    - Coral bar: Peak elution bin\n")
cat("    - Labels: Percentage of total precursors\n")
cat("    - Shows: Time-binned distribution with statistics\n")
cat("\n")
cat("  Plot 2B (10-min bins): Coarser time intervals\n")
cat("    - Same as 5-min but with 10-minute bins\n")
cat("    - Better for overview of broad elution patterns\n")
cat("\n")

cat("✅ All RT distribution plots generated successfully!\n")
cat("\n")
