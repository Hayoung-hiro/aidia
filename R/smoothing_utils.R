# smoothing_utils.R - Smoothing Utilities for DIA Window Optimization
#
# Purpose: Provide smoothing functions for m/z boundary smoothing across RT bins
#
# Methods:
#   - Savitzky-Golay (SG): Traditional fixed-window polynomial smoother (via prospectr)
#   - Whittaker-Henderson (WH): Penalized least squares with per-point weights (experimental)
#
# Dependencies: prospectr package (optional, for SG)

# prospectr availability is checked at runtime inside smooth_savgol()

# =============================================================================
# Linear Extrapolation Helper (for SG boundary handling)
# =============================================================================

#' Linear extrapolation to extend data at boundaries
#'
#' Extends data by `n_extend` points on each side using linear extrapolation
#' from the first/last 2 points. This prevents SG boundary artifacts by
#' providing the smoother with sufficient context at edges.
#'
#' Reference: Schmid et al. (2022) ACS Meas. Sci. Au, 2(2), 185-196
#'
#' @param y Numeric vector
#' @param n_extend Number of points to extend on each side
#' @return Extended numeric vector of length `length(y) + 2 * n_extend`
#' @keywords internal
extrapolate_linear <- function(y, n_extend) {
  n <- length(y)
  if (n < 2 || n_extend < 1) return(y)

  # Left extrapolation: slope from first 2 points
  slope_left <- y[2] - y[1]
  left_ext <- y[1] - slope_left * (n_extend:1)

  # Right extrapolation: slope from last 2 points
  slope_right <- y[n] - y[n - 1]
  right_ext <- y[n] + slope_right * (1:n_extend)

  c(left_ext, y, right_ext)
}

# =============================================================================
# Core Smoothing Function (Savitzky-Golay only)
# =============================================================================

#' Savitzky-Golay smoothing using prospectr package
#'
#' Falls back to simple moving average if prospectr is not available.
#'
#' @param y_array Numeric vector to be smoothed
#' @param window_size Window size (default: 7, must be odd number)
#' @param poly_order Polynomial order (default: 3)
#' @return Smoothed numeric vector
#' @keywords internal
smooth_savgol <- function(y_array, window_size = 7, poly_order = 3) {

  # Ensure we have enough data points
  if (length(y_array) < window_size) {
    warning("Data length is smaller than window size. Returning original data.")
    return(y_array)
  }

  # Ensure window_size is odd
  if (window_size %% 2 == 0) {
    window_size <- window_size + 1
    warning(sprintf("Window size must be odd. Adjusted to %d.", window_size))
  }

  # Store original length for boundary restoration
  original_length <- length(y_array)

  # Check if prospectr is available
  if (!requireNamespace("prospectr", quietly = TRUE)) {
    # Fallback: Simple moving average smoothing
    cat("     Using moving average fallback (prospectr not available)\n")
    return(smooth_moving_average(y_array, window_size))
  }

  # Use prospectr Savitzky-Golay filter with linear extrapolation at boundaries
  # (Schmid et al. 2022, ACS Meas. Sci. Au): extend data with linear extrapolation
  # before smoothing, then trim — avoids boundary artifacts from raw value retention
  tryCatch({
    half_window <- (window_size - 1) / 2

    # Linear extrapolation at boundaries to avoid edge artifacts
    y_extended <- extrapolate_linear(y_array, half_window)

    # Convert to matrix for prospectr (expects matrix input)
    y_matrix <- matrix(y_extended, nrow = 1)

    # Apply Savitzky-Golay filter using prospectr
    smoothed_matrix <- prospectr::savitzkyGolay(
      X = y_matrix,
      m = 0,              # 0th derivative (smoothing)
      p = poly_order,     # polynomial order
      w = window_size     # window size
    )

    # Convert back to vector — prospectr removes half_window from each end
    smoothed <- as.vector(smoothed_matrix)

    # After extending by half_window on each side and prospectr trimming half_window,
    # the result should be original_length. Handle any remaining mismatch.
    if (length(smoothed) == original_length) {
      return(smoothed)
    } else if (length(smoothed) > original_length) {
      # Trim excess symmetrically
      excess <- length(smoothed) - original_length
      start <- floor(excess / 2) + 1
      return(smoothed[start:(start + original_length - 1)])
    } else {
      # Shorter than expected — pad with original boundary values
      result <- numeric(original_length)
      pad <- original_length - length(smoothed)
      pad_left <- floor(pad / 2)
      result[1:pad_left] <- y_array[1:pad_left]
      result[(pad_left + 1):(pad_left + length(smoothed))] <- smoothed
      result[(pad_left + length(smoothed) + 1):original_length] <-
        y_array[(pad_left + length(smoothed) + 1):original_length]
      return(result)
    }
  }, error = function(e) {
    # If prospectr fails, use moving average fallback
    warning(sprintf("Savitzky-Golay failed: %s. Using moving average.", e$message))
    return(smooth_moving_average(y_array, window_size))
  })
}


# =============================================================================
# Whittaker-Henderson Smoother (Experimental)
# =============================================================================

#' Whittaker-Henderson Smoothing with Per-Point Weights
#'
#' Penalized least squares smoother that balances data fidelity against
#' smoothness. Supports per-point weights for adaptive smoothing:
#' high-weight points are preserved, low-weight points are smoothed
#' toward their neighbors.
#'
#' Based on Eilers (2003) "A Perfect Smoother". No external dependencies.
#'
#' @param y Numeric vector to smooth
#' @param weights Numeric vector of per-point weights (default: uniform).
#'   Higher weight = trust this point more. Use e.g. sqrt(n_precursors).
#' @param lambda Smoothing parameter (default: 10). Higher = smoother.
#'   Typical range: 1 (light) to 1000 (very heavy).
#' @param d Difference order for penalty (default: 2 for second-order).
#'
#' @return Smoothed numeric vector (same length as y)
#' @keywords internal
smooth_whittaker <- function(y, weights = NULL, lambda = 10, d = 2) {
  n <- length(y)
  if (n < 3) return(y)
  if (n > 500) {
    warning("Whittaker smoother uses dense O(n^3) solver; n=", n,
            " is too large. Returning original values.")
    return(y)
  }

  if (is.null(weights)) {
    weights <- rep(1, n)
  } else {
    # Normalize weights to mean = 1 for consistent lambda interpretation
    w_positive <- weights[weights > 0]
    if (length(w_positive) > 0) {
      weights <- weights / mean(w_positive)
    }
    # Avoid zero weights (causes singular matrix)
    weights[weights < 1e-6] <- 1e-6
  }

  E <- diag(n)
  D <- diff(E, differences = d)
  W <- diag(weights)

  z <- tryCatch(
    solve(W + lambda * crossprod(D), W %*% y),
    error = function(e) {
      warning(sprintf("Whittaker smoother failed: %s. Returning original.", e$message))
      y
    }
  )

  as.numeric(z)
}


# =============================================================================
# Boundary Smoothing Dispatcher
# =============================================================================

#' Dispatch Boundary Smoothing Method
#'
#' Dispatches to either Savitzky-Golay or Whittaker-Henderson smoothing.
#' Used for m/z boundary smoothing across RT bins.
#'
#' @param y Numeric vector to smooth
#' @param method Character: "sg" (Savitzky-Golay) or "whittaker"
#' @param weights Numeric vector of per-point weights (only used by "whittaker")
#' @param window_size SG window size (only used by "sg")
#' @param poly_order SG polynomial order (only used by "sg")
#' @param lambda Whittaker smoothing parameter (only used by "whittaker")
#'
#' @return Smoothed numeric vector
#' @keywords internal
smooth_boundaries <- function(y, method = "sg", weights = NULL,
                               window_size = 7, poly_order = 3,
                               lambda = 10) {
  if (method == "whittaker") {
    smooth_whittaker(y, weights = weights, lambda = lambda)
  } else {
    smooth_savgol(y, window_size = window_size, poly_order = poly_order)
  }
}


#' Simple Moving Average Smoothing (Fallback)
#'
#' Used when prospectr package is not available or fails.
#'
#' @param y_array Numeric vector to be smoothed
#' @param window_size Window size (must be odd)
#' @return Smoothed numeric vector
#' @keywords internal
smooth_moving_average <- function(y_array, window_size) {
  n <- length(y_array)
  half_window <- floor(window_size / 2)
  result <- numeric(n)

  for (i in 1:n) {
    start_idx <- max(1, i - half_window)
    end_idx <- min(n, i + half_window)
    result[i] <- mean(y_array[start_idx:end_idx], na.rm = TRUE)
  }

  return(result)
}

#' Smooth m/z boundaries with optional quantile pre-filtering
#'
#' @param mz_array Numeric vector of m/z values
#' @param quantile_lower Lower quantile for pre-filtering (default: 0.05)
#' @param quantile_upper Upper quantile for pre-filtering (default: 0.95)
#' @param window_size Smoothing window size (default: 7)
#' @param poly_order Polynomial order (default: 3)
#' @return Smoothed numeric vector
#' @keywords internal
smooth_mz_boundaries <- function(
  mz_array,
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  window_size = 7,
  poly_order = 3
) {

  # Apply quantile filtering first to reduce sensitivity to outliers
  mz_min <- quantile(mz_array, quantile_lower, na.rm = TRUE)
  mz_max <- quantile(mz_array, quantile_upper, na.rm = TRUE)

  # Create filtered boundaries
  filtered_array <- pmax(pmin(mz_array, mz_max), mz_min)

  # Apply smoothing
  smoothed <- smooth_savgol(filtered_array, window_size, poly_order)

  return(smoothed)
}


# =============================================================================
# S3 Post-processor: apply_smoothing()
# =============================================================================
#
# Decouples boundary smoothing from strategy-specific m/z computation. Each
# strategy method returns RAW (unsmoothed) boundaries from
# optimize_mz_ranges(); apply_smoothing() is the dispatched post-processor.
#
# Dispatch table:
#   greedy_config()   -> WH/SG + fixed-width re-centering
#   quantile_config() -> WH/SG (controlled by config$quantile_apply_smoothing)
#   outlier_config()  -> WH/SG (controlled by config$outlier_apply_smoothing)
#   kde_config()      -> no-op (KDE produces inherently smooth boundaries)
#   coverage_config() -> no-op (narrowest-range semantics)


#' Apply Boundary Smoothing to m/z Ranges (S3 Generic)
#'
#' Post-processor invoked after \code{\link{optimize_mz_ranges}}. Dispatches
#' on the class of \code{config} to apply strategy-appropriate smoothing
#' (Whittaker-Henderson or Savitzky-Golay) to \code{mz_min} / \code{mz_max}
#' across RT bins, then recalculates coverage.
#'
#' Strategies without sharp boundary semantics (kde, coverage) provide no-op
#' methods that return \code{mz_ranges} unchanged.
#'
#' @param config A strategy_config object.
#' @param mz_ranges Data frame returned by \code{optimize_mz_ranges()}.
#' @param precursor_data Data frame for coverage recalculation after smoothing.
#' @param n_windows_per_bin Integer, used by greedy strategy for width constraint.
#' @param min_width_da Numeric, used by greedy strategy for width constraint.
#' @param ... Additional arguments.
#'
#' @return Data frame of smoothed m/z ranges (same shape as input).
#' @export
#' @keywords internal
apply_smoothing <- function(config, mz_ranges, precursor_data,
                             n_windows_per_bin = 10, min_width_da = 2, ...) {
  UseMethod("apply_smoothing")
}


# -----------------------------------------------------------------------------
# No-op methods for kde and coverage
# -----------------------------------------------------------------------------

#' @rdname apply_smoothing
#' @export
apply_smoothing.kde_config <- function(config, mz_ranges, precursor_data,
                                        n_windows_per_bin = 10,
                                        min_width_da = 2, ...) {
  # KDE produces inherently smooth boundaries; no further smoothing applied.
  mz_ranges
}

#' @rdname apply_smoothing
#' @export
apply_smoothing.coverage_config <- function(config, mz_ranges, precursor_data,
                                             n_windows_per_bin = 10,
                                             min_width_da = 2, ...) {
  # Coverage strategy uses narrowest-range semantics; smoothing would
  # contradict the "minimum range to cover target" guarantee.
  mz_ranges
}


# -----------------------------------------------------------------------------
# Active methods for greedy / quantile / outlier
# -----------------------------------------------------------------------------

#' @rdname apply_smoothing
#' @export
apply_smoothing.greedy_config <- function(config, mz_ranges, precursor_data,
                                           n_windows_per_bin = 10,
                                           min_width_da = 2, ...) {
  if (!isTRUE(config$greedy_apply_smoothing)) return(mz_ranges)
  if (nrow(mz_ranges) < 3) {
    cat("     Skipping smoothing (need at least 3 RT bins)\n")
    return(mz_ranges)
  }

  smoothed <- .smooth_mz_ranges_internal(
    mz_ranges = mz_ranges,
    precursor_data = precursor_data,
    method = config$smoothing_method,
    sg_window = config$smoothing_window,
    sg_poly = config$polynomial_order,
    wh_lambda = config$whittaker_lambda
  )

  # Greedy invariant: width must remain ~ the greedy cycle range
  # (N windows x min_width_da, the SOFT recommended isolation width / S3).
  greedy_cycle_range_da <- n_windows_per_bin * min_width_da
  mz_range_per_cycle <- greedy_cycle_range_da
  for (i in seq_len(nrow(smoothed))) {
    width_after <- smoothed$mz_max[i] - smoothed$mz_min[i]
    if (width_after < mz_range_per_cycle * 0.95) {
      center <- (smoothed$mz_min[i] + smoothed$mz_max[i]) / 2
      smoothed$mz_min[i] <- center - mz_range_per_cycle / 2
      smoothed$mz_max[i] <- center + mz_range_per_cycle / 2
      smoothed$mz_width[i] <- mz_range_per_cycle
    }
  }

  # Shared invariant guard: restore bins smoothing pushed below the absolute
  # floor. No-op for greedy (fixed-width re-centering keeps width >> floor).
  smoothed <- .repair_mz_ranges(smoothed, mz_ranges, ABSOLUTE_MIN_WIDTH_DA)
  .report_repaired(smoothed)
  .recalculate_coverage(smoothed, precursor_data)
}

#' @rdname apply_smoothing
#' @export
apply_smoothing.quantile_config <- function(config, mz_ranges, precursor_data,
                                              n_windows_per_bin = 10,
                                              min_width_da = 2, ...) {
  if (!isTRUE(config$quantile_apply_smoothing)) return(mz_ranges)
  if (nrow(mz_ranges) < 3) return(mz_ranges)

  smoothed <- .smooth_mz_ranges_internal(
    mz_ranges = mz_ranges,
    precursor_data = precursor_data,
    method = config$smoothing_method,
    sg_window = config$smoothing_window,
    sg_poly = config$polynomial_order,
    wh_lambda = config$whittaker_lambda
  )
  # Shared invariant guard: revert bins where independent min/max smoothing
  # crossed the boundary or fell below the absolute floor.
  smoothed <- .repair_mz_ranges(smoothed, mz_ranges, ABSOLUTE_MIN_WIDTH_DA)
  .report_repaired(smoothed)
  cat("  -> Smoothing applied successfully\n\n")
  .recalculate_coverage(smoothed, precursor_data)
}

#' @rdname apply_smoothing
#' @export
apply_smoothing.outlier_config <- function(config, mz_ranges, precursor_data,
                                             n_windows_per_bin = 10,
                                             min_width_da = 2, ...) {
  if (!isTRUE(config$outlier_apply_smoothing)) return(mz_ranges)
  if (nrow(mz_ranges) < 3) return(mz_ranges)

  smoothed <- .smooth_mz_ranges_internal(
    mz_ranges = mz_ranges,
    precursor_data = precursor_data,
    method = config$smoothing_method,
    sg_window = config$smoothing_window,
    sg_poly = config$polynomial_order,
    wh_lambda = config$whittaker_lambda
  )
  # Shared invariant guard: revert bins where independent min/max smoothing
  # crossed the boundary or fell below the absolute floor.
  smoothed <- .repair_mz_ranges(smoothed, mz_ranges, ABSOLUTE_MIN_WIDTH_DA)
  .report_repaired(smoothed)
  cat("  -> Smoothing applied successfully\n\n")
  .recalculate_coverage(smoothed, precursor_data)
}


# -----------------------------------------------------------------------------
# Default: unknown strategy_config subclass
# -----------------------------------------------------------------------------

#' @rdname apply_smoothing
#' @export
apply_smoothing.default <- function(config, mz_ranges, ...) {
  if (inherits(config, "strategy_config")) {
    # Unknown sub-class but is a strategy_config - default to no-op
    return(mz_ranges)
  }
  stop("config must be a strategy_config object.")
}


# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

#' Smooth mz_min and mz_max columns of an mz_ranges data frame
#' @keywords internal
.smooth_mz_ranges_internal <- function(mz_ranges, precursor_data, method,
                                        sg_window, sg_poly, wh_lambda) {
  n_bins <- nrow(mz_ranges)

  if (method == "whittaker") {
    bin_weights <- sqrt(pmax(mz_ranges$n_precursors_covered, 1))
    cat(sprintf("     WH params: lambda=%.0f, weights=sqrt(n_precursors)\n",
                wh_lambda))
    mz_min_smooth <- smooth_boundaries(mz_ranges$mz_min, method = "whittaker",
                                        weights = bin_weights, lambda = wh_lambda)
    mz_max_smooth <- smooth_boundaries(mz_ranges$mz_max, method = "whittaker",
                                        weights = bin_weights, lambda = wh_lambda)
  } else {
    adaptive_window <- min(sg_window, floor(n_bins * 0.7))
    if (adaptive_window %% 2 == 0) adaptive_window <- adaptive_window + 1
    adaptive_window <- max(3, adaptive_window)
    adaptive_poly <- min(sg_poly, adaptive_window - 2)
    adaptive_poly <- max(1, adaptive_poly)
    cat(sprintf("     SG params: window=%d, poly_order=%d\n",
                adaptive_window, adaptive_poly))
    mz_min_smooth <- smooth_boundaries(mz_ranges$mz_min, method = "sg",
                                        window_size = adaptive_window,
                                        poly_order = adaptive_poly)
    mz_max_smooth <- smooth_boundaries(mz_ranges$mz_max, method = "sg",
                                        window_size = adaptive_window,
                                        poly_order = adaptive_poly)
  }

  mz_ranges$mz_min <- mz_min_smooth
  mz_ranges$mz_max <- mz_max_smooth
  mz_ranges$mz_width <- mz_max_smooth - mz_min_smooth
  mz_ranges
}

#' Repair smoothed mz_ranges rows that violate the width invariant
#'
#' Smoothing mz_min and mz_max independently can push a bin to mz_min >= mz_max
#' (crossed / negative width) or below the absolute physical floor. Such bins
#' are restored to their pre-smoothing (raw) boundaries. Only violations of the
#' ABSOLUTE floor are repaired; bins merely below the SOFT recommended width
#' (min_width_da) are left untouched — digitization (S3) observes those.
#'
#' A raw bin that is itself already degenerate is out of scope (P3, strategy
#' stage): this guard only reverts what smoothing made worse.
#'
#' @param smoothed Data frame after boundary smoothing.
#' @param raw Data frame of pre-smoothing mz_ranges (same rows/order as smoothed).
#' @param floor_da Numeric absolute minimum width (default ABSOLUTE_MIN_WIDTH_DA).
#' @return \code{smoothed} with violating rows restored from \code{raw};
#'   \code{attr(., "n_repaired")} carries the number of repaired bins.
#' @keywords internal
.repair_mz_ranges <- function(smoothed, raw, floor_da = ABSOLUTE_MIN_WIDTH_DA) {
  bad <- smoothed$mz_min >= smoothed$mz_max |
    (smoothed$mz_max - smoothed$mz_min) < floor_da
  bad[is.na(bad)] <- TRUE  # NA boundary is invalid; restore from raw
  if (any(bad)) {
    smoothed[bad, c("mz_min", "mz_max", "mz_width")] <-
      raw[bad, c("mz_min", "mz_max", "mz_width")]
  }
  attr(smoothed, "n_repaired") <- sum(bad)
  smoothed
}

#' Log the invariant-guard repair count (no output when zero)
#' @keywords internal
.report_repaired <- function(mz_ranges) {
  n_rep <- attr(mz_ranges, "n_repaired")
  if (!is.null(n_rep) && n_rep > 0) {
    cat(sprintf(
      "     Invariant guard: restored %d bin(s) to raw (smoothing broke mz_min<mz_max or width<%.1f Da)\n",
      n_rep, ABSOLUTE_MIN_WIDTH_DA))
  }
  invisible(mz_ranges)
}

#' Recalculate per-bin coverage after boundary modification
#'
#' Uses the shared \code{\link{bin_membership}} rule (rt_group when present,
#' else RT.Apex range) so smoothing coverage counts match the membership that
#' generation / statistics assign to each bin (adaptive+merge previously
#' diverged; fixed binning is unaffected — the two rules coincide there).
#' @keywords internal
.recalculate_coverage <- function(mz_ranges, precursor_data) {
  for (i in seq_len(nrow(mz_ranges))) {
    member <- bin_membership(precursor_data,
                             mz_ranges$rt_start[i],
                             mz_ranges$rt_end[i],
                             mz_ranges$rt_segment_id[i])
    bin_data <- precursor_data[which(member), , drop = FALSE]
    if (nrow(bin_data) > 0) {
      mz_values <- bin_data$Precursor.Mz
      covered <- sum(mz_values >= mz_ranges$mz_min[i] &
                     mz_values <= mz_ranges$mz_max[i])
      mz_ranges$n_precursors_covered[i] <- covered
      mz_ranges$coverage_ratio[i] <- covered / length(mz_values)
    }
  }
  mz_ranges
}
