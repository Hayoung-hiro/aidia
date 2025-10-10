# DIA Window Optimizer - RT Segment Comparison Summary

## 실행 완료 일시
**Date:** 2025-01-21  
**Input Data:** D:/Projects/DPPP_Window_isolation/DIANN-Output/report.parquet  
**Total Precursors:** 1,190,706 (validated)  
**m/z Range:** 400.4 - 901.5  
**RT Range:** 0.8 - 23.7 minutes  

---

## RT Segment별 최적화 결과 비교

### 📊 핵심 메트릭 요약

| RT Segments | Total Windows | Required Scan Rate | Achievable? | Recommended DPPP | Coverage |
|-------------|---------------|-------------------|------------|------------------|----------|
| **1 segment** | 300 | 100.0 Hz | ✅ **YES** | 0.94 | 102.0% |
| **2 segments** | 600 | 200.0 Hz | ❌ NO | 0.47 | 204.3% |
| **3 segments** | 900 | 300.0 Hz | ❌ NO | 0.31 | 300.5% |
| **4 segments** | 1200 | 400.0 Hz | ❌ NO | 0.24 | 401.8% |
| **5 segments** | 1500 | 500.0 Hz | ❌ NO | 0.19 | 499.4% |

---

## 🔍 상세 분석

### Segment 1 (단일 RT 구간)
- **Windows:** 300개
- **Scan Rate:** 100.0 Hz (기기 한계 내)
- **DPPP:** 0.94
- **Status:** ✅ **실현 가능한 유일한 설정**
- **Note:** 최적 scan rate (50 Hz)보다 높지만 최대 한계 내에서 동작

### Segment 2-5 (다중 RT 구간)
- **공통 문제:** 기기 한계 (100 Hz) 초과
- **Window 수 증가:** RT segment 당 300개씩 추가
- **Coverage 증가:** Segment 수에 비례하여 coverage 증가
- **실용성:** 현재 기기 설정으로는 실현 불가능

---

## ⚡ 기기 성능 제약

### Thermo Astral 스펙
- **최대 Scan Rate:** 100 Hz
- **최적 Scan Rate:** 50 Hz  
- **MS1/MS2 시간:** 5.0/3.0 ms
- **Cycle Time:** 3.0 seconds (고정)

### 제약 요인
1. **RT segment 증가 → Window 수 증가 → Scan rate 초과**
2. **300개 windows per segment가 기본 설정**
3. **현재 DPPP(0.94)가 너무 낮아 window 수 과다 생성**

---

## 🎯 권장사항

### 1. 단일 RT Segment 사용 (권장)
```json
{
  "rt_segments": 1,
  "target_dppp": 1.25,
  "achievable_dppp": 0.94,
  "windows": 300,
  "scan_rate": "100.0 Hz"
}
```

### 2. 다중 Segment 사용 시 DPPP 조정
| Segments | 권장 DPPP | 예상 Window 수 | 예상 Scan Rate |
|----------|-----------|---------------|----------------|
| 2 | 2.50 | 300 | 100 Hz |
| 3 | 3.75 | 300 | 100 Hz |
| 4 | 5.00 | 300 | 100 Hz |
| 5 | 6.25 | 300 | 100 Hz |

---

## 📁 생성된 파일

### 설정 파일
- `config_segment_1.json` - `config_segment_5.json`
- 각 파일의 FWHM 분석 비활성화 적용

### 결과 파일 (예상 위치)
- `optimized_windows_segment_1.csv` - `optimized_windows_segment_5.csv`
- `optimization_report_segment_1.pdf` - `optimization_report_segment_5.pdf`

---

## 🚨 주요 발견사항

1. **RT segment 수 증가는 window 수의 선형 증가를 야기**
2. **현재 기기 설정에서는 단일 segment만 실현 가능**
3. **다중 segment 사용 시 DPPP를 대폭 증가시켜야 함**
4. **Target DPPP 1.25는 현재 데이터셋에 비해 과도하게 낮음**

---

## 💡 결론

**현재 Thermo Astral 설정과 데이터셋으로는 RT segment = 1이 최적**이며, 
다중 segment 사용을 원한다면 **DPPP 값을 크게 증가**시켜 window 수를 줄여야 합니다.

**최종 권장:** RT segments = 1, DPPP = 1.25-2.0 범위에서 재최적화