# stage4_visualization.R - Stage 4: Visualization & Reporting
#
# Purpose: Generate comprehensive visualizations and reports for DIA window optimization
#
# Version: 2.0 (Updated for 3-stage refactored pipeline)
#
# Main Functions:
#   1. generate_visualizations() - Main orchestration function
#   2. 8 plot functions (plot_dppp_density, plot_rt_window_size, etc.)
#   3. create_pdf_report() - Multi-panel PDF generation
#   4. export_method_file() - Thermo Orbitrap method CSV
#   5. export_individual_plots() - Individual plot export
#
# Input: Refactored pipeline outputs
#   - validated_data (ValidatedData from Stage 1)
#   - optimization_plan (OptimizationPlan from Stage 2)
#   - optimized_windows (OptimizedWindows from Stage 3)
#
# Output: VisualizationResult with plots, reports, and method files

library(ggplot2)
library(dplyr)
library(tidyr)
library(viridis)
library(scales)
library(gridExtra)
library(grid)

# =============================================================================
# Custom Theme
# =============================================================================

#' Custom ggplot2 Theme for DIA Optimizer
#'
#' @export
theme_dia_optimizer <- function() {
  theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11, color = "gray30"),
      plot.caption = element_text(size = 9, color = "gray50", hjust = 0),
      axis.title = element_text(size = 11),
      axis.text = element_text(size = 10),
      legend.title = element_text(face = "bold", size = 10),
      legend.text = element_text(size = 9),
      panel.grid.minor = element_blank()
    )
}

# =============================================================================
# Plot 1: DPPP Density (2D Heatmap)
# =============================================================================

#' Plot DPPP Density Across RT × m/z Space
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_dppp_density <- function(optimization_plan, validated_data) {

  cat("  Generating Plot 1: DPPP Density Heatmap...\n")

  # Extract precursor data with DPPP calculations
  precursor_data <- validated_data$data %>%
    select(RT.Start, Precursor.Mz, FWHM) %>%
    mutate(
      dppp_value = (FWHM * 60 * 1.7) / optimization_plan$actual_cycle_time_sec
    )

  # Bin the data manually for tile plot
  rt_bins <- 40
  mz_bins <- 40

  binned_data <- precursor_data %>%
    mutate(
      rt_bin = cut(RT.Start, breaks = rt_bins, labels = FALSE),
      mz_bin = cut(Precursor.Mz, breaks = mz_bins, labels = FALSE)
    ) %>%
    group_by(rt_bin, mz_bin) %>%
    summarise(
      mean_dppp = mean(dppp_value),
      rt_center = mean(RT.Start),
      mz_center = mean(Precursor.Mz),
      .groups = "drop"
    )

  # Create 2D tile plot
  p <- ggplot(binned_data, aes(x = rt_center, y = mz_center, fill = mean_dppp)) +
    geom_tile() +
    scale_fill_viridis_c(
      option = "magma",
      name = "Mean DPPP",
      limits = c(0, max(binned_data$mean_dppp, na.rm = TRUE))
    ) +
    labs(
      title = "DPPP Distribution Across RT × m/z Space",
      subtitle = sprintf("Target DPPP: %.1f | Current Satisfaction: %.1f%%",
                        optimization_plan$parameters$target_dppp,
                        optimization_plan$diagnosis$current_satisfaction_ratio * 100),
      x = "Retention Time (min)",
      y = "Precursor m/z (Da)",
      caption = "Color intensity = Mean DPPP in each bin"
    ) +
    theme_dia_optimizer()

  return(p)
}

# =============================================================================
# Plot 2: RT Window Size (Bar Plot)
# =============================================================================

#' Plot Window Allocation Across RT Segments
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return ggplot object
#' @export
plot_rt_window_size <- function(optimized_windows) {

  cat("  Generating Plot 2: RT Window Size Distribution...\n")

  # Count windows per RT segment
  rt_summary <- optimized_windows$windows %>%
    group_by(rt_segment_id, rt_start, rt_end) %>%
    summarise(
      n_windows = n(),
      mean_width = mean(window_width),
      .groups = "drop"
    ) %>%
    mutate(rt_midpoint = (rt_start + rt_end) / 2)

  # Plot window count
  p <- ggplot(rt_summary, aes(x = rt_midpoint, y = n_windows)) +
    geom_col(fill = "steelblue", alpha = 0.7, width = 4) +
    geom_text(aes(label = n_windows), vjust = -0.5, size = 3) +
    labs(
      title = "Window Allocation Across RT Segments",
      subtitle = sprintf("Total windows: %d | Mean: %.1f per segment",
                        nrow(optimized_windows$windows),
                        mean(rt_summary$n_windows)),
      x = "Retention Time (min)",
      y = "Number of Windows",
      caption = "Higher bars indicate more windows allocated to that RT region"
    ) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
    theme_dia_optimizer() +
    theme(panel.grid.major.x = element_blank())

  return(p)
}

# =============================================================================
# Plot 3: RT × m/z Density Heatmap
# =============================================================================

#' Plot Precursor Density Distribution
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 50)
#'
#' @return ggplot object
#' @export
plot_rt_mz_density_heatmap <- function(validated_data, bins = 50) {

  cat("  Generating Plot 3: RT × m/z Density Heatmap...\n")

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Start, Precursor.Mz)

  # Create 2D density heatmap
  p <- ggplot(precursor_data, aes(x = RT.Start, y = Precursor.Mz)) +
    stat_density_2d(
      aes(fill = after_stat(density)),
      geom = "raster",
      contour = FALSE,
      n = bins
    ) +
    scale_fill_viridis_c(option = "plasma", name = "Density") +
    labs(
      title = "Precursor Density Distribution",
      subtitle = sprintf("%s precursors analyzed",
                        format(nrow(precursor_data), big.mark = ",")),
      x = "Retention Time (min)",
      y = "Precursor m/z (Da)",
      caption = "Bright regions = high precursor concentration"
    ) +
    theme_dia_optimizer()

  return(p)
}

# =============================================================================
# Plot 4: m/z Normalized Density (Line Plot)
# =============================================================================

#' Plot m/z Density Profiles Across RT Segments
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_mz_normalized_density <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 4: m/z Normalized Density Profiles...\n")

  # Extract RT binning and m/z optimization info from optimized_windows
  n_segments <- optimized_windows$rt_binning$n_bins
  sampled_segments <- seq(1, n_segments, by = max(1, floor(n_segments / 6)))

  # Extract density profiles for sampled segments
  density_profiles <- list()

  # Get precursor data
  precursor_data <- validated_data$data

  # Get mz_ranges from optimized_windows
  if (!is.null(optimized_windows$mz_optimization$mz_ranges)) {
    mz_ranges <- optimized_windows$mz_optimization$mz_ranges
  } else {
    # Fallback: compute from windows directly
    mz_ranges <- optimized_windows$windows %>%
      group_by(rt_segment_id) %>%
      summarise(
        rt_start = min(rt_start),
        rt_end = max(rt_end),
        mz_min = min(mz_start),
        mz_max = max(mz_end),
        .groups = "drop"
      )
  }

  for (i in sampled_segments) {
    # Get RT and m/z range for this segment
    segment_range <- mz_ranges %>%
      filter(rt_segment_id == i)

    if (nrow(segment_range) == 0) next

    # Extract scalar values
    rt_start_val <- as.numeric(segment_range$rt_start[1])
    rt_end_val <- as.numeric(segment_range$rt_end[1])

    # Filter precursors in this RT segment
    segment_data <- precursor_data %>%
      filter(RT.Start >= rt_start_val & RT.Start < rt_end_val)

    if (nrow(segment_data) == 0) next

    # Calculate density
    mz_values <- segment_data$Precursor.Mz
    dens <- density(mz_values, n = 100,
                   from = segment_range$mz_min,
                   to = segment_range$mz_max)

    # Normalize
    normalized_y <- dens$y / max(dens$y)

    density_profiles[[length(density_profiles) + 1]] <- tibble(
      rt_segment = i,
      rt_label = sprintf("RT %.0f-%.0f min",
                        segment_range$rt_start,
                        segment_range$rt_end),
      mz_center = dens$x,
      normalized_density = normalized_y
    )
  }

  if (length(density_profiles) == 0) {
    # Return empty plot if no data
    return(ggplot() +
             labs(title = "m/z Normalized Density (No Data Available)") +
             theme_dia_optimizer())
  }

  density_data <- bind_rows(density_profiles)

  # Plot
  p <- ggplot(density_data, aes(x = mz_center, y = normalized_density,
                                 color = factor(rt_label))) +
    geom_line(linewidth = 1, alpha = 0.8) +
    scale_color_viridis_d(name = "RT Segment", option = "turbo") +
    labs(
      title = "m/z Density Profiles Across RT Segments",
      subtitle = "Normalized to max density per segment (sampled segments shown)",
      x = "Precursor m/z (Da)",
      y = "Normalized Density",
      caption = "Each line shows m/z distribution for one RT segment"
    ) +
    theme_dia_optimizer() +
    theme(legend.position = "right")

  return(p)
}

# =============================================================================
# Plot 5: m/z Window Width (Scatter Plot)
# =============================================================================

#' Plot Window Width Distribution Across m/z Range
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return ggplot object
#' @export
plot_mz_window_width <- function(optimized_windows) {

  cat("  Generating Plot 5: m/z Window Width Profile...\n")

  # Extract window data
  window_data <- optimized_windows$windows %>%
    mutate(rt_midpoint = (rt_start + rt_end) / 2)

  # Calculate statistics
  mean_width <- mean(window_data$window_width)
  sd_width <- sd(window_data$window_width)

  # Plot window width
  p <- ggplot(window_data, aes(x = mz_center, y = window_width,
                                color = rt_midpoint)) +
    geom_point(alpha = 0.6, size = 2) +
    geom_hline(yintercept = mean_width,
               linetype = "dashed", color = "black", linewidth = 0.8) +
    scale_color_viridis_c(name = "RT (min)", option = "viridis") +
    labs(
      title = "Window Width Distribution Across m/z Range",
      subtitle = sprintf("Mean: %.1f Da | SD: %.1f Da | CV: %.3f",
                        mean_width, sd_width, sd_width / mean_width),
      x = "Window Center m/z (Da)",
      y = "Window Width (Da)",
      caption = "Black dashed line = mean width | Color = RT segment"
    ) +
    theme_dia_optimizer()

  return(p)
}

# =============================================================================
# Plot 6: Precursor Coverage Map
# =============================================================================

#' Plot Precursor Coverage Map
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @export
plot_precursor_coverage_map <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 6: Precursor Coverage Map...\n")

  # Sample precursors for visualization (max 5000 points for performance)
  precursor_data <- validated_data$data %>%
    select(RT.Start, Precursor.Mz)

  if (nrow(precursor_data) > 5000) {
    set.seed(42)
    precursor_data <- precursor_data %>% sample_n(5000)
  }

  window_data <- optimized_windows$windows

  # Determine coverage for each precursor
  cat("    Calculating coverage (this may take a moment)...\n")
  precursor_data <- precursor_data %>%
    rowwise() %>%
    mutate(
      is_covered = any(
        window_data$mz_start <= Precursor.Mz &
        window_data$mz_end >= Precursor.Mz &
        window_data$rt_start <= RT.Start &
        window_data$rt_end >= RT.Start
      )
    ) %>%
    ungroup()

  # Calculate coverage stats
  coverage_pct <- mean(precursor_data$is_covered) * 100
  n_covered <- sum(precursor_data$is_covered)
  n_total <- nrow(precursor_data)

  # Plot coverage
  p <- ggplot(precursor_data, aes(x = RT.Start, y = Precursor.Mz,
                                   color = is_covered)) +
    geom_point(alpha = 0.4, size = 0.8) +
    scale_color_manual(
      values = c("TRUE" = "#2ecc71", "FALSE" = "#e74c3c"),
      labels = c("TRUE" = "Covered", "FALSE" = "Not covered"),
      name = "Status"
    ) +
    labs(
      title = "Precursor Coverage Map",
      subtitle = sprintf("Coverage: %.1f%% (%d/%d precursors)",
                        coverage_pct, n_covered, n_total),
      x = "Retention Time (min)",
      y = "Precursor m/z (Da)",
      caption = "Green = covered by windows | Red = not covered (gaps)"
    ) +
    theme_dia_optimizer()

  return(p)
}

# =============================================================================
# Plot 7: Window Efficiency
# =============================================================================

#' Plot Window Efficiency (Precursors per Window)
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return ggplot object
#' @export
plot_window_efficiency <- function(optimized_windows) {

  cat("  Generating Plot 7: Window Efficiency Analysis...\n")

  # Extract window efficiency data
  window_data <- optimized_windows$windows %>%
    arrange(n_precursors) %>%
    mutate(window_rank = row_number())

  # Calculate statistics
  mean_prec <- mean(window_data$n_precursors)
  cv_prec <- sd(window_data$n_precursors) / mean_prec

  # Plot precursors per window
  p <- ggplot(window_data, aes(x = window_rank, y = n_precursors)) +
    geom_col(fill = "coral", alpha = 0.7, width = 1) +
    geom_hline(yintercept = mean_prec,
               linetype = "dashed", color = "blue", linewidth = 1) +
    annotate("text", x = nrow(window_data) * 0.85,
             y = mean_prec * 1.15,
             label = sprintf("Mean: %.1f", mean_prec),
             color = "blue", fontface = "bold", size = 4) +
    labs(
      title = "Window Efficiency: Precursors per Window",
      subtitle = sprintf("CV: %.3f | Range: %d - %d precursors",
                        cv_prec,
                        min(window_data$n_precursors),
                        max(window_data$n_precursors)),
      x = "Window Rank (sorted by precursor count)",
      y = "Number of Precursors",
      caption = "Blue line = mean | Low CV indicates uniform distribution"
    ) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
    theme_dia_optimizer() +
    theme(
      axis.text.x = element_blank(),
      panel.grid.major.x = element_blank()
    )

  return(p)
}

# =============================================================================
# Plot 8: DPPP Achievement Heatmap
# =============================================================================

#' Plot DPPP Achievement Heatmap by Window
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param target_dppp Target DPPP value (default: NULL, uses plan target)
#' @param dppp_tolerance DPPP tolerance (default: 0.5)
#'
#' @return ggplot object
#' @export
plot_dppp_achievement_heatmap <- function(optimization_plan, optimized_windows, validated_data,
                                         target_dppp = NULL, dppp_tolerance = 0.5) {

  cat("  Generating Plot 8: DPPP Achievement Heatmap...\n")

  # Use target from optimization_plan if not provided
  if (is.null(target_dppp)) {
    target_dppp <- optimization_plan$parameters$target_dppp
  }

  # Calculate DPPP for each precursor
  dppp_data <- validated_data$data %>%
    select(RT.Start, Precursor.Mz, FWHM) %>%
    mutate(
      dppp_value = (FWHM * 60 * 1.7) / optimization_plan$actual_cycle_time_sec,
      meets_target = dppp_value >= (target_dppp - dppp_tolerance) &
                     dppp_value <= (target_dppp + dppp_tolerance)
    )

  # Sample for performance
  if (nrow(dppp_data) > 5000) {
    set.seed(42)
    dppp_data <- dppp_data %>% sample_n(5000)
  }

  window_data <- optimized_windows$windows

  # Assign each precursor to a window
  cat("    Assigning precursors to windows...\n")

  # Ensure window_data has proper window_id type
  if (is.character(window_data$window_id)) {
    window_data <- window_data %>%
      mutate(window_id = as.integer(gsub("^window_", "", window_id)))
  }

  dppp_data <- dppp_data %>%
    rowwise() %>%
    mutate(
      window_id = {
        matching_windows <- which(
          window_data$mz_start <= Precursor.Mz &
          window_data$mz_end >= Precursor.Mz &
          window_data$rt_start <= RT.Start &
          window_data$rt_end >= RT.Start
        )
        if (length(matching_windows) > 0) matching_windows[1] else NA_integer_
      }
    ) %>%
    ungroup() %>%
    filter(!is.na(window_id))

  # Calculate mean achievement per window
  window_dppp <- dppp_data %>%
    group_by(window_id) %>%
    summarise(
      mean_dppp = mean(dppp_value),
      achievement_ratio = mean(as.numeric(meets_target)),
      .groups = "drop"
    ) %>%
    left_join(window_data, by = "window_id") %>%
    mutate(
      rt_midpoint = (rt_start + rt_end) / 2
    )

  # Plot heatmap
  p <- ggplot(window_dppp, aes(x = rt_midpoint, y = mz_center,
                                fill = achievement_ratio)) +
    geom_tile() +
    scale_fill_gradient2(
      low = "#e74c3c",
      mid = "#f39c12",
      high = "#2ecc71",
      midpoint = 0.5,
      limits = c(0, 1),
      name = "Target\nAchievement",
      labels = percent_format()
    ) +
    labs(
      title = "DPPP Achievement Heatmap (by Window)",
      subtitle = sprintf("Overall satisfaction: %.1f%% | Target: %.1f ± %.1f",
                        optimization_plan$diagnosis$current_satisfaction_ratio * 100,
                        target_dppp, dppp_tolerance),
      x = "Retention Time (min)",
      y = "Window Center m/z (Da)",
      caption = "Green = meeting target DPPP | Red = not meeting target"
    ) +
    theme_dia_optimizer()

  return(p)
}

# =============================================================================
# Main Visualization Function
# =============================================================================

#' Generate All Visualizations
#'
#' Main orchestration function that generates all 8 plots, PDF report,
#' method file, and individual plot exports.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_dir Character, output directory path
#' @param create_pdf Logical, create comprehensive PDF report
#' @param create_individual_plots Logical, export individual plots
#' @param plot_format Character, "png" or "pdf"
#' @param plot_dpi Numeric, plot resolution (default: 300)
#'
#' @return VisualizationResult object
#' @export
generate_visualizations <- function(
  validated_data,
  optimization_plan,
  optimized_windows,
  output_dir = "output/",
  create_pdf = TRUE,
  create_individual_plots = TRUE,
  plot_format = "png",
  plot_dpi = 300
) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   STAGE 4: Visualization & Reporting         ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  viz_start <- Sys.time()

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  cat("Step 1: Generating 8 required plots...\n")

  # Generate all plots
  plots <- list()

  plots$dppp_density <- plot_dppp_density(optimization_plan, validated_data)
  plots$rt_window_size <- plot_rt_window_size(optimized_windows)
  plots$rt_mz_heatmap <- plot_rt_mz_density_heatmap(validated_data)
  plots$mz_normalized_density <- plot_mz_normalized_density(optimized_windows, validated_data)
  plots$mz_window_width <- plot_mz_window_width(optimized_windows)
  plots$precursor_coverage_map <- plot_precursor_coverage_map(optimized_windows, validated_data)
  plots$window_efficiency <- plot_window_efficiency(optimized_windows)
  plots$dppp_achievement_heatmap <- plot_dppp_achievement_heatmap(
    optimization_plan, optimized_windows, validated_data
  )

  cat(sprintf("✅ All 8 plots generated successfully\n\n"))

  plot_end <- Sys.time()
  plot_time <- as.numeric(difftime(plot_end, viz_start, units = "secs"))

  # Initialize result structure
  report_files <- list()

  # Step 2: Export individual plots (optional)
  if (create_individual_plots) {
    cat("Step 2: Exporting individual plots...\n")
    individual_files <- export_individual_plots(
      plots, output_dir, plot_format, plot_dpi
    )
    report_files$individual_plots <- individual_files
  } else {
    cat("Step 2: Skipping individual plot export\n")
    report_files$individual_plots <- character()
  }

  # Step 3: Create PDF report (optional)
  if (create_pdf) {
    cat("\nStep 3: Creating PDF report...\n")
    pdf_file <- file.path(output_dir, "optimization_report.pdf")
    create_pdf_report(plots, validated_data, optimization_plan, optimized_windows, pdf_file)
    report_files$pdf_report <- pdf_file
  } else {
    cat("\nStep 3: Skipping PDF report creation\n")
    report_files$pdf_report <- NULL
  }

  # Step 4: Export method file (CSV for Thermo)
  cat("\nStep 4: Exporting instrument method file...\n")
  method_file <- file.path(output_dir, "method.csv")
  export_method_file(optimized_windows, method_file)
  report_files$method_file <- method_file

  # Step 5: Calculate summary statistics
  cat("\nStep 5: Calculating summary statistics...\n")
  summary_stats <- calculate_summary_statistics(validated_data, optimization_plan, optimized_windows)

  viz_end <- Sys.time()
  total_time <- as.numeric(difftime(viz_end, viz_start, units = "secs"))

  # Package results
  result <- structure(
    list(
      plots = plots,

      report_files = report_files,

      summary_statistics = summary_stats,

      metadata = list(
        instrument_type = optimization_plan$instrument$preset,
        mz_strategy = optimized_windows$parameters$mz_strategy,
        window_mode = optimized_windows$parameters$window_mode,
        generation_timestamp = viz_start,
        plot_generation_time = plot_time,
        report_generation_time = total_time - plot_time,
        total_time = total_time
      )
    ),
    class = c("VisualizationResult", "list")
  )

  cat("\n═══════════════════════════════════════════════\n")
  cat(" STAGE 4 COMPLETE\n")
  cat("═══════════════════════════════════════════════\n")
  cat(sprintf("✓ Generated: %d plots\n", length(plots)))
  cat(sprintf("✓ Method file: %s\n", basename(method_file)))
  if (!is.null(report_files$pdf_report)) {
    cat(sprintf("✓ PDF report: %s\n", basename(report_files$pdf_report)))
  }
  cat(sprintf("✓ Total time: %.2f seconds\n", total_time))
  cat("\n")

  return(result)
}

# =============================================================================
# Helper Functions
# =============================================================================

#' Export Individual Plots
#'
#' @param plots List of ggplot objects
#' @param output_dir Output directory
#' @param format "png" or "pdf"
#' @param dpi Resolution
#'
#' @return Vector of file paths
#' @export
export_individual_plots <- function(plots, output_dir, format = "png", dpi = 300) {

  plot_names <- c(
    "plot1_dppp_density",
    "plot2_rt_window_size",
    "plot3_rt_mz_heatmap",
    "plot4_mz_normalized_density",
    "plot5_mz_window_width",
    "plot6_precursor_coverage_map",
    "plot7_window_efficiency",
    "plot8_dppp_achievement_heatmap"
  )

  file_paths <- character(length(plots))

  for (i in seq_along(plots)) {
    filename <- paste0(plot_names[i], ".", format)
    filepath <- file.path(output_dir, filename)

    ggsave(
      filepath,
      plot = plots[[i]],
      width = 10,
      height = 7,
      dpi = dpi,
      bg = "white"
    )

    file_paths[i] <- filepath
    cat(sprintf("  ✓ Saved: %s\n", filename))
  }

  return(file_paths)
}

#' Create PDF Report
#'
#' @param plots List of ggplot objects
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_file PDF output path
#'
#' @export
create_pdf_report <- function(plots, validated_data, optimization_plan,
                               optimized_windows, output_file) {

  # Create multi-panel PDF with all plots
  pdf(output_file, width = 16, height = 10)

  # Title page
  grid.newpage()
  grid.text("DIA Window Optimization Report",
            x = 0.5, y = 0.7,
            gp = gpar(fontsize = 24, fontface = "bold"))
  grid.text(sprintf("Generated: %s", Sys.time()),
            x = 0.5, y = 0.4,
            gp = gpar(fontsize = 14))
  grid.text(sprintf("Instrument: %s | Windows: %d | Coverage: %.1f%%",
                   optimization_plan$instrument$preset,
                   nrow(optimized_windows$windows),
                   optimized_windows$statistics$coverage_percentage),
            x = 0.5, y = 0.3,
            gp = gpar(fontsize = 12))

  # Plot pages (2 plots per page)
  plot_pairs <- list(
    c(1, 2), c(3, 4), c(5, 6), c(7, 8)
  )

  for (pair in plot_pairs) {
    grid.newpage()
    grid.arrange(
      plots[[pair[1]]],
      plots[[pair[2]]],
      ncol = 1
    )
  }

  dev.off()

  cat(sprintf("  ✓ PDF report saved: %s\n", basename(output_file)))
}

#' Export Method File
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_file CSV output path
#'
#' @export
export_method_file <- function(optimized_windows, output_file) {

  # Create Thermo Orbitrap method file format
  method_data <- optimized_windows$windows %>%
    select(
      RT_start = rt_start,
      RT_end = rt_end,
      Center_mz = mz_center,
      Window_width = window_width
    ) %>%
    mutate(
      RT_start = round(RT_start, 2),
      RT_end = round(RT_end, 2),
      Center_mz = round(Center_mz, 1),
      Window_width = round(Window_width, 1)
    )

  # Write CSV
  write.csv(method_data, output_file, row.names = FALSE)

  cat(sprintf("  ✓ Method file saved: %s (%d windows)\n",
              basename(output_file), nrow(method_data)))
}

#' Calculate Summary Statistics
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return List of summary statistics
#' @export
calculate_summary_statistics <- function(validated_data, optimization_plan, optimized_windows) {

  windows <- optimized_windows$windows
  window_stats <- optimized_windows$statistics

  list(
    optimization_metrics = list(
      total_windows = nrow(windows),
      window_count_per_rt = optimization_plan$window_count_per_bin,
      mean_window_width_da = mean(windows$window_width),
      precursor_coverage_pct = window_stats$coverage_percentage,
      mean_precursors_per_window = window_stats$mean_precursors_per_window,
      cv_precursors = window_stats$cv_precursors
    ),

    performance_metrics = list(
      cycle_time_sec = optimization_plan$actual_cycle_time_sec,
      scan_rate_hz = 1 / optimization_plan$actual_cycle_time_sec,
      target_dppp = optimization_plan$parameters$target_dppp,
      current_dppp_satisfaction_pct = optimization_plan$diagnosis$current_satisfaction_ratio * 100,
      required_cycle_time_sec = optimization_plan$required_cycle_time_sec
    ),

    instrument_config = list(
      instrument_type = optimization_plan$instrument$preset,
      mz_strategy = optimized_windows$parameters$mz_strategy,
      window_mode = optimized_windows$parameters$window_mode,
      n_precursors = validated_data$metadata$n_precursors,
      rt_range = validated_data$metadata$rt_range,
      mz_range = validated_data$metadata$mz_range
    )
  )
}

cat("✅ Stage 4 (Visualization & Reporting) loaded successfully\n")
cat("   Version: 2.0 (Updated for 3-stage refactored pipeline)\n")
cat("   Main function: generate_visualizations()\n")
cat("   Plot functions: 8 available\n")
cat("   Export functions: create_pdf_report(), export_method_file()\n")
