# Publication Figure 1: DPPP Comparison (8cm × 4cm, no legend)

library(ggplot2)
library(dplyr)

source("R/utils_common.R")
source("R/instrument_utils.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/visualization.R")

OUTPUT_DIR <- "publication_ready"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

cm_to_inch <- function(cm) cm / 2.54

cat("Loading data...\n")

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

cat("\nGenerating Figure 1...\n")

plot1b <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)

plot1b_pub <- plot1b +
  theme(legend.position = "none")

ggsave(
  filename = file.path(OUTPUT_DIR, "Figure1_DPPP_comparison.png"),
  plot = plot1b_pub,
  width = cm_to_inch(8),
  height = cm_to_inch(4),
  dpi = 300,
  bg = "white"
)

cat("✅ Figure 1 saved\n")
