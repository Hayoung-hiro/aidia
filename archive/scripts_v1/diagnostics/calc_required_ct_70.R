# Quick calculation: Required cycle time for 70% satisfaction
library(arrow)

TARGET_DPPP <- 7.0
TARGET_SATISFACTION <- 0.70

files <- c('data/30min_report.parquet', 'data/60min_report.parquet', 'data/90min_report.parquet')

cat('\n═══════════════════════════════════════════════════════════════\n')
cat(sprintf('Target Satisfaction: %.0f%% (P%.0f percentile)\n',
            TARGET_SATISFACTION * 100,
            (1 - TARGET_SATISFACTION) * 100))
cat(sprintf('Target DPPP: %.1f\n', TARGET_DPPP))
cat('═══════════════════════════════════════════════════════════════\n\n')

for (f in files) {
  data <- read_parquet(f)
  gradient <- gsub('_report.parquet', '', basename(f))

  fwhm_sec <- data$FWHM * 60

  # 70% satisfaction → P30
  fwhm_p30 <- quantile(fwhm_sec, 0.30, na.rm = TRUE)
  required_ct_70 <- (1.7 * fwhm_p30) / TARGET_DPPP

  # 85% satisfaction → P15
  fwhm_p15 <- quantile(fwhm_sec, 0.15, na.rm = TRUE)
  required_ct_85 <- (1.7 * fwhm_p15) / TARGET_DPPP

  cat(sprintf('%s:\n', gradient))
  cat(sprintf('  70%% sat: FWHM P30=%.2f sec → Required CT=%.3f sec\n',
              fwhm_p30, required_ct_70))
  cat(sprintf('  85%% sat: FWHM P15=%.2f sec → Required CT=%.3f sec\n',
              fwhm_p15, required_ct_85))
  cat(sprintf('  Increase: +%.3f sec (+%.1f%%)\n\n',
              required_ct_70 - required_ct_85,
              ((required_ct_70 / required_ct_85) - 1) * 100))
}
