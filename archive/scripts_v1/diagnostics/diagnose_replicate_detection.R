# diagnose_replicate_detection.R - Diagnostic Script for Replicate Detection
# DIA Window Optimizer v2.0
#
# Purpose: Test replicate detection mechanism and analyze DIA-NN output structure

library(dplyr)
library(arrow)

# Source required functions
source("R/stage1_data_validation.R")
source("R/replicate_utils.R")

# ============================================================================
# Diagnostic Function: Analyze DIA-NN Report Structure
# ============================================================================

#' Diagnose Replicate Structure in DIA-NN Report
#'
#' Analyzes a DIA-NN report file to determine replicate structure
#'
#' @param file_path Path to DIA-NN report file (.parquet, .tsv, .csv)
#' @return List with diagnostic information
#' @export
diagnose_replicate_structure <- function(file_path) {
  cat("\n╔═══════════════════════════════════════════════════════╗\n")
  cat("║   Replicate Detection Diagnostic Report             ║\n")
  cat("╚═══════════════════════════════════════════════════════╝\n\n")

  # Load data
  cat("Step 1: Loading data...\n")
  if (grepl("\\.parquet$", file_path, ignore.case = TRUE)) {
    data <- arrow::read_parquet(file_path)
  } else if (grepl("\\.tsv$", file_path, ignore.case = TRUE)) {
    data <- read.delim(file_path, stringsAsFactors = FALSE)
  } else if (grepl("\\.csv$", file_path, ignore.case = TRUE)) {
    data <- read.csv(file_path, stringsAsFactors = FALSE)
  } else {
    stop("Unsupported file format. Use .parquet, .tsv, or .csv")
  }

  cat(sprintf("✓ Loaded %d rows, %d columns\n\n", nrow(data), ncol(data)))

  # Step 2: Check for Run column
  cat("Step 2: Checking for Run column...\n")
  has_run <- "Run" %in% colnames(data)

  if (!has_run) {
    cat("❌ No 'Run' column found\n")
    cat("   Available columns:\n")
    print(colnames(data))
    cat("\n")

    # Check for alternative run columns
    cat("   Checking for alternative run identifiers...\n")
    run_like_cols <- grep("run|file|sample", colnames(data),
                          ignore.case = TRUE, value = TRUE)
    if (length(run_like_cols) > 0) {
      cat("   Possible run columns found:\n")
      for (col in run_like_cols) {
        cat(sprintf("     - %s (n_unique = %d)\n",
                    col, length(unique(data[[col]]))))
      }
    } else {
      cat("   ⚠ No run-like columns found\n")
    }
    cat("\n")

    return(list(
      has_run_column = FALSE,
      n_runs = 1,
      replicate_type = "single_run",
      diagnostic = "No Run column - treating as single run",
      alternative_columns = run_like_cols
    ))
  }

  # Step 3: Analyze Run column
  cat("✓ 'Run' column found\n\n")
  cat("Step 3: Analyzing Run structure...\n")

  unique_runs <- unique(data$Run)
  n_runs <- length(unique_runs)

  cat(sprintf("✓ Detected %d unique run(s)\n\n", n_runs))

  if (n_runs == 1) {
    cat("  Replicate Type: Single Run\n")
    cat(sprintf("  Run Name: %s\n", unique_runs[1]))
    cat(sprintf("  Precursors: %d\n\n", nrow(data))

    return(list(
      has_run_column = TRUE,
      n_runs = 1,
      replicate_type = "single_run",
      run_names = unique_runs,
      diagnostic = "Single run detected - no replication"
    ))
  }

  # Multiple runs detected
  cat("  Replicate Type: Technical Replicates\n\n")

  # Step 4: Analyze replicate distribution
  cat("Step 4: Analyzing replicate distribution...\n")

  run_counts <- data %>%
    group_by(Run) %>%
    summarize(n_precursors = n(), .groups = "drop")

  cat("  Precursors per run:\n")
  for (i in 1:nrow(run_counts)) {
    cat(sprintf("    %s: %d precursors\n",
                run_counts$Run[i], run_counts$n_precursors[i]))
  }
  cat("\n")

  # Step 5: Check for Precursor.Id column
  cat("Step 5: Checking for Precursor.Id...\n")
  has_precursor_id <- "Precursor.Id" %in% colnames(data)

  if (!has_precursor_id) {
    cat("⚠ No 'Precursor.Id' column found\n")
    cat("  Consensus calculation requires Precursor.Id\n\n")

    return(list(
      has_run_column = TRUE,
      n_runs = n_runs,
      replicate_type = "technical_replicates",
      run_names = unique_runs,
      run_counts = run_counts,
      diagnostic = "Multiple runs but no Precursor.Id for consensus",
      warning = "Cannot create consensus without Precursor.Id"
    ))
  }

  cat("✓ 'Precursor.Id' column found\n\n")

  # Step 6: Analyze precursor overlap
  cat("Step 6: Analyzing precursor overlap across runs...\n")

  rep_info <- identify_replicate_groups(data)

  cat(sprintf("  Total unique precursors: %d\n", rep_info$n_precursors_unique))
  cat(sprintf("  Singletons (1 run): %d (%.1f%%)\n",
              rep_info$n_singleton,
              100 * rep_info$n_singleton / rep_info$n_precursors_unique))
  cat(sprintf("  Replicated (≥2 runs): %d (%.1f%%)\n",
              rep_info$n_replicated,
              100 * rep_info$n_replicated / rep_info$n_precursors_unique))
  cat("\n")

  cat("  Replicate distribution:\n")
  rep_dist <- as.data.frame(rep_info$replicate_distribution)
  colnames(rep_dist) <- c("n_runs", "n_precursors")
  for (i in 1:nrow(rep_dist)) {
    cat(sprintf("    %d runs: %d precursors (%.1f%%)\n",
                as.integer(as.character(rep_dist$n_runs[i])),
                rep_dist$n_precursors[i],
                100 * rep_dist$n_precursors[i] / rep_info$n_precursors_unique))
  }
  cat("\n")

  # Step 7: Estimate consensus impact
  cat("Step 7: Estimating consensus impact...\n")

  if (rep_info$n_replicated > 0) {
    # Sample CV calculation on a subset
    sample_data <- data %>%
      group_by(Precursor.Id) %>%
      filter(n() >= 2) %>%
      slice_head(n = min(100, n())) %>%
      ungroup()

    if (nrow(sample_data) > 0 && "FWHM" %in% colnames(sample_data)) {
      sample_cv <- sample_data %>%
        group_by(Precursor.Id) %>%
        summarize(
          n = n(),
          fwhm_cv = if (n() >= 2) geometric_cv(FWHM) else NA_real_,
          .groups = "drop"
        ) %>%
        filter(!is.na(fwhm_cv))

      if (nrow(sample_cv) > 0) {
        cat(sprintf("  Sample CV statistics (n=%d precursors with ≥2 runs):\n",
                    nrow(sample_cv)))
        cat(sprintf("    Mean FWHM CV: %.1f%%\n", mean(sample_cv$fwhm_cv, na.rm = TRUE)))
        cat(sprintf("    Median FWHM CV: %.1f%%\n", median(sample_cv$fwhm_cv, na.rm = TRUE)))

        # Estimate filtering
        n_filtered_20 <- sum(sample_cv$fwhm_cv > 20, na.rm = TRUE)
        n_filtered_10 <- sum(sample_cv$fwhm_cv > 10, na.rm = TRUE)

        cat(sprintf("    Would filter at CV>20%%: %d (%.1f%%)\n",
                    n_filtered_20,
                    100 * n_filtered_20 / nrow(sample_cv)))
        cat(sprintf("    Would filter at CV>10%%: %d (%.1f%%)\n",
                    n_filtered_10,
                    100 * n_filtered_10 / nrow(sample_cv)))
      }
    }
  }
  cat("\n")

  # Step 8: Recommendation
  cat("Step 8: Recommendation\n")

  if (n_runs > 1 && rep_info$n_replicated > 0) {
    cat("  ✅ Technical replicates detected\n")
    cat("  ✅ Consensus creation recommended\n")
    cat(sprintf("  ✅ Expected output: ~%d unique precursors\n",
                rep_info$n_precursors_unique))
    cat("\n")
    cat("  Suggested parameters:\n")
    cat("    enable_replicate_consensus = TRUE\n")
    cat("    min_replicates = 1  # Include singletons\n")
    cat("    max_cv_percent = 20  # Standard threshold\n")
  } else {
    cat("  ℹ Single run or no replicated precursors\n")
    cat("  ℹ Consensus creation not needed\n")
  }

  cat("\n")

  # Return diagnostic summary
  list(
    has_run_column = TRUE,
    n_runs = n_runs,
    replicate_type = if (n_runs > 1) "technical_replicates" else "single_run",
    run_names = unique_runs,
    run_counts = run_counts,
    replicate_info = rep_info,
    diagnostic = if (n_runs > 1) "Multiple runs with replication detected" else "Single run",
    recommendation = if (n_runs > 1 && rep_info$n_replicated > 0) {
      "Enable replicate consensus"
    } else {
      "No consensus needed"
    }
  )
}

# ============================================================================
# Usage Example
# ============================================================================

if (interactive()) {
  cat("\nUsage:\n")
  cat("  result <- diagnose_replicate_structure('data/report.parquet')\n")
  cat("  print(result)\n\n")
}
