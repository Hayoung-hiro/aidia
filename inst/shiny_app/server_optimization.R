# server_optimization.R - Run Optimization, Results Display, Summary Tables

server_optimization <- function(input, output, session, rv, cycle_time_result) {

  # --- DPPP Preset Buttons ---
  observeEvent(input$preset_id, {
    updateNumericInput(session, "target_dppp", value = 1.5)
  })
  observeEvent(input$preset_balanced, {
    updateNumericInput(session, "target_dppp", value = 4.0)
  })
  observeEvent(input$preset_quant, {
    updateNumericInput(session, "target_dppp", value = 7.0)
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

      # Get strategy-specific parameters with defaults
      strategy_params <- list(
        # Quantile parameters
        quantile_lower = input$quantile_lower %||% 0.05,
        quantile_upper = input$quantile_upper %||% 0.95,
        quantile_apply_smoothing = isTRUE(input$quantile_apply_smoothing %||% FALSE),
        # Coverage parameters
        target_coverage = (input$target_coverage %||% 90) / 100,  # Convert % to ratio
        # Greedy parameters
        mz_step = input$greedy_mz_step %||% 2.0,
        greedy_n_windows = NULL,  # Will be set below if manual
        greedy_apply_smoothing = isTRUE(input$greedy_apply_smoothing %||% TRUE),
        # Outlier parameters
        outlier_threshold = input$outlier_threshold %||% 3.0,
        outlier_apply_smoothing = isTRUE(input$outlier_apply_smoothing %||% FALSE),
        # SG Smoothing parameters (shared)
        smoothing_window = 7,
        polynomial_order = 3,
        # KDE parameters
        kde_density_threshold = (input$kde_density_threshold %||% 10) / 100,  # Convert % to ratio
        kde_min_coverage = (input$kde_min_coverage %||% 80) / 100  # Convert % to ratio
      )

      # Handle Greedy window count (auto vs manual)
      if (input$mz_strategy == "greedy" && !isTRUE(input$greedy_auto_windows)) {
        strategy_params$greedy_n_windows <- input$greedy_n_windows %||% 40
        cat(sprintf("[Shiny] Greedy: Manual window count = %d\n", strategy_params$greedy_n_windows))
      }

      cat("[Shiny] Strategy parameters:\n")
      cat(sprintf("  - Quantile: P%.0f-P%.0f, SG=%s\n",
                  strategy_params$quantile_lower * 100,
                  strategy_params$quantile_upper * 100,
                  ifelse(strategy_params$quantile_apply_smoothing, "YES", "NO")))
      cat(sprintf("  - Coverage target: %.0f%%\n", strategy_params$target_coverage * 100))
      cat(sprintf("  - Greedy mz_step: %.1f Da, SG=%s\n",
                  strategy_params$mz_step,
                  ifelse(strategy_params$greedy_apply_smoothing, "YES", "NO")))
      if (!is.null(strategy_params$greedy_n_windows)) {
        cat(sprintf("  - Greedy n_windows: %d (manual)\n", strategy_params$greedy_n_windows))
      }
      cat(sprintf("  - Outlier threshold: %.1f SD, SG=%s\n",
                  strategy_params$outlier_threshold,
                  ifelse(strategy_params$outlier_apply_smoothing, "YES", "NO")))
      cat(sprintf("  - KDE: threshold=%.0f%%, min_coverage=%.0f%%\n",
                  strategy_params$kde_density_threshold * 100,
                  strategy_params$kde_min_coverage * 100))

      rv$optimized_windows <- optimize_windows(
        validated_data = rv$validated_data,
        optimization_plan = rv$optimization_plan,
        mz_strategy = input$mz_strategy,
        window_mode = input$window_mode %||% "density",
        rt_bin_width_min = rt_bin_width_final,
        rt_binning_mode = rt_binning_mode_final,
        cpd_significance_level = input$cpd_significance %||% 0.05,
        cpd_min_bin_width = input$cpd_min_bin_width %||% 1.0,
        edge_void_buffer_min = input$edge_void_buffer %||% 0.5,
        edge_wash_min_precursors = input$edge_wash_threshold %||% 30,
        min_width_da = input$min_isolation_width %||% 2,
        # Pass strategy-specific parameters
        quantile_lower = strategy_params$quantile_lower,
        quantile_upper = strategy_params$quantile_upper,
        quantile_apply_smoothing = strategy_params$quantile_apply_smoothing,
        target_coverage = strategy_params$target_coverage,
        mz_step = strategy_params$mz_step,
        n_windows_override = strategy_params$greedy_n_windows,  # For Greedy manual override
        greedy_apply_smoothing = strategy_params$greedy_apply_smoothing,
        outlier_threshold = strategy_params$outlier_threshold,
        outlier_apply_smoothing = strategy_params$outlier_apply_smoothing,
        smoothing_window = strategy_params$smoothing_window,
        polynomial_order = strategy_params$polynomial_order,
        # KDE parameters
        kde_density_threshold = strategy_params$kde_density_threshold,
        kde_min_coverage = strategy_params$kde_min_coverage,
        # Forbidden zone placement optimization (all modes, default: recommended ON)
        fz_offset = if (isTRUE(input$fz_offset_preset == "custom")) {
          as.numeric(input$custom_fz_offset %||% 0.25)
        } else {
          as.numeric(input$fz_offset_preset %||% "0.25")  # "0" = disabled
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
    tags$p(
      sprintf("%s windows across %d RT bins (strategy: %s)",
              format(n_windows, big.mark = ","), n_rt_bins, strategy),
      style = "margin: 0; font-size: 14px;"
    )
  })

  output$before_summary <- renderUI({
    req(rv$validated_data)

    data <- rv$validated_data$data
    fwhm_sec <- ensure_fwhm_seconds(data$FWHM)
    median_fwhm_sec <- median(fwhm_sec, na.rm = TRUE)

    calc_result <- cycle_time_result()
    ct_text <- if (!is.null(calc_result)) sprintf("%.3f sec", calc_result$cycle_time_sec) else "N/A"

    # Estimate DPPP
    dppp_text <- if (!is.null(calc_result) && !is.na(median_fwhm_sec)) {
      est_dppp <- (1.7 * median_fwhm_sec) / calc_result$cycle_time_sec
      sprintf("~%.1f", est_dppp)
    } else {
      "N/A"
    }

    tags$div(
      style = "font-size: 14px; line-height: 2.2;",
      tags$div(tags$strong("Precursors: "), format(nrow(data), big.mark = ",")),
      tags$div(tags$strong("RT Range: "),
               sprintf("%.1f - %.1f min", min(data$RT.Apex, na.rm = TRUE), max(data$RT.Apex, na.rm = TRUE))),
      tags$div(tags$strong("m/z Range: "),
               sprintf("%.1f - %.1f Da", min(data$Precursor.Mz, na.rm = TRUE), max(data$Precursor.Mz, na.rm = TRUE))),
      tags$div(tags$strong("Median FWHM: "), sprintf("%.2f sec", median_fwhm_sec)),
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
    mode_colors <- list(
      density = "#1abc9c", fixed = "#3498db", staggered = "#9b59b6"
    )
    mode_labels <- list(
      density = "Density (Variable)", fixed = "Fixed (Equal)", staggered = "Staggered (Offset)"
    )
    mode_badge <- tags$span(
      style = sprintf(
        "background: %s; color: white; padding: 2px 8px; border-radius: 4px; font-weight: 600; font-size: 12px;",
        mode_colors[[used_mode]] %||% "#95a5a6"
      ),
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
        tags$strong("2-Cycle Interleaved: "),
        sprintf("C1: %d + C2: %d windows (forbidden zone: %.4f)", n_cycle1, n_cycle2, fz_val)
      )
    } else {
      tags$div(
        tags$strong("Width: "),
        sprintf("%.1f Da (uniform)", mean_width)
      )
    }

    # DPPP verification badge
    dppp_line <- if (!is.null(dppp_v)) {
      badge_style <- if (abs(dppp_v$deviation_pct) <= 5) {
        "background: #27ae60; color: white; padding: 2px 8px; border-radius: 4px; font-weight: 600; font-size: 12px;"
      } else {
        "background: #e74c3c; color: white; padding: 2px 8px; border-radius: 4px; font-weight: 600; font-size: 12px;"
      }
      badge_text <- if (abs(dppp_v$deviation_pct) <= 5) "PASS" else "WARNING"

      tags$div(
        tags$strong("Actual DPPP: "),
        sprintf("%.1f ", dppp_v$actual_dppp_median),
        tags$span(badge_text, style = badge_style)
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
      style = "font-size: 14px; line-height: 2.2;",
      tags$div(tags$strong("Windows: "), format(n_windows, big.mark = ",")),
      tags$div(tags$strong("RT Bins: "), n_rt_bins),
      tags$div(tags$strong("Mode: "), mode_badge),
      tags$div(tags$strong("Mean Width: "), sprintf("%.1f Da", mean_width)),
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
        deviation_str <- paste(deviation_str, "(WARNING)")
      } else {
        deviation_str <- paste(deviation_str, "(PASS)")
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
    strategy_label <- if (exists("format_strategy_label")) {
      format_strategy_label(params$mz_strategy)
    } else {
      toupper(params$mz_strategy)
    }

    tags$div(
      style = "font-size: 13px;",

      # Strategy badge
      tags$div(
        style = "margin-bottom: 10px;",
        tags$span(
          style = "background: #2c3e50; color: white; padding: 4px 10px; border-radius: 4px; font-weight: 600; font-size: 12px;",
          strategy_label
        ),
        tags$span(
          style = "background: #16a085; color: white; padding: 4px 10px; border-radius: 4px; font-weight: 600; font-size: 12px; margin-left: 4px;",
          params$window_mode %||% "density"
        )
      ),

      # m/z range
      tags$div(
        style = "padding: 8px; background: #f8f9fa; border-radius: 6px; margin-bottom: 8px; border-left: 3px solid #3498db;",
        tags$div(
          style = "font-weight: 600; color: #2c3e50;",
          sprintf("m/z Range: %.1f - %.1f Da (%.0f Da span)", mz_min, mz_max, mz_span)
        ),
        tags$div(
          style = "color: #7f8c8d; font-size: 12px; margin-top: 4px;",
          sprintf("%.0f windows/bin | %d RT bins", windows_per_bin, n_rt_bins)
        )
      ),

      # Width distribution
      tags$div(
        style = "padding: 8px; background: #f8f9fa; border-radius: 6px; border-left: 3px solid #1abc9c;",
        tags$div(
          style = "font-weight: 600; color: #2c3e50;",
          "Window Width Distribution"
        ),
        tags$div(
          style = "margin-top: 4px; color: #34495e;",
          sprintf("Min: %.1f Da | Mean: %.1f Da | Max: %.1f Da", min_width, mean_width, max_width)
        ),
        if (params$window_mode == "density") {
          tags$div(
            style = "color: #7f8c8d; font-size: 11px; margin-top: 4px; font-style: italic;",
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
      DT::formatRound(columns = c("mz_start", "mz_end", "window_width"), digits = 2)
  })
}

  # --- ValueBox Rendering for Results Summary Dashboard ---
  output$summary_box_cycle_time <- renderValueBox({
    req(rv$optimization_complete, rv$optimization_plan, rv$validated_data)
    
    orig_ct <- rv$validated_data$stats$cycle_time_sec
    new_ct <- rv$optimization_plan$stats$mean_cycle_time_sec
    
    if(is.null(orig_ct) || is.na(orig_ct) || orig_ct == 0) orig_ct <- new_ct # Fallback
    
    diff_pct <- round((orig_ct - new_ct) / orig_ct * 100, 1)
    
    subtitle <- "Cycle Time"
    icon_name <- "clock"
    color <- "info"
    
    if(diff_pct > 5) {
      subtitle <- paste0("Cycle Time (-", diff_pct, "%)")
      color <- "success"
    } else if(diff_pct < -5) {
      subtitle <- paste0("Cycle Time (+", abs(diff_pct), "%)")
      color <- "warning"
    }
    
    valueBox(
      value = paste0(round(new_ct, 2), " s"),
      subtitle = subtitle,
      icon = icon(icon_name),
      color = color
    )
  })

  output$summary_box_dppp <- renderValueBox({
    req(rv$optimization_complete, rv$optimization_plan, rv$validated_data)
    
    orig_dppp <- rv$validated_data$stats$dppp
    new_dppp <- rv$optimization_plan$stats$mean_dppp
    
    if(is.null(orig_dppp) || is.na(orig_dppp)) orig_dppp <- new_dppp # Fallback
    
    diff_val <- round(new_dppp - orig_dppp, 1)
    
    subtitle <- "Mean DPPP"
    icon_name <- "chart-line"
    color <- "info"
    
    if(diff_val >= 0.5) {
      subtitle <- paste0("Mean DPPP (+", diff_val, ")")
      color <- "success"
    } else if(diff_val <= -0.5) {
      subtitle <- paste0("Mean DPPP (", diff_val, ")")
      color <- "warning"
    }
    
    valueBox(
      value = round(new_dppp, 1),
      subtitle = subtitle,
      icon = icon(icon_name),
      color = color
    )
  })

  output$summary_box_windows <- renderValueBox({
    req(rv$optimization_complete, rv$optimization_plan)
    
    n_windows <- rv$optimization_plan$stats$n_windows
    
    valueBox(
      value = n_windows,
      subtitle = "Total Isolation Windows",
      icon = icon("layer-group"),
      color = "primary"
    )
  })
