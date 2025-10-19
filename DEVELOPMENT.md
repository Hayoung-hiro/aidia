# DIA Window Optimizer - Development Guide

**Version**: 2.0 (4-Stage Architecture)
**Last Updated**: 2025-10-13
**Status**: Active Development

---

## 📋 목차

1. [프로젝트 개요](#프로젝트-개요)
2. [아키텍처 개요](#아키텍처-개요)
3. [개발 단계 (Phases)](#개발-단계-phases)
4. [독립 개발 가이드](#독립-개발-가이드)
5. [문서 구조](#문서-구조)
6. [진행 상황](#진행-상황)

---

## 프로젝트 개요

### 목적
DIA-NN 결과를 기반으로 Thermo Orbitrap 계열 질량분석기를 위한 **최적화된 isolation window method**를 생성하는 도구

### 핵심 철학
- **진단 우선**: 현재 상태 분석 후 다음 실험 계획 지원
- **사용자 중심**: DPPP 7.0 (Quant 모드)를 기본값으로 하되, ID 모드(1.5) 지원
- **모듈화**: 각 단계를 독립적으로 개발/테스트 가능
- **실측 데이터 활용**: Raw file의 실제 injection time 반영 (선택)

### 주요 변경사항 (v2.0)
- ✅ **4-Stage Pipeline**: Data Validation → DPPP Diagnosis → Window Optimization → Visualization
- ✅ **DPPP Diagnosis 추가**: 현재 상태 진단 및 scan_time 추천
- ✅ **다양한 m/z Range 전략**: Quantile, Smoothing, Outlier removal, Coverage-based
- ✅ **3가지 Window Generation 모드**: Fixed, Overlapped, Variable
- ✅ **Raw file 기반 Injection Time 조정**: 실측 IT 기반 maxIT 추천

---

## 아키텍처 개요

### 전체 파이프라인

```
┌─────────────────────────────────────────────────────────────┐
│                    4-Stage Pipeline                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  [Stage 1] Data Validation                                  │
│      Input: DIA-NN output (+ Raw files, optional)          │
│      Output: Validated dataset + metadata                   │
│      ↓                                                       │
│  [Stage 2] DPPP Diagnosis                                   │
│      Input: Validated data + user scan_time                │
│      Output: Current status + recommended scan_time         │
│      ↓                                                       │
│  [Stage 3] Window Optimization                              │
│      ├─ [3A] Window Count Determination                    │
│      ├─ [3B] RT Binning                                    │
│      ├─ [3C] m/z Range Optimization                        │
│      └─ [3D] Window Generation                             │
│      Output: Optimized isolation windows                    │
│      ↓                                                       │
│  [Stage 4] Visualization & Reporting                        │
│      Input: All previous outputs                            │
│      Output: Plots + PDF report + method file              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 모듈 구조

```
R/
├── stage1_data_validation.R          [Phase 1]
│   ├── load_diann_data()
│   ├── load_raw_metadata()
│   ├── validate_required_columns()
│   ├── validate_data_quality()
│   └── create_validated_dataset()
│
├── stage2_dppp_diagnosis.R            [Phase 2]
│   ├── calculate_current_dppp_distribution()
│   ├── compute_satisfaction_ratio()
│   ├── recommend_scan_time()
│   ├── check_instrument_feasibility()
│   └── generate_diagnosis_report()
│
├── stage3_window_optimization.R
│   ├── module3a_window_count.R        [Phase 3A]
│   │   ├── calculate_window_count_from_scantime()
│   │   ├── check_scan_rate_feasibility()
│   │   └── adjust_for_injection_time()
│   │
│   ├── module3b_rt_binning.R          [Phase 3B] ✅ 기존 활용
│   │   └── (rt_segmentation.R 활용)
│   │
│   ├── module3c_mz_range_optimization.R [Phase 3C]
│   │   ├── optimize_range_quantile()
│   │   ├── optimize_range_smoothing()
│   │   ├── optimize_range_outlier_removal()
│   │   ├── optimize_range_coverage_based()
│   │   └── compare_range_strategies()
│   │
│   └── module3d_window_generation.R   [Phase 3D]
│       ├── generate_fixed_windows()
│       ├── generate_overlapped_windows()
│       └── generate_variable_windows()
│
└── stage4_visualization.R             [Phase 4]
    ├── plot_dppp_density()
    ├── plot_rt_window_size()
    ├── plot_rt_mz_density_heatmap()
    ├── plot_mz_normalized_density()
    ├── plot_mz_window_width()
    ├── plot_precursor_coverage_map()
    ├── plot_window_efficiency()
    ├── plot_dppp_achievement_heatmap()
    └── generate_comprehensive_report()
```

---

## 개발 단계 (Phases)

### Phase 1: Data Validation ✅ 우선순위 1
**파일**: `R/stage1_data_validation.R`
**상태**: ✅ **완료 (2025-10-15)**
**담당자**: Claude + User
**실제 소요**: 1주 (Phase 2와 함께)

**주요 작업**:
- ✅ DIA-NN output 로딩 (Parquet/TSV/CSV)
- ✅ 필수 컬럼 검증 (RT.Start, Precursor.Mz, FWHM)
- ✅ 데이터 품질 검사 (outlier, 범위 확인)
- ✅ ValidatedData 객체 생성 및 metadata 구성

**검증 결과** (test_phase1_2_simple.R):
- report.parquet 로딩 성공 (7,560 precursors after filtering) ✓
- RT range 10.00-109.92 min, m/z range 400.19-599.99 Da ✓
- FWHM statistics: median 0.20 sec (11.76 sec) ✓
- Quality score: 0.98 (excellent) ✓

**상세 문서**: [docs/phases/PHASE1_DATA_VALIDATION.md](docs/phases/PHASE1_DATA_VALIDATION.md)

---

### Phase 2: DPPP Diagnosis ✅ 우선순위 2
**파일**: `R/stage2_dppp_diagnosis.R`
**상태**: ✅ **완료 (2025-10-15)**
**담당자**: Claude + User
**실제 소요**: 1주 (논의 및 수정 포함)

**주요 작업**:
- ✅ 현재 DPPP distribution 계산
- ✅ Satisfaction ratio 계산 (>= target only, corrected)
- ✅ 최적 cycle_time 추천 (quantile corrected)
- ✅ 실제 데이터 검증 (report.parquet, RT 10-110, m/z 400-600)

**주요 수정 사항**:
- ✅ **Scan rate 공식 수정**: `n_windows / cycle_time` (was: `1 / cycle_time`)
- ✅ **Quantile 방향 수정**: `1 - target_satisfaction` (70% → 30th percentile)
- ✅ **Satisfaction 로직 수정**: `dppp >= target` (no upper limit)
- ✅ **Safety margin 추가**: 80% scan rate 제한
- ✅ **Scope 간소화**: Window count/feasibility는 Phase 3A로 이관

**검증 결과** (test_phase1_2_simple.R):
- Current cycle_time = 2.0 sec → 100% satisfaction at DPPP ≥7.5 ✓
- Required cycle_time = 2.480 sec for 70% satisfaction @ DPPP 7.5 ✓
- Recommendation: Can INCREASE cycle time by +0.48 sec (+24%) for better quality ✓
- Mean DPPP: 12.29, Median DPPP: 10.00 ✓
- API: Uses `current_cycle_time` (accurate naming) ✓

**상세 문서**:
- [docs/phases/PHASE2_DPPP_DIAGNOSIS.md](docs/phases/PHASE2_DPPP_DIAGNOSIS.md)
- [docs/DOMAIN_CONCEPTS.md](docs/DOMAIN_CONCEPTS.md) (corrected logic)

---

### Phase 3A: Window Count Determination ✅ 우선순위 3
**파일**: `R/stage3_window_optimization/module3a_window_count.R`
**상태**: ✅ **완료 (2025-10-16 Refactored)**
**담당자**: Claude + User
**실제 소요**: 1일 (complete refactoring)

**주요 작업**:
- ✅ 3-level configuration architecture (static/module/dynamic)
- ✅ Terminology unification (cycle_calculation: parallel/sequential)
- ✅ 3-mode override logic (optimize/NULL/user-specified)
- ✅ Slack-based maxIT optimization (signal quality improvement)
- ✅ Load factor system (0.8 default, user customizable)
- ✅ ms1_scans as user parameter (0=parallel, 1+=sequential)

**검증 결과** (test_module3a_integration.R):
- Parallel (Astral): 160 windows (ms1_scans=0) ✓
- Sequential (Orbitrap): 27 windows (ms1_scans=1) + maxIT +50ms ✓
- 3-mode override: optimize, NULL, user-specified all working ✓
- MaxIT optimization: Auto-increase from 50ms→100ms when slack ≥0.5s ✓
- Output structure: 3 new sections added (window_count_mode, scan_rate_settings, maxIT_optimization) ✓

**상세 문서**: [docs/phases/PHASE3A_WINDOW_COUNT.md](docs/phases/PHASE3A_WINDOW_COUNT.md)

---

### Phase 3B: RT Binning ✅ 기존 활용
**파일**: `R/rt_segmentation.R` (기존)
**상태**: ✅ 완료 (기존 코드 활용)
**담당자**: -
**예상 기간**: 1일 (검증 및 통합만)

**주요 작업**:
- 기존 `segment_rt_by_time_unit()` 활용
- Phase 3A와 통합 테스트

**상세 문서**: [docs/phases/PHASE3B_RT_BINNING.md](docs/phases/PHASE3B_RT_BINNING.md)

---

### Phase 3C: m/z Range Optimization ✅ 우선순위 4
**파일**: `R/stage3_window_optimization/module3c_mz_range_optimization.R`
**상태**: ✅ **완료 (2025-10-17)**
**담당자**: Claude+User
**실제 소요**: 2일

**주요 작업**:
- ✅ 4가지 전략 구현 (Quantile, Smoothing, Outlier removal, Coverage-based)
- ✅ DynamicDIA smoothing 통합 (Savitzky-Golay, Moving Average, Gaussian)
- ✅ Continuous RT-based smoothing 추가
- ✅ 전략 비교 기능 (compare_strategies = TRUE)

**검증 결과**:
- Quantile strategy: P5-P95 범위 계산 ✓
- Smoothing strategy: RT-dependent boundary smoothing ✓
- Outlier removal: 3-sigma 기반 outlier 제거 ✓
- Coverage-based: Target coverage 달성 최소 범위 ✓

**상세 문서**: [docs/phases/PHASE3C_MZ_RANGE.md](docs/phases/PHASE3C_MZ_RANGE.md)

---

### Phase 3D: Window Generation ✅ 우선순위 5
**파일**: `R/stage3_window_optimization/module3d_window_generation.R`
**상태**: ✅ **완료 (2025-10-17)**
**담당자**: Claude+User
**실제 소요**: 2일

**주요 작업**:
- ✅ Fixed window 생성 (equal-width per RT bin)
- ✅ Variable window 생성 (density-based quantile per RT bin)
- ✅ Overlap 기능 (optional post-processing)
- ✅ Per-RT-bin architecture (n_bins × n_windows total windows)
- ✅ Min/Max width constraints 적용

**검증 결과**:
- Fixed method: Equal-width windows with constraints ✓
- Variable method: Quantile-based adaptive windows ✓
- Overlap: Percentage or fixed Da expansion ✓
- Per-bin generation: Independent window creation per RT segment ✓

**상세 문서**: [docs/phases/PHASE3D_WINDOW_GENERATION.md](docs/phases/PHASE3D_WINDOW_GENERATION.md)

---

### Phase 4: Visualization & Reporting ✅ 우선순위 6
**파일**: `R/stage4_visualization.R`
**상태**: 🟡 **진행중 (2025-10-18 시작)**
**담당자**: Claude+User
**예상 기간**: 3-4일

**주요 작업**:
- 🟡 8가지 필수 plot 생성 (scientific journal 수준)
- 🔴 PDF 리포트 생성
- 🔴 Method file 내보내기 (CSV for Thermo instruments)

**필수 Plot 목록**:
1. DPPP Density Distribution (현재 vs 목표)
2. RT-dependent Window Count Allocation
3. RT-mz Precursor Density Heatmap
4. m/z Normalized Density Profile
5. m/z Window Width Distribution
6. Precursor Coverage Map
7. Window Efficiency Analysis
8. DPPP Achievement Heatmap (RT × m/z)

**상세 문서**: [docs/phases/PHASE4_VISUALIZATION.md](docs/phases/PHASE4_VISUALIZATION.md)

---

## 독립 개발 가이드

### 다른 PC에서 특정 Phase만 개발하기

#### 1. 환경 설정

```r
# 필수 패키지 설치
install.packages(c("arrow", "dplyr", "ggplot2", "gridExtra",
                   "jsonlite", "tidyr", "viridis", "scales",
                   "prospectr", "testthat"))
```

#### 2. 개발 워크플로우

**예시: PC A에서 Phase 1, PC B에서 Phase 2 개발**

```bash
# PC A: Phase 1 개발
git clone <repository>
cd dia_window_optimizer
git checkout -b feature/phase1-data-validation

# Phase 1 개발
# - R/stage1_data_validation.R 작성
# - tests/test_stage1.R 작성
# - tests/fixtures/stage1_output.rds 생성 (다음 Phase용 Mock)

git add .
git commit -m "feat: Implement Phase 1 - Data Validation"
git push origin feature/phase1-data-validation

# ──────────────────────────────────────────────────────────

# PC B: Phase 2 개발 (Phase 1 완료 대기 없이 진행 가능)
git clone <repository>
cd dia_window_optimizer
git checkout -b feature/phase2-dppp-diagnosis

# Phase 1 Mock 데이터 사용
source("tests/mocks/mock_stage1_output.R")
validated_data <- create_mock_stage1_output()

# Phase 2 개발
# - R/stage2_dppp_diagnosis.R 작성
# - tests/test_stage2.R 작성
# - tests/fixtures/stage2_output.rds 생성

git add .
git commit -m "feat: Implement Phase 2 - DPPP Diagnosis"
git push origin feature/phase2-dppp-diagnosis
```

#### 3. Mock 데이터 사용

각 Phase별 Mock 데이터는 `tests/mocks/` 디렉토리에 제공됩니다:

```r
# Phase 2 개발 시 Phase 1 Mock 사용 예시
source("tests/mocks/mock_stage1_output.R")
validated_data <- create_mock_stage1_output()

# Phase 2 함수 개발
result <- calculate_current_dppp_distribution(
  validated_data,
  user_scan_time = 2.0
)
```

#### 4. 단위 테스트

각 Phase는 독립적으로 테스트 가능합니다:

```r
# tests/test_stage2.R
library(testthat)

test_that("DPPP satisfaction ratio calculation works", {
  mock_data <- create_mock_stage1_output()

  result <- compute_satisfaction_ratio(
    mock_data,
    target_dppp = 7.0,
    tolerance = 0.5
  )

  expect_true(result$satisfaction_ratio >= 0 && result$satisfaction_ratio <= 1)
  expect_equal(names(result), c("satisfaction_ratio", "n_satisfied", "n_total"))
})
```

#### 5. 통합 전 검증

Phase 개발 완료 후 통합 전 체크리스트:

- [ ] 단위 테스트 모두 통과
- [ ] Mock 데이터로 정상 실행 확인
- [ ] 입출력 스펙 문서화 완료 (API_SPECIFICATION.md)
- [ ] 다음 Phase용 fixture 데이터 생성 (tests/fixtures/)
- [ ] 코드 리뷰 완료

---

## 문서 구조

```
dia_window_optimizer/
├── DEVELOPMENT.md                    # 이 파일 - 개발 전체 가이드
├── CLAUDE.md                         # AI 어시스턴트용 프로젝트 가이드
├── README.md                         # 사용자용 프로젝트 소개
│
├── docs/
│   ├── PRD.md                        # 제품 요구사항 문서 (한글)
│   ├── ARCHITECTURE.md               # 시스템 아키텍처 상세 설계
│   ├── API_SPECIFICATION.md          # 모듈 입출력 스펙
│   │
│   └── phases/                       # Phase별 개발 가이드
│       ├── PHASE1_DATA_VALIDATION.md
│       ├── PHASE2_DPPP_DIAGNOSIS.md
│       ├── PHASE3A_WINDOW_COUNT.md
│       ├── PHASE3B_RT_BINNING.md
│       ├── PHASE3C_MZ_RANGE.md
│       ├── PHASE3D_WINDOW_GENERATION.md
│       └── PHASE4_VISUALIZATION.md
│
├── tests/
│   ├── fixtures/                     # Phase별 테스트 데이터
│   │   ├── stage1_output.rds
│   │   ├── stage2_output.rds
│   │   └── stage3_output.rds
│   │
│   └── mocks/                        # Mock 생성 함수
│       ├── mock_stage1_output.R
│       ├── mock_stage2_output.R
│       └── mock_stage3_output.R
│
└── R/
    ├── stage1_data_validation.R
    ├── stage2_dppp_diagnosis.R
    ├── stage3_window_optimization/
    │   ├── module3a_window_count.R
    │   ├── module3b_rt_binning.R       # 기존 rt_segmentation.R 활용
    │   ├── module3c_mz_range_optimization.R
    │   └── module3d_window_generation.R
    └── stage4_visualization.R
```

---

## 진행 상황

### 전체 진행률: 86%

| Phase | 상태 | 진행률 | 담당자 | 완료일 |
|-------|------|--------|--------|--------|
| Phase 1 | ✅ 완료 | 100% | Claude+User | 2025-10-15 |
| Phase 2 | ✅ 완료 | 100% | Claude+User | 2025-10-15 |
| Phase 3A | ✅ 완료 | 100% | Claude+User | 2025-10-16 |
| Phase 3B | ✅ 완료 | 100% | 기존 코드 | - |
| Phase 3C | ✅ 완료 | 100% | Claude+User | 2025-10-17 |
| Phase 3D | ✅ 완료 | 100% | Claude+User | 2025-10-17 |
| Phase 4 | 🟡 진행중 | 20% | Claude+User | - |
| 문서화 | 🟡 진행중 | 80% | - | - |

### 최근 업데이트

- **2025-10-18**: 🟡 **Phase 4 Visualization 개발 시작** - Scientific journal quality plots
  - 8 essential plots for comprehensive optimization analysis
  - ggplot2-based high-resolution figures
  - DEVELOPMENT.md updated with Phase 3C-D completion status
- **2025-10-17**: ✅ **Phase 3C & 3D 완료** - m/z Range Optimization + Window Generation
  - Phase 3C: 4 strategies (Quantile, Smoothing, Outlier, Coverage) + continuous smoothing
  - Phase 3D: Per-RT-bin architecture (Fixed/Variable/Overlap modes)
  - Total windows = n_bins × n_windows (e.g., 22 bins × 200 = 4,400 windows)
- **2025-10-16**: ✅ **Phase 3A Refactoring 완료** - Complete module redesign
  - 3-level config architecture: Static (instrument) / Module constants / Dynamic (user)
  - Terminology unified: `cycle_calculation = "parallel"/"sequential"`
  - 3-mode override logic: optimize/NULL/user-specified with detailed error messages
  - Slack-based maxIT optimization: Auto-increase MS2 maxIT when slack ≥ 0.5s
  - Load factor system: 0.8 default (80% utilization) with custom override
  - ms1_scans as user parameter: 0 for parallel, 1 for sequential
  - Integration tests: 6 test suites, all passing (Astral 160 windows, Orbitrap 27 windows)
  - Fixtures created: diagnosis_quant, diagnosis_id, diagnosis_orbitrap
  - Documentation updated: API_SPECIFICATION.md, PHASE3A_WINDOW_COUNT.md
- **2025-10-15**: ✅ **Phase 1 & 2 검증 완료** - test_phase1_2_simple.R 테스트 통과
  - Phase 1: 7,560 precursors, quality score 0.98
  - Phase 2: 100% satisfaction at DPPP 7.5, required cycle_time 2.480 sec calculated
  - API decision: `current_cycle_time` (accurate naming) ✓
  - Scope decision: Phase 2 = Diagnosis only (window optimization → Phase 3A) ✓
- **2025-10-15**: ✅ **DPPP 로직 수정 완료** - Scan rate, quantile, satisfaction 수정
- **2025-10-15**: 📖 **DOMAIN_CONCEPTS.md 생성** - 수정된 개념 문서화
- **2025-10-13**: 개발 문서 구조 생성 시작
- **2025-10-13**: 4-Stage 아키텍처 설계 완료

### 주요 교훈 (Lessons Learned)

#### DPPP Diagnosis의 반직관적 특성
1. **Higher DPPP requires SHORTER cycle time**
   - 직관: "더 많은 데이터 포인트 = 더 긴 시간 필요"
   - 실제: "DPPP = (1.7 × FWHM) / cycle_time" → 짧은 cycle이 높은 DPPP

2. **70% satisfaction → 30th percentile**
   - 직관: "70% 만족 = 70th percentile 사용"
   - 실제: "Short FWHM이 어려움 → 1-0.7 = 30th percentile이 critical FWHM"

3. **Scan rate = n_windows / cycle_time**
   - 착오: "Scan rate = 1 / cycle_time (cycle 빈도)"
   - 실제: "초당 MS2 scan 횟수 = 총 window 수 / cycle 시간"

4. **Target DPPP는 minimum threshold (no upper limit)**
   - 착오: "Target DPPP 7.5 ± tolerance 범위"
   - 실제: "DPPP >= 7.5면 모두 만족 (높을수록 좋음)"

---

## 참고 문서

- [제품 요구사항 문서 (PRD)](docs/PRD.md)
- [시스템 아키텍처](docs/ARCHITECTURE.md)
- [API 명세서](docs/API_SPECIFICATION.md)
- [Phase별 개발 가이드](docs/phases/)

---

## 연락처 및 지원

- **프로젝트 리포지토리**: [GitHub Repository]
- **이슈 트래킹**: [GitHub Issues]
- **문서 업데이트 요청**: [GitHub Pull Requests]
