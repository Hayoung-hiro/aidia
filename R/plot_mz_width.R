# plot_mz_width.R
# Plot 4 Supplementary: m/z Range Width Comparison (Bar Charts)
#
# Purpose: Compare Original vs Optimized m/z width across RT segments
#          as a quantitative bar chart visualization


#' Plot m/z Width Comparison - All Strategies Overlay
#'
#' Creates a single grouped bar chart comparing Original m/z width
#' vs all strategies in one plot.
#'
#' @param windows_list Named list of OptimizedWindows objects
#'   Names: strategy name keys (e.g., "greedy", "kde", "quantile", "coverage", "outlier")
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return ggplot object
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' windows_list <- list(
#'   greedy = optimized_windows_g,
#'   kde = optimized_windows_k,
#'   quantile = optimized_windows_q,
#'   coverage = optimized_windows_c,
#'   outlier = optimized_windows_o
#' )
#' plot4c <- plot_mz_width_comparison_all_strategies(windows_list, validated_data)
#' }
plot_mz_width_comparison_all_strategies <- function(windows_list, validated_data) {

  cat("  Generating Plot 4C: m/z Width Comparison (All Strategies Overlay)...\n")

  # Strategy colors: Original + 5 strategies from design system
  bar_colors <- c(
    "Original" = "gray60",
    setNames(aidia_strategy_colors, tools::toTitleCase(names(aidia_strategy_colors)))
  )

  # Get reference mz_ranges (use quantile for RT bin structure)
  ref_mz_ranges <- windows_list[[1]]$mz_optimization$mz_ranges
  precursor_data <- validated_data$data

  # Calculate original widths
  original_widths <- precursor_data %>%
    mutate(
      rt_group = cut(
        RT.Apex,
        breaks = c(ref_mz_ranges$rt_start[1], ref_mz_ranges$rt_end),
        labels = FALSE,
        include.lowest = TRUE
      )
    ) %>%
    filter(!is.na(rt_group)) %>%
    group_by(rt_group) %>%
    summarise(
      width = max(Precursor.Mz, na.rm = TRUE) - min(Precursor.Mz, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      rt_segment_id = rt_group,
      rt_label = sprintf("RT%02d", rt_group),
      strategy = "Original"
    ) %>%
    select(rt_segment_id, rt_label, strategy, width)

  # Collect optimized widths from all strategies
  all_widths <- list()
  all_widths[[1]] <- original_widths

  for (strategy_name in names(windows_list)) {
    mz_ranges <- windows_list[[strategy_name]]$mz_optimization$mz_ranges

    strategy_widths <- mz_ranges %>%
      mutate(
        rt_label = sprintf("RT%02d", rt_segment_id),
        strategy = tools::toTitleCase(strategy_name),
        width = mz_width
      ) %>%
      select(rt_segment_id, rt_label, strategy, width)

    all_widths[[length(all_widths) + 1]] <- strategy_widths
  }

  # Combine all data — dynamic factor levels from actual strategies
  strategy_levels <- c("Original", tools::toTitleCase(names(windows_list)))
  plot_data <- safe_bind_rows(all_widths) %>%
    mutate(strategy = factor(strategy, levels = strategy_levels))

  # Calculate summary statistics
  strategy_stats <- plot_data %>%
    filter(strategy != "Original") %>%
    group_by(strategy) %>%
    summarise(mean_width = mean(width, na.rm = TRUE), .groups = "drop")

  mean_original <- mean(original_widths$width, na.rm = TRUE)

  stats_labels <- paste(
    sprintf("%s: %.1f", strategy_stats$strategy, strategy_stats$mean_width),
    collapse = " | "
  )
  subtitle_text <- sprintf("Original: %.1f Da | %s", mean_original, stats_labels)

  # Create grouped bar chart
  p <- ggplot(plot_data, aes(x = rt_label, y = width, fill = strategy)) +
    geom_col(position = position_dodge(width = 0.85), width = 0.8, alpha = 0.85) +

    scale_fill_manual(
      name = "Strategy",
      values = bar_colors
    ) +

    labs(
      title = "m/z Range Width Comparison: All Strategies",
      subtitle = subtitle_text,
      x = "RT Segment",
      y = "m/z Range Width (Da)",
      caption = "Grouped bars show Original + optimization strategies per RT segment"
    ) +

    scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +

    theme_aidia() +
    theme(
      plot.caption = element_text(hjust = 0),
      legend.position = "top",
      legend.title = element_text(face = "bold", size = 10),
      legend.text = element_text(size = 9),
      axis.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank()
    )

  return(p)
}
