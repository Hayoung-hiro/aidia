# raw_metadata_extractor.R - Raw file metadata extraction using rawrr package

library(rawrr)
library(rjson)
library(dplyr)

#' Extract metadata from raw file using header information
#'
#' @param raw_file_path Path to raw file
#' @param detailed_scan_analysis Whether to perform detailed scan analysis (default: FALSE for speed)
#' @return List with extracted metadata
extract_raw_metadata <- function(raw_file_path, detailed_scan_analysis = FALSE) {

  if (!file.exists(raw_file_path)) {
    warning(sprintf("Raw file not found: %s", raw_file_path))
    return(NULL)
  }

  analysis_type <- if (detailed_scan_analysis) "detailed" else "fast"
  cat(sprintf("Extracting metadata (%s) from: %s\n", analysis_type, basename(raw_file_path)))

  # Check if rawrr can read the file
  if (!rawrr::isRawFileReaderAvailable()) {
    stop("Thermo RawFileReader not available. Please install rawrr dependencies.")
  }

  tryCatch({
    # Extract file header
    file_header <- rawrr::readFileHeader(raw_file_path)

    # Calculate scan statistics from header (fast method)
    total_scans <- file_header$NumberOfSpectra
    ms2_scans <- ifelse(is.null(file_header$`Number of MS2 spectra`), 0, file_header$`Number of MS2 spectra`)
    ms1_scans <- total_scans - ms2_scans

    # Estimate scan timing from header information
    duration_minutes <- as.numeric(difftime(file_header$EndTime, file_header$StartTime, units = "mins"))
    estimated_scan_rate <- total_scans / (duration_minutes * 60)  # scans per second

    # Estimate cycle time if we have both MS1 and MS2 scans
    estimated_cycle_time <- if (ms1_scans > 0 && ms2_scans > 0) {
      (duration_minutes * 60) / ms1_scans  # seconds per cycle
    } else {
      NA
    }

    # Create scan cycle stats (maintain compatibility with existing structure)
    scan_cycle_stats <- if (!is.na(estimated_cycle_time)) {
      list(
        # Legacy field names for compatibility
        avg_cycle_time = estimated_cycle_time,
        scan_rate = estimated_scan_rate,
        ms2_per_cycle = ms2_scans / ms1_scans,
        total_duration = duration_minutes * 60,
        # Additional fields for enhanced functionality
        estimated_cycle_time = estimated_cycle_time,
        estimated_scan_rate = estimated_scan_rate,
        avg_scan_interval = estimated_cycle_time / (ms2_scans / ms1_scans + 1),
        median_scan_interval = estimated_cycle_time / (ms2_scans / ms1_scans + 1),
        method = if (detailed_scan_analysis) "header_with_scan_analysis" else "header_estimated"
      )
    } else {
      NULL
    }

    # Optional detailed scan analysis (slow but accurate)
    detailed_info <- if (detailed_scan_analysis) {
      perform_detailed_scan_analysis(raw_file_path)
    } else {
      NULL
    }

    # Compile metadata (base structure identical to original)
    metadata <- list(
      file_info = list(
        file_path = raw_file_path,
        file_name = basename(raw_file_path),
        file_size = file.size(raw_file_path),
        creation_date = file_header$CreationDate,
        acquisition_date = file_header$AcquisitionDate
      ),
      instrument = list(
        model = file_header$InstrumentModel,
        serial_number = file_header$SerialNumber,
        software_version = file_header$SoftwareVersion,
        firmware_version = ifelse(is.null(file_header$FirmwareVersion), "Unknown", file_header$FirmwareVersion)
      ),
      acquisition = list(
        start_time = file_header$StartTime,
        end_time = file_header$EndTime,
        duration_minutes = duration_minutes,
        number_of_spectra = file_header$NumberOfSpectra,
        mass_resolution = ifelse(is.null(file_header$MassResolution), "Unknown", file_header$MassResolution)
      ),
      scan_statistics = list(
        total_scans = total_scans,
        ms1_scans = ms1_scans,
        ms2_scans = ms2_scans,
        scan_range = c(1, total_scans),  # Estimated range
        rt_range_minutes = c(0, duration_minutes),  # From start to end time
        data_source = if (detailed_scan_analysis) "header_plus_detailed" else "header_calculated"
      ),
      scan_cycle_stats = scan_cycle_stats,
      method_info = list(
        has_method = FALSE,  # Method extraction not available
        method_count = 0,
        note = "Method extraction skipped for performance"
      ),
      extraction_timestamp = Sys.time()
    )

    # Add detailed scan info only when detailed analysis is performed
    if (detailed_scan_analysis && !is.null(detailed_info)) {
      metadata$detailed_scan_info <- detailed_info
    }

    # Print summary
    print_extraction_summary(metadata, analysis_type)

    return(metadata)

  }, error = function(e) {
    warning(sprintf("Failed to extract metadata from %s: %s", basename(raw_file_path), e$message))
    return(NULL)
  })
}

#' Perform detailed scan analysis (optional, slower)
#'
#' @param raw_file_path Path to raw file
#' @return List with detailed scan information
perform_detailed_scan_analysis <- function(raw_file_path) {

  cat("  Performing detailed scan analysis (this may take longer)...\n")

  tryCatch({
    # Get scan index for detailed analysis
    scan_info <- rawrr::readIndex(raw_file_path)

    if (nrow(scan_info) == 0) {
      return(NULL)
    }

    # Calculate actual scan statistics
    ms1_scans <- scan_info[scan_info$MSOrder == 1, ]
    ms2_scans <- scan_info[scan_info$MSOrder == 2, ]

    # Detailed timing analysis
    detailed_stats <- if (nrow(scan_info) > 1) {
      calculate_detailed_scan_stats(scan_info)
    } else {
      NULL
    }

    return(list(
      actual_rt_range = c(min(scan_info$rtinseconds) / 60, max(scan_info$rtinseconds) / 60),
      actual_scan_range = c(min(scan_info$scan), max(scan_info$scan)),
      scan_intervals = detailed_stats,
      total_scans_verified = nrow(scan_info),
      ms1_scans_verified = nrow(ms1_scans),
      ms2_scans_verified = nrow(ms2_scans)
    ))

  }, error = function(e) {
    warning(sprintf("Detailed scan analysis failed: %s", e$message))
    return(NULL)
  })
}

#' Calculate detailed scan statistics
#'
#' @param scan_info Scan index data frame
#' @return List with detailed statistics
calculate_detailed_scan_stats <- function(scan_info) {

  if (nrow(scan_info) < 2) {
    return(NULL)
  }

  # Calculate scan intervals
  scan_intervals <- diff(scan_info$rtinseconds)

  # MS1 cycle analysis
  ms1_scans <- scan_info[scan_info$MSOrder == 1, ]

  if (nrow(ms1_scans) > 1) {
    cycle_times <- diff(ms1_scans$rtinseconds)
    avg_cycle_time <- mean(cycle_times)
    ms2_per_cycle <- nrow(scan_info[scan_info$MSOrder == 2, ]) / nrow(ms1_scans)
  } else {
    avg_cycle_time <- NA
    ms2_per_cycle <- NA
  }

  # Overall timing
  total_time <- max(scan_info$rtinseconds) - min(scan_info$rtinseconds)
  scan_rate <- nrow(scan_info) / total_time

  return(list(
    avg_scan_interval = mean(scan_intervals),
    median_scan_interval = median(scan_intervals),
    avg_cycle_time = avg_cycle_time,
    ms2_per_cycle = ms2_per_cycle,
    scan_rate = scan_rate,
    total_duration = total_time,
    cycle_time_variability = if(!is.na(avg_cycle_time)) sd(cycle_times) else NA
  ))
}

#' Print extraction summary
#'
#' @param metadata Extracted metadata
#' @param analysis_type Type of analysis performed
print_extraction_summary <- function(metadata, analysis_type) {

  cat(sprintf("  • Instrument: %s (S/N: %s)\n",
              metadata$instrument$model,
              metadata$instrument$serial_number))
  cat(sprintf("  • Duration: %.1f minutes\n", metadata$acquisition$duration_minutes))
  cat(sprintf("  • Total scans: %d (MS1: %d, MS2: %d)\n",
              metadata$scan_statistics$total_scans,
              metadata$scan_statistics$ms1_scans,
              metadata$scan_statistics$ms2_scans))

  if (!is.null(metadata$scan_cycle_stats)) {
    cat(sprintf("  • Estimated cycle time: %.2f seconds\n", metadata$scan_cycle_stats$estimated_cycle_time))
    cat(sprintf("  • Estimated scan rate: %.1f Hz\n", metadata$scan_cycle_stats$estimated_scan_rate))
    cat(sprintf("  • MS2 per cycle: %.1f\n", metadata$scan_cycle_stats$ms2_per_cycle))
  }

  cat(sprintf("  • Analysis type: %s\n", analysis_type))

  # Additional info for detailed analysis
  if (!is.null(metadata$detailed_scan_info)) {
    cat(sprintf("  • Verified scan counts match header: %s\n",
                metadata$detailed_scan_info$total_scans_verified == metadata$scan_statistics$total_scans))
  }
}

#' Process multiple raw files in a directory
#'
#' @param raw_file_dir Directory containing raw files
#' @param pattern File pattern to match (default: "*.raw")
#' @param save_json Whether to save individual JSON files
#' @param json_output_dir Directory for JSON output files
#' @param detailed_analysis Whether to perform detailed scan analysis
#' @return List of metadata from all files
process_raw_files_batch <- function(raw_file_dir,
                                   pattern = "\\.raw$",
                                   save_json = TRUE,
                                   json_output_dir = "metadata",
                                   detailed_analysis = FALSE) {

  if (!dir.exists(raw_file_dir)) {
    stop(sprintf("Directory not found: %s", raw_file_dir))
  }

  # Find raw files
  raw_files <- list.files(raw_file_dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)

  if (length(raw_files) == 0) {
    stop(sprintf("No raw files found in: %s", raw_file_dir))
  }

  analysis_mode <- if (detailed_analysis) "detailed" else "fast"
  cat(sprintf("🔬 Processing %d raw files (%s mode)...\n", length(raw_files), analysis_mode))

  # Create output directory if needed
  if (save_json && !dir.exists(json_output_dir)) {
    dir.create(json_output_dir, recursive = TRUE)
  }

  # Process each file
  all_metadata <- list()
  start_time <- Sys.time()

  for (i in seq_along(raw_files)) {
    raw_file <- raw_files[i]
    file_name <- tools::file_path_sans_ext(basename(raw_file))

    cat(sprintf("\n[%d/%d] Processing: %s\n", i, length(raw_files), basename(raw_file)))

    # Extract metadata with specified analysis level
    metadata <- extract_raw_metadata(raw_file, detailed_scan_analysis = detailed_analysis)

    if (!is.null(metadata)) {
      all_metadata[[file_name]] <- metadata

      # Save individual JSON file if requested
      if (save_json) {
        json_file <- file.path(json_output_dir, paste0(file_name, "_metadata.json"))
        metadata_json <- rjson::toJSON(metadata, indent = 2)
        cat(metadata_json, file = json_file)
        cat(sprintf("  JSON saved: %s\n", json_file))
      }
    }
  }

  # Save combined metadata
  if (save_json && length(all_metadata) > 0) {
    combined_filename <- if (detailed_analysis) "combined_metadata_detailed.json" else "combined_metadata.json"
    combined_file <- file.path(json_output_dir, combined_filename)
    combined_json <- rjson::toJSON(all_metadata, indent = 2)
    cat(combined_json, file = combined_file)
    cat(sprintf("\nCombined metadata saved: %s\n", combined_file))
  }

  end_time <- Sys.time()
  total_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

  cat(sprintf("\n✅ Processing complete!\n"))
  cat(sprintf("   • Processed %d files successfully\n", length(all_metadata)))
  cat(sprintf("   • Total time: %.1f seconds (%.2f sec/file)\n", total_time, total_time/length(raw_files)))
  cat(sprintf("   • Analysis mode: %s\n", analysis_mode))

  return(all_metadata)
}

#' Get metadata summary for all processed files (updated for new structure)
#'
#' @param metadata_list List of metadata from process_raw_files_batch
#' @return Data frame with summary statistics
get_metadata_summary <- function(metadata_list) {

  if (length(metadata_list) == 0) {
    return(data.frame())
  }

  # Extract key metrics from each file (using original field names for compatibility)
  summary_data <- data.frame(
    file_name = character(),
    instrument_model = character(),
    duration_minutes = numeric(),
    total_scans = integer(),
    ms1_scans = integer(),
    ms2_scans = integer(),
    avg_cycle_time = numeric(),
    scan_rate = numeric(),
    stringsAsFactors = FALSE
  )

  for (file_name in names(metadata_list)) {
    meta <- metadata_list[[file_name]]

    # Extract cycle stats using original field names for compatibility
    cycle_stats <- meta$scan_cycle_stats
    avg_cycle_time <- if (!is.null(cycle_stats)) cycle_stats$avg_cycle_time else NA
    scan_rate <- if (!is.null(cycle_stats)) cycle_stats$scan_rate else NA

    summary_data <- rbind(summary_data, data.frame(
      file_name = file_name,
      instrument_model = meta$instrument$model,
      duration_minutes = meta$acquisition$duration_minutes,
      total_scans = meta$scan_statistics$total_scans,
      ms1_scans = meta$scan_statistics$ms1_scans,
      ms2_scans = meta$scan_statistics$ms2_scans,
      avg_cycle_time = avg_cycle_time,
      scan_rate = scan_rate,
      stringsAsFactors = FALSE
    ))
  }

  return(summary_data)
}

#' Extract scan-level timing information for FWHM analysis
#'
#' @param raw_file_path Path to raw file
#' @param rt_window_minutes RT window around target RT (default: ±2 minutes)
#' @param target_rt_minutes Target RT for focused analysis (optional)
#' @return Data frame with scan timing details
extract_scan_timing_details <- function(raw_file_path,
                                       rt_window_minutes = 2,
                                       target_rt_minutes = NULL) {

  if (!file.exists(raw_file_path)) {
    warning(sprintf("Raw file not found: %s", raw_file_path))
    return(NULL)
  }

  cat(sprintf("Extracting detailed scan timing from: %s\n", basename(raw_file_path)))

  tryCatch({
    # Get scan index
    scan_index <- rawrr::readIndex(raw_file_path)

    # Convert RT to minutes
    scan_index$RT_minutes <- scan_index$rtinseconds / 60

    # Filter by RT window if specified
    if (!is.null(target_rt_minutes)) {
      rt_min <- target_rt_minutes - rt_window_minutes
      rt_max <- target_rt_minutes + rt_window_minutes
      scan_index <- scan_index[scan_index$RT_minutes >= rt_min & scan_index$RT_minutes <= rt_max, ]
    }

    # Calculate scan intervals
    if (nrow(scan_index) > 1) {
      scan_index$scan_interval <- c(NA, diff(scan_index$rtinseconds))
      scan_index$cycle_position <- NA

      # Identify cycle positions for MS2 scans
      ms1_positions <- which(scan_index$MSOrder == 1)

      for (i in seq_along(ms1_positions)) {
        start_pos <- ms1_positions[i]
        end_pos <- ifelse(i < length(ms1_positions), ms1_positions[i + 1] - 1, nrow(scan_index))

        cycle_scans <- start_pos:end_pos
        scan_index$cycle_position[cycle_scans] <- seq_along(cycle_scans) - 1  # 0-indexed within cycle
      }
    }

    return(scan_index)

  }, error = function(e) {
    warning(sprintf("Failed to extract scan timing from %s: %s", basename(raw_file_path), e$message))
    return(NULL)
  })
}

#' Check if rawrr is properly configured
#'
#' @return Boolean indicating if rawrr can read files
check_rawrr_status <- function() {

  cat("Checking rawrr configuration...\n")

  # Check if RawFileReader is available
  if (rawrr::isRawFileReaderAvailable()) {
    cat("✅ Thermo RawFileReader is available\n")

    # Get version info if possible
    tryCatch({
      version_info <- rawrr::rawrrVersion()
      cat(sprintf("  rawrr version: %s\n", version_info))
    }, error = function(e) {
      cat("  rawrr version: Unknown\n")
    })

    return(TRUE)
  } else {
    cat("❌ Thermo RawFileReader is not available\n")
    cat("   Please install the necessary dependencies:\n")
    cat("   1. Install Thermo MSFileReader\n")
    cat("   2. Ensure .NET Framework is available\n")
    cat("   3. Restart R session\n")
    return(FALSE)
  }
}

# Legacy function aliases for backward compatibility
extract_raw_metadata_fast <- function(raw_file_path) {
  extract_raw_metadata(raw_file_path, detailed_scan_analysis = FALSE)
}

process_raw_files_batch_fast <- function(raw_file_dir, pattern = "\\.raw$",
                                        save_json = TRUE, json_output_dir = "metadata") {
  process_raw_files_batch(raw_file_dir, pattern, save_json, json_output_dir, detailed_analysis = FALSE)
}