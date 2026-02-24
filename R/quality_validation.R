# quality_validation.R - Data Quality Validation Functions
# DIA Window Optimizer v2.0
#
# Purpose: Extract quality validation logic from Stage 1 for better modularity


# =====================================================
# Quality Validation Pipeline
# =====================================================

#' Validate data quality (main entry point)
#'
#' Pipeline-based quality validation with outlier detection, RT/m/z validation,
#' and quality score calculation
#'
#' @param data Data frame with RT.Apex, Precursor.Mz, FWHM columns
#' @return List with quality_score, warnings, errors, details
#' @export
validate_data_quality <- function(data) {

  # Pipeline: Detection → Validation → Scoring
  results <- list(
    fwhm_outliers = detect_fwhm_outliers(data$FWHM),
    rt_issues = validate_rt_values(data$RT.Apex),
    mz_issues = validate_mz_values(data$Precursor.Mz)
  )

  # Collect warnings and errors
  warnings <- collect_warnings(results)
  errors <- collect_errors(results)

  # Calculate quality score
  quality_score <- calculate_quality_score(
    fwhm_outlier_pct = results$fwhm_outliers$pct_outliers,
    rt_issue_pct = results$rt_issues$pct_issues,
    mz_issue_pct = results$mz_issues$pct_invalid
  )

  return(list(
    quality_score = quality_score,
    warnings = warnings,
    errors = errors,
    details = results
  ))
}


# =====================================================
# Outlier Detection
# =====================================================

#' Detect FWHM outliers using IQR method
#'
#' @param fwhm_vector Numeric vector of FWHM values
#' @param iqr_multiplier IQR multiplier (default: 1.5)
#' @return List with outlier information
detect_fwhm_outliers <- function(fwhm_vector, iqr_multiplier = 1.5) {

  Q1 <- quantile(fwhm_vector, 0.25, na.rm = TRUE)
  Q3 <- quantile(fwhm_vector, 0.75, na.rm = TRUE)
  IQR_val <- Q3 - Q1

  lower_bound <- Q1 - iqr_multiplier * IQR_val
  upper_bound <- Q3 + iqr_multiplier * IQR_val

  outlier_indices <- which(fwhm_vector < lower_bound | fwhm_vector > upper_bound)

  return(list(
    indices = outlier_indices,
    n_outliers = length(outlier_indices),
    pct_outliers = length(outlier_indices) / length(fwhm_vector),
    lower_bound = lower_bound,
    upper_bound = upper_bound
  ))
}


# =====================================================
# Value Validation
# =====================================================

#' Validate RT values
#'
#' @param rt_vector Numeric vector of RT values
#' @return List with validation results
validate_rt_values <- function(rt_vector) {

  n_negative <- sum(rt_vector < 0, na.rm = TRUE)
  n_na <- sum(is.na(rt_vector))
  n_total <- length(rt_vector)

  pct_issues <- (n_negative + n_na) / n_total

  return(list(
    n_negative = n_negative,
    n_na = n_na,
    n_total = n_total,
    pct_issues = pct_issues
  ))
}


#' Validate m/z values
#'
#' @param mz_vector Numeric vector of m/z values
#' @param valid_range Valid m/z range c(min, max)
#' @return List with validation results
validate_mz_values <- function(mz_vector, valid_range = c(50, 5000)) {

  n_below <- sum(mz_vector < valid_range[1], na.rm = TRUE)
  n_above <- sum(mz_vector > valid_range[2], na.rm = TRUE)
  n_na <- sum(is.na(mz_vector))
  n_invalid <- n_below + n_above + n_na
  n_total <- length(mz_vector)

  return(list(
    n_invalid = n_invalid,
    n_below = n_below,
    n_above = n_above,
    n_na = n_na,
    pct_invalid = n_invalid / n_total,
    valid_range = valid_range
  ))
}


# =====================================================
# Quality Scoring
# =====================================================

#' Calculate quality score from validation results
#'
#' @param fwhm_outlier_pct FWHM outlier percentage
#' @param rt_issue_pct RT issue percentage
#' @param mz_issue_pct m/z issue percentage
#' @return Quality score 0-1
calculate_quality_score <- function(
  fwhm_outlier_pct,
  rt_issue_pct,
  mz_issue_pct
) {

  # Weight factors
  W_FWHM <- 0.4
  W_RT <- 0.3
  W_MZ <- 0.3

  # Component scores (1 - issue_rate)
  fwhm_score <- 1 - min(fwhm_outlier_pct, 1.0)
  rt_score <- 1 - min(rt_issue_pct, 1.0)
  mz_score <- 1 - min(mz_issue_pct, 1.0)

  # Weighted average
  quality_score <- W_FWHM * fwhm_score + W_RT * rt_score + W_MZ * mz_score

  return(max(0, min(1, quality_score)))
}


# =====================================================
# Warning/Error Collection
# =====================================================

#' Collect warnings from validation results
#'
#' @param results List with fwhm_outliers, rt_issues, mz_issues
#' @return Character vector of warnings
collect_warnings <- function(results) {

  warnings <- character()

  # FWHM outliers warning
  if (results$fwhm_outliers$pct_outliers > 0.1) {
    warnings <- c(warnings, sprintf(
      "High FWHM outlier rate: %.1f%% (%.0f outliers)",
      results$fwhm_outliers$pct_outliers * 100,
      results$fwhm_outliers$n_outliers
    ))
  }

  # m/z validation warning
  if (results$mz_issues$n_invalid > 0) {
    warnings <- c(warnings, sprintf(
      "%d precursors with invalid m/z (< 50 or > 5000 Da)",
      results$mz_issues$n_invalid
    ))
  }

  return(warnings)
}


#' Collect errors from validation results
#'
#' @param results List with fwhm_outliers, rt_issues, mz_issues
#' @return Character vector of errors
collect_errors <- function(results) {

  errors <- character()

  # RT negative values error
  if (results$rt_issues$n_negative > 0) {
    errors <- c(errors, sprintf(
      "%d precursors with negative RT",
      results$rt_issues$n_negative
    ))
  }

  return(errors)
}
