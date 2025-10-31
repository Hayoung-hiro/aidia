# =============================================================================
# Configuration File Validation Script
# =============================================================================
# Validates JSON configuration files before running optimization
# =============================================================================

source("R/config_loader.R")

# =============================================================================
# Main Validation Function
# =============================================================================

#' Validate configuration file and print detailed report
#'
#' @param config_path Path to JSON configuration file
#' @return Invisible logical (TRUE if valid, FALSE otherwise)
#' @export
#'
#' @examples
#' # Validate default configuration
#' validate_config_file("config/optimization_config.json")
#'
#' # Validate preset
#' validate_config_file("config/presets/fusion_lumos_standard.json")
validate_config_file <- function(config_path) {

  cat("\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║              CONFIGURATION FILE VALIDATION                     ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  cat(sprintf("File: %s\n\n", config_path))

  # Check file existence
  if (!file.exists(config_path)) {
    cat("❌ VALIDATION FAILED\n")
    cat(sprintf("   Configuration file not found: %s\n", config_path))
    return(invisible(FALSE))
  }

  # Load JSON
  cat("📄 Loading JSON file...\n")
  config <- tryCatch(
    {
      fromJSON(config_path, simplifyVector = TRUE, simplifyDataFrame = FALSE)
    },
    error = function(e) {
      cat(sprintf("❌ JSON parsing error: %s\n", e$message))
      return(NULL)
    }
  )

  if (is.null(config)) {
    return(invisible(FALSE))
  }

  cat("✅ JSON file loaded successfully\n\n")

  # Validate configuration
  cat("🔍 Validating configuration...\n\n")
  validation_result <- validate_optimization_config(config)

  # Print validation results
  if (validation_result$valid) {
    cat("╔════════════════════════════════════════════════════════════════╗\n")
    cat("║                    ✅ VALIDATION PASSED                        ║\n")
    cat("╚════════════════════════════════════════════════════════════════╝\n\n")

    cat("All configuration checks passed. Configuration is ready to use.\n\n")

    # Print configuration summary
    print_config_summary(config)

    cat("\n📌 To run optimization with this configuration:\n")
    cat(sprintf("   source('run_with_config.R')\n"))
    cat(sprintf("   run_optimization('%s')\n\n", config_path))

    return(invisible(TRUE))

  } else {
    cat("╔════════════════════════════════════════════════════════════════╗\n")
    cat("║                    ❌ VALIDATION FAILED                        ║\n")
    cat("╚════════════════════════════════════════════════════════════════╝\n\n")

    cat(sprintf("Found %d error(s):\n\n", length(validation_result$errors)))

    for (i in seq_along(validation_result$errors)) {
      cat(sprintf("  %d. %s\n", i, validation_result$errors[i]))
    }

    cat("\n📝 Please fix the errors and try again.\n")
    cat("   Reference: config/optimization_config_template.json\n\n")

    return(invisible(FALSE))
  }
}

# =============================================================================
# Batch Validation Function
# =============================================================================

#' Validate all configuration files in a directory
#'
#' @param config_dir Directory containing JSON configuration files
#' @return Data frame with validation results
#' @export
#'
#' @examples
#' # Validate all presets
#' validate_all_configs("config/presets")
validate_all_configs <- function(config_dir = "config") {

  cat("\n╔════════════════════════════════════════════════════════════════╗\n")
  cat("║              BATCH CONFIGURATION VALIDATION                    ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  # Find all JSON files
  json_files <- list.files(
    config_dir,
    pattern = "\\.json$",
    full.names = TRUE,
    recursive = TRUE
  )

  if (length(json_files) == 0) {
    cat(sprintf("⚠️  No JSON files found in: %s\n", config_dir))
    return(invisible(NULL))
  }

  cat(sprintf("Found %d JSON file(s) to validate:\n\n", length(json_files)))

  # Validate each file
  results <- list()

  for (i in seq_along(json_files)) {
    json_file <- json_files[i]

    cat(sprintf("[%d/%d] %s\n", i, length(json_files), basename(json_file)))
    cat("────────────────────────────────────────────────────────────\n")

    # Load and validate
    config <- tryCatch(
      {
        fromJSON(json_file, simplifyVector = TRUE, simplifyDataFrame = FALSE)
      },
      error = function(e) {
        cat(sprintf("   ❌ JSON parsing error: %s\n\n", e$message))
        return(NULL)
      }
    )

    if (is.null(config)) {
      results[[i]] <- data.frame(
        File = basename(json_file),
        Path = json_file,
        Valid = FALSE,
        Errors = "JSON parsing failed",
        Project_Name = NA,
        Instrument = NA,
        stringsAsFactors = FALSE
      )
      next
    }

    validation_result <- validate_optimization_config(config)

    if (validation_result$valid) {
      cat("   ✅ Valid\n")

      project_name <- ifelse(
        !is.null(config$project_metadata$project_name),
        config$project_metadata$project_name,
        "Unknown"
      )

      instrument <- ifelse(
        !is.null(config$instrument$preset),
        config$instrument$preset,
        "Unknown"
      )

      results[[i]] <- data.frame(
        File = basename(json_file),
        Path = json_file,
        Valid = TRUE,
        Errors = "",
        Project_Name = project_name,
        Instrument = instrument,
        stringsAsFactors = FALSE
      )

    } else {
      cat(sprintf("   ❌ Invalid (%d error(s))\n", length(validation_result$errors)))

      for (error in validation_result$errors) {
        cat(sprintf("      - %s\n", error))
      }

      results[[i]] <- data.frame(
        File = basename(json_file),
        Path = json_file,
        Valid = FALSE,
        Errors = paste(validation_result$errors, collapse = "; "),
        Project_Name = NA,
        Instrument = NA,
        stringsAsFactors = FALSE
      )
    }

    cat("\n")
  }

  # Create summary table
  summary_table <- do.call(rbind, results)

  # Print summary
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║                    VALIDATION SUMMARY                          ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n\n")

  n_valid <- sum(summary_table$Valid)
  n_invalid <- sum(!summary_table$Valid)
  total <- nrow(summary_table)

  cat(sprintf("Total files: %d\n", total))
  cat(sprintf("✅ Valid: %d (%.0f%%)\n", n_valid, 100 * n_valid / total))
  cat(sprintf("❌ Invalid: %d (%.0f%%)\n\n", n_invalid, 100 * n_invalid / total))

  print(summary_table[, c("File", "Valid", "Project_Name", "Instrument")])

  cat("\n")

  return(invisible(summary_table))
}

# =============================================================================
# Usage Examples
# =============================================================================

# Example 1: Validate single configuration
# validate_config_file("config/optimization_config.json")

# Example 2: Validate preset
# validate_config_file("config/presets/fusion_lumos_standard.json")

# Example 3: Validate all configurations
# validate_all_configs("config")

# Example 4: Validate all presets
# validate_all_configs("config/presets")
