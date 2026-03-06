# test_whittaker.R - Manual test for Whittaker-Henderson smoother
# Run: source("tests/manual/test_whittaker.R")

devtools::load_all(quiet = TRUE)

cat("\n=== Test 1: Whittaker basic ===\n")
y <- c(400, 420, 415, 450, 440, 430, 460, 455, 470, 480)
result <- smooth_whittaker(y, lambda = 10)
cat("Input: ", y, "\n")
cat("Output:", round(result, 1), "\n")
cat("Smooth (no wild jumps):", max(abs(diff(result))) < max(abs(diff(y))), "\n")

cat("\n=== Test 2: Weighted (sparse bin #5) ===\n")
y_noisy <- c(400, 420, 430, 440, 500, 460, 470, 480, 490, 500)
#                                   ^^^ outlier at position 5
weights <- c(200, 300, 250, 280, 30, 270, 290, 310, 260, 240)
#                                ^^^ sparse bin: only 30 precursors

result_uniform <- smooth_whittaker(y_noisy, lambda = 10)
result_weighted <- smooth_whittaker(y_noisy, weights = weights, lambda = 10)

cat("Raw at pos 5:     ", y_noisy[5], "\n")
cat("Uniform weight:   ", round(result_uniform[5], 1), "\n")
cat("Weighted (low w5):", round(result_weighted[5], 1), "\n")
cat("WH pulls sparse bin more toward neighbors:",
    abs(result_weighted[5] - y_noisy[5]) > abs(result_uniform[5] - y_noisy[5]), "\n")

cat("\n=== Test 3: smooth_boundaries dispatcher ===\n")
sg_result <- smooth_boundaries(y, method = "sg", window_size = 5, poly_order = 2)
wh_result <- smooth_boundaries(y, method = "whittaker", lambda = 10)
cat("SG length:", length(sg_result), "WH length:", length(wh_result), "\n")
cat("Both same length as input:", length(sg_result) == 10 && length(wh_result) == 10, "\n")

cat("\n=== Test 4: Edge cases ===\n")
cat("n=2 passthrough:", identical(smooth_whittaker(c(1, 2)), c(1, 2)), "\n")
cat("n=1 passthrough:", identical(smooth_whittaker(c(1)), c(1)), "\n")
cat("NULL weights OK:", is.numeric(smooth_whittaker(y, weights = NULL, lambda = 5)), "\n")

cat("\n=== Test 5: Lambda sensitivity ===\n")
cat("lambda=1  (light):", round(smooth_whittaker(y_noisy, lambda = 1)[5], 1), "\n")
cat("lambda=10 (mid):  ", round(smooth_whittaker(y_noisy, lambda = 10)[5], 1), "\n")
cat("lambda=100 (heavy):", round(smooth_whittaker(y_noisy, lambda = 100)[5], 1), "\n")
cat("lambda=1000 (max): ", round(smooth_whittaker(y_noisy, lambda = 1000)[5], 1), "\n")

cat("\n=== Test 6: Strategy config integration ===\n")
cfg <- greedy_config(smoothing_method = "whittaker", whittaker_lambda = 20)
cat("Config method:", cfg$smoothing_method, "\n")
cat("Config lambda:", cfg$whittaker_lambda, "\n")

cfg_q <- quantile_config(apply_smoothing = TRUE, smoothing_method = "whittaker")
cat("Quantile config method:", cfg_q$smoothing_method, "\n")

cat("\nAll tests complete.\n")
