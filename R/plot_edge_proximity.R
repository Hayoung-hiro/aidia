# plot_edge_proximity.R
# Plot 17: Window Edge Proximity Analysis
#
# Purpose: Quantify how close precursors are to the nearest window boundary.
#          Precursors near edges (< 1 Da) risk incomplete fragmentation due
#          to quadrupole transmission roll-off. This metric directly motivates
#          staggered window designs and helps evaluate boundary effect severity.
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
#' Creates a histogram of relative edge distance (normalized to half-window-width).
#' 0 = at boundary, 1 = at window center. Shows how many precursors are
#' near boundaries and motivates staggered window placement.
#'
#' The danger threshold adapts to window width: min(1.0 Da, mean_width * 0.25).
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
  edge_dist_clean <- edge_dist[!is.na(edge_dist)]

  if (length(edge_dist_clean) < 2) {
    return(create_insufficient_data_plot(
      title = "Window Edge Proximity",
      message = "Insufficient data\n(no precursors matched to windows)"
    ))
  }

  # Calculate mean window width for adaptive threshold
  if ("window_width" %in% names(windows)) {
    mean_width <- mean(windows$window_width, na.rm = TRUE)
  } else {
    mean_width <- mean(windows$mz_end - windows$mz_start, na.rm = TRUE)
  }
  half_width <- mean_width / 2

  # Normalize to relative position: 0 = boundary, 1 = center
  relative_dist <- pmin(edge_dist_clean / half_width, 1.0)

  df <- data.frame(relative_distance = relative_dist)

  # Adaptive danger threshold (relative to window width)
  danger_rel <- 0.25  # Inner 25% from each edge = 50% of window is "danger"
  n_danger <- sum(relative_dist < danger_rel)
  pct_danger <- n_danger / length(relative_dist) * 100
  n_center <- sum(relative_dist >= 0.5)
  pct_center <- n_center / length(relative_dist) * 100
  median_rel <- median(relative_dist)

  # Window mode for staggered recommendation

  window_mode <- optimized_windows$parameters$window_mode %||% "density"

  p <- ggplot(df, aes(x = relative_distance)) +
    # Boundary zone shading (< 25% from edge)
    annotate(
      "rect",
      xmin = 0, xmax = danger_rel,
      ymin = -Inf, ymax = Inf,
      fill = aidia_colors$accent,
      alpha = 0.12
    ) +
    # Center zone shading (> 50% from edge)
    annotate(
      "rect",
      xmin = 0.5, xmax = 1.0,
      ymin = -Inf, ymax = Inf,
      fill = aidia_colors$success,
      alpha = 0.08
    ) +
    # Histogram
    geom_histogram(
      aes(y = after_stat(density)),
      bins = 40,
      fill = aidia_colors$primary,
      color = "white",
      alpha = 0.7,
      linewidth = 0.2
    ) +
    geom_density(
      color = aidia_colors$primary,
      linewidth = 0.8,
      alpha = 0.6
    ) +
    # Danger threshold line
    geom_vline(
      xintercept = danger_rel,
      linetype = "dashed",
      color = aidia_colors$accent,
      linewidth = 0.7
    ) +
    # Center boundary
    geom_vline(
      xintercept = 0.5,
      linetype = "dashed",
      color = aidia_colors$success,
      linewidth = 0.5
    ) +
    # Median line
    geom_vline(
      xintercept = median_rel,
      linetype = "solid",
      color = "gray30",
      linewidth = 0.6
    ) +
    # Zone labels
    annotate(
      "text",
      x = danger_rel / 2, y = Inf,
      label = sprintf("Boundary zone\n%.0f%%", pct_danger),
      vjust = 1.8, size = 3, fontface = "bold",
      color = aidia_colors$accent
    ) +
    annotate(
      "text",
      x = 0.75, y = Inf,
      label = sprintf("Center zone\n%.0f%%", pct_center),
      vjust = 1.8, size = 3, fontface = "bold",
      color = aidia_colors$after_success
    ) +
    annotate(
      "text",
      x = median_rel, y = Inf,
      label = sprintf("Median: %.2f", median_rel),
      vjust = 3.5, hjust = -0.1, size = 3, color = "gray30"
    ) +
    scale_x_continuous(
      limits = c(0, 1),
      breaks = seq(0, 1, by = 0.25),
      labels = c("0\n(boundary)", "0.25", "0.5", "0.75", "1.0\n(center)"),
      expand = expansion(mult = c(0, 0))
    ) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    labs(
      title = "Window Edge Proximity (Relative)",
      subtitle = sprintf(
        "Mean window width: %.1f Da | %.0f%% of precursors in boundary zone (<25%% from edge)",
        mean_width, pct_danger
      ),
      x = "Relative Distance from Nearest Edge (0 = boundary, 1 = center)",
      y = "Density",
      caption = if (window_mode != "staggered") {
        "Staggered window mode shifts boundaries in alternating RT bins, reducing boundary-zone precursors"
      } else {
        "Staggered mode active: boundaries shift in alternating RT bins"
      }
    ) +
    theme_aidia() +
    theme(
      panel.grid.minor = element_blank()
    )

  return(p)
}
