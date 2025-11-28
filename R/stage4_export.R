# stage4_export.R - Export Functions for Stage 4 Visualization
#
# Purpose: Handle export of plots and PDF reports
#
# Functions:
#   - export_individual_plots(): Export plots to individual files
#   - create_pdf_report(): Create multi-panel PDF report
#
# Dependencies: ggplot2, gridExtra, grid

library(ggplot2)
library(gridExtra)
library(grid)

# =============================================================================
# Export Individual Plots
# =============================================================================

#' Export Individual Plots
#'
#' Exports each plot in the list to individual files with the specified format.
#'
#' @param plots List of ggplot objects (must be named)
#' @param output_dir Output directory path
#' @param format File format: "png" or "pdf" (default: "png")
#' @param dpi Resolution in DPI (default: 300)
#'
#' @return Vector of file paths
#' @export
export_individual_plots <- function(plots, output_dir, format = "png", dpi = 300) {

  # Use plot names directly from the list
  # This makes it flexible and handles dynamically generated plots
  plot_names <- names(plots)

  if (is.null(plot_names) || length(plot_names) == 0) {
    stop("Plot list must have named elements")
  }

  file_paths <- character(length(plots))

  for (i in seq_along(plots)) {
    filename <- paste0(plot_names[i], ".", format)
    filepath <- file.path(output_dir, filename)

    ggsave(
      filepath,
      plot = plots[[i]],
      width = 10,
      height = 7,
      dpi = dpi,
      bg = "white"
    )

    file_paths[i] <- filepath
    cat(sprintf("  OK Saved: %s\n", filename))
  }

  return(file_paths)
}

# =============================================================================
# Create PDF Report
# =============================================================================

#' Create PDF Report
#'
#' Creates a comprehensive multi-panel PDF report with all plots.
#'
#' @param plots List of ggplot objects
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_file PDF output path
#'
#' @export
create_pdf_report <- function(plots, validated_data, optimization_plan,
                               optimized_windows, output_file) {

  # Create multi-panel PDF with all plots
  pdf(output_file, width = 16, height = 10)

  # Title page
  grid.newpage()
  grid.text("DIA Window Optimization Report",
            x = 0.5, y = 0.7,
            gp = gpar(fontsize = 24, fontface = "bold"))
  grid.text(sprintf("Generated: %s", Sys.time()),
            x = 0.5, y = 0.4,
            gp = gpar(fontsize = 14))
  grid.text(sprintf("Instrument: %s | Windows: %d | Coverage: %.1f%%",
                   optimization_plan$instrument$preset,
                   nrow(optimized_windows$windows),
                   optimized_windows$statistics$coverage_percentage),
            x = 0.5, y = 0.3,
            gp = gpar(fontsize = 12))

  # Plot pages (2 plots per page)
  plot_pairs <- list(
    c(1, 2), c(3, 4), c(5, 6), c(7, 8)
  )

  for (pair in plot_pairs) {
    if (pair[1] <= length(plots) && pair[2] <= length(plots)) {
      grid.newpage()
      grid.arrange(
        plots[[pair[1]]],
        plots[[pair[2]]],
        ncol = 1
      )
    } else if (pair[1] <= length(plots)) {
      grid.newpage()
      print(plots[[pair[1]]])
    }
  }

  # Handle remaining plots if more than 8
  if (length(plots) > 8) {
    remaining <- 9:length(plots)
    for (i in seq(1, length(remaining), by = 2)) {
      grid.newpage()
      if (i + 1 <= length(remaining)) {
        grid.arrange(
          plots[[remaining[i]]],
          plots[[remaining[i + 1]]],
          ncol = 1
        )
      } else {
        print(plots[[remaining[i]]])
      }
    }
  }

  dev.off()

  cat(sprintf("  OK PDF report saved: %s\n", basename(output_file)))
}

cat("  [stage4_export.R] Export functions loaded\n")
