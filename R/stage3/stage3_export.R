# stage3_export.R - Export Functions for Stage 3
#
# Purpose: Export DIA windows to CSV and method files for instrument upload
#
# Functions:
#   - export_windows_to_csv(): Single strategy export
#   - export_method_files(): Multi-strategy batch export
#   - print.OptimizedWindows: S3 print method
#   - summary.OptimizedWindows: S3 summary method
#
# Dependencies: dplyr, utils_common.R

library(dplyr)

# =============================================================================
# Single Strategy CSV Export
# =============================================================================

#' Export Windows to CSV for Instrument Upload (Extended Format)
#'
#' Creates instrument-ready CSV file with 22-column extended format
#' compatible with Thermo Orbitrap instruments.
#'
#' @param optimized_windows OptimizedWindows object
#' @param output_file Character, output CSV file path
#' @param validated_data ValidatedData object (for N_Precursors calculation)
#' @param optimization_plan OptimizationPlan object (optional, for cycle time)
#' @param instrument_type Character, instrument type (default: "orbitrap")
#' @param project_name Character, project name for filename (default: "report")
#' @param normalized_agc_target Numeric, AGC target percentage (default: 800)
#'
#' @return NULL (invisible), writes CSV file
#' @export
export_windows_to_csv <- function(optimized_windows, output_file,
                                  validated_data,
                                  optimization_plan = NULL,
                                  instrument_type = "orbitrap",
                                  project_name = "report",
                                  normalized_agc_target = 800) {

  validate_input_type(optimized_windows, "OptimizedWindows", "optimized_windows")
  validate_input_type(validated_data, "ValidatedData", "validated_data")

  # Extract recommended cycle time
  recommended_cycle_time <- if (!is.null(optimization_plan)) {
    optimization_plan$required_cycle_time_sec
  } else {
    NA_real_
  }

  windows <- optimized_windows$windows
  precursor_data <- get_precursor_data(validated_data)

  # Calculate N_Precursors for each window
  cat("  Calculating precursors per window...\n")
  windows_with_counts <- calculate_precursors_per_window(windows, precursor_data)

  # Create 22-column extended format (Thermo Orbitrap compatible)
  method_file <- windows_with_counts %>%
    mutate(
      # Empty columns (Thermo format compatibility)
      Compound = "",
      Formula = "",
      Adduct = "(no adduct)",

      # Core columns
      `m/z` = round(mz_center, 1),
      z = 1,
      `t start (min)` = round(rt_start, 1),
      `t stop (min)` = round(rt_end, 1),
      `Isolation Window (m/z)` = round(mz_end - mz_start, 1),
      `Normalized AGC Target (%)` = normalized_agc_target,
      `Start (m/z)` = round(mz_start, 1),
      `End (m/z)` = round(mz_end, 1),

      # Metadata columns
      Window_ID = row_number(),
      RT_Segment_ID = rt_segment_id,
      RT_Center = round((rt_start + rt_end) / 2, 1),
      RT_Width = round(rt_end - rt_start, 1),
      N_Precursors = n_precursors,
      Overlap_Prev = 0,
      Overlap_Next = 0,

      # Configuration
      Instrument = instrument_type,
      Generation_Method = optimized_windows$parameters$mz_strategy,
      Window_Type = optimized_windows$parameters$window_mode,

      # Column 22: Recommended cycle time (rounded to 1 decimal)
      Recommended_Cycle_Time_Sec = round(recommended_cycle_time, 1)
    ) %>%
    select(Compound, Formula, Adduct, `m/z`, z,
           `t start (min)`, `t stop (min)`,
           `Isolation Window (m/z)`, `Normalized AGC Target (%)`,
           `Start (m/z)`, `End (m/z)`,
           Window_ID, RT_Segment_ID, RT_Center, RT_Width,
           N_Precursors, Overlap_Prev, Overlap_Next,
           Instrument, Generation_Method, Window_Type,
           Recommended_Cycle_Time_Sec)

  # Write CSV file (no header comments for extended format)
  write.csv(method_file, output_file, row.names = FALSE, quote = TRUE)

  cat(sprintf("OK Method file exported: %s (%d windows, 22 columns)\n",
              output_file, nrow(method_file)))
  invisible(NULL)
}

# =============================================================================
# Multi-Strategy Batch Export
# =============================================================================

#' Export Method Files for Multiple Strategies
#'
#' Batch export method CSV files for multiple optimization strategies.
#' Default behavior exports all 4 strategies (quantile, coverage, outlier, smoothing).
#'
#' @param windows_list Named list of OptimizedWindows objects from different strategies
#' @param output_dir Character, output directory path
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2 (optional)
#' @param strategies Character vector of strategies to export (default: all 4)
#' @param instrument_type Character, instrument type (default: "orbitrap")
#' @param normalized_agc_target Numeric, AGC target percentage (default: 100)
#'
#' @return Named list of exported file paths
#'
#' @examples
#' # Export all 4 strategies (default)
#' method_files <- export_method_files(windows_list, "output/", validated_data, plan)
#'
#' # Export specific strategies only
#' method_files <- export_method_files(
#'   windows_list, "output/", validated_data, plan,
#'   strategies = c("smoothing", "quantile")
#' )
#'
#' @export
export_method_files <- function(windows_list,
                                output_dir,
                                validated_data,
                                optimization_plan = NULL,
                                strategies = c("quantile", "coverage", "outlier", "smoothing"),
                                instrument_type = "orbitrap",
                                normalized_agc_target = 100) {

  # Validate inputs
  if (!is.list(windows_list)) {
    stop("windows_list must be a named list of OptimizedWindows objects")
  }

  if (length(windows_list) == 0) {
    stop("windows_list is empty")
  }

  validate_input_type(validated_data, "ValidatedData", "validated_data")

  # Create output directory if needed
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Filter strategies to available ones
  available_strategies <- names(windows_list)
  if (is.null(available_strategies)) {
    stop("windows_list must be a named list (names = strategy names)")
  }

  strategies_to_export <- intersect(strategies, available_strategies)

  if (length(strategies_to_export) == 0) {
    warning(sprintf(
      "No matching strategies found. Available: %s, Requested: %s",
      paste(available_strategies, collapse = ", "),
      paste(strategies, collapse = ", ")
    ))
    return(list())
  }

  # Export each strategy
  cat(sprintf("\nExporting method files for %d strategies...\n", length(strategies_to_export)))

  method_files <- list()
  for (strategy in strategies_to_export) {
    output_file <- file.path(output_dir, sprintf("method_%s.csv", strategy))

    cat(sprintf("  - %s: ", strategy))

    export_windows_to_csv(
      optimized_windows = windows_list[[strategy]],
      output_file = output_file,
      validated_data = validated_data,
      optimization_plan = optimization_plan,
      instrument_type = instrument_type,
      normalized_agc_target = normalized_agc_target
    )

    method_files[[strategy]] <- output_file
  }

  cat("OK All method files exported successfully\n\n")

  invisible(method_files)
}

# =============================================================================
# S3 Methods
# =============================================================================
# Note: S3 methods (print, summary) are now centralized in R/s3_classes.R
# This ensures consistency and reduces code duplication.
# See: print.OptimizedWindows(), summary.OptimizedWindows()

cat("  [stage3_export.R] Export functions loaded\n")
