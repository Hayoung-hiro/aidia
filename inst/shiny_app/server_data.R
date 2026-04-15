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
      shinyjs::enable(selector = "a[data-value=\047setup\047]")
      rv$optimization_complete <- FALSE
      rv$optimized_windows <- NULL

      # Cache FWHM conversion (immutable until next upload)
      rv$fwhm_sec <- ensure_fwhm_seconds(rv$validated_data$data$FWHM)
      rv$median_fwhm_sec <- median(rv$fwhm_sec, na.rm = TRUE)

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

  output$dppp_preview_table <- renderUI({
    preview <- dppp_preview_reactive()
    req(preview)

    target_dppp <- input$target_dppp
    target_satisfaction <- input$target_satisfaction
    dppp_data <- preview$dppp_preview

    # Build rows with conditional highlighting
    rows <- lapply(seq_len(nrow(dppp_data)), function(i) {
      meets <- dppp_data$dppp_median[i] >= target_dppp &&
               dppp_data$satisfaction_pct[i] >= target_satisfaction

      row_style <- if (meets) {
        "background: var(--semantic-success-bg); font-weight: 600;"
      } else {
        ""
      }

      status_cell <- if (meets) {
        tags$td(class = "text-semantic-success", style = "font-weight: 700;",
                icon("check-circle"), " PASS")
      } else {
        tags$td(class = "text-muted", "Below")
      }

      tags$tr(
        style = row_style,
        tags$td(sprintf("%.1f sec", dppp_data$cycle_time_sec[i])),
        tags$td(sprintf("%.1f", dppp_data$dppp_median[i])),
        tags$td(sprintf("%.0f%%", dppp_data$satisfaction_pct[i])),
        status_cell
      )
    })

    tags$table(
      class = "table table-sm",
      style = "font-size: 13px;",
      tags$thead(
        tags$tr(
          class = "panel-raised", style = "font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px;",
          tags$th("Cycle Time"),
          tags$th("DPPP"),
          tags$th("Satisfaction"),
          tags$th("Status")
        )
      ),
      tags$tbody(rows)
    )
  })

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
               class = "text-semantic-danger")
      ))
    }

    # Check if current cycle time meets requirements
    meets_target <- !is.null(current_ct) && current_ct <= rec_ct

    tags$div(
      class = "panel-raised", style = "padding: 10px;",

      # Main recommendation
      tags$div(
        style = "display: flex; align-items: center; gap: 8px; margin-bottom: 8px;",
        icon("lightbulb", class = "text-semantic-warning", style = "font-size: 18px;"),
        tags$strong("Target Requirements")
      ),
      tags$p(
        style = "margin: 0 0 8px 0; font-size: 13px;",
        sprintf("For DPPP >= %.1f with %d%% satisfaction:", target, satisfaction)
      ),
      tags$p(
        style = "margin: 0 0 12px 0; font-size: 14px;",
        "Required cycle time <= ",
        tags$strong(sprintf("%.2f sec", rec_ct), class = "text-accent", style = "font-size: 16px;")
      ),

      # Current status
      if (!is.null(current_ct)) {
        if (meets_target) {
          tags$div(
            class = "status-pass",
            tags$span(
              class = "status-text",
              sprintf("Your current cycle time (%.2f sec) MEETS the requirement!", current_ct)
            )
          )
        } else {
          # Calculate how much reduction is needed
          reduction_needed <- current_ct - rec_ct
          reduction_pct <- (reduction_needed / current_ct) * 100

          tags$div(
            class = "status-fail",
            tags$span(
              class = "status-text",
              sprintf("Current: %.2f sec -> Need: <=%.2f sec", current_ct, rec_ct)
            ),
            tags$br(),
            tags$span(
              class = "status-text", style = "font-size: 12px;",
              sprintf("Reduce cycle time by %.1f sec (%.0f%% reduction needed)", reduction_needed, reduction_pct)
            ),
            tags$br(),
            tags$span(
              class = "text-muted", style = "font-size: 11px; font-style: italic;",
              "Tip: Use fewer windows, faster scan rate, or lower target DPPP"
            )
          )
        }
      }
    )
  })

  # --- Output: Window Count Preview in DPPP Target Section (Step 2) ---
  output$dppp_window_count_preview <- renderUI({
    req(rv$validated_data)
    calc_ct <- cycle_time_result()
    req(calc_ct)

    median_fwhm <- rv$median_fwhm_sec
    target <- input$target_dppp
    req(target)
    ms2_sec <- calc_ct$ms2$scan_time_ms / 1000

    est_windows <- estimate_window_count_preview(median_fwhm, target, ms2_sec)

    tags$div(
      class = "panel-accent", style = "margin-top: 10px;",
      tags$span(style = "font-size: 13px;", "Estimated windows: "),
      tags$strong(class = "text-accent", style = "font-size: 16px;", est_windows),
      tags$span(class = "text-muted", style = "font-size: 12px;",
                sprintf(" (at DPPP %.1f, CT %.2fs)", target, calc_ct$cycle_time_sec))
    )
  })

  # --- Output: Sidebar Data Summary (compact) ---
  output$sidebar_data_summary <- renderUI({
    req(rv$validated_data)
    data <- rv$validated_data$data
    fwhm_sec <- rv$fwhm_sec

    tags$div(
      class = "text-muted", style = "font-size: 11px; line-height: 1.9;",
      tags$div(sprintf("Precursors: %s", format(nrow(data), big.mark = ","))),
      tags$div(sprintf("RT: %.1f - %.1f min", min(data$RT.Apex), max(data$RT.Apex))),
      tags$div(sprintf("m/z: %.0f - %.0f Da", min(data$Precursor.Mz), max(data$Precursor.Mz))),
      tags$div(sprintf("FWHM: %.2f sec (median)", rv$median_fwhm_sec)),
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
    data_class <- if (data_ok) "pipeline-active" else "pipeline-pending"

    opt_text <- if (opt_ok && !is.null(rv$optimized_windows)) {
      sprintf("%d windows", nrow(rv$optimized_windows$windows))
    } else "Pending"
    opt_class <- if (opt_ok) "pipeline-active" else "pipeline-pending"

    export_text <- if (opt_ok) "Ready" else "Waiting"
    export_class <- if (opt_ok) "pipeline-active" else "pipeline-pending"

    tags$div(
      style = "font-size: 11px; line-height: 2.0;",
      tags$div(class = data_class,
               tags$span(HTML("&#9679;"), style = "margin-right: 4px;"), "Data: ", data_text),
      tags$div(class = opt_class,
               tags$span(HTML("&#9679;"), style = "margin-right: 4px;"), "Optimized: ", opt_text),
      tags$div(class = export_class,
               tags$span(HTML("&#9679;"), style = "margin-right: 4px;"), "Export: ", export_text)
    )
  })

  # --- Output: FWHM Distribution Ridgeline (by charge, top 3) ---
  output$fwhm_ridgeline <- renderPlot({
    req(rv$validated_data)
    data <- rv$validated_data$data
    fwhm_sec <- rv$fwhm_sec

    # Precursor.Charge is in QC_COLUMNS (kept if available, not required)
    has_charge <- "Precursor.Charge" %in% colnames(data)
    charge <- if (has_charge) as.integer(data$Precursor.Charge) else rep(NA_integer_, length(fwhm_sec))

    plot_data <- data.frame(FWHM = fwhm_sec, Charge = charge)
    plot_data <- plot_data[!is.na(plot_data$FWHM), ]

    # Data-adaptive x-axis: focus on distribution shape, trim long tail
    # Use P95 * 1.3 to capture the main peak with slight headroom, not extreme outliers
    fwhm_p95 <- quantile(plot_data$FWHM, 0.95, na.rm = TRUE)
    xlim_max <- max(10, ceiling(fwhm_p95 * 1.3))

    # Fallback to simple density if no charge data
    if (!has_charge || all(is.na(plot_data$Charge))) {
      plot_data$Charge <- factor("All")
      return(
        ggplot2::ggplot(plot_data, ggplot2::aes(x = FWHM, y = Charge, fill = Charge)) +
          ggridges::geom_density_ridges(alpha = 0.7) +
          ggplot2::coord_cartesian(xlim = c(0, xlim_max)) +
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
      ggplot2::coord_cartesian(xlim = c(0, xlim_max)) +
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

    s <- compute_data_summary(rv$validated_data)

    data.frame(
      Metric = c(
        "Total Precursors",
        "RT Range (min)",
        "m/z Range",
        "Median FWHM (sec)"
      ),
      Value = c(
        format(s$n_final, big.mark = ","),
        sprintf("%.1f - %.1f", s$rt_min, s$rt_max),
        sprintf("%.1f - %.1f", s$mz_min, s$mz_max),
        sprintf("%.2f", s$fwhm_median_sec)
      )
    )
  })
}
