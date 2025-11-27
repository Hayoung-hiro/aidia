# test_complexity_metrics.R - Test DIA Complexity Metrics
# DIA Window Optimizer v2.2
#
# Purpose: Comprehensive testing of complexity measurement functions
# Tests all 6 complexity metrics (PCI, RCI, MSS, CSI, CHS, UDCS)
#
# Usage:
#   source("tests/manual/test_complexity_metrics.R")
#
# Expected Result: All tests PASS
#
# Author: DIAoptimizer Team
# Version: 1.0
# Last Updated: 2025-11-27

# =============================================================================
# Setup
# =============================================================================

# Set working directory if needed
if (!grepl("DIAoptimizer$", getwd())) {
  setwd("~/DIAoptimizer")  # Adjust as needed
}

cat("\n")
cat("╔═══════════════════════════════════════════════════════════════╗\n")
cat("║   DIA Complexity Metrics Test Suite                          ║\n")
cat("╚═══════════════════════════════════════════════════════════════╝\n\n")

# Load required libraries
suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

# Source complexity modules
cat("Loading complexity modules...\n")
source("R/complexity_metrics.R")
source("R/complexity_visualization.R")

# =============================================================================
# Test Data: Use Real Data
# =============================================================================

cat("\n--- Loading Real Data ---\n")

# Find parquet file
data_files <- list.files("data", pattern = "*_report\\.parquet$",
                         recursive = TRUE, full.names = TRUE)

if (length(data_files) == 0) {
  # Try TSV fallback
  data_files <- list.files("data", pattern = "*_report\\.tsv$",
                           recursive = TRUE, full.names = TRUE)
}

if (length(data_files) == 0) {
  cat("ERROR: No DIA-NN report files found in data/ directory\n")
  cat("Please add a DIA-NN output file (*_report.parquet or *_report.tsv)\n")
  stop("Test data not found")
}

# Load data
cat(sprintf("Loading: %s\n", basename(data_files[1])))

# Load with arrow or read TSV
if (grepl("\\.parquet$", data_files[1])) {
  suppressPackageStartupMessages(library(arrow))
  raw_data <- read_parquet(data_files[1])
} else {
  raw_data <- read.delim(data_files[1], stringsAsFactors = FALSE)
}

# Extract essential columns
test_data <- raw_data %>%
  select(any_of(c("RT.Start", "Precursor.Mz", "FWHM"))) %>%
  filter(!is.na(RT.Start), !is.na(Precursor.Mz)) %>%
  as_tibble()

cat(sprintf("Loaded %d precursors\n", nrow(test_data)))
cat(sprintf("RT range: %.1f - %.1f min\n",
            min(test_data$RT.Start), max(test_data$RT.Start)))
cat(sprintf("m/z range: %.1f - %.1f Da\n",
            min(test_data$Precursor.Mz), max(test_data$Precursor.Mz)))


# =============================================================================
# Test Counter
# =============================================================================

tests_passed <- 0
tests_failed <- 0

check_test <- function(condition, test_name, details = NULL) {
  if (condition) {
    cat(sprintf("  [PASS] %s\n", test_name))
    if (!is.null(details)) cat(sprintf("         %s\n", details))
    tests_passed <<- tests_passed + 1
  } else {
    cat(sprintf("  [FAIL] %s\n", test_name))
    if (!is.null(details)) cat(sprintf("         %s\n", details))
    tests_failed <<- tests_failed + 1
  }
}


# =============================================================================
# Test 1: PCI (Precursor Co-isolation Index)
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 1: Precursor Co-isolation Index (PCI)\n")
cat("═══════════════════════════════════════════════\n")

pci_result <- calculate_pci(test_data,
                            rt_window_sec = 60,
                            mz_window_da = 25,
                            sample_size = 2000)

# Validate structure
check_test(
  inherits(pci_result, "PCI"),
  "PCI returns correct class",
  sprintf("Class: %s", paste(class(pci_result), collapse = ", "))
)

check_test(
  !is.null(pci_result$mean_pci) && is.numeric(pci_result$mean_pci),
  "PCI contains mean_pci",
  sprintf("Mean PCI: %.2f", pci_result$mean_pci)
)

check_test(
  pci_result$mean_pci >= 0,
  "PCI mean is non-negative",
  sprintf("Value: %.2f", pci_result$mean_pci)
)

check_test(
  length(pci_result$distribution) > 0,
  "PCI distribution is populated",
  sprintf("N samples: %d", length(pci_result$distribution))
)

check_test(
  !is.null(pci_result$complexity_level),
  "PCI complexity level assigned",
  sprintf("Level: %s", pci_result$complexity_level)
)


# =============================================================================
# Test 2: RCI (RT Crowding Index)
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 2: RT Crowding Index (RCI)\n")
cat("═══════════════════════════════════════════════\n")

rci_result <- calculate_rci(test_data, n_bins = 50)

check_test(
  inherits(rci_result, "RCI"),
  "RCI returns correct class",
  sprintf("Class: %s", paste(class(rci_result), collapse = ", "))
)

check_test(
  rci_result$gini_coefficient >= 0 && rci_result$gini_coefficient <= 1,
  "Gini coefficient in valid range [0,1]",
  sprintf("Gini: %.3f", rci_result$gini_coefficient)
)

check_test(
  rci_result$peak_to_avg_ratio >= 1,
  "Peak-to-avg ratio >= 1",
  sprintf("Ratio: %.2f", rci_result$peak_to_avg_ratio)
)

check_test(
  length(rci_result$bin_counts) == rci_result$n_bins,
  "Correct number of bins",
  sprintf("Bins: %d", rci_result$n_bins)
)

check_test(
  !is.null(rci_result$crowding_level),
  "RCI crowding level assigned",
  sprintf("Level: %s", rci_result$crowding_level)
)


# =============================================================================
# Test 3: MSS (m/z Spacing Score)
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 3: m/z Spacing Score (MSS)\n")
cat("═══════════════════════════════════════════════\n")

mss_result <- calculate_mss(test_data, rt_bin_width_min = 1.0)

check_test(
  inherits(mss_result, "MSS"),
  "MSS returns correct class",
  sprintf("Class: %s", paste(class(mss_result), collapse = ", "))
)

check_test(
  mss_result$global_mean_spacing > 0,
  "Mean spacing is positive",
  sprintf("Mean spacing: %.3f Da", mss_result$global_mean_spacing)
)

check_test(
  mss_result$global_min_spacing >= 0,
  "Min spacing is non-negative",
  sprintf("Min spacing: %.4f Da", mss_result$global_min_spacing)
)

check_test(
  mss_result$critical_pair_ratio >= 0 && mss_result$critical_pair_ratio <= 1,
  "Critical pair ratio in valid range",
  sprintf("Critical pairs: %.2f%%", mss_result$critical_pair_ratio * 100)
)

check_test(
  nrow(mss_result$spacing_by_rt) > 0,
  "Per-RT-bin spacing data available",
  sprintf("RT bins: %d", nrow(mss_result$spacing_by_rt))
)


# =============================================================================
# Test 4: CSI (Chimeric Spectrum Index)
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 4: Chimeric Spectrum Index (CSI)\n")
cat("═══════════════════════════════════════════════\n")

csi_result <- calculate_csi(test_data, windows = NULL)

check_test(
  inherits(csi_result, "CSI"),
  "CSI returns correct class",
  sprintf("Class: %s", paste(class(csi_result), collapse = ", "))
)

check_test(
  csi_result$chimeric_ratio >= 0 && csi_result$chimeric_ratio <= 1,
  "Chimeric ratio in valid range [0,1]",
  sprintf("Chimeric ratio: %.2f%%", csi_result$chimeric_ratio * 100)
)

check_test(
  csi_result$clean_ratio + csi_result$chimeric_ratio == 1,
  "Clean + chimeric ratios sum to 1",
  sprintf("Sum: %.3f", csi_result$clean_ratio + csi_result$chimeric_ratio)
)

check_test(
  csi_result$mean_co_isolation >= 0,
  "Mean co-isolation is non-negative",
  sprintf("Mean: %.2f precursors/window", csi_result$mean_co_isolation)
)

check_test(
  !is.null(csi_result$chimeric_level),
  "CSI chimeric level assigned",
  sprintf("Level: %s", csi_result$chimeric_level)
)


# =============================================================================
# Test 5: CHS (Complexity Heatmap Score)
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 5: Complexity Heatmap Score (CHS)\n")
cat("═══════════════════════════════════════════════\n")

chs_result <- calculate_chs(test_data, rt_bins = 30, mz_bins = 30)

check_test(
  inherits(chs_result, "CHS"),
  "CHS returns correct class",
  sprintf("Class: %s", paste(class(chs_result), collapse = ", "))
)

check_test(
  is.matrix(chs_result$density_matrix),
  "Density matrix is a matrix",
  sprintf("Dimensions: %d x %d", nrow(chs_result$density_matrix),
          ncol(chs_result$density_matrix))
)

check_test(
  chs_result$max_density >= 1,
  "Max density is at least 1",
  sprintf("Max density: %d", chs_result$max_density)
)

check_test(
  chs_result$spatial_entropy >= 0 && chs_result$spatial_entropy <= 1,
  "Spatial entropy in valid range [0,1]",
  sprintf("Entropy: %.3f", chs_result$spatial_entropy)
)

check_test(
  chs_result$occupancy_ratio > 0,
  "Occupancy ratio is positive",
  sprintf("Occupancy: %.1f%%", chs_result$occupancy_ratio * 100)
)


# =============================================================================
# Test 6: UDCS (Unified DIA Complexity Score)
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 6: Unified DIA Complexity Score (UDCS)\n")
cat("═══════════════════════════════════════════════\n")

udcs_result <- calculate_udcs(test_data, verbose = FALSE)

check_test(
  inherits(udcs_result, "UDCS"),
  "UDCS returns correct class",
  sprintf("Class: %s", paste(class(udcs_result), collapse = ", "))
)

check_test(
  udcs_result$total_score >= 0 && udcs_result$total_score <= 100,
  "UDCS total score in valid range [0,100]",
  sprintf("Score: %.1f", udcs_result$total_score)
)

check_test(
  all(sapply(udcs_result$components, function(x) x >= 0 && x <= 25)),
  "All component scores in valid range [0,25]",
  sprintf("Components: D=%.1f, C=%.1f, S=%.1f, Ch=%.1f",
          udcs_result$components$density,
          udcs_result$components$crowding,
          udcs_result$components$spacing,
          udcs_result$components$chimeric)
)

component_sum <- sum(unlist(udcs_result$components))
check_test(
  abs(component_sum - udcs_result$total_score) < 0.1,
  "Component sum equals total score",
  sprintf("Sum: %.1f, Total: %.1f", component_sum, udcs_result$total_score)
)

check_test(
  !is.null(udcs_result$interpretation),
  "UDCS interpretation provided",
  sprintf("Interpretation: %s", substr(udcs_result$interpretation, 1, 50))
)


# =============================================================================
# Test 7: Calculate All Metrics
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 7: Calculate All Complexity Metrics\n")
cat("═══════════════════════════════════════════════\n")

complexity_all <- calculate_all_complexity_metrics(test_data, verbose = FALSE)

check_test(
  inherits(complexity_all, "DIAComplexity"),
  "Returns DIAComplexity class",
  sprintf("Class: %s", paste(class(complexity_all), collapse = ", "))
)

check_test(
  all(c("pci", "rci", "mss", "csi", "chs", "udcs") %in% names(complexity_all)),
  "Contains all 6 metric objects",
  sprintf("Available: %s", paste(names(complexity_all)[1:6], collapse = ", "))
)

check_test(
  !is.null(complexity_all$summary),
  "Summary object included",
  sprintf("UDCS Score: %.1f", complexity_all$summary$udcs_score)
)


# =============================================================================
# Test 8: Visualization Functions
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 8: Visualization Functions\n")
cat("═══════════════════════════════════════════════\n")

# PCI plot
p_pci <- tryCatch({
  plot_pci_distribution(complexity_all$pci)
}, error = function(e) NULL)

check_test(
  !is.null(p_pci) && inherits(p_pci, "ggplot"),
  "PCI plot created successfully",
  "plot_pci_distribution()"
)

# RCI plot
p_rci <- tryCatch({
  plot_rci_profile(complexity_all$rci)
}, error = function(e) NULL)

check_test(
  !is.null(p_rci) && inherits(p_rci, "ggplot"),
  "RCI plot created successfully",
  "plot_rci_profile()"
)

# MSS plot
p_mss <- tryCatch({
  plot_mss_distribution(complexity_all$mss)
}, error = function(e) NULL)

check_test(
  !is.null(p_mss) && inherits(p_mss, "ggplot"),
  "MSS plot created successfully",
  "plot_mss_distribution()"
)

# CSI plot
p_csi <- tryCatch({
  plot_csi_distribution(complexity_all$csi)
}, error = function(e) NULL)

check_test(
  !is.null(p_csi) && inherits(p_csi, "ggplot"),
  "CSI plot created successfully",
  "plot_csi_distribution()"
)

# CHS heatmap
p_chs <- tryCatch({
  plot_chs_heatmap(complexity_all$chs)
}, error = function(e) NULL)

check_test(
  !is.null(p_chs) && inherits(p_chs, "ggplot"),
  "CHS heatmap created successfully",
  "plot_chs_heatmap()"
)

# UDCS radar
p_radar <- tryCatch({
  plot_udcs_radar(complexity_all$udcs)
}, error = function(e) NULL)

check_test(
  !is.null(p_radar) && inherits(p_radar, "ggplot"),
  "UDCS radar plot created successfully",
  "plot_udcs_radar()"
)


# =============================================================================
# Test 9: Edge Cases
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 9: Edge Cases\n")
cat("═══════════════════════════════════════════════\n")

# Small dataset
small_data <- test_data %>% head(100)
small_pci <- tryCatch({
  calculate_pci(small_data, sample_size = 50)
}, error = function(e) NULL)

check_test(
  !is.null(small_pci),
  "PCI handles small dataset (100 rows)",
  sprintf("Mean PCI: %.2f", if (!is.null(small_pci)) small_pci$mean_pci else NA)
)

# Very narrow RT range
narrow_rt_data <- test_data %>%
  filter(RT.Start >= median(RT.Start) - 1 & RT.Start <= median(RT.Start) + 1)

narrow_rci <- tryCatch({
  calculate_rci(narrow_rt_data, n_bins = 10)
}, error = function(e) NULL)

check_test(
  !is.null(narrow_rci),
  "RCI handles narrow RT range (2 min)",
  sprintf("Gini: %.3f", if (!is.null(narrow_rci)) narrow_rci$gini_coefficient else NA)
)


# =============================================================================
# Performance Test
# =============================================================================

cat("\n═══════════════════════════════════════════════\n")
cat("TEST 10: Performance\n")
cat("═══════════════════════════════════════════════\n")

# Time the full complexity analysis
start_time <- Sys.time()
perf_result <- calculate_all_complexity_metrics(test_data, verbose = FALSE)
elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

check_test(
  elapsed < 30,
  sprintf("Full analysis completes in reasonable time (<30s): %.2fs", elapsed),
  sprintf("Dataset size: %d precursors", nrow(test_data))
)


# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("                    TEST SUMMARY                               \n")
cat("═══════════════════════════════════════════════════════════════\n")
cat(sprintf("  Total tests:  %d\n", tests_passed + tests_failed))
cat(sprintf("  Passed:       %d\n", tests_passed))
cat(sprintf("  Failed:       %d\n", tests_failed))
cat("───────────────────────────────────────────────────────────────\n")

if (tests_failed == 0) {
  cat("  Status:       ✅ ALL TESTS PASSED\n")
} else {
  cat(sprintf("  Status:       ❌ %d TEST(S) FAILED\n", tests_failed))
}

cat("═══════════════════════════════════════════════════════════════\n\n")

# Print complexity summary
cat("Complexity Analysis Results:\n")
print(perf_result)


# =============================================================================
# Optional: Save Test Plots
# =============================================================================

if (FALSE) {  # Set to TRUE to save plots
  output_dir <- "output_complexity_test"
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  # Save individual plots
  ggsave(file.path(output_dir, "01_pci_distribution.png"), p_pci,
         width = 10, height = 6, dpi = 150)
  ggsave(file.path(output_dir, "02_rci_profile.png"), p_rci,
         width = 10, height = 6, dpi = 150)
  ggsave(file.path(output_dir, "03_mss_distribution.png"), p_mss,
         width = 10, height = 6, dpi = 150)
  ggsave(file.path(output_dir, "04_csi_distribution.png"), p_csi,
         width = 10, height = 6, dpi = 150)
  ggsave(file.path(output_dir, "05_chs_heatmap.png"), p_chs,
         width = 10, height = 8, dpi = 150)
  ggsave(file.path(output_dir, "06_udcs_radar.png"), p_radar,
         width = 8, height = 8, dpi = 150)

  cat(sprintf("\nPlots saved to: %s/\n", output_dir))
}

# Return test result
invisible(tests_failed == 0)
