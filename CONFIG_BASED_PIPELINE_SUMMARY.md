# Config-Based Pipeline with Stage 4 - Implementation Summary

## 🎯 목표 달성

기존 `run_with_config.R`를 수정하여 **JSON configuration 파일로 Stage 1-4 전체 파이프라인**을 제어할 수 있도록 구현했습니다.

## ✅ 주요 개선사항

### Before (기존)
- `run_with_config.R`: **Stage 1-3만 실행** (Data Validation, Optimization Planning, Window Optimization)
- `config/optimization_config.json`에 `"include_plots": true`가 있지만 **사용되지 않음**
- Stage 4 visualization은 **별도 스크립트로 수동 실행** 필요

### After (개선)
- `run_with_config.R`: **Stage 1-4 전체 실행** (Visualization 포함)
- JSON config의 `"include_plots"` 설정을 **실제로 활용**
- **단일 설정 파일**로 전체 파이프라인 제어 가능
- **3개 gradient** (30min, 60min, 90min) **동시 처리**
- Gradient별 **24개 plot + PDF report + method CSV** 자동 생성

## 📝 수정 내용

### 1. `run_with_config.R` 수정

#### Stage 4 모듈 로딩 추가 (Line 17)
```r
source("R/stage4_visualization.R")  # Added for Stage 4
```

#### Stage 4 실행 로직 추가 (Line 230-294)
```r
# ==================================================================
# Stage 4: Visualization & Reporting (if enabled)
# ==================================================================

if (config$output$include_plots) {
  # Create gradient-specific output directory
  viz_output_dir <- file.path(output_dir, paste0(gradient_name, "_visualization"))

  # Prepare windows_list for comparison (use 'variable' mode)
  windows_list_variable <- list()
  for (strategy in mz_strategies) {
    combo_name <- paste(strategy, "variable", sep = "_")
    if (combo_name %in% names(file_results)) {
      windows_list_variable[[strategy]] <- file_results[[combo_name]]$windows_result
    }
  }

  # Generate visualizations
  viz_result <- generate_visualizations(
    validated_data = validated_data,
    optimization_plan = optimization_plan,
    optimized_windows = file_results[[primary_combo]]$windows_result,
    output_dir = viz_output_dir,
    create_pdf = TRUE,
    create_individual_plots = TRUE,
    plot_format = "png",
    plot_dpi = 300,
    windows_list = pass_windows_list  # NULL if <4 strategies
  )
}
```

#### Final Report 섹션 확장 (Line 342-352)
```r
if (config$output$include_plots) {
  cat(sprintf("✅ Visualizations: Generated for %d gradients\n", length(input_files)))
  cat(sprintf("   - Each gradient: 24 plots + PDF report + method CSV\n"))
  for (input_file in input_files) {
    if (file.exists(input_file)) {
      gradient <- extract_gradient_name(input_file)
      viz_dir <- file.path(output_dir, paste0(gradient, "_visualization"))
      cat(sprintf("   - %s: %s/\n", gradient, viz_dir))
    }
  }
}
```

### 2. Config 파일 업데이트

#### `config/optimization_config.json` 수정
```json
{
  "output": {
    "output_dir": "results_config_based_with_viz",
    "include_summary": true,
    "include_plots": true  // ← 이제 실제로 사용됨!
  }
}
```

## 🚀 사용 방법

### 기본 사용 (Full Pipeline)
```r
# R에서 실행
source('run_with_config.R')
run_optimization('config/optimization_config.json')
```

또는 커맨드 라인에서:
```bash
Rscript -e "source('run_with_config.R'); run_optimization('config/optimization_config.json')"
```

### Visualization 끄기
`config/optimization_config.json`에서:
```json
{
  "output": {
    "include_plots": false  // ← Stage 4 비활성화
  }
}
```

## 📊 생성된 결과물

### Full Config 테스트 결과
```
results_config_based_with_viz/
├── 30min_visualization/
│   ├── plot*.png (24 files)
│   ├── optimization_report.pdf
│   └── method.csv
│
├── 60min_visualization/
│   ├── plot*.png (24 files)
│   ├── optimization_report.pdf
│   └── method.csv
│
├── 90min_visualization/
│   ├── plot*.png (24 files)
│   ├── optimization_report.pdf
│   └── method.csv
│
├── 30min_*.csv (8 files: 4 strategies × 2 modes)
├── 60min_*.csv (8 files: 4 strategies × 2 modes)
├── 90min_*.csv (8 files: 4 strategies × 2 modes)
└── batch_processing_summary.csv
```

**총 파일 수:**
- 78 visualization files (24 PNG + 1 PDF + 1 CSV per gradient × 3)
- 24 method CSV files (8 per gradient × 3)
- 1 batch summary CSV
- **Total: 103 files**

## 🎨 24개 Plot Suite (각 gradient별)

1. **DPPP Distribution** (2개): Simple + Enhanced
2. **RT × m/z Density** (3개): Heatmap + Histogram (continuous/5-min)
3. **m/z Density Overlay** (1개): RT segment별 비교
4. **m/z Range Optimization** (5개): 4 strategies + comparison
5. **Coverage Map** (1개): 2×2 grid (all strategies)
6. **Satisfaction Curve** (1개): Cycle time trade-off
7. **Window Width Distribution** (8개): 4 strategies × 2 (density + index)
8. **Strategy Comparison** (3개): Ridge + Box + CDF

## 💡 Insights

`✶ Insight ─────────────────────────────────────`
**Config 기반 설계의 장점:**

1. **단일 진실의 원천 (Single Source of Truth)**
   - 모든 파라미터를 JSON 파일에 집중
   - 버전 관리 용이 (git으로 config 파일 추적)
   - 실험 재현성 보장

2. **유연한 워크플로우**
   - `include_plots: false` → Stage 1-3만 (빠른 window 생성)
   - `include_plots: true` → Stage 1-4 전체 (publication-ready 결과)

3. **Batch Processing**
   - 여러 gradient를 한번에 처리
   - 일관된 파라미터로 비교 가능한 결과
   - 자동화된 결과물 생성

4. **확장 가능한 구조**
   - 새로운 instrument preset 추가 용이
   - Visualization 옵션 확장 가능
   - 전략/모드 조합 자유롭게 제어
`─────────────────────────────────────────────────`

## 🔧 기술적 개선사항

### windows_list 처리 개선
```r
# Pass windows_list only if all 4 strategies are present
pass_windows_list <- if (length(windows_list_variable) >= 4) {
  windows_list_variable
} else {
  NULL  # Let generate_visualizations() re-compute
}
```

**이유:** Stage 4의 `generate_visualizations()` 함수는 모든 4개 전략이 있다고 가정합니다.
Config에서 일부 전략만 지정한 경우 (`"strategies": ["quantile", "smoothing"]`),
`windows_list`를 NULL로 전달하여 함수가 자동으로 필요한 전략을 재계산하도록 합니다.

### Gradient별 Output Directory 구조
```r
viz_output_dir <- file.path(output_dir, paste0(gradient_name, "_visualization"))
```

**이유:** 각 gradient의 visualization을 별도 디렉토리에 저장하여 결과를 명확하게 구분합니다.

## 📝 테스트 Config 예제

### Full Test (3 gradients, 4 strategies, 2 modes)
```json
{
  "input_data": {
    "input_files": [
      "data/30min_report.parquet",
      "data/60min_report.parquet",
      "data/90min_report.parquet"
    ]
  },
  "mz_optimization": {
    "strategies": ["quantile", "smoothing", "outlier", "coverage"]
  },
  "window_generation": {
    "modes": ["fixed", "variable"]
  },
  "output": {
    "include_plots": true
  }
}
```

### Quick Test (1 gradient, 2 strategies, 1 mode)
```json
{
  "input_data": {
    "input_files": ["data/90min_report.parquet"]
  },
  "mz_optimization": {
    "strategies": ["quantile", "smoothing"]
  },
  "window_generation": {
    "modes": ["variable"]
  },
  "output": {
    "include_plots": true
  }
}
```

## 🎯 다음 단계 제안

### 1. Config 파라미터 확장
```json
{
  "output": {
    "include_plots": true,
    "plot_dpi": 300,           // Customizable DPI
    "plot_format": "png",      // png, pdf, svg
    "create_individual": true  // Individual plot files
  }
}
```

### 2. Preset 라이브러리 생성
```
config/presets/
├── quant_mode_70pct.json      # DPPP 7.0, 70% satisfaction
├── id_mode_50pct.json         # DPPP 1.5, 50% satisfaction
├── astral_narrow_dia.json     # Astral-specific settings
└── fusion_lumos_standard.json # Fusion Lumos defaults
```

### 3. Parallel Processing
- 여러 gradient를 병렬로 처리하여 속도 향상
- `parallel` 패키지 활용

## 📚 관련 파일

- **Main Script**: [run_with_config.R](run_with_config.R)
- **Config File**: [config/optimization_config.json](config/optimization_config.json)
- **Test Config**: [config/test_single_file.json](config/test_single_file.json)
- **Execution Log**: [config_with_viz_full.log](config_with_viz_full.log)

---

**Generated**: 2025-11-03
**Status**: ✅ Successfully implemented and tested
**Performance**: ~90 seconds per gradient (full pipeline including Stage 4)
