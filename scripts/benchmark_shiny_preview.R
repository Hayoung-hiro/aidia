# Feasibility probe, not a real-data or end-to-end Shiny benchmark.
# Run from the repository root: Rscript --vanilla scripts/benchmark_shiny_preview.R
devtools::load_all(".", quiet = TRUE)
set.seed(20260908)
cat("Source:", normalizePath("."), "\n")
cat("R:", as.character(getRversion()), "\n")
quiet_run <- function(expr) {
  invisible(capture.output(value <- suppressMessages(expr)))
  value
}
# Minimal typed plan, following test-strategy-comparison.R. Stage 2 is excluded.
preview_plan <- structure(list(
  window_count_per_bin = 40L,
  instrument = list(preset = "test", cycle_mode = "sequential",
                    ms1_time_sec = 0.5, ms2_time_sec = 0.05),
  scan_time = list(t_scan_ms = 50), required_cycle_time_sec = 2.5
), class = c("OptimizationPlan", "list"))
settings <- data.frame(threshold = c(0.1, 0.2, 0.1), coverage = c(0.8, 0.8, 0.9))
rows <- list()
for (n in c(10000L, 100000L)) {
  x <- tibble::tibble(
    Precursor.Mz = 400 + 700 * rbeta(n, 2, 4),
    RT.Apex = runif(n, 0, 60), FWHM = rep(4, n)
  )
  vd <- structure(list(data = x), class = c("ValidatedData", "list"))
  for (i in seq_len(nrow(settings))) {
    times <- numeric(3)
    for (trial in seq_along(times)) {
      times[trial] <- system.time({
        result <- quiet_run(optimize_windows(
          validated_data = vd, optimization_plan = preview_plan,
          strategy_config = kde_config(settings$threshold[i], settings$coverage[i]),
          n_windows_override = 40L, window_mode = "density",
          rt_bin_width_min = 5, rt_binning_mode = "fixed",
          min_width_da = 2, max_width_da = 80, fz_offset = 0.25
        ))
      })[["elapsed"]]
    }
    rows[[length(rows) + 1L]] <- data.frame(
      observations = n, threshold = settings$threshold[i],
      min_coverage = settings$coverage[i],
      seconds_min = min(times), seconds_median = median(times),
      seconds_max = max(times), window_rows = nrow(result$windows),
      unique_coverage_pct = result$statistics$coverage_percentage
    )
    print(rows[[length(rows)]], row.names = FALSE)
  }
}
cat("\nCSV results (3 consecutive trials per configuration; no application cache):\n")
write.csv(do.call(rbind, rows), stdout(), row.names = FALSE)
cat("\nExcludes upload, validation, Stage 2, plots, PDF/comparison, worker transfer and browser rendering.\n")
