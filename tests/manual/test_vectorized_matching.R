# Test: Vectorized vs Loop Precursor Counting
# Verify that the new vectorized implementation produces identical results

# Load functions
source("R/utils_common.R")

# Create test data
precursor_rt <- c(10.1, 10.5, 20.2, 20.8, 25.1)
precursor_mz <- c(400.5, 450.2, 500.8, 550.3, 600.5)

windows <- data.frame(
  rt_start = c(10, 20, 25),
  rt_end = c(15, 25, 30),
  mz_start = c(400, 500, 600),
  mz_end = c(500, 600, 700)
)

cat("\n==================================================\n")
cat("Test Data:\n")
cat("==================================================\n")
cat("Precursors:\n")
for (i in 1:length(precursor_rt)) {
  cat(sprintf("  %d: RT=%.1f, m/z=%.1f\n", i, precursor_rt[i], precursor_mz[i]))
}
cat("\nWindows:\n")
for (i in 1:nrow(windows)) {
  cat(sprintf("  %d: RT=[%.0f-%.0f], m/z=[%.0f-%.0f]\n",
              i, windows$rt_start[i], windows$rt_end[i],
              windows$mz_start[i], windows$mz_end[i]))
}

# Method 1: Loop-based (original implementation)
cat("\n==================================================\n")
cat("Method 1: Loop-based (original)\n")
cat("==================================================\n")

calc_loop <- function(windows, rt, mz) {
  sapply(1:nrow(windows), function(i) {
    w <- windows[i, ]
    sum(
      rt >= w$rt_start &
      rt <= w$rt_end &
      mz >= w$mz_start &
      mz <= w$mz_end,
      na.rm = TRUE
    )
  })
}

result_loop <- calc_loop(windows, precursor_rt, precursor_mz)
cat("Result:", result_loop, "\n")

# Show details
for (i in 1:nrow(windows)) {
  w <- windows[i, ]
  matches <- which(
    precursor_rt >= w$rt_start &
    precursor_rt <= w$rt_end &
    precursor_mz >= w$mz_start &
    precursor_mz <= w$mz_end
  )
  cat(sprintf("  Window %d: %d precursors", i, length(matches)))
  if (length(matches) > 0) {
    cat(sprintf(" (indices: %s)", paste(matches, collapse=", ")))
  }
  cat("\n")
}

# Method 2: Vectorized (new implementation)
cat("\n==================================================\n")
cat("Method 2: Vectorized (new)\n")
cat("==================================================\n")

result_vectorized <- count_precursors_in_2d_windows(
  precursor_rt = precursor_rt,
  precursor_mz = precursor_mz,
  window_rt_start = windows$rt_start,
  window_rt_end = windows$rt_end,
  window_mz_start = windows$mz_start,
  window_mz_end = windows$mz_end
)

cat("Result:", result_vectorized, "\n")

# Comparison
cat("\n==================================================\n")
cat("Comparison:\n")
cat("==================================================\n")
cat("Loop result:       ", result_loop, "\n")
cat("Vectorized result: ", result_vectorized, "\n")
cat("\n")
cat("Type of loop result:      ", class(result_loop), "\n")
cat("Type of vectorized result:", class(result_vectorized), "\n")
cat("\n")

# Convert to same type for comparison
result_loop_int <- as.integer(result_loop)
result_vectorized_int <- as.integer(result_vectorized)

cat("Identical (as integer): ", identical(result_loop_int, result_vectorized_int), "\n")
cat("All equal:              ", all(result_loop == result_vectorized), "\n")

if (all(result_loop == result_vectorized)) {
  cat("\n✅ SUCCESS: Both methods produce identical results!\n")
} else {
  cat("\n❌ FAILURE: Results differ!\n")
  cat("Differences:\n")
  for (i in 1:length(result_loop)) {
    if (result_loop[i] != result_vectorized[i]) {
      cat(sprintf("  Window %d: Loop=%d, Vectorized=%d\n",
                  i, result_loop[i], result_vectorized[i]))
    }
  }
}

cat("\n==================================================\n")
