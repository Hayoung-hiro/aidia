# export_methods.R - Export Functions for Stage 3
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


# =============================================================================
# Loop N Helper (shared by export + visualization)
# =============================================================================

#' Calculate Loop N for Staggered DIA
#'
#' Determines the number of windows per cycle per RT bin (Loop Control N)
#' from a staggered windows data frame. Returns NULL for non-staggered windows.
#'
#' @param windows Data frame with columns: cycle, rt_segment_id
#'
#' @return Integer Loop N value, or NULL if not staggered
#' @keywords internal
calculate_loop_n <- function(windows) {
  if (!"cycle" %in% colnames(windows)) return(NULL)

  loop_count <- windows %>%
    filter(cycle == 1L) %>%
    count(rt_segment_id) %>%
    pull(n)
  loop_n <- unique(loop_count)

  if (length(loop_n) > 1) {
    warning(sprintf("Staggered window count varies across RT bins (%s). Loop Control may misalign.",
                    paste(loop_n, collapse = ", ")))
  }
  loop_n[1]
}


# =============================================================================
# Single Strategy CSV Export
# =============================================================================

#' Export Windows to CSV for Instrument Upload
#'
#' Creates instrument-ready CSV file with 16-column format (17 for staggered)
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

  windows <- optimized_windows$windows
  precursor_data <- get_precursor_data(validated_data)
  is_staggered <- "cycle" %in% colnames(windows)

  # Calculate N_Precursors for each window
  cat("  Calculating precursors per window...\n")
  windows_with_counts <- calculate_precursors_per_window(windows, precursor_data)

  # --- Staggered: Compound naming + Loop Count ---
  if (is_staggered) {
    windows_with_counts <- windows_with_counts %>%
      group_by(rt_segment_id, cycle) %>%
      mutate(.win_seq = row_number()) %>%
      ungroup() %>%
      mutate(.compound = sprintf("C%d_RT%d_W%02d", cycle, rt_segment_id, .win_seq))

    loop_n <- calculate_loop_n(windows_with_counts)
  } else {
    windows_with_counts$.compound <- ""
    loop_n <- NULL
  }

  # Create extended format (Thermo Orbitrap compatible)
  method_file <- windows_with_counts %>%
    mutate(
      # Thermo format columns
      Compound = .compound,
      Formula = "",
      Adduct = "(no adduct)",

      # Core columns
      `m/z` = round(mz_center, 4),
      z = 0,
      `t start (min)` = round(rt_start, 1),
      `t stop (min)` = round(rt_end, 1),
      `Isolation Window (m/z)` = round(mz_end - mz_start, 4),
      `Normalized AGC Target (%)` = normalized_agc_target,
      `Start (m/z)` = round(mz_start, 4),
      `End (m/z)` = round(mz_end, 4),

      # Metadata columns
      Window_ID = row_number(),
      RT_Segment_ID = rt_segment_id,
      RT_Center = round((rt_start + rt_end) / 2, 1),
      RT_Width = round(rt_end - rt_start, 1),
      N_Precursors = n_precursors
    )

  # Column selection: base 16 + Cycle for staggered
  base_cols <- c("Compound", "Formula", "Adduct", "m/z", "z",
                 "t start (min)", "t stop (min)",
                 "Isolation Window (m/z)", "Normalized AGC Target (%)",
                 "Start (m/z)", "End (m/z)",
                 "Window_ID", "RT_Segment_ID", "RT_Center", "RT_Width",
                 "N_Precursors")

  if (is_staggered) {
    method_file$Cycle <- windows_with_counts$cycle
    base_cols <- c(base_cols, "Cycle")
  }

  method_file <- method_file %>% select(all_of(base_cols))

  # Write CSV file
  write.csv(method_file, output_file, row.names = FALSE, quote = TRUE)

  n_cols <- ncol(method_file)
  cat(sprintf("OK Method file exported: %s (%d windows, %d columns)\n",
              output_file, nrow(method_file), n_cols))

  # Staggered: print Loop Control guidance
  if (is_staggered && !is.null(loop_n)) {
    n_bins <- length(unique(windows$rt_segment_id))
    cat(sprintf("   Staggered DIA: Set Loop Control N = %d (windows per RT bin per cycle)\n", loop_n))
    cat(sprintf("   Layout: %d RT bins x %d windows/cycle x 2 cycles, C1-first ordering\n",
                n_bins, loop_n))
  }
  invisible(NULL)
}

# =============================================================================
# Multi-Strategy Batch Export
# =============================================================================

#' Export Method Files for Multiple Strategies
#'
#' Batch export method CSV files for multiple optimization strategies.
#' Default behavior exports all 5 strategies (greedy, kde, quantile, coverage, outlier).
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
#' \dontrun{
#' # Export all 4 strategies (default)
#' method_files <- export_method_files(windows_list, "output/", validated_data, plan)
#'
#' # Export specific strategies only
#' method_files <- export_method_files(
#'   windows_list, "output/", validated_data, plan,
#'   strategies = c("greedy", "quantile")
#' )
#' }
#'
#' @export
export_method_files <- function(windows_list,
                                output_dir,
                                validated_data,
                                optimization_plan = NULL,
                                strategies = STRATEGY_PREFERRED_ORDER,
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
    # Build filename using standardized naming if available
    output_filename <- if (exists("format_output_filename") &&
                           !is.null(windows_list[[strategy]]$parameters$window_mode)) {
      params <- windows_list[[strategy]]$parameters
      format_output_filename(
        type = "method",
        instrument_preset = instrument_type,
        strategy = strategy,
        window_mode = params$window_mode %||% "density",
        rt_binning_mode = params$rt_binning_mode %||% "fixed",
        rt_bin_width_min = params$rt_bin_width_min %||% 5
      )
    } else {
      sprintf("method_%s.csv", strategy)
    }
    output_file <- file.path(output_dir, output_filename)

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

