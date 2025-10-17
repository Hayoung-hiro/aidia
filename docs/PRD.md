# 제품 요구사항 문서 (PRD)
# DIA Window Optimizer v2.0

**작성일**: 2025년 10월 13일
**버전**: 2.0
**상태**: 승인됨

---

## 1. 프로젝트 개요

### 1.1 배경 및 목적

DIA (Data-Independent Acquisition) 질량분석법은 proteomics 연구에서 널리 사용되는 기술입니다. 그러나 최적의 isolation window 설정은 다음과 같은 과제가 있습니다:

- **DPPP (Data Points Per Peak) 최적화**: 정량 정확도와 식별 민감도 사이의 균형
- **샘플별 차이**: 전구체 분포가 샘플마다 다름
- **장비 제약**: Scan rate, injection time 등 물리적 한계
- **실험 계획**: 현재 상태 진단 없이 다음 실험 설계가 어려움

본 도구는 **DIA-NN 분석 결과를 기반으로 다음 실험을 위한 최적화된 isolation window method**를 생성하고, **현재 acquisition 설정의 적절성을 진단**하는 것을 목표로 합니다.

### 1.2 핵심 가치 제안

1. **진단 우선 접근**: 현재 DPPP 달성도를 분석하여 개선 방향 제시
2. **실측 데이터 기반**: Raw file의 실제 injection time을 반영한 현실적 최적화
3. **다양한 최적화 전략**: Fixed, Overlapped, Variable window 모드 및 다양한 m/z range 전략
4. **Quant 중심 기본값**: DPPP 7.0을 기본으로 하되 ID 모드(1.5) 지원

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

### 3.1 Stage 1: 데이터 검증 (Data Validation)

#### FR-1.1: DIA-NN 데이터 로딩
**우선순위**: P0 (필수)

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
- [ ] 필수 컬럼 존재 (RT.Start, Precursor.Mz, FWHM)
- [ ] RT 값이 양수이며 순서대로 정렬
- [ ] m/z 값이 유효 범위 내 (50-5000 Da)
- [ ] FWHM 값이 양수 (0.01-10 min)

---

#### FR-1.2: Raw File Metadata 추출 (선택)
**우선순위**: P1 (높음)

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

#### FR-1.3: 데이터 품질 검증
**우선순위**: P0 (필수)

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

**요구사항**:
- Target DPPP ± tolerance 범위 내 전구체 비율 계산
- RT bin별 satisfaction ratio 분석
- m/z bin별 satisfaction ratio 분석

**공식**:
```r
satisfaction_ratio =
  sum(abs(DPPP - target_dppp) <= tolerance) / length(DPPP)
```

**기본값**:
- `target_dppp = 7.0` (Quant 모드)
- `dppp_tolerance = 0.5` (±0.5 허용)

**출력**:
```r
list(
  satisfaction_ratio = 0.72,  # 72%
  n_satisfied = 857,709,
  n_total = 1,190,706,
  by_rt_bin = tibble(...),
  by_mz_bin = tibble(...)
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

**전략 2: Smoothing-based (DynamicDIA)**
```r
# 기존 dynamicDIA.R 활용
boundaries <- compute_smooth_mz_boundaries(
  rt_binning_result,
  dynamic = TRUE,
  smoothing_method = "savgol"
)
```

**전략 3: Outlier Removal**
```r
Q1 <- quantile(Precursor.Mz, 0.25)
Q3 <- quantile(Precursor.Mz, 0.75)
IQR <- Q3 - Q1
mz_min <- Q1 - 1.5 * IQR
mz_max <- Q3 + 1.5 * IQR
```

**전략 4: Coverage-based (NEW)**
```r
# 목표: 95% precursor를 커버하면서 range 최소화
cumulative_dist <- ecdf(Precursor.Mz)
mz_min <- quantile(Precursor.Mz, 0.025)  # 2.5%
mz_max <- quantile(Precursor.Mz, 0.975)  # 97.5%
coverage <- 0.95
```

**비교 출력**:
```r
tibble(
  strategy = c("quantile", "smoothing", "outlier_removal", "coverage_based"),
  mz_min = c(...),
  mz_max = c(...),
  range_width = mz_max - mz_min,
  precursor_coverage = c(...),
  outliers_removed = c(...)
)
```

---

#### FR-3.5: Window Generation (3가지 모드)
**우선순위**: P0 (필수)

**모드 1: Fixed Windows**
```r
# 균등 간격
window_width <- (mz_max - mz_min) / n_windows
windows <- seq(mz_min, mz_max, by = window_width)
```

**모드 2: Overlapped Windows**
```r
# Fixed + overlap (1% overlap 기본값)
overlap_da <- window_width * 0.01
windows_overlapped <- Fixed windows - (overlap_da / 2)
```

**모드 3: Variable Windows (Density equalization)**
```r
# 기존 window_generator.R 활용
# Largest remainder method로 정확한 n_windows 보장
windows <- generate_windows_from_boundaries(
  rt_binning_result,
  boundary_result,
  n_windows = 215
)
```

---

### 3.4 Stage 4: 시각화 및 보고

#### FR-4.1: 필수 Plots (8개)
**우선순위**: P0 (필수)

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

- [ ] Stage 1: 1M precursors를 30초 이내 로딩 및 검증
- [ ] Stage 2: DPPP satisfaction ratio 정확히 계산 (수동 검증 대비 오차 < 1%)
- [ ] Stage 2: Scan_time 추천이 satisfaction ratio 향상 (실제 테스트 검증)
- [ ] Stage 3: 정확히 지정된 개수의 windows 생성 (오차 ±1개 이내)
- [ ] Stage 3: Variable mode에서 CV(precursors per window) < 0.2
- [ ] Stage 4: 모든 필수 plot 정상 생성
- [ ] Stage 4: PDF 리포트 생성 및 method file 내보내기

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

### 7.3 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| 1.0 | 2025-09-01 | 초기 버전 (단일 최적화) |
| 2.0 | 2025-10-13 | 4-Stage 아키텍처로 재설계 |
