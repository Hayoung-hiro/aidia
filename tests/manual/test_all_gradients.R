# test_all_gradients.R
# Quick pipeline test for 30min, 60min, 90min gradients

suppressPackageStartupMessages({
  library(dplyr)
  source("R/utils_common.R")
  source("R/stage1_data_validation.R")
  source("R/stage2_optimization_planning.R")
  source("R/stage3_window_optimization.R")
  source("R/stage4_visualization.R")
})

datasets <- c("30min", "60min", "90min")
results <- list()

cat("\n╔═══════════════════════════════════════════════╗\n")
cat("║  Multi-Gradient Pipeline Test (30/60/90min) ║\n")
cat("╚═══════════════════════════════════════════════╝\n\n")

for (name in datasets) {
  cat(sprintf("─── Testing %s gradient ───\n", name))
  
  file <- sprintf("data/%s_report.parquet", name)
  output_dir <- sprintf("output/pipeline_test/%s", name)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  tryCatch({
    # Stage 1-3 (suppress output)
    sink(nullfile())
    validated <- create_validated_dataset(file)
    plan <- plan_optimization(validated, current_cycle_time = 3.5, 
                              instrument_preset = "astral", 
                              target_dppp = 7.0)
    windows <- optimize_windows(validated, plan, rt_bin_width_min = 5, 
                                 mz_strategy = "smoothing", 
                                 window_mode = "variable")
    
    # Stage 4
    viz <- generate_visualizations(
      validated, plan, windows, 
      output_dir = output_dir,
      create_individual_plots = FALSE
    )
    sink()
    
    results[[name]] <- list(
      precursors = nrow(validated$data),
      windows = nrow(windows$windows),
      coverage = windows$statistics$coverage_percentage,
      plots = length(viz$plots),
      rt_range = diff(validated$metadata$rt_range)
    )
    
    cat(sprintf("✅ %5d precursors → %3d windows (%.1f%% coverage, %.0fmin RT)\n",
                results[[name]]$precursors,
                results[[name]]$windows,
                results[[name]]$coverage,
                results[[name]]$rt_range))
    
  }, error = function(e) {
    sink()
    cat(sprintf("❌ FAILED: %s\n", e$message))
    results[[name]] <- NULL
  })
}

cat("\n╔═══════════════════════════════════════════════╗\n")
cat("║  Summary                                     ║\n")
cat("╚═══════════════════════════════════════════════╝\n\n")

for (name in datasets) {
  if (!is.null(results[[name]])) {
    cat(sprintf("  %s: ✅ PASS (%d plots, %.1f%% coverage)\n", 
                name, 
                results[[name]]$plots,
                results[[name]]$coverage))
  } else {
    cat(sprintf("  %s: ❌ FAIL\n", name))
  }
}

cat("\n")
passed <- sum(!sapply(results, is.null))
cat(sprintf("✅ Pipeline test: %d / %d datasets passed\n\n", passed, length(datasets)))

if (passed == length(datasets)) {
  cat("🎉 All gradient lengths passed!\n")
  cat("   Output: output/pipeline_test/{30min,60min,90min}/\n\n")
}
