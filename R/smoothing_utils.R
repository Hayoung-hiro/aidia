# smoothing_utils.R - Simplified Smoothing Utilities for DIA Window Optimization
#
# Purpose: Provide essential smoothing functions extracted from dynamicDIA.R
#
# Dependencies: prospectr package only

library(prospectr)

# =============================================================================
# Core Smoothing Function (Savitzky-Golay only)
# =============================================================================

#' Savitzky-Golay smoothing using prospectr package
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

cat("✅ Smoothing utilities loaded\n")
cat("   Main function: smooth_savgol(), smooth_mz_boundaries()\n")
cat("   Dependencies: prospectr\n")
