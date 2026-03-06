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

