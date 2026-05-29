# replicate_utils.R - Technical Replicate Management Utilities
# DIA Window Optimizer v2.0
#
# Purpose: Handle technical replicates using median-based consensus and geometric CV


# ============================================================================
# Task 2.1.1: Replicate Group Identification - GREEN Phase (Minimal Implementation)
# ============================================================================

#' Identify and Count Replicate Groups
#'
#' Counts the number of replicates for each precursor across multiple runs.
#'
#' @param data Tibble with columns Precursor.Id and Run
#' @return List with replicate statistics
#' @export
identify_replicate_groups <- function(data) {
  # Validate columns
  if (!"Precursor.Id" %in% colnames(data)) {
    stop("Missing column: Precursor.Id")
  }
  if (!"Run" %in% colnames(data)) {
    stop("Missing column: Run")
  }

  # Count replicates per precursor
  replicate_counts <- data %>%
    group_by(Precursor.Id) %>%
    summarize(n_replicates = n(), .groups = "drop") %>%
    deframe()

  # Distribution analysis
  n_singleton <- sum(replicate_counts == 1)
  n_replicated <- sum(replicate_counts > 1)

  list(
    n_precursors_unique = length(replicate_counts),
    replicate_counts = replicate_counts,
    n_singleton = n_singleton,
    n_replicated = n_replicated,
    n_runs = length(unique(data$Run)),
    replicate_distribution = table(replicate_counts)
  )
}

# ============================================================================
# Task 2.1.2: CV Calculation Functions - GREEN Phase (CORRECTED)
# ============================================================================

#' Calculate Base Coefficient of Variation (for Linear-Scale Data)
#'
#' Calculates standard CV% for linear-scale data (RT, FWHM) using:
#' CV = (sd / mean) * 100
#'
#' Reference: docs/GEOMETRIC_CV_GUIDE.md
#'
#' @param x Numeric vector of values
#' @return Base CV percentage, or NA if n < 2
#' @keywords internal
base_cv <- function(x) {
  # Remove NA values
  x <- x[!is.na(x)]

  if (length(x) < 2) return(NA_real_)

  # Base CV formula: (SD / Mean) * 100
  cv_pct <- (sd(x) / mean(x)) * 100

  return(cv_pct)
}

#' Calculate Geometric Coefficient of Variation (for Log-Normal Data)
#'
#' Calculates geometric CV% for log-normal data (intensity) following:
#' CV = sqrt(exp(sd(log(x))^2) - 1) * 100
#'
#' Reference: docs/GEOMETRIC_CV_GUIDE.md
#'
#' @param x Numeric vector of values
#' @return Geometric CV percentage, or NA if n < 2
#' @keywords internal
geometric_cv <- function(x) {
  # Remove NA and non-positive values: log() requires x > 0, and zero/negative
  # intensities are invalid for a log-normal (geometric) CV.
  x <- x[!is.na(x) & x > 0]

  if (length(x) < 2) return(NA_real_)

  # Geometric CV formula
  # CV = sqrt(exp(sd(log(x))^2) - 1) * 100
  log_x <- log(x)
  sigma_log <- sd(log_x)

  cv_pct <- sqrt(exp(sigma_log^2) - 1) * 100

  return(cv_pct)
}

# ============================================================================
# Task 2.1.3: Consensus Dataset Calculation - GREEN Phase (Minimal Implementation)
# ============================================================================

#' Calculate Consensus Dataset from Technical Replicates (CORRECTED)
#'
#' Creates a consensus dataset by taking median values across replicates
#' and filtering based on intensity CV% (proteomics standard).
#'
#' @param data Tibble with columns Precursor.Id, Run, RT.Start, Precursor.Mz, FWHM, Precursor.Quantity (optional)
#' @param min_replicates Minimum number of replicates (default: 1)
#' @param max_intensity_cv_percent Maximum intensity CV% threshold for filtering (default: 30)
#' @return Tibble with consensus values and replicate statistics
#' @export
calculate_consensus_dataset <- function(data, min_replicates = 1,
                                        max_intensity_cv_percent = 30) {
  n_before <- nrow(data)

  # Identify replicates
  rep_info <- identify_replicate_groups(data)

  # Check if intensity column exists
  has_intensity <- "Precursor.Quantity" %in% colnames(data)

  # Step 1: Calculate CV% for each precursor across replicates
  # Use base_cv for RT/FWHM (linear scale), geometric_cv for intensity (log-normal)
  if (has_intensity) {
    cv_stats <- data %>%
      group_by(Precursor.Id) %>%
      summarise(
        n_replicates = n(),
        RT_CV_pct = if (n() >= 2) base_cv(RT.Start) else NA_real_,
        Mz_CV_pct = if (n() >= 2) base_cv(Precursor.Mz) else NA_real_,
        FWHM_CV_pct = if (n() >= 2) base_cv(FWHM) else NA_real_,
        Intensity_CV_pct = if (n() >= 2) geometric_cv(Precursor.Quantity) else NA_real_,
        .groups = "drop"
      )
  } else {
    cv_stats <- data %>%
      group_by(Precursor.Id) %>%
      summarise(
        n_replicates = n(),
        RT_CV_pct = if (n() >= 2) base_cv(RT.Start) else NA_real_,
        Mz_CV_pct = if (n() >= 2) base_cv(Precursor.Mz) else NA_real_,
        FWHM_CV_pct = if (n() >= 2) base_cv(FWHM) else NA_real_,
        .groups = "drop"
      )
  }

  # Step 2: Calculate median values (preserve categorical columns if present)
  has_protein_group <- "Protein.Group" %in% colnames(data)
  has_charge <- "Precursor.Charge" %in% colnames(data)

  # Check if RT.Apex is available (computed in Stage 1 before consensus)
  has_rt_apex <- "RT.Apex" %in% colnames(data)

  # Base consensus: always compute these
  consensus_values <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      RT.Start = median(RT.Start, na.rm = TRUE),
      RT.Apex = if (has_rt_apex) median(RT.Apex, na.rm = TRUE) else median(RT.Start, na.rm = TRUE),
      Precursor.Mz = median(Precursor.Mz, na.rm = TRUE),
      FWHM = median(FWHM, na.rm = TRUE),
      .groups = "drop"
    )

  # Add optional columns via join (avoids 4-way branch explosion)
  if (has_intensity) {
    intensity_vals <- data %>%
      group_by(Precursor.Id) %>%
      summarise(Precursor.Quantity = median(Precursor.Quantity, na.rm = TRUE), .groups = "drop")
    consensus_values <- left_join(consensus_values, intensity_vals, by = "Precursor.Id")
  }
  if (has_protein_group) {
    protein_vals <- data %>%
      group_by(Precursor.Id) %>%
      summarise(Protein.Group = first(Protein.Group), .groups = "drop")
    consensus_values <- left_join(consensus_values, protein_vals, by = "Precursor.Id")
  }
  if (has_charge) {
    charge_vals <- data %>%
      group_by(Precursor.Id) %>%
      summarise(Precursor.Charge = first(Precursor.Charge), .groups = "drop")
    consensus_values <- left_join(consensus_values, charge_vals, by = "Precursor.Id")
  }

  # Step 3: Join consensus values with CV stats
  consensus <- consensus_values %>%
    left_join(cv_stats, by = "Precursor.Id")

  # Step 4: Intensity CV filtering (keep singletons)
  # CRITICAL: Use intensity CV for filtering (proteomics standard), not FWHM CV
  if (has_intensity) {
    filtered <- consensus %>%
      filter(
        n_replicates >= min_replicates,
        (n_replicates == 1 | is.na(Intensity_CV_pct) | Intensity_CV_pct <= max_intensity_cv_percent)
      )
  } else {
    # If no intensity column, keep all precursors (no CV filtering)
    filtered <- consensus %>%
      filter(n_replicates >= min_replicates)
  }

  # Add metadata
  metadata_list <- list(
    n_runs = rep_info$n_runs,
    n_precursors_before = n_before,
    n_precursors_unique = rep_info$n_precursors_unique,
    n_precursors_after = nrow(filtered),
    n_singleton = sum(filtered$n_replicates == 1),
    n_replicated = sum(filtered$n_replicates > 1),
    n_filtered_cv = nrow(consensus) - nrow(filtered),
    mean_rt_cv_pct = mean(filtered$RT_CV_pct, na.rm = TRUE),
    mean_fwhm_cv_pct = mean(filtered$FWHM_CV_pct, na.rm = TRUE)
  )

  # Add intensity CV to metadata if available
  if (has_intensity) {
    metadata_list$mean_intensity_cv_pct <- mean(filtered$Intensity_CV_pct, na.rm = TRUE)
  }

  attr(filtered, "metadata") <- metadata_list

  filtered
}
