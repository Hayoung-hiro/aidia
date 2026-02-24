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
#' @export
plot_rt_mz_density_heatmap <- function(validated_data, bins = 50) {

  cat("  Generating RT x m/z Density Heatmap...\n")

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Apex, Precursor.Mz)

  # Create 2D density heatmap
  p <- ggplot(precursor_data, aes(x = RT.Apex, y = Precursor.Mz)) +
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
    theme_aidia()

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
#' @export
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

if (!isNamespaceLoaded("aidia")) cat("  [plot_density.R] Density visualization functions loaded\n")
