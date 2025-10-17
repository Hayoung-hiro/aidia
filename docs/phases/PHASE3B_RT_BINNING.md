# Phase 3B: RT Binning - Integration Guide

**Version**: 1.0
**Last Updated**: 2025-10-13
**Status**: ✅ 기존 코드 활용
**Priority**: ⭐⭐ 우선순위 (통합 및 검증)
**Estimated Duration**: 1일 (통합 및 테스트)

---

## 📋 목차

1. [개요](#개요)
2. [기존 구현 분석](#기존-구현-분석)
3. [입출력 스펙](#입출력-스펙)
4. [통합 가이드](#통합-가이드)
5. [테스트 전략](#테스트-전략)
6. [Definition of Done](#definition-of-done)

---

## 개요

### Phase 3B의 역할

**RT Binning**은 retention time 공간을 일정한 시간 단위로 분할하여 RT-dependent window optimization의 기반을 제공하는 단계입니다.

**핵심 철학**:
- **시간 기반 분할**: 등간격 시간 단위 (예: 5분 bins) 또는 명시적 breakpoints
- **밀도 비종속적**: Precursor 개수가 아닌 시간 간격으로 분할
- **기존 코드 활용**: `R/rt_segmentation.R`의 구현 활용

### 기존 구현 위치

```r
# 기존 파일 (이미 구현됨)
R/rt_segmentation.R

# 주요 함수
- segment_rt_by_time_unit()        # 등간격 시간 단위 분할
- segment_rt_by_time_breaks()      # 명시적 breakpoints
- (기타 legacy functions)
```

### 이 Phase의 작업

**새로운 구현 불필요** - 기존 코드를 Stage 3 파이프라인에 통합하기만 하면 됩니다:
- [ ] Phase 3A 출력과 통합
- [ ] Phase 3C 입력 생성
- [ ] Mock data 작성
- [ ] Unit test 작성
- [ ] 문서화 업데이트

---

## 기존 구현 분석

### 1. `segment_rt_by_time_unit()` 함수

**위치**: `R/rt_segmentation.R`

**기능**: 등간격 시간 단위로 RT 분할

**사용 예시**:
```r
source("R/rt_segmentation.R")
data <- load_diann_data("report.parquet")

# 5-minute bins
rt_bins <- segment_rt_by_time_unit(
  data,
  rt_bin_width_min = 5
)

# Output structure:
# rt_bins$segments - tibble with RT segments
# rt_bins$stats - summary statistics
```

**출력 구조**:
```r
rt_bins <- list(
  segments = tibble(
    rt_segment_id = integer(),       # 1, 2, 3, ...
    rt_start = numeric(),            # Start RT (min)
    rt_end = numeric(),              # End RT (min)
    n_precursors = integer(),        # Precursor count in bin
    precursor_indices = list()       # Indices of precursors in this bin
  ),

  stats = list(
    n_segments = integer(),
    mean_precursors_per_segment = numeric(),
    sd_precursors_per_segment = numeric(),
    cv = numeric(),                  # Coefficient of variation
    rt_range = numeric(2)
  ),

  parameters = list(
    rt_bin_width_min = numeric(),
    method = "time_unit"
  )
)
```

### 2. `segment_rt_by_time_breaks()` 함수

**위치**: `R/rt_segmentation.R`

**기능**: 명시적 RT breakpoints로 분할

**사용 예시**:
```r
# Custom breakpoints
rt_bins <- segment_rt_by_time_breaks(
  data,
  rt_breaks_min = c(10, 20, 35, 50, 70, 110)
)

# Creates bins: [10-20], [20-35], [35-50], [50-70], [70-110]
```

### 3. 기존 코드의 장점

✅ **이미 구현 완료**: 시간 기반 binning 로직 완성
✅ **검증됨**: 실제 데이터로 테스트 완료
✅ **유연함**: 등간격 및 명시적 breakpoints 지원
✅ **통계 포함**: Segment별 통계 자동 계산

### 4. 통합 시 필요한 수정

**최소한의 수정만 필요**:
- [ ] Phase 3A 출력 (WindowCountResult)과 연결
- [ ] Phase 3C 입력 형식으로 출력 변환
- [ ] RT segment별 precursor 데이터 그룹화
- [ ] API 문서 업데이트

---

## 입출력 스펙

### Input Specification

```r
# Phase 1 출력 (ValidatedData)
validated_data <- create_mock_stage1_output()

# Phase 3A 출력 (WindowCountResult)
window_count_result <- create_mock_stage3a_output()

# User 입력 파라미터
rt_bin_width_min <- 5                # 등간격 분할 (5-minute bins)
# OR
rt_breaks_min <- c(10, 20, 35, 50, 70, 110)  # 명시적 breakpoints
```

### Output Specification

```r
RTBinningResult <- structure(
  list(
    rt_segments = tibble(
      rt_segment_id = integer(),       # 1, 2, 3, ...
      rt_start = numeric(),            # Start RT (min)
      rt_end = numeric(),              # End RT (min)
      n_precursors = integer(),        # Precursor count
      precursor_data = list()          # Precursor data for this segment
    ),

    stats = list(
      n_segments = integer(),
      total_precursors = integer(),
      mean_precursors_per_segment = numeric(),
      sd_precursors_per_segment = numeric(),
      cv = numeric(),                  # Coefficient of variation
      rt_range = numeric(2)
    ),

    parameters = list(
      rt_bin_width_min = numeric(),    # If time_unit method
      rt_breaks_min = numeric(),       # If time_breaks method
      method = character()             # "time_unit" or "time_breaks"
    ),

    metadata = list(
      window_count = integer(),        # From Phase 3A
      scan_time = numeric(),           # From Phase 3A
      binning_timestamp = POSIXct()
    )
  ),
  class = c("RTBinningResult", "list")
)
```

---

## 통합 가이드

### 1. 래퍼 함수 작성

**파일**: `R/stage3_window_optimization/module3b_rt_binning.R`

```r
# =====================================================
# Phase 3B: RT Binning (Integration Wrapper)
# =====================================================

#' Perform RT Binning for Window Optimization
#'
#' @param validated_data ValidatedData object from Phase 1
#' @param window_count_result WindowCountResult from Phase 3A
#' @param rt_bin_width_min Numeric, time bin width in minutes (for time_unit method)
#' @param rt_breaks_min Numeric vector, explicit RT breakpoints (for time_breaks method)
#' @param method Character, "time_unit" or "time_breaks" (default: "time_unit")
#'
#' @return RTBinningResult object
#' @export
perform_rt_binning <- function(
  validated_data,
  window_count_result,
  rt_bin_width_min = 5,
  rt_breaks_min = NULL,
  method = "time_unit"
) {
  cat("=== Phase 3B: RT Binning ===\n\n")

  # Step 1: Determine method
  if (!is.null(rt_breaks_min)) {
    method <- "time_breaks"
    cat(sprintf("Using explicit RT breakpoints: %s\n",
                paste(rt_breaks_min, collapse=", ")))
  } else {
    method <- "time_unit"
    cat(sprintf("Using time unit binning: %.1f min bins\n", rt_bin_width_min))
  }

  # Step 2: Load existing RT segmentation code
  source("R/rt_segmentation.R")

  # Step 3: Perform segmentation
  cat("\nStep 1: Segmenting RT space...\n")

  if (method == "time_unit") {
    rt_bins <- segment_rt_by_time_unit(
      validated_data$data,
      rt_bin_width_min = rt_bin_width_min
    )
  } else {
    rt_bins <- segment_rt_by_time_breaks(
      validated_data$data,
      rt_breaks_min = rt_breaks_min
    )
  }

  cat(sprintf("  Created %d RT segments\n", nrow(rt_bins$segments)))

  # Step 4: Attach precursor data to each segment
  cat("\nStep 2: Grouping precursors by RT segment...\n")

  rt_segments_with_data <- rt_bins$segments %>%
    rowwise() %>%
    mutate(
      precursor_data = list(
        validated_data$data %>%
          filter(RT.Start >= rt_start, RT.Start < rt_end) %>%
          select(Precursor.Id, RT.Start, Precursor.Mz, FWHM)
      )
    ) %>%
    ungroup()

  # Step 5: Package results
  cat("\nStep 3: Packaging RT binning results...\n")

  result <- structure(
    list(
      rt_segments = rt_segments_with_data,

      stats = list(
        n_segments = nrow(rt_segments_with_data),
        total_precursors = sum(rt_segments_with_data$n_precursors),
        mean_precursors_per_segment = mean(rt_segments_with_data$n_precursors),
        sd_precursors_per_segment = sd(rt_segments_with_data$n_precursors),
        cv = sd(rt_segments_with_data$n_precursors) /
             mean(rt_segments_with_data$n_precursors),
        rt_range = range(validated_data$data$RT.Start)
      ),

      parameters = if (method == "time_unit") {
        list(
          rt_bin_width_min = rt_bin_width_min,
          rt_breaks_min = NULL,
          method = "time_unit"
        )
      } else {
        list(
          rt_bin_width_min = NULL,
          rt_breaks_min = rt_breaks_min,
          method = "time_breaks"
        )
      },

      metadata = list(
        window_count = window_count_result$window_count,
        scan_time = window_count_result$scan_time,
        binning_timestamp = Sys.time()
      )
    ),
    class = c("RTBinningResult", "list")
  )

  cat("\n=== Phase 3B Complete ===\n")
  cat(sprintf("✅ RT binning successful: %d segments created\n",
              result$stats$n_segments))
  cat(sprintf("   Precursors per segment: %.1f ± %.1f (CV: %.2f)\n",
              result$stats$mean_precursors_per_segment,
              result$stats$sd_precursors_per_segment,
              result$stats$cv))

  return(result)
}

#' Visualize RT Binning Results
#'
#' @param rt_binning_result RTBinningResult object
#'
#' @return ggplot object
#' @export
visualize_rt_binning <- function(rt_binning_result) {
  library(ggplot2)

  # Create visualization data
  viz_data <- rt_binning_result$rt_segments %>%
    mutate(
      rt_midpoint = (rt_start + rt_end) / 2,
      bin_label = sprintf("[%.1f-%.1f]", rt_start, rt_end)
    )

  # Plot precursor distribution across RT segments
  p <- ggplot(viz_data, aes(x = rt_midpoint, y = n_precursors)) +
    geom_col(fill = "steelblue", alpha = 0.7) +
    geom_hline(yintercept = rt_binning_result$stats$mean_precursors_per_segment,
               linetype = "dashed", color = "red", linewidth = 1) +
    labs(
      title = "RT Binning: Precursor Distribution",
      subtitle = sprintf("Method: %s | %d segments | CV: %.2f",
                        rt_binning_result$parameters$method,
                        rt_binning_result$stats$n_segments,
                        rt_binning_result$stats$cv),
      x = "Retention Time (min)",
      y = "Number of Precursors",
      caption = "Red dashed line = mean precursors per segment"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      axis.text = element_text(size = 10)
    )

  return(p)
}
```

### 2. 기존 코드 활용 전략

**최소 수정 원칙**:
- ✅ `R/rt_segmentation.R` 코드는 그대로 유지
- ✅ 새로운 래퍼 함수 (`perform_rt_binning()`)만 추가
- ✅ 입출력 형식을 Stage 3 파이프라인에 맞게 변환
- ✅ Precursor data를 각 segment에 attach

---

## 테스트 전략

### Mock Data 생성

**파일**: `tests/mocks/mock_stage3b_output.R`

```r
#' Create Mock Stage 3B Output
#'
#' @param n_segments Number of RT segments (default: 10)
#' @param n_precursors Total precursors (default: 1000)
#' @param rt_bin_width_min RT bin width (default: 5)
#'
#' @return RTBinningResult object
#' @export
create_mock_stage3b_output <- function(
  n_segments = 10,
  n_precursors = 1000,
  rt_bin_width_min = 5
) {
  # Load Phase 1 mock
  source("tests/mocks/mock_stage1_output.R")
  validated_data <- create_mock_stage1_output(n_precursors)

  # Create RT segments
  rt_range <- range(validated_data$data$RT.Start)
  rt_breaks <- seq(rt_range[1], rt_range[2], length.out = n_segments + 1)

  rt_segments <- tibble(
    rt_segment_id = 1:n_segments,
    rt_start = rt_breaks[1:n_segments],
    rt_end = rt_breaks[2:(n_segments + 1)]
  ) %>%
    rowwise() %>%
    mutate(
      precursor_data = list(
        validated_data$data %>%
          filter(RT.Start >= rt_start, RT.Start < rt_end) %>%
          select(Precursor.Id, RT.Start, Precursor.Mz, FWHM)
      ),
      n_precursors = nrow(precursor_data)
    ) %>%
    ungroup()

  # Create result
  result <- structure(
    list(
      rt_segments = rt_segments,

      stats = list(
        n_segments = n_segments,
        total_precursors = n_precursors,
        mean_precursors_per_segment = n_precursors / n_segments,
        sd_precursors_per_segment = sd(rt_segments$n_precursors),
        cv = sd(rt_segments$n_precursors) / mean(rt_segments$n_precursors),
        rt_range = rt_range
      ),

      parameters = list(
        rt_bin_width_min = rt_bin_width_min,
        rt_breaks_min = NULL,
        method = "time_unit"
      ),

      metadata = list(
        window_count = 120,
        scan_time = 1.85,
        binning_timestamp = Sys.time()
      )
    ),
    class = c("RTBinningResult", "list")
  )

  return(result)
}
```

---

### Unit Tests

**파일**: `tests/test_stage3b.R`

```r
library(testthat)
source("tests/mocks/mock_stage1_output.R")
source("tests/mocks/mock_stage3a_output.R")
source("R/stage3_window_optimization/module3b_rt_binning.R")

# =====================================================
# Test: Time Unit Binning
# =====================================================

test_that("perform_rt_binning works with time_unit method", {
  # Setup
  validated_data <- create_mock_stage1_output(n_precursors = 1000)
  window_count_result <- create_mock_stage3a_output()

  # Execute
  result <- perform_rt_binning(
    validated_data = validated_data,
    window_count_result = window_count_result,
    rt_bin_width_min = 5,
    method = "time_unit"
  )

  # Verify class
  expect_s3_class(result, "RTBinningResult")

  # Verify structure
  expect_true(all(c("rt_segments", "stats", "parameters", "metadata") %in%
                  names(result)))

  # Verify segments
  expect_true(nrow(result$rt_segments) > 0)
  expect_true(all(c("rt_segment_id", "rt_start", "rt_end", "n_precursors",
                    "precursor_data") %in% colnames(result$rt_segments)))

  # Verify each segment has data
  for (i in 1:nrow(result$rt_segments)) {
    expect_true(is.data.frame(result$rt_segments$precursor_data[[i]]))
    expect_equal(nrow(result$rt_segments$precursor_data[[i]]),
                 result$rt_segments$n_precursors[i])
  }

  # Verify stats
  expect_equal(result$stats$n_segments, nrow(result$rt_segments))
  expect_equal(result$stats$total_precursors, 1000)
  expect_true(result$stats$cv >= 0)

  # Verify parameters
  expect_equal(result$parameters$method, "time_unit")
  expect_equal(result$parameters$rt_bin_width_min, 5)
})

# =====================================================
# Test: Time Breaks Binning
# =====================================================

test_that("perform_rt_binning works with time_breaks method", {
  # Setup
  validated_data <- create_mock_stage1_output(n_precursors = 1000)
  window_count_result <- create_mock_stage3a_output()

  # Custom breakpoints
  rt_breaks <- c(10, 20, 35, 50, 70, 110)

  # Execute
  result <- perform_rt_binning(
    validated_data = validated_data,
    window_count_result = window_count_result,
    rt_breaks_min = rt_breaks,
    method = "time_breaks"
  )

  # Verify method
  expect_equal(result$parameters$method, "time_breaks")
  expect_equal(result$parameters$rt_breaks_min, rt_breaks)
  expect_null(result$parameters$rt_bin_width_min)

  # Verify segment count (n_breaks - 1)
  expect_equal(result$stats$n_segments, length(rt_breaks) - 1)

  # Verify segment boundaries match breaks
  expect_equal(result$rt_segments$rt_start[1], rt_breaks[1])
  expect_equal(result$rt_segments$rt_end[nrow(result$rt_segments)],
               rt_breaks[length(rt_breaks)])
})

# =====================================================
# Test: Precursor Coverage
# =====================================================

test_that("all precursors are assigned to RT segments", {
  # Setup
  validated_data <- create_mock_stage1_output(n_precursors = 500)
  window_count_result <- create_mock_stage3a_output()

  # Execute
  result <- perform_rt_binning(
    validated_data = validated_data,
    window_count_result = window_count_result,
    rt_bin_width_min = 5
  )

  # Count total precursors across all segments
  total_assigned <- sum(result$rt_segments$n_precursors)

  # Should match original (allowing for boundary effects)
  expect_equal(total_assigned, 500, tolerance = 0.05)
  expect_equal(result$stats$total_precursors, 500)
})

# =====================================================
# Test: RT Segment Continuity
# =====================================================

test_that("RT segments are continuous without gaps", {
  # Setup
  validated_data <- create_mock_stage1_output(n_precursors = 1000)
  window_count_result <- create_mock_stage3a_output()

  # Execute
  result <- perform_rt_binning(
    validated_data = validated_data,
    window_count_result = window_count_result,
    rt_bin_width_min = 5
  )

  # Check continuity
  for (i in 1:(nrow(result$rt_segments) - 1)) {
    current_end <- result$rt_segments$rt_end[i]
    next_start <- result$rt_segments$rt_start[i + 1]

    # Segments should be continuous (allowing small floating point tolerance)
    expect_equal(current_end, next_start, tolerance = 0.01)
  }
})

# =====================================================
# Test: Visualization
# =====================================================

test_that("visualize_rt_binning generates plot", {
  # Setup
  mock_result <- create_mock_stage3b_output()

  # Execute
  plot <- visualize_rt_binning(mock_result)

  # Verify plot class
  expect_s3_class(plot, "ggplot")

  # Verify plot can be printed (no errors)
  expect_silent(print(plot))
})

# =====================================================
# Test: Integration with Phase 3A
# =====================================================

test_that("RT binning integrates with Phase 3A output", {
  # Setup
  validated_data <- create_mock_stage1_output()
  window_count_result <- create_mock_stage3a_output(
    n_windows = 120,
    scan_time = 1.85
  )

  # Execute
  result <- perform_rt_binning(
    validated_data = validated_data,
    window_count_result = window_count_result,
    rt_bin_width_min = 5
  )

  # Verify Phase 3A metadata is preserved
  expect_equal(result$metadata$window_count, 120)
  expect_equal(result$metadata$scan_time, 1.85)
})
```

---

## Definition of Done

Phase 3B 통합 완료 기준:

### 통합 완성도
- [ ] `perform_rt_binning()` 래퍼 함수 구현 완료
- [ ] `visualize_rt_binning()` 시각화 함수 구현 완료
- [ ] Phase 3A 출력과 연결 확인
- [ ] Phase 3C 입력 형식 생성 확인

### 테스트 커버리지
- [ ] Time unit binning 테스트 통과
- [ ] Time breaks binning 테스트 통과
- [ ] Precursor coverage 테스트 통과 (모든 precursor 할당)
- [ ] RT segment continuity 테스트 통과 (gap 없음)
- [ ] 시각화 생성 테스트 통과

### 기존 코드 검증
- [ ] `R/rt_segmentation.R` 함수 정상 동작 확인
- [ ] `segment_rt_by_time_unit()` 출력 검증
- [ ] `segment_rt_by_time_breaks()` 출력 검증
- [ ] 기존 코드 수정 불필요 확인

### 코드 품질
- [ ] 래퍼 함수 roxygen2 문서화 완료
- [ ] 진행 상황 출력 (progress reporting)
- [ ] 에러 처리 구현
- [ ] 코드 리뷰 완료

### 통합 준비
- [ ] Phase 3A 출력과 호환성 확인 (WindowCountResult)
- [ ] Phase 3C 입력 형식 생성 (RTBinningResult)
- [ ] Mock data 생성 함수 작성 (`create_mock_stage3b_output()`)
- [ ] Fixture 데이터 저장 (`tests/fixtures/stage3b_output.rds`)

### 문서화
- [ ] 통합 가이드 작성 완료 (이 문서)
- [ ] API 문서 업데이트 (`docs/API_SPECIFICATION.md`)
- [ ] DEVELOPMENT.md 진행 상황 업데이트
- [ ] 기존 함수 사용 예시 작성

### 검증
- [ ] 5-minute bins 시나리오 테스트
- [ ] Custom RT breaks 시나리오 테스트
- [ ] Precursor count 변동성 확인 (CV 계산)
- [ ] 시각화 출력 검증

---

## 참고 자료

### 관련 문서
- [API Specification](../API_SPECIFICATION.md)
- [Phase 3A: Window Count Determination](PHASE3A_WINDOW_COUNT.md)
- [Phase 3C: m/z Range Optimization](PHASE3C_MZ_RANGE.md)

### 관련 코드
- `R/rt_segmentation.R` - 기존 RT binning 구현 (활용)
- `R/stage3_window_optimization/module3b_rt_binning.R` - 통합 래퍼 (신규)

### RT Binning 철학

**시간 기반 분할 (Time-based Binning)**:
- **목적**: 등간격 시간 해상도로 RT 공간 분할
- **방법**: 5분 bins (10-15, 15-20, 20-25 min) 또는 custom breakpoints
- **특징**: Precursor 개수는 bin마다 다를 수 있음 (밀도 비종속적)
- **용도**: RT-dependent m/z range optimization의 기반

**밀도 기반 분할과의 차이** (사용 안 함):
- ❌ 밀도 기반: 각 bin의 precursor 개수 균등화
- ✅ 시간 기반: 시간 간격 균등화 (현재 방식)

---

## 개발 시작하기

```bash
# 1. 기존 코드 확인
R
source("R/rt_segmentation.R")

# 2. 기존 함수 테스트
data <- create_mock_stage1_output()$data
rt_bins <- segment_rt_by_time_unit(data, rt_bin_width_min = 5)
str(rt_bins)

# 3. 래퍼 함수 작성
# R/stage3_window_optimization/module3b_rt_binning.R 생성

# 4. Mock data 작성
source("tests/mocks/mock_stage3b_output.R")
mock_result <- create_mock_stage3b_output()
str(mock_result)

# 5. Unit test 실행
source("tests/test_stage3b.R")
test_file("tests/test_stage3b.R")
```

**개발 순서 권장**:
1. `R/rt_segmentation.R` 함수 동작 확인
2. `perform_rt_binning()` 래퍼 작성 (기존 함수 호출)
3. Precursor data attachment 구현
4. `visualize_rt_binning()` 시각화 함수 작성
5. Mock data 생성 함수 작성
6. Unit tests 작성 및 실행

---

**Note**: Phase 3B는 기존에 잘 작동하는 코드를 활용하므로 **최소한의 통합 작업**만 필요합니다. 새로운 알고리즘 구현이 아닌 **파이프라인 연결**에 집중하세요.

---

**End of Phase 3B Integration Guide**
