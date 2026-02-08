# rt_segmentation.R - Time-Based RT Binning for DIA Window Optimization
#
# Module 2: RT Binning
#
# This module provides time-based RT binning strategies:
# - Time-Unit Binning: Equal time intervals (e.g., 5-minute bins)
# - Explicit Breakpoints: User-defined RT boundaries
# - Density-Based (experimental): Adaptive binning for comparison
#
# Purpose: Group precursors by retention time for RT-dependent window optimization
# NOT for equalizing precursor counts (that's done in Module 3 window allocation)
#
# Key Principle: Different RT bins SHOULD have different precursor counts
# This reflects the natural precursor density variation across the gradient

library(dplyr)
library(ggplot2)
library(gridExtra)
library(scales)

# ============================================================================
# Core RT Binning Strategies
# ============================================================================

#' Segment RT range by time unit (equal time intervals)
#'
#' Groups precursors into RT bins based on time intervals (e.g., 5-minute bins).
#' This ensures temporal consistency across the gradient.
#' Each bin will have different precursor counts reflecting natural density variation.
#'
#' @param data DIA-NN data frame with RT.Start column
#' @param rt_bin_width_min Time width per bin in minutes (default: 5)
#' @return List with binning results
#' @export
#'
#' @examples
#' # 5-minute bins (default)
#' result <- segment_rt_by_time_unit(data, rt_bin_width_min = 5)
#' # Output: 10-15, 15-20, 20-25, ..., 105-110 min
#'
#' # 3-minute bins for finer temporal resolution
#' result <- segment_rt_by_time_unit(data, rt_bin_width_min = 3)
#' # Output: 10-13, 13-16, 16-19, ..., 107-110 min
segment_rt_by_time_unit <- function(data, rt_bin_width_min = 5) {

  cat(sprintf("\n=== Time-Based RT Binning (bin_width=%.1f min) ===\n", rt_bin_width_min))

  # Validate input
  if (rt_bin_width_min <= 0) {
    stop("rt_bin_width_min must be positive")
  }

  if (!"RT.Start" %in% colnames(data)) {
    stop("Data must contain RT.Start column")
  }

  # Calculate RT range
  rt_range <- range(data$RT.Start, na.rm = TRUE)
  rt_min <- rt_range[1]
  rt_max <- rt_range[2]
  total_rt_span <- rt_max - rt_min

  cat(sprintf("RT range: %.2f - %.2f min (span: %.2f min)\n",
              rt_min, rt_max, total_rt_span))

  # Generate time-based breaks
  # Start from rounded minimum (nearest bin_width multiple)
  rt_start_rounded <- floor(rt_min / rt_bin_width_min) * rt_bin_width_min

  rt_breaks <- seq(rt_start_rounded, rt_max + rt_bin_width_min,
                   by = rt_bin_width_min)

  # Filter breaks to actual data range
  rt_breaks <- rt_breaks[rt_breaks >= rt_min]
  rt_breaks <- c(rt_min, rt_breaks[rt_breaks > rt_min])

  # Ensure max RT is included
  if (rt_breaks[length(rt_breaks)] < rt_max) {
    rt_breaks <- c(rt_breaks, rt_max)
  }

  n_bins <- length(rt_breaks) - 1

  cat(sprintf("Generated %d time-based RT bins\n", n_bins))

  # Assign RT bins
  data$rt_bin <- cut(data$RT.Start,
                     breaks = rt_breaks,
                     labels = paste0("Bin", 1:n_bins),
                     include.lowest = TRUE)

  # Calculate bin statistics
  bin_stats <- data %>%
    group_by(rt_bin) %>%
    summarise(
      rt_start = min(RT.Start),
      rt_end = max(RT.Start),
      rt_width = rt_end - rt_start,
      n_precursors = n(),
      density = n() / (rt_end - rt_start),
      mean_mz = mean(Precursor.Mz, na.rm = TRUE),
      .groups = 'drop'
    )

  # Calculate precursor count variation (CV)
  # Note: High CV is EXPECTED and CORRECT for time-based binning
  precursor_cv <- calculate_precursor_cv(bin_stats$n_precursors)

  cat("\nBin statistics:\n")
  print(bin_stats, n = Inf)

  cat(sprintf("\nPrecursor count CV: %.3f (high CV is expected for time-based binning)\n",
              precursor_cv))
  cat("Note: Different bins SHOULD have different precursor counts.\n")
  cat("      This reflects natural density variation across the gradient.\n")
  cat("      Window allocation (Module 3) will equalize density within each bin.\n")

  return(list(
    data = data,
    breaks = rt_breaks,
    stats = bin_stats,
    precursor_cv = precursor_cv,
    method = "time_unit",
    rt_bin_width_min = rt_bin_width_min,
    n_bins = n_bins
  ))
}

#' Segment RT range by explicit breakpoints
#'
#' Groups precursors into RT bins using user-defined time boundaries.
#' Allows custom bin widths for different regions of the gradient.
#'
#' @param data DIA-NN data frame with RT.Start column
#' @param rt_breaks_min Vector of RT breakpoints in minutes
#' @return List with binning results
#' @export
#'
#' @examples
#' # Custom breakpoints for variable-width bins
#' result <- segment_rt_by_time_breaks(data,
#'                                     rt_breaks_min = c(10, 20, 35, 50, 70, 110))
#' # Output bins:
#' #   Bin1: 10-20 min (10 min width)
#' #   Bin2: 20-35 min (15 min width)
#' #   Bin3: 35-50 min (15 min width)
#' #   Bin4: 50-70 min (20 min width)
#' #   Bin5: 70-110 min (40 min width)
segment_rt_by_time_breaks <- function(data, rt_breaks_min) {

  cat(sprintf("\n=== Time-Based RT Binning (explicit breakpoints) ===\n"))

  # Validate input
  if (length(rt_breaks_min) < 2) {
    stop("rt_breaks_min must have at least 2 values (start and end)")
  }

  if (!"RT.Start" %in% colnames(data)) {
    stop("Data must contain RT.Start column")
  }

  # Sort breaks
  rt_breaks_min <- sort(rt_breaks_min)

  # Check for duplicates
  if (any(duplicated(rt_breaks_min))) {
    stop("rt_breaks_min contains duplicate values")
  }

  # Validate against data range
  rt_range <- range(data$RT.Start, na.rm = TRUE)
  rt_min <- rt_range[1]
  rt_max <- rt_range[2]

  if (rt_breaks_min[1] > rt_min) {
    warning(sprintf("First break (%.2f min) > data minimum (%.2f min). Adjusting...",
                   rt_breaks_min[1], rt_min))
    rt_breaks_min[1] <- rt_min
  }

  if (rt_breaks_min[length(rt_breaks_min)] < rt_max) {
    warning(sprintf("Last break (%.2f min) < data maximum (%.2f min). Adjusting...",
                   rt_breaks_min[length(rt_breaks_min)], rt_max))
    rt_breaks_min[length(rt_breaks_min)] <- rt_max
  }

  n_bins <- length(rt_breaks_min) - 1

  cat(sprintf("RT range: %.2f - %.2f min\n", rt_min, rt_max))
  cat(sprintf("Using %d explicit breakpoints → %d bins\n",
              length(rt_breaks_min), n_bins))

  # Print bin widths
  bin_widths <- diff(rt_breaks_min)
  cat("\nBin widths:\n")
  for (i in 1:n_bins) {
    cat(sprintf("  Bin%d: %.2f - %.2f min (%.2f min width)\n",
                i, rt_breaks_min[i], rt_breaks_min[i+1], bin_widths[i]))
  }

  # Assign RT bins
  data$rt_bin <- cut(data$RT.Start,
                     breaks = rt_breaks_min,
                     labels = paste0("Bin", 1:n_bins),
                     include.lowest = TRUE)

  # Calculate bin statistics
  bin_stats <- data %>%
    group_by(rt_bin) %>%
    summarise(
      rt_start = min(RT.Start),
      rt_end = max(RT.Start),
      rt_width = rt_end - rt_start,
      n_precursors = n(),
      density = n() / (rt_end - rt_start),
      mean_mz = mean(Precursor.Mz, na.rm = TRUE),
      .groups = 'drop'
    )

  # Calculate precursor count variation
  precursor_cv <- calculate_precursor_cv(bin_stats$n_precursors)

  cat("\nBin statistics:\n")
  print(bin_stats, n = Inf)

  cat(sprintf("\nPrecursor count CV: %.3f (high CV is expected for custom breakpoints)\n",
              precursor_cv))
  cat("Note: Variable bin widths allow adaptation to gradient characteristics.\n")

  return(list(
    data = data,
    breaks = rt_breaks_min,
    stats = bin_stats,
    precursor_cv = precursor_cv,
    method = "explicit_breaks",
    rt_breaks_min = rt_breaks_min,
    n_bins = n_bins
  ))
}

#' Segment RT range based on precursor density (EXPERIMENTAL)
#'
#' Adaptive RT binning that places more bins in high-density regions.
#' This is an experimental approach for comparison with time-based binning.
#'
#' WARNING: This method aims for balanced precursor counts, which may not
#' provide optimal temporal consistency. Use time-based binning (Module 2)
#' for production workflows.
#'
#' @param data DIA-NN data frame with RT.Start column
#' @param target_n_bins Target number of bins (approximate)
#' @param density_threshold Density threshold for bin splitting (0-1, default: 0.8)
#' @return List with binning results
#' @export
segment_rt_density <- function(data, target_n_bins = 10, density_threshold = 0.8) {

  cat(sprintf("\n=== EXPERIMENTAL: Density-Based RT Binning ===\n"))
  cat("WARNING: This is an experimental method for comparison purposes.\n")
  cat("         Use time-based binning (segment_rt_by_time_unit) for production.\n\n")

  cat(sprintf("Target bins: %d, Density threshold: %.2f\n",
              target_n_bins, density_threshold))

  # Calculate initial uniform breaks as starting point
  rt_range <- range(data$RT.Start, na.rm = TRUE)
  rt_min <- rt_range[1]
  rt_max <- rt_range[2]

  # Calculate density in fine-grained bins
  n_fine_bins <- target_n_bins * 10
  rt_fine_bins <- seq(rt_min, rt_max, length.out = n_fine_bins + 1)

  # Count precursors per fine bin
  fine_counts <- hist(data$RT.Start, breaks = rt_fine_bins, plot = FALSE)$counts

  # Normalize density
  max_count <- max(fine_counts)
  normalized_density <- fine_counts / max_count

  # Adaptive break placement
  adaptive_breaks <- c(rt_min)

  # Calculate cumulative counts for adaptive splitting
  total_precursors <- sum(fine_counts)
  target_per_bin <- total_precursors / target_n_bins

  current_count <- 0
  for (i in seq_along(fine_counts)) {
    current_count <- current_count + fine_counts[i]

    # Create break if accumulated enough precursors AND in low-density region
    if (current_count >= target_per_bin &&
        normalized_density[i] < density_threshold &&
        i < length(fine_counts)) {

      adaptive_breaks <- c(adaptive_breaks, rt_fine_bins[i + 1])
      current_count <- 0
    }
  }

  # Add final break
  adaptive_breaks <- c(adaptive_breaks, rt_max)
  adaptive_breaks <- unique(adaptive_breaks)

  n_bins <- length(adaptive_breaks) - 1

  cat(sprintf("Generated %d bins (target: %d)\n", n_bins, target_n_bins))

  # Assign bins
  data$rt_bin <- cut(data$RT.Start,
                     breaks = adaptive_breaks,
                     labels = paste0("Bin", 1:n_bins),
                     include.lowest = TRUE)

  # Calculate statistics
  bin_stats <- data %>%
    group_by(rt_bin) %>%
    summarise(
      rt_start = min(RT.Start),
      rt_end = max(RT.Start),
      rt_width = rt_end - rt_start,
      n_precursors = n(),
      density = n() / (rt_end - rt_start),
      mean_mz = mean(Precursor.Mz, na.rm = TRUE),
      .groups = 'drop'
    )

  precursor_cv <- calculate_precursor_cv(bin_stats$n_precursors)

  cat("\nBin statistics:\n")
  print(bin_stats, n = Inf)
  cat(sprintf("\nPrecursor count CV: %.3f (lower CV due to density-based balancing)\n",
              precursor_cv))

  return(list(
    data = data,
    breaks = adaptive_breaks,
    stats = bin_stats,
    precursor_cv = precursor_cv,
    method = "density_experimental",
    target_n_bins = target_n_bins,
    density_threshold = density_threshold,
    n_bins = n_bins
  ))
}

# ============================================================================
# Analysis and Utility Functions
# ============================================================================

#' Calculate precursor count coefficient of variation (CV)
#'
#' @param precursor_counts Vector of precursor counts per bin
#' @return CV value
#' @export
calculate_precursor_cv <- function(precursor_counts) {

  if (length(precursor_counts) < 2) {
    return(NA)
  }

  mean_count <- mean(precursor_counts)
  sd_count <- sd(precursor_counts)

  # Coefficient of variation (CV)
  cv <- sd_count / mean_count

  return(cv)
}

#' Analyze RT bin balance
#'
#' Provides detailed analysis of precursor distribution across RT bins.
#' For time-based binning, high variation is EXPECTED and reflects natural
#' precursor density patterns.
#'
#' @param binning_result Result from segment_rt_by_time_unit or segment_rt_by_time_breaks
#' @return Data frame with balance analysis
#' @export
analyze_rt_bin_balance <- function(binning_result) {

  stats <- binning_result$stats
  mean_precursors <- mean(stats$n_precursors)

  balance_data <- data.frame(
    rt_bin = stats$rt_bin,
    rt_start = stats$rt_start,
    rt_end = stats$rt_end,
    rt_width = stats$rt_width,
    n_precursors = stats$n_precursors,
    density = stats$density,
    deviation_from_mean = stats$n_precursors - mean_precursors,
    deviation_pct = ((stats$n_precursors - mean_precursors) / mean_precursors) * 100,
    stringsAsFactors = FALSE
  )

  # Add density classification
  density_quantiles <- quantile(balance_data$density, probs = c(0.33, 0.67))
  balance_data$density_class <- cut(balance_data$density,
                                     breaks = c(0, density_quantiles, Inf),
                                     labels = c("Low", "Medium", "High"),
                                     include.lowest = TRUE)

  return(balance_data)
}

#' Compare time-based binning strategies
#'
#' Compares different RT bin widths to help select optimal temporal resolution.
#'
#' @param data DIA-NN data frame
#' @param bin_widths_min Vector of bin widths to compare (in minutes)
#' @return List with comparison results
#' @export
#'
#' @examples
#' # Compare 3-min, 5-min, and 10-min bins
#' comparison <- compare_time_binning_strategies(data,
#'                                               bin_widths_min = c(3, 5, 10))
compare_time_binning_strategies <- function(data, bin_widths_min = c(3, 5, 10)) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   TIME-BASED RT BINNING COMPARISON           ║\n")
  cat("╚═══════════════════════════════════════════════╝\n")

  results <- list()

  for (width in bin_widths_min) {
    cat(sprintf("\n--- Testing bin_width = %.1f min ---\n", width))
    results[[paste0("width_", width)]] <- segment_rt_by_time_unit(data, width)
  }

  # Create comparison summary
  summary_data <- data.frame(
    bin_width_min = numeric(),
    n_bins = integer(),
    precursor_cv = numeric(),
    min_precursors = integer(),
    max_precursors = integer(),
    mean_precursors = numeric(),
    sd_precursors = numeric(),
    min_bin_width = numeric(),
    max_bin_width = numeric(),
    stringsAsFactors = FALSE
  )

  for (result_name in names(results)) {
    result <- results[[result_name]]
    stats <- result$stats

    summary_data <- rbind(summary_data, data.frame(
      bin_width_min = result$rt_bin_width_min,
      n_bins = result$n_bins,
      precursor_cv = result$precursor_cv,
      min_precursors = min(stats$n_precursors),
      max_precursors = max(stats$n_precursors),
      mean_precursors = mean(stats$n_precursors),
      sd_precursors = sd(stats$n_precursors),
      min_bin_width = min(stats$rt_width),
      max_bin_width = max(stats$rt_width),
      stringsAsFactors = FALSE
    ))
  }

  cat("\n=== COMPARISON SUMMARY ===\n")
  print(summary_data)

  cat("\n📊 Interpretation:\n")
  cat("  - Smaller bin width → finer temporal resolution, more bins\n")
  cat("  - Larger bin width → coarser resolution, fewer bins\n")
  cat("  - High precursor CV is EXPECTED (reflects natural density variation)\n")
  cat("  - Select bin width based on gradient characteristics and instrument cycle time\n")

  return(list(
    results = results,
    summary = summary_data
  ))
}

# ============================================================================
# Visualization Functions
# ============================================================================

#' Visualize RT binning results
#'
#' Creates comprehensive visualization of RT bin distribution and statistics.
#'
#' @param binning_result Result from segment_rt_by_time_unit or segment_rt_by_time_breaks
#' @param save_plot Whether to save plot (default: FALSE)
#' @param plot_dir Directory for saving plots
#' @return ggplot object
#' @export
visualize_rt_binning <- function(binning_result,
                                 save_plot = FALSE,
                                 plot_dir = "plots") {

  stats <- binning_result$stats

  # Create multi-panel plot
  p1 <- plot_precursor_count_per_bin(stats, binning_result$method)
  p2 <- plot_rt_bin_widths(stats, binning_result$method)
  p3 <- plot_precursor_density_per_bin(stats, binning_result$method)
  p4 <- plot_rt_coverage(stats, binning_result$method)

  combined_plot <- gridExtra::grid.arrange(p1, p2, p3, p4, nrow = 2, ncol = 2)

  if (save_plot) {
    if (!dir.exists(plot_dir)) {
      dir.create(plot_dir, recursive = TRUE)
    }

    filename <- file.path(plot_dir, sprintf("rt_binning_%s.png", binning_result$method))
    ggsave(filename, combined_plot, width = 14, height = 10, dpi = 300)
    cat(sprintf("Saved: %s\n", filename))
  }

  return(combined_plot)
}

#' Plot precursor count per RT bin
#' @param stats Bin statistics data frame
#' @param method Binning method name
#' @return ggplot object
#' @export
plot_precursor_count_per_bin <- function(stats, method) {

  p <- ggplot(stats, aes(x = rt_bin, y = n_precursors, fill = n_precursors)) +
    geom_bar(stat = "identity", alpha = 0.8, color = "black", size = 0.3) +
    geom_text(aes(label = format(n_precursors, big.mark = ",")),
              vjust = -0.5, size = 3) +
    scale_fill_viridis_c(option = "plasma", name = "Precursors") +
    labs(
      title = "Precursor Count per RT Bin",
      subtitle = sprintf("Method: %s | High variation is EXPECTED", method),
      x = "RT Bin",
      y = "Number of Precursors"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 9),
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "right"
    ) +
    scale_y_continuous(labels = comma)

  return(p)
}

#' Plot RT bin widths
#' @param stats Bin statistics data frame
#' @param method Binning method name
#' @return ggplot object
#' @export
plot_rt_bin_widths <- function(stats, method) {

  p <- ggplot(stats, aes(x = rt_bin, y = rt_width, fill = rt_width)) +
    geom_bar(stat = "identity", alpha = 0.8, color = "black", size = 0.3) +
    geom_text(aes(label = sprintf("%.1f", rt_width)),
              vjust = -0.5, size = 3) +
    scale_fill_viridis_c(option = "viridis", name = "Width (min)") +
    labs(
      title = "RT Bin Width Distribution",
      subtitle = sprintf("Method: %s | Temporal resolution", method),
      x = "RT Bin",
      y = "Bin Width (minutes)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 9),
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "right"
    )

  return(p)
}

#' Plot precursor density per RT bin
#' @param stats Bin statistics data frame
#' @param method Binning method name
#' @return ggplot object
#' @export
plot_precursor_density_per_bin <- function(stats, method) {

  p <- ggplot(stats, aes(x = rt_bin, y = density, fill = density)) +
    geom_bar(stat = "identity", alpha = 0.8, color = "black", size = 0.3) +
    geom_text(aes(label = sprintf("%.0f", density)),
              vjust = -0.5, size = 3) +
    scale_fill_viridis_c(option = "magma", name = "Density") +
    labs(
      title = "Precursor Density per RT Bin",
      subtitle = sprintf("Method: %s | Precursors per minute", method),
      x = "RT Bin",
      y = "Density (precursors/min)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 9),
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "right"
    )

  return(p)
}

#' Plot RT coverage visualization
#' @param stats Bin statistics data frame
#' @param method Binning method name
#' @return ggplot object
#' @export
plot_rt_coverage <- function(stats, method) {

  p <- ggplot(stats, aes(xmin = rt_start, xmax = rt_end,
                         ymin = 0, ymax = 1, fill = n_precursors)) +
    geom_rect(alpha = 0.8, color = "black", size = 0.5) +
    geom_text(aes(x = (rt_start + rt_end) / 2, y = 0.5,
                  label = as.character(rt_bin)),
              size = 3, fontface = "bold") +
    scale_fill_viridis_c(option = "plasma", name = "Precursors", labels = comma) +
    labs(
      title = "RT Coverage and Bin Boundaries",
      subtitle = sprintf("Method: %s | Temporal segmentation", method),
      x = "Retention Time (min)",
      y = ""
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 9),
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank()
    )

  return(p)
}

cat("✅ Module 2 (RT Segmentation) loaded successfully\n")
cat("   Available functions:\n")
cat("   - segment_rt_by_time_unit(data, rt_bin_width_min = 5)\n")
cat("   - segment_rt_by_time_breaks(data, rt_breaks_min)\n")
cat("   - segment_rt_density(data, target_n_bins, density_threshold) [experimental]\n")
cat("   - analyze_rt_bin_balance(binning_result)\n")
cat("   - compare_time_binning_strategies(data, bin_widths_min)\n")
cat("   - visualize_rt_binning(binning_result)\n")
