# server_optimization.R - Run Optimization, Results Display, Summary Tables

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

  # --- Run Optimization ---
  observeEvent(input$run_optimization, {
    # Check if data is loaded
    if (is.null(rv$validated_data) || !rv$data_loaded) {
      showNotification("Please upload a parquet file first!", type = "warning")
      return()
    }

    # Show processing notification
    showNotification("Running optimization...", id = "opt_progress", duration = NULL, type = "message")

    # Reset flag so FALSE -> TRUE transition triggers observeEvent in app.R
    rv$optimization_complete <- FALSE

    tryCatch({
      cat("\n[Shiny] Starting optimization...\n")
      cat("[Shiny] Instrument:", input$instrument, "\n")
      cat("[Shiny] Target DPPP:", input$target_dppp, "\n")
      cat("[Shiny] Target Satisfaction:", input$target_satisfaction, "%\n")
      cat("[Shiny] m/z Strategy:", input$mz_strategy, "\n")

      # Log IT mode for Orbitrap instruments
      is_orbitrap <- is_orbitrap_instrument(input$instrument)
      is_astral <- is_astral_instrument(input$instrument)

      if (is_orbitrap) {
        ms1_it_mode <- if (isTRUE(input$ms1_it_auto)) "AUTO" else sprintf("CUSTOM (%d ms)", input$ms1_it_custom)
        ms2_it_mode <- if (isTRUE(input$ms2_it_auto)) "AUTO" else sprintf("CUSTOM (%d ms)", input$ms2_it_custom)
        cat("[Shiny] MS1 IT Mode:", ms1_it_mode, "\n")
        cat("[Shiny] MS2 IT Mode:", ms2_it_mode, "\n")
      } else if (is_astral) {
        cat("[Shiny] Astral MS2 IT:", input$astral_ms2_it, "ms\n")
      }

      # Stage 2: Optimization Planning
      cat("[Shiny] Running plan_optimization()...\n")

      # Determine Custom IT override (Orbitrap only)
      ms2_time_override_sec <- NULL
      if (is_orbitrap && !isTRUE(input$ms2_it_auto)) {
        ms2_time_override_sec <- (input$ms2_it_custom %||% 50) / 1000  # ms to sec
        cat("[Shiny] Custom MS2 IT Override:", input$ms2_it_custom, "ms\n")
      } else if (is_astral) {
        ms2_time_override_sec <- (input$astral_ms2_it %||% 3) / 1000
        cat("[Shiny] Astral MS2 IT:", input$astral_ms2_it, "ms\n")
      } else {
        cat("[Shiny] Using Auto IT (Sweet Spot mode)\n")
      }

      # Get calculated current cycle time from experiment parameters
      calc_result <- cycle_time_result()
      current_cycle_time_sec <- if (!is.null(calc_result)) {
        cat("[Shiny] Using calculated current cycle time:", calc_result$cycle_time_sec, "sec\n")
        cat("[Shiny]   - MS1 scan time:", calc_result$ms1$scan_time_ms, "ms\n")
        cat("[Shiny]   - MS2 scan time:", calc_result$ms2$scan_time_ms, "ms\n")
        cat("[Shiny]   - Window count:", calc_result$window_count, "\n")
        cat("[Shiny]   - Efficiency:", calc_result$ms2$efficiency_pct, "%\n")
        calc_result$cycle_time_sec
      } else {
        cat("[Shiny] No calculated cycle time, using auto-estimate\n")
        NULL
      }

      rv$optimization_plan <- plan_optimization(
        validated_data = rv$validated_data,
        instrument_preset = input$instrument,
        target_dppp = input$target_dppp,
        target_satisfaction = input$target_satisfaction / 100,
        ms2_time_override = ms2_time_override_sec,
        current_cycle_time = current_cycle_time_sec,
        ms2_resolution = if (!is.null(input$ms2_resolution)) as.numeric(input$ms2_resolution) else NULL
      )
      cat("[Shiny] plan_optimization() completed!\n")

      # Debug: Show key optimization parameters
      cat("[Shiny] === OPTIMIZATION PLAN DEBUG ===\n")
      cat("[Shiny] Target DPPP:", input$target_dppp, "\n")
      cat("[Shiny] Required Cycle Time:", rv$optimization_plan$required_cycle_time_sec, "sec\n")
      cat("[Shiny] Current Cycle Time:", rv$optimization_plan$current_cycle_time_sec, "sec\n")
      cat("[Shiny] Windows per bin:", rv$optimization_plan$window_count_per_bin, "\n")
      cat("[Shiny] t_scan:", rv$optimization_plan$timing$t_scan_ms, "ms\n")
      cat("[Shiny] ================================\n")

      # Determine RT bin width and binning mode
      rt_binning_mode_input <- input$rt_binning_mode %||% "fixed"

      if (rt_binning_mode_input == "custom") {
        # Custom: user-specified bin width, fixed binning
        rt_bin_width_final <- input$rt_bin_width
        rt_binning_mode_final <- "fixed"
        cat("[Shiny] Custom RT Bin Width:", rt_bin_width_final, "min (fixed binning)\n")
      } else {
        # Fixed and Adaptive: auto-calculate bin width
        rt_range <- range(rv$validated_data$data$RT.Apex, na.rm = TRUE)
        auto_result <- calculate_auto_rt_bin_width(
          rt_range = rt_range,
          mz_strategy = input$mz_strategy,
          target_min_bins = 5
        )
        rt_bin_width_final <- auto_result$bin_width

        if (rt_binning_mode_input == "adaptive") {
          rt_binning_mode_final <- "adaptive"
          cat("[Shiny] Adaptive RT Binning: auto width =", rt_bin_width_final, "min (used as min constraint)")
          cat(" (", auto_result$n_bins, " target bins for ", input$mz_strategy, " strategy)\n", sep = "")
        } else {
          rt_binning_mode_final <- "fixed"
          cat("[Shiny] Fixed RT Binning: auto width =", rt_bin_width_final, "min")
          cat(" (", auto_result$n_bins, " bins for ", input$mz_strategy, " strategy)\n", sep = "")
        }

        showNotification(
          sprintf("RT bin: %.1f min (%s, %d bins)", rt_bin_width_final, rt_binning_mode_final, auto_result$n_bins),
          type = "message", duration = 3
        )
      }

      # Stage 3: Window Optimization with selected m/z strategy
      cat("[Shiny] Running optimize_windows()...\n")
      cat("[Shiny] m/z Range Strategy:", input$mz_strategy, "\n")
      cat("[Shiny] Window Width Mode:", input$window_mode, "\n")
      cat("[Shiny] RT Binning Mode:", input$rt_binning_mode %||% "fixed", "\n")
      cat("[Shiny] Min Isolation Width:", input$min_isolation_width, "Da\n")
      cat("[Shiny] Max Isolation Width:", input$max_isolation_width %||% 80, "Da\n")

      # Build typed strategy_config (validated by constructors)
      # Common: resolve window count (auto or manual, for all strategies)
      use_auto_windows <- isTRUE(input$auto_windows %||% TRUE)
      manual_n_win <- input$manual_n_windows %||% 40

      strategy_cfg <- switch(input$mz_strategy,
        greedy = greedy_config(
          auto_windows = use_auto_windows,
          n_windows = manual_n_win,
          mz_step = input$greedy_mz_step %||% 0.5,
          apply_smoothing = isTRUE(input$greedy_apply_smoothing %||% TRUE)
        ),
        quantile = quantile_config(
          lower = input$quantile_lower %||% 0.05,
          upper = input$quantile_upper %||% 0.95,
          apply_smoothing = isTRUE(input$quantile_apply_smoothing %||% TRUE)
        ),
        coverage = coverage_config(
          target = (input$target_coverage %||% 90) / 100
        ),
        outlier = outlier_config(
          threshold = input$outlier_threshold %||% 3.0,
          apply_smoothing = isTRUE(input$outlier_apply_smoothing %||% TRUE)
        ),
        kde = kde_config(
          density_threshold = (input$kde_density_threshold %||% 10) / 100,
          min_coverage = (input$kde_min_coverage %||% 80) / 100
        )
      )
      cat("[Shiny] Strategy config:", input$mz_strategy, "\n")
      cat("[Shiny]  ", paste(names(as.list(strategy_cfg)), collapse = ", "), "\n")

      # For non-greedy strategies, pass manual window count override
      n_win_override <- if (!use_auto_windows && input$mz_strategy != "greedy") {
        as.integer(manual_n_win)
      } else {
        NULL  # greedy handles it internally via greedy_config
      }

      rv$optimized_windows <- optimize_windows(
        validated_data = rv$validated_data,
        optimization_plan = rv$optimization_plan,
        strategy_config = strategy_cfg,
        n_windows_override = n_win_override,
        window_mode = input$window_mode %||% "density",
        rt_bin_width_min = rt_bin_width_final,
        rt_binning_mode = rt_binning_mode_final,
        cpd_significance_level = input$cpd_significance %||% 0.05,
        cpd_min_bin_width = input$cpd_min_bin_width %||% 1.0,
        edge_void_buffer_min = input$edge_void_buffer %||% 0.5,
        edge_wash_min_precursors = input$edge_wash_threshold %||% 30,
        min_width_da = input$min_isolation_width %||% 2,
        max_width_da = input$max_isolation_width %||% 80,
        fz_offset = if (isTRUE(input$fz_offset_preset == "custom")) {
          as.numeric(input$custom_fz_offset %||% 0.25)
        } else {
          as.numeric(input$fz_offset_preset %||% "0.25")
        }
      )
      cat("[Shiny] optimize_windows() completed!\n")

      rv$optimization_complete <- TRUE
      shinyjs::enable(selector = "a[data-value=\047results\047]")

      removeNotification("opt_progress")
      showNotification(
        paste("Optimization complete:", nrow(rv$optimized_windows$windows), "windows generated"),
        type = "message"
      )

    }, error = function(e) {
      cat("[Shiny] ERROR in optimization:", e$message, "\n")
      removeNotification("opt_progress")
      showNotification(paste("Error:", e$message), type = "error", duration = 10)
      rv$optimization_complete <- FALSE
    })
  })

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

    calc_result <- cycle_time_result()
    ct_text <- if (!is.null(calc_result)) sprintf("%.3f sec", calc_result$cycle_time_sec) else "N/A"

    # Estimate DPPP
    dppp_text <- if (!is.null(calc_result) && !is.na(median_fwhm_sec)) {
      est_dppp <- calculate_dppp(median_fwhm_sec, calc_result$cycle_time_sec)
      sprintf("~%.1f", est_dppp)
    } else {
      "N/A"
    }

    tags$div(
      class = "summary-list",
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
          sprintf("C1: %d + C2: %d windows (forbidden zone: %.4f)", n_cycle1, n_cycle2, fz_val)
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
          sprintf(" Actual DPPP is %.0f%% higher than planned (fewer windows than estimated)", abs(deviation))
        )
      } else {
        tags$div(class = "text-muted", style = "font-size: 12px; margin-top: 2px;",
          icon("info-circle"),
          sprintf(" Actual DPPP is %.0f%% lower than planned (more windows than estimated)", abs(deviation))
        )
      }

      tagList(
        tags$div(
          tags$strong("Actual DPPP: "),
          sprintf("%.1f ", dppp_v$actual_dppp_median),
          tags$span(badge_text, class = badge_class)
        ),
        explanation
      )
    } else {
      NULL
    }

    actual_ct_line <- if (!is.null(dppp_v)) {
      tags$div(tags$strong("Actual Cycle: "), sprintf("%.3f sec", dppp_v$actual_cycle_time_sec))
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

  # --- Output: Optimization Summary Table ---
  output$optimization_summary <- renderTable({
    req(rv$optimized_windows)

    windows <- rv$optimized_windows$windows
    plan <- rv$optimization_plan
    params <- rv$optimized_windows$parameters

    # Determine IT mode display
    is_orbitrap <- is_orbitrap_instrument(input$instrument)
    is_astral <- is_astral_instrument(input$instrument)

    it_mode_display <- if (is_orbitrap) {
      if (isTRUE(input$ms2_it_auto)) {
        "Auto (Sweet Spot)"
      } else {
        sprintf("Custom (%d ms)", input$ms2_it_custom %||% 50)
      }
    } else if (is_astral) {
      sprintf("%.1f ms", input$astral_ms2_it %||% 3)
    } else {
      "N/A (TOF)"
    }

    # Window width distribution
    widths <- windows$window_width
    width_sd <- sd(widths, na.rm = TRUE)
    width_min <- min(widths, na.rm = TRUE)
    width_max <- max(widths, na.rm = TRUE)
    used_mode <- params$window_mode %||% "density"

    # Build metrics dynamically (include DPPP verification if available)
    metrics <- c(
      "Total Windows",
      "RT Bins",
      "RT Bin Width (min)",
      "Window Mode",
      "IT Mode",
      "Mean Width (Da)",
      "Width Range (Da)",
      "Width SD (Da)",
      "Coverage (%)",
      "Planned Cycle Time (sec)"
    )
    values <- c(
      nrow(windows),
      length(unique(windows$rt_segment_id)),
      sprintf("%.1f", params$rt_bin_width_min),
      used_mode,
      it_mode_display,
      sprintf("%.1f", mean(widths)),
      sprintf("%.1f - %.1f", width_min, width_max),
      sprintf("%.2f", width_sd),
      sprintf("%.1f%%", rv$optimized_windows$statistics$coverage_percentage),
      sprintf("%.2f", plan$required_cycle_time_sec)
    )

    # Add DPPP re-verification results if available
    dppp_v <- rv$optimized_windows$dppp_verification
    if (!is.null(dppp_v)) {
      metrics <- c(metrics,
        "Actual Cycle Time (sec)",
        "Actual DPPP (median)",
        "DPPP Deviation (%)"
      )
      deviation_str <- sprintf("%.1f%%", dppp_v$deviation_pct)
      if (abs(dppp_v$deviation_pct) > 5) {
        direction <- if (dppp_v$deviation_pct > 0) "higher" else "lower"
        deviation_str <- sprintf("%s (%s than planned)", deviation_str, direction)
      } else {
        deviation_str <- paste(deviation_str, "(within 5% tolerance)")
      }
      values <- c(values,
        sprintf("%.3f", dppp_v$actual_cycle_time_sec),
        sprintf("%.2f", dppp_v$actual_dppp_median),
        deviation_str
      )
    }

    data.frame(Metric = metrics, Value = values)
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

    windows <- rv$optimized_windows$windows
    used_mode <- rv$optimized_windows$parameters$window_mode %||% "density"

    # Select key columns for preview (include is_staggered for staggered mode)
    preview_cols <- c("rt_segment_id", "mz_start", "mz_end",
                      "window_width", "n_precursors")
    if (used_mode == "staggered") {
      if ("cycle" %in% colnames(windows)) preview_cols <- c(preview_cols, "cycle")
      if ("is_staggered" %in% colnames(windows)) preview_cols <- c(preview_cols, "is_staggered")
    }

    preview_data <- windows[, intersect(preview_cols, names(windows))]

    DT::datatable(
      preview_data,
      options = list(
        pageLength = 20,
        scrollX = TRUE,
        dom = 'ltip'
      ),
      rownames = FALSE
    ) %>%
      DT::formatRound(columns = c("mz_start", "mz_end", "window_width"), digits = 4)
  })

  # --- Precursors-per-Window Plot ---
  output$plot_precursors_per_window <- renderPlot({
    req(rv$optimized_windows, rv$validated_data)
    plot_precursors_per_window(
      optimized_windows = rv$optimized_windows,
      validated_data = rv$validated_data
    )
  })

  # --- Cached evaluation result (avoid redundant evaluate_windows calls) ---
  cached_evaluation <- reactive({
    req(rv$optimized_windows, rv$validated_data, rv$optimization_plan)
    tryCatch(
      evaluate_windows(rv$optimized_windows, rv$validated_data, rv$optimization_plan),
      error = function(e) NULL
    )
  })

  # --- Temporal Density Plot ---
  output$plot_temporal_density <- renderPlot({
    eval_result <- cached_evaluation()
    if (is.null(eval_result)) {
      return(create_insufficient_data_plot(
        title = "Precursor Temporal Density",
        message = "Evaluation data not available"
      ))
    }
    plot_temporal_density(eval_result)
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

    # Color: based on whether DPPP target is achievable at this cycle time
    # The optimizer already computed this — if we have results, the target IS met
    # Show green (target met) with neutral context about the change
    subtitle <- sprintf("Cycle Time (%s)", change_text)
    color <- "success"
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
      subtitle <- sprintf("Median DPPP (target %.1f met)", target_dppp)
    } else if (!is.na(target_dppp) && new_dppp >= target_dppp * 0.9) {
      color <- "warning"
      subtitle <- sprintf("Median DPPP (%.0f%% of target %.1f)",
                          new_dppp / target_dppp * 100, target_dppp)
    } else {
      color <- "danger"
      subtitle <- sprintf("Median DPPP (target %.1f not met)", target_dppp %||% 0)
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
    n_per_bin <- rv$optimization_plan$window_count_per_bin
    n_total <- nrow(rv$optimized_windows$windows) %||%
      rv$optimized_windows$statistics$total_windows
    used_mode <- rv$optimized_windows$parameters$window_mode %||% "density"

    # Determine display value — staggered mode shows Loop N prominently
    vb_value <- n_per_bin
    vb_subtitle <- sprintf("%d per bin (%d total)", n_per_bin, n_total)

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
