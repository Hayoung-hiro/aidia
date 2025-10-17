# Phase 3A: Window Count Determination - Development Guide

**Version**: 2.0
**Last Updated**: 2025-10-16
**Status**: 🟢 완료 (Refactored)
**Priority**: ⭐⭐⭐ 우선순위 3
**Completion Date**: 2025-10-16

---

## 🎉 Phase 3A 완료 - 주요 구현 사항 (v2.0)

### 2025-10-16 Refactoring 완료

**핵심 변경사항**:
1. **3-Level Configuration Architecture**: Static (instrument) vs Module Constants vs Dynamic (user parameters)
2. **Terminology Unification**: `cycle_calculation = "parallel"/"sequential"` (replaced ms2_based/traditional)
3. **3-Mode Override Logic**: "optimize", NULL (→ optimize), or integer (user-specified with feasibility check)
4. **Slack-based MaxIT Optimization**: Automatic MS2 maxIT increase when slack ≥ 0.5 sec
5. **Load Factor System**: Conservative 0.8 default with user override capability
6. **ms1_scans as User Parameter**: 0 for parallel (Astral), 1+ for sequential (Orbitrap)

**New Output Structure**:
- `window_count_mode`: Mode tracking ("optimize" or "user_specified_N")
- `scan_rate_settings`: max_scan_rate_hz, load_factor, effective_scan_rate_hz, ms1_scans
- `maxIT_optimization`: Slack utilization details and signal quality improvement

**Testing**:
- ✅ 6 test suites, all passing
- ✅ Fixtures created (diagnosis_quant, diagnosis_id, diagnosis_orbitrap)
- ✅ Cross-instrument validation (Astral 160 windows vs Orbitrap 27 windows)

**Files Updated**:
- [config/instruments.R](../../config/instruments.R) - Simplified to 7 fields
- [R/stage3_window_optimization/module3a_window_count.R](../../R/stage3_window_optimization/module3a_window_count.R) - Complete refactoring
- [tests/create_fixtures.R](../../tests/create_fixtures.R) - Fixture generation
- [tests/test_module3a_integration.R](../../tests/test_module3a_integration.R) - Integration tests
- [docs/API_SPECIFICATION.md](../API_SPECIFICATION.md) - Section 3.0 added

---

## 📋 목차

1. [개요](#개요)
2. [Phase 3A 목표](#phase-3a-목표)
3. [입출력 스펙](#입출력-스펙)
4. [기능 요구사항](#기능-요구사항)
5. [구현 가이드](#구현-가이드)
6. [테스트 전략](#테스트-전략)
7. [Definition of Done](#definition-of-done)

---

## 개요

### Phase 3A의 역할

**Window Count Determination**은 사용자가 원하는 scan_time과 instrument 제약을 기반으로 최적의 isolation window 개수를 결정하는 단계입니다.

**핵심 철학**:
- **Instrument-Aware**: 각 instrument의 scan rate와 timing 제약 반영
- **Cycle Time 기반**: DPPP 목표를 달성하면서 instrument 한계 내에서 동작
- **Raw Metadata 활용**: 실측 injection time 기반 maxIT 조정 (선택)

### 주요 계산

```r
# Window count 계산 공식
n_windows = floor(scan_time × scan_rate_hz) - 1  # -1 for MS1

# Cycle time 계산 (instrument-dependent)
# Astral (parallel acquisition):
cycle_time = max(MS1_time, n_windows × MS2_time)

# Orbitrap (sequential acquisition):
cycle_time = MS1_time + (n_windows × MS2_time)

# Feasibility check
is_feasible = (cycle_time <= scan_time) AND (n_windows >= min_windows)
```

### 입력 데이터

Phase 2의 출력 (DiagnosisResult):
```r
diagnosis <- structure(
  list(
    recommendation = list(
      optimal_scan_time = 1.85,
      expected_window_count = 120
    ),
    instrument_constraints = list(
      instrument_type = "astral",
      max_scan_rate = 50,
      ms1_time = 0.1,
      ms2_time = 0.015
    )
  ),
  class = c("DiagnosisResult", "list")
)
```

### 출력 데이터

```r
WindowCountResult <- structure(
  list(
    window_count = integer(),              # Final determined window count
    scan_time = numeric(),                 # Scan time used (sec)
    cycle_time = numeric(),                # Calculated cycle time (sec)

    timing_breakdown = list(
      ms1_time = numeric(),                # MS1 acquisition time (sec)
      ms2_time_per_window = numeric(),     # MS2 per window (sec)
      total_ms2_time = numeric(),          # Total MS2 time (sec)
      overhead_time = numeric()            # Overhead (sec)
    ),

    feasibility = list(
      is_feasible = logical(),
      scan_rate_check = logical(),         # Within scan rate limit?
      cycle_time_check = logical(),        # cycle_time <= scan_time?
      min_windows_check = logical(),       # n_windows >= min_windows?
      warnings = character()
    ),

    raw_metadata = list(                   # Optional: if enable_raw_metadata = TRUE
      actual_injection_times = numeric(),  # Measured IT values (ms)
      recommended_maxIT = numeric(),       # Suggested maxIT (ms)
      it_adjustment_applied = logical()
    ),

    metadata = list(
      instrument_type = character(),
      scan_rate_hz = numeric(),
      target_dppp = numeric(),
      calculation_timestamp = POSIXct()
    )
  ),
  class = c("WindowCountResult", "list")
)
```

---

## Phase 3A 목표

### 주요 기능

1. **Window Count 계산**
   - scan_time과 instrument scan_rate 기반 계산
   - MS1 scan을 제외한 MS2 window 개수 결정
   - Instrument type별 최적화 (Astral, Exploris, traditional)

2. **Cycle Time 검증**
   - Parallel acquisition (Astral): `max(MS1_time, n_windows × MS2_time)`
   - Sequential acquisition (Orbitrap): `MS1_time + (n_windows × MS2_time)`
   - Cycle time이 scan_time을 초과하지 않도록 보장

3. **Scan Rate Feasibility**
   - Instrument의 최대 scan rate 제약 확인
   - 총 scan 개수 (MS1 + MS2 windows) ≤ max_possible_scans
   - 위반 시 경고 및 조정 제안

4. **Raw Metadata 통합 (선택)**
   - Raw file에서 실측된 injection time 분석
   - 평균 injection time 기반 maxIT 추천
   - AGC target과 maxIT 조정으로 cycle time 최적화

### 성공 지표

- [x] Window count가 instrument 제약 내에서 정확하게 계산됨
- [x] Cycle time이 scan_time을 초과하지 않음
- [x] Instrument type별 계산 방식이 올바르게 적용됨
- [x] Raw metadata 사용 시 injection time 기반 조정 적용
- [x] Feasibility check가 모든 제약을 검증

---

## 입출력 스펙

### Input Specification

```r
# Phase 2 출력 (필수)
diagnosis <- create_mock_stage2_output()

# User 입력 파라미터
scan_time <- 1.85                        # 초 단위 (from Phase 2 recommendation)
target_dppp <- 7.0                       # Quant 모드
instrument_preset <- "astral"            # Instrument type

# Raw metadata 통합 (선택)
enable_raw_metadata <- FALSE             # TRUE if rawfile/ directory present
rawfile_dir <- "rawfile/"                # Path to raw MS files
```

### Output Specification

```r
# WindowCountResult 구조
window_count_result <- determine_window_count(
  diagnosis = diagnosis,
  scan_time = 1.85,
  target_dppp = 7.0,
  instrument_preset = "astral",
  enable_raw_metadata = FALSE
)

# 접근 예시
window_count_result$window_count           # 120
window_count_result$cycle_time             # 1.8 sec
window_count_result$feasibility$is_feasible  # TRUE
window_count_result$timing_breakdown$ms1_time  # 0.1 sec
window_count_result$timing_breakdown$total_ms2_time  # 1.8 sec
```

---

## 기능 요구사항

### 1. Window Count 계산

**함수**: `calculate_window_count_from_scantime()`

**목적**: scan_time과 instrument scan_rate로부터 MS2 window 개수 계산

**알고리즘**:
```r
# Step 1: Calculate total available scans
total_scans <- floor(scan_time × scan_rate_hz)

# Step 2: Reserve 1 scan for MS1
n_windows <- total_scans - 1

# Step 3: Apply minimum constraint
min_windows <- 20  # Configurable minimum
n_windows <- max(n_windows, min_windows)

# Step 4: Verify against maximum
max_windows <- 500  # Configurable maximum
if (n_windows > max_windows) {
  warning(sprintf("Calculated window count (%d) exceeds maximum (%d). Capping at %d.",
                  n_windows, max_windows, max_windows))
  n_windows <- max_windows
}

return(n_windows)
```

**구현 체크리스트**:
- [ ] scan_time과 scan_rate로 total scans 계산
- [ ] MS1 scan 제외 (-1)
- [ ] Minimum window count 제약 적용
- [ ] Maximum window count 제약 적용
- [ ] 경고 메시지 생성 (cap 발생 시)
- [ ] 입력 검증 (scan_time > 0, scan_rate > 0)

**에러 처리**:
- scan_time ≤ 0 → 에러
- scan_rate ≤ 0 → 에러
- total_scans < 2 (no room for MS2) → 에러 + 제안

---

### 2. Cycle Time 계산

**함수**: `calculate_cycle_time()`

**목적**: Instrument type에 따라 cycle time 계산

**알고리즘**:
```r
calculate_cycle_time <- function(n_windows, instrument_type, ms1_time, ms2_time) {
  total_ms2_time <- n_windows * ms2_time

  if (instrument_type == "astral") {
    # Parallel acquisition: MS2 scans happen during MS1
    cycle_time <- max(ms1_time, total_ms2_time)
  } else {
    # Sequential acquisition: MS1 then MS2
    cycle_time <- ms1_time + total_ms2_time
  }

  return(list(
    cycle_time = cycle_time,
    ms1_time = ms1_time,
    ms2_time_per_window = ms2_time,
    total_ms2_time = total_ms2_time
  ))
}
```

**구현 체크리스트**:
- [ ] Instrument type 분기 (astral vs others)
- [ ] Parallel acquisition: `max(MS1, total_MS2)` 계산
- [ ] Sequential acquisition: `MS1 + total_MS2` 계산
- [ ] Timing breakdown 반환 (상세 정보)
- [ ] Overhead time 고려 (선택, 기본 0)
- [ ] 입력 검증 (n_windows > 0, ms1_time > 0, ms2_time > 0)

**Instrument Type별 계산**:
- **Astral**: `cycle_time = max(0.1, 120 × 0.015) = max(0.1, 1.8) = 1.8 sec`
- **Exploris**: `cycle_time = 0.05 + (120 × 0.02) = 0.05 + 2.4 = 2.45 sec`
- **Traditional Orbitrap**: `cycle_time = 0.1 + (60 × 0.08) = 0.1 + 4.8 = 4.9 sec`

---

### 3. Scan Rate Feasibility Check

**함수**: `check_scan_rate_feasibility()`

**목적**: Window count가 instrument scan rate 제약 내에 있는지 확인

**알고리즘**:
```r
check_scan_rate_feasibility <- function(
  n_windows,
  scan_time,
  max_scan_rate_hz
) {
  # Calculate maximum possible scans
  max_possible_scans <- floor(scan_time * max_scan_rate_hz)

  # Total scans needed (MS1 + MS2 windows)
  total_scans_needed <- n_windows + 1

  # Check feasibility
  is_feasible <- total_scans_needed <= max_possible_scans

  # Generate warning if not feasible
  warning_msg <- NULL
  if (!is_feasible) {
    warning_msg <- sprintf(
      "Window count (%d) + MS1 (1) = %d scans exceeds maximum (%d scans in %.2f sec at %.0f Hz). Reduce window count to %d or increase scan_time.",
      n_windows, total_scans_needed, max_possible_scans, scan_time, max_scan_rate_hz,
      max_possible_scans - 1
    )
  }

  return(list(
    is_feasible = is_feasible,
    total_scans_needed = total_scans_needed,
    max_possible_scans = max_possible_scans,
    warning = warning_msg
  ))
}
```

**구현 체크리스트**:
- [ ] max_possible_scans 계산
- [ ] total_scans_needed 계산 (n_windows + 1)
- [ ] Feasibility 판정
- [ ] 경고 메시지 생성 (실패 시)
- [ ] 조정 제안 포함 (reduce window count or increase scan_time)
- [ ] 입력 검증

---

### 4. Cycle Time vs Scan Time Check

**함수**: `check_cycle_time_feasibility()`

**목적**: Cycle time이 scan_time을 초과하지 않는지 확인

**알고리즘**:
```r
check_cycle_time_feasibility <- function(cycle_time, scan_time, tolerance = 0.01) {
  # Allow small tolerance for floating point precision
  is_feasible <- cycle_time <= (scan_time + tolerance)

  # Generate warning if not feasible
  warning_msg <- NULL
  if (!is_feasible) {
    warning_msg <- sprintf(
      "Calculated cycle time (%.3f sec) exceeds scan time (%.2f sec). Reduce window count or increase MS2 speed.",
      cycle_time, scan_time
    )
  }

  return(list(
    is_feasible = is_feasible,
    cycle_time = cycle_time,
    scan_time = scan_time,
    margin = scan_time - cycle_time,  # Positive = OK, Negative = Problem
    warning = warning_msg
  ))
}
```

**구현 체크리스트**:
- [ ] Cycle time vs scan_time 비교
- [ ] Floating point tolerance 적용 (기본 0.01 sec)
- [ ] Feasibility 판정
- [ ] 경고 메시지 생성 (실패 시)
- [ ] Margin 계산 (여유 시간)
- [ ] 조정 제안 포함

---

### 5. Raw Metadata 통합 (선택)

**함수**: `adjust_for_injection_time()`

**목적**: Raw file의 실측 injection time 기반으로 maxIT 추천

**알고리즘**:
```r
adjust_for_injection_time <- function(
  rawfile_dir,
  current_ms2_time,
  target_reduction_pct = 0.9  # Reduce IT by 10%
) {
  # Step 1: Load raw metadata
  raw_metadata <- load_raw_metadata(rawfile_dir)

  # Step 2: Extract actual injection times (ms)
  actual_it_values <- raw_metadata$ms2_injection_times

  # Step 3: Calculate statistics
  mean_it <- mean(actual_it_values, na.rm = TRUE)
  median_it <- median(actual_it_values, na.rm = TRUE)
  p95_it <- quantile(actual_it_values, 0.95, na.rm = TRUE)

  # Step 4: Recommend reduced maxIT (10% reduction)
  recommended_maxIT <- median_it * target_reduction_pct

  # Step 5: Estimate new MS2 time
  # Assumption: IT reduction proportionally reduces MS2 time
  adjusted_ms2_time <- current_ms2_time * (recommended_maxIT / median_it)

  return(list(
    actual_injection_times = actual_it_values,
    mean_it = mean_it,
    median_it = median_it,
    p95_it = p95_it,
    current_median_it = median_it,
    recommended_maxIT = recommended_maxIT,
    current_ms2_time = current_ms2_time,
    adjusted_ms2_time = adjusted_ms2_time,
    time_saved_per_window = current_ms2_time - adjusted_ms2_time,
    it_adjustment_applied = TRUE
  ))
}
```

**구현 체크리스트**:
- [ ] Raw file 존재 여부 확인
- [ ] Raw metadata 로딩 (Phase 1 함수 활용)
- [ ] Injection time 통계 계산
- [ ] Recommended maxIT 계산 (median × 0.9)
- [ ] Adjusted MS2 time 추정
- [ ] Time savings 계산
- [ ] 조정 적용 여부 플래그

**에러 처리**:
- rawfile_dir 없음 → 경고 + skip raw metadata
- Raw metadata 파싱 실패 → 경고 + skip adjustment
- Injection time 데이터 없음 → 경고 + skip adjustment

---

### 6. 통합 함수

**함수**: `determine_window_count()`

**목적**: Phase 3A의 모든 계산을 통합하여 실행

**워크플로우**:
```r
determine_window_count <- function(
  diagnosis,
  scan_time = NULL,                      # If NULL, use diagnosis$recommendation$optimal_scan_time
  target_dppp = 7.0,
  instrument_preset = "astral",
  enable_raw_metadata = FALSE,
  rawfile_dir = NULL,
  min_windows = 20,
  max_windows = 500
) {
  cat("=== Phase 3A: Window Count Determination ===\n\n")

  # Step 0: Load instrument configuration
  cat("Step 0: Loading instrument configuration...\n")
  instrument_config <- load_instrument_config(instrument_preset)
  ms1_time <- instrument_config$ms1_time
  ms2_time <- instrument_config$ms2_time
  scan_rate_hz <- instrument_config$scan_rate_hz
  instrument_type <- instrument_config$type

  # Use recommended scan_time if not provided
  if (is.null(scan_time)) {
    scan_time <- diagnosis$recommendation$optimal_scan_time
    cat(sprintf("  Using recommended scan_time: %.2f sec\n", scan_time))
  }

  # Step 1: Calculate window count
  cat("\nStep 1: Calculating window count...\n")
  n_windows <- calculate_window_count_from_scantime(
    scan_time, scan_rate_hz, min_windows, max_windows
  )
  cat(sprintf("  Window count: %d\n", n_windows))

  # Step 2: Adjust for raw metadata (optional)
  raw_metadata_result <- NULL
  if (enable_raw_metadata && !is.null(rawfile_dir)) {
    cat("\nStep 2: Adjusting for raw metadata...\n")
    raw_metadata_result <- adjust_for_injection_time(rawfile_dir, ms2_time)
    if (raw_metadata_result$it_adjustment_applied) {
      ms2_time <- raw_metadata_result$adjusted_ms2_time
      cat(sprintf("  Adjusted MS2 time: %.4f sec (from %.4f sec)\n",
                  ms2_time, raw_metadata_result$current_ms2_time))
    }
  } else {
    cat("\nStep 2: Raw metadata integration disabled\n")
  }

  # Step 3: Calculate cycle time
  cat("\nStep 3: Calculating cycle time...\n")
  timing <- calculate_cycle_time(n_windows, instrument_type, ms1_time, ms2_time)
  cycle_time <- timing$cycle_time
  cat(sprintf("  Cycle time: %.3f sec (%s acquisition)\n",
              cycle_time, ifelse(instrument_type == "astral", "parallel", "sequential")))

  # Step 4: Feasibility checks
  cat("\nStep 4: Checking feasibility...\n")

  # Check 4a: Scan rate
  scan_rate_check <- check_scan_rate_feasibility(n_windows, scan_time, scan_rate_hz)
  if (scan_rate_check$is_feasible) {
    cat("  ✅ Scan rate check: PASS\n")
  } else {
    cat(sprintf("  ⚠️  Scan rate check: FAIL - %s\n", scan_rate_check$warning))
  }

  # Check 4b: Cycle time
  cycle_time_check <- check_cycle_time_feasibility(cycle_time, scan_time)
  if (cycle_time_check$is_feasible) {
    cat(sprintf("  ✅ Cycle time check: PASS (margin: %.3f sec)\n", cycle_time_check$margin))
  } else {
    cat(sprintf("  ⚠️  Cycle time check: FAIL - %s\n", cycle_time_check$warning))
  }

  # Check 4c: Minimum windows
  min_windows_check <- (n_windows >= min_windows)
  if (min_windows_check) {
    cat(sprintf("  ✅ Minimum windows check: PASS (%d >= %d)\n", n_windows, min_windows))
  } else {
    cat(sprintf("  ⚠️  Minimum windows check: FAIL (%d < %d)\n", n_windows, min_windows))
  }

  # Overall feasibility
  is_feasible <- scan_rate_check$is_feasible &&
                 cycle_time_check$is_feasible &&
                 min_windows_check

  # Collect warnings
  warnings <- c()
  if (!is.null(scan_rate_check$warning)) warnings <- c(warnings, scan_rate_check$warning)
  if (!is.null(cycle_time_check$warning)) warnings <- c(warnings, cycle_time_check$warning)
  if (!min_windows_check) {
    warnings <- c(warnings, sprintf("Window count (%d) below minimum (%d)", n_windows, min_windows))
  }

  # Step 5: Package results
  cat("\nStep 5: Packaging results...\n")
  result <- structure(
    list(
      window_count = n_windows,
      scan_time = scan_time,
      cycle_time = cycle_time,

      timing_breakdown = list(
        ms1_time = timing$ms1_time,
        ms2_time_per_window = timing$ms2_time_per_window,
        total_ms2_time = timing$total_ms2_time,
        overhead_time = 0  # Reserved for future use
      ),

      feasibility = list(
        is_feasible = is_feasible,
        scan_rate_check = scan_rate_check$is_feasible,
        cycle_time_check = cycle_time_check$is_feasible,
        min_windows_check = min_windows_check,
        warnings = warnings
      ),

      raw_metadata = if (!is.null(raw_metadata_result)) raw_metadata_result else list(),

      metadata = list(
        instrument_type = instrument_type,
        scan_rate_hz = scan_rate_hz,
        target_dppp = target_dppp,
        calculation_timestamp = Sys.time()
      )
    ),
    class = c("WindowCountResult", "list")
  )

  cat("\n=== Phase 3A Complete ===\n")
  if (is_feasible) {
    cat(sprintf("✅ Window count determination successful: %d windows\n", n_windows))
  } else {
    cat("⚠️  Window count determination completed with warnings. Review feasibility checks.\n")
  }

  return(result)
}
```

**구현 체크리스트**:
- [ ] 모든 하위 함수 호출
- [ ] 진행 상황 출력 (progress reporting)
- [ ] 에러 발생 시 graceful handling
- [ ] 결과 객체 구조화 (WindowCountResult class)
- [ ] 입력 파라미터 검증
- [ ] Optional scan_time (use recommendation if NULL)
- [ ] Optional raw metadata integration

---

## 구현 가이드

### 파일 구조

```r
# R/stage3_window_optimization/module3a_window_count.R

# =====================================================
# Phase 3A: Window Count Determination
# =====================================================

#' Calculate Window Count from Scan Time
#'
#' @param scan_time Numeric, scan time in seconds
#' @param scan_rate_hz Numeric, instrument scan rate in Hz
#' @param min_windows Integer, minimum allowed windows (default: 20)
#' @param max_windows Integer, maximum allowed windows (default: 500)
#'
#' @return Integer, number of MS2 windows
#' @export
calculate_window_count_from_scantime <- function(
  scan_time,
  scan_rate_hz,
  min_windows = 20,
  max_windows = 500
) {
  # TODO: Implement window count calculation
  # 1. Validate inputs
  # 2. Calculate total scans
  # 3. Reserve 1 for MS1
  # 4. Apply min/max constraints
  # 5. Generate warnings if capped

  stop("Not implemented yet")
}

#' Calculate Cycle Time
#'
#' @param n_windows Integer, number of isolation windows
#' @param instrument_type Character, "astral" or other
#' @param ms1_time Numeric, MS1 acquisition time (sec)
#' @param ms2_time Numeric, MS2 acquisition time per window (sec)
#'
#' @return List with cycle_time, ms1_time, ms2_time_per_window, total_ms2_time
#' @export
calculate_cycle_time <- function(n_windows, instrument_type, ms1_time, ms2_time) {
  # TODO: Implement cycle time calculation
  # 1. Calculate total MS2 time
  # 2. Branch on instrument type (parallel vs sequential)
  # 3. Return detailed timing breakdown

  stop("Not implemented yet")
}

#' Check Scan Rate Feasibility
#'
#' @param n_windows Integer, number of windows
#' @param scan_time Numeric, scan time in seconds
#' @param max_scan_rate_hz Numeric, maximum scan rate in Hz
#'
#' @return List with is_feasible, total_scans_needed, max_possible_scans, warning
#' @export
check_scan_rate_feasibility <- function(n_windows, scan_time, max_scan_rate_hz) {
  # TODO: Implement scan rate feasibility check
  # 1. Calculate max possible scans
  # 2. Calculate total scans needed
  # 3. Compare and determine feasibility
  # 4. Generate warning if infeasible

  stop("Not implemented yet")
}

#' Check Cycle Time Feasibility
#'
#' @param cycle_time Numeric, calculated cycle time (sec)
#' @param scan_time Numeric, target scan time (sec)
#' @param tolerance Numeric, tolerance for floating point (default: 0.01)
#'
#' @return List with is_feasible, cycle_time, scan_time, margin, warning
#' @export
check_cycle_time_feasibility <- function(cycle_time, scan_time, tolerance = 0.01) {
  # TODO: Implement cycle time feasibility check
  # 1. Compare cycle_time vs scan_time
  # 2. Apply tolerance
  # 3. Calculate margin
  # 4. Generate warning if infeasible

  stop("Not implemented yet")
}

#' Adjust for Injection Time (Raw Metadata)
#'
#' @param rawfile_dir Character, path to raw files directory
#' @param current_ms2_time Numeric, current MS2 time (sec)
#' @param target_reduction_pct Numeric, target IT reduction (default: 0.9 = 10% reduction)
#'
#' @return List with injection time statistics and recommended maxIT
#' @export
adjust_for_injection_time <- function(
  rawfile_dir,
  current_ms2_time,
  target_reduction_pct = 0.9
) {
  # TODO: Implement raw metadata adjustment
  # 1. Load raw metadata (use Phase 1 functions)
  # 2. Extract injection times
  # 3. Calculate statistics (mean, median, p95)
  # 4. Recommend reduced maxIT
  # 5. Estimate adjusted MS2 time
  # 6. Return adjustment details

  stop("Not implemented yet")
}

#' Determine Window Count (Main Function)
#'
#' @param diagnosis DiagnosisResult from Phase 2
#' @param scan_time Numeric, scan time (NULL = use recommendation)
#' @param target_dppp Numeric, target DPPP
#' @param instrument_preset Character, instrument type
#' @param enable_raw_metadata Logical, enable raw metadata integration
#' @param rawfile_dir Character, path to raw files
#' @param min_windows Integer, minimum windows (default: 20)
#' @param max_windows Integer, maximum windows (default: 500)
#'
#' @return WindowCountResult object
#' @export
determine_window_count <- function(
  diagnosis,
  scan_time = NULL,
  target_dppp = 7.0,
  instrument_preset = "astral",
  enable_raw_metadata = FALSE,
  rawfile_dir = NULL,
  min_windows = 20,
  max_windows = 500
) {
  # TODO: Implement integrated window count determination
  # 1. Load instrument config
  # 2. Calculate window count
  # 3. Adjust for raw metadata (optional)
  # 4. Calculate cycle time
  # 5. Run feasibility checks
  # 6. Package results

  stop("Not implemented yet")
}
```

---

## 테스트 전략

### Mock Data 생성

**파일**: `tests/mocks/mock_stage3a_output.R`

```r
#' Create Mock Stage 3A Output
#'
#' @param n_windows Number of windows (default: 120)
#' @param scan_time Scan time in seconds (default: 1.85)
#' @param instrument_type Instrument type (default: "astral")
#'
#' @return WindowCountResult object
#' @export
create_mock_stage3a_output <- function(
  n_windows = 120,
  scan_time = 1.85,
  instrument_type = "astral"
) {
  # Mock timing calculation
  ms1_time <- 0.1
  ms2_time <- 0.015
  total_ms2_time <- n_windows * ms2_time

  if (instrument_type == "astral") {
    cycle_time <- max(ms1_time, total_ms2_time)
  } else {
    cycle_time <- ms1_time + total_ms2_time
  }

  # Mock result
  result <- structure(
    list(
      window_count = n_windows,
      scan_time = scan_time,
      cycle_time = cycle_time,

      timing_breakdown = list(
        ms1_time = ms1_time,
        ms2_time_per_window = ms2_time,
        total_ms2_time = total_ms2_time,
        overhead_time = 0
      ),

      feasibility = list(
        is_feasible = TRUE,
        scan_rate_check = TRUE,
        cycle_time_check = TRUE,
        min_windows_check = TRUE,
        warnings = character(0)
      ),

      raw_metadata = list(),

      metadata = list(
        instrument_type = instrument_type,
        scan_rate_hz = 50,
        target_dppp = 7.0,
        calculation_timestamp = Sys.time()
      )
    ),
    class = c("WindowCountResult", "list")
  )

  return(result)
}
```

---

### Unit Tests

**파일**: `tests/test_stage3a.R`

```r
library(testthat)
source("tests/mocks/mock_stage2_output.R")
source("R/stage3_window_optimization/module3a_window_count.R")

# =====================================================
# Test: Window Count Calculation
# =====================================================

test_that("calculate_window_count_from_scantime works correctly", {
  # Test case 1: Standard Astral parameters
  n_win <- calculate_window_count_from_scantime(
    scan_time = 2.0,
    scan_rate_hz = 50,
    min_windows = 20,
    max_windows = 500
  )

  expect_equal(n_win, 99)  # floor(2.0 * 50) - 1 = 100 - 1 = 99

  # Test case 2: Low scan time
  n_win <- calculate_window_count_from_scantime(
    scan_time = 0.5,
    scan_rate_hz = 50,
    min_windows = 20,
    max_windows = 500
  )

  expect_equal(n_win, 20)  # floor(0.5 * 50) - 1 = 24, but capped at min_windows

  # Test case 3: High scan time
  n_win <- calculate_window_count_from_scantime(
    scan_time = 12.0,
    scan_rate_hz = 50,
    min_windows = 20,
    max_windows = 500
  )

  expect_equal(n_win, 500)  # floor(12.0 * 50) - 1 = 599, but capped at max_windows
})

# =====================================================
# Test: Cycle Time Calculation
# =====================================================

test_that("calculate_cycle_time handles parallel and sequential correctly", {
  # Test case 1: Astral (parallel)
  timing <- calculate_cycle_time(
    n_windows = 120,
    instrument_type = "astral",
    ms1_time = 0.1,
    ms2_time = 0.015
  )

  expect_equal(timing$cycle_time, max(0.1, 120 * 0.015))  # max(0.1, 1.8) = 1.8
  expect_equal(timing$ms1_time, 0.1)
  expect_equal(timing$total_ms2_time, 1.8)

  # Test case 2: Exploris (sequential)
  timing <- calculate_cycle_time(
    n_windows = 120,
    instrument_type = "orbitrap_exploris",
    ms1_time = 0.05,
    ms2_time = 0.02
  )

  expect_equal(timing$cycle_time, 0.05 + (120 * 0.02))  # 0.05 + 2.4 = 2.45
  expect_equal(timing$ms1_time, 0.05)
  expect_equal(timing$total_ms2_time, 2.4)
})

# =====================================================
# Test: Scan Rate Feasibility
# =====================================================

test_that("check_scan_rate_feasibility validates constraints", {
  # Test case 1: Feasible configuration
  result <- check_scan_rate_feasibility(
    n_windows = 99,
    scan_time = 2.0,
    max_scan_rate_hz = 50
  )

  expect_true(result$is_feasible)
  expect_equal(result$total_scans_needed, 100)  # 99 + 1
  expect_equal(result$max_possible_scans, 100)  # floor(2.0 * 50)
  expect_null(result$warning)

  # Test case 2: Infeasible configuration
  result <- check_scan_rate_feasibility(
    n_windows = 150,
    scan_time = 2.0,
    max_scan_rate_hz = 50
  )

  expect_false(result$is_feasible)
  expect_equal(result$total_scans_needed, 151)
  expect_equal(result$max_possible_scans, 100)
  expect_true(!is.null(result$warning))
})

# =====================================================
# Test: Cycle Time Feasibility
# =====================================================

test_that("check_cycle_time_feasibility validates timing", {
  # Test case 1: Feasible (cycle < scan)
  result <- check_cycle_time_feasibility(
    cycle_time = 1.8,
    scan_time = 2.0
  )

  expect_true(result$is_feasible)
  expect_equal(result$margin, 0.2)  # 2.0 - 1.8
  expect_null(result$warning)

  # Test case 2: Infeasible (cycle > scan)
  result <- check_cycle_time_feasibility(
    cycle_time = 2.5,
    scan_time = 2.0
  )

  expect_false(result$is_feasible)
  expect_equal(result$margin, -0.5)  # 2.0 - 2.5
  expect_true(!is.null(result$warning))
})

# =====================================================
# Test: Integrated Determination
# =====================================================

test_that("determine_window_count integrates all components", {
  # Setup
  mock_diagnosis <- create_mock_stage2_output()

  # Execute
  result <- determine_window_count(
    diagnosis = mock_diagnosis,
    scan_time = 1.85,
    target_dppp = 7.0,
    instrument_preset = "astral",
    enable_raw_metadata = FALSE
  )

  # Verify class
  expect_s3_class(result, "WindowCountResult")

  # Verify structure
  expect_true(all(c("window_count", "scan_time", "cycle_time", "timing_breakdown",
                    "feasibility", "metadata") %in% names(result)))

  # Verify values
  expect_true(result$window_count > 0)
  expect_equal(result$scan_time, 1.85)
  expect_true(result$cycle_time > 0)
  expect_true(result$feasibility$is_feasible)

  # Verify timing breakdown
  expect_true(result$timing_breakdown$ms1_time > 0)
  expect_true(result$timing_breakdown$ms2_time_per_window > 0)
  expect_true(result$timing_breakdown$total_ms2_time > 0)
})

# =====================================================
# Test: Raw Metadata Integration
# =====================================================

test_that("raw metadata adjustment works when enabled", {
  skip_if_not(dir.exists("tests/fixtures/rawfile"), "Raw files not available")

  mock_diagnosis <- create_mock_stage2_output()

  # Execute with raw metadata
  result <- determine_window_count(
    diagnosis = mock_diagnosis,
    scan_time = 1.85,
    instrument_preset = "astral",
    enable_raw_metadata = TRUE,
    rawfile_dir = "tests/fixtures/rawfile"
  )

  # Verify raw metadata section exists
  expect_true("raw_metadata" %in% names(result))
  expect_true(length(result$raw_metadata) > 0)

  # Verify adjustment applied
  if (result$raw_metadata$it_adjustment_applied) {
    expect_true(!is.null(result$raw_metadata$recommended_maxIT))
    expect_true(!is.null(result$raw_metadata$adjusted_ms2_time))
  }
})
```

---

## Definition of Done

Phase 3A 개발 완료 기준:

### 기능 완성도
- [ ] `calculate_window_count_from_scantime()` 구현 완료
- [ ] `calculate_cycle_time()` 구현 완료
- [ ] `check_scan_rate_feasibility()` 구현 완료
- [ ] `check_cycle_time_feasibility()` 구현 완료
- [ ] `adjust_for_injection_time()` 구현 완료 (optional)
- [ ] `determine_window_count()` 통합 함수 구현 완료

### 테스트 커버리지
- [ ] 모든 public 함수에 대한 unit test 작성
- [ ] Edge case 테스트 통과 (min/max windows, low/high scan_time)
- [ ] Mock data로 전체 워크플로우 테스트 통과
- [ ] Instrument preset별 테스트 통과 (Astral, Exploris)
- [ ] Raw metadata integration 테스트 (optional)

### 코드 품질
- [ ] 모든 함수에 roxygen2 문서화 완료
- [ ] 에러 처리 및 경고 메시지 구현
- [ ] 진행 상황 출력 (progress reporting)
- [ ] 코드 리뷰 완료

### 통합 준비
- [ ] Phase 2 출력과 호환성 확인 (DiagnosisResult)
- [ ] Phase 3B 입력 준비 (WindowCountResult)
- [ ] Mock data 생성 함수 작성 (`create_mock_stage3a_output()`)
- [ ] Fixture 데이터 저장 (`tests/fixtures/stage3a_output.rds`)

### 문서화
- [ ] 함수별 사용 예시 작성
- [ ] API 문서 업데이트 (`docs/API_SPECIFICATION.md`)
- [ ] Phase 3A 개발 가이드 완료 (이 문서)
- [ ] DEVELOPMENT.md 진행 상황 업데이트

### 검증
- [ ] Astral parallel acquisition 검증
- [ ] Exploris/Orbitrap sequential acquisition 검증
- [ ] Scan rate 제약 검증
- [ ] Cycle time 제약 검증
- [ ] Raw metadata integration 검증 (if enabled)

---

## 참고 자료

### 관련 문서
- [API Specification](../API_SPECIFICATION.md)
- [Architecture](../ARCHITECTURE.md)
- [Phase 2: DPPP Diagnosis](PHASE2_DPPP_DIAGNOSIS.md)
- [Phase 3B: RT Binning](PHASE3B_RT_BINNING.md)

### 관련 코드
- `config/instruments.R` - Instrument timing configurations
- `R/stage1_data_validation.R` - Raw metadata loading functions
- `R/stage2_dppp_diagnosis.R` - DPPP calculation and diagnosis

### Cycle Time 공식
```r
# Astral (parallel acquisition):
cycle_time = max(MS1_time, n_windows × MS2_time)
# MS2 scans happen during MS1 acquisition

# Orbitrap (sequential acquisition):
cycle_time = MS1_time + (n_windows × MS2_time)
# MS1 then MS2 scans sequentially
```

### Instrument Timing Examples

**Thermo Astral**:
- Max scan rate: 50 Hz (optimized: 100 Hz)
- MS1 time: 0.1 sec
- MS2 time: 0.015 sec (per window)
- Acquisition: Parallel (MS2 during MS1)
- Example: 120 windows → cycle_time = max(0.1, 120×0.015) = 1.8 sec

**Thermo Orbitrap Exploris**:
- Max scan rate: 25 Hz (optimized: 40 Hz)
- MS1 time: 0.05 sec
- MS2 time: 0.02 sec (per window)
- Acquisition: Sequential (MS1 then MS2)
- Example: 120 windows → cycle_time = 0.05 + (120×0.02) = 2.45 sec

---

## 개발 시작하기

```bash
# 1. Phase 2 완료 확인
R
source("tests/mocks/mock_stage2_output.R")
mock_diagnosis <- create_mock_stage2_output()
str(mock_diagnosis)

# 2. Instrument config 확인
source("config/instruments.R")
instruments <- get_all_instruments()
str(instruments$astral)

# 3. Phase 3A 디렉토리 생성
mkdir -p R/stage3_window_optimization

# 4. Phase 3A 스켈레톤 생성
# R/stage3_window_optimization/module3a_window_count.R 파일 생성

# 5. 첫 함수 구현 (calculate_window_count_from_scantime)
# 가장 간단한 함수부터 시작

# 6. Unit test 작성 및 실행
source("tests/test_stage3a.R")
test_file("tests/test_stage3a.R")
```

**개발 순서 권장**:
1. `calculate_window_count_from_scantime()` - 기본 계산
2. `calculate_cycle_time()` - Instrument type 분기
3. `check_scan_rate_feasibility()` - 제약 검증
4. `check_cycle_time_feasibility()` - 제약 검증
5. `adjust_for_injection_time()` - Optional raw metadata
6. `determine_window_count()` - 통합 함수

---

**End of Phase 3A Development Guide**
