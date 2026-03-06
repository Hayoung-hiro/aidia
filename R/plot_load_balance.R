# plot_load_balance.R
# Plot 16: Precursor Load Balance Across Windows
#
# Purpose: Visualize how evenly precursors are distributed across isolation
#          windows within each RT segment. Shows IQR band per RT segment
#          with individual window points and a high-load threshold band.
#
# Dependencies: ggplot2, dplyr


#' Plot Precursor Load Balance Across Windows
#'
#' Shows precursor count per window across RT segments with IQR crossbar,
#' individual window points, and a high-load threshold band (>2x mean).
#' Lower CV = more uniform distribution of precursors across windows.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_precursor_load_balance <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 16: Precursor Load Balance...\n")

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  # Count precursors per window using 2D matching
  counts <- count_precursors_in_2d_windows(
    precursor_rt  = precursor_data$RT.Apex,
    precursor_mz  = precursor_data$Precursor.Mz,
    window_rt_start = windows$rt_start,
    window_rt_end   = windows$rt_end,
    window_mz_start = windows$mz_start,
    window_mz_end   = windows$mz_end
  )

  # Build data frame
  df <- data.frame(
    rt_segment_id = windows$rt_segment_id,
    precursor_count = counts
  )

  if (nrow(df) < 2) {
    return(create_insufficient_data_plot(
      title = "Precursor Load Balance",
      message = "Insufficient data\n(need at least 2 windows)"
    ))
  }

  # Calculate per-segment stats
  segment_stats <- df %>%
    dplyr::group_by(rt_segment_id) %>%
    dplyr::summarize(
      mean_count = mean(precursor_count),
      median_count = median(precursor_count),
      q25 = quantile(precursor_count, 0.25),
      q75 = quantile(precursor_count, 0.75),
      sd_count   = sd(precursor_count),
      cv         = ifelse(mean_count > 0, sd_count / mean_count, NA),
      n_windows  = dplyr::n(),
      .groups = "drop"
    )

  # Overall stats
  overall_mean <- mean(df$precursor_count)
  overall_cv <- sd(df$precursor_count) / overall_mean

  # High-load threshold: >2x overall mean
  high_load_threshold <- overall_mean * 2
  n_high_load <- sum(df$precursor_count > high_load_threshold)
  pct_high_load <- n_high_load / nrow(df) * 100

  # RT bin labels
  df$rt_label <- sprintf("RT %02d", df$rt_segment_id)
  df$rt_label <- factor(df$rt_label,
                         levels = unique(df$rt_label[order(df$rt_segment_id)]))
  segment_stats$rt_label <- sprintf("RT %02d", segment_stats$rt_segment_id)
  segment_stats$rt_label <- factor(segment_stats$rt_label,
                                    levels = levels(df$rt_label))

  # Color points: high-load windows highlighted
  df$load_status <- ifelse(df$precursor_count > high_load_threshold,
                            "high_load", "normal")

  p <- ggplot(df, aes(x = rt_label, y = precursor_count)) +
    # High-load zone shading (above 2x mean)
    annotate(
      "rect",
      xmin = -Inf, xmax = Inf,
      ymin = high_load_threshold, ymax = Inf,
      fill = aidia_colors$accent,
      alpha = 0.08
    ) +
    # High-load threshold line
    geom_hline(
      yintercept = high_load_threshold,
      linetype = "dashed",
      color = aidia_colors$accent,
      linewidth = 0.6
    ) +
    # IQR ribbon
    geom_crossbar(
      data = segment_stats,
      aes(x = rt_label, y = median_count, ymin = q25, ymax = q75),
      fill = aidia_colors$success,
      color = aidia_colors$success,
      alpha = 0.25,
      linewidth = 0.4,
      width = 0.6
    ) +
    # Individual window points — colored by load status
    geom_jitter(
      aes(color = load_status),
      width = 0.18,
      size = 1.0,
      alpha = 0.5
    ) +
    scale_color_manual(
      values = c("normal" = aidia_colors$primary,
                  "high_load" = aidia_colors$accent),
      guide = "none"
    ) +
    # High-load threshold label
    annotate(
      "text",
      x = length(levels(df$rt_label)),
      y = high_load_threshold,
      label = sprintf("High load (>%.0f)", high_load_threshold),
      hjust = 1.05, vjust = -0.5,
      size = 3, fontface = "bold",
      color = aidia_colors$accent
    ) +
    scale_y_continuous(expand = expansion(mult = c(0.02, 0.1))) +
    labs(
      title = "Precursor Load Balance Across Windows",
      subtitle = sprintf(
        "Mean: %.1f precursors/window | CV: %.0f%% | %.1f%% windows above high-load threshold",
        overall_mean, overall_cv * 100, pct_high_load
      ),
      x = "RT Segment",
      y = "Precursors per Window",
      caption = sprintf(
        "Band = IQR (25th\u201375th) | High load = >2\u00d7 mean (%.0f) | %s total windows",
        high_load_threshold, format(nrow(windows), big.mark = ",")
      )
    ) +
    theme_aidia() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank()
    )

  return(p)
}


#' Plot Window Utilization Distribution
#'
#' Histogram showing the distribution of precursor counts across all
#' isolation windows. Reveals both sparsity (empty/low-count windows)
#' and crowding (high-count windows). Key summary statistics annotated:
#' median, mean, % empty windows, and 95th percentile.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
plot_load_balance_stacked <- function(optimized_windows, validated_data) {

  cat("  Generating Plot 16: Window Utilization Distribution...\n")

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  # Count precursors per window using 2D matching
  counts <- count_precursors_in_2d_windows(
    precursor_rt    = precursor_data$RT.Apex,
    precursor_mz    = precursor_data$Precursor.Mz,
    window_rt_start = windows$rt_start,
    window_rt_end   = windows$rt_end,
    window_mz_start = windows$mz_start,
    window_mz_end   = windows$mz_end
  )

  df <- data.frame(precursor_count = counts)

  if (nrow(df) < 2) {
    return(create_insufficient_data_plot(
      title = "Window Utilization Distribution",
      message = "Insufficient data\n(need at least 2 windows)"
    ))
  }

  # Summary statistics
  n_windows    <- nrow(df)
  n_empty      <- sum(df$precursor_count == 0)
  pct_empty    <- n_empty / n_windows * 100
  mean_count   <- mean(df$precursor_count)
  median_count <- median(df$precursor_count)
  p95_count    <- quantile(df$precursor_count, 0.95)
  max_count    <- max(df$precursor_count)
  cv_count     <- sd(df$precursor_count) / mean_count * 100

  # Determine bin width: aim for ~30 bins in the non-zero range
  count_range <- max_count - 0
  bin_width <- max(1, round(count_range / 30))

  p <- ggplot(df, aes(x = precursor_count)) +
    geom_histogram(
      binwidth = bin_width,
      fill = aidia_colors$before,
      color = "white",
      alpha = 0.75
    ) +
    # Median line
    geom_vline(
      xintercept = median_count,
      linetype = "solid",
      color = aidia_colors$primary,
      linewidth = 0.9
    ) +
    annotate(
      "text",
      x = median_count, y = Inf,
      label = sprintf("Median: %.0f", median_count),
      hjust = -0.15, vjust = 1.8,
      size = 3.5, fontface = "bold",
      color = aidia_colors$primary
    ) +
    # 95th percentile line (crowding threshold)
    geom_vline(
      xintercept = p95_count,
      linetype = "dashed",
      color = aidia_colors$accent,
      linewidth = 0.7
    ) +
    annotate(
      "text",
      x = p95_count, y = Inf,
      label = sprintf("P95: %.0f", p95_count),
      hjust = -0.15, vjust = 3.3,
      size = 3.2, fontface = "bold",
      color = aidia_colors$accent
    ) +
    scale_x_continuous(
      expand = expansion(mult = c(0.02, 0.05))
    ) +
    scale_y_continuous(
      expand = expansion(mult = c(0, 0.08))
    ) +
    labs(
      title = "Window Utilization Distribution",
      subtitle = sprintf(
        "Mean: %.1f | Median: %.0f | CV: %.0f%% | Empty windows: %.1f%% (%d/%d) | P95: %.0f | Max: %.0f",
        mean_count, median_count, cv_count, pct_empty, n_empty, n_windows,
        p95_count, max_count
      ),
      x = "Precursors per Window",
      y = "Number of Windows",
      caption = sprintf(
        "%s total windows | Solid line = median | Dashed line = 95th percentile (crowding threshold)",
        format(n_windows, big.mark = ",")
      )
    ) +
    theme_aidia() +
    theme(
      panel.grid.major.x = element_blank(),
      panel.grid.minor   = element_blank()
    )

  return(p)
}
