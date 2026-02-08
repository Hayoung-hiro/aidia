# Report.parquet Analysis Script
# Analyze DPPP distribution with scan_time = 2 seconds

# Load required libraries
library(arrow)
library(dplyr)
library(ggplot2)
library(scales)

# Load data_loader functions
source("R/data_loader.R")

# Load report.parquet
cat("Loading report.parquet...\n")
data <- load_diann_data("report.parquet", apply_quality_filters = TRUE)

# Set scan time (cycle time) to 2 seconds
scan_time_sec <- 2.0
scan_time_min <- scan_time_sec / 60  # Convert to minutes

cat(sprintf("\nUsing scan time: %.1f seconds (%.3f minutes)\n", scan_time_sec, scan_time_min))

# Calculate DPPP using the formula: DPPP = (1.7 × FWHM_minutes) / cycle_time_minutes
# Following Spectronaut standard where peak width = 1.7 × FWHM
data <- data %>%
  mutate(
    DPPP = (1.7 * FWHM) / scan_time_min
  )

# Calculate statistics
fwhm_median <- median(data$FWHM, na.rm = TRUE)
fwhm_mean <- mean(data$FWHM, na.rm = TRUE)
dppp_median <- median(data$DPPP, na.rm = TRUE)
dppp_mean <- mean(data$DPPP, na.rm = TRUE)
dppp_q25 <- quantile(data$DPPP, 0.25, na.rm = TRUE)
dppp_q75 <- quantile(data$DPPP, 0.75, na.rm = TRUE)

# Print summary statistics
cat("\n=== DPPP Analysis Summary ===\n")
cat(sprintf("Total precursors analyzed: %d\n", nrow(data)))
cat(sprintf("FWHM (minutes):\n"))
cat(sprintf("  Median: %.3f (%.1f seconds)\n", fwhm_median, fwhm_median * 60))
cat(sprintf("  Mean: %.3f (%.1f seconds)\n", fwhm_mean, fwhm_mean * 60))
cat(sprintf("DPPP distribution:\n"))
cat(sprintf("  Median: %.2f\n", dppp_median))
cat(sprintf("  Mean: %.2f\n", dppp_mean))
cat(sprintf("  Q25-Q75: %.2f - %.2f\n", dppp_q25, dppp_q75))

# Create density plot
cat("\nCreating DPPP density plot...\n")

p <- ggplot(data, aes(x = DPPP)) +
  geom_density(fill = "steelblue", alpha = 0.7, color = "darkblue", size = 1) +
  geom_vline(xintercept = dppp_median, color = "red", linetype = "dashed", size = 1) +
  geom_vline(xintercept = dppp_mean, color = "orange", linetype = "dotted", size = 1) +

  # Add annotations
  annotate("text", x = dppp_median, y = Inf,
           label = sprintf("Median DPPP: %.2f", dppp_median),
           hjust = -0.1, vjust = 1.2, color = "red", size = 4, fontface = "bold") +

  annotate("text", x = max(data$DPPP, na.rm = TRUE) * 0.7, y = Inf,
           label = sprintf("Median FWHM: %.3f min (%.1f sec)", fwhm_median, fwhm_median * 60),
           hjust = 0, vjust = 2.5, color = "black", size = 4, fontface = "bold") +

  annotate("text", x = max(data$DPPP, na.rm = TRUE) * 0.7, y = Inf,
           label = sprintf("Scan Time: %.1f sec", scan_time_sec),
           hjust = 0, vjust = 4, color = "black", size = 4) +

  annotate("text", x = max(data$DPPP, na.rm = TRUE) * 0.7, y = Inf,
           label = sprintf("N = %s precursors", format(nrow(data), big.mark = ",")),
           hjust = 0, vjust = 5.5, color = "black", size = 3.5) +

  # Styling
  labs(
    title = "DPPP Distribution Analysis",
    subtitle = "Data Points Per Peak (DPPP) = (1.7 × FWHM) / Cycle Time",
    x = "DPPP (Data Points Per Peak)",
    y = "Density",
    caption = "Red dashed line: Median DPPP | Orange dotted line: Mean DPPP"
  ) +

  theme_minimal() +
  theme(
    plot.title = element_text(size = 16, face = "bold"),
    plot.subtitle = element_text(size = 12, color = "gray60"),
    axis.title = element_text(size = 12, face = "bold"),
    axis.text = element_text(size = 10),
    plot.caption = element_text(size = 9, color = "gray50")
  ) +

  scale_x_continuous(breaks = pretty_breaks(n = 8)) +
  scale_y_continuous(labels = comma_format())

# Save plot
ggsave("dppp_density_plot.png", p, width = 12, height = 8, dpi = 300)
cat("Plot saved as: dppp_density_plot.png\n")

# Additional analysis: DPPP by RT segments
cat("\n=== DPPP by RT Segments ===\n")
data <- data %>%
  mutate(
    RT_segment = cut(RT.Start,
                    breaks = 5,
                    labels = paste("Segment", 1:5),
                    include.lowest = TRUE)
  )

rt_summary <- data %>%
  group_by(RT_segment) %>%
  summarise(
    n_precursors = n(),
    median_fwhm = median(FWHM, na.rm = TRUE),
    median_dppp = median(DPPP, na.rm = TRUE),
    mean_dppp = mean(DPPP, na.rm = TRUE),
    .groups = "drop"
  )

print(rt_summary)

# Create RT segment plot
p_rt <- ggplot(data, aes(x = RT_segment, y = DPPP)) +
  geom_boxplot(fill = "lightblue", alpha = 0.7) +
  geom_hline(yintercept = dppp_median, color = "red", linetype = "dashed") +

  labs(
    title = "DPPP Distribution Across RT Segments",
    x = "Retention Time Segments",
    y = "DPPP (Data Points Per Peak)",
    caption = "Red dashed line: Overall Median DPPP"
  ) +

  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    axis.title = element_text(size = 12, face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

ggsave("dppp_rt_segments.png", p_rt, width = 10, height = 6, dpi = 300)
cat("RT segment plot saved as: dppp_rt_segments.png\n")

cat("\n=== Analysis Complete ===\n")
cat("Files generated:\n")
cat("- dppp_density_plot.png: Main DPPP density distribution\n")
cat("- dppp_rt_segments.png: DPPP distribution across RT segments\n")