#' ============================================================================
#' Window Optimization Validation Script
#' ============================================================================
#'
#' Purpose: Validate the effectiveness of DIA window optimization by comparing
#'          DIA-NN results before and after applying optimized isolation windows.
#'
#' Usage:
#'   source("scripts/validation/validate_window_optimization.R")
#'
#'   # Option 1: Compare Before/After DIA-NN results
#'   comparison <- compare_dia_results(
#'     before_file = "path/to/before_report.parquet",
#'     after_file = "path/to/after_report.parquet"
#'   )
#'
#'   # Option 2: Calculate predictive metrics from optimized windows
#'   metrics <- calculate_window_quality_metrics(
#'     validated_data = validated_data,
#'     windows = optimized_windows
#'   )
#'
#'   # Option 3: Full validation report
#'   report <- generate_validation_report(
#'     before_file, after_file, optimized_windows, output_dir
#'   )
#'
#' Author: DIA Window Optimizer Project
#' Version: 1.0
#' Date: 2025-11-28
#' ============================================================================

# Required packages
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(arrow)      # For parquet files
  library(scales)
  library(patchwork)  # For combining plots
})

# =============================================================================
# SECTION 1: Before/After DIA-NN Result Comparison
# =============================================================================

#' Compare DIA-NN results before and after window optimization
#'
#' @param before_file Path to DIA-NN report BEFORE optimization
#' @param after_file Path to DIA-NN report AFTER optimization
#' @param q_value_threshold FDR threshold for filtering (default: 0.01)
#' @return List containing comparison metrics and summary
#'
#' @examples
#' comparison <- compare_dia_results(
#'   before_file = "results/standard_dia/report.parquet",
#'   after_file = "results/optimized_dia/report.parquet"
#' )
#' print(comparison$summary)
compare_dia_results <- function(before_file,
                                 after_file,
                                 q_value_threshold = 0.01) {

  cat("\n", strrep("=", 70), "\n")
  cat("  DIA-NN Results Comparison: Before vs After Optimization\n")
  cat(strrep("=", 70), "\n\n")

  # Load data
  cat("[1/4] Loading DIA-NN reports...\n")
  before_data <- load_diann_report(before_file)
  after_data <- load_diann_report(after_file)

  cat(sprintf("  - Before: %s precursors\n", format(nrow(before_data), big.mark = ",")))
  cat(sprintf("  - After:  %s precursors\n", format(nrow(after_data), big.mark = ",")))

  # Calculate metrics
  cat("\n[2/4] Calculating identification metrics...\n")
  id_metrics <- calculate_identification_metrics(before_data, after_data, q_value_threshold)

  cat("\n[3/4] Calculating quantification metrics...\n")
  quant_metrics <- calculate_quantification_metrics(before_data, after_data)

  cat("\n[4/4] Generating summary...\n")
  summary_table <- create_comparison_summary(id_metrics, quant_metrics)

  # Print summary
  cat("\n", strrep("-", 70), "\n")
  cat("  COMPARISON SUMMARY\n")
  cat(strrep("-", 70), "\n\n")
  print(summary_table, n = Inf)

  # Return results
  list(
    before_data = before_data,
    after_data = after_data,
    identification = id_metrics,
    quantification = quant_metrics,
    summary = summary_table
  )
}


#' Load DIA-NN report (parquet or TSV)
#' @keywords internal
load_diann_report <- function(file_path) {
  # Guard: file must exist
  if (!file.exists(file_path)) {
    stop(sprintf("File not found: %s", file_path))
  }

  ext <- tolower(tools::file_ext(file_path))
  supported_formats <- c("parquet", "tsv", "txt")

  # Guard: unsupported format
  if (!ext %in% supported_formats) {
    stop(sprintf("Unsupported file format: %s (use .parquet or .tsv)", ext))
  }

  # Load based on format
  data <- if (ext == "parquet") {
    arrow::read_parquet(file_path)
  } else {
    readr::read_tsv(file_path, show_col_types = FALSE)
  }

  as_tibble(data)
}


#' Calculate identification metrics
#' @keywords internal
calculate_identification_metrics <- function(before_data, after_data, q_threshold) {

  # Filter by Q.Value
  before_filtered <- before_data %>%
    filter(if ("Q.Value" %in% names(.)) Q.Value <= q_threshold else TRUE)
  after_filtered <- after_data %>%
    filter(if ("Q.Value" %in% names(.)) Q.Value <= q_threshold else TRUE)

  # Precursor counts
  precursor_before <- nrow(before_filtered)
  precursor_after <- nrow(after_filtered)


  # Unique peptides (if Modified.Sequence available)
  peptide_before <- NA
  peptide_after <- NA
  if ("Modified.Sequence" %in% names(before_data)) {
    peptide_before <- n_distinct(before_filtered$Modified.Sequence)
    peptide_after <- n_distinct(after_filtered$Modified.Sequence)
  }

  # Protein groups (if Protein.Group available)
  protein_before <- NA
  protein_after <- NA
  if ("Protein.Group" %in% names(before_data)) {
    protein_before <- n_distinct(before_filtered$Protein.Group)
    protein_after <- n_distinct(after_filtered$Protein.Group)
  }

  # Q.Value distribution
  qvalue_stats_before <- NULL
  qvalue_stats_after <- NULL
  if ("Q.Value" %in% names(before_data)) {
    qvalue_stats_before <- summary(before_data$Q.Value)
    qvalue_stats_after <- summary(after_data$Q.Value)
  }

  list(
    precursors = list(before = precursor_before, after = precursor_after),
    peptides = list(before = peptide_before, after = peptide_after),
    proteins = list(before = protein_before, after = protein_after),
    qvalue_before = qvalue_stats_before,
    qvalue_after = qvalue_stats_after,
    q_threshold = q_threshold
  )
}


#' Calculate quantification metrics
#' @keywords internal
calculate_quantification_metrics <- function(before_data, after_data) {

  metrics <- list()

  # Quantity.Quality (if available)
  if ("Quantity.Quality" %in% names(before_data) &&
      "Quantity.Quality" %in% names(after_data)) {
    metrics$quantity_quality <- list(
      before_mean = mean(before_data$Quantity.Quality, na.rm = TRUE),
      after_mean = mean(after_data$Quantity.Quality, na.rm = TRUE),
      before_median = median(before_data$Quantity.Quality, na.rm = TRUE),
      after_median = median(after_data$Quantity.Quality, na.rm = TRUE)
    )
  }

  # Missing value rate (Precursor.Quantity)
  if ("Precursor.Quantity" %in% names(before_data)) {
    metrics$missing_rate <- list(
      before = sum(is.na(before_data$Precursor.Quantity)) / nrow(before_data) * 100,
      after = sum(is.na(after_data$Precursor.Quantity)) / nrow(after_data) * 100
    )
  }

  # Intensity distribution
  if ("Precursor.Quantity" %in% names(before_data)) {
    metrics$intensity <- list(
      before_median = median(before_data$Precursor.Quantity, na.rm = TRUE),
      after_median = median(after_data$Precursor.Quantity, na.rm = TRUE),
      before_mean = mean(before_data$Precursor.Quantity, na.rm = TRUE),
      after_mean = mean(after_data$Precursor.Quantity, na.rm = TRUE)
    )
  }

  # CV calculation (if Run column exists for replicates)
  if ("Run" %in% names(before_data) && n_distinct(before_data$Run) > 1) {
    metrics$cv <- calculate_replicate_cv(before_data, after_data)
  }

  metrics
}


#' Calculate replicate CV
#' @keywords internal
calculate_replicate_cv <- function(before_data, after_data) {

  calc_cv <- function(data) {
    if (!"Precursor.Id" %in% names(data) || !"Run" %in% names(data)) {
      return(NA)
    }

    cv_data <- data %>%
      group_by(Precursor.Id) %>%
      filter(n() > 1) %>%
      summarise(
        cv = sd(Precursor.Quantity, na.rm = TRUE) / mean(Precursor.Quantity, na.rm = TRUE) * 100,
        .groups = "drop"
      )

    median(cv_data$cv, na.rm = TRUE)
  }

  list(
    before_median_cv = calc_cv(before_data),
    after_median_cv = calc_cv(after_data)
  )
}


#' Create comparison summary table
#' @keywords internal
create_comparison_summary <- function(id_metrics, quant_metrics) {

  rows <- list()

  # Identification metrics
  rows[[length(rows) + 1]] <- tibble(
    Category = "Identification",
    Metric = "Precursors",
    Before = id_metrics$precursors$before,
    After = id_metrics$precursors$after,
    Change = id_metrics$precursors$after - id_metrics$precursors$before,
    Change_Pct = (id_metrics$precursors$after - id_metrics$precursors$before) /
                  id_metrics$precursors$before * 100
  )

  if (!is.na(id_metrics$peptides$before)) {
    rows[[length(rows) + 1]] <- tibble(
      Category = "Identification",
      Metric = "Peptides",
      Before = id_metrics$peptides$before,
      After = id_metrics$peptides$after,
      Change = id_metrics$peptides$after - id_metrics$peptides$before,
      Change_Pct = (id_metrics$peptides$after - id_metrics$peptides$before) /
                    id_metrics$peptides$before * 100
    )
  }

  if (!is.na(id_metrics$proteins$before)) {
    rows[[length(rows) + 1]] <- tibble(
      Category = "Identification",
      Metric = "Proteins",
      Before = id_metrics$proteins$before,
      After = id_metrics$proteins$after,
      Change = id_metrics$proteins$after - id_metrics$proteins$before,
      Change_Pct = (id_metrics$proteins$after - id_metrics$proteins$before) /
                    id_metrics$proteins$before * 100
    )
  }

  # Quantification metrics
  if (!is.null(quant_metrics$quantity_quality)) {
    rows[[length(rows) + 1]] <- tibble(
      Category = "Quantification",
      Metric = "Quantity.Quality (mean)",
      Before = round(quant_metrics$quantity_quality$before_mean, 3),
      After = round(quant_metrics$quantity_quality$after_mean, 3),
      Change = round(quant_metrics$quantity_quality$after_mean -
                     quant_metrics$quantity_quality$before_mean, 3),
      Change_Pct = (quant_metrics$quantity_quality$after_mean -
                    quant_metrics$quantity_quality$before_mean) /
                    quant_metrics$quantity_quality$before_mean * 100
    )
  }

  if (!is.null(quant_metrics$missing_rate)) {
    rows[[length(rows) + 1]] <- tibble(
      Category = "Quantification",
      Metric = "Missing Rate (%)",
      Before = round(quant_metrics$missing_rate$before, 2),
      After = round(quant_metrics$missing_rate$after, 2),
      Change = round(quant_metrics$missing_rate$after -
                     quant_metrics$missing_rate$before, 2),
      Change_Pct = (quant_metrics$missing_rate$after -
                    quant_metrics$missing_rate$before) /
                    max(quant_metrics$missing_rate$before, 0.01) * 100
    )
  }

  if (!is.null(quant_metrics$cv)) {
    rows[[length(rows) + 1]] <- tibble(
      Category = "Quantification",
      Metric = "Replicate CV (median %)",
      Before = round(quant_metrics$cv$before_median_cv, 1),
      After = round(quant_metrics$cv$after_median_cv, 1),
      Change = round(quant_metrics$cv$after_median_cv -
                     quant_metrics$cv$before_median_cv, 1),
      Change_Pct = (quant_metrics$cv$after_median_cv -
                    quant_metrics$cv$before_median_cv) /
                    quant_metrics$cv$before_median_cv * 100
    )
  }

  # Metrics where lower values indicate improvement
  lower_is_better_metrics <- c("Missing Rate (%)", "Replicate CV (median %)")

  bind_rows(rows) %>%
    mutate(
      Change_Pct = round(Change_Pct, 1),
      is_lower_better = Metric %in% lower_is_better_metrics,
      Interpretation = case_when(
        is_lower_better & Change_Pct < 0 ~ "Improved",
        !is_lower_better & Change_Pct > 0 ~ "Improved",
        Change_Pct == 0 ~ "No change",
        TRUE ~ "Decreased"
      )
    ) %>%
    select(-is_lower_better)  # Remove helper column from output
}


# =============================================================================
# SECTION 2: Predictive Window Quality Metrics
# =============================================================================

#' Calculate window quality metrics (predictive, no re-analysis needed)
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param windows OptimizedWindows from Stage 3
#' @param original_window_width Original isolation window width (Th)
#' @return List of quality metrics
#'
#' @examples
#' metrics <- calculate_window_quality_metrics(
#'   validated_data = result$validated_data,
#'   windows = result$windows$quantile,
#'   original_window_width = 25  # Original fixed 25 Th windows
#' )
calculate_window_quality_metrics <- function(validated_data,
                                              windows,
                                              original_window_width = NULL) {

  cat("\n", strrep("=", 70), "\n")
  cat("  Window Quality Metrics (Predictive)\n")
  cat(strrep("=", 70), "\n\n")

  # Extract data
  data <- if ("data" %in% names(validated_data)) validated_data$data else validated_data

  cat("[1/4] Calculating precursor density...\n")
  density <- calculate_precursor_density(data, windows)

  cat("[2/4] Calculating interference scores...\n")
  interference <- calculate_interference_score(data, windows)

  cat("[3/4] Calculating window efficiency...\n")
  efficiency <- calculate_window_efficiency(data, windows)

  cat("[4/4] Generating summary...\n")

  # Combine metrics
  window_metrics <- windows %>%
    left_join(density, by = c("rt_segment_id", "mz_start", "mz_end")) %>%
    left_join(interference, by = c("rt_segment_id", "mz_start", "mz_end")) %>%
    left_join(efficiency, by = c("rt_segment_id", "mz_start", "mz_end"))

  # Summary statistics
  summary_stats <- tibble(
    Metric = c(
      "Mean Precursor Count per Window",
      "Mean Precursor Density (per Th)",
      "Median Pseudo-PIF",
      "Mean Interference Score",
      "Mean Window Efficiency",
      "Total Coverage Rate (%)",
      "Mean Window Width (Th)",
      "Window Width SD (Th)"
    ),
    Value = c(
      round(mean(window_metrics$precursor_count, na.rm = TRUE), 1),
      round(mean(window_metrics$density_per_th, na.rm = TRUE), 2),
      round(median(window_metrics$pseudo_pif, na.rm = TRUE), 3),
      round(mean(window_metrics$interference_score, na.rm = TRUE), 3),
      round(mean(window_metrics$efficiency, na.rm = TRUE), 2),
      round(sum(window_metrics$covered_count, na.rm = TRUE) / nrow(data) * 100, 1),
      round(mean(window_metrics$mz_end - window_metrics$mz_start, na.rm = TRUE), 2),
      round(sd(window_metrics$mz_end - window_metrics$mz_start, na.rm = TRUE), 2)
    ),
    Interpretation = c(
      "Lower = less co-isolation per scan",
      "Lower = better selectivity",
      "Higher = better precursor purity",
      "Lower = less fragment confusion",
      "Higher = better utilization",
      "Higher = more complete coverage",
      "Varies by strategy",
      "Lower = more uniform windows"
    )
  )

  # Print summary
  cat("\n", strrep("-", 70), "\n")
  cat("  WINDOW QUALITY SUMMARY\n")
  cat(strrep("-", 70), "\n\n")
  print(summary_stats, n = Inf)

  # Compare with original if provided
  if (!is.null(original_window_width)) {
    cat("\n  Comparison with original fixed windows:\n")
    new_width <- mean(window_metrics$mz_end - window_metrics$mz_start, na.rm = TRUE)
    cat(sprintf("  - Original width: %.1f Th (fixed)\n", original_window_width))
    cat(sprintf("  - Optimized mean: %.1f Th (variable)\n", new_width))
    cat(sprintf("  - Change: %.1f%% \n", (new_width - original_window_width) / original_window_width * 100))
  }

  list(
    window_metrics = window_metrics,
    summary = summary_stats,
    density = density,
    interference = interference,
    efficiency = efficiency
  )
}


#' Calculate precursor density per window
#' @keywords internal
calculate_precursor_density <- function(data, windows) {

  windows %>%
    rowwise() %>%
    mutate(
      precursor_count = sum(
        data$Precursor.Mz >= mz_start &
        data$Precursor.Mz <= mz_end &
        data$RT.Start >= rt_start &
        data$RT.Start <= rt_end
      ),
      window_width = mz_end - mz_start,
      density_per_th = precursor_count / window_width,
      pseudo_pif = ifelse(precursor_count > 0, 1 / precursor_count, 1)
    ) %>%
    ungroup() %>%
    select(rt_segment_id, mz_start, mz_end,
           precursor_count, window_width, density_per_th, pseudo_pif)
}


#' Calculate interference score
#' @keywords internal
calculate_interference_score <- function(data, windows, mz_threshold = 0.5) {

  windows %>%
    rowwise() %>%
    mutate(
      mz_values = list(
        data %>%
          filter(Precursor.Mz >= mz_start, Precursor.Mz <= mz_end,
                 RT.Start >= rt_start, RT.Start <= rt_end) %>%
          pull(Precursor.Mz)
      ),
      n_precursors = length(mz_values[[1]]),
      close_pairs = {
        mz <- mz_values[[1]]
        if (length(mz) < 2) 0
        else {
          # Count pairs within threshold
          dists <- as.vector(dist(mz))
          sum(dists < mz_threshold)
        }
      },
      interference_score = ifelse(
        n_precursors > 1,
        close_pairs / (n_precursors * (n_precursors - 1) / 2),  # Normalize by possible pairs
        0
      )
    ) %>%
    ungroup() %>%
    select(rt_segment_id, mz_start, mz_end,
           n_precursors, close_pairs, interference_score)
}


#' Calculate window efficiency
#' @keywords internal
calculate_window_efficiency <- function(data, windows) {

  total_precursors <- nrow(data)

  windows %>%
    rowwise() %>%
    mutate(
      covered_count = sum(
        data$Precursor.Mz >= mz_start &
        data$Precursor.Mz <= mz_end &
        data$RT.Start >= rt_start &
        data$RT.Start <= rt_end
      ),
      window_area = (mz_end - mz_start) * (rt_end - rt_start),
      efficiency = ifelse(window_area > 0, covered_count / window_area, 0),
      coverage_contribution = covered_count / total_precursors * 100
    ) %>%
    ungroup() %>%
    select(rt_segment_id, mz_start, mz_end,
           covered_count, window_area, efficiency, coverage_contribution)
}


# =============================================================================
# SECTION 3: Visualization Functions
# =============================================================================

#' Plot comparison of before/after metrics
#'
#' @param comparison Result from compare_dia_results()
#' @param output_file Optional path to save plot
#' @return ggplot object
plot_comparison_summary <- function(comparison, output_file = NULL) {

  summary_data <- comparison$summary %>%
    filter(!is.na(Change_Pct)) %>%
    mutate(
      Metric = factor(Metric, levels = rev(Metric)),
      Direction = ifelse(Interpretation == "Improved", "Improved", "Not Improved")
    )

  p <- ggplot(summary_data, aes(x = Metric, y = Change_Pct, fill = Direction)) +
    geom_col() +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    coord_flip() +
    scale_fill_manual(values = c("Improved" = "#2E8B57", "Not Improved" = "#CD5C5C")) +
    labs(
      title = "Window Optimization Effect",
      subtitle = "Comparison of DIA-NN results before and after optimization",
      x = NULL,
      y = "Change (%)",
      fill = "Status"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      legend.position = "bottom"
    )

  if (!is.null(output_file)) {
    ggsave(output_file, p, width = 10, height = 6, dpi = 300)
    cat(sprintf("Plot saved to: %s\n", output_file))
  }

  p
}


#' Plot window quality metrics
#'
#' @param metrics Result from calculate_window_quality_metrics()
#' @param output_file Optional path to save plot
#' @return ggplot object
plot_window_quality <- function(metrics, output_file = NULL) {

  window_data <- metrics$window_metrics

  # Panel 1: Precursor density by RT
  p1 <- ggplot(window_data, aes(x = rt_start, y = density_per_th)) +
    geom_point(alpha = 0.6, color = "#4169E1") +
    geom_smooth(method = "loess", se = TRUE, color = "#DC143C") +
    labs(
      title = "Precursor Density by RT",
      x = "RT Start (min)",
      y = "Precursors per Th"
    ) +
    theme_minimal()

  # Panel 2: Interference score distribution
  p2 <- ggplot(window_data, aes(x = interference_score)) +
    geom_histogram(bins = 30, fill = "#4169E1", alpha = 0.7, color = "white") +
    geom_vline(xintercept = mean(window_data$interference_score, na.rm = TRUE),
               linetype = "dashed", color = "#DC143C", linewidth = 1) +
    labs(
      title = "Interference Score Distribution",
      subtitle = sprintf("Mean: %.3f", mean(window_data$interference_score, na.rm = TRUE)),
      x = "Interference Score",
      y = "Count"
    ) +
    theme_minimal()

  # Panel 3: Window width vs efficiency
  p3 <- ggplot(window_data, aes(x = mz_end - mz_start, y = efficiency)) +
    geom_point(alpha = 0.6, color = "#4169E1") +
    geom_smooth(method = "lm", se = TRUE, color = "#DC143C") +
    labs(
      title = "Window Width vs Efficiency",
      x = "Window Width (Th)",
      y = "Efficiency"
    ) +
    theme_minimal()

  # Panel 4: Pseudo-PIF distribution
  p4 <- ggplot(window_data, aes(x = pseudo_pif)) +
    geom_histogram(bins = 30, fill = "#2E8B57", alpha = 0.7, color = "white") +
    geom_vline(xintercept = median(window_data$pseudo_pif, na.rm = TRUE),
               linetype = "dashed", color = "#DC143C", linewidth = 1) +
    labs(
      title = "Pseudo-PIF Distribution",
      subtitle = sprintf("Median: %.3f", median(window_data$pseudo_pif, na.rm = TRUE)),
      x = "Pseudo-PIF (1/precursor count)",
      y = "Count"
    ) +
    theme_minimal()

  # Combine
  combined <- (p1 | p2) / (p3 | p4) +
    plot_annotation(
      title = "Window Quality Assessment",
      theme = theme(plot.title = element_text(face = "bold", size = 16))
    )

  if (!is.null(output_file)) {
    ggsave(output_file, combined, width = 12, height = 10, dpi = 300)
    cat(sprintf("Plot saved to: %s\n", output_file))
  }

  combined
}


# =============================================================================
# SECTION 4: Full Validation Report
# =============================================================================

#' Generate comprehensive validation report
#'
#' @param before_file Path to DIA-NN report BEFORE optimization
#' @param after_file Path to DIA-NN report AFTER optimization (NULL if not available)
#' @param validated_data ValidatedData from pipeline (optional)
#' @param windows OptimizedWindows from pipeline (optional)
#' @param output_dir Directory for output files
#' @return List containing all validation results
generate_validation_report <- function(before_file = NULL,
                                        after_file = NULL,
                                        validated_data = NULL,
                                        windows = NULL,
                                        output_dir = "validation_results") {

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("  WINDOW OPTIMIZATION VALIDATION REPORT\n")
  cat(strrep("=", 70), "\n")
  cat(sprintf("  Generated: %s\n", Sys.time()))
  cat(strrep("=", 70), "\n\n")

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat(sprintf("Created output directory: %s\n\n", output_dir))
  }

  results <- list()

  # Part 1: Before/After comparison (if both files provided)
  if (!is.null(before_file) && !is.null(after_file)) {
    cat("\n### PART 1: Before/After DIA-NN Comparison ###\n")

    results$comparison <- compare_dia_results(before_file, after_file)

    # Save comparison plot
    plot_file <- file.path(output_dir, "comparison_summary.png")
    results$comparison_plot <- plot_comparison_summary(results$comparison, plot_file)

    # Save summary table
    summary_file <- file.path(output_dir, "comparison_summary.csv")
    write.csv(results$comparison$summary, summary_file, row.names = FALSE)
    cat(sprintf("\nSummary saved to: %s\n", summary_file))
  }

  # Part 2: Window quality metrics (if windows provided)
  if (!is.null(validated_data) && !is.null(windows)) {
    cat("\n### PART 2: Window Quality Metrics ###\n")

    results$quality <- calculate_window_quality_metrics(validated_data, windows)

    # Save quality plot
    plot_file <- file.path(output_dir, "window_quality.png")
    results$quality_plot <- plot_window_quality(results$quality, plot_file)

    # Save metrics table
    metrics_file <- file.path(output_dir, "window_metrics.csv")
    write.csv(results$quality$window_metrics, metrics_file, row.names = FALSE)
    cat(sprintf("\nMetrics saved to: %s\n", metrics_file))

    # Save summary
    summary_file <- file.path(output_dir, "quality_summary.csv")
    write.csv(results$quality$summary, summary_file, row.names = FALSE)
  }

  # Final summary
  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("  VALIDATION COMPLETE\n")
  cat(strrep("=", 70), "\n")
  cat(sprintf("  Output directory: %s\n", normalizePath(output_dir)))
  cat(sprintf("  Files generated: %d\n", length(list.files(output_dir))))
  cat(strrep("=", 70), "\n\n")

  invisible(results)
}


# =============================================================================
# SECTION 5: Utility Functions
# =============================================================================

#' Quick summary of window optimization effect
#'
#' @param comparison Result from compare_dia_results()
#' @return Character string with summary
summarize_optimization_effect <- function(comparison) {

  summary <- comparison$summary

  # Key metrics
  precursor_change <- summary %>% filter(Metric == "Precursors") %>% pull(Change_Pct)

  quality_change <- if ("Quantity.Quality (mean)" %in% summary$Metric) {
    summary %>% filter(Metric == "Quantity.Quality (mean)") %>% pull(Change_Pct)
  } else NA

  missing_change <- if ("Missing Rate (%)" %in% summary$Metric) {
    summary %>% filter(Metric == "Missing Rate (%)") %>% pull(Change_Pct)
  } else NA

  # Build summary
  msg <- sprintf(
    "Window Optimization Effect Summary:
    - Precursor identification: %+.1f%%
    - Quantification quality: %s
    - Missing values: %s

    Overall: %s",
    precursor_change,
    ifelse(is.na(quality_change), "N/A", sprintf("%+.1f%%", quality_change)),
    ifelse(is.na(missing_change), "N/A", sprintf("%+.1f%%", missing_change)),
    ifelse(precursor_change > 0, "IMPROVEMENT", "NO IMPROVEMENT")
  )

  cat(msg)
  invisible(msg)
}


# =============================================================================
# EXAMPLE USAGE (commented out)
# =============================================================================

# # Example 1: Compare Before/After DIA-NN results
# comparison <- compare_dia_results(
#   before_file = "data/standard_method_report.parquet",
#   after_file = "data/optimized_method_report.parquet"
# )
# plot_comparison_summary(comparison, "comparison.png")
#
# # Example 2: Calculate predictive window metrics
# source("main.R")
# results <- run_complete_pipeline(data_dir = "data", instrument_preset = "astral")
#
# metrics <- calculate_window_quality_metrics(
#   validated_data = results$validated_data,
#   windows = results$windows$quantile,
#   original_window_width = 25
# )
# plot_window_quality(metrics, "window_quality.png")
#
# # Example 3: Full validation report
# report <- generate_validation_report(
#   before_file = "data/before.parquet",
#   after_file = "data/after.parquet",
#   validated_data = results$validated_data,
#   windows = results$windows$quantile,
#   output_dir = "validation_output"
# )

cat("\n[validate_window_optimization.R] Loaded successfully.\n")
cat("Available functions:\n")
cat("  - compare_dia_results(before_file, after_file)\n")
cat("  - calculate_window_quality_metrics(validated_data, windows)\n")
cat("  - generate_validation_report(...)\n")
cat("  - plot_comparison_summary(comparison)\n")
cat("  - plot_window_quality(metrics)\n\n")
