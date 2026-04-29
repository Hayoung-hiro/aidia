# export_publication.R - Publication-Quality Figure Export
#
# Purpose: Re-render AIDIA ggplot objects at journal-specific dimensions,
#          fonts, and vector formats for manuscript submission.
#
# Design: Same ggplot objects from generate_visualizations() are re-rendered
#         with publication theme override. No duplicate plot generation needed.
#
# Dependencies: ggplot2, gridExtra, grid, grDevices (cairo_pdf)
# Optional: patchwork (for multi-panel assembly with panel labels)


# =============================================================================
# Journal Presets
# =============================================================================

#' Get journal figure size preset
#'
#' Returns figure dimensions for common proteomics and analytical chemistry
#' journals. Sizes are based on published author guidelines.
#'
#' @param journal Character, journal key (e.g., "jpr", "mcp", "analchem")
#' @param column Character, column width: "single", "1.5", or "double"
#'
#' @return Named list with width_mm, width_in, height_in, base_size, dpi
#' @export
#'
#' @examples
#' get_journal_preset("jpr", "single")
#' get_journal_preset("nature_methods", "double")
get_journal_preset <- function(journal = "jpr", column = "single") {

  # Journal column width database (mm)
  journal_db <- list(
    jpr = list(
      name = "Journal of Proteome Research",
      single = 85, half = 114, double = 170,
      max_height_mm = 230
    ),
    mcp = list(
      name = "Molecular & Cellular Proteomics",
      single = 85, half = 114, double = 170,
      max_height_mm = 230
    ),
    analchem = list(
      name = "Analytical Chemistry",
      single = 84, half = 114, double = 174,
      max_height_mm = 234
    ),
    nature_methods = list(
      name = "Nature Methods",
      single = 89, half = 120, double = 183,
      max_height_mm = 247
    ),
    proteomics = list(
      name = "Proteomics",
      single = 82, half = 114, double = 170,
      max_height_mm = 230
    ),
    jasms = list(
      name = "J. American Society for Mass Spectrometry",
      single = 84, half = 114, double = 174,
      max_height_mm = 234
    )
  )

  journal <- tolower(journal)
  if (!journal %in% names(journal_db)) {
    available <- paste(names(journal_db), collapse = ", ")
    stop(sprintf("Unknown journal '%s'. Available: %s", journal, available))
  }

  j <- journal_db[[journal]]

  # Map column parameter to width
  col_key <- switch(column,
    "single" = "single",
    "1.5"    = "half",
    "half"   = "half",
    "double" = "double",
    "full"   = "double",
    stop(sprintf("Unknown column type '%s'. Use: single, 1.5, double", column))
  )

  width_mm <- j[[col_key]]
  width_in <- width_mm / 25.4

  # Default height: 0.7 x width for single panel
  height_in <- width_in * 0.7
  max_height_in <- j$max_height_mm / 25.4

  # base_size calibrated for legibility at publication dimensions:
  # At single column (3.35"), base_size=8 yields ~7pt axis titles (>= 6pt min)
  base_size <- if (width_mm <= 90) 8 else if (width_mm <= 120) 9 else 10

  list(
    journal_name = j$name,
    column = column,
    width_mm = width_mm,
    width_in = width_in,
    height_in = height_in,
    max_height_in = max_height_in,
    base_size = base_size,
    dpi = 600
  )
}


# =============================================================================
# Main Export Function
# =============================================================================

#' Export selected plots for publication
#'
#' Re-renders AIDIA ggplot objects at journal-specific dimensions with
#' publication-appropriate theme sizing. Supports PDF (vector), SVG, TIFF,
#' and high-DPI PNG output.
#'
#' @param plots Named list of ggplot/grob objects (from generate_visualizations()$plots)
#' @param selected Character vector of plot names to export (e.g., "s1_01_density_heatmap").
#'   If NULL, exports all plots.
#' @param output_dir Character, output directory for publication figures
#' @param journal Character, journal preset key (default: "jpr").
#'   Available: "jpr", "mcp", "analchem", "nature_methods", "proteomics", "jasms"
#' @param column Character, column width: "single" (default), "1.5", or "double"
#' @param format Character, output format: "pdf" (default), "svg", "tiff", "png"
#' @param height_in Numeric, override figure height in inches. If NULL, uses
#'   preset default (0.7 x width).
#' @param base_size Numeric, override theme base_size. If NULL, uses preset.
#' @param dpi Numeric, resolution for raster formats (default: from preset, typically 600)
#' @param panel_assembly Named list for multi-panel figure assembly. Each element
#'   is a character vector of plot names to combine. Requires patchwork package.
#'   Example: list(figure1 = c("s1_01_density_heatmap", "s1_03_mz_density"))
#'
#' @return Invisible list of exported file paths
#' @export
#'
#' @examples
#' \dontrun{
#' results <- generate_visualizations(validated, plan, windows)
#'
#' # Export 2 plots for JPR single column
#' export_publication_figures(
#'   results$plots,
#'   selected = c("s1_01_density_heatmap", "s2_01_impact_summary"),
#'   journal = "jpr", column = "single"
#' )
#'
#' # Export as multi-panel figure with A/B labels
#' export_publication_figures(
#'   results$plots,
#'   panel_assembly = list(
#'     figure_1 = c("s1_01_density_heatmap", "s1_03_mz_density"),
#'     figure_2 = c("s2_02_window_layout", "s2_04_load_balance")
#'   ),
#'   journal = "nature_methods", column = "double"
#' )
#' }
export_publication_figures <- function(
  plots,
  selected = NULL,
  output_dir = "figures/",
  journal = "jpr",
  column = "single",
  format = "pdf",
  height_in = NULL,
  base_size = NULL,
  dpi = NULL,
  panel_assembly = NULL
) {

  # --- Validate inputs ---
  if (!is.list(plots) || is.null(names(plots))) {
    stop("'plots' must be a named list of ggplot/grob objects")
  }

  format <- match.arg(format, c("pdf", "svg", "tiff", "png"))

  # --- Get journal preset ---
  preset <- get_journal_preset(journal, column)

  # Apply overrides
  if (!is.null(base_size)) preset$base_size <- base_size
  if (!is.null(height_in)) preset$height_in <- height_in
  if (!is.null(dpi)) preset$dpi <- dpi

  # --- Create output directory ---
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  cat("\n==================================================\n")
  cat("   Publication Figure Export\n")
  cat("==================================================\n\n")
  cat(sprintf("  Journal:    %s\n", preset$journal_name))
  cat(sprintf("  Column:     %s (%d mm = %.2f in)\n", column, preset$width_mm, preset$width_in))
  cat(sprintf("  Height:     %.2f in\n", preset$height_in))
  cat(sprintf("  base_size:  %d\n", preset$base_size))
  cat(sprintf("  Format:     %s @ %d DPI\n", toupper(format), preset$dpi))
  cat(sprintf("  Output:     %s\n\n", output_dir))

  exported_files <- character()

  # --- Phase 1: Multi-panel assembly (if requested) ---
  if (!is.null(panel_assembly)) {
    if (!requireNamespace("patchwork", quietly = TRUE)) {
      stop("Package 'patchwork' is required for panel assembly. Install with: install.packages('patchwork')")
    }

    cat("  Assembling multi-panel figures...\n")

    for (fig_name in names(panel_assembly)) {
      plot_keys <- panel_assembly[[fig_name]]

      # Validate all keys exist
      missing <- setdiff(plot_keys, names(plots))
      if (length(missing) > 0) {
        warning(sprintf("  [!] %s: missing plots: %s — skipping",
                        fig_name, paste(missing, collapse = ", ")))
        next
      }

      # Collect and override theme for each sub-plot
      sub_plots <- lapply(plot_keys, function(key) {
        .pub_override_theme(plots[[key]], preset$base_size)
      })

      # Assemble with patchwork
      assembled <- .assemble_panels(sub_plots, preset)

      # Save
      filepath <- .pub_save(assembled, fig_name, output_dir, format, preset)
      exported_files <- c(exported_files, filepath)
      cat(sprintf("  OK %s (%d panels)\n", basename(filepath), length(plot_keys)))
    }
  }

  # --- Phase 2: Individual plots ---
  if (is.null(selected)) {
    selected <- names(plots)
  }

  # Exclude plots already in panel_assembly
  if (!is.null(panel_assembly)) {
    assembled_plots <- unlist(panel_assembly, use.names = FALSE)
    selected <- setdiff(selected, assembled_plots)
  }

  # Validate selection
  missing <- setdiff(selected, names(plots))
  if (length(missing) > 0) {
    warning(sprintf("  [!] Plots not found: %s", paste(missing, collapse = ", ")))
    selected <- intersect(selected, names(plots))
  }

  if (length(selected) > 0) {
    cat(sprintf("  Exporting %d individual plots...\n", length(selected)))

    for (plot_name in selected) {
      p <- plots[[plot_name]]
      p_pub <- .pub_override_theme(p, preset$base_size)

      filepath <- .pub_save(p_pub, plot_name, output_dir, format, preset)
      exported_files <- c(exported_files, filepath)
      cat(sprintf("  OK %s\n", basename(filepath)))
    }
  }

  # --- Summary ---
  cat(sprintf("\n  Exported %d figures to %s\n", length(exported_files), output_dir))

  # Print font size estimation
  .print_font_size_table(preset)

  cat("\n==================================================\n\n")

  invisible(exported_files)
}


# =============================================================================
# Internal Helpers
# =============================================================================

#' Override theme for publication rendering
#'
#' For ggplot objects, appends theme_aidia with publication base_size.
#' For grob objects, returns as-is (theme was set during construction).
#'
#' @param p ggplot or grob object
#' @param base_size Numeric, publication base font size
#'
#' @return Modified plot object
#' @keywords internal
.pub_override_theme <- function(p, base_size) {
  if (inherits(p, "ggplot")) {
    p + theme_aidia(base_size = base_size)
  } else {
    # grob/gtable — cannot override theme post-hoc
    p
  }
}


#' Assemble multiple plots into a multi-panel figure with labels
#'
#' Uses patchwork for A/B/C panel labeling.
#'
#' @param sub_plots List of ggplot/grob objects
#' @param preset Journal preset from get_journal_preset()
#'
#' @return patchwork object
#' @keywords internal
.assemble_panels <- function(sub_plots, preset) {
  n <- length(sub_plots)

  # Determine layout: 1 = single, 2 = side-by-side, 3+ = 2-col grid
  if (n == 1) {
    assembled <- sub_plots[[1]]
  } else if (n == 2) {
    assembled <- sub_plots[[1]] + sub_plots[[2]]
  } else {
    # Stack in 2-column grid
    assembled <- patchwork::wrap_plots(sub_plots, ncol = 2)
  }

  # Add panel labels (A, B, C...)
  tag_size <- if (preset$base_size <= 8) 10 else 12
  assembled <- assembled +
    patchwork::plot_annotation(tag_levels = "A") &
    ggplot2::theme(plot.tag = ggplot2::element_text(
      size = tag_size, face = "bold"
    ))

  assembled
}


#' Save a plot to file in publication format
#'
#' @param p ggplot, patchwork, or grob object
#' @param name File name (without extension)
#' @param output_dir Output directory
#' @param format File format
#' @param preset Journal preset
#'
#' @return File path
#' @keywords internal
.pub_save <- function(p, name, output_dir, format, preset) {
  filename <- paste0(name, ".", format)
  filepath <- file.path(output_dir, filename)

  # Select device
  device <- switch(format,
    "pdf"  = grDevices::cairo_pdf,
    "svg"  = grDevices::svg,
    "tiff" = NULL,  # ggsave handles TIFF natively
    "png"  = NULL
  )

  # Handle grob objects separately
  if (inherits(p, "grob") || inherits(p, "gTree") || inherits(p, "gtable")) {
    .pub_save_grob(p, filepath, format, preset)
    return(filepath)
  }

  # ggsave for ggplot and patchwork objects
  ggsave_args <- list(
    filename = filepath,
    plot = p,
    width = preset$width_in,
    height = preset$height_in,
    dpi = preset$dpi,
    bg = "white"
  )

  if (!is.null(device)) {
    ggsave_args$device <- device
  }

  # TIFF compression
  if (format == "tiff") {
    ggsave_args$compression <- "lzw"
  }

  do.call(ggplot2::ggsave, ggsave_args)
  filepath
}


#' Save grob objects to publication format
#'
#' Opens a graphics device, renders the grob, and closes.
#'
#' @keywords internal
.pub_save_grob <- function(grob, filepath, format, preset) {
  width <- preset$width_in
  height <- preset$height_in

  # Open device
  switch(format,
    "pdf" = grDevices::cairo_pdf(filepath, width = width, height = height),
    "svg" = grDevices::svg(filepath, width = width, height = height),
    "tiff" = grDevices::tiff(filepath, width = width, height = height,
                              units = "in", res = preset$dpi, compression = "lzw"),
    "png" = grDevices::png(filepath, width = width, height = height,
                            units = "in", res = preset$dpi)
  )
  on.exit(grDevices::dev.off(), add = TRUE)

  grid::grid.draw(grob)
}


#' Print estimated font sizes at publication dimensions
#'
#' Helps users verify text legibility at final print size.
#'
#' @keywords internal
.print_font_size_table <- function(preset) {
  bs <- preset$base_size

  cat("\n  Font size at publication scale:\n")
  cat("  -----------------------------------------------\n")
  cat(sprintf("  %-16s %4.1f pt  %s\n", "Title",      bs + 1,   .pt_verdict(bs + 1)))
  cat(sprintf("  %-16s %4.1f pt  %s\n", "Axis title",  bs - 1,   .pt_verdict(bs - 1)))
  cat(sprintf("  %-16s %4.1f pt  %s\n", "Axis text",   bs - 2,   .pt_verdict(bs - 2)))
  cat(sprintf("  %-16s %4.1f pt  %s\n", "Legend text",  bs - 3,   .pt_verdict(bs - 3)))
  cat(sprintf("  %-16s %4.1f pt  %s\n", "Caption",     bs - 3,   .pt_verdict(bs - 3)))
  cat("  -----------------------------------------------\n")
  cat("  (Minimum: 6 pt for most journals)\n")
}


#' Font size verdict helper
#' @keywords internal
.pt_verdict <- function(pt) {
  if (pt >= 7) return("[OK]")
  if (pt >= 6) return("[borderline]")
  return("[too small]")
}
