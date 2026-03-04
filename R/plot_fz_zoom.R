# plot_fz_zoom.R - Plot 14: Forbidden Zone Zoom-in (Micro View)
#
# Purpose: Static visualization showing how FZ-optimized boundaries avoid
#          isotope clusters by sitting in inter-peak valleys. Compares
#          FZ boundary (green) vs naive integer boundary (red dashed).
#
# Dependencies: ggplot2, dplyr, stats, theme_aidia.R


#' Forbidden Zone Zoom-in Plot (Micro View)
#'
#' Creates a zoomed view (~5 Da range) around a representative window boundary,
#' showing simulated isotope envelope peaks at integer m/z positions. The
#' FZ-optimized boundary (green) sits in the valley between isotope clusters,
#' while a naive integer boundary (red dashed) would cut through a cluster.
#'
#' Only generated when \code{fz_offset > 0} (forbidden zone optimization active).
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param boundary_index Integer, index of the internal boundary to zoom into.
#'   NULL (default) selects the median internal boundary.
#' @param fz_offset Numeric, forbidden zone offset used in optimization
#'   (default: 0.25)
#' @param zoom_range_da Numeric, total m/z range to display (default: 5)
#' @param base_size Numeric, base font size for theme_aidia (default: 12)
#'
#' @return A ggplot object
#' @keywords internal
plot_fz_zoom <- function(optimized_windows,
                          boundary_index = NULL,
                          fz_offset = 0.25,
                          zoom_range_da = 5,
                          base_size = 12) {

  windows <- optimized_windows$windows

  if (nrow(windows) == 0) stop("No windows found in optimized_windows object")

  is_staggered <- "cycle" %in% colnames(windows)

  # Get internal boundaries (excluding range edges)
  # Use Cycle 1 boundaries if staggered
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

  # Internal boundaries = end of window i = start of window i+1
  if (nrow(seg_windows) < 2) {
    stop("Need at least 2 windows to show internal boundaries")
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

  # --- Simulated Isotope Envelope ---
  # Generate Gaussian peaks at integer m/z positions
  half_range <- zoom_range_da / 2
  mz_min <- fz_boundary - half_range
  mz_max <- fz_boundary + half_range

  # Integer positions within range
  peak_positions <- seq(floor(mz_min), ceiling(mz_max))

  # High-resolution m/z axis
  mz_axis <- seq(mz_min, mz_max, length.out = 2000)

  # Gaussian envelope parameters
  peak_sd <- 0.08  # Narrow peaks simulating isotope clusters
  peak_heights <- stats::runif(length(peak_positions), min = 0.4, max = 1.0)
  # Make the peak nearest to integer_boundary taller for visual impact
  nearest_idx <- which.min(abs(peak_positions - integer_boundary))
  peak_heights[nearest_idx] <- 1.0

  # Sum of Gaussians
  envelope <- numeric(length(mz_axis))
  for (i in seq_along(peak_positions)) {
    envelope <- envelope + peak_heights[i] *
      stats::dnorm(mz_axis, mean = peak_positions[i], sd = peak_sd)
  }
  # Normalize to 0-1 range
  envelope <- envelope / max(envelope)

  envelope_df <- data.frame(mz = mz_axis, intensity = envelope)

  # --- Forbidden Zone Band ---
  # FZ sits between integer positions: [N + 0.5 - offset, N + 0.5 + offset]
  # Find the FZ band containing our boundary
  fz_center <- floor(fz_boundary) + 0.5
  fz_band_start <- fz_center - fz_offset
  fz_band_end <- fz_center + fz_offset

  fz_band_df <- data.frame(
    xmin = fz_band_start,
    xmax = fz_band_end,
    ymin = 0,
    ymax = 1.15
  )

  # --- Build Plot ---
  p <- ggplot() +
    # Forbidden zone band (light gray background)
    geom_rect(
      data = fz_band_df,
      aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
      fill = aidia_colors$grid, alpha = 0.5
    ) +
    # Isotope envelope
    geom_area(
      data = envelope_df,
      aes(x = mz, y = intensity),
      fill = viridis::viridis(1, option = "cividis", begin = 0.4),
      alpha = 0.4
    ) +
    geom_line(
      data = envelope_df,
      aes(x = mz, y = intensity),
      color = viridis::viridis(1, option = "cividis", begin = 0.6),
      linewidth = 0.6
    ) +
    # Integer boundary (red dashed — bad placement)
    geom_vline(
      xintercept = integer_boundary,
      color = aidia_colors$accent,
      linetype = "dashed", linewidth = 0.8, alpha = 0.8
    ) +
    # FZ-optimized boundary (green — good placement)
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
             size = base_size / 3.5, fontface = "bold",
             hjust = -0.1) +
    annotate("text",
             x = fz_boundary, y = 1.02,
             label = sprintf("FZ: %.4f", fz_boundary),
             color = aidia_colors$success,
             size = base_size / 3.5, fontface = "bold",
             hjust = -0.1) +
    # FZ band label
    annotate("text",
             x = fz_center, y = 1.12,
             label = "Forbidden Zone",
             color = aidia_colors$secondary,
             size = base_size / 4, fontface = "italic") +
    # Labels and theme
    labs(
      title = "Forbidden Zone Boundary Placement",
      subtitle = sprintf(
        "FZ offset = %.2f Da | Boundary shifted %.4f Da from integer",
        fz_offset, abs(fz_boundary - integer_boundary)
      ),
      caption = "Green = FZ-optimized boundary (valley) | Red dashed = Integer boundary (through cluster)",
      x = "m/z (Da)",
      y = "Simulated Isotope Intensity"
    ) +
    theme_aidia(base_size = base_size) +
    theme(
      plot.title = element_text(hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5),
      axis.text.y = element_blank(),
      panel.grid.major.y = element_blank()
    ) +
    coord_cartesian(xlim = c(mz_min, mz_max), ylim = c(0, 1.2))

  return(p)
}
