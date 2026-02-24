# Publication Figures with 16:9 Aspect Ratio
# No fixed cm sizing - let ggplot2 handle dimensions naturally

library(ggplot2)
library(dplyr)
library(gridExtra)

source("R/utils_common.R")
source("R/instrument_utils.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/visualization.R")
source("R/plot_density_overlay.R")

OUTPUT_DIR <- "publication_ready"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║        Publication Figures Generation (16:9 Ratio)            ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# =============================================================================
# Data Loading
# =============================================================================

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

# Generate all 4 strategies
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

# =============================================================================
# Figure 1: DPPP Comparison (16:9, no legend)
# =============================================================================

cat("\n=== Figure 1: DPPP Comparison ===\n")

plot1b <- plot_dppp_comparison_enhanced(optimization_plan, validated_data)

plot1b_pub <- plot1b +
  theme(
    legend.position = "none",
    aspect.ratio = 9/16  # 16:9 ratio
  )

ggsave(
  filename = file.path(OUTPUT_DIR, "Figure1_DPPP_comparison.png"),
  plot = plot1b_pub,
  width = 16,
  height = 9,
  dpi = 300,
  bg = "white"
)

cat("✅ Figure1_DPPP_comparison.png (16:9 ratio)\n")

# =============================================================================
# Figure 2: Coverage Map 2x2 (16:9)
# =============================================================================

cat("\n=== Figure 2: Coverage Map 2x2 ===\n")

plot5 <- plot_density_with_mz_ranges_grid(windows_list, validated_data, bins = 50)

# For grid objects, we save directly
ggsave(
  filename = file.path(OUTPUT_DIR, "Figure2_coverage_map.png"),
  plot = plot5,
  width = 16,
  height = 9,
  dpi = 300,
  bg = "white"
)

cat("✅ Figure2_coverage_map.png (16:9 ratio)\n")

# =============================================================================
# Figure 3: m/z Distribution 2x1 Grid (16:9)
# =============================================================================

cat("\n=== Figure 3: m/z Distribution 2x1 Grid ===\n")

# Panel A: Global m/z density
plot3a <- ggplot(validated_data$data, aes(x = Precursor.Mz)) +
  geom_density(fill = "steelblue", alpha = 0.6, linewidth = 0.8) +
  labs(
    title = "(A) Global m/z Distribution",
    x = "m/z (Da)",
    y = "Density"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 11, face = "bold"),
    axis.title = element_text(size = 10),
    axis.text = element_text(size = 9),
    aspect.ratio = 9/16
  )

# Panel B: Excluded regions
excluded_data <- validated_data$data %>%
  mutate(
    in_range = Precursor.Mz >= min(windows_greedy$mz_optimization$mz_ranges$mz_min) &
               Precursor.Mz <= max(windows_greedy$mz_optimization$mz_ranges$mz_max)
  )

plot3b <- ggplot(excluded_data, aes(x = Precursor.Mz, fill = in_range)) +
  geom_histogram(bins = 100, alpha = 0.7) +
  scale_fill_manual(
    values = c("TRUE" = "steelblue", "FALSE" = "red"),
    labels = c("TRUE" = "In Range", "FALSE" = "Excluded")
  ) +
  labs(
    title = "(B) Greedy Strategy - Coverage",
    x = "m/z (Da)",
    y = "Count",
    fill = ""
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 11, face = "bold"),
    axis.title = element_text(size = 10),
    axis.text = element_text(size = 9),
    legend.position = "top",
    legend.title = element_text(size = 9),
    legend.text = element_text(size = 8),
    aspect.ratio = 9/16
  )

# Combine panels
fig3 <- grid.arrange(plot3a, plot3b, nrow = 1)

ggsave(
  file.path(OUTPUT_DIR, "Figure3_mz_optimization.png"),
  fig3,
  width = 16,
  height = 9,
  dpi = 300,
  bg = "white"
)

cat("✅ Figure3_mz_optimization.png (16:9 ratio, 2x1 grid)\n")

# =============================================================================
# Figure 4: Window Width Distribution (16:9, adjusted scale)
# =============================================================================

cat("\n=== Figure 4: Window Width Distribution ===\n")

windows <- windows_greedy$windows

# Calculate density
dens <- density(windows$window_width)
dens_max <- max(dens$y)

# Segment summary
seg_data <- windows %>%
  group_by(rt_segment_id) %>%
  summarise(
    n_windows = n(),
    n_precursors = sum(n_precursors),
    .groups = "drop"
  ) %>%
  mutate(
    # Scale variable width height to match density scale
    height = (n_precursors / sum(n_precursors)) * dens_max * 1.5
  )

plot4 <- ggplot(windows, aes(x = window_width)) +
  # Density curve
  geom_density(fill = "gray80", color = "gray40", alpha = 0.6, linewidth = 0.8) +
  # Variable width bars - SCALED TO DENSITY
  geom_segment(
    data = seg_data,
    aes(x = n_windows, xend = n_windows, y = 0, yend = height),
    color = "#FF8C00", linewidth = 1.5, alpha = 0.7
  ) +
  geom_point(
    data = seg_data,
    aes(x = n_windows, y = height),
    color = "#FF8C00", size = 2.5, alpha = 0.8
  ) +
  scale_y_continuous(
    name = "Density",
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_x_continuous(name = "Window Width (Da)") +
  labs(title = "Window Width Distribution - Greedy Strategy") +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 11, face = "bold"),
    axis.title = element_text(size = 10),
    axis.text = element_text(size = 9),
    panel.grid.minor = element_blank(),
    aspect.ratio = 9/16
  )

ggsave(
  file.path(OUTPUT_DIR, "Figure4_window_width.png"),
  plot4,
  width = 16,
  height = 9,
  dpi = 300,
  bg = "white"
)

cat("✅ Figure4_window_width.png (16:9 ratio)\n")

# =============================================================================
# Summary
# =============================================================================

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║            All Publication Figures Complete (16:9)            ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Output files in publication_ready/:\n")
cat("  ├── Figure1_DPPP_comparison.png (16:9 ratio, no legend)\n")
cat("  ├── Figure2_coverage_map.png (16:9 ratio, 2×2 grid)\n")
cat("  ├── Figure3_mz_optimization.png (16:9 ratio, 2×1 grid)\n")
cat("  └── Figure4_window_width.png (16:9 ratio, adjusted scale)\n\n")

cat("All figures generated at 300 dpi for publication quality.\n")
