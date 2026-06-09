# test_all_gradients.R
# Multi-strategy pipeline test for 30min, 60min, 90min gradients
# Tests all 4 strategies: quantile, coverage, outlier, smoothing

suppressPackageStartupMessages({
  library(dplyr)
  source("R/utils_common.R")
  source("R/data_validation.R")
  source("R/optimization_planning.R")
  source("R/window_optimization.R")
  source("R/visualization.R")
})

datasets <- c("30min", "60min", "90min")
strategies <- c("quantile", "coverage", "outlier", "smoothing")
results <- list()

cat("\n╔═══════════════════════════════════════════════════════════╗\n")
cat("║  Multi-Strategy Pipeline Test (4 strategies × 3 gradients) ║\n")
cat("╚═══════════════════════════════════════════════════════════╝\n\n")

for (name in datasets) {
  cat(sprintf("─── Testing %s gradient (4 strategies) ───\n", name))

  file <- sprintf("data/%s_report.parquet", name)
  output_dir <- sprintf("output/pipeline_test/%s", name)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  tryCatch({
    # Stage 1-2 (suppress output)
    sink(nullfile())
    validated <- create_validated_dataset(file)
    plan <- plan_optimization(validated, current_cycle_time = 3.5,
                              instrument_preset = "astral",
                              target_dppp = 7.0)
    sink()

    # Stage 3: Generate windows for all 4 strategies
    cat("  Strategies: ")
    windows_list <- list()
    for (strategy in strategies) {
      sink(nullfile())
      windows_list[[strategy]] <- optimize_windows(
        validated, plan,
        rt_bin_width_min = 5,
        mz_strategy = strategy,
        window_mode = "density"
      )
      sink()
      cat(sprintf("%s(%d) ", strategy, nrow(windows_list[[strategy]]$windows)))
    }
    cat("\n")

    # Stage 3B: Export method files for all 4 strategies (NEW)
    cat("  Method files: ")
    sink(nullfile())
    method_files <- export_method_files(
      windows_list = windows_list,
      output_dir = output_dir,
      validated_data = validated,
      strategies = c("quantile", "coverage", "outlier", "smoothing"),  # All 4 strategies
      instrument_type = plan$instrument$preset
    )
    sink()
    cat(sprintf("%d exported\n", length(method_files)))

    # Stage 4: Visualization (plots only)
    sink(nullfile())
    viz <- generate_visualizations(
      validated, plan,
      optimized_windows = windows_list[["smoothing"]],  # Primary strategy for single-strategy plots
      windows_list = windows_list,  # All 4 strategies for comparison plots
      output_dir = output_dir,
      create_individual_plots = TRUE  # Generate individual PNG files
    )
    sink()

    results[[name]] <- list(
      precursors = nrow(validated$data),
      strategies = lapply(windows_list, function(w) list(
        windows = nrow(w$windows),
        coverage = w$statistics$coverage_percentage
      )),
      plots = length(viz$plots),
      method_files = length(method_files),
      rt_range = diff(validated$metadata$rt_range)
    )

    cat(sprintf("  ✅ %5d precursors, %d plots + %d method files\n",
                results[[name]]$precursors,
                results[[name]]$plots,
                results[[name]]$method_files))
    
  }, error = function(e) {
    sink()
    cat(sprintf("❌ FAILED: %s\n", e$message))
    results[[name]] <- NULL
  })
}

cat("\n╔═══════════════════════════════════════════════════════════╗\n")
cat("║  Summary                                                 ║\n")
cat("╚═══════════════════════════════════════════════════════════╝\n\n")

for (name in datasets) {
  if (!is.null(results[[name]])) {
    cat(sprintf("  %s: ✅ PASS (%d plots)\n", name, results[[name]]$plots))
    for (strategy in strategies) {
      s <- results[[name]]$strategies[[strategy]]
      cat(sprintf("    - %s: %3d windows (%.1f%% coverage)\n",
                  strategy, s$windows, s$coverage))
    }
  } else {
    cat(sprintf("  %s: ❌ FAIL\n", name))
  }
}

cat("\n")
passed <- sum(!sapply(results, is.null))
cat(sprintf("✅ Pipeline test: %d / %d datasets passed\n\n", passed, length(datasets)))

if (passed == length(datasets)) {
  cat("🎉 All gradient lengths × all strategies passed!\n")
  cat("   Total combinations: 4 strategies × 3 gradients = 12 tests\n")
  cat("   Output: output/pipeline_test/{30min,60min,90min}/\n")
  cat("     - optimization_report.pdf (24 plots)\n")
  cat("     - method_{strategy}.csv × 4 (16 columns each)\n")
  cat("     - 24 × *.png files\n\n")
}
