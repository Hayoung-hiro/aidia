# test_smooth_na.R - Check if smooth_savgol produces NA

source("R/smoothing_utils.R")

# Test data
y <- runif(20, 400, 1000)

cat("Input:\n")
cat("  Length:", length(y), "\n")
cat("  Range:", min(y), "-", max(y), "\n")
cat("  Has NA:", any(is.na(y)), "\n")

# Smooth
smoothed <- smooth_savgol(y, window_size = 7, poly_order = 3)

cat("\nOutput:\n")
cat("  Length:", length(smoothed), "\n")
cat("  Range:", min(smoothed, na.rm = TRUE), "-", max(smoothed, na.rm = TRUE), "\n")
cat("  Has NA:", any(is.na(smoothed)), "\n")
cat("  NA count:", sum(is.na(smoothed)), "\n")

if (any(is.na(smoothed))) {
  na_indices <- which(is.na(smoothed))
  cat("  NA indices:", na_indices, "\n")
}

cat("\nFirst 5 values:\n")
print(smoothed[1:5])

cat("\nLast 5 values:\n")
print(smoothed[16:20])
