# analyze_fwhm_simple.R - Simplified FWHM visualization

library(arrow)
library(dplyr)
library(ggplot2)
library(viridis)

# Load data
cat("Loading DIA-NN data...\n")
data <- read_parquet("D:/Projects/DPPP_Window_isolation/DIANN-Output/report.parquet")

# Sample data for faster processing
cat("Sampling data for visualization...\n")
set.seed(123)
sample_size <- 100000

analysis_data <- data %>%
  filter(!is.na(FWHM), FWHM > 0, FWHM < 10,
         !is.na(RT.Start), !is.na(Precursor.Quantity)) %>%
  sample_n(min(sample_size, n())) %>%
  mutate(
    FWHM_seconds = FWHM * 60,
    RT_minutes = RT.Start,
    Log_Quantity = log10(Precursor.Quantity + 1)
  )

cat(sprintf("Analyzing %d sampled precursors\n", nrow(analysis_data)))

# Create directory for plots
if (!dir.exists("plots")) {
  dir.create("plots")
}

# 1. FWHM vs RT - Point plot with smooth line
cat("Creating FWHM vs RT plot...\n")
p1 <- ggplot(analysis_data, aes(x = RT_minutes, y = FWHM_seconds)) +
  geom_point(alpha = 0.1, size = 0.5, color = "steelblue") +
  geom_smooth(method = "gam", color = "red", linewidth = 1, se = TRUE) +
  labs(
    title = "FWHM Distribution Across Retention Time",
    subtitle = sprintf("n = %d precursors (sampled)", nrow(analysis_data)),
    x = "Retention Time (minutes)",
    y = "FWHM (seconds)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )

ggsave("plots/fwhm_vs_rt.png", p1, width = 10, height = 6, dpi = 150)

# 2. FWHM vs Quantity - Point plot
cat("Creating FWHM vs Quantity plot...\n")
p2 <- ggplot(analysis_data, aes(x = Log_Quantity, y = FWHM_seconds)) +
  geom_point(alpha = 0.1, size = 0.5, color = "darkgreen") +
  geom_smooth(method = "gam", color = "red", linewidth = 1, se = TRUE) +
  labs(
    title = "FWHM vs Signal Intensity",
    subtitle = "Log10(Quantity) vs FWHM",
    x = "Log10(Precursor Quantity)",
    y = "FWHM (seconds)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )

ggsave("plots/fwhm_vs_quantity.png", p2, width = 10, height = 6, dpi = 150)

# 3. RT binned analysis
cat("Creating RT binned analysis...\n")
rt_bins <- 20
analysis_data$RT_bin <- cut(analysis_data$RT_minutes, breaks = rt_bins)

rt_summary <- analysis_data %>%
  group_by(RT_bin) %>%
  summarise(
    RT_mid = mean(RT_minutes),
    mean_FWHM = mean(FWHM_seconds),
    median_FWHM = median(FWHM_seconds),
    q25_FWHM = quantile(FWHM_seconds, 0.25),
    q75_FWHM = quantile(FWHM_seconds, 0.75),
    n = n(),
    .groups = 'drop'
  )

p3 <- ggplot(rt_summary, aes(x = RT_mid)) +
  geom_ribbon(aes(ymin = q25_FWHM, ymax = q75_FWHM), fill = "steelblue", alpha = 0.3) +
  geom_line(aes(y = median_FWHM), color = "steelblue", linewidth = 1.5) +
  geom_line(aes(y = mean_FWHM), color = "darkblue", linewidth = 1, linetype = "dashed") +
  geom_point(aes(y = median_FWHM), color = "steelblue", size = 2) +
  labs(
    title = "FWHM Trend Across Retention Time",
    subtitle = "Median (solid) and Mean (dashed) with IQR shading",
    x = "Retention Time (minutes)",
    y = "FWHM (seconds)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )

ggsave("plots/fwhm_rt_trend.png", p3, width = 10, height = 6, dpi = 150)

# 4. Quantity quartile analysis
cat("Creating Quantity quartile analysis...\n")
analysis_data$Quantity_quartile <- cut(analysis_data$Precursor.Quantity,
                                      breaks = quantile(analysis_data$Precursor.Quantity, 
                                                       probs = c(0, 0.25, 0.5, 0.75, 1)),
                                      labels = c("Q1\n(Low)", "Q2", "Q3", "Q4\n(High)"),
                                      include.lowest = TRUE)

quantity_summary <- analysis_data %>%
  group_by(Quantity_quartile) %>%
  summarise(
    mean_FWHM = mean(FWHM_seconds),
    median_FWHM = median(FWHM_seconds),
    sd_FWHM = sd(FWHM_seconds),
    n = n(),
    .groups = 'drop'
  )

p4 <- ggplot(quantity_summary, aes(x = Quantity_quartile, y = median_FWHM)) +
  geom_col(fill = "coral", alpha = 0.7) +
  geom_errorbar(aes(ymin = median_FWHM - sd_FWHM, ymax = median_FWHM + sd_FWHM),
                width = 0.2, color = "darkred") +
  geom_text(aes(label = sprintf("%.2f", median_FWHM)), vjust = -0.5) +
  labs(
    title = "FWHM by Signal Intensity Quartiles",
    subtitle = "Median ± SD",
    x = "Intensity Quartiles",
    y = "FWHM (seconds)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )

ggsave("plots/fwhm_quantity_quartiles.png", p4, width = 8, height = 6, dpi = 150)

# 5. 2D Contour plot
cat("Creating 2D contour plot...\n")
p5 <- ggplot(analysis_data, aes(x = RT_minutes, y = Log_Quantity)) +
  geom_density_2d_filled(alpha = 0.7) +
  scale_fill_viridis_d() +
  labs(
    title = "2D Density: RT vs Quantity",
    x = "Retention Time (minutes)",
    y = "Log10(Precursor Quantity)",
    fill = "Density"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    legend.position = "right"
  )

ggsave("plots/fwhm_2d_density.png", p5, width = 10, height = 6, dpi = 150)

# Statistical analysis
cat("\n=== Statistical Analysis ===\n")

# Overall statistics
overall_stats <- analysis_data %>%
  summarise(
    n = n(),
    fwhm_mean = mean(FWHM_seconds),
    fwhm_median = median(FWHM_seconds),
    fwhm_sd = sd(FWHM_seconds),
    fwhm_cv = sd(FWHM_seconds) / mean(FWHM_seconds) * 100
  )

cat("\nOverall FWHM Statistics:\n")
cat(sprintf("  Mean: %.2f ± %.2f seconds\n", overall_stats$fwhm_mean, overall_stats$fwhm_sd))
cat(sprintf("  Median: %.2f seconds\n", overall_stats$fwhm_median))
cat(sprintf("  CV: %.1f%%\n", overall_stats$fwhm_cv))

# Correlation analysis
cor_rt <- cor(analysis_data$RT_minutes, analysis_data$FWHM_seconds, use = "complete.obs")
cor_quantity <- cor(analysis_data$Log_Quantity, analysis_data$FWHM_seconds, use = "complete.obs")

cat(sprintf("\nCorrelation with FWHM:\n"))
cat(sprintf("  RT: %.3f\n", cor_rt))
cat(sprintf("  Log(Quantity): %.3f\n", cor_quantity))

# RT trend
rt_change <- (max(rt_summary$median_FWHM) - min(rt_summary$median_FWHM)) / min(rt_summary$median_FWHM) * 100
cat(sprintf("\nFWHM change across RT: %.1f%%\n", rt_change))

# Quantity trend
cat("\nFWHM by Intensity Quartiles:\n")
print(quantity_summary)

# Save summary
summary_text <- capture.output({
  cat("FWHM Analysis Summary\n")
  cat("=====================\n\n")
  cat(sprintf("Data points analyzed: %d\n", nrow(analysis_data)))
  cat(sprintf("RT range: %.1f - %.1f minutes\n", min(analysis_data$RT_minutes), max(analysis_data$RT_minutes)))
  cat(sprintf("FWHM range: %.2f - %.2f seconds\n", min(analysis_data$FWHM_seconds), max(analysis_data$FWHM_seconds)))
  cat("\n")
  print(overall_stats)
  cat("\n")
  cat(sprintf("Correlation RT-FWHM: %.3f\n", cor_rt))
  cat(sprintf("Correlation Quantity-FWHM: %.3f\n", cor_quantity))
  cat(sprintf("FWHM variation across RT: %.1f%%\n", rt_change))
  cat("\n")
  cat("RT Trend Summary:\n")
  print(rt_summary)
  cat("\n")
  cat("Quantity Quartile Summary:\n")
  print(quantity_summary)
})

writeLines(summary_text, "plots/fwhm_analysis_summary.txt")

cat("\n✅ Analysis complete! All plots saved to 'plots' directory.\n")
cat("Summary saved to: plots/fwhm_analysis_summary.txt\n")