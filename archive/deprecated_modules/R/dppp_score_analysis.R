# dppp_score_analysis.R - DPPP-Score Correlation Analysis
#
# This module analyzes the relationship between DPPP and DIA-NN identification scores.
# Hypothesis: High DPPP → increased co-isolation → reduced selectivity → lower scores

library(dplyr)
library(ggplot2)
library(viridis)
library(scales)

# ============================================================================
# DPPP-Score Correlation Analysis
# ============================================================================

#' Analyze correlation between DPPP and identification score
#'
#' Tests the hypothesis that high DPPP regions (high precursor load) lead to
#' increased co-isolation and reduced identification scores.
#'
#' @param data DIA-NN data with FWHM and score columns
#' @param scan_time Current scan time for DPPP calculation (default: 2.0)
#' @param score_column Name of score column (default: "CScore" for DIA-NN)
#' @param stratify_by_density Stratify analysis by precursor density (default: TRUE)
#' @return List with correlation analysis results
#' @export
analyze_dppp_score_correlation <- function(data,
                                          scan_time = 2.0,
                                          score_column = "CScore",
                                          stratify_by_density = TRUE) {

  cat("\n=== DPPP-Score Correlation Analysis ===\n")
  cat("Hypothesis: High DPPP → Co-isolation → Low Score\n\n")

  # Validate required columns
  required_cols <- c("FWHM", score_column, "RT.Start", "Precursor.Mz")
  missing_cols <- setdiff(required_cols, names(data))

  if (length(missing_cols) > 0) {
    stop(sprintf("Missing required columns: %s", paste(missing_cols, collapse = ", ")))
  }

  # Calculate DPPP if not present
  if (!"current_DPPP" %in% names(data)) {
    data <- data %>%
      mutate(
        fwhm_seconds = FWHM * 60,
        current_DPPP = (1.7 * fwhm_seconds) / scan_time
      )
  }

  # Filter valid data
  valid_data <- data %>%
    filter(
      !is.na(FWHM), FWHM > 0,
      !is.na(.data[[score_column]]), .data[[score_column]] > 0,
      !is.na(current_DPPP), !is.infinite(current_DPPP)
    )

  cat(sprintf("Valid data points: %d (%.1f%%)\n",
              nrow(valid_data),
              100 * nrow(valid_data) / nrow(data)))

  # Calculate overall correlation
  cor_pearson <- cor(valid_data$current_DPPP, valid_data[[score_column]],
                     method = "pearson", use = "complete.obs")
  cor_spearman <- cor(valid_data$current_DPPP, valid_data[[score_column]],
                     method = "spearman", use = "complete.obs")

  cat(sprintf("\n--- Overall Correlation ---\n"))
  cat(sprintf("Pearson correlation: %.3f\n", cor_pearson))
  cat(sprintf("Spearman correlation: %.3f\n", cor_spearman))

  if (cor_pearson < -0.1) {
    cat("✓ Negative correlation detected: High DPPP → Low Score\n")
    cat("  → Hypothesis SUPPORTED: Co-isolation impacts selectivity\n")
  } else if (cor_pearson > 0.1) {
    cat("✗ Positive correlation detected: High DPPP → High Score\n")
    cat("  → Hypothesis REJECTED: Other factors may dominate\n")
  } else {
    cat("○ Weak correlation: No clear relationship\n")
    cat("  → Hypothesis INCONCLUSIVE: Further stratification needed\n")
  }

  # Stratify by DPPP level
  dppp_q <- quantile(valid_data$current_DPPP, probs = c(0.25, 0.75), na.rm = TRUE)

  valid_data <- valid_data %>%
    mutate(
      dppp_level = case_when(
        current_DPPP < dppp_q[1] ~ "Low_DPPP",
        current_DPPP > dppp_q[2] ~ "High_DPPP",
        TRUE ~ "Medium_DPPP"
      )
    )

  # Score statistics by DPPP level
  score_by_dppp <- valid_data %>%
    group_by(dppp_level) %>%
    summarise(
      n = n(),
      mean_score = mean(.data[[score_column]], na.rm = TRUE),
      median_score = median(.data[[score_column]], na.rm = TRUE),
      sd_score = sd(.data[[score_column]], na.rm = TRUE),
      mean_dppp = mean(current_DPPP, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    arrange(desc(mean_dppp))

  cat("\n--- Score by DPPP Level ---\n")
  print(score_by_dppp)

  # Density-stratified analysis if requested
  density_stratified <- NULL
  if (stratify_by_density) {
    density_stratified <- analyze_density_stratified_scores(
      valid_data,
      score_column,
      rt_bins = 20,
      mz_bins = 20
    )
  }

  # Return comprehensive results
  results <- list(
    data = valid_data,
    correlation = list(
      pearson = cor_pearson,
      spearman = cor_spearman,
      hypothesis_supported = (cor_pearson < -0.1)
    ),
    score_by_dppp_level = score_by_dppp,
    density_stratified = density_stratified,
    scan_time = scan_time,
    score_column = score_column
  )

  return(results)
}

#' Analyze scores stratified by spatial density
#'
#' @param data Data with DPPP and score columns
#' @param score_column Score column name
#' @param rt_bins Number of RT bins (default: 20)
#' @param mz_bins Number of m/z bins (default: 20)
#' @return Density-stratified analysis
#' @export
analyze_density_stratified_scores <- function(data,
                                             score_column,
                                             rt_bins = 20,
                                             mz_bins = 20) {

  cat("\n--- Density-Stratified Score Analysis ---\n")

  # Create RT × m/z bins
  rt_breaks <- seq(min(data$RT.Start), max(data$RT.Start), length.out = rt_bins + 1)
  mz_breaks <- seq(min(data$Precursor.Mz), max(data$Precursor.Mz), length.out = mz_bins + 1)

  data$rt_bin <- cut(data$RT.Start, breaks = rt_breaks, include.lowest = TRUE, labels = FALSE)
  data$mz_bin <- cut(data$Precursor.Mz, breaks = mz_breaks, include.lowest = TRUE, labels = FALSE)

  # Calculate statistics per bin
  bin_stats <- data %>%
    group_by(rt_bin, mz_bin) %>%
    summarise(
      n_precursors = n(),
      mean_dppp = mean(current_DPPP, na.rm = TRUE),
      median_dppp = median(current_DPPP, na.rm = TRUE),
      mean_score = mean(.data[[score_column]], na.rm = TRUE),
      median_score = median(.data[[score_column]], na.rm = TRUE),
      rt_center = mean(RT.Start),
      mz_center = mean(Precursor.Mz),
      .groups = 'drop'
    ) %>%
    filter(n_precursors > 0)

  # Classify bins by density
  density_q <- quantile(bin_stats$n_precursors, probs = c(0.33, 0.67), na.rm = TRUE)

  bin_stats <- bin_stats %>%
    mutate(
      density_class = case_when(
        n_precursors < density_q[1] ~ "Low_Density",
        n_precursors > density_q[2] ~ "High_Density",
        TRUE ~ "Medium_Density"
      )
    )

  # Score vs DPPP by density class
  density_comparison <- bin_stats %>%
    group_by(density_class) %>%
    summarise(
      n_bins = n(),
      mean_n_precursors = mean(n_precursors),
      mean_dppp = mean(mean_dppp, na.rm = TRUE),
      mean_score = mean(mean_score, na.rm = TRUE),
      correlation_dppp_score = cor(mean_dppp, mean_score, use = "complete.obs"),
      .groups = 'drop'
    ) %>%
    arrange(desc(mean_n_precursors))

  cat("\nScore vs DPPP by Density Class:\n")
  print(density_comparison)

  # Test hypothesis: High density → stronger DPPP-score anticorrelation
  high_density_bins <- bin_stats %>% filter(density_class == "High_Density")
  low_density_bins <- bin_stats %>% filter(density_class == "Low_Density")

  cor_high <- cor(high_density_bins$mean_dppp, high_density_bins$mean_score, use = "complete.obs")
  cor_low <- cor(low_density_bins$mean_dppp, low_density_bins$mean_score, use = "complete.obs")

  cat(sprintf("\nHigh-density regions: r = %.3f\n", cor_high))
  cat(sprintf("Low-density regions: r = %.3f\n", cor_low))

  if (cor_high < cor_low - 0.1) {
    cat("✓ High-density regions show stronger DPPP-score anticorrelation\n")
    cat("  → Co-isolation effect is density-dependent\n")
  } else {
    cat("○ No clear density-dependent effect detected\n")
  }

  return(list(
    bin_stats = bin_stats,
    density_comparison = density_comparison,
    correlation_high_density = cor_high,
    correlation_low_density = cor_low
  ))
}

# ============================================================================
# Visualization Functions for DPPP-Score Analysis
# ============================================================================

#' Plot DPPP vs Score scatter plot
#'
#' @param correlation_result Result from analyze_dppp_score_correlation()
#' @param color_by DPPP level or density class (default: "dppp_level")
#' @return ggplot object
#' @export
plot_dppp_score_scatter <- function(correlation_result, color_by = "dppp_level") {

  data <- correlation_result$data
  score_col <- correlation_result$score_column

  # Sample data if too large (for performance)
  if (nrow(data) > 50000) {
    data <- data %>% sample_n(50000)
    subtitle_note <- "(Showing 50,000 random samples)"
  } else {
    subtitle_note <- sprintf("(All %d data points)", nrow(data))
  }

  p <- ggplot(data, aes(x = current_DPPP, y = .data[[score_col]])) +
    geom_hex(bins = 50, alpha = 0.8) +
    scale_fill_viridis_c(
      name = "Count",
      option = "inferno",
      trans = "log10"
    ) +
    geom_smooth(method = "lm", color = "red", size = 1.2, se = TRUE, alpha = 0.2) +
    labs(
      title = "DPPP vs Identification Score",
      subtitle = sprintf(
        "r = %.3f (Pearson) | %s | %s",
        correlation_result$correlation$pearson,
        ifelse(correlation_result$correlation$hypothesis_supported,
               "Hypothesis SUPPORTED ✓",
               "Hypothesis NOT supported ✗"),
        subtitle_note
      ),
      x = "DPPP (Data Points Per Peak)",
      y = sprintf("%s (Identification Score)", score_col)
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "right"
    )

  return(p)
}

#' Plot score distribution by DPPP level
#'
#' @param correlation_result Result from analyze_dppp_score_correlation()
#' @return ggplot object
#' @export
plot_score_by_dppp_level <- function(correlation_result) {

  data <- correlation_result$data
  score_col <- correlation_result$score_column

  # Order levels by DPPP
  data$dppp_level <- factor(data$dppp_level,
                             levels = c("Low_DPPP", "Medium_DPPP", "High_DPPP"))

  p <- ggplot(data, aes(x = dppp_level, y = .data[[score_col]], fill = dppp_level)) +
    geom_violin(alpha = 0.6, scale = "width") +
    geom_boxplot(width = 0.2, alpha = 0.8, outlier.alpha = 0.3, outlier.size = 0.5) +
    scale_fill_manual(
      values = c("Low_DPPP" = "#27AE60", "Medium_DPPP" = "#F39C12", "High_DPPP" = "#E74C3C"),
      name = "DPPP Level"
    ) +
    labs(
      title = "Score Distribution by DPPP Level",
      subtitle = sprintf(
        "Testing: High DPPP → Low Score | r = %.3f",
        correlation_result$correlation$pearson
      ),
      x = "DPPP Level",
      y = sprintf("%s (Identification Score)", score_col)
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "none"
    ) +
    stat_summary(
      fun = mean,
      geom = "point",
      shape = 23,
      size = 4,
      fill = "white",
      color = "black"
    ) +
    stat_summary(
      fun = mean,
      geom = "text",
      aes(label = sprintf("%.2f", after_stat(y))),
      vjust = -1,
      size = 3.5,
      fontface = "bold"
    )

  return(p)
}

#' Plot 2D heatmap of DPPP vs Score
#'
#' @param correlation_result Result with density stratification
#' @return ggplot object
#' @export
plot_dppp_score_heatmap <- function(correlation_result) {

  if (is.null(correlation_result$density_stratified)) {
    stop("Density stratification not performed. Run with stratify_by_density=TRUE")
  }

  bin_stats <- correlation_result$density_stratified$bin_stats

  p <- ggplot(bin_stats, aes(x = rt_center, y = mz_center)) +
    geom_raster(aes(fill = mean_score), interpolate = FALSE) +
    scale_fill_viridis_c(
      name = "Mean Score",
      option = "viridis"
    ) +
    geom_contour(aes(z = mean_dppp), color = "white", alpha = 0.5, size = 0.5, bins = 5) +
    labs(
      title = "Score Heatmap with DPPP Contours",
      subtitle = "White contours = DPPP levels | Color = Mean Score",
      x = "Retention Time (min)",
      y = "Precursor m/z"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "right",
      panel.grid = element_blank()
    ) +
    coord_cartesian(expand = FALSE)

  return(p)
}

#' Plot density-stratified correlation
#'
#' @param correlation_result Result with density stratification
#' @return ggplot object
#' @export
plot_density_stratified_correlation <- function(correlation_result) {

  if (is.null(correlation_result$density_stratified)) {
    stop("Density stratification not performed")
  }

  bin_stats <- correlation_result$density_stratified$bin_stats

  # Order density classes
  bin_stats$density_class <- factor(
    bin_stats$density_class,
    levels = c("Low_Density", "Medium_Density", "High_Density")
  )

  p <- ggplot(bin_stats, aes(x = mean_dppp, y = mean_score, color = density_class)) +
    geom_point(aes(size = n_precursors), alpha = 0.6) +
    geom_smooth(method = "lm", se = TRUE, alpha = 0.2, size = 1.2) +
    scale_color_manual(
      values = c(
        "Low_Density" = "#27AE60",
        "Medium_Density" = "#F39C12",
        "High_Density" = "#E74C3C"
      ),
      name = "Density Class"
    ) +
    scale_size_continuous(
      name = "Precursors/Bin",
      range = c(1, 8)
    ) +
    labs(
      title = "DPPP-Score Correlation by Density Class",
      subtitle = sprintf(
        "High-density r = %.3f | Low-density r = %.3f",
        correlation_result$density_stratified$correlation_high_density,
        correlation_result$density_stratified$correlation_low_density
      ),
      x = "Mean DPPP (per bin)",
      y = sprintf("Mean %s (per bin)", correlation_result$score_column)
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "right"
    )

  return(p)
}

#' Create comprehensive DPPP-score analysis report
#'
#' @param correlation_result Result from analyze_dppp_score_correlation()
#' @param output_file PDF file path (optional)
#' @return List of ggplot objects
#' @export
create_dppp_score_report <- function(correlation_result, output_file = NULL) {

  cat("\n=== Creating DPPP-Score Analysis Report ===\n")

  plots <- list()

  # Plot 1: Scatter plot
  plots$scatter <- plot_dppp_score_scatter(correlation_result)

  # Plot 2: Score by DPPP level
  plots$by_level <- plot_score_by_dppp_level(correlation_result)

  # Plot 3 & 4: Density-stratified (if available)
  if (!is.null(correlation_result$density_stratified)) {
    plots$heatmap <- plot_dppp_score_heatmap(correlation_result)
    plots$stratified <- plot_density_stratified_correlation(correlation_result)
  }

  # Save if output file specified
  if (!is.null(output_file)) {
    n_plots <- length(plots)
    combined <- gridExtra::grid.arrange(
      grobs = plots,
      ncol = 2,
      top = grid::textGrob("DPPP-Score Correlation Analysis",
                           gp = grid::gpar(fontsize = 18, fontface = "bold"))
    )

    ggplot2::ggsave(
      output_file,
      combined,
      width = 14,
      height = 7 * ceiling(n_plots / 2),
      dpi = 300
    )

    cat(sprintf("✓ Report saved to: %s\n", output_file))
  }

  return(plots)
}
