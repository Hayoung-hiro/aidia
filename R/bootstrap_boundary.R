# bootstrap_boundary.R - Bootstrap Confidence Intervals for m/z Boundaries
#
# Purpose: Estimate boundary uncertainty via stratified bootstrap resampling.
#   For each iteration, precursors are resampled with replacement within each
#   RT bin, and m/z boundaries are recalculated using the same strategy.
#   Percentile-based CIs quantify how sensitive boundaries are to sample composition.
#
# Reference: Efron & Tibshirani (1993), "An Introduction to the Bootstrap"
#
# Dependencies: R/mz_optimization.R, R/rt_binning.R


# =============================================================================
# Main Bootstrap Function
# =============================================================================

#' Bootstrap Confidence Intervals for m/z Boundaries
#'
#' Estimates boundary uncertainty by resampling precursors within each RT bin
#' and recalculating m/z boundaries. Returns percentile-based confidence
#' intervals for both mz_min and mz_max across RT segments.
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param strategy_config A strategy_config object (e.g., greedy_config())
#' @param n_boot Integer, number of bootstrap iterations (default: 200)
#' @param ci_level Numeric, confidence level 0-1 (default: 0.95 for 95% CI)
#' @param rt_bin_width_min Numeric, RT bin width in minutes (default: 5)
#' @param seed Integer or NULL, random seed for reproducibility (default: 42)
#' @param rt_bin_width_min_override Numeric or NULL, override rt_bin_width_min (default: NULL)
#' @param verbose Logical, print progress (default: TRUE)
#'
#' @return A list with class "boundary_ci" containing:
#'   \item{ci_data}{Data frame with per-RT-bin CI bounds}
#'   \item{boot_matrix_min}{Matrix of bootstrap mz_min values (n_boot x n_bins)}
#'   \item{boot_matrix_max}{Matrix of bootstrap mz_max values (n_boot x n_bins)}
#'   \item{observed}{Data frame of observed (non-bootstrap) boundaries}
#'   \item{params}{List of parameters used}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' ci <- bootstrap_boundary_ci(
#'   validated_data, plan,
#'   strategy_config = greedy_config(),
#'   n_boot = 200
#' )
#' plot_boundary_ci(ci, validated_data)
#' }
bootstrap_boundary_ci <- function(validated_data,
                                  optimization_plan,
                                  strategy_config = greedy_config(),
                                  n_boot = 200,
                                  ci_level = 0.95,
                                  rt_bin_width_min = 5,
                                  rt_bin_width_min_override = NULL,
                                  seed = 42,
                                  verbose = TRUE) {

  if (!inherits(validated_data, "ValidatedData")) {
    stop("validated_data must be a ValidatedData object from Stage 1")
  }
  if (!inherits(strategy_config, "strategy_config")) {
    stop("strategy_config must be a strategy_config object")
  }

  # Use override if provided, otherwise default
  if (!is.null(rt_bin_width_min_override)) {
    rt_bin_width_min <- rt_bin_width_min_override
  }

  strategy <- strategy_config$strategy
  alpha <- (1 - ci_level) / 2
  probs <- c(alpha, 0.5, 1 - alpha)

  if (verbose) {
    cat(sprintf("\n=== Bootstrap Boundary CI (%d iterations, %.0f%% CI) ===\n",
                n_boot, ci_level * 100))
    cat(sprintf("  Strategy: %s | RT bin width: %.1f min\n", strategy, rt_bin_width_min))
  }

  # =========================================================================
  # Step 1: Prepare RT bins and observed boundaries
  # =========================================================================
  precursor_data <- validated_data$data

  # Create RT bins
  rt_result <- perform_rt_binning_internal(
    precursor_data, rt_bin_width_min,
    rt_binning_mode = "fixed"
  )
  precursor_data <- rt_result$data
  rt_stats <- rt_result$stats
  n_bins <- rt_result$n_bins

  if (verbose) {
    cat(sprintf("  RT bins: %d | Precursors: %s\n", n_bins,
                format(nrow(precursor_data), big.mark = ",")))
  }

  # Flatten strategy config for optimize_mz_ranges_internal
  sc <- as.list(strategy_config)

  # Calculate observed boundaries (the "real" result)
  observed_ranges <- compute_mz_boundaries_quiet(
    precursor_data, rt_stats, sc, optimization_plan
  )

  # =========================================================================
  # Step 2: Bootstrap resampling
  # =========================================================================
  if (!is.null(seed)) set.seed(seed)

  boot_min <- matrix(NA_real_, nrow = n_boot, ncol = n_bins)
  boot_max <- matrix(NA_real_, nrow = n_boot, ncol = n_bins)

  # Pre-split precursors by RT bin for efficiency
  bin_data_list <- lapply(1:n_bins, function(i) {
    precursor_data[precursor_data$rt_group == i, ]
  })
  bin_sizes <- vapply(bin_data_list, nrow, integer(1))

  t_start <- proc.time()

  for (b in seq_len(n_boot)) {
    if (verbose && b %% 50 == 0) {
      cat(sprintf("  Iteration %d/%d...\n", b, n_boot))
    }

    # Stratified resample: within each RT bin, sample with replacement
    resampled <- lapply(seq_len(n_bins), function(i) {
      bd <- bin_data_list[[i]]
      if (nrow(bd) < 2) return(bd)
      bd[sample.int(nrow(bd), replace = TRUE), ]
    })
    resampled_data <- do.call(rbind, resampled)

    # Recalculate boundaries with resampled data
    boot_ranges <- tryCatch(
      compute_mz_boundaries_quiet(resampled_data, rt_stats, sc, optimization_plan),
      error = function(e) NULL
    )

    if (!is.null(boot_ranges) && nrow(boot_ranges) == n_bins) {
      boot_min[b, ] <- boot_ranges$mz_min
      boot_max[b, ] <- boot_ranges$mz_max
    }
  }

  elapsed <- (proc.time() - t_start)["elapsed"]
  if (verbose) {
    valid_boots <- sum(!is.na(boot_min[, 1]))
    cat(sprintf("  Completed: %d/%d valid iterations in %.1f sec\n",
                valid_boots, n_boot, elapsed))
  }

  # =========================================================================
  # Step 3: Compute percentile CIs
  # =========================================================================
  ci_data <- data.frame(
    rt_segment_id = 1:n_bins,
    rt_start = rt_stats$rt_start,
    rt_end = rt_stats$rt_end,
    rt_mid = (rt_stats$rt_start + rt_stats$rt_end) / 2,
    # Observed values
    mz_min_obs = observed_ranges$mz_min,
    mz_max_obs = observed_ranges$mz_max,
    # mz_min CI
    mz_min_lower = apply(boot_min, 2, quantile, probs = probs[1], na.rm = TRUE),
    mz_min_median = apply(boot_min, 2, quantile, probs = probs[2], na.rm = TRUE),
    mz_min_upper = apply(boot_min, 2, quantile, probs = probs[3], na.rm = TRUE),
    # mz_max CI
    mz_max_lower = apply(boot_max, 2, quantile, probs = probs[1], na.rm = TRUE),
    mz_max_median = apply(boot_max, 2, quantile, probs = probs[2], na.rm = TRUE),
    mz_max_upper = apply(boot_max, 2, quantile, probs = probs[3], na.rm = TRUE),
    # CI width (uncertainty measure)
    mz_min_ci_width = NA_real_,
    mz_max_ci_width = NA_real_,
    n_precursors = observed_ranges$n_precursors_covered,
    stringsAsFactors = FALSE
  )
  ci_data$mz_min_ci_width <- ci_data$mz_min_upper - ci_data$mz_min_lower
  ci_data$mz_max_ci_width <- ci_data$mz_max_upper - ci_data$mz_max_lower

  if (verbose) {
    cat(sprintf("\n  --- CI Summary (%.0f%%) ---\n", ci_level * 100))
    cat(sprintf("  mz_min CI width: mean=%.1f Da, max=%.1f Da\n",
                mean(ci_data$mz_min_ci_width), max(ci_data$mz_min_ci_width)))
    cat(sprintf("  mz_max CI width: mean=%.1f Da, max=%.1f Da\n",
                mean(ci_data$mz_max_ci_width), max(ci_data$mz_max_ci_width)))
    cat(sprintf("  Widest CI bin: RT%02d (%.1f + %.1f = %.1f Da total)\n",
                which.max(ci_data$mz_min_ci_width + ci_data$mz_max_ci_width),
                ci_data$mz_min_ci_width[which.max(ci_data$mz_min_ci_width + ci_data$mz_max_ci_width)],
                ci_data$mz_max_ci_width[which.max(ci_data$mz_min_ci_width + ci_data$mz_max_ci_width)],
                max(ci_data$mz_min_ci_width + ci_data$mz_max_ci_width)))
  }

  result <- structure(
    list(
      ci_data = ci_data,
      boot_matrix_min = boot_min,
      boot_matrix_max = boot_max,
      observed = observed_ranges,
      params = list(
        strategy = strategy,
        n_boot = n_boot,
        ci_level = ci_level,
        rt_bin_width_min = rt_bin_width_min,
        seed = seed,
        elapsed_sec = elapsed
      )
    ),
    class = c("boundary_ci", "list")
  )

  return(result)
}


# =============================================================================
# Internal: Quiet boundary computation (no console output)
# =============================================================================

#' Compute m/z Boundaries Without Console Output
#'
#' Wrapper around optimize_mz_ranges_internal that suppresses all cat() output.
#' Used internally by bootstrap to avoid flooding the console.
#'
#' @param precursor_data Data frame with rt_group and Precursor.Mz
#' @param rt_stats RT statistics data frame
#' @param sc Flattened strategy config list
#' @param optimization_plan OptimizationPlan object
#'
#' @return Data frame with mz_min, mz_max, n_precursors_covered per RT bin
#' @keywords internal
compute_mz_boundaries_quiet <- function(precursor_data, rt_stats, sc, optimization_plan) {
  invisible(capture.output(
    result <- optimize_mz_ranges_internal(
      precursor_data = precursor_data,
      rt_stats = rt_stats,
      strategy = sc$strategy,
      target_coverage = sc$target_coverage %||% 0.95,
      quantile_lower = sc$quantile_lower %||% 0.05,
      quantile_upper = sc$quantile_upper %||% 0.95,
      outlier_threshold = sc$outlier_threshold %||% 3.0,
      smoothing_window = sc$smoothing_window %||% 7,
      polynomial_order = sc$polynomial_order %||% 3,
      n_windows_per_bin = optimization_plan$window_count_per_bin,
      min_width_da = 2,
      mz_step = sc$mz_step %||% 0.5,
      greedy_apply_smoothing = sc$greedy_apply_smoothing %||% TRUE,
      kde_density_threshold = sc$kde_density_threshold %||% 0.1,
      kde_min_coverage = sc$kde_min_coverage %||% 0.80,
      quantile_apply_smoothing = sc$quantile_apply_smoothing %||% FALSE,
      outlier_apply_smoothing = sc$outlier_apply_smoothing %||% FALSE,
      coverage_mode = sc$coverage_mode %||% "narrowest",
      smoothing_method = sc$smoothing_method %||% "sg",
      whittaker_lambda = sc$whittaker_lambda %||% 10
    )
  ))
  result
}


# =============================================================================
# Print Method
# =============================================================================

#' Print Bootstrap CI Summary
#'
#' @param x boundary_ci object
#' @param ... Ignored
#' @export
print.boundary_ci <- function(x, ...) {
  ci <- x$ci_data
  p <- x$params
  cat(sprintf("Bootstrap Boundary CI: %s strategy\n", p$strategy))
  cat(sprintf("  %d iterations, %.0f%% CI, %.1f sec\n",
              p$n_boot, p$ci_level * 100, p$elapsed_sec))
  cat(sprintf("  RT bins: %d | RT bin width: %.1f min\n",
              nrow(ci), p$rt_bin_width_min))
  cat(sprintf("  mz_min CI width: %.1f Da (mean), %.1f Da (max)\n",
              mean(ci$mz_min_ci_width), max(ci$mz_min_ci_width)))
  cat(sprintf("  mz_max CI width: %.1f Da (mean), %.1f Da (max)\n",
              mean(ci$mz_max_ci_width), max(ci$mz_max_ci_width)))
  invisible(x)
}
