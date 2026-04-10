# column_selection.R - Automatic Essential Column Selection
# DIA Window Optimizer v2.0
#
# Purpose: Automatically keep only essential columns for memory efficiency
#          No configuration needed - always applies the same logic


# ============================================================================
# Essential Columns for Pipeline (Stages 1-4)
# ============================================================================

#' Essential Columns Required for Full Pipeline
#'
#' These columns are ALWAYS required for the complete optimization workflow.
#' Based on actual usage analysis across all stages:
#'   - Stage 2 (DPPP diagnosis): FWHM
#'   - Stage 3 (Window optimization): RT.Apex, Precursor.Mz
#'   - Stage 4 (Visualization): RT.Apex, Precursor.Mz, FWHM
#'
#' RT.Apex is computed in Stage 1 as midpoint of RT.Start and RT.Stop.
#' All downstream stages use RT.Apex as the single RT reference.
#'
#' @keywords internal
ESSENTIAL_COLUMNS <- c(
  "Precursor.Id",      # Unique identifier (required for tracking)
  "RT.Apex",           # Midpoint of RT.Start and RT.Stop (computed in Stage 1)
  "Precursor.Mz",      # m/z value in Da (Stage 3, 4)
  "FWHM",              # Full-width at half maximum in minutes (Stage 2, 4)
  "Protein.Group"      # Protein group for identification (user-requested)
)

#' QC Columns Added After Replicate Consensus
#'
#' These columns are created in Stage 1 if technical replicates are present.
#' Keep them if available for QC reporting.
#'
#' @keywords internal
QC_COLUMNS <- c(
  "Precursor.Charge",  # Charge state (visualization: FWHM by charge, optional)
  "Precursor.Quantity",  # Median intensity across replicates (for reference)
  "n_replicates",      # Number of replicates per precursor
  "RT_CV_pct",         # RT coefficient of variation (%)
  "Mz_CV_pct",         # m/z coefficient of variation (%)
  "FWHM_CV_pct",       # FWHM coefficient of variation (%)
  "Intensity_CV_pct"   # Intensity CV (geometric, if present)
)

# ============================================================================
# Automatic Column Selection
# ============================================================================

#' Select Essential Columns (Automatic, No Configuration)
#'
#' Automatically filters ValidatedData to keep only columns needed for
#' the optimization pipeline. This function:
#'   1. Always keeps ESSENTIAL_COLUMNS
#'   2. Keeps QC_COLUMNS if they exist (after consensus)
#'   3. Removes all other columns for memory efficiency
#'
#' No user configuration needed - this always applies the same logic.
#'
#' @param data Tibble, the validated data to filter
#' @param verbose Logical, print column selection summary? (default: TRUE)
#'
#' @return Tibble with selected columns only
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' # Standard usage (automatic)
#' filtered_data <- select_essential_columns(validated_data$data)
#'
#' # Silent mode
#' filtered_data <- select_essential_columns(validated_data$data, verbose = FALSE)
#' }
select_essential_columns <- function(data, verbose = TRUE) {

  # Get available columns
  available_columns <- colnames(data)

  # Check for essential columns
  missing_essential <- setdiff(ESSENTIAL_COLUMNS, available_columns)

  # Handle Protein.Group alternatives
  protein_col_alternatives <- c("Protein.Group", "Protein.Ids", "Protein.Names")
  has_protein_col <- any(protein_col_alternatives %in% available_columns)

  if ("Protein.Group" %in% missing_essential && has_protein_col) {
    # Use alternative protein column
    for (alt_col in protein_col_alternatives) {
      if (alt_col %in% available_columns) {
        if (alt_col != "Protein.Group") {
          # Rename to standard Protein.Group
          data <- data %>%
            rename(Protein.Group = !!sym(alt_col))
          available_columns <- colnames(data)
          if (verbose) {
            cat(sprintf("  -> Renamed '%s' to 'Protein.Group'\n", alt_col))
          }
        }
        break
      }
    }
    missing_essential <- setdiff(ESSENTIAL_COLUMNS, available_columns)
  }

  # Fatal error if essential columns still missing
  if (length(missing_essential) > 0) {
    stop(sprintf(
      "Missing essential columns in data: %s\n  Available: %s",
      paste(missing_essential, collapse = ", "),
      paste(available_columns, collapse = ", ")
    ))
  }

  # Build list of columns to keep
  columns_to_keep <- c(
    ESSENTIAL_COLUMNS,
    intersect(QC_COLUMNS, available_columns)  # Keep QC columns if present
  )

  # Filter data
  filtered_data <- data %>%
    select(all_of(columns_to_keep))

  # Print summary if verbose
  if (verbose) {
    n_before <- ncol(data)
    n_after <- ncol(filtered_data)
    n_removed <- n_before - n_after
    pct_reduction <- round((n_removed / n_before) * 100, 1)

    cat(sprintf("OK Column selection: %d -> %d columns (removed %d, %.1f%% reduction)\n",
                n_before, n_after, n_removed, pct_reduction))

    # List kept columns if reasonable number
    if (n_after <= 15) {
      cat(sprintf("  Kept: %s\n", paste(columns_to_keep, collapse = ", ")))
    }
  }

  return(filtered_data)
}

# ============================================================================
# Validation Helper
# ============================================================================

#' Validate Essential Columns Presence
#'
#' Check if all essential columns are present in data.
#' Used for early validation before processing.
#'
#' @param data Tibble to check
#'
#' @return Logical, TRUE if all essential columns present (stops on error)
#' @keywords internal
validate_essential_columns <- function(data) {

  available_columns <- colnames(data)
  missing_essential <- setdiff(ESSENTIAL_COLUMNS, available_columns)

  # Handle Protein.Group alternatives
  if ("Protein.Group" %in% missing_essential) {
    protein_alternatives <- c("Protein.Ids", "Protein.Names")
    if (any(protein_alternatives %in% available_columns)) {
      # Can be renamed, not actually missing
      missing_essential <- setdiff(missing_essential, "Protein.Group")
    }
  }

  if (length(missing_essential) > 0) {
    stop(sprintf(
      "Missing essential columns: %s\n  Required: %s\n  Available: %s",
      paste(missing_essential, collapse = ", "),
      paste(ESSENTIAL_COLUMNS, collapse = ", "),
      paste(available_columns, collapse = ", ")
    ))
  }

  return(TRUE)
}
