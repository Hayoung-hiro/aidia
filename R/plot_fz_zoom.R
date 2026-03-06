# plot_fz_zoom.R - Plot 14: Forbidden Zone Zoom-in (Micro View)
#
# Purpose: Visualize how FZ-optimized boundaries sit in low-density inter-peak
#          valleys using ACTUAL precursor data (not simulated). Shows real m/z
#          distribution near a window boundary with FZ vs integer placement.
#
# Dependencies: ggplot2, dplyr, stats, theme_aidia.R


#' Forbidden Zone Zoom-in Plot (Micro View)
#'
#' Creates a zoomed view (~5 Da range) around a representative window boundary,
#' showing actual precursor m/z density. The FZ-optimized boundary (green) sits
#' in a low-density valley between isotope clusters at integer m/z positions,
#' while a naive integer boundary (red dashed) falls on a high-density peak.
#'
#' Only generated when \code{fz_offset > 0} (forbidden zone optimization active).
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param boundary_index Integer, index of the internal boundary to zoom into.
#'   NULL (default) selects the median internal boundary.
#' @param fz_offset Numeric, forbidden zone offset used in optimization
#'   (default: 0.25)
#' @param zoom_range_da Numeric, total m/z range to display (default: 5)
#'
#' @return A ggplot object
#' @keywords internal
plot_fz_zoom <- function(optimized_windows,
                          validated_data,
                          boundary_index = NULL,
                          fz_offset = 0.25,
                          zoom_range_da = 5) {

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  if (nrow(windows) == 0) stop("No windows found in optimized_windows object")

  is_staggered <- "cycle" %in% colnames(windows)

  # Get internal boundaries (excluding range edges)
  if (is_staggered) {
    c1_windows <- windows %>%
      filter(cycle == 1L) %>%
      arrange(rt_segment_id, mz_start)
  } else {
    c1_windows <- windows %>%
      arrange(rt_segment_id, mz_start)
  }

  # Select a representative RT segment (median)
  median_seg <- select_median_rt_segment(c1_windows)
  seg_windows <- c1_windows %>% filter(rt_segment_id == median_seg)

  if (nrow(seg_windows) < 2) {
    return(create_insufficient_data_plot(
      title = "Forbidden Zone Boundary Placement",
      message = "Need at least 2 windows to show internal boundaries"
    ))
  }

  internal_boundaries <- seg_windows$mz_end[-nrow(seg_windows)]

  # Select boundary
  if (is.null(boundary_index)) {
    boundary_index <- ceiling(length(internal_boundaries) / 2)
  }
  boundary_index <- min(boundary_index, length(internal_boundaries))
  fz_boundary <- internal_boundaries[boundary_index]

  # Nearest integer boundary (naive placement)
  integer_boundary <- round(fz_boundary)

  # --- Real Precursor Data in Zoom Window ---
  half_range <- zoom_range_da / 2
  mz_min <- fz_boundary - half_range
  mz_max <- fz_boundary + half_range

  # Filter precursors in the zoom range (all RT segments — to get enough data)
  zoom_precursors <- precursor_data$Precursor.Mz[
    precursor_data$Precursor.Mz >= mz_min & precursor_data$Precursor.Mz <= mz_max
  ]

  if (length(zoom_precursors) < 5) {
    return(create_insufficient_data_plot(
      title = "Forbidden Zone Boundary Placement",
      message = sprintf("Only %d precursors in zoom range (%.1f-%.1f Da)",
                        length(zoom_precursors), mz_min, mz_max)
    ))
  }

  # Compute fractional m/z (distance from nearest integer)
  # This reveals the isotope cluster periodicity pattern
  df <- data.frame(mz = zoom_precursors)

  # High-resolution KDE for smooth density
  kde <- stats::density(zoom_precursors, n = 1024,
                        from = mz_min, to = mz_max,
                        adjust = 0.3)  # Narrow bandwidth to show fine structure
  density_df <- data.frame(mz = kde$x, density = kde$y)
  # Normalize to 0-1
  density_df$density <- density_df$density / max(density_df$density)

  # --- Forbidden Zone Band ---
  fz_center <- floor(fz_boundary) + 0.5
  fz_band_start <- fz_center - fz_offset
  fz_band_end <- fz_center + fz_offset

  fz_band_df <- data.frame(
    xmin = fz_band_start,
    xmax = fz_band_end,
    ymin = 0,
    ymax = 1.15
  )

  # Density at boundary positions (for annotation)
  density_at_fz <- approx(density_df$mz, density_df$density, xout = fz_boundary)$y
  density_at_int <- approx(density_df$mz, density_df$density, xout = integer_boundary)$y

  # --- Build Plot ---
  p <- ggplot() +
    # Forbidden zone band
    geom_rect(
      data = fz_band_df,
      aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
      fill = aidia_colors$grid, alpha = 0.5
    ) +
    # Precursor m/z histogram (rug-like)
    geom_histogram(
      data = df,
      aes(x = mz, y = after_stat(density) / max(after_stat(density))),
      bins = 80,
      fill = viridis::viridis(1, option = "cividis", begin = 0.4),
      alpha = 0.35,
      color = NA
    ) +
    # KDE density curve
    geom_line(
      data = density_df,
      aes(x = mz, y = density),
      color = viridis::viridis(1, option = "cividis", begin = 0.6),
      linewidth = 0.8
    ) +
    # Integer boundary (red dashed — naive)
    geom_vline(
      xintercept = integer_boundary,
      color = aidia_colors$accent,
      linetype = "dashed", linewidth = 0.8, alpha = 0.8
    ) +
    # FZ-optimized boundary (green — good)
    geom_vline(
      xintercept = fz_boundary,
      color = aidia_colors$success,
      linetype = "solid", linewidth = 1.0
    ) +
    # Boundary labels
    annotate("text",
             x = integer_boundary, y = 1.08,
             label = sprintf("Integer: %d", integer_boundary),
             color = aidia_colors$accent,
             size = 3.5, fontface = "bold",
             hjust = -0.1) +
    annotate("text",
             x = fz_boundary, y = 1.02,
             label = sprintf("FZ: %.2f", fz_boundary),
             color = aidia_colors$success,
             size = 3.5, fontface = "bold",
             hjust = -0.1) +
    # FZ band label
    annotate("text",
             x = fz_center, y = 1.12,
             label = "Forbidden Zone",
             color = aidia_colors$secondary,
             size = 3, fontface = "italic") +
    labs(
      title = "Forbidden Zone Boundary Placement",
      subtitle = sprintf(
        "FZ offset = %.2f Da | %d precursors in view | Boundary shifted %.2f Da from integer",
        fz_offset, length(zoom_precursors), abs(fz_boundary - integer_boundary)
      ),
      caption = sprintf(
        "Actual precursor m/z density | Density at FZ boundary: %.2f vs Integer: %.2f (lower = better)",
        density_at_fz %||% 0, density_at_int %||% 0
      ),
      x = "m/z (Da)",
      y = "Relative Precursor Density"
    ) +
    theme_aidia() +
    theme(
      axis.text.y = element_blank(),
      panel.grid.major.y = element_blank()
    ) +
    coord_cartesian(xlim = c(mz_min, mz_max), ylim = c(0, 1.2))

  return(p)
}
