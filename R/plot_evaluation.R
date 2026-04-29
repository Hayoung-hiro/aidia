# plot_evaluation.R
# Window Evaluation Plots
#
# Purpose: Visualize per-window precursor distribution, temporal density
#          (co-elution proxy), and cross-strategy window width comparisons.
#          Complements evaluate_windows() output.
#
# Functions:
#   - plot_precursors_per_window(): Bar chart of precursor counts by window
#   - plot_temporal_density(): Heatmap of co-eluting precursor density
#   - plot_width_distribution_comparison(): Violin+box comparison across strategies
#
# Dependencies: ggplot2, dplyr, viridis, utils_common.R, theme_aidia.R


# =============================================================================
# Plot: Precursor Distribution Across Windows
# =============================================================================

#' Plot Precursors Per Window Bar Chart
#'
#' Bar chart showing the number of precursors in each isolation window,
#' colored by window width. Helps identify overloaded or empty windows.
#' When optimization_plan is provided, computes a "before" baseline using
#' the current cycle time's window count with equal-width placement.
#'
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2 (optional, for baseline)
#' @param max_windows Integer, max windows to show per RT bin (default: NULL = all)
#' @param evaluation_result Optional list from \code{evaluate_windows()}.
#'   When provided, per-window precursor counts are taken from its
#'   \code{per_window} component instead of being recomputed.
#'
#' @return ggplot object
#' @keywords internal
plot_precursors_per_window <- function(optimized_windows,
                                       validated_data,
                                       optimization_plan = NULL,
                                       max_windows = NULL,
                                       evaluation_result = NULL) {

  cat("  Generating Evaluation Plot: Precursor Distribution Across Windows...\n")

  windows        <- optimized_windows$windows
  precursor_data <- validated_data$data

  # ---- Count precursors per window (2D RT+mz matching) --------------------
  # Reuse evaluation result when available to avoid O(n_windows * n_precursors) work
  if (!is.null(evaluation_result) && !is.null(evaluation_result$per_window) &&
      nrow(evaluation_result$per_window) > 0) {
    pw <- evaluation_result$per_window
    # per_window rows are 1:1 with input windows — attach RT columns
    windows_counted <- data.frame(
      mz_start      = pw$mz_start,
      mz_end        = pw$mz_end,
      rt_start      = windows$rt_start,
      rt_end        = windows$rt_end,
      rt_segment_id = pw$rt_segment_id,
      n_precursors  = pw$n_precursors,
      stringsAsFactors = FALSE
    )
  } else {
    windows_counted <- calculate_precursors_per_window(windows, precursor_data)
  }

  if (nrow(windows_counted) < 1) {
    return(create_insufficient_data_plot(
      title   = "Precursor Distribution Across Windows",
      message = "No window data available"
    ))
  }

  # ---- Optionally trim to max_windows per RT bin --------------------------
  if (!is.null(max_windows) && is.numeric(max_windows) && max_windows > 0) {
    windows_counted <- windows_counted %>%
      dplyr::group_by(rt_segment_id) %>%
      dplyr::slice_head(n = as.integer(max_windows)) %>%
      dplyr::ungroup()
  }

  # ---- Compute mz_center, widths, and load status -------------------------
  windows_counted <- windows_counted %>%
    dplyr::mutate(
      mz_center    = (mz_start + mz_end) / 2,
      window_width = get_window_widths(windows_counted)
    )

  n_bins <- length(unique(windows_counted$rt_segment_id))
  median_note <- NULL

  # ---- Summary statistics -------------------------------------------------
  mean_n   <- mean(windows_counted$n_precursors, na.rm = TRUE)
  min_n    <- min(windows_counted$n_precursors,  na.rm = TRUE)
  max_n    <- max(windows_counted$n_precursors,  na.rm = TRUE)
  n_wins   <- nrow(windows_counted)
  cv_optimized <- if (mean_n > 0) sd(windows_counted$n_precursors, na.rm = TRUE) / mean_n else NA

  # ---- Baseline: equal-width windows at current (pre-optimization) conditions
  baseline_result <- tryCatch({
    # Determine baseline window count from current acquisition conditions
    if (!is.null(optimization_plan)) {
      current_ct <- optimization_plan$diagnosis$current_cycle_time_sec
      ms2_time <- optimization_plan$instrument$ms2_scan_time_ms / 1000
      baseline_n_per_bin <- if (!is.na(current_ct) && !is.na(ms2_time) && ms2_time > 0) {
        as.integer(floor(current_ct / ms2_time))
      } else {
        # Fallback: same count as optimized
        optimized_windows$parameters$window_count_per_bin %||%
          nrow(windows) / n_bins
      }
    } else {
      baseline_n_per_bin <- nrow(windows) / n_bins
    }

    # Generate equal-width windows per RT bin using canonical fixed-window generator
    rt_bins_df <- unique(windows[, c("rt_start", "rt_end", "rt_segment_id")])
    naive_windows_list <- lapply(seq_len(nrow(rt_bins_df)), function(i) {
      bin_prec <- precursor_data[precursor_data$RT.Apex >= rt_bins_df$rt_start[i] &
                                 precursor_data$RT.Apex <= rt_bins_df$rt_end[i], ]
      if (nrow(bin_prec) < 2) return(NULL)
      mz_range <- range(bin_prec$Precursor.Mz, na.rm = TRUE)
      n_win <- min(baseline_n_per_bin, 500L)
      if (n_win < 1) return(NULL)
      bin_windows <- generate_fixed_windows_internal(
        mz_min = mz_range[1], mz_max = mz_range[2],
        n_windows = n_win, min_width_da = 1, max_width_da = 500,
        fz_offset = 0
      )
      bin_windows$rt_start      <- rt_bins_df$rt_start[i]
      bin_windows$rt_end        <- rt_bins_df$rt_end[i]
      bin_windows$rt_segment_id <- rt_bins_df$rt_segment_id[i]
      bin_windows
    })
    naive_windows <- do.call(rbind, naive_windows_list)
    naive_counted <- calculate_precursors_per_window(naive_windows, precursor_data)
    naive_mean <- mean(naive_counted$n_precursors, na.rm = TRUE)
    naive_cv <- if (naive_mean > 0) sd(naive_counted$n_precursors, na.rm = TRUE) / naive_mean else NA
    list(cv = naive_cv, n_per_bin = baseline_n_per_bin)
  }, error = function(e) list(cv = NA, n_per_bin = NA))

  # Build subtitle with baseline comparison
  subtitle_text <- sprintf(
    "%d windows | Mean: %.1f | Range: %d\u2013%d precursors/window",
    n_wins, mean_n, min_n, max_n
  )
  if (!is.na(cv_optimized) && !is.na(baseline_result$cv)) {
    cv_change <- (1 - cv_optimized / baseline_result$cv) * 100
    baseline_label <- if (!is.na(baseline_result$n_per_bin)) {
      sprintf("before: %d win/bin, CV %.2f", baseline_result$n_per_bin, baseline_result$cv)
    } else {
      sprintf("equal-width CV: %.2f", baseline_result$cv)
    }
    subtitle_text <- paste0(subtitle_text, sprintf(
      "\nLoad CV: %.2f (%s, %.0f%% improvement)",
      cv_optimized, baseline_label, cv_change
    ))
  }

  # ---- Compute load ratio (vs mean) for color mapping ---------------------
  windows_counted <- windows_counted %>%
    dplyr::mutate(
      load_ratio = n_precursors / mean(n_precursors, na.rm = TRUE)
    )

  # ---- Build plot ---------------------------------------------------------
  p <- ggplot2::ggplot(
    windows_counted,
    ggplot2::aes(
      xmin = mz_start,
      xmax = mz_end,
      ymin = 0,
      ymax = n_precursors,
      fill = load_ratio
    )
  ) +
    # Bars with width proportional to actual isolation window width
    ggplot2::geom_rect(color = "white", linewidth = 0.25, alpha = 0.85) +
    # Mean reference line
    ggplot2::geom_hline(
      yintercept = mean_n,
      linetype   = "dashed",
      color      = aidia_colors$accent,
      linewidth  = 0.7
    ) +
    ggplot2::annotate(
      "text",
      x     = -Inf,
      y     = mean_n,
      label = sprintf("Mean: %.1f", mean_n),
      hjust = -0.1,
      vjust = -0.5,
      size  = 3.2,
      fontface = "italic",
      color = aidia_colors$accent
    ) +
    # Diverging fill: blue = underloaded, white = balanced, red = overloaded
    # Limits 0.2-1.8x ensure the midpoint (1.0) stays visually centered;
    # data beyond these bounds still renders at the extreme color.
    ggplot2::scale_fill_gradient2(
      name     = "Load\nRatio",
      low      = aidia_colors$before,
      mid      = "white",
      high     = aidia_colors$accent,
      midpoint = 1.0,
      limits   = c(
        min(0.2, min(windows_counted$load_ratio, na.rm = TRUE)),
        max(1.8, max(windows_counted$load_ratio, na.rm = TRUE))
      ),
      labels   = function(x) sprintf("%.1fx", x)
    ) +
    ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(0, 0.12))
    ) +
    ggplot2::scale_x_continuous(
      labels = function(x) sprintf("%.0f", x)
    ) +
    ggplot2::labs(
      title    = "Precursor Distribution Across Windows",
      subtitle = subtitle_text,
      x        = "m/z",
      y        = "Precursors per Window",
      caption  = "Bar width = isolation window width (Da) | Dashed line = mean count | Color: blue = underloaded, red = overloaded"
    ) +
    theme_aidia() +
    ggplot2::theme(
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor   = ggplot2::element_blank(),
      legend.position    = "right"
    )

  # Facet by RT segment when multiple bins are present
  if (n_bins > 1) {
    p <- p + ggplot2::facet_wrap(
      ~ rt_segment_id,
      labeller = ggplot2::labeller(
        rt_segment_id = function(x) sprintf("RT Bin %s", x)
      ),
      scales = "free_x"
    )
  }

  return(p)
}


# =============================================================================
# Plot: Precursor Temporal Density (Co-Elution Proxy)
# =============================================================================

#' Plot Precursor Temporal Density Across Windows
#'
#' Heatmap showing the maximum number of concurrently eluting identified
#' precursors within each isolation window. Higher density indicates
#' greater deconvolution difficulty. Uses geom_rect with diverging fill.
#'
#' \strong{Important:} Values are a \strong{lower bound} because only
#' successfully identified precursors are counted (survivor bias).
#'
#' @param evaluation_result List returned by \code{evaluate_windows()}.
#'   Must contain \code{per_window} with \code{temporal_density_max} column.
#' @param baseline_density Optional list with \code{median}, \code{mean},
#'   \code{max}, \code{n_per_bin} from baseline (equal-width) windows.
#'   When provided, the subtitle includes a before/after comparison.
#'
#' @return ggplot object
#' @keywords internal
plot_temporal_density <- function(evaluation_result, baseline_density = NULL) {

  cat("  Generating Evaluation Plot: Precursor Temporal Density...\n")

  per_window <- evaluation_result$per_window

  if (is.null(per_window) || nrow(per_window) < 1 ||
      !"temporal_density_max" %in% names(per_window) ||
      all(is.na(per_window$temporal_density_max))) {
    return(create_insufficient_data_plot(
      title   = "Precursor Temporal Density",
      message = "Temporal density data not available\n(requires FWHM)"
    ))
  }

  n_bins <- length(unique(per_window$rt_segment_id))

  median_note <- NULL

  # Summary statistics
  max_density  <- max(per_window$temporal_density_max, na.rm = TRUE)
  mean_density <- mean(per_window$temporal_density_max, na.rm = TRUE)
  median_density <- median(per_window$temporal_density_max, na.rm = TRUE)
  n_wins <- nrow(per_window)

  # High-density windows (> 2x median) indicate deconvolution hotspots
  n_high <- sum(per_window$temporal_density_max > 2 * median_density, na.rm = TRUE)
  pct_high <- n_high / n_wins * 100

  subtitle_text <- sprintf(
    "%d windows | Max: %d | Median: %.1f | Mean: %.1f co-eluting | %.0f%% high-density (>2x median)",
    n_wins, max_density, median_density, mean_density, pct_high
  )

  # Append baseline comparison when available
  if (!is.null(baseline_density) && !is.na(baseline_density$median)) {
    change_pct <- (1 - median_density / baseline_density$median) * 100
    subtitle_text <- paste0(subtitle_text, sprintf(
      "\nBaseline (equal-width, %d win/bin): median %.1f | %.0f%% %s",
      baseline_density$n_per_bin, baseline_density$median,
      abs(change_pct), if (change_pct > 0) "reduction" else "increase"
    ))
  }

  p <- ggplot2::ggplot(
    per_window,
    ggplot2::aes(
      xmin = mz_start,
      xmax = mz_end,
      ymin = 0,
      ymax = temporal_density_max,
      fill = temporal_density_max
    )
  ) +
    ggplot2::geom_rect(color = "white", linewidth = 0.25, alpha = 0.85) +
    # Median reference line
    ggplot2::geom_hline(
      yintercept = median_density,
      linetype   = "dashed",
      color      = aidia_colors$accent,
      linewidth  = 0.7
    ) +
    ggplot2::annotate(
      "text",
      x     = -Inf,
      y     = median_density,
      label = sprintf("Median: %.1f", median_density),
      hjust = -0.1,
      vjust = -0.5,
      size  = 3.2,
      fontface = "italic",
      color = aidia_colors$accent
    ) +
    viridis::scale_fill_viridis(
      name     = "Max\nDensity",
      option   = "inferno",
      direction = -1,
      begin    = 0.1,
      end      = 0.9
    ) +
    ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(0, 0.12))
    ) +
    ggplot2::scale_x_continuous(
      labels = function(x) sprintf("%.0f", x)
    ) +
    ggplot2::labs(
      title    = "Precursor Temporal Density (Co-Elution Proxy)",
      subtitle = subtitle_text,
      x        = "m/z",
      y        = "Max Co-Eluting Precursors",
      caption  = "Based on identified precursors only (lower bound) | Higher = harder deconvolution"
    ) +
    theme_aidia() +
    ggplot2::theme(
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor   = ggplot2::element_blank(),
      legend.position    = "right"
    )

  # Facet by RT segment when multiple bins are present
  if (n_bins > 1) {
    p <- p + ggplot2::facet_wrap(
      ~ rt_segment_id,
      labeller = ggplot2::labeller(
        rt_segment_id = function(x) sprintf("RT Bin %s", x)
      ),
      scales = "free_x"
    )
  }

  return(p)
}


# =============================================================================
# Plot: Window Width Distribution Comparison Across Strategies
# =============================================================================

#' Plot Window Width Distribution Comparison
#'
#' Violin + box plot comparing window width distributions across multiple
#' optimization strategies. Useful for understanding how adaptive each
#' strategy is to local m/z precursor density.
#'
#' @param windows_list Named list of OptimizedWindows objects
#'   Names should be strategy keys (e.g., "greedy", "kde", "quantile").
#'   At least 2 strategies required.
#'
#' @return ggplot object
#' @keywords internal
plot_width_distribution_comparison <- function(windows_list) {

  cat("  Generating Evaluation Plot: Window Width Distribution by Strategy...\n")

  if (length(windows_list) < 2) {
    return(create_insufficient_data_plot(
      title   = "Window Width Distribution by Strategy",
      message = "At least 2 strategies required\nfor comparison"
    ))
  }

  # ---- Collect width data from each strategy ------------------------------
  strategy_names <- order_strategies(names(windows_list))

  strategy_data <- lapply(strategy_names, function(s) {
    w      <- windows_list[[s]]$windows
    widths <- get_window_widths(w)
    data.frame(
      strategy       = s,
      strategy_label = format_strategy_label(s),
      window_width   = widths,
      stringsAsFactors = FALSE
    )
  })
  strategy_data <- safe_bind_rows(strategy_data)

  if (nrow(strategy_data) < 4) {
    return(create_insufficient_data_plot(
      title   = "Window Width Distribution by Strategy",
      message = "Insufficient window data\nfor distribution plot"
    ))
  }

  # Enforce canonical factor order on display labels
  label_order <- format_strategy_label(strategy_names)
  strategy_data$strategy_label <- factor(strategy_data$strategy_label,
                                          levels = label_order)
  strategy_data$strategy <- factor(strategy_data$strategy,
                                    levels = strategy_names)

  # ---- Summary stats for subtitle -----------------------------------------
  overall_median <- median(strategy_data$window_width, na.rm = TRUE)

  per_strategy <- strategy_data %>%
    dplyr::group_by(strategy_label) %>%
    dplyr::summarize(
      med = median(window_width, na.rm = TRUE),
      cv  = sd(window_width, na.rm = TRUE) / mean(window_width, na.rm = TRUE),
      .groups = "drop"
    )

  stats_parts <- sprintf("%s: %.1f Da (CV %.0f%%)",
                          per_strategy$strategy_label,
                          per_strategy$med,
                          per_strategy$cv * 100)
  subtitle_text <- paste(
    "Median width by strategy:",
    paste(stats_parts, collapse = " | ")
  )

  # ---- Build plot ---------------------------------------------------------
  p <- ggplot2::ggplot(
    strategy_data,
    ggplot2::aes(x = strategy_label, y = window_width, fill = strategy)
  ) +
    # Overall median reference line
    ggplot2::geom_hline(
      yintercept = overall_median,
      linetype   = "dashed",
      color      = aidia_colors$secondary,
      linewidth  = 0.6,
      alpha      = 0.8
    ) +
    ggplot2::annotate(
      "text",
      x     = length(strategy_names) + 0.45,
      y     = overall_median,
      label = sprintf("Overall median\n%.1f Da", overall_median),
      hjust = 1,
      vjust = -0.3,
      size  = 3,
      color = aidia_colors$secondary
    ) +
    # Violin layer (distribution shape)
    ggplot2::geom_violin(
      alpha     = 0.3,
      linewidth = 0.4,
      trim      = FALSE
    ) +
    # Boxplot layer (statistical summary on top of violin)
    ggplot2::geom_boxplot(
      width         = 0.15,
      outlier.shape = 21,
      outlier.size  = 1.2,
      outlier.alpha = 0.5,
      linewidth     = 0.5
    ) +
    scale_fill_strategy(guide = "none") +
    ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(0.02, 0.08)),
      labels = function(x) sprintf("%.0f", x)
    ) +
    ggplot2::labs(
      title    = "Window Width Distribution by Strategy",
      subtitle = subtitle_text,
      x        = "Strategy",
      y        = "Window Width (Da)",
      caption  = "Wider distribution = more adaptive to local m/z density | Dashed line = overall median"
    ) +
    theme_aidia() +
    ggplot2::theme(
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor   = ggplot2::element_blank(),
      axis.text.x        = ggplot2::element_text(face = "bold")
    )

  return(p)
}
