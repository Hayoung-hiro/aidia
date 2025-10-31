# test_dppp_score_correlation.R
# Test DPPP-score correlation analysis with real data

# Load required libraries
library(arrow)
library(dplyr)

# Source modules
source("R/dppp_analyzer_enhanced.R")
source("R/dppp_score_analysis.R")

cat("==============================================\n")
cat("   DPPP-Score Correlation Analysis Test\n")
cat("==============================================\n")

# ============================================================================
# Test 1: Load Real Data
# ============================================================================

cat("\n[1] Loading real DIA-NN data...\n")
data <- read_parquet("rawfile/report.parquet")

cat(sprintf("✓ Loaded %d precursors\n", nrow(data)))
cat(sprintf("  Columns: %s\n", paste(head(names(data), 10), collapse = ", ")))

# Check for score columns
score_columns <- grep("Score|score", names(data), value = TRUE)
cat(sprintf("\n  Available score columns: %s\n", paste(score_columns, collapse = ", ")))

# Select primary score column
if ("CScore" %in% names(data)) {
  primary_score <- "CScore"
} else if ("Global.Q.Value" %in% names(data)) {
  primary_score <- "Global.Q.Value"
  cat("  Note: Using Q-value (lower = better)\n")
} else if (length(score_columns) > 0) {
  primary_score <- score_columns[1]
} else {
  stop("No score column found in data")
}

cat(sprintf("  Using score column: %s\n", primary_score))

# ============================================================================
# Test 2: DPPP Analysis (for context)
# ============================================================================

cat("\n[2] Running DPPP distribution analysis...\n")
dppp_analysis <- analyze_dppp_distribution(
  data,
  scan_time = 2.0,
  target_dppp = 1.25,
  dppp_tolerance = 0.1
)

# ============================================================================
# Test 3: DPPP-Score Correlation Analysis
# ============================================================================

cat("\n[3] Analyzing DPPP-Score correlation...\n")
correlation_result <- analyze_dppp_score_correlation(
  data,
  scan_time = 2.0,
  score_column = primary_score,
  stratify_by_density = TRUE
)

# ============================================================================
# Test 4: Generate Visualizations
# ============================================================================

cat("\n[4] Creating visualizations...\n")

# Create output directory
if (!dir.exists("test_output")) {
  dir.create("test_output", recursive = TRUE)
}

# Fixed heatmap test
cat("\n  Testing fixed DPPP heatmap...\n")
p_heatmap <- plot_dppp_heatmap_2d(dppp_analysis)
ggsave(
  "test_output/dppp_heatmap_fixed.png",
  p_heatmap,
  width = 10,
  height = 8,
  dpi = 300
)
cat("  ✓ Saved: test_output/dppp_heatmap_fixed.png\n")

# DPPP-score plots
cat("\n  Creating DPPP-score correlation plots...\n")
plots <- create_dppp_score_report(
  correlation_result,
  output_file = "test_output/dppp_score_correlation_report.pdf"
)

# Save individual plots
ggsave(
  "test_output/dppp_score_scatter.png",
  plots$scatter,
  width = 10,
  height = 8,
  dpi = 300
)

ggsave(
  "test_output/score_by_dppp_level.png",
  plots$by_level,
  width = 10,
  height = 8,
  dpi = 300
)

if (!is.null(plots$heatmap)) {
  ggsave(
    "test_output/dppp_score_heatmap.png",
    plots$heatmap,
    width = 10,
    height = 8,
    dpi = 300
  )
}

if (!is.null(plots$stratified)) {
  ggsave(
    "test_output/density_stratified_correlation.png",
    plots$stratified,
    width = 10,
    height = 8,
    dpi = 300
  )
}

cat("\n  ✓ All plots saved to test_output/\n")

# ============================================================================
# Test 5: Summary Report
# ============================================================================

cat("\n==============================================\n")
cat("           ANALYSIS SUMMARY\n")
cat("==============================================\n")

cat("\n--- DPPP Distribution ---\n")
cat(sprintf("Mean DPPP: %.2f\n", dppp_analysis$stats$mean))
cat(sprintf("Median DPPP: %.2f\n", dppp_analysis$stats$median))
cat(sprintf("Target satisfaction: %.1f%%\n",
            dppp_analysis$satisfaction$satisfaction_ratio * 100))

cat("\n--- DPPP-Score Correlation ---\n")
cat(sprintf("Pearson correlation: %.3f\n", correlation_result$correlation$pearson))
cat(sprintf("Spearman correlation: %.3f\n", correlation_result$correlation$spearman))
cat(sprintf("Hypothesis (High DPPP → Low Score): %s\n",
            ifelse(correlation_result$correlation$hypothesis_supported,
                   "SUPPORTED ✓", "NOT SUPPORTED ✗")))

cat("\n--- Score by DPPP Level ---\n")
print(correlation_result$score_by_dppp_level)

if (!is.null(correlation_result$density_stratified)) {
  cat("\n--- Density-Stratified Analysis ---\n")
  cat(sprintf("High-density regions: r = %.3f\n",
              correlation_result$density_stratified$correlation_high_density))
  cat(sprintf("Low-density regions: r = %.3f\n",
              correlation_result$density_stratified$correlation_low_density))

  if (correlation_result$density_stratified$correlation_high_density <
      correlation_result$density_stratified$correlation_low_density - 0.1) {
    cat("✓ Co-isolation effect is density-dependent\n")
  } else {
    cat("○ No clear density-dependent effect\n")
  }
}

cat("\n==============================================\n")
cat("           TEST COMPLETED\n")
cat("==============================================\n")
cat("\nGenerated files:\n")
cat("  - test_output/dppp_heatmap_fixed.png (fixed heatmap)\n")
cat("  - test_output/dppp_score_scatter.png\n")
cat("  - test_output/score_by_dppp_level.png\n")
cat("  - test_output/dppp_score_heatmap.png\n")
cat("  - test_output/density_stratified_correlation.png\n")
cat("  - test_output/dppp_score_correlation_report.pdf\n")
cat("\n")
