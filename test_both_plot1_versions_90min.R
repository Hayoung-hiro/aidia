# Test Both Plot 1 Versions (Simple + Enhanced) with 90min dataset

library(arrow)
library(dplyr)
library(ggplot2)
library(jsonlite)

# Source modules
source("R/utils_common.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage4_visualization.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║     Test Both Plot 1 Versions: Simple + Enhanced (90min)     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Load configuration
config_path <- "config/test_config.json"
cat(sprintf("Loading configuration: %s\n", config_path))
config <- fromJSON(config_path)
cat("✅ Configuration loaded successfully\n\n")

# ===========================================================================
# Stage 1: Data Validation
# ===========================================================================
cat("Stage 1: Data Validation\n\n")

validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)

cat(sprintf("✅ %s precursors validated\n\n", format(nrow(validated_data$data), big.mark = ",")))

# ===========================================================================
# Stage 2: Optimization Planning
# ===========================================================================
cat("Stage 2: Optimization Planning\n\n")

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,
  instrument_preset = config$instrument$preset,
  target_dppp = config$dppp_parameters$target_dppp,
  target_satisfaction = config$dppp_parameters$target_satisfaction,
  dppp_tolerance = 0.0,
  load_factor = config$scan_settings$load_factor,
  ms1_scans_per_cycle = config$scan_settings$ms1_scans_per_cycle
)

cat(sprintf("✅ Recommended cycle time: %.2f sec\n\n", optimization_plan$required_cycle_time_sec))

# ===========================================================================
# Generate Both Plot 1 Versions
# ===========================================================================
cat("Generating Both Plot 1 Versions\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# Create output directory
dir.create("test_plots", showWarnings = FALSE)

# Version 1: Simple
cat("1. Simple Version (Clean, Minimal)\n")
cat("   ─────────────────────────────────────────────────────────────\n")
plot1_simple <- plot_dppp_comparison(optimization_plan, validated_data)

output_simple <- "test_plots/plot1_simple_90min.png"
ggsave(
  filename = output_simple,
  plot = plot1_simple,
  width = 12,
  height = 8,
  dpi = 300,
  bg = "white"
)

size_simple <- file.info(output_simple)$size / 1024
cat(sprintf("   ✅ Simple version saved: %s (%.1f KB)\n\n", output_simple, size_simple))

# Version 2: Enhanced
cat("2. Enhanced Version (With Visual Annotations)\n")
cat("   ─────────────────────────────────────────────────────────────\n")
plot1_enhanced <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)

output_enhanced <- "test_plots/plot1_enhanced_90min.png"
ggsave(
  filename = output_enhanced,
  plot = plot1_enhanced,
  width = 12,
  height = 8,
  dpi = 300,
  bg = "white"
)

size_enhanced <- file.info(output_enhanced)$size / 1024
cat(sprintf("   ✅ Enhanced version saved: %s (%.1f KB)\n\n", output_enhanced, size_enhanced))

# ===========================================================================
# Summary
# ===========================================================================
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    DUAL PLOT GENERATION COMPLETE               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Plot 1 Output Files:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat(sprintf("  📊 Simple:   %s (%.1f KB)\n", output_simple, size_simple))
cat(sprintf("  📊 Enhanced: %s (%.1f KB)\n\n", output_enhanced, size_enhanced))

cat("Feature Comparison:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat("  Simple Version:\n")
cat("    ✓ Dual density curves\n")
cat("    ✓ Target DPPP line\n")
cat("    ✓ Basic statistics annotation\n")
cat("    ✓ Clean, minimal design\n")
cat("    → Best for: Quick overview, presentations\n\n")

cat("  Enhanced Version:\n")
cat("    ✓ Everything from Simple +\n")
cat("    ✓ Target satisfied region (green zone)\n")
cat("    ✓ Median DPPP lines (current + recommended)\n")
cat("    ✓ DPPP shift arrow with improvement value\n")
cat("    ✓ Extended statistics (median DPPP, improvement)\n")
cat("    → Best for: Detailed analysis, reports\n\n")

cat("Recommendation:\n")
cat("  • Use BOTH versions in pipeline output\n")
cat("  • Simple for quick reference\n")
cat("  • Enhanced for in-depth understanding\n")
cat("\n")
