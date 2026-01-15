# Shiny App 코드 동기화 전략

## 문제 정의

R 파이프라인 코드가 수정될 때 Shiny 앱이 깨지지 않도록 보장하는 방법

---

## 전략 비교

### Option A: API 추상화 레이어 (권장 ⭐)

```
┌─────────────────┐                    ┌─────────────────┐
│   R Pipeline    │                    │   Shiny App     │
│  (stage1-4.R)   │                    │    (app.R)      │
└────────┬────────┘                    └────────┬────────┘
         │                                      │
         ↓                                      ↓
┌─────────────────────────────────────────────────────────┐
│                  pipeline_api.R                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  run_pipeline_safe()                            │   │
│  │  - 입력 검증                                    │   │
│  │  - 에러 핸들링                                  │   │
│  │  - 표준화된 출력                                │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**장점**:
- Shiny 앱은 API만 의존 (파이프라인 변경에 격리)
- 중앙 집중화된 에러 핸들링
- 테스트 용이

**단점**:
- 추가 개발 필요 (1-2일)
- 레이어 하나 추가

**복잡도**: ⭐⭐ (중간)

---

### Option B: R 패키지화

```
┌─────────────────────────────────────────────────────────┐
│  diaoptimizer (R Package)                               │
│  ├── R/                                                 │
│  │   ├── stage1_*.R                                     │
│  │   ├── stage2_*.R                                     │
│  │   └── ...                                            │
│  ├── NAMESPACE (exported functions)                     │
│  ├── DESCRIPTION (version, dependencies)                │
│  └── man/ (documentation)                               │
└─────────────────────────────────────────────────────────┘
                         ↓
              library(diaoptimizer)
                         ↓
┌─────────────────────────────────────────────────────────┐
│  Shiny App                                              │
│  - 패키지 버전 고정 가능                                │
│  - 명확한 API 계약                                      │
└─────────────────────────────────────────────────────────┘
```

**장점**:
- 버전 관리 명확
- CRAN/GitHub 배포 가능
- 문서화 강제

**단점**:
- 초기 설정 복잡 (3-5일)
- 패키지 빌드 프로세스 필요
- devtools 학습 필요

**복잡도**: ⭐⭐⭐⭐ (높음)

---

### Option C: 통합 테스트 기반 (현실적 MVP)

```
┌─────────────────┐     source()      ┌─────────────────┐
│   R Pipeline    │ ────────────────→ │   Shiny App     │
└────────┬────────┘                   └────────┬────────┘
         │                                     │
         ↓                                     ↓
┌─────────────────────────────────────────────────────────┐
│  tests/integration/test_shiny_compatibility.R           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  test_shiny_pipeline_integration()              │   │
│  │  - Stage 함수 존재 여부                          │   │
│  │  - 함수 시그니처 검증                           │   │
│  │  - 반환값 구조 검증                             │   │
│  │  - Shiny 앱 로드 테스트                         │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**장점**:
- 즉시 구현 가능
- 기존 구조 유지
- 변경 감지 자동화

**단점**:
- 사후 감지 (예방 아님)
- 테스트 실행 필요

**복잡도**: ⭐⭐ (낮음)

---

## 권장: Option A + C 조합

### Phase 1: 통합 테스트 (즉시)
파이프라인 변경 시 Shiny 호환성 자동 검증

### Phase 2: API 레이어 (MVP 후)
안정화되면 추상화 레이어 도입

---

## 구현 계획

### Phase 1: 통합 테스트 스크립트

```r
# tests/integration/test_shiny_compatibility.R

test_shiny_pipeline_compatibility <- function() {
  cat("Testing Shiny-Pipeline Compatibility...\n")

  # 1. 필수 함수 존재 확인
  required_functions <- c(
    "create_validated_dataset",
    "plan_optimization",
    "optimize_windows",
    "get_instrument_config",
    "export_windows_to_csv"
  )

  for (fn in required_functions) {
    if (!exists(fn, mode = "function")) {
      stop(sprintf("FAIL: Function '%s' not found!", fn))
    }
    cat(sprintf("  ✓ %s exists\n", fn))
  }

  # 2. 함수 시그니처 검증
  # create_validated_dataset 파라미터 확인
  cvd_args <- names(formals(create_validated_dataset))
  required_cvd_args <- c("data_source")
  if (!all(required_cvd_args %in% cvd_args)) {
    stop("FAIL: create_validated_dataset signature changed!")
  }

  # 3. 반환값 구조 테스트 (실제 데이터로)
  # ... (실제 테스트 코드)

  cat("\n✅ All compatibility tests passed!\n")
}
```

### Phase 2: API 래퍼 레이어

```r
# R/shiny_api.R - Shiny 앱 전용 API

#' Run Pipeline for Shiny (Safe Wrapper)
#'
#' 모든 에러를 캐치하고 표준화된 결과 반환
#' Shiny 앱은 이 함수만 호출
#'
run_pipeline_for_shiny <- function(
  file_path,
  instrument_preset,
  target_dppp,
  target_satisfaction,
  mz_strategy = "quantile"
) {

  # 표준화된 결과 구조
  result <- list(
    success = FALSE,
    data = NULL,
    plan = NULL,
    windows = NULL,
    error = NULL,
    warnings = list()
  )

  tryCatch({
    # Stage 1
    result$data <- create_validated_dataset(
      data_source = file_path,
      enable_replicate_consensus = TRUE
    )

    # Stage 2
    instrument_config <- get_instrument_config(instrument_preset)
    result$plan <- plan_optimization(
      validated_data = result$data,
      instrument_config = instrument_config,
      target_dppp = target_dppp,
      target_satisfaction = target_satisfaction
    )

    # Stage 3
    result$windows <- optimize_windows(
      validated_data = result$data,
      optimization_plan = result$plan,
      mz_strategy = mz_strategy,
      window_mode = "variable"
    )

    result$success <- TRUE

  }, error = function(e) {
    result$error <- e$message
  }, warning = function(w) {
    result$warnings <- c(result$warnings, w$message)
  })

  return(result)
}

#' Export for Shiny (Safe Wrapper)
export_for_shiny <- function(result, output_file, instrument_type) {

  if (!result$success) {
    stop("Cannot export: Pipeline did not complete successfully")
  }

  export_windows_to_csv(
    optimized_windows = result$windows,
    output_file = output_file,
    validated_data = result$data,
    optimization_plan = result$plan,
    instrument_type = instrument_type
  )
}

#' Get Summary for Shiny Display
get_summary_for_shiny <- function(result) {

  if (!result$success) {
    return(data.frame(
      Status = "Error",
      Message = result$error
    ))
  }

  data.frame(
    Metric = c(
      "Precursors",
      "Windows",
      "Coverage",
      "Cycle Time"
    ),
    Value = c(
      nrow(result$data$data),
      nrow(result$windows$windows),
      sprintf("%.1f%%", result$windows$statistics$coverage_percentage * 100),
      sprintf("%.2f sec", result$plan$required_cycle_time_sec)
    )
  )
}
```

---

## 변경 관리 워크플로우

### 파이프라인 수정 시 체크리스트

```markdown
## Pipeline 변경 체크리스트

### 함수 시그니처 변경 시
- [ ] Shiny API 래퍼 업데이트
- [ ] 호환성 테스트 실행
- [ ] app.R 호출부 확인

### 새 의존성 추가 시
- [ ] shiny_app/setup_shiny.R에 패키지 추가
- [ ] app.R 상단에 library() 추가

### 반환값 구조 변경 시
- [ ] get_summary_for_shiny() 업데이트
- [ ] UI 표시 로직 확인

### 테스트 명령어
source("tests/integration/test_shiny_compatibility.R")
test_shiny_pipeline_compatibility()
```

---

## Git Hooks (자동화)

```bash
# .git/hooks/pre-commit

#!/bin/bash
# Shiny 호환성 테스트 자동 실행

echo "Running Shiny compatibility tests..."
Rscript -e "source('tests/integration/test_shiny_compatibility.R'); test_shiny_pipeline_compatibility()"

if [ $? -ne 0 ]; then
  echo "❌ Shiny compatibility test failed!"
  echo "Please fix compatibility issues before committing."
  exit 1
fi

echo "✅ Shiny compatibility OK"
```

---

## 버전 동기화 규칙

| 파이프라인 변경 | Shiny 앱 영향 | 필요 조치 |
|----------------|---------------|----------|
| 내부 로직 수정 | 없음 | 없음 |
| 버그 픽스 | 개선 | 테스트만 |
| 새 기능 추가 | 없음 (옵션) | UI 추가 고려 |
| 파라미터 추가 | 잠재적 | API 래퍼 확인 |
| 파라미터 제거 | 🔴 위험 | 즉시 수정 |
| 함수명 변경 | 🔴 위험 | 즉시 수정 |
| 반환값 변경 | 🔴 위험 | 즉시 수정 |

---

## 문서 버전

- **버전**: 1.0
- **최종 수정**: 2025-01-14
- **상태**: 전략 수립 완료
