# test_plot2_only.R
# Test Plot 2: RT × m/z Density Heatmap

library(dplyr)
library(ggplot2)
library(arrow)
library(viridis)

# Load modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/visualization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║              Test Plot 2: RT × m/z Density Heatmap             ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load validated data (using integrated test output)
cat("Loading validated data from integrated test...\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)

cat(sprintf("✅ Loaded %s precursors\n\n",
            format(nrow(validated_data$data), big.mark = ",")))

# Generate Plot 2
cat("Generating Plot 2: RT × m/z Density Heatmap...\n")
plot2 <- plot_rt_mz_density_heatmap(validated_data, bins = 50)

# Save plot
output_dir <- "test_plots/"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

output_file <- file.path(output_dir, "plot2_rt_mz_heatmap_test.png")

ggsave(
  output_file,
  plot2,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)

file_size <- file.info(output_file)$size / 1024

cat("\n✅ Plot 2 generated successfully!\n")
cat(sprintf("   File: %s\n", output_file))
cat(sprintf("   Size: %.1f KB\n", file_size))
cat(sprintf("   Dimensions: 10 × 7 inches @ 300 DPI\n"))

cat("\n📊 Plot 2 Details:\n")
cat("   - Type: 2D density heatmap\n")
cat("   - X-axis: Retention Time (min)\n")
cat("   - Y-axis: Precursor m/z (Da)\n")
cat("   - Color: Precursor density (viridis plasma)\n")
cat("   - Bins: 50 × 50\n")
cat("\n")
