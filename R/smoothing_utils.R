# smoothing_utils.R - Simplified Smoothing Utilities for DIA Window Optimization
#
# Purpose: Provide essential smoothing functions extracted from dynamicDIA.R
#
# Dependencies: prospectr package only

# prospectr availability is checked at runtime inside smooth_savgol()

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
#' @export
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

  # Use prospectr Savitzky-Golay filter
  tryCatch({
    # Convert to matrix for prospectr (expects matrix input)
    y_matrix <- matrix(y_array, nrow = 1)

    # Apply Savitzky-Golay filter using prospectr
    # NOTE: prospectr returns shorter vector (removes boundary points)
    smoothed_matrix <- prospectr::savitzkyGolay(
      X = y_matrix,
      m = 0,              # 0th derivative (smoothing)
      p = poly_order,     # polynomial order
      w = window_size     # window size
    )

    # Convert back to vector
    smoothed <- as.vector(smoothed_matrix)

    # Handle boundary truncation by prospectr
    # Following dynamicDIA.py approach: keep original values at boundaries
    # prospectr removes (window_size - 1) / 2 points from each end
    if (length(smoothed) < original_length) {
      half_window <- (window_size - 1) / 2

      # Create result vector
      result <- numeric(original_length)

      # Keep original values at boundaries (dynamicDIA method)
      # This is scientifically correct: boundaries lack sufficient neighboring points
      # for reliable smoothing, so we preserve the actual measured values
      result[1:half_window] <- y_array[1:half_window]
      result[(original_length - half_window + 1):original_length] <-
        y_array[(original_length - half_window + 1):original_length]

      # Fill middle section with smoothed values
      result[(half_window + 1):(original_length - half_window)] <- smoothed

      return(result)
    }

    return(smoothed)
  }, error = function(e) {
    # If prospectr fails, use moving average fallback
    warning(sprintf("Savitzky-Golay failed: %s. Using moving average.", e$message))
    return(smooth_moving_average(y_array, window_size))
  })
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
#' @export
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

if (!isNamespaceLoaded("aidia")) {
  cat("OK Smoothing utilities loaded\n")
  cat("   Main function: smooth_savgol(), smooth_mz_boundaries()\n")
  if (exists("PROSPECTR_AVAILABLE") && PROSPECTR_AVAILABLE) {
    cat("   Mode: Savitzky-Golay (prospectr)\n")
  } else {
    cat("   Mode: Moving average (fallback - prospectr not available)\n")
  }
}
