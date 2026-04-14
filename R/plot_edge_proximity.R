# plot_edge_proximity.R
# Plot 17: Window Edge Proximity Analysis
#
# Purpose: Quantify how close precursors are to the nearest window boundary.
#          Precursors near edges (< 1 Da) risk incomplete fragmentation due
#          to quadrupole transmission roll-off.
#
# Functions:
#   - plot_edge_proximity(): Histogram with staggered simulation overlay
#   - plot_edge_proximity_spatial(): RT x m/z scatter colored by edge zone
#
# Dependencies: ggplot2, dplyr


#' Calculate Minimum Distance to Window Boundary for Each Precursor
#'
#' For each precursor, finds its assigned window (by RT + m/z) and computes
#' the minimum distance to either boundary edge.
#'
#' @param precursor_data Data frame with Precursor.Mz and RT.Apex columns
#' @param windows Data frame with mz_start, mz_end, rt_start, rt_end columns
#'
#' @return Numeric vector of minimum edge distances (Da), NA if unassigned
#' @keywords internal
calculate_edge_distances <- function(precursor_data, windows) {

  n_precursors <- nrow(precursor_data)
  edge_dist <- rep(NA_real_, n_precursors)

  # Group windows by RT segment for efficiency
  rt_key <- paste(windows$rt_start, windows$rt_end, sep = "_")
  unique_rt <- unique(data.frame(
    rt_start = windows$rt_start,
    rt_end   = windows$rt_end,
    key      = rt_key,
    stringsAsFactors = FALSE
  ))

  for (r in seq_len(nrow(unique_rt))) {
    # Find precursors in this RT bin
    rt_mask <- precursor_data$RT.Apex >= unique_rt$rt_start[r] &
               precursor_data$RT.Apex <= unique_rt$rt_end[r]
    p_idx <- which(rt_mask)

    if (length(p_idx) == 0) next

    # Windows in this RT bin
    w_idx <- which(rt_key == unique_rt$key[r])
    w_starts <- windows$mz_start[w_idx]
    w_ends   <- windows$mz_end[w_idx]

    for (i in p_idx) {
      mz <- precursor_data$Precursor.Mz[i]
      # Find which window contains this precursor
      in_window <- which(mz >= w_starts & mz < w_ends)

      if (length(in_window) == 0) next

      # Use first matching window (should be unique)
      wi <- in_window[1]
      dist_to_lower <- mz - w_starts[wi]
      dist_to_upper <- w_ends[wi] - mz
      edge_dist[i] <- min(dist_to_lower, dist_to_upper)
    }
  }

  return(edge_dist)
}


#' Plot Window Edge Proximity Distribution
#'
#' Histogram of relative edge distance (0 = boundary, 1 = center) with
#' staggered mode simulation overlay. Shows how staggered boundary shifting
#' reduces the fraction of precursors in the boundary zone.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_edge_proximity <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 17: Window Edge Proximity...\n")

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  # Calculate edge distances (absolute Da)
  edge_dist <- calculate_edge_distances(precursor_data, windows)

  # Remove NAs (unassigned precursors)
  matched <- !is.na(edge_dist)
  edge_dist_clean <- edge_dist[matched]

  if (length(edge_dist_clean) < 2) {
    return(create_insufficient_data_plot(
      title = "Window Edge Proximity",
      message = "Insufficient data\n(no precursors matched to windows)"
    ))
  }

  mean_width <- mean(get_window_widths(windows), na.rm = TRUE)
  half_width <- mean_width / 2

  # Normalize to relative: 0 = boundary, 1 = center
  relative_dist <- pmin(edge_dist_clean / half_width, 1.0)

  # --- Simulate staggered effect ---
  # Shift all boundaries by half window width (cycle 2)
  shifted_windows <- windows
  shifted_windows$mz_start <- shifted_windows$mz_start + half_width
  shifted_windows$mz_end <- shifted_windows$mz_end + half_width
  edge_dist_shifted <- calculate_edge_distances(precursor_data, shifted_windows)

  # Effective: best of two cycles per precursor
  effective_dist <- pmax(edge_dist, edge_dist_shifted, na.rm = TRUE)
  effective_matched <- !is.na(effective_dist)
  effective_clean <- effective_dist[effective_matched]
  effective_rel <- pmin(effective_clean / half_width, 1.0)

  # --- Stats ---
  danger_rel <- 0.25
  pct_danger <- sum(relative_dist < danger_rel) / length(relative_dist) * 100
  pct_center <- sum(relative_dist >= 0.5) / length(relative_dist) * 100
  pct_danger_stag <- sum(effective_rel < danger_rel) / length(effective_rel) * 100
  median_rel <- median(relative_dist)

  median_abs_da <- median(edge_dist_clean, na.rm = TRUE)

  # Combined data frame for legend-mapped density lines
  df_density <- data.frame(
    relative_distance = c(relative_dist, effective_rel),
    mode = factor(
      rep(c("Current", "Staggered (sim.)"), c(length(relative_dist), length(effective_rel))),
      levels = c("Current", "Staggered (sim.)", "Uniform")
    )
  )
  df_current <- data.frame(relative_distance = relative_dist)

  # Uniform reference as a dummy data frame for legend
  df_uniform <- data.frame(
    x = c(0, 1), y = c(1.0, 1.0),
    mode = factor("Uniform", levels = c("Current", "Staggered (sim.)", "Uniform"))
  )

  p <- ggplot() +
    # Boundary zone shading
    annotate("rect", xmin = 0, xmax = danger_rel,
             ymin = -Inf, ymax = Inf,
             fill = aidia_colors$accent, alpha = 0.12) +
    # Center zone shading
    annotate("rect", xmin = 0.5, xmax = 1.0,
             ymin = -Inf, ymax = Inf,
             fill = aidia_colors$success, alpha = 0.08) +
    # Uniform baseline (mapped to legend)
    geom_line(data = df_uniform, aes(x = x, y = y, color = mode, linetype = mode),
              linewidth = 0.5) +
    # Histogram: current only
    geom_histogram(
      data = df_current,
      aes(x = relative_distance, y = after_stat(density)),
      bins = 40, fill = aidia_colors$before, color = "white",
      alpha = 0.5, linewidth = 0.2
    ) +
    # Density lines (mapped to legend)
    geom_density(
      data = df_density,
      aes(x = relative_distance, color = mode, linetype = mode),
      linewidth = 0.8
    ) +
    # Threshold lines
    geom_vline(xintercept = danger_rel, linetype = "dashed",
               color = aidia_colors$accent, linewidth = 0.7) +
    geom_vline(xintercept = 0.5, linetype = "dashed",
               color = aidia_colors$success, linewidth = 0.5) +
    # Median line
    geom_vline(xintercept = median_rel, linetype = "solid",
               color = "gray30", linewidth = 0.6) +
    # Staggered improvement stats (annotation box)
    annotate("label",
             x = 0.97, y = Inf,
             label = sprintf(
               "Boundary: %.0f%% \u2192 %.0f%%\nCenter: %.0f%% \u2192 %.0f%%\nMedian: %.2f \u2192 %.2f",
               pct_danger, pct_danger_stag,
               pct_center, sum(effective_rel >= 0.5) / length(effective_rel) * 100,
               median_rel, median(effective_rel)
             ),
             vjust = 1.2, hjust = 1, size = 3,
             fill = "white", color = "gray40",
             label.padding = unit(0.4, "lines"),
             label.r = unit(0.15, "lines")) +
    # Color + linetype scales (legend)
    scale_color_manual(
      name = NULL,
      values = c("Current" = aidia_colors$before_dark,
                 "Staggered (sim.)" = aidia_colors$success,
                 "Uniform" = "gray50")
    ) +
    scale_linetype_manual(
      name = NULL,
      values = c("Current" = "solid",
                 "Staggered (sim.)" = "dashed",
                 "Uniform" = "dotted")
    ) +
    scale_x_continuous(
      limits = c(0, 1),
      breaks = seq(0, 1, by = 0.25),
      labels = c("0\n(boundary)", "0.25", "0.5", "0.75", "1.0\n(center)"),
      expand = expansion(mult = c(0, 0))
    ) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    labs(
      title = "Window Edge Proximity",
      subtitle = sprintf("%s precursors | Mean width: %.1f Da",
                         format(length(edge_dist_clean), big.mark = ","), mean_width),
      x = "Relative Distance from Nearest Edge (0 = boundary, 1 = center)",
      y = "Density",
      caption = sprintf("Current \u2192 Staggered (simulated, best of two offset cycles) | %s precursors",
                        format(length(edge_dist_clean), big.mark = ","))
    ) +
    theme_aidia() +
    theme(
      panel.grid.minor = element_blank(),
      legend.position = "bottom",
      legend.key.width = unit(1, "cm"),
      legend.text = element_text(size = 9),
      legend.margin = margin(0, 0, 0, 0),
      legend.box.margin = margin(-5, 0, 0, 0)
    )

  return(p)
}


#' Plot Edge Proximity Spatial View (RT x m/z)
#'
#' Scatter plot of precursors on the RT x m/z plane, colored by edge
#' proximity zone. Reveals WHERE boundary-zone precursors concentrate
#' in the gradient and m/z space.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_edge_proximity_spatial <- function(optimized_windows, validated_data) {

  cat("  Generating Edge Proximity Spatial View...\n")

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  edge_dist <- calculate_edge_distances(precursor_data, windows)

  mean_width <- mean(get_window_widths(windows), na.rm = TRUE)
  half_width <- mean_width / 2

  # Build data frame with edge distance category
  matched <- !is.na(edge_dist)
  rel_dist <- pmin(edge_dist[matched] / half_width, 1.0)

  df <- data.frame(
    rt = precursor_data$RT.Apex[matched],
    mz = precursor_data$Precursor.Mz[matched],
    edge_rel = rel_dist,
    zone = cut(rel_dist,
               breaks = c(-Inf, 0.25, 0.5, Inf),
               labels = c("Boundary (<25%)", "Middle (25-50%)", "Center (>50%)"))
  )

  pct_boundary <- sum(df$zone == "Boundary (<25%)") / nrow(df) * 100

  # Sort: center first (background), boundary on top (foreground)
  df <- df[order(-df$edge_rel), ]

  p <- ggplot(df, aes(x = rt, y = mz, color = zone)) +
    geom_point(size = 0.8, alpha = 0.5) +
    scale_color_manual(
      values = c(
        "Boundary (<25%)" = aidia_colors$accent,
        "Middle (25-50%)"  = "gray60",
        "Center (>50%)"    = aidia_colors$success
      ),
      name = "Edge Proximity"
    ) +
    labs(
      title = "Edge Proximity: Spatial Distribution",
      subtitle = sprintf(
        "%s precursors | %.0f%% in boundary zone | Mean width: %.1f Da",
        format(nrow(df), big.mark = ","), pct_boundary, mean_width
      ),
      x = "Retention Time (min)",
      y = "m/z (Da)"
    ) +
    theme_aidia() +
    theme(legend.position = "right")

  return(p)
}
