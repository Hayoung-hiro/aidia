# Phase 1: Data Validation
# Development Guide

**담당자**: [할당 대기]
**예상 기간**: 2-3일
**우선순위**: P0 (최우선)
**상태**: 🔴 개발 대기

---

## 목차

1. [개요](#개요)
2. [기능 요구사항](#기능-요구사항)
3. [개발 작업](#개발-작업)
4. [테스트 가이드](#테스트-가이드)
5. [완료 조건](#완료-조건)

---

## 개요

### 목적

DIA-NN output 파일과 Raw file (선택)을 로딩하고, 데이터 품질을 검증하여 후속 Stage에서 사용할 수 있는 깨끗한 데이터셋을 생성합니다.

### 입력

```r
# Required
proteome_file <- "path/to/report.parquet"  # or .tsv, .csv

# Optional
raw_file_dir <- "path/to/rawfiles/"
rt_range <- c(10, 110)  # RT filtering
mz_range <- c(380, 980)  # m/z filtering
```

### 출력

```r
structure(
  list(
    data = tibble(
      RT.Start = numeric(),
      Precursor.Mz = numeric(),
      FWHM = numeric(),
      ...  # other columns
    ),
    metadata = list(
      n_precursors = 1190706,
      rt_range = c(10.5, 112.3),
      mz_range = c(382.1, 978.4),
      fwhm_stats = list(mean = 0.3, median = 0.29, ...),
      has_raw_metadata = FALSE
    ),
    validation_status = list(
      all_passed = TRUE,
      quality_score = 0.95,
      warnings = character(),
      errors = character()
    )
  ),
  class = c("ValidatedData", "list")
)
```

---

## 기능 요구사항

### FR-1.1: DIA-NN 데이터 로딩

#### 구현 함수

```r
#' Load DIA-NN output file
#'
#' @param proteome_file Path to DIA-NN output (.parquet, .tsv, .csv)
#' @param rt_range Optional RT filtering range c(min, max) in minutes
#' @param mz_range Optional m/z filtering range c(min, max) in Da
#' @param required_columns Required column names
#' @return List with data and metadata
load_diann_data <- function(
  proteome_file,
  rt_range = NULL,
  mz_range = NULL,
  required_columns = c("RT.Start", "Precursor.Mz", "FWHM")
) {

  # TODO: Implement
  # 1. Detect file format
  # 2. Load data (arrow::read_parquet, readr::read_tsv, readr::read_csv)
  # 3. Apply filtering
  # 4. Return list

  stop("Not implemented")
}
```

#### 구현 체크리스트

- [ ] 파일 존재 확인
- [ ] 파일 형식 자동 감지 (.parquet, .tsv, .csv)
- [ ] 적절한 리더 함수 선택
  - Parquet: `arrow::read_parquet()`
  - TSV: `readr::read_tsv()`
  - CSV: `readr::read_csv()`
- [ ] RT 범위 필터링 (if specified)
- [ ] m/z 범위 필터링 (if specified)
- [ ] 메타데이터 수집 (file size, row counts, load time)
- [ ] Progress bar 표시 (large files)

#### 파일 형식 감지 로직

```r
detect_file_format <- function(file_path) {
  ext <- tolower(tools::file_ext(file_path))

  format <- switch(ext,
    "parquet" = "parquet",
    "tsv" = "tsv",
    "txt" = "tsv",  # Assume txt is TSV
    "csv" = "csv",
    stop(sprintf("Unsupported file format: .%s", ext))
  )

  return(format)
}
```

#### 오류 처리

```r
# File not found
if (!file.exists(proteome_file)) {
  stop(sprintf(
    "File not found: %s\n" +
    "Please check the file path and try again.",
    proteome_file
  ))
}

# Empty file
if (nrow(data) == 0) {
  stop("Loaded data is empty. Please check the input file.")
}

# File too large (warning)
file_size_mb <- file.info(proteome_file)$size / 1024^2
if (file_size_mb > 1000) {
  warning(sprintf(
    "Large file detected (%.1f MB). Loading may take a while...",
    file_size_mb
  ))
}
```

---

### FR-1.2: Raw File Metadata 추출 (선택)

#### 구현 함수

```r
#' Load raw file metadata (injection times)
#'
#' @param raw_file_dir Directory containing .raw files
#' @param file_pattern Regex pattern for raw files
#' @return List with injection time statistics
load_raw_metadata <- function(
  raw_file_dir,
  file_pattern = "\\.raw$"
) {

  # TODO: Implement
  # 1. Find raw files
  # 2. Extract injection times (MS1, MS2)
  # 3. Calculate statistics
  # 4. Return list or NULL if fails

  stop("Not implemented")
}
```

#### 구현 체크리스트

- [ ] 디렉토리 존재 확인
- [ ] Raw file 목록 찾기
- [ ] Raw file metadata 추출 (rawrr 패키지 활용 고려)
- [ ] Injection time 통계 계산
  - Median, mean, percentiles
  - IT efficiency (median_IT / maxIT)
- [ ] Actual cycle time 계산
- [ ] Graceful failure (raw file 읽기 실패 시 NULL 반환)

#### 참고: Raw File 처리

```r
# Option 1: rawrr 패키지 사용 (권장)
library(rawrr)
raw_data <- readFileHeader(raw_file_path)

# Option 2: MSstats 패키지
# Option 3: Custom parser (복잡함)

# Fallback: Raw metadata 없이 진행
if (is.null(raw_metadata)) {
  warning("Raw metadata extraction failed. Continuing without it.")
  return(NULL)
}
```

---

### FR-1.3: 데이터 품질 검증

#### 구현 함수

```r
#' Validate data quality
#'
#' @param data Loaded DIA-NN data
#' @param fwhm_outlier_iqr IQR multiplier for FWHM outliers
#' @param rt_outlier_iqr IQR multiplier for RT outliers
#' @param mz_valid_range Valid m/z range c(min, max)
#' @return List with validation results
validate_data_quality <- function(
  data,
  fwhm_outlier_iqr = 1.5,
  rt_outlier_iqr = 3.0,
  mz_valid_range = c(50, 5000)
) {

  # TODO: Implement
  # 1. FWHM outlier detection (IQR method)
  # 2. RT range validation
  # 3. m/z range validation
  # 4. Calculate quality score
  # 5. Generate recommendations

  stop("Not implemented")
}
```

#### FWHM Outlier Detection (IQR Method)

```r
detect_fwhm_outliers <- function(fwhm_vector, iqr_multiplier = 1.5) {

  Q1 <- quantile(fwhm_vector, 0.25, na.rm = TRUE)
  Q3 <- quantile(fwhm_vector, 0.75, na.rm = TRUE)
  IQR <- Q3 - Q1

  lower_bound <- Q1 - iqr_multiplier * IQR
  upper_bound <- Q3 + iqr_multiplier * IQR

  outlier_indices <- which(fwhm_vector < lower_bound | fwhm_vector > upper_bound)
  outlier_values <- fwhm_vector[outlier_indices]

  return(list(
    indices = outlier_indices,
    values = outlier_values,
    n_outliers = length(outlier_indices),
    pct_outliers = length(outlier_indices) / length(fwhm_vector)
  ))
}
```

#### Quality Score 계산

```r
calculate_quality_score <- function(validation_results) {

  # Weight factors
  W_FWHM <- 0.4
  W_RT <- 0.3
  W_MZ <- 0.3

  # Component scores (0-1, lower is worse)
  fwhm_score <- 1 - min(validation_results$fwhm_outliers$pct_outliers, 1.0)
  rt_score <- 1 - min(validation_results$rt_issues$pct_issues, 1.0)
  mz_score <- 1 - min(validation_results$mz_issues$pct_invalid, 1.0)

  # Weighted average
  quality_score <- W_FWHM * fwhm_score +
                   W_RT * rt_score +
                   W_MZ * mz_score

  return(max(0, min(1, quality_score)))  # Clamp to [0, 1]
}
```

---

### FR-1.4: ValidatedData 생성 (메인 함수)

#### 구현 함수

```r
#' Create validated dataset (Stage 1 main function)
#'
#' @param proteome_file Path to DIA-NN output
#' @param raw_file_dir Path to raw files directory (optional)
#' @param rt_range RT filtering range
#' @param mz_range m/z filtering range
#' @param enable_raw_metadata Whether to load raw metadata
#' @param quality_threshold Minimum quality score (0-1)
#' @return ValidatedData object
create_validated_dataset <- function(
  proteome_file,
  raw_file_dir = NULL,
  rt_range = NULL,
  mz_range = NULL,
  enable_raw_metadata = FALSE,
  quality_threshold = 0.8
) {

  cat("\n╔═══════════════════════════════════════════════╗\n")
  cat("║   STAGE 1: Data Validation                   ║\n")
  cat("╚═══════════════════════════════════════════════╝\n\n")

  # Step 1: Load DIA-NN data
  cat("Step 1: Loading DIA-NN data...\n")
  loaded_data <- load_diann_data(proteome_file, rt_range, mz_range)
  cat(sprintf("✓ Loaded %d precursors\n", nrow(loaded_data$data)))

  # Step 2: Validate required columns
  cat("\nStep 2: Validating required columns...\n")
  validate_required_columns(loaded_data$data)
  cat("✓ All required columns present\n")

  # Step 3: Load raw metadata (if requested)
  raw_metadata <- NULL
  if (enable_raw_metadata && !is.null(raw_file_dir)) {
    cat("\nStep 3: Loading raw file metadata...\n")
    raw_metadata <- load_raw_metadata(raw_file_dir)

    if (!is.null(raw_metadata)) {
      cat("✓ Raw metadata loaded\n")
    } else {
      warning("Raw metadata extraction failed")
    }
  }

  # Step 4: Validate data quality
  cat("\nStep 4: Validating data quality...\n")
  quality_results <- validate_data_quality(loaded_data$data)
  quality_score <- calculate_quality_score(quality_results)
  cat(sprintf("✓ Quality score: %.2f\n", quality_score))

  # Check quality threshold
  if (quality_score < quality_threshold) {
    warning(sprintf(
      "Data quality score (%.2f) below threshold (%.2f)",
      quality_score, quality_threshold
    ))
  }

  # Step 5: Construct ValidatedData object
  cat("\nStep 5: Creating ValidatedData object...\n")

  validated_data <- structure(
    list(
      data = loaded_data$data,
      metadata = list(
        n_precursors = nrow(loaded_data$data),
        rt_range = range(loaded_data$data$RT.Start, na.rm = TRUE),
        mz_range = range(loaded_data$data$Precursor.Mz, na.rm = TRUE),
        fwhm_stats = list(
          mean = mean(loaded_data$data$FWHM, na.rm = TRUE),
          median = median(loaded_data$data$FWHM, na.rm = TRUE),
          sd = sd(loaded_data$data$FWHM, na.rm = TRUE),
          q25 = quantile(loaded_data$data$FWHM, 0.25, na.rm = TRUE),
          q75 = quantile(loaded_data$data$FWHM, 0.75, na.rm = TRUE)
        ),
        has_raw_metadata = !is.null(raw_metadata),
        raw_metadata = raw_metadata
      ),
      validation_status = list(
        all_passed = quality_score >= quality_threshold,
        quality_score = quality_score,
        n_warnings = length(quality_results$warnings),
        n_errors = length(quality_results$errors),
        warnings = quality_results$warnings,
        errors = quality_results$errors
      )
    ),
    class = c("ValidatedData", "list")
  )

  cat("✓ ValidatedData object created\n")
  cat("\n═══ STAGE 1 COMPLETE ═══\n")

  return(validated_data)
}
```

---

## 개발 작업

### 파일 생성

```r
# Create module file
R/stage1_data_validation.R

# Content structure:
# 1. Package dependencies
# 2. Helper functions
# 3. Main functions (load_diann_data, validate_data_quality, etc.)
# 4. S3 methods (print.ValidatedData, summary.ValidatedData)
```

### 필수 패키지

```r
# Add to DESCRIPTION or install manually
library(arrow)        # Parquet reading
library(readr)        # TSV/CSV reading
library(dplyr)        # Data manipulation
library(tibble)       # Modern data frames

# Optional
library(rawrr)        # Raw file reading (if available)
```

### S3 Methods 구현

```r
#' Print method for ValidatedData
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
}

#' Summary method for ValidatedData
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
  cat(sprintf("  Mean: %.3f min\n", object$metadata$fwhm_stats$mean))
  cat(sprintf("  Median: %.3f min\n", object$metadata$fwhm_stats$median))
  cat(sprintf("  SD: %.3f min\n", object$metadata$fwhm_stats$sd))

  cat("\nValidation Status:\n")
  cat(sprintf("  Quality score: %.2f\n", object$validation_status$quality_score))
  cat(sprintf("  Warnings: %d\n", object$validation_status$n_warnings))
  cat(sprintf("  Errors: %d\n", object$validation_status$n_errors))

  if (object$validation_status$n_warnings > 0) {
    cat("\nWarnings:\n")
    for (w in object$validation_status$warnings) {
      cat(sprintf("  ⚠️  %s\n", w))
    }
  }
}
```

---

## 테스트 가이드

### 단위 테스트

```r
# tests/test_stage1.R
library(testthat)

test_that("File format detection works", {
  expect_equal(detect_file_format("data.parquet"), "parquet")
  expect_equal(detect_file_format("data.tsv"), "tsv")
  expect_equal(detect_file_format("data.csv"), "csv")
  expect_equal(detect_file_format("data.txt"), "tsv")  # Assume TSV

  expect_error(detect_file_format("data.xlsx"))
})

test_that("FWHM outlier detection works", {
  # Create data with known outliers
  fwhm <- c(rep(0.3, 100), 5.0, 0.01)  # 2 outliers

  result <- detect_fwhm_outliers(fwhm, iqr_multiplier = 1.5)

  expect_equal(result$n_outliers, 2)
  expect_true(5.0 %in% result$values)
  expect_true(0.01 %in% result$values)
})

test_that("Quality score is in valid range", {
  mock_results <- list(
    fwhm_outliers = list(pct_outliers = 0.05),
    rt_issues = list(pct_issues = 0.02),
    mz_issues = list(pct_invalid = 0.01)
  )

  score <- calculate_quality_score(mock_results)

  expect_gte(score, 0)
  expect_lte(score, 1)
})

test_that("ValidatedData creation succeeds with valid input", {
  # Use mock data
  mock_file <- create_mock_diann_file()

  result <- create_validated_dataset(mock_file)

  expect_s3_class(result, "ValidatedData")
  expect_true(result$validation_status$all_passed)
  expect_gt(result$metadata$n_precursors, 0)
})
```

### Mock 데이터 생성

```r
# tests/mocks/mock_stage1_output.R
create_mock_diann_file <- function(n_precursors = 10000, output_file = tempfile(fileext = ".parquet")) {

  set.seed(42)

  mock_data <- tibble(
    RT.Start = runif(n_precursors, 10, 110),
    Precursor.Mz = rnorm(n_precursors, 650, 150),
    FWHM = abs(rnorm(n_precursors, 0.3, 0.05)),
    Charge = sample(2:4, n_precursors, replace = TRUE),
    Protein.Names = paste0("Protein_", sample(1:1000, n_precursors, replace = TRUE))
  )

  # Write to parquet
  arrow::write_parquet(mock_data, output_file)

  return(output_file)
}

#' Create mock Stage 1 output for downstream stages
create_mock_stage1_output <- function(n_precursors = 100000) {

  set.seed(42)

  structure(
    list(
      data = tibble(
        RT.Start = runif(n_precursors, 10, 110),
        Precursor.Mz = rnorm(n_precursors, 650, 150),
        FWHM = abs(rnorm(n_precursors, 0.3, 0.05))
      ),
      metadata = list(
        n_precursors = n_precursors,
        rt_range = c(10, 110),
        mz_range = c(380, 980),
        fwhm_stats = list(
          mean = 0.3,
          median = 0.29,
          sd = 0.05,
          q25 = 0.27,
          q75 = 0.33
        ),
        has_raw_metadata = FALSE,
        raw_metadata = NULL
      ),
      validation_status = list(
        all_passed = TRUE,
        quality_score = 0.95,
        n_warnings = 0,
        n_errors = 0,
        warnings = character(),
        errors = character()
      )
    ),
    class = c("ValidatedData", "list")
  )
}
```

### 통합 테스트

```r
test_that("End-to-end Stage 1 pipeline works", {
  # Create mock input
  mock_file <- create_mock_diann_file(n_precursors = 1000)

  # Run full pipeline
  result <- create_validated_dataset(
    proteome_file = mock_file,
    quality_threshold = 0.8
  )

  # Assertions
  expect_s3_class(result, "ValidatedData")
  expect_equal(nrow(result$data), 1000)
  expect_gte(result$validation_status$quality_score, 0.8)

  # Cleanup
  unlink(mock_file)
})
```

---

## 완료 조건 (Definition of Done)

### 기능 완료

- [ ] `load_diann_data()` 구현 및 테스트
  - [ ] Parquet, TSV, CSV 모두 지원
  - [ ] RT/m/z 필터링 동작
  - [ ] Progress bar 표시 (large files)

- [ ] `load_raw_metadata()` 구현 및 테스트 (선택)
  - [ ] Raw file 감지
  - [ ] Injection time 추출
  - [ ] Graceful failure

- [ ] `validate_data_quality()` 구현 및 테스트
  - [ ] FWHM outlier detection
  - [ ] RT validation
  - [ ] m/z validation
  - [ ] Quality score 계산

- [ ] `create_validated_dataset()` 구현 및 테스트
  - [ ] 모든 하위 함수 통합
  - [ ] ValidatedData 객체 생성
  - [ ] 진행 상황 출력

- [ ] S3 methods 구현
  - [ ] print.ValidatedData
  - [ ] summary.ValidatedData

### 테스트 완료

- [ ] 단위 테스트 커버리지 > 80%
- [ ] 통합 테스트 통과
- [ ] Mock 데이터 생성 함수 작성
- [ ] Stage 2에서 사용할 fixture 생성 (`tests/fixtures/stage1_output.rds`)

### 문서화 완료

- [ ] 함수 roxygen2 문서화
- [ ] 예제 코드 작성
- [ ] 오류 메시지 명확화

### 코드 품질

- [ ] Lint 통과 (lintr 패키지)
- [ ] 코드 리뷰 완료
- [ ] 성능 테스트 (1M precursors < 30초)

---

## 참고 자료

- [API Specification](../API_SPECIFICATION.md#stage-1-data-validation)
- [Architecture Document](../ARCHITECTURE.md#1-stage-1-data-validation)
- [PRD](../PRD.md#31-stage-1-데이터-검증-data-validation)

---

**End of Phase 1 Development Guide**
