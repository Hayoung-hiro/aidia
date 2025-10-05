# visualizer.R - Visualization functions for DIA window optimization

library(ggplot2)
library(gridExtra)
library(scales)
library(viridis)

#' Create comprehensive visualization plots
#' 
#' @param data Original DIA-NN data
#' @param optimized_windows Optimized window layout
#' @param rt_segments Number of RT segments used
#' @param instrument_config Instrument configuration
#' @return List of ggplot objects
create_visualization_plots <- function(data, optimized_windows, rt_segments, instrument_config = NULL) {
  
  # Pre-optimization plots
  p1 <- plot_precursor_distribution(data)
  p2 <- plot_rt_segment_distribution(data, rt_segments)
  p3 <- plot_current_dppp_distribution(data, instrument_config)
  
  # Post-optimization plots
  p4 <- plot_window_layout(optimized_windows$windows)
  p5 <- plot_coverage_analysis(data, optimized_windows$windows)
  p6 <- plot_optimization_summary(data, optimized_windows)
  
  return(list(
    pre_optimization = list(p1, p2, p3),
    post_optimization = list(p4, p5, p6)
  ))
}

#' Plot precursor m/z distribution
#' 
#' @param data DIA-NN data
#' @return ggplot object
plot_precursor_distribution <- function(data) {
  
  p <- ggplot(data, aes(x = Precursor.Mz)) +
    geom_histogram(bins = 100, fill = "steelblue", alpha = 0.7, color = "black", size = 0.2) +
    geom_density(aes(y = after_stat(count)), color = "red", size = 1) +
    labs(
      title = "Precursor m/z Distribution",
      subtitle = sprintf("Total: %d precursors", nrow(data)),
      x = "Precursor m/z",
      y = "Count"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11)
    ) +
    scale_x_continuous(breaks = pretty_breaks(n = 10))
  
  return(p)
}

#' Plot RT segment distribution
#' 
#' @param data DIA-NN data
#' @param rt_segments Number of RT segments
#' @return ggplot object
plot_rt_segment_distribution <- function(data, rt_segments) {
  
  # Create RT segments
  rt_breaks <- seq(min(data$RT.Start), max(data$RT.Start), length.out = rt_segments + 1)
  data$rt_segment <- cut(data$RT.Start, breaks = rt_breaks, 
                         labels = 1:rt_segments, include.lowest = TRUE)
  
  # Summarize by segment
  segment_summary <- data %>%
    group_by(rt_segment) %>%
    summarise(
      count = n(),
      mean_mz = mean(Precursor.Mz),
      .groups = 'drop'
    )
  
  p <- ggplot(segment_summary, aes(x = rt_segment, y = count)) +
    geom_bar(stat = "identity", fill = "coral", alpha = 0.7, color = "black") +
    geom_text(aes(label = count), vjust = -0.5, size = 3) +
    labs(
      title = "Precursor Distribution across RT Segments",
      subtitle = sprintf("%d RT segments", rt_segments),
      x = "RT Segment",
      y = "Number of Precursors"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11)
    )
  
  return(p)
}

#' Plot current DPPP distribution
#' 
#' @param data DIA-NN data
#' @param instrument_config Instrument configuration
#' @return ggplot object
plot_current_dppp_distribution <- function(data, instrument_config) {
  
  if (is.null(instrument_config)) {
    # Create a placeholder plot
    p <- ggplot(data.frame(x = 1), aes(x = x)) +
      geom_blank() +
      annotate("text", x = 1, y = 1, 
               label = "DPPP distribution requires instrument configuration",
               size = 5) +
      theme_void()
    return(p)
  }
  
  # Estimate current DPPP based on typical window settings
  typical_windows <- 50  # Typical number of windows
  cycle_time <- calculate_cycle_time(
    typical_windows,
    instrument_config$ms1_time,
    instrument_config$ms2_time,
    instrument_config$cycle_calculation
  )
  
  dppp_values <- sapply(data$FWHM, function(fwhm) {
    calculate_dppp(fwhm, cycle_time, instrument_config$cycle_calculation)
  })
  
  dppp_df <- data.frame(dppp = dppp_values)
  
  p <- ggplot(dppp_df, aes(x = dppp)) +
    geom_histogram(bins = 50, fill = "darkgreen", alpha = 0.7, color = "black", size = 0.2) +
    geom_vline(xintercept = 1.25, color = "red", linetype = "dashed", size = 1) +
    geom_vline(xintercept = mean(dppp_values), color = "blue", linetype = "dashed", size = 1) +
    annotate("text", x = 1.25, y = Inf, label = "Target: 1.25", 
             vjust = 2, hjust = -0.1, color = "red") +
    annotate("text", x = mean(dppp_values), y = Inf, 
             label = sprintf("Mean: %.2f", mean(dppp_values)), 
             vjust = 2, hjust = 1.1, color = "blue") +
    labs(
      title = "Current DPPP Distribution",
      subtitle = sprintf("Based on %d windows", typical_windows),
      x = "DPPP (Data Points Per Peak)",
      y = "Count"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11)
    ) +
    xlim(0, 5)
  
  return(p)
}

#' Plot optimized window layout
#' 
#' @param windows Optimized windows data frame
#' @return ggplot object
plot_window_layout <- function(windows) {
  
  # Prepare data for visualization
  windows$window_id <- 1:nrow(windows)
  
  # Create segments for windows
  window_segments <- data.frame()
  for (i in 1:nrow(windows)) {
    window_segments <- rbind(window_segments, 
      data.frame(
        window_id = windows$window_id[i],
        rt_segment = windows$rt_segment[i],
        x = c(windows$window_start[i], windows$window_end[i], 
              windows$window_end[i], windows$window_start[i]),
        y = c(0, 0, 1, 1)
      )
    )
  }
  
  p <- ggplot(window_segments, aes(x = x, y = window_id, group = window_id)) +
    geom_polygon(aes(fill = factor(rt_segment)), alpha = 0.6, color = "black", size = 0.2) +
    scale_fill_viridis_d(name = "RT Segment", na.value = "gray50") +
    labs(
      title = "Optimized Isolation Window Layout",
      subtitle = sprintf("%d windows", nrow(windows)),
      x = "m/z",
      y = "Window Index"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      legend.position = "right"
    ) +
    scale_x_continuous(breaks = pretty_breaks(n = 10))
  
  return(p)
}

#' Plot coverage analysis
#' 
#' @param data Original data
#' @param windows Optimized windows
#' @return ggplot object
plot_coverage_analysis <- function(data, windows) {
  
  # Calculate coverage for each precursor
  data$covered <- FALSE
  data$n_windows <- 0
  
  for (i in 1:nrow(windows)) {
    in_window <- data$Precursor.Mz >= windows$window_start[i] & 
                 data$Precursor.Mz <= windows$window_end[i]
    data$covered[in_window] <- TRUE
    data$n_windows[in_window] <- data$n_windows[in_window] + 1
  }
  
  coverage_pct <- 100 * sum(data$covered) / nrow(data)
  
  # Create 2D density plot
  p <- ggplot(data, aes(x = Precursor.Mz, y = RT.Start)) +
    geom_point(aes(color = covered), alpha = 0.3, size = 0.5) +
    scale_color_manual(values = c("FALSE" = "red", "TRUE" = "green"),
                      labels = c("Not Covered", "Covered"),
                      name = "Coverage") +
    # Add window boundaries
    geom_vline(data = windows, aes(xintercept = window_start), 
              alpha = 0.2, linetype = "dashed") +
    geom_vline(data = windows, aes(xintercept = window_end), 
              alpha = 0.2, linetype = "dashed") +
    labs(
      title = "Precursor Coverage Analysis",
      subtitle = sprintf("Coverage: %.1f%%", coverage_pct),
      x = "Precursor m/z",
      y = "RT (minutes)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 11),
      legend.position = "bottom"
    )
  
  return(p)
}

#' Plot optimization summary
#' 
#' @param data Original data
#' @param optimization_result Optimization results
#' @return ggplot object
plot_optimization_summary <- function(data, optimization_result) {
  
  # Create summary metrics
  summary_data <- data.frame(
    Metric = c("Total Windows", "Target DPPP", "Achieved DPPP", 
               "Cycle Time (s)", "Scan Rate (Hz)", "Coverage (%)"),
    Value = c(
      optimization_result$n_windows,
      1.25,  # Target DPPP
      round(optimization_result$dppp, 2),
      round(optimization_result$cycle_time, 2),
      round(optimization_result$scan_rate, 1),
      round(optimization_result$validation$coverage_pct, 1)
    )
  )
  
  # Create a table plot
  p <- ggplot(summary_data, aes(x = 1, y = rev(1:nrow(summary_data)))) +
    geom_tile(fill = "white", color = "black") +
    geom_text(aes(label = Metric), x = 0.5, hjust = 0, size = 4) +
    geom_text(aes(label = Value), x = 1.5, hjust = 1, size = 4, fontface = "bold") +
    xlim(0, 2) +
    labs(
      title = "Optimization Summary",
      subtitle = "Key Performance Metrics"
    ) +
    theme_void() +
    theme(
      plot.title = element_text(size = 14, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 11, hjust = 0.5)
    )
  
  return(p)
}

#' Create combined visualization report
#' 
#' @param plots List of plots from create_visualization_plots
#' @param output_file Optional file path to save the plot
#' @return Combined plot
create_combined_report <- function(plots, output_file = NULL) {
  
  # Combine pre-optimization plots
  pre_combined <- arrangeGrob(
    grobs = plots$pre_optimization,
    ncol = 2,
    top = "Pre-Optimization Analysis"
  )
  
  # Combine post-optimization plots
  post_combined <- arrangeGrob(
    grobs = plots$post_optimization,
    ncol = 2,
    top = "Post-Optimization Results"
  )
  
  # Combine all
  final_plot <- arrangeGrob(
    pre_combined,
    post_combined,
    ncol = 1
  )
  
  if (!is.null(output_file)) {
    ggsave(output_file, final_plot, width = 12, height = 16, dpi = 300)
    cat(sprintf("Visualization saved to: %s\n", output_file))
  }

  return(final_plot)
}

# ============================================================================
# Module 3: RT-Dependent Density Visualization
# Visualization functions for 2D density analysis and dynamicDIA integration
# ============================================================================

#' Plot 2D RT × m/z density heatmap
#'
#' Creates a heatmap showing precursor density across retention time and m/z dimensions.
#' Useful for identifying high-density regions and understanding sample complexity.
#'
#' @param density_analysis Output from analyze_rt_dependent_density()
#' @param title Plot title (optional)
#' @param highlight_regions High-density regions to highlight (optional)
#' @return ggplot object
#' @export
plot_density_heatmap_2d <- function(density_analysis,
                                   title = "RT × m/z Precursor Density",
                                   highlight_regions = NULL) {

  # Convert density matrix to long format for ggplot
  density_df <- expand.grid(
    rt = density_analysis$rt_centers,
    mz = density_analysis$mz_centers
  )
  density_df$density <- as.vector(density_analysis$density_matrix)

  # Create base heatmap
  p <- ggplot(density_df, aes(x = mz, y = rt, fill = density)) +
    geom_tile() +
    scale_fill_viridis_c(
      option = "plasma",
      name = "Precursors",
      trans = "log1p",  # Log scale for better visualization
      labels = comma
    ) +
    labs(
      title = title,
      subtitle = sprintf("Total: %d precursors | Max density: %d precursors/bin",
                        density_analysis$statistics$total_precursors,
                        density_analysis$statistics$max_density),
      x = "Precursor m/z",
      y = "Retention Time (min)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "right",
      panel.grid = element_blank()
    ) +
    coord_cartesian(expand = FALSE)

  # Add high-density region overlays if provided
  if (!is.null(highlight_regions) && nrow(highlight_regions$regions) > 0) {
    p <- p + geom_rect(
      data = highlight_regions$regions,
      aes(xmin = mz_min, xmax = mz_max,
          ymin = rt_min, ymax = rt_max),
      inherit.aes = FALSE,
      fill = NA,
      color = "red",
      size = 1,
      linetype = "dashed"
    )
  }

  return(p)
}

#' Plot high-density region overlay
#'
#' Visualizes identified high-density regions with statistics.
#'
#' @param density_analysis Output from analyze_rt_dependent_density()
#' @param high_density_regions Output from identify_high_density_regions()
#' @return ggplot object
#' @export
plot_high_density_regions <- function(density_analysis, high_density_regions) {

  if (nrow(high_density_regions$regions) == 0) {
    # Create empty plot with message
    p <- ggplot() +
      annotate("text", x = 0.5, y = 0.5,
               label = "No high-density regions detected\nat current threshold",
               size = 6, hjust = 0.5) +
      theme_void() +
      labs(title = "High-Density Region Analysis")

    return(p)
  }

  # Create heatmap with region highlights
  p <- plot_density_heatmap_2d(
    density_analysis,
    title = "High-Density Region Identification",
    highlight_regions = high_density_regions
  )

  # Add region labels for top 5 regions
  top_regions <- head(high_density_regions$regions, 5)

  if (nrow(top_regions) > 0) {
    p <- p + geom_text(
      data = top_regions,
      aes(x = (mz_min + mz_max) / 2,
          y = (rt_min + rt_max) / 2,
          label = region_id),
      inherit.aes = FALSE,
      color = "white",
      fontface = "bold",
      size = 4
    )
  }

  # Add threshold information
  p <- p + labs(
    subtitle = sprintf(
      "Threshold: P%.0f (%.1f precursors/bin) | %d regions identified",
      high_density_regions$threshold_percentile * 100,
      high_density_regions$threshold,
      high_density_regions$n_regions
    )
  )

  return(p)
}

#' Plot RT-dependent m/z boundaries (raw vs smoothed)
#'
#' Compares raw and smoothed RT-dependent m/z boundaries to visualize
#' the effect of dynamicDIA smoothing.
#'
#' @param smoothing_result Output from apply_dynamicDIA_smoothing()
#' @param show_delta Display delta (difference) between raw and smoothed (default: TRUE)
#' @return ggplot object
#' @export
plot_rt_dependent_boundaries <- function(smoothing_result, show_delta = TRUE) {

  # Prepare data for plotting
  boundary_df <- data.frame(
    RT = smoothing_result$rt_centers,
    raw_low = smoothing_result$raw_boundaries$mz_low,
    raw_high = smoothing_result$raw_boundaries$mz_high,
    smooth_low = smoothing_result$smoothed_boundaries$mz_low,
    smooth_high = smoothing_result$smoothed_boundaries$mz_high
  )

  # Create main boundary plot
  p <- ggplot(boundary_df, aes(x = RT)) +
    # Raw boundaries (dashed lines)
    geom_line(aes(y = raw_low, color = "Raw (Low)"),
              linetype = "dashed", size = 0.8, alpha = 0.6) +
    geom_line(aes(y = raw_high, color = "Raw (High)"),
              linetype = "dashed", size = 0.8, alpha = 0.6) +
    # Smoothed boundaries (solid lines)
    geom_line(aes(y = smooth_low, color = "Smoothed (Low)"),
              size = 1.2) +
    geom_line(aes(y = smooth_high, color = "Smoothed (High)"),
              size = 1.2) +
    scale_color_manual(
      values = c(
        "Raw (Low)" = "gray60",
        "Raw (High)" = "gray60",
        "Smoothed (Low)" = "dodgerblue",
        "Smoothed (High)" = "firebrick"
      ),
      name = "Boundary Type"
    ) +
    labs(
      title = sprintf("RT-Dependent m/z Boundaries (%s Smoothing)",
                     toupper(smoothing_result$method)),
      subtitle = sprintf("Window size: %d | Mean Δm/z: %.2f Da",
                        smoothing_result$parameters$window_size,
                        mean(c(smoothing_result$smoothing_stats$mean_delta_low,
                              smoothing_result$smoothing_stats$mean_delta_high))),
      x = "Retention Time (min)",
      y = "m/z"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "bottom"
    )

  # Add delta visualization if requested
  if (show_delta) {
    delta_low <- abs(boundary_df$smooth_low - boundary_df$raw_low)
    delta_high <- abs(boundary_df$smooth_high - boundary_df$raw_high)

    # Create inset delta plot
    delta_df <- data.frame(
      RT = rep(boundary_df$RT, 2),
      Delta = c(delta_low, delta_high),
      Boundary = rep(c("Low", "High"), each = nrow(boundary_df))
    )

    p_delta <- ggplot(delta_df, aes(x = RT, y = Delta, color = Boundary)) +
      geom_line(size = 0.8) +
      scale_color_manual(values = c("Low" = "dodgerblue", "High" = "firebrick")) +
      labs(
        title = "Smoothing Effect (Δm/z)",
        x = "RT (min)",
        y = "|Δm/z| (Da)"
      ) +
      theme_minimal() +
      theme(
        plot.title = element_text(size = 10),
        legend.position = "none",
        plot.background = element_rect(fill = "white", color = "black")
      )

    # Combine main plot with delta inset (not implemented in basic ggplot)
    # For now, return main plot only
    # TODO: Use patchwork or gridExtra for inset
  }

  return(p)
}

#' Plot smoothing method comparison
#'
#' Side-by-side comparison of different smoothing methods
#' (Savitzky-Golay, moving average, Gaussian).
#'
#' @param comparison_result Output from compare_smoothing_methods()
#' @return Combined ggplot object (gridExtra)
#' @export
plot_smoothing_comparison <- function(comparison_result) {

  # Create individual plots for each method
  p_savgol <- plot_rt_dependent_boundaries(comparison_result$savgol, show_delta = FALSE) +
    labs(title = "Savitzky-Golay Smoothing")

  p_movav <- plot_rt_dependent_boundaries(comparison_result$movav, show_delta = FALSE) +
    labs(title = "Moving Average Smoothing")

  p_gaussian <- plot_rt_dependent_boundaries(comparison_result$gaussian, show_delta = FALSE) +
    labs(title = "Gaussian Smoothing")

  # Create comparison statistics plot
  comp_df <- comparison_result$comparison
  comp_long <- tidyr::pivot_longer(
    comp_df,
    cols = c(Mean_Delta_Low, Mean_Delta_High),
    names_to = "Boundary",
    values_to = "Mean_Delta"
  ) %>%
    mutate(Boundary = gsub("Mean_Delta_", "", Boundary))

  p_stats <- ggplot(comp_long, aes(x = Method, y = Mean_Delta, fill = Boundary)) +
    geom_bar(stat = "identity", position = "dodge", alpha = 0.7) +
    geom_text(aes(label = sprintf("%.2f", Mean_Delta)),
              position = position_dodge(width = 0.9),
              vjust = -0.5, size = 3) +
    scale_fill_manual(values = c("Low" = "dodgerblue", "High" = "firebrick")) +
    labs(
      title = "Smoothing Effect Comparison",
      subtitle = sprintf("Recommended: %s", comparison_result$recommended_method),
      x = "Smoothing Method",
      y = "Mean |Δm/z| (Da)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 10, color = "darkgreen"),
      legend.position = "bottom",
      axis.text.x = element_text(angle = 15, hjust = 1)
    )

  # Combine all plots
  combined <- gridExtra::grid.arrange(
    p_savgol, p_movav,
    p_gaussian, p_stats,
    ncol = 2,
    top = grid::textGrob("dynamicDIA Smoothing Method Comparison",
                         gp = grid::gpar(fontsize = 16, fontface = "bold"))
  )

  return(combined)
}

#' Plot RT-dependent m/z range width
#'
#' Visualizes how the m/z range width varies across retention time
#' after smoothing. Useful for understanding RT-dependent coverage.
#'
#' @param smoothing_result Output from apply_dynamicDIA_smoothing()
#' @return ggplot object
#' @export
plot_rt_dependent_width <- function(smoothing_result) {

  # Calculate range widths
  width_df <- data.frame(
    RT = smoothing_result$rt_centers,
    raw_width = smoothing_result$raw_boundaries$mz_high -
                smoothing_result$raw_boundaries$mz_low,
    smooth_width = smoothing_result$smoothed_boundaries$mz_high -
                   smoothing_result$smoothed_boundaries$mz_low
  )

  # Calculate width change
  width_df$width_change <- width_df$smooth_width - width_df$raw_width

  # Create plot
  p <- ggplot(width_df, aes(x = RT)) +
    geom_ribbon(aes(ymin = 0, ymax = raw_width),
                fill = "gray70", alpha = 0.4) +
    geom_line(aes(y = smooth_width, color = "Smoothed Width"),
              size = 1.2) +
    geom_line(aes(y = raw_width, color = "Raw Width"),
              linetype = "dashed", size = 0.8) +
    scale_color_manual(
      values = c("Smoothed Width" = "dodgerblue", "Raw Width" = "gray50"),
      name = "m/z Range"
    ) +
    labs(
      title = "RT-Dependent m/z Range Width",
      subtitle = sprintf("Method: %s | Mean width change: %.2f Da",
                        smoothing_result$method,
                        mean(width_df$width_change)),
      x = "Retention Time (min)",
      y = "m/z Range Width (Da)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 10),
      legend.position = "bottom"
    )

  return(p)
}

#' Create comprehensive Module 3 visualization report
#'
#' Generates a multi-panel report with all RT-dependent density
#' and smoothing analysis visualizations.
#'
#' @param density_analysis Output from analyze_rt_dependent_density()
#' @param high_density_regions Output from identify_high_density_regions() (optional)
#' @param smoothing_result Output from apply_dynamicDIA_smoothing() (optional)
#' @param output_file Output PDF file path (optional)
#' @return Grid arrangement of plots
#' @export
create_density_analysis_report <- function(density_analysis,
                                          high_density_regions = NULL,
                                          smoothing_result = NULL,
                                          output_file = NULL) {

  cat("\n=== Creating RT-Dependent Density Analysis Report ===\n")

  plots <- list()

  # Plot 1: Basic 2D density heatmap
  plots[[1]] <- plot_density_heatmap_2d(density_analysis)

  # Plot 2: High-density regions if available
  if (!is.null(high_density_regions)) {
    plots[[2]] <- plot_high_density_regions(density_analysis, high_density_regions)
  }

  # Plot 3: RT-dependent boundaries if smoothing applied
  if (!is.null(smoothing_result)) {
    plots[[3]] <- plot_rt_dependent_boundaries(smoothing_result, show_delta = TRUE)
    plots[[4]] <- plot_rt_dependent_width(smoothing_result)
  }

  # Combine plots
  if (length(plots) > 0) {
    combined <- gridExtra::grid.arrange(
      grobs = plots,
      ncol = 2,
      top = grid::textGrob("RT-Dependent Density Analysis Report",
                           gp = grid::gpar(fontsize = 18, fontface = "bold"))
    )

    # Save if output file specified
    if (!is.null(output_file)) {
      ggplot2::ggsave(
        output_file,
        combined,
        width = 14,
        height = 10 + (length(plots) %/% 2) * 5,
        dpi = 300
      )
      cat(sprintf("✓ Report saved to: %s\n", output_file))
    }

    return(combined)
  } else {
    cat("⚠ No plots generated\n")
    return(NULL)
  }
}