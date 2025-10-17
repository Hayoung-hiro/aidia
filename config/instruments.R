# instruments.R - Instrument presets for DIA window optimization

#' Get instrument configuration presets
#' 
#' @return List of instrument configurations
get_instrument_configs <- function() {
  
  instrument_configs <- list(
    astral = list(
      name = "Thermo Astral",
      ms1_time = 5.0,        # ms - realistic Astral timing
      ms2_time = 3.0,        # ms - realistic Astral timing
      max_windows = 300,     # maximum isolation windows for practical operation
      min_window_width = 2.0, # minimum window width for narrow-DIA
      max_scan_rate = 100,   # Hz - hardware maximum
      cycle_calculation = "parallel",  # MS1 and MS2 overlap
      description = "Astral narrow-DIA optimized configuration"
    ),

    orbitrap = list(
      name = "Thermo Orbitrap",
      ms1_time = 100.0,      # ms
      ms2_time = 50.0,       # ms
      max_scan_rate = 12,    # Hz - hardware maximum
      cycle_calculation = "sequential",  # MS1 then MS2
      description = "High-resolution Orbitrap mass spectrometer"
    ),

    orbitrap_exploris = list(
      name = "Thermo Orbitrap Exploris",
      ms1_time = 50.0,       # ms
      ms2_time = 22.0,       # ms
      max_scan_rate = 40,    # Hz - hardware maximum
      cycle_calculation = "sequential",  # MS1 then MS2
      description = "Orbitrap Exploris series with FAIMS"
    ),

    timstof = list(
      name = "Bruker timsTOF",
      ms1_time = 10.0,       # ms
      ms2_time = 2.0,        # ms
      max_scan_rate = 100,   # Hz - hardware maximum
      cycle_calculation = "parallel",  # MS1 and MS2 overlap
      description = "Trapped ion mobility mass spectrometer"
    ),

    timstof_pro = list(
      name = "Bruker timsTOF Pro",
      ms1_time = 10.0,       # ms
      ms2_time = 1.5,        # ms
      max_scan_rate = 120,   # Hz - hardware maximum
      cycle_calculation = "parallel",  # MS1 and MS2 overlap
      description = "timsTOF Pro with PASEF technology"
    ),

    sciex_7600 = list(
      name = "SCIEX 7600 ZenoTOF",
      ms1_time = 20.0,       # ms
      ms2_time = 10.0,       # ms
      max_scan_rate = 50,    # Hz - hardware maximum
      cycle_calculation = "sequential",  # MS1 then MS2
      description = "QTOF with Zeno trap technology"
    ),

    waters_synapt = list(
      name = "Waters SYNAPT",
      ms1_time = 50.0,       # ms
      ms2_time = 20.0,       # ms
      max_scan_rate = 20,    # Hz - hardware maximum
      cycle_calculation = "sequential",  # MS1 then MS2
      description = "Ion mobility-enabled QTOF"
    ),

    custom = list(
      name = "Custom Instrument",
      ms1_time = 50.0,       # ms (user configurable)
      ms2_time = 25.0,       # ms (user configurable)
      max_scan_rate = 20,    # Hz (user configurable)
      cycle_calculation = "sequential",  # User configurable
      description = "User-defined instrument settings"
    )
  )
  
  return(instrument_configs)
}

#' Get specific instrument configuration
#' 
#' @param instrument_name Name of the instrument preset
#' @param custom_settings Optional list of custom settings to override
#' @return Instrument configuration list
get_instrument_config <- function(instrument_name, custom_settings = NULL) {
  
  configs <- get_instrument_configs()
  
  if (!instrument_name %in% names(configs)) {
    stop(sprintf("Unknown instrument preset: %s\nAvailable: %s", 
                instrument_name,
                paste(names(configs), collapse = ", ")))
  }
  
  config <- configs[[instrument_name]]
  
  # Apply custom settings if provided
  if (!is.null(custom_settings)) {
    for (setting in names(custom_settings)) {
      if (setting %in% names(config) && !is.null(custom_settings[[setting]])) {
        config[[setting]] <- custom_settings[[setting]]
        cat(sprintf("Override %s: %s -> %s\n", 
                   setting, 
                   configs[[instrument_name]][[setting]], 
                   custom_settings[[setting]]))
      }
    }
  }
  
  return(config)
}

#' List available instruments
#'
#' @return Data frame with instrument information
list_instruments <- function() {

  configs <- get_instrument_configs()

  instrument_df <- data.frame(
    Preset = names(configs),
    Name = sapply(configs, function(x) x$name),
    MS1_Time_ms = sapply(configs, function(x) x$ms1_time),
    MS2_Time_ms = sapply(configs, function(x) x$ms2_time),
    Max_Hz = sapply(configs, function(x) x$max_scan_rate),
    Cycle_Calc = sapply(configs, function(x) x$cycle_calculation),
    stringsAsFactors = FALSE
  )

  return(instrument_df)
}

#' Print instrument information
#'
#' @param instrument_name Name of the instrument preset
print_instrument_info <- function(instrument_name) {

  config <- get_instrument_config(instrument_name)

  cat("\n=== Instrument Configuration ===\n")
  cat(sprintf("Name: %s\n", config$name))
  cat(sprintf("Description: %s\n", config$description))
  cat(sprintf("MS1 time: %.1f ms\n", config$ms1_time))
  cat(sprintf("MS2 time: %.1f ms\n", config$ms2_time))
  cat(sprintf("Max scan rate: %.0f Hz\n", config$max_scan_rate))
  cat(sprintf("Cycle calculation: %s\n", config$cycle_calculation))
  cat("================================\n\n")
}

#' Validate instrument settings
#' 
#' @param config Instrument configuration
#' @return Logical indicating if settings are valid
validate_instrument_config <- function(config) {
  
  valid <- TRUE
  errors <- character()
  
  # Check MS1 time
  if (!is.null(config$ms1_time)) {
    if (config$ms1_time <= 0 || config$ms1_time > 1000) {
      errors <- c(errors, "MS1 time must be between 0 and 1000 ms")
      valid <- FALSE
    }
  }
  
  # Check MS2 time
  if (!is.null(config$ms2_time)) {
    if (config$ms2_time <= 0 || config$ms2_time > 500) {
      errors <- c(errors, "MS2 time must be between 0 and 500 ms")
      valid <- FALSE
    }
  }
  
  # Check scan rate
  if (!is.null(config$max_scan_rate)) {
    if (config$max_scan_rate <= 0 || config$max_scan_rate > 500) {
      errors <- c(errors, "Max scan rate must be between 0 and 500 Hz")
      valid <- FALSE
    }
  }
  
  # Check cycle calculation method
  if (!config$cycle_calculation %in% c("parallel", "sequential")) {
    errors <- c(errors, "Cycle calculation must be 'parallel' or 'sequential'")
    valid <- FALSE
  }
  
  if (!valid) {
    cat("Instrument configuration errors:\n")
    for (error in errors) {
      cat(sprintf("  - %s\n", error))
    }
  }
  
  return(valid)
}