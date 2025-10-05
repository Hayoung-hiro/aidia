# data_loader.R - Data loading and preprocessing functions for DIA-NN output
#
# Main Workflow:
# 1. Load DIA-NN output (parquet, TSV, CSV)
# 2. Validate required columns (RT.Start, RT.Stop, Precursor.Mz, FWHM)
# 3. Apply DIA-NN quality filters (Q-values, protein groups, etc.)
# 4. Remove duplicate precursors
# 5. Return clean dataset ready for DPPP optimization
#
# Requirements:
# - DIA-NN version 2.2 or later (for FWHM column in main report)

library(arrow)
library(dplyr)
library(tidyr)

#' Load DIA-NN output data from various formats
#'
#' @param file_path Path to DIA-NN output file (parquet, tsv, or csv)
#' @param rt_min Minimum RT in minutes (default: 0)
#' @param rt_max Maximum RT in minutes (NULL for max in data)
#' @param apply_quality_filters Apply DIA-NN quality filters (default: TRUE)
#' @param ... Additional arguments passed to filter_diann_quality()
#' @return Data frame with processed DIA-NN data
load_diann_data <- function(file_path, rt_min = 0, rt_max = NULL,
                           apply_quality_filters = TRUE, ...) {
  
  # Detect file format and read accordingly
  file_ext <- tolower(tools::file_ext(file_path))
  
  if (!file.exists(file_path)) {
    stop(sprintf("File not found: %s", file_path))
  }
  
  # Read file based on extension
  if (file_ext == "parquet") {
    cat("Loading parquet file...\n")
    data <- arrow::read_parquet(file_path)
  } else if (file_ext == "tsv") {
    cat("Loading TSV file...\n")
    data <- read.delim(file_path, stringsAsFactors = FALSE)
  } else if (file_ext == "csv") {
    cat("Loading CSV file...\n")
    data <- read.csv(file_path, stringsAsFactors = FALSE)
  } else {
    stop("Unsupported file format. Use parquet, tsv, or csv.")
  }
  
  # Check for required columns
  required_cols <- c("RT.Start", "RT.Stop", "Precursor.Mz", "FWHM")
  missing_cols <- setdiff(required_cols, names(data))
  
  if (length(missing_cols) > 0) {
    # Try alternative column names
    alt_names <- list(
      "RT.Start" = c("RT", "Retention.Time", "RT_Start"),
      "RT.Stop" = c("RT_Stop", "RT.End", "RT_End"),
      "Precursor.Mz" = c("Precursor.MZ", "Precursor", "m/z", "mz"),
      "FWHM" = c("FWHM", "Peak.Width", "PeakWidth")
    )
    
    for (col in missing_cols) {
      for (alt in alt_names[[col]]) {
        if (alt %in% names(data)) {
          names(data)[names(data) == alt] <- col
          missing_cols <- setdiff(missing_cols, col)
          break
        }
      }
    }
  }
  
  if (length(missing_cols) > 0) {
    if ("FWHM" %in% missing_cols) {
      stop(sprintf("FWHM column not found in DIA-NN output.\n" +
                  "Please use DIA-NN version 2.2 or later which includes FWHM values in the main report.\n" +
                  "Missing columns: %s", paste(missing_cols, collapse = ", ")))
    } else {
      stop(sprintf("Required columns missing: %s", paste(missing_cols, collapse = ", ")))
    }
  }
  
  # # Calculate FWHM if not present
  # if (!"FWHM" %in% names(data)) {
  #   if ("RT.Stop" %in% names(data) && "RT.Start" %in% names(data)) {
  #     # Estimate FWHM from peak width
  #     data$FWHM <- (data$RT.Stop - data$RT.Start) * 0.5
  #     cat("FWHM estimated from RT.Start and RT.Stop\n")
  #   } else {
  #     # Use default FWHM value
  #     data$FWHM <- 0.5  # 30 seconds default
  #     cat("Using default FWHM of 0.5 minutes (30 seconds)\n")
  #   }
  # }
  
  # # Convert RT to minutes if needed
  # if (max(data$RT.Start, na.rm = TRUE) > 200) {
  #   # Likely in seconds, convert to minutes
  #   cat("Converting RT from seconds to minutes...\n")
  #   data$RT.Start <- data$RT.Start / 60
  #   data$RT.Stop <- data$RT.Stop / 60
  #   if ("FWHM" %in% names(data)) {
  #     data$FWHM <- data$FWHM / 60
  #   }
  # }
  
  # Filter by RT range
  if (!is.null(rt_max)) {
    data <- data %>%
      filter(RT.Start >= rt_min & RT.Start <= rt_max)
  } else {
    data <- data %>%
      filter(RT.Start >= rt_min)
  }
  
  # Remove NA values
  data <- data %>%
    filter(!is.na(Precursor.Mz) & !is.na(RT.Start) & !is.na(FWHM))

  # Apply data validation and quality filtering
  cat("\n=== Data Validation and Quality Control ===\n")
  data <- validate_data(data, apply_quality_filters = apply_quality_filters, ...)

  # Calculate summary statistics
  cat("\n=== Final Data Summary ===\n")
  cat(sprintf("  Total precursors: %d\n", nrow(data)))
  cat(sprintf("  m/z range: %.1f - %.1f\n",
              min(data$Precursor.Mz), max(data$Precursor.Mz)))
  cat(sprintf("  RT range: %.1f - %.1f minutes\n",
              min(data$RT.Start), max(data$RT.Start)))
  cat(sprintf("  Mean FWHM: %.2f minutes (%.1f seconds)\n",
              mean(data$FWHM), mean(data$FWHM) * 60))

  return(data)
}

#' Apply DIA-NN quality filters based on official guidelines
#'
#' @param data Data frame with DIA-NN data
#' @param q_value_threshold Q.Value threshold (default: 0.01)
#' @param lib_q_value_threshold Lib.Q.Value threshold (default: 0.01)
#' @param global_q_value_threshold Global.Q.Value threshold (default: 0.01)
#' @param pg_q_value_threshold PG.Q.Value threshold (default: 0.05)
#' @param quantity_quality_threshold Quantity.Quality threshold (default: 0.5, NULL to skip)
#' @param pg_maxlfq_quality_threshold PG.MaxLFQ.Quality threshold (default: 0.7, NULL to skip)
#' @param channel_q_value_threshold Channel.Q.Value threshold for plexDIA (default: NULL)
#' @param apply_empirical_lib_filter Apply Global Q-value filters (FALSE if using empirical library from same samples)
#' @return Filtered data frame
filter_diann_quality <- function(data,
                                q_value_threshold = 0.01,
                                lib_q_value_threshold = 0.01,
                                global_q_value_threshold = 0.01,
                                pg_q_value_threshold = 0.05,
                                quantity_quality_threshold = 0.5,
                                pg_maxlfq_quality_threshold = 0.7,
                                channel_q_value_threshold = NULL,
                                apply_empirical_lib_filter = TRUE) {

  initial_rows <- nrow(data)
  cat("=== Applying DIA-NN Quality Filters ===\n")
  cat(sprintf("Initial precursors: %d\n", initial_rows))

  # Core Q-value filters (recommended for most cases)

  # 1. Q.Value filter (automatically done by DIA-NN if FDR=1%)
  if ("Q.Value" %in% names(data) && !is.null(q_value_threshold)) {
    before <- nrow(data)
    data <- data %>% filter(Q.Value <= q_value_threshold)
    cat(sprintf("Q.Value <= %.3f: %d -> %d (removed %d)\n",
                q_value_threshold, before, nrow(data), before - nrow(data)))
  }

  # 2. Library Q-value filters
  if ("Lib.Q.Value" %in% names(data) && !is.null(lib_q_value_threshold)) {
    before <- nrow(data)
    data <- data %>% filter(Lib.Q.Value <= lib_q_value_threshold)
    cat(sprintf("Lib.Q.Value <= %.3f: %d -> %d (removed %d)\n",
                lib_q_value_threshold, before, nrow(data), before - nrow(data)))
  }

  # 3. Global Q-value filters (unless using empirical library from same samples)
  if (apply_empirical_lib_filter) {
    if ("Global.Q.Value" %in% names(data) && !is.null(global_q_value_threshold)) {
      before <- nrow(data)
      data <- data %>% filter(Global.Q.Value <= global_q_value_threshold)
      cat(sprintf("Global.Q.Value <= %.3f: %d -> %d (removed %d)\n",
                  global_q_value_threshold, before, nrow(data), before - nrow(data)))
    }
  }

  # 4. Protein group Q-value filters
  for (pg_col in c("Lib.PG.Q.Value", "Global.PG.Q.Value")) {
    if (pg_col %in% names(data) && !is.null(pg_q_value_threshold)) {
      # Apply Global.PG.Q.Value only if not using empirical library
      if (pg_col == "Global.PG.Q.Value" && !apply_empirical_lib_filter) next

      before <- nrow(data)
      data <- data %>% filter(.data[[pg_col]] <= pg_q_value_threshold)
      cat(sprintf("%s <= %.3f: %d -> %d (removed %d)\n",
                  pg_col, pg_q_value_threshold, before, nrow(data), before - nrow(data)))
    }
  }

  # 5. Peptidoform Q-value filters (for Peptidoforms scoring mode)
  for (pep_col in c("Lib.Peptidoform.Q.Value", "Global.Peptidoform.Q.Value")) {
    if (pep_col %in% names(data) && !is.null(global_q_value_threshold)) {
      # Apply Global.Peptidoform.Q.Value only if not using empirical library
      if (pep_col == "Global.Peptidoform.Q.Value" && !apply_empirical_lib_filter) next

      before <- nrow(data)
      data <- data %>% filter(.data[[pep_col]] <= global_q_value_threshold)
      cat(sprintf("%s <= %.3f: %d -> %d (removed %d)\n",
                  pep_col, global_q_value_threshold, before, nrow(data), before - nrow(data)))
    }
  }

  # 6. PG.Q.Value filter (typically 0.01-0.05)
  if ("PG.Q.Value" %in% names(data) && !is.null(pg_q_value_threshold)) {
    before <- nrow(data)
    data <- data %>% filter(PG.Q.Value <= pg_q_value_threshold)
    cat(sprintf("PG.Q.Value <= %.3f: %d -> %d (removed %d)\n",
                pg_q_value_threshold, before, nrow(data), before - nrow(data)))
  }

  # 7. Channel Q-value filter for multiplexed (plexDIA) data
  if ("Channel.Q.Value" %in% names(data) && !is.null(channel_q_value_threshold)) {
    before <- nrow(data)
    data <- data %>% filter(Channel.Q.Value <= channel_q_value_threshold)
    cat(sprintf("Channel.Q.Value <= %.3f: %d -> %d (removed %d)\n",
                channel_q_value_threshold, before, nrow(data), before - nrow(data)))
  }

  # Optional quality filters (for QuantUMS)

  # 8. Quantity Quality filter
  if ("Quantity.Quality" %in% names(data) && !is.null(quantity_quality_threshold)) {
    before <- nrow(data)
    data <- data %>% filter(Quantity.Quality >= quantity_quality_threshold)
    cat(sprintf("Quantity.Quality >= %.1f: %d -> %d (removed %d)\n",
                quantity_quality_threshold, before, nrow(data), before - nrow(data)))
  }

  # 9. PG MaxLFQ Quality filter
  if ("PG.MaxLFQ.Quality" %in% names(data) && !is.null(pg_maxlfq_quality_threshold)) {
    before <- nrow(data)
    data <- data %>% filter(PG.MaxLFQ.Quality >= pg_maxlfq_quality_threshold)
    cat(sprintf("PG.MaxLFQ.Quality >= %.1f: %d -> %d (removed %d)\n",
                pg_maxlfq_quality_threshold, before, nrow(data), before - nrow(data)))
  }

  final_rows <- nrow(data)
  overall_removed <- initial_rows - final_rows

  cat(sprintf("\n=== Quality Filtering Summary ===\n"))
  cat(sprintf("Total removed: %d (%.1f%%)\n",
              overall_removed, 100 * overall_removed / initial_rows))
  cat(sprintf("Final precursors: %d\n", final_rows))

  return(data)
}

#' Validate and clean DIA-NN data
#'
#' @param data Data frame with DIA-NN data
#' @param apply_quality_filters Apply DIA-NN quality filters (default: TRUE)
#' @param ... Additional arguments for filter_diann_quality()
#' @return Cleaned data frame
validate_data <- function(data, apply_quality_filters = TRUE, ...) {

  initial_rows <- nrow(data)

  # Apply DIA-NN quality filters first
  if (apply_quality_filters) {
    data <- filter_diann_quality(data, ...)
  }

  # Remove duplicates based on precursor m/z and RT
  before_dedup <- nrow(data)
  data <- data %>%
    distinct(Precursor.Mz, RT.Start, .keep_all = TRUE)

  if (nrow(data) < before_dedup) {
    cat(sprintf("Removed %d duplicate precursors\n", before_dedup - nrow(data)))
  }

  # Final validation summary
  final_rows <- nrow(data)

  if (final_rows < initial_rows) {
    cat(sprintf("\n=== Overall Validation Summary ===\n"))
    cat(sprintf("Total validation: %d -> %d (%.1f%% retained)\n",
                initial_rows, final_rows,
                100 * final_rows / initial_rows))
  }

  return(data)
}

# #' Load DIA-NN data with optional raw metadata integration
# #'
# #' @param file_path Path to DIA-NN output file
# #' @param rt_min Minimum RT in minutes (default: 0)
# #' @param rt_max Maximum RT in minutes (NULL for max in data)
# #' @param integrate_raw_metadata Whether to integrate raw file metadata
# #' @param raw_file_dir Directory containing raw files
# #' @return Enhanced data frame with optional metadata integration
# load_diann_data_enhanced <- function(file_path, rt_min = 0, rt_max = NULL,
#                                    integrate_raw_metadata = FALSE,
#                                    raw_file_dir = "rawfile") {
#
#   # Load basic DIA-NN data
#   data <- load_diann_data(file_path, rt_min, rt_max)
#
#   # Integrate raw metadata if requested
#   if (integrate_raw_metadata) {
#     cat("\n=== Raw Metadata Integration ===\n")
#
#     # Check if raw file directory exists
#     if (!dir.exists(raw_file_dir)) {
#       cat(sprintf("Raw file directory not found: %s\n", raw_file_dir))
#       cat("Proceeding without metadata integration\n")
#       return(data)
#     }
#
#     # Check rawrr availability
#     if (!rawrr::isRawFileReaderAvailable()) {
#       cat("Thermo RawFileReader not available\n")
#       cat("Proceeding without metadata integration\n")
#       cat("Install rawrr dependencies to enable metadata extraction\n")
#       return(data)
#     }
#
#     # Source required modules
#     source("R/raw_metadata_extractor.R")
#
#     # Extract metadata from raw files
#     raw_metadata <- process_raw_files_batch(
#       raw_file_dir = raw_file_dir,
#       save_json = TRUE,
#       json_output_dir = "metadata"
#     )
#
#     if (length(raw_metadata) > 0) {
#       # Add metadata columns to data
#       data <- add_metadata_to_diann_data(data, raw_metadata)
#       cat("✅ Raw metadata successfully integrated\n")
#     } else {
#       cat("⚠️ No metadata extracted from raw files\n")
#     }
#   }
#
#   return(data)
# }

# #' Add raw file metadata to DIA-NN data
# #'
# #' @param diann_data DIA-NN data frame
# #' @param raw_metadata List of raw file metadata
# #' @return Enhanced DIA-NN data with metadata columns
# add_metadata_to_diann_data <- function(diann_data, raw_metadata) {
#
#   cat("Adding metadata columns to DIA-NN data...\n")
#
#   # Initialize metadata columns
#   diann_data$Raw.File.Name <- NA
#   diann_data$Instrument.Model <- NA
#   diann_data$Serial.Number <- NA
#   diann_data$Scan.Rate.Hz <- NA
#   diann_data$Avg.Cycle.Time.Sec <- NA
#   diann_data$MS2.Per.Cycle <- NA
#   diann_data$Acquisition.Duration.Min <- NA
#   diann_data$Metadata.Available <- FALSE
#   diann_data$FWHM.Confidence <- 1.0  # Default confidence for DIA-NN FWHM
#
#   # Use the first raw file metadata (or implement file matching logic)
#   if (length(raw_metadata) > 0) {
#     primary_metadata <- raw_metadata[[1]]
#     file_name <- names(raw_metadata)[1]
#
#     cat(sprintf("Using metadata from: %s\n", file_name))
#
#     # Add metadata to all rows
#     diann_data$Raw.File.Name <- file_name
#     diann_data$Instrument.Model <- primary_metadata$instrument$model
#     diann_data$Serial.Number <- primary_metadata$instrument$serial_number
#     diann_data$Acquisition.Duration.Min <- primary_metadata$acquisition$duration_minutes
#     diann_data$Metadata.Available <- TRUE
#
#     # Add scan statistics if available
#     if (!is.null(primary_metadata$scan_cycle_stats)) {
#       diann_data$Scan.Rate.Hz <- primary_metadata$scan_cycle_stats$scan_rate
#       diann_data$Avg.Cycle.Time.Sec <- primary_metadata$scan_cycle_stats$avg_cycle_time
#       diann_data$MS2.Per.Cycle <- primary_metadata$scan_cycle_stats$ms2_per_cycle
#
#       # Adjust FWHM confidence based on scan rate stability
#       scan_rate <- primary_metadata$scan_cycle_stats$scan_rate
#       if (!is.na(scan_rate) && scan_rate >= 5 && scan_rate <= 50) {
#         diann_data$FWHM.Confidence <- 1.1  # Boost confidence for stable scan rates
#       } else if (!is.na(scan_rate) && scan_rate > 50) {
#         diann_data$FWHM.Confidence <- 0.9  # Reduce confidence for very high scan rates
#       }
#     }
#
#     cat(sprintf("  • Instrument: %s (S/N: %s)\n",
#                 primary_metadata$instrument$model,
#                 primary_metadata$instrument$serial_number))
#     cat(sprintf("  • Duration: %.1f minutes\n",
#                 primary_metadata$acquisition$duration_minutes))
#     if (!is.null(primary_metadata$scan_cycle_stats$scan_rate)) {
#       cat(sprintf("  • Scan rate: %.1f Hz\n",
#                   primary_metadata$scan_cycle_stats$scan_rate))
#     }
#   }
#
#   return(diann_data)
# }

# #' Load user configuration from JSON file
# #'
# #' @param config_file Path to user configuration JSON file
# #' @return User configuration list
# load_user_config <- function(config_file) {
#
#   if (!file.exists(config_file)) {
#     stop(sprintf("User configuration file not found: %s", config_file))
#   }
#
#   cat(sprintf("Loading user configuration from: %s\n", config_file))
#
#   config_json <- readLines(config_file, warn = FALSE)
#   config_json <- paste(config_json, collapse = "")
#
#   user_config <- rjson::fromJSON(config_json)
#
#   cat(sprintf("✅ User configuration loaded\n"))
#   cat(sprintf("  • Source instrument: %s\n", user_config$metadata_source$instrument_model))
#   cat(sprintf("  • Recommended preset: %s\n", user_config$recommended_settings$primary_preset))
#
#   return(user_config)
# }

# #' Apply user configuration to instrument settings
# #'
# #' @param user_config User configuration from load_user_config
# #' @return Instrument configuration compatible with existing system
# apply_user_config_to_instrument <- function(user_config) {
#
#   cat("Applying user configuration to instrument settings...\n")
#
#   # Source instrument configurations
#   source("config/instruments.R")
#
#   # Get recommended preset
#   preset_name <- user_config$recommended_settings$primary_preset
#
#   if (preset_name %in% names(get_instrument_configs())) {
#     # Load base configuration
#     base_config <- get_instrument_config(preset_name)
#     cat(sprintf("Using base preset: %s\n", preset_name))
#   } else {
#     # Use custom configuration
#     base_config <- get_instrument_config("custom")
#     cat("Using custom configuration\n")
#   }
#
#   # Apply custom overrides from user config
#   custom_overrides <- user_config$recommended_settings$custom_overrides
#
#   if (length(custom_overrides) > 0) {
#     cat("Applying custom overrides:\n")
#
#     for (setting in names(custom_overrides)) {
#       if (setting %in% names(base_config)) {
#         old_value <- base_config[[setting]]
#         base_config[[setting]] <- custom_overrides[[setting]]
#         cat(sprintf("  • %s: %s -> %s\n", setting, old_value, custom_overrides[[setting]]))
#       }
#     }
#   }
#
#   # Add user config metadata
#   base_config$user_config_source <- user_config$metadata_source$raw_file
#   base_config$config_confidence <- user_config$recommended_settings$confidence_level
#
#   return(base_config)
# }

#' Get data summary statistics
#'
#' @param data DIA-NN data frame
#' @return List with summary statistics
get_data_summary <- function(data) {

  summary_stats <- list(
    n_precursors = nrow(data),
    mz_range = c(min(data$Precursor.Mz), max(data$Precursor.Mz)),
    rt_range = c(min(data$RT.Start), max(data$RT.Start)),
    fwhm_stats = list(
      mean = mean(data$FWHM),
      median = median(data$FWHM),
      sd = sd(data$FWHM),
      min = min(data$FWHM),
      max = max(data$FWHM)
    ),
    mz_density = nrow(data) / diff(range(data$Precursor.Mz)),
    rt_density = nrow(data) / diff(range(data$RT.Start))
  )

  # # Add metadata summary if available
  # if ("Metadata.Available" %in% names(data)) {
  #   summary_stats$metadata_integration <- list(
  #     metadata_available = sum(data$Metadata.Available),
  #     integration_rate = sum(data$Metadata.Available) / nrow(data) * 100,
  #     average_confidence = mean(data$FWHM.Confidence, na.rm = TRUE)
  #   )
  #
  #   if (any(data$Metadata.Available)) {
  #     summary_stats$instrument_info <- list(
  #       model = unique(data$Instrument.Model[data$Metadata.Available])[1],
  #       scan_rate = if (any(!is.na(data$Scan.Rate.Hz))) {
  #         mean(data$Scan.Rate.Hz, na.rm = TRUE)
  #       } else {
  #         NA
  #       }
  #     )
  #   }
  # }

  return(summary_stats)
}