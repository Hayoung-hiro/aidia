# visualization.R - Stage 4: Visualization & Reporting (Orchestrator)
#
# Purpose: Generate comprehensive visualizations and reports for DIA window optimization
#
# Version: 4.1 (Modularized architecture)
#
# Architecture:
#   This file is the orchestrator that sources modular plot functions from R/
#   and coordinates the overall visualization pipeline.
#
# Sourced Modules:
#   - R/plot_dppp.R: DPPP distribution comparison plots
#   - R/plot_density.R: Density heatmap and normalized density
#   - R/plot_satisfaction.R: Satisfaction vs cycle time curve
#   - R/export_plots.R: Export and PDF report functions
#
# Legacy Plot Modules (consolidated into R/):
#   - R/plot_rt_histogram.R: Binned RT histogram
#   - R/plot_density_overlay.R: Coverage map grid
#   - R/plot_window_width.R: Window width distribution
#   - R/plot_strategy_comparison.R: Strategy width comparison
#
# Main Functions:
#   1. generate_visualizations() - Main orchestration function
#   2. calculate_summary_statistics() - Calculate optimization metrics
#
# Input: Refactored pipeline outputs
#   - validated_data (ValidatedData from Stage 1)
#   - optimization_plan (OptimizationPlan from Stage 2)
#   - optimized_windows (OptimizedWindows from Stage 3)
#
# Output: VisualizationResult with plots, reports, and method files


# =============================================================================
# Main Visualization Function
# =============================================================================

#' Generate All Visualizations
#'
#' Main orchestration function that generates plots, PDF report, and
#' individual plot exports. As of v0.4.1, this function is registry-driven:
#' plot definitions live in \code{R/plot_registry.R} and report templates
#' select a subset of them.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#' @param output_dir Character, output directory path
#' @param create_pdf Logical, create comprehensive PDF report
#' @param create_individual_plots Logical, export individual plots
#' @param plot_format Character, "png" or "pdf"
#' @param plot_dpi Numeric, plot resolution (default: 300)
#' @param windows_list Optional: Pre-computed windows for all strategies
#' @param report_template Character, name of report template
#'   (\code{"full"} = ~44 plots, default; \code{"minimal"} = ~7 essential plots).
#'   See \code{names(REPORT_TEMPLATES)} for available templates.
#'
#' @return VisualizationResult object
#' @export
generate_visualizations <- function(
  validated_data,
  optimization_plan,
  optimized_windows,
  output_dir = "output/",
  create_pdf = TRUE,
  create_individual_plots = TRUE,
  plot_format = "png",
  plot_dpi = 300,
  windows_list = NULL,
  report_template = "full"
) {

  cat("\n==================================================\n")
  cat("   STAGE 4: Visualization & Reporting\n")
  cat("==================================================\n\n")

  viz_start <- Sys.time()

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Validate report template
  if (!report_template %in% names(REPORT_TEMPLATES)) {
    stop(sprintf("Unknown report_template '%s'. Available: %s",
                 report_template,
                 paste(names(REPORT_TEMPLATES), collapse = ", ")))
  }

  cat(sprintf("Step 1: Generating plots (template='%s')...\n", report_template))

  # Select registry entries for this template, then build context with only
  # the prerequisites those entries need (lazy: minimal template skips
  # evaluation_result + windows_list re-computation).
  selected <- filter_by_template(PLOT_REGISTRY, report_template)
  needs <- collect_requirements(selected)

  ctx <- build_visualization_context(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    optimized_windows = optimized_windows,
    windows_list = windows_list,
    needs = needs
  )

  # Generate plots via registry dispatch
  plots <- list()
  for (entry in selected) {
    keys <- expand_plot_keys(entry, ctx)
    if (length(keys) == 0) next
    if (!should_generate(entry, ctx)) next

    for (k in keys) {
      cat(sprintf("  -> %s\n", k))
      result <- tryCatch({
        if (!is.null(entry$expand_over) && entry$expand_over == "strategies") {
          # Recover the strategy name from the expanded key
          strategy <- sub("^app_b_(.+?)_.*$", "\\1", k)
          entry$generate(ctx, strategy)
        } else {
          entry$generate(ctx)
        }
      }, error = function(e) {
        cat(sprintf("     [!] failed: %s\n", e$message))
        NULL
      })
      if (!is.null(result)) plots[[k]] <- result
    }
  }
  cat(sprintf("\nOK All %d plots generated successfully\n\n", length(plots)))

  plot_end <- Sys.time()
  plot_time <- as.numeric(difftime(plot_end, viz_start, units = "secs"))

  # Initialize result structure
  report_files <- list()

  # Step 2: Export individual plots (optional)
  if (create_individual_plots) {
    cat("Step 2: Exporting individual plots...\n")
    individual_files <- export_individual_plots(
      plots, output_dir, plot_format, plot_dpi
    )
    report_files$individual_plots <- individual_files
  } else {
    cat("Step 2: Skipping individual plot export\n")
    report_files$individual_plots <- character()
  }

  # Step 3: Create PDF report (optional)
  if (create_pdf) {
    cat("\nStep 3: Creating PDF report...\n")
    # Build report filename from optimized_windows metadata
    pdf_filename <- if (!is.null(optimized_windows$parameters$window_mode)) {
      format_output_filename(
        type = "report",
        instrument_preset = optimized_windows$metadata$instrument_preset %||%
                            optimization_plan$instrument$preset %||% "custom",
        strategy = NULL,
        window_mode = optimized_windows$parameters$window_mode,
        rt_binning_mode = optimized_windows$parameters$rt_binning_mode %||% "fixed",
        rt_bin_width_min = optimized_windows$parameters$rt_bin_width_min %||% 5,
        ext = "pdf"
      )
    } else {
      "optimization_report.pdf"
    }
    pdf_file <- file.path(output_dir, pdf_filename)
    create_pdf_report(plots, validated_data, optimization_plan, optimized_windows, pdf_file)
    report_files$pdf_report <- pdf_file
  } else {
    cat("\nStep 3: Skipping PDF report creation\n")
    report_files$pdf_report <- NULL
  }

  # NOTE: Method file export has been moved to Stage 3 (export_method_files)
  # Stage 4 now focuses solely on visualization

  # Step 4: Calculate summary statistics
  cat("\nStep 4: Calculating summary statistics...\n")
  summary_stats <- calculate_summary_statistics(validated_data, optimization_plan, optimized_windows)

  viz_end <- Sys.time()
  total_time <- as.numeric(difftime(viz_end, viz_start, units = "secs"))

  # Package results
  result <- structure(
    list(
      plots = plots,

      report_files = report_files,

      summary_statistics = summary_stats,

      metadata = list(
        instrument_type = optimization_plan$instrument$preset,
        mz_strategy = optimized_windows$parameters$mz_strategy,
        window_mode = optimized_windows$parameters$window_mode,
        generation_timestamp = viz_start,
        plot_generation_time = plot_time,
        report_generation_time = total_time - plot_time,
        total_time = total_time
      )
    ),
    class = c("VisualizationResult", "list")
  )

  cat("\n==================================================\n")
  cat(" STAGE 4 COMPLETE (Visualization Only)\n")
  cat("==================================================\n")
  cat(sprintf("OK Generated: %d plots\n", length(plots)))
  if (!is.null(report_files$pdf_report)) {
    cat(sprintf("OK PDF report: %s\n", basename(report_files$pdf_report)))
  }
  cat(sprintf("OK Total time: %.2f seconds\n", total_time))
  cat("\nNote: Method files should be exported using Stage 3's export_method_files()\n")
  cat("\n")

  return(result)
}


# =============================================================================
# Visualization Context Builder
# =============================================================================

#' Build the Visualization Context (Lazy Prerequisites)
#'
#' Assembles a context list passed to each registry entry's
#' \code{generate(ctx)} closure. Computes shared prerequisites
#' (\code{evaluation_result}, \code{windows_list}, \code{baseline_density})
#' only when at least one selected plot needs them.
#'
#' @param validated_data ValidatedData
#' @param optimization_plan OptimizationPlan
#' @param optimized_windows OptimizedWindows
#' @param windows_list Optional pre-computed strategy windows.
#' @param needs Character vector of requirement names collected from registry
#'   entries (see \code{collect_requirements()}).
#' @return List with always-present base fields plus any requested
#'   prerequisites (NULL if computation failed).
#' @keywords internal
build_visualization_context <- function(validated_data, optimization_plan,
                                          optimized_windows,
                                          windows_list = NULL,
                                          needs = character(0)) {

  ctx <- list(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    optimized_windows = optimized_windows,
    active_strategy = optimized_windows$parameters$mz_strategy,
    fz_offset = optimized_windows$parameters$fz_offset %||% 0.25
  )

  # In-silico evaluation (cheap-ish; needed by s2_05, s2_06)
  if ("evaluation_result" %in% needs) {
    cat("  [ctx] running in-silico window evaluation...\n")
    ctx$evaluation_result <- tryCatch(
      evaluate_windows(optimized_windows, validated_data, optimization_plan),
      error = function(e) {
        cat(sprintf("  [ctx] evaluation failed: %s\n", e$message))
        NULL
      }
    )
  }

  # Multi-strategy re-optimization (expensive; needed by s3_*, app_b_*)
  if ("windows_list" %in% needs) {
    if (is.null(windows_list)) {
      cat("  [ctx] computing windows for all 5 strategies (this can take ~30s)...\n")
      ctx$windows_list <- .compute_default_strategy_windows(
        validated_data, optimization_plan, optimized_windows
      )
    } else {
      ctx$windows_list <- windows_list
      cat(sprintf("  [ctx] using pre-computed windows_list (%d strategies)\n",
                  length(windows_list)))
    }
  }

  # Baseline temporal density (only meaningful when evaluation succeeded)
  if ("baseline_density" %in% needs) {
    if (!is.null(ctx$evaluation_result)) {
      ctx$baseline_density <- .compute_baseline_density(
        validated_data, optimization_plan, optimized_windows
      )
    } else {
      ctx$baseline_density <- NULL
    }
  }

  ctx
}


#' Compute Default Strategy Windows for Multi-Strategy Plots
#'
#' Re-runs \code{optimize_windows()} for each strategy in
#' \code{STRATEGY_PREFERRED_ORDER}, keeping the same RT binning and window
#' mode as the user's primary optimization.
#'
#' @keywords internal
.compute_default_strategy_windows <- function(validated_data, optimization_plan,
                                                optimized_windows) {
  strategies <- STRATEGY_PREFERRED_ORDER

  # Use typed strategy_config constructors (avoids the flat-param deprecation
  # warning emitted by optimize_windows()).
  config_constructors <- list(
    greedy   = greedy_config,
    kde      = kde_config,
    quantile = quantile_config,
    coverage = coverage_config,
    outlier  = outlier_config
  )

  windows_list <- list()
  for (strategy in strategies) {
    cat(sprintf("    - %s ...\n", strategy))
    invisible(capture.output(
      windows_list[[strategy]] <- optimize_windows(
        validated_data    = validated_data,
        optimization_plan = optimization_plan,
        strategy_config   = config_constructors[[strategy]](),
        rt_bin_width_min  = optimized_windows$parameters$rt_bin_width_min,
        window_mode       = optimized_windows$parameters$window_mode,
        rt_binning_mode   = optimized_windows$parameters$rt_binning_mode %||% "fixed"
      )
    ))
  }
  windows_list
}


#' Compute Baseline Temporal Density (Naive Windows)
#'
#' Builds naive fixed-width windows from current acquisition parameters and
#' computes the sweepline co-elution density. Used by
#' \code{plot_temporal_density()} for before/after comparison.
#'
#' @keywords internal
.compute_baseline_density <- function(validated_data, optimization_plan,
                                        optimized_windows) {
  tryCatch({
    precursors <- validated_data$data
    windows <- optimized_windows$windows
    n_bins <- length(unique(windows$rt_segment_id))
    current_ct <- optimization_plan$diagnosis$current_cycle_time_sec
    ms2_time <- optimization_plan$instrument$ms2_scan_time_ms / 1000
    baseline_n <- if (!is.na(current_ct) && !is.na(ms2_time) && ms2_time > 0) {
      as.integer(floor(current_ct / ms2_time))
    } else {
      as.integer(nrow(windows) / n_bins)
    }

    rt_bins_df <- unique(windows[, c("rt_start", "rt_end", "rt_segment_id")])
    naive_list <- lapply(seq_len(nrow(rt_bins_df)), function(i) {
      bin_prec <- precursors[precursors$RT.Apex >= rt_bins_df$rt_start[i] &
                              precursors$RT.Apex <= rt_bins_df$rt_end[i], ]
      if (nrow(bin_prec) < 2) return(NULL)
      mz_rng <- range(bin_prec$Precursor.Mz, na.rm = TRUE)
      n_win <- min(baseline_n, 500L)
      if (n_win < 1) return(NULL)
      bw <- generate_fixed_windows_internal(
        mz_min = mz_rng[1], mz_max = mz_rng[2],
        n_windows = n_win, min_width_da = 1,
        max_width_da = 500, fz_offset = 0
      )
      bw$rt_start <- rt_bins_df$rt_start[i]
      bw$rt_end   <- rt_bins_df$rt_end[i]
      bw
    })
    naive_windows <- do.call(rbind, naive_list)
    if (is.null(naive_windows) || nrow(naive_windows) < 1) stop("no baseline windows")

    td <- calculate_precursor_temporal_density(
      precursor_mz    = precursors$Precursor.Mz,
      precursor_rt    = precursors$RT.Apex,
      precursor_fwhm  = precursors$FWHM,
      window_mz_start = naive_windows$mz_start,
      window_mz_end   = naive_windows$mz_end,
      window_rt_start = naive_windows$rt_start,
      window_rt_end   = naive_windows$rt_end
    )
    list(
      median = median(td$density_max, na.rm = TRUE),
      mean   = mean(td$density_max, na.rm = TRUE),
      max    = max(td$density_max, na.rm = TRUE),
      n_per_bin = baseline_n
    )
  }, error = function(e) NULL)
}


# =============================================================================
# Summary Statistics
# =============================================================================

#' Calculate Summary Statistics
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return List of summary statistics
#' @keywords internal
calculate_summary_statistics <- function(validated_data, optimization_plan, optimized_windows) {

  windows <- optimized_windows$windows
  window_stats <- optimized_windows$statistics

  list(
    optimization_metrics = list(
      total_windows = nrow(windows),
      window_count_per_rt = optimization_plan$window_count_per_bin,
      mean_window_width_da = mean(windows$window_width),
      precursor_coverage_pct = window_stats$coverage_percentage,
      mean_precursors_per_window = window_stats$mean_precursors_per_window,
      cv_precursors = window_stats$cv_precursors
    ),

    performance_metrics = list(
      cycle_time_sec = optimization_plan$actual_cycle_time_sec,
      scan_rate_hz = 1 / optimization_plan$actual_cycle_time_sec,
      target_dppp = optimization_plan$parameters$target_dppp,
      current_dppp_satisfaction_pct = optimization_plan$diagnosis$current_satisfaction_ratio * 100,
      required_cycle_time_sec = optimization_plan$required_cycle_time_sec
    ),

    instrument_config = list(
      instrument_type = optimization_plan$instrument$preset,
      mz_strategy = optimized_windows$parameters$mz_strategy,
      window_mode = optimized_windows$parameters$window_mode,
      n_precursors = validated_data$metadata$n_precursors,
      rt_range = validated_data$metadata$rt_range,
      mz_range = validated_data$metadata$mz_range
    )
  )
}

