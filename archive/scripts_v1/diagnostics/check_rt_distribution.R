# check_rt_distribution.R
# Quick check of RT distribution in the dataset

library(arrow)
library(dplyr)
library(ggplot2)

# Load data
cat("Loading data...\n")
data <- read_parquet('data/90min_report.parquet')

cat('\n=== RT Distribution Analysis ===\n')
cat(sprintf('Total precursors: %d\n', nrow(data)))
cat(sprintf('RT range: %.1f - %.1f minutes\n', min(data$RT.Start), max(data$RT.Start)))

# Bin by 10-minute intervals
rt_bins <- data %>%
  mutate(rt_bin = cut(RT.Start, breaks = seq(0, 80, by = 10), include.lowest = TRUE)) %>%
  group_by(rt_bin) %>%
  summarise(n_precursors = n(), .groups = 'drop')

cat('\nPrecursors per 10-minute RT bin:\n')
print(rt_bins)

# Check early vs late RT
early_rt <- sum(data$RT.Start < 30)
late_rt <- sum(data$RT.Start >= 60)

cat(sprintf('\nEarly RT (<30 min): %d precursors (%.1f%%)\n', early_rt, early_rt/nrow(data)*100))
cat(sprintf('Late RT (>=60 min): %d precursors (%.1f%%)\n', late_rt, late_rt/nrow(data)*100))

# Check the peak region
cat('\nTop 5 RT regions by precursor count (5-min bins):\n')
peak_analysis <- data %>%
  mutate(rt_5min = floor(RT.Start / 5) * 5) %>%
  group_by(rt_5min) %>%
  summarise(n = n(), .groups = 'drop') %>%
  arrange(desc(n)) %>%
  head(5)
print(peak_analysis)

# Create simple histogram
cat('\nCreating RT histogram...\n')
p <- ggplot(data, aes(x = RT.Start)) +
  geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7) +
  labs(
    title = "RT Distribution of Precursors",
    x = "Retention Time (min)",
    y = "Number of Precursors"
  ) +
  theme_minimal()

ggsave("test_plots/rt_distribution_check.png", p, width = 10, height = 6, dpi = 150)
cat("✅ Saved: test_plots/rt_distribution_check.png\n")

# Check m/z distribution in late RT region
cat('\n=== m/z Distribution in Late RT (60-75 min) ===\n')
late_rt_data <- data %>% filter(RT.Start >= 60 & RT.Start < 75)
cat(sprintf('Precursors in late RT: %d\n', nrow(late_rt_data)))
cat(sprintf('m/z range: %.1f - %.1f\n', min(late_rt_data$Precursor.Mz), max(late_rt_data$Precursor.Mz)))

mz_quantiles <- quantile(late_rt_data$Precursor.Mz, probs = c(0.05, 0.25, 0.5, 0.75, 0.95))
cat('\nm/z quantiles in late RT:\n')
print(mz_quantiles)
