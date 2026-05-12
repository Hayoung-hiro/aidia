# plot_registry.R - Visualization Plot Registry (v0.4.1+)
#
# Purpose: Centralize plot metadata so generate_visualizations() can:
#   - select plots by report template (full, minimal, ...)
#   - skip conditional plots when prerequisites aren't met
#   - expand multi-strategy templates dynamically based on windows_list
#   - lazy-compute shared prerequisites (evaluation_result, windows_list,
#     baseline_density) only when at least one selected plot needs them
#
# Architecture:
#   PLOT_REGISTRY      - list of entries, one per plot or expansion template
#   REPORT_TEMPLATES   - metadata for each template name
#   filter_by_template - select entries matching a template name
#   expand_plot_keys   - turn an expand_over entry into concrete keys
#   build_visualization_context - compute prerequisites lazily
#
# Each PLOT_REGISTRY entry has the shape:
#   list(
#     key          = "s1_02_fwhm_distribution",     # concrete plot key, OR
#     key_template = "app_b_{strategy}_mz_excluded",# template with placeholder
#     generate     = function(ctx, ...) ggplot,     # closure that builds the plot
#     templates    = c("full", "minimal"),          # which templates include this
#     when         = function(ctx) <logical>,       # condition (NULL = always)
#     requires     = c("evaluation_result", ...),   # ctx fields that must be built
#     expand_over  = "strategies"                   # NULL or "strategies"
#   )
#
# See docs/adr/0003-plot-registry-report-template.md for rationale.


# =============================================================================
# Report Templates
# =============================================================================

#' Report Templates for Visualization
#'
#' Named list of report templates. Each template selects a subset of plots
#' from \code{PLOT_REGISTRY}. Use \code{names(REPORT_TEMPLATES)} to list
#' available templates.
#'
#' @keywords internal
REPORT_TEMPLATES <- list(
  full = list(
    description = "All plots — current default behavior (~44 plots with 5 strategies)"
  ),
  minimal = list(
    description = "Essential plots for quick preview (~7 plots)"
  )
)


# =============================================================================
# Plot Registry
# =============================================================================

#' Plot Registry for AIDIA Visualizations
#'
#' List of plot entries. Each entry describes how one plot is generated,
#' which templates include it, any prerequisites, and conditional logic.
#'
#' @keywords internal
PLOT_REGISTRY <- list(

  # ---------------------------------------------------------------------------
  # Section 1: Foundational Input (s1_*)
  # ---------------------------------------------------------------------------

  list(
    key = "s1_01_density_heatmap",
    generate = function(ctx) plot_rt_mz_density_heatmap(ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "s1_02_fwhm_distribution",
    generate = function(ctx) plot_fwhm_distribution(ctx$validated_data,
                                                     ctx$optimization_plan),
    templates = c("full")
  ),
  list(
    key = "s1_03_mz_density",
    generate = function(ctx) plot_mz_normalized_density(ctx$optimized_windows,
                                                         ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "s1_04_dppp_diagnosis",
    generate = function(ctx) plot_dppp_diagnosis_table(ctx$optimization_plan,
                                                        ctx$validated_data),
    templates = c("full", "minimal")
  ),
  list(
    key = "s1_05_satisfaction_curve",
    generate = function(ctx) plot_satisfaction_curve(ctx$optimization_plan,
                                                      ctx$validated_data),
    templates = c("full", "minimal")
  ),
  list(
    key = "s1_06_dppp_comparison",
    generate = function(ctx) plot_dppp_comparison(ctx$optimization_plan,
                                                    ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "s1_07_dppp_curve",
    generate = function(ctx) plot_dppp_comparison_enhanced(ctx$optimization_plan,
                                                             ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "s1_08_dppp_satisfaction",
    generate = function(ctx) plot_dppp_satisfaction_combined(ctx$optimization_plan,
                                                               ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "s1_09_rt_histogram",
    generate = function(ctx) plot_rt_histogram(ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "s1_10_rt_histogram_5min",
    generate = function(ctx) plot_rt_histogram_binned(ctx$validated_data,
                                                       bin_width_min = 5),
    templates = c("full")
  ),
  list(
    key = "s1_11_dppp_distribution",
    generate = function(ctx) plot_dppp_distribution(ctx$optimization_plan,
                                                      ctx$validated_data),
    templates = c("full")
  ),

  # ---------------------------------------------------------------------------
  # Section 2: Optimization Outcome (s2_*)
  # ---------------------------------------------------------------------------

  list(
    key = "s2_01_impact_summary",
    generate = function(ctx) plot_optimization_impact(ctx$optimization_plan,
                                                        ctx$optimized_windows,
                                                        ctx$validated_data),
    templates = c("full", "minimal")
  ),
  list(
    key = "s2_02_window_layout",
    generate = function(ctx) plot_window_width_distribution(ctx$optimized_windows,
                                                              ctx$validated_data),
    templates = c("full", "minimal")
  ),
  list(
    key = "s2_03_window_index",
    generate = function(ctx) plot_cumulative_window_count(ctx$optimized_windows,
                                                            ctx$validated_data,
                                                            max_segments_to_show = 6),
    templates = c("full")
  ),
  list(
    key = "s2_04_load_balance",
    generate = function(ctx) plot_precursor_load_balance(ctx$optimized_windows,
                                                           ctx$validated_data,
                                                           ctx$optimization_plan),
    templates = c("full", "minimal")
  ),
  list(
    key = "s2_05_precursor_distribution",
    generate = function(ctx) plot_precursors_per_window(ctx$optimized_windows,
                                                          ctx$validated_data,
                                                          ctx$optimization_plan,
                                                          evaluation_result = ctx$evaluation_result),
    requires = "evaluation_result",
    templates = c("full")
  ),
  list(
    key = "s2_06_temporal_density",
    generate = function(ctx) plot_temporal_density(ctx$evaluation_result,
                                                     baseline_density = ctx$baseline_density),
    requires = c("evaluation_result", "baseline_density"),
    when = function(ctx) !is.null(ctx$evaluation_result),
    templates = c("full")
  ),
  list(
    key = "s2_07_rt_bin_quality",
    generate = function(ctx) plot_rt_bin_quality_heatmap(ctx$optimized_windows,
                                                           ctx$validated_data,
                                                           ctx$optimization_plan),
    templates = c("full")
  ),
  list(
    key = "s2_tiling_coverage",
    generate = function(ctx) plot_tiling_coverage_map(ctx$optimized_windows,
                                                       ctx$validated_data),
    when = function(ctx) identical(ctx$optimized_windows$parameters$window_mode, "staggered"),
    templates = c("full")
  ),

  # ---------------------------------------------------------------------------
  # Section 3: Strategy Comparison (s3_*)
  # ---------------------------------------------------------------------------

  list(
    key = "s3_01_strategy_table",
    generate = function(ctx) plot_strategy_comparison_table(ctx$windows_list,
                                                              active_strategy = ctx$active_strategy),
    requires = "windows_list",
    when = function(ctx) !is.null(ctx$windows_list),
    templates = c("full", "minimal")
  ),
  list(
    key = "s3_02_strategy_ridge",
    generate = function(ctx) plot_strategy_width_ridge(ctx$windows_list,
                                                         ctx$validated_data,
                                                         active_strategy = ctx$active_strategy),
    requires = "windows_list",
    when = function(ctx) !is.null(ctx$windows_list),
    templates = c("full", "minimal")
  ),
  list(
    key = "s3_03_heatmap_boundary",
    generate = function(ctx) plot_density_with_mz_ranges_grid(ctx$windows_list,
                                                                ctx$validated_data),
    requires = "windows_list",
    when = function(ctx) !is.null(ctx$windows_list),
    templates = c("full")
  ),
  list(
    key = "s3_04_width_profile",
    generate = function(ctx) plot_strategy_width_profile(ctx$windows_list,
                                                           ctx$validated_data,
                                                           active_strategy = ctx$active_strategy),
    requires = "windows_list",
    when = function(ctx) !is.null(ctx$windows_list),
    templates = c("full")
  ),

  # ---------------------------------------------------------------------------
  # Appendix A: Per-Precursor Analysis (app_a_*)
  # ---------------------------------------------------------------------------

  list(
    key = "app_a_alignment_density",
    generate = function(ctx) plot_alignment_density(ctx$optimized_windows,
                                                      ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "app_a_charge_state",
    generate = function(ctx) plot_charge_mz_distribution(ctx$optimized_windows,
                                                           ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "app_a_edge_proximity",
    generate = function(ctx) plot_edge_proximity(ctx$optimized_windows,
                                                   ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "app_a_edge_spatial",
    generate = function(ctx) plot_edge_proximity_spatial(ctx$optimized_windows,
                                                           ctx$validated_data),
    templates = c("full")
  ),
  list(
    key = "app_a_fz_validation",
    generate = function(ctx) plot_fz_validation(ctx$validated_data,
                                                  fz_offset = ctx$fz_offset),
    templates = c("full")
  ),
  list(
    key = "app_a_fz_zoom",
    generate = function(ctx) plot_fz_zoom(ctx$optimized_windows,
                                            ctx$validated_data,
                                            fz_offset = ctx$fz_offset),
    templates = c("full")
  ),

  # ---------------------------------------------------------------------------
  # Appendix B: Per-Strategy Details (app_b_*) — multi-strategy expansion
  # ---------------------------------------------------------------------------

  list(
    key_template = "app_b_{strategy}_mz_excluded",
    generate = function(ctx, strategy) {
      plot_mz_distribution_with_exclusions(
        ctx$windows_list[[strategy]], ctx$validated_data, max_bins_to_show = 6
      )
    },
    requires = "windows_list",
    expand_over = "strategies",
    templates = c("full")
  ),
  list(
    key_template = "app_b_{strategy}_window_layout",
    generate = function(ctx, strategy) {
      plot_window_width_distribution(ctx$windows_list[[strategy]],
                                      ctx$validated_data)
    },
    requires = "windows_list",
    expand_over = "strategies",
    templates = c("full")
  ),
  list(
    key_template = "app_b_{strategy}_window_index",
    generate = function(ctx, strategy) {
      plot_cumulative_window_count(ctx$windows_list[[strategy]],
                                    ctx$validated_data,
                                    max_segments_to_show = 6)
    },
    requires = "windows_list",
    expand_over = "strategies",
    templates = c("full")
  ),
  list(
    key = "app_b_width_all_strategies",
    generate = function(ctx) plot_mz_width_comparison_all_strategies(ctx$windows_list,
                                                                       ctx$validated_data),
    requires = "windows_list",
    when = function(ctx) !is.null(ctx$windows_list),
    templates = c("full")
  ),

  # ---------------------------------------------------------------------------
  # Appendix D: Adaptive RT Binning Validation (app_d_*)
  # ---------------------------------------------------------------------------

  list(
    key = "app_d_changepoint",
    generate = function(ctx) plot_rt_changepoint_validation(ctx$validated_data,
                                                              ctx$optimized_windows),
    when = function(ctx) identical(ctx$optimized_windows$rt_binning$rt_binning_mode %||% "fixed",
                                    "adaptive"),
    templates = c("full")
  ),
  list(
    key = "app_d_ks_trace",
    generate = function(ctx) plot_ks_statistic_trace(ctx$optimized_windows),
    when = function(ctx) identical(ctx$optimized_windows$rt_binning$rt_binning_mode %||% "fixed",
                                    "adaptive"),
    templates = c("full")
  )
)


# =============================================================================
# Helpers
# =============================================================================

#' Filter Registry Entries by Template
#'
#' @param registry List of PLOT_REGISTRY entries.
#' @param template Character, template name (e.g., \code{"full"}, \code{"minimal"}).
#' @return List of entries that include the template in their \code{templates} field.
#' @keywords internal
filter_by_template <- function(registry, template) {
  Filter(function(e) template %in% e$templates, registry)
}


#' Expand a Registry Entry to Concrete Plot Keys
#'
#' If \code{entry$expand_over} is set, expands the entry into one concrete
#' key per element of \code{ctx[[expand_over]]}. Otherwise returns the
#' single concrete key from \code{entry$key}.
#'
#' @param entry A PLOT_REGISTRY entry.
#' @param ctx Visualization context.
#' @return Character vector of concrete plot keys.
#' @keywords internal
expand_plot_keys <- function(entry, ctx) {
  # Use [[ ]] to avoid R's $-partial-matching (key vs key_template).
  if (is.null(entry[["expand_over"]])) return(entry[["key"]])

  if (entry[["expand_over"]] == "strategies") {
    if (is.null(ctx$windows_list)) return(character(0))
    strategies <- names(ctx$windows_list)
    template_str <- entry[["key_template"]]
    if (is.null(template_str)) {
      stop("entry with expand_over='strategies' must define key_template")
    }
    return(vapply(strategies,
                   function(s) sub("\\{strategy\\}", s, template_str),
                   character(1)))
  }

  stop(sprintf("Unknown expand_over value: '%s'", entry[["expand_over"]]))
}


#' Should This Entry Be Generated?
#'
#' Evaluates the entry's \code{when} predicate. Note that \code{requires}
#' is NOT used here as a null-block: it only signals which prerequisites the
#' context-builder should compute. To express a hard requirement, set
#' \code{when = function(ctx) !is.null(ctx$some_field)}.
#'
#' @param entry A PLOT_REGISTRY entry.
#' @param ctx Visualization context.
#' @return Logical TRUE if the entry should generate plots.
#' @keywords internal
should_generate <- function(entry, ctx) {
  if (!is.null(entry$when)) {
    cond <- tryCatch(entry$when(ctx), error = function(e) FALSE)
    if (!isTRUE(cond)) return(FALSE)
  }
  TRUE
}


#' Determine Which Prerequisites Are Needed
#'
#' Walks selected registry entries and collects the union of their
#' \code{requires} fields.
#'
#' @param entries List of PLOT_REGISTRY entries (after template filtering).
#' @return Character vector of unique requirement names.
#' @keywords internal
collect_requirements <- function(entries) {
  unique(unlist(lapply(entries, function(e) e$requires)))
}
