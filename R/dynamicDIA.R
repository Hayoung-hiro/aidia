# dynamicDIA.R - Dynamic DIA Window Optimization for R
# Ported from Python implementation for manuscript-dynamic-dia

library(dplyr)
library(readr)
library(prospectr)  # For professional Savitzky-Golay smoothing

# ============================================================================
# Smoothing Functions using prospectr
# ============================================================================

#' Savitzky-Golay smoothing using prospectr package
#'
#' @param y_array Numeric vector to be smoothed
#' @param window_size Window size (default: 7 to match Python implementation)
#' @param poly_order Polynomial order (default: 3 to match Python implementation)
#' @return Smoothed numeric vector
savitzky_golay_smooth <- function(y_array, window_size = 7, poly_order = 3) {

  # Ensure we have enough data points
  if (length(y_array) < window_size) {
    warning("Data length is smaller than window size. Returning original data.")
    return(y_array)
  }

  # Convert to matrix for prospectr (expects matrix input)
  y_matrix <- matrix(y_array, nrow = 1)

  # Apply Savitzky-Golay filter using prospectr
  smoothed_matrix <- prospectr::savitzkyGolay(
    X = y_matrix,
    m = 0,              # 0th derivative (smoothing)
    p = poly_order,     # polynomial order
    w = window_size     # window size
  )

  # Convert back to vector
  return(as.vector(smoothed_matrix))
}

#' Alternative smoothing function for boundary refinement
#'
#' @param y_array Numeric vector to be smoothed
#' @param method Smoothing method: "savgol", "movav", or "gaussian"
#' @param ... Additional parameters for smoothing methods
#' @return Smoothed numeric vector
smooth_boundaries <- function(y_array, method = "savgol", ...) {

  switch(method,
    "savgol" = {
      # Savitzky-Golay (default)
      savitzky_golay_smooth(y_array, ...)
    },
    "movav" = {
      # Moving average using prospectr
      window_size <- list(...)$window_size %||% 7
      y_matrix <- matrix(y_array, nrow = 1)
      smoothed <- prospectr::movav(y_matrix, w = window_size)
      as.vector(smoothed)
    },
    "gaussian" = {
      # Gaussian smoothing using prospectr
      sigma <- list(...)$sigma %||% 1
      y_matrix <- matrix(y_array, nrow = 1)
      smoothed <- prospectr::gapDer(y_matrix, m = 0, w = 5, s = sigma)
      as.vector(smoothed)
    },
    {
      # Default to Savitzky-Golay
      savitzky_golay_smooth(y_array, ...)
    }
  )
}

# ============================================================================
# Utility Functions
# ============================================================================

#' Round to closest integer
#'
#' @param a Numeric value
#' @return Closest integer
round_to_closest <- function(a) {
  floor_val <- floor(a)
  frac <- a - floor_val

  if (frac < 0.5) {
    return(floor_val)
  } else {
    return(ceiling(a))
  }
}

#' Validate and adjust m/z bin size to instrument optimized values
#'
#' @param mz_bin_size Desired bin size
#' @param opt_dia_slope Instrument-specific slope parameter
#' @return Validated bin size
validate_mz_bin_size <- function(mz_bin_size, opt_dia_slope) {

  if (mz_bin_size <= 0) {
    stop("Bin size must be > 0")
  }

  if (mz_bin_size < opt_dia_slope) {
    factor <- round_to_closest(opt_dia_slope / mz_bin_size)
    return(opt_dia_slope / factor)
  } else {
    factor <- round_to_closest(mz_bin_size / opt_dia_slope)
    return(factor * opt_dia_slope)
  }
}

#' Convert m/z to instrument-optimized values
#'
#' @param mz m/z value
#' @param opt_dia_slope Instrument slope parameter
#' @param opt_dia_int Instrument intercept parameter
#' @return Optimized m/z value
convert_to_optimized_mz <- function(mz, opt_dia_slope, opt_dia_int) {
  return(floor(mz / opt_dia_slope) * opt_dia_slope + opt_dia_int)
}

# ============================================================================
# Core DIA Optimization Algorithm
# ============================================================================

#' Compute optimal precursor isolation window locations
#'
#' @param isolation_width_th Isolation window width in Th
#' @param instrument_speed_hz Instrument scan speed in Hz
#' @param cycle_time_sec Cycle time in seconds
#' @param hist 2D histogram matrix (RT x m/z)
#' @param mz_axis m/z axis values
#' @param smoothing_method Smoothing method for boundaries ("savgol", "movav", "gaussian")
#' @return List with low_mz_values, high_mz_values, total_peptides
compute_precursor_locations <- function(isolation_width_th, instrument_speed_hz,
                                      cycle_time_sec, hist, mz_axis,
                                      smoothing_method = "savgol") {

  # Calculate scanning parameters
  scans_per_cycle <- floor(cycle_time_sec * instrument_speed_hz)
  mz_range_per_cycle <- as.integer(scans_per_cycle * isolation_width_th)

  # Histogram dimensions and step size
  num_mz_bins <- ncol(hist)
  mz_step <- mz_axis[2] - mz_axis[1]
  mz_indices_per_cycle <- as.integer(mz_range_per_cycle / mz_step)
  num_trials <- num_mz_bins - mz_indices_per_cycle + 1

  if (num_trials <= 0) {
    stop("m/z range per cycle is larger than available m/z range. Adjust parameters.")
  }

  best_mz_bins <- numeric(nrow(hist))
  total_num_peptides <- 0

  # For each RT row, find optimal m/z window position
  for (ridx in seq_len(nrow(hist))) {
    rt_row <- hist[ridx, ]
    max_idx <- 1
    max_peptides <- 0

    # Try each possible window position
    for (tidx in seq_len(num_trials)) {
      end_idx <- min(num_mz_bins, tidx + mz_indices_per_cycle - 1)
      peptides_covered <- sum(rt_row[tidx:end_idx])

      if (peptides_covered > max_peptides) {
        max_idx <- tidx
        max_peptides <- peptides_covered
      }
    }

    # Handle case where no peptides found
    if (max_peptides == 0) {
      max_idx <- if (ridx == 1) 1 else best_mz_bins[ridx - 1]
    }

    best_mz_bins[ridx] <- max_idx
    total_num_peptides <- total_num_peptides + max_peptides
  }

  # Convert indices to m/z values
  low_mz_values <- (best_mz_bins - 1) * mz_step + mz_axis[1]
  high_mz_values <- low_mz_values + mz_range_per_cycle

  # Apply professional smoothing using prospectr
  low_mz_values_smooth <- smooth_boundaries(low_mz_values, method = smoothing_method)
  high_mz_values_smooth <- smooth_boundaries(high_mz_values, method = smoothing_method)

  cat(sprintf("Applied %s smoothing to isolation window boundaries\n", smoothing_method))

  return(list(
    low_mz_values = low_mz_values_smooth,
    high_mz_values = high_mz_values_smooth,
    total_peptides = total_num_peptides,
    raw_low_mz = low_mz_values,
    raw_high_mz = high_mz_values
  ))
}

# ============================================================================
# DIA Method Creation Functions
# ============================================================================

#' Create scheduled DIA scan method
#'
#' @param rt_axis Retention time axis
#' @param low_mz_values Lower m/z boundaries
#' @param high_mz_values Upper m/z boundaries
#' @param isolation_width_th Isolation window width
#' @param opt_dia_slope Instrument slope parameter (default: 1.00045475)
#' @param opt_dia_int Instrument intercept parameter (default: 0.25)
#' @return List of scheduled DIA scan information
create_scheduled_dia_scans <- function(rt_axis, low_mz_values, high_mz_values,
                                     isolation_width_th,
                                     opt_dia_slope = 1.00045475,
                                     opt_dia_int = 0.25) {

  # Validate isolation width
  dia_isolation_width <- validate_mz_bin_size(isolation_width_th, opt_dia_slope)

  scheduled_dia <- list()

  for (i in seq_along(rt_axis)) {
    rt <- rt_axis[i]
    low <- low_mz_values[i]
    high <- high_mz_values[i]

    # Convert to instrument-optimized m/z values
    dia_low <- convert_to_optimized_mz(low, opt_dia_slope, opt_dia_int)
    dia_high <- convert_to_optimized_mz(high, opt_dia_slope, opt_dia_int)

    # Calculate number of scans needed
    num_scans <- as.integer(ceiling((dia_high - dia_low) / dia_isolation_width) + 1)

    # Generate scan m/z values
    dia_scans <- numeric(num_scans)
    for (sidx in seq_len(num_scans)) {
      dia_scans[sidx] <- (sidx - 1) * dia_isolation_width + dia_low
    }

    scheduled_dia[[i]] <- list(
      rt = rt,
      scans = dia_scans
    )
  }

  return(scheduled_dia)
}

#' Save scheduled DIA scans to CSV file
#'
#' @param file_name Output file name
#' @param scheduled_dia Scheduled DIA scan list
#' @return Invisible TRUE on success
save_scheduled_dia_scans <- function(file_name, scheduled_dia) {

  # Prepare data frame
  scan_data <- data.frame(
    mz = numeric(),
    t_start_min = numeric(),
    t_stop_min = numeric(),
    stringsAsFactors = FALSE
  )

  # Process each time period
  for (sidx in seq_len(length(scheduled_dia) - 1)) {
    period <- scheduled_dia[[sidx]]
    next_period <- scheduled_dia[[sidx + 1]]

    start_time <- period$rt
    stop_time <- next_period$rt

    # Add all scans for this time period
    for (prec in period$scans) {
      scan_data <- rbind(scan_data, data.frame(
        mz = prec,
        t_start_min = start_time,
        t_stop_min = stop_time,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Write to CSV
  write_csv(scan_data, file_name)

  cat(sprintf("Scheduled DIA method saved to: %s\n", file_name))
  cat(sprintf("Total scheduled scans: %d\n", nrow(scan_data)))

  return(invisible(TRUE))
}

# ============================================================================
# High-Level Workflow Functions
# ============================================================================

#' Create histogram from peptide data
#'
#' @param peptide_data Data frame with 'rt' and 'mz' columns
#' @param rt_bin_size_min RT bin size in minutes
#' @param mz_bin_size m/z bin size
#' @return List with hist, rt_axis, mz_axis
create_peptide_histogram <- function(peptide_data, rt_bin_size_min = 3, mz_bin_size = 5) {

  if (!all(c("rt", "mz") %in% names(peptide_data))) {
    stop("peptide_data must contain 'rt' and 'mz' columns")
  }

  # Create bin edges
  rt_edges <- seq(min(peptide_data$rt), max(peptide_data$rt), by = rt_bin_size_min)
  mz_edges <- seq(min(peptide_data$mz), max(peptide_data$mz), by = mz_bin_size)

  # Create 2D histogram
  hist_result <- hist2d(peptide_data$rt, peptide_data$mz,
                       xbreaks = rt_edges, ybreaks = mz_edges)

  # Calculate axis centers
  rt_axis <- rt_edges[-length(rt_edges)] + rt_bin_size_min / 2
  mz_axis <- mz_edges[-length(mz_edges)] + mz_bin_size / 2

  return(list(
    hist = hist_result$counts,
    rt_axis = rt_axis,
    mz_axis = mz_axis,
    rt_edges = rt_edges,
    mz_edges = mz_edges
  ))
}

#' Simple 2D histogram function
#'
#' @param x X values
#' @param y Y values
#' @param xbreaks X bin edges
#' @param ybreaks Y bin edges
#' @return List with counts matrix
hist2d <- function(x, y, xbreaks, ybreaks) {

  # Bin the data
  x_bins <- cut(x, breaks = xbreaks, include.lowest = TRUE, labels = FALSE)
  y_bins <- cut(y, breaks = ybreaks, include.lowest = TRUE, labels = FALSE)

  # Create count matrix
  nx <- length(xbreaks) - 1
  ny <- length(ybreaks) - 1
  counts <- matrix(0, nrow = nx, ncol = ny)

  # Count occurrences
  for (i in seq_along(x)) {
    if (!is.na(x_bins[i]) && !is.na(y_bins[i])) {
      counts[x_bins[i], y_bins[i]] <- counts[x_bins[i], y_bins[i]] + 1
    }
  }

  return(list(counts = counts))
}

#' Complete dynamic DIA method generation workflow
#'
#' @param peptide_data Data frame with peptide RT and m/z information
#' @param isolation_width_th Isolation window width (default: 8)
#' @param instrument_speed_hz Instrument speed (default: 14.6)
#' @param cycle_time_sec Cycle time (default: 2.5)
#' @param rt_bin_size_min RT binning (default: 3)
#' @param mz_bin_size m/z binning (default: 5)
#' @param smoothing_method Smoothing method ("savgol", "movav", "gaussian")
#' @param output_file Output file name (optional)
#' @return List with optimization results and scheduled scans
generate_dynamic_dia_method <- function(peptide_data,
                                       isolation_width_th = 8,
                                       instrument_speed_hz = 14.6,
                                       cycle_time_sec = 2.5,
                                       rt_bin_size_min = 3,
                                       mz_bin_size = 5,
                                       smoothing_method = "savgol",
                                       output_file = NULL) {

  cat("🧬 Generating dynamic DIA method using prospectr smoothing...\n")

  # Step 1: Create histogram
  cat("1. Creating peptide histogram...\n")
  hist_result <- create_peptide_histogram(peptide_data, rt_bin_size_min, mz_bin_size)

  # Step 2: Compute optimal window locations
  cat("2. Computing optimal window locations...\n")
  optimization_result <- compute_precursor_locations(
    isolation_width_th, instrument_speed_hz, cycle_time_sec,
    hist_result$hist, hist_result$mz_axis, smoothing_method
  )

  # Step 3: Create scheduled scans
  cat("3. Creating scheduled DIA scans...\n")
  scheduled_dia <- create_scheduled_dia_scans(
    hist_result$rt_axis,
    optimization_result$low_mz_values,
    optimization_result$high_mz_values,
    isolation_width_th
  )

  # Step 4: Save results
  if (!is.null(output_file)) {
    cat("4. Saving method to file...\n")
    save_scheduled_dia_scans(output_file, scheduled_dia)
  }

  # Print summary
  cat(sprintf("✅ Method generation complete!\n"))
  cat(sprintf("   • Smoothing method: %s (prospectr)\n", smoothing_method))
  cat(sprintf("   • Total peptides covered: %d\n", optimization_result$total_peptides))
  cat(sprintf("   • RT range: %.1f - %.1f min\n",
              min(hist_result$rt_axis), max(hist_result$rt_axis)))
  cat(sprintf("   • m/z range: %.1f - %.1f\n",
              min(optimization_result$low_mz_values), max(optimization_result$high_mz_values)))
  cat(sprintf("   • Number of time segments: %d\n", length(scheduled_dia)))

  return(list(
    histogram = hist_result,
    optimization = optimization_result,
    scheduled_scans = scheduled_dia,
    parameters = list(
      isolation_width_th = isolation_width_th,
      instrument_speed_hz = instrument_speed_hz,
      cycle_time_sec = cycle_time_sec,
      smoothing_method = smoothing_method
    )
  ))
}

# ============================================================================
# Package Installation Helper
# ============================================================================

#' Check and install required packages
#'
#' @return Invisible TRUE if all packages are available
check_dependencies <- function() {

  required_packages <- c("dplyr", "readr", "prospectr")

  missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

  if (length(missing_packages) > 0) {
    cat("Installing missing packages:", paste(missing_packages, collapse = ", "), "\n")
    install.packages(missing_packages)
  }

  # Load all packages
  sapply(required_packages, library, character.only = TRUE, quietly = TRUE)

  cat("✅ All dependencies loaded successfully\n")
  cat("   • prospectr: Professional chemometrics smoothing\n")
  cat("   • dplyr: Data manipulation\n")
  cat("   • readr: File I/O\n")

  return(invisible(TRUE))
}