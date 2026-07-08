# mz_optimization.R - m/z Range Optimization (S3 dispatch)
#
# Purpose: Optimize m/z ranges for each RT bin using one of five strategies.
#
# Architecture (v0.4.1+, S3 dispatch):
#   optimize_mz_ranges(config, ...) is an S3 generic.
#
#     GLOBAL strategies (override top-level method):
#       optimize_mz_ranges.greedy_config()  - MacCoss Lab sliding window
#       optimize_mz_ranges.kde_config()     - Kernel Density Estimation
#
#     LOCAL strategies (inherit per-RT-bin iteration from parent):
#       optimize_mz_ranges.local_strategy_config()  - parent: per-bin loop
#         compute_mz_range_for_bin.quantile_config()  - P5-P95 per bin
#         compute_mz_range_for_bin.coverage_config()  - narrowest range
#         compute_mz_range_for_bin.outlier_config()   - mean +/- SD
#
# Boundary smoothing is a SEPARATE post-processor in R/smoothing_utils.R
# (apply_smoothing() S3 generic), NOT part of these methods. Each method
# returns RAW (unsmoothed) m/z boundaries.
#
# See docs/adr/0002-s3-dispatch-mz-optimization.md for design rationale.
#
# Dependencies: dplyr, R/strategy_config.R, R/utils_common.R


# =============================================================================
# Generic: optimize_mz_ranges()
# =============================================================================

#' Optimize m/z Ranges Across RT Bins (S3 Generic)
#'
#' Dispatches on the class of \code{config} to invoke a strategy-specific
#' implementation. Returns a data frame with raw (unsmoothed) m/z boundaries
#' per RT bin. To apply boundary smoothing, pass the result through
#' \code{\link{apply_smoothing}}.
#'
#' @param config A strategy_config object (use \code{\link{greedy_config}},
#'   \code{\link{kde_config}}, \code{\link{quantile_config}},
#'   \code{\link{coverage_config}}, or \code{\link{outlier_config}}).
#' @param precursor_data Data frame with at least \code{rt_group} and
#'   \code{Precursor.Mz} columns.
#' @param rt_stats Data frame of RT bin statistics with \code{rt_start},
#'   \code{rt_end} columns (one row per bin).
#' @param n_windows_per_bin Integer, number of MS2 windows per RT bin.
#'   Required by greedy strategy (determines fixed m/z range per cycle).
#' @param min_width_da Numeric, minimum isolation window width in Da.
#'   Used by greedy strategy.
#' @param mz_range_min Numeric, fallback minimum m/z for empty RT bins.
#' @param mz_range_max Numeric, fallback maximum m/z for empty RT bins.
#' @param ... Additional arguments passed to method.
#'
#' @return Data frame with columns rt_segment_id, rt_start, rt_end, mz_min,
#'   mz_max, mz_width, n_precursors_covered, coverage_ratio. The KDE method
#'   additionally returns a \code{kde_peak_mz} column.
#'
#' @export
#' @keywords internal
optimize_mz_ranges <- function(config, precursor_data, rt_stats,
                                n_windows_per_bin = 10, min_width_da = 2,
                                mz_range_min = 400, mz_range_max = 1200,
                                ...) {
  UseMethod("optimize_mz_ranges")
}


# =============================================================================
# Shared result-row constructor
# =============================================================================

#' Build a Single m/z Range Result Row
#'
#' Constructs the canonical per-RT-bin result row shared by every strategy
#' (LOCAL parent, greedy, KDE). Centralizing the schema here means a new result
#' column is added in ONE place. The optional \code{kde_peak_mz} is appended as
#' the last column only when supplied (KDE strategy).
#'
#' @param i Integer RT bin index.
#' @param rt_stats Data frame of RT bin statistics (uses \code{rt_start},
#'   \code{rt_end} at row \code{i}).
#' @param mz_min,mz_max Numeric m/z bounds for the bin.
#' @param n_covered Integer precursors covered by \code{[mz_min, mz_max]}.
#' @param coverage_ratio Numeric coverage fraction (or \code{NA} for empty bins).
#' @param kde_peak_mz Optional numeric KDE peak m/z (KDE strategy only).
#'
#' @return One-row data frame with the standard m/z range columns.
#' @keywords internal
make_mz_range_row <- function(i, rt_stats, mz_min, mz_max, n_covered,
                              coverage_ratio, kde_peak_mz = NULL) {
  row <- data.frame(
    rt_segment_id = i,
    rt_start = rt_stats$rt_start[i],
    rt_end = rt_stats$rt_end[i],
    mz_min = mz_min,
    mz_max = mz_max,
    mz_width = mz_max - mz_min,
    n_precursors_covered = n_covered,
    coverage_ratio = coverage_ratio
  )
  if (!is.null(kde_peak_mz)) row$kde_peak_mz <- kde_peak_mz
  row
}


# =============================================================================
# LOCAL Strategy: parent method (per-RT-bin iteration)
# =============================================================================

#' Optimize m/z Ranges via Per-RT-Bin Iteration (LOCAL Strategies)
#'
#' Parent S3 method for all \code{local_strategy_config} subclasses
#' (quantile, coverage, outlier). Iterates over RT bins, dispatches the
#' per-bin computation via \code{\link{compute_mz_range_for_bin}}, then
#' assembles the result data frame.
#'
#' Subclasses do NOT override this method; they only implement
#' \code{compute_mz_range_for_bin.*_config()}.
#'
#' @inheritParams optimize_mz_ranges
#' @return Data frame with m/z ranges per RT segment.
#' @export
#' @keywords internal
optimize_mz_ranges.local_strategy_config <- function(config, precursor_data,
                                                       rt_stats,
                                                       n_windows_per_bin = 10,
                                                       min_width_da = 2,
                                                       mz_range_min = 400,
                                                       mz_range_max = 1200,
                                                       ...) {
  n_bins <- nrow(rt_stats)
  strategy_name <- toupper(config$strategy)

  cat(sprintf("  Strategy: %s (LOCAL optimization)\n", strategy_name))
  cat("  -> Calculate m/z independently per RT bin\n")
  if (inherits(config, "coverage_config") && config$coverage_mode == "centered") {
    cat("  -> Coverage mode: CENTERED (expand from median)\n")
  }
  cat("  -> Sequential processing\n\n")

  process_func <- function(i) {
    bin_data <- precursor_data %>% dplyr::filter(rt_group == i)

    if (nrow(bin_data) == 0) {
      # Empty bin - use configured fallback range
      return(make_mz_range_row(i, rt_stats, mz_range_min, mz_range_max,
                               n_covered = 0, coverage_ratio = NA))
    }

    # Strategy-specific m/z bounds (dispatched on config class)
    bounds <- compute_mz_range_for_bin(config, bin_data)

    mz_values <- bin_data$Precursor.Mz
    covered <- sum(mz_values >= bounds$mz_min & mz_values <= bounds$mz_max)
    coverage_ratio <- covered / length(mz_values)

    make_mz_range_row(i, rt_stats, bounds$mz_min, bounds$mz_max,
                      n_covered = covered, coverage_ratio = coverage_ratio)
  }

  bin_results <- lapply(1:n_bins, process_func)
  safe_bind_rows(bin_results)
}


# =============================================================================
# Sub-generic: compute_mz_range_for_bin() (LOCAL strategies only)
# =============================================================================

#' Compute m/z Range for a Single RT Bin (S3 Generic)
#'
#' Strategy-specific computation invoked by
#' \code{optimize_mz_ranges.local_strategy_config()} on each non-empty RT bin.
#' Each LOCAL strategy implements one method.
#'
#' @param config A \code{local_strategy_config} subclass.
#' @param bin_data Data frame of precursors in a single RT bin
#'   (filtered by \code{rt_group}).
#'
#' @return List with \code{mz_min}, \code{mz_max} numeric scalars.
#' @export
#' @keywords internal
compute_mz_range_for_bin <- function(config, bin_data) {
  UseMethod("compute_mz_range_for_bin")
}

#' @rdname compute_mz_range_for_bin
#' @export
compute_mz_range_for_bin.quantile_config <- function(config, bin_data) {
  mz_values <- bin_data$Precursor.Mz
  list(
    mz_min = quantile(mz_values, config$quantile_lower, na.rm = TRUE, names = FALSE),
    mz_max = quantile(mz_values, config$quantile_upper, na.rm = TRUE, names = FALSE)
  )
}

#' @rdname compute_mz_range_for_bin
#' @export
compute_mz_range_for_bin.coverage_config <- function(config, bin_data) {
  mz_values <- bin_data$Precursor.Mz
  n_total <- length(mz_values)
  n_target <- ceiling(n_total * config$target_coverage)

  if (config$coverage_mode == "centered") {
    # Centered: expand symmetrically from median
    mz_median <- median(mz_values)
    abs_diff <- abs(mz_values - mz_median)
    dist_threshold <- quantile(abs_diff, config$target_coverage, names = FALSE)
    return(list(
      mz_min = mz_median - dist_threshold,
      mz_max = mz_median + dist_threshold
    ))
  }

  # Narrowest mode: minimum-width window containing n_target precursors
  mz_sorted <- sort(mz_values)
  valid_starts <- length(mz_sorted) - n_target + 1

  if (valid_starts > 0) {
    starts <- 1:valid_starts
    ends <- starts + n_target - 1
    widths <- mz_sorted[ends] - mz_sorted[starts]
    best_idx <- which.min(widths)
    list(
      mz_min = mz_sorted[starts[best_idx]],
      mz_max = mz_sorted[ends[best_idx]]
    )
  } else {
    list(mz_min = min(mz_values), mz_max = max(mz_values))
  }
}

#' @rdname compute_mz_range_for_bin
#' @export
compute_mz_range_for_bin.outlier_config <- function(config, bin_data) {
  mz_values <- bin_data$Precursor.Mz
  mz_mean <- mean(mz_values, na.rm = TRUE)
  mz_sd <- sd(mz_values, na.rm = TRUE)

  # A single precursor gives sd = NA (all-identical m/z with n >= 2 gives sd = 0,
  # which the normal path handles). NA sd would propagate to NA bounds ->
  # mz_values[NA] -> min/max(NA, na.rm = TRUE) = Inf/-Inf. With no spread there
  # are no outliers: return the raw value range.
  if (is.na(mz_sd)) {
    return(list(mz_min = min(mz_values, na.rm = TRUE),
                mz_max = max(mz_values, na.rm = TRUE)))
  }

  lower_bound <- mz_mean - (config$outlier_threshold * mz_sd)
  upper_bound <- mz_mean + (config$outlier_threshold * mz_sd)

  inliers <- mz_values >= lower_bound & mz_values <= upper_bound
  mz_inliers <- mz_values[inliers]

  if (length(mz_inliers) > 0) {
    list(mz_min = min(mz_inliers, na.rm = TRUE),
         mz_max = max(mz_inliers, na.rm = TRUE))
  } else {
    list(mz_min = min(mz_values, na.rm = TRUE),
         mz_max = max(mz_values, na.rm = TRUE))
  }
}


# =============================================================================
# GLOBAL Strategy: Greedy (MacCoss Lab sliding window)
# =============================================================================

#' Optimize m/z Ranges with Greedy Sliding Window (GLOBAL Strategy)
#'
#' MacCoss Lab dynamicDIA algorithm: the m/z range per cycle is FIXED
#' (\code{n_windows_per_bin * min_width_da}). The algorithm slides this fixed
#' range across the m/z axis to find the position covering the maximum
#' precursors in each RT bin.
#'
#' Returns RAW boundaries (no smoothing applied). To smooth, pass through
#' \code{\link{apply_smoothing}}.
#'
#' Reference: https://github.com/uw-maccosslab/manuscript-dynamic-dia
#'
#' @inheritParams optimize_mz_ranges
#' @return Data frame with m/z ranges per RT segment.
#' @export
#' @keywords internal
optimize_mz_ranges.greedy_config <- function(config, precursor_data, rt_stats,
                                              n_windows_per_bin = 10,
                                              min_width_da = 2,
                                              mz_range_min = 400,
                                              mz_range_max = 1200,
                                              ...) {
  n_bins <- nrow(rt_stats)
  # width-semantics-split: `min_width_da` is the SOFT recommended isolation
  # width (instrument recommended_min_width_da, digitization S3). The greedy
  # cycle range is its capacity: N windows x recommended width.
  greedy_cycle_range_da <- n_windows_per_bin * min_width_da
  mz_range_per_cycle <- greedy_cycle_range_da
  mz_step <- config$mz_step

  cat("  Strategy: GREEDY (m/z sliding optimization)\n")
  cat("  -> Slide window across m/z axis, maximize precursor count\n")
  cat(sprintf("     Windows per bin: %d\n", n_windows_per_bin))
  cat(sprintf("     Isolation width: %.1f Da\n", min_width_da))
  cat(sprintf("     Fixed m/z range per cycle: %.1f Da\n", mz_range_per_cycle))
  cat(sprintf("     Sliding step: %.1f Da\n\n", mz_step))

  mz_min_raw <- numeric(n_bins)
  mz_max_raw <- numeric(n_bins)
  n_precursors_covered <- numeric(n_bins)
  coverage_ratios <- numeric(n_bins)
  n_precursors_total <- numeric(n_bins)

  for (i in 1:n_bins) {
    bin_data <- precursor_data %>% dplyr::filter(rt_group == i)

    if (nrow(bin_data) == 0) {
      center <- (mz_range_min + mz_range_max) / 2
      mz_min_raw[i] <- center - mz_range_per_cycle / 2
      mz_max_raw[i] <- center + mz_range_per_cycle / 2
      n_precursors_covered[i] <- 0
      coverage_ratios[i] <- NA
      n_precursors_total[i] <- 0
      next
    }

    mz_values <- bin_data$Precursor.Mz
    n_precursors <- length(mz_values)
    n_precursors_total[i] <- n_precursors
    global_mz_min <- min(mz_values)
    global_mz_max <- max(mz_values)
    global_mz_range <- global_mz_max - global_mz_min

    if (global_mz_range <= mz_range_per_cycle) {
      # Precursor range fits within fixed window - center it
      center <- (global_mz_min + global_mz_max) / 2
      mz_min_raw[i] <- center - mz_range_per_cycle / 2
      mz_max_raw[i] <- center + mz_range_per_cycle / 2
      n_precursors_covered[i] <- n_precursors
    } else {
      # Greedy search via sorted + findInterval (O(n log n))
      best_count <- 0
      best_mz_min <- global_mz_min
      mz_sorted <- sort(mz_values)
      trial_starts <- seq(global_mz_min,
                          global_mz_max - mz_range_per_cycle,
                          by = mz_step)

      for (trial_mz_min in trial_starts) {
        trial_mz_max <- trial_mz_min + mz_range_per_cycle
        left <- findInterval(trial_mz_min, mz_sorted, left.open = TRUE)
        right <- findInterval(trial_mz_max, mz_sorted, left.open = FALSE)
        precursors_in_range <- right - left

        if (precursors_in_range > best_count) {
          best_count <- precursors_in_range
          best_mz_min <- trial_mz_min
        }
      }

      mz_min_raw[i] <- best_mz_min
      mz_max_raw[i] <- best_mz_min + mz_range_per_cycle
      n_precursors_covered[i] <- best_count
    }

    coverage_ratios[i] <- n_precursors_covered[i] / n_precursors
  }

  # Build result data frame (no smoothing here - that's apply_smoothing's job)
  result_rows <- vector("list", n_bins)
  for (i in 1:n_bins) {
    result_rows[[i]] <- make_mz_range_row(
      i, rt_stats, mz_min_raw[i], mz_max_raw[i],
      n_covered = n_precursors_covered[i], coverage_ratio = coverage_ratios[i])
  }

  mean_coverage <- mean(coverage_ratios, na.rm = TRUE)
  cat(sprintf("     Optimized %d RT bins\n", n_bins))
  cat(sprintf("     Mean coverage (raw): %.1f%% (within fixed %.0f Da range)\n",
              mean_coverage * 100, mz_range_per_cycle))

  if (mean_coverage < 0.5) {
    cat("\n  [!] Note: Low coverage is expected when precursor m/z distribution\n")
    cat(sprintf("         is wider than instrument capacity (%.0f Da range).\n",
                mz_range_per_cycle))
    cat("         Consider using 'coverage' strategy for higher coverage.\n")
  }

  safe_bind_rows(result_rows)
}


# =============================================================================
# GLOBAL Strategy: KDE (Density-peak based)
# =============================================================================

#' Optimize m/z Ranges via Kernel Density Estimation (GLOBAL Strategy)
#'
#' Finds the densest m/z regions per RT bin. Computes 1D KDE, locates the
#' density peak, expands until density drops below threshold OR minimum
#' coverage is met.
#'
#' KDE strategy does NOT support boundary smoothing
#' (\code{\link{apply_smoothing}} is a no-op for \code{kde_config}).
#'
#' @inheritParams optimize_mz_ranges
#' @return Data frame with m/z ranges per RT segment plus a
#'   \code{kde_peak_mz} column.
#' @export
#' @keywords internal
optimize_mz_ranges.kde_config <- function(config, precursor_data, rt_stats,
                                            n_windows_per_bin = 10,
                                            min_width_da = 2,
                                            mz_range_min = 400,
                                            mz_range_max = 1200,
                                            ...) {
  n_bins <- nrow(rt_stats)
  mz_ranges <- vector("list", n_bins)
  density_threshold <- config$kde_density_threshold
  min_coverage <- config$kde_min_coverage

  cat("  Strategy: KDE (Density-Peak based m/z range)\n")
  cat("  -> Find density peak, expand until threshold reached\n")
  cat(sprintf("     Density threshold: %.0f%% of peak\n", density_threshold * 100))
  cat(sprintf("     Minimum coverage target: %.0f%%\n\n", min_coverage * 100))

  for (i in 1:n_bins) {
    bin_data <- precursor_data %>% dplyr::filter(rt_group == i)

    if (nrow(bin_data) == 0) {
      mz_ranges[[i]] <- make_mz_range_row(
        i, rt_stats, mz_range_min, mz_range_max,
        n_covered = 0, coverage_ratio = NA, kde_peak_mz = NA)
      next
    }

    mz_values <- bin_data$Precursor.Mz
    n_precursors <- length(mz_values)

    if (n_precursors < 10) {
      # Too few points for meaningful KDE
      mz_min <- min(mz_values) - 10
      mz_max <- max(mz_values) + 10
      kde_peak <- median(mz_values)
    } else {
      kde <- tryCatch({
        density(mz_values, bw = "SJ", n = 512)
      }, error = function(e) {
        density(mz_values, bw = "nrd0", n = 512)
      })

      peak_idx <- which.max(kde$y)
      kde_peak <- kde$x[peak_idx]
      peak_density <- kde$y[peak_idx]
      threshold_value <- peak_density * density_threshold

      left_idx <- peak_idx
      while (left_idx > 1 && kde$y[left_idx] > threshold_value) {
        left_idx <- left_idx - 1
      }
      kde_mz_min <- kde$x[left_idx]

      right_idx <- peak_idx
      while (right_idx < length(kde$y) && kde$y[right_idx] > threshold_value) {
        right_idx <- right_idx + 1
      }
      kde_mz_max <- kde$x[right_idx]

      covered_kde <- sum(mz_values >= kde_mz_min & mz_values <= kde_mz_max)
      coverage_kde <- covered_kde / n_precursors

      if (coverage_kde < min_coverage) {
        # Expand to meet minimum coverage
        sorted_mz <- sort(mz_values)
        n_needed <- ceiling(n_precursors * min_coverage)
        best_width <- Inf
        best_start <- 1

        for (start_idx in 1:(n_precursors - n_needed + 1)) {
          end_idx <- start_idx + n_needed - 1
          width <- sorted_mz[end_idx] - sorted_mz[start_idx]
          range_includes_peak <- sorted_mz[start_idx] <= kde_peak &&
                                 sorted_mz[end_idx] >= kde_peak
          if (range_includes_peak && width < best_width) {
            best_width <- width
            best_start <- start_idx
          }
        }

        if (best_width == Inf) {
          for (start_idx in 1:(n_precursors - n_needed + 1)) {
            end_idx <- start_idx + n_needed - 1
            width <- sorted_mz[end_idx] - sorted_mz[start_idx]
            if (width < best_width) {
              best_width <- width
              best_start <- start_idx
            }
          }
        }

        mz_min <- sorted_mz[best_start]
        mz_max <- sorted_mz[best_start + n_needed - 1]
      } else {
        mz_min <- kde_mz_min
        mz_max <- kde_mz_max
      }
    }

    # Small margin (2%)
    margin <- (mz_max - mz_min) * 0.02
    mz_min <- mz_min - margin
    mz_max <- mz_max + margin

    covered <- sum(mz_values >= mz_min & mz_values <= mz_max)
    coverage_ratio <- covered / n_precursors

    mz_ranges[[i]] <- make_mz_range_row(
      i, rt_stats, mz_min, mz_max,
      n_covered = covered, coverage_ratio = coverage_ratio, kde_peak_mz = kde_peak)
  }

  mean_coverage <- mean(sapply(mz_ranges, function(x) x$coverage_ratio), na.rm = TRUE)
  mean_width <- mean(sapply(mz_ranges, function(x) x$mz_width), na.rm = TRUE)
  cat(sprintf("     Optimized %d RT bins\n", n_bins))
  cat(sprintf("     Mean coverage: %.1f%%\n", mean_coverage * 100))
  cat(sprintf("     Mean m/z width: %.1f Da\n", mean_width))

  safe_bind_rows(mz_ranges)
}


# =============================================================================
# Default error: unknown strategy_config subclass
# =============================================================================

#' @rdname optimize_mz_ranges
#' @export
optimize_mz_ranges.default <- function(config, ...) {
  if (inherits(config, "strategy_config")) {
    stop(sprintf(
      "No optimize_mz_ranges() method for class '%s'. ",
      class(config)[1]
    ), "Add a method via S3 dispatch: optimize_mz_ranges.<class>().")
  }
  stop("config must be a strategy_config object created by greedy_config(), ",
       "kde_config(), quantile_config(), coverage_config(), or outlier_config().")
}
