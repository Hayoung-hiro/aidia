# module3b_rt_binning.R - Simple RT Binning for DIA Window Optimization
#
# Module 3B: RT Binning (Simplified)
#
# Purpose: Group precursors by retention time bins for RT-dependent m/z optimization
# Strategy: Simple time-unit binning (e.g., 5-minute bins) using dplyr::group_by()
#
# Input: ValidatedData (Phase 1 output)
# Output: ValidatedData + rt_group column
#
# Version: 2.0 (Simplified)
# Last Updated: 2025-10-16

library(dplyr)
library(ggplot2)

cat("✅ Module 3B (RT Binning - Simplified) loading...\n")

#' Perform Simple RT Binning
#'
#' Groups precursors into RT bins based on equal time intervals.
#' This is a simplified version that only adds rt_group column to validated data.
#'
#' @param validated_data ValidatedData object from Phase 1
#' @param rt_bin_width_min Numeric, time bin width in minutes (default: 5)
#'
#' @return List with:
#'   - data: Original data with rt_group column added
#'   - rt_group_stats: Summary of precursor counts per RT group
#'   - parameters: Binning parameters used
#'
#' @export
#'
#' @examples
#' result <- perform_rt_binning(validated_data, rt_bin_width_min = 5)
#' # Access grouped data
#' grouped_data <- result$data %>% group_by(rt_group)
perform_rt_binning <- function(
  validated_data,
  rt_bin_width_min = 5
) {
  cat("=== Phase 3B: RT Binning (Simplified) ===\n\n")

  # Validate input
  if (!inherits(validated_data, "ValidatedData")) {
    stop("Input must be a ValidatedData object from Phase 1")
  }

  if (rt_bin_width_min <= 0) {
    stop("rt_bin_width_min must be positive")
  }

  data <- validated_data$data

  # Step 1: Calculate RT range
  cat("Step 1: Calculating RT range...\n")
  rt_range <- range(data$RT.Start, na.rm = TRUE)
  rt_min <- rt_range[1]
  rt_max <- rt_range[2]

  cat(sprintf("  RT range: %.2f - %.2f min (span: %.2f min)\n",
              rt_min, rt_max, rt_max - rt_min))

  # Step 2: Create RT bins (integer boundary alignment for robustness)
  cat(sprintf("\nStep 2: Creating RT bins (%.1f min width)...\n", rt_bin_width_min))

  # Generate breakpoints with integer boundaries for RT robustness
  # Round start to nearest multiple, ceiling end to next multiple
  rt_start_rounded <- round(rt_min / rt_bin_width_min) * rt_bin_width_min
  rt_end_rounded <- ceiling(rt_max / rt_bin_width_min) * rt_bin_width_min
  rt_breaks <- seq(rt_start_rounded, rt_end_rounded, by = rt_bin_width_min)

  cat(sprintf("  Aligned RT range: %.1f - %.1f min (integer boundaries)\n",
              rt_start_rounded, rt_end_rounded))

  n_bins <- length(rt_breaks) - 1
  cat(sprintf("  Generated %d RT bins\n", n_bins))

  # Step 3: Assign RT groups (simple cut)
  cat("\nStep 3: Assigning RT groups to precursors...\n")

  data <- data %>%
    mutate(
      rt_group = cut(
        RT.Start,
        breaks = rt_breaks,
        labels = 1:n_bins,
        include.lowest = TRUE
      ),
      rt_group = as.integer(as.character(rt_group))  # Convert factor to integer
    )

  # Step 4: Calculate group statistics
  cat("\nStep 4: Calculating RT group statistics...\n")

  rt_group_stats <- data %>%
    group_by(rt_group) %>%
    summarise(
      rt_start = min(RT.Start),
      rt_end = max(RT.Start),
      n_precursors = n(),
      .groups = 'drop'
    )

  cat(sprintf("  Total groups: %d\n", nrow(rt_group_stats)))
  cat(sprintf("  Precursors per group: min=%d, max=%d, mean=%.1f\n",
              min(rt_group_stats$n_precursors),
              max(rt_group_stats$n_precursors),
              mean(rt_group_stats$n_precursors)))

  # === INSIGHT: Detailed RT Bin Statistics ===
  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   RT Binning Insights                        ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  cat("RT Bin | RT Range (min)  | N_Precursors | Percent\n")
  cat("-------|------------------|--------------|--------\n")

  total_precursors <- sum(rt_group_stats$n_precursors)

  for (i in 1:nrow(rt_group_stats)) {
    bin <- rt_group_stats[i, ]
    cat(sprintf("  %2d   | %5.1f - %5.1f    | %12s | %5.1f%%\n",
                bin$rt_group,
                bin$rt_start,
                bin$rt_end,
                format(bin$n_precursors, big.mark = ","),
                100 * bin$n_precursors / total_precursors))
  }

  cat("-------|------------------|--------------|--------\n")
  cat(sprintf(" Total |                  | %12s | 100.0%%\n",
              format(total_precursors, big.mark = ",")))
  cat("\n")

  # Step 5: Package results
  cat("\nStep 5: Packaging results...\n")

  # Update ValidatedData object with rt_group column
  result_data <- validated_data
  result_data$data <- data

  # Add RT binning info to metadata
  result_data$metadata$rt_binning <- list(
    n_groups = n_bins,
    rt_bin_width_min = rt_bin_width_min,
    rt_breaks = rt_breaks
  )

  result <- list(
    data = result_data,  # ValidatedData with rt_group column

    rt_group_stats = rt_group_stats,

    parameters = list(
      rt_bin_width_min = rt_bin_width_min,
      n_bins = n_bins,
      rt_range = rt_range
    )
  )

  cat("\n=== Phase 3B Complete ===\n")
  cat(sprintf("✅ RT binning successful: %d groups created\n", n_bins))
  cat("   Data ready for Phase 3C (m/z range optimization)\n")

  return(result)
}


#' Visualize RT Binning Results (Simple Barchart)
#'
#' Creates a simple barchart showing precursor counts per RT group.
#'
#' @param rt_binning_result Result from perform_rt_binning()
#'
#' @return ggplot object
#' @export
#'
#' @examples
#' plot <- visualize_rt_binning(result)
#' print(plot)
visualize_rt_binning <- function(rt_binning_result) {

  stats <- rt_binning_result$rt_group_stats
  params <- rt_binning_result$parameters

  # Create simple barchart
  p <- ggplot(stats, aes(x = factor(rt_group), y = n_precursors)) +
    geom_col(fill = "steelblue", alpha = 0.7, color = "black", linewidth = 0.3) +
    geom_text(aes(label = format(n_precursors, big.mark = ",")),
              vjust = -0.5, size = 3) +
    labs(
      title = "RT Binning: Precursor Count per RT Group",
      subtitle = sprintf("Bin width: %.1f min | %d groups | RT range: %.1f-%.1f min",
                        params$rt_bin_width_min,
                        params$n_bins,
                        params$rt_range[1],
                        params$rt_range[2]),
      x = "RT Group",
      y = "Number of Precursors"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 10),
      axis.text = element_text(size = 10),
      axis.title = element_text(size = 12)
    ) +
    scale_y_continuous(labels = scales::comma)

  return(p)
}


#' Get Precursor Data Grouped by RT
#'
#' Convenience function to get precursor data grouped by rt_group.
#' Ready for use in Phase 3C.
#'
#' @param rt_binning_result Result from perform_rt_binning()
#'
#' @return Grouped tibble (grouped_df)
#' @export
#'
#' @examples
#' grouped_data <- get_grouped_data(result)
#' # Use in Phase 3C
#' grouped_data %>%
#'   group_map(~ optimize_mz_range_for_group(.x))
get_grouped_data <- function(rt_binning_result) {
  data <- rt_binning_result$data$data
  grouped <- data %>% group_by(rt_group)
  return(grouped)
}


cat("✅ Module 3B (RT Binning - Simplified) loaded successfully\n")
cat("   Available functions:\n")
cat("   - perform_rt_binning(validated_data, rt_bin_width_min = 5)\n")
cat("   - visualize_rt_binning(rt_binning_result)\n")
cat("   - get_grouped_data(rt_binning_result)\n")
cat("\n")
cat("   Usage:\n")
cat("   result <- perform_rt_binning(validated_data, rt_bin_width_min = 5)\n")
cat("   plot <- visualize_rt_binning(result)\n")
cat("   grouped_data <- get_grouped_data(result)  # For Phase 3C\n")
