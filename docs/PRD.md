# 제품 요구사항 문서 (PRD)
# DIA Window Optimizer v2.0

**작성일**: 2025년 10월 13일 (최초)
**최종 업데이트**: 2025년 11월 17일
**버전**: 2.0.1 (v2.0 Refactored Architecture)
**상태**: 승인됨 - 구현 진행 중

---

## 1. 프로젝트 개요

### 1.1 배경 및 목적

DIA (Data-Independent Acquisition) 질량분석법은 proteomics 연구에서 널리 사용되는 기술입니다. 그러나 최적의 isolation window 설정은 다음과 같은 과제가 있습니다:

- **DPPP (Data Points Per Peak) 최적화**: 정량 정확도와 식별 민감도 사이의 균형
- **샘플별 차이**: 전구체 분포가 샘플마다 다름
- **장비 제약**: Scan rate, injection time 등 물리적 한계
- **실험 계획**: 현재 상태 진단 없이 다음 실험 설계가 어려움
- **Technical Replicate 관리**: 여러 Run의 데이터를 통합하여 재현성 향상

본 도구는 **DIA-NN 분석 결과를 기반으로 다음 실험을 위한 최적화된 isolation window method**를 생성하고, **현재 acquisition 설정의 적절성을 진단**하는 것을 목표로 합니다.

**Version 2.0 특징**:
- **3-Stage Streamlined Pipeline**: 통합된 아키텍처로 단순화
- **GLOBAL vs LOCAL Optimization**: m/z 최적화 전략의 이중 접근법
- **Adaptive Parameters**: Gradient 길이에 따른 자동 파라미터 조정
- **Technical Replicate Support**: 여러 Run의 데이터 통합 및 QC

### 1.2 핵심 가치 제안

1. **진단 우선 접근**: 현재 DPPP 달성도를 분석하여 개선 방향 제시
2. **실측 데이터 기반**: Raw file의 실제 injection time을 반영한 현실적 최적화
3. **통합 최적화 파이프라인**: 3-Stage 아키텍처로 단순화된 워크플로우
4. **Adaptive 전략**:
   - **GLOBAL Smoothing**: 연속적인 m/z 함수 (모든 gradient 길이 지원)
   - **LOCAL Strategies**: Bin-specific 정확한 m/z range (Quantile, Coverage, Outlier)
   - **Auto Parameter Selection**: Gradient 특성에 따른 자동 파라미터 조정
5. **Technical Replicate 관리**: Consensus 방식으로 재현성 향상 및 QC
6. **다양한 Window 모드**: Fixed, Variable (density-based) window 생성
7. **Quant 중심 기본값**: DPPP 7.0을 기본으로 하되 ID 모드(1.5) 지원

---

## 2. 사용자 스토리

### 2.1 주요 사용자 (Persona)

#### Persona 1: Proteomics 연구자 (정량 분석)
- **목표**: 차별 발현 분석을 위한 정확한 정량
- **니즈**: DPPP 7.0+ 달성, 재현성 높은 결과
- **Pain point**: 기존 방법이 DPPP 목표를 달성하지 못함

#### Persona 2: Proteomics 연구자 (발견적 연구)
- **목표**: 최대한 많은 전구체 식별
- **니즈**: DPPP 1.5, 더 많은 windows
- **Pain point**: 식별 민감도와 정량 정확도 사이 트레이드오프

#### Persona 3: Core Facility 운영자
- **목표**: 다양한 샘플에 대한 범용 방법 개발
- **니즈**: 빠른 최적화, 다양한 전략 비교
- **Pain point**: 샘플별 최적화 시간 부족

### 2.2 사용자 시나리오

#### 시나리오 1: 현재 방법 진단
```
As a proteomics 연구자,
I want to 현재 acquisition 설정의 DPPP 달성도를 확인하고,
So that 다음 실험에서 개선할 수 있다.

Given: DIA-NN 분석 완료된 데이터
When: 현재 scan_time = 2.0초로 분석
Then:
  - 72%의 전구체만 DPPP 7.0 ± 0.5 달성
  - 권장 scan_time = 1.85초
  - 예상 개선: 88% 달성 가능
```

#### 시나리오 2: 새로운 방법 생성
```
As a proteomics 연구자,
I want to DPPP 7.0을 달성하는 최적화된 isolation window를,
So that 다음 실험에서 더 정확한 정량 결과를 얻을 수 있다.

Given: 권장 scan_time = 1.85초
When: Variable window 모드로 최적화
Then:
  - 215개 windows 생성
  - 각 window당 균등한 전구체 분포
  - Method file (.csv) 내보내기
```

#### 시나리오 3: Raw file 기반 Injection Time 최적화
```
As a core facility 운영자,
I want to Raw file의 실제 injection time을 분석하여,
So that maxIT 설정을 최적화할 수 있다.

Given: Raw file + DIA-NN 결과
When: Injection time 분석
Then:
  - 현재 maxIT = 20ms
  - 실제 median IT = 18.5ms (92% 효율)
  - 권장 maxIT = 22ms (더 많은 ions 수집 가능)
```

---

## 3. 기능 요구사항

**v2.0 아키텍처 개요**:
```
[Stage 1] Data Validation → ValidatedData
    ↓
[Stage 2] Optimization Planning (MERGED) → OptimizationPlan
    (DPPP Diagnosis + Window Count Determination)
    ↓
[Stage 3] Window Optimization (UNIFIED) → OptimizedWindows
    (RT Binning + m/z Range + Window Generation)
    ↓
[Stage 4] Visualization & Reporting → Plots + PDF + Method file
```

### 3.1 Stage 1: 데이터 검증 (Data Validation)

**상태**: ✅ 구현 완료 (Technical Replicate 기능 제외)

#### FR-1.1: DIA-NN 데이터 로딩
**우선순위**: P0 (필수)
**구현 상태**: ✅ 완료

**요구사항**:
- Parquet, TSV, CSV 형식 자동 감지 및 로딩
- 대용량 파일 (1M+ precursors) 효율적 처리
- 진행 상황 표시 (progress bar)

**입력**:
- `proteome_file`: DIA-NN output 파일 경로
- `rt_range`: (선택) RT 필터링 범위
- `mz_range`: (선택) m/z 필터링 범위

**출력**:
```r
list(
  data = tibble(RT.Start, Precursor.Mz, FWHM, ...),
  n_precursors = 1190706,
  rt_range = c(10.5, 112.3),
  mz_range = c(382.1, 978.4)
)
```

**검증 조건**:
- [x] 필수 컬럼 존재 (RT.Start, Precursor.Mz, FWHM)
- [x] RT 값이 양수이며 순서대로 정렬
- [x] m/z 값이 유효 범위 내 (50-5000 Da)
- [x] FWHM 값이 양수 (0.01-10 min)

---

#### FR-1.2: Technical Replicate 관리 (**NEW in v2.0**)
**우선순위**: P0 (필수)
**구현 상태**: 📋 Milestone 2 계획됨

**1. Replicate 그룹 인식**:
- DIA-NN `Run` 컬럼 기반 자동 인식
- `Precursor.Id` 기준으로 Replicate 매칭
- Replicate 수 분포 분석 (1개, 2개, 3개 등)

**2. Consensus 전략 (Median 기반)**:
- **Replicate ≥ 2**: Median 값 사용 + CV% 계산
- **Replicate = 1**: 원본 값 유지 + CV% = NA
- **필터링**: CV% > threshold인 precursor 제거 (단, n=1은 유지)

**3. Geometric CV% 계산**:
- RT, m/z, FWHM에 대한 Replicate간 CV%
- Formula: `Geometric CV = sqrt(exp(sd(log(x))^2) - 1) * 100`
- Replicate=1인 경우 CV% = NA로 표시

**입력**:
```r
create_validated_dataset(
  proteome_file,
  enable_replicate_consensus = TRUE,
  min_replicates = 1,  # Minimum 1 (include singletons)
  max_cv_percent = 20  # Filter out high-CV precursors (n≥2)
)
```

**출력**:
```r
list(
  data = tibble(
    Precursor.Id,
    RT.Start,        # Consensus (median or original)
    Precursor.Mz,    # Consensus
    FWHM,            # Consensus
    RT_CV_pct,       # Geometric CV% or NA
    FWHM_CV_pct,     # Geometric CV% or NA
    n_replicates,    # 1, 2, 3, ...
    ...
  ),
  metadata = list(
    n_runs = 3,
    n_precursors_unique = 7793,
    n_singleton = 143,      # Replicate=1 only
    n_replicated = 7650,    # Replicate≥2
    n_filtered_cv = 15,     # Removed by CV filter
    mean_rt_cv_pct = 2.3,
    mean_fwhm_cv_pct = 8.5
  )
)
```

**처리 로직**:
```
Step 1: Replicate 그룹 식별
  - Precursor.Id별 Run 개수 계산

Step 2: Consensus 계산
  - IF n_replicates ≥ 2:
      → Value = median(values)
      → CV% = geometric_cv(values)
  - ELSE (n_replicates = 1):
      → Value = original_value
      → CV% = NA

Step 3: CV 필터링
  - IF n_replicates ≥ 2 AND CV% > max_cv_percent:
      → Remove precursor
  - ELSE:
      → Keep (including singletons)

Step 4: 통계 요약
  - Singleton vs Replicated 비율
  - Mean CV% (replicated only)
  - Filtered count
```

**참고**: `docs/GEOMETRIC_CV_GUIDE.md`

---

#### FR-1.3: Raw File Metadata 추출 (선택)
**우선순위**: P2 (낮음)
**구현 상태**: 🔴 미구현

**요구사항**:
- Raw file에서 실제 injection time 추출
- MS1, MS2 scan 통계 계산
- 실측 cycle time 계산

**입력**:
- `raw_file_dir`: Raw file 디렉토리 경로

**출력**:
```r
list(
  injection_times = vector(length = n_scans),
  median_it = 18.5,  # ms
  mean_it = 17.8,
  it_efficiency = 0.92,  # median_it / maxIT
  actual_cycle_time = 1.92  # seconds
)
```

---

#### FR-1.4: 데이터 품질 검증
**우선순위**: P0 (필수)
**구현 상태**: ✅ 완료

**요구사항**:
- FWHM outlier 감지 (IQR 방법)
- RT 범위 자동 감지
- m/z 범위 자동 감지
- 데이터 완전성 확인

**검증 규칙**:
```r
# FWHM outliers
Q1 <- quantile(FWHM, 0.25)
Q3 <- quantile(FWHM, 0.75)
IQR <- Q3 - Q1
outliers <- FWHM < (Q1 - 1.5*IQR) | FWHM > (Q3 + 1.5*IQR)

# 경고: outliers > 5%
```

---

### 3.2 Stage 2: DPPP 진단 (DPPP Diagnosis)

#### FR-2.1: 현재 DPPP 분포 계산
**우선순위**: P0 (필수)

**요구사항**:
- 사용자 지정 scan_time으로 DPPP 계산
- DPPP 분포 통계 (mean, median, percentiles)
- RT × m/z 공간에서 DPPP 분포 시각화

**공식**:
```
DPPP = (1.7 × FWHM_seconds) / cycle_time_seconds

where:
  - 1.7 = Spectronaut 표준 peak width factor
  - cycle_time = scan_time (사용자 입력)
```

**출력**:
```r
list(
  mean_dppp = 6.8,
  median_dppp = 6.5,
  p25_dppp = 5.2,
  p75_dppp = 8.1,
  dppp_distribution = vector(length = n_precursors)
)
```

---

#### FR-2.2: DPPP Satisfaction Ratio 계산
**우선순위**: P0 (필수)
**구현 상태**: ✅ 완료

**요구사항**:
- Target DPPP 이상인 전구체 비율 계산
- RT bin별 satisfaction ratio 분석
- m/z bin별 satisfaction ratio 분석

**공식**:
```r
# Proportion of precursors meeting minimum DPPP requirement
satisfaction_ratio = sum(DPPP >= target_dppp) / length(DPPP)
```

**기본값**:
- `target_dppp = 7.0` (Quant 모드)
- `target_dppp = 1.5` (ID 모드)

**설명**:
- **Satisfaction Ratio = 0.72** → 전체의 72%가 DPPP ≥ 7.0
- **Goal**: Maximize proportion of precursors meeting target DPPP
- **Optimization**: Adjust scan_time to maximize satisfaction ratio

**출력**:
```r
list(
  satisfaction_ratio = 0.72,  # 72% with DPPP ≥ 7.0
  n_satisfied = 857709,
  n_total = 1190706,
  by_rt_bin = tibble(rt_bin, satisfaction_ratio, ...),
  by_mz_bin = tibble(mz_bin, satisfaction_ratio, ...)
)
```

---

#### FR-2.3: 최적 Scan Time 추천
**우선순위**: P0 (필수)

**요구사항**:
- Satisfaction ratio를 최대화하는 scan_time 찾기
- Instrument scan rate 제약 고려
- Trade-off 분석 제공

**알고리즘**:
```r
# Optimization objective
objective <- function(scan_time) {
  dppp_distribution <- calculate_dppp(FWHM, scan_time)
  -1 * compute_satisfaction_ratio(dppp_distribution, target_dppp)
}

# Grid search + refinement
scan_time_range <- seq(1.0, 3.0, 0.1)
optimal <- optimize(objective, scan_time_range)
```

**제약 조건**:
```r
# Scan rate 제약
n_windows_max <- floor((scan_time - MS1_time) / MS2_time)
scan_rate <- n_windows_max / scan_time

if (scan_rate > instrument_max_scan_rate) {
  warning("Scan rate exceeds instrument limit")
  # Adjust scan_time upward
}
```

**출력**:
```r
list(
  optimal_scan_time = 1.85,  # seconds
  expected_satisfaction = 0.88,  # 88%
  expected_window_count = 215,
  improvement = list(
    current_satisfaction = 0.72,
    expected_satisfaction = 0.88,
    delta = +16%
  ),
  feasible = TRUE,
  warnings = character()
)
```

---

#### FR-2.4: Trade-off 분석
**우선순위**: P1 (높음)

**요구사항**:
- scan_time vs. window_count vs. satisfaction 관계 시각화
- 사용자가 트레이드오프를 이해하도록 지원

**출력**:
```r
tibble(
  scan_time = seq(1.0, 3.0, 0.1),
  window_count = c(230, 225, ..., 100),
  satisfaction_ratio = c(0.92, 0.88, ..., 0.65),
  scan_rate_hz = c(125, 118, ..., 50)
)
```

---

### 3.3 Stage 3: Window 최적화

#### FR-3.1: Window 개수 결정
**우선순위**: P0 (필수)

**요구사항**:
- Stage 2에서 추천된 scan_time 기반 계산
- Instrument scan rate 제약 확인
- 이론적 최대값 vs. 실제 가능값 비교

**공식**:
```r
# Astral (parallel)
cycle_time = scan_time
theoretical_max = floor((cycle_time * 1000 - MS1_time) / MS2_time)

# Scan rate feasibility
feasible_windows = min(
  theoretical_max,
  floor(instrument_max_scan_rate * cycle_time)
)
```

---

#### FR-3.2: Injection Time 기반 조정 (선택)
**우선순위**: P2 (중간)

**요구사항**:
- Raw file의 실제 injection time 분석
- maxIT가 너무 제한적인 경우 경고 및 권장값 제시

**로직**:
```r
if (median(actual_IT) > 0.9 * maxIT) {
  suggested_maxIT <- quantile(actual_IT, 0.75) * 1.2
  warning(sprintf(
    "Current maxIT (%d ms) too restrictive. Consider: %d ms",
    maxIT, suggested_maxIT
  ))
}
```

---

#### FR-3.3: RT Binning
**우선순위**: P0 (필수)

**요구사항**:
- 시간 기반 binning (5분 간격 기본값)
- 사용자 지정 breakpoints 지원

**기존 코드 활용**:
```r
# 기존 rt_segmentation.R 활용
result <- segment_rt_by_time_unit(data, rt_bin_width_min = 5)
```

---

#### FR-3.4: m/z Range 최적화
**우선순위**: P0 (필수)

**요구사항**:
4가지 전략을 구현하고 비교

**전략 1: Quantile-based**
```r
mz_min <- quantile(Precursor.Mz, 0.01)  # 1st percentile
mz_max <- quantile(Precursor.Mz, 0.99)  # 99th percentile
```

**전략 분류** (**v2.0 구조**):

**GLOBAL Optimization** (Smoothing):
- **Step 1**: 전체 gradient에 대해 high-resolution RT sampling
- **Step 2**: Sliding window로 각 RT point의 m/z 계산
- **Step 3**: Savitzky-Golay curve fitting
- **Step 4**: Fitted curve를 RT bin으로 분할 (interpolation)

**LOCAL Optimization** (Quantile, Coverage, Outlier):
- **Step 1**: RT bin으로 먼저 분할 (adaptive binning 적용 가능)
- **Step 2**: 각 RT bin에서 독립적으로 m/z range 계산
- **Step 3**: 전략별 최적화 (quantile/coverage/outlier)

---

**전략 1: Quantile (LOCAL)**
```r
# LOCAL: RT binning → per-bin optimization
rt_bins <- segment_rt_by_time_unit(data, rt_bin_width_min)

for (bin in rt_bins) {
  bin_precursors <- filter(data, rt_group == bin)
  mz_min[bin] <- quantile(bin_precursors$Mz, 0.05)  # P5
  mz_max[bin] <- quantile(bin_precursors$Mz, 0.95)  # P95
}
```

**전략 2: Coverage (LOCAL)**
```r
# LOCAL: RT binning → per-bin optimization
rt_bins <- segment_rt_by_time_unit(data, rt_bin_width_min)

for (bin in rt_bins) {
  bin_precursors <- filter(data, rt_group == bin)
  mz_min[bin] <- quantile(bin_precursors$Mz, 0.025)  # 2.5%
  mz_max[bin] <- quantile(bin_precursors$Mz, 0.975)  # 97.5%
}
# Coverage target: 95%
```

**전략 3: Outlier (LOCAL)**
```r
# LOCAL: RT binning → per-bin optimization
rt_bins <- segment_rt_by_time_unit(data, rt_bin_width_min)

for (bin in rt_bins) {
  bin_precursors <- filter(data, rt_group == bin)
  Q1 <- quantile(bin_precursors$Mz, 0.25)
  Q3 <- quantile(bin_precursors$Mz, 0.75)
  IQR <- Q3 - Q1
  mz_min[bin] <- Q1 - 1.5 * IQR
  mz_max[bin] <- Q3 + 1.5 * IQR
}
```

**전략 4: Smoothing (GLOBAL)** (**v2.0 Refactored**)
```r
# GLOBAL: Curve fitting → RT binning

# Step 1: Fine RT sampling (entire gradient)
rt_points <- seq(rt_min, rt_max, by = 0.5)  # 0.5-1 min interval

# Step 2: Sliding window m/z calculation
for (rt in rt_points) {
  window_precursors <- filter(data, abs(RT - rt) <= window_halfwidth)
  mz_min_raw[rt] <- quantile(window_precursors$Mz, 0.05)
  mz_max_raw[rt] <- quantile(window_precursors$Mz, 0.95)
}

# Step 3: Savitzky-Golay curve fitting
mz_min_smooth <- sgolayfilt(mz_min_raw, p = 3, n = 7)
mz_max_smooth <- sgolayfilt(mz_max_raw, p = 3, n = 7)

# Step 4: Divide into RT bins (interpolation from fitted curve)
rt_bins <- segment_rt_by_time_unit(data, rt_bin_width_min)

for (bin in rt_bins) {
  bin_center_rt <- (bin_start + bin_end) / 2
  mz_min[bin] <- interpolate_at_rt(mz_min_smooth, rt_points, bin_center_rt)
  mz_max[bin] <- interpolate_at_rt(mz_max_smooth, rt_points, bin_center_rt)
}
```

**Adaptive RT Binning** (LOCAL 전략에서만):
```r
# LOCAL strategies can use adaptive RT binning
if (gradient_length < 15) {
  rt_bin_width <- 2.0  # Short gradient
} else if (gradient_length < 40) {
  rt_bin_width <- 3.0  # Medium
} else {
  rt_bin_width <- 5.0  # Long (default)
}
```

**참고**: `docs/SMOOTHING_GLOBAL_VS_LOCAL.md`

---

**비교 출력**:
```r
tibble(
  strategy = c("quantile", "coverage", "outlier", "smoothing"),
  optimization_type = c("LOCAL", "LOCAL", "LOCAL", "GLOBAL"),
  mz_min = c(...),
  mz_max = c(...),
  range_width = mz_max - mz_min,
  precursor_coverage = c(...),
  outliers_removed = c(...)
)
```

---

#### FR-3.5: Window Generation (v2.0 통합)
**우선순위**: P0 (필수)
**구현 상태**: ✅ 완료 (Fixed, Variable)

**요구사항**:
- RT bin별 window 생성
- 정확한 window 개수 보장
- Optional overlap 지원 (향후)

---

**모드 1: Fixed Windows** (**구현 완료**)
```r
# Equal-width windows per RT bin
generate_windows(
  data,
  mz_ranges,
  n_windows_per_bin,
  mode = "fixed",
  overlap_percent = 0  # Optional (future)
)

# Implementation
for (bin in rt_bins) {
  n_windows_bin <- n_windows_per_bin[bin]
  window_width <- (mz_max[bin] - mz_min[bin]) / n_windows_bin

  windows[[bin]] <- tibble(
    mz_start = mz_min[bin] + (0:(n_windows_bin-1)) * window_width,
    mz_end = mz_min[bin] + (1:n_windows_bin) * window_width
  )
}
```

**특징**:
- ✅ Simple, predictable
- ✅ Equal-width windows
- ⚠️ May have uneven precursor distribution

---

**모드 2: Variable Windows** (**구현 완료, 권장**)
```r
# Density-based adaptive windows
generate_windows(
  data,
  mz_ranges,
  n_windows_per_bin,
  mode = "variable",
  overlap_percent = 0  # Optional (future)
)

# Uses Largest Remainder Method
# 기존 window_generator.R::generate_windows_from_boundaries()
```

**Largest Remainder Method**:
1. Target: Equal precursors per window
2. 누적 분포 기반 boundary 생성
3. Remainder 처리로 정확한 개수 보장

**특징**:
- ✅ Even precursor distribution
- ✅ Adaptive to density
- ✅ Exact window count

---

**Optional: Overlap** (**향후 추가**)
```r
# Future enhancement: overlap_percent parameter
# Works with both Fixed and Variable modes

generate_windows(
  ...,
  overlap_percent = 1.0  # 1% overlap (default: 0)
)

# Implementation (future)
if (overlap_percent > 0) {
  overlap_da <- window_width * (overlap_percent / 100)
  mz_start <- mz_start - (overlap_da / 2)
  mz_end <- mz_end + (overlap_da / 2)
}
```

**구현 우선순위**: P2 (낮음)

---

**출력**:
```r
list(
  windows = tibble(
    window_id, rt_bin, mz_start, mz_end,
    window_width, n_precursors
  ),
  statistics = list(
    total_windows = 215,
    mean_precursors_per_window = 5539,
    cv_precursors = 15.3,  # Lower = more uniform
    coverage_ratio = 0.982
  )
)
```

---

### 3.4 Stage 4: 시각화 및 보고

**상태**: ✅ 구현 완료 (8 plots, PDF report, method file)

#### FR-4.1: 필수 Plots (8개)
**우선순위**: P0 (필수)
**구현 상태**: ✅ 완료

1. **DPPP Density Plot**
   - DPPP 분포 히스토그램
   - Target DPPP ± tolerance 범위 표시

2. **RT - Window Size Plot**
   - RT bin별 window 개수 및 평균 width
   - Variable mode일 때 width 변화 시각화

3. **RT × m/z Density Heatmap**
   - 전구체 밀도 2D 히트맵
   - High density 영역 강조

4. **m/z - Normalized Density**
   - m/z 범위별 정규화된 전구체 밀도
   - Window 경계 overlay

5. **m/z - Window Width**
   - m/z 범위에 따른 window width 변화
   - Fixed vs Variable 비교

6. **Precursor Coverage Map**
   - RT × m/z 공간에서 window coverage
   - Gap 영역 강조

7. **Window Efficiency Plot**
   - Window당 전구체 수 분포
   - Uniformity 평가 (CV 계산)

8. **DPPP Achievement Heatmap**
   - RT × m/z 공간에서 DPPP 달성도
   - Target 달성 여부 color coding

---

#### FR-4.2: 종합 리포트 생성
**우선순위**: P0 (필수)

**요구사항**:
- 모든 plot을 포함한 multi-page PDF
- 각 Stage별 요약 통계
- 추천 사항 및 경고 메시지

**리포트 구조**:
```
Page 1: Executive Summary
  - DPPP satisfaction: 72% → 88% (expected)
  - Recommended scan_time: 1.85s
  - Generated windows: 215

Page 2-3: Stage 1 - Data Quality
  - Data statistics
  - FWHM distribution
  - Outliers detected

Page 4-5: Stage 2 - DPPP Diagnosis
  - Current DPPP distribution
  - Satisfaction ratio analysis
  - Trade-off curves

Page 6-8: Stage 3 - Window Optimization
  - RT binning results
  - m/z range strategy comparison
  - Window generation mode comparison

Page 9-12: Stage 4 - Visualization
  - All 8 required plots

Page 13: Recommendations
  - Next steps
  - Warnings and considerations
```

---

#### FR-4.3: Method File 내보내기
**우선순위**: P0 (필수)

**출력 형식**:
```csv
Window_ID,Center_mz,Start_mz,End_mz,Width_Da,RT_Bin
1,385.5,383.5,387.5,4.0,Bin1
2,391.2,389.5,392.9,3.4,Bin1
...
```

**추가 메타데이터**:
```json
{
  "mode": "variable",
  "target_dppp": 7.0,
  "scan_time": 1.85,
  "n_windows": 215,
  "instrument": "astral",
  "generation_date": "2025-10-13"
}
```

---

## 4. 비기능 요구사항

### 4.1 성능 요구사항

| 항목 | 요구사항 | 측정 방법 |
|------|---------|----------|
| 데이터 로딩 | < 30초 (1M precursors, parquet) | Benchmark |
| DPPP 계산 | < 10초 (1M precursors) | Benchmark |
| Window 생성 | < 2분 (전체 파이프라인) | End-to-end test |
| 메모리 사용 | < 2GB (1M precursors) | Memory profiling |

### 4.2 사용성 요구사항

- **진행 상황 표시**: 각 Stage별 progress bar
- **명확한 오류 메시지**: 실패 원인 및 해결 방법 제시
- **경고 메시지**: 잠재적 문제 사전 알림

### 4.3 확장성 요구사항

- **대용량 데이터**: 최대 5M precursors 지원
- **다양한 장비**: Astral, Exploris, 전통 Orbitrap 지원
- **플러그인 구조**: 새로운 m/z range 전략 추가 가능

---

## 5. 제약 조건

### 5.1 기술적 제약

- **R 버전**: R 4.0 이상
- **필수 패키지**: arrow, dplyr, ggplot2, prospectr
- **운영체제**: Windows, macOS, Linux

### 5.2 데이터 제약

- **필수 입력**: DIA-NN report.parquet
- **필수 컬럼**: RT.Start, Precursor.Mz, FWHM
- **선택 입력**: Raw files (.raw)

### 5.3 시간 제약

- **Phase 1-2**: 2주 이내 완료
- **Phase 3**: 3주 이내 완료
- **Phase 4**: 2주 이내 완료
- **전체**: 7주 이내 v2.0 릴리스

---

## 6. 수용 기준 (Acceptance Criteria)

### 6.1 기능 수용 기준

**Stage 1**:
- [x] 1M precursors를 30초 이내 로딩 및 검증
- [ ] Technical replicate consensus 생성 (median-based)
- [ ] Geometric CV% 계산

**Stage 2**:
- [x] DPPP satisfaction ratio 계산 (DPPP ≥ target)
- [x] Scan_time 추천이 instrument parameter 제약 조건 반영
- [x] 추천 scan_time 기반 window 개수 계산

**Stage 3**:
- [x] Window 개수가 Stage 2 추천값 사용 확인
- [x] 생성된 window 개수 정확성 (오차 ±1개 이내)
- [x] GLOBAL Smoothing: 모든 gradient 길이 지원
- [x] LOCAL strategies: RT bin별 독립 계산

**Stage 4**:
- [x] 8개 필수 plot 생성
- [x] PDF 리포트 생성
- [x] Method file 내보내기

**End-to-End Workflow**:
- [ ] Stage 2 추천 scan_time → Stage 3 window count 전달 확인
- [ ] Instrument constraints → window count 제한 반영 확인
- [ ] Generated windows → Method file 정확성 검증

### 6.2 품질 수용 기준

- [ ] 단위 테스트 커버리지 > 80%
- [ ] 통합 테스트 통과율 100%
- [ ] 메모리 사용량 < 2GB (1M precursors)
- [ ] 코드 리뷰 완료 (모든 Phase)

---

## 7. 부록

### 7.1 용어 정의

- **DPPP**: Data Points Per Peak - 크로마토그래픽 피크당 데이터 포인트 수
- **Satisfaction Ratio**: Target DPPP ± tolerance 범위 내 전구체 비율
- **Scan Time**: MS duty cycle time (초)
- **Cycle Time**: Scan time과 동일 (MS1 + all MS2 scans)
- **Injection Time (IT)**: Ion accumulation time (ms)

### 7.2 참고 문헌

- Spectronaut DPPP 정의: Peak width = 1.7 × FWHM
- DynamicDIA: Tsou et al. (2015)
- Thermo Astral specifications

### 7.3 v2.0 구현 상태 요약

**✅ 완료된 기능**:
- **Stage 1**: Data validation and loading (Replicate 기능 제외)
- **Stage 2**: DPPP diagnosis, satisfaction ratio, scan time optimization
- **Stage 3**:
  - Window count determination
  - m/z optimization (GLOBAL Smoothing + LOCAL Quantile/Coverage/Outlier)
  - Window generation (Fixed, Variable modes)
- **Stage 4**: 8 essential plots, PDF report, method file export

**📋 계획된 기능 (Milestones)**:
- **Milestone 2** (2h): Technical Replicate Management
  - Consensus strategy (median-based)
  - Geometric CV% calculation
  - QC filtering
- **Milestone 3** (1h): Documentation & Validation
  - User guide updates
  - Troubleshooting guide
  - End-to-end testing

**🔴 미구현 기능 (P2 우선순위)**:
- Raw file metadata extraction (FR-1.3)
- Window overlap mode (FR-3.5)
- Injection time-based adjustment (FR-3.2)

**📚 주요 문서**:
- `docs/SMOOTHING_GLOBAL_VS_LOCAL.md` - m/z 최적화 전략 비교
- `docs/GEOMETRIC_CV_GUIDE.md` - Technical replicate CV 계산
- `docs/ARCHITECTURE.md` - System architecture
- `IMPROVEMENT_PLAN.md` - 3 milestones roadmap

---

### 7.4 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| 1.0 | 2025-09-01 | 초기 버전 (단일 최적화) |
| 2.0 | 2025-10-13 | 4-Stage 아키텍처로 재설계 |
| 2.0.1 | 2025-11-17 | v2.0 Refactored 아키텍처 반영 |
|     |            | - 3-Stage 통합 구조 (Stage 2+3A 병합) |
|     |            | - GLOBAL vs LOCAL m/z 최적화 전략 |
|     |            | - Technical Replicate 관리 추가 |
|     |            | - Satisfaction Ratio 정의 수정 |
|     |            | - Adaptive parameters 지원 |
