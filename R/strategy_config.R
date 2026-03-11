# strategy_config.R - Strategy Configuration Objects
#
# Purpose: Constructor functions for m/z optimization strategy configs.
# Each strategy bundles its parameters into a validated object, replacing
# the flat 15+ strategy-specific params in optimize_windows().
#
# Usage:
#   optimize_windows(data, plan, strategy_config = greedy_config())
#   optimize_windows(data, plan, strategy_config = kde_config(density_threshold = 0.05))


# =============================================================================
# Strategy Config Constructors
# =============================================================================

#' Create Greedy Strategy Configuration
#'
#' MacCoss Lab sliding window algorithm. Recommended for general-purpose use.
#'
#' @param auto_windows Logical, auto-detect window count (default: TRUE)
#' @param n_windows Integer or NULL, manual window count override (used when auto_windows = FALSE)
#' @param mz_step Numeric, sliding window step size in Da (default: 0.5)
#' @param apply_smoothing Logical, apply boundary smoothing (default: TRUE)
#' @param smoothing_window Integer, SG window size (default: 7, must be odd >= 3). Only used when smoothing_method = "sg".
#' @param polynomial_order Integer, SG polynomial order (default: 3). Only used when smoothing_method = "sg".
#' @param smoothing_method Character, "whittaker" (default) or "sg" (Savitzky-Golay)
#' @param whittaker_lambda Numeric, Whittaker smoothing parameter (default: 10). Only used when smoothing_method = "whittaker".
#'
#' @return A strategy_config object for the greedy strategy
#' @export
#'
#' @examples
#' config <- greedy_config()
#' config <- greedy_config(auto_windows = FALSE, n_windows = 40, mz_step = 1.0)
#' config <- greedy_config(smoothing_method = "sg")  # use legacy SG smoother
greedy_config <- function(auto_windows = TRUE,
                          n_windows = NULL,
                          mz_step = 0.5,
                          apply_smoothing = TRUE,
                          smoothing_window = 7,
                          polynomial_order = 3,
                          smoothing_method = "whittaker",
                          whittaker_lambda = 10) {
  structure(
    list(
      strategy = "greedy",
      auto_windows = auto_windows,
      n_windows_override = if (auto_windows) NULL else n_windows,
      mz_step = mz_step,
      greedy_apply_smoothing = apply_smoothing,
      smoothing_window = smoothing_window,
      polynomial_order = polynomial_order,
      smoothing_method = smoothing_method,
      whittaker_lambda = whittaker_lambda
    ),
    class = c("strategy_config", "list")
  )
}

#' Create Quantile Strategy Configuration
#'
#' Uses percentile-based m/z range (P5-P95 by default). Fast and robust.
#'
#' @param lower Numeric, lower quantile 0-1 (default: 0.05)
#' @param upper Numeric, upper quantile 0-1 (default: 0.95)
#' @param apply_smoothing Logical, apply boundary smoothing (default: TRUE)
#' @param smoothing_window Integer, SG window size (default: 7). Only used when smoothing_method = "sg".
#' @param polynomial_order Integer, SG polynomial order (default: 3). Only used when smoothing_method = "sg".
#' @param smoothing_method Character, "whittaker" (default) or "sg" (Savitzky-Golay)
#' @param whittaker_lambda Numeric, Whittaker smoothing parameter (default: 10). Only used when smoothing_method = "whittaker".
#'
#' @return A strategy_config object for the quantile strategy
#' @export
#'
#' @examples
#' config <- quantile_config()
#' config <- quantile_config(lower = 0.10, upper = 0.90)
quantile_config <- function(lower = 0.05,
                            upper = 0.95,
                            apply_smoothing = TRUE,
                            smoothing_window = 7,
                            polynomial_order = 3,
                            smoothing_method = "whittaker",
                            whittaker_lambda = 10) {
  validate_numeric_range(lower, min = 0, max = 1, param_name = "lower")
  validate_numeric_range(upper, min = 0, max = 1, param_name = "upper")
  if (lower >= upper) stop("lower must be less than upper")

  structure(
    list(
      strategy = "quantile",
      quantile_lower = lower,
      quantile_upper = upper,
      quantile_apply_smoothing = apply_smoothing,
      smoothing_window = smoothing_window,
      polynomial_order = polynomial_order,
      smoothing_method = smoothing_method,
      whittaker_lambda = whittaker_lambda
    ),
    class = c("strategy_config", "list")
  )
}

#' Create Coverage Strategy Configuration
#'
#' Finds minimum m/z range to cover target percentage of precursors.
#'
#' @param target Numeric, target coverage 0-1 (default: 0.95)
#' @param mode Character, "narrowest" or "centered" (default: "narrowest")
#'
#' @return A strategy_config object for the coverage strategy
#' @export
#'
#' @examples
#' config <- coverage_config()
#' config <- coverage_config(target = 0.98, mode = "centered")
coverage_config <- function(target = 0.95,
                            mode = "narrowest") {
  validate_numeric_range(target, min = 0, max = 1, param_name = "target")
  if (!mode %in% c("narrowest", "centered")) {
    stop("mode must be 'narrowest' or 'centered'")
  }

  structure(
    list(
      strategy = "coverage",
      target_coverage = target,
      coverage_mode = mode
    ),
    class = c("strategy_config", "list")
  )
}

#' Create Outlier Strategy Configuration
#'
#' Uses mean +/- N*SD to define m/z range, removing outliers.
#'
#' @param threshold Numeric, SD multiplier (default: 3.0)
#' @param apply_smoothing Logical, apply boundary smoothing (default: TRUE)
#' @param smoothing_window Integer, SG window size (default: 7). Only used when smoothing_method = "sg".
#' @param polynomial_order Integer, SG polynomial order (default: 3). Only used when smoothing_method = "sg".
#' @param smoothing_method Character, "whittaker" (default) or "sg" (Savitzky-Golay)
#' @param whittaker_lambda Numeric, Whittaker smoothing parameter (default: 10). Only used when smoothing_method = "whittaker".
#'
#' @return A strategy_config object for the outlier strategy
#' @export
#'
#' @examples
#' config <- outlier_config()
#' config <- outlier_config(threshold = 2.5, apply_smoothing = TRUE)
#' config <- outlier_config(smoothing_method = "sg")  # use legacy SG smoother
outlier_config <- function(threshold = 3.0,
                           apply_smoothing = TRUE,
                           smoothing_window = 7,
                           polynomial_order = 3,
                           smoothing_method = "whittaker",
                           whittaker_lambda = 10) {
  validate_numeric_range(threshold, min = 0, param_name = "threshold")

  structure(
    list(
      strategy = "outlier",
      outlier_threshold = threshold,
      outlier_apply_smoothing = apply_smoothing,
      smoothing_window = smoothing_window,
      polynomial_order = polynomial_order,
      smoothing_method = smoothing_method,
      whittaker_lambda = whittaker_lambda
    ),
    class = c("strategy_config", "list")
  )
}

#' Create KDE Strategy Configuration
#'
#' Kernel Density Estimation to find density peaks and expand coverage.
#'
#' @param density_threshold Numeric, density threshold 0-1 (default: 0.1)
#' @param min_coverage Numeric, minimum coverage target 0-1 (default: 0.8)
#'
#' @return A strategy_config object for the KDE strategy
#' @export
#'
#' @examples
#' config <- kde_config()
#' config <- kde_config(density_threshold = 0.05, min_coverage = 0.9)
kde_config <- function(density_threshold = 0.1,
                       min_coverage = 0.8) {
  validate_numeric_range(density_threshold, min = 0, max = 1, param_name = "density_threshold")
  validate_numeric_range(min_coverage, min = 0, max = 1, param_name = "min_coverage")

  structure(
    list(
      strategy = "kde",
      kde_density_threshold = density_threshold,
      kde_min_coverage = min_coverage
    ),
    class = c("strategy_config", "list")
  )
}


# =============================================================================
# Internal Helpers
# =============================================================================

#' Flatten Strategy Config to Parameter List
#'
#' Converts a strategy_config object to a flat list of parameters
#' compatible with optimize_mz_ranges_internal().
#'
#' @param config strategy_config object
#' @return Named list of strategy parameters
#' @keywords internal
flatten_strategy_config <- function(config) {
  if (!inherits(config, "strategy_config")) {
    stop("config must be a strategy_config object")
  }
  # Return all elements except the class attribute
  as.list(config)
}

#' Build Strategy Config from Flat Parameters
#'
#' Creates a strategy_config from the legacy flat parameter style.
#' Used internally for backward compatibility.
#'
#' @param mz_strategy Character, strategy name
#' @param quantile_lower Lower quantile for quantile strategy (default 0.05)
#' @param quantile_upper Upper quantile for quantile strategy (default 0.95)
#' @param quantile_apply_smoothing Logical, apply smoothing for quantile
#' @param target_coverage Target coverage ratio for coverage strategy
#' @param coverage_mode Coverage mode: "narrowest" or "centered"
#' @param outlier_threshold Sigma threshold for outlier strategy
#' @param outlier_apply_smoothing Logical, apply smoothing for outlier
#' @param mz_step Step size in Da for greedy strategy
#' @param n_windows_override Manual window count override for greedy
#' @param greedy_apply_smoothing Logical, apply smoothing for greedy
#' @param kde_density_threshold Density threshold for KDE strategy
#' @param kde_min_coverage Minimum coverage for KDE strategy
#' @param smoothing_window Savitzky-Golay window size (legacy, used when smoothing_method="sg")
#' @param polynomial_order Savitzky-Golay polynomial order (legacy)
#' @param smoothing_method Smoothing method: "whittaker" (default) or "sg"
#' @param whittaker_lambda Lambda parameter for Whittaker-Henderson smoother
#' @return strategy_config object
#' @keywords internal
build_strategy_config <- function(mz_strategy,
                                  quantile_lower = 0.05,
                                  quantile_upper = 0.95,
                                  quantile_apply_smoothing = TRUE,
                                  target_coverage = 0.95,
                                  coverage_mode = "narrowest",
                                  outlier_threshold = 3.0,
                                  outlier_apply_smoothing = TRUE,
                                  mz_step = 0.5,
                                  n_windows_override = NULL,
                                  greedy_apply_smoothing = TRUE,
                                  kde_density_threshold = 0.1,
                                  kde_min_coverage = 0.8,
                                  smoothing_window = 7,
                                  polynomial_order = 3,
                                  smoothing_method = "whittaker",
                                  whittaker_lambda = 10) {
  switch(mz_strategy,
    greedy = greedy_config(
      auto_windows = is.null(n_windows_override),
      n_windows = n_windows_override,
      mz_step = mz_step,
      apply_smoothing = greedy_apply_smoothing,
      smoothing_window = smoothing_window,
      polynomial_order = polynomial_order,
      smoothing_method = smoothing_method,
      whittaker_lambda = whittaker_lambda
    ),
    quantile = quantile_config(
      lower = quantile_lower,
      upper = quantile_upper,
      apply_smoothing = quantile_apply_smoothing,
      smoothing_window = smoothing_window,
      polynomial_order = polynomial_order,
      smoothing_method = smoothing_method,
      whittaker_lambda = whittaker_lambda
    ),
    coverage = coverage_config(
      target = target_coverage,
      mode = coverage_mode
    ),
    outlier = outlier_config(
      threshold = outlier_threshold,
      apply_smoothing = outlier_apply_smoothing,
      smoothing_window = smoothing_window,
      polynomial_order = polynomial_order,
      smoothing_method = smoothing_method,
      whittaker_lambda = whittaker_lambda
    ),
    kde = kde_config(
      density_threshold = kde_density_threshold,
      min_coverage = kde_min_coverage
    ),
    stop(sprintf("Unknown strategy: %s", mz_strategy))
  )
}

#' Print Strategy Config
#'
#' @param x strategy_config object
#' @param ... Ignored
#' @export
print.strategy_config <- function(x, ...) {
  cat(sprintf("AIDIA Strategy Config: %s\n", x$strategy))
  params <- x[names(x) != "strategy"]
  for (nm in names(params)) {
    val <- params[[nm]]
    if (!is.null(val)) {
      cat(sprintf("  %s: %s\n", nm, val))
    }
  }
  invisible(x)
}
