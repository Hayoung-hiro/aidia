# test_savgol_direct.R - Direct test of prospectr::savitzkyGolay

library(prospectr)

y <- runif(20, 400, 1000)

cat("Input vector:\n")
cat("  Length:", length(y), "\n")
cat("  Class:", class(y), "\n")

# Convert to matrix
y_matrix <- matrix(y, nrow = 1)

cat("\nInput matrix:\n")
cat("  Dimensions:", dim(y_matrix), "\n")
cat("  Class:", class(y_matrix), "\n")

# Apply smoothing
smoothed_matrix <- prospectr::savitzkyGolay(
  X = y_matrix,
  m = 0,
  p = 3,
  w = 7
)

cat("\nOutput matrix:\n")
cat("  Dimensions:", dim(smoothed_matrix), "\n")
cat("  Class:", class(smoothed_matrix), "\n")

# Convert to vector
smoothed_vector <- as.vector(smoothed_matrix)

cat("\nOutput vector:\n")
cat("  Length:", length(smoothed_vector), "\n")
cat("  Class:", class(smoothed_vector), "\n")
cat("  NA count:", sum(is.na(smoothed_vector)), "\n")

cat("\nFirst 5:\n")
print(smoothed_vector[1:min(5, length(smoothed_vector))])

cat("\nLast 5:\n")
last_idx <- length(smoothed_vector)
print(smoothed_vector[max(1, last_idx - 4):last_idx])
