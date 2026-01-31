# stage3_strategy_characteristics.R - Window Strategy Characteristics
#
# Purpose: Describe window configuration characteristics WITHOUT quality judgment
#          This is purely descriptive - no scoring or ranking between strategies
#
# Philosophy:
#   - Each m/z strategy has DIFFERENT characteristics, not better/worse
#   - Actual DIA analysis quality can only be determined by running the method
#   - This module provides metrics to UNDERSTAND the window configuration
#
# Version: 1.0

library(dplyr)

# =============================================================================
# Strategy Characteristics Calculation
# =============================================================================

#' Calculate Strategy Characteristics
#'
#' Computes descriptive metrics for the window configuration.
#' These metrics describe WHAT the strategy produces, not HOW GOOD it is.
#'
#' @param windows Data frame with window specifications
#' @param precursor_data Data frame with precursor information
#' @param strategy Character, the m/z strategy used
#'
#' @return List with descriptive characteristics
#' @export
calculate_strategy_characteristics <- function(windows, precursor_data, strategy) {

  if (is.null(windows) || nrow(windows) == 0) {
    return(NULL)
  }

  # Basic window metrics
  n_windows <- nrow(windows)
  n_rt_bins <- length(unique(windows$rt_segment_id))
  windows_per_bin <- n_windows / n_rt_bins


  # Window width characteristics
  widths <- windows$mz_end - windows$mz_start
  width_stats <- list(
    mean_da = round(mean(widths), 1),
    median_da = round(median(widths), 1),
    min_da = round(min(widths), 1),
    max_da = round(max(widths), 1),
    sd_da = round(sd(widths), 2),
    cv_pct = round(sd(widths) / mean(widths) * 100, 1)
  )

  # m/z range coverage
  total_mz_coverage <- sum(widths)
  data_mz_range <- range(precursor_data$Precursor.Mz, na.rm = TRUE)
  data_mz_span <- diff(data_mz_range)

  # Precursor distribution
  if ("n_precursors" %in% colnames(windows)) {
    prec_per_window <- windows$n_precursors
  } else {
    # Count manually if not present
    prec_per_window <- sapply(1:nrow(windows), function(i) {
      w <- windows[i, ]
      sum(precursor_data$RT.Start >= w$rt_start &
          precursor_data$RT.Start <= w$rt_end &
          precursor_data$Precursor.Mz >= w$mz_start &
          precursor_data$Precursor.Mz < w$mz_end)
    })
  }

  precursor_stats <- list(
    total = nrow(precursor_data),
    mean_per_window = round(mean(prec_per_window), 1),
    median_per_window = round(median(prec_per_window), 1),
    min_per_window = min(prec_per_window),
    max_per_window = max(prec_per_window),
    cv_pct = round(sd(prec_per_window) / mean(prec_per_window) * 100, 1)
  )

  # Strategy-specific interpretation
  strategy_description <- get_strategy_description(strategy)

  list(
    strategy = strategy,
    strategy_description = strategy_description,

    window_count = list(
      total = n_windows,
      rt_bins = n_rt_bins,
      per_bin = windows_per_bin
    ),

    width_characteristics = width_stats,

    mz_coverage = list(
      total_da = round(total_mz_coverage, 1),
      data_range_da = round(data_mz_span, 1),
      data_range = round(data_mz_range, 1)
    ),

    precursor_distribution = precursor_stats,

    # Descriptive flags (not quality judgments)
    flags = list(
      uniform_widths = width_stats$cv_pct < 20,
      variable_widths = width_stats$cv_pct >= 20,
      balanced_precursors = precursor_stats$cv_pct < 50,
      sparse_windows = any(prec_per_window < 10),
      dense_windows = any(prec_per_window > 500)
    )
  )
}


#' Get Strategy Description
#'
#' Returns a neutral description of what each strategy does.
#' No quality judgment - just factual description.
#'
#' @param strategy Character, strategy name
#' @return Character, description
#' @keywords internal
get_strategy_description <- function(strategy) {
  descriptions <- list(
    quantile = "Uses P5-P95 percentiles of m/z distribution per RT bin. Fast and robust to outliers.",
    coverage = "Finds minimum m/z range covering target % of precursors. Conservative approach.",
    outlier = "Uses mean +/- 3*SD to include most precursors. Inclusive of high-density regions.",
    smoothing = "Applies Savitzky-Golay smoothing across RT for continuous m/z boundaries. Gradient-wide optimization."
  )

  if (strategy %in% names(descriptions)) {
    return(descriptions[[strategy]])
  }

  return(sprintf("Custom strategy: %s", strategy))
}


#' Generate Strategy Comparison Table
#'
#' Creates a comparison table of characteristics across multiple strategies.
#' This is DESCRIPTIVE only - no ranking or scoring.
#'
#' @param characteristics_list Named list of strategy characteristics
#' @return Data frame for comparison
#' @export
generate_strategy_comparison <- function(characteristics_list) {
  if (length(characteristics_list) == 0) {
    return(NULL)
  }

  comparison_df <- data.frame(
    Strategy = names(characteristics_list),
    Windows = sapply(characteristics_list, function(c) c$window_count$total),
    RT_Bins = sapply(characteristics_list, function(c) c$window_count$rt_bins),
    Mean_Width_Da = sapply(characteristics_list, function(c) c$width_characteristics$mean_da),
    Width_CV_pct = sapply(characteristics_list, function(c) c$width_characteristics$cv_pct),
    Precursors_per_Window = sapply(characteristics_list, function(c) c$precursor_distribution$mean_per_window),
    Precursor_CV_pct = sapply(characteristics_list, function(c) c$precursor_distribution$cv_pct),
    stringsAsFactors = FALSE
  )

  rownames(comparison_df) <- NULL
  comparison_df
}


#' Print Strategy Characteristics Summary
#'
#' Prints a human-readable summary of strategy characteristics.
#'
#' @param characteristics Strategy characteristics from calculate_strategy_characteristics()
#' @param verbose Logical, print detailed output
#' @export
print_strategy_characteristics <- function(characteristics, verbose = TRUE) {
  if (is.null(characteristics)) {
    cat("No characteristics available\n")
    return(invisible(NULL))
  }

  if (!verbose) return(invisible(characteristics))

  cat("\n")
  cat("Strategy Characteristics Summary\n")
  cat(sprintf("Strategy: %s\n", toupper(characteristics$strategy)))
  cat(sprintf("Description: %s\n", characteristics$strategy_description))
  cat("\n")

  cat("Window Configuration:\n")
  cat(sprintf("  Total Windows: %d\n", characteristics$window_count$total))
  cat(sprintf("  RT Bins: %d\n", characteristics$window_count$rt_bins))
  cat(sprintf("  Windows per Bin: %.1f\n", characteristics$window_count$per_bin))
  cat("\n")

  cat("Width Characteristics:\n")
  w <- characteristics$width_characteristics
  cat(sprintf("  Mean: %.1f Da, Median: %.1f Da\n", w$mean_da, w$median_da))
  cat(sprintf("  Range: %.1f - %.1f Da\n", w$min_da, w$max_da))
  cat(sprintf("  CV: %.1f%% (%s)\n", w$cv_pct,
              if (w$cv_pct < 20) "uniform" else "variable"))
  cat("\n")

  cat("Precursor Distribution:\n")
  p <- characteristics$precursor_distribution
  cat(sprintf("  Mean per Window: %.1f\n", p$mean_per_window))
  cat(sprintf("  Range: %d - %d\n", p$min_per_window, p$max_per_window))
  cat(sprintf("  CV: %.1f%%\n", p$cv_pct))
  cat("\n")

  invisible(characteristics)
}


cat("  [stage3_strategy_characteristics.R] Strategy characteristics functions loaded\n")
