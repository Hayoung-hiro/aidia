# window_evaluation.R - In-Silico Window Evaluation
#
# Purpose: Evaluate how optimized windows distribute precursors from input data.
# Provides quality flags and per-window/per-bin metrics for method assessment.
#
# Dependencies: dplyr, window_statistics.R, dppp.R, utils_common.R


# =============================================================================
# Main Evaluation Function
# =============================================================================

#' Evaluate Optimized Windows Against Input Precursor Data
#'
#' Computes per-window, per-RT-bin, overall, and quality-flag metrics that
#' quantify how well a set of optimized DIA isolation windows distributes the
#' precursors observed in the input data. Intended for internal use by the
#' Shiny app and batch export workflows.
#'
#' @param optimized_windows OptimizedWindows S3 object (Stage 3 output)
#' @param validated_data ValidatedData S3 object (Stage 1 output)
#' @param optimization_plan OptimizationPlan S3 object (Stage 2 output)
#'
#' @return Named list with four components:
#'   \describe{
#'     \item{per_window}{data.frame with one row per window: window_id,
#'       rt_segment_id, mz_start, mz_end, width, n_precursors, load_ratio,
#'       width_ok}
#'     \item{per_rt_bin}{data.frame with one row per RT bin: rt_segment_id,
#'       rt_start, rt_end, n_windows, mean_width, width_cv, total_precursors,
#'       precursor_cv, dppp_satisfaction}
#'     \item{overall}{list with coverage_pct, load_balance_cv, width_mean,
#'       width_sd, width_cv, width_min, width_max, dppp_median, n_total_windows,
#'       n_rt_bins}
#'     \item{quality_flags}{list with integer index vectors: empty_windows,
#'       overloaded_windows, width_violations, and high_cv_bins (RT bin IDs)}
#'   }
#'
#' @export
evaluate_windows <- function(optimized_windows,
                             validated_data,
                             optimization_plan) {

  # ---------------------------------------------------------------------------
  # 1. Input validation
  # ---------------------------------------------------------------------------
  validate_input_type(optimized_windows, "OptimizedWindows", "optimized_windows")
  validate_input_type(validated_data, "ValidatedData", "validated_data")
  validate_input_type(optimization_plan, "OptimizationPlan", "optimization_plan")

  windows     <- optimized_windows$windows
  precursors  <- get_precursor_data(validated_data)
  params      <- optimized_windows$parameters
  plan_params <- optimization_plan$parameters

  min_width_da  <- params$min_width_da  %||% 2
  max_width_da  <- params$max_width_da  %||% 80
  target_dppp   <- plan_params$target_dppp %||% 7.0
  cycle_time    <- optimization_plan$actual_cycle_time_sec

  # ---------------------------------------------------------------------------
  # 2. Per-window metrics
  # ---------------------------------------------------------------------------
  windows_counted <- calculate_precursors_per_window(windows, precursors)

  widths <- get_window_widths(windows_counted)
  mean_n <- mean(windows_counted$n_precursors, na.rm = TRUE)

  per_window <- data.frame(
    window_id      = windows_counted$window_id,
    rt_segment_id  = windows_counted$rt_segment_id,
    mz_start       = windows_counted$mz_start,
    mz_end         = windows_counted$mz_end,
    width          = widths,
    n_precursors   = windows_counted$n_precursors,
    load_ratio     = if (mean_n > 0) windows_counted$n_precursors / mean_n else NA_real_,
    width_ok       = widths >= min_width_da & widths <= max_width_da,
    stringsAsFactors = FALSE
  )

  # ---------------------------------------------------------------------------
  # 3. Per-RT-bin metrics
  # ---------------------------------------------------------------------------
  rt_segments <- sort(unique(windows_counted$rt_segment_id))
  fwhm_sec    <- ensure_fwhm_seconds(precursors$FWHM,
                                     unit = validated_data$metadata$fwhm_unit)

  per_rt_bin <- do.call(rbind, lapply(rt_segments, function(seg_id) {

    seg_wins <- windows_counted[windows_counted$rt_segment_id == seg_id, ,
                                drop = FALSE]

    rt_s <- seg_wins$rt_start[1]
    rt_e <- seg_wins$rt_end[1]

    # Precursors that fall in this RT bin (shared membership rule: rt_group
    # when present, else RT.Apex range). See bin_membership().
    bin_mask   <- bin_membership(precursors, rt_s, rt_e, seg_id)
    bin_fwhm   <- fwhm_sec[bin_mask]

    # DPPP per precursor in this bin, using the actual post-optimization
    # cycle time (constant across bins for a given run).
    bin_dppp <- if (length(bin_fwhm) > 0 && cycle_time > 0) {
      calculate_dppp(bin_fwhm, cycle_time)
    } else {
      numeric(0)
    }

    dppp_sat <- if (length(bin_dppp) > 0) {
      dppp_satisfaction_pct(bin_dppp, target_dppp)
    } else {
      NA_real_
    }

    seg_widths <- get_window_widths(seg_wins)

    data.frame(
      rt_segment_id   = seg_id,
      rt_start        = rt_s,
      rt_end          = rt_e,
      n_windows       = nrow(seg_wins),
      mean_width      = mean(seg_widths, na.rm = TRUE),
      width_cv        = calculate_cv(seg_widths),
      total_precursors = sum(seg_wins$n_precursors, na.rm = TRUE),
      precursor_cv    = calculate_cv(seg_wins$n_precursors),
      dppp_satisfaction = dppp_sat,
      stringsAsFactors = FALSE
    )
  }))

  # ---------------------------------------------------------------------------
  # 4. Overall metrics
  # ---------------------------------------------------------------------------
  win_stats <- calculate_window_statistics_internal(
    windows = windows_counted,
    precursor_data = precursors
  )

  overall <- list(
    coverage_pct     = win_stats$coverage_percentage,
    load_balance_cv  = calculate_cv(per_window$n_precursors),
    width_mean       = win_stats$window_width_mean,
    width_sd         = win_stats$window_width_sd,
    width_cv         = win_stats$window_width_cv,
    width_min        = win_stats$min_window_width,
    width_max        = win_stats$max_window_width,
    dppp_median      = optimized_windows$dppp_verification$actual_dppp_median %||%
                         calculate_dppp(median(fwhm_sec, na.rm = TRUE), cycle_time),
    n_total_windows  = nrow(per_window),
    n_rt_bins        = nrow(per_rt_bin)
  )

  # ---------------------------------------------------------------------------
  # 5. Temporal density (co-elution proxy)
  # ---------------------------------------------------------------------------
  # Only compute if FWHM data is available
  has_fwhm <- "FWHM" %in% names(precursors) && !all(is.na(precursors$FWHM))

  if (has_fwhm) {
    temporal_density <- calculate_precursor_temporal_density(
      precursor_mz    = precursors$Precursor.Mz,
      precursor_rt    = precursors$RT.Apex,
      precursor_fwhm  = precursors$FWHM,
      window_mz_start = windows$mz_start,
      window_mz_end   = windows$mz_end,
      window_rt_start = windows$rt_start,
      window_rt_end   = windows$rt_end
    )

    per_window$temporal_density_max  <- temporal_density$density_max
    per_window$temporal_density_mean <- temporal_density$density_mean

    overall$temporal_density_max_global  <- max(temporal_density$density_max, na.rm = TRUE)
    overall$temporal_density_mean_global <- mean(temporal_density$density_mean, na.rm = TRUE)
  } else {
    per_window$temporal_density_max  <- NA_real_
    per_window$temporal_density_mean <- NA_real_
    overall$temporal_density_max_global  <- NA_real_
    overall$temporal_density_mean_global <- NA_real_
  }

  # ---------------------------------------------------------------------------
  # 6. Quality flags
  # ---------------------------------------------------------------------------
  overload_threshold <- 2 * mean_n

  # High-density threshold: windows above P95 temporal density
  high_density_threshold <- if (has_fwhm && any(!is.na(per_window$temporal_density_max))) {
    quantile(per_window$temporal_density_max, 0.95, na.rm = TRUE)
  } else {
    Inf
  }

  quality_flags <- list(
    empty_windows      = which(per_window$n_precursors == 0),
    overloaded_windows = which(per_window$n_precursors > overload_threshold),
    width_violations   = which(!per_window$width_ok),
    high_cv_bins       = per_rt_bin$rt_segment_id[
      !is.na(per_rt_bin$precursor_cv) & per_rt_bin$precursor_cv > 0.5
    ],
    high_density_windows = which(
      !is.na(per_window$temporal_density_max) &
        per_window$temporal_density_max > high_density_threshold
    )
  )

  list(
    per_window    = per_window,
    per_rt_bin    = per_rt_bin,
    overall       = overall,
    quality_flags = quality_flags
  )
}
