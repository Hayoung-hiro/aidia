# The selected target and margin guide suggestions; applying a suggestion writes
# the same custom offset used by manual entry and the window-generation worker.
server_fz_boundary <- function(input, output, session, rv) {
  profile <- reactive({
    if (is.null(rv$validated_data)) return(NULL)
    aidia:::prepare_fz_profile(aidia:::get_precursor_data(rv$validated_data))
  })
  target <- reactive(input$fz_target %||% "z2")
  margin <- reactive({
    value <- input$fz_margin
    if (is.null(value) && !"fz_margin" %in% names(input)) value <- .05
    req(length(value) == 1L, is.finite(value), value >= .001, value <= .25)
    value
  })
  suggestion <- reactive({
    req(profile(), target() %in% c("z2", "all"))
    aidia:::suggest_fz_offset(profile(), target(), margin())
  })
  observe({
    model <- profile()
    session$sendCustomMessage("aidia:fz-profile", list(profile = if (is.null(model)) NULL else
      list(groups = lapply(model$groups, function(group) {
        group$phase <- I(group$phase)
        group
      }), increment = model$increment)))
  })
  output$fz_validation_plot <- renderPlot({
    model <- profile()
    if (is.null(model)) return(NULL)
    aidia:::plot_fz_phase_histogram(if (target() == "z2") model$z2 else model$phase,
      if (target() == "z2") "2+ precursors" else "All charges")
  }, res = 96, bg = "transparent",
    alt = "Precursor phase histogram for the selected charge target. Drag the boundary to choose an offset.")

  # A separate diagnostic view: changing it must not change the scoring target.
  diagnostic_by_charge <- reactive(identical(input$fz_diagnostic_view, "charge"))
  diagnostic_cells <- reactive({
    req(profile())
    aidia:::prepare_fz_diagnostic(profile(), diagnostic_by_charge())
  })
  selected_offset <- reactive({
    preset <- input$fz_offset_preset
    req(preset, preset != "0")
    value <- if (preset == "custom") input$custom_fz_offset else as.numeric(preset)
    req(length(value) == 1L, is.finite(value), value >= .0001, value <= .9999)
    value
  })
  output$fz_diagnostic_plot <- renderPlot({
    aidia:::plot_fz_diagnostic(diagnostic_cells(), selected_offset(), margin())
  }, height = function() {
    160 + 170 * max(1L, length(unique(diagnostic_cells()$charge)))
  }, res = 96, bg = "transparent",
    alt = "Precursor phase versus m/z. The horizontal line is the selected offset; dashed lines bound the comparison band.")
  output$fz_local_counts <- renderTable({
    req(profile())
    summary <- aidia:::summarize_fz_mz_bins(profile(), selected_offset(), margin(),
      diagnostic_by_charge())
    req(nrow(summary))
    data.frame(Charge = as.character(summary$charge),
      `m/z interval` = sprintf("[%g, %g)", summary$mz_lower, summary$mz_lower + 50),
      `In band / total` = paste0(format(summary$near, big.mark = ",", trim = TRUE),
        " / ", format(summary$n, big.mark = ",", trim = TRUE)),
      `In band (%)` = sprintf("%.2f", 100 * summary$fraction), check.names = FALSE)
  }, striped = TRUE, bordered = FALSE, spacing = "xs", width = "100%")

  output$fz_charge_summary <- renderText({
    model <- profile()
    req(model)
    paste(vapply(model$groups, function(group) sprintf("%s: %s (%.1f%%)", group$label,
      format(group$n, big.mark = ","), 100 * group$n / model$n), character(1)), collapse = " | ")
  })
  output$fz_recommendation <- renderUI({
    result <- suggestion()
    if (is.null(result$offset)) return(tags$span(class = "text-muted", result$reason))
    applied <- isTRUE(all.equal(selected_offset(), result$offset, tolerance = 1e-8))
    div(class = "fz-optimum",
      tags$strong(sprintf("Optimal offset: %.4f", result$offset)),
      if (applied) tags$span(class = "fz-applied", icon("check"), "Applied"),
      tags$span(class = "fz-optimum-detail", sprintf("Fewest %s in the edge band: %s / %s (\u00b1%.3f m/z)",
        if (target() == "z2") "2+ precursors" else "precursors",
        format(result$target_count, big.mark = ","), format(result$target_n, big.mark = ","), margin())))
  })
  observe({
    valid <- length(input$fz_margin) == 1L && is.finite(input$fz_margin) &&
      input$fz_margin >= .001 && input$fz_margin <= .25
    enabled <- valid && !is.null(profile()) && isTRUE(input$fz_offset_preset != "0") &&
      !is.null(suggestion()$offset)
    session$sendCustomMessage("aidia:fz-suggestion-enabled", list(enabled = enabled))
  })
  observeEvent(input$fz_apply_suggestion, {
    req(input$fz_offset_preset != "0")
    result <- suggestion()
    req(result$offset)
    updateNumericInput(session, "custom_fz_offset", value = result$offset)
    updateSelectInput(session, "fz_offset_preset", selected = "custom")
  })
}
