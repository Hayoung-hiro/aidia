# =============================================================================
# Quick Publication-Ready Figures (From Existing Results)
# =============================================================================
#
# Purpose: Quickly generate publication figures by loading existing data
#
# =============================================================================

library(ggplot2)
library(dplyr)
library(gridExtra)
library(grid)
library(png)

# Configuration
RESULTS_DIR <- "results_90min_visualization"
OUTPUT_DIR <- "publication_ready"

# Create output directory
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║       Quick Publication Figure Generation                     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Helper function
cm_to_inch <- function(cm) cm / 2.54

# =============================================================================
# Load saved RDS data (if available)
# =============================================================================

# Try to find the most recent results directory
if (!dir.exists(RESULTS_DIR)) {
  cat("Looking for results directories...\n")
  results_dirs <- list.dirs(".", recursive = FALSE, full.names = TRUE)
  results_dirs <- results_dirs[grepl("90min", results_dirs)]

  if (length(results_dirs) > 0) {
    RESULTS_DIR <- results_dirs[1]
    cat(sprintf("Using: %s\n\n", RESULTS_DIR))
  } else {
    stop("No 90min results directory found!")
  }
}

# =============================================================================
# Figure 1: Recreate plot1b without legend
# =============================================================================

cat("Figure 1: Loading and modifying plot1b...\n")

# Load the existing PNG and display it
existing_plot <- file.path(RESULTS_DIR, "plot1b_dppp_comparison_enhanced.png")

if (file.exists(existing_plot)) {
  # Read PNG
  img <- png::readPNG(existing_plot)

  # Create a simple grid display
  grid.newpage()
  grid.raster(img)

  # For now, we'll just copy it - we'll need the RDS data to remove legend properly
  cat("  ⚠️ Need RDS data to modify legend. Copying original for now.\n")

  # Let's try a different approach - load from source
} else {
  cat("  ❌ plot1b not found in", RESULTS_DIR, "\n")
}

cat("\n")

# =============================================================================
# Better approach: Run minimal pipeline with specific plot generation
# =============================================================================

cat("Running minimal pipeline for publication plots...\n")
cat("─────────────────────────────────────────────────────────────\n")

# Source required modules
source("R/utils_common.R")
source("R/instrument_utils.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")

# Check if we have saved data
if (file.exists("publication_ready/pipeline_data.rds")) {
  cat("Loading cached pipeline data...\n")
  cached <- readRDS("publication_ready/pipeline_data.rds")
  validated_data <- cached$validated_data
  optimization_plan <- cached$optimization_plan
  windows_greedy <- cached$windows_greedy
  windows_list <- cached$windows_list
} else {
  cat("Running fresh pipeline...\n")

  # Quick pipeline
  validated_data <- create_validated_dataset(
    proteome_file = "data/90min_report.parquet",
    apply_quality_filters = TRUE
  )

  optimization_plan <- plan_optimization(
    validated_data = validated_data,
    current_cycle_time = 2.0,
    instrument_preset = "fusion_lumos",
    target_dppp = 7.0,
    target_satisfaction = 0.70
  )

  # Greedy only (for speed)
  windows_greedy <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    rt_bin_width_min = 5,
    mz_strategy = "greedy",
    window_mode = "density",
    smoothing_window = 3,
    polynomial_order = 2
  )

  # Save for reuse
  saveRDS(list(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    windows_greedy = windows_greedy
  ), "publication_ready/pipeline_data.rds")
}

cat("✅ Data loaded\n\n")

# =============================================================================
# Figure 1: DPPP Comparison (8cm x 4cm, NO LEGEND)
# =============================================================================

cat("Generating Figure 1: DPPP Comparison (no legend)...\n")

# Source plot function
source("R/stage4_visualization.R")

# Generate plot
plot1b <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)

# Remove legend
plot1b_pub <- plot1b +
  theme(
    legend.position = "none",
    plot.title = element_text(size = 10, face = "bold"),
    plot.subtitle = element_text(size = 8),
    axis.title = element_text(size = 9),
    axis.text = element_text(size = 8),
    panel.grid.minor = element_blank()
  )

# Save
ggsave(
  filename = file.path(OUTPUT_DIR, "Figure1_DPPP_comparison.png"),
  plot = plot1b_pub,
  width = cm_to_inch(8),
  height = cm_to_inch(4),
  dpi = 300,
  units = "in",
  bg = "white"
)

cat("  ✅ Figure1_DPPP_comparison.png (8 × 4 cm)\n\n")

# =============================================================================
# Summary
# =============================================================================

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║              Publication Figure Complete                       ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat(sprintf("Output: %s/\n", OUTPUT_DIR))
cat("  ├── Figure1_DPPP_comparison.png (8 × 4 cm, 300 dpi)\n")
cat("\n")
