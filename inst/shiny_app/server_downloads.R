# server_downloads.R - Download Handlers (Method File, PDF Report, Batch ZIP)

# Export choices are deliberate download-time controls, unlike optimization
# settings. Both single-file and ZIP delivery use this same conversion.
.shiny_export_options <- function(input) {
  end <- input$acquisition_end_min
  if (is.null(end) || is.na(end)) end <- NULL
  list(fill_void = isTRUE(input$fill_void), acquisition_end_min = end)
}

server_downloads <- function(input, output, session, rv) {

  # --- Helper: Build project name from sample/condition inputs ---
  build_project_name <- function(default = "shiny_export") {
    parts <- c(trimws(input$sample_name %||% ""),
               trimws(input$condition %||% ""))
    name <- paste(parts[nchar(parts) > 0], collapse = "_")
    if (nchar(name) == 0) default else name
  }

  # --- Helper: Generate descriptive filename using pipeline convention ---
  shiny_output_filename <- function(type, ext) {
    format_result_filename(rv$optimized_windows, type = type, ext = ext,
                           prefix = build_project_name(default = ""))
  }

  # --- Helper: Format preview card ---
  format_preview_card <- function(title, subtitle, sample_data, description) {
    lines <- strsplit(sample_data, "\n", fixed = TRUE)[[1]]
    cells <- lapply(lines, function(line) strsplit(line, ",", fixed = TRUE)[[1]])
    tags$div(class = "export-format-card",
      div(class = "export-format-heading", tags$strong(title),
        tags$span(class = "text-muted", subtitle),
        tags$span(class = "export-example-label", "Example rows")),
      div(class = "workflow-table-scroll",
        tags$table(class = "table table-sm export-format-table",
          tags$caption(class = "sr-only", paste(title, "columns and illustrative example rows")),
          tags$thead(tags$tr(lapply(cells[[1]], function(value) tags$th(scope = "col", value)))),
          tags$tbody(lapply(cells[-1], function(values) tags$tr(lapply(values, tags$td)))))),
      tags$small(class = "text-muted", description))
  }

  # --- Export Format Preview ---
  output$export_format_preview <- renderUI({
    fmt <- input$export_format %||% "thermo"

    switch(fmt,
      thermo = format_preview_card(
        "Thermo Targeted Mass List", "Xcalibur-compatible CSV",
        "Compound,Formula,Adduct,m/z,z,t start (min),t stop (min),Isolation Window (m/z)\n1,,(no adduct),425.2523,1,11.4,28,50.5046",
        "8 columns including m/z, charge, RT start/stop, and isolation width. Adjacent RT groups join without gaps."
      ),
      center_mass = format_preview_card(
        "Center Mass List", "Generic 2-column format",
        "Center Mass (m/z),Window Width (m/z)\n425.2523000,50.5046000\n475.7569000,50.5046000",
        "Compatible with various DIA method software"
      ),
      mz_range = format_preview_card(
        "m/z Range List", "Single-column boundary format",
        "m/z range\n 400.0000000-450.5046000\n 450.5046000-501.0092000",
        "7 decimal precision, space-prefixed start-end pairs"
      )
    )
  })

  # --- Download Handler: Unified Method File (format selected by dropdown) ---
  output$download_method <- downloadHandler(
    filename = function() {
      fmt <- input$export_format %||% "thermo"
      type_name <- switch(fmt,
        thermo = "method",
        center_mass = "center_mass",
        mz_range = "mz_range"
      )
      shiny_output_filename(type_name, "csv")
    },
    content = function(file) {
      req(rv$optimized_windows)
      fmt <- input$export_format %||% "thermo"

      do.call(export_method_formats, c(list(
        optimized_windows = rv$optimized_windows,
        output_files = setNames(file, fmt), validated_data = rv$validated_data
      ), .shiny_export_options(input)))
    }
  )

  # --- Download Handler: PDF Report ---
  output$download_pdf <- downloadHandler(
    filename = function() {
      shiny_output_filename("report", "pdf")
    },
    content = function(file) {
      req(rv$optimization_complete, rv$optimized_windows,
          rv$validated_data, rv$optimization_plan)

      showNotification("Generating PDF report...", id = "pdf_progress",
                       duration = NULL, type = "message")

      tryCatch({
        cat("[Shiny] Generating PDF report with all 5 strategies...\n")

        temp_dir <- tempdir()
        viz_output_dir <- file.path(temp_dir, "shiny_report")
        if (!dir.exists(viz_output_dir)) dir.create(viz_output_dir, recursive = TRUE)

        # Build windows_list for all 5 strategies (reuse current result)
        windows_list <- build_strategy_comparison(
          optimized_windows = rv$optimized_windows,
          validated_data = rv$validated_data,
          optimization_plan = rv$optimization_plan,
          notify_fn = function(strategy, idx) {
            showNotification(
              sprintf("PDF: optimizing %s (%d/5)...", strategy, idx),
              id = "pdf_progress", duration = NULL, type = "message"
            )
          }
        )

        showNotification("PDF: generating plots...",
                         id = "pdf_progress", duration = NULL, type = "message")

        report_template_choice <- input$pdf_report_template %||% "full"
        cat(sprintf("[Shiny] PDF report_template = '%s'\n", report_template_choice))

        viz_result <- generate_visualizations(
          validated_data = rv$validated_data,
          optimization_plan = rv$optimization_plan,
          optimized_windows = rv$optimized_windows,
          output_dir = viz_output_dir,
          create_pdf = FALSE,
          create_individual_plots = FALSE,
          windows_list = windows_list,
          report_template = report_template_choice
        )

        cat("[Shiny] Creating structured PDF...\n")
        create_pdf_report(
          plots = viz_result$plots,
          validated_data = rv$validated_data,
          optimization_plan = rv$optimization_plan,
          optimized_windows = rv$optimized_windows,
          output_file = file
        )

        removeNotification("pdf_progress")
        cat("[Shiny] PDF report generated successfully!\n")

      }, error = function(e) {
        cat("[Shiny] ERROR generating PDF:", e$message, "\n")
        removeNotification("pdf_progress")
        showNotification(paste("PDF Error:", e$message), type = "error", duration = 10)
      })
    }
  )

  # --- Download Handler: Batch Export (ZIP) ---
  # Exports the selected strategy in all 3 CSV formats (Thermo, Center Mass, m/z Range)
  output$download_batch_zip <- downloadHandler(
    filename = function() {
      shiny_output_filename("all_formats", "zip")
    },
    content = function(file) {
      req(rv$optimized_windows, rv$validated_data, rv$optimization_plan)

      showNotification("Exporting selected strategy in all formats...",
                       id = "batch_progress", duration = NULL, type = "message")

      tryCatch({
        strategy <- rv$optimized_windows$parameters$mz_strategy %||% "custom"
        do.call(export_method_bundle, c(list(
          optimized_windows = rv$optimized_windows,
          output_path = file, validated_data = rv$validated_data,
          delivery = "zip"
        ), .shiny_export_options(input)))

        removeNotification("batch_progress")
        showNotification(
          sprintf("Export complete: %s strategy, 3 formats", strategy),
          type = "message", duration = 5
        )

      }, error = function(e) {
        cat("[Shiny] ERROR in batch export:", e$message, "\n")
        removeNotification("batch_progress")
        showNotification(paste("Batch Error:", e$message), type = "error", duration = 10)
      })
    }
  )
}
