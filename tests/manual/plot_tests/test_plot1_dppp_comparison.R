# =============================================================================
# Test Plot 1: DPPP Distribution Comparison
# =============================================================================

library(arrow)
library(dplyr)
library(ggplot2)
library(tidyr)

source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/visualization.R")
source("R/config_loader.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          Test Plot 1: DPPP Comparison                         ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load configuration
config <- load_optimization_config("config/test_config.json")

# Run Stage 1
cat("Stage 1: Data Validation\n")
validated_data <- create_validated_dataset(
  proteome_file = "data/30min_report.parquet",
  apply_quality_filters = TRUE
)
cat(sprintf("✅ %s precursors validated\n\n", format(nrow(validated_data$data), big.mark = ",")))

# Run Stage 2
cat("Stage 2: Optimization Planning\n")
optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,  # Changed to 2.0 sec for better visualization
  instrument_preset = config$instrument$preset,
  target_dppp = config$dppp_parameters$target_dppp,
  target_satisfaction = config$dppp_parameters$target_satisfaction,
  dppp_tolerance = 0.0,
  load_factor = config$scan_settings$load_factor,
  ms1_scans_per_cycle = config$scan_settings$ms1_scans_per_cycle
)
cat(sprintf("✅ Recommended cycle time: %.2f sec\n\n", optimization_plan$required_cycle_time_sec))

# Generate Plot 1
cat("Generating Plot 1: DPPP Comparison\n")
cat("─────────────────────────────────────────────────────────────\n")

plot1 <- plot_dppp_comparison(optimization_plan, validated_data)

# Save plot
output_dir <- "test_plots"
dir.create(output_dir, showWarnings = FALSE)
output_file <- file.path(output_dir, "plot1_dppp_comparison.png")

ggsave(
  filename = output_file,
  plot = plot1,
  width = 12,
  height = 8,
  dpi = 300
)

cat(sprintf("✅ Plot saved: %s\n", output_file))
cat(sprintf("   File size: %.1f KB\n", file.info(output_file)$size / 1024))

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    TEST COMPLETE                               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Visual inspection checklist:\n")
cat("  [ ] Two density curves visible (blue + coral)\n")
cat("  [ ] Target DPPP line (black dashed) present\n")
cat("  [ ] Annotation box with formula and statistics\n")
cat("  [ ] Legend shows current vs recommended cycle time\n")
cat("  [ ] Curves show shift toward higher DPPP\n")
cat("\n")
