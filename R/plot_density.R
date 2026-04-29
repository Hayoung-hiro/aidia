# plot_density.R - Density Visualization Functions
#
# Purpose: Generate density-related plots for precursor distribution analysis
#
# Functions:
#   - plot_rt_mz_density_heatmap(): 2D density heatmap (RT x m/z)
#   - plot_mz_normalized_density(): Normalized m/z density profiles by RT segment
#
# Dependencies: ggplot2, dplyr, viridis


# =============================================================================
# Plot 2: RT x m/z Density Heatmap
# =============================================================================

#' Plot Precursor Density Distribution
#'
#' Creates a 2D density heatmap showing the distribution of precursors
#' across retention time (RT) and m/z space.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 50)
#'
#' @return ggplot object
#' @keywords internal
plot_rt_mz_density_heatmap <- function(validated_data, bins = 150) {

  cat("  Generating RT x m/z Heatmap...\n")

  precursor_data <- validated_data$data
  mz_range <- range(precursor_data$Precursor.Mz)
  rt_range <- range(precursor_data$RT.Apex)
  n_label <- format(nrow(precursor_data), big.mark = ",")

  # KDE heatmap — matches S5 boundary grid style for visual continuity
  # S1: "here is the bottleneck" → S5: "here is the solution (green boundaries)"
  p <- ggplot(precursor_data, aes(x = RT.Apex, y = Precursor.Mz)) +
    stat_density_2d(
      aes(fill = after_stat(density)),
      geom = "raster",
      contour = FALSE,
      n = bins
    ) +
    scale_fill_viridis_c(
      option = "inferno",
      name = "Density",
      guide = guide_colorbar(
        barwidth = 1.2, barheight = 12,
        title.position = "top"
      )
    ) +
    labs(
      title = "Precursor Density Distribution",
      subtitle = sprintf(
        "%s precursors | m/z %.0f\u2013%.0f Da | RT %.1f\u2013%.1f min",
        n_label, mz_range[1], mz_range[2], rt_range[1], rt_range[2]
      ),
      x = "Retention Time (min)",
      y = "m/z (Da)",
      caption = "Bright regions = high precursor density | See Section 5 for optimized boundary overlay"
    ) +
    theme_aidia()

  return(p)
}


#' Plot 3D Precursor Intensity Surface
#'
#' Creates a 3D perspective plot showing summed precursor intensity as a
#' surface above the RT x m/z plane. Complements the 2D density heatmap:
#' - 2D heatmap (01a) shows WHERE precursors are concentrated (count)
#' - 3D surface (01b) shows WHERE valuable signal is concentrated (intensity)
#'
#' Uses binned aggregation of Precursor.Quantity per RT x m/z grid cell.
#' Falls back to count density if Precursor.Quantity is unavailable.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param n_grid Number of grid points per axis (default: 60)
#' @param theta Viewing angle (azimuth) in degrees (default: 35)
#' @param phi Viewing angle (elevation) in degrees (default: 25)
#' @return Invisible NULL (renders directly to device via plot3D::persp3D)
#' @keywords internal
plot_rt_mz_intensity_surface <- function(validated_data, n_grid = 50,
                                         theta = -50, phi = 30) {

  cat("  Generating 3D Intensity Surface (plot3D)...\n")

  if (!requireNamespace("plot3D", quietly = TRUE)) {
    stop("plot3D package is required. Install with: install.packages('plot3D')")
  }

  precursor_data <- validated_data$data
  rt <- precursor_data$RT.Apex
  mz <- precursor_data$Precursor.Mz
  n_precursors <- format(nrow(precursor_data), big.mark = ",")

  has_intensity <- "Precursor.Quantity" %in% names(precursor_data) &&
    !all(is.na(precursor_data$Precursor.Quantity))

  # Log-transform intensity at precursor level (MATLAB convention)
  if (has_intensity) {
    log_z <- log10(precursor_data$Precursor.Quantity + 1)
    z_label <- "Summed Intensity"
    main_title <- sprintf("Precursor Intensity Landscape (%s precursors)", n_precursors)
  } else {
    log_z <- rep(1, length(rt))  # uniform weight for count-based
    z_label <- "Count"
    main_title <- sprintf("Precursor Density Landscape (%s precursors)", n_precursors)
  }

  # Grid interpolation: scattered precursors → regular surface (MATLAB surf style)
  if (requireNamespace("akima", quietly = TRUE)) {
    grid_out <- akima::interp(
      x = mz, y = rt, z = log_z,
      nx = n_grid, ny = n_grid,
      linear = TRUE
    )
    mz_grid <- grid_out$x
    rt_grid <- grid_out$y
    z_plot <- grid_out$z
    # Replace NA (no data regions) with 0
    z_plot[is.na(z_plot)] <- 0
  } else {
    # Fallback: binning (if akima not available)
    mz_breaks <- seq(min(mz), max(mz), length.out = n_grid + 1)
    rt_breaks <- seq(min(rt), max(rt), length.out = n_grid + 1)
    mz_grid <- (mz_breaks[-1] + mz_breaks[-(n_grid + 1)]) / 2
    rt_grid <- (rt_breaks[-1] + rt_breaks[-(n_grid + 1)]) / 2
    mz_bin <- findInterval(mz, mz_breaks, all.inside = TRUE)
    rt_bin <- findInterval(rt, rt_breaks, all.inside = TRUE)
    z_plot <- matrix(0, nrow = n_grid, ncol = n_grid)
    for (i in seq_along(mz_bin)) {
      z_plot[mz_bin[i], rt_bin[i]] <- z_plot[mz_bin[i], rt_bin[i]] + log_z[i]
    }
  }

  old_par <- par(mar = c(2, 2, 3, 4), bg = "white")
  on.exit(par(old_par), add = TRUE)

  # MATLAB surf() style: continuous surface, x=m/z, y=RT, z=log10(intensity)
  plot3D::persp3D(
    x = mz_grid, y = rt_grid, z = z_plot,
    colvar = z_plot,
    col = viridis::inferno(256),
    colkey = list(side = 4, length = 0.6, width = 0.8,
                  cex.axis = 0.8, cex.clab = 0.9),
    theta = theta, phi = phi,
    shade = 0.3,
    border = NA,
    facets = TRUE,
    expand = 0.5,
    bty = "b2",
    xlab = "m/z (Da)",
    ylab = "RT (min)",
    zlab = sprintf("log10(%s)", z_label),
    main = main_title,
    cex.main = 1.1,
    font.main = 2,
    ticktype = "detailed",
    cex.axis = 0.7,
    cex.lab = 0.85,
    NAcol = "transparent"
  )

  invisible(NULL)
}



# =============================================================================
# Plot 2C: RT x m/z Density Heatmap with Optimized Window Overlay
# =============================================================================

#' Plot RT x m/z Density Heatmap with Window Boundaries
#'
#' Overlays optimized isolation window boundaries on the precursor density
#' heatmap. This is the primary Section 3 visualization — it answers
#' "how do the optimized windows relate to where precursors actually are?"
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 150)
#'
#' @return ggplot object
#' @keywords internal
plot_heatmap_with_windows <- function(optimized_windows, validated_data, bins = 150) {

  cat("  Generating RT x m/z Heatmap with Window Overlay...\n")

  precursor_data <- validated_data$data
  windows <- optimized_windows$windows

  n_windows <- nrow(windows)
  n_rt_bins <- length(unique(windows$rt_segment_id))

  # Calculate window widths for subtitle
  widths <- get_window_widths(windows)

  p <- ggplot() +
    # Layer 1: Precursor density heatmap
    stat_density_2d(
      data = precursor_data,
      aes(x = RT.Apex, y = Precursor.Mz, fill = after_stat(density)),
      geom = "raster",
      contour = FALSE,
      n = bins
    ) +
    scale_fill_viridis_c(option = "plasma", name = "Precursor\nDensity") +
    # Layer 2: Window rectangles (transparent fill, colored border)
    geom_rect(
      data = windows,
      aes(xmin = rt_start, xmax = rt_end,
          ymin = mz_start, ymax = mz_end),
      fill = NA,
      color = "white",
      linewidth = 0.4,
      alpha = 0.8
    ) +
    # Layer 3: RT bin boundary lines (thicker, dashed)
    geom_vline(
      xintercept = sort(unique(c(windows$rt_start, max(windows$rt_end)))),
      linetype = "dashed",
      color = aidia_colors$warning,
      linewidth = 0.5,
      alpha = 0.6
    ) +
    labs(
      title = "Precursor Density with Optimized Window Layout",
      subtitle = sprintf(
        "%d windows | %d RT bins | Width: %.0f\u2013%.0f Da (mean %.1f)",
        n_windows, n_rt_bins,
        min(widths), max(widths), mean(widths)
      ),
      x = "Retention Time (min)",
      y = "m/z (Da)",
      caption = "Heatmap = precursor density | White rectangles = isolation windows"
    ) +
    theme_aidia() +
    theme(
      legend.position = "right"
    ) +
    coord_cartesian(
      xlim = range(precursor_data$RT.Apex),
      ylim = range(precursor_data$Precursor.Mz)
    )

  return(p)
}


# =============================================================================
# Plot 3: m/z Normalized Density (Line Plot by RT Segment)
# =============================================================================

#' Plot m/z Density Profiles Across RT Segments
#'
#' Creates normalized density profiles showing m/z distribution
#' for sampled RT segments, useful for comparing how precursor
#' distribution changes across the gradient.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_mz_normalized_density <- function(optimized_windows, validated_data) {

  cat("  Generating m/z Normalized Density Profiles...\n")

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
      filter(RT.Apex >= rt_start_val & RT.Apex < rt_end_val)

    if (nrow(segment_data) < 2) next  # Need at least 2 points for density estimation

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
             theme_aidia())
  }

  # Combine density profiles (using safe_bind_rows for vctrs compatibility)
  density_data <- safe_bind_rows(density_profiles)

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
    theme_aidia() +
    theme(legend.position = "right")

  return(p)
}

