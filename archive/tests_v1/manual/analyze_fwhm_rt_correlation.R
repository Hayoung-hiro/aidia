# analyze_fwhm_rt_correlation.R
# Check if FWHM correlates with RT position in real DIA data

library(arrow)
library(dplyr)

data <- arrow::read_parquet("data/30min_report.parquet")
cat("Total rows:", nrow(data), "\n")

# Compute RT.Apex
if ("RT.Stop" %in% names(data)) {
  data$RT.Apex <- (data$RT.Start + data$RT.Stop) / 2
} else {
  data$RT.Apex <- data$RT.Start
}

# Filter valid
valid <- data[!is.na(data$FWHM) & !is.na(data$RT.Apex) & data$FWHM > 0, ]
cat("Valid precursors:", nrow(valid), "\n\n")

# ── Correlation ──
cat("=== FWHM vs RT.Apex Correlation ===\n")
pearson <- cor(valid$RT.Apex, valid$FWHM, method = "pearson")
spearman <- cor(valid$RT.Apex, valid$FWHM, method = "spearman")
cat(sprintf("Pearson  r = %.4f  (R² = %.4f)\n", pearson, pearson^2))
cat(sprintf("Spearman rho = %.4f\n\n", spearman))

lm_fit <- lm(FWHM ~ RT.Apex, data = valid)
cat(sprintf("Linear model: FWHM = %.6f * RT + %.4f\n", coef(lm_fit)[2], coef(lm_fit)[1]))
cat(sprintf("R² = %.4f\n\n", summary(lm_fit)$r.squared))

# ── Quintile analysis ──
cat("=== FWHM by RT Quintile ===\n")
breaks <- quantile(valid$RT.Apex, probs = seq(0, 1, 0.2))
valid$rt_q <- cut(valid$RT.Apex, breaks = breaks, include.lowest = TRUE,
                  labels = c("Q1(early)", "Q2", "Q3(mid)", "Q4", "Q5(late)"))

qstats <- valid %>%
  group_by(rt_q) %>%
  summarise(
    n = n(),
    rt_lo = min(RT.Apex), rt_hi = max(RT.Apex),
    fwhm_mean = mean(FWHM), fwhm_median = median(FWHM),
    fwhm_sd = sd(FWHM), .groups = "drop"
  )

for (i in seq_len(nrow(qstats))) {
  r <- qstats[i, ]
  cat(sprintf("  %-10s RT %.1f-%.1f  n=%5d  mean=%.4f  med=%.4f  SD=%.4f\n",
              r$rt_q, r$rt_lo, r$rt_hi, r$n, r$fwhm_mean, r$fwhm_median, r$fwhm_sd))
}

medians <- qstats$fwhm_median
cat(sprintf("\nMedian FWHM range: %.4f - %.4f min\n", min(medians), max(medians)))
cat(sprintf("Max/Min ratio: %.2fx\n", max(medians) / min(medians)))
cat(sprintf("Relative variation: %.1f%%\n\n", (max(medians) - min(medians)) / mean(medians) * 100))

# ── FWHM seconds for DPPP context ──
cat("=== DPPP Impact (cycle_time = 1.43 sec) ===\n")
cycle_time <- 1.43
for (i in seq_len(nrow(qstats))) {
  r <- qstats[i, ]
  fwhm_sec <- r$fwhm_median * 60
  dppp <- (1.7 * fwhm_sec) / cycle_time
  max_ct <- (1.7 * fwhm_sec) / 7.0  # For target DPPP=7
  max_win <- floor(max_ct / 0.005)   # Astral: 5ms per scan
  cat(sprintf("  %-10s median FWHM=%.1fs  DPPP=%.1f  max_cycle=%.2fs  max_windows=%d\n",
              r$rt_q, fwhm_sec, dppp, max_ct, max_win))
}

# ── Per-run consistency ──
cat("\n=== FWHM by Run ===\n")
run_stats <- valid %>%
  group_by(Run) %>%
  summarise(n = n(), fwhm_med = median(FWHM), .groups = "drop")
for (i in seq_len(nrow(run_stats))) {
  r <- run_stats[i, ]
  cat(sprintf("  %s: n=%d, median=%.4f\n", basename(r$Run), r$n, r$fwhm_med))
}

cat("\nDone.\n")
