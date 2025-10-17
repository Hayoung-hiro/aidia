# Phase 3D: Window Generation - Development Guide

**Version**: 1.0
**Last Updated**: 2025-10-13
**Status**: 🟡 부분 구현됨 (Variable 완료, Fixed/Overlapped 추가 필요)
**Priority**: ⭐⭐⭐ 우선순위 5
**Estimated Duration**: 3-4일

---

## 📋 목차

1. [개요](#개요)
2. [Phase 3D 목표](#phase-3d-목표)
3. [입출력 스펙](#입출력-스펙)
4. [Window Generation 모드](#window-generation-모드)
5. [구현 가이드](#구현-가이드)
6. [테스트 전략](#테스트-전략)
7. [Definition of Done](#definition-of-done)

---

## 개요

### Phase 3D의 역할

**Window Generation**은 최적화된 m/z 범위 내에서 실제 isolation window를 생성하는 최종 단계입니다.

**핵심 철학**:
- **3가지 모드 지원**: Fixed, Variable, Overlapped
- **기존 코드 활용**: `R/window_generator.R`의 Variable 모드 활용
- **사용자 제어**: Window 개수, 폭, overlap 비율 명시적 제어

### 기존 구현 상태

**✅ 완료된 기능** (`R/window_generator.R`):
- ✅ Variable window generation (density-based)
- ✅ Largest Remainder Method (exact window count allocation)
- ✅ Density analysis within boundaries
- ✅ Min/max width constraints

**🔴 추가 필요**:
- ❌ Fixed window generation
- ❌ Overlapped window generation
- ❌ 3가지 모드 통합 인터페이스

### 입력 데이터

Phase 3C의 출력 (MzRangeResult):
```r
mz_range_result <- structure(
  list(
    mz_ranges = tibble(
      rt_segment_id = integer(),
      rt_start = numeric(),
      rt_end = numeric(),
      mz_min = numeric(),
      mz_max = numeric(),
      mz_range_width = numeric(),
      n_precursors_covered = integer()
    ),
    ...
  ),
  class = c("MzRangeResult", "list")
)
```

### 출력 데이터

```r
WindowGenerationResult <- structure(
  list(
    windows = tibble(
      window_id = integer(),             # 1, 2, 3, ...
      rt_segment_id = integer(),         # RT segment
      rt_start = numeric(),              # RT range start (min)
      rt_end = numeric(),                # RT range end (min)
      mz_start = numeric(),              # Window start (Da)
      mz_end = numeric(),                # Window end (Da)
      mz_center = numeric(),             # Window center (Da)
      window_width = numeric(),          # Width (Da)
      n_precursors = integer(),          # Precursors in window
      overlap_prev = numeric(),          # Overlap with previous (Da)
      overlap_next = numeric()           # Overlap with next (Da)
    ),

    statistics = list(
      total_windows = integer(),
      target_windows = integer(),
      mean_precursors_per_window = numeric(),
      sd_precursors_per_window = numeric(),
      cv_precursors = numeric(),
      min_window_width = numeric(),
      max_window_width = numeric(),
      mean_window_width = numeric(),
      total_overlap_da = numeric()       # For overlapped mode
    ),

    coverage_analysis = list(
      total_precursors = integer(),
      covered_precursors = integer(),
      coverage_ratio = numeric(),
      uncovered_regions = tibble()       # Gaps in coverage
    ),

    parameters = list(
      window_type = character(),         # "fixed", "variable", "overlapped"
      n_windows = integer(),
      min_width_da = numeric(),
      max_width_da = numeric(),
      overlap_percentage = numeric()     # For overlapped mode
    ),

    metadata = list(
      generation_method = character(),
      allocation_method = character(),   # "largest_remainder" for variable
      generation_timestamp = POSIXct()
    )
  ),
  class = c("WindowGenerationResult", "list")
)
```

---

## Phase 3D 목표

### 주요 기능

1. **Fixed Window Generation**
   - 각 RT segment 내에서 등간격 고정폭 window 생성
   - Simple하고 예측 가능
   - Window 개수로 폭 자동 결정

2. **Variable Window Generation** (기존 활용)
   - Density-based adaptive window width
   - High density → narrow windows
   - Low density → wide windows
   - Largest Remainder Method로 정확한 window count

3. **Overlapped Window Generation**
   - Window 간 overlap 지원
   - Overlap percentage 사용자 지정 (예: 10%, 25%)
   - Precursor sampling 증가

4. **통합 인터페이스**
   - 3가지 모드를 단일 함수로 호출
   - 파라미터로 모드 선택
   - 일관된 출력 형식

### 성공 지표

- [x] Fixed window generation 구현 완료
- [x] Variable window generation 기존 코드 통합
- [x] Overlapped window generation 구현 완료
- [x] 3가지 모드 통합 인터페이스 완성
- [x] Coverage ratio ≥ 95% 달성
- [x] Window count deviation < 5%

---

## 입출력 스펙

### Input Specification

```r
# Phase 3B 출력 (RTBinningResult)
rt_binning_result <- create_mock_stage3b_output()

# Phase 3C 출력 (MzRangeResult)
mz_range_result <- create_mock_stage3c_output()

# User 입력 파라미터
window_type <- "variable"          # "fixed", "variable", "overlapped"
n_windows <- 100                   # Total window count
min_width_da <- 2                  # Minimum window width (Da)
max_width_da <- 80                 # Maximum window width (Da)
overlap_percentage <- 0            # For overlapped mode (0-50%)
```

### Output Specification

```r
# WindowGenerationResult 구조
window_result <- generate_isolation_windows(
  rt_binning_result = rt_binning_result,
  mz_range_result = mz_range_result,
  window_type = "variable",
  n_windows = 100
)

# 접근 예시
window_result$windows$window_id                  # 1, 2, 3, ...
window_result$windows$mz_start                   # Window start m/z
window_result$windows$mz_end                     # Window end m/z
window_result$statistics$total_windows            # 100
window_result$coverage_analysis$coverage_ratio    # 0.95
```

---

## Window Generation 모드

### 1. Fixed Window Mode

**개념**: 각 RT segment 내에서 등간격 고정폭 window 생성

**알고리즘**:
```r
generate_fixed_windows <- function(
  rt_binning_result,
  mz_range_result,
  n_windows,
  min_width_da = 2,
  max_width_da = 80
) {
  all_windows <- tibble()

  # For each RT segment
  for (i in 1:nrow(mz_range_result$mz_ranges)) {
    segment <- mz_range_result$mz_ranges[i, ]

    # Calculate m/z range for this segment
    mz_min <- segment$mz_min
    mz_max <- segment$mz_max
    mz_range_width <- mz_max - mz_min

    # Allocate windows proportionally to m/z range
    # (or based on precursor count)
    segment_windows <- round(n_windows * (mz_range_width / total_mz_range))
    segment_windows <- max(1, segment_windows)  # At least 1 window

    # Calculate fixed window width
    window_width <- mz_range_width / segment_windows

    # Apply constraints
    if (window_width < min_width_da) {
      window_width <- min_width_da
      segment_windows <- floor(mz_range_width / window_width)
    } else if (window_width > max_width_da) {
      window_width <- max_width_da
      segment_windows <- ceiling(mz_range_width / window_width)
    }

    # Generate windows with fixed width
    for (j in 1:segment_windows) {
      mz_start <- mz_min + (j - 1) * window_width
      mz_end <- min(mz_start + window_width, mz_max)
      mz_center <- (mz_start + mz_end) / 2

      # Count precursors
      segment_data <- rt_binning_result$rt_segments$precursor_data[[i]]
      n_prec <- sum(segment_data$Precursor.Mz >= mz_start &
                    segment_data$Precursor.Mz < mz_end)

      all_windows <- bind_rows(all_windows, tibble(
        window_id = nrow(all_windows) + 1,
        rt_segment_id = segment$rt_segment_id,
        rt_start = segment$rt_start,
        rt_end = segment$rt_end,
        mz_start = mz_start,
        mz_end = mz_end,
        mz_center = mz_center,
        window_width = mz_end - mz_start,
        n_precursors = n_prec,
        overlap_prev = 0,
        overlap_next = 0
      ))
    }
  }

  return(all_windows)
}
```

**장점**:
- ✅ 간단하고 예측 가능
- ✅ 구현 용이
- ✅ Instrument programming 직관적

**단점**:
- ❌ Precursor 분포 무시
- ❌ Window당 precursor 개수 불균등
- ❌ 비효율적 (sparse regions도 동일 폭)

**사용 시나리오**:
- 단순한 window scheme 선호
- Precursor 분포가 균일
- 빠른 method 생성 필요

---

### 2. Variable Window Mode (기존 활용)

**개념**: Density-based adaptive window width

**기존 구현**: `R/window_generator.R`의 `generate_windows_from_boundaries()`

**주요 특징**:
```r
# Largest Remainder Method for EXACT window count
# Step 1: Calculate exact quotas
exact_quotas <- (n_windows * bin_precursors) / total_precursors

# Step 2: Assign floor values
floor_allocations <- floor(exact_quotas)

# Step 3: Calculate remainders
remainders <- exact_quotas - floor_allocations

# Step 4: Distribute remaining windows to bins with largest remainders
remainder_order <- order(remainders, decreasing = TRUE)
top_remainder_bins <- remainder_order[1:windows_remaining]
floor_allocations[top_remainder_bins] <- floor_allocations[top_remainder_bins] + 1

# Step 5: Generate windows with equal precursor distribution per segment
quantile_probs <- seq(0, 1, length.out = bin_n_windows + 1)
mz_breaks <- quantile(bin_data$Precursor.Mz, probs = quantile_probs)
```

**장점**:
- ✅ Uniform precursor density
- ✅ EXACT window count 보장
- ✅ High density → narrow windows
- ✅ Low density → wide windows
- ✅ 검증된 알고리즘

**단점**:
- ❌ 계산 복잡도 높음
- ❌ Window 폭 예측 어려움

**사용 시나리오**:
- Optimal DPPP 달성 필요
- Precursor 분포가 불균등
- 고품질 데이터

---

### 3. Overlapped Window Mode

**개념**: Window 간 overlap으로 precursor sampling 증가

**알고리즘**:
```r
generate_overlapped_windows <- function(
  rt_binning_result,
  mz_range_result,
  n_windows,
  overlap_percentage = 10,  # 10% overlap
  min_width_da = 2,
  max_width_da = 80
) {
  # Step 1: Generate base windows (Fixed or Variable)
  base_windows <- generate_fixed_windows(
    rt_binning_result, mz_range_result, n_windows,
    min_width_da, max_width_da
  )

  # Step 2: Apply overlap
  overlap_fraction <- overlap_percentage / 100

  overlapped_windows <- tibble()

  for (i in 1:nrow(base_windows)) {
    window <- base_windows[i, ]

    # Calculate overlap amounts
    overlap_da <- window$window_width * overlap_fraction

    # Expand window boundaries
    mz_start_expanded <- window$mz_start - overlap_da / 2
    mz_end_expanded <- window$mz_end + overlap_da / 2

    # Constrain to segment boundaries
    segment_mz_range <- mz_range_result$mz_ranges %>%
      filter(rt_segment_id == window$rt_segment_id)

    mz_start_expanded <- max(mz_start_expanded, segment_mz_range$mz_min)
    mz_end_expanded <- min(mz_end_expanded, segment_mz_range$mz_max)

    # Calculate overlaps with neighbors
    overlap_prev <- 0
    overlap_next <- 0

    if (i > 1) {
      prev_window <- overlapped_windows[i - 1, ]
      if (prev_window$rt_segment_id == window$rt_segment_id) {
        overlap_prev <- max(0, prev_window$mz_end - mz_start_expanded)
      }
    }

    if (i < nrow(base_windows)) {
      next_window <- base_windows[i + 1, ]
      if (next_window$rt_segment_id == window$rt_segment_id) {
        # Estimate overlap with next (will be refined)
        overlap_next <- max(0, mz_end_expanded - next_window$mz_start + overlap_da / 2)
      }
    }

    # Recount precursors in expanded window
    segment_data <- rt_binning_result$rt_segments$precursor_data[[window$rt_segment_id]]
    n_prec <- sum(segment_data$Precursor.Mz >= mz_start_expanded &
                  segment_data$Precursor.Mz < mz_end_expanded)

    overlapped_windows <- bind_rows(overlapped_windows, tibble(
      window_id = window$window_id,
      rt_segment_id = window$rt_segment_id,
      rt_start = window$rt_start,
      rt_end = window$rt_end,
      mz_start = mz_start_expanded,
      mz_end = mz_end_expanded,
      mz_center = (mz_start_expanded + mz_end_expanded) / 2,
      window_width = mz_end_expanded - mz_start_expanded,
      n_precursors = n_prec,
      overlap_prev = overlap_prev,
      overlap_next = overlap_next
    ))
  }

  return(overlapped_windows)
}
```

**장점**:
- ✅ Precursor sampling 증가
- ✅ Missing peaks 위험 감소
- ✅ Overlap 비율 명시적 제어

**단점**:
- ❌ Cycle time 증가 (same n_windows, wider coverage)
- ❌ Overlapping region 중복 측정
- ❌ 복잡한 deconvolution 필요 (downstream)

**사용 시나리오**:
- Missing precursor 최소화
- Critical precursor 보호
- Cycle time 여유 있음

**Overlap Percentage 권장**:
- **10%**: 보수적, minimal overlap
- **25%**: 중간, good balance
- **50%**: 공격적, maximum coverage (but expensive)

---

## 구현 가이드

### 파일 구조

```r
# R/stage3_window_optimization/module3d_window_generation.R

# =====================================================
# Phase 3D: Window Generation
# =====================================================

#' Generate Isolation Windows (Main Function)
#'
#' @param rt_binning_result RTBinningResult from Phase 3B
#' @param mz_range_result MzRangeResult from Phase 3C
#' @param window_type Character, "fixed", "variable", "overlapped"
#' @param n_windows Integer, total window count
#' @param min_width_da Numeric, minimum window width (default: 2)
#' @param max_width_da Numeric, maximum window width (default: 80)
#' @param overlap_percentage Numeric, overlap % for overlapped mode (default: 0)
#'
#' @return WindowGenerationResult object
#' @export
generate_isolation_windows <- function(
  rt_binning_result,
  mz_range_result,
  window_type = "variable",
  n_windows = 100,
  min_width_da = 2,
  max_width_da = 80,
  overlap_percentage = 0
) {
  cat("=== Phase 3D: Window Generation ===\n\n")

  # Validate inputs
  if (!window_type %in% c("fixed", "variable", "overlapped")) {
    stop(sprintf("Invalid window_type: %s. Must be 'fixed', 'variable', or 'overlapped'.",
                 window_type))
  }

  cat(sprintf("Window type: %s\n", window_type))
  cat(sprintf("Target windows: %d\n", n_windows))
  cat(sprintf("Width constraints: %.1f - %.1f Da\n", min_width_da, max_width_da))
  if (overlap_percentage > 0) {
    cat(sprintf("Overlap: %.1f%%\n", overlap_percentage))
  }

  # Step 1: Generate base windows based on type
  cat("\nStep 1: Generating windows...\n")

  if (window_type == "fixed") {
    windows <- generate_fixed_windows(
      rt_binning_result, mz_range_result, n_windows,
      min_width_da, max_width_da
    )
    generation_method <- "fixed_width"
    allocation_method <- "proportional"

  } else if (window_type == "variable") {
    # Use existing implementation from R/window_generator.R
    source("R/window_generator.R")

    # Convert Phase 3C output to Module 3 format (boundary_result)
    boundary_result <- convert_mz_range_to_boundary_format(mz_range_result)

    variable_result <- generate_windows_from_boundaries(
      rt_binning_result = rt_binning_result,
      boundary_result = boundary_result,
      n_windows = n_windows,
      min_width_da = min_width_da,
      max_width_da = max_width_da
    )

    # Convert to standard format
    windows <- variable_result$windows %>%
      rename(
        rt_segment_id = rt_bin,
        mz_start = window_start,
        mz_end = window_end,
        mz_center = center_mz
      ) %>%
      mutate(
        window_id = row_number(),
        rt_start = NA,  # Will be filled from rt_binning_result
        rt_end = NA,
        overlap_prev = 0,
        overlap_next = 0
      )

    generation_method <- "density_based"
    allocation_method <- "largest_remainder"

  } else if (window_type == "overlapped") {
    windows <- generate_overlapped_windows(
      rt_binning_result, mz_range_result, n_windows,
      overlap_percentage, min_width_da, max_width_da
    )
    generation_method <- "overlapped"
    allocation_method <- "proportional_with_overlap"
  }

  cat(sprintf("  Generated %d windows\n", nrow(windows)))

  # Step 2: Calculate statistics
  cat("\nStep 2: Calculating statistics...\n")
  statistics <- calculate_window_statistics(windows)

  # Step 3: Analyze coverage
  cat("\nStep 3: Analyzing coverage...\n")
  coverage <- analyze_precursor_coverage(
    windows, rt_binning_result, mz_range_result
  )

  # Step 4: Package results
  cat("\nStep 4: Packaging results...\n")

  result <- structure(
    list(
      windows = windows,

      statistics = statistics,

      coverage_analysis = coverage,

      parameters = list(
        window_type = window_type,
        n_windows = n_windows,
        min_width_da = min_width_da,
        max_width_da = max_width_da,
        overlap_percentage = overlap_percentage
      ),

      metadata = list(
        generation_method = generation_method,
        allocation_method = allocation_method,
        generation_timestamp = Sys.time()
      )
    ),
    class = c("WindowGenerationResult", "list")
  )

  cat("\n=== Phase 3D Complete ===\n")
  cat(sprintf("✅ Generated %d windows (target: %d, deviation: %.1f%%)\n",
              nrow(windows), n_windows,
              100 * abs(nrow(windows) - n_windows) / n_windows))
  cat(sprintf("   Coverage: %.1f%% (%d/%d precursors)\n",
              coverage$coverage_ratio * 100,
              coverage$covered_precursors,
              coverage$total_precursors))

  return(result)
}

#' Generate Fixed Windows
#'
#' @param rt_binning_result RTBinningResult from Phase 3B
#' @param mz_range_result MzRangeResult from Phase 3C
#' @param n_windows Integer, total window count
#' @param min_width_da Numeric, minimum window width
#' @param max_width_da Numeric, maximum window width
#'
#' @return Tibble of windows
#' @export
generate_fixed_windows <- function(
  rt_binning_result,
  mz_range_result,
  n_windows,
  min_width_da = 2,
  max_width_da = 80
) {
  # TODO: Implement fixed window generation
  # 1. Calculate total m/z range
  # 2. Allocate windows proportionally to each RT segment
  # 3. Generate equal-width windows within each segment
  # 4. Apply width constraints
  # 5. Count precursors per window

  stop("Not implemented yet")
}

#' Generate Overlapped Windows
#'
#' @param rt_binning_result RTBinningResult from Phase 3B
#' @param mz_range_result MzRangeResult from Phase 3C
#' @param n_windows Integer, total window count
#' @param overlap_percentage Numeric, overlap percentage (0-50)
#' @param min_width_da Numeric, minimum window width
#' @param max_width_da Numeric, maximum window width
#'
#' @return Tibble of overlapped windows
#' @export
generate_overlapped_windows <- function(
  rt_binning_result,
  mz_range_result,
  n_windows,
  overlap_percentage = 10,
  min_width_da = 2,
  max_width_da = 80
) {
  # TODO: Implement overlapped window generation
  # 1. Generate base windows (fixed or variable)
  # 2. Calculate overlap amount per window
  # 3. Expand window boundaries
  # 4. Constrain to segment m/z ranges
  # 5. Calculate overlap with neighbors
  # 6. Recount precursors in expanded windows

  stop("Not implemented yet")
}

# =====================================================
# Helper Functions
# =====================================================

#' Calculate Window Statistics
#'
#' @param windows Tibble of generated windows
#'
#' @return List with statistics
calculate_window_statistics <- function(windows) {
  list(
    total_windows = nrow(windows),
    mean_precursors_per_window = mean(windows$n_precursors),
    sd_precursors_per_window = sd(windows$n_precursors),
    cv_precursors = sd(windows$n_precursors) / mean(windows$n_precursors),
    min_window_width = min(windows$window_width),
    max_window_width = max(windows$window_width),
    mean_window_width = mean(windows$window_width),
    total_overlap_da = sum(windows$overlap_prev + windows$overlap_next) / 2
  )
}

#' Analyze Precursor Coverage
#'
#' @param windows Tibble of windows
#' @param rt_binning_result RTBinningResult
#' @param mz_range_result MzRangeResult
#'
#' @return List with coverage analysis
analyze_precursor_coverage <- function(
  windows,
  rt_binning_result,
  mz_range_result
) {
  # TODO: Implement coverage analysis
  # 1. Count total precursors
  # 2. Count covered precursors (within any window)
  # 3. Calculate coverage ratio
  # 4. Identify uncovered regions (gaps)

  stop("Not implemented yet")
}

#' Convert MzRangeResult to boundary_result format
#'
#' Helper function to convert Phase 3C output to format expected by
#' existing R/window_generator.R functions
#'
#' @param mz_range_result MzRangeResult from Phase 3C
#'
#' @return boundary_result in Module 3 format
convert_mz_range_to_boundary_format <- function(mz_range_result) {
  # TODO: Implement format conversion
  stop("Not implemented yet")
}
```

---

## 테스트 전략

### Mock Data 생성

**파일**: `tests/mocks/mock_stage3d_output.R`

```r
#' Create Mock Stage 3D Output
#'
#' @param n_windows Number of windows (default: 100)
#' @param window_type Window type (default: "variable")
#'
#' @return WindowGenerationResult object
#' @export
create_mock_stage3d_output <- function(
  n_windows = 100,
  window_type = "variable"
) {
  # Load Phase 3B and 3C mocks
  source("tests/mocks/mock_stage3b_output.R")
  source("tests/mocks/mock_stage3c_output.R")

  rt_binning_result <- create_mock_stage3b_output()
  mz_range_result <- create_mock_stage3c_output()

  # Create mock windows
  windows <- tibble(
    window_id = 1:n_windows,
    rt_segment_id = rep(1:10, each = n_windows/10),
    rt_start = rep(seq(10, 100, length.out = 10), each = n_windows/10),
    rt_end = rep(seq(20, 110, length.out = 10), each = n_windows/10),
    mz_start = seq(400, 1200, length.out = n_windows),
    mz_end = seq(410, 1210, length.out = n_windows),
    mz_center = seq(405, 1205, length.out = n_windows),
    window_width = 10,
    n_precursors = rpois(n_windows, lambda = 100),
    overlap_prev = 0,
    overlap_next = 0
  )

  # Apply overlap if needed
  if (window_type == "overlapped") {
    windows <- windows %>%
      mutate(
        overlap_prev = c(0, rep(1, n_windows - 1)),
        overlap_next = c(rep(1, n_windows - 1), 0)
      )
  }

  # Create result
  result <- structure(
    list(
      windows = windows,

      statistics = list(
        total_windows = n_windows,
        target_windows = n_windows,
        mean_precursors_per_window = mean(windows$n_precursors),
        sd_precursors_per_window = sd(windows$n_precursors),
        cv_precursors = sd(windows$n_precursors) / mean(windows$n_precursors),
        min_window_width = min(windows$window_width),
        max_window_width = max(windows$window_width),
        mean_window_width = mean(windows$window_width),
        total_overlap_da = sum(windows$overlap_prev + windows$overlap_next) / 2
      ),

      coverage_analysis = list(
        total_precursors = 10000,
        covered_precursors = 9500,
        coverage_ratio = 0.95,
        uncovered_regions = tibble()
      ),

      parameters = list(
        window_type = window_type,
        n_windows = n_windows,
        min_width_da = 2,
        max_width_da = 80,
        overlap_percentage = ifelse(window_type == "overlapped", 10, 0)
      ),

      metadata = list(
        generation_method = window_type,
        allocation_method = "mock",
        generation_timestamp = Sys.time()
      )
    ),
    class = c("WindowGenerationResult", "list")
  )

  return(result)
}
```

---

### Unit Tests

**파일**: `tests/test_stage3d.R`

```r
library(testthat)
source("tests/mocks/mock_stage3b_output.R")
source("tests/mocks/mock_stage3c_output.R")
source("R/stage3_window_optimization/module3d_window_generation.R")

# =====================================================
# Test: Fixed Window Generation
# =====================================================

test_that("generate_fixed_windows creates equal-width windows", {
  # Setup
  rt_binning_result <- create_mock_stage3b_output()
  mz_range_result <- create_mock_stage3c_output()

  # Execute
  windows <- generate_fixed_windows(
    rt_binning_result, mz_range_result,
    n_windows = 100,
    min_width_da = 2,
    max_width_da = 80
  )

  # Verify structure
  expect_true(is.data.frame(windows))
  expect_true(all(c("window_id", "mz_start", "mz_end", "window_width") %in%
                  colnames(windows)))

  # Verify window count approximately matches target
  expect_true(abs(nrow(windows) - 100) < 10)

  # Verify windows are non-overlapping (overlap = 0)
  expect_equal(sum(windows$overlap_prev), 0)
  expect_equal(sum(windows$overlap_next), 0)

  # Verify windows within each RT segment have similar width
  for (seg_id in unique(windows$rt_segment_id)) {
    seg_windows <- windows %>% filter(rt_segment_id == seg_id)
    width_cv <- sd(seg_windows$window_width) / mean(seg_windows$window_width)
    expect_true(width_cv < 0.1)  # Low variation within segment
  }
})

# =====================================================
# Test: Variable Window Generation (Existing)
# =====================================================

test_that("variable window generation uses existing implementation", {
  # Setup
  rt_binning_result <- create_mock_stage3b_output()
  mz_range_result <- create_mock_stage3c_output()

  # Execute
  result <- generate_isolation_windows(
    rt_binning_result = rt_binning_result,
    mz_range_result = mz_range_result,
    window_type = "variable",
    n_windows = 100
  )

  # Verify class
  expect_s3_class(result, "WindowGenerationResult")

  # Verify variable window characteristics
  expect_true(result$statistics$cv_precursors < 0.3)  # Uniform precursor distribution
  expect_true(result$metadata$allocation_method == "largest_remainder")

  # Verify window count matches target (exactly or very close)
  expect_true(abs(result$statistics$total_windows - 100) <= 5)
})

# =====================================================
# Test: Overlapped Window Generation
# =====================================================

test_that("generate_overlapped_windows creates overlapping windows", {
  # Setup
  rt_binning_result <- create_mock_stage3b_output()
  mz_range_result <- create_mock_stage3c_output()

  # Execute
  windows <- generate_overlapped_windows(
    rt_binning_result, mz_range_result,
    n_windows = 100,
    overlap_percentage = 10
  )

  # Verify overlap exists
  expect_true(sum(windows$overlap_prev) > 0)
  expect_true(sum(windows$overlap_next) > 0)

  # Verify overlap is approximately 10% of window width
  mean_overlap <- mean(windows$overlap_prev + windows$overlap_next) / 2
  mean_width <- mean(windows$window_width)
  overlap_ratio <- mean_overlap / mean_width

  expect_true(abs(overlap_ratio - 0.10) < 0.05)  # Within 5% of target

  # Verify windows still cover expected range
  expect_true(min(windows$mz_start) <= min(mz_range_result$mz_ranges$mz_min) + 5)
  expect_true(max(windows$mz_end) >= max(mz_range_result$mz_ranges$mz_max) - 5)
})

# =====================================================
# Test: Integrated Window Generation
# =====================================================

test_that("generate_isolation_windows integrates all modes", {
  # Setup
  rt_binning_result <- create_mock_stage3b_output()
  mz_range_result <- create_mock_stage3c_output()

  # Test each mode
  for (mode in c("fixed", "variable", "overlapped")) {
    # Execute
    result <- generate_isolation_windows(
      rt_binning_result = rt_binning_result,
      mz_range_result = mz_range_result,
      window_type = mode,
      n_windows = 100,
      overlap_percentage = ifelse(mode == "overlapped", 10, 0)
    )

    # Verify class
    expect_s3_class(result, "WindowGenerationResult")

    # Verify structure
    expect_true(all(c("windows", "statistics", "coverage_analysis",
                      "parameters", "metadata") %in% names(result)))

    # Verify windows tibble
    expect_equal(nrow(result$windows), result$statistics$total_windows)

    # Verify coverage
    expect_true(result$coverage_analysis$coverage_ratio >= 0.90)

    # Verify parameters match
    expect_equal(result$parameters$window_type, mode)
  }
})

# =====================================================
# Test: Coverage Analysis
# =====================================================

test_that("coverage analysis identifies uncovered regions", {
  # Setup
  rt_binning_result <- create_mock_stage3b_output()
  mz_range_result <- create_mock_stage3c_output()

  # Generate windows with intentional gaps
  windows <- generate_fixed_windows(
    rt_binning_result, mz_range_result,
    n_windows = 50,  # Fewer windows = more gaps
    min_width_da = 2,
    max_width_da = 20  # Narrower max width = more gaps
  )

  # Analyze coverage
  coverage <- analyze_precursor_coverage(
    windows, rt_binning_result, mz_range_result
  )

  # Verify coverage < 100% (should have gaps)
  expect_true(coverage$coverage_ratio < 1.0)

  # Verify uncovered regions identified
  if (coverage$coverage_ratio < 0.99) {
    expect_true(nrow(coverage$uncovered_regions) > 0)
  }
})

# =====================================================
# Test: Window Statistics
# =====================================================

test_that("window statistics are calculated correctly", {
  # Setup
  windows <- tibble(
    window_id = 1:10,
    mz_start = seq(400, 1000, length.out = 10),
    mz_end = seq(450, 1050, length.out = 10),
    window_width = 50,
    n_precursors = c(100, 110, 90, 105, 95, 100, 105, 95, 100, 110),
    overlap_prev = 0,
    overlap_next = 0
  )

  # Execute
  stats <- calculate_window_statistics(windows)

  # Verify statistics
  expect_equal(stats$total_windows, 10)
  expect_equal(stats$mean_window_width, 50)
  expect_equal(stats$mean_precursors_per_window, 101)
  expect_true(stats$cv_precursors < 0.1)  # Low variation
  expect_equal(stats$total_overlap_da, 0)  # No overlap
})
```

---

## Definition of Done

Phase 3D 개발 완료 기준:

### 기능 완성도
- [ ] `generate_fixed_windows()` 구현 완료
- [ ] `generate_overlapped_windows()` 구현 완료
- [ ] `generate_isolation_windows()` 통합 함수 완료
- [ ] `calculate_window_statistics()` 구현 완료
- [ ] `analyze_precursor_coverage()` 구현 완료
- [ ] `convert_mz_range_to_boundary_format()` 구현 완료

### 기존 코드 통합
- [ ] `R/window_generator.R` 활용 확인
- [ ] Variable mode 정상 동작 확인
- [ ] Largest Remainder Method 보존

### 테스트 커버리지
- [ ] Fixed mode unit test 통과
- [ ] Variable mode integration test 통과
- [ ] Overlapped mode unit test 통과
- [ ] Coverage analysis test 통과
- [ ] 3가지 모드 비교 테스트

### 코드 품질
- [ ] 모든 함수 roxygen2 문서화
- [ ] 에러 처리 및 경고 메시지
- [ ] 진행 상황 출력
- [ ] 코드 리뷰 완료

### 통합 준비
- [ ] Phase 3C 출력과 호환성 확인
- [ ] Phase 4 입력 형식 생성
- [ ] Mock data 생성 함수 작성
- [ ] Fixture 데이터 저장

### 문서화
- [ ] 각 모드별 사용 예시
- [ ] API 문서 업데이트
- [ ] Phase 3D 개발 가이드 완료
- [ ] DEVELOPMENT.md 업데이트

### 검증
- [ ] Fixed mode: window 폭 균일성 확인
- [ ] Variable mode: precursor 균등성 확인 (CV < 0.3)
- [ ] Overlapped mode: overlap % 정확도 확인
- [ ] Coverage ≥ 95% 달성 (all modes)
- [ ] Window count deviation < 5%

---

## 참고 자료

### 관련 문서
- [API Specification](../API_SPECIFICATION.md)
- [Phase 3C: m/z Range Optimization](PHASE3C_MZ_RANGE.md)
- [Phase 4: Visualization](PHASE4_VISUALIZATION.md)

### 관련 코드
- `R/window_generator.R` - 기존 Variable window 구현 (활용)
- `R/stage3_window_optimization/module3d_window_generation.R` - 통합 구현 (신규)

### Window Mode 비교

| Mode | Width | Precursor Distribution | Overlap | Complexity | Use Case |
|------|-------|------------------------|---------|------------|----------|
| Fixed | 균일 | 불균등 | None | 낮음 | Simple method |
| Variable | 가변 | 균등 | None | 높음 | Optimal DPPP |
| Overlapped | 가변 | 균등 | Yes | 중간 | Max coverage |

### Overlap Percentage 가이드

- **0%**: No overlap (Fixed/Variable 기본)
- **10%**: Minimal overlap, conservative
- **25%**: Moderate overlap, balanced
- **50%**: Maximum overlap, expensive cycle time

---

## 개발 시작하기

```bash
# 1. Phase 3C 완료 확인
R
source("tests/mocks/mock_stage3c_output.R")
mz_range_result <- create_mock_stage3c_output()
str(mz_range_result)

# 2. 기존 window_generator.R 확인
source("R/window_generator.R")
# Check generate_windows_from_boundaries()

# 3. Phase 3D 디렉토리 확인
mkdir -p R/stage3_window_optimization

# 4. Phase 3D 스켈레톤 생성
# R/stage3_window_optimization/module3d_window_generation.R

# 5. 첫 함수 구현 (generate_fixed_windows)
# 가장 간단한 Fixed mode부터 시작

# 6. Unit test 작성 및 실행
source("tests/test_stage3d.R")
test_file("tests/test_stage3d.R")
```

**개발 순서 권장**:
1. `generate_fixed_windows()` - 가장 간단
2. `convert_mz_range_to_boundary_format()` - Helper
3. Variable mode 통합 (기존 코드 활용)
4. `calculate_window_statistics()` - 통계 계산
5. `analyze_precursor_coverage()` - Coverage 분석
6. `generate_overlapped_windows()` - Overlap 추가
7. `generate_isolation_windows()` - 통합 함수

---

**Note**: Phase 3D는 기존 `R/window_generator.R`의 Variable 모드를 활용하되, Fixed와 Overlapped 모드를 추가하여 사용자 선택의 폭을 넓힙니다.

---

**End of Phase 3D Development Guide**
