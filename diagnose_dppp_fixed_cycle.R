# =============================================================================
# DPPP Diagnosis with FIXED Cycle Time (2 seconds)
# =============================================================================
# Recalculates DPPP based on actual measurement conditions
# =============================================================================

library(arrow)
library(dplyr)
library(ggplot2)

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║     DPPP Diagnosis - Fixed Cycle Time Analysis                  ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Configuration
ACTUAL_CYCLE_TIME <- 2.0   # 실제 측정시 사용된 cycle time (고정값)
TARGET_DPPP <- 7.0          # Quantification mode target
DPPP_TOLERANCE <- 0.5       # ±0.5 acceptable
SATISFACTION_TARGET <- 0.70  # 70% should meet target

# Function to calculate DPPP
calculate_dppp <- function(fwhm_seconds, cycle_time_seconds) {
  # DPPP = (1.7 × FWHM) / cycle_time
  dppp <- (1.7 * fwhm_seconds) / cycle_time_seconds
  return(dppp)
}

# Function to calculate required cycle time for target DPPP
calculate_required_cycle_time <- function(fwhm_seconds, target_dppp) {
  # cycle_time = (1.7 × FWHM) / target_dppp
  cycle_time <- (1.7 * fwhm_seconds) / target_dppp
  return(cycle_time)
}

# Process each file
parquet_files <- list.files("data", pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("Found %d parquet files for analysis\n", length(parquet_files)))
cat(sprintf("Fixed cycle time used: %.1f seconds\n\n", ACTUAL_CYCLE_TIME))
cat("═══════════════════════════════════════════════════════════════\n\n")

all_results <- list()

for (file in parquet_files) {
  file_name <- basename(file)
  base_name <- gsub("\\.parquet$", "", file_name)

  # Load data
  data <- arrow::read_parquet(file)

  # Find FWHM column
  fwhm_col <- NULL
  if ("FWHM" %in% names(data)) fwhm_col <- "FWHM"
  else if ("FWHM.sec" %in% names(data)) fwhm_col <- "FWHM.sec"
  else if ("Peak.Width" %in% names(data)) fwhm_col <- "Peak.Width"

  if (is.null(fwhm_col)) next

  # Get FWHM values
  fwhm_values <- data[[fwhm_col]]
  fwhm_values <- fwhm_values[!is.na(fwhm_values) & fwhm_values > 0]

  # Convert to seconds if needed
  if (median(fwhm_values) > 2) {
    fwhm_seconds <- fwhm_values
  } else {
    fwhm_seconds <- fwhm_values * 60
  }

  # Calculate statistics
  fwhm_median <- median(fwhm_seconds)
  fwhm_mean <- mean(fwhm_seconds)
  fwhm_q1 <- quantile(fwhm_seconds, 0.25)
  fwhm_q3 <- quantile(fwhm_seconds, 0.75)

  # Calculate ACTUAL DPPP with fixed cycle time
  actual_dppp_values <- calculate_dppp(fwhm_seconds, ACTUAL_CYCLE_TIME)
  actual_dppp_median <- median(actual_dppp_values)
  actual_dppp_mean <- mean(actual_dppp_values)

  # Calculate satisfaction with actual cycle time
  within_target <- actual_dppp_values >= (TARGET_DPPP - DPPP_TOLERANCE) &
                  actual_dppp_values <= (TARGET_DPPP + DPPP_TOLERANCE)
  actual_satisfaction <- mean(within_target)

  # Calculate REQUIRED cycle time for target DPPP
  required_cycle_time <- calculate_required_cycle_time(fwhm_median, TARGET_DPPP)

  # Calculate how many windows this would allow
  # MS1 = 100ms, MS2 = 50ms per window
  max_windows_current <- floor((ACTUAL_CYCLE_TIME - 0.1) / 0.05)
  max_windows_required <- floor((required_cycle_time - 0.1) / 0.05)

  # Determine gradient type
  gradient_type <- case_when(
    grepl("30min", base_name) ~ "30min",
    grepl("60min", base_name) ~ "60min",
    grepl("90min", base_name) ~ "90min",
    TRUE ~ "unknown"
  )

  # Store results
  result <- list(
    file = base_name,
    gradient = gradient_type,
    fwhm_median = fwhm_median,
    fwhm_q1 = fwhm_q1,
    fwhm_q3 = fwhm_q3,
    actual_cycle_time = ACTUAL_CYCLE_TIME,
    actual_dppp_median = actual_dppp_median,
    actual_satisfaction = actual_satisfaction,
    required_cycle_time = required_cycle_time,
    max_windows_current = max_windows_current,
    max_windows_required = max_windows_required,
    cycle_time_reduction = (ACTUAL_CYCLE_TIME - required_cycle_time) / ACTUAL_CYCLE_TIME * 100
  )

  all_results[[base_name]] <- result
}

# Create summary
results_df <- bind_rows(all_results)

# Print detailed analysis
cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║          ANALYSIS WITH FIXED CYCLE TIME (2.0 sec)               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Group by gradient
gradient_summary <- results_df %>%
  group_by(gradient) %>%
  summarise(
    n = n(),
    avg_fwhm = mean(fwhm_median),
    avg_actual_dppp = mean(actual_dppp_median),
    avg_satisfaction = mean(actual_satisfaction),
    avg_required_cycle = mean(required_cycle_time),
    avg_windows_required = mean(max_windows_required),
    .groups = "drop"
  )

for (i in 1:nrow(gradient_summary)) {
  cat(sprintf("\n📊 %s Gradient Analysis\n", gradient_summary$gradient[i]))
  cat("═══════════════════════════════════════════════════════════════\n\n")

  cat("📈 Peak Characteristics:\n")
  cat(sprintf("  • Average FWHM: %.1f seconds\n", gradient_summary$avg_fwhm[i]))
  cat(sprintf("  • Peak width (1.7×FWHM): %.1f seconds\n",
              gradient_summary$avg_fwhm[i] * 1.7))

  cat("\n🔍 Current State (Fixed 2.0 sec cycle):\n")
  cat(sprintf("  • Actual DPPP: %.1f\n", gradient_summary$avg_actual_dppp[i]))
  cat(sprintf("  • Target DPPP: %.1f\n", TARGET_DPPP))
  cat(sprintf("  • Satisfaction: %.0f%%\n", gradient_summary$avg_satisfaction[i] * 100))

  # Diagnosis
  if (gradient_summary$avg_actual_dppp[i] < TARGET_DPPP - DPPP_TOLERANCE) {
    cat(sprintf("  • ⚠️ UNDERSAMPLING: Cycle time too long for these peaks\n"))
  } else if (gradient_summary$avg_actual_dppp[i] > TARGET_DPPP + DPPP_TOLERANCE) {
    cat(sprintf("  • ⚠️ OVERSAMPLING: Cycle time shorter than needed\n"))
  } else {
    cat(sprintf("  • ✅ OPTIMAL: Good peak sampling\n"))
  }

  cat("\n🎯 Required Settings for DPPP 7.0:\n")
  cat(sprintf("  • Required cycle time: %.2f seconds\n",
              gradient_summary$avg_required_cycle[i]))
  cat(sprintf("  • Reduction needed: %.0f%%\n",
              (ACTUAL_CYCLE_TIME - gradient_summary$avg_required_cycle[i]) /
              ACTUAL_CYCLE_TIME * 100))
  cat(sprintf("  • Maximum windows possible: %.0f\n",
              gradient_summary$avg_windows_required[i]))

  cat("\n💡 Interpretation:\n")
  if (gradient_summary$avg_required_cycle[i] < ACTUAL_CYCLE_TIME) {
    reduction_pct <- (ACTUAL_CYCLE_TIME - gradient_summary$avg_required_cycle[i]) /
                    ACTUAL_CYCLE_TIME * 100
    cat(sprintf("  → Peaks are NARROW, need %.0f%% shorter cycle time\n", reduction_pct))
    cat(sprintf("  → Current 2.0 sec is too long for optimal quantification\n"))
  }
}

# Detailed results table
cat("\n\n📋 Detailed Results by Dataset:\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat(sprintf("%-20s %8s %12s %12s %12s %10s\n",
            "Dataset", "FWHM(s)", "Actual DPPP", "Satisfaction", "Required CT", "Max Win"))
cat("───────────────────────────────────────────────────────────────\n")

for (i in 1:nrow(results_df)) {
  cat(sprintf("%-20s %8.1f %12.1f %11.0f%% %12.2f %10.0f\n",
              results_df$file[i],
              results_df$fwhm_median[i],
              results_df$actual_dppp_median[i],
              results_df$actual_satisfaction[i] * 100,
              results_df$required_cycle_time[i],
              results_df$max_windows_required[i]))
}

# Save results
output_dir <- "results_dppp_fixed_cycle"
if (!dir.exists(output_dir)) dir.create(output_dir)

write.csv(results_df,
          file.path(output_dir, "dppp_analysis_fixed_2sec.csv"),
          row.names = FALSE)
write.csv(gradient_summary,
          file.path(output_dir, "dppp_summary_by_gradient.csv"),
          row.names = FALSE)

# Final recommendations
cat("\n\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║                  CONCLUSIONS & RECOMMENDATIONS                  ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

overall_dppp <- mean(results_df$actual_dppp_median)
overall_satisfaction <- mean(results_df$actual_satisfaction)

cat("📊 Overall Assessment:\n")
cat(sprintf("  • Fixed cycle time used: %.1f seconds\n", ACTUAL_CYCLE_TIME))
cat(sprintf("  • Average DPPP achieved: %.1f (Target: %.1f)\n", overall_dppp, TARGET_DPPP))
cat(sprintf("  • Overall satisfaction: %.0f%% (Target: %.0f%%)\n",
            overall_satisfaction * 100, SATISFACTION_TARGET * 100))

cat("\n🔍 Root Cause:\n")
if (overall_dppp < TARGET_DPPP) {
  cat("  • Cycle time (2.0 sec) is TOO LONG for your peak widths\n")
  cat("  • Narrow peaks are being UNDERSAMPLED\n")
  cat("  • This reduces quantification accuracy\n")
}

cat("\n✅ Recommendations for Future Experiments:\n\n")

for (i in 1:nrow(gradient_summary)) {
  cat(sprintf("📌 %s Gradient:\n", gradient_summary$gradient[i]))
  cat(sprintf("  • Use cycle time: %.2f seconds\n", gradient_summary$avg_required_cycle[i]))
  cat(sprintf("  • Maximum windows: %d\n", gradient_summary$avg_windows_required[i]))
  cat(sprintf("  • This will achieve DPPP: %.1f\n\n", TARGET_DPPP))
}

cat("🔧 Method Optimization Strategy:\n")
cat("  1. REDUCE cycle time to match peak widths\n")
cat("  2. ADJUST window count to fit within new cycle time\n")
cat("  3. MAINTAIN high coverage (>95%) with fewer windows\n")
cat("  4. VERIFY DPPP ≥ 7.0 for quantification\n")

cat(sprintf("\n✅ Analysis complete! Results saved in: %s/\n", output_dir))