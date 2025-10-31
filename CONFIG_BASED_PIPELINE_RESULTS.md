# Config-Based Pipeline Execution Results

**실행 일시**: 2025-10-31
**설정 파일**: [config/optimization_config.json](config/optimization_config.json)
**출력 디렉토리**: `results_fusion_lumos_min10_sat70_json/`

---

## 📋 실행 설정

### 입력 데이터
- **파일**: `data/30min_report.parquet`
- **사용자 지정 Cycle Time**: **1.2초** (config에서 명시)
- **Raw 전처리**: 22,047 precursors (23,379 → 94.3% 유지율)

### 분석 파라미터
- **Instrument**: Thermo Fusion Lumos (20 Hz, sequential acquisition)
- **Target DPPP**: 7.0 (Quant mode)
- **Target Satisfaction**: 70%
- **RT Binning**: 5분 단위 (총 2개 bins)
- **m/z Strategies**: quantile, smoothing, outlier, coverage
- **Window Modes**: fixed, variable

---

## 🎯 Stage 2: DPPP 진단 결과

### 현재 실험 상태 (Cycle Time = 1.2초)

| 항목 | 값 | 설명 |
|------|-----|------|
| **현재 DPPP** | 7.72 ± 2.09 | 중앙값: 6.98 |
| **현재 만족도** | **46.9%** | 10,335 / 22,047 precursors |
| **목표 만족도** | 70% | Config에서 설정 |
| **권장 Cycle Time** | ≤ 1.18초 | 0.02초 감소 필요 (1.7%) |
| **결정된 Window 수** | **17개/RT bin** | 총 34개 windows (2 RT bins) |

### Feasibility 검증

| 검증 항목 | 결과 | 상세 |
|----------|------|------|
| ✅ Cycle time check | **PASS** | 실제 0.900초 ≤ 권장 1.180초 |
| ✅ Scan rate check | **PASS** | 18 scans ≤ 23 max |
| ✅ Window range check | **PASS** | 17 ≤ 300 max |

**결론**: 목표 만족도 70% 달성 가능 ✅

---

## 🪟 Stage 3: Window Optimization 결과

### 전략 비교표 (8가지 조합)

| Strategy | Mode | Windows | Coverage | Width (Da) | CV_Precursors | 특징 |
|----------|------|---------|----------|------------|---------------|------|
| **quantile** | fixed | 34 | 90.0% | 26.43±0.28 | 0.406 | 균일한 폭 |
| **quantile** | variable | 34 | 90.0% | 26.43±8.83 | 0.297 | ✅ **균일 density** |
| **smoothing** | fixed | 34 | 90.0% | 26.43±0.28 | 0.406 | 균일한 폭 |
| **smoothing** | variable | 34 | 90.0% | 26.43±8.83 | 0.297 | ✅ **균일 density** |
| **outlier** | fixed | 34 | 100.0% | 35.24±0.10 | 0.554 | 최대 coverage |
| **outlier** | variable | 32 | 94.1% | 30.48±11.76 | 0.297 | ✅ **균일 density** |
| **coverage** | fixed | 34 | 95.0% | 28.85±0.34 | 0.407 | Balanced |
| **coverage** | variable | 34 | 95.0% | 28.85±10.41 | 0.297 | ✅ **균일 density** |

---

## 📊 주요 발견사항

### 1. Variable Mode의 우수성

**Variable mode가 모든 전략에서 CV_Precursors를 ~0.30으로 균일화**:
- Fixed mode: CV 0.406-0.554 (불균일한 precursor 분포)
- Variable mode: CV ~0.297 (균일한 precursor 분포) ✅

**장점**:
- 각 window가 비슷한 수의 precursor를 포함 → 균형잡힌 데이터 수집
- MS2 스캔 시간 활용 최적화
- 정량 정확도 향상

### 2. 전략별 특성

#### 📌 Quantile & Smoothing (동일 결과)
- **Coverage**: 90.0%
- **Width**: 26.43 Da (가장 좁음)
- **장점**: 좁은 isolation window → 높은 spectral quality
- **단점**: 5% 및 95% quantile로 precursor 10% 손실
- **추천**: 높은 spectral quality가 중요한 경우

#### 📌 Outlier
- **Coverage**: 100.0% (fixed) / 94.1% (variable)
- **Width**: 35.24 Da (fixed) / 30.48 Da (variable)
- **장점**: 최대 coverage (fixed mode에서 100%)
- **단점**: 넓은 window → fragment 간섭 가능성 증가
- **추천**: Discovery proteomics, 최대 ID 수

#### 📌 Coverage (Balanced)
- **Coverage**: 95.0%
- **Width**: 28.85 Da
- **장점**: Quantile과 Outlier의 중간
- **추천**: 대부분의 실험 (균형잡힌 선택) ⭐

---

## 🎯 최종 추천

### 🥇 최우선 추천: **Coverage + Variable**

**파일**: `30min_coverage_variable_thermo.csv`

**이유**:
- ✅ 95% coverage (충분한 ID)
- ✅ 28.85 Da width (적절한 spectral quality)
- ✅ CV 0.297 (균일한 precursor 분포)
- ✅ 34 windows (실현 가능)
- ✅ 균형잡힌 접근법

### 🥈 대안 1: **Quantile + Variable** (높은 Spectral Quality)

**파일**: `30min_quantile_variable_thermo.csv`

**이유**:
- 26.43 Da (가장 좁은 window → 최고 spectral quality)
- 90% coverage (약간 낮지만 충분)
- 정량 정확도 최우선 시

### 🥉 대안 2: **Outlier + Fixed** (최대 Coverage)

**파일**: `30min_outlier_fixed_thermo.csv`

**이유**:
- 100% coverage (모든 precursor 포함)
- 35.24 Da (약간 넓지만 허용 가능)
- Discovery proteomics용

---

## 📁 생성된 파일 구조

```
results_fusion_lumos_min10_sat70_json/
├── 30min_quantile_fixed_thermo.csv       (4.5 KB)
├── 30min_quantile_variable_thermo.csv    (4.7 KB) ⭐
├── 30min_smoothing_fixed_thermo.csv      (4.6 KB)
├── 30min_smoothing_variable_thermo.csv   (4.7 KB) ⭐
├── 30min_outlier_fixed_thermo.csv        (4.5 KB)
├── 30min_outlier_variable_thermo.csv     (4.4 KB) ⭐
├── 30min_coverage_fixed_thermo.csv       (4.6 KB)
├── 30min_coverage_variable_thermo.csv    (4.7 KB) ⭐⭐⭐ 최우선 추천
└── batch_processing_summary.csv          (917 bytes)
```

---

## 🔧 Method 파일 포맷 (Thermo 22-column)

각 CSV 파일은 Thermo Orbitrap 표준 22-column 포맷으로 생성됨:

### 필수 컬럼 (Thermo Instrument Method 호환)
1. `Compound`, `Formula`, `Adduct` (DIA에서는 비어있음)
2. `m/z`, `z` (중심 m/z 및 charge state)
3. `t start (min)`, `t stop (min)` (RT window)
4. `Isolation Window (m/z)` (isolation width)
5. `Normalized AGC Target (%)` (100%)
6. `Start (m/z)`, `End (m/z)` (m/z window 범위)

### 추가 정보 컬럼
7. `Window_ID` (1-34)
8. `RT_Segment_ID` (1-2, RT bin)
9. `RT_Center`, `RT_Width` (RT 정보)
10. `N_Precursors` (window 내 precursor 수)
11. `Overlap_Prev`, `Overlap_Next` (인접 window와 겹침)
12. `Instrument` ("Thermo Fusion Lumos")
13. `Generation_Method` (예: "coverage_variable")
14. `Window_Type` ("fixed" or "variable")
15. **`Recommended_Cycle_Time_Sec` (1.2초)** ⭐ 중요!

---

## 📈 성능 지표

### 처리 시간
- **Stage 1 (Data Validation)**: 0.84초
- **Stage 2 (Optimization Planning)**: 0.09초
- **Stage 3 (Window Optimization)**: 0.08-0.31초 per combination
- **총 처리 시간**: ~3초 (8개 조합)

### 데이터 품질
- **전처리 유지율**: 94.3% (23,379 → 22,047)
- **Coverage 범위**: 90.0% - 100.0%
- **Window 수**: 32-34개 (RT bin 당 17개 목표)

---

## 🚀 다음 단계

### 1. Method 파일 업로드
1. **추천 파일 선택**: `30min_coverage_variable_thermo.csv`
2. **Thermo Orbitrap에 업로드**
3. **Cycle time 확인**: 1.18초 이하로 설정
4. **실험 수행**

### 2. 실험 조건 확인
- MS1 scan: 1회/cycle
- MS2 scans: 34회/cycle (17개 windows × 2 RT bins)
- AGC target: 100% normalized
- Isolation width: variable (26-35 Da depending on strategy)

### 3. 결과 검증
- DIA-NN으로 데이터 처리
- DPPP 분포 확인 (목표: 7.0 ± tolerance)
- Satisfaction ratio 확인 (목표: ≥70%)
- 필요시 재최적화

---

## 🔍 Config 기반 파이프라인의 장점

### ✅ 재현성
- 동일한 JSON 파일 → 동일한 결과
- 모든 파라미터 문서화
- 버전 관리 가능

### ✅ 유연성
- 파라미터 변경 용이
- 다양한 조건 테스트
- Batch processing 지원

### ✅ 추적성
- 실험 조건 명확히 기록
- Cycle time 사용자 지정 가능
- 전략별 비교 용이

---

## 📚 참고 문서

- [config/optimization_config.json](config/optimization_config.json) - 사용된 설정
- [run_with_config.R](run_with_config.R) - 파이프라인 코드
- [CURRENT_CYCLE_TIME_FEATURE.md](CURRENT_CYCLE_TIME_FEATURE.md) - Cycle time 기능 설명
- [DEVELOPMENT.md](DEVELOPMENT.md) - 전체 프로젝트 문서

---

**생성 일시**: 2025-10-31 19:34 KST
**Pipeline Version**: 4.0
**Status**: ✅ 성공적으로 완료
