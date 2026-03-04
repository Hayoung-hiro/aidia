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
#' Creates a histogram/density of precursor distance to the nearest window
#' boundary. Highlights the danger zone (< 1 Da) where quadrupole
#' transmission roll-off reduces fragmentation quality.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param danger_threshold Numeric, edge distance threshold in Da (default: 1.0)
#'
#' @return ggplot object
#' @keywords internal
plot_edge_proximity <- function(optimized_windows, validated_data,
                                danger_threshold = 1.0) {

  cat("  Generating Plot 17: Window Edge Proximity...\n")

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  # Calculate edge distances
  edge_dist <- calculate_edge_distances(precursor_data, windows)

  # Remove NAs (unassigned precursors)
  edge_dist_clean <- edge_dist[!is.na(edge_dist)]

  if (length(edge_dist_clean) < 2) {
    return(create_insufficient_data_plot(
      title = "Window Edge Proximity",
      message = "Insufficient data\n(no precursors matched to windows)"
    ))
  }

  df <- data.frame(edge_distance = edge_dist_clean)

  # Stats for annotation
  n_danger <- sum(edge_dist_clean < danger_threshold)
  pct_danger <- n_danger / length(edge_dist_clean) * 100
  median_dist <- median(edge_dist_clean)

  # Determine x-axis limit (cap at reasonable range)
  x_max <- min(quantile(edge_dist_clean, 0.99), max(edge_dist_clean))

  p <- ggplot(df, aes(x = edge_distance)) +
    # Danger zone shading
    annotate(
      "rect",
      xmin = 0, xmax = danger_threshold,
      ymin = -Inf, ymax = Inf,
      fill = aidia_colors$accent,
      alpha = 0.12
    ) +
    # Histogram + density overlay
    geom_histogram(
      aes(y = after_stat(density)),
      bins = 60,
      fill = aidia_colors$success,
      color = "white",
      alpha = 0.7,
      linewidth = 0.2
    ) +
    geom_density(
      color = "#1E8449",
      linewidth = 0.9
    ) +
    # Danger threshold line
    geom_vline(
      xintercept = danger_threshold,
      linetype = "dashed",
      color = aidia_colors$accent,
      linewidth = 0.8
    ) +
    # Median line
    geom_vline(
      xintercept = median_dist,
      linetype = "solid",
      color = aidia_colors$primary,
      linewidth = 0.7,
      alpha = 0.6
    ) +
    # Danger zone label
    annotate(
      "text",
      x = danger_threshold / 2,
      y = Inf,
      label = sprintf("Danger zone\n%.1f%% (%s)", pct_danger, format(n_danger, big.mark = ",")),
      vjust = 2,
      size = 3.2,
      fontface = "bold",
      color = aidia_colors$accent
    ) +
    # Median label
    annotate(
      "text",
      x = median_dist,
      y = Inf,
      label = sprintf("Median: %.1f Da", median_dist),
      vjust = 1.2,
      hjust = -0.05,
      size = 3.2,
      fontface = "bold",
      color = aidia_colors$primary
    ) +
    scale_x_continuous(
      limits = c(0, x_max),
      expand = expansion(mult = c(0, 0.02))
    ) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    labs(
      title = "Window Edge Proximity",
      subtitle = sprintf(
        "Distance from precursor to nearest window boundary | %s precursors matched",
        format(length(edge_dist_clean), big.mark = ",")
      ),
      x = "Distance to Nearest Window Edge (Da)",
      y = "Density",
      caption = sprintf("Danger zone: < %.1f Da (quadrupole transmission roll-off region)", danger_threshold)
    ) +
    theme_aidia() +
    theme(
      panel.grid.minor = element_blank()
    )

  return(p)
}
