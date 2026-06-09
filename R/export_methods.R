# export_methods.R - Export Functions for Stage 3
#
# Purpose: Export DIA windows to CSV and method files for instrument upload
#
# Functions:
#   - export_windows_to_csv(): Single strategy Thermo CSV export
#   - export_center_mass_list(): Generic center mass + width format
#   - export_mz_range_list(): Generic m/z boundary format
#   - export_batch_comparison(): Multi-strategy, multi-format batch export + comparison
#   - export_method_files(): Multi-strategy Thermo CSV batch export
#
# Dependencies: dplyr, utils_common.R, window_statistics.R


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
#' @export
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
#' Creates an instrument-ready CSV file in the 8-column Thermo Xcalibur Targeted
#' Mass List format, compatible with Thermo Orbitrap instruments.
#'
#' @param optimized_windows OptimizedWindows object
#' @param output_file Character, output CSV file path
#' @param validated_data ValidatedData object (for N_Precursors calculation)
#' @param charge_state Integer, value for the `z` column (default: 1). DIA wide
#'   windows isolate by m/z range, so charge is metadata only and does not affect
#'   acquisition. Default is 1 (the Xcalibur default) because Xcalibur's mass-list
#'   importer flags `z = 0` as invalid and drops it, forcing manual re-entry.
#'   Set to 0 to request "ignore charge state" if your importer accepts it.
#'
#' @return NULL (invisible), writes CSV file
#' @export
export_windows_to_csv <- function(optimized_windows, output_file,
                                  validated_data,
                                  charge_state = 1L) {

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
    windows_with_counts$.compound <- as.character(seq_len(nrow(windows_with_counts)))
    loop_n <- NULL
  }

  # Create Thermo Xcalibur Targeted Mass List format
  # 8 core columns: Compound, Formula, Adduct, m/z, z, RT Time (min), Window (min), Isolation Window (m/z)
  # NOTE: Compound is read from the pre-built .compound column (never a bare
  # `if (is_staggered)` inside mutate() — `is_staggered` is also a data column
  # on staggered windows, which would shadow the scalar and break the if()).
  method_file <- windows_with_counts %>%
    mutate(
      Compound = .compound,
      Formula = "",
      Adduct = "",
      `m/z` = round(mz_center, 4),
      z = charge_state,
      `RT Time (min)` = round((rt_start + rt_end) / 2, 1),
      `Window (min)` = round(rt_end - rt_start, 1),
      `Isolation Window (m/z)` = round(mz_end - mz_start, 4)
    )

  base_cols <- c("Compound", "Formula", "Adduct", "m/z", "z",
                 "RT Time (min)", "Window (min)", "Isolation Window (m/z)")

  method_file <- method_file %>% select(all_of(base_cols))

  # Write CSV file
  write.csv(method_file, output_file, row.names = FALSE, quote = FALSE)

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
# Generic Format Exports
# =============================================================================

#' Export Center Mass List (Generic Format)
#'
#' Creates a 2-column CSV with window center mass and width.
#' Compatible with various DIA method software.
#'
#' @param optimized_windows OptimizedWindows object
#' @param output_file Character, output CSV file path
#'
#' @return NULL (invisible), writes CSV file
#' @export
export_center_mass_list <- function(optimized_windows, output_file) {
  validate_input_type(optimized_windows, "OptimizedWindows", "optimized_windows")
  windows <- optimized_windows$windows

  center_mass_df <- data.frame(
    `Center Mass (m/z)` = round(windows$mz_center, 7),
    `Window Width (m/z)` = round(windows$window_width, 7),
    check.names = FALSE
  )

  write.csv(center_mass_df, output_file, row.names = FALSE, quote = FALSE)
  cat(sprintf("OK Center mass list exported: %s (%d windows)\n", output_file, nrow(center_mass_df)))
  invisible(NULL)
}


#' Export m/z Range List (Boundary Format)
#'
#' Creates a single-column CSV with m/z start-end range pairs.
#' 7 decimal places for precision. Useful for method verification.
#'
#' @param optimized_windows OptimizedWindows object
#' @param output_file Character, output CSV file path
#'
#' @return NULL (invisible), writes CSV file
#' @export
export_mz_range_list <- function(optimized_windows, output_file) {
  validate_input_type(optimized_windows, "OptimizedWindows", "optimized_windows")
  windows <- optimized_windows$windows

  # Single column format: " start-end" with space prefix and 7 decimal places
  range_values <- sprintf(" %.7f-%.7f", windows$mz_start, windows$mz_end)
  range_df <- data.frame(`m/z range` = range_values, check.names = FALSE)

  write.csv(range_df, output_file, row.names = FALSE, quote = FALSE)
  cat(sprintf("OK m/z range list exported: %s (%d windows)\n", output_file, nrow(range_df)))
  invisible(NULL)
}


# =============================================================================
# Batch Strategy Comparison Export
# =============================================================================

#' Export Batch Strategy Comparison
#'
#' Runs multiple strategies and exports all format variants plus a comparison summary.
#' Creates subdirectories for each format (thermo, center_mass, mz_range) and
#' an optional comparison.csv with per-strategy metrics.
#'
#' @param windows_list Named list of OptimizedWindows objects
#' @param validated_data ValidatedData object
#' @param output_dir Character, output directory path
#' @param formats Character vector, export formats (default: all 3)
#' @param include_comparison Logical, include comparison.csv (default: TRUE)
#'
#' @return Character, path to output directory (invisible)
#' @export
export_batch_comparison <- function(windows_list,
                                    validated_data,
                                    output_dir,
                                    formats = c("thermo", "center_mass", "mz_range"),
                                    include_comparison = TRUE) {

  # Validate inputs
  if (!is.list(windows_list) || length(windows_list) == 0) {
    stop("windows_list must be a non-empty named list of OptimizedWindows objects")
  }
  if (is.null(names(windows_list))) {
    stop("windows_list must be a named list (names = strategy names)")
  }
  validate_input_type(validated_data, "ValidatedData", "validated_data")

  # Create output subdirectories
  subdirs <- list(
    thermo      = file.path(output_dir, "thermo"),
    center_mass = file.path(output_dir, "center_mass"),
    mz_range    = file.path(output_dir, "mz_range")
  )
  for (fmt in formats) {
    if (!dir.exists(subdirs[[fmt]])) {
      dir.create(subdirs[[fmt]], recursive = TRUE, showWarnings = FALSE)
    }
  }

  precursor_data <- get_precursor_data(validated_data)
  strategies <- names(windows_list)
  cat(sprintf("\nBatch export: %d strategies x %d formats\n",
              length(strategies), length(formats)))

  # Export each strategy in each format
  for (strategy in strategies) {
    opt_win <- windows_list[[strategy]]
    file_stem <- sprintf("%s_%s", strategy,
                         format(Sys.Date(), "%Y%m%d"))

    cat(sprintf("  - %s: ", strategy))

    if ("thermo" %in% formats) {
      export_windows_to_csv(
        optimized_windows = opt_win,
        output_file = file.path(subdirs$thermo, paste0(file_stem, "_thermo.csv")),
        validated_data = validated_data
      )
    }
    if ("center_mass" %in% formats) {
      export_center_mass_list(
        optimized_windows = opt_win,
        output_file = file.path(subdirs$center_mass, paste0(file_stem, "_center_mass.csv"))
      )
    }
    if ("mz_range" %in% formats) {
      export_mz_range_list(
        optimized_windows = opt_win,
        output_file = file.path(subdirs$mz_range, paste0(file_stem, "_mz_range.csv"))
      )
    }
  }

  # Generate comparison summary
  if (include_comparison && length(strategies) > 1) {
    cat("  Generating comparison.csv...\n")

    comparison_rows <- lapply(strategies, function(strategy) {
      opt_win <- windows_list[[strategy]]
      windows <- opt_win$windows

      # Calculate window statistics for coverage
      win_stats <- calculate_window_statistics_internal(
        windows = calculate_precursors_per_window(windows, precursor_data),
        precursor_data = precursor_data
      )

      widths <- get_window_widths(windows)

      data.frame(
        strategy          = strategy,
        n_windows         = nrow(windows),
        mean_width_da     = round(mean(widths, na.rm = TRUE), 2),
        width_cv          = round(calculate_cv(widths), 4),
        coverage_pct      = round(win_stats$coverage_percentage, 2),
        load_balance_cv   = round(win_stats$cv_precursors, 4),
        min_precursors    = win_stats$min_precursors_per_window,
        max_precursors    = win_stats$max_precursors_per_window,
        mean_precursors   = round(win_stats$mean_precursors_per_window, 1),
        stringsAsFactors  = FALSE
      )
    })

    comparison_df <- do.call(rbind, comparison_rows)
    comparison_file <- file.path(output_dir, "comparison.csv")
    write.csv(comparison_df, comparison_file, row.names = FALSE)
    cat(sprintf("OK Comparison saved: %s (%d strategies)\n",
                comparison_file, nrow(comparison_df)))
  }

  cat("OK Batch export complete\n\n")
  invisible(output_dir)
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
#' @param strategies Character vector of strategies to export (default: all 4)
#' @param instrument_type Character, instrument type (default: "orbitrap")
#'
#' @return Named list of exported file paths
#'
#' @examples
#' \dontrun{
#' # Export all 4 strategies (default)
#' method_files <- export_method_files(windows_list, "output/", validated_data)
#'
#' # Export specific strategies only
#' method_files <- export_method_files(
#'   windows_list, "output/", validated_data,
#'   strategies = c("greedy", "quantile")
#' )
#' }
#'
#' @export
export_method_files <- function(windows_list,
                                output_dir,
                                validated_data,
                                strategies = STRATEGY_PREFERRED_ORDER,
                                instrument_type = "orbitrap") {

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
      validated_data = validated_data
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

