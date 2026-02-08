# =============================================================================
# Generate All Publication Figures
# =============================================================================

library(ggplot2)
library(dplyr)
library(tidyr)
library(gridExtra)
library(grid)
library(viridis)
library(scales)

source("R/utils_common.R")
source("R/instrument_utils.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")
source("R/stage4_visualization.R")

OUTPUT_DIR <- "publication_ready"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

cm_to_inch <- function(cm) cm / 2.54

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║       Publication Figure Generation (90min data)              ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Pipeline
# =============================================================================

cat("Step 1: Loading and validating data...\n")

validated_data <- create_validated_dataset(
  proteome_file = "data/90min_report.parquet",
  apply_quality_filters = TRUE
)

cat("\nStep 2: Optimization planning...\n")

optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = 2.0,
  instrument_preset = "fusion_lumos",
  target_dppp = 7.0,
  target_satisfaction = 0.70
)

cat("\nStep 3: Window optimization (4 strategies)...\n")

windows_quantile <- optimize_windows(
  validated_data, optimization_plan,
  rt_bin_width_min = 5, mz_strategy = "quantile", window_mode = "density"
)

windows_greedy <- optimize_windows(
  validated_data, optimization_plan,
  rt_bin_width_min = 5, mz_strategy = "greedy", window_mode = "density",
  smoothing_window = 3, polynomial_order = 2
)

windows_outlier <- optimize_windows(
  validated_data, optimization_plan,
  rt_bin_width_min = 5, mz_strategy = "outlier", window_mode = "density"
)

windows_coverage <- optimize_windows(
  validated_data, optimization_plan,
  rt_bin_width_min = 5, mz_strategy = "coverage", window_mode = "density"
)

windows_list <- list(
  quantile = windows_quantile,
  greedy = windows_greedy,
  outlier = windows_outlier,
  coverage = windows_coverage
)

cat("\n✅ Pipeline complete!\n\n")

# =============================================================================
# Figure 1: DPPP Comparison (8cm × 4cm, NO LEGEND)
# =============================================================================

cat("Generating Figure 1: DPPP Comparison...\n")

plot1b <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)
plot1b_pub <- plot1b + theme(legend.position = "none")

ggsave(
  file.path(OUTPUT_DIR, "Figure1_DPPP_comparison.png"),
  plot1b_pub, width = cm_to_inch(8), height = cm_to_inch(4),
  dpi = 300, bg = "white"
)

cat("  ✅ Figure1_DPPP_comparison.png\n\n")

# =============================================================================
# Figure 2: Coverage Map 2×2 (8cm × 4.5cm)
# =============================================================================

cat("Generating Figure 2: Coverage Map 2×2...\n")

if (file.exists("R/plots/plot5_density_with_mz_ranges.R")) {
  source("R/plots/plot5_density_with_mz_ranges.R")
}

plot5 <- plot_density_with_mz_ranges_grid(windows_list, validated_data)

ggsave(
  file.path(OUTPUT_DIR, "Figure2_coverage_map.png"),
  plot5, width = cm_to_inch(8), height = cm_to_inch(4.5),
  dpi = 300, bg = "white"
)

cat("  ✅ Figure2_coverage_map.png\n\n")

# =============================================================================
# Figure 3: Plot3 + Plot4 Grid (8cm × 4.5cm)
# =============================================================================

cat("Generating Figure 3: m/z Density + Greedy...\n")

# Plot 3: m/z density overlay
plot3 <- plot_mz_normalized_density(windows_greedy, validated_data)
plot3_pub <- plot3 +
  theme(
    plot.title = element_text(size = 9, face = "bold"),
    axis.title = element_text(size = 8),
    axis.text = element_text(size = 7),
    legend.position = "top",
    legend.title = element_text(size = 7),
    legend.text = element_text(size = 6)
  ) +
  labs(title = "(A) m/z Density by RT Segment")

# Plot 4: Greedy m/z excluded
if (file.exists("R/plots/plot4_mz_distribution_excluded.R")) {
  source("R/plots/plot4_mz_distribution_excluded.R")
}

plot4 <- plot_mz_distribution_with_exclusions(windows_greedy, validated_data)
plot4_pub <- plot4 +
  theme(
    plot.title = element_text(size = 9, face = "bold"),
    axis.title = element_text(size = 8),
    axis.text = element_text(size = 7),
    legend.position = "none"
  ) +
  labs(title = "(B) Greedy - Excluded Precursors")

# Combine
fig3 <- grid.arrange(plot3_pub, plot4_pub, nrow = 2)

ggsave(
  file.path(OUTPUT_DIR, "Figure3_mz_optimization.png"),
  fig3, width = cm_to_inch(8), height = cm_to_inch(4.5),
  dpi = 300, bg = "white"
)

cat("  ✅ Figure3_mz_optimization.png\n\n")

# =============================================================================
# Figure 4: Window Width with Adjusted Scale
# =============================================================================

cat("Generating Figure 4: Window Width Distribution (adjusted)...\n")

# Custom function with adjusted variable width scale
plot_window_width_adj <- function(optimized_windows) {

  windows <- optimized_windows$windows

  # Calculate overall density
  dens <- density(windows$window_width)
  dens_max <- max(dens$y)

  # Segment data
  seg_data <- windows %>%
    group_by(rt_segment_id) %>%
    summarise(
      n_windows = n(),
      n_precursors = sum(n_precursors),
      .groups = "drop"
    ) %>%
    mutate(
      # Scale to match density height
      height = (n_precursors / sum(n_precursors)) * dens_max * 1.2
    )

  p <- ggplot(windows, aes(x = window_width)) +
    # Density curve
    geom_density(fill = "gray80", color = "gray40", alpha = 0.6, linewidth = 0.8) +
    # Variable width bars - SCALED
    geom_segment(
      data = seg_data,
      aes(x = n_windows, xend = n_windows, y = 0, yend = height),
      color = "#FF8C00", linewidth = 1.5, alpha = 0.7
    ) +
    geom_point(
      data = seg_data,
      aes(x = n_windows, y = height),
      color = "#FF8C00", size = 2, alpha = 0.8
    ) +
    scale_y_continuous(name = "Density", expand = expansion(mult = c(0, 0.05))) +
    scale_x_continuous(name = "Window Width (Da)") +
    labs(title = "Window Width Distribution - Greedy Strategy") +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 10, face = "bold"),
      axis.title = element_text(size = 9),
      axis.text = element_text(size = 8),
      panel.grid.minor = element_blank()
    )

  return(p)
}

plot7_adj <- plot_window_width_adj(windows_greedy)

ggsave(
  file.path(OUTPUT_DIR, "Figure4_window_width.png"),
  plot7_adj, width = cm_to_inch(8), height = cm_to_inch(4),
  dpi = 300, bg = "white"
)

cat("  ✅ Figure4_window_width.png\n\n")

# =============================================================================
# Summary
# =============================================================================

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║              All Publication Figures Complete!                 ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Output files in publication_ready/:\n")
cat("  ├── Figure1_DPPP_comparison.png (8 × 4 cm)\n")
cat("  ├── Figure2_coverage_map.png (8 × 4.5 cm)\n")
cat("  ├── Figure3_mz_optimization.png (8 × 4.5 cm)\n")
cat("  └── Figure4_window_width.png (8 × 4 cm)\n\n")

cat("All figures: 300 dpi, publication-ready!\n\n")
