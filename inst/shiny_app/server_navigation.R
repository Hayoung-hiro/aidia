# Navigation explains unmet prerequisites instead of disabling click targets.
.shiny_prepare_issues <- function(input, data_loaded, cycle, data_error = NULL) {
  issues <- character()
  if (!isTRUE(data_loaded)) {
    issues[["parquet_file"]] <- if (!is.null(data_error))
      paste("Choose a valid report.parquet file. Upload failed:", data_error)
      else "Upload a report.parquet file before continuing."
  }
  fields <- c(current_window_count = "Input windows per cycle")
  if (isTRUE(input$instrument %in% c("astral", "astral_zoom"))) {
    fields <- c(fields, astral_ms2_it = "MS2 injection time")
  } else {
    if (!isTRUE(input$ms1_it_auto)) fields <- c(fields, ms1_it_custom = "MS1 maximum injection time")
    if (!isTRUE(input$ms2_it_auto)) fields <- c(fields, ms2_it_custom = "MS2 maximum injection time")
  }
  for (id in names(fields)) {
    value <- input[[id]]
    if (length(value) != 1L || !is.finite(value) || value <= 0) {
      issues[[id]] <- sprintf("Enter a positive value for %s.", fields[[id]])
    }
  }
  if (!"current_window_count" %in% names(issues) && input$current_window_count != floor(input$current_window_count))
    issues[["current_window_count"]] <- "Enter a whole number of input windows."
  original_defaults <- list(original_mz_min = 400, original_mz_max = 1000)
  original <- lapply(names(original_defaults), function(id)
    if (id %in% names(input)) input[[id]] else original_defaults[[id]])
  names(original) <- names(original_defaults)
  for (id in names(original)) {
    value <- original[[id]]
    if (length(value) != 1L || !is.finite(value) || value <= 0)
      issues[[id]] <- "Enter a positive original m/z boundary."
  }
  if (!any(names(original) %in% names(issues)) && original$original_mz_min >= original$original_mz_max)
    issues[["original_mz_max"]] <- "Original m/z end must be above the start."
  if (is.null(cycle) && length(issues) == 0L)
    issues[["instrument"]] <- "Check the instrument and MS1/MS2 settings so acquisition timing can be calculated."
  issues
}

server_navigation <- function(input, output, session, rv, cycle_time_result) {
  attempted <- reactiveVal(FALSE)
  issues <- reactive(.shiny_prepare_issues(input, rv$data_loaded,
    cycle_time_result(), rv$data_error))
  observe({
    session$sendCustomMessage("workflow-validation", list(scope = "prepare", issues = as.list(issues())))
  })
  output$prepare_navigation_feedback <- renderUI({
    messages <- issues()
    if (!length(messages) || !attempted()) return(NULL)
    div(class = paste("workflow-navigation-feedback", if (attempted()) "needs-attention"),
      role = "status", "Complete the highlighted field to continue.")
  })
  go <- function(target) {
    if (identical(target, "setup") && length(issues())) {
      attempted(TRUE)
      updateTabItems(session, "tabs", "data")
      session$sendCustomMessage("workflow-focus", names(issues())[[1]])
    } else if (identical(target, "results") && !isTRUE(rv$optimization_complete)) {
      showNotification("Confirm your window settings in step 2 to prepare results and downloads.", type = "message")
      go("setup")
    } else updateTabItems(session, "tabs", target)
  }
  observeEvent(input$btn_to_setup, go("setup"))
  observeEvent(input$workflow_navigate, {
    if (input$workflow_navigate %in% c("data", "setup", "results")) go(input$workflow_navigate)
  })
  observeEvent(rv$validated_data, attempted(FALSE), ignoreNULL = FALSE)
}
