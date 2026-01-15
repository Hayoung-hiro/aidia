# diaoptimizer 패키지 - 함수 분류 명세

## 개요

| 항목 | 값 |
|------|-----|
| **총 함수** | 119개 |
| **내보내기 (Export)** | 15개 |
| **내부 함수** | 104개 |
| **S3 클래스** | 4개 |

---

## Tier 1: 내보내기 함수 (Export)

사용자가 직접 호출하는 함수들. 문서화 + 예제 필수.

### 파이프라인 메인 함수

```r
# main.R
run_complete_pipeline()       # 전체 파이프라인 실행

# Stage 1
create_validated_dataset()    # DIA-NN 데이터 로드 및 검증

# Stage 2
plan_optimization()           # 최적화 계획 수립

# Stage 3
optimize_windows()            # 윈도우 최적화 실행

# Stage 4
generate_visualizations()     # 시각화 생성
```

### Instrument 관리

```r
get_instrument_config()       # Instrument 설정 조회
list_available_instruments()  # 사용 가능한 Instrument 목록
```

### 데이터 접근

```r
get_precursor_data()          # ValidatedData에서 precursor 추출
get_fwhm_values()             # FWHM 값 추출
calculate_dppp()              # DPPP 계산
```

### 내보내기

```r
export_windows_to_csv()       # CSV 메서드 파일 내보내기
export_method_files()         # 다중 전략 일괄 내보내기
create_pdf_report()           # PDF 리포트 생성
```

---

## Tier 2: S3 클래스 및 메서드

### 클래스 정의

| 클래스 | 용도 | Stage |
|--------|------|-------|
| `ValidatedData` | 검증된 DIA-NN 데이터 | Stage 1 출력 |
| `OptimizationPlan` | 최적화 계획 | Stage 2 출력 |
| `OptimizedWindows` | 최적화된 윈도우 | Stage 3 출력 |
| `VisualizationResult` | 시각화 결과 | Stage 4 출력 |

### S3 메서드 (자동 내보내기)

```r
# 생성자 (내부용이지만 S3 시스템상 필요)
new_ValidatedData()
new_OptimizationPlan()
new_OptimizedWindows()
new_VisualizationResult()

# 타입 검사 (내보내기 권장)
is_ValidatedData()
is_OptimizationPlan()
is_OptimizedWindows()
is_VisualizationResult()

# print 메서드 (추가 필요!)
print.ValidatedData()         # 현재 없음 → 추가 필요
print.OptimizationPlan()      # 현재 없음 → 추가 필요
print.OptimizedWindows()      # 현재 없음 → 추가 필요

# summary 메서드 (추가 필요!)
summary.ValidatedData()       # 현재 없음 → 추가 필요
```

---

## Tier 3: 내부 함수 (Internal)

문서화하지만 내보내지 않음. `@keywords internal` 태그 사용.

### 이미 `_internal` 접미사 있음 (유지)

```r
calculate_cycle_time_internal()
calculate_required_cycle_time_internal()
calculate_window_count_internal()
diagnose_dppp_internal()
optimize_mz_ranges_internal()
optimize_mz_ranges_smoothing_internal()
generate_fixed_windows_internal()
generate_variable_windows_internal()
generate_windows_internal()
perform_rt_binning_internal()
apply_overlap_internal()
calculate_window_statistics_internal()
```

### 내부 함수 (접미사 없음, 유지 가능)

```r
# 로딩 함수
load_diann_data()
load_diann_data_simple()
load_and_filter_data()
load_instruments_config()
load_optional_raw_metadata()

# 검증 함수
validate_data()
validate_data_quality()
validate_input_parameters()
validate_input_type()
validate_numeric_range()
validate_positive_integer()
validate_required_columns()
validate_essential_columns()
validate_instrument_config()
validate_rt_values()
validate_mz_values()

# 유틸리티
calculate_cv()
calculate_summary_stats()
calculate_quality_score()
calculate_fwhm_stats()
calculate_effective_scan_rate()
calculate_satisfaction_ratio()
calculate_precursors_per_window()
```

### Print 유틸리티 (내부용 명확화 권장)

```r
# 현재
print_header()
print_step()
print_success()
print_warning()
print_info()

# 권장: 내부 함수 표시 (선택사항)
.print_header()   # 또는 유지 (충돌 위험 낮음)
```

---

## Tier 4: Plot 함수

Stage 4에서만 사용. 기본적으로 내부 함수이나, 고급 사용자를 위해 일부 내보내기 고려.

### 핵심 플롯 (내보내기 고려)

```r
plot_dppp_comparison()        # DPPP 비교 플롯
plot_rt_mz_density_heatmap()  # 밀도 히트맵
plot_satisfaction_curve()     # 만족도 곡선
```

### 상세 플롯 (내부용)

```r
plot_dppp_comparison_enhanced()
plot_rt_histogram()
plot_rt_histogram_binned()
plot_mz_normalized_density()
plot_density_with_mz_range()
plot_density_with_mz_ranges_grid()
plot_mz_range_optimization()
plot_mz_width_comparison()
plot_mz_width_comparison_all_strategies()
plot_mz_distribution_with_exclusions()
plot_window_width_distribution()
plot_window_width_distribution_faceted()
plot_cumulative_window_count()
plot_strategy_width_ridge()
plot_strategy_width_boxplot()
plot_strategy_width_cdf()
plot_strategy_width_comparison_combined()
plot_mz_window_width()
```

---

## 함수명 변경 권장사항

### 필수 변경 (0개)
현재 함수명들이 이미 적절함. 필수 변경 사항 없음.

### 권장 변경 (선택사항)

| 현재 | 권장 | 이유 |
|------|------|------|
| `list_available_instruments()` | `list_instruments()` | 간결화 |
| `create_pdf_report()` | `export_pdf_report()` | 일관성 (export_*) |

### 유지 (변경 불필요)

- `*_internal` 함수들: 이미 적절한 명명
- S3 관련 함수들: 규칙 준수
- `calculate_*`: 일관성 있음
- `validate_*`: 일관성 있음
- `plot_*`: 일관성 있음

---

## NAMESPACE 설정 (roxygen2)

```r
# 내보내기 함수에 추가
#' @export
create_validated_dataset <- function(...) { }

# 내부 함수에 추가
#' @keywords internal
load_diann_data <- function(...) { }

# S3 메서드 등록
#' @export
print.ValidatedData <- function(x, ...) { }
```

---

## 파일 구조 (패키지화 후)

```
diaoptimizer/
├── DESCRIPTION
├── NAMESPACE              # roxygen2 자동 생성
├── LICENSE
├── R/
│   ├── diaoptimizer-package.R  # 패키지 문서
│   ├── utils_common.R
│   ├── instrument_utils.R
│   ├── s3_classes.R
│   ├── stage1_data_validation.R
│   ├── stage2_optimization_planning.R
│   ├── stage3_window_optimization.R
│   ├── stage3/                 # 모듈 유지
│   ├── stage4_visualization.R
│   ├── stage4_export.R
│   ├── plots/                  # 플롯 모듈 유지
│   └── plot*.R                 # 개별 플롯
├── man/                   # roxygen2 자동 생성
├── inst/
│   └── config/
│       └── instruments.json
├── tests/
│   └── testthat/
└── vignettes/             # 사용 가이드
```

---

## 체크리스트

### 패키지화 전 필수
- [x] deprecated 파일 분리 완료
- [ ] S3 print/summary 메서드 추가
- [ ] roxygen2 문서 완성
- [ ] NAMESPACE 설정

### 패키지화 후
- [ ] R CMD check 통과
- [ ] 테스트 커버리지 확보
- [ ] vignette 작성
- [ ] GitHub 배포

---

**문서 버전**: 1.0
**최종 수정**: 2025-01-14
