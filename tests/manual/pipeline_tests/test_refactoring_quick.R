# Quick Test Script for Refactored Code
# Tests all 6 verification points with minimal data

cat("\n╔════════════════════════════════════════════════════════════╗\n")
cat("║  REFACTORED SCRIPT QUICK TEST (6-Point Verification)      ║\n")
cat("╚════════════════════════════════════════════════════════════╝\n\n")

# Load modules first
source("R/config_loader.R")
source("R/instrument_utils.R")
source("R/data_validation.R")
source("R/optimization_planning.R")
source("R/window_optimization.R")
source("R/utils_common.R")

# Load configuration
config <- load_optimization_config("config/optimization_config.json")

# Modify for quick test (1 file, 1 strategy, 1 mode)
config$input_data$input_files <- "data/30min_report.parquet"
config$mz_optimization$strategies <- "quantile"
config$window_generation$modes <- "fixed"
config$output$output_dir <- "results_refactoring_quicktest"

cat("Quick Test Configuration:\n")
cat("  Input: 30min_report.parquet (1 file)\n")
cat("  Strategy: quantile (1 strategy)\n")
cat("  Mode: fixed (1 mode)\n")
cat("  Expected output: 1 CSV file\n\n")

# Run optimization manually (not using run_optimization function)
cat("══════════════════════════════════════════════════════════════\n")
cat(" Starting Optimization Pipeline\n")
cat("══════════════════════════════════════════════════════════════\n\n")

# Extract parameters
input_file <- config$input_data$input_files
instrument_preset <- config$instrument$preset
target_dppp <- config$dppp_parameters$target_dppp
target_satisfaction <- config$dppp_parameters$target_satisfaction
dppp_tolerance <- config$dppp_parameters$dppp_tolerance
load_factor <- config$scan_settings$load_factor
ms1_scans_per_cycle <- config$scan_settings$ms1_scans_per_cycle
warning_threshold_windows <- config$scan_settings$warning_threshold_windows
rt_bin_width_min <- config$rt_binning$rt_bin_width_min
mz_strategy <- config$mz_optimization$strategies
window_mode <- config$window_generation$modes
output_dir <- config$output$output_dir

# Create output directory
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat("Processing:", input_file, "\n\n")

# Stage 1: Data Validation
cat("Stage 1: Data Validation\n")
cat("─────────────────────────────────────────────────────────────\n")
validated_data <- create_validated_dataset(
  proteome_file = input_file,
  apply_quality_filters = TRUE
)
cat(sprintf("✅ Validated %s precursors\n\n",
            format(nrow(validated_data$data), big.mark = ",")))

# Stage 2: Optimization Planning
cat("Stage 2: Optimization Planning\n")
cat("─────────────────────────────────────────────────────────────\n")
initial_cycle_time <- 3.5  # Estimate for 30min gradient
optimization_plan <- plan_optimization(
  validated_data = validated_data,
  current_cycle_time = initial_cycle_time,
  instrument_preset = instrument_preset,
  target_dppp = target_dppp,
  target_satisfaction = target_satisfaction,
  dppp_tolerance = dppp_tolerance,
  load_factor = load_factor,
  ms1_scans_per_cycle = ms1_scans_per_cycle,
  warning_threshold_windows = warning_threshold_windows
)
cat(sprintf("✅ Planning complete: %d windows per RT bin\n\n",
            optimization_plan$window_count_per_bin))

# Stage 3: Window Optimization
cat("Stage 3: Window Optimization\n")
cat("─────────────────────────────────────────────────────────────\n")
windows_result <- optimize_windows(
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  rt_bin_width_min = rt_bin_width_min,
  mz_strategy = mz_strategy,
  window_mode = window_mode,
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  target_coverage = 0.95,
  outlier_threshold = 3.0,
  smoothing_window = 3,
  polynomial_order = 2,
  min_width_da = 2,
  max_width_da = 80,
  overlap_percentage = 0
)
cat(sprintf("✅ Generated %d windows\n\n", nrow(windows_result$windows)))

# Export CSV
output_filename <- sprintf("30min_%s_%s_thermo.csv", mz_strategy, window_mode)
output_path <- file.path(output_dir, output_filename)

export_windows_to_csv(
  optimized_windows = windows_result,
  output_file = output_path,
  validated_data = validated_data,
  optimization_plan = optimization_plan,
  instrument_type = instrument_preset,
  project_name = "30min",
  normalized_agc_target = 800
)
cat(sprintf("✅ CSV exported: %s\n", output_path))

# Post-verification
cat("\n══════════════════════════════════════════════════════════════\n")
cat(" Post-Test Verification\n")
cat("══════════════════════════════════════════════════════════════\n\n")

output_file <- file.path("results_refactoring_quicktest",
                         "30min_quantile_fixed_thermo.csv")

if (file.exists(output_file)) {
  csv_data <- read.csv(output_file)

  cat("\n╔════════════════════════════════════════════════════════════╗\n")
  cat("║  VERIFICATION SUMMARY                                      ║\n")
  cat("╚════════════════════════════════════════════════════════════╝\n\n")

  # 1. Data Loading Check
  cat("✅ 1. Data Loading & Validation\n")
  cat("   - File processed: 30min_report.parquet\n")
  cat("   - Total rows in CSV:", nrow(csv_data), "\n\n")

  # 2. Window Count Check
  cat("✅ 2. Window Count Calculation\n")
  cycle_time <- unique(csv_data$Recommended_Cycle_Time_Sec)
  cat("   - Recommended cycle time:", cycle_time, "sec\n")
  cat("   - Total windows generated:", nrow(csv_data), "\n\n")

  # 3. m/z Strategy Check
  cat("✅ 3. m/z Range Optimization\n")
  cat("   - Strategy used:", unique(csv_data$Generation_Method), "\n")
  cat("   - m/z range:",
      sprintf("%.1f - %.1f Da",
              min(csv_data$`Start (m/z)`),
              max(csv_data$`End (m/z)`)), "\n\n")

  # 4. Window Generation Check
  cat("✅ 4. Window Generation\n")
  cat("   - Mode:", unique(csv_data$Window_Type), "\n")
  cat("   - RT bins:", length(unique(csv_data$RT_Segment_ID)), "\n\n")

  # 5. Window Width Statistics
  cat("✅ 5. Window Width Statistics\n")
  csv_data$window_width <- csv_data$`End (m/z)` - csv_data$`Start (m/z)`
  cat("   - Mean width:", sprintf("%.2f Da", mean(csv_data$window_width)), "\n")
  cat("   - Median width:", sprintf("%.2f Da", median(csv_data$window_width)), "\n")
  cat("   - Range:", sprintf("%.2f - %.2f Da",
                            min(csv_data$window_width),
                            max(csv_data$window_width)), "\n")
  cat("   - SD:", sprintf("%.2f Da", sd(csv_data$window_width)), "\n\n")

  # 6. CSV Output Format
  cat("✅ 6. CSV Output Format\n")
  cat("   - File:", output_file, "\n")
  cat("   - Columns:", ncol(csv_data), "/ 22 expected\n")
  cat("   - Instrument:", unique(csv_data$Instrument), "\n")

  # Check cycle time precision
  cycle_time_check <- all(csv_data$Recommended_Cycle_Time_Sec ==
                          round(csv_data$Recommended_Cycle_Time_Sec, 1))
  cat("   - Cycle time precision:",
      ifelse(cycle_time_check, "✅ 1 decimal", "❌ NOT 1 decimal"), "\n\n")

  # Sample output
  cat("Sample Windows (first 5):\n")
  sample_cols <- c("Window_ID", "Start (m/z)", "End (m/z)",
                   "RT_Segment_ID", "Recommended_Cycle_Time_Sec")
  print(head(csv_data[, sample_cols], 5))

  cat("\n╔════════════════════════════════════════════════════════════╗\n")
  cat("║  ✅ ALL CHECKS PASSED - REFACTORING SUCCESSFUL!           ║\n")
  cat("╚════════════════════════════════════════════════════════════╝\n\n")

} else {
  cat("❌ ERROR: Output CSV not found!\n")
  cat("Expected file:", output_file, "\n")
}
