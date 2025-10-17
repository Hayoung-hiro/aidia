# System Architecture Document
# DIA Window Optimizer v2.0

**Version**: 2.0.0
**Last Updated**: 2025-10-13
**Status**: Design Complete

---

## 목차

1. [아키텍처 개요](#아키텍처-개요)
2. [시스템 구성요소](#시스템-구성요소)
3. [데이터 흐름](#데이터-흐름)
4. [핵심 알고리즘](#핵심-알고리즘)
5. [확장성 설계](#확장성-설계)
6. [성능 최적화](#성능-최적화)
7. [오류 처리 전략](#오류-처리-전략)

---

## 아키텍처 개요

### 설계 원칙

1. **모듈화 (Modularity)**
   - 각 Stage는 독립적으로 실행 및 테스트 가능
   - 명확한 입출력 계약 (API Specification)
   - 낮은 결합도, 높은 응집도

2. **파이프라인 패턴 (Pipeline Pattern)**
   - 각 Stage는 이전 Stage의 출력을 입력으로 사용
   - 순차적 데이터 변환
   - 각 단계에서 데이터 검증

3. **전략 패턴 (Strategy Pattern)**
   - m/z range 최적화: 4가지 전략 (Quantile, Smoothing, Outlier, Coverage)
   - Window generation: 3가지 모드 (Fixed, Overlapped, Variable)
   - 런타임에 전략 선택 가능

4. **실패 격리 (Failure Isolation)**
   - 각 Stage의 오류가 전체 시스템에 영향 최소화
   - Graceful degradation (예: Raw metadata 실패 시 계속 진행)
   - 명확한 오류 메시지 및 복구 제안

### 시스템 레이어

```
┌─────────────────────────────────────────┐
│  Presentation Layer                     │  - CLI interface
│  (main.R, quick_optimize())            │  - Progress reporting
├─────────────────────────────────────────┤
│  Business Logic Layer                   │  - Stage orchestration
│  (4-Stage Pipeline)                    │  - Validation logic
│                                         │  - Optimization algorithms
├─────────────────────────────────────────┤
│  Data Access Layer                      │  - File I/O (Parquet, TSV)
│  (data_loader.R, method_writer.R)     │  - Raw file metadata
├─────────────────────────────────────────┤
│  Utility Layer                          │  - DPPP calculation
│  (dppp_calculator.R, utils.R)         │  - Statistics utilities
│                                         │  - Instrument configs
├─────────────────────────────────────────┤
│  Visualization Layer                    │  - ggplot2 plotting
│  (visualizer.R, stage4_visualization) │  - PDF report generation
└─────────────────────────────────────────┘
```

---

## 시스템 구성요소

### 1. Stage 1: Data Validation

#### 책임 (Responsibilities)
- DIA-NN output 로딩 및 파싱
- Raw file metadata 추출 (선택)
- 데이터 품질 검증
- Outlier 감지 및 보고

#### 주요 컴포넌트

```r
# Component Diagram
┌─────────────────────────────────────┐
│  Stage1Controller                   │
│  (create_validated_dataset)        │
└────────┬───────────────┬───────────┘
         │               │
    ┌────▼────┐    ┌────▼──────┐
    │ Loader  │    │ Validator │
    └────┬────┘    └────┬──────┘
         │              │
    ┌────▼────────────┐ │
    │ FileTypeDetector│ │
    │ ParquetReader   │ │
    │ TSVReader       │ │
    │ CSVReader       │ │
    └─────────────────┘ │
                        │
                   ┌────▼──────────┐
                   │ QualityChecker│
                   │ OutlierDetect │
                   └───────────────┘
```

#### 의사결정 로직

```r
# 파일 형식 자동 감지
detect_file_format <- function(file_path) {
  ext <- tools::file_ext(file_path)

  format <- switch(tolower(ext),
    "parquet" = "parquet",
    "tsv" = "tsv",
    "txt" = "tsv",
    "csv" = "csv",
    stop("Unsupported file format")
  )

  return(format)
}

# Quality score 계산
calculate_quality_score <- function(validation_results) {
  fwhm_outlier_rate <- validation_results$fwhm_outliers$pct_outliers
  rt_issue_rate <- length(validation_results$rt_issues$out_of_range) / n_total
  mz_issue_rate <- validation_results$mz_issues$n_invalid / n_total

  quality_score <- 1.0 - (
    0.4 * fwhm_outlier_rate +
    0.3 * rt_issue_rate +
    0.3 * mz_issue_rate
  )

  return(max(0, quality_score))  # Clamp to [0, 1]
}
```

---

### 2. Stage 2: DPPP Diagnosis

#### 책임
- 현재 DPPP 분포 계산
- Satisfaction ratio 분석
- 최적 scan_time 추천
- Trade-off 분석

#### 핵심 알고리즘: Scan Time Optimization

```r
# Grid Search with Constraint Checking
optimize_scan_time <- function(
  validated_data,
  target_dppp,
  dppp_tolerance,
  instrument_config
) {

  # Define search space
  scan_time_candidates <- seq(1.0, 3.0, by = 0.05)

  # Objective: Maximize satisfaction ratio
  results <- sapply(scan_time_candidates, function(st) {

    # Calculate window count for this scan_time
    n_windows <- calculate_window_count_from_scantime(st, instrument_config)

    # Check instrument feasibility
    scan_rate <- n_windows / st
    if (scan_rate > instrument_config$max_scan_rate) {
      return(-Inf)  # Infeasible
    }

    # Calculate DPPP distribution
    fwhm_seconds <- validated_data$data$FWHM * 60
    dppp_dist <- (fwhm_seconds * 1.7) / st

    # Calculate satisfaction ratio
    satisfied <- abs(dppp_dist - target_dppp) <= dppp_tolerance
    satisfaction <- sum(satisfied) / length(satisfied)

    return(satisfaction)
  })

  # Find optimal
  optimal_idx <- which.max(results)
  optimal_scan_time <- scan_time_candidates[optimal_idx]
  optimal_satisfaction <- results[optimal_idx]

  return(list(
    scan_time = optimal_scan_time,
    satisfaction = optimal_satisfaction
  ))
}
```

#### Trade-off Analysis

```
     Scan Time ↑
           │
           │    ┌───────────────┐
           │    │ More Windows  │ ← Better ID
           │    └───────────────┘
           │           ↓
           │    Lower DPPP ← Worse Quant
           │
     ──────┴─────────────────────────→
                Scan Time

Trade-off Surface:
- Short scan_time → Many windows, Low DPPP → Good for ID
- Long scan_time → Few windows, High DPPP → Good for Quant
```

---

### 3. Stage 3: Window Optimization

#### 3-Phase Architecture

```
Phase A: Window Count Determination
    ↓
Phase B: RT Binning (기존 활용)
    ↓
Phase C: m/z Range Optimization (4 Strategies)
    ↓
Phase D: Window Generation (3 Modes)
```

#### Phase C: m/z Range Strategy Selection

```r
# Strategy Pattern Implementation
MzRangeStrategy <- R6::R6Class("MzRangeStrategy",
  public = list(
    optimize = function(data, params) {
      stop("Abstract method")
    }
  )
)

QuantileStrategy <- R6::R6Class("QuantileStrategy",
  inherit = MzRangeStrategy,
  public = list(
    optimize = function(data, params) {
      mz_min <- quantile(data$Precursor.Mz, params$lower_quantile)
      mz_max <- quantile(data$Precursor.Mz, params$upper_quantile)
      return(list(mz_min = mz_min, mz_max = mz_max))
    }
  )
)

# ... SmoothingStrategy, OutlierStrategy, CoverageStrategy

# Strategy selector
select_mz_strategy <- function(strategy_name) {
  strategies <- list(
    "quantile" = QuantileStrategy$new(),
    "smoothing" = SmoothingStrategy$new(),
    "outlier_removal" = OutlierStrategy$new(),
    "coverage_based" = CoverageStrategy$new()
  )

  return(strategies[[strategy_name]])
}
```

#### Phase D: Window Generation Modes

**Largest Remainder Method (Variable Mode)**

```r
# Exact window count allocation
allocate_windows_exact <- function(n_windows, precursor_counts) {

  total_precursors <- sum(precursor_counts)
  n_bins <- length(precursor_counts)

  # Step 1: Calculate exact quotas
  exact_quotas <- (n_windows * precursor_counts) / total_precursors

  # Step 2: Assign floor values
  floor_allocations <- floor(exact_quotas)

  # Step 3: Calculate remainders
  remainders <- exact_quotas - floor_allocations

  # Step 4: Distribute remaining windows
  windows_allocated <- sum(floor_allocations)
  windows_remaining <- n_windows - windows_allocated

  if (windows_remaining > 0) {
    # Sort by remainder (descending)
    remainder_order <- order(remainders, decreasing = TRUE)
    top_bins <- remainder_order[1:windows_remaining]

    # Add 1 window to each top bin
    floor_allocations[top_bins] <- floor_allocations[top_bins] + 1
  }

  # Verify exact allocation
  stopifnot(sum(floor_allocations) == n_windows)

  return(floor_allocations)
}
```

**알고리즘 비교**

| 모드 | 복잡도 | 정확도 | 유스케이스 |
|------|--------|--------|-----------|
| Fixed | O(1) | 정확 | 단순, 예측 가능 |
| Overlapped | O(n) | 정확 | Ion bleeding 보정 |
| Variable | O(n log n) | 정확 | Density equalization |

---

### 4. Stage 4: Visualization

#### Plot Generation Pipeline

```
Data Preparation
    ↓
ggplot Object Creation
    ↓
Theme Application
    ↓
Multi-panel Arrangement (gridExtra)
    ↓
PDF Export
```

#### Visualization Architecture

```r
# Plot Factory Pattern
PlotFactory <- list(
  create_dppp_density = function(data) {
    ggplot(data, aes(x = dppp)) +
      geom_density(fill = "blue", alpha = 0.5) +
      theme_minimal()
  },

  create_rt_window_size = function(data) {
    ggplot(data, aes(x = rt_bin, y = window_width)) +
      geom_boxplot() +
      theme_minimal()
  },

  # ... other plot creators
)

# Report Assembler
assemble_report <- function(plots, output_file) {
  pdf(output_file, width = 11, height = 8.5)

  # Page 1: Executive Summary
  grid.arrange(
    plots$summary_table,
    plots$key_metrics,
    ncol = 1
  )

  # Page 2-3: Stage 1 Results
  grid.arrange(
    plots$data_quality,
    plots$fwhm_distribution,
    ncol = 2
  )

  # ... more pages

  dev.off()
}
```

---

## 데이터 흐름

### End-to-End Data Flow

```
┌──────────────┐
│ DIA-NN       │
│ output.parquet│
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────┐
│ Stage 1: Data Validation         │
│                                   │
│ Input:  Parquet file             │
│ Output: ValidatedData             │
│   - data: tibble(RT, mz, FWHM)  │
│   - metadata: stats              │
│   - validation_status: QC        │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│ Stage 2: DPPP Diagnosis          │
│                                   │
│ Input:  ValidatedData             │
│         + user_scan_time          │
│ Output: DiagnosisResult           │
│   - current_status: DPPP dist    │
│   - recommendation: optimal_st   │
│   - tradeoff_analysis: curves    │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│ Stage 3: Window Optimization     │
│                                   │
│ Input:  DiagnosisResult           │
│         + instrument_config       │
│                                   │
│ Phase A: n_windows = f(scan_time)│
│ Phase B: RT binning              │
│ Phase C: m/z range optimize      │
│ Phase D: Window generation       │
│                                   │
│ Output: OptimizedWindows          │
│   - windows: tibble(id, mz, RT)  │
│   - statistics: performance      │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│ Stage 4: Visualization           │
│                                   │
│ Input:  All previous outputs     │
│ Output: PDF report + method file │
│   - optimization_report.pdf      │
│   - optimized_windows.csv        │
└──────────────────────────────────┘
```

### State Transitions

```r
# State machine for pipeline execution
PipelineState <- list(
  INITIALIZED = 0,
  STAGE1_COMPLETE = 1,
  STAGE2_COMPLETE = 2,
  STAGE3_COMPLETE = 3,
  STAGE4_COMPLETE = 4,
  FAILED = -1
)

execute_pipeline <- function(config) {
  state <- PipelineState$INITIALIZED

  tryCatch({
    # Stage 1
    validated_data <- create_validated_dataset(config)
    state <- PipelineState$STAGE1_COMPLETE

    # Stage 2
    diagnosis <- generate_diagnosis_report(validated_data, config)
    state <- PipelineState$STAGE2_COMPLETE

    # Stage 3
    optimized_windows <- optimize_windows(diagnosis, config)
    state <- PipelineState$STAGE3_COMPLETE

    # Stage 4
    report <- generate_comprehensive_report(
      validated_data, diagnosis, optimized_windows
    )
    state <- PipelineState$STAGE4_COMPLETE

    return(list(state = state, result = report))

  }, error = function(e) {
    return(list(
      state = PipelineState$FAILED,
      error_at_stage = state,
      error_message = e$message
    ))
  })
}
```

---

## 핵심 알고리즘

### DPPP Calculation

```r
# Spectronaut Standard Implementation
PEAK_WIDTH_FACTOR <- 1.7

calculate_dppp <- function(fwhm_minutes, cycle_time_seconds) {
  # Convert FWHM to seconds
  fwhm_seconds <- fwhm_minutes * 60

  # Apply peak width factor (Spectronaut definition)
  peak_width_seconds <- fwhm_seconds * PEAK_WIDTH_FACTOR

  # DPPP = peak width / cycle time
  dppp <- peak_width_seconds / cycle_time_seconds

  return(dppp)
}

# Vectorized version for efficiency
calculate_dppp_distribution <- function(fwhm_vector, cycle_time) {
  fwhm_seconds <- fwhm_vector * 60
  peak_width_seconds <- fwhm_seconds * PEAK_WIDTH_FACTOR
  dppp_distribution <- peak_width_seconds / cycle_time

  return(dppp_distribution)
}

# Performance: O(n) where n = number of precursors
# Memory: O(n) for output vector
```

### Density Equalization Algorithm

```r
# Objective: Distribute precursors uniformly across windows
equalize_density <- function(precursor_mz, n_windows) {

  # Step 1: Sort precursors by m/z
  sorted_mz <- sort(precursor_mz)
  n_precursors <- length(sorted_mz)

  # Step 2: Calculate target precursors per window
  target_per_window <- n_precursors / n_windows

  # Step 3: Create window boundaries using quantiles
  quantile_probs <- seq(0, 1, length.out = n_windows + 1)
  window_boundaries <- quantile(sorted_mz, probs = quantile_probs)

  # Step 4: Verify uniform distribution
  window_counts <- sapply(1:n_windows, function(i) {
    sum(sorted_mz >= window_boundaries[i] &
        sorted_mz < window_boundaries[i + 1])
  })

  # Coefficient of variation as uniformity measure
  cv <- sd(window_counts) / mean(window_counts)

  return(list(
    boundaries = window_boundaries,
    counts = window_counts,
    cv = cv,
    uniformity_score = 1 - cv  # Higher is better
  ))
}
```

### RT-Dependent m/z Range (DynamicDIA)

```r
# Savitzky-Golay Smoothing for RT-dependent boundaries
smooth_mz_boundaries <- function(rt_bins, mz_boundaries) {

  # Extract raw boundaries
  rt_centers <- sapply(rt_bins, function(b) mean(b$RT.Start))
  mz_min_raw <- sapply(rt_bins, function(b) min(b$Precursor.Mz))
  mz_max_raw <- sapply(rt_bins, function(b) max(b$Precursor.Mz))

  # Apply Savitzky-Golay filter (polynomial smoothing)
  library(prospectr)
  mz_min_smooth <- savitzkyGolay(
    mz_min_raw,
    p = 3,  # Polynomial order
    w = 7,  # Window size
    m = 0   # Derivative order (0 = no derivative)
  )

  mz_max_smooth <- savitzkyGolay(mz_max_raw, p = 3, w = 7, m = 0)

  return(list(
    rt_centers = rt_centers,
    mz_min_raw = mz_min_raw,
    mz_max_raw = mz_max_raw,
    mz_min_smooth = mz_min_smooth,
    mz_max_smooth = mz_max_smooth
  ))
}

# Smoothing reduces outlier impact by ~80%
# Computational complexity: O(n * w) where w = window size
```

---

## 확장성 설계

### 1. 새로운 m/z Range 전략 추가

```r
# Plugin architecture
register_mz_strategy <- function(strategy_name, strategy_function) {
  MZ_STRATEGIES[[strategy_name]] <- strategy_function
}

# Example: 새로운 ML-based 전략 추가
register_mz_strategy("ml_based", function(data, params) {
  # Machine learning-based boundary prediction
  model <- load_ml_model(params$model_path)
  boundaries <- predict(model, data)
  return(boundaries)
})
```

### 2. 새로운 Instrument 지원

```r
# Instrument configuration registry
INSTRUMENT_CONFIGS <- list()

register_instrument <- function(name, config) {
  INSTRUMENT_CONFIGS[[name]] <<- config
}

# Example: 새로운 장비 추가
register_instrument("sciex_7600", list(
  name = "SCIEX 7600 ZenoTOF",
  ms1_time = 20.0,  # ms
  ms2_time = 10.0,  # ms
  max_scan_rate = 50,  # Hz
  cycle_calculation = "sequential"
))
```

### 3. 커스텀 Visualization 추가

```r
# Extensible plot registry
CUSTOM_PLOTS <- list()

register_plot <- function(plot_name, plot_function) {
  CUSTOM_PLOTS[[plot_name]] <<- plot_function
}

# Example: 새로운 plot 추가
register_plot("precursor_charge_distribution", function(data) {
  ggplot(data, aes(x = Charge)) +
    geom_bar() +
    labs(title = "Precursor Charge State Distribution")
})
```

---

## 성능 최적화

### 1. 메모리 효율성

```r
# Large dataset handling strategy
handle_large_dataset <- function(file_path) {

  # 1. Estimate data size
  file_size_mb <- file.info(file_path)$size / 1024^2

  if (file_size_mb > 1000) {  # > 1GB
    warning("Large dataset detected. Using chunked processing.")

    # 2. Chunk-based processing
    chunk_size <- 100000
    results <- process_in_chunks(file_path, chunk_size)

  } else {
    # 3. Load entire dataset
    results <- arrow::read_parquet(file_path)
  }

  return(results)
}

# Memory profiling
monitor_memory <- function(expr) {
  gc()
  mem_before <- pryr::mem_used()

  result <- expr

  gc()
  mem_after <- pryr::mem_used()

  cat(sprintf("Memory used: %.2f MB\n",
              (mem_after - mem_before) / 1024^2))

  return(result)
}
```

### 2. 계산 최적화

```r
# Vectorization for DPPP calculation
# Avoid loops - use vectorized operations

# BAD: Loop-based (slow)
calculate_dppp_loop <- function(fwhm_vector, cycle_time) {
  result <- numeric(length(fwhm_vector))
  for (i in seq_along(fwhm_vector)) {
    result[i] <- (fwhm_vector[i] * 60 * 1.7) / cycle_time
  }
  return(result)
}

# GOOD: Vectorized (fast)
calculate_dppp_vectorized <- function(fwhm_vector, cycle_time) {
  return((fwhm_vector * 60 * 1.7) / cycle_time)
}

# Performance: ~100x faster for large vectors
```

### 3. 병렬 처리

```r
# Parallel processing for independent RT bins
library(parallel)

process_rt_bins_parallel <- function(rt_bins, n_cores = 4) {

  cl <- makeCluster(n_cores)
  clusterExport(cl, c("optimize_rt_bin", "calculate_dppp"))

  results <- parLapply(cl, rt_bins, function(bin) {
    optimize_rt_bin(bin)
  })

  stopCluster(cl)

  return(results)
}

# Performance: ~3x faster with 4 cores
# Use for >10 RT bins
```

---

## 오류 처리 전략

### 1. 계층적 오류 처리

```r
# Level 1: Function-level validation
validate_input <- function(data, param_name) {
  if (is.null(data)) {
    stop(sprintf("%s cannot be NULL", param_name))
  }
  if (!is.numeric(data) && !is.data.frame(data)) {
    stop(sprintf("%s must be numeric or data.frame", param_name))
  }
}

# Level 2: Stage-level error handling
execute_stage <- function(stage_func, ...) {
  tryCatch({
    result <- stage_func(...)
    return(list(success = TRUE, result = result))

  }, error = function(e) {
    return(list(
      success = FALSE,
      error = e$message,
      traceback = sys.calls()
    ))
  })
}

# Level 3: Pipeline-level graceful degradation
execute_pipeline_safe <- function(config) {

  stages <- list(
    stage1 = create_validated_dataset,
    stage2 = generate_diagnosis_report,
    stage3 = optimize_windows,
    stage4 = generate_comprehensive_report
  )

  results <- list()

  for (stage_name in names(stages)) {
    stage_result <- execute_stage(stages[[stage_name]], ...)

    if (!stage_result$success) {
      warning(sprintf("Stage %s failed: %s",
                      stage_name, stage_result$error))

      # Attempt recovery or skip optional stages
      if (stage_name == "stage4") {
        # Stage 4 is optional - continue
        next
      } else {
        # Critical stage - abort
        stop(sprintf("Critical stage %s failed", stage_name))
      }
    }

    results[[stage_name]] <- stage_result$result
  }

  return(results)
}
```

### 2. 사용자 친화적 오류 메시지

```r
# Error message formatter
format_error <- function(error_type, details) {

  messages <- list(
    "file_not_found" = sprintf(
      "❌ File not found: %s\n" +
      "💡 Suggestion: Check file path and permissions",
      details$file_path
    ),

    "invalid_dppp_range" = sprintf(
      "❌ Invalid DPPP target: %.2f\n" +
      "💡 Suggestion: DPPP should be between 1.0 and 10.0\n" +
      "   - For Quant mode: use 7.0\n" +
      "   - For ID mode: use 1.5",
      details$dppp_value
    ),

    "scan_rate_exceeded" = sprintf(
      "❌ Scan rate (%.1f Hz) exceeds instrument limit (%.1f Hz)\n" +
      "💡 Suggestions:\n" +
      "   1. Increase scan_time to %.2f seconds\n" +
      "   2. Or reduce window count to %d",
      details$required_rate,
      details$max_rate,
      details$suggested_scan_time,
      details$suggested_window_count
    )
  )

  return(messages[[error_type]])
}
```

---

## 테스트 전략

### 단위 테스트 구조

```r
# tests/test_stage1.R
library(testthat)

test_that("Data loading handles missing columns", {
  # Arrange
  mock_data <- tibble(RT.Start = c(1, 2, 3))  # Missing Precursor.Mz

  # Act & Assert
  expect_error(
    validate_required_columns(mock_data),
    regexp = "Missing required column: Precursor.Mz"
  )
})

test_that("FWHM outlier detection works correctly", {
  # Arrange
  data <- create_mock_data_with_outliers()

  # Act
  result <- validate_data_quality(data)

  # Assert
  expect_gt(result$fwhm_outliers$n_outliers, 0)
  expect_lt(result$quality_score, 1.0)
})
```

### 통합 테스트

```r
# tests/test_integration.R
test_that("End-to-end pipeline executes successfully", {
  # Arrange
  config <- create_test_config()

  # Act
  result <- execute_pipeline(config)

  # Assert
  expect_equal(result$state, PipelineState$STAGE4_COMPLETE)
  expect_true(file.exists(result$result$report_file))
})
```

---

## 부록

### 성능 벤치마크 (예상치)

| 작업 | Dataset Size | 예상 시간 | 메모리 |
|------|--------------|----------|--------|
| Data Loading | 1M precursors (Parquet) | < 30초 | < 500 MB |
| DPPP Calculation | 1M precursors | < 10초 | < 200 MB |
| Window Optimization | 1M precursors, 200 windows | < 60초 | < 800 MB |
| Report Generation | Full pipeline | < 30초 | < 300 MB |
| **Total** | **1M precursors** | **< 2분** | **< 2 GB** |

### 확장 가능한 컴포넌트

1. **MzRangeOptimizer**: 새로운 전략 플러그인
2. **WindowGenerator**: 새로운 generation 모드
3. **InstrumentConfig**: 새로운 장비 지원
4. **VisualizationEngine**: 커스텀 plot 추가
5. **ReportFormatter**: 다양한 출력 형식 (HTML, Excel)

---

**End of Architecture Document**
