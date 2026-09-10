#' Name an Output from a Completed Optimization
#'
#' Uses result metadata rather than current setup controls. Legacy results may
#' supply an instrument or strategy fallback through the optional arguments.
#' @param optimized_windows OptimizedWindows result.
#' @param type Output kind, such as method, center_mass, mz_range, or report.
#' @param ext File extension without a dot.
#' @param prefix Optional sample or condition prefix.
#' @param instrument_preset Optional explicit instrument override.
#' @param strategy Optional fallback strategy for legacy results.
#' @return A filename without a directory.
#' @export
format_result_filename <- function(optimized_windows, type = "method", ext = "csv",
                                    prefix = "", instrument_preset = NULL,
                                    strategy = NULL) {
  validate_input_type(optimized_windows, "OptimizedWindows", "optimized_windows")
  params <- optimized_windows$parameters
  name <- format_output_filename(
    type = type,
    instrument_preset = instrument_preset %||%
      optimized_windows$metadata$instrument_preset %||% "orbitrap",
    strategy = params$mz_strategy %||% strategy %||% "custom",
    window_mode = params$window_mode %||% "density",
    rt_binning_mode = params$rt_binning_mode %||% "fixed",
    rt_bin_width_min = params$rt_bin_width_min %||% 5,
    ext = ext
  )
  if (nzchar(prefix)) paste0(prefix, "_", name) else name
}

.validate_method_formats <- function(formats) {
  if (!is.character(formats) || !length(formats) || anyNA(formats) ||
      anyDuplicated(formats) ||
      !all(formats %in% c("thermo", "center_mass", "mz_range"))) {
    stop("formats must contain unique names: thermo, center_mass, mz_range.",
         call. = FALSE)
  }
}

.validate_export_charge_state <- function(charge_state) {
  if (!is.numeric(charge_state) || is.complex(charge_state) ||
      length(charge_state) != 1L || !is.finite(charge_state) ||
      charge_state < 0 || charge_state > 100 ||
      charge_state != floor(charge_state)) {
    stop("charge_state must be a single integer from 0 to 100.", call. = FALSE)
  }
  invisible(NULL)
}

#' Export Selected Method Formats to Explicit Destinations
#'
#' Centralizes format dispatch and RT schedule option forwarding. Existing
#' format writers determine the file contents and precision.
#' @param optimized_windows OptimizedWindows result.
#' @param output_files Named character vector of paths; names are thermo,
#'   center_mass, or mz_range. Parent directories are created as needed.
#' @param validated_data ValidatedData used for the optimization; required for
#'   Thermo export.
#' @param fill_void Extend the Thermo schedule to acquisition bounds.
#' @param acquisition_start_min Acquisition start in minutes.
#' @param acquisition_end_min Acquisition end in minutes, or NULL.
#' @param charge_state Expected precursor charge for Thermo exports (integer
#'   0-100, default 1). See [export_windows_to_csv()].
#' @return Named character vector of written paths, invisibly.
#' @export
export_method_formats <- function(optimized_windows, output_files,
                                   validated_data = NULL, fill_void = FALSE,
                                   acquisition_start_min = 0,
                                   acquisition_end_min = NULL,
                                   charge_state = 1L) {
  .validate_method_formats(names(output_files))
  if (!is.character(output_files) || anyNA(output_files) ||
      any(!nzchar(output_files)) || anyDuplicated(output_files)) {
    stop("output_files must contain distinct non-empty paths.", call. = FALSE)
  }
  validate_input_type(optimized_windows, "OptimizedWindows", "optimized_windows")
  if ("thermo" %in% names(output_files)) {
    validate_input_type(validated_data, "ValidatedData", "validated_data")
    .validate_export_charge_state(charge_state)
  }
  for (format in names(output_files)) {
    path <- output_files[[format]]
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    switch(format,
      thermo = export_windows_to_csv(
        optimized_windows, path, validated_data, fill_void = fill_void,
        acquisition_start_min = acquisition_start_min,
        acquisition_end_min = acquisition_end_min,
        charge_state = charge_state
      ),
      center_mass = export_center_mass_list(optimized_windows, path),
      mz_range = export_mz_range_list(optimized_windows, path)
    )
  }
  invisible(output_files)
}

.zip_method_files <- function(files, archive) {
  old_dir <- setwd(dirname(files[[1L]]))
  on.exit(setwd(old_dir), add = TRUE)
  status <- utils::zip(archive, files = basename(files), flags = "-q")
  if (!identical(as.integer(status), 0L) || !file.exists(archive)) {
    stop("Method ZIP creation failed.", call. = FALSE)
  }
}

#' Deliver Method Formats as a Directory or ZIP
#'
#' Writes the selected formats as thermo.csv, center_mass.csv and mz_range.csv.
#' ZIP delivery creates a fresh archive so repeated downloads cannot retain
#' files from an earlier export. Temporary files and working-directory changes
#' are handled inside the export module.
#' @param optimized_windows OptimizedWindows result.
#' @param output_path Destination directory or ZIP file.
#' @param validated_data ValidatedData used for the optimization.
#' @param delivery Either directory or zip.
#' @param formats Selected format names.
#' @param fill_void Extend the Thermo schedule to acquisition bounds.
#' @param acquisition_start_min Acquisition start in minutes.
#' @param acquisition_end_min Acquisition end in minutes, or NULL.
#' @param charge_state Expected precursor charge for Thermo exports (integer
#'   0-100, default 1). See [export_windows_to_csv()].
#' @return For directory delivery, named file paths; for ZIP delivery, the
#'   archive path. Both are returned invisibly.
#' @export
export_method_bundle <- function(optimized_windows, output_path,
                                  validated_data = NULL,
                                  delivery = c("directory", "zip"),
                                  formats = c("thermo", "center_mass", "mz_range"),
                                  fill_void = FALSE, acquisition_start_min = 0,
                                  acquisition_end_min = NULL,
                                  charge_state = 1L) {
  delivery <- match.arg(delivery)
  .validate_method_formats(formats)
  if ("thermo" %in% formats) .validate_export_charge_state(charge_state)
  if (!is.character(output_path) || length(output_path) != 1L ||
      is.na(output_path) || !nzchar(output_path)) {
    stop("output_path must be a non-empty path.", call. = FALSE)
  }
  if (delivery == "zip") {
    directory <- tempfile("aidia_method_export_")
    dir.create(directory)
    on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  } else {
    directory <- output_path
  }
  files <- setNames(file.path(directory, paste0(formats, ".csv")), formats)
  export_method_formats(optimized_windows, files, validated_data,
                        fill_void, acquisition_start_min, acquisition_end_min,
                        charge_state = charge_state)
  if (delivery == "directory") return(invisible(files))

  archive <- file.path(directory, "methods.zip")
  .zip_method_files(files, archive)
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(archive, output_path, overwrite = TRUE)) {
    stop("Could not copy the method ZIP to output_path.", call. = FALSE)
  }
  invisible(output_path)
}
