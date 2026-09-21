# plot_load_balance.R
# Plot 16: Precursor Load Balance Across Windows
#
# Purpose: Visualize how evenly precursors are distributed across isolation
#          windows within each RT segment. Shows IQR band per RT segment
#          with individual window points, including empty windows.
#
# Dependencies: ggplot2, dplyr


#' Plot Precursor Load Balance Across Windows
#'
#' Shows precursor count per window across RT segments with IQR crossbar,
#' individual window points, retaining empty windows. Lower within-group CV
#' indicates more uniform load; pooled CV also reflects differences across RT.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2 (optional, for baseline)
#' @param aggregate_rt Logical; pool per-window loads across RT groups for display.
#'
#' @return ggplot object
#' @keywords internal
plot_precursor_load_balance <- function(optimized_windows, validated_data,
                                        optimization_plan = NULL, aggregate_rt = FALSE) {

  cat("  Generating Plot 16: Precursor Load Balance...\n")

  windows <- optimized_windows$windows
  precursor_data <- validated_data$data

  # Count precursors per window using 2D matching
  counts <- calculate_precursors_per_window(windows, precursor_data)$n_precursors

  # Build data frame
  df <- data.frame(
    rt_segment_id = windows$rt_segment_id,
    precursor_count = counts
  )

  if (nrow(df) < 1) {
    return(create_insufficient_data_plot(
      title = "Precursor Load Balance",
      message = "No windows available"
    ))
  }

  if (aggregate_rt) df$rt_segment_id <- 1L

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
  overall_cv <- if (overall_mean > 0) sd(df$precursor_count) / overall_mean else NA_real_

  # ---- Baseline: equal-width window load per RT bin ----
  n_bins <- length(unique(windows$rt_segment_id))
  baseline_df <- NULL
  baseline_stats <- NULL
  baseline_cv <- NA_real_
  baseline_n_per_bin <- NA_integer_

  tryCatch({
    original <- .original_method_settings(optimization_plan, optimized_windows)
    baseline_n_per_bin <- original$n_windows
    naive_windows <- .fixed_baseline_windows(optimization_plan, optimized_windows)
    if (is.null(naive_windows) || nrow(naive_windows) < 1) stop("Original method settings unavailable")

    naive_counts <- calculate_precursors_per_window(naive_windows, precursor_data)$n_precursors

    baseline_df <- data.frame(
      rt_segment_id   = naive_windows$rt_segment_id,
      precursor_count = naive_counts
    )
    if (aggregate_rt) baseline_df$rt_segment_id <- 1L
    naive_mean <- mean(naive_counts)
    baseline_cv <- if (naive_mean > 0) sd(naive_counts) / naive_mean else NA

    baseline_stats <- baseline_df %>%
      dplyr::group_by(rt_segment_id) %>%
      dplyr::summarize(
        median_count = median(precursor_count),
        q25 = quantile(precursor_count, 0.25),
        q75 = quantile(precursor_count, 0.75),
        .groups = "drop"
      )
    cat(sprintf("    Baseline computed: %d windows, CV=%.2f, median load=%.1f\n",
                nrow(naive_windows), baseline_cv, median(naive_counts)))
  }, error = function(e) {
    cat(sprintf("    [!] Baseline computation failed: %s\n", e$message))
  })

  has_baseline <- !is.null(baseline_df) && nrow(baseline_df) > 0

  # Pooling CV mixes between-RT abundance differences with within-RT balance.
  # Keep it descriptive and never turn it into an improvement/failure grade.
  cv_text <- function(x) if (is.finite(x)) sprintf("%.0f%%", 100 * x) else "N/A"
  subtitle_text <- paste("Pooled window-load CV:", cv_text(overall_cv))
  if (has_baseline) {
    subtitle_text <- sprintf("Pooled load CV: Original fixed (%d windows/cycle) %s | Optimized %s",
      baseline_n_per_bin, cv_text(baseline_cv), cv_text(overall_cv))
  }

  # RT bin labels
  df$rt_label <- sprintf("RT %02d", df$rt_segment_id)
  df$rt_label <- factor(df$rt_label,
                         levels = unique(df$rt_label[order(df$rt_segment_id)]))
  segment_stats$rt_label <- sprintf("RT %02d", segment_stats$rt_segment_id)
  segment_stats$rt_label <- factor(segment_stats$rt_label,
                                    levels = levels(df$rt_label))

  if (has_baseline) {
    # ---- Dodged comparison: Baseline vs Optimized side-by-side ----
    df$group <- "Optimized"
    baseline_df$group <- "Baseline"
    baseline_df$rt_label <- sprintf("RT %02d", baseline_df$rt_segment_id)

    combined_df <- rbind(
      df[, c("rt_label", "precursor_count", "group")],
      baseline_df[, c("rt_label", "precursor_count", "group")]
    )
    combined_df$rt_label <- factor(combined_df$rt_label, levels = levels(df$rt_label))
    combined_df$group <- factor(combined_df$group, levels = c("Baseline", "Optimized"))

    # Per-group per-bin stats
    combined_stats <- combined_df %>%
      dplyr::group_by(rt_label, group) %>%
      dplyr::summarize(
        median_count = median(precursor_count),
        q25 = quantile(precursor_count, 0.25),
        q75 = quantile(precursor_count, 0.75),
        .groups = "drop"
      )

    group_colors <- c(
      "Baseline"  = aidia_colors$before_muted,
      "Optimized" = aidia_colors$success
    )
    group_outline <- c(
      "Baseline"  = aidia_colors$before_muted_dark,
      "Optimized" = aidia_colors$after_success
    )
    p <- ggplot(combined_df, aes(x = rt_label, y = precursor_count, fill = group)) +
      geom_crossbar(
        data = combined_stats,
        aes(x = rt_label, y = median_count, ymin = q25, ymax = q75,
            color = group),
        alpha = 0.3,
        linewidth = 0.4,
        width = 0.4,
        position = position_dodge(width = 0.6)
      ) +
      geom_point(
        aes(color = group),
        size = 0.8,
        alpha = 0.4,
        position = position_jitterdodge(jitter.width = 0.1, jitter.height = 0, dodge.width = 0.6, seed = 1)
      ) +
      scale_fill_manual(values = group_colors, name = NULL, labels = c(Baseline = "Original", Optimized = "Designed")) +
      scale_color_manual(values = group_outline, name = NULL, labels = c(Baseline = "Original", Optimized = "Designed")) +
      scale_y_continuous(expand = expansion(mult = c(0.02, 0.1))) +
      labs(
        title = "Precursor Load Balance: Baseline vs Optimized",
        subtitle = subtitle_text,
        x = "RT Segment",
        y = "Precursors per Window",
        caption = "Left (gray) = equal-width baseline | Right (green) = optimized | Band = IQR"
      ) +
      theme_aidia() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1),
        panel.grid.major.x = element_blank(),
        panel.grid.minor = element_blank(),
        legend.position = "top"
      )
  } else {
    # ---- Single group (no baseline available) ----
    p <- ggplot(df, aes(x = rt_label, y = precursor_count)) +
      geom_crossbar(
        data = segment_stats,
        aes(x = rt_label, y = median_count, ymin = q25, ymax = q75),
        fill = aidia_colors$success,
        color = aidia_colors$success,
        alpha = 0.25,
        linewidth = 0.4,
        width = 0.6
      ) +
      geom_jitter(
        color = aidia_colors$primary,
        width = 0.18,
        size = 1.0,
        alpha = 0.5
      ) +
      scale_y_continuous(expand = expansion(mult = c(0.02, 0.1))) +
      labs(
        title = "Precursor Load Balance Across Windows",
        subtitle = subtitle_text,
        x = "RT Segment",
        y = "Precursors per Window",
        caption = "Band = IQR (25th\u201375th) | Lower CV = more uniform distribution"
      ) +
      theme_aidia() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1),
        panel.grid.major.x = element_blank(),
        panel.grid.minor = element_blank()
      )
  }

  if (aggregate_rt) p <- p + scale_x_discrete(labels = "Whole method") + labs(x = NULL)
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
