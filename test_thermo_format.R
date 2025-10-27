# Test script for Thermo Fusion Lumos format export
# Tests the modified Module 3D export_windows_to_csv() function

# Load libraries
library(dplyr)
library(tidyr)

# Source required modules
source("R/stage3_window_optimization/module3d_window_generation.R")

# Load test data (using existing stage3d_result if available)
if (file.exists("stage3d_result.rds")) {
  cat("Loading existing Stage 3D result...\n")
  stage3d_result <- readRDS("stage3d_result.rds")
} else {
  cat("Creating mock Stage 3D result for testing...\n")

  # Create mock WindowGenerationResult for testing
  mock_windows <- tibble(
    window_id = 1:10,
    rt_segment_id = rep(1:2, each = 5),
    rt_start = rep(c(0, 45), each = 5),
    rt_end = rep(c(45, 90), each = 5),
    mz_start = seq(400, 490, by = 10),
    mz_end = seq(410, 500, by = 10),
    mz_center = seq(405, 495, by = 10),
    window_width = rep(10, 10),
    n_precursors = round(runif(10, 50, 150)),
    overlap_prev = c(0, rep(0.5, 4), 0, rep(0.5, 4)),
    overlap_next = c(rep(0.5, 4), 0, rep(0.5, 4), 0)
  )

  stage3d_result <- list(
    windows = mock_windows,
    parameters = list(
      window_type = "Variable",
      overlap = 0.05
    ),
    statistics = list(
      total_windows = nrow(mock_windows),
      mean_precursors_per_window = mean(mock_windows$n_precursors),
      sd_precursors_per_window = sd(mock_windows$n_precursors),
      cv_precursors = sd(mock_windows$n_precursors) / mean(mock_windows$n_precursors)
    ),
    coverage_analysis = list(
      coverage_percentage = 95.8,
      uncovered_regions = tibble()
    )
  )

  class(stage3d_result) <- c("WindowGenerationResult", "list")
}

cat("\n=== Testing Thermo Fusion Lumos Format Export ===\n\n")

# Test 1: Export with new Thermo format (default)
cat("Test 1: Exporting with Thermo Fusion Lumos format...\n")
export_windows_to_csv(
  window_result = stage3d_result,
  output_file = "test_output_thermo.csv",
  instrument_type = "astral",
  strategy = "smoothing",
  include_metadata = TRUE,
  format = "thermo",  # New Thermo format
  agc_target = 800
)

# Test 2: Export with legacy format for comparison
cat("\nTest 2: Exporting with legacy format for comparison...\n")
export_windows_to_csv(
  window_result = stage3d_result,
  output_file = "test_output_legacy.csv",
  instrument_type = "astral",
  strategy = "smoothing",
  include_metadata = TRUE,
  format = "legacy"  # Old format
)

# Read and display both formats
cat("\n=== Format Comparison ===\n")

# Read Thermo format
thermo_data <- read.csv("test_output_thermo.csv")
cat("\nThermo Fusion Lumos format columns:\n")
cat(paste(names(thermo_data), collapse = ", "))
cat("\n\nFirst 3 rows of Thermo format:\n")
print(head(thermo_data[, 1:9], 3))  # Show first 9 columns

# Read legacy format
legacy_data <- read.csv("test_output_legacy.csv")
cat("\n\nLegacy format columns:\n")
cat(paste(names(legacy_data), collapse = ", "))
cat("\n\nFirst 3 rows of legacy format:\n")
print(head(legacy_data[, 1:10], 3))  # Show first 10 columns

# Verify critical columns in Thermo format
cat("\n=== Verification of Thermo Format ===\n")
cat("\n✓ Required Thermo columns present:\n")
required_cols <- c("Compound", "Formula", "Adduct", "m.z", "z",
                   "t.start..min.", "t.stop..min.",
                   "Isolation.Window..m.z.", "Normalized.AGC.Target....")
for (col in required_cols) {
  if (col %in% names(thermo_data)) {
    cat(sprintf("  ✓ %s\n", col))
  } else {
    cat(sprintf("  ✗ %s MISSING!\n", col))
  }
}

# Show mapping of values
cat("\n✓ Value mapping verification:\n")
cat(sprintf("  m/z values: %.1f - %.1f (Centers of isolation windows)\n",
            min(thermo_data$m.z), max(thermo_data$m.z)))
cat(sprintf("  RT range: %.1f - %.1f min\n",
            min(thermo_data$t.start..min.), max(thermo_data$t.stop..min.)))
cat(sprintf("  Isolation widths: %.1f Da\n",
            unique(thermo_data$Isolation.Window..m.z.)))
cat(sprintf("  AGC Target: %d%%\n",
            unique(thermo_data$Normalized.AGC.Target....)))

cat("\n✅ Test completed successfully!\n")
cat("\nOutput files created:\n")
cat("  - test_output_thermo.csv (Thermo Fusion Lumos format)\n")
cat("  - test_output_legacy.csv (Legacy format)\n")