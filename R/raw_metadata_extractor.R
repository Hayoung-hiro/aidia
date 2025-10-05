# raw_metadata_extractor.R - Raw file metadata extraction using rawrr package

library(rawrr)
library(rjson)
library(dplyr)

# #' Extract metadata from Thermo raw file to JSON format
# #'
# #' @param input_raw_file Path to Thermo raw file
# #' @param output_json_file Path for output JSON file (default: temp file)
# #' @return Path to created JSON file
# .rawrrHeaderJson <- function(input_raw_file,
#                              output_json_file = tempfile(fileext = ".json")) {

#   # Check if raw file exists
#   if (!file.exists(input_raw_file)) {
#     stop(sprintf("Raw file not found: %s", input_raw_file))
#   }

#   # Extract header information
#   header_info <- input_raw_file |>
#     rawrr::readFileHeader() |>
#     rjson::toJSON(indent = 1)

#   # Write to file
#   cat(header_info, file = output_json_file)

#   cat(sprintf("Metadata extracted to: %s\n", output_json_file))
#   return(output_json_file)
# }

#' Extract metadata from raw file 
#'
#' @param raw_file_path Path to raw file
#' @return List with extracted metadata
extract_raw_metadata_fast <- function(raw_file_path) {

  if (!file.exists(raw_file_path)) {
    warning(sprintf("Raw file not found: %s", raw_file_path))
    return(NULL)
  }

  cat(sprintf("Fast extracting metadata from: %s\n", basename(raw_file_path)))

  # Check if rawrr can read the file
  if (!rawrr::isRawFileReaderAvailable()) {
    stop("Thermo RawFileReader not available. Please install rawrr dependencies.")
  }

  tryCatch({
    # Extract file header only
    file_header <- rawrr::readFileHeader(raw_file_path)

    # Calculate scan statistics from header (avoid readIndex for performance)
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

    # Create estimated scan cycle stats
    scan_cycle_stats <- if (!is.na(estimated_cycle_time)) {
      list(
        estimated_cycle_time = estimated_cycle_time,
        estimated_scan_rate = estimated_scan_rate,
        ms2_per_cycle = ms2_scans / ms1_scans,
        total_duration = duration_minutes * 60,
        method = "header_estimated"
      )
    } else {
      NULL
    }

    # Compile metadata
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
        data_source = "header_calculated_fast"
      ),
      scan_cycle_stats = scan_cycle_stats,
      method_info = list(
        has_method = FALSE,  # Method extraction not available
        method_count = 0,
        note = "Method extraction skipped for performance"
      ),
      extraction_timestamp = Sys.time()
    )

    cat(sprintf("  • Instrument: %s (S/N: %s)\n",
                metadata$instrument$model,
                metadata$instrument$serial_number))
    cat(sprintf("  • Duration: %.1f minutes\n", metadata$acquisition$duration_minutes))
    cat(sprintf("  • Total scans: %d (MS1: %d, MS2: %d)\n",
                metadata$scan_statistics$total_scans,
                metadata$scan_statistics$ms1_scans,
                metadata$scan_statistics$ms2_scans))

    if (!is.null(scan_cycle_stats)) {
      cat(sprintf("  • Estimated cycle time: %.2f seconds\n", scan_cycle_stats$estimated_cycle_time))
      cat(sprintf("  • Estimated scan rate: %.1f Hz\n", scan_cycle_stats$estimated_scan_rate))
      cat(sprintf("  • MS2 per cycle: %.1f\n", scan_cycle_stats$ms2_per_cycle))
    }

    cat(sprintf("  • Data source: %s (fast extraction)\n", metadata$scan_statistics$data_source))

    return(metadata)

  }, error = function(e) {
    warning(sprintf("Failed to extract metadata from %s: %s", basename(raw_file_path), e$message))
    return(NULL)
  })
}

#' Extract comprehensive metadata from raw file (original version with readIndex)
#'
#' @param raw_file_path Path to raw file
#' @return List with extracted metadata
extract_raw_metadata <- function(raw_file_path) {

  if (!file.exists(raw_file_path)) {
    warning(sprintf("Raw file not found: %s", raw_file_path))
    return(NULL)
  }

  cat(sprintf("Extracting metadata from: %s\n", basename(raw_file_path)))

  # Check if rawrr can read the file
  if (!rawrr::isRawFileReaderAvailable()) {
    stop("Thermo RawFileReader not available. Please install rawrr dependencies.")
  }

  tryCatch({
    # Extract file header
    file_header <- rawrr::readFileHeader(raw_file_path)

    # Calculate scan statistics from header (avoid readIndex for performance)
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

    # Create estimated scan cycle stats
    scan_cycle_stats <- if (!is.na(estimated_cycle_time)) {
      list(
        estimated_cycle_time = estimated_cycle_time,
        estimated_scan_rate = estimated_scan_rate,
        ms2_per_cycle = ms2_scans / ms1_scans,
        total_duration = duration_minutes * 60,
        method = "header_estimated"
      )
    } else {
      NULL
    }

    # Compile metadata
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
        duration_minutes = as.numeric(difftime(file_header$EndTime, file_header$StartTime, units = "mins")),
        number_of_spectra = file_header$NumberOfSpectra,
        mass_resolution = ifelse(is.null(file_header$MassResolution), "Unknown", file_header$MassResolution)
      ),
      scan_statistics = list(
        total_scans = total_scans,
        ms1_scans = ms1_scans,
        ms2_scans = ms2_scans,
        scan_range = c(1, total_scans),  # Estimated range
        rt_range_minutes = c(0, duration_minutes),  # From start to end time
        data_source = "header_calculated"
      ),
      scan_cycle_stats = scan_cycle_stats,
      method_info = list(
        has_method = FALSE,  # Method extraction not available
        method_count = 0,
        note = "Method extraction skipped for performance"
      ),
      extraction_timestamp = Sys.time()
    )

    cat(sprintf("  • Instrument: %s (S/N: %s)\n",
                metadata$instrument$model,
                metadata$instrument$serial_number))
    cat(sprintf("  • Duration: %.1f minutes\n", metadata$acquisition$duration_minutes))
    cat(sprintf("  • Total scans: %d (MS1: %d, MS2: %d)\n",
                metadata$scan_statistics$total_scans,
                metadata$scan_statistics$ms1_scans,
                metadata$scan_statistics$ms2_scans))

    if (!is.null(scan_cycle_stats)) {
      cat(sprintf("  • Estimated cycle time: %.2f seconds\n", scan_cycle_stats$estimated_cycle_time))
      cat(sprintf("  • Estimated scan rate: %.1f Hz\n", scan_cycle_stats$estimated_scan_rate))
      cat(sprintf("  • MS2 per cycle: %.1f\n", scan_cycle_stats$ms2_per_cycle))
    }

    cat(sprintf("  • Data source: %s (fast extraction)\n", metadata$scan_statistics$data_source))

    return(metadata)

  }, error = function(e) {
    warning(sprintf("Failed to extract metadata from %s: %s", basename(raw_file_path), e$message))
    return(NULL)
  })
}

#' Calculate scan cycle statistics from scan index
#'
#' @param scan_info Scan index data frame from rawrr::readIndex
#' @return List with cycle statistics
calculate_scan_cycle_stats <- function(scan_info) {

  if (nrow(scan_info) < 2) {
    return(NULL)
  }

  # Calculate scan intervals
  scan_intervals <- diff(scan_info$rtinseconds)

  # Identify MS1 scans for cycle calculation
  ms1_scans <- scan_info[scan_info$MSOrder == 1, ]

  if (nrow(ms1_scans) > 1) {
    # Calculate cycle times (time between MS1 scans)
    cycle_times <- diff(ms1_scans$rtinseconds)
    avg_cycle_time <- mean(cycle_times)

    # Calculate number of MS2 scans per cycle
    ms2_per_cycle <- nrow(scan_info[scan_info$MSOrder == 2, ]) / nrow(ms1_scans)
  } else {
    avg_cycle_time <- NA
    ms2_per_cycle <- NA
  }

  # Overall scan rate
  total_time <- max(scan_info$rtinseconds) - min(scan_info$rtinseconds)
  scan_rate <- nrow(scan_info) / total_time

  return(list(
    avg_scan_interval = mean(scan_intervals),
    median_scan_interval = median(scan_intervals),
    avg_cycle_time = avg_cycle_time,
    ms2_per_cycle = ms2_per_cycle,
    scan_rate = scan_rate,
    total_duration = total_time
  ))
}

#' Process multiple raw files in a directory (fast version using header only)
#'
#' @param raw_file_dir Directory containing raw files
#' @param pattern File pattern to match (default: "*.raw")
#' @param save_json Whether to save individual JSON files
#' @param json_output_dir Directory for JSON output files
#' @return List of metadata from all files
process_raw_files_batch_fast <- function(raw_file_dir,
                                         pattern = "\\.raw$",
                                         save_json = TRUE,
                                         json_output_dir = "metadata") {

  if (!dir.exists(raw_file_dir)) {
    stop(sprintf("Directory not found: %s", raw_file_dir))
  }

  # Find raw files
  raw_files <- list.files(raw_file_dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)

  if (length(raw_files) == 0) {
    stop(sprintf("No raw files found in: %s", raw_file_dir))
  }

  cat(sprintf("🚀 Fast processing %d raw files (header only)...\n", length(raw_files)))

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

    # Extract metadata using fast method (header only)
    metadata <- extract_raw_metadata_fast(raw_file)

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
    combined_file <- file.path(json_output_dir, "combined_metadata_fast.json")
    combined_json <- rjson::toJSON(all_metadata, indent = 2)
    cat(combined_json, file = combined_file)
    cat(sprintf("\nCombined metadata saved: %s\n", combined_file))
  }

  end_time <- Sys.time()
  total_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

  cat(sprintf("\n✅ Fast processing complete!\n"))
  cat(sprintf("   • Processed %d files successfully\n", length(all_metadata)))
  cat(sprintf("   • Total time: %.1f seconds (%.2f sec/file)\n", total_time, total_time/length(raw_files)))
  cat(sprintf("   • Data source: header_calculated_fast\n"))

  return(all_metadata)
}

#' Process multiple raw files in a directory (original version with readIndex)
#'
#' @param raw_file_dir Directory containing raw files
#' @param pattern File pattern to match (default: "*.raw")
#' @param save_json Whether to save individual JSON files
#' @param json_output_dir Directory for JSON output files
#' @return List of metadata from all files
process_raw_files_batch <- function(raw_file_dir,
                                   pattern = "\\.raw$",
                                   save_json = TRUE,
                                   json_output_dir = "metadata") {

  if (!dir.exists(raw_file_dir)) {
    stop(sprintf("Directory not found: %s", raw_file_dir))
  }

  # Find raw files
  raw_files <- list.files(raw_file_dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)

  if (length(raw_files) == 0) {
    stop(sprintf("No raw files found in: %s", raw_file_dir))
  }

  cat(sprintf("Found %d raw files to process\n", length(raw_files)))

  # Create output directory if needed
  if (save_json && !dir.exists(json_output_dir)) {
    dir.create(json_output_dir, recursive = TRUE)
  }

  # Process each file
  all_metadata <- list()

  for (i in seq_along(raw_files)) {
    raw_file <- raw_files[i]
    file_name <- tools::file_path_sans_ext(basename(raw_file))

    cat(sprintf("\n[%d/%d] Processing: %s\n", i, length(raw_files), basename(raw_file)))

    # Extract metadata
    metadata <- extract_raw_metadata(raw_file)

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
    combined_file <- file.path(json_output_dir, "combined_metadata.json")
    combined_json <- rjson::toJSON(all_metadata, indent = 2)
    cat(combined_json, file = combined_file)
    cat(sprintf("\nCombined metadata saved: %s\n", combined_file))
  }

  cat(sprintf("\nProcessed %d files successfully\n", length(all_metadata)))

  return(all_metadata)
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

#' Get metadata summary for all processed files
#'
#' @param metadata_list List of metadata from process_raw_files_batch
#' @return Data frame with summary statistics
get_metadata_summary <- function(metadata_list) {

  if (length(metadata_list) == 0) {
    return(data.frame())
  }

  # Extract key metrics from each file
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

    summary_data <- rbind(summary_data, data.frame(
      file_name = file_name,
      instrument_model = meta$instrument$model,
      duration_minutes = meta$acquisition$duration_minutes,
      total_scans = meta$scan_statistics$total_scans,
      ms1_scans = meta$scan_statistics$ms1_scans,
      ms2_scans = meta$scan_statistics$ms2_scans,
      avg_cycle_time = ifelse(is.null(meta$scan_cycle_stats$avg_cycle_time), NA, meta$scan_cycle_stats$avg_cycle_time),
      scan_rate = ifelse(is.null(meta$scan_cycle_stats$scan_rate), NA, meta$scan_cycle_stats$scan_rate),
      stringsAsFactors = FALSE
    ))
  }

  return(summary_data)
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