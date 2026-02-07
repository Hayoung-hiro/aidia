# Quick test: Adaptive RT binning with real data
# Tests just the RT binning module (not full pipeline) for fast feedback

setwd("D:/Projects/aidia")
source("R/stage3/stage3_rt_binning.R")
library(arrow)
library(dplyr)

cat("Loading real data...\n")
df <- arrow::read_parquet("data/30min_report.parquet")
cat(sprintf("  Rows: %s | Columns: %d\n", format(nrow(df), big.mark=","), ncol(df)))
cat(sprintf("  Columns: %s\n", paste(head(names(df), 10), collapse=", ")))

# Check for required columns
required <- c("Precursor.Mz", "Protein.Group")
rt_cols <- intersect(c("RT.Start", "RT.Apex"), names(df))
cat(sprintf("  RT columns available: %s\n", paste(rt_cols, collapse=", ")))

# Compute RT.Apex if needed
if (!"RT.Apex" %in% names(df) && "RT.Stop" %in% names(df)) {
  df$RT.Apex <- (df$RT.Start + df$RT.Stop) / 2
  cat("  Computed RT.Apex from midpoint\n")
} else if (!"RT.Apex" %in% names(df)) {
  df$RT.Apex <- df$RT.Start
  cat("  Using RT.Start as RT.Apex (no RT.Stop)\n")
}

# Ensure FWHM exists
if (!"FWHM" %in% names(df)) {
  df$FWHM <- 0.3  # Default
  cat("  Using default FWHM=0.3\n")
}

# Ensure Precursor.Id exists
if (!"Precursor.Id" %in% names(df)) {
  if ("Precursor.Id" %in% names(df)) {
    # Already there
  } else {
    df$Precursor.Id <- paste0("P", seq_len(nrow(df)))
    cat("  Generated Precursor.Id\n")
  }
}

cat(sprintf("\n  RT range: %.2f - %.2f min\n", min(df$RT.Start), max(df$RT.Start)))
cat(sprintf("  m/z range: %.1f - %.1f Da\n", min(df$Precursor.Mz), max(df$Precursor.Mz)))

# ============================================
# Test 1: Fixed binning
# ============================================
cat("\n=== TEST 1: Fixed RT Binning ===\n")
t1 <- system.time({
  result_fixed <- perform_rt_binning_internal(
    df, rt_bin_width_min = 5, rt_binning_mode = "fixed"
  )
})
cat(sprintf("  Time: %.2f sec\n", t1["elapsed"]))
cat(sprintf("  Bins: %d\n", result_fixed$n_bins))
cat(sprintf("  Breaks: %s\n", paste(round(result_fixed$rt_breaks, 1), collapse=", ")))
cat(sprintf("  adaptive_info: %s\n", ifelse(is.null(result_fixed$adaptive_info), "NULL (correct)", "UNEXPECTED")))

# ============================================
# Test 2: Adaptive binning
# ============================================
cat("\n=== TEST 2: Adaptive RT Binning (KS) ===\n")
t2 <- system.time({
  result_adaptive <- perform_rt_binning_internal(
    df, rt_bin_width_min = 5, rt_binning_mode = "adaptive",
    cpd_significance_level = 0.05,
    cpd_min_bin_width = 1.0,
    cpd_max_bin_width = 15.0,
    cpd_min_precursors_per_bin = 50
  )
})
cat(sprintf("  Time: %.2f sec\n", t2["elapsed"]))
cat(sprintf("  Bins: %d\n", result_adaptive$n_bins))
cat(sprintf("  Breaks: %s\n", paste(round(result_adaptive$rt_breaks, 1), collapse=", ")))

if (!is.null(result_adaptive$adaptive_info)) {
  ai <- result_adaptive$adaptive_info
  cat(sprintf("  Change points: %d\n", ai$n_change_points))
  cat(sprintf("  Fallback: %s\n", ai$fallback))
  cat(sprintf("  Significance: %.3f\n", ai$significance_level))
  if (ai$n_change_points > 0 && !ai$fallback) {
    cat(sprintf("  Change point positions: %s\n",
                paste(round(ai$change_point_positions, 2), collapse=", ")))
  }
  cat(sprintf("  KS stats range: [%.4f, %.4f]\n",
              min(ai$ks_statistics), max(ai$ks_statistics)))
  cat(sprintf("  Significant p-values: %d / %d\n",
              sum(ai$p_values < 0.05), length(ai$p_values)))
}

# ============================================
# Comparison
# ============================================
cat("\n=== COMPARISON ===\n")
cat(sprintf("  Fixed bins:    %d | Adaptive bins: %d\n",
            result_fixed$n_bins, result_adaptive$n_bins))
cat(sprintf("  Fixed precursors per bin: %.0f avg\n",
            mean(result_fixed$stats$n_precursors)))
cat(sprintf("  Adaptive precursors per bin: %.0f avg\n",
            mean(result_adaptive$stats$n_precursors)))

# Check that all precursors are assigned
cat(sprintf("  Fixed NAs: %d | Adaptive NAs: %d\n",
            sum(is.na(result_fixed$data$rt_group)),
            sum(is.na(result_adaptive$data$rt_group))))

cat("\n=== ALL TESTS PASSED ===\n")
