# stage1_data_validation.R - Stage 1: Data Validation
# DIA Window Optimizer v2.0
#
# Purpose: Load and validate DIA-NN data, producing ValidatedData structure for downstream stages

library(dplyr)
library(tibble)

# Source dependencies
source_if_exists <- function(file_path) {
  if (file.exists(file_path)) {
    source(file_path)
  }
}

# Try to source existing utilities
source_if_exists("R/data_loader.R")
source_if_exists("R/utils.R")
source_if_exists("R/replicate_utils.R")

#' Validate DIA-NN Data and Create ValidatedData Structure
#'
#' Main function for Stage 1: Loads DIA-NN output, performs quality validation,
#' and creates a structured ValidatedData object for downstream stages.
#'
#' @param proteome_file Path to DIA-NN output file (.parquet, .tsv, .csv)
#' @param raw_file_dir Path to raw files directory (optional, for metadata extraction)
#' @param rt_range RT filtering range c(min, max) in minutes (optional)
#' @param mz_range m/z filtering range c(min, max) in Da (optional)
#' @param enable_raw_metadata Whether to attempt raw file metadata extraction (default: FALSE)
#' @param enable_replicate_consensus Enable technical replicate consensus handling (default: TRUE)
#' @param min_replicates Minimum number of replicates to keep (default: 1)
#' @param max_cv_percent Maximum CV% threshold for replicate filtering (default: 20)
#' @param quality_threshold Minimum quality score 0-1 (default: 0.8)
#' @param apply_quality_filters Apply DIA-NN Q-value filters (default: TRUE)
#' @param ... Additional arguments passed to filter_diann_quality()
#'
#' @return ValidatedData S3 object with data, metadata, and validation_status
#' @export
create_validated_dataset <- function(
  proteome_file,
  raw_file_dir = NULL,
  rt_range = NULL,
  mz_range = NULL,
  enable_raw_metadata = FALSE,
  enable_replicate_consensus = TRUE,
  min_replicates = 1,
  max_cv_percent = 20,
  quality_threshold = 0.8,
  apply_quality_filters = TRUE,
  ...
) {

  cat("\n")
  cat("╔═══════════════════════════════════════════════╗\n")
  cat("║   STAGE 1: Data Validation                   ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  start_time <- Sys.time()

  # Step 1: Load DIA-NN data
  cat("Step 1: Loading DIA-NN data...\n")

  loaded_data <- load_diann_data_wrapper(
    proteome_file = proteome_file,
    rt_range = rt_range,
    mz_range = mz_range,
    apply_quality_filters = apply_quality_filters,
    ...
  )

  cat(sprintf("✓ Loaded %d precursors\n", nrow(loaded_data$data)))

  # Step 2: Validate required columns
  cat("\nStep 2: Validating required columns...\n")

  required_cols <- c("RT.Start", "Precursor.Mz", "FWHM")
  validate_required_columns(loaded_data$data, required_cols)

  cat("✓ All required columns present\n")

  # Step 3: Load raw metadata (optional)
  raw_metadata <- NULL
  has_raw_metadata <- FALSE

  if (enable_raw_metadata && !is.null(raw_file_dir)) {
    cat("\nStep 3: Attempting to load raw file metadata...\n")

    raw_metadata <- load_raw_metadata_safely(raw_file_dir)

    if (!is.null(raw_metadata)) {
      has_raw_metadata <- TRUE
      cat("✓ Raw metadata loaded successfully\n")
    } else {
      cat("⚠ Raw metadata loading failed (continuing without it)\n")
    }
  } else {
    cat("\nStep 3: Skipping raw metadata (not requested)\n")
  }

  # Step 4: Handle technical replicates (if present)
  cat("\nStep 4: Checking for technical replicates...\n")

  # Check if "Run" column exists
  has_run_column <- "Run" %in% colnames(loaded_data$data)

  if (has_run_column) {
    n_runs <- length(unique(loaded_data$data$Run))
    cat(sprintf("✓ Detected %d run(s)\n", n_runs))
  } else {
    n_runs <- 1
    cat("✓ No Run column - treating as single run\n")
  }

  # Apply replicate consensus if enabled and multiple runs detected
  data_for_validation <- loaded_data$data
  consensus_meta <- list(n_runs = n_runs)

  if (n_runs > 1 && enable_replicate_consensus && has_run_column) {
    cat(sprintf("  → Creating consensus dataset (max CV: %d%%)...\n", max_cv_percent))

    data_for_validation <- calculate_consensus_dataset(
      loaded_data$data,
      min_replicates = min_replicates,
      max_cv_percent = max_cv_percent
    )

    # Extract consensus metadata
    consensus_meta <- attr(data_for_validation, "metadata")
    if (is.null(consensus_meta)) {
      consensus_meta <- list(n_runs = n_runs)
    }

    cat(sprintf("  ✓ Consensus: %d → %d precursors (filtered %d by CV)\n",
                consensus_meta$n_precursors_before,
                consensus_meta$n_precursors_after,
                consensus_meta$n_filtered_cv))
  } else if (enable_replicate_consensus && n_runs == 1) {
    cat("  → Single run detected - skipping consensus\n")
  } else if (!enable_replicate_consensus) {
    cat("  → Replicate consensus disabled\n")
  }

  # Step 5: Validate data quality
  cat("\nStep 5: Validating data quality...\n")

  quality_results <- validate_data_quality_wrapper(data_for_validation)
  quality_score <- quality_results$quality_score

  cat(sprintf("✓ Quality score: %.2f\n", quality_score))

  # Check quality threshold
  quality_passed <- quality_score >= quality_threshold

  if (!quality_passed) {
    warning(sprintf(
      "Data quality score (%.2f) below threshold (%.2f)",
      quality_score, quality_threshold
    ))
  }

  # Step 6: Calculate metadata statistics
  cat("\nStep 6: Computing metadata statistics...\n")

  fwhm_stats <- calculate_fwhm_stats(data_for_validation$FWHM)
  rt_range_actual <- range(data_for_validation$RT.Start, na.rm = TRUE)
  mz_range_actual <- range(data_for_validation$Precursor.Mz, na.rm = TRUE)

  cat("✓ Metadata computed\n")

  # Step 7: Construct ValidatedData object
  cat("\nStep 7: Creating ValidatedData object...\n")

  end_time <- Sys.time()
  processing_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

  # Merge consensus metadata with base metadata
  base_metadata <- list(
    n_precursors = nrow(data_for_validation),
    rt_range = rt_range_actual,
    mz_range = mz_range_actual,
    fwhm_stats = fwhm_stats,
    has_raw_metadata = has_raw_metadata,
    raw_metadata = raw_metadata,
    file_info = list(
      proteome_file = proteome_file,
      file_format = loaded_data$file_format,
      load_time_sec = loaded_data$load_time_sec
    ),
    processing_time_sec = processing_time
  )

  # Merge with consensus metadata
  metadata <- c(base_metadata, consensus_meta)

  validated_data <- structure(
    list(
      data = data_for_validation,
      metadata = metadata,

      validation_status = list(
        all_passed = quality_passed,
        quality_score = quality_score,
        n_warnings = length(quality_results$warnings),
        n_errors = length(quality_results$errors),
        warnings = quality_results$warnings,
        errors = quality_results$errors,
        quality_details = quality_results$details
      )
    ),
    class = c("ValidatedData", "list")
  )

  cat("✓ ValidatedData object created\n")
  cat("\n═══ STAGE 1 COMPLETE ═══\n")
  cat(sprintf("Processing time: %.2f seconds\n", processing_time))

  return(validated_data)
}


# =====================================================
# Helper Functions
# =====================================================

#' Load DIA-NN data wrapper
#'
#' Wrapper around load_diann_data() from data_loader.R with consistent return structure
#'
#' @param proteome_file Path to DIA-NN file
#' @param rt_range RT range filter
#' @param mz_range m/z range filter
#' @param apply_quality_filters Apply Q-value filters
#' @param ... Additional arguments
#' @return List with data, file_format, load_time_sec
load_diann_data_wrapper <- function(
  proteome_file,
  rt_range = NULL,
  mz_range = NULL,
  apply_quality_filters = TRUE,
  ...
) {

  # Check file exists
  if (!file.exists(proteome_file)) {
    stop(sprintf("File not found: %s", proteome_file))
  }

  # Detect file format
  file_ext <- tolower(tools::file_ext(proteome_file))
  file_format <- switch(file_ext,
    "parquet" = "parquet",
    "tsv" = "tsv",
    "txt" = "tsv",
    "csv" = "csv",
    stop(sprintf("Unsupported file format: .%s\nUse .parquet, .tsv, .txt, or .csv", file_ext))
  )

  # Load data with timing
  load_start <- Sys.time()

  if (exists("load_diann_data")) {
    # Use existing load_diann_data function
    rt_min <- if (!is.null(rt_range)) rt_range[1] else 0
    rt_max <- if (!is.null(rt_range)) rt_range[2] else NULL

    data <- load_diann_data(
      file_path = proteome_file,
      rt_min = rt_min,
      rt_max = rt_max,
      apply_quality_filters = apply_quality_filters,
      ...
    )
  } else {
    # Fallback: simple loading
    data <- load_diann_data_simple(proteome_file, rt_range, mz_range)
  }

  load_end <- Sys.time()
  load_time_sec <- as.numeric(difftime(load_end, load_start, units = "secs"))

  # Apply m/z filter if specified (in case load_diann_data doesn't support it)
  if (!is.null(mz_range) && "Precursor.Mz" %in% names(data)) {
    data <- data %>%
      filter(Precursor.Mz >= mz_range[1] & Precursor.Mz <= mz_range[2])
  }

  return(list(
    data = data,
    file_format = file_format,
    load_time_sec = load_time_sec
  ))
}


#' Simple DIA-NN data loader (fallback)
#'
#' Basic implementation if load_diann_data() is not available
#'
#' @param file_path Path to file
#' @param rt_range RT range
#' @param mz_range m/z range
#' @return Tibble with loaded data
load_diann_data_simple <- function(file_path, rt_range = NULL, mz_range = NULL) {

  file_ext <- tolower(tools::file_ext(file_path))

  # Read file
  if (file_ext == "parquet") {
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("Package 'arrow' required for parquet files. Install with: install.packages('arrow')")
    }
    data <- arrow::read_parquet(file_path)
  } else if (file_ext %in% c("tsv", "txt")) {
    data <- read.delim(file_path, stringsAsFactors = FALSE)
  } else if (file_ext == "csv") {
    data <- read.csv(file_path, stringsAsFactors = FALSE)
  }

  # Convert to tibble
  data <- as_tibble(data)

  # Apply filters
  if (!is.null(rt_range) && "RT.Start" %in% names(data)) {
    data <- data %>% filter(RT.Start >= rt_range[1] & RT.Start <= rt_range[2])
  }

  if (!is.null(mz_range) && "Precursor.Mz" %in% names(data)) {
    data <- data %>% filter(Precursor.Mz >= mz_range[1] & Precursor.Mz <= mz_range[2])
  }

  # Remove NA values in critical columns
  data <- data %>%
    filter(!is.na(RT.Start) & !is.na(Precursor.Mz) & !is.na(FWHM))

  return(data)
}


#' Validate required columns exist
#'
#' @param data Data frame
#' @param required_cols Character vector of required column names
#' @return TRUE if valid, stops otherwise
validate_required_columns <- function(data, required_cols) {

  missing_cols <- setdiff(required_cols, names(data))

  if (length(missing_cols) > 0) {
    stop(sprintf(
      "Required columns missing: %s\n" +
      "Available columns: %s",
      paste(missing_cols, collapse = ", "),
      paste(head(names(data), 10), collapse = ", ")
    ))
  }

  return(TRUE)
}


#' Load raw file metadata safely
#'
#' Attempts to load raw metadata, returns NULL on failure
#'
#' @param raw_file_dir Directory containing raw files
#' @return List with metadata or NULL
load_raw_metadata_safely <- function(raw_file_dir) {

  tryCatch({
    # Check directory exists
    if (!dir.exists(raw_file_dir)) {
      cat(sprintf("  Directory not found: %s\n", raw_file_dir))
      return(NULL)
    }

    # Check if load_raw_metadata function exists
    if (!exists("load_raw_metadata")) {
      cat("  load_raw_metadata() function not available\n")
      return(NULL)
    }

    # Attempt to load
    metadata <- load_raw_metadata(raw_file_dir)

    return(metadata)

  }, error = function(e) {
    cat(sprintf("  Error loading raw metadata: %s\n", e$message))
    return(NULL)
  })
}


#' Validate data quality wrapper
#'
#' Wrapper around validate_data_quality() or implements basic validation
#'
#' @param data Data frame
#' @return List with quality_score, warnings, errors, details
validate_data_quality_wrapper <- function(data) {

  warnings <- character()
  errors <- character()
  details <- list()

  # Basic validation checks

  # 1. FWHM outliers (IQR method)
  fwhm_outliers <- detect_fwhm_outliers(data$FWHM, iqr_multiplier = 1.5)
  details$fwhm_outliers <- fwhm_outliers

  if (fwhm_outliers$pct_outliers > 0.1) {
    warnings <- c(warnings, sprintf(
      "High FWHM outlier rate: %.1f%% (%.0f outliers)",
      fwhm_outliers$pct_outliers * 100,
      fwhm_outliers$n_outliers
    ))
  }

  # 2. RT validation
  rt_issues <- validate_rt_values(data$RT.Start)
  details$rt_issues <- rt_issues

  if (rt_issues$n_negative > 0) {
    errors <- c(errors, sprintf("%d precursors with negative RT", rt_issues$n_negative))
  }

  # 3. m/z validation
  mz_issues <- validate_mz_values(data$Precursor.Mz)
  details$mz_issues <- mz_issues

  if (mz_issues$n_invalid > 0) {
    warnings <- c(warnings, sprintf(
      "%d precursors with invalid m/z (< 50 or > 5000 Da)",
      mz_issues$n_invalid
    ))
  }

  # Calculate overall quality score
  quality_score <- calculate_quality_score_simple(
    fwhm_outlier_pct = fwhm_outliers$pct_outliers,
    rt_issue_pct = rt_issues$pct_issues,
    mz_issue_pct = mz_issues$pct_invalid
  )

  return(list(
    quality_score = quality_score,
    warnings = warnings,
    errors = errors,
    details = details
  ))
}


#' Detect FWHM outliers using IQR method
#'
#' @param fwhm_vector Numeric vector of FWHM values
#' @param iqr_multiplier IQR multiplier (default: 1.5)
#' @return List with outlier information
detect_fwhm_outliers <- function(fwhm_vector, iqr_multiplier = 1.5) {

  Q1 <- quantile(fwhm_vector, 0.25, na.rm = TRUE)
  Q3 <- quantile(fwhm_vector, 0.75, na.rm = TRUE)
  IQR_val <- Q3 - Q1

  lower_bound <- Q1 - iqr_multiplier * IQR_val
  upper_bound <- Q3 + iqr_multiplier * IQR_val

  outlier_indices <- which(fwhm_vector < lower_bound | fwhm_vector > upper_bound)

  return(list(
    indices = outlier_indices,
    n_outliers = length(outlier_indices),
    pct_outliers = length(outlier_indices) / length(fwhm_vector),
    lower_bound = lower_bound,
    upper_bound = upper_bound
  ))
}


#' Validate RT values
#'
#' @param rt_vector Numeric vector of RT values
#' @return List with validation results
validate_rt_values <- function(rt_vector) {

  n_negative <- sum(rt_vector < 0, na.rm = TRUE)
  n_na <- sum(is.na(rt_vector))
  n_total <- length(rt_vector)

  pct_issues <- (n_negative + n_na) / n_total

  return(list(
    n_negative = n_negative,
    n_na = n_na,
    n_total = n_total,
    pct_issues = pct_issues
  ))
}


#' Validate m/z values
#'
#' @param mz_vector Numeric vector of m/z values
#' @param valid_range Valid m/z range c(min, max)
#' @return List with validation results
validate_mz_values <- function(mz_vector, valid_range = c(50, 5000)) {

  n_below <- sum(mz_vector < valid_range[1], na.rm = TRUE)
  n_above <- sum(mz_vector > valid_range[2], na.rm = TRUE)
  n_na <- sum(is.na(mz_vector))
  n_invalid <- n_below + n_above + n_na
  n_total <- length(mz_vector)

  return(list(
    n_invalid = n_invalid,
    n_below = n_below,
    n_above = n_above,
    n_na = n_na,
    pct_invalid = n_invalid / n_total,
    valid_range = valid_range
  ))
}


#' Calculate simple quality score
#'
#' @param fwhm_outlier_pct FWHM outlier percentage
#' @param rt_issue_pct RT issue percentage
#' @param mz_issue_pct m/z issue percentage
#' @return Quality score 0-1
calculate_quality_score_simple <- function(
  fwhm_outlier_pct,
  rt_issue_pct,
  mz_issue_pct
) {

  # Weight factors
  W_FWHM <- 0.4
  W_RT <- 0.3
  W_MZ <- 0.3

  # Component scores (1 - issue_rate)
  fwhm_score <- 1 - min(fwhm_outlier_pct, 1.0)
  rt_score <- 1 - min(rt_issue_pct, 1.0)
  mz_score <- 1 - min(mz_issue_pct, 1.0)

  # Weighted average
  quality_score <- W_FWHM * fwhm_score + W_RT * rt_score + W_MZ * mz_score

  return(max(0, min(1, quality_score)))
}


#' Calculate FWHM statistics
#'
#' @param fwhm_vector Numeric vector of FWHM values
#' @return List with statistics
calculate_fwhm_stats <- function(fwhm_vector) {

  list(
    mean = mean(fwhm_vector, na.rm = TRUE),
    median = median(fwhm_vector, na.rm = TRUE),
    sd = sd(fwhm_vector, na.rm = TRUE),
    q25 = quantile(fwhm_vector, 0.25, na.rm = TRUE),
    q75 = quantile(fwhm_vector, 0.75, na.rm = TRUE),
    min = min(fwhm_vector, na.rm = TRUE),
    max = max(fwhm_vector, na.rm = TRUE)
  )
}


# =====================================================
# S3 Methods for ValidatedData
# =====================================================

#' Print method for ValidatedData
#'
#' @param x ValidatedData object
#' @param ... Additional arguments
#' @export
print.ValidatedData <- function(x, ...) {
  cat("ValidatedData object\n")
  cat(sprintf("  Precursors: %d\n", x$metadata$n_precursors))
  cat(sprintf("  RT range: %.2f - %.2f min\n",
              x$metadata$rt_range[1], x$metadata$rt_range[2]))
  cat(sprintf("  m/z range: %.1f - %.1f Da\n",
              x$metadata$mz_range[1], x$metadata$mz_range[2]))
  cat(sprintf("  Quality score: %.2f\n", x$validation_status$quality_score))
  cat(sprintf("  Status: %s\n",
              ifelse(x$validation_status$all_passed, "✓ PASSED", "✗ FAILED")))

  if (x$validation_status$n_warnings > 0) {
    cat(sprintf("  Warnings: %d\n", x$validation_status$n_warnings))
  }

  invisible(x)
}


#' Summary method for ValidatedData
#'
#' @param object ValidatedData object
#' @param ... Additional arguments
#' @export
summary.ValidatedData <- function(object, ...) {
  cat("╔═══════════════════════════════════════════════╗\n")
  cat("║   ValidatedData Summary                      ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  cat("Data Overview:\n")
  cat(sprintf("  Precursors: %d\n", object$metadata$n_precursors))
  cat(sprintf("  RT range: %.2f - %.2f min\n",
              object$metadata$rt_range[1], object$metadata$rt_range[2]))
  cat(sprintf("  m/z range: %.1f - %.1f Da\n",
              object$metadata$mz_range[1], object$metadata$mz_range[2]))

  cat("\nFWHM Statistics:\n")
  cat(sprintf("  Mean: %.3f min (%.1f sec)\n",
              object$metadata$fwhm_stats$mean,
              object$metadata$fwhm_stats$mean * 60))
  cat(sprintf("  Median: %.3f min (%.1f sec)\n",
              object$metadata$fwhm_stats$median,
              object$metadata$fwhm_stats$median * 60))
  cat(sprintf("  SD: %.3f min\n", object$metadata$fwhm_stats$sd))
  cat(sprintf("  Range: %.3f - %.3f min\n",
              object$metadata$fwhm_stats$min,
              object$metadata$fwhm_stats$max))

  cat("\nValidation Status:\n")
  cat(sprintf("  Quality score: %.2f\n", object$validation_status$quality_score))
  cat(sprintf("  Passed: %s\n", ifelse(object$validation_status$all_passed, "YES", "NO")))
  cat(sprintf("  Warnings: %d\n", object$validation_status$n_warnings))
  cat(sprintf("  Errors: %d\n", object$validation_status$n_errors))

  if (object$validation_status$n_warnings > 0) {
    cat("\nWarnings:\n")
    for (w in object$validation_status$warnings) {
      cat(sprintf("  ⚠️  %s\n", w))
    }
  }

  if (object$validation_status$n_errors > 0) {
    cat("\nErrors:\n")
    for (e in object$validation_status$errors) {
      cat(sprintf("  ❌ %s\n", e))
    }
  }

  cat("\nFile Information:\n")
  cat(sprintf("  Source: %s\n", basename(object$metadata$file_info$proteome_file)))
  cat(sprintf("  Format: %s\n", object$metadata$file_info$file_format))
  cat(sprintf("  Load time: %.2f sec\n", object$metadata$file_info$load_time_sec))
  cat(sprintf("  Processing time: %.2f sec\n", object$metadata$processing_time_sec))

  invisible(object)
}
