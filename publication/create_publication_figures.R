# =============================================================================
# Create Publication-Ready Figures
# =============================================================================
#
# Purpose: Generate high-quality figures for manuscript publication
#
# Figure specifications:
#   Figure 1: plot1b_dppp_comparison (8cm x 4cm, no legend)
#   Figure 2: plot5_coverage_map_2x2 (8cm x 4.5cm)
#   Figure 3: plot3 + plot4_smoothing grid 2x1 (8cm x 4.5cm)
#   Figure 4: plot7_smoothing with adjusted variable width scale
#
# Output: publication_ready/ directory
#
# =============================================================================

library(ggplot2)
library(dplyr)
library(tidyr)
library(viridis)
library(scales)
library(gridExtra)
library(grid)
library(arrow)

# Source required modules
source("R/utils_common.R")
source("R/instrument_utils.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

# =============================================================================
# Configuration
# =============================================================================

INPUT_FILE <- "data/90min_report.parquet"
OUTPUT_DIR <- "publication_ready"
INSTRUMENT <- "fusion_lumos"
TARGET_DPPP <- 7.0
TARGET_SATISFACTION <- 0.70

# Create output directory
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║       Publication-Ready Figure Generation                     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Configuration:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat(sprintf("  Input: %s\n", INPUT_FILE))
cat(sprintf("  Output: %s/\n", OUTPUT_DIR))
cat(sprintf("  Target DPPP: %.1f\n", TARGET_DPPP))
cat(sprintf("  Satisfaction: %.0f%%\n\n", TARGET_SATISFACTION * 100))

# =============================================================================
# Run Pipeline to Generate Data
# =============================================================================

cat("Running optimization pipeline...\n")
cat("─────────────────────────────────────────────────────────────\n")

# Stage 1: Data Validation
validated_data <- create_validated_dataset(
  proteome_file = INPUT_FILE,
  apply_quality_filters = TRUE
)

# Stage 2: Optimization Planning
optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,  # 90min typical
  instrument_preset = INSTRUMENT,
  target_dppp = TARGET_DPPP,
  target_satisfaction = TARGET_SATISFACTION
)

# Stage 3: Window Optimization (Smoothing strategy only for publication)
windows_smoothing <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "smoothing",
  window_mode = "variable",
  smoothing_window = 3,
  polynomial_order = 2
)

# Also generate other strategies for comparison plots
windows_quantile <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "quantile",
  window_mode = "variable"
)

windows_outlier <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "outlier",
  window_mode = "variable"
)

windows_coverage <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = 5,
  mz_strategy = "coverage",
  window_mode = "variable"
)

windows_list <- list(
  quantile = windows_quantile,
  smoothing = windows_smoothing,
  outlier = windows_outlier,
  coverage = windows_coverage
)

cat("\n✅ Pipeline complete\n\n")

# =============================================================================
# Helper Functions
# =============================================================================

#' Convert cm to inches for ggplot2
#' @param cm Size in centimeters
#' @return Size in inches
cm_to_inch <- function(cm) {
  cm / 2.54
}

#' Save plot with exact dimensions
#' @param plot ggplot object
#' @param filename Output filename
#' @param width_cm Width in cm
#' @param height_cm Height in cm
#' @param dpi Resolution (default: 300)
save_publication_plot <- function(plot, filename, width_cm, height_cm, dpi = 300) {
  width_inch <- cm_to_inch(width_cm)
  height_inch <- cm_to_inch(height_cm)

  filepath <- file.path(OUTPUT_DIR, filename)

  ggsave(
    filename = filepath,
    plot = plot,
    width = width_inch,
    height = height_inch,
    dpi = dpi,
    units = "in",
    bg = "white"
  )

  cat(sprintf("  ✅ Saved: %s (%.1f x %.1f cm, %d dpi)\n",
              filename, width_cm, height_cm, dpi))
}

# =============================================================================
# Figure 1: DPPP Comparison (8cm x 4cm, NO LEGEND)
# =============================================================================

cat("\nFigure 1: DPPP Distribution Comparison\n")
cat("─────────────────────────────────────────────────────────────\n")

# Use existing plot function and modify
source("R/stage4_visualization.R")

# Generate base plot
plot1b <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)

# Remove legend and adjust for publication
plot1b_pub <- plot1b +
  theme(legend.position = "none") +  # Remove legend
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 10),
    plot.subtitle = element_text(size = 8),
    axis.title = element_text(size = 9),
    axis.text = element_text(size = 8),
    panel.grid.minor = element_blank(),
    plot.margin = margin(5, 5, 5, 5, "pt")
  )

save_publication_plot(plot1b_pub, "Figure1_DPPP_comparison.png",
                     width_cm = 8, height_cm = 4)

# =============================================================================
# Figure 2: Coverage Map 2x2 (8cm x 4.5cm)
# =============================================================================

cat("\nFigure 2: Coverage Map 2×2 Grid\n")
cat("─────────────────────────────────────────────────────────────\n")

# Source plot5 function
if (file.exists("R/plot5_density_with_mz_ranges.R")) {
  source("R/plot5_density_with_mz_ranges.R")
}

# Generate coverage map
plot5 <- plot_coverage_map_2x2(
  validated_data = validated_data,
  windows_list = windows_list
)

# Adjust for publication size
plot5_pub <- plot5 +
  theme(
    strip.text = element_text(size = 8, face = "bold"),
    axis.title = element_text(size = 8),
    axis.text = element_text(size = 7),
    plot.title = element_text(size = 10, face = "bold"),
    legend.title = element_text(size = 8),
    legend.text = element_text(size = 7),
    plot.margin = margin(5, 5, 5, 5, "pt")
  )

save_publication_plot(plot5_pub, "Figure2_coverage_map_2x2.png",
                     width_cm = 8, height_cm = 4.5)

# =============================================================================
# Figure 3: plot3 + plot4_smoothing Grid 2x1 (8cm x 4.5cm)
# =============================================================================

cat("\nFigure 3: m/z Density + Smoothing Optimization (2×1 Grid)\n")
cat("─────────────────────────────────────────────────────────────\n")

# Generate plot3: m/z density overlay
plot3 <- plot_mz_density_overlay(
  validated_data = validated_data,
  optimized_windows = windows_smoothing
)

# Adjust for grid layout
plot3_pub <- plot3 +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 9, face = "bold"),
    axis.title = element_text(size = 8),
    axis.text = element_text(size = 7),
    legend.title = element_text(size = 8),
    legend.text = element_text(size = 7),
    legend.position = "top",
    plot.margin = margin(5, 5, 5, 5, "pt")
  ) +
  labs(title = "(A) m/z Density by RT Segment")

# Generate plot4: smoothing m/z excluded
if (file.exists("R/plot4_mz_distribution_excluded.R")) {
  source("R/plot4_mz_distribution_excluded.R")
}

plot4_smoothing <- plot_mz_distribution_excluded(
  validated_data = validated_data,
  optimized_windows = windows_smoothing,
  strategy_name = "smoothing"
)

# Adjust for grid layout
plot4_pub <- plot4_smoothing +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 9, face = "bold"),
    axis.title = element_text(size = 8),
    axis.text = element_text(size = 7),
    legend.position = "none",
    plot.margin = margin(5, 5, 5, 5, "pt")
  ) +
  labs(title = "(B) Smoothing Strategy - Excluded Precursors")

# Combine into 2x1 grid
figure3_combined <- grid.arrange(
  plot3_pub,
  plot4_pub,
  nrow = 2,
  heights = c(1, 1)
)

save_publication_plot(figure3_combined, "Figure3_mz_density_optimization.png",
                     width_cm = 8, height_cm = 4.5)

# =============================================================================
# Figure 4: plot7_smoothing with Adjusted Variable Width Scale
# =============================================================================

cat("\nFigure 4: Window Width Distribution (Adjusted Scale)\n")
cat("─────────────────────────────────────────────────────────────\n")

# Source plot7 function
if (file.exists("R/plot7_window_width_distribution.R")) {
  source("R/plot7_window_width_distribution.R")
}

# Create adjusted version of plot7
plot_window_width_adjusted <- function(optimized_windows, strategy_name = "smoothing") {

  windows <- optimized_windows$windows

  # Prepare data
  plot_data <- windows %>%
    mutate(
      rt_segment = factor(rt_segment_id),
      window_width = window_width
    )

  # Calculate density and variable width on same scale
  density_max <- max(density(plot_data$window_width)$y)

  # Get variable mode widths per RT segment
  segment_widths <- plot_data %>%
    group_by(rt_segment) %>%
    summarise(
      rt_center = mean(c(rt_start[1], rt_end[1])),
      n_windows = n(),
      .groups = "drop"
    )

  # Calculate density for each RT segment
  segment_densities <- plot_data %>%
    group_by(rt_segment) %>%
    summarise(
      density_scale = n() / sum(plot_data$n_precursors) * density_max,
      .groups = "drop"
    )

  segment_widths <- segment_widths %>%
    left_join(segment_densities, by = "rt_segment")

  # Create plot
  p <- ggplot(plot_data, aes(x = window_width)) +
    # Density curve (gray)
    geom_density(
      fill = "gray80",
      color = "gray40",
      alpha = 0.6,
      linewidth = 0.8
    ) +
    # Variable width bars - ADJUSTED TO DENSITY SCALE
    geom_point(
      data = segment_widths,
      aes(x = n_windows, y = density_scale),
      color = "#FF8C00",  # Dark orange
      size = 2,
      alpha = 0.8
    ) +
    geom_segment(
      data = segment_widths,
      aes(x = n_windows, xend = n_windows, y = 0, yend = density_scale),
      color = "#FF8C00",
      linewidth = 1.5,
      alpha = 0.7
    ) +
    scale_x_continuous(
      name = "Window Width (Da)",
      breaks = seq(0, 100, 5)
    ) +
    scale_y_continuous(
      name = "Density",
      expand = expansion(mult = c(0, 0.05))
    ) +
    labs(
      title = sprintf("Window Width Distribution - %s Strategy",
                      tools::toTitleCase(strategy_name))
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 10, face = "bold"),
      axis.title = element_text(size = 9),
      axis.text = element_text(size = 8),
      panel.grid.minor = element_blank(),
      plot.margin = margin(5, 5, 5, 5, "pt")
    )

  return(p)
}

# Generate adjusted plot7
plot7_adjusted <- plot_window_width_adjusted(
  optimized_windows = windows_smoothing,
  strategy_name = "smoothing"
)

save_publication_plot(plot7_adjusted, "Figure4_window_width_adjusted.png",
                     width_cm = 8, height_cm = 4)

# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║              Publication Figures Complete                      ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Output files:\n")
cat("─────────────────────────────────────────────────────────────\n")
cat(sprintf("  %s/\n", OUTPUT_DIR))
cat("    ├── Figure1_DPPP_comparison.png (8 × 4 cm)\n")
cat("    ├── Figure2_coverage_map_2x2.png (8 × 4.5 cm)\n")
cat("    ├── Figure3_mz_density_optimization.png (8 × 4.5 cm)\n")
cat("    └── Figure4_window_width_adjusted.png (8 × 4 cm)\n")
cat("\n")

cat("All figures generated at 300 dpi for publication quality\n")
cat("Ready for manuscript submission!\n\n")
