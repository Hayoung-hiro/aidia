# utils_common.R - Common Utility Functions
#
# Purpose: General-purpose utilities for progress reporting, statistics,
# data access, unit conversion, timing, and output formatting.
#
# Domain-specific modules extracted to dedicated files:
#   - R/dppp.R: DPPP calculations, FWHM conversion, window count estimation
#   - R/precursor_matching.R: Window-precursor counting and matching
#   - R/validation_helpers.R: Input type/range/integer validation


# =============================================================================
# Progress & UI Functions
# =============================================================================

#' Print Formatted Header
#'
#' Creates a consistent box-style header for stage/section titles.
#'
#' @param title Character, the title text to display
#' @param width Integer, total width of the box (default: 50)
#'
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' print_header("Stage 2: Optimization Planning")
#' }
print_header <- function(title, width = 50) {
  # Calculate padding
  title_length <- nchar(title)
  if (title_length > width - 6) {
    title <- substr(title, 1, width - 6)
    title_length <- width - 6
  }

  padding_total <- width - title_length - 4  # 4 for "|  " and "  |"
  padding_left <- floor(padding_total / 2)
  padding_right <- ceiling(padding_total / 2)

  # Print box
  cat("\n")
  cat(rep("=", width), "\n", sep = "")
  cat("|",
      rep(" ", padding_left), title, rep(" ", padding_right),
      "|\n", sep = "")
  cat(rep("=", width), "\n\n", sep = "")
}

#' Print Progress Step
#'
#' Prints a numbered step with consistent formatting.
#'
#' @param step_num Integer, step number
#' @param description Character, step description
#'
#' @keywords internal
print_step <- function(step_num, description) {
  cat(sprintf("\n--- Step %d: %s ---\n", step_num, description))
}

#' Print Success Message
#'
#' Prints a formatted success message with checkmark.
#'
#' @param message Character, success message
#' @param indent Integer, number of spaces to indent (default: 2)
#'
#' @keywords internal
print_success <- function(message, indent = 2) {
  cat(sprintf("%s[OK] %s\n", rep(" ", indent), message))
}

#' Print Warning Message
#'
#' Prints a formatted warning message with warning symbol.
#'
#' @param message Character, warning message
#' @param indent Integer, number of spaces to indent (default: 2)
#'
#' @keywords internal
print_warning <- function(message, indent = 2) {
  cat(sprintf("%s[!] %s\n", rep(" ", indent), message))
}

#' Print Info Message
#'
#' Prints a formatted info message.
#'
#' @param message Character, info message
#' @param indent Integer, number of spaces to indent (default: 2)
#'
#' @keywords internal
print_info <- function(message, indent = 2) {
  cat(sprintf("%s%s\n", rep(" ", indent), message))
}


# =============================================================================
# Statistical Functions
# =============================================================================

#' Calculate Summary Statistics
#'
#' Computes comprehensive summary statistics for a numeric vector.
#' Handles NA values gracefully and returns consistent structure.
#'
#' @param x Numeric vector
#' @param na.rm Logical, remove NA values (default: TRUE)
#'
#' @return Named list with mean, median, sd, min, max, p25, p75
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' data <- rnorm(1000, mean = 10, sd = 2)
#' stats <- calculate_summary_stats(data)
#' print(stats$mean)  # ~10
#' }
calculate_summary_stats <- function(x, na.rm = TRUE) {
  list(
    mean = mean(x, na.rm = na.rm),
    median = median(x, na.rm = na.rm),
    sd = sd(x, na.rm = na.rm),
    min = min(x, na.rm = na.rm),
    max = max(x, na.rm = na.rm),
    p25 = quantile(x, 0.25, na.rm = na.rm, names = FALSE),
    p75 = quantile(x, 0.75, na.rm = na.rm, names = FALSE),
    n = length(x),
    n_na = sum(is.na(x))
  )
}

#' Calculate Coefficient of Variation (CV)
#'
#' CV = SD / Mean, expressed as a proportion or percentage.
#'
#' @param x Numeric vector
#' @param as_percentage Logical, return as percentage (default: FALSE)
#' @param na.rm Logical, remove NA values (default: TRUE)
#'
#' @return Numeric, coefficient of variation
#' @keywords internal
calculate_cv <- function(x, as_percentage = FALSE, na.rm = TRUE) {
  m <- mean(x, na.rm = na.rm)
  s <- sd(x, na.rm = na.rm)

  if (m == 0) {
    warning("Mean is zero, CV is undefined")
    return(NA)
  }

  cv <- s / m

  if (as_percentage) {
    return(cv * 100)
  } else {
    return(cv)
  }
}


# =============================================================================
# Data Access Functions (Getters)
# =============================================================================

#' Extract Precursor Data from ValidatedData
#'
#' Safe accessor function that handles different ValidatedData structures.
#'
#' @param validated_data ValidatedData object
#'
#' @return Tibble with precursor data
#' @keywords internal
get_precursor_data <- function(validated_data) {
  validate_input_type(validated_data, "ValidatedData", "validated_data")

  if (!is.null(validated_data$data)) {
    return(validated_data$data)
  } else {
    stop("ValidatedData object does not contain $data field")
  }
}

#' Extract FWHM Values
#'
#' Extracts FWHM values and converts to seconds if needed.
#'
#' @param validated_data ValidatedData object
#' @param unit Character, "seconds" or "minutes" (default: "seconds")
#'
#' @return Numeric vector of FWHM values
#' @keywords internal
get_fwhm_values <- function(validated_data, unit = "seconds") {
  data <- get_precursor_data(validated_data)

  if (!"FWHM" %in% names(data)) {
    stop("ValidatedData does not contain FWHM column")
  }

  fwhm <- data$FWHM

  if (unit == "seconds") {
    return(ensure_fwhm_seconds(fwhm))
  } else if (unit == "minutes") {
    return(fwhm)
  } else {
    stop("unit must be 'seconds' or 'minutes'")
  }
}


#' Compute Data Summary Statistics
#'
#' Returns raw (unformatted) summary statistics from a ValidatedData object.
#' Single source of truth consumed by both the PDF report and Shiny UI.
#'
#' @param validated_data ValidatedData object from Stage 1
#'
#' @return Named list with: n_raw, n_runs, n_final, n_filtered_cv,
#'   mz_min, mz_max, rt_min, rt_max, fwhm_median_sec, fwhm_mean_sec,
#'   fwhm_outlier_pct
#' @export
compute_data_summary <- function(validated_data) {
  data <- validated_data$data
  meta <- validated_data$metadata
  vs   <- validated_data$validation_status

  fwhm_sec <- ensure_fwhm_seconds(data$FWHM)

  n_raw   <- meta$n_precursors_before %||% meta$n_precursors
  n_runs  <- meta$n_runs %||% 1L
  n_final <- nrow(data)

  qd <- vs$quality_details %||% vs$details
  fwhm_outlier_pct <- if (!is.null(qd$fwhm_outliers)) {
    qd$fwhm_outliers$pct_outliers * 100
  } else 0

  list(
    n_raw            = n_raw,
    n_runs           = n_runs,
    n_final          = n_final,
    n_filtered_cv    = meta$n_filtered_cv %||% 0,
    mz_min           = min(data$Precursor.Mz, na.rm = TRUE),
    mz_max           = max(data$Precursor.Mz, na.rm = TRUE),
    rt_min           = min(data$RT.Apex, na.rm = TRUE),
    rt_max           = max(data$RT.Apex, na.rm = TRUE),
    fwhm_median_sec  = median(fwhm_sec, na.rm = TRUE),
    fwhm_mean_sec    = mean(fwhm_sec, na.rm = TRUE),
    fwhm_outlier_pct = fwhm_outlier_pct
  )
}


# =============================================================================
# Data Structure Conversion
# =============================================================================

#' Convert Minutes to Seconds
#'
#' Simple unit conversion utility.
#'
#' @param minutes Numeric, value in minutes
#'
#' @return Numeric, value in seconds
#' @keywords internal
minutes_to_seconds <- function(minutes) {
  return(minutes * 60)
}

#' Convert Seconds to Minutes
#'
#' Simple unit conversion utility.
#'
#' @param seconds Numeric, value in seconds
#'
#' @return Numeric, value in minutes
#' @keywords internal
seconds_to_minutes <- function(seconds) {
  return(seconds / 60)
}


# =============================================================================
# Timing Utilities
# =============================================================================

#' Create Timing Logger
#'
#' Creates a simple timing utility for tracking execution time.
#'
#' @return List with start() and elapsed() functions
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' timer <- create_timer()
#' # ... do work ...
#' elapsed <- timer$elapsed()  # seconds
#' }
create_timer <- function() {
  start_time <- Sys.time()

  list(
    start = function() {
      start_time <<- Sys.time()
    },
    elapsed = function(unit = "secs") {
      as.numeric(difftime(Sys.time(), start_time, units = unit))
    }
  )
}


# =============================================================================
# S3 Method Helpers
# =============================================================================

#' Create S3 Object with Class
#'
#' Helper to create S3 objects with consistent structure.
#'
#' @param data List, object data
#' @param class_name Character, S3 class name
#'
#' @return S3 object
#' @keywords internal
create_s3_object <- function(data, class_name) {
  obj <- structure(data, class = c(class_name, "list"))

  # Auto-validate if a validator exists for this class
  validator_fn <- paste0("validate_", class_name)
  if (exists(validator_fn, mode = "function")) {
    get(validator_fn)(obj)
  }

  obj
}


# =============================================================================
# Plot Utilities
# =============================================================================

#' Create Insufficient Data Placeholder Plot
#'
#' Returns a standardized ggplot placeholder when there isn't enough data
#' to render a meaningful visualization (e.g., density plots need >= 2 points).
#'
#' @param title Character, plot title
#' @param subtitle Character, plot subtitle (default: "Not enough data points")
#' @param message Character, message to display (default: "Insufficient data")
#'
#' @return A ggplot object with centered text message
#' @export
create_insufficient_data_plot <- function(title,
                                          subtitle = "Not enough data points",
                                          message = "Insufficient data\n(need at least 2 data points)") {
  # Center text at (0.5, 0.5) in normalized coordinates (0-1 range)
  # size = 5 is large enough to be readable but not overwhelming
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0.5, y = 0.5,
                      label = message, size = 5, hjust = 0.5) +
    ggplot2::labs(title = title, subtitle = subtitle) +
    ggplot2::theme_void()
}


#' Select Median RT Segment
#'
#' Picks the middle RT segment from a windows data frame. Used by verification
#' plots (tiling coverage, alignment density, FZ zoom) to show a representative
#' segment without requiring user selection.
#'
#' @param windows Data frame with rt_segment_id column
#'
#' @return Integer, the median rt_segment_id
#' @keywords internal
select_median_rt_segment <- function(windows) {
  all_segments <- sort(unique(windows$rt_segment_id))
  all_segments[ceiling(length(all_segments) / 2)]
}


#' Get Window Widths from Windows Data Frame
#'
#' Extracts window widths, using the pre-computed `window_width` column
#' if available, otherwise computing from `mz_end - mz_start`.
#'
#' @param windows Data frame with window boundaries
#'
#' @return Numeric vector of window widths
#' @keywords internal
get_window_widths <- function(windows) {
  if ("window_width" %in% names(windows)) {
    windows$window_width
  } else if ("mz_width" %in% names(windows)) {
    windows$mz_width
  } else {
    windows$mz_end - windows$mz_start
  }
}


#' Order Strategy Names in Canonical Display Order
#'
#' Returns strategy names sorted by the canonical AIDIA order
#' (GLOBAL first, then LOCAL), preserving any unknown strategies at the end.
#'
#' @param strategy_names Character vector of strategy names
#'
#' @return Character vector in canonical order
#' @keywords internal
order_strategies <- function(strategy_names) {
  available <- intersect(STRATEGY_PREFERRED_ORDER, unique(strategy_names))
  extra <- setdiff(unique(strategy_names), STRATEGY_PREFERRED_ORDER)
  c(available, extra)
}


# =============================================================================
# Data Manipulation Utilities
# =============================================================================

#' Safe bind_rows with fallback for vctrs compatibility issues
#'
#' Wrapper around dplyr::bind_rows that falls back to base R rbind
#' when vctrs package has compatibility issues (e.g., ffi_list2 error).
#'
#' @param ... Data frames or list of data frames to bind
#'
#' @return Combined data frame
#' @keywords internal
safe_bind_rows <- function(...) {
  tryCatch({
    dplyr::bind_rows(...)
  }, error = function(e) {
    # Fallback for vctrs/rlang package compatibility issues
    args <- list(...)
    if (length(args) == 1 && is.list(args[[1]])) {
      args <- args[[1]]
    }
    do.call(rbind, lapply(args, as.data.frame))
  })
}


# =============================================================================
# Output Filename Formatting
# =============================================================================

#' Map Instrument Preset to Short Name
#'
#' Converts instrument preset keys to concise abbreviations for output filenames.
#'
#' @param instrument_preset Character, instrument preset key from instruments.json
#'
#' @return Character, short instrument name
#' @keywords internal
format_short_instrument_name <- function(instrument_preset) {
  mapping <- c(
    astral           = "astral",
    astral_zoom      = "astral_zm",
    exploris         = "exploris",
    eclipse          = "eclipse",
    fusion_lumos     = "lumos",
    qexactive        = "qe",
    qexactive_hfx    = "qe_hfx",
    timstof          = "timstof",
    timstof_pro      = "timstof_pro",
    timstof_ultra    = "timstof_ult",
    waters_synapt    = "synapt",
    custom           = "custom"
  )
  short <- mapping[instrument_preset]
  if (is.na(short)) return(instrument_preset)
  as.character(short)
}

#' Map Window Mode to Short Name
#'
#' @param window_mode Character, window generation mode
#' @return Character, short window mode name
#' @keywords internal
format_short_window_mode <- function(window_mode) {
  mapping <- c(
    density   = "dens",
    fixed     = "Fix",
    staggered = "stag"
  )
  short <- mapping[window_mode]
  if (is.na(short)) return(window_mode)
  as.character(short)
}

#' Map RT Binning Mode to Short Name
#'
#' @param rt_binning_mode Character, RT binning mode ("fixed", "adaptive", or "custom")
#' @param rt_bin_width_min Numeric, RT bin width in minutes (used for custom mode)
#' @return Character, short RT mode name
#' @keywords internal
format_short_rt_mode <- function(rt_binning_mode, rt_bin_width_min = 5) {
  if (rt_binning_mode == "fixed") return("Fix")
  if (rt_binning_mode == "adaptive") return("Adapt")
  # Custom mode: include the bin width
  sprintf("%gmin", rt_bin_width_min)
}

#' Build Standardized Output Filename
#'
#' Generates filename in format: \code{type_instrument_strategy_window_rt_date.ext}
#'
#' @param type Character, output type ("method" or "report")
#' @param instrument_preset Character, instrument preset key
#' @param strategy Character, m/z optimization strategy (NULL for report)
#' @param window_mode Character, window generation mode
#' @param rt_binning_mode Character, RT binning mode
#' @param rt_bin_width_min Numeric, RT bin width (for custom mode)
#' @param ext Character, file extension without dot (default: "csv")
#' @param date Character, date string (default: today in YYYYMMDD format)
#'
#' @return Character, formatted filename (without directory path)
#' @export
#' @keywords internal
format_output_filename <- function(type,
                                   instrument_preset,
                                   strategy = NULL,
                                   window_mode,
                                   rt_binning_mode,
                                   rt_bin_width_min = 5,
                                   ext = "csv",
                                   date = format(Sys.Date(), "%Y%m%d")) {
  inst <- format_short_instrument_name(instrument_preset)
  win  <- format_short_window_mode(window_mode)
  rt   <- format_short_rt_mode(rt_binning_mode, rt_bin_width_min)

  if (!is.null(strategy)) {
    sprintf("%s_%s_%s_%s_%s_%s.%s", type, inst, strategy, win, rt, date, ext)
  } else {
    sprintf("%s_%s_%s_%s_%s.%s", type, inst, win, rt, date, ext)
  }
}


# =============================================================================
# S3 Metrics Extraction
# =============================================================================

#' Extract Before/After Metrics from Optimization Results
#'
#' Centralized accessor for DPPP, cycle time, strategy, window mode, and
#' scorecard fields from OptimizationPlan and OptimizedWindows S3 objects.
#' Provides consistent null handling across PDF reports and Shiny ValueBoxes.
#'
#' @param optimization_plan OptimizationPlan object from Stage 2
#' @param optimized_windows OptimizedWindows object from Stage 3
#'
#' @return Named list with orig_dppp, new_dppp, target_dppp, orig_ct, new_ct,
#'   strategy, window_mode, target_satisfaction, n_windows, windows_per_bin,
#'   coverage_pct, and mean_width
#' @export
#' @keywords internal
extract_before_after_metrics <- function(optimization_plan, optimized_windows) {
  # Window width: use shared helper (handles window_width -> mz_width -> compute)
  windows <- optimized_windows$windows
  widths <- get_window_widths(windows)
  mean_width <- if (length(widths) > 0) mean(widths, na.rm = TRUE) else NA_real_

  # Coverage: try percentage first, then ratio

  coverage_pct <- optimized_windows$statistics$coverage_percentage %||% NA_real_
  if (is.na(coverage_pct)) {
    ratio <- optimized_windows$statistics$mean_coverage_ratio %||% NA_real_
    if (!is.na(ratio)) coverage_pct <- ratio * 100
  }

  list(
    orig_dppp          = optimization_plan$diagnosis$current_dppp_mean %||% NA_real_,
    new_dppp           = optimized_windows$dppp_verification$actual_dppp_median %||% NA_real_,
    target_dppp        = optimization_plan$parameters$target_dppp %||% NA_real_,
    orig_ct            = optimization_plan$diagnosis$current_cycle_time_sec %||% NA_real_,
    new_ct             = optimized_windows$dppp_verification$actual_cycle_time_sec %||%
                         optimization_plan$actual_cycle_time_sec %||%
                         optimization_plan$required_cycle_time_sec %||% NA_real_,
    strategy           = optimized_windows$parameters$mz_strategy %||% "unknown",
    window_mode        = optimized_windows$parameters$window_mode %||% "unknown",
    target_satisfaction = optimization_plan$parameters$target_satisfaction %||% NA_real_,
    n_windows          = nrow(optimized_windows$windows) %||% 0L,
    windows_per_bin    = optimization_plan$window_count_per_bin,
    coverage_pct       = coverage_pct,
    mean_width         = mean_width
  )
}


# =============================================================================
# Gradient / Cycle Time Heuristics
# =============================================================================

#' Extract Gradient Name from File Path
#'
#' Parses gradient duration from DIA-NN report filenames (e.g., "30min", "60min").
#'
#' @param file_path Character, path to input file
#'
#' @return Character, gradient name (e.g., "30min") or "unknown"
#' @export
extract_gradient_name <- function(file_path) {
  basename_file <- basename(file_path)

  if (grepl("30min", basename_file)) {
    return("30min")
  } else if (grepl("60min", basename_file)) {
    return("60min")
  } else if (grepl("90min", basename_file)) {
    return("90min")
  } else {
    # Generic extraction
    matches <- regmatches(basename_file, regexpr("[0-9]+min", basename_file))
    if (length(matches) > 0) {
      return(matches[1])
    } else {
      return("unknown")
    }
  }
}

#' Estimate Cycle Time from Gradient Name
#'
#' Heuristic cycle time estimation based on gradient length:
#' <= 30min -> 1.2s, <= 60min -> 1.6s, > 60min -> 2.0s.
#'
#' @param gradient_name Character, gradient name (e.g., "30min")
#'
#' @return Numeric, estimated cycle time in seconds
#' @export
estimate_cycle_time <- function(gradient_name) {
  gradient_min <- as.numeric(gsub("min.*", "", gradient_name))

  if (gradient_min <= 30) {
    return(1.2)  # Fast gradient
  } else if (gradient_min <= 60) {
    return(1.6)  # Medium gradient
  } else {
    return(2.0)  # Long gradient
  }
}
