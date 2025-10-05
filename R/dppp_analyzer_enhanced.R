# dppp_analyzer_enhanced.R - Enhanced DPPP Distribution Analysis and Optimization
#
# This module provides comprehensive DPPP analysis including:
# - Current DPPP distribution calculation from FWHM data
# - DPPP satisfaction ratio analysis
# - Interactive scan_time optimization
# - 2D visualization (RT × m/z DPPP heatmap)

library(dplyr)
library(ggplot2)
library(viridis)
library(scales)

# ============================================================================
# Core DPPP Distribution Analysis
# ============================================================================

#' Analyze current DPPP distribution from DIA-NN data
#'
#' @param data DIA-NN data frame with FWHM column
#' @param scan_time Current or assumed scan time in seconds (default: 2.0)
#' @param target_dppp Target DPPP value for satisfaction calculation
#' @param dppp_tolerance Tolerance for DPPP satisfaction (default: 0.1)
#' @param instrument_config Instrument configuration (optional)
#' @return List with DPPP analysis results
#' @export
analyze_dppp_distribution <- function(data,
                                     scan_time = 2.0,
                                     target_dppp = 1.25,
                                     dppp_tolerance = 0.1,
                                     instrument_config = NULL) {

  cat("\n=== Enhanced DPPP Distribution Analysis ===\n")
  cat(sprintf("Current scan_time: %.2f seconds\n", scan_time))
  cat(sprintf("Target DPPP: %.2f (tolerance: ±%.2f)\n", target_dppp, dppp_tolerance))

  # Validate data
  if (!("FWHM" %in% names(data))) {
    stop("Data must contain FWHM column for DPPP analysis")
  }

  # Filter valid FWHM values
  valid_data <- data %>%
    filter(!is.na(FWHM), FWHM > 0)

  if (nrow(valid_data) == 0) {
    stop("No valid FWHM values found in data")
  }

  cat(sprintf("Valid precursors with FWHM: %d (%.1f%%)\n",
              nrow(valid_data),
              100 * nrow(valid_data) / nrow(data)))

  # Calculate DPPP for each precursor
  # Formula: DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds
  # Using scan_time as proxy for cycle_time
  valid_data <- valid_data %>%
    mutate(
      FWHM_seconds = FWHM * 60,  # Convert minutes to seconds
      peak_width_seconds = FWHM_seconds * 1.7,  # Spectronaut standard
      current_DPPP = peak_width_seconds / scan_time
    )

  # Calculate DPPP statistics
  dppp_stats <- list(
    mean = mean(valid_data$current_DPPP),
    median = median(valid_data$current_DPPP),
    sd = sd(valid_data$current_DPPP),
    q25 = quantile(valid_data$current_DPPP, 0.25),
    q75 = quantile(valid_data$current_DPPP, 0.75),
    min = min(valid_data$current_DPPP),
    max = max(valid_data$current_DPPP),
    mode = calculate_mode(valid_data$current_DPPP, breaks = 50)
  )

  # Calculate satisfaction ratio
  satisfaction_analysis <- calculate_dppp_satisfaction_ratio(
    valid_data$current_DPPP,
    target_dppp,
    dppp_tolerance
  )

  # Create 2D binning for RT × m/z DPPP distribution
  dppp_2d <- create_dppp_2d_distribution(
    valid_data,
    rt_bins = 50,
    mz_bins = 50
  )

  # Print summary
  cat("\n--- DPPP Distribution Statistics ---\n")
  cat(sprintf("Mean DPPP: %.2f\n", dppp_stats$mean))
  cat(sprintf("Median DPPP: %.2f\n", dppp_stats$median))
  cat(sprintf("Std Dev: %.2f\n", dppp_stats$sd))
  cat(sprintf("Q25-Q75: [%.2f, %.2f]\n", dppp_stats$q25, dppp_stats$q75))
  cat(sprintf("Range: [%.2f, %.2f]\n", dppp_stats$min, dppp_stats$max))

  cat("\n--- DPPP Satisfaction Analysis ---\n")
  cat(sprintf("Target DPPP: %.2f ± %.2f\n", target_dppp, dppp_tolerance))
  cat(sprintf("Satisfaction ratio: %.1f%% (%d / %d precursors)\n",
              satisfaction_analysis$satisfaction_ratio * 100,
              satisfaction_analysis$n_satisfied,
              satisfaction_analysis$n_total))
  cat(sprintf("Below target: %.1f%% (%d precursors)\n",
              satisfaction_analysis$below_ratio * 100,
              satisfaction_analysis$n_below))
  cat(sprintf("Above target: %.1f%% (%d precursors)\n",
              satisfaction_analysis$above_ratio * 100,
              satisfaction_analysis$n_above))

  # Return comprehensive results
  return(list(
    data = valid_data,
    stats = dppp_stats,
    satisfaction = satisfaction_analysis,
    dppp_2d = dppp_2d,
    scan_time = scan_time,
    target_dppp = target_dppp,
    tolerance = dppp_tolerance
  ))
}

#' Calculate DPPP satisfaction ratio
#'
#' @param dppp_values Vector of DPPP values
#' @param target_dppp Target DPPP value
#' @param tolerance Tolerance around target (default: 0.1)
#' @return List with satisfaction analysis
#' @export
calculate_dppp_satisfaction_ratio <- function(dppp_values,
                                             target_dppp,
                                             tolerance = 0.1) {

  n_total <- length(dppp_values)

  # Define satisfaction range
  lower_bound <- target_dppp - tolerance
  upper_bound <- target_dppp + tolerance

  # Count precursors in each category
  n_satisfied <- sum(dppp_values >= lower_bound & dppp_values <= upper_bound)
  n_below <- sum(dppp_values < lower_bound)
  n_above <- sum(dppp_values > upper_bound)

  # Calculate ratios
  satisfaction_ratio <- n_satisfied / n_total
  below_ratio <- n_below / n_total
  above_ratio <- n_above / n_total

  return(list(
    n_total = n_total,
    n_satisfied = n_satisfied,
    n_below = n_below,
    n_above = n_above,
    satisfaction_ratio = satisfaction_ratio,
    below_ratio = below_ratio,
    above_ratio = above_ratio,
    target_dppp = target_dppp,
    tolerance = tolerance,
    lower_bound = lower_bound,
    upper_bound = upper_bound
  ))
}

#' Create 2D DPPP distribution (RT × m/z)
#'
#' @param data Data frame with RT.Start, Precursor.Mz, and FWHM columns
#' @param rt_bins Number of RT bins (default: 50)
#' @param mz_bins Number of m/z bins (default: 50)
#' @param scan_time Current scan time for DPPP calculation if current_DPPP not present (default: 2.0)
#' @return List with 2D binned DPPP data
#' @export
create_dppp_2d_distribution <- function(data, rt_bins = 50, mz_bins = 50, scan_time = 2.0) {

  # Calculate current_DPPP if not present
  if (!"current_DPPP" %in% names(data)) {
    data <- data %>%
      mutate(
        fwhm_seconds = FWHM * 60,
        current_DPPP = (1.7 * fwhm_seconds) / scan_time
      )
  }

  # Create RT bins
  rt_breaks <- seq(min(data$RT.Start), max(data$RT.Start), length.out = rt_bins + 1)
  data$rt_bin <- cut(data$RT.Start, breaks = rt_breaks, include.lowest = TRUE, labels = FALSE)

  # Create m/z bins
  mz_breaks <- seq(min(data$Precursor.Mz), max(data$Precursor.Mz), length.out = mz_bins + 1)
  data$mz_bin <- cut(data$Precursor.Mz, breaks = mz_breaks, include.lowest = TRUE, labels = FALSE)

  # Calculate average DPPP per bin
  dppp_2d_summary <- data %>%
    group_by(rt_bin, mz_bin) %>%
    summarise(
      mean_dppp = mean(current_DPPP, na.rm = TRUE),
      median_dppp = median(current_DPPP, na.rm = TRUE),
      n_precursors = n(),
      rt_center = mean(RT.Start),
      mz_center = mean(Precursor.Mz),
      .groups = 'drop'
    )

  return(list(
    summary = dppp_2d_summary,
    rt_breaks = rt_breaks,
    mz_breaks = mz_breaks,
    rt_bins = rt_bins,
    mz_bins = mz_bins
  ))
}

# ============================================================================
# Interactive Scan Time Optimization
# ============================================================================

#' Calculate optimal scan_time for target DPPP satisfaction
#'
#' @param data DIA-NN data with FWHM column
#' @param target_dppp Target DPPP value
#' @param target_satisfaction_ratio Desired satisfaction ratio (0-1, default: 0.80)
#' @param dppp_tolerance Tolerance for DPPP satisfaction (default: 0.1)
#' @param scan_time_range Range of scan_times to test (default: c(1.0, 3.0))
#' @param n_steps Number of scan_time steps to test (default: 50)
#' @return List with optimal scan_time recommendation
#' @export
calculate_optimal_scan_time <- function(data,
                                       target_dppp = 1.25,
                                       target_satisfaction_ratio = 0.80,
                                       dppp_tolerance = 0.1,
                                       scan_time_range = c(1.0, 3.0),
                                       n_steps = 50) {

  cat("\n=== Calculating Optimal Scan Time ===\n")
  cat(sprintf("Target DPPP: %.2f (tolerance: ±%.2f)\n", target_dppp, dppp_tolerance))
  cat(sprintf("Target satisfaction ratio: %.1f%%\n", target_satisfaction_ratio * 100))
  cat(sprintf("Scan time range: [%.2f, %.2f] seconds\n", scan_time_range[1], scan_time_range[2]))

  # Validate data
  valid_data <- data %>%
    filter(!is.na(FWHM), FWHM > 0) %>%
    mutate(
      FWHM_seconds = FWHM * 60,
      peak_width_seconds = FWHM_seconds * 1.7
    )

  # Test different scan_time values
  scan_times <- seq(scan_time_range[1], scan_time_range[2], length.out = n_steps)

  results <- data.frame(
    scan_time = scan_times,
    satisfaction_ratio = numeric(n_steps),
    mean_dppp = numeric(n_steps),
    median_dppp = numeric(n_steps),
    n_satisfied = integer(n_steps)
  )

  cat("\nTesting scan_time values...")

  for (i in seq_along(scan_times)) {
    st <- scan_times[i]

    # Calculate DPPP for this scan_time
    dppp_values <- valid_data$peak_width_seconds / st

    # Calculate satisfaction
    satisfaction <- calculate_dppp_satisfaction_ratio(
      dppp_values,
      target_dppp,
      dppp_tolerance
    )

    results$satisfaction_ratio[i] <- satisfaction$satisfaction_ratio
    results$mean_dppp[i] <- mean(dppp_values)
    results$median_dppp[i] <- median(dppp_values)
    results$n_satisfied[i] <- satisfaction$n_satisfied
  }

  cat(" Done.\n")

  # Find scan_time that achieves target satisfaction
  optimal_idx <- which.min(abs(results$satisfaction_ratio - target_satisfaction_ratio))

  if (length(optimal_idx) == 0) {
    warning("Could not find scan_time achieving target satisfaction")
    optimal_idx <- which.max(results$satisfaction_ratio)
  }

  optimal_scan_time <- results$scan_time[optimal_idx]
  achieved_satisfaction <- results$satisfaction_ratio[optimal_idx]
  achieved_dppp <- results$mean_dppp[optimal_idx]

  # Calculate expected window count impact
  # Assuming proportional relationship: window_count ∝ 1/scan_time
  current_scan_time <- 2.0  # Default baseline
  window_count_ratio <- current_scan_time / optimal_scan_time

  cat("\n--- Optimization Results ---\n")
  cat(sprintf("Recommended scan_time: %.2f seconds\n", optimal_scan_time))
  cat(sprintf("Expected satisfaction: %.1f%%\n", achieved_satisfaction * 100))
  cat(sprintf("Expected mean DPPP: %.2f\n", achieved_dppp))
  cat(sprintf("Window count impact: %.0f%% (ratio: %.2f)\n",
              (window_count_ratio - 1) * 100, window_count_ratio))

  if (achieved_satisfaction >= target_satisfaction_ratio) {
    cat(sprintf("✅ Target satisfaction (%.1f%%) achieved!\n",
                target_satisfaction_ratio * 100))
  } else {
    cat(sprintf("⚠️  Warning: Could not achieve target satisfaction\n"))
    cat(sprintf("   Best achievable: %.1f%%\n", achieved_satisfaction * 100))
  }

  return(list(
    optimal_scan_time = optimal_scan_time,
    achieved_satisfaction = achieved_satisfaction,
    achieved_dppp = achieved_dppp,
    target_satisfaction = target_satisfaction_ratio,
    window_count_ratio = window_count_ratio,
    scan_time_curve = results,
    target_dppp = target_dppp,
    tolerance = dppp_tolerance
  ))
}

#' Generate scan_time vs satisfaction trade-off analysis
#'
#' @param optimization_result Result from calculate_optimal_scan_time
#' @param current_scan_time Current scan_time for comparison (default: 2.0)
#' @param current_window_count Current window count (optional)
#' @return Trade-off analysis data frame
#' @export
analyze_scan_time_tradeoffs <- function(optimization_result,
                                       current_scan_time = 2.0,
                                       current_window_count = NULL) {

  curve_data <- optimization_result$scan_time_curve

  # Add trade-off metrics
  curve_data <- curve_data %>%
    mutate(
      window_count_ratio = current_scan_time / scan_time,
      satisfaction_delta = satisfaction_ratio - optimization_result$target_satisfaction,
      dppp_delta = mean_dppp - optimization_result$target_dppp
    )

  # If current window count provided, calculate expected window counts
  if (!is.null(current_window_count)) {
    curve_data$expected_windows <- round(current_window_count * curve_data$window_count_ratio)
  }

  # Identify key points
  optimal_idx <- which.min(abs(curve_data$satisfaction_ratio - optimization_result$target_satisfaction))
  current_idx <- which.min(abs(curve_data$scan_time - current_scan_time))

  curve_data$point_type <- "regular"
  curve_data$point_type[optimal_idx] <- "optimal"
  curve_data$point_type[current_idx] <- "current"

  return(curve_data)
}

# ============================================================================
# Utility Functions
# ============================================================================

#' Calculate mode of a distribution
#'
#' @param x Numeric vector
#' @param breaks Number of breaks for histogram
#' @return Mode value
calculate_mode <- function(x, breaks = 30) {
  if (length(x) == 0) return(NA)

  h <- hist(x, breaks = breaks, plot = FALSE)
  mode_idx <- which.max(h$counts)
  mode_value <- (h$breaks[mode_idx] + h$breaks[mode_idx + 1]) / 2

  return(mode_value)
}

#' Print DPPP analysis summary
#'
#' @param dppp_analysis Result from analyze_dppp_distribution
#' @export
print_dppp_summary <- function(dppp_analysis) {
  cat("\n╔════════════════════════════════════════════╗\n")
  cat("║        DPPP ANALYSIS SUMMARY              ║\n")
  cat("╚════════════════════════════════════════════╝\n")

  cat(sprintf("\nScan Time: %.2f seconds\n", dppp_analysis$scan_time))
  cat(sprintf("Target DPPP: %.2f ± %.2f\n",
              dppp_analysis$target_dppp,
              dppp_analysis$tolerance))

  cat("\n--- Distribution Statistics ---\n")
  cat(sprintf("Mean DPPP: %.2f\n", dppp_analysis$stats$mean))
  cat(sprintf("Median DPPP: %.2f\n", dppp_analysis$stats$median))
  cat(sprintf("Std Dev: %.2f\n", dppp_analysis$stats$sd))
  cat(sprintf("Range: [%.2f, %.2f]\n",
              dppp_analysis$stats$min,
              dppp_analysis$stats$max))

  cat("\n--- Satisfaction Analysis ---\n")
  cat(sprintf("Satisfied: %.1f%% (%d precursors)\n",
              dppp_analysis$satisfaction$satisfaction_ratio * 100,
              dppp_analysis$satisfaction$n_satisfied))
  cat(sprintf("Below target: %.1f%% (%d precursors)\n",
              dppp_analysis$satisfaction$below_ratio * 100,
              dppp_analysis$satisfaction$n_below))
  cat(sprintf("Above target: %.1f%% (%d precursors)\n",
              dppp_analysis$satisfaction$above_ratio * 100,
              dppp_analysis$satisfaction$n_above))

  cat("\n")
}

#' Compare DPPP distributions between iterations
#'
#' @param dppp_analysis_list List of DPPP analysis results
#' @return Comparison data frame
#' @export
compare_dppp_distributions <- function(dppp_analysis_list) {

  n_analyses <- length(dppp_analysis_list)

  comparison <- data.frame(
    iteration = names(dppp_analysis_list),
    scan_time = numeric(n_analyses),
    mean_dppp = numeric(n_analyses),
    median_dppp = numeric(n_analyses),
    satisfaction_ratio = numeric(n_analyses),
    n_satisfied = integer(n_analyses),
    n_below = integer(n_analyses),
    n_above = integer(n_analyses)
  )

  for (i in seq_along(dppp_analysis_list)) {
    analysis <- dppp_analysis_list[[i]]
    comparison$scan_time[i] <- analysis$scan_time
    comparison$mean_dppp[i] <- analysis$stats$mean
    comparison$median_dppp[i] <- analysis$stats$median
    comparison$satisfaction_ratio[i] <- analysis$satisfaction$satisfaction_ratio
    comparison$n_satisfied[i] <- analysis$satisfaction$n_satisfied
    comparison$n_below[i] <- analysis$satisfaction$n_below
    comparison$n_above[i] <- analysis$satisfaction$n_above
  }

  return(comparison)
}

# ============================================================================
# Visualization Functions
# ============================================================================

#' Visualize DPPP analysis results (comprehensive)
#'
#' @param dppp_analysis Result from analyze_dppp_distribution
#' @param optimization_result Result from calculate_optimal_scan_time (optional)
#' @param save_plots Whether to save plots to files (default: FALSE)
#' @param plot_dir Directory for saving plots (default: "plots")
#' @return List of ggplot objects
#' @export
visualize_dppp_analysis <- function(dppp_analysis,
                                   optimization_result = NULL,
                                   save_plots = FALSE,
                                   plot_dir = "plots") {

  plots <- list()

  # Plot 1: DPPP distribution histogram
  plots$dppp_histogram <- plot_dppp_histogram(dppp_analysis)

  # Plot 2: DPPP 2D heatmap (RT × m/z)
  plots$dppp_heatmap <- plot_dppp_heatmap_2d(dppp_analysis)

  # Plot 3: DPPP satisfaction breakdown
  plots$satisfaction_breakdown <- plot_dppp_satisfaction_breakdown(dppp_analysis)

  # If optimization result provided, add optimization plots
  if (!is.null(optimization_result)) {
    # Plot 4: Satisfaction curve
    plots$satisfaction_curve <- plot_satisfaction_curve(optimization_result)

    # Plot 5: Trade-off analysis
    plots$tradeoff_analysis <- plot_scan_time_tradeoff(optimization_result)
  }

  # Save plots if requested
  if (save_plots) {
    if (!dir.exists(plot_dir)) {
      dir.create(plot_dir, recursive = TRUE)
    }

    for (plot_name in names(plots)) {
      filename <- file.path(plot_dir, paste0("dppp_", plot_name, ".png"))
      ggsave(filename, plots[[plot_name]], width = 10, height = 8, dpi = 300)
      cat(sprintf("Saved: %s\n", filename))
    }
  }

  return(plots)
}

#' Plot DPPP distribution histogram
#'
#' @param dppp_analysis Result from analyze_dppp_distribution
#' @return ggplot object
#' @export
plot_dppp_histogram <- function(dppp_analysis) {

  data <- dppp_analysis$data
  target <- dppp_analysis$target_dppp
  tolerance <- dppp_analysis$tolerance

  p <- ggplot(data, aes(x = current_DPPP)) +
    geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7, color = "black", size = 0.2) +
    geom_density(aes(y = after_stat(count)), color = "red", size = 1.2) +
    geom_vline(xintercept = target, color = "darkgreen", linetype = "dashed", size = 1) +
    geom_vline(xintercept = target - tolerance, color = "orange", linetype = "dotted", size = 0.8) +
    geom_vline(xintercept = target + tolerance, color = "orange", linetype = "dotted", size = 0.8) +
    annotate("rect",
             xmin = target - tolerance, xmax = target + tolerance,
             ymin = 0, ymax = Inf,
             alpha = 0.2, fill = "green") +
    labs(
      title = "DPPP Distribution Analysis",
      subtitle = sprintf("Scan time: %.2f sec | Target DPPP: %.2f ± %.2f | Satisfaction: %.1f%%",
                        dppp_analysis$scan_time,
                        target,
                        tolerance,
                        dppp_analysis$satisfaction$satisfaction_ratio * 100),
      x = "DPPP (Data Points Per Peak)",
      y = "Count"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      axis.text = element_text(size = 10),
      axis.title = element_text(size = 12, face = "bold")
    ) +
    scale_x_continuous(breaks = pretty_breaks(n = 10))

  return(p)
}

#' Plot DPPP 2D heatmap (RT × m/z)
#'
#' @param dppp_analysis Result from analyze_dppp_distribution
#' @return ggplot object
#' @export
plot_dppp_heatmap_2d <- function(dppp_analysis) {

  dppp_2d <- dppp_analysis$dppp_2d$summary
  target <- dppp_analysis$target_dppp

  p <- ggplot(dppp_2d, aes(x = rt_center, y = mz_center, fill = mean_dppp)) +
    geom_tile() +
    scale_fill_viridis_c(
      name = "Mean DPPP",
      option = "plasma",
      limits = c(0, max(dppp_2d$mean_dppp, na.rm = TRUE))
    ) +
    geom_contour(aes(z = mean_dppp), color = "white", alpha = 0.3, size = 0.5) +
    labs(
      title = "DPPP Distribution Heatmap (RT × m/z)",
      subtitle = sprintf("Target DPPP: %.2f | Current scan_time: %.2f sec",
                        target,
                        dppp_analysis$scan_time),
      x = "Retention Time (min)",
      y = "Precursor m/z"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      legend.position = "right"
    )

  return(p)
}

#' Plot DPPP satisfaction breakdown
#'
#' @param dppp_analysis Result from analyze_dppp_distribution
#' @return ggplot object
#' @export
plot_dppp_satisfaction_breakdown <- function(dppp_analysis) {

  satisfaction <- dppp_analysis$satisfaction

  breakdown_data <- data.frame(
    category = c("Below Target", "Satisfied", "Above Target"),
    count = c(satisfaction$n_below, satisfaction$n_satisfied, satisfaction$n_above),
    ratio = c(satisfaction$below_ratio, satisfaction$satisfaction_ratio, satisfaction$above_ratio),
    color = c("#E74C3C", "#27AE60", "#F39C12")
  )

  breakdown_data$category <- factor(breakdown_data$category,
                                   levels = c("Below Target", "Satisfied", "Above Target"))

  p <- ggplot(breakdown_data, aes(x = category, y = count, fill = category)) +
    geom_bar(stat = "identity", alpha = 0.8, color = "black", size = 0.5) +
    geom_text(aes(label = sprintf("%d\n(%.1f%%)", count, ratio * 100)),
              vjust = -0.5, size = 4, fontface = "bold") +
    scale_fill_manual(values = breakdown_data$color) +
    labs(
      title = "DPPP Satisfaction Breakdown",
      subtitle = sprintf("Target: %.2f ± %.2f | Total precursors: %d",
                        dppp_analysis$target_dppp,
                        dppp_analysis$tolerance,
                        satisfaction$n_total),
      x = "Category",
      y = "Number of Precursors"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      legend.position = "none",
      axis.text = element_text(size = 10),
      axis.title = element_text(size = 12, face = "bold")
    ) +
    scale_y_continuous(labels = comma)

  return(p)
}

#' Plot satisfaction ratio vs scan_time curve
#'
#' @param optimization_result Result from calculate_optimal_scan_time
#' @param current_scan_time Current scan_time for comparison (default: 2.0)
#' @return ggplot object
#' @export
plot_satisfaction_curve <- function(optimization_result, current_scan_time = 2.0) {

  curve_data <- optimization_result$scan_time_curve
  optimal_st <- optimization_result$optimal_scan_time
  target_sat <- optimization_result$target_satisfaction

  p <- ggplot(curve_data, aes(x = scan_time, y = satisfaction_ratio)) +
    geom_line(color = "steelblue", size = 1.2) +
    geom_point(alpha = 0.3, size = 1) +
    geom_hline(yintercept = target_sat, color = "darkgreen",
               linetype = "dashed", size = 1) +
    geom_vline(xintercept = optimal_st, color = "red",
               linetype = "dashed", size = 1) +
    geom_vline(xintercept = current_scan_time, color = "orange",
               linetype = "dotted", size = 1) +
    geom_point(data = curve_data[which.min(abs(curve_data$scan_time - optimal_st)), ],
               aes(x = scan_time, y = satisfaction_ratio),
               color = "red", size = 4, shape = 21, fill = "white", stroke = 2) +
    annotate("text",
             x = optimal_st, y = min(curve_data$satisfaction_ratio),
             label = sprintf("Optimal: %.2f sec", optimal_st),
             hjust = -0.1, vjust = -0.5, color = "red", fontface = "bold") +
    annotate("text",
             x = max(curve_data$scan_time), y = target_sat,
             label = sprintf("Target: %.1f%%", target_sat * 100),
             hjust = 1, vjust = -0.5, color = "darkgreen", fontface = "bold") +
    labs(
      title = "DPPP Satisfaction vs Scan Time",
      subtitle = sprintf("Target satisfaction: %.1f%% | Optimal scan_time: %.2f sec",
                        target_sat * 100, optimal_st),
      x = "Scan Time (seconds)",
      y = "Satisfaction Ratio"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11)
    ) +
    scale_y_continuous(labels = percent, breaks = pretty_breaks(n = 10)) +
    scale_x_continuous(breaks = pretty_breaks(n = 10))

  return(p)
}

#' Plot scan_time trade-off analysis
#'
#' @param optimization_result Result from calculate_optimal_scan_time
#' @param current_scan_time Current scan_time (default: 2.0)
#' @param current_window_count Current window count (optional)
#' @return ggplot object
#' @export
plot_scan_time_tradeoff <- function(optimization_result,
                                   current_scan_time = 2.0,
                                   current_window_count = NULL) {

  tradeoff_data <- analyze_scan_time_tradeoffs(
    optimization_result,
    current_scan_time,
    current_window_count
  )

  # Create multi-metric plot
  p <- ggplot(tradeoff_data, aes(x = scan_time)) +
    geom_line(aes(y = satisfaction_ratio, color = "Satisfaction Ratio"), size = 1.2) +
    geom_line(aes(y = mean_dppp / max(mean_dppp), color = "Mean DPPP (normalized)"),
              size = 1.2, linetype = "dashed") +
    geom_line(aes(y = window_count_ratio / max(window_count_ratio), color = "Window Count Ratio (normalized)"),
              size = 1.2, linetype = "dotted") +
    geom_point(data = subset(tradeoff_data, point_type == "optimal"),
               aes(y = satisfaction_ratio), color = "red", size = 4, shape = 21,
               fill = "white", stroke = 2) +
    geom_point(data = subset(tradeoff_data, point_type == "current"),
               aes(y = satisfaction_ratio), color = "orange", size = 4, shape = 21,
               fill = "white", stroke = 2) +
    scale_color_manual(
      name = "Metric",
      values = c("Satisfaction Ratio" = "steelblue",
                 "Mean DPPP (normalized)" = "darkgreen",
                 "Window Count Ratio (normalized)" = "purple")
    ) +
    labs(
      title = "Scan Time Trade-off Analysis",
      subtitle = sprintf("Optimal: %.2f sec | Current: %.2f sec",
                        optimization_result$optimal_scan_time,
                        current_scan_time),
      x = "Scan Time (seconds)",
      y = "Normalized Metrics"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      legend.position = "bottom"
    ) +
    scale_y_continuous(breaks = pretty_breaks(n = 10)) +
    scale_x_continuous(breaks = pretty_breaks(n = 10))

  return(p)
}
