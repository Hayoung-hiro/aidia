# Shared, snapshot-only calculation for preview and confirmed results.
.shiny_compute_windows <- function(input, validated_data, calc_result = NULL) {
  strategy_configs <- .shiny_strategy_configs(input)
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

  optimization_plan <- plan_optimization(
    validated_data = validated_data,
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
  cat("[Shiny] Required Cycle Time:", optimization_plan$required_cycle_time_sec, "sec\n")
  cat("[Shiny] Current Cycle Time:", optimization_plan$current_cycle_time_sec, "sec\n")
  cat("[Shiny] Windows per bin:", optimization_plan$window_count_per_bin, "\n")
  cat("[Shiny] t_scan:", optimization_plan$timing$t_scan_ms, "ms\n")
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
    rt_range <- range(validated_data$data$RT.Apex, na.rm = TRUE)
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

  strategy_cfg <- strategy_configs[[input$mz_strategy]]
  cat("[Shiny] Strategy config:", input$mz_strategy, "\n")
  cat("[Shiny]  ", paste(names(as.list(strategy_cfg)), collapse = ", "), "\n")

  # For non-greedy strategies, pass manual window count override
  n_win_override <- if (!use_auto_windows && input$mz_strategy != "greedy") {
    as.integer(manual_n_win)
  } else {
    NULL  # greedy handles it internally via greedy_config
  }

  optimized_windows <- optimize_windows(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    strategy_config = strategy_cfg,
    comparison_strategy_configs = strategy_configs,
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
  list(plan = optimization_plan, windows = optimized_windows)
}
