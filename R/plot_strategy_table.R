#' Plot Strategy Comparison Summary Table
#'
#' Creates a visual table comparing all strategies side by side.
#' Shows Coverage%, Mean Width, Window Count, and Range Utilization.
#' Does NOT recommend a strategy - provides insights only for informed decision-making.
#'
#' Purpose: Provide at-a-glance comparison of key metrics across all strategies
#' to help users understand trade-offs. Final quantification quality depends
#' on sample complexity and downstream analysis software.
#'
#' @param windows_list Named list of OptimizedWindows objects (one per strategy)
#' @param active_strategy Character, the user's selected strategy key (optional).
#'   When provided, the corresponding row is highlighted with bold text and accent color.
#'
#' @return grob object (tableGrob)
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' p <- plot_strategy_comparison_table(windows_list, active_strategy = "greedy")
#' grid::grid.draw(p)
#' ggsave("strategy_comparison.png", p, width = 12, height = 6)
#' }
plot_strategy_comparison_table <- function(windows_list, active_strategy = NULL) {

  cat("  Generating Strategy Comparison Table...\n")

  # Build summary data frame from each strategy's statistics
  strategy_names <- names(windows_list)
  summary_data <- lapply(strategy_names, function(strategy) {
    optimized_windows <- windows_list[[strategy]]

    # Extract window count
    n_windows <- nrow(optimized_windows$windows)

    # Extract mean window width (canonical accessor)
    mean_width <- mean(get_window_widths(optimized_windows$windows), na.rm = TRUE)

    # Extract coverage from statistics (handle both list and tibble formats)
    if (is.list(optimized_windows$statistics)) {
      coverage <- optimized_windows$statistics$mean_coverage_ratio
    } else if (is.data.frame(optimized_windows$statistics)) {
      coverage <- mean(optimized_windows$statistics$coverage_ratio, na.rm = TRUE)
    } else {
      coverage <- NA
    }

    # Fallback: try mz_ranges
    if (is.null(coverage) || length(coverage) == 0 || is.na(coverage)) {
      if (!is.null(optimized_windows$mz_optimization$mz_ranges)) {
        coverage <- mean(optimized_windows$mz_optimization$mz_ranges$coverage_ratio, na.rm = TRUE)
      }
    }

    # Default to 0 if still unavailable
    if (is.null(coverage) || length(coverage) == 0 || is.na(coverage)) {
      coverage <- 0
    }

    # Create row
    data.frame(
      Strategy = format_strategy_label(strategy),
      Coverage_Pct = coverage * 100,
      Mean_Width_Da = mean_width,
      Windows = n_windows,
      strategy_internal = strategy,  # For utilization logic
      stringsAsFactors = FALSE
    )
  }) %>%
    bind_rows()

  # Calculate Range Utilization labels
  # Use median as reference point for "Peak-focused" vs "Wide-range" vs "Balanced"
  median_width <- median(summary_data$Mean_Width_Da, na.rm = TRUE)

  summary_data <- summary_data %>%
    mutate(
      Range_Utilization = case_when(
        # Strategy-specific labels
        strategy_internal == "quantile" ~ "Conservative",
        strategy_internal == "coverage" ~ "Inclusive",
        strategy_internal == "kde" ~ "Peak-focused",
        strategy_internal == "greedy" ~ "Adaptive",
        # General heuristics
        Mean_Width_Da < median_width * 0.9 ~ "Peak-focused",
        Mean_Width_Da > median_width * 1.1 ~ "Wide-range",
        TRUE ~ "Balanced"
      )
    ) %>%
    select(-strategy_internal)  # Remove helper column

  # Format table for display
  display_table <- summary_data %>%
    mutate(
      Coverage = sprintf("%.1f%%", Coverage_Pct),
      `Mean Width` = sprintf("%.1f Da", Mean_Width_Da),
      Windows = format(Windows, big.mark = ","),
      `Range Utilization` = Range_Utilization
    ) %>%
    select(Strategy, Coverage, `Mean Width`, Windows, `Range Utilization`)

  # Per-row styling: highlight active strategy
  n_r <- nrow(display_table)
  row_fontfaces <- rep("plain", n_r)
  row_colors <- rep(aidia_colors$primary, n_r)
  row_bg <- rep(c("#FFFFFF", aidia_colors$grid), length.out = n_r)

  if (!is.null(active_strategy)) {
    active_label <- format_strategy_label(active_strategy)
    active_idx <- which(display_table$Strategy == active_label)
    if (length(active_idx) == 1) {
      row_fontfaces[active_idx] <- "bold"
      row_colors[active_idx] <- aidia_colors$success
      row_bg[active_idx] <- "#EEFAF6"
    }
  }

  # Create tableGrob with AIDIA colors
  table_grob <- gridExtra::tableGrob(
    display_table,
    rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core = list(
        fg_params = list(
          fontsize = 10,
          col = row_colors,
          fontface = row_fontfaces
        ),
        bg_params = list(
          fill = row_bg,
          col = aidia_colors$grid,
          lwd = 1
        )
      ),
      colhead = list(
        fg_params = list(
          fontsize = 11,
          col = "white",
          fontface = "bold"
        ),
        bg_params = list(
          fill = aidia_colors$primary,
          col = "white",
          lwd = 1.5
        )
      ),
      rowhead = list(
        fg_params = list(fontsize = 10)
      )
    )
  )

  # Add title and note
  title_grob <- grid::textGrob(
    "Strategy Comparison Summary",
    gp = grid::gpar(fontsize = 14, fontface = "bold", col = aidia_colors$primary)
  )

  note_grob <- grid::textGrob(
    "No single strategy is universally optimal. Evaluate based on your analytical goals and sample complexity.",
    gp = grid::gpar(fontsize = 8, col = aidia_colors$secondary, fontface = "italic"),
    just = "left",
    x = 0.02
  )

  # Assemble final plot with title and note
  composite <- gridExtra::arrangeGrob(
    title_grob,
    table_grob,
    note_grob,
    ncol = 1,
    heights = c(0.1, 0.8, 0.1)
  )

  return(composite)
}

