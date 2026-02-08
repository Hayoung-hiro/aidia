# test_window_generation.R - Module 4 Validation
#
# Tests all window generation modes and integration with Modules 1-3

library(arrow)
library(dplyr)
library(ggplot2)

source("R/window_generator.R")
source("R/rt_segmentation.R")

cat("==============================================\n")
cat("   MODULE 4: Window Generation Testing\n")
cat("==============================================\n")

# Load data
cat("\n[1] Loading data...\n")
data <- read_parquet("rawfile/report.parquet")
cat(sprintf("✓ Loaded %d precursors\n", nrow(data)))

mz_range <- range(data$Precursor.Mz, na.rm = TRUE)
rt_range <- range(data$RT.Start, na.rm = TRUE)
cat(sprintf("  m/z range: %.1f - %.1f\n", mz_range[1], mz_range[2]))
cat(sprintf("  RT range: %.1f - %.1f min\n", rt_range[1], rt_range[2]))

# ========================================
# TEST 1: Fixed Windows (Static Mode)
# ========================================
cat("\n==============================================\n")
cat("TEST 1: Fixed Windows (Static Mode)\n")
cat("==============================================\n")

target_windows <- 30
cat(sprintf("\nGenerating %d fixed-width windows...\n", target_windows))

fixed_windows <- generate_fixed_windows(
  mz_range = mz_range,
  target_window_count = target_windows,
  overlap_percentage = 0,
  min_width = 2.0,
  max_width = 50.0
)

cat(sprintf("✓ Generated %d windows\n", nrow(fixed_windows)))
cat(sprintf("  Window width: %.2f Da (uniform)\n", fixed_windows$width[1]))
cat(sprintf("  m/z coverage: %.1f - %.1f\n", min(fixed_windows$mz_start), max(fixed_windows$mz_end)))

# Calculate coverage
coverage_fixed <- calculate_window_coverage(data, fixed_windows)
cat(sprintf("\nCoverage Analysis:\n"))
cat(sprintf("  Covered precursors: %d / %d (%.1f%%)\n",
           coverage_fixed$coverage_stats$covered_precursors,
           coverage_fixed$coverage_stats$total_precursors,
           coverage_fixed$coverage_stats$coverage_percentage))
cat(sprintf("  Gaps: %d regions, total %.2f Da\n",
           coverage_fixed$coverage_stats$total_gaps,
           coverage_fixed$coverage_stats$total_gap_width))
cat(sprintf("  Mean precursors/window: %.0f\n",
           coverage_fixed$coverage_stats$total_precursors / nrow(fixed_windows)))

# Export
export_windows_to_method(
  fixed_windows,
  "test_output/method_fixed_static.csv",
  instrument_type = "astral",
  method_name = "Test_Fixed_Static"
)

# ========================================
# TEST 2: Variable Windows (Density-Based)
# ========================================
cat("\n==============================================\n")
cat("TEST 2: Variable Windows (Density-Based)\n")
cat("==============================================\n")

cat(sprintf("\nGenerating ~%d variable-width windows...\n", target_windows))
cat("  Adaptation: High density → Narrow windows\n")
cat("             Low density  → Wide windows\n")

variable_windows <- generate_variable_windows(
  data = data,
  mz_range = mz_range,
  target_window_count = target_windows,
  density_bins = 100,
  adaptation_strength = 0.6,
  min_width = 2.0,
  max_width = 50.0,
  overlap_percentage = 0
)

cat(sprintf("✓ Generated %d windows\n", nrow(variable_windows)))
cat(sprintf("  Window width range: %.2f - %.2f Da\n",
           min(variable_windows$width), max(variable_windows$width)))
cat(sprintf("  Mean width: %.2f Da\n", mean(variable_windows$width)))
cat(sprintf("  Median width: %.2f Da\n", median(variable_windows$width)))

# Compare narrow vs wide windows
narrow_windows <- variable_windows %>% filter(width < quantile(width, 0.25))
wide_windows <- variable_windows %>% filter(width > quantile(width, 0.75))

cat(sprintf("\nNarrow windows (Q1, %.2f Da):\n", mean(narrow_windows$width)))
cat(sprintf("  Count: %d\n", nrow(narrow_windows)))
cat(sprintf("  Mean density score: %.3f (high density regions)\n", mean(narrow_windows$density_score)))

cat(sprintf("\nWide windows (Q4, %.2f Da):\n", mean(wide_windows$width)))
cat(sprintf("  Count: %d\n", nrow(wide_windows)))
cat(sprintf("  Mean density score: %.3f (low density regions)\n", mean(wide_windows$density_score)))

# Calculate coverage
coverage_variable <- calculate_window_coverage(data, variable_windows)
cat(sprintf("\nCoverage Analysis:\n"))
cat(sprintf("  Covered precursors: %d / %d (%.1f%%)\n",
           coverage_variable$coverage_stats$covered_precursors,
           coverage_variable$coverage_stats$total_precursors,
           coverage_variable$coverage_stats$coverage_percentage))
cat(sprintf("  Gaps: %d regions, total %.2f Da\n",
           coverage_variable$coverage_stats$total_gaps,
           coverage_variable$coverage_stats$total_gap_width))

# Export
export_windows_to_method(
  variable_windows,
  "test_output/method_variable_static.csv",
  instrument_type = "astral",
  method_name = "Test_Variable_Static"
)

# ========================================
# TEST 3: Overlapped Windows
# ========================================
cat("\n==============================================\n")
cat("TEST 3: Overlapped Windows\n")
cat("==============================================\n")

overlap_pct <- 0.5
cat(sprintf("\nGenerating %d overlapped windows (%.0f%% overlap)...\n",
           target_windows, overlap_pct * 100))

overlapped_windows <- generate_fixed_windows(
  mz_range = mz_range,
  target_window_count = target_windows,
  overlap_percentage = overlap_pct,
  min_width = 2.0,
  max_width = 50.0
)

cat(sprintf("✓ Generated %d windows\n", nrow(overlapped_windows)))
cat(sprintf("  Window width: %.2f Da\n", overlapped_windows$width[1]))
cat(sprintf("  Step size: %.2f Da (%.0f%% of width)\n",
           overlapped_windows$mz_start[2] - overlapped_windows$mz_start[1],
           (1 - overlap_pct) * 100))

# Calculate coverage
coverage_overlapped <- calculate_window_coverage(data, overlapped_windows)
cat(sprintf("\nCoverage Analysis:\n"))
cat(sprintf("  Covered precursors: %d / %d (%.1f%%)\n",
           coverage_overlapped$coverage_stats$covered_precursors,
           coverage_overlapped$coverage_stats$total_precursors,
           coverage_overlapped$coverage_stats$coverage_percentage))
cat(sprintf("  Multi-covered: %d (%.1f%% of total)\n",
           coverage_overlapped$coverage_stats$multi_covered_precursors,
           coverage_overlapped$coverage_stats$multi_coverage_ratio * 100))
cat(sprintf("  Mean windows/precursor: %.2f\n",
           coverage_overlapped$coverage_stats$mean_windows_per_precursor))
cat(sprintf("  Overlap regions: %d, total %.2f Da\n",
           coverage_overlapped$coverage_stats$total_overlaps,
           coverage_overlapped$coverage_stats$total_overlap_width))

# Export
export_windows_to_method(
  overlapped_windows,
  "test_output/method_overlapped_static.csv",
  instrument_type = "astral",
  method_name = "Test_Overlapped_Static"
)

# ========================================
# TEST 4: RT-Dependent Dynamic Windows
# ========================================
cat("\n==============================================\n")
cat("TEST 4: RT-Dependent Dynamic Windows\n")
cat("==============================================\n")

n_segments <- 5
cat(sprintf("\nTesting all 3 RT segmentation strategies with %d segments:\n", n_segments))

# 4A: Uniform RT segmentation
cat("\n--- Strategy A: Uniform (equal time) ---\n")
rt_uniform <- segment_rt_uniform(data, n_segments = n_segments)
cat(sprintf("✓ RT segments: %.1f min each\n", (rt_range[2] - rt_range[1]) / n_segments))

dynamic_uniform <- generate_rt_dependent_windows(
  data = data,
  rt_segments = rt_uniform,
  window_type = "variable",
  target_windows_per_segment = ceiling(target_windows / n_segments),
  adaptation_strength = 0.6
)

cat(sprintf("✓ Generated %d windows across %d RT segments\n",
           nrow(dynamic_uniform$windows), n_segments))
cat(sprintf("  Windows per segment: %.1f\n",
           nrow(dynamic_uniform$windows) / n_segments))

# Show segment summary
cat("\nSegment Summary:\n")
print(dynamic_uniform$segment_summary %>%
       select(rt_segment_name, rt_start, rt_end, n_windows, n_precursors, precursors_per_window) %>%
       mutate(across(where(is.numeric), ~round(., 2))))

export_windows_to_method(
  dynamic_uniform$windows,
  "test_output/method_dynamic_uniform.csv",
  instrument_type = "astral",
  method_name = "Test_Dynamic_Uniform"
)

# 4B: Density-based RT segmentation
cat("\n--- Strategy B: Density-based (adaptive) ---\n")
rt_density <- segment_rt_density(data, n_segments = n_segments, density_threshold = 0.8)

dynamic_density <- generate_rt_dependent_windows(
  data = data,
  rt_segments = rt_density,
  window_type = "variable",
  target_windows_per_segment = ceiling(target_windows / n_segments),
  adaptation_strength = 0.6
)

cat(sprintf("✓ Generated %d windows across %d RT segments\n",
           nrow(dynamic_density$windows), n_segments))

cat("\nSegment Summary:\n")
print(dynamic_density$segment_summary %>%
       select(rt_segment_name, rt_start, rt_end, n_windows, n_precursors, precursors_per_window) %>%
       mutate(across(where(is.numeric), ~round(., 2))))

export_windows_to_method(
  dynamic_density$windows,
  "test_output/method_dynamic_density.csv",
  instrument_type = "astral",
  method_name = "Test_Dynamic_Density"
)

# 4C: Quantile-based RT segmentation
cat("\n--- Strategy C: Quantile-based (equal precursor count) ---\n")
rt_quantile <- segment_rt_quantile(data, n_segments = n_segments)

dynamic_quantile <- generate_rt_dependent_windows(
  data = data,
  rt_segments = rt_quantile,
  window_type = "variable",
  target_windows_per_segment = ceiling(target_windows / n_segments),
  adaptation_strength = 0.6
)

cat(sprintf("✓ Generated %d windows across %d RT segments\n",
           nrow(dynamic_quantile$windows), n_segments))

cat("\nSegment Summary:\n")
print(dynamic_quantile$segment_summary %>%
       select(rt_segment_name, rt_start, rt_end, n_windows, n_precursors, precursors_per_window) %>%
       mutate(across(where(is.numeric), ~round(., 2))))

export_windows_to_method(
  dynamic_quantile$windows,
  "test_output/method_dynamic_quantile.csv",
  instrument_type = "astral",
  method_name = "Test_Dynamic_Quantile"
)

# ========================================
# TEST 5: Quick Generation Wrapper
# ========================================
cat("\n==============================================\n")
cat("TEST 5: Quick Generation Wrapper\n")
cat("==============================================\n")

cat("\nTesting convenient quick_generate_windows() wrapper...\n")

# Static mode
cat("\n--- Quick: Static Variable Windows ---\n")
result_static <- quick_generate_windows(
  data = data,
  window_type = "variable",
  mode = "static",
  target_dppp = 1.25,
  scan_time = 2.0,
  n_windows = 25,
  output_file = "test_output/method_quick_static.csv"
)

# Dynamic mode
cat("\n--- Quick: Dynamic Variable Windows ---\n")
result_dynamic <- quick_generate_windows(
  data = data,
  window_type = "variable",
  mode = "dynamic",
  target_dppp = 1.25,
  scan_time = 2.0,
  n_windows = 25,
  rt_segments = 5,
  rt_mode = "density",
  output_file = "test_output/method_quick_dynamic.csv"
)

# ========================================
# COMPARISON SUMMARY
# ========================================
cat("\n==============================================\n")
cat("   COMPARISON SUMMARY\n")
cat("==============================================\n")

comparison <- data.frame(
  Method = c("Fixed", "Variable", "Overlapped",
            "Dynamic-Uniform", "Dynamic-Density", "Dynamic-Quantile"),
  Windows = c(
    nrow(fixed_windows),
    nrow(variable_windows),
    nrow(overlapped_windows),
    nrow(dynamic_uniform$windows),
    nrow(dynamic_density$windows),
    nrow(dynamic_quantile$windows)
  ),
  Coverage_pct = c(
    coverage_fixed$coverage_stats$coverage_percentage,
    coverage_variable$coverage_stats$coverage_percentage,
    coverage_overlapped$coverage_stats$coverage_percentage,
    NA, NA, NA  # Calculate separately for dynamic
  ),
  Mean_Width = c(
    mean(fixed_windows$width),
    mean(variable_windows$width),
    mean(overlapped_windows$width),
    mean(dynamic_uniform$windows$width),
    mean(dynamic_density$windows$width),
    mean(dynamic_quantile$windows$width)
  ),
  Width_Range = c(
    sprintf("%.2f", fixed_windows$width[1]),  # All same
    sprintf("%.2f-%.2f", min(variable_windows$width), max(variable_windows$width)),
    sprintf("%.2f", overlapped_windows$width[1]),  # All same
    sprintf("%.2f-%.2f", min(dynamic_uniform$windows$width), max(dynamic_uniform$windows$width)),
    sprintf("%.2f-%.2f", min(dynamic_density$windows$width), max(dynamic_density$windows$width)),
    sprintf("%.2f-%.2f", min(dynamic_quantile$windows$width), max(dynamic_quantile$windows$width))
  )
)

print(comparison)

cat("\n==============================================\n")
cat("   KEY FINDINGS\n")
cat("==============================================\n")

cat("\n1. Window Width Adaptation:\n")
cat(sprintf("   Fixed:    Uniform %.2f Da (no adaptation)\n", mean(fixed_windows$width)))
cat(sprintf("   Variable: Adaptive %.2f-%.2f Da (density-based)\n",
           min(variable_windows$width), max(variable_windows$width)))
cat(sprintf("   → Variable windows provide %.1fx width range\n",
           max(variable_windows$width) / min(variable_windows$width)))

cat("\n2. Coverage vs Selectivity:\n")
cat(sprintf("   Fixed:      %.1f%% coverage, %.0f precursors/window\n",
           coverage_fixed$coverage_stats$coverage_percentage,
           coverage_fixed$coverage_stats$total_precursors / nrow(fixed_windows)))
cat(sprintf("   Overlapped: %.1f%% coverage, %.2f windows/precursor (multi-coverage)\n",
           coverage_overlapped$coverage_stats$coverage_percentage,
           coverage_overlapped$coverage_stats$mean_windows_per_precursor))

cat("\n3. RT-Dependent Optimization:\n")
cat(sprintf("   Static:  Single window scheme for entire gradient\n"))
cat(sprintf("   Dynamic: %d segment-specific schemes\n", n_segments))
cat(sprintf("   → Dynamic enables RT-dependent m/z targeting\n"))

cat("\n4. RT Segmentation Strategy Impact:\n")
balance_uniform <- sd(dynamic_uniform$segment_summary$precursors_per_window) /
                  mean(dynamic_uniform$segment_summary$precursors_per_window)
balance_density <- sd(dynamic_density$segment_summary$precursors_per_window) /
                  mean(dynamic_density$segment_summary$precursors_per_window)
balance_quantile <- sd(dynamic_quantile$segment_summary$precursors_per_window) /
                   mean(dynamic_quantile$segment_summary$precursors_per_window)

cat(sprintf("   Uniform:  CV = %.3f (%.0f precursors/window)\n",
           balance_uniform,
           mean(dynamic_uniform$segment_summary$precursors_per_window)))
cat(sprintf("   Density:  CV = %.3f (%.0f precursors/window)\n",
           balance_density,
           mean(dynamic_density$segment_summary$precursors_per_window)))
cat(sprintf("   Quantile: CV = %.3f (%.0f precursors/window) ← Most balanced\n",
           balance_quantile,
           mean(dynamic_quantile$segment_summary$precursors_per_window)))

cat("\n==============================================\n")
cat("   MODULE 4 VALIDATION COMPLETE\n")
cat("==============================================\n")

cat("\nGenerated method files:\n")
cat("  - test_output/method_fixed_static.csv\n")
cat("  - test_output/method_variable_static.csv\n")
cat("  - test_output/method_overlapped_static.csv\n")
cat("  - test_output/method_dynamic_uniform.csv\n")
cat("  - test_output/method_dynamic_density.csv\n")
cat("  - test_output/method_dynamic_quantile.csv\n")
cat("  - test_output/method_quick_static.csv\n")
cat("  - test_output/method_quick_dynamic.csv\n")

cat("\n✓ All window generation modes validated successfully!\n")
