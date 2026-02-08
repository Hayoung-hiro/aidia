# analyze_fwhm_detailed.R - Detailed FWHM visualization by RT and Quantity

library(arrow)
library(dplyr)
library(ggplot2)
library(viridis)
library(gridExtra)

# Load data
cat("Loading DIA-NN data...\n")
data <- read_parquet("D:/Projects/DPPP_Window_isolation/DIANN-Output/report.parquet")

# Prepare data for analysis
cat("Preparing data for analysis...\n")
analysis_data <- data %>%
  filter(!is.na(FWHM), FWHM > 0, FWHM < 10,
         !is.na(RT.Start), !is.na(Precursor.Quantity)) %>%
  mutate(
    FWHM_seconds = FWHM * 60,
    RT_minutes = RT.Start,
    Log_Quantity = log10(Precursor.Quantity + 1)
  )

cat(sprintf("Analyzing %d precursors with valid data\n", nrow(analysis_data)))

# Calculate statistics
stats_summary <- analysis_data %>%
  summarise(
    n = n(),
    fwhm_median = median(FWHM_seconds),
    fwhm_mean = mean(FWHM_seconds),
    fwhm_sd = sd(FWHM_seconds),
    rt_range = paste(round(min(RT_minutes), 1), "-", round(max(RT_minutes), 1)),
    quantity_range = paste(round(min(Precursor.Quantity), 0), "-", round(max(Precursor.Quantity), 0))
  )

print(stats_summary)

# Create plots
cat("\nCreating visualizations...\n")

# 1. FWHM vs RT - Scatter plot with density
p1 <- ggplot(analysis_data %>% sample_n(min(50000, nrow(analysis_data))), 
             aes(x = RT_minutes, y = FWHM_seconds)) +
  geom_hex(bins = 50) +
  scale_fill_viridis(name = "Count", trans = "log10") +
  geom_smooth(method = "loess", color = "red", size = 1, se = TRUE) +
  labs(
    title = "FWHM Distribution Across Retention Time",
    subtitle = sprintf("n = %d precursors | Median FWHM = %.2f sec", 
                      nrow(analysis_data), stats_summary$fwhm_median),
    x = "Retention Time (minutes)",
    y = "FWHM (seconds)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(size = 11)
  )

# 2. FWHM vs Quantity - Scatter plot with density
p2 <- ggplot(analysis_data %>% sample_n(min(50000, nrow(analysis_data))), 
             aes(x = Log_Quantity, y = FWHM_seconds)) +
  geom_hex(bins = 50) +
  scale_fill_viridis(name = "Count", trans = "log10") +
  geom_smooth(method = "loess", color = "red", size = 1, se = TRUE) +
  labs(
    title = "FWHM Distribution by Signal Intensity",
    subtitle = "Log10(Quantity) vs FWHM",
    x = "Log10(Precursor Quantity)",
    y = "FWHM (seconds)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(size = 11)
  )

# 3. 2D density plot - RT vs Quantity colored by FWHM
p3 <- ggplot(analysis_data %>% sample_n(min(20000, nrow(analysis_data))), 
             aes(x = RT_minutes, y = Log_Quantity, color = FWHM_seconds)) +
  geom_point(alpha = 0.3, size = 0.5) +
  scale_color_viridis(name = "FWHM (sec)") +
  labs(
    title = "2D Distribution: RT vs Quantity (colored by FWHM)",
    x = "Retention Time (minutes)",
    y = "Log10(Precursor Quantity)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    axis.title = element_text(size = 11)
  )

# 4. Boxplot analysis by RT bins
rt_bins <- 20
analysis_data$RT_bin <- cut(analysis_data$RT_minutes, breaks = rt_bins)

p4 <- ggplot(analysis_data, aes(x = RT_bin, y = FWHM_seconds)) +
  geom_boxplot(fill = "steelblue", alpha = 0.7, outlier.alpha = 0.1) +
  geom_smooth(aes(group = 1), method = "loess", color = "red", se = FALSE) +
  labs(
    title = sprintf("FWHM Distribution Across %d RT Bins", rt_bins),
    x = "Retention Time Bins",
    y = "FWHM (seconds)"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
    plot.title = element_text(size = 14, face = "bold"),
    axis.title = element_text(size = 11)
  )

# 5. Boxplot analysis by Quantity quartiles
analysis_data$Quantity_quartile <- cut(analysis_data$Precursor.Quantity,
                                      breaks = quantile(analysis_data$Precursor.Quantity, 
                                                       probs = c(0, 0.25, 0.5, 0.75, 1)),
                                      labels = c("Q1 (Low)", "Q2", "Q3", "Q4 (High)"),
                                      include.lowest = TRUE)

p5 <- ggplot(analysis_data, aes(x = Quantity_quartile, y = FWHM_seconds, fill = Quantity_quartile)) +
  geom_boxplot(alpha = 0.7, outlier.alpha = 0.1) +
  scale_fill_viridis_d() +
  labs(
    title = "FWHM Distribution by Signal Intensity Quartiles",
    x = "Intensity Quartiles",
    y = "FWHM (seconds)"
  ) +
  theme_minimal() +
  theme(
    legend.position = "none",
    plot.title = element_text(size = 14, face = "bold"),
    axis.title = element_text(size = 11)
  )

# 6. Heatmap - RT vs Quantity bins with mean FWHM
rt_breaks <- seq(min(analysis_data$RT_minutes), max(analysis_data$RT_minutes), length.out = 21)
quantity_breaks <- quantile(analysis_data$Log_Quantity, probs = seq(0, 1, 0.1))

heatmap_data <- analysis_data %>%
  mutate(
    RT_group = cut(RT_minutes, breaks = rt_breaks, include.lowest = TRUE),
    Quantity_group = cut(Log_Quantity, breaks = quantity_breaks, include.lowest = TRUE)
  ) %>%
  group_by(RT_group, Quantity_group) %>%
  summarise(
    mean_FWHM = mean(FWHM_seconds),
    median_FWHM = median(FWHM_seconds),
    n = n(),
    .groups = 'drop'
  ) %>%
  filter(n >= 10)  # Only show bins with sufficient data

# Extract numeric values for plotting
heatmap_data$RT_mid <- as.numeric(gsub("\\((.*),.*", "\\1", heatmap_data$RT_group)) + 
                       (as.numeric(gsub(".*,(.*)\\]", "\\1", heatmap_data$RT_group)) - 
                        as.numeric(gsub("\\((.*),.*", "\\1", heatmap_data$RT_group))) / 2
heatmap_data$Quantity_mid <- as.numeric(gsub("\\((.*),.*", "\\1", heatmap_data$Quantity_group)) + 
                             (as.numeric(gsub(".*,(.*)\\]", "\\1", heatmap_data$Quantity_group)) - 
                              as.numeric(gsub("\\((.*),.*", "\\1", heatmap_data$Quantity_group))) / 2

p6 <- ggplot(heatmap_data, aes(x = RT_mid, y = Quantity_mid, fill = median_FWHM)) +
  geom_tile() +
  scale_fill_viridis(name = "Median\nFWHM (sec)") +
  labs(
    title = "FWHM Heatmap: RT vs Quantity",
    subtitle = "Median FWHM values in 2D bins",
    x = "Retention Time (minutes)",
    y = "Log10(Precursor Quantity)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(size = 11)
  )

# Save individual plots
cat("\nSaving plots...\n")
ggsave("plots/fwhm_vs_rt_density.png", p1, width = 10, height = 6, dpi = 300)
ggsave("plots/fwhm_vs_quantity_density.png", p2, width = 10, height = 6, dpi = 300)
ggsave("plots/fwhm_2d_distribution.png", p3, width = 10, height = 6, dpi = 300)
ggsave("plots/fwhm_rt_boxplot.png", p4, width = 12, height = 6, dpi = 300)
ggsave("plots/fwhm_quantity_boxplot.png", p5, width = 8, height = 6, dpi = 300)
ggsave("plots/fwhm_heatmap.png", p6, width = 10, height = 6, dpi = 300)

# Create combined plot
combined <- grid.arrange(p1, p2, p4, p5, ncol = 2, nrow = 2,
                        top = "FWHM Analysis: RT and Quantity Dependencies")
ggsave("plots/fwhm_combined_analysis.png", combined, width = 16, height = 12, dpi = 300)

# Statistical analysis
cat("\n=== Statistical Analysis ===\n")

# Correlation analysis
cor_rt <- cor(analysis_data$RT_minutes, analysis_data$FWHM_seconds, method = "spearman")
cor_quantity <- cor(analysis_data$Log_Quantity, analysis_data$FWHM_seconds, method = "spearman")

cat(sprintf("Spearman correlation - RT vs FWHM: %.3f\n", cor_rt))
cat(sprintf("Spearman correlation - Log(Quantity) vs FWHM: %.3f\n", cor_quantity))

# Linear model
lm_model <- lm(FWHM_seconds ~ RT_minutes + Log_Quantity + RT_minutes:Log_Quantity, 
               data = analysis_data)
summary_lm <- summary(lm_model)

cat("\nLinear Model Results:\n")
cat(sprintf("R-squared: %.3f\n", summary_lm$r.squared))
cat("\nCoefficients:\n")
print(summary_lm$coefficients)

# RT trend analysis
rt_trend <- analysis_data %>%
  group_by(RT_bin) %>%
  summarise(
    RT_mid = mean(RT_minutes),
    mean_FWHM = mean(FWHM_seconds),
    median_FWHM = median(FWHM_seconds),
    sd_FWHM = sd(FWHM_seconds),
    n = n()
  )

cat("\n=== RT Trend Summary ===\n")
cat(sprintf("FWHM range across RT: %.2f - %.2f seconds\n", 
            min(rt_trend$median_FWHM), max(rt_trend$median_FWHM)))
cat(sprintf("Maximum variation: %.1f%%\n", 
            (max(rt_trend$median_FWHM) - min(rt_trend$median_FWHM)) / min(rt_trend$median_FWHM) * 100))

# Quantity trend analysis
quantity_trend <- analysis_data %>%
  group_by(Quantity_quartile) %>%
  summarise(
    mean_FWHM = mean(FWHM_seconds),
    median_FWHM = median(FWHM_seconds),
    sd_FWHM = sd(FWHM_seconds),
    n = n()
  )

cat("\n=== Quantity Trend Summary ===\n")
print(quantity_trend)

cat("\n✅ Analysis complete! All plots saved to 'plots' directory.\n")