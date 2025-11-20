# column_selection.R - Flexible Column Selection for Memory Optimization
# DIA Window Optimizer v2.0
#
# Purpose: Select essential columns from validated data for memory efficiency
#          while supporting diverse workflows (PTM-specific, different platforms)

library(dplyr)

# ============================================================================
# Core Constants
# ============================================================================

#' Essential Columns for Complete Pipeline (Stages 1-4)
#'
#' These columns are ALWAYS required for the full optimization workflow.
#'
#' @export
ESSENTIAL_COLUMNS <- c(
  "Precursor.Id",   # Unique identifier for tracking
  "RT.Start",       # Retention time (Stage 3: binning, Stage 4: plots)
  "Precursor.Mz",   # m/z value (Stage 3: range optimization, Stage 4: plots)
  "FWHM"            # Peak width (Stage 2: DPPP, Stage 4: plots)
)

#' QC Columns Added After Replicate Consensus
#'
#' These columns are present after technical replicate handling in Stage 1.
#' Keep them for QC reporting if available.
#'
#' @export
QC_COLUMNS <- c(
  "n_replicates",      # Number of replicates per precursor
  "RT_CV_pct",         # RT coefficient of variation (%)
  "Mz_CV_pct",         # m/z coefficient of variation (%)
  "FWHM_CV_pct",       # FWHM coefficient of variation (%)
  "Intensity_CV_pct"   # Intensity CV (geometric, if Precursor.Quantity present)
)

#' Optional Intensity Column for CV Filtering
#'
#' Used in Stage 1 for intensity-based quality filtering.
#' If missing, CV filtering is skipped (graceful degradation).
#'
#' @export
INTENSITY_COLUMN <- "Precursor.Quantity"

# ============================================================================
# Column Selection Modes
# ============================================================================

#' Get Columns for Selection Mode
#'
#' Returns a list of columns to keep based on the specified mode.
#'
#' @param mode Character, selection mode:
#'   - "minimal": Essential columns only (4 columns, ~80% memory savings)
#'   - "standard": Essential + QC columns (default, balanced)
#'   - "full": Keep all columns (for debugging)
#'   - "custom": User-specified columns via `additional_columns`
#' @param additional_columns Character vector, custom columns to add (for "custom" mode)
#' @param available_columns Character vector, columns present in data (for validation)
#'
#' @return Character vector of columns to keep
#' @export
#'
#' @examples
#' # Minimal mode
#' cols <- get_columns_for_mode("minimal")
#' # c("Precursor.Id", "RT.Start", "Precursor.Mz", "FWHM")
#'
#' # Standard mode
#' cols <- get_columns_for_mode("standard", available_columns = colnames(data))
#' # Essential + QC columns (if present)
#'
#' # Custom mode
#' cols <- get_columns_for_mode("custom",
#'   additional_columns = c("Precursor.Charge", "Modified.Sequence")
#' )
get_columns_for_mode <- function(
  mode = "standard",
  additional_columns = NULL,
  available_columns = NULL
) {

  # Validate mode
  valid_modes <- c("minimal", "standard", "full", "custom")
  if (!mode %in% valid_modes) {
    stop(sprintf(
      "Invalid mode '%s'. Must be one of: %s",
      mode, paste(valid_modes, collapse = ", ")
    ))
  }

  # Mode-specific selection
  if (mode == "minimal") {
    # Essential only
    columns_to_keep <- ESSENTIAL_COLUMNS

  } else if (mode == "standard") {
    # Essential + QC columns (if available)
    columns_to_keep <- c(ESSENTIAL_COLUMNS, QC_COLUMNS)

    # Filter to available columns only
    if (!is.null(available_columns)) {
      columns_to_keep <- intersect(columns_to_keep, available_columns)
    }

  } else if (mode == "full") {
    # Keep all columns
    if (is.null(available_columns)) {
      warning("mode='full' requires available_columns argument. Falling back to 'standard'.")
      return(get_columns_for_mode("standard", available_columns = available_columns))
    }
    columns_to_keep <- available_columns

  } else if (mode == "custom") {
    # Essential + user-specified
    columns_to_keep <- unique(c(ESSENTIAL_COLUMNS, additional_columns))

    # Validate custom columns are available
    if (!is.null(available_columns)) {
      missing_cols <- setdiff(additional_columns, available_columns)
      if (length(missing_cols) > 0) {
        warning(sprintf(
          "Requested columns not found in data: %s",
          paste(missing_cols, collapse = ", ")
        ))
      }
      columns_to_keep <- intersect(columns_to_keep, available_columns)
    }
  }

  return(columns_to_keep)
}

# ============================================================================
# Main Selection Function
# ============================================================================

#' Select Essential Columns from Validated Data
#'
#' Filters ValidatedData$data to keep only necessary columns for memory efficiency.
#' Supports flexible workflows (PTM-specific, different platforms, custom analysis).
#'
#' @param data Tibble, the validated data to filter
#' @param mode Character, selection mode ("minimal", "standard", "full", "custom")
#'   Default: "standard"
#' @param additional_columns Character vector, custom columns to add (for mode="custom")
#' @param preserve_intensity Logical, force keeping Precursor.Quantity if present?
#'   Default: TRUE
#' @param verbose Logical, print column selection summary? Default: TRUE
#'
#' @return Tibble with selected columns only
#' @export
#'
#' @examples
#' # Standard mode (essential + QC)
#' filtered_data <- select_essential_columns(validated_data$data)
#'
#' # Minimal mode (memory-optimized)
#' filtered_data <- select_essential_columns(
#'   validated_data$data,
#'   mode = "minimal"
#' )
#'
#' # Custom mode (PTM workflow)
#' filtered_data <- select_essential_columns(
#'   validated_data$data,
#'   mode = "custom",
#'   additional_columns = c("Modified.Sequence", "Precursor.Charge")
#' )
select_essential_columns <- function(
  data,
  mode = "standard",
  additional_columns = NULL,
  preserve_intensity = TRUE,
  verbose = TRUE
) {

  # Get available columns
  available_columns <- colnames(data)

  # Get columns for selected mode
  columns_to_keep <- get_columns_for_mode(
    mode = mode,
    additional_columns = additional_columns,
    available_columns = available_columns
  )

  # Preserve intensity column if requested and available
  if (preserve_intensity && INTENSITY_COLUMN %in% available_columns) {
    if (!INTENSITY_COLUMN %in% columns_to_keep) {
      columns_to_keep <- c(columns_to_keep, INTENSITY_COLUMN)
    }
  }

  # Ensure essential columns are present
  missing_essential <- setdiff(ESSENTIAL_COLUMNS, available_columns)
  if (length(missing_essential) > 0) {
    stop(sprintf(
      "Missing essential columns in data: %s",
      paste(missing_essential, collapse = ", ")
    ))
  }

  # Filter data
  filtered_data <- data %>%
    select(all_of(columns_to_keep))

  # Print summary if verbose
  if (verbose) {
    n_before <- ncol(data)
    n_after <- ncol(filtered_data)
    n_removed <- n_before - n_after
    pct_reduction <- round((n_removed / n_before) * 100, 1)

    cat(sprintf("\n✓ Column Selection: %s mode\n", mode))
    cat(sprintf("  Before: %d columns\n", n_before))
    cat(sprintf("  After: %d columns (%d removed, %.1f%% reduction)\n",
                n_after, n_removed, pct_reduction))

    # List kept columns
    if (n_after <= 10) {
      cat(sprintf("  Kept: %s\n", paste(columns_to_keep, collapse = ", ")))
    }
  }

  return(filtered_data)
}

# ============================================================================
# Validation Helpers
# ============================================================================

#' Validate Column Presence
#'
#' Check if required columns are present in data. Used for graceful degradation.
#'
#' @param data Tibble to check
#' @param required_columns Character vector of required columns
#' @param context Character, context description for error messages
#'
#' @return Logical, TRUE if all required columns present
#' @export
validate_column_presence <- function(
  data,
  required_columns,
  context = "operation"
) {

  missing_cols <- setdiff(required_columns, colnames(data))

  if (length(missing_cols) > 0) {
    stop(sprintf(
      "Missing required columns for %s: %s",
      context,
      paste(missing_cols, collapse = ", ")
    ))
  }

  return(TRUE)
}

#' Check Optional Column Availability
#'
#' Returns which optional columns are available in data.
#' Useful for conditional feature activation.
#'
#' @param data Tibble to check
#' @param optional_columns Character vector of optional columns
#'
#' @return Character vector of available optional columns
#' @export
check_optional_columns <- function(data, optional_columns) {
  intersect(optional_columns, colnames(data))
}

# ============================================================================
# Memory Estimation
# ============================================================================

#' Estimate Memory Usage of Data
#'
#' Calculates approximate memory usage of a tibble.
#'
#' @param data Tibble to estimate
#' @param unit Character, output unit ("MB", "KB", "bytes")
#'
#' @return Numeric, estimated memory usage
#' @export
#'
#' @examples
#' estimate_memory(data, unit = "MB")
#' # 3.2
estimate_memory <- function(data, unit = "MB") {

  # Estimate: nrow × ncol × 8 bytes (assuming numeric/double)
  n_rows <- nrow(data)
  n_cols <- ncol(data)

  bytes <- n_rows * n_cols * 8

  # Convert to requested unit
  if (unit == "MB") {
    return(bytes / (1024^2))
  } else if (unit == "KB") {
    return(bytes / 1024)
  } else {
    return(bytes)
  }
}

#' Calculate Memory Savings
#'
#' Compares memory usage before and after column selection.
#'
#' @param data_before Tibble before filtering
#' @param data_after Tibble after filtering
#'
#' @return List with memory_before, memory_after, savings_mb, savings_pct
#' @export
calculate_memory_savings <- function(data_before, data_after) {

  mem_before <- estimate_memory(data_before, unit = "MB")
  mem_after <- estimate_memory(data_after, unit = "MB")

  savings_mb <- mem_before - mem_after
  savings_pct <- (savings_mb / mem_before) * 100

  list(
    memory_before_mb = round(mem_before, 2),
    memory_after_mb = round(mem_after, 2),
    savings_mb = round(savings_mb, 2),
    savings_pct = round(savings_pct, 1)
  )
}
