# Test Plot 1 with 90min_report.parquet

library(arrow)
library(dplyr)
library(ggplot2)
library(jsonlite)

# Source modules
source("R/utils_common.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/visualization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          Test Plot 1: DPPP Comparison (90min)                ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load configuration
config_path <- "config/test_config.json"
cat(sprintf("Loading configuration: %s\n", config_path))
config <- fromJSON(config_path)
cat("✅ Configuration loaded and validated successfully\n\n")

# ===========================================================================
# Stage 1: Data Validation
# ===========================================================================
cat("Stage 1: Data Validation\n\n")

validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",  # Changed to 90min
  apply_quality_filters = TRUE
)

cat(sprintf("✅ %s precursors validated\n\n", format(nrow(validated_data$data), big.mark = ",")))

# ===========================================================================
# Stage 2: Optimization Planning
# ===========================================================================
cat("Stage 2: Optimization Planning\n\n")

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,  # Current state
  instrument_preset = config$instrument$preset,
  target_dppp = config$dppp_parameters$target_dppp,
  target_satisfaction = config$dppp_parameters$target_satisfaction,
  dppp_tolerance = 0.0,
  load_factor = config$scan_settings$load_factor,
  ms1_scans_per_cycle = config$scan_settings$ms1_scans_per_cycle
)

cat(sprintf("✅ Recommended cycle time: %.2f sec\n\n", optimization_plan$required_cycle_time_sec))

# ===========================================================================
# Generate Plot 1
# ===========================================================================
cat("Generating Plot 1: DPPP Comparison (90min dataset)\n")
cat("─────────────────────────────────────────────────────────────\n")

# Create output directory
dir.create("test_plots", showWarnings = FALSE)

# Generate plot
plot1 <- plot_dppp_comparison(optimization_plan, validated_data)

# Save plot
output_file <- "test_plots/plot1_dppp_comparison_90min.png"
ggsave(
  filename = output_file,
  plot = plot1,
  width = 12,
  height = 8,
  dpi = 300,
  bg = "white"
)

file_size <- file.info(output_file)$size / 1024
cat(sprintf("✅ Plot saved: %s\n", output_file))
cat(sprintf("   File size: %.1f KB\n\n", file_size))

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    TEST COMPLETE                               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("90min Dataset Results:\n")
cat(sprintf("  Current (2.0 sec): %.1f%% satisfaction\n",
            optimization_plan$diagnosis$current_satisfaction_ratio * 100))
cat(sprintf("  Recommended (%.2f sec): %.1f%%+ satisfaction\n",
            optimization_plan$required_cycle_time_sec,
            optimization_plan$parameters$target_satisfaction * 100))
cat("\n")
