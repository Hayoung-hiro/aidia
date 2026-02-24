# plot_rt_changepoint.R - RT Change Point Validation Plots
#
# Purpose: Visualize adaptive RT binning results with contour density overlay
#          and KS statistic trace for change point diagnostics.
#
# Functions:
#   - plot_rt_changepoint_validation(): 2D density contour + adaptive vs fixed bin boundaries
#   - plot_ks_statistic_trace(): KS statistic across RT with significance markers
#
# Dependencies: ggplot2, viridis, scales


# =============================================================================
# Plot 11: RT Change Point Validation - Contour Density + Bin Boundaries
# =============================================================================

#' RT Change Point Validation: Adaptive vs Fixed Binning
#'
#' 2D density contour plot of precursors in RT x m/z space, overlaid with
#' adaptive bin boundaries (red) and fixed-width reference boundaries (gray).
#' Visually demonstrates how adaptive binning aligns with precursor density
#' gradients compared to naive equal-width bins.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimized_windows OptimizedWindows object from Stage 3 (adaptive mode)
#' @param fixed_bin_width Numeric, reference fixed bin width in minutes (default: 5)
#'
#' @return ggplot object
#' @export
plot_rt_changepoint_validation <- function(validated_data,
                                           optimized_windows,
                                           fixed_bin_width = 5) {

  precursor_data <- validated_data$data

  # Use RT.Apex as the single RT reference (computed in Stage 1)
  if (!("RT.Apex" %in% names(precursor_data))) {
    warning("RT.Apex not found in data - cannot generate changepoint plot")
    return(ggplot() + annotate("text", x = 0.5, y = 0.5, label = "RT.Apex column missing") + theme_void())
  }
  rt_col <- precursor_data$RT.Apex
  mz_col <- precursor_data$Precursor.Mz

  # Build plot data frame (drop NAs for clean density estimation)
  plot_df <- data.frame(rt = rt_col, mz = mz_col)
  plot_df <- plot_df[complete.cases(plot_df), ]

  if (nrow(plot_df) < 10) {
    return(
      ggplot() +
        annotate("text", x = 0.5, y = 0.5,
                 label = "Insufficient data for contour plot (< 10 precursors)",
                 size = 5, color = "gray50") +
        theme_void()
    )
  }

  # --- Adaptive bin boundaries ---
  rt_stats <- optimized_windows$rt_binning$rt_stats
  adaptive_boundaries <- sort(unique(c(rt_stats$rt_start, rt_stats$rt_end)))
  n_adaptive <- length(unique(rt_stats$rt_segment_id))

  # --- Fixed bin boundaries for comparison ---
  rt_range <- range(plot_df$rt, na.rm = TRUE)
  fixed_boundaries <- seq(rt_range[1], rt_range[2], by = fixed_bin_width)
  # Ensure the last boundary reaches the end
  if (max(fixed_boundaries) < rt_range[2]) {
    fixed_boundaries <- c(fixed_boundaries, rt_range[2])
  }
  n_fixed <- length(fixed_boundaries) - 1

  # --- Build the plot ---
  p <- ggplot(plot_df, aes(x = rt, y = mz)) +
    # Layer 1: Filled 2D density contour
    stat_density_2d_filled(
      contour_var = "density",
      alpha = 0.85
    ) +
    scale_fill_viridis_d(
      option = "plasma",
      name = "Density",
      guide = guide_legend(reverse = TRUE, ncol = 1)
    ) +
    # Layer 2: Fixed boundaries (gray dashed, behind adaptive)
    geom_vline(
      xintercept = fixed_boundaries,
      linetype = "dashed",
      color = "gray50",
      linewidth = 0.4,
      alpha = 0.7
    ) +
    # Layer 3: Adaptive boundaries (red solid, prominent)
    geom_vline(
      xintercept = adaptive_boundaries,
      linetype = "solid",
      color = "#E74C3C",
      linewidth = 0.7,
      alpha = 0.9
    ) +
    # Labels
    labs(
      title = "RT Change Point Validation: Adaptive vs Fixed Binning",
      subtitle = sprintf("Adaptive: %d bins | Fixed (%g min): %d bins",
                         n_adaptive, fixed_bin_width, n_fixed),
      x = "Retention Time (min)",
      y = "Precursor m/z (Da)",
      caption = "Red solid = adaptive boundaries | Gray dashed = fixed-width reference"
    ) +
    theme_aidia() +
    theme(
      legend.position = "right",
      legend.key.size = unit(0.4, "cm"),
      legend.text = element_text(size = 7)
    )

  return(p)
}

# =============================================================================
# Plot 11B: KS Statistic Trace Across Retention Time
# =============================================================================

#' KS Statistic Trace Across Retention Time
#'
#' Line/point plot showing the Kolmogorov-Smirnov statistic at each pre-bin
#' center along RT. Significant change points (where the m/z distribution
#' changes abruptly) are highlighted in red; detected change point positions
#' are marked with vertical lines.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3 (adaptive mode)
#'
#' @return ggplot object
#' @export
plot_ks_statistic_trace <- function(optimized_windows) {

  # --- Guard: adaptive_info must exist ---
  adaptive_info <- optimized_windows$rt_binning$adaptive_info

  if (is.null(adaptive_info)) {
    return(
      ggplot() +
        annotate("text", x = 0.5, y = 0.5,
                 label = "KS trace only available in adaptive RT binning mode",
                 size = 5, color = "gray50") +
        theme_void()
    )
  }

  ks_stats     <- adaptive_info$ks_statistics
  p_values     <- adaptive_info$p_values
  bin_centers  <- adaptive_info$pre_bin_centers
  change_pts   <- adaptive_info$change_point_positions
  sig_level    <- adaptive_info$significance_level
  if (is.null(sig_level)) sig_level <- 0.05

  # Validate extracted vectors
  if (is.null(ks_stats) || is.null(bin_centers) || length(ks_stats) == 0) {
    return(
      ggplot() +
        annotate("text", x = 0.5, y = 0.5,
                 label = "Adaptive info missing required KS statistics",
                 size = 5, color = "gray50") +
        theme_void()
    )
  }

  # KS stats are computed between adjacent pre-bin pairs, so there are

  # n-1 stats for n bin_centers. Use midpoints of adjacent centers.
  if (length(bin_centers) == length(ks_stats) + 1) {
    ks_rt_centers <- (bin_centers[-length(bin_centers)] + bin_centers[-1]) / 2
  } else {
    ks_rt_centers <- bin_centers[seq_len(length(ks_stats))]
  }

  # Build data frame
  trace_df <- data.frame(
    rt_center = ks_rt_centers,
    ks_stat = ks_stats,
    p_value = if (!is.null(p_values)) p_values else rep(NA_real_, length(ks_stats))
  )
  trace_df$significant <- !is.na(trace_df$p_value) & trace_df$p_value < sig_level

  # Determine a reference line: KS stat at the threshold boundary
  # Use the maximum KS stat among non-significant points as an approximate threshold
  nonsig_ks <- trace_df$ks_stat[!trace_df$significant]
  threshold_line <- if (length(nonsig_ks) > 0) max(nonsig_ks, na.rm = TRUE) else NA_real_

  # --- Build the plot ---
  p <- ggplot(trace_df, aes(x = rt_center, y = ks_stat)) +
    # Layer 1: Line connecting points
    geom_line(color = "gray40", linewidth = 0.5, alpha = 0.6) +
    # Layer 2: Points colored by significance
    geom_point(
      aes(color = significant),
      size = 2.5,
      alpha = 0.85
    ) +
    scale_color_manual(
      values = c("TRUE" = "#E74C3C", "FALSE" = "#95A5A6"),
      labels = c("TRUE" = sprintf("p < %.2f (change point)", sig_level),
                 "FALSE" = "Not significant"),
      name = "Significance"
    )

  # Layer 3: Horizontal threshold reference line
  if (!is.na(threshold_line)) {
    p <- p + geom_hline(
      yintercept = threshold_line,
      linetype = "dashed",
      color = "#F39C12",
      linewidth = 0.6,
      alpha = 0.8
    )
  }

  # Layer 4: Vertical lines at detected change points
  if (!is.null(change_pts) && length(change_pts) > 0) {
    p <- p + geom_vline(
      xintercept = change_pts,
      linetype = "dotted",
      color = "#3498DB",
      linewidth = 0.5,
      alpha = 0.7
    )
  }

  # Labels and theme
  p <- p +
    labs(
      title = "KS Statistic Trace Across Retention Time",
      subtitle = sprintf("Red = significant m/z distribution change (p < %.2f) | %d change points detected",
                         sig_level,
                         if (!is.null(change_pts)) length(change_pts) else 0L),
      x = "Retention Time (min)",
      y = "KS Statistic",
      caption = "Blue dotted = detected change points | Orange dashed = approximate threshold"
    ) +
    theme_aidia() +
    theme(
      legend.position = "bottom"
    )

  return(p)
}

# Module Load Message -------------------------------------------------------

if (!isNamespaceLoaded("aidia")) cat("  [plot_rt_changepoint.R] RT change point validation plots loaded\n")
