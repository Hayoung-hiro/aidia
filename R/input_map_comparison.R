#' Compare ID and MS1 maps at a fixed acquisition budget
#'
#' Designs density windows across the same full m/z range and explicit RT
#' schedule. The reference plan is never recomputed using MS1 FWHM. Empty bins
#' retain the full range with uniform windows. Both designs are evaluated on
#' the identical MS1 evaluation map, and on the ID map for inclusion reporting.
#'
#' @param id_data DIA-NN ValidatedData, with metadata$source_runs.
#' @param ms1_data ValidatedData from create_ms1_feature_dataset(), using the
#'   same selected run set as id_data.
#' @param reference_plan Existing OptimizationPlan. Its actual_cycle_time_sec,
#'   window_count_per_bin, instrument settings and targets are held fixed.
#' @param rt_breaks Strictly increasing schedule boundaries in minutes, at
#'   two-decimal precision (the Thermo export precision). No bins are dropped.
#' @param mz_range Two integer m/z endpoints. Forbidden-zone offset and overlap
#'   are disabled to preserve these exact common boundaries.
#' @param context Named list with non-empty sample, lc_condition and
#'   settings_source strings. Describes the shared scouting conditions and
#'   whether the reference settings are measured, historical, or test assumptions.
#' @param evaluation_data MS1 ValidatedData used for both designs; defaults to
#'   ms1_data. Must refer to the same selected run set. A pooled observation map
#'   can evaluate a consensus design without dropping singleton detections.
#' @param min_width_da Recommended minimum width, default 2 Da.
#' @param max_width_da Recommended maximum width, default 80 Da.
#' @return List with designs (OptimizedWindows), input_counts, satisfaction
#'   (separate denominators and FWHM sources), inclusion, window_loads, load_summary,
#'   design_differences, reference_plan and reproducibility settings. These are
#'   offline geometric/count proxies, not measured ID or quantification gains.
#' @export
compare_input_maps <- function(id_data, ms1_data, reference_plan, rt_breaks,
                               mz_range, context, evaluation_data = ms1_data,
                               min_width_da = 2, max_width_da = 80) {
  maps <- list(id = id_data, ms1 = ms1_data, evaluation_ms1 = evaluation_data)
  .validate_input_map_comparison(maps, reference_plan, rt_breaks, mz_range,
                                 context, min_width_da, max_width_da)
  n_windows <- reference_plan$window_count_per_bin
  cycle_time <- reference_plan$actual_cycle_time_sec
  designs <- lapply(maps[c("id", "ms1")], .design_fixed_map_windows,
    rt_breaks = rt_breaks, mz_range = mz_range, n_windows = n_windows,
    min_width_da = min_width_da, max_width_da = max_width_da)
  input_counts <- dplyr::bind_rows(lapply(names(maps), function(name) {
    inside <- .inside_comparison_scope(maps[[name]]$data, rt_breaks, mz_range)
    data.frame(map = name, n_runs = length(maps[[name]]$metadata$source_runs),
               aggregation = if (.is_ms1_features(maps[[name]])) maps[[name]]$metadata$feature_aggregation else "ID precursors",
               n_input = length(inside), n_in_scope = sum(inside),
               n_outside_scope = sum(!inside))
  }))
  satisfaction <- dplyr::bind_rows(lapply(names(maps), function(name) {
    .summarize_map_satisfaction(maps[[name]], name, reference_plan, rt_breaks, mz_range)
  }))
  inclusion <- list()
  loads <- list()
  for (design in names(designs)) {
    w <- designs[[design]]$windows
    for (map in c("id", "evaluation_ms1")) {
      d <- maps[[map]]$data
      matched <- .match_precursors_in_2d_windows(d$RT.Apex, d$Precursor.Mz,
        w$rt_start, w$rt_end, w$mz_start, w$mz_end)
      key <- if (.is_ms1_features(maps[[map]])) d$Feature.Key else d$Precursor.Id
      inclusion[[paste(design, map)]] <- data.frame(design = design,
        evaluation_map = map, key = key, rt_apex_min = d$RT.Apex,
        mz = d$Precursor.Mz,
        in_scope = .inside_comparison_scope(d, rt_breaks, mz_range),
        covered = matched$covered)
      if (map == "evaluation_ms1") {
        loads[[design]] <- data.frame(design = design, w,
          n_evaluation_features = matched$counts)
        names(loads[[design]])[names(loads[[design]]) == "n_precursors"] <- "n_design_rows"
      }
    }
  }
  wi <- designs$id$windows
  wm <- designs$ms1$windows
  differences <- data.frame(window_id = wi$window_id, rt_segment_id = wi$rt_segment_id,
    rt_start = wi$rt_start, rt_end = wi$rt_end,
    id_mz_start = wi$mz_start, ms1_mz_start = wm$mz_start,
    id_mz_end = wi$mz_end, ms1_mz_end = wm$mz_end,
    delta_center_da = wm$mz_center - wi$mz_center,
    delta_width_da = wm$window_width - wi$window_width)
  list(schema_version = "input-map-comparison-1", context = context,
    reference_plan = reference_plan,
    settings = list(run_name = ms1_data$metadata$source_runs,
      cycle_time_sec = cycle_time, n_windows_per_bin = n_windows,
      rt_breaks_min = rt_breaks, mz_range = mz_range,
      window_mode = "density", fz_offset = 0, overlap_percentage = 0,
      min_width_da = min_width_da, max_width_da = max_width_da,
      evaluation = "apex-based inclusion; one count per feature; shared MS1 map",
      interpretation = "offline proxy, not acquisition performance"),
    provenance = lapply(maps, function(x) x$metadata),
    designs = designs, input_counts = input_counts, satisfaction = satisfaction,
    load_summary = .summarize_comparison_loads(loads),
    inclusion = dplyr::bind_rows(inclusion), window_loads = dplyr::bind_rows(loads),
    design_differences = differences, evaluation_data = evaluation_data)
}

.validate_input_map_comparison <- function(maps, plan, rt_breaks, mz_range,
                                          context, min_width, max_width) {
  lapply(maps, validate_ValidatedData)
  if (.is_ms1_features(maps$id) || !.is_ms1_features(maps$ms1) ||
      !.is_ms1_features(maps$evaluation_ms1)) {
    stop("Expected DIA-NN id_data and MS1 ms1_data/evaluation_data.")
  }
  runs <- lapply(maps, function(x) x$metadata$source_runs)
  if (any(lengths(runs) == 0L) ||
      !setequal(runs$id, runs$ms1) || !setequal(runs$id, runs$evaluation_ms1)) {
    stop("All maps must record the same source run set; use exact run_name selection.")
  }
  validate_required_columns(maps$id$data, "Precursor.Id")
  .validate_feature_text(maps$id$data$Precursor.Id, "Precursor.Id")
  if (anyDuplicated(maps$id$data$Precursor.Id)) {
    stop("ID map must have unique Precursor.Id values; select one channel upstream if needed.")
  }
  for (map in maps) {
    d <- map$data
    if (!nrow(d) || any(!is.finite(c(d$RT.Apex, d$Precursor.Mz, d$FWHM))) ||
        any(d$FWHM <= 0) || !identical(map$metadata$fwhm_unit, "minutes")) {
      stop("Comparison maps require finite positions, positive FWHM and explicit minute units.")
    }
  }
  if (!is.list(context) || !all(c("sample", "lc_condition", "settings_source") %in% names(context))) {
    stop("context must record sample, lc_condition and settings_source.")
  }
  for (name in c("sample", "lc_condition", "settings_source")) {
    .validate_feature_text(context[[name]], name)
    if (length(context[[name]]) != 1L) stop(name, " must be a single string.")
  }
  validate_OptimizationPlan(plan)
  for (name in c("window_count_per_bin", "actual_cycle_time_sec")) {
    x <- plan[[name]]
    if (length(x) != 1L || !is.numeric(x) || !is.finite(x) || x <= 0) {
      stop(name, " must be a finite positive scalar.")
    }
  }
  if (plan$window_count_per_bin != floor(plan$window_count_per_bin)) {
    stop("Reference window count must be an integer.")
  }
  for (name in c("target_dppp", "target_satisfaction")) {
    x <- plan$parameters[[name]]
    if (length(x) != 1L || !is.numeric(x) || !is.finite(x) || x <= 0 ||
        (name == "target_satisfaction" && x > 1)) stop("Invalid reference ", name)
  }
  tolerance <- plan$parameters$dppp_tolerance %||% 0
  if (!is.numeric(tolerance) || length(tolerance) != 1L ||
      !is.finite(tolerance) || tolerance < 0 || tolerance >= plan$parameters$target_dppp) {
    stop("Invalid reference dppp_tolerance.")
  }
  if (!is.numeric(rt_breaks) || length(rt_breaks) < 2L ||
      any(!is.finite(rt_breaks)) || any(diff(rt_breaks) <= 0) || min(rt_breaks) < 0 ||
      any(abs(rt_breaks - round(rt_breaks, 2)) > 1e-9)) {
    stop("rt_breaks must be increasing non-negative minutes at two-decimal export precision.")
  }
  if (!is.numeric(mz_range) || length(mz_range) != 2L ||
      any(!is.finite(mz_range)) || any(mz_range != round(mz_range)) ||
      mz_range[1] <= 0 || diff(mz_range) <= 0) {
    stop("mz_range must be two increasing positive integer endpoints.")
  }
  if (length(min_width) != 1L || length(max_width) != 1L ||
      !is.numeric(min_width) || !is.numeric(max_width) ||
      any(!is.finite(c(min_width, max_width))) || min_width < ABSOLUTE_MIN_WIDTH_DA ||
      max_width <= min_width || diff(mz_range) < plan$window_count_per_bin * ceiling(min_width)) {
    stop("Width settings cannot preserve the fixed count and range; use a feasible reference budget.")
  }
}

.inside_comparison_scope <- function(data, rt_breaks, mz_range) {
  data$RT.Apex >= min(rt_breaks) & data$RT.Apex <= max(rt_breaks) &
    data$Precursor.Mz >= mz_range[1] & data$Precursor.Mz <= mz_range[2]
}

.design_fixed_map_windows <- function(map, rt_breaks, mz_range, n_windows,
                                      min_width_da, max_width_da) {
  data <- map$data
  group <- findInterval(data$RT.Apex, rt_breaks, rightmost.closed = TRUE)
  windows <- dplyr::bind_rows(lapply(seq_len(length(rt_breaks) - 1L), function(i) {
    mz <- data$Precursor.Mz[group == i]
    mz <- mz[mz >= mz_range[1] & mz <= mz_range[2]]
    # Empty and sparse bins are retained, without noisy fallback warnings.
    w <- if (length(mz) < n_windows * 2) {
      digitize_windows_to_n(mz_range[1], mz_range[2], n_windows,
        rep(1, n_windows), min_width_da, max_width_da, fz_offset = 0)
    } else {
      generate_variable_windows_internal(mz, mz_range[1], mz_range[2],
        n_windows, min_width_da, max_width_da, fz_offset = 0)
    }
    if (nrow(w) != n_windows || min(w$mz_start) != mz_range[1] ||
        max(w$mz_end) != mz_range[2]) stop("Window generator changed the fixed budget/range.")
    w$rt_segment_id <- i
    w$rt_start <- rt_breaks[i]
    w$rt_end <- rt_breaks[i + 1L]
    w$window_id <- paste0("RT", i, "_W", seq_len(n_windows))
    w
  }))
  windows <- calculate_precursors_per_window(windows, data)
  result <- new_OptimizedWindows(windows,
    statistics = calculate_window_statistics_internal(windows, data),
    parameters = list(window_mode = "density", mz_strategy = "full_range",
      min_width_da = min_width_da, max_width_da = max_width_da, fz_offset = 0))
  validate_OptimizedWindows(result)
  result
}

.summarize_map_satisfaction <- function(map, name, plan, rt_breaks, mz_range) {
  inside <- .inside_comparison_scope(map$data, rt_breaks, mz_range)
  fwhm <- ensure_fwhm_seconds(map$data$FWHM, unit = map$metadata$fwhm_unit)
  dppp <- calculate_dppp(fwhm, plan$actual_cycle_time_sec)
  sources <- if (.is_ms1_features(map)) map$data$fwhm_source else rep("DIA-NN FWHM", length(dppp))
  groups <- c(list(all = which(inside)), split(which(inside), sources[inside]))
  dplyr::bind_rows(lapply(seq_along(groups), function(i) {
    rows <- groups[[i]]
    n <- length(rows)
    tolerance <- plan$parameters$dppp_tolerance %||% 0
    sat <- calculate_satisfaction_ratio(dppp[rows], plan$parameters$target_dppp, tolerance)
    satisfied <- sat$n_satisfied
    predicted <- sat$satisfaction_ratio
    data.frame(map = name, denominator = if (.is_ms1_features(map)) "MS1 features" else "ID precursors",
      fwhm_source = if (i == 1L) "all sources" else names(groups)[i],
      n_total = n, n_satisfied = satisfied, predicted_satisfaction = predicted,
      target_dppp = plan$parameters$target_dppp,
      dppp_tolerance = tolerance, effective_threshold = sat$threshold_lower,
      target_satisfaction = plan$parameters$target_satisfaction,
      meets_target = predicted >= plan$parameters$target_satisfaction,
      median_dppp_wholepeak = if (n) median(dppp[rows]) else NA_real_,
      cycle_time_sec = plan$actual_cycle_time_sec)
  }))
}

.summarize_comparison_loads <- function(loads) {
  dplyr::bind_rows(lapply(names(loads), function(design) {
    rows <- loads[[design]]
    groups <- c(list(all = seq_len(nrow(rows))), split(seq_len(nrow(rows)), rows$rt_segment_id))
    dplyr::bind_rows(lapply(names(groups), function(segment) {
      n <- rows$n_evaluation_features[groups[[segment]]]
      data.frame(design = design, rt_segment = segment, n_windows = length(n),
        n_feature_assignments = sum(n), mean_features = mean(n), max_features = max(n),
        cv_features = if (length(n) > 1L && mean(n) > 0) stats::sd(n) / mean(n) else NA_real_,
        n_empty_windows = sum(n == 0))
    }))
  }))
}

#' Export a fixed-budget input-map comparison
#'
#' @param comparison Result of compare_input_maps().
#' @param output_dir New or empty directory. Existing non-empty directories are
#'   rejected to protect prior outputs and upstream caches.
#' @return Invisible normalized output directory. Writes CSV metrics, both
#'   Thermo method lists, a JSON manifest and a complete RDS result.
#' @export
export_input_map_comparison <- function(comparison, output_dir) {
  if (!identical(comparison$schema_version, "input-map-comparison-1")) {
    stop("Expected a compare_input_maps() result.")
  }
  if (dir.exists(output_dir) && length(list.files(output_dir, all.files = TRUE, no.. = TRUE))) {
    stop("output_dir must be new or empty; existing outputs are never overwritten.")
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  for (name in c("input_counts", "satisfaction", "inclusion", "window_loads", "load_summary", "design_differences")) {
    utils::write.csv(comparison[[name]], file.path(output_dir, paste0(name, ".csv")), row.names = FALSE)
  }
  for (name in names(comparison$designs)) {
    export_windows_to_csv(comparison$designs[[name]],
      file.path(output_dir, paste0(name, "_method.csv")), comparison$evaluation_data,
      fill_void = FALSE)
  }
  manifest <- comparison[c("schema_version", "context", "settings", "reference_plan", "provenance")]
  jsonlite::write_json(manifest, file.path(output_dir, "manifest.json"),
    pretty = TRUE, auto_unbox = TRUE, null = "null", digits = NA)
  saveRDS(comparison, file.path(output_dir, "comparison.rds"))
  invisible(normalizePath(output_dir, winslash = "/", mustWork = TRUE))
}
