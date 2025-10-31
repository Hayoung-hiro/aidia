# dppp_calculator.R - DPPP calculation engine for DIA window optimization

#' Calculate DPPP (Data Points Per Peak) based on FWHM and cycle time
#' 
#' @param fwhm_minutes FWHM in minutes
#' @param cycle_time_seconds Duty cycle time in seconds
#' @param instrument Instrument type ("astral", "orbitrap", "timstof")
#' @return DPPP value
calculate_dppp <- function(fwhm_minutes, cycle_time_seconds, instrument = "astral") {
  
  # Convert FWHM to seconds for calculation
  fwhm_seconds <- fwhm_minutes * 60
  
  # Calculate DPPP - it's the same calculation regardless of instrument type
  # DPPP = FWHM_seconds / cycle_time_seconds
  dppp <- fwhm_seconds / cycle_time_seconds
  
  return(dppp)
}

#' Calculate cycle time based on number of windows and instrument settings
#' 
#' @param n_windows Number of isolation windows
#' @param ms1_time MS1 acquisition time in milliseconds
#' @param ms2_time MS2 acquisition time per window in milliseconds
#' @param instrument Instrument type
#' @return Cycle time in seconds
calculate_cycle_time <- function(n_windows, ms1_time, ms2_time, instrument) {
  
  # Handle both instrument names and calculation types
  if (instrument %in% c("ms2_based", "parallel")) {
    # Parallel acquisition (Astral, TimsTOF)
    cycle_time_ms <- max(ms1_time, n_windows * ms2_time)
  } else if (instrument %in% c("traditional", "sequential")) {
    # Sequential acquisition (Orbitrap)
    cycle_time_ms <- ms1_time + (n_windows * ms2_time)
  } else {
    # Try specific instrument names
    cycle_time_ms <- switch(instrument,
      "astral" = {
        # Astral has parallel MS1/MS2 acquisition
        # Cycle time is max of MS1 time or total MS2 time
        max(ms1_time, n_windows * ms2_time)
      },
      "orbitrap" = {
        # Traditional sequential acquisition
        # Cycle time is MS1 + all MS2
        ms1_time + (n_windows * ms2_time)
      },
      "timstof" = {
        # TimsTOF has fast parallel acquisition
        # Similar to Astral but with different timing
        max(ms1_time, n_windows * ms2_time)
      },
      {
        stop(sprintf("Unknown instrument type or calculation method: %s", instrument))
      }
    )
  }
  
  # Convert to seconds
  cycle_time_seconds <- cycle_time_ms / 1000
  
  return(cycle_time_seconds)
}

#' Calculate cycle time from target DPPP (Reference Implementation)
#' 
#' @param target_dppp Target DPPP value
#' @param mean_fwhm Mean FWHM in seconds
#' @return Cycle time in milliseconds
calculate_cycle_time_from_dppp <- function(target_dppp, mean_fwhm) {
  # Reference formula: cycle_time = (mean_fwhm / target_dppp) * 1000
  cycle_time_ms <- (mean_fwhm / target_dppp) * 1000
  return(cycle_time_ms)
}

#' Calculate number of windows from cycle time (Reference Implementation)
#' 
#' @param cycle_time_ms Cycle time in milliseconds
#' @param ms1_time MS1 time in milliseconds
#' @param ms2_time MS2 time in milliseconds
#' @param fixed_window Use fixed window count
#' @param fixed_n_windows Fixed number of windows
#' @return Number of windows
calculate_windows_from_cycle_time <- function(cycle_time_ms, ms1_time, ms2_time, 
                                            fixed_window = FALSE, fixed_n_windows = 30) {
  if (fixed_window) {
    return(fixed_n_windows)
  }
  
  # Reference formula: n_windows = floor((cycle_time - ms1_time) / ms2_time)
  n_windows <- floor((cycle_time_ms - ms1_time) / ms2_time)
  
  # Apply reasonable constraints
  n_windows <- max(5, n_windows)  # Minimum 5 windows
  n_windows <- min(300, n_windows)  # Maximum 300 windows for Astral
  
  return(n_windows)
}

#' Validate DPPP against instrument constraints
#' 
#' @param dppp Calculated DPPP value
#' @param instrument_config Instrument configuration
#' @param n_windows Number of windows
#' @return List with validation results and warnings
validate_dppp <- function(dppp, instrument_config, n_windows) {
  
  warnings <- character()
  valid <- TRUE
  
  # Check if DPPP is in acceptable range
  if (dppp < 1.0) {
    warnings <- c(warnings, "DPPP is below 1.0 - insufficient sampling")
    valid <- FALSE
  }
  
  if (dppp > 5.0) {
    warnings <- c(warnings, "DPPP is above 5.0 - may be oversampling")
  }
  
  # Check scan rate
  if (!is.null(instrument_config$max_scan_rate)) {
    cycle_time_s <- calculate_cycle_time(
      n_windows, 
      instrument_config$ms1_time,
      instrument_config$ms2_time,
      instrument_config$cycle_calculation
    )
    # Correct scan rate calculation: MS2 scans per second
    scan_rate <- n_windows / cycle_time_s
    
    if (scan_rate > instrument_config$max_scan_rate) {
      warnings <- c(warnings, 
                   sprintf("Required scan rate (%.1f Hz) exceeds instrument limit (%.1f Hz)",
                          scan_rate, instrument_config$max_scan_rate))
      warnings <- c(warnings,
                   sprintf("Need %.0f MS2 scans in %.3f seconds (%.1f Hz required)",
                          n_windows, cycle_time_s, scan_rate))
      valid <- FALSE
    }
  }
  
  return(list(
    valid = valid,
    warnings = warnings,
    dppp = dppp,
    n_windows = n_windows
  ))
}

#' Calculate actual DPPP from FWHM and cycle time
#' 
#' @param fwhm_seconds FWHM in seconds
#' @param cycle_time_ms Cycle time in milliseconds
#' @return DPPP value
calculate_actual_dppp <- function(fwhm_seconds, cycle_time_ms) {
  cycle_time_seconds <- cycle_time_ms / 1000
  dppp <- fwhm_seconds / cycle_time_seconds
  return(dppp)
}

#' Calculate DPPP distribution for data (Reference approach)
#' 
#' @param data DIA-NN data with FWHM column
#' @param cycle_time_ms Cycle time in milliseconds
#' @return Vector of DPPP values
calculate_dppp_distribution <- function(data, cycle_time_ms) {
  
  # Calculate DPPP for each precursor
  dppp_values <- sapply(data$FWHM, function(fwhm) {
    fwhm_seconds <- fwhm * 60  # Convert to seconds
    calculate_actual_dppp(fwhm_seconds, cycle_time_ms)
  })
  
  return(dppp_values)
}

#' Find mode of a distribution
#' 
#' @param x Numeric vector
#' @param breaks Number of breaks for histogram
#' @return Mode value
calculate_mode <- function(x, breaks = 30) {
  if (length(x) == 0) return(NA)
  
  h <- hist(x, breaks = breaks, plot = FALSE)
  mode_idx <- which.max(h$counts)
  mode_value <- (h$breaks[mode_idx] + h$breaks[mode_idx + 1]) / 2
  
  return(mode_value)
}