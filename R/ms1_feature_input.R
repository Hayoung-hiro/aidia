#' Read an alphaextract MS1 feature table
#'
#' One row must represent one feature, not an isotope hill or centroid.
#' Multiple files/runs are accepted. Use inputs from the same batch; suitability
#' is the user's responsibility and sample/LC labels do not block loading.
#' Original columns are retained. Canonical RT and FWHM columns are in minutes.
#' No peptide identity, protein annotation, or identification quality is inferred.
#'
#' @param features One or more parquet paths, or a data frame in that schema.
#' @param run_name Exact run names to select. NULL includes all supplied runs.
#' @param provenance Named list of extraction/source information. For example,
#'   the contents of alphaextract's optional scan_meta.json, read by the caller.
#' @param aggregation "auto" uses consensus when alphaextract export group keys
#'   are present, otherwise pools observations. "consensus" requires shared
#'   export_id and feature_group_id; "pooled" counts each detection separately.
#' @param min_replicates Minimum distinct runs per consensus feature; NULL uses
#'   ceiling(n_runs / 2), as in the DIA-NN path. Ignored for pooled observations.
#' @return A ValidatedData object with input_type = "ms1_features", Feature.Key,
#'   original apex, explicit units and extraction provenance. Missing/invalid
#'   required values cause an error; rows are never silently discarded.
#' @export
create_ms1_feature_dataset <- function(features, run_name = NULL,
                                       provenance = list(),
                                       aggregation = c("auto", "pooled", "consensus"),
                                       min_replicates = NULL) {
  aggregation <- match.arg(aggregation)
  source_file <- NULL
  if (is.character(features) && length(features) && !anyNA(features)) {
    if (any(!file.exists(features)) || any(tolower(tools::file_ext(features)) != "parquet")) {
      stop("features must contain existing parquet files or a data frame.")
    }
    source_file <- normalizePath(features, winslash = "/", mustWork = TRUE)
    tables <- lapply(source_file, function(path) {
      d <- arrow::read_parquet(path)
      validate_required_columns(d, c("run_name", "mz", "rt_apex", "rt_start",
        "rt_end", "rt_unit", "fwhm", "fwhm_source"))
      d$feature_uid <- .make_feature_key(d)
      if (!"rt_shift_min" %in% names(d)) d$rt_shift_min <- 0
      d
    })
    features <- dplyr::bind_rows(tables)
  }
  if (!is.data.frame(features) || nrow(features) == 0L) {
    stop("features must be a non-empty feature-level table.")
  }
  if (!is.list(provenance) || (length(provenance) &&
      (is.null(names(provenance)) || any(!nzchar(names(provenance)))))) {
    stop("provenance must be a named list.")
  }
  validate_required_columns(features, c("run_name", "mz", "rt_apex", "rt_start",
                                       "rt_end", "rt_unit", "fwhm", "fwhm_source"))
  if (any(c("isotope_rank", "scan_uid", "pattern_position") %in% names(features))) {
    stop("Expected feature-level rows, not isotope/centroid rows.")
  }
  .validate_feature_text(features$run_name, "run_name")
  if (!is.null(run_name)) {
    .validate_feature_text(run_name, "run_name selection")
    if (any(!run_name %in% features$run_name)) stop("Selected run_name is absent from the feature table.")
    features <- features[features$run_name %in% run_name, , drop = FALSE]
  }
  features <- tibble::as_tibble(features)
  .validate_feature_values(features)
  rt_scale <- .feature_time_scale(features)
  features$Feature.Key <- .make_feature_key(features)
  shift <- if ("rt_shift_min" %in% names(features)) features$rt_shift_min else 0
  if (!is.numeric(shift) || any(!is.finite(shift))) stop("rt_shift_min must be finite numeric minutes.")
  if (length(shift) > 1L && any(vapply(split(shift, features$run_name),
      function(x) length(unique(x)) != 1L, logical(1)))) stop("rt_shift_min must be constant within each run.")
  features$Precursor.Mz <- features$mz
  features$RT.Start <- features$rt_start * rt_scale + shift
  features$RT.Stop <- features$rt_end * rt_scale + shift
  features$RT.Apex <- features$rt_apex * rt_scale + shift
  features$FWHM <- features$fwhm
  for (unit in c("minutes", "seconds")) {
    rows <- if (unit == "seconds") rt_scale == 1 / 60 else rt_scale == 1
    if (any(rows)) features$FWHM[rows] <- ensure_fwhm_seconds(features$fwhm[rows], unit = unit) / 60
  }
  if (any(features$RT.Start < 0)) stop("rt_shift_min produces negative aligned RT boundaries.")
  if ("charge" %in% names(features)) features$Precursor.Charge <- features$charge
  runs <- unique(features$run_name)
  has_groups <- any(c("feature_group_id", "export_id") %in% names(features))
  if (aggregation == "auto") aggregation <- if (has_groups) "consensus" else "pooled"
  observations <- features
  min_runs <- NULL
  if (aggregation == "consensus") {
    .validate_feature_groups(features)
    min_runs <- resolve_min_replicates(length(runs), min_replicates)
    if (!is.finite(min_runs) || min_runs != floor(min_runs)) stop("min_replicates must be an integer.")
    features <- .summarize_ms1_consensus(observations, min_runs)
    if (!nrow(features)) stop("No feature groups meet min_replicates; lower the detection threshold.")
  }
  result <- package_validated_data(
    data = features,
    file_info = list(feature_file = source_file, file_format = if (is.null(source_file))
      "data.frame" else "parquet"),
    raw_metadata = NULL, consensus_meta = list(n_runs = length(runs),
      n_input_features = nrow(observations), feature_aggregation = aggregation,
      min_replicates = min_runs),
    column_meta = list(columns_kept = names(features)),
    quality_results = list(quality_score = 1, warnings = character(),
      errors = character(), details = list(scope = "structural feature validation only")),
    quality_passed = TRUE, processing_time = 0
  )
  result$metadata$input_type <- "ms1_features"
  result$metadata$source_runs <- runs
  result$metadata$feature_provenance <- list(
    source_file = source_file, original_time_unit = unique(observations$rt_unit),
    row_grain = "feature", extraction = provenance,
    fwhm_sources = as.list(table(observations$fwhm_source))
  )
  if (aggregation == "consensus") result$feature_observations <- observations
  validate_ValidatedData(result)
  result
}

.feature_time_scale <- function(features) {
  units <- features$rt_unit
  if (any(!units %in% c("minute", "minutes", "second", "seconds"))) {
    stop("rt_unit must be explicit minute(s) or second(s) for RT and fwhm.")
  }
  scale <- ifelse(units %in% c("second", "seconds"), 1 / 60, 1)
  if (any(vapply(split(scale, features$run_name), function(x) length(unique(x)) != 1L, logical(1)))) {
    stop("rt_unit must be consistent within each run.")
  }
  scale
}

.validate_feature_groups <- function(features) {
  validate_required_columns(features, c("export_id", "feature_group_id"))
  .validate_feature_text(features$export_id, "export_id")
  .validate_feature_text(features$feature_group_id, "feature_group_id")
  if (length(unique(features$export_id)) != 1L) {
    stop("Consensus requires files from one joint alphaextract export_id. Use pooled mode for independent exports.")
  }
  if (anyDuplicated(features[c("run_name", "feature_group_id")])) {
    stop("A feature group may contain at most one observation per run.")
  }
  if ("charge" %in% names(features)) {
    charges <- unique(features[!is.na(features$charge), c("feature_group_id", "charge")])
    if (anyDuplicated(charges$feature_group_id)) stop("Feature group contains conflicting charge states.")
  }
}

.summarize_ms1_consensus <- function(features, min_runs) {
  # Group keys are correspondence hypotheses from the producer, never peptide IDs.
  ids <- sort(unique(features$feature_group_id))
  group <- match(features$feature_group_id, ids)
  first <- match(ids, features$feature_group_id)
  # The group validator guarantees at most one observation per run.
  counts <- tabulate(group, length(ids))
  ends <- cumsum(counts)
  median_by_group <- function(values) {
    ordered <- values[order(group, values)]
    (ordered[ends - floor(counts / 2)] + ordered[ends - floor((counts - 1) / 2)]) / 2
  }
  sources <- rep("", length(ids))
  for (source in sort(unique(features$fwhm_source))) {
    seen <- unique(group[features$fwhm_source == source])
    sources[seen] <- paste0(sources[seen], ifelse(nzchar(sources[seen]), ";", ""), source)
  }
  result <- tibble::tibble(feature_group_id = ids,
    Feature.Key = paste0(features$export_id[first], "#G", ids),
    export_id = features$export_id[first], n_replicates = counts,
    Precursor.Mz = median_by_group(features$Precursor.Mz),
    RT.Start = median_by_group(features$RT.Start), RT.Apex = median_by_group(features$RT.Apex),
    RT.Stop = median_by_group(features$RT.Stop), FWHM = median_by_group(features$FWHM),
    fwhm_source = sources,
    Precursor.Charge = if ("Precursor.Charge" %in% names(features)) features$Precursor.Charge[first] else NA_real_)
  result[counts >= min_runs, ]
}

.validate_feature_text <- function(x, name) {
  if (!is.character(x) || !length(x) || anyNA(x) || any(!nzchar(trimws(x)))) {
    stop(name, " must contain non-empty strings without missing values.")
  }
}

.validate_feature_values <- function(features) {
  for (name in c("mz", "rt_apex", "rt_start", "rt_end", "fwhm")) {
    x <- features[[name]]
    if (!is.numeric(x) || any(!is.finite(x))) {
      stop(name, " must contain finite numeric values without missing values.")
    }
  }
  if (any(features$mz <= 0) || any(features$fwhm <= 0)) {
    stop("mz and fwhm must be positive.")
  }
  if (any(features$rt_start < 0 | features$rt_start >= features$rt_end |
          features$rt_apex < features$rt_start | features$rt_apex > features$rt_end)) {
    stop("Invalid RT boundaries: require 0 <= rt_start <= rt_apex <= rt_end and start < end.")
  }
  .validate_feature_text(features$fwhm_source, "fwhm_source")
  .validate_feature_text(features$rt_unit, "rt_unit")
  for (name in intersect(c("charge", "intensity_apex", "intensity_sum",
                           "n_isotopes", "n_scans"), names(features))) {
    x <- features[[name]]
    if (!is.numeric(x) || any(!is.finite(x[!is.na(x)])) || any(x < 0, na.rm = TRUE)) {
      stop(name, " must be non-negative finite numeric values or NA.")
    }
    if (name %in% c("charge", "n_isotopes", "n_scans") &&
        any(x < 1 | x != floor(x), na.rm = TRUE)) {
      stop(name, " must be positive integers or NA.")
    }
  }
}

.make_feature_key <- function(features) {
  if (!any(c("feature_id", "feature_uid") %in% names(features))) {
    stop("feature_id or feature_uid is required.")
  }
  if ("feature_id" %in% names(features)) {
    id <- features$feature_id
    present <- !is.na(id)
    if ((any(!present) && !"feature_uid" %in% names(features)) ||
        any(!nzchar(trimws(as.character(id[present])))) ||
        (is.numeric(id) && any(!is.finite(id[present]) | id[present] < 0 | id[present] != floor(id[present]))) ||
        anyDuplicated(features[present, c("run_name", "feature_id")])) {
      stop("feature_id must be non-missing and unique within the selected run.")
    }
  }
  if ("feature_uid" %in% names(features)) {
    .validate_feature_text(features$feature_uid, "feature_uid")
    key <- features$feature_uid
    if (any(!startsWith(key, paste0(features$run_name, "#F")))) {
      stop("feature_uid must agree with the alphaextract run_name#F prefix.")
    }
    if ("feature_id" %in% names(features) &&
        any(key[present] != paste0(features$run_name[present], "#F", features$feature_id[present]))) {
      stop("feature_uid must agree with alphaextract run_name#Ffeature_id.")
    }
  } else {
    key <- paste0(features$run_name, "#F", features$feature_id)
  }
  if (anyDuplicated(key)) stop("Duplicate feature key in selected run.")
  key
}

.is_ms1_features <- function(x) {
  identical(x$metadata$input_type, "ms1_features")
}

.validate_ms1_dataset <- function(x) {
  consensus <- identical(x$metadata$feature_aggregation, "consensus")
  observations <- if (consensus) x$feature_observations else x$data
  if (!is.data.frame(observations)) stop("MS1 consensus requires feature_observations.")
  validate_required_columns(observations, c("Feature.Key", "run_name", "fwhm_source",
    "RT.Start", "RT.Stop", "mz", "rt_apex", "rt_start", "rt_end", "rt_unit", "fwhm"))
  if (!identical(x$metadata$fwhm_unit, "minutes") ||
      !identical(x$metadata$source_runs, unique(observations$run_name)) ||
      x$metadata$n_runs != length(unique(observations$run_name)) ||
      !x$metadata$feature_aggregation %in% c("pooled", "consensus") ||
      !is.list(x$metadata$feature_provenance) ||
      !all(c("source_file", "original_time_unit", "row_grain", "extraction",
             "fwhm_sources") %in% names(x$metadata$feature_provenance))) {
    stop("Invalid MS1 feature metadata: units, source runs and feature_provenance required.")
  }
  .validate_feature_values(observations)
  scale <- .feature_time_scale(observations)
  shift <- if ("rt_shift_min" %in% names(observations)) observations$rt_shift_min else 0
  for (pair in list(c("Precursor.Mz", "mz"), c("RT.Apex", "rt_apex"),
                    c("RT.Start", "rt_start"), c("RT.Stop", "rt_end"), c("FWHM", "fwhm"))) {
    expected <- observations[[pair[2]]] * if (pair[1] == "Precursor.Mz") 1 else scale
    if (startsWith(pair[1], "RT.")) expected <- expected + shift
    if (!isTRUE(all.equal(observations[[pair[1]]], expected, tolerance = 1e-12))) {
      stop("Canonical ", pair[1], " disagrees with original feature values/units.")
    }
  }
  if (!identical(observations$Feature.Key, .make_feature_key(observations))) {
    stop("Invalid Feature.Key: does not match source feature identifiers.")
  }
  if (consensus) {
    .validate_feature_groups(observations)
    expected <- .summarize_ms1_consensus(observations, x$metadata$min_replicates)
    if (!isTRUE(all.equal(x$data, expected))) stop("MS1 consensus disagrees with source observations.")
  }
  invisible(x)
}
