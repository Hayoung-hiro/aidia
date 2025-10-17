# Phase 3C: m/z Range Optimization - Development Guide

**Version**: 1.0
**Last Updated**: 2025-10-13
**Status**: 🔴 개발 대기
**Priority**: ⭐⭐⭐ 우선순위 4
**Estimated Duration**: 4-5일

---

## 📋 목차

1. [개요](#개요)
2. [Phase 3C 목표](#phase-3c-목표)
3. [입출력 스펙](#입출력-스펙)
4. [최적화 전략](#최적화-전략)
5. [구현 가이드](#구현-가이드)
6. [테스트 전략](#테스트-전략)
7. [Definition of Done](#definition-of-done)

---

## 개요

### Phase 3C의 역할

**m/z Range Optimization**은 각 RT segment에서 isolation window를 배치할 최적의 m/z 범위를 결정하는 단계입니다.

**핵심 철학**:
- **다양한 전략 지원**: Quantile, Smoothing, Outlier removal, Coverage-based
- **DynamicDIA 통합**: Savitzky-Golay smoothing으로 RT-dependent 범위 결정
- **사용자 선택**: 데이터 특성과 목적에 따라 전략 선택 가능

### 주요 개념

```
RT-dependent m/z Range Optimization

각 RT segment마다 독립적인 m/z 범위 결정:

RT Segment 1 (10-15 min): m/z 400-1200
RT Segment 2 (15-20 min): m/z 380-1250
RT Segment 3 (20-25 min): m/z 390-1230
...

목적:
1. Outlier precursor 제외
2. 빈 m/z 영역 제외
3. RT에 따라 변하는 precursor 분포 반영
4. Window 개수를 유의미한 영역에 집중
```

### 입력 데이터

Phase 3B의 출력 (RTBinningResult):
```r
rt_binning_result <- structure(
  list(
    rt_segments = tibble(
      rt_segment_id = integer(),
      rt_start = numeric(),
      rt_end = numeric(),
      n_precursors = integer(),
      precursor_data = list()      # Each segment's precursor data
    ),
    ...
  ),
  class = c("RTBinningResult", "list")
)
```

### 출력 데이터

```r
MzRangeResult <- structure(
  list(
    mz_ranges = tibble(
      rt_segment_id = integer(),       # Matches RT segments
      rt_start = numeric(),
      rt_end = numeric(),
      mz_min = numeric(),              # Optimized m/z minimum
      mz_max = numeric(),              # Optimized m/z maximum
      mz_range_width = numeric(),      # max - min
      n_precursors_covered = integer(), # Precursors within range
      coverage_ratio = numeric()        # Covered / total
    ),

    strategy_comparison = tibble(     # If compare_strategies = TRUE
      strategy = character(),
      mean_coverage = numeric(),
      mean_mz_width = numeric(),
      total_precursors_covered = integer()
    ),

    smoothing_data = list(            # If dynamic = TRUE
      raw_boundaries = tibble(...),   # Before smoothing
      smoothed_boundaries = tibble(...), # After smoothing
      smoothing_method = character(), # "savgol", "movav", "gaussian"
      smoothing_params = list()
    ),

    metadata = list(
      strategy_used = character(),    # "quantile", "smoothing", etc.
      dynamic_mode = logical(),       # TRUE if smoothing applied
      outlier_threshold = numeric(),
      optimization_timestamp = POSIXct()
    )
  ),
  class = c("MzRangeResult", "list")
)
```

---

## Phase 3C 목표

### 주요 기능

1. **4가지 최적화 전략 구현**
   - **Quantile-based**: Percentile 기반 범위 결정 (예: P5-P95)
   - **Smoothing-based** (DynamicDIA): Savitzky-Golay smoothing으로 RT-dependent 범위
   - **Outlier removal**: Statistical outlier 제거 후 범위 결정
   - **Coverage-based**: 목표 coverage 달성하는 최소 범위

2. **DynamicDIA 통합**
   - Savitzky-Golay smoothing (기존 `R/dynamicDIA.R` 활용)
   - Gaussian smoothing
   - Moving average smoothing
   - Raw vs smoothed boundary 비교

3. **전략 비교 및 추천**
   - 각 전략의 coverage, m/z width, precursor count 비교
   - 데이터 특성에 따른 최적 전략 추천
   - 시각화를 통한 전략 평가

4. **RT-dependent m/z Range**
   - RT segment별 독립적 m/z 범위
   - Smooth transitions between segments (smoothing 사용 시)
   - Precursor 분포 변화 반영

### 성공 지표

- [x] 4가지 전략 모두 구현 완료
- [x] DynamicDIA smoothing 통합
- [x] RT segment별 m/z 범위 정확히 계산
- [x] Coverage ratio ≥ 95% 달성
- [x] 전략 비교 및 추천 시스템 동작

---

## 입출력 스펙

### Input Specification

```r
# Phase 3B 출력 (필수)
rt_binning_result <- create_mock_stage3b_output()

# User 입력 파라미터
strategy <- "smoothing"              # "quantile", "smoothing", "outlier", "coverage"
dynamic <- TRUE                      # Use DynamicDIA smoothing
smoothing_method <- "savgol"         # "savgol", "movav", "gaussian"
smoothing_window_size <- 7           # Window size for smoothing
polynomial_order <- 3                # For savgol
target_coverage <- 0.95              # For coverage-based strategy
quantile_lower <- 0.05               # For quantile-based (P5)
quantile_upper <- 0.95               # For quantile-based (P95)
outlier_threshold <- 3.0             # For outlier removal (n*SD)
compare_strategies <- FALSE          # Compare all strategies
```

### Output Specification

```r
# MzRangeResult 구조
mz_range_result <- optimize_mz_ranges(
  rt_binning_result = rt_binning_result,
  strategy = "smoothing",
  dynamic = TRUE,
  smoothing_method = "savgol"
)

# 접근 예시
mz_range_result$mz_ranges$mz_min[1]           # 첫 RT segment의 min m/z
mz_range_result$mz_ranges$mz_max[1]           # 첫 RT segment의 max m/z
mz_range_result$mz_ranges$coverage_ratio[1]   # Coverage ratio
mz_range_result$metadata$strategy_used         # "smoothing"
mz_range_result$smoothing_data$smoothing_method # "savgol"
```

---

## 최적화 전략

### 1. Quantile-Based Strategy

**개념**: Percentile 기반으로 m/z 범위 결정

**알고리즘**:
```r
optimize_range_quantile <- function(
  precursor_data,
  quantile_lower = 0.05,
  quantile_upper = 0.95
) {
  # Extract m/z values
  mz_values <- precursor_data$Precursor.Mz

  # Calculate quantiles
  mz_min <- quantile(mz_values, quantile_lower)
  mz_max <- quantile(mz_values, quantile_upper)

  # Count covered precursors
  covered <- mz_values >= mz_min & mz_values <= mz_max
  n_covered <- sum(covered)
  coverage_ratio <- n_covered / length(mz_values)

  return(list(
    mz_min = mz_min,
    mz_max = mz_max,
    mz_range_width = mz_max - mz_min,
    n_precursors_covered = n_covered,
    coverage_ratio = coverage_ratio
  ))
}
```

**장점**:
- ✅ 간단하고 직관적
- ✅ Outlier에 robust
- ✅ Coverage 명시적 제어

**단점**:
- ❌ RT-dependent 변화 반영 안 함 (dynamic = FALSE)
- ❌ 급격한 boundary 변화 가능

**사용 시나리오**:
- 빠른 탐색 최적화
- 데이터가 균일한 경우
- Outlier가 많은 경우

---

### 2. Smoothing-Based Strategy (DynamicDIA)

**개념**: Savitzky-Golay smoothing으로 RT-dependent 범위 결정

**알고리즘**:
```r
optimize_range_smoothing <- function(
  rt_segments,
  smoothing_method = "savgol",
  smoothing_window_size = 7,
  polynomial_order = 3
) {
  # Step 1: Extract raw boundaries for each RT segment
  raw_boundaries <- rt_segments %>%
    rowwise() %>%
    mutate(
      mz_min_raw = min(precursor_data$Precursor.Mz),
      mz_max_raw = max(precursor_data$Precursor.Mz)
    ) %>%
    select(rt_segment_id, rt_start, rt_end, mz_min_raw, mz_max_raw)

  # Step 2: Apply smoothing to boundaries
  if (smoothing_method == "savgol") {
    # Savitzky-Golay filtering (via prospectr package)
    library(prospectr)
    mz_min_smooth <- savitzkyGolay(
      raw_boundaries$mz_min_raw,
      p = polynomial_order,
      w = smoothing_window_size,
      m = 0
    )
    mz_max_smooth <- savitzkyGolay(
      raw_boundaries$mz_max_raw,
      p = polynomial_order,
      w = smoothing_window_size,
      m = 0
    )
  } else if (smoothing_method == "movav") {
    # Moving average
    mz_min_smooth <- stats::filter(
      raw_boundaries$mz_min_raw,
      rep(1/smoothing_window_size, smoothing_window_size),
      sides = 2
    )
    mz_max_smooth <- stats::filter(
      raw_boundaries$mz_max_raw,
      rep(1/smoothing_window_size, smoothing_window_size),
      sides = 2
    )
  } else if (smoothing_method == "gaussian") {
    # Gaussian smoothing
    mz_min_smooth <- gaussian_smooth(
      raw_boundaries$mz_min_raw,
      sigma = smoothing_window_size / 6
    )
    mz_max_smooth <- gaussian_smooth(
      raw_boundaries$mz_max_raw,
      sigma = smoothing_window_size / 6
    )
  }

  # Step 3: Create smoothed boundaries
  smoothed_boundaries <- raw_boundaries %>%
    mutate(
      mz_min = mz_min_smooth,
      mz_max = mz_max_smooth,
      mz_range_width = mz_max - mz_min
    )

  # Step 4: Calculate coverage for each segment
  smoothed_boundaries <- smoothed_boundaries %>%
    rowwise() %>%
    mutate(
      covered_indices = list(which(
        rt_segments$precursor_data[[rt_segment_id]]$Precursor.Mz >= mz_min &
        rt_segments$precursor_data[[rt_segment_id]]$Precursor.Mz <= mz_max
      )),
      n_precursors_covered = length(covered_indices),
      coverage_ratio = n_precursors_covered /
                       nrow(rt_segments$precursor_data[[rt_segment_id]])
    )

  return(list(
    raw_boundaries = raw_boundaries,
    smoothed_boundaries = smoothed_boundaries,
    smoothing_method = smoothing_method,
    smoothing_params = list(
      window_size = smoothing_window_size,
      polynomial_order = polynomial_order
    )
  ))
}
```

**장점**:
- ✅ RT-dependent 변화 반영
- ✅ Smooth transitions
- ✅ DynamicDIA 논문 검증됨
- ✅ Gradient continuity 보장

**단점**:
- ❌ 파라미터 튜닝 필요 (window_size, polynomial_order)
- ❌ 계산 복잡도 높음
- ❌ Boundary edge effects

**사용 시나리오**:
- RT-dependent precursor 분포
- 부드러운 m/z 변화 필요
- 고품질 데이터

---

### 3. Outlier Removal Strategy

**개념**: Statistical outlier 제거 후 min/max 결정

**알고리즘**:
```r
optimize_range_outlier_removal <- function(
  precursor_data,
  outlier_threshold = 3.0
) {
  # Extract m/z values
  mz_values <- precursor_data$Precursor.Mz

  # Calculate mean and SD
  mz_mean <- mean(mz_values)
  mz_sd <- sd(mz_values)

  # Define outlier boundaries (mean ± threshold*SD)
  lower_bound <- mz_mean - (outlier_threshold * mz_sd)
  upper_bound <- mz_mean + (outlier_threshold * mz_sd)

  # Filter outliers
  inliers <- mz_values >= lower_bound & mz_values <= upper_bound
  mz_inliers <- mz_values[inliers]

  # Determine range from inliers
  mz_min <- min(mz_inliers)
  mz_max <- max(mz_inliers)

  # Calculate coverage
  covered <- mz_values >= mz_min & mz_values <= mz_max
  n_covered <- sum(covered)
  coverage_ratio <- n_covered / length(mz_values)

  return(list(
    mz_min = mz_min,
    mz_max = mz_max,
    mz_range_width = mz_max - mz_min,
    n_precursors_covered = n_covered,
    coverage_ratio = coverage_ratio,
    n_outliers_removed = sum(!inliers)
  ))
}
```

**장점**:
- ✅ Outlier 명시적 제거
- ✅ 정규분포 가정 하에 효과적
- ✅ Threshold 조정 가능

**단점**:
- ❌ 정규분포 가정 필요
- ❌ RT-dependent 변화 반영 안 함
- ❌ Threshold 선택 민감

**사용 시나리오**:
- Contaminant precursor 제거
- 정규분포 데이터
- Outlier threshold 명확한 경우

---

### 4. Coverage-Based Strategy

**개념**: 목표 coverage 달성하는 최소 m/z 범위 결정

**알고리즘**:
```r
optimize_range_coverage_based <- function(
  precursor_data,
  target_coverage = 0.95
) {
  # Extract m/z values and sort
  mz_values <- sort(precursor_data$Precursor.Mz)
  n_total <- length(mz_values)
  n_target <- ceiling(n_total * target_coverage)

  # Try different window sizes to find minimum range
  # that covers target number of precursors
  min_range_width <- Inf
  best_mz_min <- NULL
  best_mz_max <- NULL

  for (i in 1:(n_total - n_target + 1)) {
    # Window: [i, i + n_target - 1]
    mz_min <- mz_values[i]
    mz_max <- mz_values[i + n_target - 1]
    range_width <- mz_max - mz_min

    if (range_width < min_range_width) {
      min_range_width <- range_width
      best_mz_min <- mz_min
      best_mz_max <- mz_max
    }
  }

  # Calculate actual coverage
  covered <- mz_values >= best_mz_min & mz_values <= best_mz_max
  n_covered <- sum(covered)
  coverage_ratio <- n_covered / n_total

  return(list(
    mz_min = best_mz_min,
    mz_max = best_mz_max,
    mz_range_width = min_range_width,
    n_precursors_covered = n_covered,
    coverage_ratio = coverage_ratio
  ))
}
```

**장점**:
- ✅ 최소 m/z 범위로 target coverage 달성
- ✅ Window 개수 최소화
- ✅ Coverage 정확히 제어

**단점**:
- ❌ 계산 복잡도 O(n²)
- ❌ 극단적 outlier에 민감
- ❌ RT-dependent 변화 반영 안 함

**사용 시나리오**:
- Window 개수 최소화 필요
- Coverage 명시적 목표
- 계산 시간 여유 있음

---

## 구현 가이드

### 파일 구조

```r
# R/stage3_window_optimization/module3c_mz_range_optimization.R

# =====================================================
# Phase 3C: m/z Range Optimization
# =====================================================

#' Optimize m/z Ranges (Main Function)
#'
#' @param rt_binning_result RTBinningResult from Phase 3B
#' @param strategy Character, "quantile", "smoothing", "outlier", "coverage"
#' @param dynamic Logical, enable DynamicDIA smoothing (default: TRUE)
#' @param smoothing_method Character, "savgol", "movav", "gaussian"
#' @param smoothing_window_size Integer, smoothing window size
#' @param polynomial_order Integer, polynomial order for savgol
#' @param target_coverage Numeric, target coverage for coverage-based (0-1)
#' @param quantile_lower Numeric, lower quantile for quantile-based
#' @param quantile_upper Numeric, upper quantile for quantile-based
#' @param outlier_threshold Numeric, SD threshold for outlier removal
#' @param compare_strategies Logical, compare all strategies (default: FALSE)
#'
#' @return MzRangeResult object
#' @export
optimize_mz_ranges <- function(
  rt_binning_result,
  strategy = "smoothing",
  dynamic = TRUE,
  smoothing_method = "savgol",
  smoothing_window_size = 7,
  polynomial_order = 3,
  target_coverage = 0.95,
  quantile_lower = 0.05,
  quantile_upper = 0.95,
  outlier_threshold = 3.0,
  compare_strategies = FALSE
) {
  cat("=== Phase 3C: m/z Range Optimization ===\n\n")

  # TODO: Implement integrated m/z range optimization
  # 1. Select strategy
  # 2. Apply strategy to each RT segment
  # 3. If dynamic = TRUE and strategy = "smoothing", apply DynamicDIA
  # 4. Calculate coverage for each segment
  # 5. If compare_strategies = TRUE, run all strategies and compare
  # 6. Package results

  stop("Not implemented yet")
}

#' Optimize Range: Quantile Strategy
#'
#' @param precursor_data Data frame with precursor m/z values
#' @param quantile_lower Numeric, lower quantile (default: 0.05)
#' @param quantile_upper Numeric, upper quantile (default: 0.95)
#'
#' @return List with mz_min, mz_max, coverage_ratio
#' @export
optimize_range_quantile <- function(
  precursor_data,
  quantile_lower = 0.05,
  quantile_upper = 0.95
) {
  # TODO: Implement quantile-based optimization
  stop("Not implemented yet")
}

#' Optimize Range: Smoothing Strategy (DynamicDIA)
#'
#' @param rt_segments RT segments with precursor data
#' @param smoothing_method Character, "savgol", "movav", "gaussian"
#' @param smoothing_window_size Integer, window size
#' @param polynomial_order Integer, polynomial order (for savgol)
#'
#' @return List with raw/smoothed boundaries, smoothing params
#' @export
optimize_range_smoothing <- function(
  rt_segments,
  smoothing_method = "savgol",
  smoothing_window_size = 7,
  polynomial_order = 3
) {
  # TODO: Implement smoothing-based optimization
  # 1. Extract raw boundaries for each RT segment
  # 2. Apply smoothing (savgol, movav, or gaussian)
  # 3. Calculate coverage for smoothed boundaries
  # 4. Return raw vs smoothed comparison

  stop("Not implemented yet")
}

#' Optimize Range: Outlier Removal Strategy
#'
#' @param precursor_data Data frame with precursor m/z values
#' @param outlier_threshold Numeric, SD threshold (default: 3.0)
#'
#' @return List with mz_min, mz_max, coverage_ratio, n_outliers_removed
#' @export
optimize_range_outlier_removal <- function(
  precursor_data,
  outlier_threshold = 3.0
) {
  # TODO: Implement outlier removal optimization
  stop("Not implemented yet")
}

#' Optimize Range: Coverage-Based Strategy
#'
#' @param precursor_data Data frame with precursor m/z values
#' @param target_coverage Numeric, target coverage ratio (0-1)
#'
#' @return List with mz_min, mz_max, coverage_ratio
#' @export
optimize_range_coverage_based <- function(
  precursor_data,
  target_coverage = 0.95
) {
  # TODO: Implement coverage-based optimization
  # 1. Sort m/z values
  # 2. Find minimum range that covers target % of precursors
  # 3. Return optimal range

  stop("Not implemented yet")
}

#' Compare All Strategies
#'
#' @param rt_binning_result RTBinningResult from Phase 3B
#' @param ... Additional parameters for strategies
#'
#' @return Data frame comparing strategies
#' @export
compare_range_strategies <- function(rt_binning_result, ...) {
  # TODO: Implement strategy comparison
  # 1. Run all 4 strategies
  # 2. Calculate metrics for each (coverage, mz_width, etc.)
  # 3. Return comparison data frame

  stop("Not implemented yet")
}

# =====================================================
# Helper Functions
# =====================================================

#' Gaussian Smoothing
#'
#' @param x Numeric vector
#' @param sigma Numeric, standard deviation
#'
#' @return Smoothed numeric vector
gaussian_smooth <- function(x, sigma = 1.0) {
  # TODO: Implement Gaussian kernel smoothing
  stop("Not implemented yet")
}

#' Calculate Coverage Ratio
#'
#' @param mz_values Numeric vector of m/z values
#' @param mz_min Numeric, minimum m/z
#' @param mz_max Numeric, maximum m/z
#'
#' @return Numeric, coverage ratio (0-1)
calculate_coverage_ratio <- function(mz_values, mz_min, mz_max) {
  covered <- sum(mz_values >= mz_min & mz_values <= mz_max)
  total <- length(mz_values)
  return(covered / total)
}
```

---

## 테스트 전략

### Mock Data 생성

**파일**: `tests/mocks/mock_stage3c_output.R`

```r
#' Create Mock Stage 3C Output
#'
#' @param n_segments Number of RT segments (default: 10)
#' @param strategy Strategy used (default: "smoothing")
#'
#' @return MzRangeResult object
#' @export
create_mock_stage3c_output <- function(
  n_segments = 10,
  strategy = "smoothing"
) {
  # Load Phase 3B mock
  source("tests/mocks/mock_stage3b_output.R")
  rt_binning_result <- create_mock_stage3b_output(n_segments)

  # Create mock m/z ranges
  mz_ranges <- rt_binning_result$rt_segments %>%
    mutate(
      mz_min = runif(n(), 350, 400),
      mz_max = runif(n(), 1200, 1250),
      mz_range_width = mz_max - mz_min,
      n_precursors_covered = round(n_precursors * 0.95),
      coverage_ratio = 0.95
    ) %>%
    select(rt_segment_id, rt_start, rt_end, mz_min, mz_max,
           mz_range_width, n_precursors_covered, coverage_ratio)

  # Create result
  result <- structure(
    list(
      mz_ranges = mz_ranges,

      strategy_comparison = NULL,

      smoothing_data = if (strategy == "smoothing") {
        list(
          raw_boundaries = mz_ranges %>%
            mutate(mz_min_raw = mz_min + rnorm(n(), 0, 10),
                   mz_max_raw = mz_max + rnorm(n(), 0, 10)),
          smoothed_boundaries = mz_ranges,
          smoothing_method = "savgol",
          smoothing_params = list(window_size = 7, polynomial_order = 3)
        )
      } else {
        list()
      },

      metadata = list(
        strategy_used = strategy,
        dynamic_mode = (strategy == "smoothing"),
        outlier_threshold = NULL,
        optimization_timestamp = Sys.time()
      )
    ),
    class = c("MzRangeResult", "list")
  )

  return(result)
}
```

---

### Unit Tests

**파일**: `tests/test_stage3c.R`

```r
library(testthat)
source("tests/mocks/mock_stage3b_output.R")
source("R/stage3_window_optimization/module3c_mz_range_optimization.R")

# =====================================================
# Test: Quantile Strategy
# =====================================================

test_that("optimize_range_quantile works correctly", {
  # Setup
  precursor_data <- data.frame(
    Precursor.Mz = c(seq(400, 1200, length.out = 950),
                     rep(c(300, 1400), each = 25))  # Add outliers
  )

  # Execute
  result <- optimize_range_quantile(
    precursor_data,
    quantile_lower = 0.05,
    quantile_upper = 0.95
  )

  # Verify structure
  expect_true(all(c("mz_min", "mz_max", "coverage_ratio") %in% names(result)))

  # Verify values
  expect_true(result$mz_min >= 300)
  expect_true(result$mz_max <= 1400)
  expect_true(result$coverage_ratio >= 0.9 && result$coverage_ratio <= 1.0)

  # Verify P5 and P95
  expect_equal(result$mz_min, quantile(precursor_data$Precursor.Mz, 0.05),
               tolerance = 0.01)
  expect_equal(result$mz_max, quantile(precursor_data$Precursor.Mz, 0.95),
               tolerance = 0.01)
})

# =====================================================
# Test: Smoothing Strategy
# =====================================================

test_that("optimize_range_smoothing applies DynamicDIA smoothing", {
  # Setup
  rt_binning_result <- create_mock_stage3b_output(n_segments = 10)

  # Execute
  result <- optimize_range_smoothing(
    rt_binning_result$rt_segments,
    smoothing_method = "savgol",
    smoothing_window_size = 7,
    polynomial_order = 3
  )

  # Verify structure
  expect_true(all(c("raw_boundaries", "smoothed_boundaries",
                    "smoothing_method") %in% names(result)))

  # Verify smoothed boundaries differ from raw
  expect_false(identical(result$raw_boundaries$mz_min_raw,
                        result$smoothed_boundaries$mz_min))

  # Verify smoothing parameters
  expect_equal(result$smoothing_method, "savgol")
  expect_equal(result$smoothing_params$window_size, 7)
})

# =====================================================
# Test: Outlier Removal Strategy
# =====================================================

test_that("optimize_range_outlier_removal removes outliers", {
  # Setup with known outliers
  precursor_data <- data.frame(
    Precursor.Mz = c(seq(500, 1000, length.out = 900),
                     rep(c(200, 1500), each = 50))  # Obvious outliers
  )

  # Execute
  result <- optimize_range_outlier_removal(
    precursor_data,
    outlier_threshold = 3.0
  )

  # Verify outliers removed
  expect_true(result$n_outliers_removed > 0)
  expect_true(result$mz_min > 200)
  expect_true(result$mz_max < 1500)
  expect_true(result$coverage_ratio >= 0.85)
})

# =====================================================
# Test: Coverage-Based Strategy
# =====================================================

test_that("optimize_range_coverage_based achieves target coverage", {
  # Setup
  precursor_data <- data.frame(
    Precursor.Mz = runif(1000, 400, 1200)
  )

  # Execute
  result <- optimize_range_coverage_based(
    precursor_data,
    target_coverage = 0.95
  )

  # Verify coverage achieved
  expect_true(result$coverage_ratio >= 0.95)
  expect_true(result$n_precursors_covered >= 950)

  # Verify minimum range property
  # (difficult to test directly, but check reasonable bounds)
  expect_true(result$mz_range_width > 0)
  expect_true(result$mz_range_width < 800)  # Less than full range
})

# =====================================================
# Test: Strategy Comparison
# =====================================================

test_that("compare_range_strategies runs all strategies", {
  # Setup
  rt_binning_result <- create_mock_stage3b_output(n_segments = 5)

  # Execute
  comparison <- compare_range_strategies(rt_binning_result)

  # Verify structure
  expect_true(is.data.frame(comparison))
  expect_true(all(c("strategy", "mean_coverage", "mean_mz_width") %in%
                  colnames(comparison)))

  # Verify all 4 strategies present
  expect_equal(nrow(comparison), 4)
  expect_true(all(c("quantile", "smoothing", "outlier", "coverage") %in%
                  comparison$strategy))
})

# =====================================================
# Test: Integrated Optimization
# =====================================================

test_that("optimize_mz_ranges integrates all components", {
  # Setup
  rt_binning_result <- create_mock_stage3b_output(n_segments = 10)

  # Execute
  result <- optimize_mz_ranges(
    rt_binning_result = rt_binning_result,
    strategy = "smoothing",
    dynamic = TRUE,
    smoothing_method = "savgol"
  )

  # Verify class
  expect_s3_class(result, "MzRangeResult")

  # Verify structure
  expect_true(all(c("mz_ranges", "metadata") %in% names(result)))

  # Verify mz_ranges has correct number of rows
  expect_equal(nrow(result$mz_ranges), 10)

  # Verify each segment has valid m/z range
  expect_true(all(result$mz_ranges$mz_min < result$mz_ranges$mz_max))
  expect_true(all(result$mz_ranges$coverage_ratio >= 0 &
                  result$mz_ranges$coverage_ratio <= 1))

  # Verify metadata
  expect_equal(result$metadata$strategy_used, "smoothing")
  expect_true(result$metadata$dynamic_mode)
})
```

---

## Definition of Done

Phase 3C 개발 완료 기준:

### 기능 완성도
- [ ] `optimize_range_quantile()` 구현 완료
- [ ] `optimize_range_smoothing()` 구현 완료 (DynamicDIA)
- [ ] `optimize_range_outlier_removal()` 구현 완료
- [ ] `optimize_range_coverage_based()` 구현 완료
- [ ] `compare_range_strategies()` 구현 완료
- [ ] `optimize_mz_ranges()` 통합 함수 구현 완료

### DynamicDIA 통합
- [ ] Savitzky-Golay smoothing 구현 (prospectr 패키지)
- [ ] Moving average smoothing 구현
- [ ] Gaussian smoothing 구현
- [ ] Raw vs smoothed boundary 비교 기능

### 테스트 커버리지
- [ ] 각 전략별 unit test 작성
- [ ] Edge case 테스트 (extreme outliers, uniform distribution)
- [ ] Strategy comparison 테스트
- [ ] Mock data로 전체 워크플로우 테스트

### 코드 품질
- [ ] 모든 함수 roxygen2 문서화
- [ ] 에러 처리 및 경고 메시지
- [ ] 진행 상황 출력
- [ ] 코드 리뷰 완료

### 통합 준비
- [ ] Phase 3B 출력과 호환성 확인
- [ ] Phase 3D 입력 형식 생성
- [ ] Mock data 생성 함수 작성
- [ ] Fixture 데이터 저장

### 문서화
- [ ] 각 전략별 사용 예시
- [ ] API 문서 업데이트
- [ ] Phase 3C 개발 가이드 완료
- [ ] DEVELOPMENT.md 업데이트

### 검증
- [ ] Coverage ≥ 95% 달성 확인
- [ ] 4가지 전략 비교 및 추천
- [ ] DynamicDIA smoothing 정확도
- [ ] RT-dependent m/z 범위 정확성

---

## 참고 자료

### 관련 문서
- [API Specification](../API_SPECIFICATION.md)
- [Phase 3B: RT Binning](PHASE3B_RT_BINNING.md)
- [Phase 3D: Window Generation](PHASE3D_WINDOW_GENERATION.md)

### 관련 코드
- `R/dynamicDIA.R` - DynamicDIA smoothing 구현 (기존 활용)
- `R/mz_boundaries.R` - m/z boundary 계산 (기존 참조)

### 전략 선택 가이드

| 전략 | 사용 시나리오 | Coverage | Complexity | RT-dependent |
|------|---------------|----------|------------|--------------|
| Quantile | 빠른 탐색, outlier 많음 | 명시적 | 낮음 | ❌ |
| Smoothing | 고품질 데이터, RT 변화 | ≥95% | 높음 | ✅ |
| Outlier | Contaminant 제거 | Variable | 중간 | ❌ |
| Coverage | Window 최소화 | 정확함 | 높음 | ❌ |

---

## 개발 시작하기

```bash
# 1. Phase 3B 완료 확인
R
source("tests/mocks/mock_stage3b_output.R")
rt_binning_result <- create_mock_stage3b_output()
str(rt_binning_result)

# 2. DynamicDIA 코드 확인
source("R/dynamicDIA.R")
# Check available smoothing functions

# 3. Phase 3C 스켈레톤 생성
# R/stage3_window_optimization/module3c_mz_range_optimization.R

# 4. 첫 함수 구현 (optimize_range_quantile)
# 가장 간단한 전략부터 시작

# 5. Unit test 작성 및 실행
source("tests/test_stage3c.R")
test_file("tests/test_stage3c.R")
```

**개발 순서 권장**:
1. `optimize_range_quantile()` - 가장 간단
2. `optimize_range_outlier_removal()` - 통계 기반
3. `optimize_range_coverage_based()` - 알고리즘 복잡
4. `optimize_range_smoothing()` - DynamicDIA 통합
5. `compare_range_strategies()` - 전략 비교
6. `optimize_mz_ranges()` - 통합 함수

---

**End of Phase 3C Development Guide**
