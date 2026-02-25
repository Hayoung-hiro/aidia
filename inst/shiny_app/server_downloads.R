# server_downloads.R - Download Handlers (CSV Method File + PDF Report)

server_downloads <- function(input, output, session, rv) {

  # --- Helper: Generate descriptive filename using pipeline convention ---
  shiny_output_filename <- function(type, ext) {
    params <- rv$optimized_windows$parameters
    format_output_filename(
      type = type,
      instrument_preset = input$instrument,
      strategy = input$mz_strategy,
      window_mode = input$window_mode %||% "density",
      rt_binning_mode = input$rt_binning_mode %||% "fixed",
      rt_bin_width_min = params$rt_bin_width_min %||% 5,
      ext = ext
    )
  }

  # --- Download Handler: CSV Method File ---
  output$download_csv <- downloadHandler(
    filename = function() {
      shiny_output_filename("method", "csv")
    },
    content = function(file) {
      req(rv$optimized_windows, rv$validated_data)

      # Build project name from inputs
      project_name <- paste(
        c(
          trimws(input$sample_name %||% ""),
          trimws(input$condition %||% "")
        )[nchar(c(trimws(input$sample_name %||% ""),
                  trimws(input$condition %||% ""))) > 0],
        collapse = "_"
      )
      if (nchar(project_name) == 0) project_name <- "shiny_export"

      # Use existing export function from Stage 3
      export_windows_to_csv(
        optimized_windows = rv$optimized_windows,
        output_file = file,
        validated_data = rv$validated_data,
        optimization_plan = rv$optimization_plan,
        instrument_type = input$instrument,
        project_name = project_name
      )
    }
  )

  # --- Download Handler: PDF Report ---
  output$download_pdf <- downloadHandler(
    filename = function() {
      shiny_output_filename("report", "pdf")
    },
    content = function(file) {
      req(rv$optimized_windows, rv$validated_data, rv$optimization_plan)

      showNotification("Generating PDF report...", id = "pdf_progress",
                       duration = NULL, type = "message")

      tryCatch({
        cat("[Shiny] Generating structured PDF report via generate_visualizations()...\n")

        # Use the pipeline's Stage 4 to generate plots + structured PDF
        temp_dir <- tempdir()
        viz_output_dir <- file.path(temp_dir, "shiny_report")
        if (!dir.exists(viz_output_dir)) dir.create(viz_output_dir, recursive = TRUE)

        # Generate all visualizations (single-strategy mode for Shiny)
        viz_result <- generate_visualizations(
          validated_data = rv$validated_data,
          optimization_plan = rv$optimization_plan,
          optimized_windows = rv$optimized_windows,
          output_dir = viz_output_dir,
          create_pdf = FALSE,
          create_individual_plots = FALSE,
          windows_list = setNames(
            list(rv$optimized_windows),
            input$mz_strategy
          )
        )

        # Create structured PDF using the pipeline's create_pdf_report()
        cat("[Shiny] Creating structured PDF with create_pdf_report()...\n")
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
}
