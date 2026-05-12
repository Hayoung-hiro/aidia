# s3_classes.R - Centralized S3 Class Definitions
#
# Purpose: Provide formal S3 class infrastructure for the DIA Window Optimizer
#          pipeline with consistent constructors, validators, and methods.
#
# Version: 2.1 (Phase 2 Refactoring)
#
# Classes:
#   - ValidatedData: Stage 1 output (validated precursor data)
#   - OptimizationPlan: Stage 2 output (DPPP diagnosis + window planning)
#   - OptimizedWindows: Stage 3 output (generated isolation windows)
#   - VisualizationResult: Stage 4 output (plots and reports)
#
# Pattern: Each class follows R's S3 best practices:
#   1. Low-level constructor (new_*) - Internal, no validation
#   2. Validator (validate_*) - Check object integrity
#   3. User constructor (*) - Public API with validation
#   4. Type checking (is_*) - Predicate functions
#   5. Coercion (as_*) - Convert from other types

# =============================================================================
# Class 1: ValidatedData
# =============================================================================

#' Low-level ValidatedData Constructor (Internal)
#'
#' Creates a ValidatedData object without validation. For internal use only.
#'
#' @param data Tibble with precursor data
#' @param metadata List with data metadata
#' @param validation_status List with validation results
#' @param file_info List with source file information
#'
#' @return ValidatedData S3 object
#' @keywords internal
new_ValidatedData <- function(data,
                               metadata = list(),
                               validation_status = list(),
                               file_info = list()) {
  structure(
    list(
      data = data,
      metadata = metadata,
      validation_status = validation_status,
      file_info = file_info
    ),
    class = c("ValidatedData", "list")
  )
}

#' Validate ValidatedData Object
#'
#' Checks that a ValidatedData object has all required components
#' and that they meet the expected format.
#'
#' @param x Object to validate
#'
#' @return The object (invisibly) if valid, throws error if not
#' @export
validate_ValidatedData <- function(x) {
  # Check class

if (!inherits(x, "ValidatedData")) {
    stop("Object must be of class 'ValidatedData'", call. = FALSE)
  }

  # Check required fields
  required_fields <- c("data", "metadata", "validation_status")
  missing_fields <- setdiff(required_fields, names(x))
  if (length(missing_fields) > 0) {
    stop(sprintf("ValidatedData missing required fields: %s",
                 paste(missing_fields, collapse = ", ")), call. = FALSE)
  }

  # Check data is a data frame
  if (!is.data.frame(x$data)) {
    stop("ValidatedData$data must be a data frame", call. = FALSE)
  }

  # Check required columns in data
  required_cols <- c("Precursor.Mz", "RT.Apex", "FWHM")
  missing_cols <- setdiff(required_cols, names(x$data))
  if (length(missing_cols) > 0) {
    stop(sprintf("ValidatedData$data missing required columns: %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)
  }

  # Check metadata fields
  required_meta <- c("n_precursors", "rt_range", "mz_range")
  missing_meta <- setdiff(required_meta, names(x$metadata))
  if (length(missing_meta) > 0) {
    stop(sprintf("ValidatedData$metadata missing required fields: %s",
                 paste(missing_meta, collapse = ", ")), call. = FALSE)
  }

  invisible(x)
}

#' Check if Object is ValidatedData
#'
#' @param x Object to check
#' @return Logical, TRUE if object is ValidatedData
#' @export
is_ValidatedData <- function(x) {
  inherits(x, "ValidatedData")
}

#' Coerce to ValidatedData
#'
#' Attempts to convert a data frame to ValidatedData object.
#'
#' @param x Object to coerce (data.frame with precursor data)
#' @param ... Additional arguments passed to constructor
#'
#' @return ValidatedData object
#' @export
as_ValidatedData <- function(x, ...) {
  UseMethod("as_ValidatedData")
}

#' @export
as_ValidatedData.data.frame <- function(x, ...) {
  # Calculate metadata from data frame
  metadata <- list(
    n_precursors = nrow(x),
    rt_range = range(x$RT.Apex, na.rm = TRUE),
    mz_range = range(x$Precursor.Mz, na.rm = TRUE),
    fwhm_stats = list(
      mean = mean(x$FWHM, na.rm = TRUE),
      median = median(x$FWHM, na.rm = TRUE),
      sd = sd(x$FWHM, na.rm = TRUE)
    )
  )

  validation_status <- list(
    all_passed = TRUE,
    quality_score = 1.0,
    n_warnings = 0,
    n_errors = 0,
    warnings = character(0),
    errors = character(0)
  )

  result <- new_ValidatedData(
    data = x,
    metadata = metadata,
    validation_status = validation_status,
    file_info = list(source = "coerced", timestamp = Sys.time())
  )

  validate_ValidatedData(result)
  result
}

# =============================================================================
# Class 2: OptimizationPlan
# =============================================================================

#' Low-level OptimizationPlan Constructor (Internal)
#'
#' @param window_count_per_bin Integer, optimal window count per RT bin
#' @param required_cycle_time_sec Numeric, required cycle time
#' @param actual_cycle_time_sec Numeric, actual calculated cycle time
#' @param diagnosis List with DPPP diagnosis results
#' @param recommendation List with adjustment recommendations
#' @param feasibility List with feasibility assessment
#' @param instrument List with instrument configuration
#' @param parameters List with planning parameters
#'
#' @return OptimizationPlan S3 object
#' @keywords internal
new_OptimizationPlan <- function(window_count_per_bin,
                                  required_cycle_time_sec,
                                  actual_cycle_time_sec,
                                  diagnosis = list(),
                                  recommendation = list(),
                                  feasibility = list(),
                                  instrument = list(),
                                  parameters = list()) {
  structure(
    list(
      window_count_per_bin = window_count_per_bin,
      required_cycle_time_sec = required_cycle_time_sec,
      actual_cycle_time_sec = actual_cycle_time_sec,
      diagnosis = diagnosis,
      recommendation = recommendation,
      feasibility = feasibility,
      instrument = instrument,
      parameters = parameters
    ),
    class = c("OptimizationPlan", "list")
  )
}

#' Validate OptimizationPlan Object
#'
#' @param x Object to validate
#' @return The object (invisibly) if valid, throws error if not
#' @export
validate_OptimizationPlan <- function(x) {
  if (!inherits(x, "OptimizationPlan")) {
    stop("Object must be of class 'OptimizationPlan'", call. = FALSE)
  }

  # Check required fields
  required_fields <- c("window_count_per_bin", "required_cycle_time_sec",
                       "actual_cycle_time_sec", "diagnosis", "feasibility",
                       "instrument")
  missing_fields <- setdiff(required_fields, names(x))
  if (length(missing_fields) > 0) {
    stop(sprintf("OptimizationPlan missing required fields: %s",
                 paste(missing_fields, collapse = ", ")), call. = FALSE)
  }

  # Validate numeric fields
  if (!is.numeric(x$window_count_per_bin) || x$window_count_per_bin < 1) {
    stop("window_count_per_bin must be a positive integer", call. = FALSE)
  }

  if (!is.numeric(x$required_cycle_time_sec) || x$required_cycle_time_sec <= 0) {
    stop("required_cycle_time_sec must be a positive number", call. = FALSE)
  }

  # Check diagnosis fields
  required_diag <- c("current_cycle_time_sec", "current_ct_is_estimated",
                      "current_satisfaction_ratio", "current_dppp_mean",
                      "current_dppp_median", "current_dppp_sd",
                      "n_satisfied", "n_total")
  missing_diag <- setdiff(required_diag, names(x$diagnosis))
  if (length(missing_diag) > 0) {
    stop(sprintf("OptimizationPlan$diagnosis missing: %s",
                 paste(missing_diag, collapse = ", ")), call. = FALSE)
  }

  # Check feasibility fields
  required_feas <- c("is_feasible", "cycle_time_ok", "scan_rate_ok", "window_range_ok")
  missing_feas <- setdiff(required_feas, names(x$feasibility))
  if (length(missing_feas) > 0) {
    stop(sprintf("OptimizationPlan$feasibility missing: %s",
                 paste(missing_feas, collapse = ", ")), call. = FALSE)
  }
  if (!is.logical(x$feasibility$is_feasible)) {
    stop("feasibility$is_feasible must be logical", call. = FALSE)
  }

  # Check instrument fields
  required_inst <- c("preset", "name", "cycle_mode")
  missing_inst <- setdiff(required_inst, names(x$instrument))
  if (length(missing_inst) > 0) {
    stop(sprintf("OptimizationPlan$instrument missing: %s",
                 paste(missing_inst, collapse = ", ")), call. = FALSE)
  }

  # Check parameters fields
  required_params <- c("target_dppp", "target_satisfaction")
  missing_params <- setdiff(required_params, names(x$parameters))
  if (length(missing_params) > 0) {
    stop(sprintf("OptimizationPlan$parameters missing: %s",
                 paste(missing_params, collapse = ", ")), call. = FALSE)
  }

  invisible(x)
}

#' Check if Object is OptimizationPlan
#'
#' @param x Object to check
#' @return Logical, TRUE if object is OptimizationPlan
#' @export
is_OptimizationPlan <- function(x) {
  inherits(x, "OptimizationPlan")
}

# =============================================================================
# Class 3: OptimizedWindows
# =============================================================================

#' Low-level OptimizedWindows Constructor (Internal)
#'
#' @param windows Data frame with window specifications
#' @param statistics List with window statistics
#' @param rt_binning List with RT binning information
#' @param mz_optimization List with m/z optimization details
#' @param parameters List with generation parameters
#' @param metadata List with processing metadata
#'
#' @return OptimizedWindows S3 object
#' @keywords internal
new_OptimizedWindows <- function(windows,
                                  statistics = list(),
                                  rt_binning = list(),
                                  mz_optimization = list(),
                                  parameters = list(),
                                  metadata = list()) {
  structure(
    list(
      windows = windows,
      statistics = statistics,
      rt_binning = rt_binning,
      mz_optimization = mz_optimization,
      parameters = parameters,
      metadata = metadata
    ),
    class = c("OptimizedWindows", "list")
  )
}

#' Validate OptimizedWindows Object
#'
#' @param x Object to validate
#' @return The object (invisibly) if valid, throws error if not
#' @export
validate_OptimizedWindows <- function(x) {
  if (!inherits(x, "OptimizedWindows")) {
    stop("Object must be of class 'OptimizedWindows'", call. = FALSE)
  }

  # Check required fields
  required_fields <- c("windows", "statistics", "parameters")
  missing_fields <- setdiff(required_fields, names(x))
  if (length(missing_fields) > 0) {
    stop(sprintf("OptimizedWindows missing required fields: %s",
                 paste(missing_fields, collapse = ", ")), call. = FALSE)
  }

  # Validate windows data frame
  if (!is.data.frame(x$windows)) {
    stop("OptimizedWindows$windows must be a data frame", call. = FALSE)
  }

  required_cols <- c("mz_start", "mz_end", "rt_start", "rt_end")
  missing_cols <- setdiff(required_cols, names(x$windows))
  if (length(missing_cols) > 0) {
    stop(sprintf("OptimizedWindows$windows missing columns: %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)
  }

  # Validate statistics
  required_stats <- c("total_windows", "coverage_percentage")
  missing_stats <- setdiff(required_stats, names(x$statistics))
  if (length(missing_stats) > 0) {
    stop(sprintf("OptimizedWindows$statistics missing: %s",
                 paste(missing_stats, collapse = ", ")), call. = FALSE)
  }

  invisible(x)
}

#' Check if Object is OptimizedWindows
#'
#' @param x Object to check
#' @return Logical, TRUE if object is OptimizedWindows
#' @export
is_OptimizedWindows <- function(x) {
  inherits(x, "OptimizedWindows")
}

# =============================================================================
# Class 4: VisualizationResult
# =============================================================================

#' Low-level VisualizationResult Constructor (Internal)
#'
#' @param plots Named list of ggplot objects
#' @param reports List with report information
#' @param export_paths List with exported file paths
#' @param summary List with visualization summary statistics
#' @param metadata List with processing metadata
#'
#' @return VisualizationResult S3 object
#' @keywords internal
new_VisualizationResult <- function(plots = list(),
                                     reports = list(),
                                     export_paths = list(),
                                     summary = list(),
                                     metadata = list()) {
  structure(
    list(
      plots = plots,
      reports = reports,
      export_paths = export_paths,
      summary = summary,
      metadata = metadata
    ),
    class = c("VisualizationResult", "list")
  )
}

#' Validate VisualizationResult Object
#'
#' @param x Object to validate
#' @return The object (invisibly) if valid, throws error if not
#' @export
validate_VisualizationResult <- function(x) {
  if (!inherits(x, "VisualizationResult")) {
    stop("Object must be of class 'VisualizationResult'", call. = FALSE)
  }

  # Check required fields
  required_fields <- c("plots", "metadata")
  missing_fields <- setdiff(required_fields, names(x))
  if (length(missing_fields) > 0) {
    stop(sprintf("VisualizationResult missing required fields: %s",
                 paste(missing_fields, collapse = ", ")), call. = FALSE)
  }

  # Validate plots is a list
  if (!is.list(x$plots)) {
    stop("VisualizationResult$plots must be a list", call. = FALSE)
  }

  invisible(x)
}

#' Check if Object is VisualizationResult
#'
#' @param x Object to check
#' @return Logical, TRUE if object is VisualizationResult
#' @export
is_VisualizationResult <- function(x) {
  inherits(x, "VisualizationResult")
}

# =============================================================================
# Accessor Functions (Getters)
# =============================================================================

#' Get Precursor Data from ValidatedData
#'
#' Safe accessor that returns the precursor data tibble.
#'
#' @param x ValidatedData object
#' @return Tibble with precursor data
#' @export
get_data <- function(x) {
  UseMethod("get_data")
}

#' @export
get_data.ValidatedData <- function(x) {
  x$data
}

#' @export
get_data.default <- function(x) {
  stop("get_data() requires a ValidatedData object", call. = FALSE)
}

#' Get Metadata
#'
#' @param x S3 object
#' @return Metadata list
#' @export
get_metadata <- function(x) {
  UseMethod("get_metadata")
}

#' @export
get_metadata.ValidatedData <- function(x) {
  x$metadata
}

#' @export
get_metadata.OptimizationPlan <- function(x) {
  list(
    window_count = x$window_count_per_bin,
    required_cycle_time = x$required_cycle_time_sec,
    actual_cycle_time = x$actual_cycle_time_sec,
    instrument = x$instrument$name
  )
}

#' @export
get_metadata.OptimizedWindows <- function(x) {
  x$metadata
}

#' @export
get_metadata.VisualizationResult <- function(x) {
  x$metadata
}

#' @export
get_metadata.default <- function(x) {
  stop("get_metadata() not supported for this object type", call. = FALSE)
}

#' Get Windows Data Frame
#'
#' @param x OptimizedWindows object
#' @return Data frame with window specifications
#' @export
get_windows <- function(x) {
  UseMethod("get_windows")
}

#' @export
get_windows.OptimizedWindows <- function(x) {
  x$windows
}

#' @export
get_windows.default <- function(x) {
  stop("get_windows() requires an OptimizedWindows object", call. = FALSE)
}

#' Get Statistics
#'
#' @param x S3 object with statistics
#' @return Statistics list
#' @export
get_statistics <- function(x) {
  UseMethod("get_statistics")
}

#' @export
get_statistics.OptimizedWindows <- function(x) {
  x$statistics
}

#' @export
get_statistics.default <- function(x) {
  stop("get_statistics() not supported for this object type", call. = FALSE)
}

#' Get Diagnosis Results
#'
#' @param x OptimizationPlan object
#' @return Diagnosis list
#' @export
get_diagnosis <- function(x) {
  UseMethod("get_diagnosis")
}

#' @export
get_diagnosis.OptimizationPlan <- function(x) {
  x$diagnosis
}

#' @export
get_diagnosis.default <- function(x) {
  stop("get_diagnosis() requires an OptimizationPlan object", call. = FALSE)
}

#' Get Plots
#'
#' @param x VisualizationResult object
#' @param name Optional plot name to retrieve specific plot
#' @return Plot list or single plot
#' @export
get_plots <- function(x, name = NULL) {
  UseMethod("get_plots")
}

#' @export
get_plots.VisualizationResult <- function(x, name = NULL) {
  if (is.null(name)) {
    x$plots
  } else {
    if (!name %in% names(x$plots)) {
      stop(sprintf("Plot '%s' not found. Available: %s",
                   name, paste(names(x$plots), collapse = ", ")), call. = FALSE)
    }
    x$plots[[name]]
  }
}

#' @export
get_plots.default <- function(x, name = NULL) {
  stop("get_plots() requires a VisualizationResult object", call. = FALSE)
}

# =============================================================================
# S3 Print Methods
# =============================================================================

#' Print method for ValidatedData
#' @param x A ValidatedData object
#' @param ... Additional arguments (ignored)
#' @export
print.ValidatedData <- function(x, ...) {
  cat("ValidatedData object\n")
  cat(sprintf("  Precursors: %s\n",
              format(x$metadata$n_precursors, big.mark = ",")))
  cat(sprintf("  RT range: %.2f - %.2f min\n",
              x$metadata$rt_range[1], x$metadata$rt_range[2]))
  cat(sprintf("  m/z range: %.1f - %.1f Da\n",
              x$metadata$mz_range[1], x$metadata$mz_range[2]))
  cat(sprintf("  Quality score: %.2f\n", x$validation_status$quality_score))
  cat(sprintf("  Status: %s\n",
              ifelse(x$validation_status$all_passed, "OK PASSED", "X FAILED")))
  invisible(x)
}

#' Print method for OptimizationPlan
#' @param x An OptimizationPlan object
#' @param ... Additional arguments (ignored)
#' @export
print.OptimizationPlan <- function(x, ...) {
  cat("OptimizationPlan object\n")
  cat(sprintf("  Window count: %d per RT bin\n", x$window_count_per_bin))
  cat(sprintf("  Required cycle time: <= %.3f sec\n", x$required_cycle_time_sec))
  cat(sprintf("  Actual cycle time: %.3f sec\n", x$actual_cycle_time_sec))
  cat(sprintf("  Feasibility: %s\n",
              if (x$feasibility$is_feasible) "OK PASS" else "!! WARNINGS"))
  cat(sprintf("  Instrument: %s\n", x$instrument$name))
  invisible(x)
}

#' Print method for OptimizedWindows
#' @param x An OptimizedWindows object
#' @param ... Additional arguments (ignored)
#' @export
print.OptimizedWindows <- function(x, ...) {
  cat("OptimizedWindows object\n")
  cat(sprintf("  Total windows: %d\n", nrow(x$windows)))
  cat(sprintf("  RT bins: %d (%.1f min each)\n",
              x$rt_binning$n_bins,
              x$parameters$rt_bin_width_min))
  cat(sprintf("  Windows per bin: %d\n", x$parameters$n_windows_per_bin))
  cat(sprintf("  Coverage: %.1f%%\n", x$statistics$coverage_percentage))
  cat(sprintf("  Window mode: %s\n", x$parameters$window_mode))
  cat(sprintf("  m/z strategy: %s\n", x$parameters$mz_strategy))
  invisible(x)
}

#' Print method for VisualizationResult
#' @param x A VisualizationResult object
#' @param ... Additional arguments (ignored)
#' @export
print.VisualizationResult <- function(x, ...) {
  cat("VisualizationResult object\n")
  cat(sprintf("  Plots: %d\n", length(x$plots)))
  if (length(x$plots) > 0) {
    cat(sprintf("  Available: %s\n",
                paste(head(names(x$plots), 5), collapse = ", ")))
    if (length(x$plots) > 5) {
      cat(sprintf("           ... and %d more\n", length(x$plots) - 5))
    }
  }
  if (!is.null(x$export_paths$pdf)) {
    cat(sprintf("  PDF: %s\n", x$export_paths$pdf))
  }
  invisible(x)
}

# =============================================================================
# S3 Summary Methods
# =============================================================================

#' Summary method for ValidatedData
#' @param object A ValidatedData object
#' @param ... Additional arguments (ignored)
#' @export
summary.ValidatedData <- function(object, ...) {
  cat("=== ValidatedData Summary ===\n\n")

  cat("Data Overview:\n")
  cat(sprintf("  Precursors: %s\n",
              format(object$metadata$n_precursors, big.mark = ",")))
  cat(sprintf("  RT range: %.2f - %.2f min\n",
              object$metadata$rt_range[1], object$metadata$rt_range[2]))
  cat(sprintf("  m/z range: %.1f - %.1f Da\n",
              object$metadata$mz_range[1], object$metadata$mz_range[2]))

  if (!is.null(object$metadata$fwhm_stats)) {
    cat("\nFWHM Statistics:\n")
    mean_sec <- ensure_fwhm_seconds(object$metadata$fwhm_stats$mean)
    cat(sprintf("  Mean: %.3f min (%.1f sec)\n", mean_sec / 60, mean_sec))
    cat(sprintf("  Median: %.3f min\n", object$metadata$fwhm_stats$median))
    cat(sprintf("  SD: %.3f min\n", object$metadata$fwhm_stats$sd))
  }

  cat("\nValidation Status:\n")
  cat(sprintf("  Quality score: %.2f\n", object$validation_status$quality_score))
  cat(sprintf("  Passed: %s\n",
              ifelse(object$validation_status$all_passed, "YES", "NO")))
  cat(sprintf("  Warnings: %d\n", object$validation_status$n_warnings))

  invisible(object)
}

#' Summary method for OptimizationPlan
#' @param object An OptimizationPlan object
#' @param ... Additional arguments (ignored)
#' @export
summary.OptimizationPlan <- function(object, ...) {
  cat("=== Optimization Plan Summary ===\n\n")

  cat("Planning Results:\n")
  cat(sprintf("  Window count per bin: %d\n", object$window_count_per_bin))
  cat(sprintf("  Required cycle time: <= %.3f sec\n", object$required_cycle_time_sec))
  cat(sprintf("  Actual cycle time: %.3f sec\n", object$actual_cycle_time_sec))
  cat(sprintf("  Cycle time margin: %.3f sec\n",
              object$required_cycle_time_sec - object$actual_cycle_time_sec))

  cat("\nDiagnosis:\n")
  cat(sprintf("  Current cycle time: %.3f sec\n",
              object$diagnosis$current_cycle_time_sec))
  cat(sprintf("  Current satisfaction: %.1f%%\n",
              object$diagnosis$current_satisfaction_ratio * 100))

  cat("\nFeasibility:\n")
  cat(sprintf("  Overall: %s\n",
              if (object$feasibility$is_feasible) "OK FEASIBLE" else "!! WARNINGS"))
  cat(sprintf("  Cycle time check: %s\n",
              if (object$feasibility$cycle_time_ok) "OK PASS" else "X FAIL"))
  cat(sprintf("  Scan rate check: %s\n",
              if (object$feasibility$scan_rate_ok) "OK PASS" else "X FAIL"))

  cat("\nInstrument:\n")
  cat(sprintf("  Name: %s\n", object$instrument$name))
  cat(sprintf("  Max scan rate: %.0f Hz\n", object$instrument$max_scan_rate_hz))

  invisible(object)
}

#' Summary method for OptimizedWindows
#' @param object An OptimizedWindows object
#' @param ... Additional arguments (ignored)
#' @export
summary.OptimizedWindows <- function(object, ...) {
  cat("=== Optimized Windows Summary ===\n\n")

  cat("Window Generation:\n")
  cat(sprintf("  Total windows: %d\n", object$statistics$total_windows))
  cat(sprintf("  RT bins: %d (%.1f min each)\n",
              object$rt_binning$n_bins,
              object$parameters$rt_bin_width_min))
  cat(sprintf("  Windows per bin: %d\n", object$parameters$n_windows_per_bin))

  cat("\nWindow Characteristics:\n")
  cat(sprintf("  Width: %.2f +/- %.2f Da\n",
              object$statistics$window_width_mean,
              object$statistics$window_width_sd))
  cat(sprintf("  Range: %.1f - %.1f Da\n",
              object$statistics$min_window_width,
              object$statistics$max_window_width))

  cat("\nPrecursor Distribution:\n")
  cat(sprintf("  Per window: %.1f +/- %.1f (CV: %.2f)\n",
              object$statistics$mean_precursors_per_window,
              object$statistics$sd_precursors_per_window,
              object$statistics$cv_precursors))

  cat("\nCoverage:\n")
  cat(sprintf("  Total precursors: %s\n",
              format(object$statistics$total_precursors, big.mark = ",")))
  cat(sprintf("  Covered: %s (%.1f%%)\n",
              format(object$statistics$covered_precursors, big.mark = ","),
              object$statistics$coverage_percentage))

  cat("\nParameters:\n")
  cat(sprintf("  m/z strategy: %s\n", object$parameters$mz_strategy))
  cat(sprintf("  Window mode: %s\n", object$parameters$window_mode))

  invisible(object)
}

#' Summary method for VisualizationResult
#' @param object A VisualizationResult object
#' @param ... Additional arguments (ignored)
#' @export
summary.VisualizationResult <- function(object, ...) {
  cat("=== Visualization Result Summary ===\n\n")

  cat("Plots Generated:\n")
  cat(sprintf("  Total plots: %d\n", length(object$plots)))
  if (length(object$plots) > 0) {
    for (name in names(object$plots)) {
      cat(sprintf("    - %s\n", name))
    }
  }

  cat("\nExport Paths:\n")
  if (!is.null(object$export_paths$pdf)) {
    cat(sprintf("  PDF: %s\n", object$export_paths$pdf))
  }
  if (!is.null(object$export_paths$plots_dir)) {
    cat(sprintf("  Plots: %s\n", object$export_paths$plots_dir))
  }

  if (!is.null(object$metadata$processing_time_sec)) {
    cat(sprintf("\nProcessing time: %.2f sec\n",
                object$metadata$processing_time_sec))
  }

  invisible(object)
}

