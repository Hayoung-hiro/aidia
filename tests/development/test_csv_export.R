# test_csv_export.R - Test CSV export with correct metadata

library(dplyr)

# Source module
source("R/stage3_window_optimization/module3d_window_generation.R")

# Load existing results
cat("Loading Orbitrap results...\n")
window_result <- readRDS("final_test_orbitrap/stage3d_windows_quantile_variable.rds")

# Create test output directory
test_dir <- "test_csv_output"
if (!dir.exists(test_dir)) dir.create(test_dir)

cat("\nTesting CSV export with correct metadata...\n")
cat("  Instrument: orbitrap\n")
cat("  Strategy: quantile\n")
cat("  Mode: variable\n\n")

# Export CSV with correct parameters
export_windows_to_csv(
  window_result = window_result,
  output_file = file.path(test_dir, "windows_quantile_variable_test.csv"),
  instrument_type = "orbitrap",
  strategy = "quantile",
  include_metadata = TRUE
)

cat("\nChecking exported CSV...\n")
csv_data <- read.csv(file.path(test_dir, "windows_quantile_variable_test.csv"))

cat(sprintf("  Rows: %d\n", nrow(csv_data)))
cat(sprintf("  Columns: %d\n", ncol(csv_data)))
cat(sprintf("\nFirst row metadata:\n"))
cat(sprintf("  Instrument: %s\n", csv_data$Instrument[1]))
cat(sprintf("  Generation_Method: %s\n", csv_data$Generation_Method[1]))
cat(sprintf("  Window_Type: %s\n", csv_data$Window_Type[1]))

cat("\n✅ CSV export test complete!\n")
cat(sprintf("   Output: %s\n", file.path(test_dir, "windows_smoothing_variable_test.csv")))
