# user_config_generator.R - Generate user configuration from raw file metadata

library(rjson)
library(dplyr)

#' Generate user configuration from raw file metadata
#'
#' @param raw_metadata List of raw file metadata from extract_raw_metadata
#' @param output_file Path for user configuration JSON file
#' @return User configuration list
generate_user_config_from_metadata <- function(raw_metadata, output_file = "user_config.json") {

  cat("=== Generating User Configuration from Raw Metadata ===\n")

  if (length(raw_metadata) == 0) {
    stop("No raw metadata provided for configuration generation")
  }

  # Take the first file as primary (or combine if multiple)
  primary_metadata <- raw_metadata[[1]]

  cat(sprintf("Using metadata from: %s\n", primary_metadata$file_info$file_name))

  # Extract key timing parameters
  user_config <- list(
    metadata_source = list(
      raw_file = primary_metadata$file_info$file_name,
      extraction_date = as.character(primary_metadata$extraction_timestamp),
      instrument_model = primary_metadata$instrument$model,
      serial_number = primary_metadata$instrument$serial_number
    ),

    instrument_timing = list(
      actual_scan_rate_hz = if (!is.null(primary_metadata$scan_cycle_stats$scan_rate)) {
        round(primary_metadata$scan_cycle_stats$scan_rate, 2)
      } else {
        NA
      },

      actual_cycle_time_sec = if (!is.null(primary_metadata$scan_cycle_stats$avg_cycle_time)) {
        round(primary_metadata$scan_cycle_stats$avg_cycle_time, 3)
      } else {
        NA
      },

      ms2_per_cycle = if (!is.null(primary_metadata$scan_cycle_stats$ms2_per_cycle)) {
        round(primary_metadata$scan_cycle_stats$ms2_per_cycle, 1)
      } else {
        NA
      },

      total_duration_min = round(primary_metadata$acquisition$duration_minutes, 2),
      total_scans = primary_metadata$scan_statistics$total_scans,
      ms1_scans = primary_metadata$scan_statistics$ms1_scans,
      ms2_scans = primary_metadata$scan_statistics$ms2_scans
    ),

    acquisition_parameters = list(
      rt_range_minutes = primary_metadata$scan_statistics$rt_range_minutes,
      acquisition_start = as.character(primary_metadata$acquisition$start_time),
      acquisition_end = as.character(primary_metadata$acquisition$end_time)
    ),

    recommended_settings = list(),  # Will be filled by comparison function

    config_generation = list(
      generated_at = as.character(Sys.time()),
      version = "1.0"
    )
  )

  # Calculate derived parameters
  if (!is.na(user_config$instrument_timing$actual_cycle_time_sec) &&
      !is.na(user_config$instrument_timing$ms2_per_cycle)) {

    # Estimate individual MS2 scan time
    estimated_ms2_time <- (user_config$instrument_timing$actual_cycle_time_sec * 1000) /
                          user_config$instrument_timing$ms2_per_cycle

    user_config$instrument_timing$estimated_ms2_time_ms <- round(estimated_ms2_time, 1)
  }

  # Save to JSON file
  user_config_json <- rjson::toJSON(user_config, indent = 2)
  cat(user_config_json, file = output_file)

  cat(sprintf("User configuration saved to: %s\n", output_file))

  return(user_config)
}

#' Compare user config with existing instrument presets
#'
#' @param user_config User configuration from generate_user_config_from_metadata
#' @return Comparison results with recommendations
compare_with_instrument_presets <- function(user_config) {

  cat("=== Comparing with Instrument Presets ===\n")

  # Source instrument configurations
  source("config/instruments.R")

  # Get all instrument presets
  instrument_configs <- get_instrument_configs()

  # Extract user instrument timing
  user_scan_rate <- user_config$instrument_timing$actual_scan_rate_hz
  user_ms2_time <- user_config$instrument_timing$estimated_ms2_time_ms
  user_model <- user_config$metadata_source$instrument_model

  cat(sprintf("User instrument: %s\n", user_model))
  cat(sprintf("Actual scan rate: %.2f Hz\n", user_scan_rate))
  if (!is.na(user_ms2_time)) {
    cat(sprintf("Estimated MS2 time: %.1f ms\n", user_ms2_time))
  }

  # Compare with each preset
  comparison_results <- data.frame(
    preset_name = character(),
    preset_instrument = character(),
    preset_max_hz = numeric(),
    preset_ms2_time = numeric(),
    scan_rate_diff = numeric(),
    ms2_time_diff = numeric(),
    match_score = numeric(),
    recommended = logical(),
    stringsAsFactors = FALSE
  )

  for (preset_name in names(instrument_configs)) {
    preset <- instrument_configs[[preset_name]]

    # Calculate differences
    scan_rate_diff <- if (!is.na(user_scan_rate)) {
      abs(user_scan_rate - preset$max_scan_rate) / preset$max_scan_rate * 100
    } else {
      NA
    }

    ms2_time_diff <- if (!is.na(user_ms2_time)) {
      abs(user_ms2_time - preset$ms2_time) / preset$ms2_time * 100
    } else {
      NA
    }

    # Calculate match score (lower is better)
    match_score <- 0
    if (!is.na(scan_rate_diff)) match_score <- match_score + scan_rate_diff
    if (!is.na(ms2_time_diff)) match_score <- match_score + ms2_time_diff

    # Name-based matching bonus
    if (grepl("astral", tolower(user_model)) && grepl("astral", tolower(preset$name))) {
      match_score <- match_score * 0.5  # Strong preference for name match
    } else if (grepl("orbitrap", tolower(user_model)) && grepl("orbitrap", tolower(preset$name))) {
      match_score <- match_score * 0.5
    } else if (grepl("timstof", tolower(user_model)) && grepl("timstof", tolower(preset$name))) {
      match_score <- match_score * 0.5
    }

    comparison_results <- rbind(comparison_results, data.frame(
      preset_name = preset_name,
      preset_instrument = preset$name,
      preset_max_hz = preset$max_scan_rate,
      preset_ms2_time = preset$ms2_time,
      scan_rate_diff = scan_rate_diff,
      ms2_time_diff = ms2_time_diff,
      match_score = match_score,
      recommended = FALSE,
      stringsAsFactors = FALSE
    ))
  }

  # Find best match
  if (nrow(comparison_results) > 0) {
    best_match_idx <- which.min(comparison_results$match_score)
    comparison_results$recommended[best_match_idx] <- TRUE

    best_match <- comparison_results[best_match_idx, ]

    cat("\n📊 Comparison Results:\n")
    cat(sprintf("Best match: %s (%s)\n", best_match$preset_name, best_match$preset_instrument))
    cat(sprintf("  Scan rate difference: %.1f%%\n", best_match$scan_rate_diff))
    if (!is.na(best_match$ms2_time_diff)) {
      cat(sprintf("  MS2 time difference: %.1f%%\n", best_match$ms2_time_diff))
    }
    cat(sprintf("  Match score: %.1f\n", best_match$match_score))
  }

  return(comparison_results)
}

#' Generate instrument configuration recommendations
#'
#' @param user_config User configuration
#' @param comparison_results Results from compare_with_instrument_presets
#' @return Updated user config with recommendations
generate_instrument_recommendations <- function(user_config, comparison_results) {

  cat("\n=== Generating Instrument Recommendations ===\n")

  # Get best match
  best_match <- comparison_results[comparison_results$recommended, ]

  if (nrow(best_match) == 0) {
    cat("No suitable preset match found, using custom settings\n")
    recommended_preset <- "custom"
  } else {
    recommended_preset <- best_match$preset_name
    cat(sprintf("Recommended preset: %s\n", recommended_preset))
  }

  # Source instrument configurations
  source("config/instruments.R")
  instrument_configs <- get_instrument_configs()

  # Generate custom settings based on actual measurements
  user_scan_rate <- user_config$instrument_timing$actual_scan_rate_hz
  user_ms2_time <- user_config$instrument_timing$estimated_ms2_time_ms

  custom_settings <- list()

  if (!is.na(user_scan_rate)) {
    # Use actual scan rate with some margin
    custom_settings$max_scan_rate <- round(user_scan_rate * 0.9, 1)  # 90% of actual for safety
    custom_settings$optimal_scan_rate <- round(user_scan_rate * 0.7, 1)  # 70% for optimal
  }

  if (!is.na(user_ms2_time)) {
    custom_settings$ms2_time <- round(user_ms2_time, 1)
  }

  # Estimate MS1 time if we have cycle information
  if (!is.na(user_config$instrument_timing$actual_cycle_time_sec) &&
      !is.na(user_config$instrument_timing$ms2_per_cycle) &&
      !is.na(user_ms2_time)) {

    total_ms2_time <- user_ms2_time * user_config$instrument_timing$ms2_per_cycle
    cycle_time_ms <- user_config$instrument_timing$actual_cycle_time_sec * 1000
    estimated_ms1_time <- cycle_time_ms - total_ms2_time

    if (estimated_ms1_time > 0) {
      custom_settings$ms1_time <- round(estimated_ms1_time, 1)
    }
  }

  # Add recommendations to user config
  user_config$recommended_settings <- list(
    primary_preset = recommended_preset,
    custom_overrides = custom_settings,
    confidence_level = if (nrow(best_match) > 0 && best_match$match_score < 20) {
      "high"
    } else if (nrow(best_match) > 0 && best_match$match_score < 50) {
      "medium"
    } else {
      "low"
    },
    notes = generate_recommendation_notes(user_config, comparison_results)
  )

  # Print recommendations
  cat("\n🎯 Final Recommendations:\n")
  cat(sprintf("  Primary preset: %s\n", recommended_preset))
  cat(sprintf("  Confidence: %s\n", user_config$recommended_settings$confidence_level))

  if (length(custom_settings) > 0) {
    cat("  Custom overrides:\n")
    for (setting in names(custom_settings)) {
      cat(sprintf("    %s: %s\n", setting, custom_settings[[setting]]))
    }
  }

  for (note in user_config$recommended_settings$notes) {
    cat(sprintf("  📝 %s\n", note))
  }

  return(user_config)
}

#' Generate recommendation notes
#'
#' @param user_config User configuration
#' @param comparison_results Comparison results
#' @return Vector of recommendation notes
generate_recommendation_notes <- function(user_config, comparison_results) {

  notes <- character()

  user_scan_rate <- user_config$instrument_timing$actual_scan_rate_hz
  best_match <- comparison_results[comparison_results$recommended, ]

  # Scan rate analysis
  if (!is.na(user_scan_rate)) {
    if (user_scan_rate > 50) {
      notes <- c(notes, "High scan rate detected - consider using narrow DIA windows")
    } else if (user_scan_rate < 10) {
      notes <- c(notes, "Low scan rate - wider windows may be more suitable")
    }
  }

  # Preset match quality
  if (nrow(best_match) > 0) {
    if (best_match$match_score < 10) {
      notes <- c(notes, "Excellent match with existing preset")
    } else if (best_match$match_score < 30) {
      notes <- c(notes, "Good match with existing preset, minor adjustments recommended")
    } else {
      notes <- c(notes, "Moderate match - consider custom configuration")
    }
  }

  # Data quality recommendations
  cycle_time <- user_config$instrument_timing$actual_cycle_time_sec
  if (!is.na(cycle_time)) {
    if (cycle_time > 3) {
      notes <- c(notes, "Long cycle time may limit acquisition speed")
    } else if (cycle_time < 0.5) {
      notes <- c(notes, "Very fast acquisition - ensure data quality is sufficient")
    }
  }

  return(notes)
}

#' Save updated user configuration
#'
#' @param user_config Updated user configuration with recommendations
#' @param output_file Output file path
save_user_config <- function(user_config, output_file = "user_config_final.json") {

  # Update generation timestamp
  user_config$config_generation$final_generated_at <- as.character(Sys.time())

  # Save to JSON
  user_config_json <- rjson::toJSON(user_config, indent = 2)
  cat(user_config_json, file = output_file)

  cat(sprintf("Final user configuration saved to: %s\n", output_file))

  return(output_file)
}

#' Complete workflow: metadata to user config
#'
#' @param raw_file_dir Directory containing raw files
#' @param output_dir Directory for output files
#' @return Final user configuration
create_user_config_from_raw_files <- function(raw_file_dir = "rawfile",
                                             output_dir = "config") {

  cat("\n")
  cat("╔══════════════════════════════════════════════╗\n")
  cat("║    USER CONFIGURATION FROM RAW METADATA     ║\n")
  cat("╚══════════════════════════════════════════════╝\n\n")

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Step 1: Extract metadata from raw files
  source("R/raw_metadata_extractor.R")

  metadata_dir <- file.path(output_dir, "metadata")
  raw_metadata <- process_raw_files_batch(
    raw_file_dir = raw_file_dir,
    save_json = TRUE,
    json_output_dir = metadata_dir
  )

  if (length(raw_metadata) == 0) {
    stop("No metadata extracted from raw files")
  }

  # Step 2: Generate user configuration
  user_config_file <- file.path(output_dir, "user_config.json")
  user_config <- generate_user_config_from_metadata(raw_metadata, user_config_file)

  # Step 3: Compare with instrument presets
  comparison_results <- compare_with_instrument_presets(user_config)

  # Step 4: Generate recommendations
  user_config <- generate_instrument_recommendations(user_config, comparison_results)

  # Step 5: Save final configuration
  final_config_file <- file.path(output_dir, "user_config_final.json")
  save_user_config(user_config, final_config_file)

  # Step 6: Save comparison results
  comparison_file <- file.path(output_dir, "preset_comparison.csv")
  write.csv(comparison_results, comparison_file, row.names = FALSE)
  cat(sprintf("Preset comparison saved to: %s\n", comparison_file))

  cat("\n✅ User configuration generation complete!\n")
  cat(sprintf("📁 Configuration files created in: %s\n", output_dir))

  return(list(
    user_config = user_config,
    comparison_results = comparison_results,
    config_file = final_config_file
  ))
}