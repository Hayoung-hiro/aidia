# stage1_data_validation.R - Stage 1: Data Validation
# DIA Window Optimizer v2.0
#
# Purpose: Load and validate DIA-NN data, producing ValidatedData structure for downstream stages
# Refactored: Option B - Pipeline pattern with memory optimization


# Source dependencies only when running outside package context
if (!isNamespaceLoaded("aidia")) {
  source_if_exists <- function(file_path) {
    if (file.exists(file_path)) {
      source(file_path)
    }
  }

  source_if_exists("R/data_loader.R")
  source_if_exists("R/utils.R")
  source_if_exists("R/replicate_utils.R")
  source_if_exists("R/column_selection_simple.R")
  source_if_exists("R/quality_validation.R")
}

#' Validate DIA-NN Data and Create ValidatedData Structure
#'
#' Main function for Stage 1: Loads DIA-NN output, performs quality validation,
#' and creates a structured ValidatedData object for downstream stages.
#'
#' Pipeline Pattern: Data flows through transformation functions:
#'   Load → Validate Columns → Handle Replicates → Select Columns → Validate Quality → Package
#'
#' Column Selection: Automatically keeps only essential columns for memory efficiency
#' (Precursor.Id, RT.Start, Precursor.Mz, FWHM, Protein.Group + QC columns if present)
#'
#' @param proteome_file Path to DIA-NN output file (.parquet, .tsv, .csv)
#' @param raw_file_dir Path to raw files directory (optional, for metadata extraction)
#' @param rt_range RT filtering range c(min, max) in minutes (optional)
#' @param mz_range m/z filtering range c(min, max) in Da (optional)
#' @param enable_raw_metadata Whether to attempt raw file metadata extraction (default: FALSE)
#' @param enable_replicate_consensus Enable technical replicate consensus handling (default: TRUE)
#' @param min_replicates Minimum number of replicates to keep (default: 1)
#' @param max_intensity_cv_percent Maximum intensity CV% threshold for filtering (default: 30)
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
  max_intensity_cv_percent = 30,
  quality_threshold = 0.8,
  apply_quality_filters = TRUE,
  ...
) {

  cat("\n")
  cat("╔═══════════════════════════════════════════════╗\n")
  cat("║   STAGE 1: Data Validation                   ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  start_time <- Sys.time()

  # Early validation (fail-fast)
  validate_input_parameters(
    proteome_file = proteome_file,
    quality_threshold = quality_threshold,
    max_intensity_cv_percent = max_intensity_cv_percent
  )

  # Pipeline Step 1: Load data
  loaded_data <- proteome_file %>%
    load_and_filter_data(
      rt_range = rt_range,
      mz_range = mz_range,
      apply_quality_filters = apply_quality_filters,
      ...
    )

  cat(sprintf("✓ Loaded %d precursors\n", nrow(loaded_data$data)))

  # Pipeline Step 2: Validate required columns
  cat("\nStep 2: Validating required columns...\n")
  validate_required_columns(loaded_data$data, c("RT.Start", "Precursor.Mz", "FWHM"))
  cat("✓ All required columns present\n")

  # Compute RT.Apex from midpoint of RT.Start and RT.Stop
  if ("RT.Stop" %in% names(loaded_data$data)) {
    loaded_data$data$RT.Apex <- (loaded_data$data$RT.Start + loaded_data$data$RT.Stop) / 2
    cat("✓ Computed RT.Apex from midpoint of RT.Start and RT.Stop\n")
  } else {
    loaded_data$data$RT.Apex <- loaded_data$data$RT.Start
    cat("i RT.Stop not available, using RT.Start as RT.Apex\n")
  }

  # Pipeline Step 3: Raw metadata (optional)
  raw_metadata <- load_optional_raw_metadata(
    enable = enable_raw_metadata,
    raw_file_dir = raw_file_dir
  )

  # Pipeline Step 4: Handle technical replicates + Column selection
  processed_data <- loaded_data$data %>%
    handle_technical_replicates(
      enable_consensus = enable_replicate_consensus,
      min_replicates = min_replicates,
      max_intensity_cv_percent = max_intensity_cv_percent
    ) %>%
    select_essential_columns_pipeline(verbose = TRUE)

  # Extract metadata from pipeline
  consensus_meta <- attr(processed_data, "consensus_metadata") %||% list()
  column_meta <- attr(processed_data, "column_metadata") %||% list()

  # Pipeline Step 5: Quality validation
  cat("\nStep 5: Validating data quality...\n")
  quality_results <- validate_data_quality(processed_data)
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

  # Pipeline Step 6: Package ValidatedData object
  cat("\nStep 6: Creating ValidatedData object...\n")

  end_time <- Sys.time()
  processing_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

  validated_data <- package_validated_data(
    data = processed_data,
    file_info = list(
      proteome_file = proteome_file,
      file_format = loaded_data$file_format,
      load_time_sec = loaded_data$load_time_sec
    ),
    raw_metadata = raw_metadata,
    consensus_meta = consensus_meta,
    column_meta = column_meta,
    quality_results = quality_results,
    quality_passed = quality_passed,
    processing_time = processing_time
  )

  cat("✓ ValidatedData object created\n")
  cat("\n═══ STAGE 1 COMPLETE ═══\n")
  cat(sprintf("Processing time: %.2f seconds\n", processing_time))

  return(validated_data)
}


# =====================================================
# Pipeline Component Functions
# =====================================================

#' Early validation of input parameters (fail-fast)
#'
#' @param proteome_file File path
#' @param quality_threshold Quality threshold
#' @param max_intensity_cv_percent CV threshold
validate_input_parameters <- function(proteome_file, quality_threshold, max_intensity_cv_percent) {

  # Check file exists
  if (!file.exists(proteome_file)) {
    stop(sprintf("File not found: %s", proteome_file))
  }

  # Check file format
  file_ext <- tolower(tools::file_ext(proteome_file))
  if (!file_ext %in% c("parquet", "tsv", "txt", "csv")) {
    stop(sprintf(
      "Unsupported file format: .%s\nSupported formats: .parquet, .tsv, .txt, .csv",
      file_ext
    ))
  }

  # Check thresholds
  if (quality_threshold < 0 || quality_threshold > 1) {
    stop("quality_threshold must be between 0 and 1")
  }

  if (max_intensity_cv_percent <= 0 || max_intensity_cv_percent > 100) {
    stop("max_intensity_cv_percent must be between 0 and 100")
  }
}


#' Load and filter DIA-NN data
#'
#' @param proteome_file File path
#' @param rt_range RT range
#' @param mz_range m/z range
#' @param apply_quality_filters Apply Q-value filters
#' @param ... Additional arguments
#' @return List with data, file_format, load_time_sec
load_and_filter_data <- function(
  proteome_file,
  rt_range = NULL,
  mz_range = NULL,
  apply_quality_filters = TRUE,
  ...
) {

  cat("Step 1: Loading DIA-NN data...\n")

  file_ext <- tolower(tools::file_ext(proteome_file))
  file_format <- switch(file_ext,
    "parquet" = "parquet",
    "tsv" = "tsv",
    "txt" = "tsv",
    "csv" = "csv"
  )

  load_start <- Sys.time()

  # Load data
  if (exists("load_diann_data")) {
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

  # Apply m/z filter if specified
  if (!is.null(mz_range) && "Precursor.Mz" %in% names(data)) {
    data <- data %>%
      filter(Precursor.Mz >= mz_range[1] & Precursor.Mz <= mz_range[2])
  }

  load_end <- Sys.time()
  load_time_sec <- as.numeric(difftime(load_end, load_start, units = "secs"))

  return(list(
    data = data,
    file_format = file_format,
    load_time_sec = load_time_sec
  ))
}


#' Simple DIA-NN data loader (fallback)
#'
#' @param file_path File path
#' @param rt_range RT range
#' @param mz_range m/z range
#' @return Tibble
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

  # Convert to tibble and apply filters
  data <- as_tibble(data) %>%
    filter(!is.na(RT.Start) & !is.na(Precursor.Mz) & !is.na(FWHM))

  if (!is.null(rt_range) && "RT.Start" %in% names(data)) {
    data <- data %>% filter(RT.Start >= rt_range[1] & RT.Start <= rt_range[2])
  }

  if (!is.null(mz_range) && "Precursor.Mz" %in% names(data)) {
    data <- data %>% filter(Precursor.Mz >= mz_range[1] & Precursor.Mz <= mz_range[2])
  }

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
      "Required columns missing: %s\nAvailable columns: %s",
      paste(missing_cols, collapse = ", "),
      paste(head(names(data), 10), collapse = ", ")
    ))
  }

  return(TRUE)
}


#' Load optional raw metadata
#'
#' @param enable Whether to load
#' @param raw_file_dir Directory
#' @return List or NULL
load_optional_raw_metadata <- function(enable, raw_file_dir) {

  if (!enable || is.null(raw_file_dir)) {
    cat("\nStep 3: Skipping raw metadata (not requested)\n")
    return(NULL)
  }

  cat("\nStep 3: Attempting to load raw file metadata...\n")

  raw_metadata <- tryCatch({
    if (!dir.exists(raw_file_dir)) {
      cat(sprintf("  Directory not found: %s\n", raw_file_dir))
      return(NULL)
    }

    if (!exists("load_raw_metadata")) {
      cat("  load_raw_metadata() function not available\n")
      return(NULL)
    }

    metadata <- load_raw_metadata(raw_file_dir)
    cat("✓ Raw metadata loaded successfully\n")
    return(metadata)

  }, error = function(e) {
    cat(sprintf("  Error loading raw metadata: %s\n", e$message))
    return(NULL)
  })

  return(raw_metadata)
}


#' Handle technical replicates with consensus calculation
#'
#' Pipeline function that processes replicates and attaches metadata
#'
#' @param data Input data frame
#' @param enable_consensus Whether to enable consensus
#' @param min_replicates Minimum replicates
#' @param max_intensity_cv_percent CV threshold
#' @return Data frame with consensus_metadata attribute
handle_technical_replicates <- function(
  data,
  enable_consensus,
  min_replicates,
  max_intensity_cv_percent
) {

  cat("\nStep 4: Checking for technical replicates...\n")

  has_run_column <- "Run" %in% colnames(data)

  if (!has_run_column) {
    cat("✓ No Run column - treating as single run\n")
    attr(data, "consensus_metadata") <- list(n_runs = 1)
    return(data)
  }

  n_runs <- length(unique(data$Run))
  cat(sprintf("✓ Detected %d run(s)\n", n_runs))

  if (n_runs == 1 || !enable_consensus) {
    msg <- if (n_runs == 1) "Single run detected" else "Replicate consensus disabled"
    cat(sprintf("  → %s - skipping consensus\n", msg))
    attr(data, "consensus_metadata") <- list(n_runs = n_runs)
    return(data)
  }

  # Apply consensus
  cat(sprintf("  → Creating consensus dataset (max intensity CV: %d%%)...\n", max_intensity_cv_percent))

  consensus_data <- calculate_consensus_dataset(
    data,
    min_replicates = min_replicates,
    max_intensity_cv_percent = max_intensity_cv_percent
  )

  # Extract and attach metadata
  consensus_meta <- attr(consensus_data, "metadata") %||% list(n_runs = n_runs)

  cat(sprintf("  ✓ Consensus: %d → %d precursors (filtered %d by CV)\n",
              consensus_meta$n_precursors_before %||% nrow(data),
              consensus_meta$n_precursors_after %||% nrow(consensus_data),
              consensus_meta$n_filtered_cv %||% 0))

  attr(consensus_data, "consensus_metadata") <- consensus_meta

  return(consensus_data)
}


#' Column selection pipeline wrapper
#'
#' @param data Data frame
#' @param verbose Verbose output
#' @return Data frame with column_metadata attribute
select_essential_columns_pipeline <- function(data, verbose = TRUE) {

  cat("\nStep 4.5: Column selection (automatic)...\n")

  n_columns_before <- ncol(data)

  if (exists("select_essential_columns")) {
    data <- select_essential_columns(data = data, verbose = verbose)
  } else {
    warning("Column selection function not available - keeping all columns")
  }

  n_columns_after <- ncol(data)

  # Attach metadata
  attr(data, "column_metadata") <- list(
    n_columns_before = n_columns_before,
    n_columns_after = n_columns_after,
    n_removed = n_columns_before - n_columns_after,
    columns_kept = colnames(data),
    essential_columns = if (exists("ESSENTIAL_COLUMNS")) ESSENTIAL_COLUMNS else character()
  )

  return(data)
}


#' Package ValidatedData object
#'
#' @param data Processed data
#' @param file_info File information
#' @param raw_metadata Raw metadata
#' @param consensus_meta Consensus metadata
#' @param column_meta Column metadata
#' @param quality_results Quality results
#' @param quality_passed Quality passed flag
#' @param processing_time Processing time
#' @return ValidatedData S3 object
package_validated_data <- function(
  data,
  file_info,
  raw_metadata,
  consensus_meta,
  column_meta,
  quality_results,
  quality_passed,
  processing_time
) {

  # Calculate metadata statistics
  fwhm_stats <- calculate_fwhm_stats(data$FWHM)
  rt_range_actual <- range(data$RT.Apex, na.rm = TRUE)
  mz_range_actual <- range(data$Precursor.Mz, na.rm = TRUE)

  metadata <- list(
    n_precursors = nrow(data),
    n_columns = ncol(data),
    rt_range = rt_range_actual,
    mz_range = mz_range_actual,
    fwhm_stats = fwhm_stats,
    has_raw_metadata = !is.null(raw_metadata),
    raw_metadata = raw_metadata,
    file_info = file_info,
    column_selection = column_meta,
    processing_time_sec = processing_time
  )

  # Merge consensus metadata
  metadata <- c(metadata, consensus_meta)

  validated_data <- structure(
    list(
      data = data,
      metadata = metadata,
      validation_status = list(
        all_passed = quality_passed,
        quality_score = quality_results$quality_score,
        n_warnings = length(quality_results$warnings),
        n_errors = length(quality_results$errors),
        warnings = quality_results$warnings,
        errors = quality_results$errors,
        quality_details = quality_results$details
      )
    ),
    class = c("ValidatedData", "list")
  )

  return(validated_data)
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
# Note: S3 methods (print, summary) are now centralized in R/s3_classes.R
# This ensures consistency and reduces code duplication.
# See: print.ValidatedData(), summary.ValidatedData()
