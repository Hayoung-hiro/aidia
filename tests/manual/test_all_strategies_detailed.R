# Test all 4 strategies with detailed output for 30min data

suppressPackageStartupMessages({
  library(dplyr)
  source("R/utils_common.R")
  source("R/stage1_data_validation.R")
  source("R/stage2_optimization_planning.R")
  source("R/stage3_window_optimization.R")
  source("R/stage4_visualization.R")
})

cat("\n═══════════════════════════════════════════════════════════\n")
cat("  4-Strategy Detailed Test (30min data)\n")
cat("═══════════════════════════════════════════════════════════\n\n")

# Stage 1-2 (suppress output)
sink(nullfile())
validated <- create_validated_dataset("data/30min_report.parquet")
plan <- plan_optimization(validated, current_cycle_time = 3.5, 
                          instrument_preset = "astral", 
                          target_dppp = 7.0)
sink()

cat(sprintf("Dataset: 30min (%d precursors)\n\n", nrow(validated$data)))

strategies <- c("quantile", "coverage", "outlier", "smoothing")
windows_list <- list()

cat("─── Testing 4 Strategies ───\n\n")

for (strategy in strategies) {
  cat(sprintf("Strategy: %s\n", toupper(strategy)))
  
  sink(nullfile())
  windows <- optimize_windows(validated, plan, 
                              rt_bin_width_min = 5, 
                              mz_strategy = strategy, 
                              window_mode = "variable")
  sink()
  
  windows_list[[strategy]] <- windows
  
  cat(sprintf("  Windows:  %3d\n", nrow(windows$windows)))
  cat(sprintf("  Coverage: %.1f%%\n", windows$statistics$coverage_percentage))
  cat(sprintf("  Mean m/z: %.1f Da\n", windows$statistics$mean_mz_width))
  cat("\n")
}

cat("─── Multi-Strategy Visualization ───\n\n")

output_dir <- "output/test_4strategies"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

sink(nullfile())
viz <- generate_visualizations(
  validated, plan, 
  optimized_windows = windows_list[["quantile"]],
  windows_list = windows_list,  # All 4 strategies
  output_dir = output_dir,
  create_individual_plots = TRUE
)
sink()

cat(sprintf("Generated: %d plots\n\n", length(viz$plots)))

# Count plots by category
multi_strategy_plots <- grep("strategy|coverage_map|ridge|boxplot|cdf", 
                              names(viz$plots), value = TRUE)

cat(sprintf("  Total plots: %d\n", length(viz$plots)))
cat(sprintf("  Multi-strategy plots: %d\n", length(multi_strategy_plots)))
cat("\n")

cat("Plot breakdown:\n")
cat(sprintf("  Plot 1 (DPPP): %d\n", sum(grepl("plot1", names(viz$plots)))))
cat(sprintf("  Plot 2 (Heatmap): %d\n", sum(grepl("plot2", names(viz$plots)))))
cat(sprintf("  Plot 3 (Density): %d\n", sum(grepl("plot3", names(viz$plots)))))
cat(sprintf("  Plot 4 (m/z): %d\n", sum(grepl("plot4", names(viz$plots)))))
cat(sprintf("  Plot 5 (Coverage): %d\n", sum(grepl("plot5", names(viz$plots)))))
cat(sprintf("  Plot 6 (Satisfaction): %d\n", sum(grepl("plot6", names(viz$plots)))))
cat(sprintf("  Plot 7 (Width): %d\n", sum(grepl("plot7", names(viz$plots)))))
cat(sprintf("  Plot 8 (Strategy): %d\n", sum(grepl("plot8", names(viz$plots)))))
cat("\n")

cat("All plot names:\n")
for (i in seq_along(viz$plots)) {
  cat(sprintf("%2d. %s\n", i, names(viz$plots)[i]))
}

cat("\n═══════════════════════════════════════════════════════════\n")
cat(sprintf("✅ Test complete: %d plots generated\n", length(viz$plots)))
cat("═══════════════════════════════════════════════════════════\n\n")
