# Reproducible diagnostic of the CURRENT adaptive RT splitter, not a new algorithm.
# Run from the repository root: Rscript docs/reviews/rt-partition-probe.R
# Synthetic observations are independent; no claims about real-data error rates.
devtools::load_all(".")
results <- list()
for (scenario in c("stationary", "smooth_drift", "single_jump")) {
  for (replicate in seq_len(50)) {
    set.seed(20260908 + replicate)
    rt <- seq(0.001, 29.999, length.out = 4000)
    center <- switch(scenario,
      stationary = rep(600, length(rt)),
      smooth_drift = 480 + 8 * rt,
      single_jump = ifelse(rt < 15, 550, 670)
    )
    precursors <- data.frame(RT.Apex = rt,
                             Precursor.Mz = rnorm(length(rt), center, 40))
    # Use the production implementation, including its width constraints,
    # sparse-bin merging and fallback. No clipping of synthetic m/z values.
    output <- suppressWarnings(perform_adaptive_rt_binning_internal(precursors))
    p <- output$adaptive_info$p_values
    results[[length(results) + 1L]] <- data.frame(
      scenario, replicate,
      raw_candidates = sum(p < 0.05),
      holm_candidates = sum(p.adjust(p, method = "holm") < 0.05),
      final_bins = output$n_bins,
      fallback = isTRUE(output$adaptive_info$fallback),
      raw_midpoint_detected = p[50] < 0.05
    )
  }
}
results <- do.call(rbind, results)
path <- "docs/reviews/2026-09-08-rt-partition-probe.csv"
write.csv(results, path, row.names = FALSE)
summary <- do.call(rbind, lapply(split(results, results$scenario), function(x) {
  data.frame(scenario = x$scenario[1], repeats = nrow(x),
    mean_raw_candidates = mean(x$raw_candidates),
    any_raw_candidate_fraction = mean(x$raw_candidates > 0),
    any_holm_candidate_fraction = mean(x$holm_candidates > 0),
    median_final_bins = median(x$final_bins),
    min_final_bins = min(x$final_bins), max_final_bins = max(x$final_bins),
    fallback_fraction = mean(x$fallback),
    midpoint_detection_fraction = mean(x$raw_midpoint_detected))
}))
print(summary, row.names = FALSE)
cat("Saved diagnostic runs to:", path, "\n")
