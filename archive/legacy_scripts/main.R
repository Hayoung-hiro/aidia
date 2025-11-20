# main.R - Main execution script for DIA Window Optimizer

# Load all modules
source("R/data_loader.R")
source("R/dppp_calculator.R")
source("R/optimizer.R")
source("R/visualizer.R")
# source("R/method_writer.R")  # DEPRECATED: Moved to archive/legacy_scripts/method_writer_old.R
source("R/utils.R")
source("R/fwhm_analyzer.R")
source("config/instruments.R")

#' Main optimization function
#' 
#' @param config_file Path to configuration file (JSON) or NULL for manual config
#' @param ... Additional parameters to override configuration
#' @return List with optimization results
main_optimization <- function(config_file = NULL, ...) {
  
  # Start timer
  start_time <- Sys.time()
  
  cat("\n")
  cat("╔════════════════════════════════════════════╗\n")
  cat("║   DIA ISOLATION WINDOW OPTIMIZER v1.0     ║\n")
  cat("║   RT-dependent Dynamic Optimization       ║\n")
  cat("╚════════════════════════════════════════════╝\n")
  cat("\n")
  
  # Check required packages
  if (!check_packages()) {
    stop("Please install missing packages before running")
  }
  
  # Step 1: Load configuration
  cat("=== Step 1: Loading Configuration ===\n")
  
  if (!is.null(config_file)) {
    config <- load_config(config_file)
    cat(sprintf("Configuration loaded from: %s\n", config_file))
  } else {
    config <- create_default_config()
    cat("Using default configuration\n")
  }
  
  # Override with additional parameters
  override_params <- list(...)
  for (param in names(override_params)) {
    config[[param]] <- override_params[[param]]
  }
  
  print_config(config)
  
  # Step 2: Set up instrument configuration (with optional user config)
  cat("=== Step 2: Setting Up Instrument ===\n")

  # Check if user configuration from raw metadata is available
  if (config$use_user_config && file.exists("config/user_config_final.json")) {
    cat("Loading user configuration from raw metadata...\n")
    user_config <- load_user_config("config/user_config_final.json")
    instrument_config <- apply_user_config_to_instrument(user_config)
  } else {
    # Use standard preset configuration
    instrument_config <- get_instrument_config(
      config$instrument_preset,
      list(
        ms1_time = config$ms1_time,
        ms2_time = config$ms2_time,
        max_scan_rate = config$scan_rate_limit
      )
    )
  }

  print_instrument_info(config$instrument_preset)

  if (!validate_instrument_config(instrument_config)) {
    stop("Invalid instrument configuration")
  }
  
  # Step 3: Load data with optional raw metadata integration
  cat("=== Step 3: Loading DIA-NN Data ===\n")

  # Check if raw metadata integration is requested
  if (config$enable_raw_metadata && dir.exists("rawfile")) {
    cat("Raw metadata integration enabled\n")
    data <- load_diann_data_enhanced(
      config$proteome_file,
      config$rt_min,
      config$rt_max,
      integrate_raw_metadata = TRUE,
      raw_file_dir = "rawfile"
    )
  } else {
    data <- load_diann_data(
      config$proteome_file,
      config$rt_min,
      config$rt_max
    )
  }

  # Validate data
  data <- validate_data(data)

  timer(start_time, "Data loading")
  
  # Step 4: FWHM Analysis (if enabled)
  fwhm_analysis <- NULL
  if (config$fwhm_analysis_enabled) {
    cat("\n=== Step 4a: FWHM Analysis ===\n")
    
    fwhm_start <- Sys.time()
    fwhm_analysis <- analyze_fwhm_comprehensive(
      data, 
      rt_segments = config$rt_segments,
      mz_bins = 20
    )
    
    # Print analysis summary
    print_fwhm_summary(fwhm_analysis)
    
    timer(fwhm_start, "FWHM analysis")
  }
  
  # Step 5: Run optimization
  cat("\n=== Step 5: Optimizing Isolation Windows ===\n")
  
  opt_start <- Sys.time()
  
  optimized_windows <- optimize_isolation_windows(
    data = data,
    target_dppp = config$target_dppp,
    instrument_config = instrument_config,
    mz_range = config$mz_range,
    rt_segments = config$rt_segments,
    window_mode = config$window_mode,
    min_window_width = config$min_window_width,
    max_window_width = config$max_window_width,
    overlap_mode = config$overlap_mode,
    overlap_value = config$overlap_value,
    min_precursors_per_window = config$min_precursors_per_window,
    fwhm_strategy = config$fwhm_strategy,
    fwhm_analysis = fwhm_analysis
  )
  
  timer(opt_start, "Optimization")
  
  # Step 6: Generate results
  cat("\n=== Step 6: Generating Results ===\n")
  
  # Generate analysis report
  report <- generate_analysis_report(data, optimized_windows, instrument_config)
  print_report(report)
  
  # Print Hz validation details
  if (!is.null(optimized_windows$scan_rate)) {
    cat("\n═══ INSTRUMENT PERFORMANCE CHECK ═══\n")
    cat(sprintf("Instrument: %s\n", instrument_config$name))
    cat(sprintf("Required scan rate: %.1f Hz (%.0f MS2 scans in %.3f sec cycle)\n", 
                optimized_windows$scan_rate, optimized_windows$n_windows, optimized_windows$cycle_time))
    cat(sprintf("Instrument max rate: %.1f Hz\n", instrument_config$max_scan_rate))
    cat(sprintf("Instrument optimal rate: %.1f Hz\n", instrument_config$optimal_scan_rate))
    
    # Check if achievable
    if (optimized_windows$scan_rate > instrument_config$max_scan_rate) {
      cat("\n❌ WARNING: Scan rate exceeds instrument capabilities!\n")
      cat(sprintf("   Required: %.1f Hz | Available: %.1f Hz\n", 
                  optimized_windows$scan_rate, instrument_config$max_scan_rate))
      cat("\n   Recommendations:\n")
      cat(sprintf("   • Increase DPPP to %.2f or higher\n", 
                  config$target_dppp * (optimized_windows$scan_rate / instrument_config$max_scan_rate)))
      cat(sprintf("   • Or reduce window count to %d\n", 
                  floor(optimized_windows$n_windows * instrument_config$max_scan_rate / optimized_windows$scan_rate)))
    } else if (optimized_windows$scan_rate > instrument_config$optimal_scan_rate) {
      cat("\n⚠️  Note: Scan rate exceeds optimal rate\n")
      cat(sprintf("   Current: %.1f Hz | Optimal: %.1f Hz\n", 
                  optimized_windows$scan_rate, instrument_config$optimal_scan_rate))
      cat("   May impact data quality at high scan rates\n")
    } else {
      cat("\n✅ Scan rate is within instrument capabilities\n")
    }
    cat("════════════════════════════════════\n")
  }
  
  # Step 7: Create visualizations if requested
  if (config$create_plots) {
    cat("\n=== Step 7: Creating Visualizations ===\n")
    
    plots <- create_visualization_plots(
      data, 
      optimized_windows, 
      config$rt_segments,
      instrument_config
    )
    
    # Add FWHM analysis plots if available
    if (!is.null(fwhm_analysis)) {
      fwhm_plots <- visualize_fwhm_analysis(fwhm_analysis, save_plots = TRUE, plot_dir = "plots")
      plots <- c(plots, fwhm_plots)
    }
    
    if (!is.null(config$plot_output)) {
      combined_plot <- create_combined_report(plots, config$plot_output)
      cat(sprintf("Plots saved to: %s\n", config$plot_output))
    }
  }
  
  # Step 8: Export method file
  cat("\n=== Step 8: Exporting Method File ===\n")
  
  method_file <- export_method_file(
    optimized_windows$windows, 
    config$output_format, 
    config$output_path,
    instrument_config
  )
  
  # Save configuration for reproducibility
  config_output <- paste0(config$output_path, "_config.json")
  save_config(config, config_output)
  
  # Final timer
  total_time <- timer(start_time, "Total analysis")
  
  cat("\n")
  cat("╔════════════════════════════════════════════╗\n")
  cat("║        OPTIMIZATION COMPLETE!              ║\n")
  cat(sprintf("║   Total time: %.1f seconds                  ║\n", total_time))
  cat("╚════════════════════════════════════════════╝\n")
  cat("\n")
  
  # Return results
  return(list(
    report = report,
    plots = if(config$create_plots) plots else NULL,
    windows = optimized_windows,
    config = config,
    method_file = method_file,
    fwhm_analysis = fwhm_analysis
  ))
}

#' Quick optimization with minimal configuration
#' 
#' @param proteome_file Path to DIA-NN output file
#' @param instrument Instrument preset name
#' @param target_dppp Target DPPP value
#' @return Optimization results
quick_optimize <- function(proteome_file, 
                         instrument = "astral", 
                         target_dppp = 1.25) {
  
  result <- main_optimization(
    proteome_file = proteome_file,
    instrument_preset = instrument,
    target_dppp = target_dppp,
    create_plots = TRUE
  )
  
  return(result)
}

# CLI wrapper
if (sys.nframe() == 0) {
  # Running as script
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) == 0) {
    cat("Usage: Rscript main.R [config_file.json]\n")
    cat("   or: Rscript main.R [proteome_file] [instrument] [target_dppp]\n\n")
    cat("Examples:\n")
    cat("  Rscript main.R config.json\n")
    cat("  Rscript main.R data.parquet astral 1.25\n")
    cat("\nAvailable instruments:\n")
    print(list_instruments())
  } else if (length(args) == 1 && endsWith(args[1], ".json")) {
    # Configuration file provided
    result <- main_optimization(config_file = args[1])
  } else if (length(args) >= 1) {
    # Direct parameters provided
    proteome_file <- args[1]
    instrument <- ifelse(length(args) >= 2, args[2], "astral")
    target_dppp <- ifelse(length(args) >= 3, as.numeric(args[3]), 1.25)
    
    result <- quick_optimize(proteome_file, instrument, target_dppp)
  }
}
