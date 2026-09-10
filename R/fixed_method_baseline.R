#' Describe the Original Fixed DIA Method
#'
#' Defines contiguous equal-width windows over one constant m/z range.
#' These settings describe the reference method, not optimization constraints.
#' @param n_windows Original number of MS2 windows per cycle.
#' @param mz_min Lower edge of the original range (default 400).
#' @param mz_max Upper edge of the original range (default 1000).
#' @return List of original fixed-method settings.
#' @export
fixed_method_config <- function(n_windows, mz_min = 400, mz_max = 1000) {
  scalar <- function(x) is.numeric(x) && !is.complex(x) &&
    length(x) == 1L && is.finite(x)
  if (!scalar(n_windows) || n_windows < 1 || n_windows != floor(n_windows)) {
    stop("Original window count must be a positive integer.", call. = FALSE)
  }
  if (!scalar(mz_min) || !scalar(mz_max) || mz_min <= 0 || mz_max <= mz_min) {
    stop("Original m/z range must have finite positive limits with start < end.",
         call. = FALSE)
  }
  list(type = "fixed", mz_min = mz_min, mz_max = mz_max,
       n_windows = as.integer(n_windows), window_width = (mz_max - mz_min) / n_windows)
}

.original_method_settings <- function(optimization_plan, optimized_windows) {
  optimized_windows$parameters$original_method %||% optimization_plan$original_method
}

# Slice a constant reference schedule only for comparison/display. Its m/z
# edges never change with the candidate's RT partitions or observed m/z extrema.
.fixed_baseline_windows <- function(optimization_plan, optimized_windows) {
  original <- .original_method_settings(optimization_plan, optimized_windows)
  if (is.null(original)) return(NULL)
  config <- fixed_method_config(original$n_windows, original$mz_min, original$mz_max)
  segments <- unique(optimized_windows$windows[, c("rt_start", "rt_end", "rt_segment_id")])
  edges <- seq(config$mz_min, config$mz_max, length.out = config$n_windows + 1L)
  do.call(rbind, lapply(seq_len(nrow(segments)), function(i) {
    data.frame(
      rt_segment_id = segments$rt_segment_id[i],
      rt_start = segments$rt_start[i], rt_end = segments$rt_end[i],
      mz_start = head(edges, -1L), mz_end = tail(edges, -1L),
      mz_center = (head(edges, -1L) + tail(edges, -1L)) / 2,
      window_width = config$window_width
    )
  }))
}

#' Evaluate the Input-Defined Fixed Reference Method
#'
#' Reuses the temporal-density proxy on the same RT segments as the candidate.
#' The reference m/z range and window count come from the execution snapshot.
#' No reference is fabricated for older results without that snapshot.
#' @param validated_data ValidatedData used for the optimization.
#' @param optimization_plan OptimizationPlan with original method settings.
#' @param optimized_windows OptimizedWindows result.
#' @return Reference density summary, or NULL when original settings are absent.
#' @export
evaluate_fixed_method_baseline <- function(validated_data, optimization_plan,
                                           optimized_windows) {
  original <- .original_method_settings(optimization_plan, optimized_windows)
  if (is.null(original)) return(NULL)
  precursors <- get_precursor_data(validated_data)
  if (!"FWHM" %in% names(precursors) || all(is.na(precursors$FWHM))) return(NULL)
  windows <- .fixed_baseline_windows(optimization_plan, optimized_windows)
  if (is.null(windows) || nrow(windows) == 0L) return(NULL)
  td <- calculate_precursor_temporal_density(
    precursor_mz = precursors$Precursor.Mz,
    precursor_rt = precursors$RT.Apex,
    precursor_fwhm = precursors$FWHM,
    window_mz_start = windows$mz_start, window_mz_end = windows$mz_end,
    window_rt_start = windows$rt_start, window_rt_end = windows$rt_end
  )
  covered <- is.finite(precursors$Precursor.Mz) &
    precursors$Precursor.Mz >= original$mz_min & precursors$Precursor.Mz <= original$mz_max
  list(median = median(td$density_max, na.rm = TRUE),
       mean = mean(td$density_max, na.rm = TRUE),
       max = max(td$density_max, na.rm = TRUE),
       n_per_bin = original$n_windows, mz_min = original$mz_min,
       mz_max = original$mz_max, window_width = original$window_width,
       coverage_pct = if (length(covered)) mean(covered) * 100 else NA_real_,
       cycle_time_sec = original$cycle_time_sec,
       label = "Original fixed method", windows = windows)
}
