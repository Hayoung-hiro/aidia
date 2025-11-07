# DIA Window Optimizer 개선 계획

**작성일**: 2025-11-03
**상태**: 계획 수립 완료 (패키징 작업 선행 후 구현)
**우선순위**: Pre-packaging improvements

---

## 📊 현재 상태 분석

### 발견된 주요 이슈

**Issue 1: m/z Optimization Parameters - Smoothing Failure**
- **현재 설정**:
  - Config: `smoothing_window: 3`, `polynomial_order: 2`
  - 함수 기본값: `smoothing_window: 7`, `polynomial_order: 3`
- **문제점**:
  - **30min gradient**: RT range 11.9-21.8 min (실제 10분), 5min RT bin → **2개 bin만 생성**
  - **Smoothing window=3**: 2개 bin에서 작동 불가 (최소 3개 데이터 포인트 필요)
  - **근본 원인**: 짧은 gradient + 고정 RT bin width = RT bin 부족
- **영향**:
  - Smoothing strategy 완전 실패
  - 사용자가 이유를 모름 (에러 메시지 불명확)
  - Gradient 길이별로 수동 조정 필요

**Issue 2: Sample/Run Management - Replicate Information Loss**
- **현재 상태**:
  - 30min_report.parquet: **3개 Run** (technical replicates, 총 23,379 rows)
  - 60min_report.parquet: 여러 Run 포함 (확인 필요)
  - 90min_report.parquet: 여러 Run 포함 (확인 필요)
- **문제점**:
  - **현재 처리**: 모든 Run을 하나로 통합 (중복 카운트)
  - **데이터 왜곡**: 동일 precursor가 3번 카운트 → m/z 분포, FWHM 왜곡
  - **정보 손실**: Run간 CV%, 재현성 정보 활용 불가
- **영향**:
  - DPPP 계산 정확도 저하
  - Window 최적화 품질 저하
  - QC 메트릭 부재

---

## 🎯 개선 계획 1: Adaptive m/z Optimization Parameters

### 배경 지식

**Savitzky-Golay 필터 제약사항**:
```
1. Window size ≤ 데이터 포인트 개수 (RT bins)
2. Window size는 홀수여야 함 (중심점 필요)
3. Polynomial order < window size
4. 효과적인 smoothing을 위한 권장: window_size ≥ 5
```

**현재 30min 데이터 상세 분석**:
```
실제 RT range: 11.9 - 21.8 min
→ 유효 RT 구간: 약 10분
→ RT bin (5 min) 개수: ceiling(10 / 5) = 2 bins

Smoothing 요구사항:
- window_size = 3 (최소) → 3개 bins 필요
- window_size = 7 (권장) → 7개 bins 필요

현재: 2 bins < 3 bins (minimum) → Smoothing 불가능!
```

### 해결 방안: 3-Tier Adaptive System

#### Tier 1: Auto-Detect and Fallback (Immediate Fix)

**목표**: Smoothing 불가능할 때 자동으로 quantile strategy로 전환

```r
# R/stage3_window_optimization.R 수정
optimize_mz_ranges_with_fallback <- function(..., strategy, n_rt_bins) {

  if (strategy == "smoothing") {
    # Check feasibility
    if (n_rt_bins < 3) {
      cat("⚠️  WARNING: Smoothing strategy requires ≥3 RT bins\n")
      cat(sprintf("   Current: %d bins (RT range / bin width)\n", n_rt_bins))
      cat("   → Automatically switching to 'quantile' strategy\n")
      cat("   → Consider: reduce rt_bin_width_min or use longer gradient\n\n")

      strategy <- "quantile"  # Fallback
    }
  }

  # Continue with selected/fallback strategy
  return(optimize_mz_ranges_internal(..., strategy = strategy))
}
```

**장점**: 즉시 적용 가능, 기존 코드 최소 수정
**단점**: Smoothing을 원하는 사용자는 여전히 수동 조정 필요

#### Tier 2: Adaptive Parameter Selection (Recommended)

**목표**: RT bin 개수에 따라 smoothing parameters 자동 조정

```r
#' Calculate optimal smoothing parameters based on data characteristics
#'
#' @param n_rt_bins Number of RT bins
#' @param gradient_length_min Total gradient length in minutes
#' @return List with smoothing_window, polynomial_order, and feasibility flag
adaptive_smoothing_params <- function(n_rt_bins, gradient_length_min) {

  # Rule 1: Window size = 50-70% of bins (ensure odd number)
  max_window_size <- floor(n_rt_bins * 0.7)
  window_size <- max(3, min(max_window_size, 11))  # Range: 3-11

  # Ensure odd
  if (window_size %% 2 == 0) window_size <- window_size + 1

  # Rule 2: Polynomial order = min(window_size - 2, 3)
  poly_order <- min(window_size - 2, 3)

  # Rule 3: Feasibility check
  feasible <- (n_rt_bins >= 3) && (window_size <= n_rt_bins)

  # Recommendations
  if (!feasible) {
    recommended_bin_width <- gradient_length_min / 5  # Target 5 bins minimum
    cat("⚠️  Smoothing not feasible with current settings\n")
    cat(sprintf("   Current: %d RT bins (need ≥3)\n", n_rt_bins))
    cat(sprintf("   Recommendation: Reduce rt_bin_width to ≤ %.1f min\n",
                recommended_bin_width))
  }

  return(list(
    smoothing_window = window_size,
    polynomial_order = poly_order,
    feasible = feasible,
    message = if (feasible) {
      sprintf("Adaptive: window=%d, poly=%d for %d bins",
              window_size, poly_order, n_rt_bins)
    } else {
      "Smoothing not feasible (insufficient RT bins)"
    }
  ))
}
```

**적용 예시**:
| Gradient | RT Range | RT Bin (5min) | Bins | Adaptive Window | Poly Order | Feasible? |
|----------|----------|---------------|------|-----------------|------------|-----------|
| 30min    | 10 min   | 5 min         | 2    | 3               | 1          | ❌ No     |
| 60min    | 35 min   | 5 min         | 7    | 5               | 3          | ✅ Yes    |
| 90min    | 64 min   | 5 min         | 13   | 9               | 3          | ✅ Yes    |

**적용 with RT bin adjustment**:
| Gradient | RT Range | RT Bin (2min) | Bins | Adaptive Window | Poly Order | Feasible? |
|----------|----------|---------------|------|-----------------|------------|-----------|
| 30min    | 10 min   | 2 min         | 5    | 3               | 1          | ✅ Yes    |
| 60min    | 35 min   | 2 min         | 18   | 11              | 3          | ✅ Yes    |
| 90min    | 64 min   | 2 min         | 32   | 11              | 3          | ✅ Yes    |

#### Tier 3: Intelligent RT Bin Adjustment (Advanced)

**목표**: Gradient 길이에 따라 RT bin width 자동 조정

```r
#' Optimize RT bin width based on gradient characteristics
#'
#' @param rt_range Total RT range in minutes
#' @param target_min_bins Minimum target number of bins (default: 5)
#' @param user_bin_width User-specified bin width or NULL for auto
#' @return Optimized RT bin width in minutes
optimize_rt_bin_width <- function(rt_range,
                                   target_min_bins = 5,
                                   user_bin_width = NULL) {

  # If user specified, validate
  if (!is.null(user_bin_width) && user_bin_width != "auto") {
    n_bins <- ceiling(rt_range / user_bin_width)

    if (n_bins < 3) {
      cat("⚠️  User-specified RT bin width results in too few bins\n")
      cat(sprintf("   rt_bin_width: %.1f min → %d bins (need ≥3)\n",
                  user_bin_width, n_bins))
      cat("   → Adjusting to ensure minimum 5 bins\n\n")

      # Auto-adjust
      user_bin_width <- NULL
    } else {
      return(user_bin_width)  # User choice is valid
    }
  }

  # Auto mode: calculate optimal bin width
  if (is.null(user_bin_width) || user_bin_width == "auto") {

    # Gradient-specific recommendations
    if (rt_range <= 15) {
      # Short gradient (≤15 min): 2-3 min bins
      bin_width <- max(2.0, rt_range / target_min_bins)
    } else if (rt_range <= 40) {
      # Medium gradient (15-40 min): 3-4 min bins
      bin_width <- max(3.0, rt_range / (target_min_bins * 1.2))
    } else {
      # Long gradient (>40 min): 5 min bins (standard)
      bin_width <- 5.0
    }

    n_bins <- ceiling(rt_range / bin_width)

    cat("📊 Auto-optimized RT binning:\n")
    cat(sprintf("   RT range: %.1f min\n", rt_range))
    cat(sprintf("   RT bin width: %.1f min\n", bin_width))
    cat(sprintf("   Number of bins: %d\n\n", n_bins))

    return(bin_width)
  }
}
```

### 통합 솔루션: Unified Optimization Function

```r
#' Optimize all Stage 3 parameters based on data characteristics
#'
#' @param validated_data ValidatedData object from Stage 1
#' @param rt_bin_width_min User RT bin width or "auto"
#' @param smoothing_window User smoothing window or "auto"
#' @param polynomial_order User polynomial order or "auto"
#' @return List of optimized parameters
optimize_stage3_parameters <- function(validated_data,
                                       rt_bin_width_min = "auto",
                                       smoothing_window = "auto",
                                       polynomial_order = "auto") {

  # Extract RT characteristics
  rt_range <- diff(range(validated_data$data$RT.Start, na.rm = TRUE))

  # Step 1: Optimize RT bin width
  rt_bin_optimized <- optimize_rt_bin_width(rt_range,
                                             user_bin_width = rt_bin_width_min)
  n_bins <- ceiling(rt_range / rt_bin_optimized)

  # Step 2: Optimize smoothing parameters
  smoothing_params <- adaptive_smoothing_params(n_bins, rt_range)

  # Override with user values if specified
  if (!is.null(smoothing_window) && smoothing_window != "auto") {
    smoothing_params$smoothing_window <- smoothing_window
  }

  if (!is.null(polynomial_order) && polynomial_order != "auto") {
    smoothing_params$polynomial_order <- polynomial_order
  }

  # Step 3: Validate final parameters
  if (!smoothing_params$feasible) {
    cat("⚠️  FINAL WARNING: Smoothing strategy will use fallback\n")
    cat("   To enable smoothing, use one of:\n")
    cat(sprintf("   1. Reduce rt_bin_width to ≤ %.1f min\n", rt_range / 3))
    cat("   2. Use 'quantile' or 'outlier' strategy instead\n\n")
  }

  # Return optimized parameters
  return(list(
    rt_bin_width_min = rt_bin_optimized,
    n_rt_bins = n_bins,
    smoothing_window = smoothing_params$smoothing_window,
    polynomial_order = smoothing_params$polynomial_order,
    smoothing_feasible = smoothing_params$feasible,
    optimization_message = smoothing_params$message
  ))
}
```

### Config 파일 업데이트

#### config/optimization_config.json
```json
{
  "rt_binning": {
    "rt_bin_width_min": "auto",
    "_comment_rt_bin_width_min": "Options: 'auto' (adaptive based on gradient), or numeric (e.g., 5.0)",
    "_note": "auto mode: 2-3 min for short gradients (<15 min), 3-4 min for medium (15-40 min), 5 min for long (>40 min)"
  },

  "mz_optimization": {
    "strategies": ["quantile", "smoothing", "outlier", "coverage"],

    "smoothing_window": "auto",
    "_comment_smoothing_window": "Options: 'auto' (adaptive based on RT bins), or odd integer ≥3",
    "_note_smoothing_window": "auto mode: 50-70% of RT bins, range 3-11",

    "polynomial_order": "auto",
    "_comment_polynomial_order": "Options: 'auto' (min(window-2, 3)), or integer 1-5",

    "quantile_lower": 0.05,
    "quantile_upper": 0.95,
    "target_coverage": 0.95,
    "outlier_threshold": 3.0
  }
}
```

### 구현 단계

**Phase 1A: Immediate Fallback** (30분)
- [ ] `optimize_mz_ranges_with_fallback()` 추가
- [ ] Smoothing 불가능 시 quantile로 자동 전환
- [ ] Warning 메시지 개선
- [ ] 최소 단위 테스트

**Phase 1B: Adaptive Parameters** (1시간)
- [ ] `adaptive_smoothing_params()` 구현
- [ ] `optimize_rt_bin_width()` 구현
- [ ] `optimize_stage3_parameters()` 통합 함수
- [ ] Config에 "auto" 지원 추가

**Phase 1C: Testing & Documentation** (30분)
- [ ] 3개 gradient로 통합 테스트
- [ ] Edge case 테스트 (매우 짧은/긴 gradient)
- [ ] README에 adaptive parameter 설명 추가

---

## 🎯 개선 계획 2: Technical Replication 관리

### 현재 문제점 상세

**데이터 구조 확인**:
```
30min_report.parquet:
├── Run 1: 7,793 precursors (unique peptide-charge combinations)
├── Run 2: 7,793 precursors (technical replicate)
└── Run 3: 7,793 precursors (technical replicate)
Total: 23,379 rows (same precursors measured 3 times)
```

**현재 처리 방식의 문제**:
1. **중복 카운트**: 동일 precursor가 3번 카운트됨
   - m/z 분포 왜곡 (같은 m/z가 3배 빈도)
   - FWHM 분포 왜곡 (같은 FWHM이 3배 빈도)
   - DPPP 계산 부정확 (밀도 기반 메트릭 왜곡)

2. **재현성 정보 손실**:
   - Run간 RT 변동 (instrument drift, column aging)
   - Run간 FWHM 변동 (signal quality, matrix effects)
   - CV% 계산 불가 (QC 메트릭 부재)

3. **통계적 문제**:
   - Pseudo-replication: 독립적이지 않은 샘플을 독립으로 처리
   - N 부풀리기: 실제 N=1 (biological replicate)이지만 N=3처럼 처리

### 해결 방안: 3가지 접근법 비교

#### Option A: Representative Run Selection (가장 간단)

**개념**: 품질이 가장 좋은 하나의 Run만 선택

```r
#' Select best quality run from technical replicates
#'
#' @param data Raw DIA-NN data with multiple runs
#' @return Data from best quality run
select_representative_run <- function(data) {

  # Calculate quality metrics per run
  run_quality <- data %>%
    group_by(Run) %>%
    summarise(
      n_precursors = n(),
      median_fwhm = median(FWHM, na.rm = TRUE),
      mean_intensity = mean(Precursor.Quantity, na.rm = TRUE),
      median_score = median(Q.Value, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      # Quality score: more IDs + higher intensity + narrower peaks + better scores
      quality_score = (n_precursors / max(n_precursors)) * 0.3 +
                      (mean_intensity / max(mean_intensity)) * 0.3 +
                      (min(median_fwhm) / median_fwhm) * 0.2 +  # Lower FWHM is better
                      (min(median_score) / median_score) * 0.2   # Lower Q-value is better
    ) %>%
    arrange(desc(quality_score))

  best_run <- run_quality$Run[1]

  cat("📊 Representative Run Selection:\n")
  print(run_quality, n = nrow(run_quality))
  cat(sprintf("\n✅ Selected: %s (quality score: %.3f)\n\n",
              best_run, run_quality$quality_score[1]))

  return(data %>% filter(Run == best_run))
}
```

**장점**:
- ✅ 매우 간단, 기존 파이프라인 수정 최소
- ✅ 중복 문제 완전 해결
- ✅ 실제 Run 데이터 사용 (평균이 아닌)

**단점**:
- ❌ 나머지 Run 정보 완전 버림 (데이터 낭비)
- ❌ CV%, 재현성 정보 없음
- ❌ Run 선택 기준이 주관적

**사용 케이스**: 빠른 프로토타이핑, 초기 분석

#### Option B: Replicate Averaging (보수적)

**개념**: Precursor별로 Run 평균 계산

```r
#' Average technical replicates at precursor level
#'
#' @param data Raw DIA-NN data with multiple runs
#' @return Aggregated data with mean values and CV metrics
aggregate_replicates <- function(data) {

  n_runs <- length(unique(data$Run))

  # Precursor-level aggregation
  data_agg <- data %>%
    group_by(Precursor.Id) %>%
    summarise(
      # Mean values
      RT.Start = mean(RT.Start, na.rm = TRUE),
      RT.Stop = mean(RT.Stop, na.rm = TRUE),
      Precursor.Mz = mean(Precursor.Mz, na.rm = TRUE),
      FWHM = mean(FWHM, na.rm = TRUE),

      # Variability metrics (NEW!)
      RT_SD = sd(RT.Start, na.rm = TRUE),
      RT_CV = sd(RT.Start, na.rm = TRUE) / mean(RT.Start, na.rm = TRUE) * 100,
      FWHM_SD = sd(FWHM, na.rm = TRUE),
      FWHM_CV = sd(FWHM, na.rm = TRUE) / mean(FWHM, na.rm = TRUE) * 100,

      # Replication info
      n_replicates = n(),

      .groups = "drop"
    )

  cat("📊 Replicate Aggregation Summary:\n")
  cat(sprintf("   Runs: %d\n", n_runs))
  cat(sprintf("   Unique precursors: %d\n", nrow(data_agg)))
  cat(sprintf("   Mean RT CV: %.2f%%\n", mean(data_agg$RT_CV, na.rm = TRUE)))
  cat(sprintf("   Mean FWHM CV: %.2f%%\n", mean(data_agg$FWHM_CV, na.rm = TRUE)))
  cat(sprintf("   Replication rate: %.1f%%\n",
              mean(data_agg$n_replicates / n_runs) * 100))
  cat("\n")

  return(data_agg)
}
```

**장점**:
- ✅ 통계적으로 안정 (평균은 노이즈에 강함)
- ✅ CV% 정보 보존 (QC 가능)
- ✅ 모든 Run 정보 활용

**단점**:
- ❌ 평균 RT/FWHM이 실제 Run과 다를 수 있음
- ❌ Outlier Run의 영향 (mean은 outlier에 민감)

**사용 케이스**: 안정적인 재현성, QC 필요 시

#### Option C: Consensus with Quality Filtering (권장)

**개념**: Median 기반 consensus + CV% 필터링으로 품질 향상

```r
#' Create consensus dataset from technical replicates with QC filtering
#'
#' @param data Raw DIA-NN data with multiple runs
#' @param min_replicates Minimum number of replicates required (default: 2)
#' @param max_cv_pct Maximum CV% allowed for FWHM (default: 20)
#' @param use_median Use median instead of mean (default: TRUE, more robust)
#' @return List with consensus data and QC report
create_consensus_dataset <- function(data,
                                     min_replicates = 2,
                                     max_cv_pct = 20,
                                     use_median = TRUE) {

  n_runs <- length(unique(data$Run))

  # Step 1: Calculate consensus values
  if (use_median) {
    # Median is more robust to outliers
    data_consensus <- data %>%
      group_by(Precursor.Id) %>%
      summarise(
        # Consensus values (median)
        RT.Start = median(RT.Start, na.rm = TRUE),
        RT.Stop = median(RT.Stop, na.rm = TRUE),
        Precursor.Mz = median(Precursor.Mz, na.rm = TRUE),
        FWHM = median(FWHM, na.rm = TRUE),

        # Variability metrics
        RT_SD = sd(RT.Start, na.rm = TRUE),
        RT_CV = sd(RT.Start, na.rm = TRUE) / mean(RT.Start, na.rm = TRUE) * 100,
        FWHM_SD = sd(FWHM, na.rm = TRUE),
        FWHM_CV = sd(FWHM, na.rm = TRUE) / mean(FWHM, na.rm = TRUE) * 100,

        # Additional QC metrics
        RT_range = max(RT.Start) - min(RT.Start),
        FWHM_range = max(FWHM) - min(FWHM),
        n_replicates = n(),

        .groups = "drop"
      )
  } else {
    # Mean (less robust but traditional)
    data_consensus <- data %>%
      group_by(Precursor.Id) %>%
      summarise(
        RT.Start = mean(RT.Start, na.rm = TRUE),
        RT.Stop = mean(RT.Stop, na.rm = TRUE),
        Precursor.Mz = mean(Precursor.Mz, na.rm = TRUE),
        FWHM = mean(FWHM, na.rm = TRUE),

        RT_SD = sd(RT.Start, na.rm = TRUE),
        RT_CV = sd(RT.Start, na.rm = TRUE) / mean(RT.Start, na.rm = TRUE) * 100,
        FWHM_SD = sd(FWHM, na.rm = TRUE),
        FWHM_CV = sd(FWHM, na.rm = TRUE) / mean(FWHM, na.rm = TRUE) * 100,

        RT_range = max(RT.Start) - min(RT.Start),
        FWHM_range = max(FWHM) - min(FWHM),
        n_replicates = n(),

        .groups = "drop"
      )
  }

  # Step 2: Quality filtering
  data_filtered <- data_consensus %>%
    filter(
      n_replicates >= min_replicates,                    # Replication filter
      (FWHM_CV <= max_cv_pct | is.na(FWHM_CV))          # CV filter (NA = single replicate)
    )

  # Step 3: Generate QC report
  qc_report <- list(
    total_runs = n_runs,
    aggregation_method = ifelse(use_median, "median", "mean"),

    # Before filtering
    precursors_before = nrow(data_consensus),
    mean_rt_cv_before = mean(data_consensus$RT_CV, na.rm = TRUE),
    mean_fwhm_cv_before = mean(data_consensus$FWHM_CV, na.rm = TRUE),

    # After filtering
    precursors_after = nrow(data_filtered),
    removed_count = nrow(data_consensus) - nrow(data_filtered),
    removed_pct = (1 - nrow(data_filtered) / nrow(data_consensus)) * 100,

    mean_rt_cv_after = mean(data_filtered$RT_CV, na.rm = TRUE),
    mean_fwhm_cv_after = mean(data_filtered$FWHM_CV, na.rm = TRUE),

    # Replication statistics
    replication_rate = mean(data_filtered$n_replicates / n_runs) * 100,

    # Filtering criteria used
    filters = list(
      min_replicates = min_replicates,
      max_cv_pct = max_cv_pct
    )
  )

  # Print QC report
  cat("╔══════════════════════════════════════════════════════════╗\n")
  cat("║       Consensus Dataset QC Report                       ║\n")
  cat("╚══════════════════════════════════════════════════════════╝\n\n")

  cat(sprintf("Aggregation method: %s\n", qc_report$aggregation_method))
  cat(sprintf("Total runs: %d\n\n", qc_report$total_runs))

  cat("Before QC filtering:\n")
  cat(sprintf("  Precursors: %s\n", format(qc_report$precursors_before, big.mark = ",")))
  cat(sprintf("  Mean RT CV: %.2f%%\n", qc_report$mean_rt_cv_before))
  cat(sprintf("  Mean FWHM CV: %.2f%%\n\n", qc_report$mean_fwhm_cv_before))

  cat("QC Filters applied:\n")
  cat(sprintf("  Min replicates: %d\n", min_replicates))
  cat(sprintf("  Max FWHM CV: %d%%\n\n", max_cv_pct))

  cat("After QC filtering:\n")
  cat(sprintf("  Precursors: %s (%.1f%% retained)\n",
              format(qc_report$precursors_after, big.mark = ","),
              100 - qc_report$removed_pct))
  cat(sprintf("  Removed: %s (%.1f%% failed QC)\n",
              format(qc_report$removed_count, big.mark = ","),
              qc_report$removed_pct))
  cat(sprintf("  Mean RT CV: %.2f%%\n", qc_report$mean_rt_cv_after))
  cat(sprintf("  Mean FWHM CV: %.2f%%\n", qc_report$mean_fwhm_cv_after))
  cat(sprintf("  Replication rate: %.1f%%\n\n", qc_report$replication_rate))

  # Return both data and QC report
  return(list(
    data = data_filtered,
    qc_report = qc_report
  ))
}
```

**장점**:
- ✅ Median은 outlier에 매우 강함
- ✅ QC 필터링으로 품질 향상 (노이즈 제거)
- ✅ 상세한 QC report (재현성 추적)
- ✅ CV% 정보 보존
- ✅ 유연한 필터 기준 (min_replicates, max_cv)

**단점**:
- ❌ 약간 복잡한 구현
- ❌ 일부 precursor 손실 (QC 실패)

**사용 케이스**: 프로덕션 환경, Publication-quality 분석

### 비교 요약

| Feature | Representative | Average | Consensus (권장) |
|---------|----------------|---------|------------------|
| **구현 복잡도** | ⭐ Very Simple | ⭐⭐ Simple | ⭐⭐⭐ Moderate |
| **중복 제거** | ✅ Perfect | ✅ Perfect | ✅ Perfect |
| **데이터 활용** | ❌ 1/N only | ✅ All runs | ✅ All runs |
| **Outlier 저항성** | ❌ No | ⚠️ Medium (mean) | ✅ High (median) |
| **CV% 정보** | ❌ No | ✅ Yes | ✅ Yes + QC |
| **품질 필터링** | ❌ No | ❌ No | ✅ Yes |
| **QC Report** | ❌ No | ⚠️ Basic | ✅ Comprehensive |
| **권장 사용** | Quick test | Stable data | Production |

### Stage 1 통합 계획

**create_validated_dataset() 함수 확장**:

```r
#' Create validated dataset with replicate handling
#'
#' @param proteome_file Path to DIA-NN output file
#' @param apply_quality_filters Apply DIA-NN quality filters (default: TRUE)
#' @param replicate_handling Replicate handling strategy (default: "consensus")
#'   Options: "representative", "average", "consensus", "none"
#' @param min_replicates Minimum replicates for consensus (default: 2)
#' @param max_cv_percent Maximum CV% for consensus QC (default: 20)
#' @param use_median Use median for consensus (default: TRUE)
#'
#' @return ValidatedData object with replicate-handled data
create_validated_dataset <- function(
  proteome_file,
  apply_quality_filters = TRUE,
  replicate_handling = "consensus",
  min_replicates = 2,
  max_cv_percent = 20,
  use_median = TRUE
) {

  # Step 1: Load raw data
  data_raw <- load_diann_data(proteome_file)

  # Step 2: Apply quality filters (existing)
  if (apply_quality_filters) {
    data_qc <- apply_diann_quality_filters(data_raw)
  } else {
    data_qc <- data_raw
  }

  # Step 3: Check for multiple runs
  n_runs <- length(unique(data_qc$Run))

  if (n_runs > 1) {
    cat(sprintf("\n📊 Detected %d runs (technical replicates)\n", n_runs))
    cat(sprintf("   Replicate handling: %s\n\n", replicate_handling))

    # Apply selected replicate handling strategy
    if (replicate_handling == "representative") {
      data_final <- select_representative_run(data_qc)
      qc_report <- NULL

    } else if (replicate_handling == "average") {
      data_final <- aggregate_replicates(data_qc)
      qc_report <- NULL

    } else if (replicate_handling == "consensus") {
      result <- create_consensus_dataset(
        data_qc,
        min_replicates = min_replicates,
        max_cv_pct = max_cv_percent,
        use_median = use_median
      )
      data_final <- result$data
      qc_report <- result$qc_report

    } else if (replicate_handling == "none") {
      cat("⚠️  WARNING: Using all runs without aggregation\n")
      cat("   This may cause duplication issues in downstream analysis\n\n")
      data_final <- data_qc
      qc_report <- NULL

    } else {
      stop("Invalid replicate_handling option: ", replicate_handling)
    }

  } else {
    cat("\n📊 Single run detected (no replication)\n\n")
    data_final <- data_qc
    qc_report <- NULL
  }

  # Step 4: Continue with existing validation...
  # (RT range, m/z range, FWHM stats, etc.)

  # Add QC report to metadata
  metadata$replicate_qc <- qc_report

  return(ValidatedData)
}
```

### Config 파일 업데이트

#### config/optimization_config.json
```json
{
  "input_data": {
    "input_files": [
      "data/30min_report.parquet",
      "data/60min_report.parquet",
      "data/90min_report.parquet"
    ],
    "current_cycle_time": 2.0,

    "replicate_handling": "consensus",
    "_comment_replicate_handling": "Options: 'representative' (best run), 'average' (mean), 'consensus' (median + QC), 'none' (use all)",
    "_note_replicate_handling": "Recommended: 'consensus' for production, 'representative' for quick tests",

    "min_replicates": 2,
    "_comment_min_replicates": "Minimum number of replicates for consensus (filter out low-replicated precursors)",

    "max_cv_percent": 20,
    "_comment_max_cv_percent": "Maximum FWHM CV% for quality filtering (higher CV = poor reproducibility)",

    "use_median": true,
    "_comment_use_median": "Use median (robust) vs mean (traditional) for consensus"
  }
}
```

### 구현 단계

**Phase 2A: Core Functions** (1시간)
- [ ] `select_representative_run()` 구현
- [ ] `aggregate_replicates()` 구현
- [ ] `create_consensus_dataset()` 구현 (권장)
- [ ] 단위 테스트 (mock 데이터)

**Phase 2B: Stage 1 Integration** (30분)
- [ ] `create_validated_dataset()` 확장
- [ ] replicate_handling 파라미터 추가
- [ ] QC report를 metadata에 추가

**Phase 2C: Config & Testing** (30분)
- [ ] Config에 replicate 옵션 추가
- [ ] Config loader 수정
- [ ] 3개 gradient로 통합 테스트
- [ ] Edge case 테스트 (1 run, 2 runs, 5+ runs)

**Phase 2D: Visualization** (1시간, Optional)
- [ ] QC plot 추가 (CV% distribution)
- [ ] Before/after comparison plot
- [ ] Replicate correlation plot

---

## 📋 전체 구현 로드맵

### Milestone 1: Critical Fixes (2h)
**목표**: Smoothing 실패 문제 해결

- [ ] **Sprint 1.1**: Fallback mechanism (30분)
  - Smoothing 불가능 시 quantile로 자동 전환
  - Warning 메시지 개선

- [ ] **Sprint 1.2**: Adaptive parameters (1h)
  - `adaptive_smoothing_params()` 구현
  - `optimize_rt_bin_width()` 구현
  - Config "auto" 지원

- [ ] **Sprint 1.3**: Testing (30분)
  - 3개 gradient 통합 테스트
  - Edge case 테스트

### Milestone 2: Replicate Management (2h)
**목표**: Technical replicate 올바른 처리

- [ ] **Sprint 2.1**: Core functions (1h)
  - 3가지 replicate handling 구현
  - QC report 생성

- [ ] **Sprint 2.2**: Integration (30분)
  - Stage 1에 통합
  - Config 옵션 추가

- [ ] **Sprint 2.3**: Testing (30분)
  - 실제 데이터 테스트
  - QC report 검증

### Milestone 3: Documentation & Validation (1h)
**목표**: 사용자 가이드 및 검증

- [ ] **Sprint 3.1**: Documentation (30min)
  - README 업데이트 (adaptive parameters)
  - Config template 업데이트
  - Troubleshooting 가이드

- [ ] **Sprint 3.2**: Final validation (30min)
  - 전체 파이프라인 테스트
  - Before/after 성능 비교
  - Edge case 최종 확인

---

## 💡 핵심 인사이트

`✶ Insight ─────────────────────────────────────`
**개선의 핵심 원칙:**

1. **Adaptive > Fixed Parameters**
   - 고정 파라미터는 모든 상황에 부적합
   - 데이터 특성에 따라 자동 조정 (gradient 길이, RT bin 개수)
   - "auto" 설정으로 사용자 부담 감소 + 전문가는 수동 조정 가능

2. **Quality > Quantity in Replicates**
   - 단순 통합보다는 품질 향상에 활용
   - CV% 필터링으로 노이즈 제거
   - QC report로 데이터 신뢰도 추적
   - Median > Mean (outlier 저항성)

3. **Fail-Safe > Fail-Silent**
   - Smoothing 불가능 시 명확한 경고 + 자동 fallback
   - 사용자에게 해결책 제시 (rt_bin_width 조정 권장)
   - Silent failure 방지

4. **Transparency > Black Box**
   - QC report로 모든 처리 과정 공개
   - 제거된 precursor 수, 이유 명시
   - Before/after 비교 메트릭 제공
`─────────────────────────────────────────────────`

---

## 🔬 검증 계획

### 테스트 시나리오

**Scenario 1: Short Gradient (30min)**
- **Before**: Smoothing 실패 (2 bins)
- **After**: Auto-adjust RT bin to 2 min (5 bins) → Smoothing 성공
- **Expected**: Warning 메시지 + 자동 조정 알림

**Scenario 2: Medium Gradient (60min)**
- **Before**: Smoothing 작동하지만 최적 아님 (window=3, 7 bins)
- **After**: Adaptive window=5 (더 효과적)
- **Expected**: Improved smoothing quality

**Scenario 3: Long Gradient (90min)**
- **Before**: Smoothing 잘 작동 (window=3, 13 bins)
- **After**: Adaptive window=9 (더 강력한 smoothing)
- **Expected**: Smoother m/z boundaries

**Scenario 4: Technical Replicates (3 runs)**
- **Before**: 23,379 rows (중복), DPPP 왜곡
- **After**: 7,793 unique precursors (consensus), 정확한 DPPP
- **Expected**: CV% < 20%, QC report 생성

### 성능 메트릭

**m/z Optimization Quality**:
- Smoothing 성공률: Before 33% (1/3 gradients) → After 100% (3/3)
- m/z boundary smoothness: RMSE 감소 예상
- Coverage 유지: > 95%

**Replicate Handling Quality**:
- 중복 제거율: 100% (N=3 → N=1 unique)
- Mean FWHM CV: < 15% (good), 15-20% (acceptable), > 20% (filtered)
- Precursor retention: > 90% (QC filter 후)

---

## 🚀 다음 단계

### 즉시 수행 (패키징 전)
1. ✅ 이 문서 생성 완료
2. 패키징 작업 수행 (PACKAGING_PLAN.md 기반)
3. 패키징 완료 후 이 개선사항 구현

### 개선 작업 순서 (패키징 후)
1. **Milestone 1**: Critical Fixes (Smoothing) - 2시간
2. **Milestone 2**: Replicate Management - 2시간
3. **Milestone 3**: Documentation & Validation - 1시간

**총 예상 시간**: 5시간

---

**작성자**: Claude Code Assistant
**Version**: 1.0
**Status**: 📝 Planning Complete → Pending Package Development
