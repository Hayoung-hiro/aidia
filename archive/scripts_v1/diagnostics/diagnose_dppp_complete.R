# =============================================================================
# DPPP Diagnosis for All Datasets
# =============================================================================
# Analyzes current DPPP state and recommends cycle times
# =============================================================================

library(arrow)
library(dplyr)
library(ggplot2)
library(tidyr)

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║           DPPP Diagnosis - Current State Analysis               ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Configuration
TARGET_DPPP <- 7.0        # Quantification mode
DPPP_TOLERANCE <- 0.5     # ±0.5 acceptable
SATISFACTION_TARGET <- 0.70  # 70% should meet target

# Function to calculate DPPP from FWHM
calculate_dppp <- function(fwhm_seconds, cycle_time_seconds) {
  # DPPP = (1.7 × FWHM) / cycle_time
  # 1.7 factor: chromatographic peak width = 1.7 × FWHM
  dppp <- (1.7 * fwhm_seconds) / cycle_time_seconds
  return(dppp)
}

# Function to calculate required cycle time for target DPPP
calculate_required_cycle_time <- function(fwhm_seconds, target_dppp) {
  # cycle_time = (1.7 × FWHM) / target_dppp
  cycle_time <- (1.7 * fwhm_seconds) / target_dppp
  return(cycle_time)
}

# Function to diagnose single dataset
diagnose_dataset <- function(file_path) {

  file_name <- basename(file_path)
  base_name <- gsub("\\.parquet$", "", file_name)

  # Load data
  data <- arrow::read_parquet(file_path)

  # Check for FWHM column
  fwhm_col <- NULL
  if ("FWHM" %in% names(data)) {
    fwhm_col <- "FWHM"
  } else if ("FWHM.sec" %in% names(data)) {
    fwhm_col <- "FWHM.sec"
  } else if ("Peak.Width" %in% names(data)) {
    fwhm_col <- "Peak.Width"
  }

  if (is.null(fwhm_col)) {
    # Try to estimate from other columns
    warning(sprintf("No FWHM column found in %s", file_name))
    return(NULL)
  }

  # Extract FWHM values (in seconds)
  fwhm_values <- data[[fwhm_col]]
  fwhm_values <- fwhm_values[!is.na(fwhm_values) & fwhm_values > 0]

  if (length(fwhm_values) == 0) {
    warning(sprintf("No valid FWHM values in %s", file_name))
    return(NULL)
  }

  # Convert to seconds if needed (assuming values > 1 are in seconds, < 1 in minutes)
  if (median(fwhm_values) > 2) {
    # Already in seconds
    fwhm_seconds <- fwhm_values
  } else {
    # Convert from minutes to seconds
    fwhm_seconds <- fwhm_values * 60
  }

  # Calculate FWHM statistics
  fwhm_stats <- list(
    min = min(fwhm_seconds),
    q1 = quantile(fwhm_seconds, 0.25),
    median = median(fwhm_seconds),
    mean = mean(fwhm_seconds),
    q3 = quantile(fwhm_seconds, 0.75),
    max = max(fwhm_seconds),
    sd = sd(fwhm_seconds),
    n = length(fwhm_seconds)
  )

  # Test different cycle times
  cycle_times <- seq(0.5, 10, by = 0.1)  # 0.5 to 10 seconds

  # For each cycle time, calculate DPPP and satisfaction
  cycle_time_analysis <- data.frame(
    cycle_time = cycle_times,
    median_dppp = NA,
    mean_dppp = NA,
    satisfaction_ratio = NA,
    within_tolerance = NA
  )

  for (i in 1:length(cycle_times)) {
    ct <- cycle_times[i]
    dppp_values <- calculate_dppp(fwhm_seconds, ct)

    cycle_time_analysis$median_dppp[i] <- median(dppp_values)
    cycle_time_analysis$mean_dppp[i] <- mean(dppp_values)

    # Calculate satisfaction ratio (% meeting target ± tolerance)
    within_target <- dppp_values >= (TARGET_DPPP - DPPP_TOLERANCE) &
                    dppp_values <= (TARGET_DPPP + DPPP_TOLERANCE)
    cycle_time_analysis$satisfaction_ratio[i] <- mean(within_target)

    # Check if median is within tolerance
    cycle_time_analysis$within_tolerance[i] <-
      cycle_time_analysis$median_dppp[i] >= (TARGET_DPPP - DPPP_TOLERANCE) &
      cycle_time_analysis$median_dppp[i] <= (TARGET_DPPP + DPPP_TOLERANCE)
  }

  # Find optimal cycle time (highest satisfaction ratio)
  optimal_idx <- which.max(cycle_time_analysis$satisfaction_ratio)
  optimal_cycle_time <- cycle_time_analysis$cycle_time[optimal_idx]
  optimal_satisfaction <- cycle_time_analysis$satisfaction_ratio[optimal_idx]
  optimal_median_dppp <- cycle_time_analysis$median_dppp[optimal_idx]

  # Calculate cycle time for exact target DPPP (using median FWHM)
  target_cycle_time <- calculate_required_cycle_time(fwhm_stats$median, TARGET_DPPP)

  # Calculate current DPPP assuming typical cycle times
  # Estimate based on gradient length and typical window counts
  gradient_type <- case_when(
    grepl("30min", base_name) ~ "30min",
    grepl("60min", base_name) ~ "60min",
    grepl("90min", base_name) ~ "90min",
    TRUE ~ "unknown"
  )

  estimated_current_cycle <- case_when(
    gradient_type == "30min" ~ 1.5,  # ~30 windows
    gradient_type == "60min" ~ 2.5,  # ~60 windows
    gradient_type == "90min" ~ 4.0,  # ~80 windows
    TRUE ~ 2.0
  )

  current_dppp_values <- calculate_dppp(fwhm_seconds, estimated_current_cycle)
  current_dppp_stats <- list(
    median = median(current_dppp_values),
    mean = mean(current_dppp_values),
    satisfaction = mean(current_dppp_values >= (TARGET_DPPP - DPPP_TOLERANCE) &
                       current_dppp_values <= (TARGET_DPPP + DPPP_TOLERANCE))
  )

  # Return diagnosis results
  return(list(
    file = base_name,
    gradient_type = gradient_type,
    n_precursors = length(fwhm_seconds),

    # FWHM statistics (seconds)
    fwhm_min = fwhm_stats$min,
    fwhm_q1 = fwhm_stats$q1,
    fwhm_median = fwhm_stats$median,
    fwhm_q3 = fwhm_stats$q3,
    fwhm_max = fwhm_stats$max,

    # Current state (estimated)
    current_cycle_time = estimated_current_cycle,
    current_dppp_median = current_dppp_stats$median,
    current_dppp_mean = current_dppp_stats$mean,
    current_satisfaction = current_dppp_stats$satisfaction,

    # Optimal cycle time
    optimal_cycle_time = optimal_cycle_time,
    optimal_dppp_median = optimal_median_dppp,
    optimal_satisfaction = optimal_satisfaction,

    # Target cycle time
    target_cycle_time = target_cycle_time,

    # Window count estimation (MS1=100ms, MS2=50ms)
    estimated_windows_current = floor((estimated_current_cycle - 0.1) / 0.05),
    estimated_windows_optimal = floor((optimal_cycle_time - 0.1) / 0.05),
    estimated_windows_target = floor((target_cycle_time - 0.1) / 0.05)
  ))
}

# =============================================================================
# Main Analysis
# =============================================================================

# Get all parquet files
parquet_files <- list.files("data", pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("Found %d parquet files for DPPP diagnosis\n\n", length(parquet_files)))

# Analyze each file
all_results <- list()
for (file in parquet_files) {
  cat(sprintf("Analyzing: %s\n", basename(file)))
  result <- diagnose_dataset(file)
  if (!is.null(result)) {
    all_results[[result$file]] <- result
    cat(sprintf("  ✓ FWHM median: %.1f sec\n", result$fwhm_median))
    cat(sprintf("  ✓ Current DPPP: %.1f (%.0f%% satisfaction)\n",
                result$current_dppp_median, result$current_satisfaction * 100))
    cat(sprintf("  ✓ Optimal cycle time: %.1f sec (%.0f%% satisfaction)\n",
                result$optimal_cycle_time, result$optimal_satisfaction * 100))
  }
  cat("\n")
}

# =============================================================================
# Generate Summary Report
# =============================================================================

if (length(all_results) > 0) {

  diagnosis_df <- bind_rows(all_results)

  cat("\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║                    DPPP DIAGNOSIS SUMMARY                       ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  # Group by gradient
  gradient_summary <- diagnosis_df %>%
    group_by(gradient_type) %>%
    summarise(
      n_files = n(),
      avg_fwhm = mean(fwhm_median),

      # Current state
      avg_current_cycle = mean(current_cycle_time),
      avg_current_dppp = mean(current_dppp_median),
      avg_current_satisfaction = mean(current_satisfaction),

      # Optimal
      avg_optimal_cycle = mean(optimal_cycle_time),
      avg_optimal_dppp = mean(optimal_dppp_median),
      avg_optimal_satisfaction = mean(optimal_satisfaction),

      # Target
      avg_target_cycle = mean(target_cycle_time),
      avg_windows_optimal = mean(estimated_windows_optimal),

      .groups = "drop"
    )

  cat("Summary by Gradient Type:\n")
  cat("═══════════════════════════════════════════════════════════════\n\n")

  for (i in 1:nrow(gradient_summary)) {
    cat(sprintf("📊 %s Gradient\n", gradient_summary$gradient_type[i]))
    cat("───────────────────────────────────────────────────────────\n")

    cat("\n📈 FWHM Analysis:\n")
    cat(sprintf("  • Average FWHM: %.1f seconds\n", gradient_summary$avg_fwhm[i]))
    cat(sprintf("  • Chromatographic peak width: %.1f seconds (1.7 × FWHM)\n",
                gradient_summary$avg_fwhm[i] * 1.7))

    cat("\n🔍 Current State (Estimated):\n")
    cat(sprintf("  • Cycle time: %.1f seconds\n", gradient_summary$avg_current_cycle[i]))
    cat(sprintf("  • DPPP: %.1f (Target: %.1f)\n",
                gradient_summary$avg_current_dppp[i], TARGET_DPPP))
    cat(sprintf("  • Satisfaction: %.0f%% (Target: %.0f%%)\n",
                gradient_summary$avg_current_satisfaction[i] * 100,
                SATISFACTION_TARGET * 100))

    status <- if(gradient_summary$avg_current_satisfaction[i] >= SATISFACTION_TARGET) {
      "✅ MEETS TARGET"
    } else {
      "⚠️ NEEDS OPTIMIZATION"
    }
    cat(sprintf("  • Status: %s\n", status))

    cat("\n🎯 Optimal Settings:\n")
    cat(sprintf("  • Recommended cycle time: %.1f seconds\n",
                gradient_summary$avg_optimal_cycle[i]))
    cat(sprintf("  • Expected DPPP: %.1f\n", gradient_summary$avg_optimal_dppp[i]))
    cat(sprintf("  • Expected satisfaction: %.0f%%\n",
                gradient_summary$avg_optimal_satisfaction[i] * 100))
    cat(sprintf("  • Estimated windows: ~%.0f\n", gradient_summary$avg_windows_optimal[i]))

    cat("\n💡 Cycle Time for Exact DPPP %.1f:\n", TARGET_DPPP)
    cat(sprintf("  • Required: %.1f seconds\n", gradient_summary$avg_target_cycle[i]))
    cat(sprintf("  • This allows ~%.0f windows with your MS times\n",
                floor((gradient_summary$avg_target_cycle[i] - 0.1) / 0.05)))

    cat("\n")
  }

  # Detailed table
  cat("\n📋 Detailed Results by Dataset:\n")
  cat("═══════════════════════════════════════════════════════════════\n")
  cat(sprintf("%-20s %10s %10s %12s %12s %12s\n",
              "Dataset", "FWHM (s)", "Current", "Current", "Optimal", "Optimal"))
  cat(sprintf("%-20s %10s %10s %12s %12s %12s\n",
              "", "", "DPPP", "Satisf.", "Cycle (s)", "Satisf."))
  cat("───────────────────────────────────────────────────────────────\n")

  for (i in 1:nrow(diagnosis_df)) {
    cat(sprintf("%-20s %10.1f %10.1f %11.0f%% %12.1f %11.0f%%\n",
                diagnosis_df$file[i],
                diagnosis_df$fwhm_median[i],
                diagnosis_df$current_dppp_median[i],
                diagnosis_df$current_satisfaction[i] * 100,
                diagnosis_df$optimal_cycle_time[i],
                diagnosis_df$optimal_satisfaction[i] * 100))
  }

  # Save results
  output_dir <- "results_dppp_diagnosis"
  if (!dir.exists(output_dir)) {
    dir.create(output_dir)
  }

  # Save detailed results
  write.csv(diagnosis_df,
            file.path(output_dir, "dppp_diagnosis_detailed.csv"),
            row.names = FALSE)

  # Save summary
  write.csv(gradient_summary,
            file.path(output_dir, "dppp_diagnosis_summary.csv"),
            row.names = FALSE)

  cat("\n\n✅ DPPP Diagnosis Complete!\n")
  cat(sprintf("Results saved in: %s/\n", output_dir))

  # Overall recommendation
  cat("\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║                    RECOMMENDATIONS                              ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  overall_satisfaction <- mean(diagnosis_df$current_satisfaction)
  if (overall_satisfaction >= SATISFACTION_TARGET) {
    cat("✅ Current settings are generally GOOD for quantification\n")
    cat(sprintf("   Average satisfaction: %.0f%% (Target: %.0f%%)\n",
                overall_satisfaction * 100, SATISFACTION_TARGET * 100))
  } else {
    cat("⚠️ Current settings need OPTIMIZATION for better quantification\n")
    cat(sprintf("   Average satisfaction: %.0f%% (Target: %.0f%%)\n",
                overall_satisfaction * 100, SATISFACTION_TARGET * 100))

    cat("\nRecommended actions:\n")
    cat("1. Adjust cycle time to optimal values shown above\n")
    cat("2. Reduce window count if cycle time is too long\n")
    cat("3. Consider gradient-specific optimization\n")
  }

  cat("\n🔧 Window Count Guidelines (for your MS1=100ms, MS2=50ms):\n")
  cat(sprintf("  • 30min gradient: ~%.0f windows (%.1f sec cycle time)\n",
              mean(diagnosis_df$estimated_windows_optimal[diagnosis_df$gradient_type == "30min"]),
              mean(diagnosis_df$optimal_cycle_time[diagnosis_df$gradient_type == "30min"])))
  cat(sprintf("  • 60min gradient: ~%.0f windows (%.1f sec cycle time)\n",
              mean(diagnosis_df$estimated_windows_optimal[diagnosis_df$gradient_type == "60min"]),
              mean(diagnosis_df$optimal_cycle_time[diagnosis_df$gradient_type == "60min"])))
  cat(sprintf("  • 90min gradient: ~%.0f windows (%.1f sec cycle time)\n",
              mean(diagnosis_df$estimated_windows_optimal[diagnosis_df$gradient_type == "90min"]),
              mean(diagnosis_df$optimal_cycle_time[diagnosis_df$gradient_type == "90min"])))

} else {
  cat("\n❌ No valid results obtained.\n")
}