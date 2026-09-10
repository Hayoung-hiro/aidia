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
#' When \code{Precursor.Charge} is available and at least two charge states each
#' have >= 5 precursors in the zoom range, the plot is faceted by charge state so
#' the single placed boundary (computed on the z=1 grid) can be read against each
#' charge's own cluster periodicity. Otherwise a single combined panel is shown.
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
  cat("  Generating FZ Zoom plot...\n")

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

  # --- Real precursor data in zoom window ---
  half_range <- zoom_range_da / 2
  mz_min <- fz_boundary - half_range
  mz_max <- fz_boundary + half_range

  zoom_idx <- precursor_data$Precursor.Mz >= mz_min &
    precursor_data$Precursor.Mz <= mz_max
  zoom_mz <- precursor_data$Precursor.Mz[zoom_idx]

  if (length(zoom_mz) < 5) {
    return(create_insufficient_data_plot(
      title = "Forbidden Zone Boundary Placement",
      message = sprintf("Only %d precursors in zoom range (%.1f-%.1f Da)",
                        length(zoom_mz), mz_min, mz_max)
    ))
  }

  # --- Charge-faceted path (only when charge data supports >= 2 panels) ---
  if ("Precursor.Charge" %in% colnames(precursor_data)) {
    # Factors must be read by their labels, not their internal level codes.
    zoom_charge <- suppressWarnings(as.numeric(as.character(
      precursor_data$Precursor.Charge[zoom_idx]
    )))
    charge_df <- data.frame(mz = zoom_mz, charge = zoom_charge)
    valid_charge <- is.finite(zoom_charge) & zoom_charge > 0 &
      zoom_charge == floor(zoom_charge)
    charge_df <- charge_df[valid_charge, ]
    counts <- table(charge_df$charge)
    retained <- as.integer(names(counts[counts >= 5]))
    if (length(retained) >= 2) {
      zoom_df <- charge_df[charge_df$charge %in% retained, ]
      return(fz_zoom_faceted(zoom_df, fz_boundary, integer_boundary,
                             mz_min, mz_max, fz_offset))
    }
  }

  # --- Fallback: single combined panel (original behavior) ---
  fz_zoom_single_panel(zoom_mz, fz_boundary, integer_boundary,
                       mz_min, mz_max, fz_offset)
}

#' Single-panel forbidden zone zoom (original layout)
#'
#' @param zoom_mz Numeric vector of precursor m/z within the zoom range
#' @param fz_boundary Numeric FZ-optimized boundary m/z
#' @param integer_boundary Numeric nearest-integer boundary m/z
#' @param mz_min,mz_max Numeric zoom range limits
#' @param fz_offset Numeric forbidden zone offset
#' @return A ggplot object
#' @keywords internal
fz_zoom_single_panel <- function(zoom_mz, fz_boundary, integer_boundary,
                                 mz_min, mz_max, fz_offset) {
  df <- data.frame(mz = zoom_mz)

  kde <- stats::density(zoom_mz, n = 1024, from = mz_min, to = mz_max,
                        adjust = 0.3)
  density_df <- data.frame(mz = kde$x, density = kde$y)
  density_df$density <- density_df$density / max(density_df$density)

  fz_center <- floor(fz_boundary) + 0.5
  fz_band_df <- data.frame(
    xmin = fz_center - fz_offset,
    xmax = fz_center + fz_offset,
    ymin = 0,
    ymax = 1.15
  )

  density_at_fz <- approx(density_df$mz, density_df$density, xout = fz_boundary)$y
  density_at_int <- approx(density_df$mz, density_df$density, xout = integer_boundary)$y

  ggplot() +
    geom_rect(
      data = fz_band_df,
      aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
      fill = aidia_colors$grid, alpha = 0.5
    ) +
    geom_histogram(
      data = df,
      aes(x = mz, y = after_stat(density) / max(after_stat(density))),
      bins = 80,
      fill = viridis::viridis(1, option = "cividis", begin = 0.4),
      alpha = 0.35, color = NA
    ) +
    geom_line(
      data = density_df,
      aes(x = mz, y = density),
      color = viridis::viridis(1, option = "cividis", begin = 0.6),
      linewidth = 0.8
    ) +
    geom_vline(xintercept = integer_boundary, color = aidia_colors$accent,
               linetype = "dashed", linewidth = 0.8, alpha = 0.8) +
    geom_vline(xintercept = fz_boundary, color = aidia_colors$success,
               linetype = "solid", linewidth = 1.0) +
    annotate("text", x = integer_boundary, y = 1.08,
             label = sprintf("Integer: %d", integer_boundary),
             color = aidia_colors$accent, size = 3.5, fontface = "bold",
             hjust = -0.1) +
    annotate("text", x = fz_boundary, y = 1.02,
             label = sprintf("FZ: %.2f", fz_boundary),
             color = aidia_colors$success, size = 3.5, fontface = "bold",
             hjust = -0.1) +
    annotate("text", x = fz_center, y = 1.12, label = "Forbidden Zone",
             color = aidia_colors$secondary, size = 3, fontface = "italic") +
    labs(
      title = "Forbidden Zone Boundary Placement",
      subtitle = sprintf(
        "FZ offset = %.2f Da | %d precursors in view | Boundary shifted %.2f Da from integer",
        fz_offset, length(zoom_mz), abs(fz_boundary - integer_boundary)
      ),
      caption = sprintf(
        "Actual precursor m/z density | Density at FZ boundary: %.2f vs Integer: %.2f (lower = better)",
        density_at_fz %||% 0, density_at_int %||% 0
      ),
      x = "m/z (Da)", y = "Relative Precursor Density"
    ) +
    theme_aidia() +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank()) +
    coord_cartesian(xlim = c(mz_min, mz_max), ylim = c(0, 1.2))
}

#' Per-charge forbidden-zone band rectangles for the zoom plot
#'
#' For charge \code{z}, isotope-cluster periodicity in m/z is
#' \code{OPTIMAL_INCREMENT / z}; gap centers fall at \code{(k + 0.5) * period}.
#' The single-panel fallback retains its original shading independently.
#'
#' @param charge Integer charge state
#' @param mz_min,mz_max Numeric zoom range limits
#' @param fz_offset Numeric forbidden zone offset (band half-width at z=1)
#' @param ymax Numeric top of the band rectangle (default 1.15)
#' @return data.frame with columns charge, xmin, xmax, ymin, ymax
#' @keywords internal
fz_zoom_band_df <- function(charge, mz_min, mz_max, fz_offset, ymax = 1.15) {
  period <- OPTIMAL_INCREMENT / charge
  half <- fz_offset / charge
  k_min <- floor(mz_min / period) - 1
  k_max <- ceiling(mz_max / period) + 1
  centers <- (seq(k_min, k_max) + 0.5) * period
  centers <- centers[centers >= mz_min & centers <= mz_max]
  data.frame(
    charge = rep(charge, length(centers)),
    xmin = centers - half,
    xmax = centers + half,
    ymin = rep(0, length(centers)),
    ymax = rep(ymax, length(centers))
  )
}

#' Charge-faceted forbidden zone zoom (one panel per charge state)
#'
#' @param zoom_df data.frame with columns \code{mz} and \code{charge}
#'   (already filtered to charges with >= 5 precursors in range)
#' @param fz_boundary Numeric FZ-optimized boundary m/z (common to all facets)
#' @param integer_boundary Numeric nearest-integer boundary m/z
#' @param mz_min,mz_max Numeric zoom range limits
#' @param fz_offset Numeric forbidden zone offset
#' @return A ggplot object faceted by charge state
#' @keywords internal
fz_zoom_faceted <- function(zoom_df, fz_boundary, integer_boundary,
                            mz_min, mz_max, fz_offset) {
  charge_levels <- sort(unique(zoom_df$charge))

  density_df <- do.call(rbind, lapply(charge_levels, function(z) {
    mz_z <- zoom_df$mz[zoom_df$charge == z]
    kde <- stats::density(mz_z, n = 512, from = mz_min, to = mz_max,
                          adjust = 0.3)
    data.frame(mz = kde$x, density = kde$y / max(kde$y), charge = z)
  }))

  band_df <- do.call(rbind, lapply(charge_levels, function(z) {
    fz_zoom_band_df(z, mz_min, mz_max, fz_offset)
  }))

  # Color map keyed by charge (consistent with Plot 19)
  pal <- if (length(charge_levels) <= 5) {
    aidia_charge_colors[seq_along(charge_levels)]
  } else {
    viridis::viridis(length(charge_levels), option = "D")
  }
  names(pal) <- as.character(charge_levels)

  zoom_df$charge_f    <- factor(zoom_df$charge, levels = charge_levels)
  density_df$charge_f <- factor(density_df$charge, levels = charge_levels)
  band_df$charge_f    <- factor(band_df$charge, levels = charge_levels)
  charge_counts <- table(zoom_df$charge_f)

  ggplot() +
    geom_rect(
      data = band_df,
      aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
      fill = aidia_colors$grid, alpha = 0.5
    ) +
    geom_histogram(
      data = zoom_df,
      aes(x = mz, y = after_stat(ndensity), fill = charge_f),
      bins = 80, alpha = 0.35, color = NA, show.legend = FALSE
    ) +
    geom_line(
      data = density_df,
      aes(x = mz, y = density, color = charge_f),
      linewidth = 0.8, show.legend = FALSE
    ) +
    geom_vline(xintercept = integer_boundary, color = aidia_colors$accent,
               linetype = "dashed", linewidth = 0.8, alpha = 0.8) +
    geom_vline(xintercept = fz_boundary, color = aidia_colors$success,
               linetype = "solid", linewidth = 1.0) +
    scale_fill_manual(values = pal) +
    scale_color_manual(values = pal) +
    facet_grid(
      charge_f ~ .,
      labeller = labeller(charge_f = function(x) {
        paste0("z = ", x, " (n = ", charge_counts[x], ")")
      })
    ) +
    labs(
      title = "Forbidden Zone Boundary Placement by Charge State",
      subtitle = sprintf(
        "FZ offset = %.2f Da | same boundary in every panel | shifted %.2f Da from integer",
        fz_offset, abs(fz_boundary - integer_boundary)
      ),
      caption = paste0(
        "Per-charge real precursor density. The z=1 grid boundary (green) ",
        "need not align with z=2/z=3 cluster gaps (shorter period)."
      ),
      x = "m/z (Da)", y = "Relative Precursor Density"
    ) +
    theme_aidia() +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank()) +
    coord_cartesian(xlim = c(mz_min, mz_max))
}
