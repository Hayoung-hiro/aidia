# Session-owned templates survive draft changes until the session ends, so a
# confirmed result always retains the exact template used for that analysis.
server_method <- function(input, output, session, rv) {
  directory <- tempfile("aidia_method_templates_")
  dir.create(directory)
  session$onSessionEnded(function() unlink(directory, recursive = TRUE))
  rv$method_context <- NULL
  rv$method_error <- NULL

  output$adaptive_rt_available <- renderText({
    if (identical(rv$confirmed_run$method$instrument, "astral_zoom")) "true" else "false"
  })
  outputOptions(output, "adaptive_rt_available", suspendWhenHidden = FALSE)

  observeEvent(input$method_file, {
    upload <- input$method_file
    rv$method_context <- NULL
    rv$method_error <- NULL
    session$sendCustomMessage("workflow-upload-state", list(id = "method_file", state = "reading"))
    showNotification("Reading acquisition method...", id = "method_import", duration = NULL)
    tryCatch({
      if (!grepl("\\.meth$", upload$name, ignore.case = TRUE) || upload$size > 64 * 1024^2)
        stop("Choose a .meth file no larger than 64 MB.")
      path <- tempfile("template_", tmpdir = directory, fileext = ".meth")
      if (!file.copy(upload$datapath, path)) stop("Could not keep a copy of the method template.")
      method <- inspect_thermo_method(path)
      method$filename <- upload$name
      updateSelectInput(session, "instrument", selected = method$instrument)
      for (level in c("ms1", "ms2")) {
        scan <- method[[level]]
        resolutions <- sort(unique(c(if (level == "ms1") c(15000, 30000, 60000, 120000, 240000, 480000)
          else c(7500, 15000, 30000, 45000, 60000, 120000, 240000), scan$resolution)))
        resolution_id <- if (method$instrument == "astral_zoom" && level == "ms1") "astral_ms1_resolution" else paste0(level, "_resolution")
        if (length(scan$resolution)) updateSelectInput(session, resolution_id,
          choices = setNames(as.character(resolutions), format(resolutions, big.mark = ",", trim = TRUE)),
          selected = as.character(scan$resolution))
        updateCheckboxInput(session, paste0(level, "_it_auto"), value = scan$max_it_mode == "Auto")
        updateNumericInput(session, paste0(level, "_it_custom"), value = scan$max_it_ms)
        updateNumericInput(session, paste0(level, "_agc"), value = scan$agc_percent)
      }
      if (method$instrument == "astral_zoom")
        updateSliderInput(session, "astral_ms2_it", value = method$ms2$max_it_ms,
          min = min(2, method$ms2$max_it_ms), max = max(40, method$ms2$max_it_ms), step = 0.1)
      updateNumericInput(session, "ms1_scans_per_cycle", value = method$ms1_scans_per_cycle)
      updateNumericInput(session, "current_window_count", value = method$window_count)
      updateNumericInput(session, "original_mz_min", value = method$mz_min)
      updateNumericInput(session, "original_mz_max", value = method$mz_max)
      rv$method_context <- method
      session$sendCustomMessage("workflow-upload-state", list(id = "method_file", state = "ready"))
    }, error = function(e) {
      rv$method_error <- conditionMessage(e)
      session$sendCustomMessage("workflow-upload-state", list(id = "method_file", state = "error"))
      showNotification(rv$method_error, type = "error", duration = 12)
    }, finally = removeNotification("method_import"))
  })

  observeEvent(input$remove_method, {
    rv$method_context <- NULL
    rv$method_error <- NULL
    shinyjs::reset("method_file")
    session$sendCustomMessage("workflow-upload-state", list(id = "method_file", state = "empty"))
  })

  output$method_import_status <- renderUI({
    if (!is.null(rv$method_error)) return(div(class = "workflow-field-error", role = "alert", rv$method_error))
    method <- rv$method_context
    if (is.null(method)) return(tags$p(class = "workflow-file-note",
      "Auto-fill acquisition settings and enable .meth export."))
    report_rt <- rv$validated_data$data$RT.Apex
    report_rt <- report_rt[is.finite(report_rt)]
    mismatch <- if (length(report_rt) && max(report_rt) > method$duration_min)
      div(class = "workflow-field-error", role = "alert",
        sprintf(paste0("Report RT reaches %.2f min; this template ends at %.2f min. ",
          "Native .meth output needs a template covering the designed RT schedule. ",
          "Use a matching method/report pair. You can still analyze the data and export CSV."),
          max(report_rt), method$duration_min)) else NULL
    div(class = "workflow-template-status", role = "status",
      div(class = "workflow-template-line",
        span(sprintf("%s | %g min", method$model, method$duration_min)),
        actionButton("remove_method", "Remove", class = "btn-link btn-sm")),
      tags$details(class = "workflow-template-details",
        tags$summary("Template details"),
        tags$p(class = "workflow-template-filename", method$filename),
        tags$p(sprintf("%d windows/cycle. Acquisition settings are shown below and can be edited.", method$window_count)),
        if (identical(method$native_output_scan_type, "tMS2")) tags$p(sprintf(
          "Template MS2: %s. Native output: Full Scan + scheduled tMS2, with window widths and RT ranges in one table.",
          method$ms2_scan_type)),
        if (length(method$expected_peak_width_sec)) tags$p(sprintf(
          "Expected peak width: %g s (method setting, preserved on export). Peak sampling uses the report's measured FWHM.",
          method$expected_peak_width_sec))),
      mismatch)
  })

  previous_native <- FALSE
  previous_template <- NULL
  observeEvent(rv$confirmed_run, {
    method <- rv$confirmed_run$method
    available <- !is.null(method)
    # Seed export controls only when the confirmed template changes. Draft
    # uploads and reconfirming the same template preserve the user's choices.
    if (available && !identical(previous_template, method$sha256)) {
      updateNumericInput(session, "acquisition_end_min", value = method$duration_min)
      updateCheckboxInput(session, "fill_void", value = TRUE)
      updateNumericInput(session, "export_charge_state", value = 0L)
    } else if (!available && previous_native) {
      # Do not carry template-specific defaults into a template-free result.
      updateNumericInput(session, "acquisition_end_min", value = NA_real_)
      updateCheckboxInput(session, "fill_void", value = FALSE)
      updateNumericInput(session, "export_charge_state", value = 1L)
    }
    previous_template <<- method$sha256
    choices <- c("Thermo Targeted Mass List" = "thermo", "Center Mass List" = "center_mass", "m/z Range List" = "mz_range")
    if (available) choices <- c("Thermo native method (.meth)" = "native", choices)
    selected <- isolate(input$export_format) %||% "thermo"
    if (available && !previous_native) selected <- "native"
    if (!selected %in% choices) selected <- "thermo"
    previous_native <<- available
    updateSelectInput(session, "export_format", choices = choices, selected = selected)
  }, ignoreNULL = FALSE)
}
