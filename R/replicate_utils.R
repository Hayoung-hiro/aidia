# replicate_utils.R - Technical Replicate Management Utilities
# DIA Window Optimizer v2.0
#
# Purpose: Handle technical replicates using median-based consensus and geometric CV

library(dplyr)
library(tibble)

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
# Task 2.1.2: Geometric CV Calculation - GREEN Phase (Minimal Implementation)
# ============================================================================

#' Calculate Geometric Coefficient of Variation
#'
#' Calculates geometric CV% for log-transformed data following the formula:
#' CV = sqrt(exp(sd(log(x))^2) - 1) * 100
#'
#' Reference: docs/GEOMETRIC_CV_GUIDE.md
#'
#' @param x Numeric vector of values
#' @return Geometric CV percentage, or NA if n < 2
#' @export
geometric_cv <- function(x) {
  # Remove NA values
  x <- x[!is.na(x)]

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

#' Calculate Consensus Dataset from Technical Replicates
#'
#' Creates a consensus dataset by taking median values across replicates
#' and filtering based on geometric CV%.
#'
#' @param data Tibble with columns Precursor.Id, Run, RT.Start, Precursor.Mz, FWHM
#' @param min_replicates Minimum number of replicates (default: 1)
#' @param max_cv_percent Maximum CV% threshold for filtering (default: 20)
#' @return Tibble with consensus values and replicate statistics
#' @export
calculate_consensus_dataset <- function(data, min_replicates = 1,
                                        max_cv_percent = 20) {
  n_before <- nrow(data)

  # Identify replicates
  rep_info <- identify_replicate_groups(data)

  # Step 1: Calculate CV% for each precursor across replicates
  cv_stats <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      n_replicates = n(),
      RT_CV_pct = if (n() >= 2) geometric_cv(RT.Start) else NA_real_,
      Mz_CV_pct = if (n() >= 2) geometric_cv(Precursor.Mz) else NA_real_,
      FWHM_CV_pct = if (n() >= 2) geometric_cv(FWHM) else NA_real_,
      .groups = "drop"
    )

  # Step 2: Calculate median values
  consensus_values <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      RT.Start = median(RT.Start, na.rm = TRUE),
      Precursor.Mz = median(Precursor.Mz, na.rm = TRUE),
      FWHM = median(FWHM, na.rm = TRUE),
      .groups = "drop"
    )

  # Step 3: Join consensus values with CV stats
  consensus <- consensus_values %>%
    left_join(cv_stats, by = "Precursor.Id")

  # Step 4: CV filtering (keep singletons)
  filtered <- consensus %>%
    filter(
      n_replicates >= min_replicates,
      (n_replicates == 1 | is.na(FWHM_CV_pct) | FWHM_CV_pct <= max_cv_percent)
    )

  # Add metadata
  attr(filtered, "metadata") <- list(
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

  filtered
}
