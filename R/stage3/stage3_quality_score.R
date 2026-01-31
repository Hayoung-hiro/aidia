# stage3_quality_score.R - Window Optimization Quality Score System
#
# Purpose: Quantify the quality of DIA window optimization results
#          for comparing strategies and guiding improvements
#
# Version: 1.0 (Initial implementation)
#
# Quality Score Formula:
#   Quality_Score = w1×Coverage + w2×Uniformity + w3×Efficiency + w4×Specificity
#
# Metrics:
#   - Coverage:    Fraction of precursors within windows (0-1)
#   - Uniformity:  Evenness of precursor distribution across windows (0-1)
#   - Efficiency:  Precursor density per m/z width (normalized 0-1)
#   - Specificity: Precision of targeting (precursors/window_area, normalized 0-1)
#
# Default Weights:
#   - Coverage:    0.35 (most important - precursor inclusion)
#   - Uniformity:  0.25 (balanced distribution)
#   - Efficiency:  0.20 (efficient m/z usage)
#   - Specificity: 0.20 (precise targeting)
#
# Dependencies: dplyr

library(dplyr)

# =============================================================================
# Quality Score Calculation Functions
# =============================================================================

#' Calculate Quality Score for Optimized Windows
#'
#' Computes a composite quality score (0-100) based on four metrics:
#' Coverage, Uniformity, Efficiency, and Specificity.
#'
#' @param windows Data frame with window specifications (from optimize_windows)
#'   Required columns: rt_start, rt_end, mz_start, mz_end, n_precursors
#' @param precursor_data Data frame with precursor information
#'   Required columns: RT.Start, Precursor.Mz
#' @param weights Named numeric vector with weights for each metric
#'   Default: c(coverage = 0.35, uniformity = 0.25, efficiency = 0.20, specificity = 0.20)
#'
#' @return List with:
#'   - quality_score: Overall score (0-100)
#'   - metrics: Individual metric values (0-1 each)
#'   - weights: Weights used
#'   - details: Additional diagnostic information
#'
#' @export
#'
#' @examples
#' quality <- calculate_window_quality_score(windows$windows, validated_data$data)
#' cat("Quality Score:", quality$quality_score, "\n")
calculate_window_quality_score <- function(
    windows,
    precursor_data,
    weights = c(coverage = 0.35, uniformity = 0.25, efficiency = 0.20, specificity = 0.20)
) {
  # Validate inputs
  if (is.null(windows) || nrow(windows) == 0) {
    stop("Windows data frame is empty or NULL")
  }
  if (is.null(precursor_data) || nrow(precursor_data) == 0) {
    stop("Precursor data frame is empty or NULL")
  }

  # Validate weights sum to 1
  if (abs(sum(weights) - 1.0) > 0.01) {
    warning("Weights do not sum to 1.0. Normalizing...")
    weights <- weights / sum(weights)
  }

  # Ensure required columns exist
  required_window_cols <- c("rt_start", "rt_end", "mz_start", "mz_end")
  missing_cols <- setdiff(required_window_cols, colnames(windows))
  if (length(missing_cols) > 0) {
    stop(paste("Missing window columns:", paste(missing_cols, collapse = ", ")))
  }

  required_precursor_cols <- c("RT.Start", "Precursor.Mz")
  missing_cols <- setdiff(required_precursor_cols, colnames(precursor_data))
  if (length(missing_cols) > 0) {
    stop(paste("Missing precursor columns:", paste(missing_cols, collapse = ", ")))
  }

  # Calculate window widths if not present
  if (!"window_width" %in% colnames(windows)) {
    windows$window_width <- windows$mz_end - windows$mz_start
  }

  # Calculate each metric
  coverage_result <- calculate_coverage_metric(windows, precursor_data)
  uniformity_result <- calculate_uniformity_metric(windows)
  efficiency_result <- calculate_efficiency_metric(windows, precursor_data)
  specificity_result <- calculate_specificity_metric(windows, precursor_data)

  # Combine metrics
  metrics <- c(
    coverage = coverage_result$value,
    uniformity = uniformity_result$value,
    efficiency = efficiency_result$value,
    specificity = specificity_result$value
  )

  # Calculate weighted quality score (0-100 scale)
  quality_score <- sum(weights * metrics) * 100

  # Prepare detailed results
  details <- list(
    coverage = coverage_result$details,
    uniformity = uniformity_result$details,
    efficiency = efficiency_result$details,
    specificity = specificity_result$details,
    n_windows = nrow(windows),
    n_precursors = nrow(precursor_data)
  )

  list(
    quality_score = round(quality_score, 1),
    metrics = metrics,
    weights = weights,
    details = details
  )
}


# =============================================================================
# Individual Metric Calculations
# =============================================================================

#' Calculate Coverage Metric
#'
#' Coverage = fraction of precursors that fall within at least one window
#'
#' @param windows Data frame with window specifications
#' @param precursor_data Data frame with precursor data
#'
#' @return List with value (0-1) and details
#' @keywords internal
calculate_coverage_metric <- function(windows, precursor_data) {
  # Mark each precursor as covered or not
  precursor_data$covered <- FALSE

  for (i in 1:nrow(windows)) {
    w <- windows[i, ]
    in_window <- (precursor_data$RT.Start >= w$rt_start) &
                 (precursor_data$RT.Start <= w$rt_end) &
                 (precursor_data$Precursor.Mz >= w$mz_start) &
                 (precursor_data$Precursor.Mz < w$mz_end)
    precursor_data$covered[in_window] <- TRUE
  }

  covered_count <- sum(precursor_data$covered)
  total_count <- nrow(precursor_data)
  coverage_ratio <- covered_count / total_count

  list(
    value = coverage_ratio,
    details = list(
      covered_precursors = covered_count,
      total_precursors = total_count,
      coverage_percentage = round(coverage_ratio * 100, 2)
    )
  )
}


#' Calculate Uniformity Metric
#'
#' Uniformity = 1 - CV of precursors per window
#' Higher value = more even distribution across windows
#'
#' The CV is capped at 1.0 to ensure uniformity stays in [0, 1]
#'
#' @param windows Data frame with window specifications (must have n_precursors)
#'
#' @return List with value (0-1) and details
#' @keywords internal
calculate_uniformity_metric <- function(windows) {
  # Need n_precursors column
  if (!"n_precursors" %in% colnames(windows)) {
    warning("n_precursors column not found. Returning default uniformity.")
    return(list(value = 0.5, details = list(message = "n_precursors column missing")))
  }

  n_prec <- windows$n_precursors

  # Handle edge cases
  if (length(n_prec) < 2) {
    return(list(value = 1.0, details = list(message = "Only one window, perfect uniformity")))
  }

  mean_prec <- mean(n_prec, na.rm = TRUE)
  sd_prec <- sd(n_prec, na.rm = TRUE)

  if (is.na(mean_prec) || mean_prec == 0) {
    return(list(value = 0.0, details = list(message = "No precursors in windows")))
  }

  cv <- sd_prec / mean_prec
  # Cap CV at 1.0 to keep uniformity in [0, 1]
  cv_capped <- min(cv, 1.0)
  uniformity <- 1 - cv_capped

  list(
    value = uniformity,
    details = list(
      mean_precursors_per_window = round(mean_prec, 1),
      sd_precursors_per_window = round(sd_prec, 1),
      cv_precursors = round(cv, 3),
      cv_capped = round(cv_capped, 3)
    )
  )
}


#' Calculate Efficiency Metric
#'
#' Efficiency = precursor density per unit m/z width, normalized to [0, 1]
#'
#' Higher efficiency = more precursors per m/z unit (tighter windows)
#'
#' Normalization: Uses a reference density based on optimal packing
#' (assumes max ~50 precursors per Da for well-optimized windows)
#'
#' @param windows Data frame with window specifications
#' @param precursor_data Data frame with precursor data
#'
#' @return List with value (0-1) and details
#' @keywords internal
calculate_efficiency_metric <- function(windows, precursor_data) {
  total_mz_width <- sum(windows$window_width, na.rm = TRUE)
  total_precursors <- nrow(precursor_data)

  if (total_mz_width == 0) {
    return(list(value = 0.0, details = list(message = "Total m/z width is zero")))
  }

  # Raw density: precursors per Da
  raw_density <- total_precursors / total_mz_width

  # Normalize: reference density is 50 precursors/Da (very tight windows)
  # Most real datasets will be 1-20 precursors/Da
  # Using sigmoid-like normalization for smooth [0, 1] mapping
  reference_density <- 50.0
  efficiency <- 1 - exp(-raw_density / reference_density * 3)
  efficiency <- min(max(efficiency, 0), 1)  # Clamp to [0, 1]

  list(
    value = efficiency,
    details = list(
      total_mz_width_da = round(total_mz_width, 1),
      total_precursors = total_precursors,
      precursors_per_da = round(raw_density, 3),
      reference_density = reference_density
    )
  )
}


#' Calculate Specificity Metric
#'
#' Specificity = how precisely windows target precursor-rich regions
#'
#' Calculated as: covered_precursors / total_2D_window_area (RT × m/z)
#' Normalized using a reference area density
#'
#' Higher specificity = windows are tightly focused on precursor regions
#'
#' @param windows Data frame with window specifications
#' @param precursor_data Data frame with precursor data
#'
#' @return List with value (0-1) and details
#' @keywords internal
calculate_specificity_metric <- function(windows, precursor_data) {
  # Calculate 2D area of each window (RT range × m/z range)
  windows$rt_width <- windows$rt_end - windows$rt_start
  windows$area_2d <- windows$rt_width * windows$window_width

  total_area <- sum(windows$area_2d, na.rm = TRUE)

  if (total_area == 0) {
    return(list(value = 0.0, details = list(message = "Total 2D area is zero")))
  }

  # Count covered precursors (reuse coverage logic)
  precursor_data$covered <- FALSE
  for (i in 1:nrow(windows)) {
    w <- windows[i, ]
    in_window <- (precursor_data$RT.Start >= w$rt_start) &
                 (precursor_data$RT.Start <= w$rt_end) &
                 (precursor_data$Precursor.Mz >= w$mz_start) &
                 (precursor_data$Precursor.Mz < w$mz_end)
    precursor_data$covered[in_window] <- TRUE
  }

  covered_count <- sum(precursor_data$covered)

  # 2D density: precursors per (min × Da) area unit
  area_density <- covered_count / total_area

  # Reference: 5 precursors per (min × Da) is very specific
  # Most datasets: 0.1-2 precursors per (min × Da)
  reference_density <- 5.0
  specificity <- 1 - exp(-area_density / reference_density * 3)
  specificity <- min(max(specificity, 0), 1)  # Clamp to [0, 1]

  list(
    value = specificity,
    details = list(
      total_2d_area = round(total_area, 1),
      covered_precursors = covered_count,
      precursors_per_area = round(area_density, 4),
      reference_density = reference_density
    )
  )
}


# =============================================================================
# Quality Report Generation
# =============================================================================

#' Generate Quality Report for Window Optimization
#'
#' Creates a formatted report comparing quality scores across strategies
#' or summarizing a single optimization result.
#'
#' @param quality_scores Named list of quality score results from calculate_window_quality_score()
#'   Names should be strategy names (e.g., "quantile", "smoothing")
#' @param verbose Logical, print detailed report (default: TRUE)
#'
#' @return Data frame with quality comparison
#' @export
#'
#' @examples
#' # Single strategy
#' q1 <- calculate_window_quality_score(windows1$windows, data)
#' report <- generate_quality_report(list(quantile = q1))
#'
#' # Multiple strategies
#' q_list <- list(
#'   quantile = calculate_window_quality_score(windows_quantile$windows, data),
#'   smoothing = calculate_window_quality_score(windows_smoothing$windows, data)
#' )
#' report <- generate_quality_report(q_list)
generate_quality_report <- function(quality_scores, verbose = TRUE) {
  if (length(quality_scores) == 0) {
    stop("No quality scores provided")
  }

  # Build comparison data frame
  report_df <- data.frame(
    strategy = names(quality_scores),
    quality_score = sapply(quality_scores, function(q) q$quality_score),
    coverage = sapply(quality_scores, function(q) round(q$metrics["coverage"] * 100, 1)),
    uniformity = sapply(quality_scores, function(q) round(q$metrics["uniformity"] * 100, 1)),
    efficiency = sapply(quality_scores, function(q) round(q$metrics["efficiency"] * 100, 1)),
    specificity = sapply(quality_scores, function(q) round(q$metrics["specificity"] * 100, 1)),
    stringsAsFactors = FALSE
  )
  rownames(report_df) <- NULL

  # Sort by quality score (descending)
  report_df <- report_df[order(-report_df$quality_score), ]

  if (verbose) {
    cat("\n")
    cat("╔═══════════════════════════════════════════════════════════════════════╗\n")
    cat("║               WINDOW OPTIMIZATION QUALITY REPORT                      ║\n")
    cat("╚═══════════════════════════════════════════════════════════════════════╝\n\n")

    cat("Strategy Comparison (sorted by Quality Score):\n")
    cat("───────────────────────────────────────────────────────────────────────────\n")
    cat(sprintf("%-12s %8s %10s %10s %10s %10s\n",
                "Strategy", "Score", "Coverage", "Uniform", "Effic", "Specif"))
    cat("───────────────────────────────────────────────────────────────────────────\n")

    for (i in 1:nrow(report_df)) {
      row <- report_df[i, ]
      cat(sprintf("%-12s %7.1f%% %9.1f%% %9.1f%% %9.1f%% %9.1f%%\n",
                  row$strategy,
                  row$quality_score,
                  row$coverage,
                  row$uniformity,
                  row$efficiency,
                  row$specificity))
    }
    cat("───────────────────────────────────────────────────────────────────────────\n")

    # Highlight best strategy
    best <- report_df[1, ]
    cat(sprintf("\n🏆 Best Strategy: %s (Quality Score: %.1f%%)\n",
                best$strategy, best$quality_score))

    # Weight explanation
    cat("\n📊 Weights: Coverage=35%, Uniformity=25%, Efficiency=20%, Specificity=20%\n")
    cat("   Higher scores indicate better optimization quality.\n\n")
  }

  report_df
}


#' Get Quality Score Interpretation
#'
#' Provides human-readable interpretation of quality score ranges
#'
#' @param score Numeric quality score (0-100)
#'
#' @return Character string with interpretation
#' @export
interpret_quality_score <- function(score) {
  if (score >= 85) {
    return("Excellent - Highly optimized windows with balanced metrics")
  } else if (score >= 70) {
    return("Good - Well-optimized windows suitable for most applications")
  } else if (score >= 55) {
    return("Moderate - Acceptable optimization, consider parameter tuning")
  } else if (score >= 40) {
    return("Fair - Suboptimal, review m/z strategy or RT binning")
  } else {
    return("Poor - Significant optimization issues, investigate data quality")
  }
}


cat("  [stage3_quality_score.R] Quality Score functions loaded\n")
