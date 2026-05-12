# plot_boundary_ci.R - Bootstrap CI Visualization for m/z Boundaries
#
# Purpose: Visualize boundary uncertainty from bootstrap resampling.
#   Shows observed boundaries with CI ribbons overlaid on a density heatmap,
#   making it easy to identify RT bins where boundaries are unstable.
#
# Dependencies: ggplot2, R/theme_aidia.R, R/bootstrap_boundary.R


#' Plot m/z Boundary Confidence Intervals
#'
#' Creates a density heatmap with observed m/z boundaries and bootstrap CI
#' ribbons. Wide ribbons indicate high sample sensitivity; narrow ribbons
#' indicate robust boundaries.
#'
#' @param ci_result boundary_ci object from bootstrap_boundary_ci()
#' @param validated_data ValidatedData object from Stage 1
#' @param show_median Logical, show bootstrap median as dashed line (default: FALSE)
#' @param bins Integer, density heatmap resolution (default: 50)
#'
#' @return ggplot object
#' @export
#'
#' @examples
#' \dontrun{
#' ci <- bootstrap_boundary_ci(validated_data, plan, strategy_config = greedy_config())
#' plot_boundary_ci(ci, validated_data)
#' }
plot_boundary_ci <- function(ci_result, validated_data,
                             show_median = FALSE, bins = 50) {
  cat("  Generating Boundary CI plot...\n")

  if (!inherits(ci_result, "boundary_ci")) {
    stop("ci_result must be a boundary_ci object from bootstrap_boundary_ci()")
  }

  ci <- ci_result$ci_data
  params <- ci_result$params

  # Precursor data for density heatmap
  precursor_data <- validated_data$data %>%
    dplyr::select(RT.Apex, Precursor.Mz)

  # Strategy label
  strategy_label <- format_strategy_label(params$strategy)

  # Mean CI widths for subtitle
  mean_ci_min <- mean(ci$mz_min_ci_width)
  mean_ci_max <- mean(ci$mz_max_ci_width)
  max_ci <- max(ci$mz_min_ci_width + ci$mz_max_ci_width)

  # CI ribbon data for upper boundary
  ci_upper <- data.frame(
    rt = ci$rt_mid,
    ymin = ci$mz_max_lower,
    ymax = ci$mz_max_upper,
    observed = ci$mz_max_obs,
    median_val = ci$mz_max_median,
    boundary = "upper"
  )

  # CI ribbon data for lower boundary
  ci_lower <- data.frame(
    rt = ci$rt_mid,
    ymin = ci$mz_min_lower,
    ymax = ci$mz_min_upper,
    observed = ci$mz_min_obs,
    median_val = ci$mz_min_median,
    boundary = "lower"
  )

  ci_ribbons <- rbind(ci_upper, ci_lower)

  # Build plot
  p <- ggplot(precursor_data, aes(x = RT.Apex, y = Precursor.Mz)) +
    # Background density heatmap
    stat_density_2d(
      aes(fill = after_stat(density)),
      geom = "raster",
      contour = FALSE,
      n = bins,
      alpha = 0.7
    ) +
    scale_fill_viridis_c(option = "plasma", name = "Density") +

    # CI ribbons (semi-transparent bands)
    geom_ribbon(
      data = ci_upper,
      aes(x = rt, ymin = ymin, ymax = ymax),
      fill = aidia_colors$accent,
      alpha = 0.3,
      inherit.aes = FALSE
    ) +
    geom_ribbon(
      data = ci_lower,
      aes(x = rt, ymin = ymin, ymax = ymax),
      fill = aidia_strategy_colors[["greedy"]],
      alpha = 0.3,
      inherit.aes = FALSE
    ) +

    # Observed boundary lines (solid)
    geom_line(
      data = ci_upper,
      aes(x = rt, y = observed),
      color = aidia_colors$accent,
      linewidth = 1.0,
      inherit.aes = FALSE
    ) +
    geom_line(
      data = ci_lower,
      aes(x = rt, y = observed),
      color = aidia_strategy_colors[["greedy"]],
      linewidth = 1.0,
      inherit.aes = FALSE
    )

  # Optional: bootstrap median as dashed line
  if (show_median) {
    p <- p +
      geom_line(
        data = ci_upper,
        aes(x = rt, y = median_val),
        color = aidia_colors$accent,
        linewidth = 0.6,
        linetype = "dashed",
        inherit.aes = FALSE
      ) +
      geom_line(
        data = ci_lower,
        aes(x = rt, y = median_val),
        color = aidia_strategy_colors[["greedy"]],
        linewidth = 0.6,
        linetype = "dashed",
        inherit.aes = FALSE
      )
  }

  p <- p +
    labs(
      title = sprintf("Boundary Uncertainty: %s", strategy_label),
      subtitle = sprintf(
        "%d bootstrap iterations | %.0f%% CI | Mean CI width: lower=%.1f Da, upper=%.1f Da",
        params$n_boot, params$ci_level * 100, mean_ci_min, mean_ci_max
      ),
      x = "Retention Time (min)",
      y = "m/z (Da)",
      caption = sprintf(
        "Solid = observed boundary | Shaded = %.0f%% CI | Blue = lower, Red = upper",
        params$ci_level * 100
      )
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


#' Plot CI Width per RT Bin (Bar Chart)
#'
#' Shows the CI width for each RT bin as a grouped bar chart.
#' Highlights bins where boundaries are most uncertain (sample-sensitive).
#'
#' @param ci_result boundary_ci object from bootstrap_boundary_ci()
#'
#' @return ggplot object
#' @export
plot_boundary_ci_width <- function(ci_result) {
  cat("  Generating Boundary CI Width plot...\n")

  if (!inherits(ci_result, "boundary_ci")) {
    stop("ci_result must be a boundary_ci object")
  }

  ci <- ci_result$ci_data
  params <- ci_result$params

  # Reshape for grouped bar chart
  plot_data <- rbind(
    data.frame(
      rt_bin = sprintf("RT%02d", ci$rt_segment_id),
      rt_mid = ci$rt_mid,
      boundary = "Lower (mz_min)",
      ci_width = ci$mz_min_ci_width,
      n_precursors = ci$n_precursors,
      stringsAsFactors = FALSE
    ),
    data.frame(
      rt_bin = sprintf("RT%02d", ci$rt_segment_id),
      rt_mid = ci$rt_mid,
      boundary = "Upper (mz_max)",
      ci_width = ci$mz_max_ci_width,
      n_precursors = ci$n_precursors,
      stringsAsFactors = FALSE
    )
  )

  # Color by boundary type
  boundary_colors <- c(
    "Lower (mz_min)" = aidia_strategy_colors[["greedy"]],
    "Upper (mz_max)" = aidia_colors$accent
  )

  strategy_label <- format_strategy_label(params$strategy)

  p <- ggplot(plot_data, aes(x = rt_bin, y = ci_width, fill = boundary)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6, alpha = 0.85) +

    # Annotate precursor counts
    geom_text(
      data = plot_data[plot_data$boundary == "Lower (mz_min)", ],
      aes(x = rt_bin, y = -max(plot_data$ci_width) * 0.05,
          label = format(n_precursors, big.mark = ",")),
      size = 2.8, color = "gray50", inherit.aes = FALSE
    ) +

    scale_fill_manual(name = "Boundary", values = boundary_colors) +
    scale_y_continuous(expand = expansion(mult = c(0.12, 0.05))) +

    labs(
      title = sprintf("Boundary CI Width per RT Bin: %s", strategy_label),
      subtitle = sprintf(
        "%d bootstrap iterations | %.0f%% CI | Wider = more sample-sensitive",
        params$n_boot, params$ci_level * 100
      ),
      x = "RT Segment (precursor count below)",
      y = sprintf("%.0f%% CI Width (Da)", params$ci_level * 100),
      caption = "Numbers below bars = precursor count per bin"
    ) +
    theme_aidia() +
    theme(
      legend.position = "top",
      axis.text.x = element_text(angle = 45, hjust = 1),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank()
    )

  return(p)
}


#' Compare CI Widths Between Two Smoothing Methods
#'
#' Side-by-side comparison of bootstrap CI widths for two configurations
#' (e.g., SG vs Whittaker-Henderson smoothing).
#'
#' @param ci_a boundary_ci object (first method)
#' @param ci_b boundary_ci object (second method)
#' @param label_a Character, label for first method (default: "SG")
#' @param label_b Character, label for second method (default: "Whittaker")
#'
#' @return ggplot object
#' @export
plot_boundary_ci_comparison <- function(ci_a, ci_b,
                                        label_a = "SG",
                                        label_b = "Whittaker") {
  cat("  Generating Boundary CI Comparison plot...\n")

  # Combine CI width data from both methods
  build_df <- function(ci_result, label) {
    ci <- ci_result$ci_data
    data.frame(
      rt_bin = sprintf("RT%02d", ci$rt_segment_id),
      rt_mid = ci$rt_mid,
      total_ci_width = ci$mz_min_ci_width + ci$mz_max_ci_width,
      mz_min_ci = ci$mz_min_ci_width,
      mz_max_ci = ci$mz_max_ci_width,
      method = label,
      stringsAsFactors = FALSE
    )
  }

  plot_data <- rbind(build_df(ci_a, label_a), build_df(ci_b, label_b))
  plot_data$method <- factor(plot_data$method, levels = c(label_a, label_b))

  method_colors <- c(
    setNames(aidia_colors$before, label_a),
    setNames(aidia_colors$after, label_b)
  )

  # Summary for subtitle (derive from already-bound plot_data)
  mean_a <- mean(plot_data$total_ci_width[plot_data$method == label_a])
  mean_b <- mean(plot_data$total_ci_width[plot_data$method == label_b])
  pct_change <- (mean_b - mean_a) / mean_a * 100

  p <- ggplot(plot_data, aes(x = rt_bin, y = total_ci_width, fill = method)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6, alpha = 0.85) +
    scale_fill_manual(name = "Method", values = method_colors) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +

    labs(
      title = sprintf("Boundary CI Comparison: %s vs %s", label_a, label_b),
      subtitle = sprintf(
        "Mean total CI: %s=%.1f Da, %s=%.1f Da (%+.1f%%)",
        label_a, mean_a, label_b, mean_b, pct_change
      ),
      x = "RT Segment",
      y = "Total CI Width (Da) = lower + upper",
      caption = sprintf(
        "%d bootstrap iterations each | %.0f%% CI",
        ci_a$params$n_boot, ci_a$params$ci_level * 100
      )
    ) +
    theme_aidia() +
    theme(
      legend.position = "top",
      axis.text.x = element_text(angle = 45, hjust = 1),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank()
    )

  return(p)
}
