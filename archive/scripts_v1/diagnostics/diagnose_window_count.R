# Diagnostic Script: Window Count Investigation
# Purpose: Understand why all gradients produce 20 windows per RT bin

library(arrow)
library(dplyr)

# Source modules
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/utils_common.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Window Count Diagnostic Analysis                            ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Configuration
INSTRUMENT_PRESET <- "orbitrap"
TARGET_DPPP <- 7.0
TARGET_SATISFACTION <- 0.85
LOAD_FACTOR <- 0.8

# Test files
INPUT_FILES <- c(
  "data/30min_report.parquet",
  "data/60min_report.parquet",
  "data/90min_report.parquet"
)

# Cycle time estimates (from run_refactored_batch.R)
CYCLE_TIME_ESTIMATES <- c(1.2, 1.6, 2.0)

cat("Configuration:\n")
cat(sprintf("  Instrument: %s\n", INSTRUMENT_PRESET))
cat(sprintf("  Target DPPP: %.1f\n", TARGET_DPPP))
cat(sprintf("  Target Satisfaction: %.0f%%\n", TARGET_SATISFACTION * 100))
cat(sprintf("  Load Factor: %.0f%%\n", LOAD_FACTOR * 100))
cat("\n")

# Analyze each gradient
results <- list()

for (i in 1:length(INPUT_FILES)) {

  input_file <- INPUT_FILES[i]
  gradient_name <- gsub("_report.parquet", "", basename(input_file))
  current_cycle_time <- CYCLE_TIME_ESTIMATES[i]

  cat("═══════════════════════════════════════════════════════════════\n")
  cat(sprintf("Analyzing: %s (current cycle time: %.1f sec)\n", gradient_name, current_cycle_time))
  cat("═══════════════════════════════════════════════════════════════\n\n")

  # Stage 1: Validation
  cat("Stage 1: Loading and validating data...\n")
  validated_data <- create_validated_dataset(
    proteome_file = input_file,
    apply_quality_filters = TRUE
  )
  cat(sprintf("  ✅ Loaded %s precursors\n", format(nrow(validated_data$data), big.mark = ",")))

  # Get FWHM statistics
  fwhm_minutes <- validated_data$data$FWHM
  fwhm_seconds <- fwhm_minutes * 60

  cat("\nFWHM Statistics:\n")
  cat(sprintf("  Mean: %.2f min (%.1f sec)\n", mean(fwhm_minutes), mean(fwhm_seconds)))
  cat(sprintf("  Median: %.2f min (%.1f sec)\n", median(fwhm_minutes), median(fwhm_seconds)))
  cat(sprintf("  P15: %.2f min (%.1f sec)\n",
              quantile(fwhm_minutes, 0.15),
              quantile(fwhm_seconds, 0.15)))
  cat(sprintf("  P50: %.2f min (%.1f sec)\n",
              quantile(fwhm_minutes, 0.50),
              quantile(fwhm_seconds, 0.50)))
  cat(sprintf("  P85: %.2f min (%.1f sec)\n",
              quantile(fwhm_minutes, 0.85),
              quantile(fwhm_seconds, 0.85)))

  # Calculate theoretical required cycle time manually
  # Formula: required_cycle_time = (1.7 × FWHM_critical) / target_DPPP
  # FWHM_critical = P15 (15th percentile, for 85% satisfaction)
  fwhm_critical <- quantile(fwhm_seconds, 0.15)
  theoretical_required_ct <- (1.7 * fwhm_critical) / TARGET_DPPP

  cat(sprintf("\nTheoretical Calculation:\n"))
  cat(sprintf("  FWHM critical (P15): %.2f sec\n", fwhm_critical))
  cat(sprintf("  Required cycle time: (1.7 × %.2f) / %.1f = %.3f sec\n",
              fwhm_critical, TARGET_DPPP, theoretical_required_ct))

  # Stage 2: Planning
  cat("\nStage 2: Running optimization planning...\n")
  optimization_plan <- plan_optimization(
    validated_data = validated_data,
    current_cycle_time = current_cycle_time,
    instrument_preset = INSTRUMENT_PRESET,
    target_dppp = TARGET_DPPP,
    target_satisfaction = TARGET_SATISFACTION,
    load_factor = LOAD_FACTOR
  )

  # Extract results
  required_ct <- optimization_plan$required_cycle_time_sec
  window_count <- optimization_plan$window_count_per_bin
  actual_ct <- optimization_plan$actual_cycle_time_sec

  cat("\nPlanning Results:\n")
  cat(sprintf("  Current cycle time: %.3f sec\n", current_cycle_time))
  cat(sprintf("  Required cycle time: ≤ %.3f sec\n", required_ct))
  cat(sprintf("  Window count per bin: %d\n", window_count))
  cat(sprintf("  Actual cycle time: %.3f sec\n", actual_ct))

  # Calculate effective scan rate
  effective_scan_rate <- 12 * LOAD_FACTOR  # Traditional Orbitrap: 12 Hz
  total_scans <- floor(required_ct * effective_scan_rate)
  ms1_scans <- 1  # Sequential
  calculated_windows <- total_scans - ms1_scans

  cat("\nWindow Count Calculation Breakdown:\n")
  cat(sprintf("  Max scan rate: 12 Hz (Traditional Orbitrap)\n"))
  cat(sprintf("  Load factor: %.0f%%\n", LOAD_FACTOR * 100))
  cat(sprintf("  Effective scan rate: %.1f Hz\n", effective_scan_rate))
  cat(sprintf("  Total scans: floor(%.3f × %.1f) = %d\n",
              required_ct, effective_scan_rate, total_scans))
  cat(sprintf("  MS1 scans reserved: %d\n", ms1_scans))
  cat(sprintf("  Window count: %d - %d = %d\n",
              total_scans, ms1_scans, calculated_windows))

  # Store results
  results[[gradient_name]] <- list(
    current_cycle_time = current_cycle_time,
    fwhm_p15_sec = fwhm_critical,
    theoretical_required_ct = theoretical_required_ct,
    actual_required_ct = required_ct,
    window_count = window_count,
    effective_scan_rate = effective_scan_rate
  )

  cat("\n")
}

# Summary comparison
cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    SUMMARY COMPARISON                          ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

summary_df <- data.frame(
  Gradient = names(results),
  Input_CT = sapply(results, function(x) x$current_cycle_time),
  FWHM_P15 = sapply(results, function(x) x$fwhm_p15_sec),
  Required_CT = sapply(results, function(x) x$actual_required_ct),
  Window_Count = sapply(results, function(x) x$window_count),
  Eff_Scan_Rate = sapply(results, function(x) x$effective_scan_rate)
)

print(summary_df)

cat("\n")
cat("Key Findings:\n")
cat("─────────────────────────────────────────────────────────────\n")

# Check if required cycle times are similar
ct_range <- max(summary_df$Required_CT) - min(summary_df$Required_CT)
ct_mean <- mean(summary_df$Required_CT)

if (ct_range < 0.5) {
  cat("✅ EXPLANATION FOUND:\n")
  cat(sprintf("   All gradients have similar required cycle times (%.3f ± %.3f sec)\n",
              ct_mean, ct_range / 2))
  cat("   This is because FWHM distributions are similar across gradients.\n")
  cat("   With Traditional Orbitrap (9.6 Hz effective):\n")
  cat(sprintf("   → floor(%.3f × 9.6) - 1 = %d windows per RT bin\n",
              ct_mean, summary_df$Window_Count[1]))
  cat("\n")
  cat("   The input cycle time (1.2, 1.6, 2.0 sec) is only used to calculate\n")
  cat("   current DPPP satisfaction, NOT to determine window count.\n")
  cat("\n")
  cat("   Window count is determined by:\n")
  cat("   1. Analyzing FWHM distribution\n")
  cat("   2. Finding critical FWHM (P15 for 85% satisfaction)\n")
  cat("   3. Calculating REQUIRED cycle time for target DPPP 7.0\n")
  cat("   4. Converting to window count based on instrument scan rate\n")
} else {
  cat("⚠️  Required cycle times vary significantly:\n")
  cat(sprintf("   Range: %.3f - %.3f sec (Δ = %.3f sec)\n",
              min(summary_df$Required_CT),
              max(summary_df$Required_CT),
              ct_range))
  cat("   Window counts should be different but are not.\n")
  cat("   → This indicates a potential bug in the calculation.\n")
}

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Diagnostic Complete\n")
cat("═══════════════════════════════════════════════════════════════\n")
