# JSON Configuration System User Guide

**Version**: 1.0
**Last Updated**: 2025-10-27

---

## 📋 개요

DIA Window Optimizer의 JSON 설정 파일 시스템을 통해 스크립트 수정 없이 모든 최적화 파라미터를 관리할 수 있습니다.

### 주요 개선사항

✅ **개선 1: recommend_cycle_time을 CSV에 추가**
- 22번째 컬럼 `Recommended_Cycle_Time_Sec` 추가
- Stage 2에서 계산된 required_cycle_time을 모든 row에 포함
- 분석 시 중요한 지표를 CSV에서 직접 확인 가능

✅ **개선 2: JSON 기반 설정 관리**
- 프로젝트 메타데이터, 장비, DPPP, RT binning, m/z 전략 등 모든 파라미터를 JSON으로 관리
- 설정 버전 관리 및 재현성 향상
- 여러 실험 조건 비교 용이

---

## 🚀 빠른 시작

### 1. 기본 사용법

```r
# JSON 설정으로 최적화 실행
source("run_with_config.R")
run_optimization("config/optimization_config.json")
```

### 2. 프리셋 사용

```r
# Fusion Lumos 표준 설정
run_optimization("config/presets/fusion_lumos_standard.json")

# Quant 모드 (85% satisfaction)
run_optimization("config/presets/quant_mode_85pct.json")

# ID 모드 (70% satisfaction, max identification)
run_optimization("config/presets/id_mode_70pct.json")

# Astral narrow-DIA
run_optimization("config/presets/astral_narrow_dia.json")
```

### 3. 설정 검증

```r
# 단일 설정 파일 검증
source("validate_config.R")
validate_config_file("config/optimization_config.json")

# 모든 프리셋 검증
validate_all_configs("config/presets")
```

---

## 📁 파일 구조

```
config/
├── optimization_config_template.json  # 템플릿 (주석 포함 가이드)
├── optimization_config.json           # 실제 사용할 설정 파일
├── test_config.json                   # 테스트용 간단 설정
└── presets/                           # 사전 정의된 프리셋
    ├── quant_mode_85pct.json         # Quant mode, 85% satisfaction
    ├── id_mode_70pct.json             # ID mode, 70% satisfaction
    ├── fusion_lumos_standard.json     # Fusion Lumos 표준 설정
    └── astral_narrow_dia.json         # Astral narrow-DIA 설정

R/
└── config_loader.R                    # JSON 로드 및 검증 함수

run_with_config.R                      # JSON 기반 실행 스크립트
validate_config.R                      # 설정 검증 스크립트
```

---

## ⚙️ 설정 파라미터 가이드

### 파라미터 중요도 분류

#### 🔴 필수 설정 (반드시 지정)

1. **project_metadata.project_name**: 프로젝트 식별자
2. **project_metadata.date**: 분석 날짜 (ISO 형식: YYYY-MM-DD)
3. **input_data.input_files**: 입력 DIA-NN parquet 파일 경로 배열
4. **instrument.preset**: 장비 타입 선택
5. **output.output_dir**: 결과 출력 디렉토리

#### 🟡 중요 설정 (실험 목적에 따라 조정)

6. **dppp_parameters.target_dppp**: DPPP 목표값
   - `1.5` = ID mode (최대 identification)
   - `4.0` = Balanced mode
   - `7.0` = Quant mode (정확한 정량, 권장)

7. **dppp_parameters.target_satisfaction**: 만족도 목표
   - `0.70` = 70% (relaxed)
   - `0.85` = 85% (standard)
   - `0.90` = 90% (strict)

8. **rt_binning.rt_bin_width_min**: RT bin 폭 (분)
   - 권장: 3-7분
   - 짧은 bin = RT 특이성 높음, 관리할 bin 많음
   - 긴 bin = 단순함, RT 특이성 낮음

9. **mz_optimization.strategies**: m/z 최적화 전략 배열
   - `"quantile"`: Percentile 기반 (빠르고 robust)
   - `"smoothing"`: DynamicDIA (RT-dependent)
   - `"outlier"`: Outlier 제거 (robust)
   - `"coverage"`: 최소 범위 (conservative)

10. **window_generation.modes**: Window 생성 모드 배열
    - `"fixed"`: Equal-width windows
    - `"variable"`: Density-based adaptive (권장)

#### 🟢 고급 설정 (기본값 사용 권장, 필요시 조정)

11. **dppp_parameters.load_factor**: Scan rate 활용률
    - `0.8` = Conservative (안정성, 권장)
    - `0.9` = Moderate
    - `1.0` = Aggressive (불안정 가능)

12. **window_count_constraints.min_windows**: 최소 window 개수 per RT bin
13. **window_count_constraints.max_windows**: 최대 window 개수 per RT bin
14. **mz_optimization.quantile_lower**: Lower percentile (기본 0.05 = P5)
15. **mz_optimization.quantile_upper**: Upper percentile (기본 0.95 = P95)
16. **mz_optimization.smoothing_window**: Smoothing window size (RT bin <5개면 3으로 감소)
17. **window_generation.min_width_da**: 최소 window 폭 (Da)
18. **window_generation.max_width_da**: 최대 window 폭 (Da)
19. **window_generation.overlap_percentage**: Window 간 overlap 비율

#### ⚪ 선택 설정 (null 가능)

20. **instrument.custom_settings**: 커스텀 장비 설정 (preset 오버라이드)
21. **window_count_constraints.ms1_scans**: MS1 스캔 개수 (null=자동 감지)
22. **dppp_parameters.dppp_tolerance**: DPPP 허용 오차 (기본 0.0)

---

## 📝 설정 파일 예제

### 예제 1: Fusion Lumos 70% Satisfaction

```json
{
  "project_metadata": {
    "project_name": "Fusion_Lumos_70pct",
    "date": "2025-10-27",
    "description": "Fusion Lumos with 70% satisfaction",
    "analyst": "Your Name"
  },

  "input_data": {
    "input_files": [
      "data/30min_report.parquet",
      "data/60min_report.parquet",
      "data/90min_report.parquet"
    ]
  },

  "instrument": {
    "preset": "fusion_lumos",
    "custom_settings": null
  },

  "dppp_parameters": {
    "target_dppp": 7.0,
    "target_satisfaction": 0.70,
    "dppp_tolerance": 0.0,
    "load_factor": 0.8
  },

  "window_count_constraints": {
    "min_windows": 10,
    "max_windows": 500,
    "ms1_scans": null
  },

  "rt_binning": {
    "rt_bin_width_min": 5.0
  },

  "mz_optimization": {
    "strategies": ["quantile", "smoothing", "outlier", "coverage"],
    "quantile_lower": 0.05,
    "quantile_upper": 0.95,
    "target_coverage": 0.95,
    "outlier_threshold": 3.0,
    "smoothing_window": 3,
    "polynomial_order": 2
  },

  "window_generation": {
    "modes": ["fixed", "variable"],
    "min_width_da": 2,
    "max_width_da": 80,
    "overlap_percentage": 0
  },

  "output": {
    "output_dir": "results_fusion_lumos_70pct",
    "include_summary": true,
    "include_plots": false
  }
}
```

### 예제 2: 커스텀 장비 설정

```json
{
  "instrument": {
    "preset": "custom",
    "custom_settings": {
      "ms1_time": 50.0,
      "ms2_time": 30.0,
      "max_scan_rate": 18,
      "cycle_calculation": "sequential"
    }
  }
}
```

---

## 🎯 사용 시나리오

### 시나리오 1: 여러 Satisfaction 레벨 비교

```r
# 70% satisfaction
run_optimization("config/my_project_sat70.json")

# 85% satisfaction
run_optimization("config/my_project_sat85.json")

# 90% satisfaction
run_optimization("config/my_project_sat90.json")
```

각 JSON 파일의 `output_dir`을 다르게 설정하여 결과를 별도 폴더에 저장합니다.

### 시나리오 2: 장비 간 비교

```r
# Traditional Orbitrap
run_optimization("config/orbitrap_comparison.json")

# Fusion Lumos
run_optimization("config/fusion_lumos_comparison.json")

# Astral
run_optimization("config/astral_comparison.json")
```

### 시나리오 3: 전략 비교

```json
// 전략 1: Quantile only
"mz_optimization": {
  "strategies": ["quantile"]
}

// 전략 2: All strategies
"mz_optimization": {
  "strategies": ["quantile", "smoothing", "outlier", "coverage"]
}
```

---

## ✅ 검증 가이드

### 설정 검증 워크플로우

1. **템플릿 복사**
   ```bash
   cp config/optimization_config_template.json config/my_config.json
   ```

2. **설정 수정**
   - 텍스트 에디터로 `my_config.json` 열기
   - 주석(`_comment_*`) 라인 제거
   - 필요한 값 수정

3. **검증 실행**
   ```r
   source("validate_config.R")
   validate_config_file("config/my_config.json")
   ```

4. **오류 수정**
   - 검증 실패 시 오류 메시지 확인
   - 템플릿 참조하여 수정
   - 재검증

5. **최적화 실행**
   ```r
   source("run_with_config.R")
   run_optimization("config/my_config.json")
   ```

---

## 📊 CSV 출력 형식 (22-column Thermo Standard)

### 컬럼 구조

| Column | Name | Description | Example |
|--------|------|-------------|---------|
| 1-3 | Compound, Formula, Adduct | Empty for DIA | "", "", "" |
| 4-5 | m/z, z | Center m/z, charge | 480.8, 2 |
| 6-7 | t start (min), t stop (min) | RT window | 11.9, 16.9 |
| 8 | Isolation Window (m/z) | Window width | 26.2 |
| 9 | Normalized AGC Target (%) | AGC target | 100 |
| 10-11 | Start (m/z), End (m/z) | m/z range | 467.7, 493.9 |
| 12 | Window_ID | Window index | 1, 2, 3, ... |
| 13 | RT_Segment_ID | RT segment | 1, 2, 3, ... |
| 14-15 | RT_Center, RT_Width | RT center, width | 14.4, 5.0 |
| 16 | N_Precursors | Precursor count | 239 |
| 17-18 | Overlap_Prev, Overlap_Next | Overlap with adjacent | 0, 26.2 |
| 19 | Instrument | Instrument name | "Thermo Fusion Lumos" |
| 20 | Generation_Method | Strategy_Mode | "quantile_fixed" |
| 21 | Window_Type | Mode | "fixed" |
| **22** | **Recommended_Cycle_Time_Sec** | **Required cycle time** | **1.180** |

### ✨ 신규 추가: Column 22 (Recommended_Cycle_Time_Sec)

- **목적**: Stage 2에서 계산된 required cycle time 정보를 CSV에 포함
- **형식**: 소수점 3자리 (초 단위)
- **활용**:
  - 실제 MS method 설정 시 cycle time 참조
  - 분석 후 최적화 파라미터 역추적
  - DPPP 달성 여부 검증

---

## 🔍 트러블슈팅

### 문제 1: JSON 파싱 오류

```
❌ JSON parsing error: ...
```

**해결**:
- JSON 문법 검사 (콤마, 중괄호, 대괄호)
- 마지막 항목 뒤 콤마 제거
- 문자열은 반드시 쌍따옴표 `"` 사용

### 문제 2: 입력 파일 없음

```
Input file not found: data/30min_report.parquet
```

**해결**:
- 파일 경로 확인 (절대 경로 또는 상대 경로)
- 파일 존재 여부 확인
- 경로 구분자 확인 (Windows: `/` 또는 `\\`)

### 문제 3: 파라미터 범위 오류

```
dppp_parameters.target_satisfaction must be between 0.5 and 1.0
```

**해결**:
- 템플릿의 허용 범위 확인
- 값 수정 후 재검증

### 문제 4: Smoothing 전략 오류

```
prospectr::savitzkyGolay(): filter length w must be lower than ncol(X)
```

**해결**:
- RT bin 개수가 적을 때 발생 (< 5개)
- `smoothing_window` 값을 3으로 감소
- 또는 `rt_bin_width_min` 감소하여 bin 개수 증가

---

## 📚 추가 리소스

### 관련 문서
- **DEVELOPMENT.md**: 전체 프로젝트 구조 및 진행 상황
- **CLAUDE.md**: Claude Code를 위한 개발 가이드
- **docs/ARCHITECTURE.md**: 시스템 아키텍처 상세
- **docs/API_SPECIFICATION.md**: 모듈 I/O 스펙

### 지원되는 Instrument Presets

| Preset | Name | Max Hz | Cycle Calculation |
|--------|------|--------|-------------------|
| `astral` | Thermo Astral | 100 | parallel |
| `orbitrap` | Thermo Orbitrap | 12 | sequential |
| `orbitrap_exploris` | Thermo Exploris | 40 | sequential |
| `fusion_lumos` | Thermo Fusion Lumos | 20 | sequential |
| `timstof` | Bruker timsTOF | 100 | parallel |
| `timstof_pro` | Bruker timsTOF Pro | 120 | parallel |
| `sciex_7600` | SCIEX 7600 ZenoTOF | 50 | sequential |
| `waters_synapt` | Waters SYNAPT | 20 | sequential |
| `custom` | Custom Instrument | User-defined | User-defined |

---

## 📞 지원

문제가 발생하거나 추가 지원이 필요한 경우:

1. **설정 검증**: `validate_config.R` 스크립트 실행
2. **템플릿 참조**: `config/optimization_config_template.json` 확인
3. **프리셋 참조**: `config/presets/*.json` 예제 확인
4. **로그 확인**: R 콘솔 출력 메시지 검토

---

**Version**: 1.0
**Last Updated**: 2025-10-27
**Author**: DIA Window Optimizer Development Team
