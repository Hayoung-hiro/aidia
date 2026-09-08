# Settings shared across strategies. Keep these in OptimizedWindows$parameters
# alongside all strategy configurations, rather than reconstructing a run from
# presentation controls or a partial set of defaults.
.comparison_parameter_names <- c(
  "rt_bin_width_min", "window_mode", "mz_range_min", "mz_range_max",
  "min_width_da", "max_width_da", "overlap_percentage", "fz_offset",
  "rt_binning_mode", "cpd_min_bin_width", "cpd_max_bin_width",
  "cpd_min_precursors_per_bin", "cpd_significance_level",
  "edge_void_buffer_min", "edge_wash_min_precursors", "width_grid_step"
)

.validate_comparison_strategy_configs <- function(configs) {
  if (!is.list(configs) || is.null(names(configs)) ||
      anyNA(names(configs)) || anyDuplicated(names(configs)) ||
      !all(names(configs) %in% STRATEGY_PREFERRED_ORDER)) {
    stop("comparison_strategy_configs must be a named list of supported strategies.",
         call. = FALSE)
  }
  for (name in names(configs)) {
    if (!inherits(configs[[name]], "strategy_config") ||
        !identical(configs[[name]]$strategy, name)) {
      stop("Each comparison_strategy_configs entry must match its strategy name.",
           call. = FALSE)
    }
  }
  invisible(configs)
}

.resolve_comparison_strategy_configs <- function(selected, configs) {
  defaults <- list(greedy = greedy_config(), kde = kde_config(),
                   quantile = quantile_config(), coverage = coverage_config(),
                   outlier = outlier_config())
  if (!is.null(configs)) {
    .validate_comparison_strategy_configs(configs)
    supplied_selected <- configs[[selected$strategy]]
    if (!is.null(supplied_selected) && !identical(supplied_selected, selected)) {
      stop("The selected comparison configuration must match strategy_config.",
           call. = FALSE)
    }
    defaults[names(configs)] <- configs
  }
  defaults[[selected$strategy]] <- selected
  defaults
}

.validate_comparison_parameters <- function(parameters) {
  required <- c(.comparison_parameter_names, "n_windows_per_bin",
                "mz_strategy", "strategy_configs")
  missing <- setdiff(required, names(parameters))
  if (!is.list(parameters) || length(missing) > 0L) {
    stop("Completed optimization settings are incomplete (missing: ",
         paste(missing, collapse = ", "),
         "). Run optimize_windows() again before comparing strategies.",
         call. = FALSE)
  }
  .validate_comparison_strategy_configs(parameters$strategy_configs)
  if (!setequal(names(parameters$strategy_configs), STRATEGY_PREFERRED_ORDER) ||
      length(parameters$mz_strategy) != 1L || is.na(parameters$mz_strategy) ||
      !parameters$mz_strategy %in% names(parameters$strategy_configs)) {
    stop("Completed settings must include all five strategy configurations.",
         call. = FALSE)
  }
  validate_positive_integer(parameters$n_windows_per_bin,
                            param_name = "n_windows_per_bin")
  invisible(parameters)
}

#' Prepare a Strategy Comparison from a Completed Optimization
#'
#' Reuses the selected result and computes other strategies with its saved
#' common settings, resolved window count, and all strategy-specific settings
#' saved when optimization ran. Live Shiny controls are never read.
#'
#' Older results without complete saved settings must be optimized again;
#' missing settings are never silently replaced with defaults.
#'
#' @param optimized_windows Completed OptimizedWindows result to reuse.
#' @param validated_data ValidatedData used for the completed optimization.
#' @param optimization_plan OptimizationPlan used for the completed optimization.
#' @param strategies Character vector of strategies to include, in output order.
#' @param notify_fn Optional function taking a strategy name and its one-based
#'   position in \code{strategies}; called before each new optimization.
#'
#' @return Named list of OptimizedWindows results in the requested order.
#' @export
build_strategy_comparison <- function(optimized_windows, validated_data,
                                      optimization_plan,
                                      strategies = STRATEGY_PREFERRED_ORDER,
                                      notify_fn = NULL) {
  validate_OptimizedWindows(optimized_windows)
  validate_input_type(validated_data, "ValidatedData", "validated_data")
  validate_input_type(optimization_plan, "OptimizationPlan", "optimization_plan")
  params <- optimized_windows$parameters
  .validate_comparison_parameters(params)

  if (!is.character(strategies) || length(strategies) == 0L ||
      anyNA(strategies) || anyDuplicated(strategies) ||
      !all(strategies %in% STRATEGY_PREFERRED_ORDER)) {
    stop("strategies must contain unique supported strategy names.", call. = FALSE)
  }
  if (!is.null(notify_fn) && !is.function(notify_fn)) {
    stop("notify_fn must be NULL or a function.", call. = FALSE)
  }
  common <- params[.comparison_parameter_names]
  common$n_windows_override <- params$n_windows_per_bin
  results <- setNames(vector("list", length(strategies)), strategies)
  for (i in seq_along(strategies)) {
    strategy <- strategies[[i]]
    if (identical(strategy, params$mz_strategy)) {
      results[[i]] <- optimized_windows
      next
    }
    configs <- params$strategy_configs
    config <- configs[[strategy]]
    # Greedy resolves its count from its config before the general override.
    if (inherits(config, "greedy_config")) {
      config$auto_windows <- FALSE
      config$n_windows_override <- params$n_windows_per_bin
    }
    configs[[strategy]] <- config
    if (!is.null(notify_fn)) notify_fn(strategy, i)
    results[[i]] <- do.call(optimize_windows, c(list(
      validated_data = validated_data, optimization_plan = optimization_plan,
      strategy_config = config, comparison_strategy_configs = configs
    ), common))
  }
  results
}
