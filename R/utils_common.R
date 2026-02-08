# utils_common.R - Common Utility Functions
#
# Purpose: Centralize reusable functions to reduce code duplication
# and improve maintainability across the DIA Window Optimizer pipeline.
#
# Version: 2.0 (Refactored)
# Last Updated: 2025-10-25

library(dplyr)
library(tibble)

# =============================================================================
# Constants
# =============================================================================

#' Peak Width Factor for DPPP Calculation
#'
#' Chromatographic peak width is approximately 1.7 times the FWHM.
#' This is a standard constant used in DPPP (Data Points Per Peak) calculations.
#'
#' @export
PEAK_WIDTH_FACTOR <- 1.7

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
#' @export
#'
#' @examples
#' print_header("Stage 2: Optimization Planning")
print_header <- function(title, width = 50) {
  # Calculate padding
  title_length <- nchar(title)
  if (title_length > width - 6) {
    title <- substr(title, 1, width - 6)
    title_length <- width - 6
  }

  padding_total <- width - title_length - 4  # 4 for "║  " and "  ║"
  padding_left <- floor(padding_total / 2)
  padding_right <- ceiling(padding_total / 2)

  # Print box
  cat("\n")
  cat(rep("═", width), "\n", sep = "")
  cat("║",
      rep(" ", padding_left), title, rep(" ", padding_right),
      "║\n", sep = "")
  cat(rep("═", width), "\n\n", sep = "")
}

#' Print Progress Step
#'
#' Prints a numbered step with consistent formatting.
#'
#' @param step_num Integer, step number
#' @param description Character, step description
#'
#' @export
print_step <- function(step_num, description) {
  cat(sprintf("\n─── Step %d: %s ───\n", step_num, description))
}

#' Print Success Message
#'
#' Prints a formatted success message with checkmark.
#'
#' @param message Character, success message
#' @param indent Integer, number of spaces to indent (default: 2)
#'
#' @export
print_success <- function(message, indent = 2) {
  cat(sprintf("%s✅ %s\n", rep(" ", indent), message))
}

#' Print Warning Message
#'
#' Prints a formatted warning message with warning symbol.
#'
#' @param message Character, warning message
#' @param indent Integer, number of spaces to indent (default: 2)
#'
#' @export
print_warning <- function(message, indent = 2) {
  cat(sprintf("%s⚠️  %s\n", rep(" ", indent), message))
}

#' Print Info Message
#'
#' Prints a formatted info message.
#'
#' @param message Character, info message
#' @param indent Integer, number of spaces to indent (default: 2)
#'
#' @export
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
#' @export
#'
#' @examples
#' data <- rnorm(1000, mean = 10, sd = 2)
#' stats <- calculate_summary_stats(data)
#' print(stats$mean)  # ~10
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
#' @export
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
# Input Validation Functions
# =============================================================================

#' Validate Input Object Type
#'
#' Checks if an object inherits from expected class(es) and provides
#' informative error messages.
#'
#' @param obj Object to validate
#' @param expected_class Character vector, expected class name(s)
#' @param param_name Character, parameter name for error message
#'
#' @return NULL (invisible), throws error if validation fails
#' @export
validate_input_type <- function(obj, expected_class, param_name = "input") {
  if (!any(sapply(expected_class, function(cls) inherits(obj, cls)))) {
    stop(sprintf(
      "%s must be of type %s, but got: %s",
      param_name,
      paste(expected_class, collapse = " or "),
      paste(class(obj), collapse = ", ")
    ))
  }
  invisible(NULL)
}

#' Validate Numeric Range
#'
#' Checks if a numeric value is within specified range.
#'
#' @param value Numeric, value to check
#' @param min Numeric, minimum allowed value (inclusive, NULL = no min)
#' @param max Numeric, maximum allowed value (inclusive, NULL = no max)
#' @param param_name Character, parameter name for error message
#'
#' @return NULL (invisible), throws error if validation fails
#' @export
validate_numeric_range <- function(value, min = NULL, max = NULL,
                                   param_name = "value") {
  if (!is.numeric(value) || length(value) != 1) {
    stop(sprintf("%s must be a single numeric value", param_name))
  }

  if (!is.null(min) && value < min) {
    stop(sprintf("%s must be >= %.2f, got: %.2f", param_name, min, value))
  }

  if (!is.null(max) && value > max) {
    stop(sprintf("%s must be <= %.2f, got: %.2f", param_name, max, value))
  }

  invisible(NULL)
}

#' Validate Positive Integer
#'
#' Checks if a value is a positive integer.
#'
#' @param value Numeric, value to check
#' @param param_name Character, parameter name for error message
#' @param allow_zero Logical, allow zero (default: FALSE)
#'
#' @return NULL (invisible), throws error if validation fails
#' @export
validate_positive_integer <- function(value, param_name = "value",
                                      allow_zero = FALSE) {
  if (!is.numeric(value) || length(value) != 1) {
    stop(sprintf("%s must be a single numeric value", param_name))
  }

  if (value != floor(value)) {
    stop(sprintf("%s must be an integer, got: %.2f", param_name, value))
  }

  min_val <- if (allow_zero) 0 else 1
  if (value < min_val) {
    stop(sprintf("%s must be >= %d, got: %d", param_name, min_val, value))
  }

  invisible(NULL)
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
#' @export
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
#' @export
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


# =============================================================================
# DPPP Calculation Functions
# =============================================================================

#' Calculate DPPP (Data Points Per Peak)
#'
#' Computes DPPP using the standard formula:
#' DPPP = (peak_width_factor × FWHM_seconds) / cycle_time_seconds
#'
#' @param fwhm_seconds Numeric vector, FWHM in seconds
#' @param cycle_time_sec Numeric, cycle time in seconds
#' @param peak_width_factor Numeric, peak width factor (default: 1.7)
#'
#' @return Numeric vector of DPPP values
#' @export
#'
#' @examples
#' fwhm <- c(10, 15, 20)  # seconds
#' cycle_time <- 2  # seconds
#' dppp <- calculate_dppp(fwhm, cycle_time)
#' # Returns: c(8.5, 12.75, 17.0)
calculate_dppp <- function(fwhm_seconds, cycle_time_sec,
                          peak_width_factor = PEAK_WIDTH_FACTOR) {
  validate_numeric_range(cycle_time_sec, min = 0, param_name = "cycle_time_sec")

  if (cycle_time_sec == 0) {
    stop("cycle_time_sec cannot be zero")
  }

  dppp <- (peak_width_factor * fwhm_seconds) / cycle_time_sec
  return(dppp)
}

#' Calculate Satisfaction Ratio
#'
#' Computes the proportion of values meeting a target threshold.
#'
#' @param values Numeric vector
#' @param target Numeric, target threshold
#' @param tolerance Numeric, tolerance around target (default: 0.0)
#' @param direction Character, "greater" or "within" (default: "greater")
#'
#' @return List with satisfaction_ratio, n_satisfied, n_total, threshold
#' @export
calculate_satisfaction_ratio <- function(values, target, tolerance = 0.0,
                                        direction = "greater") {
  threshold_lower <- target - tolerance
  threshold_upper <- target + tolerance

  if (direction == "greater") {
    # Values must be >= threshold_lower
    meets_target <- values >= threshold_lower
  } else if (direction == "within") {
    # Values must be within [threshold_lower, threshold_upper]
    meets_target <- values >= threshold_lower & values <= threshold_upper
  } else {
    stop("direction must be 'greater' or 'within'")
  }

  satisfaction_ratio <- mean(meets_target, na.rm = TRUE)
  n_satisfied <- sum(meets_target, na.rm = TRUE)
  n_total <- length(values)

  list(
    satisfaction_ratio = satisfaction_ratio,
    n_satisfied = n_satisfied,
    n_total = n_total,
    threshold_lower = threshold_lower,
    threshold_upper = if (direction == "within") threshold_upper else NULL,
    meets_target = meets_target
  )
}


# =============================================================================
# Window-Precursor Matching (Optimized)
# =============================================================================

#' Count Precursors in Windows (Vectorized)
#'
#' Efficiently counts precursors in each window using vectorized operations.
#' This is 50-100x faster than nested loops.
#'
#' @param precursor_mz Numeric vector, precursor m/z values
#' @param window_starts Numeric vector, window start m/z values
#' @param window_ends Numeric vector, window end m/z values
#'
#' @return Integer vector, precursor count per window
#' @export
#'
#' @examples
#' precursors <- c(400.5, 450.2, 500.8, 550.3, 600.1)
#' starts <- c(400, 500, 600)
#' ends <- c(500, 600, 700)
#' counts <- count_precursors_in_windows(precursors, starts, ends)
#' # Returns: c(2, 2, 1)
count_precursors_in_windows <- function(precursor_mz, window_starts,
                                       window_ends) {
  n_windows <- length(window_starts)

  if (length(window_ends) != n_windows) {
    stop("window_starts and window_ends must have same length")
  }

  # Use cut() for efficient binning
  # Create breaks vector combining all boundaries
  breaks <- c(window_starts, window_ends[n_windows])
  breaks <- unique(sort(breaks))  # Remove duplicates and sort

  # Assign each precursor to a window
  assignments <- cut(precursor_mz,
                     breaks = breaks,
                     include.lowest = TRUE,
                     right = FALSE,  # [start, end)
                     labels = FALSE)

  # Count precursors per window
  counts <- as.vector(table(factor(assignments, levels = 1:n_windows)))

  return(counts)
}

#' Count Precursors in 2D Windows (RT x m/z)
#'
#' Memory-efficient function to count precursors in each 2D window.
#' Groups windows by RT segment and uses findInterval() on sorted m/z
#' for O(n + m*log(n)) time and O(n + m) memory instead of O(n*m).
#'
#' @param precursor_rt Numeric vector, precursor retention times
#' @param precursor_mz Numeric vector, precursor m/z values
#' @param window_rt_start Numeric vector, window RT start values
#' @param window_rt_end Numeric vector, window RT end values
#' @param window_mz_start Numeric vector, window m/z start values
#' @param window_mz_end Numeric vector, window m/z end values
#'
#' @return Integer vector with precursor counts for each window
#'
#' @examples
#' rt <- c(10.1, 10.5, 20.2, 20.8)
#' mz <- c(400.5, 450.2, 500.8, 550.3)
#' win_rt_start <- c(10, 20)
#' win_rt_end <- c(15, 25)
#' win_mz_start <- c(400, 500)
#' win_mz_end <- c(500, 600)
#' counts <- count_precursors_in_2d_windows(rt, mz, win_rt_start, win_rt_end,
#'                                           win_mz_start, win_mz_end)
#' # Returns: c(2, 2) - first window has 2 precursors, second has 2
count_precursors_in_2d_windows <- function(precursor_rt, precursor_mz,
                                            window_rt_start, window_rt_end,
                                            window_mz_start, window_mz_end) {
  n_windows <- length(window_rt_start)
  n_precursors <- length(precursor_rt)

  # Validate inputs
  if (length(window_rt_end) != n_windows ||
      length(window_mz_start) != n_windows ||
      length(window_mz_end) != n_windows) {
    stop("All window vectors must have same length")
  }

  if (length(precursor_mz) != n_precursors) {
    stop("precursor_rt and precursor_mz must have same length")
  }

  counts <- integer(n_windows)

  # Group windows by unique RT segment to avoid redundant RT filtering
  # Each RT segment shares the same rt_start/rt_end
  rt_key <- paste(window_rt_start, window_rt_end, sep = "_")
  unique_rt <- unique(data.frame(
    rt_start = window_rt_start,
    rt_end = window_rt_end,
    key = rt_key,
    stringsAsFactors = FALSE
  ))

  for (r in seq_len(nrow(unique_rt))) {
    # Filter precursors in this RT segment once
    rt_mask <- precursor_rt >= unique_rt$rt_start[r] &
               precursor_rt <= unique_rt$rt_end[r]
    mz_in_rt <- precursor_mz[rt_mask]

    if (length(mz_in_rt) == 0) next

    # Sort m/z for binary search
    mz_sorted <- sort(mz_in_rt)

    # Find which windows belong to this RT group
    win_idx <- which(rt_key == unique_rt$key[r])

    for (w in win_idx) {
      # findInterval: count of values in [mz_start, mz_end)
      # left = index of last value < mz_start
      # right = index of last value <= mz_end (using mz_end as break)
      left <- findInterval(window_mz_start[w], mz_sorted, left.open = TRUE)
      right <- findInterval(window_mz_end[w], mz_sorted, left.open = FALSE)
      counts[w] <- right - left
    }
  }

  return(counts)
}

#' Find Windows Containing Precursor
#'
#' For each precursor, finds which windows contain it.
#' Returns a list where each element corresponds to a precursor.
#'
#' @param precursor_mz Numeric, single precursor m/z value
#' @param window_starts Numeric vector, window start m/z values
#' @param window_ends Numeric vector, window end m/z values
#'
#' @return Integer vector, indices of windows containing this precursor
#' @export
find_windows_for_precursor <- function(precursor_mz, window_starts,
                                       window_ends) {
  which(precursor_mz >= window_starts & precursor_mz < window_ends)
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
#' @export
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
#' @export
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
#' @export
#'
#' @examples
#' timer <- create_timer()
#' # ... do work ...
#' elapsed <- timer$elapsed()  # seconds
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
#' @export
create_s3_object <- function(data, class_name) {
  structure(data, class = c(class_name, "list"))
}


# =============================================================================
# Source S3 Classes Module
# =============================================================================

# Source centralized S3 class definitions if not already loaded
if (!exists("new_ValidatedData")) {
  s3_classes_path <- "R/s3_classes.R"
  if (file.exists(s3_classes_path)) {
    source(s3_classes_path)
  }
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
#' @export
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
#' @export
format_short_instrument_name <- function(instrument_preset) {
  mapping <- c(
    astral           = "astral",
    astral_zoom      = "astral_zm",
    astral_sensitive = "astral_sens",
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
#' @export
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
#' @export
format_short_rt_mode <- function(rt_binning_mode, rt_bin_width_min = 5) {
  if (rt_binning_mode == "fixed") return("Fix")
  if (rt_binning_mode == "adaptive") return("Adapt")
  # Custom mode: include the bin width
  sprintf("%gmin", rt_bin_width_min)
}

#' Build Standardized Output Filename
#'
#' Generates filename in format: {type}_{instrument}_{strategy}_{window}_{rt}_{date}.{ext}
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
# FWHM Unit Conversion
# =============================================================================

#' Ensure FWHM Values Are in Seconds
#'
#' Detects whether FWHM values are in minutes (median < 1) and converts
#' to seconds if needed. Uses median-based heuristic: chromatographic FWHM
#' is typically 5-30 seconds, so a median below 1 second is physically
#' implausible and indicates minutes.
#'
#' @param fwhm_vector Numeric vector of FWHM values (may contain NAs)
#'
#' @return Numeric vector of FWHM values in seconds
#' @export
ensure_fwhm_seconds <- function(fwhm_vector) {
  fwhm_clean <- fwhm_vector[!is.na(fwhm_vector)]
  if (length(fwhm_clean) == 0) return(fwhm_vector)
  if (median(fwhm_clean) < 1) {
    return(fwhm_vector * 60)
  }
  return(fwhm_vector)
}


# =============================================================================
# Preview / Estimation Helpers
# =============================================================================

#' Estimate Window Count for Quick Preview
#'
#' Quick estimation of how many MS2 windows fit given FWHM, DPPP target,
#' and MS2 scan time. Used by Shiny preview and quick_dppp_preview.
#'
#' @param fwhm_median_sec Numeric, median FWHM in seconds
#' @param target_dppp Numeric, target data points per peak
#' @param ms2_time_sec Numeric, MS2 scan time in seconds
#' @param min_windows Integer, minimum window count (default: 10)
#' @param max_windows Integer, maximum window count (default: 200)
#'
#' @return Integer, estimated window count clamped to [min_windows, max_windows]
#' @export
estimate_window_count_preview <- function(fwhm_median_sec, target_dppp, ms2_time_sec,
                                          min_windows = 10, max_windows = 200) {
  n <- floor((1.7 * fwhm_median_sec) / (target_dppp * ms2_time_sec))
  max(min_windows, min(max_windows, n))
}

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


# =============================================================================
# Module Loading
# =============================================================================

cat("OK Common utilities loaded successfully\n")
cat("   Available functions:\n")
cat("   - UI: print_header(), print_step(), print_success(), print_warning()\n")
cat("   - Stats: calculate_summary_stats(), calculate_cv()\n")
cat("   - Validation: validate_input_type(), validate_numeric_range()\n")
cat("   - DPPP: calculate_dppp(), calculate_satisfaction_ratio()\n")
cat("   - Performance: count_precursors_in_windows()\n")
cat("   - Timing: create_timer()\n")
cat("   - Naming: format_output_filename(), format_short_instrument_name()\n")
cat("   - Shared API: ensure_fwhm_seconds(), estimate_window_count_preview()\n")
cat("   - Shared API: extract_gradient_name(), estimate_cycle_time()\n")
cat("   - S3 Classes: ValidatedData, OptimizationPlan, OptimizedWindows\n")
