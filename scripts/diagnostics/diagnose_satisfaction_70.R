# Diagnostic Script: Window Count with 70% Satisfaction Target
# Purpose: Compare window counts between 85% and 70% satisfaction targets

library(arrow)
library(dplyr)

# Source modules
source("R/stage1_data_validation.R")
source("R/stage2_optimization_planning.R")
source("R/utils_common.R")

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Satisfaction 70% vs 85% Comparison                          ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Configuration
INSTRUMENT_PRESET <- "orbitrap"
TARGET_DPPP <- 7.0
LOAD_FACTOR <- 0.8

# Test both satisfaction targets
SATISFACTION_TARGETS <- c(0.70, 0.85)

# Test files
INPUT_FILES <- c(
  "data/30min_report.parquet",
  "data/60min_report.parquet",
  "data/90min_report.parquet"
)

# Cycle time estimates
CYCLE_TIME_ESTIMATES <- c(1.2, 1.6, 2.0)

cat("Configuration:\n")
cat(sprintf("  Instrument: %s\n", INSTRUMENT_PRESET))
cat(sprintf("  Target DPPP: %.1f\n", TARGET_DPPP))
cat(sprintf("  Load Factor: %.0f%%\n", LOAD_FACTOR * 100))
cat(sprintf("  Comparing Satisfaction: 70%% vs 85%%\n"))
cat("\n")

# Store results for comparison
all_results <- list()

for (satisfaction in SATISFACTION_TARGETS) {

  cat("═══════════════════════════════════════════════════════════════\n")
  cat(sprintf("Target Satisfaction: %.0f%%\n", satisfaction * 100))
  cat("═══════════════════════════════════════════════════════════════\n\n")

  results <- list()

  for (i in 1:length(INPUT_FILES)) {

    input_file <- INPUT_FILES[i]
    gradient_name <- gsub("_report.parquet", "", basename(input_file))
    current_cycle_time <- CYCLE_TIME_ESTIMATES[i]

    cat(sprintf("--- %s (input CT: %.1f sec) ---\n", gradient_name, current_cycle_time))

    # Stage 1: Validation (quiet mode)
    validated_data <- suppressMessages(create_validated_dataset(
      proteome_file = input_file,
      apply_quality_filters = TRUE
    ))

    # Get FWHM statistics
    fwhm_seconds <- validated_data$data$FWHM * 60

    # Calculate critical FWHM for this satisfaction target
    critical_percentile <- 1 - satisfaction
    fwhm_critical <- quantile(fwhm_seconds, critical_percentile)

    # Calculate theoretical required cycle time
    theoretical_required_ct <- (1.7 * fwhm_critical) / TARGET_DPPP

    cat(sprintf("  FWHM P%.0f: %.2f sec\n", critical_percentile * 100, fwhm_critical))
    cat(sprintf("  Theoretical required CT: %.3f sec\n", theoretical_required_ct))

    # Stage 2: Planning (quiet mode)
    optimization_plan <- suppressMessages(plan_optimization(
      validated_data = validated_data,
      current_cycle_time = current_cycle_time,
      instrument_preset = INSTRUMENT_PRESET,
      target_dppp = TARGET_DPPP,
      target_satisfaction = satisfaction,
      load_factor = LOAD_FACTOR
    ))

    # Extract results
    required_ct <- optimization_plan$required_cycle_time_sec
    window_count <- optimization_plan$window_count_per_bin
    actual_ct <- optimization_plan$actual_cycle_time_sec

    # Calculate natural window count (before min constraint)
    effective_scan_rate <- 12 * LOAD_FACTOR
    total_scans <- floor(required_ct * effective_scan_rate)
    ms1_scans <- 1
    natural_windows <- total_scans - ms1_scans

    cat(sprintf("  Required CT: %.3f sec\n", required_ct))
    cat(sprintf("  Natural window count: %d\n", natural_windows))
    cat(sprintf("  Applied window count: %d (min=20)\n", window_count))
    cat(sprintf("  Actual CT: %.3f sec\n", actual_ct))
    cat("\n")

    # Store results
    results[[gradient_name]] <- list(
      gradient = gradient_name,
      satisfaction = satisfaction,
      fwhm_critical = fwhm_critical,
      required_ct = required_ct,
      natural_windows = natural_windows,
      applied_windows = window_count,
      actual_ct = actual_ct
    )
  }

  all_results[[sprintf("sat_%.0f", satisfaction * 100)]] <- results
}

# Create comparison table
cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                    COMPARISON TABLE                            ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Extract data for both satisfaction levels
sat70 <- all_results$sat_70
sat85 <- all_results$sat_85

comparison_df <- data.frame(
  Gradient = c("30min", "60min", "90min"),

  # 70% satisfaction
  FWHM_P30 = sapply(sat70, function(x) x$fwhm_critical),
  Required_CT_70 = sapply(sat70, function(x) x$required_ct),
  Natural_Win_70 = sapply(sat70, function(x) x$natural_windows),
  Applied_Win_70 = sapply(sat70, function(x) x$applied_windows),

  # 85% satisfaction
  FWHM_P15 = sapply(sat85, function(x) x$fwhm_critical),
  Required_CT_85 = sapply(sat85, function(x) x$required_ct),
  Natural_Win_85 = sapply(sat85, function(x) x$natural_windows),
  Applied_Win_85 = sapply(sat85, function(x) x$applied_windows)
)

print(comparison_df)

cat("\n")
cat("Key Findings:\n")
cat("─────────────────────────────────────────────────────────────\n")

# Compare natural window counts
natural_70 <- comparison_df$Natural_Win_70
natural_85 <- comparison_df$Natural_Win_85

cat("\n1. NATURAL Window Count (before min=20 constraint):\n")
cat(sprintf("   70%% satisfaction: %s windows per bin\n",
            paste(natural_70, collapse = ", ")))
cat(sprintf("   85%% satisfaction: %s windows per bin\n",
            paste(natural_85, collapse = ", ")))

if (all(natural_70 > natural_85)) {
  cat("   ✅ 70%% allows MORE windows (longer cycle time acceptable)\n")
} else if (all(natural_70 == natural_85)) {
  cat("   ⚠️  70%% and 85%% produce SAME window count\n")
} else {
  cat("   ❌ Unexpected pattern - needs investigation\n")
}

# Compare applied window counts
applied_70 <- comparison_df$Applied_Win_70
applied_85 <- comparison_df$Applied_Win_85

cat("\n2. APPLIED Window Count (after min=20 constraint):\n")
cat(sprintf("   70%% satisfaction: %s windows per bin\n",
            paste(applied_70, collapse = ", ")))
cat(sprintf("   85%% satisfaction: %s windows per bin\n",
            paste(applied_85, collapse = ", ")))

if (all(applied_70 == 20) && all(applied_85 == 20)) {
  cat("   ⚠️  Both constrained to 20 windows minimum\n")
} else if (any(applied_70 > 20)) {
  cat("   ✅ 70%% satisfaction EXCEEDS minimum constraint\n")
} else {
  cat("   ℹ️  Different window counts applied\n")
}

# Calculate increase percentages
cat("\n3. FWHM Critical Percentile Increase:\n")
for (i in 1:3) {
  gradient <- comparison_df$Gradient[i]
  fwhm_p15 <- comparison_df$FWHM_P15[i]
  fwhm_p30 <- comparison_df$FWHM_P30[i]
  increase_pct <- ((fwhm_p30 / fwhm_p15) - 1) * 100

  cat(sprintf("   %s: P15 %.2f → P30 %.2f sec (+%.1f%%)\n",
              gradient, fwhm_p15, fwhm_p30, increase_pct))
}

cat("\n4. Required Cycle Time Increase:\n")
for (i in 1:3) {
  gradient <- comparison_df$Gradient[i]
  ct_85 <- comparison_df$Required_CT_85[i]
  ct_70 <- comparison_df$Required_CT_70[i]
  increase_pct <- ((ct_70 / ct_85) - 1) * 100

  cat(sprintf("   %s: %.3f → %.3f sec (+%.1f%%)\n",
              gradient, ct_85, ct_70, increase_pct))
}

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Recommendation:\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

if (all(natural_70 >= 20) && any(natural_85 < 20)) {
  cat("✅ Satisfaction 70%% is EFFECTIVE:\n")
  cat("   - Natural window counts EXCEED 20 minimum\n")
  cat("   - No constraint interference\n")
  cat("   - Window counts will vary based on cycle time\n")
  cat("\n")
  cat("   Recommended: Use target_satisfaction = 0.70 for variable window counts\n")
} else if (all(natural_70 < 20)) {
  cat("⚠️  Satisfaction 70%% still constrained:\n")
  cat("   - Natural window counts still below 20\n")
  cat("   - Need to lower satisfaction further OR reduce min_windows\n")
  cat("\n")
  cat("   Options:\n")
  cat("   1. Use satisfaction = 0.60 or lower\n")
  cat("   2. Reduce min_windows from 20 to 10\n")
} else {
  cat("ℹ️  Mixed results:\n")
  cat("   Some gradients exceed minimum, others don't\n")
  cat("   Consider gradient-specific settings\n")
}

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Diagnostic Complete\n")
cat("═══════════════════════════════════════════════════════════════\n")
