# server_downloads.R - Download Handlers (CSV, Center Mass, m/z Range, PDF, Batch ZIP)

server_downloads <- function(input, output, session, rv) {

  # --- Helper: Generate descriptive filename using pipeline convention ---
  shiny_output_filename <- function(type, ext) {
    params <- rv$optimized_windows$parameters
    base_name <- format_output_filename(
      type = type,
      instrument_preset = input$instrument,
      strategy = input$mz_strategy,
      window_mode = input$window_mode %||% "density",
      rt_binning_mode = input$rt_binning_mode %||% "fixed",
      rt_bin_width_min = params$rt_bin_width_min %||% 5,
      ext = ext
    )

    # Prepend sample/condition name if provided
    parts <- c(trimws(input$sample_name %||% ""),
               trimws(input$condition %||% ""))
    prefix <- paste(parts[nchar(parts) > 0], collapse = "_")

    if (nchar(prefix) > 0) paste0(prefix, "_", base_name) else base_name
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

  # --- Download Handler: Center Mass List ---
  output$download_center_mass <- downloadHandler(
    filename = function() {
      shiny_output_filename("center_mass", "csv")
    },
    content = function(file) {
      req(rv$optimized_windows)
      export_center_mass_list(
        optimized_windows = rv$optimized_windows,
        output_file = file
      )
    }
  )

  # --- Download Handler: m/z Range List ---
  output$download_mz_range <- downloadHandler(
    filename = function() {
      shiny_output_filename("mz_range", "csv")
    },
    content = function(file) {
      req(rv$optimized_windows)
      export_mz_range_list(
        optimized_windows = rv$optimized_windows,
        output_file = file
      )
    }
  )

  # --- Download Handler: Batch Export (ZIP) ---
  output$download_batch_zip <- downloadHandler(
    filename = function() {
      shiny_output_filename("batch_export", "zip")
    },
    content = function(file) {
      req(rv$validated_data, rv$optimization_plan)

      showNotification("Running all 5 strategies for batch export...",
                       id = "batch_progress", duration = NULL, type = "message")

      tryCatch({
        # Collect shared parameters from current optimization run
        window_mode <- input$window_mode %||% "density"
        rt_bin_width <- rv$optimized_windows$parameters$rt_bin_width_min %||% 5
        rt_binning_mode <- input$rt_binning_mode %||% "fixed"
        min_width_da <- input$min_isolation_width %||% 2
        max_width_da <- input$max_isolation_width %||% 80
        fz_offset <- if (isTRUE(input$fz_offset_preset == "custom")) {
          as.numeric(input$custom_fz_offset %||% 0.25)
        } else {
          as.numeric(input$fz_offset_preset %||% "0.25")
        }

        # Strategy config constructors (default params for fair comparison)
        config_constructors <- list(
          greedy   = greedy_config,
          kde      = kde_config,
          quantile = quantile_config,
          coverage = coverage_config,
          outlier  = outlier_config
        )

        # Run each strategy
        windows_list <- list()
        for (strategy in STRATEGY_PREFERRED_ORDER) {
          showNotification(
            sprintf("Optimizing: %s (%d/5)...",
                    strategy, which(STRATEGY_PREFERRED_ORDER == strategy)),
            id = "batch_progress", duration = NULL, type = "message"
          )

          cfg <- config_constructors[[strategy]]()
          cat(sprintf("[Shiny Batch] Running strategy: %s\n", strategy))

          windows_list[[strategy]] <- optimize_windows(
            validated_data = rv$validated_data,
            optimization_plan = rv$optimization_plan,
            strategy_config = cfg,
            window_mode = window_mode,
            rt_bin_width_min = rt_bin_width,
            rt_binning_mode = rt_binning_mode,
            min_width_da = min_width_da,
            max_width_da = max_width_da,
            fz_offset = fz_offset
          )
        }

        # Export to temp directory
        showNotification("Exporting all formats + comparison...",
                         id = "batch_progress", duration = NULL, type = "message")

        batch_dir <- file.path(tempdir(), paste0("aidia_batch_", format(Sys.time(), "%Y%m%d_%H%M%S")))
        export_batch_comparison(
          windows_list = windows_list,
          validated_data = rv$validated_data,
          optimization_plan = rv$optimization_plan,
          output_dir = batch_dir
        )

        # ZIP the output directory
        old_wd <- setwd(batch_dir)
        on.exit(setwd(old_wd), add = TRUE)
        all_files <- list.files(".", recursive = TRUE)
        utils::zip(file, files = all_files)

        removeNotification("batch_progress")
        showNotification(
          sprintf("Batch export complete: %d strategies, 3 formats + comparison",
                  length(windows_list)),
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
