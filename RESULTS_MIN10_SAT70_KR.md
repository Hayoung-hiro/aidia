# 분석 결과: min_windows=10, satisfaction=70%

## 🎯 실행 요약

**설정 변경**:
- **Min windows**: 20 → **10** (50% 감소)
- **Target satisfaction**: 85% → **70%** (15%p 감소)
- **출력 디렉토리**: `results_min10_sat70/`

**실행 완료**: 24개 CSV 파일 생성 성공 ✅

## 📊 핵심 결과

### Window Count 변화 (Fixed Mode 기준)

| Gradient | 이전 (min=20, sat=85%) | 현재 (min=10, sat=70%) | RT Bins | Win/Bin (이전) | Win/Bin (현재) |
|----------|------------------------|------------------------|---------|----------------|----------------|
| **30min** | 40 windows | **20 windows** | 2 | 20 | **10** ✅ |
| **60min** | 140 windows | **70 windows** | 7 | 20 | **10** ✅ |
| **90min** | 260 windows | **195 windows** | 13 | 20 | **15** ✅ |

### 핵심 발견

**✅ Window count가 이제 gradient에 따라 다릅니다!**

#### 상세 분석

**30min & 60min**:
- Required cycle time: ~1.18-1.24초
- Natural window count: **10 windows per bin**
- 최소 제약(10) 도달 → **제약 없음**
- **자연 계산값 그대로 사용** ✅

**90min**:
- Required cycle time: **1.702초** (70% satisfaction)
- Natural window count: **15 windows per bin**
- 최소 제약(10) 초과 → **제약 없음**
- **자연 계산값 그대로 사용** ✅

## 🔍 Window Width 변화

| Gradient | 이전 Width | 현재 Width | 변화량 |
|----------|-----------|-----------|--------|
| 30min | 22.5 Da | **44.9 Da** | +22.5 Da (+100%) |
| 60min | 21.1 Da | **42.2 Da** | +21.1 Da (+100%) |
| 90min | 20.7 Da | **27.6 Da** | +6.9 Da (+33%) |

**이유**: Window 수가 절반으로 감소 (특히 30min, 60min)하여 각 window가 더 넓은 m/z 범위를 커버합니다.

## 📈 Total Window Count 비교

```
이전 설정 (min=20, sat=85%):
30min:  40 windows (20×2)
60min: 140 windows (20×7)
90min: 260 windows (20×13)
Total: 440 windows

현재 설정 (min=10, sat=70%):
30min:  20 windows (10×2)
60min:  70 windows (10×7)
90min: 195 windows (15×13)
Total: 285 windows (-35%)
```

**Window 수 감소**: 440 → 285 windows (**-155 windows, -35%**)

## 🎯 Cycle Time & DPPP 영향

### Required Cycle Time

| Gradient | Sat 85% | Sat 70% | 증가량 |
|----------|---------|---------|--------|
| 30min | 1.170 sec | **1.180 sec** | +0.010 sec (+0.9%) |
| 60min | 1.200 sec | **1.241 sec** | +0.041 sec (+3.4%) |
| 90min | 1.236 sec | **1.702 sec** | +0.466 sec (+37.7%) |

**90min에서 큰 증가**: P15 (5.09초) → P30 (7.01초) FWHM으로 인해 37.7% 증가

### Actual Cycle Time (10 windows)

| Gradient | Actual CT | Required CT | 여유 |
|----------|-----------|-------------|------|
| 30min | **0.600 sec** | 1.180 sec | -0.580 sec (매우 빠름) |
| 60min | **0.600 sec** | 1.241 sec | -0.641 sec (매우 빠름) |
| 90min | **0.850 sec** | 1.702 sec | -0.852 sec (매우 빠름) |

**모든 gradient가 required cycle time보다 훨씬 빠릅니다** ✅

## 📁 생성된 파일

### 30min Gradient (20 windows total)

| Strategy | Mode | Windows | Coverage | Width |
|----------|------|---------|----------|-------|
| quantile | fixed | 20 | 90.0% | 44.94 ± 0.48 Da |
| quantile | variable | 19 | 86.8% | 42.77 ± 10.31 Da |
| smoothing | fixed | 20 | 90.0% | 44.94 ± 0.48 Da |
| smoothing | variable | 19 | 86.8% | 42.77 ± 10.31 Da |
| outlier | fixed | 20 | 100.0% | 59.91 ± 0.17 Da |
| outlier | variable | 17 | 86.4% | 46.99 ± 11.10 Da |
| coverage | fixed | 20 | 95.0% | 49.05 ± 0.59 Da |
| coverage | variable | 18 | 88.2% | 44.77 ± 11.11 Da |

### 60min Gradient (70 windows total)

| Strategy | Mode | Windows | Coverage | Width |
|----------|------|---------|----------|-------|
| quantile | fixed | 70 | 90.0% | 42.20 ± 2.90 Da |
| quantile | variable | 67 | 86.6% | 40.09 ± 9.06 Da |
| smoothing | fixed | 70 | 89.6% | 42.11 ± 2.84 Da |
| smoothing | variable | 65 | 85.9% | 40.26 ± 8.36 Da |
| outlier | fixed | 70 | 100.0% | 54.77 ± 2.18 Da |
| outlier | variable | 59 | 84.3% | 46.58 ± 12.10 Da |
| coverage | fixed | 70 | 95.0% | 45.46 ± 3.07 Da |
| coverage | variable | 66 | 89.0% | 43.25 ± 9.75 Da |

### 90min Gradient (195 windows total, **15 per bin!**)

| Strategy | Mode | Windows | Coverage | Width |
|----------|------|---------|----------|-------|
| quantile | fixed | 195 | 90.0% | 27.63 ± 2.15 Da |
| quantile | variable | 195 | 87.8% | 26.91 ± 6.82 Da |
| smoothing | fixed | 195 | 89.8% | 27.51 ± 2.10 Da |
| smoothing | variable | 195 | 87.3% | 26.92 ± 6.41 Da |
| outlier | fixed | 195 | 100.0% | 35.89 ± 1.46 Da |
| outlier | variable | 179 | 86.1% | 30.84 ± 8.84 Da |
| coverage | fixed | 195 | 95.0% | 29.76 ± 2.24 Da |
| coverage | variable | 193 | 90.0% | 28.96 ± 7.24 Da |

## ✅ 주요 성과

### 1. Window Count 변동 달성
- **30min/60min**: 10 windows per bin (자연 계산값)
- **90min**: **15 windows per bin** (자연 계산값, 이전 20에서 감소)
- **제약 없음**: 모든 gradient가 min=10 제약을 충족하거나 초과

### 2. Cycle Time 성능 우수
- 모든 gradient가 required cycle time보다 **훨씬 빠름**
- 30min/60min: 0.6초 (required 1.2초의 50%)
- 90min: 0.85초 (required 1.7초의 50%)
- **70% 이상의 precursor가 DPPP ≥ 7.0 달성 예상** ✅

### 3. Window Width 증가
- Window 수 감소로 인해 각 window가 더 넓은 범위 커버
- Coverage는 유지 (90-95%)
- **더 안정적인 MS2 acquisition 가능**

### 4. 효율성 향상
- Total window 수 35% 감소 (440 → 285)
- **더 빠른 acquisition 가능**
- **기기 부하 감소**

## 🎓 교훈

### Required Cycle Time의 역할

**기존 오해**: "Input cycle time이 window count를 결정한다"

**실제 동작**:
1. **FWHM 분포 분석** → Critical FWHM (P15 또는 P30) 추출
2. **Required cycle time 계산** = (1.7 × FWHM_critical) / Target_DPPP
3. **Window count 계산** = floor(Required_CT × Scan_Rate) - MS1_scans
4. **Min 제약 적용** = max(Natural_Windows, min_windows)

**핵심**: Required cycle time은 **FWHM 분포와 satisfaction target**에서 계산되며, input cycle time과는 무관합니다.

### Satisfaction의 영향

**85% → 70% 변경 효과**:
- Critical percentile: P15 → P30
- FWHM critical 증가 (더 넓은 peak 포함)
- Required cycle time 증가
- **더 많은 window 허용**

**특히 90min에서**:
- FWHM P15 = 5.09초 → P30 = 7.01초 (+37.7%)
- Required CT = 1.236초 → 1.702초 (+37.7%)
- Window count = 10 → **15** (+50%)

## 📌 권장사항

### 최종 설정 제안

**현재 설정 (min=10, sat=70%) 유지 권장** ✅

**이유**:
1. ✅ Window count가 gradient에 따라 적절히 변동
2. ✅ 모든 gradient에서 cycle time 목표 달성
3. ✅ 효율성 향상 (35% window 수 감소)
4. ✅ Coverage 유지 (90-95%)
5. ✅ 기기 부하 감소

### 용도별 권장 설정

**Quant-focused (정량 우선)**:
```r
TARGET_SATISFACTION <- 0.85  # Stricter
MIN_WINDOWS <- 15           # Higher minimum
→ More windows, narrower width, better quantification
```

**ID-focused (identification 우선)**:
```r
TARGET_SATISFACTION <- 0.60  # Relaxed
MIN_WINDOWS <- 10           # Lower minimum
→ Fewer windows, wider width, faster acquisition
```

**Balanced (현재 설정)**:
```r
TARGET_SATISFACTION <- 0.70  # Balanced
MIN_WINDOWS <- 10           # Allows flexibility
→ Good compromise between ID and Quant
```

## 📊 파일 위치

**결과 폴더**: `results_min10_sat70/`

**CSV 파일**: 24개
- 30min: 8 files (4 strategies × 2 modes)
- 60min: 8 files
- 90min: 8 files

**요약 파일**: `batch_processing_summary.csv`

**실행 로그**: `run_min10_sat70.log`

---

**생성 시간**: 2025-10-27
**설정**: min_windows=10, satisfaction=70%, instrument=Traditional Orbitrap
**Status**: ✅ 성공
