# Publication Figures 3 & 4 (Simple approach)

library(ggplot2)
library(dplyr)
library(gridExtra)

source("R/utils_common.R")
source("R/instrument_utils.R")
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/stage3_window_optimization.R")

OUTPUT_DIR <- "publication_ready"
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

windows_greedy <- optimize_windows(
  validated_data, optimization_plan,
  rt_bin_width_min = 5, mz_strategy = "greedy", window_mode = "density",
  smoothing_window = 3, polynomial_order = 2
)

cat("\n=== Figure 3: Custom 2x1 Grid ===\n")

# Simple m/z density plot
plot3_simple <- ggplot(validated_data$data, aes(x = Precursor.Mz)) +
  geom_density(fill = "steelblue", alpha = 0.6) +
  labs(title = "(A) Global m/z Distribution",
       x = "m/z (Da)", y = "Density") +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 9, face = "bold"),
    axis.title = element_text(size = 8),
    axis.text = element_text(size = 7)
  )

# Excluded regions plot
excluded_data <- validated_data$data %>%
  mutate(
    in_range = Precursor.Mz >= min(windows_greedy$mz_optimization$mz_ranges$mz_min) &
               Precursor.Mz <= max(windows_greedy$mz_optimization$mz_ranges$mz_max)
  )

plot3_excluded <- ggplot(excluded_data, aes(x = Precursor.Mz, fill = in_range)) +
  geom_histogram(bins = 100, alpha = 0.7) +
  scale_fill_manual(values = c("TRUE" = "steelblue", "FALSE" = "red")) +
  labs(title = "(B) Greedy Strategy - Coverage",
       x = "m/z (Da)", y = "Count", fill = "In Range") +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 9, face = "bold"),
    axis.title = element_text(size = 8),
    axis.text = element_text(size = 7),
    legend.position = "top",
    legend.title = element_text(size = 7),
    legend.text = element_text(size = 6)
  )

fig3 <- grid.arrange(plot3_simple, plot3_excluded, nrow = 2)

ggsave(
  file.path(OUTPUT_DIR, "Figure3_mz_optimization.png"),
  fig3, width = cm_to_inch(8), height = cm_to_inch(4.5),
  dpi = 300, bg = "white"
)

cat("✅ Figure3_mz_optimization.png\n\n")

# =============================================================================
# Figure 4: Window Width Distribution (adjusted scale)
# =============================================================================

cat("=== Figure 4: Window Width Distribution ===\n")

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

ggsave(
  file.path(OUTPUT_DIR, "Figure4_window_width.png"),
  plot4, width = cm_to_inch(8), height = cm_to_inch(4),
  dpi = 300, bg = "white"
)

cat("✅ Figure4_window_width.png\n\n")

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║              All Publication Figures Complete!                 ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("Output files in publication_ready/:\n")
cat("  ├── Figure1_DPPP_comparison.png (8 × 4 cm, 300 dpi)\n")
cat("  ├── Figure2_coverage_map.png (8 × 4.5 cm, 300 dpi)\n")
cat("  ├── Figure3_mz_optimization.png (8 × 4.5 cm, 300 dpi)\n")
cat("  └── Figure4_window_width.png (8 × 4 cm, 300 dpi)\n\n")
