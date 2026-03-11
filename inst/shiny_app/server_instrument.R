# server_instrument.R - Cycle Time Calculation & Instrument Display
#
# Returns: cycle_time_result reactive (used by server_data and server_optimization)

server_instrument <- function(input, output, session, rv) {

  # --- Reactive: Calculate Cycle Time from Experiment Parameters ---
  cycle_time_result <- reactive({
    # Explicitly depend on all inputs that affect cycle time calculation
    # This ensures reactivity when any of these inputs change
    instrument <- input$instrument
    ms1_scans_input <- input$ms1_scans_per_cycle  # Explicit dependency for reactivity
    window_count_input <- input$current_window_count  # Explicit dependency
    astral_ms1_res_input <- input$astral_ms1_resolution  # Explicit dependency for Astral MS1

    # Determine analyzer type
    is_orbitrap <- is_orbitrap_instrument(instrument)
    is_astral <- is_astral_instrument(instrument)

    # Build experiment config based on instrument type
    if (is_orbitrap) {
      # Get MS1 IT (auto or custom)
      ms1_it <- if (isTRUE(input$ms1_it_auto)) {
        "auto"
      } else {
        input$ms1_it_custom %||% 50
      }

      # Get MS2 IT (auto or custom)
      ms2_it <- if (isTRUE(input$ms2_it_auto)) {
        "auto"
      } else {
        input$ms2_it_custom %||% 50
      }

      # Get MS1 scans per cycle (for Boxcar support) - use the explicit dependency
      ms1_scans <- ms1_scans_input %||% 1

      config <- list(
        instrument = list(preset = instrument),
        ms1 = list(
          resolution = as.numeric(input$ms1_resolution %||% 60000),
          max_injection_time_ms = ms1_it,
          scans_per_cycle = ms1_scans
        ),
        ms2 = list(
          resolution = as.numeric(input$ms2_resolution %||% 15000),
          max_injection_time_ms = ms2_it
        ),
        dia_windows = list(
          window_count = window_count_input %||% 40
        )
      )
    } else if (is_astral) {
      # Astral: MS1 on Orbitrap (resolution-dependent), MS2 on Astral MR-TOF (parallel)
      ms2_it <- input$astral_ms2_it %||% 3.0
      astral_ms1_res <- as.numeric(input$astral_ms1_resolution %||% 240000)

      config <- list(
        instrument = list(preset = instrument),
        ms1 = list(
          resolution = astral_ms1_res,
          max_injection_time_ms = "auto",  # Auto = Orbitrap transient time
          scans_per_cycle = 0  # Parallel: MS1 during MS2
        ),
        ms2 = list(
          resolution = 80000,  # Astral fixed
          max_injection_time_ms = ms2_it
        ),
        dia_windows = list(
          window_count = window_count_input %||% 100
        )
      )
    } else {
      # TOF instruments - use explicit dependency
      ms1_scans <- ms1_scans_input %||% 0  # Usually parallel

      config <- list(
        instrument = list(preset = instrument),
        ms1 = list(
          resolution = NULL,
          max_injection_time_ms = 10,
          scans_per_cycle = ms1_scans
        ),
        ms2 = list(
          resolution = NULL,
          max_injection_time_ms = 2
        ),
        dia_windows = list(
          window_count = window_count_input %||% 50
        )
      )
    }

    # Calculate cycle time
    tryCatch({
      result <- calculate_cycle_time_from_experiment(config, verbose = FALSE)
      result
    }, error = function(e) {
      cat("[Shiny] Error calculating cycle time:", e$message, "\n")
      NULL
    })
  })

  # --- Output: Auto IT value displays ---
  output$ms1_it_auto_value <- renderText({
    ms1_res <- as.numeric(input$ms1_resolution %||% 60000)
    transient <- get_transient_time(ms1_res, "orbitrap")
    sprintf("%.0f ms (T_transient)", transient)
  })

  output$ms2_it_auto_value <- renderText({
    ms2_res <- as.numeric(input$ms2_resolution %||% 15000)
    transient <- get_transient_time(ms2_res, "orbitrap")
    sprintf("%.0f ms (T_transient)", transient)
  })

  # --- Output: Calculated Cycle Time Display ---
  output$calculated_cycle_time <- renderText({
    result <- cycle_time_result()
    if (is.null(result)) {
      return("--")
    }
    sprintf("%.3f", result$cycle_time_sec)
  })

  output$cycle_time_breakdown <- renderText({
    result <- cycle_time_result()
    if (is.null(result)) {
      return("")
    }

    ms1_scans <- result$ms1$scans_per_cycle %||% 1
    if (ms1_scans == 0) {
      # Parallel mode
      sprintf("MS1: %.0fms (parallel) | MS2: %d x %.1fms",
              result$ms1$scan_time_ms,
              result$window_count,
              result$ms2$scan_time_ms)
    } else if (ms1_scans > 1) {
      # Boxcar mode
      sprintf("MS1: %dx%.0fms | MS2: %d x %.1fms",
              ms1_scans,
              result$ms1$scan_time_ms,
              result$window_count,
              result$ms2$scan_time_ms)
    } else {
      # Standard sequential
      sprintf("MS1: %.0fms + MS2: %d x %.1fms",
              result$ms1$scan_time_ms,
              result$window_count,
              result$ms2$scan_time_ms)
    }
  })

  # --- Output: Auto Windows Info (all strategies) ---
  # Shows the recommended window count when Auto mode is selected
  # For parallel instruments: sync-optimal; for sequential: DPPP-based
  output$auto_windows_info <- renderUI({
    calc_result <- cycle_time_result()
    is_parallel <- !is.null(calc_result) &&
      identical(calc_result$instrument$cycle_calculation, "parallel")

    # Try to get windows from optimization plan first
    plan_windows <- rv$optimization_plan$n_windows_per_bin

    if (!is.null(plan_windows)) {
      # Optimization plan available
      return(tags$div(
        class = "indicator-success",
        tags$span(class = "indicator-text", sprintf("Auto: %d windows", plan_windows)),
        tags$br(),
        tags$small("(from optimization plan)", class = "text-muted")
      ))
    }

    if (is_parallel) {
      # Parallel: show sync-optimal
      ms1_trans_ms <- calc_result$ms1$transient_ms
      if (is.null(ms1_trans_ms) || ms1_trans_ms < 10) {
        ms1_res <- calc_result$ms1$resolution %||% 240000
        ms1_trans_ms <- get_transient_time(ms1_res, "orbitrap")
        if (is.na(ms1_trans_ms)) ms1_trans_ms <- calc_result$ms1$scan_time_ms
      }
      ms2_scan_ms <- calc_result$ms2$scan_time_ms
      sync <- calculate_sync_optimal_windows(ms1_trans_ms, ms2_scan_ms)
      return(tags$div(
        class = "indicator-info",
        tags$span(class = "indicator-text", sprintf("Sync-optimal: %d windows", sync$n_sync)),
        tags$br(),
        tags$small(sprintf("MS1 %.0fms / MS2 %.1fms", ms1_trans_ms, ms2_scan_ms),
                   class = "text-muted")
      ))
    }

    # Sequential: DPPP-based estimate
    dppp_windows <- NULL
    if (!is.null(rv$validated_data)) {
      fwhm_median <- rv$median_fwhm_sec
      if (!is.null(calc_result) && !is.na(fwhm_median)) {
        target_dppp <- input$target_dppp %||% 7.0
        target_sat <- (input$target_satisfaction %||% 70) / 100
        ms2_time_sec <- calc_result$ms2$scan_time_ms / 1000
        dppp_windows <- estimate_window_count_preview(fwhm_median, target_dppp, ms2_time_sec)
      }
    }

    if (!is.null(dppp_windows)) {
      tags$div(
        class = "indicator-info",
        tags$span(class = "indicator-text", sprintf("Estimated: %d windows", dppp_windows)),
        tags$br(),
        tags$small(sprintf("(for DPPP %.1f, %.0f%% satisfaction)",
                           input$target_dppp, input$target_satisfaction %||% 70),
                   class = "text-muted")
      )
    } else {
      tags$div(
        class = "indicator-muted",
        tags$span(class = "indicator-text", "Upload data to see recommended windows")
      )
    }
  })

  # --- Output: Sync Hero Window Count (parallel Section A) ---
  output$sync_hero_window_count <- renderUI({
    calc_result <- cycle_time_result()
    if (is.null(calc_result)) {
      return(tags$div(
        style = "font-size: 36px; font-weight: 700; color: var(--text-muted);", "--"
      ))
    }

    ms1_trans_ms <- calc_result$ms1$transient_ms
    if (is.null(ms1_trans_ms) || ms1_trans_ms < 10) {
      ms1_res <- calc_result$ms1$resolution %||% 240000
      ms1_trans_ms <- get_transient_time(ms1_res, "orbitrap")
      if (is.na(ms1_trans_ms)) ms1_trans_ms <- calc_result$ms1$scan_time_ms
    }
    ms2_scan_ms <- calc_result$ms2$scan_time_ms
    sync <- calculate_sync_optimal_windows(ms1_trans_ms, ms2_scan_ms)

    tags$div(
      tags$span(
        style = "font-size: 36px; font-weight: 700; color: var(--accent);",
        sprintf("%d", sync$n_sync)
      ),
      tags$span(
        class = "text-muted", style = "font-size: 14px; margin-left: 4px;",
        "windows"
      )
    )
  })

  # --- Output: Sync DPPP Confirmation Badge (parallel Section A) ---
  output$sync_dppp_confirmation <- renderUI({
    calc_result <- cycle_time_result()
    if (is.null(calc_result) || is.null(rv$validated_data)) {
      return(tags$div(
        style = "font-size: 20px; font-weight: 600; color: var(--text-muted);",
        "Upload data"
      ))
    }

    fwhm_median <- rv$median_fwhm_sec
    if (is.null(fwhm_median) || is.na(fwhm_median)) {
      return(tags$div(class = "text-muted", "FWHM not available"))
    }

    # Calculate DPPP at sync-optimal
    ms1_trans_ms <- calc_result$ms1$transient_ms
    if (is.null(ms1_trans_ms) || ms1_trans_ms < 10) {
      ms1_res <- calc_result$ms1$resolution %||% 240000
      ms1_trans_ms <- get_transient_time(ms1_res, "orbitrap")
      if (is.na(ms1_trans_ms)) ms1_trans_ms <- calc_result$ms1$scan_time_ms
    }
    ms2_scan_ms <- calc_result$ms2$scan_time_ms
    sync <- calculate_sync_optimal_windows(ms1_trans_ms, ms2_scan_ms)
    cycle_sec <- max(ms1_trans_ms, sync$n_sync * ms2_scan_ms) / 1000
    dppp_at_sync <- calculate_dppp(fwhm_median, cycle_sec)

    target_dppp <- input$target_dppp %||% 7.0
    is_met <- dppp_at_sync >= target_dppp

    tags$div(
      tags$div(
        style = sprintf("font-size: 20px; font-weight: 600; color: %s;",
                        if (is_met) "var(--semantic-success)" else "var(--semantic-warning)"),
        icon(if (is_met) "check-circle" else "exclamation-triangle"),
        sprintf(" DPPP %.0f", dppp_at_sync)
      ),
      tags$div(
        class = "text-muted", style = "font-size: 11px; margin-top: 2px;",
        sprintf("Target: %.1f", target_dppp)
      )
    )
  })

  # --- Output: Sync Detail Panel (parallel Section A) ---
  output$sync_detail_panel <- renderUI({
    calc_result <- cycle_time_result()
    if (is.null(calc_result)) {
      return(tags$div(class = "text-muted", "Configure instrument to see sync detail"))
    }

    ms1_trans_ms <- calc_result$ms1$transient_ms
    if (is.null(ms1_trans_ms) || ms1_trans_ms < 10) {
      ms1_res <- calc_result$ms1$resolution %||% 240000
      ms1_trans_ms <- get_transient_time(ms1_res, "orbitrap")
      if (is.na(ms1_trans_ms)) ms1_trans_ms <- calc_result$ms1$scan_time_ms
    }
    ms2_scan_ms <- calc_result$ms2$scan_time_ms
    ms1_overhead <- calc_result$ms1$overhead_ms %||% 10
    n_windows <- calc_result$window_count

    sync <- calculate_duty_cycle_sync(ms1_trans_ms, ms2_scan_ms, n_windows)

    # Badge color
    if (sync$duty_cycle_pct >= 95) {
      badge_style <- "background: var(--semantic-success); color: white;"
      badge_text <- sprintf("%.0f%% Synced", sync$duty_cycle_pct)
    } else if (sync$duty_cycle_pct >= 80) {
      badge_style <- "background: var(--semantic-warning); color: white;"
      badge_text <- sprintf("%.0f%% Duty Cycle", sync$duty_cycle_pct)
    } else {
      badge_style <- "background: var(--semantic-danger); color: white;"
      badge_text <- sprintf("%.0f%% Duty Cycle", sync$duty_cycle_pct)
    }

    ms1_res <- calc_result$ms1$resolution %||% 240000
    ms1_res_label <- if (ms1_res >= 1000) paste0(ms1_res / 1000, "K") else ms1_res

    tags$div(
      style = "font-size: 12px; line-height: 1.8;",
      tags$div(
        sprintf("MS1: %.0fms (Orbitrap %s)", ms1_trans_ms + ms1_overhead, ms1_res_label)
      ),
      tags$div(
        sprintf("MS2: %d \u00d7 %.1fms = %.0fms",
                n_windows, ms2_scan_ms, sync$total_ms2_time_ms)
      ),
      tags$div(
        style = "display: flex; justify-content: space-between; align-items: center; margin-top: 4px;",
        tags$span(
          if (sync$ms1_idle_ms > 1) sprintf("Idle: %.0fms (Orbitrap)", sync$ms1_idle_ms)
          else if (sync$ms2_idle_ms > 1) sprintf("Idle: %.0fms (Astral)", sync$ms2_idle_ms)
          else "No idle time",
          class = "text-muted"
        ),
        tags$span(
          style = sprintf("padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 600; %s", badge_style),
          badge_text
        )
      )
    )
  })

  # --- Output: Greedy m/z Range Display ---
  output$greedy_mz_range_display <- renderUI({
    # Get window count (from auto or manual)
    if (isTRUE(input$auto_windows %||% TRUE)) {
      # Priority: optimization plan > estimated > default
      n_windows <- rv$optimization_plan$n_windows_per_bin

      # Estimate if no plan yet
      if (is.null(n_windows) && !is.null(rv$validated_data)) {
        calc_result <- cycle_time_result()
        fwhm_median <- rv$median_fwhm_sec
        if (!is.null(calc_result) && !is.na(fwhm_median)) {
          target_dppp <- input$target_dppp %||% 7.0
          ms2_time_sec <- calc_result$ms2$scan_time_ms / 1000
          n_windows <- estimate_window_count_preview(fwhm_median, target_dppp, ms2_time_sec)
        }
      }

      n_windows <- n_windows %||% 40
    } else {
      n_windows <- input$manual_n_windows %||% 40
    }

    min_width <- input$min_isolation_width %||% 2
    mz_range <- n_windows * min_width

    # Determine if this is a reasonable range (typical precursor spread is 400-1200 m/z)
    range_status <- if (mz_range < 100) {
      list(icon = "exclamation-triangle", msg = "Very narrow - may miss many precursors",
           box_class = "range-danger", text_class = "text-semantic-danger")
    } else if (mz_range < 200) {
      list(icon = "exclamation-circle", msg = "Narrow range - check coverage",
           box_class = "range-warning", text_class = "text-semantic-warning")
    } else if (mz_range > 600) {
      list(icon = "check-circle", msg = "Wide range - good coverage expected",
           box_class = "", text_class = "text-semantic-info")
    } else {
      list(icon = "check-circle", msg = "Typical range for DIA",
           box_class = "", text_class = "text-semantic-success")
    }

    tags$div(
      class = paste("mz-range-display", range_status$box_class),

      # Main value
      tags$div(
        style = "display: flex; justify-content: space-between; align-items: baseline;",
        tags$span(
          class = "text-accent",
          style = "font-size: 18px; font-weight: 700;",
          sprintf("%.0f Da", mz_range)
        ),
        tags$span(
          class = "text-muted",
          style = "font-size: 12px;",
          "Fixed m/z Range"
        )
      ),

      # Formula breakdown
      tags$div(
        style = "margin-top: 6px; padding-top: 6px; border-top: 1px dashed var(--border-subtle);",
        tags$span(
          class = "text-accent",
          style = "font-size: 12px;",
          sprintf("%d windows", n_windows)
        ),
        tags$span(class = "text-muted", style = "margin: 0 4px;", "x"),
        tags$span(
          class = "text-accent",
          style = "font-size: 12px;",
          sprintf("%.1f Da (min width)", min_width)
        )
      ),

      # Status indicator
      tags$div(
        class = range_status$text_class,
        style = "margin-top: 6px; font-size: 11px;",
        icon(range_status$icon), " ", range_status$msg
      )
    )
  })

  # Threshold for considering a component "slowed down" (5% tolerance)
  SLOWDOWN_THRESHOLD <- 1.05

  # Helper: compute overall efficiency (optimal / current cycle time)
  # Returns a list with all derived values for reuse across render functions
  compute_overall_efficiency <- function(result) {
    if (is.null(result)) return(list(efficiency_pct = 100, optimal_ms = 0,
      optimal_sec = 0, slowdown = 1, color = "var(--semantic-success)",
      color_bg = "var(--semantic-success-bg)", icon_class = "check-circle",
      limiting = NULL, ms1_optimal_scan = 0, ms2_optimal_scan = 0))

    current_ms <- result$cycle_time_ms
    ms1_scans <- result$ms1$scans_per_cycle %||% 1
    is_parallel <- result$instrument$cycle_calculation == "parallel"

    ms1_trans <- result$ms1$transient_ms %||% 0
    ms1_over <- result$ms1$overhead_ms %||% 0
    ms2_trans <- result$ms2$transient_ms %||% 0
    ms2_over <- result$ms2$overhead_ms %||% 0

    ms1_optimal_scan <- if (ms1_trans > 0) ms1_trans + ms1_over else result$ms1$scan_time_ms
    ms2_optimal_scan <- if (ms2_trans > 0) ms2_trans + ms2_over else result$ms2$scan_time_ms

    optimal_ms <- if (is_parallel) {
      max(ms1_scans * ms1_optimal_scan, result$window_count * ms2_optimal_scan)
    } else {
      ms1_scans * ms1_optimal_scan + result$window_count * ms2_optimal_scan
    }

    efficiency_pct <- min((optimal_ms / current_ms) * 100, 100)
    slowdown <- current_ms / optimal_ms

    # Color coding (color = solid, color_bg = translucent background)
    if (efficiency_pct >= 95) {
      color <- "var(--semantic-success)"; color_bg <- "var(--semantic-success-bg)"; icon_class <- "check-circle"
    } else if (efficiency_pct >= 70) {
      color <- "var(--semantic-warning)"; color_bg <- "var(--semantic-warning-bg)"; icon_class <- "exclamation-triangle"
    } else {
      color <- "var(--semantic-danger)"; color_bg <- "var(--semantic-danger-bg)"; icon_class <- "exclamation-triangle"
    }

    # Identify limiting component
    ms1_slowdown <- result$ms1$scan_time_ms / ms1_optimal_scan
    ms2_slowdown <- result$ms2$scan_time_ms / ms2_optimal_scan
    limiting <- if (ms1_slowdown > SLOWDOWN_THRESHOLD && ms2_slowdown > SLOWDOWN_THRESHOLD) {
      "MS1 & MS2"
    } else if (ms1_slowdown > SLOWDOWN_THRESHOLD) {
      "MS1"
    } else if (ms2_slowdown > SLOWDOWN_THRESHOLD) {
      "MS2"
    } else {
      NULL
    }

    list(efficiency_pct = efficiency_pct, optimal_ms = optimal_ms,
         optimal_sec = optimal_ms / 1000, slowdown = slowdown,
         color = color, color_bg = color_bg, icon_class = icon_class, limiting = limiting,
         ms1_optimal_scan = ms1_optimal_scan, ms2_optimal_scan = ms2_optimal_scan)
  }

  output$efficiency_badge <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) return(NULL)

    eff <- compute_overall_efficiency(result)

    tags$span(
      class = "efficiency-badge",
      style = sprintf("background: %s;", eff$color),
      sprintf("%.0f%% Eff.", eff$efficiency_pct)
    )
  })

  # --- Output: Expert Settings Cycle Time Feedback (compact, Step 2) ---
  output$expert_cycle_time_feedback <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) return(NULL)

    ms1_scans <- result$ms1$scans_per_cycle %||% 1
    is_parallel <- ms1_scans == 0

    eff <- compute_overall_efficiency(result)
    eff_pct <- eff$efficiency_pct
    eff_color <- eff$color

    breakdown <- if (is_parallel) {
      sprintf("MS1: %.0fms (parallel) | MS2: %d x %.1fms",
              result$ms1$scan_time_ms, result$window_count, result$ms2$scan_time_ms)
    } else {
      sprintf("MS1: %.0fms + MS2: %d x %.1fms",
              result$ms1$scan_time_ms, result$window_count, result$ms2$scan_time_ms)
    }

    tags$div(
      class = "panel-accent",
      style = "margin-bottom: 12px;",
      tags$div(
        style = "display: flex; justify-content: space-between; align-items: center;",
        tags$div(
          tags$strong("Current Cycle Time: "),
          tags$span(sprintf("%.3f sec", result$cycle_time_sec),
                    class = "text-accent",
                    style = "font-size: 16px; font-weight: 700;")
        ),
        tags$span(
          sprintf("%.0f%% Eff.", eff_pct),
          class = "efficiency-badge",
          style = sprintf("background: %s;", eff_color)
        )
      ),
      tags$div(
        class = "text-muted",
        style = "margin-top: 4px; font-size: 11px;",
        breakdown
      )
    )
  })

  # --- Output: Cycle Time Detail Table (Main Body) ---
  output$cycle_time_detail_table <- renderTable({
    result <- cycle_time_result()
    if (is.null(result)) {
      return(data.frame(
        Parameter = c("Waiting for instrument selection..."),
        Value = c("")
      ))
    }

    # Determine instrument type for display
    is_orbitrap <- result$instrument$analyzer_type == "orbitrap"
    ms1_scans <- result$ms1$scans_per_cycle %||% 1
    is_boxcar <- ms1_scans > 1
    is_parallel <- ms1_scans == 0

    # Build parameter list dynamically
    params <- c("Instrument")
    values <- c(result$instrument$name)

    if (is_orbitrap) {
      params <- c(params, "MS1 Resolution", "MS2 Resolution")
      values <- c(values,
                  format(result$ms1$resolution, big.mark = ","),
                  format(result$ms2$resolution, big.mark = ","))
    }

    params <- c(params, "MS1 Scans/Cycle")
    values <- c(values, sprintf("%d %s", ms1_scans,
                                ifelse(is_boxcar, "(Boxcar)",
                                       ifelse(is_parallel, "(Parallel)", ""))))

    params <- c(params, "MS1 Scan Time", "MS2 Scan Time", "MS2 Window Count")
    values <- c(values,
                sprintf("%.1f ms", result$ms1$scan_time_ms),
                sprintf("%.1f ms (%.1f Hz)", result$ms2$scan_time_ms, result$theoretical_ms2_rate_hz),
                as.character(result$window_count))

    if (is_boxcar || !is_parallel) {
      params <- c(params, "MS1 Total Time")
      values <- c(values, sprintf("%.0f ms (= %d x %.0f ms)",
                                  result$ms1$total_time_ms %||% result$ms1$scan_time_ms,
                                  ms1_scans, result$ms1$scan_time_ms))
    }

    params <- c(params, "MS2 Total Time", "Cycle Time")
    values <- c(values,
                sprintf("%.0f ms", result$ms2_total_time_ms),
                sprintf("%.3f sec (%.0f ms)", result$cycle_time_sec, result$cycle_time_ms))

    data.frame(Parameter = params, Value = values)
  }, striped = TRUE, hover = TRUE, spacing = "s", width = "100%")

  # --- Output: Cycle Time Visual Breakdown ---
  output$cycle_time_visual <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) {
      return(tags$p("Configure instrument settings to see breakdown.", class = "text-muted"))
    }

    total_ms <- result$cycle_time_ms
    ms1_total_ms <- result$ms1$total_time_ms  # Use total time (includes all MS1 scans in Boxcar mode)
    ms1_pct <- (ms1_total_ms / total_ms) * 100
    ms2_pct <- (result$ms2_total_time_ms / total_ms) * 100

    # For parallel instruments, adjust display
    is_parallel <- result$instrument$cycle_calculation == "parallel"

    if (is_parallel) {
      tags$div(
        tags$p(
          class = "text-muted",
          style = "font-size: 12px; margin-bottom: 8px;",
          "Parallel Mode: MS1 acquired during MS2 scans"
        ),
        tags$div(
          class = "ct-bar-ms1", style = "height: 24px; border-radius: 4px; position: relative; overflow: hidden;",
          tags$div(
            class = "ct-bar-ms2", style = "position: absolute; left: 0; top: 0; height: 100%; width: 100%;",
            tags$span(
              style = "position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); color: white; font-size: 11px; font-weight: 600;",
              sprintf("MS2: %.0f ms (100%%)", result$ms2_total_time_ms)
            )
          )
        )
      )
    } else {
      tags$div(
        tags$p(
          class = "text-muted",
          style = "font-size: 12px; margin-bottom: 8px;",
          "Sequential Mode: MS1 -> MS2"
        ),
        tags$div(
          style = "display: flex; height: 24px; border-radius: 4px; overflow: hidden;",
          tags$div(
            class = "ct-bar-ms1", style = sprintf("width: %.1f%%; display: flex; align-items: center; justify-content: center;", ms1_pct),
            tags$span(style = "color: white; font-size: 10px; font-weight: 600;",
                      sprintf("MS1 %.0fms", ms1_total_ms))
          ),
          tags$div(
            class = "ct-bar-ms2", style = sprintf("width: %.1f%%; display: flex; align-items: center; justify-content: center;", ms2_pct),
            tags$span(style = "color: white; font-size: 10px; font-weight: 600;",
                      sprintf("MS2 %.0fms", result$ms2_total_time_ms))
          )
        )
      )
    }
  })

  # --- Output: Efficiency Detail (Optimal vs Current comparison) ---
  output$efficiency_detail <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) return(NULL)

    current_sec <- result$cycle_time_sec

    # Reuse shared efficiency computation
    eff <- compute_overall_efficiency(result)
    efficiency_pct <- eff$efficiency_pct
    optimal_sec <- eff$optimal_sec
    slowdown <- eff$slowdown
    color <- eff$color
    icon_class <- eff$icon_class
    limiting <- eff$limiting

    tags$div(
      style = sprintf("padding: 12px; border-radius: 6px; background: %s; border-left: 3px solid %s;", eff$color_bg, color),

      # Header with efficiency
      tags$div(
        style = "display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;",
        tags$div(
          style = "display: flex; align-items: center; gap: 8px;",
          icon(icon_class, style = sprintf("color: %s; font-size: 16px;", color)),
          tags$strong(sprintf("Efficiency: %.0f%%", efficiency_pct),
                      style = sprintf("color: %s; font-size: 14px;", color))
        ),
        if (!is.null(limiting)) {
          tags$span(sprintf("%s limited", limiting),
                    class = "text-muted",
                    style = "font-size: 11px; font-style: italic;")
        }
      ),

      # Optimal vs Current comparison
      tags$div(
        style = "display: flex; gap: 16px; margin-bottom: 8px;",
        tags$div(
          style = "flex: 1; text-align: center; padding: 6px; background: var(--semantic-success-bg); border-radius: 4px;",
          tags$div(class = "text-muted", style = "font-size: 10px; text-transform: uppercase;", "Optimal (Auto IT)"),
          tags$div(class = "text-semantic-success", style = "font-size: 18px; font-weight: 700;",
                   sprintf("%.3f sec", optimal_sec))
        ),
        tags$div(
          style = sprintf("flex: 1; text-align: center; padding: 6px; background: %s; border-radius: 4px;", eff$color_bg),
          tags$div(class = "text-muted", style = "font-size: 10px; text-transform: uppercase;", "Current"),
          tags$div(style = sprintf("font-size: 18px; font-weight: 700; color: %s;", color),
                   sprintf("%.3f sec", current_sec))
        )
      ),

      # Progress bar
      tags$div(
        style = "background: var(--surface-sunken); height: 8px; border-radius: 4px; overflow: hidden; margin-bottom: 6px;",
        tags$div(
          style = sprintf("width: %.1f%%; height: 100%%; background: %s; border-radius: 4px;",
                          min(efficiency_pct, 100), color)
        )
      ),

      # Slowdown message (only when not optimal)
      if (slowdown > SLOWDOWN_THRESHOLD) {
        tags$p(
          class = "text-secondary",
          style = "margin: 0; font-size: 12px;",
          sprintf("Current settings are %.1fx slower than optimal. Use Auto IT to recover speed.", slowdown)
        )
      } else {
        tags$p(
          class = "text-semantic-success",
          style = "margin: 0; font-size: 12px;",
          "Optimal! All injection times match transient times."
        )
      }
    )
  })

  # --- Output: Duty Cycle Sync Info (parallel instruments only) ---
  output$duty_cycle_sync_info <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) return(NULL)

    is_parallel <- result$instrument$cycle_calculation == "parallel"
    if (!is_parallel) return(NULL)

    # Get MS1 transient time (Orbitrap MS1, even for Astral instruments)
    # For Astral: MS1 is on Orbitrap, so transient_ms = Orbitrap transient at chosen resolution
    ms1_trans_ms <- result$ms1$transient_ms
    if (is.null(ms1_trans_ms) || ms1_trans_ms < 10) {
      # Fallback: derive from resolution if transient_ms seems wrong (e.g., Astral detection time)
      ms1_res <- result$ms1$resolution %||% 240000
      ms1_trans_ms <- get_transient_time(ms1_res, "orbitrap")
      if (is.na(ms1_trans_ms)) ms1_trans_ms <- result$ms1$scan_time_ms
    }
    ms2_scan_ms <- result$ms2$scan_time_ms
    n_windows <- result$window_count

    sync <- calculate_duty_cycle_sync(
      ms1_time_ms = ms1_trans_ms,
      ms2_scan_time_ms = ms2_scan_ms,
      n_windows = n_windows
    )

    # Badge color based on sync quality
    if (sync$duty_cycle_pct >= 95) {
      badge_class <- "status-pass"
      badge_text <- sprintf("%.0f%% Synced", sync$duty_cycle_pct)
    } else if (sync$duty_cycle_pct >= 80) {
      badge_class <- "badge-accent"
      badge_text <- sprintf("%.0f%% Duty Cycle", sync$duty_cycle_pct)
    } else {
      badge_class <- "status-fail"
      badge_text <- sprintf("%.0f%% Duty Cycle", sync$duty_cycle_pct)
    }

    # Idle detail
    idle_text <- if (sync$ms1_idle_ms > 1) {
      sprintf("MS1 idle: %.0f ms", sync$ms1_idle_ms)
    } else if (sync$ms2_idle_ms > 1) {
      sprintf("MS2 idle: %.0f ms", sync$ms2_idle_ms)
    } else {
      "No idle time"
    }

    tags$div(
      style = "padding-top: 25px;",
      tags$div(
        class = "panel-accent",
        tags$div(
          style = "display: flex; justify-content: space-between; align-items: center;",
          tags$strong("Duty Cycle Sync"),
          tags$span(class = paste("efficiency-badge", badge_class), badge_text)
        ),
        tags$div(
          class = "text-muted", style = "font-size: 11px; margin-top: 6px;",
          sprintf("MS1: %.0f ms | MS2: %d x %.1f ms = %.0f ms",
                  ms1_trans_ms, n_windows, ms2_scan_ms, sync$total_ms2_time_ms)
        ),
        tags$div(
          class = "text-muted", style = "font-size: 11px;",
          idle_text
        ),
        tags$div(
          class = "text-muted", style = "font-size: 11px;",
          sprintf("Sync-optimal: %d windows", sync$n_sync_optimal)
        )
      )
    )
  })

  # --- Output: Instrument Width Recommendations ---
  observe({
    instrument <- input$instrument
    if (is.null(instrument)) return()

    tryCatch({
      config <- get_instrument_config(instrument)
      recs <- get_instrument_width_recommendations(config)

      updateNumericInput(session, "min_isolation_width", value = recs$min_width_da)
      updateNumericInput(session, "max_isolation_width", value = recs$max_width_da)
    }, error = function(e) NULL)
  })

  # --- Output: Instrument type flag for conditional UI ---
  output$is_parallel_instrument <- reactive({
    result <- cycle_time_result()
    if (is.null(result)) return(FALSE)
    identical(result$instrument$cycle_calculation, "parallel")
  })
  outputOptions(output, "is_parallel_instrument", suspendWhenHidden = FALSE)

  # Return the reactive for other modules to use
  return(cycle_time_result)
}
