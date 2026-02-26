# server_data.R - File Upload, DPPP Preview, Data Summary, Info Boxes

server_data <- function(input, output, session, rv, cycle_time_result) {

  # --- File Upload Handler ---
  observeEvent(input$parquet_file, {
    req(input$parquet_file)

    # Show processing notification
    showNotification("Processing file...", id = "upload_progress", duration = NULL, type = "message")

    tryCatch({
      # Read parquet file
      file_path <- input$parquet_file$datapath
      cat("\n[Shiny] File uploaded:", input$parquet_file$name, "\n")
      cat("[Shiny] Temp path:", file_path, "\n")
      cat("[Shiny] File size:", file.info(file_path)$size / 1024^2, "MB\n")

      # Run Stage 1: Data Validation
      cat("[Shiny] Starting create_validated_dataset()...\n")
      rv$validated_data <- create_validated_dataset(
        proteome_file = file_path,
        enable_replicate_consensus = TRUE,
        max_intensity_cv_percent = 30
      )
      cat("[Shiny] create_validated_dataset() completed!\n")

      rv$data_loaded <- TRUE
      rv$optimization_complete <- FALSE
      rv$optimized_windows <- NULL

      # Calculate DPPP Quick Preview
      cat("[Shiny] Calculating DPPP Quick Preview...\n")
      rv$dppp_preview <- quick_dppp_preview(
        rv$validated_data,
        cycle_times = c(1.5, 2.5, 3.5),
        target_dppp = input$target_dppp
      )
      cat("[Shiny] DPPP Preview calculated!\n")

      removeNotification("upload_progress")
      showNotification(
        paste("Data loaded:", format(nrow(rv$validated_data$data), big.mark = ","), "precursors"),
        type = "message"
      )

    }, error = function(e) {
      cat("[Shiny] ERROR in file upload:", e$message, "\n")
      removeNotification("upload_progress")
      showNotification(paste("Error:", e$message), type = "error", duration = 10)
      rv$data_loaded <- FALSE
    })
  })

  # --- Output: Data Status Info Box ---
  output$data_status <- renderbs4InfoBox({
    # Guard clause: return "waiting" state early if no data loaded
    if (!rv$data_loaded || is.null(rv$validated_data)) {
      return(bs4InfoBox(
        title = "Data Status",
        value = "Waiting",
        subtitle = "Upload parquet file",
        icon = icon("cloud-upload-alt"),
        color = "warning",
        fill = TRUE
      ))
    }

    n_precursors <- nrow(rv$validated_data$data)
    has_dppp_preview <- !is.null(rv$dppp_preview)
    gradient_len <- if (has_dppp_preview) {
      sprintf("%.0f min gradient", rv$dppp_preview$gradient_length)
    } else {
      "Ready"
    }

    bs4InfoBox(
      title = "Precursors Loaded",
      value = format(n_precursors, big.mark = ","),
      subtitle = gradient_len,
      icon = icon("check-circle"),
      color = "success",
      fill = TRUE
    )
  })

  # --- Output: Optimization Status Info Box ---
  output$optimization_status <- renderbs4InfoBox({
    # Guard clause: return "pending" state early if not optimized
    if (!rv$optimization_complete || is.null(rv$optimized_windows)) {
      return(bs4InfoBox(
        title = "Optimization",
        value = "Pending",
        subtitle = "Configure and run",
        icon = icon("cogs"),
        color = "warning",
        fill = TRUE
      ))
    }

    n_windows <- nrow(rv$optimized_windows$windows)
    has_coverage <- !is.null(rv$optimized_windows$statistics$coverage_percentage)
    coverage <- if (has_coverage) {
      sprintf("%.1f%% coverage", rv$optimized_windows$statistics$coverage_percentage)
    } else {
      "Optimized"
    }

    bs4InfoBox(
      title = "Windows Generated",
      value = n_windows,
      subtitle = coverage,
      icon = icon("layer-group"),
      color = "info",
      fill = TRUE
    )
  })

  # --- Output: Download Status Info Box ---
  output$download_status <- renderbs4InfoBox({
    # Guard clause: return "waiting" state early if not ready
    if (!rv$optimization_complete) {
      return(bs4InfoBox(
        title = "Export",
        value = "Waiting",
        subtitle = "Run optimization first",
        icon = icon("hourglass-half"),
        color = "warning",
        fill = TRUE
      ))
    }

    bs4InfoBox(
      title = "Export Ready",
      value = "Download",
      subtitle = "CSV & PDF available",
      icon = icon("file-download"),
      color = "success",
      fill = TRUE
    )
  })

  # --- Output: Conditional flags for UI ---
  output$data_loaded <- reactive({ rv$data_loaded })
  outputOptions(output, "data_loaded", suspendWhenHidden = FALSE)

  output$optimization_complete <- reactive({ rv$optimization_complete })
  outputOptions(output, "optimization_complete", suspendWhenHidden = FALSE)

  # --- Reactive: DPPP Quick Preview (responds to target_dppp and satisfaction changes) ---
  dppp_preview_reactive <- reactive({
    req(rv$validated_data)

    # Get current parameters (these trigger reactivity)
    target_dppp <- input$target_dppp
    target_satisfaction <- input$target_satisfaction / 100

    # Also consider calculated cycle time
    calc_ct <- cycle_time_result()
    current_ct <- if (!is.null(calc_ct)) calc_ct$cycle_time_sec else NULL

    # Calculate DPPP preview with current target
    tryCatch({
      quick_dppp_preview(
        rv$validated_data,
        cycle_times = c(1.0, 1.5, 2.0, 2.5, 3.0, 3.5),
        target_dppp = target_dppp,
        target_satisfaction = target_satisfaction
      )
    }, error = function(e) {
      cat("[Shiny] Error in DPPP preview:", e$message, "\n")
      NULL
    })
  })

  # --- Output: DPPP Quick Preview ---
  # Output: Current target DPPP for reactive display
  output$current_target_dppp <- renderText({
    sprintf("%.1f @ %d%% satisfaction", input$target_dppp, input$target_satisfaction)
  })

  output$fwhm_summary <- renderTable({
    preview <- dppp_preview_reactive()
    req(preview)
    fwhm <- preview$fwhm_stats
    data.frame(
      Metric = c("Median", "IQR (Q25-Q75)", "Range (Min-Max)"),
      Value = c(
        sprintf("%.2f sec", fwhm$median),
        sprintf("%.2f - %.2f sec", fwhm$q25, fwhm$q75),
        sprintf("%.2f - %.2f sec", fwhm$min, fwhm$max)
      )
    )
  }, striped = TRUE, hover = TRUE, spacing = "s")

  output$dppp_preview_table <- renderTable({
    preview <- dppp_preview_reactive()
    req(preview)

    # Explicitly depend on target_dppp to ensure reactivity
    target_dppp <- input$target_dppp
    target_satisfaction <- input$target_satisfaction

    # Get current cycle time for highlighting
    calc_ct <- cycle_time_result()
    current_ct <- if (!is.null(calc_ct)) calc_ct$cycle_time_sec else NA

    # Get DPPP data from preview (recalculated with current target_dppp)
    dppp_data <- preview$dppp_preview

    # Build display data with Status based on current target
    # Status shows "v Meet" if DPPP >= target, "x Below" if not
    display_df <- data.frame(
      `Cycle Time` = sprintf("%.1f sec", dppp_data$cycle_time_sec),
      `DPPP` = sprintf("%.1f", dppp_data$dppp_median),
      `Satisfaction` = sprintf("%.0f%%", dppp_data$satisfaction_pct),
      `Status` = ifelse(
        dppp_data$satisfaction_pct >= target_satisfaction,
        sprintf("v >=%d%%", target_satisfaction),
        sprintf("x <%d%%", target_satisfaction)
      ),
      check.names = FALSE
    )

    display_df
  }, striped = TRUE, hover = TRUE, spacing = "s")

  output$dppp_recommendation <- renderUI({
    preview <- dppp_preview_reactive()
    req(preview)

    target <- input$target_dppp
    satisfaction <- input$target_satisfaction
    rec_ct <- preview$recommended_cycle_time

    # Get calculated cycle time
    calc_ct <- cycle_time_result()
    current_ct <- if (!is.null(calc_ct)) calc_ct$cycle_time_sec else NULL

    # Handle NA values
    if (is.null(rec_ct) || is.na(rec_ct)) {
      return(tags$div(
        class = "recommendation-box",
        tags$p("Recommendation not available - FWHM data may be missing.",
               style = "color: #e74c3c;")
      ))
    }

    # Check if current cycle time meets requirements
    meets_target <- !is.null(current_ct) && current_ct <= rec_ct

    tags$div(
      style = "padding: 10px; border-radius: 6px; background: #f8f9fa;",

      # Main recommendation
      tags$div(
        style = "display: flex; align-items: center; gap: 8px; margin-bottom: 8px;",
        icon("lightbulb", style = "color: #f39c12; font-size: 18px;"),
        tags$strong("Target Requirements", style = "color: #2c3e50;")
      ),
      tags$p(
        style = "margin: 0 0 8px 0; font-size: 13px; color: #34495e;",
        sprintf("For DPPP >= %.1f with %d%% satisfaction:", target, satisfaction)
      ),
      tags$p(
        style = "margin: 0 0 12px 0; font-size: 14px;",
        "Required cycle time <= ",
        tags$strong(sprintf("%.2f sec", rec_ct), style = "color: #16a085; font-size: 16px;")
      ),

      # Current status
      if (!is.null(current_ct)) {
        if (meets_target) {
          tags$div(
            style = "padding: 8px; background: #d4edda; border-radius: 4px; border-left: 3px solid #28a745;",
            tags$span(
              style = "color: #155724; font-weight: 600;",
              sprintf("Your current cycle time (%.2f sec) MEETS the requirement!", current_ct)
            )
          )
        } else {
          # Calculate how much reduction is needed
          reduction_needed <- current_ct - rec_ct
          reduction_pct <- (reduction_needed / current_ct) * 100

          tags$div(
            style = "padding: 8px; background: #f8d7da; border-radius: 4px; border-left: 3px solid #dc3545;",
            tags$span(
              style = "color: #721c24; font-weight: 600;",
              sprintf("Current: %.2f sec -> Need: <=%.2f sec", current_ct, rec_ct)
            ),
            tags$br(),
            tags$span(
              style = "color: #721c24; font-size: 12px;",
              sprintf("Reduce cycle time by %.1f sec (%.0f%% reduction needed)", reduction_needed, reduction_pct)
            ),
            tags$br(),
            tags$span(
              style = "color: #856404; font-size: 11px; font-style: italic;",
              "Tip: Use fewer windows, faster scan rate, or lower target DPPP"
            )
          )
        }
      }
    )
  })

  # --- Output: Sidebar Data Summary (compact) ---
  output$sidebar_data_summary <- renderUI({
    req(rv$validated_data)
    data <- rv$validated_data$data
    fwhm_sec <- ensure_fwhm_seconds(data$FWHM)

    tags$div(
      style = "font-size: 11px; color: #bdc3c7; line-height: 1.9;",
      tags$div(sprintf("Precursors: %s", format(nrow(data), big.mark = ","))),
      tags$div(sprintf("RT: %.1f - %.1f min", min(data$RT.Apex), max(data$RT.Apex))),
      tags$div(sprintf("m/z: %.0f - %.0f Da", min(data$Precursor.Mz), max(data$Precursor.Mz))),
      tags$div(sprintf("FWHM: %.2f sec (median)", median(fwhm_sec, na.rm = TRUE))),
      tags$div(sprintf("FWHM IQR: %.2f - %.2f sec",
                       quantile(fwhm_sec, 0.25, na.rm = TRUE),
                       quantile(fwhm_sec, 0.75, na.rm = TRUE)))
    )
  })

  # --- Output: Sidebar Pipeline Status (compact) ---
  output$sidebar_pipeline_status <- renderUI({
    data_ok <- rv$data_loaded
    opt_ok <- rv$optimization_complete

    data_text <- if (data_ok) "Loaded" else "Waiting"
    data_color <- if (data_ok) "#27ae60" else "#7f8c8d"

    opt_text <- if (opt_ok && !is.null(rv$optimized_windows)) {
      sprintf("%d windows", nrow(rv$optimized_windows$windows))
    } else "Pending"
    opt_color <- if (opt_ok) "#27ae60" else "#7f8c8d"

    export_text <- if (opt_ok) "Ready" else "Waiting"
    export_color <- if (opt_ok) "#27ae60" else "#7f8c8d"

    tags$div(
      style = "font-size: 11px; line-height: 2.0;",
      tags$div(style = sprintf("color: %s;", data_color),
               tags$span(HTML("&#9679;"), style = "margin-right: 4px;"), "Data: ", data_text),
      tags$div(style = sprintf("color: %s;", opt_color),
               tags$span(HTML("&#9679;"), style = "margin-right: 4px;"), "Optimized: ", opt_text),
      tags$div(style = sprintf("color: %s;", export_color),
               tags$span(HTML("&#9679;"), style = "margin-right: 4px;"), "Export: ", export_text)
    )
  })

  # --- Output: FWHM Distribution Ridgeline (by charge, top 3) ---
  output$fwhm_ridgeline <- renderPlot({
    req(rv$validated_data)
    data <- rv$validated_data$data
    fwhm_sec <- ensure_fwhm_seconds(data$FWHM)

    # Precursor.Charge is in QC_COLUMNS (kept if available, not required)
    has_charge <- "Precursor.Charge" %in% colnames(data)
    charge <- if (has_charge) as.integer(data$Precursor.Charge) else rep(NA_integer_, length(fwhm_sec))

    plot_data <- data.frame(FWHM = fwhm_sec, Charge = charge)
    plot_data <- plot_data[!is.na(plot_data$FWHM), ]

    # Fallback to simple density if no charge data
    if (!has_charge || all(is.na(plot_data$Charge))) {
      plot_data$Charge <- factor("All")
      return(
        ggplot2::ggplot(plot_data, ggplot2::aes(x = FWHM, y = Charge, fill = Charge)) +
          ggridges::geom_density_ridges(alpha = 0.7) +
          ggplot2::labs(x = "FWHM (sec)", y = NULL) +
          ggplot2::theme_minimal(base_size = 12) +
          ggplot2::theme(
            legend.position = "none",
            panel.grid.minor = ggplot2::element_blank(),
            plot.background = ggplot2::element_rect(fill = "transparent", color = NA),
            panel.background = ggplot2::element_rect(fill = "transparent", color = NA)
          )
      )
    }

    plot_data <- plot_data[!is.na(plot_data$Charge), ]

    # Top 3 charges by count
    charge_counts <- sort(table(plot_data$Charge), decreasing = TRUE)
    top_charges <- names(charge_counts)[seq_len(min(3, length(charge_counts)))]
    plot_data <- plot_data[plot_data$Charge %in% as.integer(top_charges), ]
    plot_data$Charge <- factor(plot_data$Charge, levels = sort(unique(plot_data$Charge)))

    ggplot2::ggplot(plot_data, ggplot2::aes(x = FWHM, y = Charge, fill = Charge)) +
      ggridges::geom_density_ridges(alpha = 0.7, scale = 1.2) +
      viridis::scale_fill_viridis(discrete = TRUE, option = "D") +
      ggplot2::labs(x = "FWHM (sec)", y = "Charge") +
      ggplot2::theme_minimal(base_size = 12) +
      ggplot2::theme(
        legend.position = "none",
        panel.grid.minor = ggplot2::element_blank(),
        plot.background = ggplot2::element_rect(fill = "transparent", color = NA),
        panel.background = ggplot2::element_rect(fill = "transparent", color = NA)
      )
  }, bg = "transparent")

  # --- Output: Data Summary Table ---
  output$data_summary <- renderTable({
    req(rv$validated_data)

    data <- rv$validated_data$data

    fwhm_sec <- ensure_fwhm_seconds(data$FWHM)
    median_fwhm_sec <- median(fwhm_sec, na.rm = TRUE)

    data.frame(
      Metric = c(
        "Total Precursors",
        "RT Range (min)",
        "m/z Range",
        "Median FWHM (sec)"
      ),
      Value = c(
        format(nrow(data), big.mark = ","),
        sprintf("%.1f - %.1f", min(data$RT.Apex), max(data$RT.Apex)),
        sprintf("%.1f - %.1f", min(data$Precursor.Mz), max(data$Precursor.Mz)),
        sprintf("%.2f", median_fwhm_sec)
      )
    )
  })
}
