# Option C: Complete Pipeline Redesign Plan

**Document Version**: 1.0
**Date**: 2025-11-19
**Status**: 📋 Planned (Not yet implemented)
**Estimated Effort**: 3-4 hours
**Risk Level**: Medium (requires comprehensive testing)

---

## Executive Summary

Option C represents a complete architectural redesign of Stage 1 using pure functional programming principles and full pipeline pattern. This aggressive refactoring targets **400-line reduction** (689 → ~290 lines) through systematic decomposition, elimination of helper wrappers, and maximum code reuse.

**Completed**: Option B (689 → 617 lines, -72 lines, 10.4% reduction)
**Proposed**: Option C (617 → ~290 lines, -327 lines additional, 53% total reduction from original)

---

## Current State (After Option B)

### File Structure
```
R/
├── stage1_data_validation.R       617 lines (main pipeline)
├── quality_validation.R           220 lines (quality checks)
├── replicate_utils.R              212 lines (consensus calculation)
├── column_selection_simple.R      150 lines (column selection)
└── utils.R                        (to be created)
```

### Current Architecture (Option B)
```
create_validated_dataset() [Main entry, 152 lines]
  ├─ validate_input_parameters()          [30 lines]
  ├─ load_and_filter_data()              [50 lines]
  ├─ load_diann_data_simple()            [30 lines]
  ├─ validate_required_columns()         [15 lines]
  ├─ load_optional_raw_metadata()        [30 lines]
  ├─ handle_technical_replicates()       [45 lines]
  ├─ select_essential_columns_pipeline() [25 lines]
  └─ package_validated_data()            [60 lines]

Pipeline Component Functions [465 lines total]
S3 Methods [87 lines]
```

---

## Option C: Complete Redesign Vision

### Design Philosophy

**Core Principles**:
1. **Pure Functions**: Each function does ONE thing, no side effects
2. **Composability**: Small functions that chain together naturally
3. **Immutability**: Data transformations return new objects, never mutate
4. **Transparency**: Pipeline flow is self-documenting
5. **Zero Duplication**: Extract all common patterns to `utils.R`

### Target Architecture

```
create_validated_dataset() [Main pipeline only, ~40 lines]
  ↓
  Pipeline: data %>%
    validate_file() %>%
    load_data() %>%
    validate_schema() %>%
    handle_replicates() %>%
    select_columns() %>%
    validate_quality() %>%
    add_metadata() %>%
    as_validated_data()

utils.R [Shared utilities, ~100 lines]
  ├─ validate_file()           [10 lines]
  ├─ load_data()               [15 lines]
  ├─ validate_schema()         [10 lines]
  ├─ add_metadata()            [20 lines]
  ├─ as_validated_data()       [25 lines]
  └─ Common validators         [20 lines]

stage1_pipeline.R [Pipeline-specific, ~150 lines]
  ├─ handle_replicates()       [40 lines]
  ├─ select_columns()          [30 lines]
  ├─ validate_quality()        [20 lines]
  └─ Pipeline helpers          [60 lines]

Total: ~290 lines (from 617 lines, -53%)
```

---

## Detailed Refactoring Plan

### Phase 1: Extract Common Utilities (1 hour)

**Goal**: Create `R/utils.R` with reusable validation and transformation functions

**New File**: `R/utils.R` (~100 lines)
```r
# ============================================================================
# File Validation
# ============================================================================

#' Validate file exists and has supported format
#' @param file_path File path
#' @return Validated file path
validate_file <- function(file_path) {
  if (!file.exists(file_path)) {
    stop(sprintf("File not found: %s", file_path))
  }

  ext <- tolower(tools::file_ext(file_path))
  if (!ext %in% c("parquet", "tsv", "txt", "csv")) {
    stop(sprintf("Unsupported format: .%s", ext))
  }

  structure(file_path, format = ext)
}


# ============================================================================
# Data Loading
# ============================================================================

#' Load data with automatic format detection
#' @param file_path Validated file path
#' @return Tibble with timing metadata
load_data <- function(file_path) {
  format <- attr(file_path, "format")

  start <- Sys.time()

  data <- switch(format,
    "parquet" = arrow::read_parquet(file_path),
    "tsv" = read.delim(file_path, stringsAsFactors = FALSE),
    "txt" = read.delim(file_path, stringsAsFactors = FALSE),
    "csv" = read.csv(file_path, stringsAsFactors = FALSE)
  )

  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))

  structure(
    as_tibble(data),
    load_time_sec = elapsed,
    file_format = format
  )
}


# ============================================================================
# Schema Validation
# ============================================================================

#' Validate required columns exist
#' @param data Data frame
#' @param required Character vector of required columns
#' @return Data unchanged (or error)
validate_schema <- function(data, required = c("RT.Start", "Precursor.Mz", "FWHM")) {
  missing <- setdiff(required, names(data))

  if (length(missing) > 0) {
    stop(sprintf(
      "Missing columns: %s\nAvailable: %s",
      paste(missing, collapse = ", "),
      paste(head(names(data), 10), collapse = ", ")
    ))
  }

  data
}


# ============================================================================
# Metadata Attachment
# ============================================================================

#' Add metadata to data object
#' @param data Data frame
#' @param ... Named metadata items
#' @return Data with metadata attributes
add_metadata <- function(data, ...) {
  metadata <- list(...)

  for (name in names(metadata)) {
    attr(data, name) <- metadata[[name]]
  }

  data
}


#' Extract all metadata from data object
#' @param data Data with metadata attributes
#' @return List of metadata
extract_metadata <- function(data) {
  attrs <- attributes(data)
  attrs[!names(attrs) %in% c("names", "row.names", "class")]
}


# ============================================================================
# ValidatedData Constructor
# ============================================================================

#' Create ValidatedData S3 object
#' @param data Processed data
#' @param metadata Metadata list
#' @param validation_status Validation results
#' @return ValidatedData object
as_validated_data <- function(data, metadata, validation_status) {
  structure(
    list(
      data = data,
      metadata = metadata,
      validation_status = validation_status
    ),
    class = c("ValidatedData", "list")
  )
}
```

**Extraction Strategy**:
1. Move all file I/O functions to `utils.R`
2. Move all validation helpers to `utils.R`
3. Move metadata manipulation to `utils.R`
4. Keep only pipeline-specific logic in `stage1_data_validation.R`

---

### Phase 2: Streamline Main Pipeline (1.5 hours)

**Goal**: Reduce main function to pure pipeline composition

**Before (Option B, 152 lines)**:
```r
create_validated_dataset <- function(...) {
  cat("\n╔═══════════════════════════════════════════════╗\n")
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

  # ... [90 more lines of orchestration]
}
```

**After (Option C, ~40 lines)**:
```r
create_validated_dataset <- function(
  proteome_file,
  rt_range = NULL,
  mz_range = NULL,
  enable_raw_metadata = FALSE,
  enable_replicate_consensus = TRUE,
  min_replicates = 1,
  max_intensity_cv_percent = 30,
  quality_threshold = 0.8,
  apply_quality_filters = TRUE,
  verbose = TRUE,
  ...
) {

  if (verbose) print_stage_header("STAGE 1: Data Validation")

  start_time <- Sys.time()

  # Pure functional pipeline
  result <- proteome_file %>%
    validate_file() %>%
    load_data() %>%
    apply_filters(rt_range, mz_range) %>%
    validate_schema() %>%
    handle_replicates(
      enable_consensus = enable_replicate_consensus,
      min_replicates = min_replicates,
      max_intensity_cv_percent = max_intensity_cv_percent
    ) %>%
    select_columns() %>%
    validate_quality() %>%
    build_validated_data(
      start_time = start_time,
      quality_threshold = quality_threshold,
      raw_metadata = load_raw_metadata_if_requested(enable_raw_metadata, raw_file_dir),
      verbose = verbose
    )

  if (verbose) print_stage_footer(result$metadata$processing_time_sec)

  result
}
```

**Key Changes**:
- ✅ Pure pipeline from start to finish
- ✅ All intermediate variable assignments removed
- ✅ All console output extracted to `print_*` helpers
- ✅ Metadata flows through pipeline via attributes
- ✅ Error handling implicit in each pipeline step

---

### Phase 3: Consolidate Pipeline Components (1 hour)

**Goal**: Create `R/stage1_pipeline.R` for Stage 1-specific transformations

**New File**: `R/stage1_pipeline.R` (~150 lines)
```r
# ============================================================================
# Data Filtering
# ============================================================================

#' Apply RT and m/z filters
#' @param data Data frame
#' @param rt_range RT range c(min, max)
#' @param mz_range m/z range c(min, max)
#' @return Filtered data
apply_filters <- function(data, rt_range = NULL, mz_range = NULL) {

  if (!is.null(rt_range)) {
    data <- data %>%
      filter(RT.Start >= rt_range[1] & RT.Start <= rt_range[2])
  }

  if (!is.null(mz_range)) {
    data <- data %>%
      filter(Precursor.Mz >= mz_range[1] & Precursor.Mz <= mz_range[2])
  }

  data %>%
    filter(!is.na(RT.Start) & !is.na(Precursor.Mz) & !is.na(FWHM))
}


# ============================================================================
# Replicate Handling
# ============================================================================

#' Handle technical replicates (pipeline wrapper)
#' @param data Data frame
#' @param enable_consensus Whether to create consensus
#' @param min_replicates Minimum replicates
#' @param max_intensity_cv_percent CV threshold
#' @return Processed data with metadata
handle_replicates <- function(
  data,
  enable_consensus = TRUE,
  min_replicates = 1,
  max_intensity_cv_percent = 30
) {

  has_run <- "Run" %in% colnames(data)
  n_runs <- if (has_run) length(unique(data$Run)) else 1

  # Early return for single run
  if (n_runs == 1 || !enable_consensus) {
    return(add_metadata(data, n_runs = n_runs))
  }

  # Apply consensus
  consensus_data <- calculate_consensus_dataset(
    data,
    min_replicates = min_replicates,
    max_intensity_cv_percent = max_intensity_cv_percent
  )

  # Preserve metadata from consensus calculation
  consensus_meta <- attr(consensus_data, "metadata") %||% list()

  add_metadata(consensus_data,
    n_runs = n_runs,
    consensus = consensus_meta
  )
}


# ============================================================================
# Column Selection
# ============================================================================

#' Select essential columns (pipeline wrapper)
#' @param data Data frame
#' @return Data with selected columns
select_columns <- function(data) {

  n_before <- ncol(data)

  selected_data <- select_essential_columns(data, verbose = FALSE)

  n_after <- ncol(selected_data)

  add_metadata(selected_data,
    n_columns_before = n_before,
    n_columns_after = n_after,
    columns_removed = n_before - n_after
  )
}


# ============================================================================
# Quality Validation
# ============================================================================

#' Validate data quality (pipeline wrapper)
#' @param data Data frame
#' @return Data with quality metadata
validate_quality <- function(data) {

  quality_results <- validate_data_quality(data)

  add_metadata(data,
    quality_score = quality_results$quality_score,
    quality_warnings = quality_results$warnings,
    quality_errors = quality_results$errors,
    quality_details = quality_results$details
  )
}


# ============================================================================
# Final Assembly
# ============================================================================

#' Build final ValidatedData object
#' @param data Processed data (with metadata attributes)
#' @param start_time Start time
#' @param quality_threshold Quality threshold
#' @param raw_metadata Raw metadata
#' @param verbose Print progress
#' @return ValidatedData S3 object
build_validated_data <- function(
  data,
  start_time,
  quality_threshold = 0.8,
  raw_metadata = NULL,
  verbose = TRUE
) {

  # Extract all metadata from pipeline
  pipeline_meta <- extract_metadata(data)

  # Calculate statistics
  fwhm_stats <- calculate_fwhm_stats(data$FWHM)
  rt_range <- range(data$RT.Start, na.rm = TRUE)
  mz_range <- range(data$Precursor.Mz, na.rm = TRUE)

  processing_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  # Assemble metadata
  metadata <- list(
    n_precursors = nrow(data),
    n_columns = ncol(data),
    rt_range = rt_range,
    mz_range = mz_range,
    fwhm_stats = fwhm_stats,
    processing_time_sec = processing_time,
    has_raw_metadata = !is.null(raw_metadata),
    raw_metadata = raw_metadata
  )

  # Merge pipeline metadata
  metadata <- c(metadata, pipeline_meta)

  # Validation status
  quality_score <- metadata$quality_score %||% 0
  quality_passed <- quality_score >= quality_threshold

  validation_status <- list(
    all_passed = quality_passed,
    quality_score = quality_score,
    n_warnings = length(metadata$quality_warnings %||% character()),
    n_errors = length(metadata$quality_errors %||% character()),
    warnings = metadata$quality_warnings %||% character(),
    errors = metadata$quality_errors %||% character(),
    quality_details = metadata$quality_details %||% list()
  )

  # Create ValidatedData object
  as_validated_data(
    data = data,
    metadata = metadata,
    validation_status = validation_status
  )
}
```

**Benefits**:
- Each function is ~15-30 lines (single responsibility)
- Pure transformations (input → output, no side effects)
- Metadata flows through attributes (no global state)
- Easy to test each component independently

---

### Phase 4: Optimize Print Functions (30 min)

**Goal**: Extract all console output to utility functions

**New Addition to `R/utils.R`**:
```r
# ============================================================================
# Console Output Helpers
# ============================================================================

#' Print stage header
#' @param title Stage title
print_stage_header <- function(title) {
  cat("\n")
  cat("╔═══════════════════════════════════════════════╗\n")
  cat(sprintf("║   %-43s ║\n", title))
  cat("╚═══════════════════════════════════════════════╝\n\n")
}


#' Print stage footer
#' @param processing_time_sec Processing time in seconds
print_stage_footer <- function(processing_time_sec) {
  cat("\n═══ STAGE 1 COMPLETE ═══\n")
  cat(sprintf("Processing time: %.2f seconds\n", processing_time_sec))
}


#' Print step message
#' @param step_num Step number
#' @param message Step message
print_step <- function(step_num, message) {
  cat(sprintf("\nStep %d: %s...\n", step_num, message))
}


#' Print success message
#' @param message Success message
print_success <- function(message) {
  cat(sprintf("✓ %s\n", message))
}
```

---

## File Size Comparison

### Option B (Current)
```
R/stage1_data_validation.R       617 lines
R/quality_validation.R           220 lines
R/replicate_utils.R              212 lines
R/column_selection_simple.R      150 lines
─────────────────────────────────────────
TOTAL:                          1199 lines
```

### Option C (Proposed)
```
R/stage1_data_validation.R        40 lines (main pipeline only)
R/stage1_pipeline.R              150 lines (pipeline components)
R/utils.R                        100 lines (shared utilities)
R/quality_validation.R           220 lines (unchanged)
R/replicate_utils.R              212 lines (unchanged)
R/column_selection_simple.R      150 lines (unchanged)
─────────────────────────────────────────
TOTAL:                           872 lines (-327 lines, -27% reduction)
```

**Stage 1 Core Reduction**:
- Option B: 617 lines
- Option C: 190 lines (40 + 150)
- **Savings**: -427 lines (-69% for core Stage 1 logic)

---

## Benefits of Option C

### 1. **Code Clarity**
- **Self-Documenting**: Pipeline flow reads like English
- **Single Responsibility**: Each function does ONE thing
- **Zero Duplication**: All common logic in `utils.R`

### 2. **Maintainability**
- **Easy Testing**: Each pipeline step is independently testable
- **Easy Debugging**: Insert `View()` or `print()` between any pipe step
- **Easy Extension**: Add new pipeline steps without touching existing code

### 3. **Performance**
- **Lazy Evaluation**: Pipeline steps only execute when needed
- **Memory Efficiency**: No intermediate variable storage
- **Attribute-Based Metadata**: Zero overhead for metadata passing

### 4. **Reusability**
- **`utils.R` Functions**: Reusable across ALL stages (Stage 2, 3, 4)
- **Consistent Patterns**: Same validation/loading logic everywhere
- **DRY Principle**: Write once, use everywhere

---

## Risks and Mitigation

### Risk 1: Attribute Metadata Loss
**Problem**: Attributes can be lost during dplyr operations

**Mitigation**:
```r
# Use preserve_attributes wrapper
preserve_attributes <- function(data, fn, ...) {
  attrs <- attributes(data)
  result <- fn(data, ...)
  attributes(result) <- c(attributes(result), attrs[!names(attrs) %in% names(attributes(result))])
  result
}

# Usage in pipeline
data %>%
  preserve_attributes(mutate, new_col = RT.Start * 2)
```

### Risk 2: Breaking Existing Tests
**Problem**: 19 integration tests expect current structure

**Mitigation**:
- ✅ Keep existing test expectations unchanged
- ✅ ValidatedData output structure remains identical
- ✅ Only internal implementation changes
- ✅ Run all 62 tests after each refactoring phase

### Risk 3: Pipeline Complexity
**Problem**: Deep pipelines can be hard to debug

**Mitigation**:
```r
# Add debug mode
if (getOption("dia.debug", FALSE)) {
  data <- data %>%
    tap(~cat("After load:", nrow(.), "rows\n")) %>%
    validate_schema() %>%
    tap(~cat("After validation:", nrow(.), "rows\n"))
}
```

---

## Implementation Checklist

### Prerequisites
- [x] Option B refactoring complete
- [x] All 62 tests passing
- [ ] Create git branch `feature/option-c-refactoring`

### Phase 1: Extract Common Utilities (1 hour)
- [ ] Create `R/utils.R` with file I/O functions
- [ ] Move validation helpers to `utils.R`
- [ ] Move metadata functions to `utils.R`
- [ ] Add print helpers to `utils.R`
- [ ] Test: All 62 tests still passing

### Phase 2: Streamline Main Pipeline (1.5 hours)
- [ ] Rewrite `create_validated_dataset()` as pure pipeline
- [ ] Remove all intermediate variable assignments
- [ ] Replace console output with print helpers
- [ ] Test: All 19 Stage 1 integration tests passing

### Phase 3: Consolidate Pipeline Components (1 hour)
- [ ] Create `R/stage1_pipeline.R`
- [ ] Move `apply_filters()` to pipeline file
- [ ] Move `handle_replicates()` wrapper to pipeline file
- [ ] Move `select_columns()` wrapper to pipeline file
- [ ] Move `validate_quality()` wrapper to pipeline file
- [ ] Move `build_validated_data()` to pipeline file
- [ ] Test: All 62 tests passing

### Phase 4: Optimize Print Functions (30 min)
- [ ] Extract all `cat()` calls to print helpers
- [ ] Add verbose flag support throughout pipeline
- [ ] Test: Verify console output unchanged

### Phase 5: Final Validation (30 min)
- [ ] Run full test suite (62 tests)
- [ ] Test with real DIA-NN data (30min, 60min, 90min gradients)
- [ ] Benchmark performance (should be ≥ Option B speed)
- [ ] Update documentation (CLAUDE.md, DEVELOPMENT.md)

### Total Estimated Time: 3-4 hours

---

## Testing Strategy

### Unit Tests (Required)
```r
# Test each utils.R function independently
test_that("validate_file works correctly", {
  expect_error(validate_file("nonexistent.parquet"), "File not found")
  expect_error(validate_file("test.xyz"), "Unsupported format")
})

test_that("load_data preserves metadata", {
  temp_file <- write_test_parquet()
  result <- load_data(validate_file(temp_file))
  expect_true(has_attr(result, "load_time_sec"))
  expect_true(has_attr(result, "file_format"))
})

test_that("add_metadata works", {
  data <- tibble(x = 1:10)
  result <- add_metadata(data, test = "value", count = 10)
  expect_equal(attr(result, "test"), "value")
  expect_equal(attr(result, "count"), 10)
})
```

### Integration Tests (Existing 19 tests)
- All existing tests MUST pass without modification
- ValidatedData output structure unchanged
- Metadata content identical to Option B

### Performance Tests
```r
# Benchmark Option B vs Option C
library(microbenchmark)

microbenchmark(
  option_b = create_validated_dataset_option_b(test_file),
  option_c = create_validated_dataset_option_c(test_file),
  times = 10
)

# Expected: Option C ≤ 110% of Option B time (acceptable 10% overhead)
```

---

## Success Criteria

✅ **Code Reduction**: ≥400 lines removed from Stage 1 core
✅ **Test Pass Rate**: 62/62 tests passing (100%)
✅ **Performance**: ≤110% of Option B execution time
✅ **Readability**: Main pipeline ≤50 lines
✅ **Reusability**: ≥5 functions in `utils.R` reusable by other stages
✅ **Documentation**: All new functions have roxygen2 docs

---

## Future Extensions (Post-Option C)

Once Option C is complete, the new architecture enables:

### 1. **Stage 2-4 Refactoring**
- Apply same pipeline pattern to Stage 2 (DPPP diagnosis)
- Apply same pipeline pattern to Stage 3 (Window optimization)
- Reuse `utils.R` functions across all stages

### 2. **Parallel Processing**
```r
# Enable parallel pipeline execution
library(future)
plan(multisession)

result <- proteome_file %>%
  validate_file() %>%
  load_data() %>%
  {
    # Fork pipeline for parallel processing
    list(
      quality = future(validate_quality(.)),
      replicates = future(handle_replicates(.)),
      selection = future(select_columns(.))
    ) %>% as_resolved()
  } %>%
  merge_pipeline_results()
```

### 3. **Caching Support**
```r
# Add caching to expensive operations
library(memoise)

load_data_cached <- memoise(load_data)
validate_quality_cached <- memoise(validate_quality)
```

### 4. **Progress Reporting**
```r
# Add progress bar to pipeline
library(progressr)

with_progress({
  p <- progressor(steps = 8)

  result <- proteome_file %>%
    validate_file() %>% {p(); .} %>%
    load_data() %>% {p(); .} %>%
    validate_schema() %>% {p(); .}
    # ... etc
})
```

---

## References

### Related Documents
- [CLAUDE.md](../CLAUDE.md) - Main development guide
- [DEVELOPMENT.md](../DEVELOPMENT.md) - Project structure
- [API_SPECIFICATION.md](API_SPECIFICATION.md) - Module interfaces

### Functional Programming Resources
- Hadley Wickham: [Advanced R - Functional Programming](https://adv-r.hadley.nz/fp.html)
- RStudio: [Pipes in R](https://r4ds.had.co.nz/pipes.html)
- [Purrr Package](https://purrr.tidyverse.org/) - Functional programming toolkit

### Pipeline Pattern Examples
- [targets package](https://books.ropensci.org/targets/) - R pipeline framework
- [drake package](https://docs.ropensci.org/drake/) - Predecessor to targets
- [recipes package](https://recipes.tidymodels.org/) - Feature engineering pipeline

---

## Appendix: Code Examples

### A. Current vs. Proposed Comparison

**Current (Option B)**:
```r
# 152 lines of orchestration
create_validated_dataset <- function(...) {
  cat("Starting...\n")

  validate_input_parameters(...)

  loaded_data <- load_and_filter_data(...)
  cat("Loaded\n")

  validate_required_columns(...)
  cat("Validated\n")

  raw_metadata <- load_optional_raw_metadata(...)

  processed_data <- loaded_data$data %>%
    handle_technical_replicates(...) %>%
    select_essential_columns_pipeline(...)

  # ... 100 more lines
}
```

**Proposed (Option C)**:
```r
# 40 lines of pure pipeline
create_validated_dataset <- function(..., verbose = TRUE) {

  if (verbose) print_stage_header("STAGE 1: Data Validation")

  proteome_file %>%
    validate_file() %>%
    load_data() %>%
    apply_filters(rt_range, mz_range) %>%
    validate_schema() %>%
    handle_replicates(...) %>%
    select_columns() %>%
    validate_quality() %>%
    build_validated_data(start_time, quality_threshold, raw_metadata, verbose)
}
```

### B. Attribute-Based Metadata Flow

```r
# Step 1: Load with metadata
data <- load_data(file_path)
# Attributes: load_time_sec, file_format

# Step 2: Add more metadata
data <- add_metadata(data, n_rows = nrow(data))
# Attributes: load_time_sec, file_format, n_rows

# Step 3: Extract all metadata
meta <- extract_metadata(data)
# List: list(load_time_sec = 0.5, file_format = "parquet", n_rows = 1000)
```

---

**End of Document**
