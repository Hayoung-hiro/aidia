# rt_segmentation.R - RT Segmentation Strategies for DIA Window Optimization
#
# This module provides multiple RT segmentation strategies:
# - Uniform: Equal time intervals (existing functionality)
# - Density-based: Adaptive segmentation based on precursor density
# - Quantile-based: Equal precursor count per segment
#
# Includes comparison framework and balance scoring

library(dplyr)
library(ggplot2)
library(gridExtra)
library(scales)

# ============================================================================
# Core RT Segmentation Strategies
# ============================================================================

#' Segment RT range uniformly (equal time intervals)
#'
#' @param data DIA-NN data frame with RT.Start column
#' @param n_segments Number of RT segments to create
#' @return List with segmentation results
#' @export
segment_rt_uniform <- function(data, n_segments = 5) {

  cat(sprintf("\n=== Uniform RT Segmentation (n=%d) ===\n", n_segments))

  rt_range <- range(data$RT.Start, na.rm = TRUE)
  rt_breaks <- seq(rt_range[1], rt_range[2], length.out = n_segments + 1)

  # Assign segments
  data$rt_segment <- cut(data$RT.Start,
                         breaks = rt_breaks,
                         labels = paste0("Seg", 1:n_segments),
                         include.lowest = TRUE)

  # Calculate segment statistics
  segment_stats <- data %>%
    group_by(rt_segment) %>%
    summarise(
      rt_start = min(RT.Start),
      rt_end = max(RT.Start),
      rt_width = rt_end - rt_start,
      n_precursors = n(),
      density = n() / (rt_end - rt_start),
      mean_mz = mean(Precursor.Mz, na.rm = TRUE),
      .groups = 'drop'
    )

  # Calculate balance score (coefficient of variation)
  balance_score <- calculate_balance_score(segment_stats$n_precursors)

  cat("Segment statistics:\n")
  print(segment_stats)
  cat(sprintf("\nBalance score (CV): %.3f\n", balance_score))

  return(list(
    data = data,
    breaks = rt_breaks,
    stats = segment_stats,
    balance_score = balance_score,
    method = "uniform",
    n_segments = n_segments
  ))
}

#' Segment RT range based on precursor density (adaptive)
#'
#' @param data DIA-NN data frame with RT.Start column
#' @param n_segments Target number of segments (approximate)
#' @param density_threshold Density threshold for segment splitting (0-1, default: 0.8)
#' @return List with segmentation results
#' @export
segment_rt_density <- function(data, n_segments = 5, density_threshold = 0.8) {

  cat(sprintf("\n=== Density-Based RT Segmentation (target n=%d, threshold=%.2f) ===\n",
              n_segments, density_threshold))

  # Calculate initial uniform breaks as starting point
  rt_range <- range(data$RT.Start, na.rm = TRUE)
  initial_breaks <- seq(rt_range[1], rt_range[2], length.out = n_segments + 1)

  # Calculate density in bins
  n_bins <- n_segments * 10  # Fine-grained binning for density calculation
  rt_bins <- seq(rt_range[1], rt_range[2], length.out = n_bins + 1)

  # Count precursors per bin
  bin_counts <- hist(data$RT.Start, breaks = rt_bins, plot = FALSE)$counts

  # Normalize density
  max_count <- max(bin_counts)
  normalized_density <- bin_counts / max_count

  # Identify high-density regions (above threshold)
  high_density_bins <- which(normalized_density >= density_threshold)

  # Adaptive break placement
  # More breaks in high-density regions, fewer in low-density regions
  adaptive_breaks <- c(rt_range[1])  # Start with min RT

  # Calculate cumulative precursor counts for adaptive splitting
  cumulative_counts <- cumsum(bin_counts)
  total_precursors <- sum(bin_counts)

  # Target precursors per segment (approximately equal)
  target_per_segment <- total_precursors / n_segments

  current_count <- 0
  for (i in seq_along(bin_counts)) {
    current_count <- current_count + bin_counts[i]

    # Check if we should create a break here
    # Break conditions:
    # 1. Accumulated enough precursors
    # 2. In a low-density region (to avoid splitting high-density peaks)
    # 3. Not the last bin
    if (current_count >= target_per_segment &&
        normalized_density[i] < density_threshold &&
        i < length(bin_counts)) {

      adaptive_breaks <- c(adaptive_breaks, rt_bins[i + 1])
      current_count <- 0
    }
  }

  # Add final break
  adaptive_breaks <- c(adaptive_breaks, rt_range[2])

  # Remove duplicate breaks and ensure reasonable number of segments
  adaptive_breaks <- unique(adaptive_breaks)

  actual_n_segments <- length(adaptive_breaks) - 1

  cat(sprintf("Generated %d segments (target: %d)\n", actual_n_segments, n_segments))

  # Assign segments
  data$rt_segment <- cut(data$RT.Start,
                         breaks = adaptive_breaks,
                         labels = paste0("Seg", 1:actual_n_segments),
                         include.lowest = TRUE)

  # Calculate segment statistics
  segment_stats <- data %>%
    group_by(rt_segment) %>%
    summarise(
      rt_start = min(RT.Start),
      rt_end = max(RT.Start),
      rt_width = rt_end - rt_start,
      n_precursors = n(),
      density = n() / (rt_end - rt_start),
      mean_mz = mean(Precursor.Mz, na.rm = TRUE),
      .groups = 'drop'
    )

  # Calculate balance score
  balance_score <- calculate_balance_score(segment_stats$n_precursors)

  cat("Segment statistics:\n")
  print(segment_stats)
  cat(sprintf("\nBalance score (CV): %.3f\n", balance_score))

  return(list(
    data = data,
    breaks = adaptive_breaks,
    stats = segment_stats,
    balance_score = balance_score,
    method = "density",
    n_segments = actual_n_segments,
    density_threshold = density_threshold
  ))
}

#' Segment RT range based on quantiles (equal precursor count)
#'
#' @param data DIA-NN data frame with RT.Start column
#' @param n_segments Number of RT segments to create
#' @return List with segmentation results
#' @export
segment_rt_quantile <- function(data, n_segments = 5) {

  cat(sprintf("\n=== Quantile-Based RT Segmentation (n=%d) ===\n", n_segments))

  # Calculate quantile breaks
  quantile_probs <- seq(0, 1, length.out = n_segments + 1)
  rt_breaks <- quantile(data$RT.Start, probs = quantile_probs, na.rm = TRUE)

  # Ensure unique breaks (in case of tied quantiles)
  rt_breaks <- unique(rt_breaks)

  if (length(rt_breaks) < n_segments + 1) {
    warning(sprintf("Only %d unique breaks generated (expected %d). Data may have many tied RT values.",
                   length(rt_breaks), n_segments + 1))
  }

  actual_n_segments <- length(rt_breaks) - 1

  # Assign segments
  data$rt_segment <- cut(data$RT.Start,
                         breaks = rt_breaks,
                         labels = paste0("Seg", 1:actual_n_segments),
                         include.lowest = TRUE)

  # Calculate segment statistics
  segment_stats <- data %>%
    group_by(rt_segment) %>%
    summarise(
      rt_start = min(RT.Start),
      rt_end = max(RT.Start),
      rt_width = rt_end - rt_start,
      n_precursors = n(),
      density = n() / (rt_end - rt_start),
      mean_mz = mean(Precursor.Mz, na.rm = TRUE),
      .groups = 'drop'
    )

  # Calculate balance score
  balance_score <- calculate_balance_score(segment_stats$n_precursors)

  cat("Segment statistics:\n")
  print(segment_stats)
  cat(sprintf("\nBalance score (CV): %.3f\n", balance_score))

  return(list(
    data = data,
    breaks = rt_breaks,
    stats = segment_stats,
    balance_score = balance_score,
    method = "quantile",
    n_segments = actual_n_segments
  ))
}

# ============================================================================
# Comparison and Analysis Functions
# ============================================================================

#' Compare multiple RT segmentation strategies
#'
#' @param data DIA-NN data frame
#' @param n_segments Number of segments for each strategy
#' @param strategies Vector of strategies to compare (default: all)
#' @param density_threshold Density threshold for density-based method
#' @return List with comparison results
#' @export
compare_segmentation_strategies <- function(data,
                                           n_segments = 5,
                                           strategies = c("uniform", "density", "quantile"),
                                           density_threshold = 0.8) {

  cat("\n╔════════════════════════════════════════════╗\n")
  cat("║   RT SEGMENTATION STRATEGY COMPARISON     ║\n")
  cat("╚════════════════════════════════════════════╝\n")

  results <- list()

  # Run each strategy
  if ("uniform" %in% strategies) {
    results$uniform <- segment_rt_uniform(data, n_segments)
  }

  if ("density" %in% strategies) {
    results$density <- segment_rt_density(data, n_segments, density_threshold)
  }

  if ("quantile" %in% strategies) {
    results$quantile <- segment_rt_quantile(data, n_segments)
  }

  # Create comparison summary
  summary_data <- data.frame(
    strategy = character(),
    n_segments = integer(),
    balance_score = numeric(),
    min_precursors = integer(),
    max_precursors = integer(),
    mean_precursors = numeric(),
    sd_precursors = numeric(),
    cv_precursors = numeric(),
    stringsAsFactors = FALSE
  )

  for (strategy_name in names(results)) {
    result <- results[[strategy_name]]
    stats <- result$stats

    summary_data <- rbind(summary_data, data.frame(
      strategy = strategy_name,
      n_segments = result$n_segments,
      balance_score = result$balance_score,
      min_precursors = min(stats$n_precursors),
      max_precursors = max(stats$n_precursors),
      mean_precursors = mean(stats$n_precursors),
      sd_precursors = sd(stats$n_precursors),
      cv_precursors = sd(stats$n_precursors) / mean(stats$n_precursors),
      stringsAsFactors = FALSE
    ))
  }

  # Print comparison
  cat("\n=== COMPARISON SUMMARY ===\n")
  print(summary_data)

  # Identify best strategy (lowest balance score = most balanced)
  best_idx <- which.min(summary_data$balance_score)
  best_strategy <- summary_data$strategy[best_idx]

  cat(sprintf("\n✅ Best balanced strategy: %s (balance score: %.3f)\n",
              best_strategy,
              summary_data$balance_score[best_idx]))

  return(list(
    results = results,
    summary = summary_data,
    best_strategy = best_strategy
  ))
}

#' Calculate balance score (coefficient of variation)
#'
#' @param precursor_counts Vector of precursor counts per segment
#' @return Balance score (CV)
#' @export
calculate_balance_score <- function(precursor_counts) {

  if (length(precursor_counts) < 2) {
    return(NA)
  }

  mean_count <- mean(precursor_counts)
  sd_count <- sd(precursor_counts)

  # Coefficient of variation (CV)
  cv <- sd_count / mean_count

  return(cv)
}

#' Analyze segment balance across strategies
#'
#' @param comparison_result Result from compare_segmentation_strategies
#' @return Balance analysis data frame
#' @export
analyze_segment_balance <- function(comparison_result) {

  balance_data <- data.frame(
    strategy = character(),
    segment = character(),
    n_precursors = integer(),
    deviation_from_mean = numeric(),
    deviation_pct = numeric(),
    stringsAsFactors = FALSE
  )

  for (strategy_name in names(comparison_result$results)) {
    result <- comparison_result$results[[strategy_name]]
    stats <- result$stats

    mean_precursors <- mean(stats$n_precursors)

    for (i in 1:nrow(stats)) {
      balance_data <- rbind(balance_data, data.frame(
        strategy = strategy_name,
        segment = as.character(stats$rt_segment[i]),
        n_precursors = stats$n_precursors[i],
        deviation_from_mean = stats$n_precursors[i] - mean_precursors,
        deviation_pct = ((stats$n_precursors[i] - mean_precursors) / mean_precursors) * 100,
        stringsAsFactors = FALSE
      ))
    }
  }

  return(balance_data)
}

# ============================================================================
# Visualization Functions
# ============================================================================

#' Visualize RT segmentation comparison
#'
#' @param comparison_result Result from compare_segmentation_strategies
#' @param save_plots Whether to save plots (default: FALSE)
#' @param plot_dir Directory for saving plots
#' @return List of ggplot objects
#' @export
visualize_segmentation_comparison <- function(comparison_result,
                                             save_plots = FALSE,
                                             plot_dir = "plots") {

  plots <- list()

  # Plot 1: Precursor count distribution by strategy
  plots$precursor_distribution <- plot_precursor_distribution_by_strategy(comparison_result)

  # Plot 2: Balance score comparison
  plots$balance_comparison <- plot_balance_score_comparison(comparison_result)

  # Plot 3: Segment size distribution
  plots$segment_sizes <- plot_segment_size_distribution(comparison_result)

  # Plot 4: RT coverage visualization
  plots$rt_coverage <- plot_rt_coverage_comparison(comparison_result)

  # Save plots if requested
  if (save_plots) {
    if (!dir.exists(plot_dir)) {
      dir.create(plot_dir, recursive = TRUE)
    }

    for (plot_name in names(plots)) {
      filename <- file.path(plot_dir, paste0("rt_seg_", plot_name, ".png"))
      ggsave(filename, plots[[plot_name]], width = 12, height = 8, dpi = 300)
      cat(sprintf("Saved: %s\n", filename))
    }
  }

  return(plots)
}

#' Plot precursor distribution by segmentation strategy
#'
#' @param comparison_result Result from compare_segmentation_strategies
#' @return ggplot object
#' @export
plot_precursor_distribution_by_strategy <- function(comparison_result) {

  # Prepare data for plotting
  plot_data <- data.frame(
    strategy = character(),
    segment = character(),
    n_precursors = integer(),
    stringsAsFactors = FALSE
  )

  for (strategy_name in names(comparison_result$results)) {
    result <- comparison_result$results[[strategy_name]]
    stats <- result$stats

    for (i in 1:nrow(stats)) {
      plot_data <- rbind(plot_data, data.frame(
        strategy = strategy_name,
        segment = paste0("Seg", i),
        n_precursors = stats$n_precursors[i],
        stringsAsFactors = FALSE
      ))
    }
  }

  # Create plot
  p <- ggplot(plot_data, aes(x = segment, y = n_precursors, fill = strategy)) +
    geom_bar(stat = "identity", position = "dodge", alpha = 0.8, color = "black", size = 0.3) +
    geom_text(aes(label = format(n_precursors, big.mark = ",")),
              position = position_dodge(width = 0.9),
              vjust = -0.5, size = 3) +
    scale_fill_brewer(palette = "Set2", name = "Strategy") +
    labs(
      title = "Precursor Distribution by RT Segmentation Strategy",
      subtitle = "Comparison of precursor counts across segments",
      x = "Segment",
      y = "Number of Precursors"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "bottom"
    ) +
    scale_y_continuous(labels = comma)

  return(p)
}

#' Plot balance score comparison
#'
#' @param comparison_result Result from compare_segmentation_strategies
#' @return ggplot object
#' @export
plot_balance_score_comparison <- function(comparison_result) {

  summary_data <- comparison_result$summary

  p <- ggplot(summary_data, aes(x = strategy, y = balance_score, fill = strategy)) +
    geom_bar(stat = "identity", alpha = 0.8, color = "black", size = 0.5) +
    geom_text(aes(label = sprintf("%.3f", balance_score)),
              vjust = -0.5, size = 5, fontface = "bold") +
    geom_hline(yintercept = 0.1, color = "green", linetype = "dashed", size = 0.8) +
    geom_hline(yintercept = 0.3, color = "orange", linetype = "dashed", size = 0.8) +
    annotate("text", x = 0.5, y = 0.1, label = "Excellent (< 0.1)",
             hjust = 0, vjust = -0.5, color = "darkgreen", size = 3) +
    annotate("text", x = 0.5, y = 0.3, label = "Good (< 0.3)",
             hjust = 0, vjust = -0.5, color = "darkorange", size = 3) +
    scale_fill_brewer(palette = "Set1", name = "Strategy") +
    labs(
      title = "Segment Balance Score Comparison",
      subtitle = "Lower score = better balance (Coefficient of Variation)",
      x = "Segmentation Strategy",
      y = "Balance Score (CV)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      legend.position = "none"
    )

  return(p)
}

#' Plot segment size distribution
#'
#' @param comparison_result Result from compare_segmentation_strategies
#' @return ggplot object
#' @export
plot_segment_size_distribution <- function(comparison_result) {

  # Prepare data
  plot_data <- data.frame(
    strategy = character(),
    segment = character(),
    rt_width = numeric(),
    stringsAsFactors = FALSE
  )

  for (strategy_name in names(comparison_result$results)) {
    result <- comparison_result$results[[strategy_name]]
    stats <- result$stats

    for (i in 1:nrow(stats)) {
      plot_data <- rbind(plot_data, data.frame(
        strategy = strategy_name,
        segment = paste0("Seg", i),
        rt_width = stats$rt_width[i],
        stringsAsFactors = FALSE
      ))
    }
  }

  p <- ggplot(plot_data, aes(x = segment, y = rt_width, fill = strategy)) +
    geom_bar(stat = "identity", position = "dodge", alpha = 0.8, color = "black", size = 0.3) +
    geom_text(aes(label = sprintf("%.1f min", rt_width)),
              position = position_dodge(width = 0.9),
              vjust = -0.5, size = 3) +
    scale_fill_brewer(palette = "Set2", name = "Strategy") +
    labs(
      title = "RT Segment Width Distribution",
      subtitle = "Time width of each segment by strategy",
      x = "Segment",
      y = "RT Width (minutes)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "bottom"
    )

  return(p)
}

#' Plot RT coverage comparison
#'
#' @param comparison_result Result from compare_segmentation_strategies
#' @return ggplot object
#' @export
plot_rt_coverage_comparison <- function(comparison_result) {

  # Prepare data for visualization
  plot_data <- data.frame(
    strategy = character(),
    rt_start = numeric(),
    rt_end = numeric(),
    segment = character(),
    n_precursors = integer(),
    stringsAsFactors = FALSE
  )

  for (strategy_name in names(comparison_result$results)) {
    result <- comparison_result$results[[strategy_name]]
    stats <- result$stats

    for (i in 1:nrow(stats)) {
      plot_data <- rbind(plot_data, data.frame(
        strategy = strategy_name,
        rt_start = stats$rt_start[i],
        rt_end = stats$rt_end[i],
        segment = as.character(stats$rt_segment[i]),
        n_precursors = stats$n_precursors[i],
        stringsAsFactors = FALSE
      ))
    }
  }

  p <- ggplot(plot_data, aes(xmin = rt_start, xmax = rt_end,
                             ymin = 0, ymax = 1, fill = n_precursors)) +
    geom_rect(alpha = 0.8, color = "black", size = 0.3) +
    facet_wrap(~ strategy, ncol = 1) +
    scale_fill_viridis_c(name = "Precursors", option = "plasma", labels = comma) +
    labs(
      title = "RT Coverage Comparison by Strategy",
      subtitle = "Segment boundaries and precursor distribution",
      x = "Retention Time (min)",
      y = ""
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      strip.text = element_text(size = 12, face = "bold")
    )

  return(p)
}
