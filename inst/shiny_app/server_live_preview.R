# Draft computation and confirmed delivery are separate session-owned snapshots.
.shiny_setup_defaults <- function(instrument) {
  widths <- get_instrument_width_recommendations(get_instrument_config(instrument))
  list(
    sampling = list(target_dppp = 7, target_satisfaction = 70, ms1_scans_per_cycle = 1),
    windows = list(mz_strategy = "kde", window_mode = "density", auto_windows = TRUE,
      manual_n_windows = 40, greedy_range_width = 200, greedy_mz_step = 2, greedy_apply_smoothing = TRUE,
      quantile_exclude_low = 5, quantile_exclude_high = 5, quantile_apply_smoothing = TRUE,
      target_coverage = 90, outlier_threshold = 3, outlier_apply_smoothing = TRUE,
      kde_density_threshold = 10, kde_min_coverage = 80,
      min_isolation_width = widths$min_width_da, max_isolation_width = widths$max_width_da,
      fz_offset_preset = "0.25", custom_fz_offset = 0.25),
    rt = list(rt_binning_mode = "fixed", rt_bin_width = 5, cpd_significance = 0.05,
      cpd_min_bin_width = 1, edge_void_buffer = 0.5, edge_wash_threshold = 30)
  )
}

.shiny_same_request <- function(run, request) {
  !is.null(run) && !is.null(request) &&
    identical(run$data_version, request$data_version) &&
    identical(run$settings, request$settings) &&
    identical(run$cycle, request$cycle)
}

.shiny_background_task <- function() {
  app_path <- .aidia_app_path
  package_path <- .aidia_package_path
  shiny::ExtendedTask$new(function(request) {
    promises::future_promise({
      worker <- new.env(parent = baseenv())
      sys.source(file.path(app_path, "preview_worker.R"), worker)
      # Return ordinary errors as data so the controller can match failed requests.
      tryCatch(worker$.shiny_preview_worker(request, package_path, app_path),
               error = function(e) list(error = conditionMessage(e), field = e$field))
    }, globals = list(request = request, app_path = app_path, package_path = package_path),
       packages = character(), seed = TRUE)
  })
}

server_live_preview <- function(input, output, session, rv, cycle_time_result,
                                task = .shiny_background_task()) {
  version <- reactiveVal(0L)
  preview <- reactiveVal(NULL)
  pending <- reactiveVal(NULL)
  active <- reactiveVal(NULL)
  failure <- reactiveVal(NULL)
  confirm_requested <- reactiveVal(NULL)

  settings <- reactive({
    instrument <- input$instrument %||% "astral"
    defaults <- do.call(c, unname(.shiny_setup_defaults(instrument)))
    values <- lapply(names(defaults), function(id) {
      if (id %in% names(input)) input[[id]] else defaults[[id]]
    })
    names(values) <- names(defaults)
    instrument_ids <- c("instrument", "ms1_resolution", "ms2_resolution",
      "ms1_it_auto", "ms1_it_custom", "ms2_it_auto", "ms2_it_custom",
      "astral_ms1_resolution", "astral_ms2_it", "current_window_count")
    original_defaults <- list(original_mz_min = 400, original_mz_max = 1000)
    original_values <- lapply(names(original_defaults), function(id)
      if (id %in% names(input)) input[[id]] else original_defaults[[id]])
    names(original_values) <- names(original_defaults)
    c(values, setNames(lapply(instrument_ids, function(id) input[[id]]), instrument_ids), original_values)
  })
  setup_issues <- reactive(c(
    .shiny_prepare_issues(settings(), TRUE, cycle_time_result()),
    .shiny_setup_issues(settings())))
  request <- reactive({
    req(rv$data_loaded, rv$validated_data)
    list(settings = settings(), cycle = cycle_time_result(),
         data_version = version(), data = rv$validated_data)
  })
  settled_request <- debounce(request, 400)

  observeEvent(rv$validated_data, {
    version(isolate(version()) + 1L)
    preview(NULL)
    pending(NULL)
    failure(NULL)
    confirm_requested(NULL)
    rv$confirmed_run <- NULL
  }, ignoreNULL = FALSE, priority = 100)

  publish <- function(run) {
    # Promoting a preview uses its exact result; it never recomputes from live input.
    rv$optimization_complete <- FALSE
    rv$confirmed_run <- run
    rv$optimization_plan <- run$plan
    rv$optimized_windows <- run$windows
    rv$optimization_complete <- TRUE
    confirm_requested(NULL)
    updateTabItems(session, "tabs", "results")
  }

  launch_pending <- function() {
    if (length(isolate(setup_issues()))) { pending(NULL); return() }
    next_request <- isolate(pending())
    if (is.null(next_request) || identical(isolate(task$status()), "running")) return()
    if (!.shiny_same_request(next_request, isolate(request()))) {
      pending(NULL)
      return()
    }
    pending(NULL)
    active(next_request)
    failure(NULL)
    task$invoke(next_request)
  }

  observeEvent(settled_request(), {
    req(rv$data_loaded)
    if (length(setup_issues())) { pending(NULL); return() }
    next_request <- settled_request()
    if (!.shiny_same_request(next_request, request())) return()
    if (.shiny_same_request(preview(), next_request)) return()
    if (.shiny_same_request(active(), next_request)) {
      pending(NULL)
      return()
    }
    if (.shiny_same_request(rv$confirmed_run, next_request)) {
      preview(rv$confirmed_run)
      failure(NULL)
      pending(NULL)
    } else {
      # Keep only the latest pending request, never a queue of slider movements.
      pending(next_request)
      launch_pending()
    }
  })

  observe({
    status <- task$status()
    if (!status %in% c("success", "error")) return()
    result <- tryCatch(task$result(), error = function(e) list(error = conditionMessage(e)))
    isolate({
      completed <- active()
      active(NULL)
      if (!is.null(completed) && isTRUE(rv$data_loaded) && !length(setup_issues()) &&
          .shiny_same_request(completed, request())) {
        if (!is.null(result$error)) {
          failure(list(request = completed, message = result$error, field = result$field))
          confirm_requested(NULL)
        } else {
          preview(result)
          failure(NULL)
          if (.shiny_same_request(confirm_requested(), completed)) publish(result)
        }
      }
      if (isTRUE(rv$data_loaded) && !is.null(pending())) launch_pending()
    })
  })

  observeEvent(input$run_optimization, {
    if (!isTRUE(rv$data_loaded) || length(setup_issues())) {
      id <- if (!isTRUE(rv$data_loaded)) "parquet_file" else names(setup_issues())[[1]]
      if (id %in% c("parquet_file", "instrument", "current_window_count", "astral_ms2_it", "ms1_it_custom", "ms2_it_custom", "original_mz_min", "original_mz_max"))
        updateTabItems(session, "tabs", "data")
      session$sendCustomMessage("workflow-focus", id)
      return()
    }
    current <- request()
    if (!is.null(failure()) && .shiny_same_request(failure()$request, current) &&
        !is.null(failure()$field)) {
      session$sendCustomMessage("workflow-focus", failure()$field)
      return()
    }
    if (.shiny_same_request(preview(), current)) {
      publish(preview())
    } else {
      confirm_requested(current)
      # Do not duplicate an already-running calculation for this same snapshot.
      if (!.shiny_same_request(active(), current)) {
        pending(current)
        launch_pending()
      }
    }
  })
  observeEvent(request(), {
    if (!is.null(confirm_requested()) &&
        !.shiny_same_request(confirm_requested(), request())) confirm_requested(NULL)
  })

  # Reset only the requested section. Instrument controls remain in Prepare data.
  slider_ids <- c("target_satisfaction", "manual_n_windows", "greedy_mz_step",
    "quantile_exclude_low", "quantile_exclude_high", "target_coverage", "outlier_threshold",
    "kde_density_threshold", "kde_min_coverage", "rt_bin_width", "cpd_significance",
    "cpd_min_bin_width")
  select_ids <- c("mz_strategy", "window_mode", "fz_offset_preset", "rt_binning_mode")
  for (group in c("sampling", "windows", "rt")) local({
    section <- group
    observeEvent(input[[paste0("reset_", section)]], {
      defaults <- .shiny_setup_defaults(input$instrument)[[section]]
      confirmed <- rv$confirmed_run
      baseline <- if (!is.null(confirmed) &&
                      identical(confirmed$settings$instrument, input$instrument)) {
        confirmed$settings[names(defaults)]
      } else defaults
      for (id in names(baseline)) {
        value <- baseline[[id]]
        if (id %in% slider_ids) updateSliderInput(session, id, value = value)
        else if (id %in% select_ids) updateSelectInput(session, id, selected = value)
        else if (is.logical(value)) updateCheckboxInput(session, id, value = value)
        else updateNumericInput(session, id, value = value)
      }
    })
  })

  state <- reactive({
    if (!isTRUE(rv$data_loaded)) return("empty")
    if (length(setup_issues())) return("invalid")
    current <- request()
    if (!is.null(failure()) && .shiny_same_request(failure()$request, current)) return("error")
    if (.shiny_same_request(rv$confirmed_run, current)) return("confirmed")
    if (.shiny_same_request(preview(), current)) return("ready")
    "updating"
  })
  rv$draft_state <- NULL
  observe({ rv$draft_state <- state() })
  observe({
    # Prepare-data errors are owned by server_navigation; keep each scope independent.
    issues <- .shiny_setup_issues(settings())
    if (state() == "error" && !is.null(failure()$field))
      issues[[failure()$field]] <- failure()$message
    session$sendCustomMessage("workflow-validation", list(scope = "setup", issues = as.list(issues)))
  })
  output$draft_status <- renderUI({
    label <- switch(state(), empty = "Upload data to preview",
      invalid = "Complete the settings below",
      error = "Preview needs attention", confirmed = "Confirmed settings",
      ready = "Preview ready - not confirmed", updating = "Updating preview...")
    div(class = paste("draft-status", paste0("draft-status-", state())),
      tags$span(class = "draft-status-label", label),
      if (!is.null(rv$confirmed_run) && state() != "confirmed")
        tags$span(class = "draft-status-note", "Downloads use the last confirmed result."))
  })
  output$setup_navigation_feedback <- renderUI({
    messages <- if (!isTRUE(rv$data_loaded)) "Upload a report.parquet file in step 1 before continuing." else setup_issues()
    if (length(messages)) return(div(class = "workflow-navigation-feedback needs-attention",
      role = "status", "Check the highlighted settings before confirming."))
    if (!is.null(confirm_requested())) div(class = "workflow-navigation-feedback", role = "status",
      "Calculating your preview. Results will open when it is ready.")
  })
  output$preview_error <- renderUI({
    if (state() == "error" && is.null(failure()$field))
      div(class = "workflow-field-error", role = "alert", failure()$message)
  })
  output$confirmed_status <- renderUI({
    req(rv$confirmed_run)
    if (state() == "confirmed") {
      div(class = "draft-status draft-status-confirmed", "Confirmed result - matches your settings")
    } else {
      div(class = "draft-status draft-status-ready",
          "Confirmed result - your edited settings have not been applied to these downloads.")
    }
  })

  output$sidebar_confirmed_method <- renderUI({
    run <- rv$confirmed_run
    if (is.null(run)) {
      return(div(class = "sidebar-method-content",
        tags$strong("No confirmed method"),
        tags$p(if (isTRUE(rv$data_loaded))
          "Confirm your settings in step 2 to prepare a download."
          else "Upload a report, then configure your windows.")))
    }
    mode <- switch(run$settings$window_mode,
      density = "Density", fixed = "Fixed", staggered = "Staggered")
    div(class = "sidebar-method-content",
      div(class = "sidebar-method-strategy",
        format_strategy_label(run$settings$mz_strategy), tags$span(mode)),
      tags$p(get_instrument_config(run$settings$instrument)$name),
      tags$p(sprintf("%s windows / %d RT groups",
        format(nrow(run$windows$windows), big.mark = ","),
        nrow(run$windows$rt_binning$rt_stats))),
      if (state() == "confirmed") {
        div(class = "sidebar-method-match", icon("check-circle"), " Matches current settings")
      } else {
        div(class = "sidebar-method-pending", icon("pencil-alt"),
          " Unconfirmed changes",
          tags$p("Downloads still use this confirmed method."))
      })
  })

  current_preview <- reactive({
    req(state() %in% c("ready", "confirmed"))
    if (state() == "confirmed") rv$confirmed_run else preview()
  })
  observe({
    rv$draft_plan <- if (state() %in% c("ready", "confirmed")) current_preview()$plan else NULL
  })
  # An old picture must never look like the result of new controls.
  output$preview_ready <- reactive({ state() %in% c("ready", "confirmed") })
  outputOptions(output, "preview_ready", suspendWhenHidden = FALSE)
  output$preview_waiting <- renderText({
    switch(state(), empty = "Upload data to see your m/z distribution.",
      invalid = "Complete the highlighted settings to update the preview.",
      error = if (!is.null(failure()$field)) "Correct the highlighted setting to update the preview."
        else "Adjust the settings or retry with Confirm & view results.",
      "Calculating the distribution and windows for your current settings...")
  })
  observeEvent(current_preview(), {
    run <- current_preview()
    bins <- run$windows$rt_binning$rt_stats
    choices <- c("All RT groups" = "all", setNames(as.character(bins$rt_segment_id),
      sprintf("%.1f - %.1f min", bins$rt_start, bins$rt_end)))
    selected <- isolate(input$preview_rt_bin)
    if (is.null(selected) || !selected %in% choices) selected <- "all"
    updateSelectInput(session, "preview_rt_bin", choices = choices, selected = selected)
  })
  selected_bin <- reactive({
    run <- current_preview()
    id <- input$preview_rt_bin
    slice <- .shiny_preview_slice(run, id)
    req(slice$profile)
    slice
  })
  output$live_mz_summary <- renderUI({
    b <- selected_bin()
    div(class = "preview-metrics",
      `data-preview-settings` = jsonlite::toJSON(b$run$settings, auto_unbox = TRUE, null = "null"),
      `data-preview-scope` = if (b$all) "all" else input$preview_rt_bin,
      if (b$all) tagList(
        tags$span(sprintf("%d RT groups | %s precursors",
          nrow(b$range), format(b$profile$n, big.mark = ","))),
        tags$span(sprintf("Window widths %.1f - %.1f Da",
          min(b$windows$window_width), max(b$windows$window_width)))
      ) else tagList(
        tags$span(sprintf("Selected range %.0f - %.0f m/z", b$range$mz_min, b$range$mz_max)),
        tags$span(sprintf("Range inclusion %.1f%%", b$range$coverage_ratio * 100)),
        tags$span(sprintf("%d precursors in this RT group", b$profile$n))),
      tags$span(sprintf("Whole-run window coverage %.1f%%", b$run$windows$statistics$coverage_percentage)))
  })
  output$live_mz_plot <- renderPlot({
    b <- selected_bin()
    if (b$all) {
      grid::grid.draw(b$run$overview)
      return(invisible(NULL))
    }
    h <- b$profile$histogram
    max_y <- max(h$density, b$profile$curve$density, na.rm = TRUE)
    plot <- ggplot2::ggplot() +
      ggplot2::geom_col(data = h, ggplot2::aes(x = mz, y = density), width = h$width,
                        fill = "#dde3e9") +
      ggplot2::annotate("rect", xmin = b$range$mz_min, xmax = b$range$mz_max,
                        ymin = 0, ymax = Inf, fill = "#087f70", alpha = 0.10)
    if (b$run$settings$mz_strategy == "kde" && !is.null(b$profile$curve)) {
      plot <- plot +
        ggplot2::geom_line(data = b$profile$curve, ggplot2::aes(x = mz, y = density),
                           color = "#536878", linewidth = 0.7) +
        ggplot2::geom_hline(yintercept = max(b$profile$curve$density) *
                             b$run$settings$kde_density_threshold / 100,
                           color = "#c38420", linetype = "dashed", linewidth = 0.6)
    }
    windows <- b$windows
    windows$band <- if ("cycle" %in% names(windows)) as.numeric(as.factor(windows$cycle)) else 1
    plot +
      ggplot2::geom_rect(data = windows,
        ggplot2::aes(xmin = mz_start, xmax = mz_end,
                     ymin = -max_y * (0.07 + 0.09 * band),
                     ymax = -max_y * (0.01 + 0.09 * band)),
        fill = "#a4d6cc", color = "#087f70", linewidth = 0.25) +
      ggplot2::labs(x = "m/z", y = "Density") +
      ggplot2::theme_minimal(base_size = 11) +
      ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                     plot.margin = ggplot2::margin(8, 12, 4, 8))
  }, res = 96, bg = "transparent")
}
