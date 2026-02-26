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
      # Astral: use the Astral IT slider (MS1 on Orbitrap, MS2 on Astral - parallel)
      ms2_it <- input$astral_ms2_it %||% 3.0

      config <- list(
        instrument = list(preset = instrument),
        ms1 = list(
          resolution = 120000,  # Orbitrap MS1
          max_injection_time_ms = 50,
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

  # --- Output: Greedy Auto Windows Info ---
  # Shows the recommended window count when Auto mode is selected
  output$greedy_auto_windows_info <- renderUI({
    # Calculate recommended windows from DPPP target and cycle time
    calc_result <- cycle_time_result()

    # Try to get windows from optimization plan first
    plan_windows <- rv$optimization_plan$n_windows_per_bin

    # Calculate based on target DPPP if we have FWHM data
    dppp_windows <- NULL
    if (!is.null(rv$validated_data)) {
      fwhm_values <- ensure_fwhm_seconds(rv$validated_data$data$FWHM)
      fwhm_median <- median(fwhm_values, na.rm = TRUE)

      if (!is.null(calc_result) && !is.na(fwhm_median)) {
        target_dppp <- input$target_dppp %||% 7.0
        ms2_time_sec <- calc_result$ms2$scan_time_ms / 1000
        dppp_windows <- estimate_window_count_preview(fwhm_median, target_dppp, ms2_time_sec)
      }
    }

    # Determine which value to show
    if (!is.null(plan_windows)) {
      # Optimization plan available
      tags$div(
        style = "background: rgba(39, 174, 96, 0.15); padding: 6px 8px; border-radius: 4px; margin: 4px 0;",
        tags$span(
          style = "color: #27ae60; font-weight: 600;",
          sprintf("Auto: %d windows", plan_windows)
        ),
        tags$br(),
        tags$small("(from optimization plan)", style = "color: #7f8c8d;")
      )
    } else if (!is.null(dppp_windows)) {
      # Estimated from DPPP calculation
      tags$div(
        style = "background: rgba(52, 152, 219, 0.15); padding: 6px 8px; border-radius: 4px; margin: 4px 0;",
        tags$span(
          style = "color: #3498db; font-weight: 600;",
          sprintf("Estimated: %d windows", dppp_windows)
        ),
        tags$br(),
        tags$small(sprintf("(for DPPP %.1f with current settings)", input$target_dppp),
                   style = "color: #7f8c8d;")
      )
    } else {
      # No data available yet
      tags$div(
        style = "background: rgba(149, 165, 166, 0.15); padding: 6px 8px; border-radius: 4px; margin: 4px 0;",
        tags$span(
          style = "color: #7f8c8d;",
          "Upload data to see recommended windows"
        )
      )
    }
  })

  # --- Output: Greedy m/z Range Display ---
  output$greedy_mz_range_display <- renderUI({
    # Get window count (from auto or manual)
    if (isTRUE(input$greedy_auto_windows)) {
      # Priority: optimization plan > estimated > default
      n_windows <- rv$optimization_plan$n_windows_per_bin

      # Estimate if no plan yet
      if (is.null(n_windows) && !is.null(rv$validated_data)) {
        calc_result <- cycle_time_result()
        fwhm_values <- ensure_fwhm_seconds(rv$validated_data$data$FWHM)
        fwhm_median <- median(fwhm_values, na.rm = TRUE)
        if (!is.null(calc_result) && !is.na(fwhm_median)) {
          target_dppp <- input$target_dppp %||% 7.0
          ms2_time_sec <- calc_result$ms2$scan_time_ms / 1000
          n_windows <- estimate_window_count_preview(fwhm_median, target_dppp, ms2_time_sec)
        }
      }

      n_windows <- n_windows %||% 40
    } else {
      n_windows <- input$greedy_n_windows %||% 40
    }

    min_width <- input$min_isolation_width %||% 2
    mz_range <- n_windows * min_width

    # Determine if this is a reasonable range (typical precursor spread is 400-1200 m/z)
    range_status <- if (mz_range < 100) {
      list(color = "#e74c3c", icon = "!", msg = "Very narrow - may miss many precursors")
    } else if (mz_range < 200) {
      list(color = "#f39c12", icon = "~", msg = "Narrow range - check coverage")
    } else if (mz_range > 600) {
      list(color = "#3498db", icon = "o", msg = "Wide range - good coverage expected")
    } else {
      list(color = "#27ae60", icon = "v", msg = "Typical range for DIA")
    }

    tags$div(
      style = "background: rgba(241, 196, 15, 0.25); padding: 10px; border-radius: 6px; margin: 8px 0; border: 1px solid rgba(241, 196, 15, 0.4);",

      # Main value
      tags$div(
        style = "display: flex; justify-content: space-between; align-items: baseline;",
        tags$span(
          style = "font-size: 18px; font-weight: 700; color: #d35400;",
          sprintf("%.0f Da", mz_range)
        ),
        tags$span(
          style = "font-size: 12px; color: #7f8c8d;",
          "Fixed m/z Range"
        )
      ),

      # Formula breakdown
      tags$div(
        style = "margin-top: 6px; padding-top: 6px; border-top: 1px dashed rgba(211, 84, 0, 0.3);",
        tags$span(
          style = "font-size: 12px; color: #8e44ad;",
          sprintf("%d windows", n_windows)
        ),
        tags$span(style = "color: #7f8c8d; margin: 0 4px;", "x"),
        tags$span(
          style = "font-size: 12px; color: #16a085;",
          sprintf("%.1f Da (min width)", min_width)
        )
      ),

      # Status indicator
      tags$div(
        style = sprintf("margin-top: 6px; font-size: 11px; color: %s;", range_status$color),
        sprintf("%s %s", range_status$icon, range_status$msg)
      )
    )
  })

  # Helper: compute overall efficiency (optimal / current cycle time)
  compute_overall_efficiency <- function(result) {
    if (is.null(result)) return(100)

    current_ms <- result$cycle_time_ms
    ms1_scans <- result$ms1$scans_per_cycle %||% 1
    is_parallel <- result$instrument$cycle_calculation == "parallel"

    ms1_trans <- result$ms1$transient_ms %||% 0
    ms1_over <- result$ms1$overhead_ms %||% 0
    ms2_trans <- result$ms2$transient_ms %||% 0
    ms2_over <- result$ms2$overhead_ms %||% 0

    ms1_opt <- if (ms1_trans > 0) ms1_trans + ms1_over else result$ms1$scan_time_ms
    ms2_opt <- if (ms2_trans > 0) ms2_trans + ms2_over else result$ms2$scan_time_ms

    optimal_ms <- if (is_parallel) {
      max(ms1_scans * ms1_opt, result$window_count * ms2_opt)
    } else {
      ms1_scans * ms1_opt + result$window_count * ms2_opt
    }

    min((optimal_ms / current_ms) * 100, 100)
  }

  output$efficiency_badge <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) return(NULL)

    efficiency_pct <- compute_overall_efficiency(result)
    color <- if (efficiency_pct >= 95) "#27ae60" else if (efficiency_pct >= 70) "#f39c12" else "#e74c3c"

    tags$span(
      style = sprintf("background: %s; color: white; padding: 2px 8px; border-radius: 4px; font-size: 10px; font-weight: 600;", color),
      sprintf("%.0f%% Eff.", efficiency_pct)
    )
  })

  # --- Output: Expert Settings Cycle Time Feedback (compact, Step 2) ---
  output$expert_cycle_time_feedback <- renderUI({
    result <- cycle_time_result()
    if (is.null(result)) return(NULL)

    ms1_scans <- result$ms1$scans_per_cycle %||% 1
    is_parallel <- ms1_scans == 0

    eff_pct <- compute_overall_efficiency(result)
    eff_color <- if (eff_pct >= 95) "#27ae60" else if (eff_pct >= 70) "#f39c12" else "#e74c3c"

    breakdown <- if (is_parallel) {
      sprintf("MS1: %.0fms (parallel) | MS2: %d x %.1fms",
              result$ms1$scan_time_ms, result$window_count, result$ms2$scan_time_ms)
    } else {
      sprintf("MS1: %.0fms + MS2: %d x %.1fms",
              result$ms1$scan_time_ms, result$window_count, result$ms2$scan_time_ms)
    }

    tags$div(
      style = "background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%); padding: 10px 14px; border-radius: 6px; margin-bottom: 12px; border-left: 3px solid #1abc9c;",
      tags$div(
        style = "display: flex; justify-content: space-between; align-items: center;",
        tags$div(
          tags$strong("Current Cycle Time: ", style = "color: #2c3e50;"),
          tags$span(sprintf("%.3f sec", result$cycle_time_sec),
                    style = "font-size: 16px; font-weight: 700; color: #1abc9c;")
        ),
        tags$span(
          sprintf("%.0f%% Eff.", eff_pct),
          style = sprintf("background: %s; color: white; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600;", eff_color)
        )
      ),
      tags$div(
        style = "margin-top: 4px; font-size: 11px; color: #7f8c8d;",
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
      return(tags$p("Configure instrument settings to see breakdown.", style = "color: #999;"))
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
          style = "font-size: 12px; color: #7f8c8d; margin-bottom: 8px;",
          "Parallel Mode: MS1 acquired during MS2 scans"
        ),
        tags$div(
          style = "background: #3498db; height: 24px; border-radius: 4px; position: relative; overflow: hidden;",
          tags$div(
            style = sprintf("position: absolute; left: 0; top: 0; height: 100%%; width: 100%%; background: #1abc9c;"),
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
          style = "font-size: 12px; color: #7f8c8d; margin-bottom: 8px;",
          "Sequential Mode: MS1 -> MS2"
        ),
        tags$div(
          style = "display: flex; height: 24px; border-radius: 4px; overflow: hidden;",
          tags$div(
            style = sprintf("width: %.1f%%; background: #3498db; display: flex; align-items: center; justify-content: center;", ms1_pct),
            tags$span(style = "color: white; font-size: 10px; font-weight: 600;",
                      sprintf("MS1 %.0fms", ms1_total_ms))
          ),
          tags$div(
            style = sprintf("width: %.1f%%; background: #1abc9c; display: flex; align-items: center; justify-content: center;", ms2_pct),
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

    # Current cycle time
    current_ms <- result$cycle_time_ms
    current_sec <- result$cycle_time_sec

    # Compute optimal cycle time (Auto IT = transient for both MS1 and MS2)
    ms1_scans <- result$ms1$scans_per_cycle %||% 1
    is_parallel <- result$instrument$cycle_calculation == "parallel"

    # Optimal scan times: transient + overhead (minimum achievable)
    ms1_trans <- result$ms1$transient_ms %||% 0
    ms1_over <- result$ms1$overhead_ms %||% 0
    ms2_trans <- result$ms2$transient_ms %||% 0
    ms2_over <- result$ms2$overhead_ms %||% 0

    ms1_optimal_scan <- if (ms1_trans > 0) ms1_trans + ms1_over else result$ms1$scan_time_ms
    ms2_optimal_scan <- if (ms2_trans > 0) ms2_trans + ms2_over else result$ms2$scan_time_ms

    # Calculate optimal cycle time
    if (is_parallel) {
      ms1_total_opt <- ms1_scans * ms1_optimal_scan
      ms2_total_opt <- result$window_count * ms2_optimal_scan
      optimal_ms <- max(ms1_total_opt, ms2_total_opt)
    } else {
      optimal_ms <- ms1_scans * ms1_optimal_scan + result$window_count * ms2_optimal_scan
    }

    optimal_sec <- optimal_ms / 1000

    # Efficiency = optimal / current (how much of cycle time is productive)
    efficiency_pct <- min((optimal_ms / current_ms) * 100, 100)
    slowdown <- current_ms / optimal_ms

    # Color coding
    if (efficiency_pct >= 95) {
      color <- "#27ae60"
      icon_class <- "check-circle"
    } else if (efficiency_pct >= 70) {
      color <- "#f39c12"
      icon_class <- "exclamation-triangle"
    } else {
      color <- "#e74c3c"
      icon_class <- "exclamation-triangle"
    }

    # Identify which component is limiting (MS1 or MS2 or both)
    ms1_slowdown <- result$ms1$scan_time_ms / ms1_optimal_scan
    ms2_slowdown <- result$ms2$scan_time_ms / ms2_optimal_scan
    limiting <- if (ms1_slowdown > 1.05 && ms2_slowdown > 1.05) {
      "MS1 & MS2"
    } else if (ms1_slowdown > 1.05) {
      "MS1"
    } else if (ms2_slowdown > 1.05) {
      "MS2"
    } else {
      NULL
    }

    tags$div(
      style = sprintf("padding: 12px; border-radius: 6px; background: %s15; border-left: 3px solid %s;", color, color),

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
                    style = "font-size: 11px; color: #7f8c8d; font-style: italic;")
        }
      ),

      # Optimal vs Current comparison
      tags$div(
        style = "display: flex; gap: 16px; margin-bottom: 8px;",
        tags$div(
          style = "flex: 1; text-align: center; padding: 6px; background: rgba(39, 174, 96, 0.1); border-radius: 4px;",
          tags$div(style = "font-size: 10px; color: #7f8c8d; text-transform: uppercase;", "Optimal (Auto IT)"),
          tags$div(style = "font-size: 18px; font-weight: 700; color: #27ae60;",
                   sprintf("%.3f sec", optimal_sec))
        ),
        tags$div(
          style = sprintf("flex: 1; text-align: center; padding: 6px; background: %s15; border-radius: 4px;", color),
          tags$div(style = "font-size: 10px; color: #7f8c8d; text-transform: uppercase;", "Current"),
          tags$div(style = sprintf("font-size: 18px; font-weight: 700; color: %s;", color),
                   sprintf("%.3f sec", current_sec))
        )
      ),

      # Progress bar
      tags$div(
        style = "background: #e9ecef; height: 8px; border-radius: 4px; overflow: hidden; margin-bottom: 6px;",
        tags$div(
          style = sprintf("width: %.1f%%; height: 100%%; background: %s; border-radius: 4px;",
                          min(efficiency_pct, 100), color)
        )
      ),

      # Slowdown message (only when not optimal)
      if (slowdown > 1.05) {
        tags$p(
          style = "margin: 0; font-size: 12px; color: #34495e;",
          sprintf("Current settings are %.1fx slower than optimal. Use Auto IT to recover speed.", slowdown)
        )
      } else {
        tags$p(
          style = "margin: 0; font-size: 12px; color: #27ae60;",
          "Optimal! All injection times match transient times."
        )
      }
    )
  })

  # Return the reactive for other modules to use
  return(cycle_time_result)
}
