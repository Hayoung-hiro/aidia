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
