# Phase 2: DPPP Diagnosis - Development Guide

**Version**: 1.0
**Last Updated**: 2025-10-13
**Status**: 🔴 개발 대기
**Priority**: ⭐⭐⭐ 우선순위 2
**Estimated Duration**: 3-4일

---

## 📋 목차

1. [개요](#개요)
2. [Phase 2 목표](#phase-2-목표)
3. [입출력 스펙](#입출력-스펙)
4. [기능 요구사항](#기능-요구사항)
5. [구현 가이드](#구현-가이드)
6. [테스트 전략](#테스트-전략)
7. [Definition of Done](#definition-of-done)

---

## 개요

### Phase 2의 역할

**DPPP Diagnosis Stage**는 현재 DIA 실험의 DPPP 상태를 진단하고, 다음 실험을 위한 최적 scan_time을 추천하는 단계입니다.

**핵심 철학**:
- **진단 우선**: 현재 상태를 먼저 이해
- **사용자 중심**: 사용자의 scan_time을 기반으로 분석
- **실험 계획 지원**: 다음 실험을 위한 구체적 추천

### 입력 데이터

Phase 1의 출력:
```r
ValidatedData <- structure(
  list(
    data = tibble(RT.Start, Precursor.Mz, FWHM, ...),
    metadata = list(
      n_precursors = integer(),
      rt_range = numeric(2),
      mz_range = numeric(2),
      fwhm_stats = list(mean = numeric(), median = numeric(), ...)
    ),
    validation_status = list(...)
  ),
  class = c("ValidatedData", "list")
)
```

### 출력 데이터

```r
DiagnosisResult <- structure(
  list(
    current_state = list(
      user_scan_time = numeric(),           # 사용자가 입력한 scan_time (초)
      dppp_distribution = tibble(
        precursor_id = integer(),
        rt = numeric(),
        mz = numeric(),
        dppp_value = numeric(),
        meets_target = logical()
      ),
      dppp_stats = list(
        mean = numeric(),
        median = numeric(),
        sd = numeric(),
        p25 = numeric(),
        p75 = numeric(),
        p95 = numeric()
      ),
      satisfaction_ratio = numeric()        # 0-1, target 달성 비율
    ),

    recommendation = list(
      optimal_scan_time = numeric(),        # 추천 scan_time (초)
      expected_satisfaction = numeric(),    # 예상 달성 비율
      expected_window_count = integer(),    # 예상 window 개수
      tradeoff_analysis = tibble(
        scan_time = numeric(),
        window_count = integer(),
        satisfaction_ratio = numeric(),
        cycle_time = numeric()
      )
    ),

    instrument_constraints = list(
      instrument_type = character(),
      max_scan_rate = numeric(),
      ms1_time = numeric(),
      ms2_time = numeric(),
      is_feasible = logical(),
      warnings = character()
    ),

    metadata = list(
      target_dppp = numeric(),              # 7.0 (Quant) or 1.5 (ID)
      dppp_tolerance = numeric(),           # default: 0.5
      analysis_timestamp = POSIXct(),
      processing_time = numeric()
    )
  ),
  class = c("DiagnosisResult", "list")
)
```

---

## Phase 2 목표

### 주요 기능

1. **현재 DPPP 분포 계산**
   - 사용자의 scan_time 기반으로 현재 DPPP 계산
   - RT × m/z 공간에서 DPPP 분포 시각화
   - 통계 요약 (mean, median, percentiles)

2. **Satisfaction Ratio 계산**
   - Target DPPP ± tolerance 범위 내 precursor 비율
   - 예: target_dppp=7.0, tolerance=0.5 → [6.5, 7.5] 범위
   - ID 모드 (1.5) vs Quant 모드 (7.0) 지원

3. **최적 scan_time 추천**
   - 목표 satisfaction_ratio (예: 85%) 달성을 위한 scan_time 계산
   - Trade-off 분석: scan_time vs window_count vs satisfaction
   - 여러 scan_time 시나리오 비교

4. **Instrument Feasibility Check**
   - 계산된 window count가 instrument scan rate 제약 내에 있는지 확인
   - Astral (parallel), Exploris (sequential) 등 instrument별 검증
   - 경고 메시지 생성

### 성공 지표

- [x] 모든 precursor에 대해 DPPP 값 계산 완료
- [x] Satisfaction ratio가 정확하게 계산됨 (tolerance 고려)
- [x] 최적 scan_time이 target satisfaction을 만족
- [x] Instrument 제약 위반 시 명확한 경고 메시지
- [x] Trade-off 분석 데이터가 시각화 가능한 형태로 제공

---

## 입출력 스펙

### Input Specification

```r
# Phase 1 출력 (필수)
validated_data <- create_mock_stage1_output()

# User 입력 파라미터
user_scan_time <- 2.0                    # 초 단위
target_dppp <- 7.0                       # Quant 모드 (or 1.5 for ID)
dppp_tolerance <- 0.5                    # ± tolerance
target_satisfaction_ratio <- 0.85        # 85% 목표
instrument_preset <- "astral"            # or "orbitrap_exploris", etc.
```

### Output Specification

```r
# DiagnosisResult 구조
diagnosis <- diagnose_dppp_status(
  validated_data = validated_data,
  user_scan_time = 2.0,
  target_dppp = 7.0,
  dppp_tolerance = 0.5,
  target_satisfaction_ratio = 0.85,
  instrument_preset = "astral"
)

# 접근 예시
diagnosis$current_state$satisfaction_ratio  # 0.72
diagnosis$recommendation$optimal_scan_time  # 1.82
diagnosis$recommendation$expected_satisfaction  # 0.85
diagnosis$instrument_constraints$is_feasible  # TRUE
```

---

## 기능 요구사항

### 1. DPPP Distribution 계산

**함수**: `calculate_current_dppp_distribution()`

**목적**: 사용자의 scan_time을 기반으로 현재 DPPP 분포 계산

**알고리즘**:
```r
# DPPP 계산 공식 (Spectronaut standard)
DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds

# Cycle time 계산 (instrument-dependent)
# Astral (parallel acquisition):
cycle_time = max(MS1_time, n_windows × MS2_time)

# Orbitrap (sequential acquisition):
cycle_time = MS1_time + (n_windows × MS2_time)

# Window count는 user_scan_time과 instrument speed로 계산
n_windows = floor(scan_time × scan_rate_hz) - 1  # -1 for MS1
```

**구현 체크리스트**:
- [ ] FWHM 데이터를 초 단위로 변환 (분 단위 → 초)
- [ ] Instrument preset에서 MS1_time, MS2_time, scan_rate 로드
- [ ] Window count 계산 (scan_time 기반)
- [ ] Cycle time 계산 (instrument type별 분기)
- [ ] 각 precursor별 DPPP 계산
- [ ] Target DPPP 달성 여부 판정 (tolerance 고려)
- [ ] 통계 요약 계산 (mean, median, percentiles)
- [ ] RT × m/z 공간에 DPPP 값 매핑

**에러 처리**:
- FWHM이 0 또는 NA인 경우 → 해당 precursor 제외 + 경고
- Window count가 1 미만인 경우 → 에러 발생
- Cycle time이 scan_time을 초과하는 경우 → 경고 발생

---

### 2. Satisfaction Ratio 계산

**함수**: `compute_satisfaction_ratio()`

**목적**: Target DPPP ± tolerance 범위 내 precursor 비율 계산

**알고리즘**:
```r
# Satisfaction range
lower_bound <- target_dppp - dppp_tolerance  # 6.5
upper_bound <- target_dppp + dppp_tolerance  # 7.5

# Count precursors within range
n_satisfied <- sum(dppp_values >= lower_bound & dppp_values <= upper_bound)
n_total <- length(dppp_values)

satisfaction_ratio <- n_satisfied / n_total  # 0.72 (72%)
```

**구현 체크리스트**:
- [ ] Target DPPP와 tolerance로 acceptable range 계산
- [ ] Range 내 precursor 개수 카운트
- [ ] Satisfaction ratio 계산 (0-1 범위)
- [ ] RT segment별 satisfaction ratio 계산 (선택)
- [ ] m/z segment별 satisfaction ratio 계산 (선택)
- [ ] Satisfied/unsatisfied precursor 위치 저장 (시각화용)

**에러 처리**:
- Target DPPP ≤ 0 → 에러
- Tolerance < 0 → 에러
- DPPP 값이 모두 NA → 에러

---

### 3. 최적 scan_time 추천

**함수**: `recommend_scan_time()`

**목적**: 목표 satisfaction_ratio를 달성하기 위한 최적 scan_time 계산

**알고리즘**:
```r
# Iterative approach: test multiple scan_time values
scan_time_range <- seq(1.0, 4.0, by = 0.05)  # 1.0 ~ 4.0초, 0.05초 간격

tradeoff_results <- tibble()

for (st in scan_time_range) {
  # Window count 계산
  n_win <- floor(st × instrument_scan_rate) - 1

  # Cycle time 계산
  if (instrument_type == "astral") {
    cycle_time <- max(ms1_time, n_win × ms2_time)
  } else {
    cycle_time <- ms1_time + (n_win × ms2_time)
  }

  # DPPP 재계산
  dppp_new <- (1.7 × fwhm_sec) / cycle_time

  # Satisfaction ratio 계산
  satisfaction <- compute_satisfaction_ratio(dppp_new, target_dppp, tolerance)

  # 결과 저장
  tradeoff_results <- bind_rows(tradeoff_results, tibble(
    scan_time = st,
    window_count = n_win,
    cycle_time = cycle_time,
    satisfaction_ratio = satisfaction
  ))
}

# Target satisfaction에 가장 가까운 scan_time 선택
optimal_row <- tradeoff_results %>%
  mutate(distance = abs(satisfaction_ratio - target_satisfaction_ratio)) %>%
  arrange(distance) %>%
  slice(1)

optimal_scan_time <- optimal_row$scan_time
```

**구현 체크리스트**:
- [ ] scan_time 범위 정의 (1.0 ~ 4.0초, 사용자 설정 가능)
- [ ] 각 scan_time에 대해 window count 계산
- [ ] 각 scan_time에 대해 cycle time 계산
- [ ] 각 scan_time에 대해 DPPP 분포 재계산
- [ ] 각 scan_time에 대해 satisfaction ratio 계산
- [ ] Trade-off 데이터 수집 (tibble 형태)
- [ ] Target satisfaction에 가장 가까운 scan_time 선택
- [ ] 예상 window count와 satisfaction 반환

**에러 처리**:
- scan_time 범위 내에서 target 달성 불가능 → 가장 가까운 값 + 경고
- Window count가 instrument 한계 초과 → 경고 발생

---

### 4. Instrument Feasibility Check

**함수**: `check_instrument_feasibility()`

**목적**: 계산된 window count가 instrument 제약을 만족하는지 확인

**검증 항목**:
```r
# 1. Window count vs scan rate
max_possible_scans <- floor(scan_time × max_scan_rate_hz)
is_feasible_scan_rate <- (n_windows + 1) <= max_possible_scans  # +1 for MS1

# 2. Cycle time vs scan time
calculated_cycle_time <- compute_cycle_time(n_windows, instrument_type)
is_feasible_cycle_time <- calculated_cycle_time <= scan_time

# 3. Minimum window width (Astral: 2 Da for narrow-DIA)
min_width_required <- 2.0  # Da
estimated_width <- total_mz_range / n_windows
is_feasible_width <- estimated_width >= min_width_required

# Overall feasibility
is_feasible <- is_feasible_scan_rate && is_feasible_cycle_time && is_feasible_width
```

**구현 체크리스트**:
- [ ] Instrument preset에서 max_scan_rate, min_width 로드
- [ ] Scan rate 제약 검증
- [ ] Cycle time 제약 검증
- [ ] Minimum window width 제약 검증 (Astral 특히)
- [ ] 각 제약별 feasibility 판정
- [ ] 위반 시 경고 메시지 생성
- [ ] 전체 feasibility 판정

**경고 메시지 예시**:
```r
warnings <- c()

if (!is_feasible_scan_rate) {
  warnings <- c(warnings, sprintf(
    "Window count (%d) exceeds instrument scan rate capacity (%d scans in %.2f sec)",
    n_windows, max_possible_scans, scan_time
  ))
}

if (!is_feasible_cycle_time) {
  warnings <- c(warnings, sprintf(
    "Calculated cycle time (%.3f sec) exceeds scan time (%.2f sec)",
    calculated_cycle_time, scan_time
  ))
}

if (!is_feasible_width) {
  warnings <- c(warnings, sprintf(
    "Estimated window width (%.2f Da) is below minimum (%.2f Da for %s)",
    estimated_width, min_width_required, instrument_type
  ))
}
```

---

### 5. 통합 함수

**함수**: `diagnose_dppp_status()`

**목적**: Phase 2의 모든 분석을 통합하여 실행

**워크플로우**:
```r
diagnose_dppp_status <- function(
  validated_data,
  user_scan_time = 2.0,
  target_dppp = 7.0,
  dppp_tolerance = 0.5,
  target_satisfaction_ratio = 0.85,
  instrument_preset = "astral"
) {
  cat("=== Phase 2: DPPP Diagnosis ===\n\n")

  # Step 1: Calculate current DPPP distribution
  cat("Step 1: Calculating current DPPP distribution...\n")
  current_state <- calculate_current_dppp_distribution(
    validated_data,
    user_scan_time,
    target_dppp,
    dppp_tolerance,
    instrument_preset
  )
  cat(sprintf("  - Current satisfaction ratio: %.1f%%\n",
              current_state$satisfaction_ratio * 100))

  # Step 2: Recommend optimal scan_time
  cat("\nStep 2: Recommending optimal scan_time...\n")
  recommendation <- recommend_scan_time(
    validated_data,
    target_dppp,
    dppp_tolerance,
    target_satisfaction_ratio,
    instrument_preset
  )
  cat(sprintf("  - Recommended scan_time: %.2f sec\n",
              recommendation$optimal_scan_time))
  cat(sprintf("  - Expected satisfaction: %.1f%%\n",
              recommendation$expected_satisfaction * 100))

  # Step 3: Check instrument feasibility
  cat("\nStep 3: Checking instrument feasibility...\n")
  constraints <- check_instrument_feasibility(
    recommendation$expected_window_count,
    recommendation$optimal_scan_time,
    validated_data$metadata$mz_range,
    instrument_preset
  )

  if (constraints$is_feasible) {
    cat("  ✅ Recommended parameters are feasible\n")
  } else {
    cat("  ⚠️  Warnings detected:\n")
    for (w in constraints$warnings) {
      cat(sprintf("     - %s\n", w))
    }
  }

  # Step 4: Package results
  cat("\nStep 4: Packaging diagnosis results...\n")
  result <- structure(
    list(
      current_state = current_state,
      recommendation = recommendation,
      instrument_constraints = constraints,
      metadata = list(
        target_dppp = target_dppp,
        dppp_tolerance = dppp_tolerance,
        analysis_timestamp = Sys.time(),
        processing_time = proc.time()["elapsed"]
      )
    ),
    class = c("DiagnosisResult", "list")
  )

  cat("\n=== Phase 2 Complete ===\n")
  return(result)
}
```

**구현 체크리스트**:
- [ ] 모든 하위 함수 호출
- [ ] 진행 상황 출력 (progress reporting)
- [ ] 에러 발생 시 graceful handling
- [ ] 결과 객체 구조화 (DiagnosisResult class)
- [ ] 처리 시간 기록
- [ ] 입력 파라미터 검증

---

## 구현 가이드

### 파일 구조

```r
# R/stage2_dppp_diagnosis.R

# =====================================================
# Phase 2: DPPP Diagnosis
# =====================================================

#' Calculate Current DPPP Distribution
#'
#' @param validated_data ValidatedData object from Phase 1
#' @param user_scan_time Numeric, user's scan time in seconds
#' @param target_dppp Numeric, target DPPP value (7.0 for Quant, 1.5 for ID)
#' @param dppp_tolerance Numeric, acceptable tolerance (default: 0.5)
#' @param instrument_preset Character, instrument type ("astral", "orbitrap_exploris", etc.)
#'
#' @return List with dppp_distribution, dppp_stats, satisfaction_ratio
#' @export
calculate_current_dppp_distribution <- function(
  validated_data,
  user_scan_time,
  target_dppp,
  dppp_tolerance,
  instrument_preset
) {
  # TODO: Implement DPPP calculation logic
  # 1. Load instrument config (MS1_time, MS2_time, scan_rate)
  # 2. Calculate window count from scan_time
  # 3. Calculate cycle time (parallel vs sequential)
  # 4. Calculate DPPP for each precursor
  # 5. Determine which precursors meet target
  # 6. Calculate statistics
  # 7. Return structured result

  stop("Not implemented yet")
}

#' Compute Satisfaction Ratio
#'
#' @param dppp_values Numeric vector of DPPP values
#' @param target_dppp Numeric, target DPPP
#' @param dppp_tolerance Numeric, tolerance
#'
#' @return Numeric, ratio of precursors within target ± tolerance
#' @export
compute_satisfaction_ratio <- function(dppp_values, target_dppp, dppp_tolerance) {
  # TODO: Implement satisfaction ratio calculation
  # 1. Define acceptable range
  # 2. Count precursors within range
  # 3. Calculate ratio

  stop("Not implemented yet")
}

#' Recommend Optimal Scan Time
#'
#' @param validated_data ValidatedData object
#' @param target_dppp Numeric, target DPPP
#' @param dppp_tolerance Numeric, tolerance
#' @param target_satisfaction_ratio Numeric, target satisfaction (0-1)
#' @param instrument_preset Character, instrument type
#' @param scan_time_range Numeric vector, range to test (default: seq(1.0, 4.0, 0.05))
#'
#' @return List with optimal_scan_time, expected_satisfaction, expected_window_count, tradeoff_analysis
#' @export
recommend_scan_time <- function(
  validated_data,
  target_dppp,
  dppp_tolerance,
  target_satisfaction_ratio,
  instrument_preset,
  scan_time_range = seq(1.0, 4.0, by = 0.05)
) {
  # TODO: Implement scan_time recommendation
  # 1. Define scan_time range to test
  # 2. For each scan_time:
  #    a. Calculate window count
  #    b. Calculate cycle time
  #    c. Calculate DPPP distribution
  #    d. Calculate satisfaction ratio
  #    e. Store results in tibble
  # 3. Find scan_time closest to target satisfaction
  # 4. Return recommendation with tradeoff data

  stop("Not implemented yet")
}

#' Check Instrument Feasibility
#'
#' @param n_windows Integer, number of isolation windows
#' @param scan_time Numeric, scan time in seconds
#' @param mz_range Numeric vector of length 2 (min, max m/z)
#' @param instrument_preset Character, instrument type
#'
#' @return List with is_feasible, warnings, instrument_type, max_scan_rate
#' @export
check_instrument_feasibility <- function(
  n_windows,
  scan_time,
  mz_range,
  instrument_preset
) {
  # TODO: Implement feasibility checks
  # 1. Load instrument constraints
  # 2. Check scan rate constraint
  # 3. Check cycle time constraint
  # 4. Check minimum window width constraint
  # 5. Generate warnings for violations
  # 6. Return overall feasibility + warnings

  stop("Not implemented yet")
}

#' Diagnose DPPP Status (Main Function)
#'
#' @param validated_data ValidatedData object from Phase 1
#' @param user_scan_time Numeric, user's current scan time
#' @param target_dppp Numeric, target DPPP (7.0 for Quant, 1.5 for ID)
#' @param dppp_tolerance Numeric, tolerance (default: 0.5)
#' @param target_satisfaction_ratio Numeric, target satisfaction (default: 0.85)
#' @param instrument_preset Character, instrument type
#'
#' @return DiagnosisResult object
#' @export
diagnose_dppp_status <- function(
  validated_data,
  user_scan_time = 2.0,
  target_dppp = 7.0,
  dppp_tolerance = 0.5,
  target_satisfaction_ratio = 0.85,
  instrument_preset = "astral"
) {
  # TODO: Implement integrated diagnosis workflow
  # 1. Calculate current DPPP distribution
  # 2. Recommend optimal scan_time
  # 3. Check instrument feasibility
  # 4. Package results into DiagnosisResult object
  # 5. Return structured result

  stop("Not implemented yet")
}

# =====================================================
# Helper Functions
# =====================================================

#' Calculate Cycle Time
#'
#' @param n_windows Integer, number of windows
#' @param instrument_type Character, "astral" or "orbitrap"
#' @param ms1_time Numeric, MS1 acquisition time (sec)
#' @param ms2_time Numeric, MS2 acquisition time per window (sec)
#'
#' @return Numeric, cycle time in seconds
compute_cycle_time <- function(n_windows, instrument_type, ms1_time, ms2_time) {
  if (instrument_type == "astral") {
    # Parallel acquisition
    return(max(ms1_time, n_windows * ms2_time))
  } else {
    # Sequential acquisition
    return(ms1_time + (n_windows * ms2_time))
  }
}

#' Calculate Window Count from Scan Time
#'
#' @param scan_time Numeric, scan time in seconds
#' @param scan_rate Numeric, instrument scan rate in Hz
#'
#' @return Integer, number of MS2 windows
calculate_window_count <- function(scan_time, scan_rate) {
  total_scans <- floor(scan_time * scan_rate)
  n_windows <- total_scans - 1  # -1 for MS1 scan
  return(max(n_windows, 1))  # At least 1 window
}
```

---

## 테스트 전략

### Mock Data 생성

**파일**: `tests/mocks/mock_stage2_output.R`

```r
#' Create Mock Stage 2 Output
#'
#' @param n_precursors Number of precursors (default: 1000)
#' @param target_dppp Target DPPP value (default: 7.0)
#' @param satisfaction_ratio Mock satisfaction ratio (default: 0.85)
#'
#' @return DiagnosisResult object
#' @export
create_mock_stage2_output <- function(
  n_precursors = 1000,
  target_dppp = 7.0,
  satisfaction_ratio = 0.85
) {
  # Load Phase 1 mock data
  source("tests/mocks/mock_stage1_output.R")
  validated_data <- create_mock_stage1_output(n_precursors)

  # Create mock DPPP distribution
  dppp_mean <- target_dppp
  dppp_sd <- 0.8
  dppp_values <- rnorm(n_precursors, mean = dppp_mean, sd = dppp_sd)
  dppp_values <- pmax(dppp_values, 0.5)  # Minimum DPPP

  # Determine which meet target
  lower <- target_dppp - 0.5
  upper <- target_dppp + 0.5
  meets_target <- dppp_values >= lower & dppp_values <= upper

  # Create dppp_distribution tibble
  dppp_distribution <- validated_data$data %>%
    mutate(
      dppp_value = dppp_values,
      meets_target = meets_target
    ) %>%
    select(precursor_id = Precursor.Id, rt = RT.Start, mz = Precursor.Mz,
           dppp_value, meets_target)

  # Mock result structure
  result <- structure(
    list(
      current_state = list(
        user_scan_time = 2.0,
        dppp_distribution = dppp_distribution,
        dppp_stats = list(
          mean = mean(dppp_values),
          median = median(dppp_values),
          sd = sd(dppp_values),
          p25 = quantile(dppp_values, 0.25),
          p75 = quantile(dppp_values, 0.75),
          p95 = quantile(dppp_values, 0.95)
        ),
        satisfaction_ratio = satisfaction_ratio
      ),

      recommendation = list(
        optimal_scan_time = 1.85,
        expected_satisfaction = 0.85,
        expected_window_count = 120,
        tradeoff_analysis = tibble(
          scan_time = seq(1.5, 2.5, by = 0.1),
          window_count = floor(seq(1.5, 2.5, by = 0.1) * 50) - 1,
          satisfaction_ratio = seq(0.78, 0.88, length.out = 11),
          cycle_time = seq(1.5, 2.5, by = 0.1)
        )
      ),

      instrument_constraints = list(
        instrument_type = "astral",
        max_scan_rate = 50,
        ms1_time = 0.1,
        ms2_time = 0.015,
        is_feasible = TRUE,
        warnings = character(0)
      ),

      metadata = list(
        target_dppp = target_dppp,
        dppp_tolerance = 0.5,
        analysis_timestamp = Sys.time(),
        processing_time = 0.5
      )
    ),
    class = c("DiagnosisResult", "list")
  )

  return(result)
}
```

---

### Unit Tests

**파일**: `tests/test_stage2.R`

```r
library(testthat)
source("tests/mocks/mock_stage1_output.R")
source("R/stage2_dppp_diagnosis.R")

# =====================================================
# Test: DPPP Distribution Calculation
# =====================================================

test_that("calculate_current_dppp_distribution works correctly", {
  # Setup
  mock_data <- create_mock_stage1_output(n_precursors = 1000)

  # Execute
  result <- calculate_current_dppp_distribution(
    validated_data = mock_data,
    user_scan_time = 2.0,
    target_dppp = 7.0,
    dppp_tolerance = 0.5,
    instrument_preset = "astral"
  )

  # Verify structure
  expect_true("dppp_distribution" %in% names(result))
  expect_true("dppp_stats" %in% names(result))
  expect_true("satisfaction_ratio" %in% names(result))

  # Verify data
  expect_equal(nrow(result$dppp_distribution), 1000)
  expect_true(all(c("rt", "mz", "dppp_value", "meets_target") %in%
                  colnames(result$dppp_distribution)))

  # Verify statistics
  expect_true(result$dppp_stats$mean > 0)
  expect_true(result$satisfaction_ratio >= 0 && result$satisfaction_ratio <= 1)
})

# =====================================================
# Test: Satisfaction Ratio Calculation
# =====================================================

test_that("compute_satisfaction_ratio calculates correctly", {
  # Test case 1: All precursors meet target
  dppp_values <- rep(7.0, 100)
  ratio <- compute_satisfaction_ratio(dppp_values, target_dppp = 7.0, dppp_tolerance = 0.5)
  expect_equal(ratio, 1.0)

  # Test case 2: None meet target
  dppp_values <- rep(10.0, 100)
  ratio <- compute_satisfaction_ratio(dppp_values, target_dppp = 7.0, dppp_tolerance = 0.5)
  expect_equal(ratio, 0.0)

  # Test case 3: Half meet target
  dppp_values <- c(rep(7.0, 50), rep(10.0, 50))
  ratio <- compute_satisfaction_ratio(dppp_values, target_dppp = 7.0, dppp_tolerance = 0.5)
  expect_equal(ratio, 0.5)
})

# =====================================================
# Test: Scan Time Recommendation
# =====================================================

test_that("recommend_scan_time finds optimal value", {
  # Setup
  mock_data <- create_mock_stage1_output(n_precursors = 1000)

  # Execute
  result <- recommend_scan_time(
    validated_data = mock_data,
    target_dppp = 7.0,
    dppp_tolerance = 0.5,
    target_satisfaction_ratio = 0.85,
    instrument_preset = "astral",
    scan_time_range = seq(1.5, 2.5, by = 0.1)
  )

  # Verify structure
  expect_true("optimal_scan_time" %in% names(result))
  expect_true("expected_satisfaction" %in% names(result))
  expect_true("expected_window_count" %in% names(result))
  expect_true("tradeoff_analysis" %in% names(result))

  # Verify values
  expect_true(result$optimal_scan_time >= 1.5 && result$optimal_scan_time <= 2.5)
  expect_true(result$expected_satisfaction >= 0 && result$expected_satisfaction <= 1)
  expect_true(result$expected_window_count > 0)

  # Verify tradeoff data
  expect_equal(nrow(result$tradeoff_analysis), 11)  # seq(1.5, 2.5, 0.1) has 11 values
  expect_true(all(c("scan_time", "window_count", "satisfaction_ratio", "cycle_time") %in%
                  colnames(result$tradeoff_analysis)))
})

# =====================================================
# Test: Instrument Feasibility Check
# =====================================================

test_that("check_instrument_feasibility validates constraints", {
  # Test case 1: Feasible configuration (Astral)
  result <- check_instrument_feasibility(
    n_windows = 100,
    scan_time = 2.0,
    mz_range = c(350, 1250),
    instrument_preset = "astral"
  )

  expect_true(result$is_feasible)
  expect_equal(length(result$warnings), 0)

  # Test case 2: Too many windows for scan rate
  result <- check_instrument_feasibility(
    n_windows = 200,  # Too many for 2.0 sec at 50 Hz
    scan_time = 2.0,
    mz_range = c(350, 1250),
    instrument_preset = "astral"
  )

  expect_false(result$is_feasible)
  expect_true(length(result$warnings) > 0)
  expect_true(any(grepl("scan rate", result$warnings)))

  # Test case 3: Too narrow windows
  result <- check_instrument_feasibility(
    n_windows = 500,  # Would result in <2 Da windows
    scan_time = 2.0,
    mz_range = c(350, 1250),
    instrument_preset = "astral"
  )

  expect_false(result$is_feasible)
  expect_true(any(grepl("window width", result$warnings)))
})

# =====================================================
# Test: Integrated Diagnosis
# =====================================================

test_that("diagnose_dppp_status integrates all components", {
  # Setup
  mock_data <- create_mock_stage1_output(n_precursors = 1000)

  # Execute
  result <- diagnose_dppp_status(
    validated_data = mock_data,
    user_scan_time = 2.0,
    target_dppp = 7.0,
    dppp_tolerance = 0.5,
    target_satisfaction_ratio = 0.85,
    instrument_preset = "astral"
  )

  # Verify class
  expect_s3_class(result, "DiagnosisResult")

  # Verify structure
  expect_true(all(c("current_state", "recommendation", "instrument_constraints", "metadata") %in%
                  names(result)))

  # Verify current_state
  expect_equal(result$current_state$user_scan_time, 2.0)
  expect_true(nrow(result$current_state$dppp_distribution) == 1000)

  # Verify recommendation
  expect_true(result$recommendation$optimal_scan_time > 0)
  expect_true(result$recommendation$expected_satisfaction >= 0 &&
              result$recommendation$expected_satisfaction <= 1)

  # Verify metadata
  expect_equal(result$metadata$target_dppp, 7.0)
  expect_equal(result$metadata$dppp_tolerance, 0.5)
})

# =====================================================
# Test: Edge Cases
# =====================================================

test_that("handles edge cases gracefully", {
  mock_data <- create_mock_stage1_output(n_precursors = 100)

  # Edge case 1: Very low scan_time
  expect_warning(
    calculate_current_dppp_distribution(
      mock_data, user_scan_time = 0.5, target_dppp = 7.0,
      dppp_tolerance = 0.5, instrument_preset = "astral"
    ),
    "scan time"
  )

  # Edge case 2: Very high scan_time
  result <- calculate_current_dppp_distribution(
    mock_data, user_scan_time = 5.0, target_dppp = 7.0,
    dppp_tolerance = 0.5, instrument_preset = "astral"
  )
  expect_true(result$satisfaction_ratio >= 0)

  # Edge case 3: ID mode (target_dppp = 1.5)
  result <- diagnose_dppp_status(
    mock_data, user_scan_time = 2.0, target_dppp = 1.5,
    dppp_tolerance = 0.2, target_satisfaction_ratio = 0.85,
    instrument_preset = "astral"
  )
  expect_equal(result$metadata$target_dppp, 1.5)
})
```

---

## Definition of Done

Phase 2 개발 완료 기준:

### 기능 완성도
- [ ] `calculate_current_dppp_distribution()` 구현 완료
- [ ] `compute_satisfaction_ratio()` 구현 완료
- [ ] `recommend_scan_time()` 구현 완료
- [ ] `check_instrument_feasibility()` 구현 완료
- [ ] `diagnose_dppp_status()` 통합 함수 구현 완료

### 테스트 커버리지
- [ ] 모든 public 함수에 대한 unit test 작성
- [ ] Edge case 테스트 통과 (scan_time 범위, DPPP 모드)
- [ ] Mock data로 전체 워크플로우 테스트 통과
- [ ] Instrument preset별 테스트 통과 (Astral, Exploris, Orbitrap)

### 코드 품질
- [ ] 모든 함수에 roxygen2 문서화 완료
- [ ] 에러 처리 및 경고 메시지 구현
- [ ] 진행 상황 출력 (progress reporting)
- [ ] 코드 리뷰 완료

### 통합 준비
- [ ] Phase 1 출력과 호환성 확인 (ValidatedData 구조)
- [ ] Phase 3 입력 준비 (DiagnosisResult 구조)
- [ ] Mock data 생성 함수 작성 (`create_mock_stage2_output()`)
- [ ] Fixture 데이터 저장 (`tests/fixtures/stage2_output.rds`)

### 문서화
- [ ] 함수별 사용 예시 작성
- [ ] API 문서 업데이트 (`docs/API_SPECIFICATION.md`)
- [ ] Phase 2 개발 가이드 완료 (이 문서)
- [ ] DEVELOPMENT.md 진행 상황 업데이트

### 검증
- [ ] Quant 모드 (DPPP 7.0) 시나리오 테스트
- [ ] ID 모드 (DPPP 1.5) 시나리오 테스트
- [ ] Astral과 Exploris instrument 비교 테스트
- [ ] Satisfaction ratio 정확도 검증 (tolerance ± 0.5)
- [ ] Scan_time 추천의 타당성 검증 (trade-off 분석)

---

## 참고 자료

### 관련 문서
- [API Specification](../API_SPECIFICATION.md)
- [Architecture](../ARCHITECTURE.md)
- [Phase 1: Data Validation](PHASE1_DATA_VALIDATION.md)
- [Phase 3A: Window Count Determination](PHASE3A_WINDOW_COUNT.md)

### 관련 코드
- `config/instruments.R` - Instrument preset 정의
- `R/dppp_calculator.R` - DPPP 계산 공식
- `R/utils.R` - Utility 함수

### DPPP 공식
```r
# Spectronaut standard
DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds

# Cycle time (instrument-dependent)
# Astral (parallel):
cycle_time = max(MS1_time, n_windows × MS2_time)

# Orbitrap (sequential):
cycle_time = MS1_time + (n_windows × MS2_time)
```

### 만족도 목표
- **Quant 모드**: target_dppp = 7.0, satisfaction ≥ 85%
- **ID 모드**: target_dppp = 1.5, satisfaction ≥ 85%
- **Balanced 모드**: target_dppp = 4.0, satisfaction ≥ 80%

---

## 개발 시작하기

```bash
# 1. Phase 1 완료 확인
R
source("tests/mocks/mock_stage1_output.R")
mock_data <- create_mock_stage1_output()
str(mock_data)  # ValidatedData 구조 확인

# 2. Phase 2 스켈레톤 생성
# R/stage2_dppp_diagnosis.R 파일 생성 (위 구현 가이드 참조)

# 3. 첫 함수 구현 (compute_satisfaction_ratio)
# 가장 간단한 함수부터 시작

# 4. Unit test 작성 및 실행
source("tests/test_stage2.R")
test_file("tests/test_stage2.R")

# 5. Mock data 생성 함수 작성
source("tests/mocks/mock_stage2_output.R")
mock_result <- create_mock_stage2_output()
str(mock_result)

# 6. 다음 함수로 이동 (calculate_current_dppp_distribution)
```

**개발 순서 권장**:
1. `compute_satisfaction_ratio()` - 가장 간단
2. `calculate_window_count()` - Helper 함수
3. `compute_cycle_time()` - Helper 함수
4. `calculate_current_dppp_distribution()` - 위 함수들 활용
5. `recommend_scan_time()` - DPPP 계산 활용
6. `check_instrument_feasibility()` - 독립적
7. `diagnose_dppp_status()` - 통합 함수

---

**End of Phase 2 Development Guide**
