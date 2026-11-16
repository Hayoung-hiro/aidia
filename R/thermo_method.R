# Native method IO is isolated in a short-lived Windows helper. The helper uses
# the installed Thermo writer and verifies the file before returning success.
.thermo_helper_call <- function(request) {
  if (.Platform$OS.type != "windows")
    stop("Native Thermo methods require Windows and the matching Thermo Workstation installation.", call. = FALSE)
  helper <- system.file("thermo", "aidia-thermo-method.exe", package = "aidia", mustWork = TRUE)
  root <- tempfile("aidia_thermo_")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  request$runtime_path <- getOption("aidia.thermo.runtime", NULL)
  request$runtime_config_path <- system.file("config", "instruments.json", package = "aidia", mustWork = TRUE)
  request_file <- file.path(root, "request.json")
  response_file <- file.path(root, "response.json")
  jsonlite::write_json(request, request_file, auto_unbox = TRUE, null = "null",
                       dataframe = "rows", digits = NA)
  status <- suppressWarnings(system2(helper,
    args = shQuote(c(request_file, response_file)), stdout = file.path(root, "stdout.log"),
    stderr = file.path(root, "stderr.log"), timeout = 120))
  if (!file.exists(response_file))
    stop("The Thermo method helper did not complete. Check the local Workstation installation.", call. = FALSE)
  response <- jsonlite::read_json(response_file, simplifyVector = TRUE)
  if (!isTRUE(response$ok) || status != 0L)
    stop(response$error %||% "Thermo method conversion failed.", call. = FALSE)
  response$result
}

#' Check the Local Thermo Method Runtime
#'
#' Checks the matching default Workstation installation first, then the
#' instrument's \code{thermo_runtime_path} in the package's
#' \code{config/instruments.json}. The setting is an absolute path to the
#' version folder containing \code{System}. Blank values use default discovery.
#' The explicit \code{aidia.thermo.runtime} R option takes priority when set.
#' @return A list containing \code{available}, \code{config_path} and per-model
#'   \code{runtimes} with availability, paths and failure reasons. If the helper
#'   cannot run, returns \code{available = FALSE} and \code{reason}.
#' @export
thermo_method_status <- function() {
  tryCatch(.thermo_helper_call(list(action = "probe")),
    error = function(e) list(available = FALSE, reason = conditionMessage(e)))
}

.validate_thermo_context <- function(method) {
  if (!inherits(method, "ThermoMethodContext") || !is.list(method) ||
      !isTRUE(method$instrument %in% c("exploris", "astral_zoom")) || !isTRUE(method$native_write) ||
      length(method$template_path) != 1L || !file.exists(method$template_path) ||
      length(method$sha256) != 1L || !grepl("^[a-f0-9]{64}$", method$sha256) ||
      length(method$duration_min) != 1L || !is.finite(method$duration_min) || method$duration_min <= 0)
    stop("Use a valid context returned by inspect_thermo_method().", call. = FALSE)
  rt <- method$adaptive_rt
  if (!is.null(rt) && (!is.list(rt) ||
      !identical(rt$supported, identical(method$instrument, "astral_zoom")) ||
      !isTRUE(rt$mode %in% c("off", "acquire_reference", "adaptive")) ||
      !all(vapply(rt[c("alignment", "acquire_reference", "has_reference")],
                  function(x) is.logical(x) && length(x) == 1L && !is.na(x), logical(1))) ||
      (identical(rt$mode, "adaptive") && (!isTRUE(rt$alignment) || !isTRUE(rt$has_reference)))))
    stop("Use Adaptive RT metadata returned by inspect_thermo_method().", call. = FALSE)
  invisible(method)
}

#' Read Acquisition Settings from a Thermo Method
#'
#' Supports Exploris 480 MS1/tMS2 templates (Workstation 5.1 SP1) and Astral Zoom
#' MS1 with mass-range DIA or tMS2 templates (Astral Workstation 2.2 SP1). Reads the
#' execution data with Thermo's implementation; the template is never saved.
#' @param template_path Path to an existing .meth file.
#' @return A ThermoMethodContext with MS1/MS2 resolution, normalized/absolute
#'   AGC, maximum injection time and mode, window geometry, duration, and SHA-256.
#' @export
inspect_thermo_method <- function(template_path) {
  if (!is.character(template_path) || length(template_path) != 1L ||
      is.na(template_path) || !file.exists(template_path))
    stop("Choose an existing .meth template.", call. = FALSE)
  template_path <- normalizePath(template_path, winslash = "/", mustWork = TRUE)
  if (file.info(template_path)$size > 64 * 1024^2)
    stop("Method files must be no larger than 64 MB.", call. = FALSE)
  method <- .thermo_helper_call(list(action = "inspect", template = template_path))
  method$template_path <- template_path
  method$filename <- basename(template_path)
  class(method) <- c("ThermoMethodContext", "list")
  .validate_thermo_context(method)
  method
}

.thermo_acquisition <- function(method, settings = NULL) {
  if (is.null(settings)) return(method[c("ms1", "ms2", "ms1_scans_per_cycle")])
  if (!identical(settings$instrument, method$instrument))
    stop("The confirmed instrument does not match the method template.", call. = FALSE)
  astral <- identical(method$instrument, "astral_zoom")
  scan <- function(level) {
    original <- method[[level]]
    value <- function(suffix, default) settings[[paste0(level, suffix)]] %||% default
    result <- list(resolution = as.numeric(value("_resolution", original$resolution)),
      max_it_mode = if (isTRUE(value("_it_auto", original$max_it_mode == "Auto"))) "Auto" else "Custom",
      max_it_ms = value("_it_custom", original$max_it_ms),
      agc_percent = value("_agc", original$agc_percent))
    if (astral && level == "ms1")
      result$resolution <- as.numeric(settings$astral_ms1_resolution %||% original$resolution)
    if (astral && level == "ms2") {
      result$resolution <- NULL  # No adjustable Orbitrap resolution on the Astral analyzer.
      result$max_it_mode <- "Custom"
      result$max_it_ms <- settings$astral_ms2_it %||% original$max_it_ms
    }
    result
  }
  list(ms1 = scan("ms1"), ms2 = scan("ms2"),
       # Parallel timing uses zero *serial* MS1 scans; the template still has one MS1 experiment.
       ms1_scans_per_cycle = if (astral) 1L else settings$ms1_scans_per_cycle %||% 1L)
}

.prepare_native_request <- function(optimized_windows, method, settings = NULL,
                                    fill_void = FALSE, acquisition_start_min = 0,
                                    acquisition_end_min = NULL, charge_state = 1L) {
  validate_input_type(optimized_windows, "OptimizedWindows", "optimized_windows")
  .validate_thermo_context(method)
  .validate_export_charge_state(charge_state)
  instrument <- optimized_windows$metadata$instrument_preset
  if (!is.null(instrument) && !identical(instrument, method$instrument))
    stop("The completed optimization does not match the template instrument.", call. = FALSE)
  windows <- .prepare_thermo_windows(optimized_windows$windows,
    fill_void = fill_void, acquisition_start_min = acquisition_start_min,
    acquisition_end_min = acquisition_end_min %||% method$duration_min)
  required <- c("mz_center", "window_width", "rt_start", "rt_end")
  if (!nrow(windows) || !all(required %in% names(windows)) ||
      any(!is.finite(as.matrix(windows[required]))) || any(windows$window_width <= 0) ||
      any(windows$rt_start < 0 | windows$rt_end <= windows$rt_start))
    stop("The designed windows contain invalid m/z widths or RT bounds. Each window must have finite values, a positive width, and an end time after its non-negative start time.", call. = FALSE)
  outside <- windows$rt_end > method$duration_min
  if (any(outside))
    stop(sprintf(paste0("Designed windows end at %.2f min, beyond the template duration of %.2f min (%d windows exceed it). ",
      "Upload a matching template covering these RTs and confirm the analysis again, or use a report matching this template. ",
      "Method and LC durations are not extended automatically."),
      max(windows$rt_end), method$duration_min, sum(outside)), call. = FALSE)
  loop_n <- 0L
  if ("cycle" %in% names(windows)) {
    if (!all(windows$cycle %in% c(1L, 2L)) || !"rt_segment_id" %in% names(windows))
      stop("Staggered native export requires cycles 1 and 2 in every RT group.", call. = FALSE)
    counts <- table(windows$rt_segment_id, factor(windows$cycle, levels = c(1L, 2L)))
    if (any(counts == 0L) || length(unique(as.vector(counts))) != 1L)
      stop("Staggered native export requires the same window count in both cycles and every RT group.", call. = FALSE)
    loop_n <- calculate_loop_n(windows)
    group <- interaction(windows$rt_segment_id, windows$cycle, drop = TRUE)
    sequence <- ave(seq_len(nrow(windows)), group, FUN = seq_along)
    compound <- sprintf("C%d_RT%d_W%02d", windows$cycle, windows$rt_segment_id, sequence)
    # Active rows must encounter C1 before C2, independently of upstream ordering.
    order <- order(windows$rt_start, windows$cycle, sequence)
    windows <- windows[order, , drop = FALSE]
    compound <- compound[order]
  } else compound <- as.character(seq_len(nrow(windows)))
  list(action = "write", template = method$template_path, template_sha256 = method$sha256,
    acquisition = .thermo_acquisition(method, settings), loop_count = as.integer(loop_n),
    windows = data.frame(compound = compound, mz = windows$mz_center,
      width = windows$window_width, start = windows$rt_start, end = windows$rt_end,
      charge = charge_state, stringsAsFactors = FALSE))
}

#' Export a Native Thermo Method from a Template
#'
#' Writes the delivered AIDIA windows into one scheduled tMS2 mass list alongside
#' the MS1 experiment. Astral DIA templates are converted to Astral tMS2 while
#' preserving acquisition settings. Sets row RT, width, charge and loop count,
#' and preserves non-MS streams. Thermo validation and reopen checks
#' must pass before a file is delivered. No instrument acquisition is started.
#' Astral Zoom Adaptive RT settings and embedded references already configured
#' in the template are preserved. Configure reference collection and RT correction
#' in the instrument's Method Editor; AIDIA does not enable or disable them.
#' @param optimized_windows A completed OptimizedWindows result.
#' @param output_file Destination .meth path, distinct from the template.
#' @param method Context returned by inspect_thermo_method().
#' @param settings Saved acquisition input settings, or NULL to keep the template
#'   acquisition settings. Shiny passes the confirmed result's settings.
#' @param fill_void Extend the first and last RT groups to acquisition bounds.
#' @param acquisition_start_min Start time in minutes.
#' @param acquisition_end_min End time; NULL uses the template duration.
#' @param charge_state Precursor charge from 0 to 100; 0 specifies no known charge.
#' @return Path to the validated output, invisibly.
#' @export
export_thermo_method <- function(optimized_windows, output_file, method, settings = NULL,
                                 fill_void = FALSE, acquisition_start_min = 0,
                                 acquisition_end_min = NULL, charge_state = 1L) {
  request <- .prepare_native_request(optimized_windows, method, settings, fill_void,
    acquisition_start_min, acquisition_end_min, charge_state)
  if (!is.character(output_file) || length(output_file) != 1L || is.na(output_file) || !nzchar(output_file))
    stop("Choose an output file path.", call. = FALSE)
  target <- normalizePath(output_file, winslash = "/", mustWork = FALSE)
  if (tolower(target) == tolower(method$template_path))
    stop("The original method template cannot be overwritten.", call. = FALSE)
  staging <- tempfile("aidia_native_output_")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  request$output <- file.path(staging, "method.meth")
  result <- .thermo_helper_call(request)
  if (!isTRUE(result$validated) || !isTRUE(result$non_ms_streams_preserved) || !file.exists(request$output))
    stop("The method did not pass native validation.", call. = FALSE)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(request$output, output_file, overwrite = TRUE))
    stop("Could not deliver the validated method file.", call. = FALSE)
  invisible(output_file)
}
