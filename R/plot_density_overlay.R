# plot_density_overlay.R
# Plot 5: RT x m/z Density Heatmap with Optimized m/z Range Overlay (2x2 Grid)
#
# Purpose: Combine Plot 2 (density heatmap) with Plot 4 (m/z range optimization)
#          to visualize how each strategy adjusts m/z ranges across RT


#' Plot RT x m/z Density Heatmap with m/z Range Overlay (Single Strategy)
#'
#' Creates density heatmap of precursors and overlays optimized m/z range
#' boundaries for one strategy.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 50)
#'
#' @return ggplot object
#' @keywords internal
plot_density_with_mz_range <- function(optimized_windows, validated_data, bins = 50) {

  # Extract precursor data
  precursor_data <- validated_data$data %>%
    select(RT.Apex, Precursor.Mz)

  # Extract m/z optimization info
  mz_ranges <- optimized_windows$mz_optimization$mz_ranges
  strategy_name <- optimized_windows$mz_optimization$strategy

  # Create boundary lines data
  # For each RT segment, we have mz_min and mz_max
  boundary_data <- mz_ranges %>%
    select(rt_start, rt_end, mz_min, mz_max) %>%
    mutate(
      rt_midpoint = (rt_start + rt_end) / 2
    )

  # Create line segments for upper and lower boundaries
  upper_boundary <- boundary_data %>%
    select(rt = rt_midpoint, mz = mz_max)

  lower_boundary <- boundary_data %>%
    select(rt = rt_midpoint, mz = mz_min)

  # Strategy label (canonical labels from theme_aidia.R)
  strategy_label <- format_strategy_label(strategy_name)

  # Calculate mean m/z width
  mean_width <- mean(mz_ranges$mz_width, na.rm = TRUE)
  mean_coverage <- mean(mz_ranges$coverage_ratio, na.rm = TRUE) * 100

  # Create density heatmap with overlay
  p <- ggplot(precursor_data, aes(x = RT.Apex, y = Precursor.Mz)) +
    # Density heatmap
    stat_density_2d(
      aes(fill = after_stat(density)),
      geom = "raster",
      contour = FALSE,
      n = bins,
      alpha = 0.8
    ) +

    # Upper boundary line
    geom_line(
      data = upper_boundary,
      aes(x = rt, y = mz),
      color = "white",
      linewidth = 1.2,
      linetype = "solid",
      inherit.aes = FALSE
    ) +

    # Lower boundary line
    geom_line(
      data = lower_boundary,
      aes(x = rt, y = mz),
      color = "white",
      linewidth = 1.2,
      linetype = "solid",
      inherit.aes = FALSE
    ) +

    # Add segment vertical dividers (optional, subtle)
    geom_vline(
      data = boundary_data,
      aes(xintercept = rt_start),
      color = "white",
      alpha = 0.2,
      linewidth = 0.3,
      linetype = "dotted"
    ) +

    scale_fill_viridis_c(
      option = "plasma",
      name = "Density"
    ) +

    labs(
      title = strategy_label,
      subtitle = sprintf("Mean width: %.1f Da | Coverage: %.1f%%",
                        mean_width, mean_coverage),
      x = "Retention Time (min)",
      y = "m/z (Da)",
      caption = NULL
    ) +

    theme_aidia() +
    theme(
      plot.subtitle = element_text(size = 10),
      legend.position = "right",
      legend.key.height = unit(1, "cm"),
      legend.key.width = unit(0.4, "cm"),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "gray90", linewidth = 0.3)
    )

  return(p)
}


#' Plot RT x m/z Density Heatmap with m/z Range Overlay (All Strategies, 2x2 Grid)
#'
#' Creates a 2x2 grid showing density heatmap with optimized m/z range overlay
#' for all optimization strategies.
#'
#' @param windows_list Named list of OptimizedWindows objects for each strategy
#'   List names should match strategy keys (e.g., "greedy", "kde", "quantile")
#' @param validated_data ValidatedData object from Stage 1
#' @param bins Number of bins for density calculation (default: 50)
#'
#' @return Combined plot (grid.arrange object)
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' windows_list <- list(
#'   quantile = optimized_windows_q,
#'   smoothing = optimized_windows_s,
#'   outlier = optimized_windows_o,
#'   coverage = optimized_windows_c
#' )
#' plot5 <- plot_density_with_mz_ranges_grid(windows_list, validated_data)
#' }
plot_density_with_mz_ranges_grid <- function(windows_list, validated_data, bins = 50) {

  cat("  Generating Plot 5: RT x m/z Density with m/z Range Overlay (2x2 Grid)...\n")

  # Use all available strategies (preserve preferred order)
  strategy_order <- order_strategies(names(windows_list))

  # Create individual plots for each strategy
  plot_list <- list()

  for (strategy_name in strategy_order) {
    cat(sprintf("    Creating density plot for %s...\n", strategy_name))

    plot_list[[strategy_name]] <- plot_density_with_mz_range(
      optimized_windows = windows_list[[strategy_name]],
      validated_data = validated_data,
      bins = bins
    )
  }

  # Determine grid layout based on number of strategies
  n_plots <- length(plot_list)
  if (n_plots == 0) {
    cat("    No strategies to plot\n")
    return(grid::textGrob("No strategies available"))
  }

  ncol <- min(2, n_plots)
  nrow <- ceiling(n_plots / ncol)

  # Create grid using grobs list (dynamic, not hardcoded)
  combined_plot <- gridExtra::arrangeGrob(
    grobs = plot_list,
    ncol = ncol,
    nrow = nrow,
    top = grid::textGrob(
      "RT x m/z Density with Optimized m/z Range Overlay",
      gp = grid::gpar(fontsize = 16, fontface = "bold")
    ),
    bottom = grid::textGrob(
      "White lines = Optimized m/z boundaries | Bright regions = High precursor density",
      gp = grid::gpar(fontsize = 10, col = "gray40")
    )
  )

  return(combined_plot)
}


#' Plot Strategy m/z Width Profile (Overlay Line Chart)
#'
#' Creates an overlay line chart showing m/z width per RT segment for all
#' strategies on the same axes. Includes a reference line for the full data
#' m/z range per RT bin. Enables direct visual comparison of how aggressively
#' each strategy trims the m/z range.
#'
#' @param windows_list Named list of OptimizedWindows objects for each strategy
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_strategy_width_profile <- function(windows_list, validated_data) {

  cat("  Generating Plot 5: Strategy Width Profile (Overlay)...\n")

  if (length(windows_list) < 2) {
    return(create_insufficient_data_plot(
      title = "Strategy m/z Width Profile",
      message = "Need at least 2 strategies for comparison"
    ))
  }

  precursor_data <- validated_data$data

  # Collect width data from all strategies
  width_list <- list()

  for (strategy_name in names(windows_list)) {
    opt_win <- windows_list[[strategy_name]]
    mz_ranges <- opt_win$mz_optimization$mz_ranges

    if (is.null(mz_ranges)) next

    wd <- mz_ranges %>%
      dplyr::select(rt_segment_id, rt_start, rt_end, mz_width) %>%
      dplyr::mutate(
        rt_mid         = (rt_start + rt_end) / 2,
        strategy       = strategy_name,
        strategy_label = format_strategy_label(strategy_name)
      )

    width_list[[strategy_name]] <- wd
  }

  if (length(width_list) == 0) {
    return(create_insufficient_data_plot(
      title = "Strategy m/z Width Profile",
      message = "No m/z range data available"
    ))
  }

  width_df <- safe_bind_rows(width_list)

  # Order strategies consistently
  ordered <- order_strategies(unique(width_df$strategy))
  width_df$strategy_label <- factor(
    width_df$strategy_label,
    levels = format_strategy_label(ordered)
  )

  # Calculate reference: full data m/z range per RT bin (using first strategy's RT structure)
  ref_ranges <- width_list[[1]]
  ref_data <- data.frame(
    rt_mid   = ref_ranges$rt_mid,
    rt_start = ref_ranges$rt_start,
    rt_end   = ref_ranges$rt_end
  )

  # Compute original m/z width per RT bin from raw precursor data
  ref_widths <- vapply(seq_len(nrow(ref_data)), function(i) {
    bin_precursors <- precursor_data %>%
      dplyr::filter(RT.Apex >= ref_data$rt_start[i] & RT.Apex < ref_data$rt_end[i])
    if (nrow(bin_precursors) < 2) return(NA_real_)
    max(bin_precursors$Precursor.Mz, na.rm = TRUE) - min(bin_precursors$Precursor.Mz, na.rm = TRUE)
  }, numeric(1))
  ref_data$original_width <- ref_widths

  # Summary stats per strategy for subtitle
  width_stats <- width_df %>%
    dplyr::group_by(strategy_label) %>%
    dplyr::summarize(mean_width = mean(mz_width, na.rm = TRUE), .groups = "drop")
  stats_text <- paste(
    sprintf("%s: %.0f Da", width_stats$strategy_label, width_stats$mean_width),
    collapse = " | "
  )
  original_mean <- mean(ref_data$original_width, na.rm = TRUE)

  # Build strategy colors — map strategy key to aidia_strategy_colors
  strategy_color_map <- setNames(
    aidia_strategy_colors[ordered],
    format_strategy_label(ordered)
  )

  p <- ggplot() +
    # Reference: original data width per RT bin (gray area)
    geom_ribbon(
      data = ref_data,
      aes(x = rt_mid, ymin = 0, ymax = original_width),
      fill = aidia_colors$before_muted,
      alpha = 0.3
    ) +
    geom_line(
      data = ref_data,
      aes(x = rt_mid, y = original_width),
      color = aidia_colors$before_muted_dark,
      linewidth = 0.6,
      linetype = "dashed"
    ) +
    # Strategy width lines
    geom_line(
      data = width_df,
      aes(x = rt_mid, y = mz_width, color = strategy_label),
      linewidth = 0.9,
      alpha = 0.85
    ) +
    geom_point(
      data = width_df,
      aes(x = rt_mid, y = mz_width, color = strategy_label),
      size = 1.5,
      alpha = 0.7
    ) +
    scale_color_manual(
      name   = "Strategy",
      values = strategy_color_map
    ) +
    scale_y_continuous(
      expand = expansion(mult = c(0, 0.05))
    ) +
    labs(
      title = "Strategy m/z Width Profile Across RT Segments",
      subtitle = sprintf(
        "Original mean: %.0f Da | %s",
        original_mean, stats_text
      ),
      x = "Retention Time (min)",
      y = "m/z Width (Da)"
    ) +
    theme_aidia() +
    theme(
      legend.position = "top",
      panel.grid.minor = element_blank()
    )

  return(p)
}
