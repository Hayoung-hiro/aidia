# API Specification
# DIA Window Optimizer v2.0

**버전**: 2.0.0
**최종 수정**: 2025-10-13

---

## 목차

1. [개요](#개요)
2. [데이터 타입 정의](#데이터-타입-정의)
3. [Stage 1: Data Validation](#stage-1-data-validation)
4. [Stage 2: DPPP Diagnosis](#stage-2-dppp-diagnosis)
5. [Stage 3: Window Optimization](#stage-3-window-optimization)
6. [Stage 4: Visualization](#stage-4-visualization)
7. [Mock 데이터 가이드](#mock-데이터-가이드)

---

## 개요

본 문서는 DIA Window Optimizer의 모든 공개 API에 대한 상세 명세를 제공합니다. 각 함수의 입력, 출력, 부작용(side effects), 오류 처리 방법을 정의합니다.

### 명명 규칙

- **함수명**: `snake_case` (예: `calculate_dppp_distribution`)
- **변수명**: `snake_case`
- **상수명**: `UPPER_CASE` (예: `PEAK_WIDTH_FACTOR`)
- **클래스**: `TitleCase` (R S3 클래스, 예: `Stage1Output`)

### 반환 타입 규칙

모든 Stage 함수는 다음 구조의 list를 반환합니다:

```r
list(
  data = ...,        # 주요 결과 데이터
  metadata = ...,    # 메타데이터 (통계, 설정 등)
  status = ...,      # 실행 상태
  warnings = ...,    # 경고 메시지
  errors = ...       # 오류 메시지 (있는 경우)
)
```

---

## 데이터 타입 정의

### ValidatedData (Stage 1 출력)

```r
#' @class ValidatedData
#' @description Stage 1에서 검증된 데이터셋
#'
#' @field data tibble
#'   - RT.Start: numeric (minutes)
#'   - RT.Stop: numeric (minutes) - optional
#'   - Precursor.Mz: numeric (Da)
#'   - FWHM: numeric (minutes)
#'   - Charge: integer - optional
#'   - [other columns preserved from input]
#'
#' @field metadata list
#'   - n_precursors: integer
#'   - rt_range: numeric vector c(min, max)
#'   - mz_range: numeric vector c(min, max)
#'   - fwhm_stats: list(mean, median, sd, q25, q75)
#'   - has_raw_metadata: logical
#'   - raw_metadata: list or NULL
#'
#' @field validation_status list
#'   - all_passed: logical
#'   - n_warnings: integer
#'   - n_errors: integer
#'   - warnings: character vector
#'   - errors: character vector
```

### DiagnosisResult (Stage 2 출력)

```r
#' @class DiagnosisResult
#' @description DPPP 진단 결과
#'
#' @field current_status list
#'   - user_scan_time: numeric (seconds)
#'   - mean_dppp: numeric
#'   - median_dppp: numeric
#'   - p25_dppp: numeric
#'   - p75_dppp: numeric
#'   - satisfaction_ratio: numeric (0-1)
#'   - n_satisfied: integer
#'   - n_total: integer
#'   - dppp_distribution: numeric vector
#'
#' @field recommendation list
#'   - optimal_scan_time: numeric (seconds)
#'   - expected_satisfaction: numeric (0-1)
#'   - expected_window_count: integer
#'   - improvement_pct: numeric
#'   - feasible: logical
#'
#' @field tradeoff_analysis tibble
#'   - scan_time: numeric
#'   - window_count: integer
#'   - satisfaction_ratio: numeric
#'   - scan_rate_hz: numeric
```

### OptimizedWindows (Stage 3 출력)

```r
#' @class OptimizedWindows
#' @description 최적화된 isolation windows
#'
#' @field windows tibble
#'   - window_id: integer
#'   - rt_bin: character
#'   - window_start: numeric (Da)
#'   - window_end: numeric (Da)
#'   - window_width: numeric (Da)
#'   - center_mz: numeric (Da)
#'   - n_precursors: integer
#'
#' @field statistics list
#'   - n_windows: integer
#'   - mean_width: numeric (Da)
#'   - sd_width: numeric (Da)
#'   - mean_precursors_per_window: numeric
#'   - cv_precursors: numeric
#'
#' @field generation_mode character
#'   One of: "fixed", "overlapped", "variable"
```

---

## Stage 1: Data Validation

### 1.1 load_diann_data()

DIA-NN output 파일을 로딩하고 기본 검증을 수행합니다.

#### 함수 시그니처

```r
load_diann_data <- function(
  proteome_file,
  rt_range = NULL,
  mz_range = NULL,
  required_columns = c("RT.Start", "Precursor.Mz", "FWHM")
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `proteome_file` | character | ✓ | - | DIA-NN output 파일 경로 (.parquet, .tsv, .csv) |
| `rt_range` | numeric[2] | ✗ | NULL | RT 필터링 범위 c(min, max) in minutes |
| `mz_range` | numeric[2] | ✗ | NULL | m/z 필터링 범위 c(min, max) in Da |
| `required_columns` | character[] | ✗ | c("RT.Start", "Precursor.Mz", "FWHM") | 필수 컬럼 목록 |

#### 반환값

```r
list(
  data = tibble(
    RT.Start = numeric(),
    Precursor.Mz = numeric(),
    FWHM = numeric(),
    ...  # other columns from input
  ),
  metadata = list(
    file_path = character(),
    file_format = character(),  # "parquet", "tsv", "csv"
    file_size_mb = numeric(),
    n_rows_original = integer(),
    n_rows_filtered = integer(),
    load_time_sec = numeric()
  ),
  status = list(
    success = logical(),
    message = character()
  )
)
```

#### 오류 처리

```r
# 파일 존재하지 않음
if (!file.exists(proteome_file)) {
  stop("File not found: ", proteome_file)
}

# 지원하지 않는 형식
if (!file_format %in% c("parquet", "tsv", "csv")) {
  stop("Unsupported file format. Use .parquet, .tsv, or .csv")
}

# 빈 파일
if (nrow(data) == 0) {
  stop("File is empty or contains no valid data")
}
```

#### 예제

```r
# Basic usage
result <- load_diann_data("report.parquet")

# With filters
result <- load_diann_data(
  "report.parquet",
  rt_range = c(10, 110),
  mz_range = c(380, 980)
)
```

---

### 1.2 load_raw_metadata()

Raw file에서 injection time 및 scan 메타데이터를 추출합니다 (선택적).

#### 함수 시그니처

```r
load_raw_metadata <- function(
  raw_file_dir,
  file_pattern = "\\.raw$"
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `raw_file_dir` | character | ✓ | - | Raw files 디렉토리 경로 |
| `file_pattern` | character | ✗ | "\\.raw$" | Raw file 패턴 (regex) |

#### 반환값

```r
list(
  injection_times = list(
    ms1 = numeric(),  # MS1 injection times (ms)
    ms2 = numeric()   # MS2 injection times (ms)
  ),
  statistics = list(
    median_it_ms1 = numeric(),
    median_it_ms2 = numeric(),
    mean_it_ms1 = numeric(),
    mean_it_ms2 = numeric(),
    it_efficiency_ms1 = numeric(),  # median_it / maxIT
    it_efficiency_ms2 = numeric()
  ),
  actual_cycle_time = numeric(),  # seconds
  n_scans = list(
    ms1 = integer(),
    ms2 = integer()
  )
)
```

#### 오류 처리

```r
# 디렉토리 존재하지 않음
if (!dir.exists(raw_file_dir)) {
  stop("Directory not found: ", raw_file_dir)
}

# Raw files 없음
raw_files <- list.files(raw_file_dir, pattern = file_pattern)
if (length(raw_files) == 0) {
  warning("No raw files found in: ", raw_file_dir)
  return(NULL)
}
```

---

### 1.3 validate_data_quality()

데이터 품질을 검증하고 outlier를 감지합니다.

#### 함수 시그니처

```r
validate_data_quality <- function(
  data,
  fwhm_outlier_iqr = 1.5,
  rt_outlier_iqr = 3.0,
  mz_valid_range = c(50, 5000)
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `data` | tibble | ✓ | - | load_diann_data() 출력 |
| `fwhm_outlier_iqr` | numeric | ✗ | 1.5 | FWHM outlier 감지 IQR 배수 |
| `rt_outlier_iqr` | numeric | ✗ | 3.0 | RT outlier 감지 IQR 배수 |
| `mz_valid_range` | numeric[2] | ✗ | c(50, 5000) | 유효한 m/z 범위 |

#### 반환값

```r
list(
  fwhm_outliers = list(
    indices = integer(),  # outlier row indices
    values = numeric(),   # outlier FWHM values
    n_outliers = integer(),
    pct_outliers = numeric()
  ),
  rt_issues = list(
    out_of_range = integer(),  # RT < 0 or RT > expected
    non_monotonic = logical()  # RT not increasing
  ),
  mz_issues = list(
    out_of_range = integer(),  # m/z outside valid_range
    n_invalid = integer()
  ),
  quality_score = numeric(),  # 0-1, overall quality
  recommendations = character()  # quality improvement suggestions
)
```

#### Quality Score 계산

```r
quality_score = 1.0 -
  (0.4 * fwhm_outlier_rate +
   0.3 * rt_issue_rate +
   0.3 * mz_issue_rate)
```

---

### 1.4 create_validated_dataset()

모든 검증을 수행하고 ValidatedData 객체를 생성합니다 (Stage 1 메인 함수).

#### 함수 시그니처

```r
create_validated_dataset <- function(
  proteome_file,
  raw_file_dir = NULL,
  rt_range = NULL,
  mz_range = NULL,
  enable_raw_metadata = FALSE,
  quality_threshold = 0.8
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `proteome_file` | character | ✓ | - | DIA-NN output 경로 |
| `raw_file_dir` | character | ✗ | NULL | Raw files 디렉토리 |
| `rt_range` | numeric[2] | ✗ | NULL | RT 필터링 범위 |
| `mz_range` | numeric[2] | ✗ | NULL | m/z 필터링 범위 |
| `enable_raw_metadata` | logical | ✗ | FALSE | Raw metadata 추출 여부 |
| `quality_threshold` | numeric | ✗ | 0.8 | 최소 품질 점수 (0-1) |

#### 반환값 (ValidatedData)

```r
structure(
  list(
    data = tibble(...),
    metadata = list(
      n_precursors = integer(),
      rt_range = numeric(2),
      mz_range = numeric(2),
      fwhm_stats = list(...),
      has_raw_metadata = logical(),
      raw_metadata = list() or NULL
    ),
    validation_status = list(
      all_passed = logical(),
      quality_score = numeric(),
      n_warnings = integer(),
      n_errors = integer(),
      warnings = character(),
      errors = character()
    )
  ),
  class = c("ValidatedData", "list")
)
```

#### 오류 처리

```r
# 품질 점수 임계값 미달
if (quality_score < quality_threshold) {
  warning(sprintf(
    "Data quality score (%.2f) below threshold (%.2f)",
    quality_score, quality_threshold
  ))
}

# 치명적 오류
if (n_errors > 0) {
  stop("Data validation failed with errors:\n",
       paste(errors, collapse = "\n"))
}
```

#### 예제

```r
# Basic validation
validated <- create_validated_dataset("report.parquet")

# With raw metadata
validated <- create_validated_dataset(
  proteome_file = "report.parquet",
  raw_file_dir = "rawfiles/",
  enable_raw_metadata = TRUE
)

# Access data
precursor_data <- validated$data
n_precursors <- validated$metadata$n_precursors
```

---

## Stage 2: DPPP Diagnosis

### 2.1 calculate_current_dppp_distribution()

현재 scan_time으로 DPPP 분포를 계산합니다.

#### 함수 시그니처

```r
calculate_current_dppp_distribution <- function(
  validated_data,
  user_scan_time,
  instrument_config
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `validated_data` | ValidatedData | ✓ | - | Stage 1 출력 |
| `user_scan_time` | numeric | ✓ | - | 사용자 현재 scan time (초) |
| `instrument_config` | list | ✓ | - | Instrument configuration |

#### Instrument Config 구조

```r
instrument_config = list(
  name = "astral",
  ms1_time = 5.0,        # ms
  ms2_time = 3.0,        # ms
  max_scan_rate = 200,   # Hz
  optimal_scan_rate = 100, # Hz
  cycle_calculation = "parallel"  # or "sequential"
)
```

#### 반환값

```r
list(
  dppp_distribution = numeric(),  # length = n_precursors
  statistics = list(
    mean = numeric(),
    median = numeric(),
    sd = numeric(),
    p25 = numeric(),
    p50 = numeric(),
    p75 = numeric(),
    min = numeric(),
    max = numeric()
  ),
  by_rt_bin = tibble(
    rt_bin = character(),
    mean_dppp = numeric(),
    median_dppp = numeric(),
    n_precursors = integer()
  ),
  by_mz_bin = tibble(
    mz_bin = character(),
    mean_dppp = numeric(),
    median_dppp = numeric(),
    n_precursors = integer()
  )
)
```

#### DPPP 계산 공식

```r
PEAK_WIDTH_FACTOR <- 1.7  # Spectronaut standard

calculate_dppp <- function(fwhm_minutes, cycle_time_seconds) {
  fwhm_seconds <- fwhm_minutes * 60
  peak_width_seconds <- fwhm_seconds * PEAK_WIDTH_FACTOR
  dppp <- peak_width_seconds / cycle_time_seconds
  return(dppp)
}
```

---

### 2.2 compute_satisfaction_ratio()

Target DPPP ± tolerance 범위 내 전구체 비율을 계산합니다.

#### 함수 시그니처

```r
compute_satisfaction_ratio <- function(
  dppp_distribution,
  target_dppp = 7.0,
  dppp_tolerance = 0.5
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `dppp_distribution` | numeric | ✓ | - | DPPP 값 벡터 |
| `target_dppp` | numeric | ✗ | 7.0 | 목표 DPPP 값 |
| `dppp_tolerance` | numeric | ✗ | 0.5 | 허용 오차 (±) |

#### 반환값

```r
list(
  satisfaction_ratio = numeric(),  # 0-1
  n_satisfied = integer(),
  n_total = integer(),
  target_range = c(
    target_dppp - dppp_tolerance,
    target_dppp + dppp_tolerance
  ),
  distribution_summary = list(
    below_range = integer(),
    within_range = integer(),
    above_range = integer()
  )
)
```

#### 계산 로직

```r
lower_bound <- target_dppp - dppp_tolerance
upper_bound <- target_dppp + dppp_tolerance

satisfied <- dppp_distribution >= lower_bound &
             dppp_distribution <= upper_bound

satisfaction_ratio <- sum(satisfied) / length(dppp_distribution)
```

---

### 2.3 recommend_scan_time()

최적 scan_time을 추천합니다.

#### 함수 시그니처

```r
recommend_scan_time <- function(
  validated_data,
  target_dppp = 7.0,
  dppp_tolerance = 0.5,
  instrument_config,
  scan_time_range = c(1.0, 3.0),
  optimization_method = "grid"
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `validated_data` | ValidatedData | ✓ | - | Stage 1 출력 |
| `target_dppp` | numeric | ✗ | 7.0 | 목표 DPPP |
| `dppp_tolerance` | numeric | ✗ | 0.5 | 허용 오차 |
| `instrument_config` | list | ✓ | - | Instrument 설정 |
| `scan_time_range` | numeric[2] | ✗ | c(1.0, 3.0) | 탐색 범위 (초) |
| `optimization_method` | character | ✗ | "grid" | "grid" or "optimize" |

#### 반환값

```r
list(
  optimal_scan_time = numeric(),  # seconds
  expected_satisfaction = numeric(),  # 0-1
  expected_window_count = integer(),
  expected_scan_rate = numeric(),  # Hz
  improvement = list(
    current_satisfaction = numeric(),
    expected_satisfaction = numeric(),
    delta_pct = numeric()
  ),
  feasibility = list(
    feasible = logical(),
    scan_rate_ok = logical(),
    within_instrument_limits = logical()
  ),
  warnings = character()
)
```

#### Optimization 알고리즘

```r
# Grid search
if (optimization_method == "grid") {
  scan_times <- seq(scan_time_range[1], scan_time_range[2], by = 0.05)

  satisfaction_scores <- sapply(scan_times, function(st) {
    dppp_dist <- calculate_current_dppp_distribution(
      validated_data, st, instrument_config
    )
    compute_satisfaction_ratio(dppp_dist, target_dppp, dppp_tolerance)$satisfaction_ratio
  })

  optimal_idx <- which.max(satisfaction_scores)
  optimal_scan_time <- scan_times[optimal_idx]
}
```

---

### 2.4 generate_diagnosis_report()

종합 진단 보고서를 생성합니다 (Stage 2 메인 함수).

#### 함수 시그니처

```r
generate_diagnosis_report <- function(
  validated_data,
  user_scan_time,
  target_dppp = 7.0,
  dppp_tolerance = 0.5,
  instrument_config
)
```

#### 반환값 (DiagnosisResult)

```r
structure(
  list(
    current_status = list(
      user_scan_time = numeric(),
      mean_dppp = numeric(),
      median_dppp = numeric(),
      satisfaction_ratio = numeric(),
      dppp_distribution = numeric()
    ),
    recommendation = list(
      optimal_scan_time = numeric(),
      expected_satisfaction = numeric(),
      expected_window_count = integer(),
      improvement_pct = numeric(),
      feasible = logical()
    ),
    tradeoff_analysis = tibble(
      scan_time = numeric(),
      window_count = integer(),
      satisfaction_ratio = numeric(),
      scan_rate_hz = numeric()
    ),
    plots = list(
      dppp_distribution_plot = ggplot(),
      satisfaction_curve_plot = ggplot(),
      tradeoff_plot = ggplot()
    )
  ),
  class = c("DiagnosisResult", "list")
)
```

---

## Stage 3: Window Optimization

### WindowCountResult (Module 3A 출력)

```r
#' @class WindowCountResult
#' @description Module 3A (Window Count Determination) 출력
#'
#' @field window_count integer
#'   최종 결정된 window 개수
#'
#' @field target_cycle_time_sec numeric
#'   Phase 2에서 제공된 목표 cycle time (제약 조건)
#'
#' @field calculated_cycle_time_sec numeric
#'   실제 계산된 cycle time
#'
#' @field window_count_mode list
#'   - mode: character ("optimize" or "user_specified_N")
#'   - description: character
#'
#' @field scan_rate_settings list
#'   - max_scan_rate_hz: numeric (장비 maximum scan rate)
#'   - load_factor: numeric (0-1, default: 0.8)
#'   - effective_scan_rate_hz: numeric (max * load_factor)
#'   - ms1_scans: integer (Reserved MS1 scans: 0 for parallel, 1 for sequential)
#'
#' @field timing_breakdown list
#'   - ms1_time: numeric (seconds)
#'   - ms2_time_per_window: numeric (seconds)
#'   - total_ms2_time: numeric (seconds)
#'   - overhead_time: numeric (seconds)
#'
#' @field maxIT_optimization list
#'   - optimization_applied: logical
#'   - original_maxIT_ms2: numeric (ms, initial value)
#'   - recommended_maxIT_ms2: numeric (ms, optimized value)
#'   - improvement_ms: numeric (ms increase)
#'   - optimized_ms2_time_sec: numeric (seconds)
#'   - slack_utilized_sec: numeric
#'   - message: character
#'
#' @field feasibility list
#'   - is_feasible: logical
#'   - scan_rate_check: logical
#'   - cycle_time_check: logical
#'   - min_windows_check: logical
#'   - warnings: character vector
#'
#' @field metadata list
#'   - cycle_calculation: character ("parallel" or "sequential")
#'   - instrument_name: character
#'   - target_dppp: numeric
#'   - calculation_timestamp: POSIXct
```

---

### 3.0 determine_window_count() [Module 3A]

Window count를 결정하고 feasibility를 검증합니다 (3-mode logic: optimize/NULL/user-specified).

#### 함수 시그니처

```r
determine_window_count <- function(
  diagnosis,
  target_cycle_time_sec = NULL,
  n_windows_override = "optimize",
  ms1_scans = NULL,
  target_dppp = 7.0,
  instrument_preset = "astral",
  custom_scan_rate_load_factor = NULL,
  custom_maxIT_optimization = NULL,
  enable_raw_metadata = FALSE,
  rawfile_dir = NULL,
  min_windows = 20,
  max_windows = 500
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `diagnosis` | DiagnosisResult | ✓ | - | Stage 2 출력 |
| `target_cycle_time_sec` | numeric | ✗ | NULL | Target cycle time (NULL: use diagnosis recommendation) |
| `n_windows_override` | character/integer | ✗ | "optimize" | "optimize", NULL, or integer (user-specified count) |
| `ms1_scans` | integer | ✗ | NULL | MS1 scans to reserve (NULL: use default=1) |
| `target_dppp` | numeric | ✗ | 7.0 | 목표 DPPP |
| `instrument_preset` | character | ✗ | "astral" | Instrument preset name |
| `custom_scan_rate_load_factor` | numeric | ✗ | NULL | Override load factor (default: 0.8) |
| `custom_maxIT_optimization` | list | ✗ | NULL | Override maxIT config |
| `enable_raw_metadata` | logical | ✗ | FALSE | Raw metadata integration |
| `rawfile_dir` | character | ✗ | NULL | Raw file directory |
| `min_windows` | integer | ✗ | 20 | 최소 window 개수 |
| `max_windows` | integer | ✗ | 500 | 최대 window 개수 |

#### 반환값 (WindowCountResult)

```r
structure(
  list(
    window_count = integer(),
    target_cycle_time_sec = numeric(),
    calculated_cycle_time_sec = numeric(),

    window_count_mode = list(
      mode = character(),
      description = character()
    ),

    scan_rate_settings = list(
      max_scan_rate_hz = numeric(),
      load_factor = numeric(),
      effective_scan_rate_hz = numeric(),
      ms1_scans = integer()
    ),

    timing_breakdown = list(
      ms1_time = numeric(),
      ms2_time_per_window = numeric(),
      total_ms2_time = numeric(),
      overhead_time = numeric()
    ),

    maxIT_optimization = list(
      optimization_applied = logical(),
      original_maxIT_ms2 = numeric(),
      recommended_maxIT_ms2 = numeric(),
      improvement_ms = numeric(),
      optimized_ms2_time_sec = numeric(),
      slack_utilized_sec = numeric(),
      message = character()
    ),

    feasibility = list(
      is_feasible = logical(),
      scan_rate_check = logical(),
      cycle_time_check = logical(),
      min_windows_check = logical(),
      warnings = character()
    ),

    metadata = list(
      cycle_calculation = character(),
      instrument_name = character(),
      target_dppp = numeric(),
      calculation_timestamp = POSIXct()
    )
  ),
  class = c("WindowCountResult", "list")
)
```

#### Override Modes

**Mode 1: "optimize" or NULL**
```r
# Script calculates optimal window count
result <- determine_window_count(
  diagnosis,
  n_windows_override = "optimize"  # or NULL
)
# Uses effective_scan_rate × target_cycle_time - ms1_scans
```

**Mode 2: User-specified (integer)**
```r
# User provides exact window count with feasibility check
result <- determine_window_count(
  diagnosis,
  n_windows_override = 150  # Specific count
)
# Throws error if infeasible with 3 solutions suggested
```

#### MaxIT Optimization

Slack-based MS2 maxIT optimization for signal quality improvement:

```r
# Auto-enabled when slack ≥ 0.5 sec
slack = target_cycle_time - calculated_cycle_time

if (slack >= 0.5) {
  # Iteratively increase MS2 maxIT by 10ms steps
  # until cycle_time reaches target or maxIT hits limit (100ms)
  maxIT_ms2_optimized = original_maxIT + (n_iterations × 10ms)
}
```

#### 오류 처리

```r
# User-specified count infeasible
if (n_windows + ms1_scans > max_possible_scans) {
  stop(sprintf(
    "User-specified window count (%d) is INFEASIBLE.\n",
    n_windows,
    "  Reason: Total scans needed (%d) exceeds maximum (%d).\n",
    "  Solutions:\n",
    "    1. Reduce window count to ≤ %d\n",
    "    2. Increase target_cycle_time_sec\n",
    "    3. Reduce MS1 scans"
  ))
}
```

#### 예제

```r
# Example 1: Optimize mode (parallel instrument)
result <- determine_window_count(
  diagnosis,
  ms1_scans = 0,  # Parallel (Astral)
  instrument_preset = "astral"
)

# Example 2: Sequential instrument with custom load factor
result <- determine_window_count(
  diagnosis,
  ms1_scans = 1,  # Sequential (Orbitrap)
  custom_scan_rate_load_factor = 0.9,
  instrument_preset = "orbitrap"
)

# Example 3: User-specified count
result <- determine_window_count(
  diagnosis,
  n_windows_override = 80,  # Specific count
  instrument_preset = "astral"
)

# Example 4: Disable maxIT optimization
result <- determine_window_count(
  diagnosis,
  custom_maxIT_optimization = list(enabled = FALSE),
  instrument_preset = "astral"
)
```

---

### 3.1 calculate_window_count_from_scantime()

Scan_time 기반으로 가능한 window 개수를 계산합니다.

#### 함수 시그니처

```r
calculate_window_count_from_scantime <- function(
  scan_time,
  instrument_config,
  safety_margin = 0.9
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `scan_time` | numeric | ✓ | - | Scan time (초) |
| `instrument_config` | list | ✓ | - | Instrument 설정 |
| `safety_margin` | numeric | ✗ | 0.9 | Safety factor (0-1) |

#### 반환값

```r
list(
  n_windows = integer(),
  theoretical_max = integer(),
  scan_rate_limited = integer(),
  applied_limit = character(),  # "theoretical" or "scan_rate"
  cycle_time = numeric(),  # seconds
  scan_rate = numeric(),  # Hz
  feasibility = list(
    feasible = logical(),
    within_limits = logical(),
    warnings = character()
  )
)
```

#### 계산 로직

```r
# Astral (parallel acquisition)
if (instrument_config$cycle_calculation == "parallel") {
  cycle_time_ms <- scan_time * 1000
  theoretical_max <- floor((cycle_time_ms - instrument_config$ms1_time) /
                           instrument_config$ms2_time)
} else {
  # Sequential acquisition (Orbitrap)
  cycle_time_ms <- scan_time * 1000
  theoretical_max <- floor((cycle_time_ms - instrument_config$ms1_time) /
                           instrument_config$ms2_time)
}

# Scan rate constraint
scan_rate_limited <- floor(instrument_config$max_scan_rate * scan_time * safety_margin)

# Final window count
n_windows <- min(theoretical_max, scan_rate_limited)
```

---

### 3.2 adjust_for_injection_time()

Raw file의 실제 injection time을 기반으로 maxIT를 조정합니다 (선택).

#### 함수 시그니처

```r
adjust_for_injection_time <- function(
  raw_metadata,
  current_maxIT,
  efficiency_threshold = 0.9,
  adjustment_factor = 1.2
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `raw_metadata` | list | ✓ | - | load_raw_metadata() 출력 |
| `current_maxIT` | numeric | ✓ | - | 현재 maxIT (ms) |
| `efficiency_threshold` | numeric | ✗ | 0.9 | IT 효율 임계값 |
| `adjustment_factor` | numeric | ✗ | 1.2 | 조정 계수 |

#### 반환값

```r
list(
  needs_adjustment = logical(),
  current_efficiency = numeric(),
  recommended_maxIT = numeric(),  # ms
  expected_improvement = numeric(),  # percentage
  justification = character()
)
```

#### 조정 로직

```r
median_it <- raw_metadata$statistics$median_it_ms2
efficiency <- median_it / current_maxIT

if (efficiency > efficiency_threshold) {
  recommended_maxIT <- quantile(raw_metadata$injection_times$ms2, 0.75) *
                       adjustment_factor
  needs_adjustment <- TRUE
} else {
  recommended_maxIT <- current_maxIT
  needs_adjustment <- FALSE
}
```

---

### 3.3 optimize_mz_range()

m/z 범위 최적화 (4가지 전략).

#### 함수 시그니처

```r
optimize_mz_range <- function(
  rt_binned_data,
  strategies = c("quantile", "smoothing", "outlier_removal", "coverage_based"),
  coverage_target = 0.95,
  quantile_range = c(0.01, 0.99),
  smoothing_config = list(...)
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `rt_binned_data` | list | ✓ | - | RT binning 결과 |
| `strategies` | character[] | ✗ | c(...) | 사용할 전략 목록 |
| `coverage_target` | numeric | ✗ | 0.95 | Coverage 목표 (0-1) |
| `quantile_range` | numeric[2] | ✗ | c(0.01, 0.99) | Quantile 범위 |
| `smoothing_config` | list | ✗ | list(...) | Smoothing 설정 |

#### 반환값

```r
list(
  strategy_comparison = tibble(
    strategy = character(),
    rt_bin = character(),
    mz_min = numeric(),
    mz_max = numeric(),
    range_width = numeric(),
    precursor_coverage = numeric(),
    n_precursors_covered = integer(),
    n_outliers_removed = integer()
  ),
  selected_strategy = character(),
  optimized_boundaries = tibble(
    rt_bin = character(),
    mz_min = numeric(),
    mz_max = numeric(),
    mz_range = numeric()
  ),
  performance_metrics = list(
    mean_coverage = numeric(),
    mean_range_reduction = numeric(),
    total_outliers_removed = integer()
  )
)
```

#### 전략별 구현

**전략 1: Quantile-based**
```r
mz_min <- quantile(data$Precursor.Mz, quantile_range[1])
mz_max <- quantile(data$Precursor.Mz, quantile_range[2])
```

**전략 2: Smoothing-based**
```r
# 기존 dynamicDIA.R 활용
boundaries <- compute_smooth_mz_boundaries(
  rt_binned_data,
  dynamic = TRUE,
  smoothing_method = "savgol"
)
```

**전략 3: Outlier Removal**
```r
Q1 <- quantile(data$Precursor.Mz, 0.25)
Q3 <- quantile(data$Precursor.Mz, 0.75)
IQR <- Q3 - Q1
mz_min <- Q1 - 1.5 * IQR
mz_max <- Q3 + 1.5 * IQR
```

**전략 4: Coverage-based**
```r
# 목표 coverage를 만족하는 최소 범위 찾기
cumulative_dist <- ecdf(data$Precursor.Mz)
lower_quantile <- (1 - coverage_target) / 2
upper_quantile <- 1 - lower_quantile
mz_min <- quantile(data$Precursor.Mz, lower_quantile)
mz_max <- quantile(data$Precursor.Mz, upper_quantile)
```

---

### 3.4 generate_windows()

Isolation windows를 생성합니다 (3가지 모드).

#### 함수 시그니처

```r
generate_windows <- function(
  rt_binned_data,
  optimized_boundaries,
  n_windows,
  generation_mode = "variable",
  min_width_da = 2,
  max_width_da = 80,
  overlap_percentage = 0
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `rt_binned_data` | list | ✓ | - | RT binning 결과 |
| `optimized_boundaries` | tibble | ✓ | - | m/z 범위 최적화 결과 |
| `n_windows` | integer | ✓ | - | 생성할 window 개수 |
| `generation_mode` | character | ✗ | "variable" | "fixed", "overlapped", "variable" |
| `min_width_da` | numeric | ✗ | 2 | 최소 window 폭 (Da) |
| `max_width_da` | numeric | ✗ | 80 | 최대 window 폭 (Da) |
| `overlap_percentage` | numeric | ✗ | 0 | Overlap % (overlapped 모드) |

#### 반환값 (OptimizedWindows)

```r
structure(
  list(
    windows = tibble(
      window_id = integer(),
      rt_bin = character(),
      window_start = numeric(),
      window_end = numeric(),
      window_width = numeric(),
      center_mz = numeric(),
      n_precursors = integer()
    ),
    statistics = list(
      n_windows = integer(),
      mean_width = numeric(),
      sd_width = numeric(),
      cv_width = numeric(),
      mean_precursors_per_window = numeric(),
      cv_precursors = numeric(),
      coverage = numeric()
    ),
    generation_mode = character(),
    allocation_method = character(),  # for variable mode
    parameters = list(
      min_width_da = numeric(),
      max_width_da = numeric(),
      overlap_percentage = numeric()
    )
  ),
  class = c("OptimizedWindows", "list")
)
```

#### 모드별 구현

**Fixed Mode**
```r
total_range <- mz_max - mz_min
window_width <- total_range / n_windows

windows <- tibble(
  window_id = 1:n_windows,
  window_start = mz_min + (0:(n_windows-1)) * window_width,
  window_end = mz_min + (1:n_windows) * window_width
)
```

**Overlapped Mode**
```r
# Fixed mode + overlap
window_width <- total_range / (n_windows - overlap_adjustment)
overlap_da <- window_width * (overlap_percentage / 100)

windows <- tibble(
  window_id = 1:n_windows,
  window_start = mz_min + (0:(n_windows-1)) * (window_width - overlap_da),
  window_end = mz_min + (0:(n_windows-1)) * (window_width - overlap_da) + window_width
)
```

**Variable Mode**
```r
# 기존 window_generator.R 활용
# Largest remainder method로 정확한 개수 보장
windows <- generate_windows_from_boundaries(
  rt_binned_data,
  optimized_boundaries,
  n_windows = n_windows,
  min_width_da = min_width_da,
  max_width_da = max_width_da
)
```

---

## Stage 4: Visualization

### 4.1 plot_dppp_density()

DPPP 분포 밀도 플롯을 생성합니다.

#### 함수 시그니처

```r
plot_dppp_density <- function(
  diagnosis_result,
  target_dppp = 7.0,
  dppp_tolerance = 0.5
)
```

#### 반환값

```r
ggplot() +
  geom_density(aes(x = dppp)) +
  geom_vline(xintercept = target_dppp, color = "red", linetype = "dashed") +
  geom_rect(aes(
    xmin = target_dppp - dppp_tolerance,
    xmax = target_dppp + dppp_tolerance
  ), alpha = 0.2, fill = "green") +
  labs(
    title = "DPPP Distribution",
    subtitle = sprintf("Satisfaction: %.1f%%", satisfaction_ratio * 100)
  )
```

---

### 4.2 generate_comprehensive_report()

모든 Stage 결과를 종합한 PDF 보고서를 생성합니다.

#### 함수 시그니처

```r
generate_comprehensive_report <- function(
  stage1_output,
  stage2_output,
  stage3_output,
  output_file = "optimization_report.pdf"
)
```

#### 파라미터

| 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `stage1_output` | ValidatedData | ✓ | - | Stage 1 결과 |
| `stage2_output` | DiagnosisResult | ✓ | - | Stage 2 결과 |
| `stage3_output` | OptimizedWindows | ✓ | - | Stage 3 결과 |
| `output_file` | character | ✗ | "..." | 출력 PDF 경로 |

#### 반환값

```r
list(
  report_file = character(),  # PDF file path
  plots = list(
    # All generated plots
  ),
  summary = list(
    n_pages = integer(),
    file_size_mb = numeric(),
    generation_time_sec = numeric()
  )
)
```

---

## Mock 데이터 가이드

### Mock Stage 1 Output

```r
create_mock_stage1_output <- function(n_precursors = 100000) {
  set.seed(42)

  structure(
    list(
      data = tibble(
        RT.Start = runif(n_precursors, 10, 110),
        Precursor.Mz = rnorm(n_precursors, 650, 150),
        FWHM = rnorm(n_precursors, 0.3, 0.05)
      ),
      metadata = list(
        n_precursors = n_precursors,
        rt_range = c(10, 110),
        mz_range = c(380, 980),
        fwhm_stats = list(
          mean = 0.3,
          median = 0.29,
          sd = 0.05
        ),
        has_raw_metadata = FALSE
      ),
      validation_status = list(
        all_passed = TRUE,
        quality_score = 0.95,
        n_warnings = 0,
        n_errors = 0,
        warnings = character(),
        errors = character()
      )
    ),
    class = c("ValidatedData", "list")
  )
}
```

### Mock Stage 2 Output

```r
create_mock_stage2_output <- function() {
  structure(
    list(
      current_status = list(
        user_scan_time = 2.0,
        mean_dppp = 6.8,
        median_dppp = 6.5,
        satisfaction_ratio = 0.72,
        dppp_distribution = rnorm(100000, 6.8, 1.2)
      ),
      recommendation = list(
        optimal_scan_time = 1.85,
        expected_satisfaction = 0.88,
        expected_window_count = 215,
        improvement_pct = 16,
        feasible = TRUE
      ),
      tradeoff_analysis = tibble(
        scan_time = seq(1.0, 3.0, 0.1),
        window_count = seq(230, 100, length.out = 21),
        satisfaction_ratio = c(0.92, 0.88, rep(0.85, 18), 0.65),
        scan_rate_hz = seq(125, 50, length.out = 21)
      )
    ),
    class = c("DiagnosisResult", "list")
  )
}
```

---

## 버전 호환성

| API 버전 | 호환 R 버전 | 릴리스 날짜 |
|----------|-------------|------------|
| 2.0.0 | R >= 4.0 | 2025-10-13 |

## 변경 이력

### v2.0.0 (2025-10-13)
- 4-Stage 아키텍처로 전면 개편
- Stage 2 DPPP Diagnosis 추가
- 다양한 m/z range 최적화 전략 추가
- 3가지 window generation 모드 지원

---

**End of API Specification**
