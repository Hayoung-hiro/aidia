# test_heatmap_simple.R - Quick heatmap test with sampling

library(arrow)
library(dplyr)
library(ggplot2)

source("R/dppp_analyzer_enhanced.R")

cat("Loading and sampling data...\n")
data_full <- read_parquet("rawfile/report.parquet")

# Sample for faster testing
set.seed(42)
data <- data_full %>% sample_n(min(100000, nrow(data_full)))
cat(sprintf("Sampled %d precursors\n", nrow(data)))

cat("\nRunning DPPP analysis...\n")
dppp_analysis <- analyze_dppp_distribution(
  data,
  scan_time = 2.0,
  target_dppp = 1.25,
  dppp_tolerance = 0.1
)

# Check data before plotting
cat("\n=== Data Check ===\n")
dppp_2d <- dppp_analysis$dppp_2d$summary %>%
  filter(n_precursors > 0, !is.na(mean_dppp))

cat(sprintf("Valid bins: %d\n", nrow(dppp_2d)))
cat(sprintf("RT range: [%.2f, %.2f]\n", min(dppp_2d$rt_center), max(dppp_2d$rt_center)))
cat(sprintf("m/z range: [%.0f, %.0f]\n", min(dppp_2d$mz_center), max(dppp_2d$mz_center)))
cat(sprintf("DPPP range: [%.2f, %.2f]\n", min(dppp_2d$mean_dppp), max(dppp_2d$mean_dppp)))

cat("\nCreating heatmap...\n")
p <- plot_dppp_heatmap_2d(dppp_analysis)

cat("Saving plot...\n")
ggsave(
  "test_output/dppp_heatmap_simple.png",
  p,
  width = 10,
  height = 8,
  dpi = 150
)

cat("\n✓ Saved: test_output/dppp_heatmap_simple.png\n")
cat("File size: ")
system("ls -lh test_output/dppp_heatmap_simple.png | awk '{print $5}'")
