# server_optimization.R - Run Optimization, Results Display, Summary Tables

# Capture every strategy's controls together at execution time, including
# controls hidden by the currently selected strategy's conditional panel.
.shiny_strategy_configs <- function(input) {
  list(
    greedy = greedy_config(
      auto_windows = isTRUE(input$auto_windows %||% TRUE),
      n_windows = input$manual_n_windows %||% 40,
      mz_step = input$greedy_mz_step %||% 0.5,
      apply_smoothing = isTRUE(input$greedy_apply_smoothing %||% TRUE)
    ),
    quantile = quantile_config(
      lower = if (!is.null(input$quantile_exclude_low)) input$quantile_exclude_low / 100 else input$quantile_lower %||% 0.05,
      upper = if (!is.null(input$quantile_exclude_high)) 1 - input$quantile_exclude_high / 100 else input$quantile_upper %||% 0.95,
      apply_smoothing = isTRUE(input$quantile_apply_smoothing %||% TRUE)
    ),
    coverage = coverage_config(target = (input$target_coverage %||% 90) / 100),
    outlier = outlier_config(
      threshold = input$outlier_threshold %||% 3.0,
      apply_smoothing = isTRUE(input$outlier_apply_smoothing %||% TRUE)
    ),
    kde = kde_config(
      density_threshold = (input$kde_density_threshold %||% 10) / 100,
      min_coverage = (input$kde_min_coverage %||% 80) / 100
    )
  )
}

server_optimization <- function(input, output, session, rv, cycle_time_result) {

  # --- Helper: Loop N badge for staggered mode (used in After summary + m/z summary) ---
  render_loop_n_badge <- function(windows) {
    loop_n <- tryCatch(calculate_loop_n(windows), error = function(e) NULL)
    if (is.null(loop_n)) return(NULL)
    tags$div(
      class = "panel-accent", style = "margin-top: 6px; font-weight: 600;",
      icon("sync-alt"),
      sprintf(" Loop Control N = %d", loop_n),
      tags$span(class = "text-muted", style = "font-weight: 400; margin-left: 8px;",
                "(set in Xcalibur method)")
    )
  }

  # --- DPPP Preset Buttons ---
  # Preset clicks only update the numeric value; visual sync is handled
  # by the single target_dppp observer below via sendCustomMessage.
  observeEvent(input$preset_id, {
    updateNumericInput(session, "target_dppp", value = 1.5)
  })
  observeEvent(input$preset_balanced, {
    updateNumericInput(session, "target_dppp", value = 4.0)
  })
  observeEvent(input$preset_quant, {
    updateNumericInput(session, "target_dppp", value = 7.0)
  })

  # DPPP button visual sync is handled purely client-side in app.R
  # (no server round-trip needed for CSS class toggles)

  # --- Isotope Boundary Validation Plot (reactive to data + fz_offset) ---
  output$fz_validation_plot <- renderPlot({
    # Requires validated data
    if (is.null(rv$validated_data)) return(NULL)

    # Resolve FZ offset from UI inputs
    fz_offset <- if (isTRUE(input$fz_offset_preset == "custom")) {
      as.numeric(input$custom_fz_offset %||% 0.25)
    } else {
      as.numeric(input$fz_offset_preset %||% "0.25")
    }

    # Skip if FZ disabled
    if (is.na(fz_offset) || fz_offset <= 0) return(NULL)

    plot <- plot_fz_validation(rv$validated_data, fz_offset = fz_offset)
    # Separate the offset text from the quality badge in the compact panel.
    for (i in seq_along(plot$layers)) {
      if (inherits(plot$layers[[i]]$geom, "GeomText"))
        plot$layers[[i]]$aes_params$vjust <- 3.8
    }
    plot +
      ggplot2::labs(title = "Isotope boundary effect", subtitle = NULL)
  }, res = 96, bg = "transparent")

  # --- Strategy Preview Image ---
  output$strategy_preview_img <- renderUI({
    strategy <- input$mz_strategy
    if (is.null(strategy)) return(NULL)

    # Map strategy to schematic image
    img_file <- sprintf("strategy_previews/schematic_%s.png", strategy)

    tags$div(
      style = "margin-bottom: 8px;",
      tags$img(
        src = img_file,
        width = "100%",
        style = "border-radius: 6px; border: 1px solid var(--border-subtle);"
      ),
      # Show KDE vs Coverage comparison when either is selected
      if (strategy %in% c("kde", "coverage")) {
        tags$details(
          style = "margin-top: 6px;",
          tags$summary(
            style = "cursor: pointer; font-size: 11px; color: var(--text-secondary);",
            "KDE vs Coverage: what's the difference?"
          ),
          tags$img(
            src = "strategy_previews/schematic_kde_vs_coverage.png",
            width = "100%",
            style = "border-radius: 6px; border: 1px solid var(--border-subtle); margin-top: 4px;"
          )
        )
      }
    )
  })

  # --- Window Mode Preview Image ---
  output$window_mode_preview_img <- renderUI({
    mode <- input$window_mode
    if (is.null(mode)) return(NULL)

    img_file <- sprintf("strategy_previews/schematic_mode_%s.png", mode)

    tags$div(
      style = "margin-bottom: 8px;",
      tags$img(
        src = img_file,
        width = "100%",
        style = "border-radius: 6px; border: 1px solid var(--border-subtle);"
      )
    )
  })

  # --- Toggle: "More Options" in Setup tab (legacy handler, harmless) ---
  observeEvent(input$toggle_setup_more, {
    shinyjs::toggle("setup_more_options")
  })

  server_live_preview(input, output, session, rv, cycle_time_result)
  server_results_comparison(input, output, session, rv)

  # =========================================================================
  # RESULTS DISPLAY OUTPUTS (Step 3)
  # =========================================================================

  output$results_status_text <- renderUI({
    req(rv$optimized_windows)
    n_windows <- nrow(rv$optimized_windows$windows)
    n_rt_bins <- length(unique(rv$optimized_windows$windows$rt_segment_id))
    strategy <- rv$optimized_windows$parameters$mz_strategy %||% "unknown"
    tags$span(
      sprintf("%s windows | %d RT bins | %s strategy",
              format(n_windows, big.mark = ","), n_rt_bins, strategy)
    )
  })

  output$before_summary <- renderUI({
    req(rv$validated_data)

    precursor_data <- rv$validated_data$data
    median_fwhm_sec <- rv$median_fwhm_sec

    plan <- rv$optimization_plan
    original <- rv$optimized_windows$parameters$original_method %||% plan$original_method
    original_ct <- original$cycle_time_sec %||% plan$diagnosis$current_cycle_time_sec
    ct_text <- if (!is.null(original_ct)) sprintf("%.3f sec", original_ct) else "N/A"

    # Estimate DPPP
    dppp_text <- if (!is.null(original_ct) && !is.na(median_fwhm_sec)) {
      est_dppp <- calculate_dppp(median_fwhm_sec, original_ct)
      sprintf("~%.1f", est_dppp)
    } else {
      "N/A"
    }

    tags$div(
      class = "summary-list",
      if (!is.null(original)) tags$div(
        tags$strong("Original fixed method: "),
        sprintf("m/z %.1f-%.1f | %d windows | %.2f m/z width",
          original$mz_min, original$mz_max, original$n_windows, original$window_width)),
      tags$div(tags$strong("Precursors: "), format(nrow(precursor_data), big.mark = ",")),
      tags$div(tags$strong("RT: "),
               sprintf("%.1f - %.1f min", min(precursor_data$RT.Apex, na.rm = TRUE), max(precursor_data$RT.Apex, na.rm = TRUE))),
      tags$div(tags$strong("m/z: "),
               sprintf("%.0f - %.0f Da", min(precursor_data$Precursor.Mz, na.rm = TRUE), max(precursor_data$Precursor.Mz, na.rm = TRUE))),
      tags$div(tags$strong("FWHM: "), sprintf("%.2f sec", median_fwhm_sec)),
      tags$div(tags$strong("Cycle Time: "), ct_text),
      tags$div(tags$strong("Est. DPPP: "), dppp_text)
    )
  })

  output$after_summary <- renderUI({
    req(rv$optimized_windows, rv$optimization_plan)

    windows <- rv$optimized_windows$windows
    plan <- rv$optimization_plan
    stats <- rv$optimized_windows$statistics
    dppp_v <- rv$optimized_windows$dppp_verification
    params <- rv$optimized_windows$parameters
    used_mode <- params$window_mode %||% "density"

    n_windows <- nrow(windows)
    n_rt_bins <- length(unique(windows$rt_segment_id))
    mean_width <- mean(windows$window_width, na.rm = TRUE)
    sd_width <- sd(windows$window_width, na.rm = TRUE)
    min_width <- min(windows$window_width, na.rm = TRUE)
    max_width <- max(windows$window_width, na.rm = TRUE)
    coverage <- stats$coverage_percentage

    # Window mode badge
    mode_badge_classes <- list(
      density = "badge-accent", fixed = "badge-dark", staggered = "badge-dark"
    )
    mode_labels <- list(
      density = "Density (Variable)", fixed = "Fixed (Equal)", staggered = "Staggered (Offset)"
    )
    mode_badge <- tags$span(
      class = mode_badge_classes[[used_mode]] %||% "badge-dark",
      mode_labels[[used_mode]] %||% used_mode
    )

    # Mode-specific width distribution line
    width_detail <- if (used_mode == "density") {
      width_ratio <- max_width / max(min_width, 0.1)
      tags$div(
        tags$strong("Width Range: "),
        sprintf("%.1f - %.1f Da (ratio: %.1fx, SD: %.2f)", min_width, max_width, width_ratio, sd_width)
      )
    } else if (used_mode == "staggered") {
      n_cycle1 <- if ("cycle" %in% colnames(windows)) sum(windows$cycle == 1L) else n_windows
      n_cycle2 <- if ("cycle" %in% colnames(windows)) sum(windows$cycle == 2L) else 0
      fz_val <- params$fz_offset %||% 0.25
      tags$div(
        tags$div(
          tags$strong("2-Cycle Interleaved: "),
          sprintf("C1: %d + C2: %d windows (isotope offset: %.4f)", n_cycle1, n_cycle2, fz_val)
        ),
        render_loop_n_badge(windows)
      )
    } else {
      tags$div(
        tags$strong("Width: "),
        sprintf("%.1f Da (uniform)", mean_width)
      )
    }

    # DPPP verification badge with clear explanation
    dppp_line <- if (!is.null(dppp_v)) {
      deviation <- dppp_v$deviation_pct
      is_ok <- abs(deviation) <= 5
      badge_class <- if (is_ok) "efficiency-badge status-pass" else "efficiency-badge status-fail"
      badge_text <- if (is_ok) "PASS" else sprintf("%.0f%% deviation", deviation)

      # Explain WHY deviation occurs
      explanation <- if (is_ok) {
        NULL
      } else if (deviation > 0) {
        tags$div(class = "text-muted", style = "font-size: 12px; margin-top: 2px;",
          icon("info-circle"),
          sprintf(" Estimated DPPP is %.0f%% higher than planned (fewer windows than estimated)", abs(deviation))
        )
      } else {
        tags$div(class = "text-muted", style = "font-size: 12px; margin-top: 2px;",
          icon("info-circle"),
          sprintf(" Estimated DPPP is %.0f%% lower than planned (more windows than estimated)", abs(deviation))
        )
      }

      tagList(
        tags$div(
          tags$strong("Est. DPPP: "),
          sprintf("%.1f ", dppp_v$actual_dppp_median),
          tags$span(badge_text, class = badge_class),
          if (!is.null(explanation)) .workflow_help("DPPP verification", explanation)
        )
      )
    } else {
      NULL
    }

    actual_ct_line <- if (!is.null(dppp_v)) {
      tags$div(tags$strong("Est. cycle: "), sprintf("%.3f sec", dppp_v$actual_cycle_time_sec))
    } else {
      tags$div(tags$strong("Planned Cycle: "), sprintf("%.3f sec", plan$required_cycle_time_sec))
    }

    tags$div(
      class = "summary-list",
      tags$div(tags$strong("Windows: "), format(n_windows, big.mark = ",")),
      tags$div(tags$strong("RT Bins: "), n_rt_bins),
      tags$div(tags$strong("Mode: "), mode_badge),
      tags$div(tags$strong("Width: "), sprintf("%.1f Da", mean_width)),
      width_detail,
      tags$div(tags$strong("Coverage: "), sprintf("%.1f%%", coverage)),
      actual_ct_line,
      dppp_line
    )
  })

  # --- Output: m/z Range Summary (post-optimization) ---
  output$mz_range_summary <- renderUI({
    req(rv$optimized_windows)

    windows <- rv$optimized_windows$windows
    params <- rv$optimized_windows$parameters

    # Overall m/z range from optimized windows
    mz_min <- min(windows$mz_start, na.rm = TRUE)
    mz_max <- max(windows$mz_end, na.rm = TRUE)
    mz_span <- mz_max - mz_min

    # Per-RT-bin statistics
    n_rt_bins <- length(unique(windows$rt_segment_id))
    windows_per_bin <- nrow(windows) / n_rt_bins

    # Width statistics
    min_width <- min(windows$window_width, na.rm = TRUE)
    max_width <- max(windows$window_width, na.rm = TRUE)
    mean_width <- mean(windows$window_width, na.rm = TRUE)

    # Strategy label
    strategy_label <- format_strategy_label(params$mz_strategy)

    tags$div(
      style = "font-size: 13px;",

      # Strategy badge
      tags$div(
        style = "margin-bottom: 10px;",
        tags$span(
          class = "badge-dark",
          strategy_label
        ),
        tags$span(
          class = "badge-accent",
          style = "margin-left: 4px;",
          params$window_mode %||% "density"
        ),
        # Loop N badge for staggered mode (inline variant)
        if ((params$window_mode %||% "density") == "staggered") {
          loop_n <- cached_loop_n()
          if (!is.null(loop_n)) {
            tags$span(class = "badge-accent", style = "margin-left: 4px;",
                      sprintf("Loop N = %d", loop_n))
          }
        }
      ),

      # m/z range
      tags$div(
        class = "panel-accent",
        style = "margin-bottom: 8px;",
        tags$div(
          style = "font-weight: 600;",
          sprintf("m/z Range: %.1f - %.1f Da (%.0f Da span)", mz_min, mz_max, mz_span)
        ),
        tags$div(
          class = "text-muted",
          style = "font-size: 12px; margin-top: 4px;",
          sprintf("%.0f windows/bin | %d RT bins", windows_per_bin, n_rt_bins)
        )
      ),

      # Width distribution
      tags$div(
        class = "panel-accent",
        tags$div(
          style = "font-weight: 600;",
          "Window Width Distribution"
        ),
        tags$div(
          style = "margin-top: 4px;",
          sprintf("Min: %.1f Da | Mean: %.1f Da | Max: %.1f Da", min_width, mean_width, max_width)
        ),
        if (params$window_mode == "density") {
          tags$div(
            class = "text-muted",
            style = "font-size: 11px; margin-top: 4px; font-style: italic;",
            sprintf("Variable width ratio: %.1fx (max/min)", max_width / max(min_width, 0.1))
          )
        }
      )
    )
  })

  # --- Output: Window Preview Table ---
  output$window_preview <- DT::renderDataTable({
    req(rv$optimized_windows)

    windows <- .shiny_delivered_windows(rv$optimized_windows$windows, .shiny_export_options(input))
    precursors <- rv$validated_data$data
    precursors$rt_group <- NULL
    windows <- aidia:::calculate_precursors_per_window(windows, precursors)
    used_mode <- rv$optimized_windows$parameters$window_mode %||% "density"

    # Select key columns for preview (include is_staggered for staggered mode)
    preview_cols <- c("rt_segment_id", "rt_start", "rt_end", "mz_start", "mz_end",
                      "window_width", "n_precursors")
    if (used_mode == "staggered") {
      if ("cycle" %in% colnames(windows)) preview_cols <- c(preview_cols, "cycle")
      if ("is_staggered" %in% colnames(windows)) preview_cols <- c(preview_cols, "is_staggered")
    }

    preview_data <- windows[, intersect(preview_cols, names(windows))]
    labels <- c(rt_segment_id = "RT group", rt_start = "RT start (min)",
        rt_end = "RT end (min)", mz_start = "m/z start", mz_end = "m/z end",
        window_width = "Width (m/z)", n_precursors = "Input precursors",
        cycle = "Cycle", is_staggered = "Staggered")
    names(preview_data) <- unname(labels[names(preview_data)])

    DT::datatable(
      preview_data,
      options = list(
        pageLength = 10,
        scrollX = TRUE,
        dom = 'ltip'
      ),
      rownames = FALSE
    ) %>%
      DT::formatRound(columns = c("m/z start", "m/z end", "Width (m/z)"), digits = 4)
  })

  # --- Cached evaluation result (avoid redundant evaluate_windows calls) ---
  cached_evaluation <- reactive({
    req(rv$optimized_windows, rv$validated_data, rv$optimization_plan)
    tryCatch(
      evaluate_windows(rv$optimized_windows, rv$validated_data, rv$optimization_plan),
      error = function(e) NULL
    )
  })

  # --- Acquisition Capacity KPIs (v0.4.x) ---------------------------------
  # Lazy reactive: derives the four "did I use the instrument well?" KPIs
  # from plan + windows + cached evaluation. Evaluation may be NULL (eval
  # failed); get_capacity_kpis() handles that by emitting filled_ratio =
  # NA and the gauge renders a gray "N/A" segment.
  cached_capacity_kpis <- reactive({
    req(rv$optimized_windows, rv$optimization_plan)
    get_capacity_kpis(
      plan       = rv$optimization_plan,
      windows    = rv$optimized_windows,
      evaluation = cached_evaluation()
    )
  })

  output$capacity_header <- renderUI({
    # Mirror cached_capacity_kpis() gating: header should only render
    # alongside the gauge, never on a stale plan with no current windows.
    req(rv$optimized_windows, rv$optimization_plan)
    tags$div(
      class = "panel-accent",
      style = "padding: 6px 10px; margin-bottom: 6px; font-weight: 500;",
      capacity_header_text(rv$optimization_plan)
    )
  })

  output$capacity_dashboard <- renderPlot({
    kpis <- cached_capacity_kpis()
    plot_capacity_kpis(kpis)
  }, res = 96, bg = "transparent")

  output$capacity_bottleneck <- renderUI({
    kpis <- cached_capacity_kpis()
    msg  <- summarize_bottleneck(kpis)
    accent_color <- unname(aidia_capacity_grade_colors[["Info"]])
    tags$div(
      class = "panel-raised",
      style = sprintf(paste(
        "padding: 8px 12px;",
        "margin-top: 6px;",
        "font-size: 13px;",
        "border-left: 3px solid %s;"
      ), accent_color),
      icon("lightbulb"),
      tags$strong(" Bottleneck: "),
      msg
    )
  })

  # --- Cached reactives for results summary (avoid redundant extraction) ---
  cached_metrics <- reactive({
    req(rv$optimization_complete, rv$optimization_plan, rv$optimized_windows)
    extract_before_after_metrics(rv$optimization_plan, rv$optimized_windows)
  })

  cached_loop_n <- reactive({
    req(rv$optimization_complete, rv$optimized_windows)
    tryCatch(calculate_loop_n(rv$optimized_windows$windows), error = function(e) NULL)
  })

  # --- ValueBox Rendering for Results Summary Dashboard ---
  # Design principle: color reflects TARGET ACHIEVEMENT, not direction of change.
  # Green = target met, Yellow = close/marginal, Red = target not met.
  # Subtitle provides context (vs. original) so users understand the trade-off.

  output$summary_box_cycle_time <- renderValueBox({
    m <- cached_metrics()
    orig_ct <- m$orig_ct
    new_ct <- m$new_ct
    target_dppp <- m$target_dppp

    if (is.null(orig_ct) || is.na(orig_ct) || orig_ct == 0) orig_ct <- new_ct
    if (is.null(new_ct) || is.na(new_ct)) new_ct <- orig_ct

    # Context: show change from original
    diff_pct <- if (!is.na(orig_ct) && orig_ct != 0) {
      round((new_ct - orig_ct) / orig_ct * 100, 1)
    } else 0

    change_text <- if (abs(diff_pct) < 1) {
      "unchanged"
    } else if (diff_pct > 0) {
      sprintf("+%.0f%% vs original", diff_pct)
    } else {
      sprintf("%.0f%% vs original", diff_pct)
    }

    # Timing is context, not evidence that the sampling target was met.
    subtitle <- sprintf("Est. cycle time (%s)", change_text)
    color <- "primary"
    icon_name <- "clock"

    valueBox(
      value = paste0(round(new_ct, 2), " s"),
      subtitle = subtitle,
      icon = icon(icon_name),
      color = color
    )
  })

  output$summary_box_dppp <- renderValueBox({
    m <- cached_metrics()
    new_dppp <- m$new_dppp
    target_dppp <- m$target_dppp

    if (is.null(new_dppp) || is.na(new_dppp)) new_dppp <- 0

    # Color: based on target achievement
    if (!is.na(target_dppp) && new_dppp >= target_dppp) {
      color <- "success"
      subtitle <- sprintf("Est. median DPPP (target %.1f met)", target_dppp)
    } else if (!is.na(target_dppp) && new_dppp >= target_dppp * 0.9) {
      color <- "warning"
      subtitle <- sprintf("Est. median DPPP (%.0f%% of target %.1f)",
                          new_dppp / target_dppp * 100, target_dppp)
    } else {
      color <- "danger"
      subtitle <- sprintf("Est. median DPPP (target %.1f not met)", target_dppp %||% 0)
    }

    valueBox(
      value = round(new_dppp, 1),
      subtitle = subtitle,
      icon = icon("chart-line"),
      color = color
    )
  })

  output$summary_box_windows <- renderValueBox({
    req(rv$optimization_complete, rv$optimized_windows)
    windows <- rv$optimized_windows$windows
    n_total <- nrow(windows) %||% rv$optimized_windows$statistics$total_windows
    n_rt_bins <- length(unique(windows$rt_segment_id))
    n_per_bin <- if (n_rt_bins > 0) round(n_total / n_rt_bins) else n_total
    used_mode <- rv$optimized_windows$parameters$window_mode %||% "density"

    # Determine display value — staggered mode shows Loop N prominently
    vb_value <- n_per_bin
    vb_subtitle <- sprintf("Windows / RT group (%d total)", n_total)

    if (used_mode == "staggered") {
      loop_n <- cached_loop_n()
      if (!is.null(loop_n)) {
        vb_value <- sprintf("%d (Loop %d)", n_per_bin, loop_n)
        vb_subtitle <- sprintf("%d per bin | %d total | Staggered", n_per_bin, n_total)
      }
    }

    valueBox(
      value = vb_value,
      subtitle = vb_subtitle,
      icon = icon("layer-group"),
      color = "primary"
    )
  })
}
