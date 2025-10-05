# method_writer.R - Method file export functions

#' Export method file in various formats
#' 
#' @param windows Optimized windows data frame
#' @param format Output format ("csv", "tsv", "bruker", "thermo", "waters")
#' @param output_path Output file path
#' @param instrument_config Instrument configuration
#' @return Path to exported file
export_method_file <- function(windows, 
                              format = "csv", 
                              output_path = "method_file",
                              instrument_config = NULL) {
  
  # Ensure windows are sorted by center m/z
  windows <- windows[order(windows$center_mz), ]
  
  # Add cycle order if not present
  if (!"cycle_order" %in% names(windows)) {
    windows$cycle_order <- 1:nrow(windows)
  }
  
  # Generate output based on format
  if (format == "csv") {
    output <- export_csv_format(windows)
    file_ext <- ".csv"
  } else if (format == "tsv") {
    output <- export_tsv_format(windows)
    file_ext <- ".tsv"
  } else if (format == "bruker") {
    output <- export_bruker_format(windows)
    file_ext <- ".method"
  } else if (format == "thermo") {
    output <- export_thermo_format(windows)
    file_ext <- ".meth"
  } else if (format == "waters") {
    output <- export_waters_format(windows)
    file_ext <- ".exp"
  } else {
    stop("Unsupported format. Use: csv, tsv, bruker, thermo, or waters")
  }
  
  # Write file
  full_path <- paste0(output_path, file_ext)
  
  if (format %in% c("csv", "tsv")) {
    write.table(output, full_path, row.names = FALSE, 
               sep = ifelse(format == "csv", ",", "\t"),
               quote = FALSE)
  } else {
    writeLines(output, full_path)
  }
  
  cat(sprintf("Method file exported: %s\n", full_path))
  
  return(full_path)
}

#' Export in generic CSV format
#' 
#' @param windows Windows data frame
#' @return Data frame for CSV export
export_csv_format <- function(windows) {
  
  output <- data.frame(
    Window_Index = windows$cycle_order,
    Center_Mass_mz = round(windows$center_mz, 2),
    Window_Start_mz = round(windows$window_start, 2),
    Window_End_mz = round(windows$window_end, 2),
    Window_Width_mz = round(windows$window_width, 2),
    RT_Segment = if("RT_segment" %in% names(windows)) windows$RT_segment else rep("all", nrow(windows))
  )
  
  return(output)
}

#' Export in TSV format
#' 
#' @param windows Windows data frame
#' @return Data frame for TSV export
export_tsv_format <- function(windows) {
  # Same as CSV but will be written with tab separator
  return(export_csv_format(windows))
}

#' Export in Bruker format
#' 
#' @param windows Windows data frame
#' @return Character vector with Bruker method format
export_bruker_format <- function(windows) {
  
  lines <- character()
  
  # Header
  lines <- c(lines, "# Bruker DIA Method File")
  lines <- c(lines, sprintf("# Generated: %s", Sys.Date()))
  lines <- c(lines, sprintf("# Number of windows: %d", nrow(windows)))
  lines <- c(lines, "")
  
  # Method parameters
  lines <- c(lines, "[Method]")
  lines <- c(lines, "Type=DIA")
  lines <- c(lines, sprintf("Windows=%d", nrow(windows)))
  lines <- c(lines, "")
  
  # Window definitions
  lines <- c(lines, "[Windows]")
  
  for (i in 1:nrow(windows)) {
    lines <- c(lines, sprintf("Window%d=%.2f,%.2f,%.2f",
                             i,
                             windows$window_start[i],
                             windows$window_end[i],
                             windows$center_mz[i]))
  }
  
  return(lines)
}

#' Export in Thermo format
#' 
#' @param windows Windows data frame
#' @return Character vector with Thermo method format
export_thermo_format <- function(windows) {
  
  lines <- character()
  
  # XML-style format for Thermo
  lines <- c(lines, '<?xml version="1.0" encoding="UTF-8"?>')
  lines <- c(lines, '<Method>')
  lines <- c(lines, '  <Type>DIA</Type>')
  lines <- c(lines, sprintf('  <WindowCount>%d</WindowCount>', nrow(windows)))
  lines <- c(lines, '  <Windows>')
  
  for (i in 1:nrow(windows)) {
    lines <- c(lines, '    <Window>')
    lines <- c(lines, sprintf('      <Index>%d</Index>', i))
    lines <- c(lines, sprintf('      <StartMz>%.2f</StartMz>', windows$window_start[i]))
    lines <- c(lines, sprintf('      <EndMz>%.2f</EndMz>', windows$window_end[i]))
    lines <- c(lines, sprintf('      <CenterMz>%.2f</CenterMz>', windows$center_mz[i]))
    lines <- c(lines, sprintf('      <Width>%.2f</Width>', windows$window_width[i]))
    lines <- c(lines, '    </Window>')
  }
  
  lines <- c(lines, '  </Windows>')
  lines <- c(lines, '</Method>')
  
  return(lines)
}

#' Export in Waters format
#' 
#' @param windows Windows data frame
#' @return Character vector with Waters method format
export_waters_format <- function(windows) {
  
  lines <- character()
  
  # Waters specific format
  lines <- c(lines, "HDI_DIA_METHOD")
  lines <- c(lines, sprintf("VERSION\t1.0"))
  lines <- c(lines, sprintf("DATE\t%s", Sys.Date()))
  lines <- c(lines, sprintf("WINDOWS\t%d", nrow(windows)))
  lines <- c(lines, "")
  lines <- c(lines, "INDEX\tSTART\tEND\tCENTER")
  
  for (i in 1:nrow(windows)) {
    lines <- c(lines, sprintf("%d\t%.2f\t%.2f\t%.2f",
                             i,
                             windows$window_start[i],
                             windows$window_end[i],
                             windows$center_mz[i]))
  }
  
  return(lines)
}

#' Generate analysis report
#' 
#' @param original_data Original DIA-NN data
#' @param optimized_windows Optimization results
#' @param instrument_config Instrument configuration
#' @return List with analysis report
generate_analysis_report <- function(original_data, optimized_windows, instrument_config = NULL) {
  
  # Calculate current DPPP if instrument config available
  current_dppp_stats <- NULL
  if (!is.null(instrument_config)) {
    typical_windows <- 50
    cycle_time <- calculate_cycle_time(
      typical_windows,
      instrument_config$ms1_time,
      instrument_config$ms2_time,
      instrument_config$cycle_calculation
    )
    
    cycle_time_ms <- calculate_cycle_time(
      typical_windows,
      instrument_config$ms1_time,
      instrument_config$ms2_time,
      instrument_config$cycle_calculation
    ) * 1000
    
    dppp_values <- calculate_dppp_distribution(
      original_data,
      cycle_time_ms
    )
    
    current_dppp_stats <- list(
      mean = mean(dppp_values),
      median = median(dppp_values),
      sd = sd(dppp_values)
    )
  }
  
  report <- list(
    current_status = list(
      total_precursors = nrow(original_data),
      fwhm_statistics = list(
        mean = mean(original_data$FWHM),
        median = median(original_data$FWHM),
        sd = sd(original_data$FWHM),
        mode = calculate_mode(original_data$FWHM)
      ),
      current_dppp = current_dppp_stats,
      rt_range = list(
        min = min(original_data$RT.Start),
        max = max(original_data$RT.Stop)
      ),
      mz_range = list(
        min = min(original_data$Precursor.Mz),
        max = max(original_data$Precursor.Mz)
      )
    ),
    optimization_results = list(
      optimized_windows = optimized_windows$n_windows,
      optimized_dppp = optimized_windows$dppp,
      cycle_time = optimized_windows$cycle_time,
      scan_rate = optimized_windows$scan_rate,
      coverage_pct = optimized_windows$validation$coverage_pct,
      expected_improvement = calculate_improvement_metrics(
        current_dppp_stats,
        optimized_windows$dppp
      )
    ),
    warnings = optimized_windows$validation$warnings
  )
  
  return(report)
}

#' Calculate improvement metrics
#' 
#' @param current_dppp Current DPPP statistics
#' @param optimized_dppp Optimized DPPP value
#' @return List with improvement metrics
calculate_improvement_metrics <- function(current_dppp, optimized_dppp) {
  
  if (is.null(current_dppp)) {
    return(list(
      dppp_improvement = NA,
      message = "Cannot calculate improvement without current DPPP"
    ))
  }
  
  improvement <- list(
    dppp_improvement = optimized_dppp - current_dppp$mean,
    dppp_improvement_pct = 100 * (optimized_dppp - current_dppp$mean) / current_dppp$mean,
    target_achievement = optimized_dppp / 1.25 * 100
  )
  
  return(improvement)
}

#' Print analysis report
#' 
#' @param report Analysis report list
print_report <- function(report) {
  
  cat("\n===============================================\n")
  cat("        DIA WINDOW OPTIMIZATION REPORT         \n")
  cat("===============================================\n\n")
  
  cat("CURRENT STATUS:\n")
  cat("---------------\n")
  cat(sprintf("Total precursors: %d\n", report$current_status$total_precursors))
  cat(sprintf("m/z range: %.1f - %.1f\n", 
              report$current_status$mz_range$min,
              report$current_status$mz_range$max))
  cat(sprintf("RT range: %.1f - %.1f minutes\n",
              report$current_status$rt_range$min,
              report$current_status$rt_range$max))
  cat(sprintf("FWHM: mean=%.2f, median=%.2f minutes\n",
              report$current_status$fwhm_statistics$mean,
              report$current_status$fwhm_statistics$median))
  
  if (!is.null(report$current_status$current_dppp)) {
    cat(sprintf("Current DPPP: mean=%.2f, median=%.2f\n",
                report$current_status$current_dppp$mean,
                report$current_status$current_dppp$median))
  }
  
  cat("\nOPTIMIZATION RESULTS:\n")
  cat("--------------------\n")
  cat(sprintf("Optimized windows: %d\n", report$optimization_results$optimized_windows))
  cat(sprintf("Optimized DPPP: %.2f\n", report$optimization_results$optimized_dppp))
  cat(sprintf("Cycle time: %.2f seconds\n", report$optimization_results$cycle_time))
  cat(sprintf("Scan rate: %.1f Hz\n", report$optimization_results$scan_rate))
  cat(sprintf("Coverage: %.1f%%\n", report$optimization_results$coverage_pct))
  
  if (!is.null(report$optimization_results$expected_improvement$dppp_improvement)) {
    cat(sprintf("DPPP improvement: %.2f (%.1f%%)\n",
                report$optimization_results$expected_improvement$dppp_improvement,
                report$optimization_results$expected_improvement$dppp_improvement_pct))
  }
  
  if (length(report$warnings) > 0) {
    cat("\nWARNINGS:\n")
    cat("---------\n")
    for (warning in report$warnings) {
      cat(sprintf("⚠ %s\n", warning))
    }
  }
  
  cat("\n===============================================\n")
}