# 설계: Contiguous RT-Schedule Export + `t start/t stop` 형식 (방법 2)

- **날짜**: 2026-06-12
- **상태**: 설계 승인 대기 (brainstorming → writing-plans 직전)
- **범위**: AIDIA Stage 3 export 전용. optimization/stats/plot/S3 내부 로직은 **불변**.
- **개정**: 재검토에서 경계 산출을 `rt_breaks` 인덱싱 → segment 중점 방식으로 변경(빈 bin 강건, S3 변경 제거).

---

## 1. 배경 / 문제

AIDIA가 생성한 method CSV의 RT 스케줄에 세 결함이 있고, 모두 동일 증상으로 수렴한다 —
**스케줄되지 않은 RT 구간 → 기기가 그 구간을 MS1-only로 취득 → DIA-NN duty cycle 구조 붕괴 / 분석 누락.**

1. **선행/후행 void**
   첫 segment가 첫 precursor RT부터 시작한다. 그 이전 구간(0 ~ 첫 precursor)은 스케줄된 DIA window가 없어 MS1-only. 마지막 segment 이후(wash)도 동일.
   - 원인: segment의 `rt_start/rt_end`가 precursor 실측 범위(`min/max RT.Apex`)이고, RT 범위가 precursor span으로 clip됨(`rt_binning.R`).

2. **segment 간 구조적 gap**
   window의 `rt_start/rt_end`가 **연속 경계가 아니라 precursor 실측 범위**라서 인접 segment끼리 연속이 아니다. 그 사이(precursor 없는 구간)는 스케줄 공백.

3. **반올림 gap/overlap**
   현재 export(`export_methods.R`)는 `RT Time`(center)·`Window`(width)를 **각각 독립 반올림**한다. 공유 경계가 두 반올림값의 합/차로 재구성돼 어긋난다.

### 1.1 예시 파일(`mass_list_example.csv`)이 증명하는 실제 결함

이미 `t start/t stop` 형식인데도 경계가 어긋나 있어, 결함이 실물로 드러난다:

| 경계 | 값 | 결함 |
|---|---|---|
| seg1 stop → seg2 start | 28.0 → 28.05 | gap 0.05분(≈3초) 누락 |
| seg3 stop vs seg4 start | 53.45 vs 53.4 | overlap (이중 측정) |
| seg4 stop vs seg5 start | 55.4 vs 55.35 | overlap |
| seg5 stop → seg6 start | 60.65 → 60.7 | gap 누락 |
| 첫 segment start | 11.4 | 선행 void (0 아님) |

---

## 2. 목표 / 비목표

### 목표
- export된 method가 `[acquisition_start, acquisition_end]`를 **빈틈없이 연속 타일링**한다(gap·overlap·void 모두 0).
- 출력 형식을 Thermo 네이티브 `t start (min)`/`t stop (min)`로 바꾸고, `mass_list_example.csv`와 **1:1 정렬**한다.
- **export-only 변경** — optimization/stats/plot/S3 내부는 건드리지 않는다.

### 비목표
- m/z 구조 균일화(edge-padding) — 가설 단계, 보류(별도 검토).
- 기존 취득 파일 trim — 별도 1회 작업으로 완료됨.
- 다른 export 형식(`export_center_mass_list`, `export_mz_range_list`) — 이번 변경 대상 아님.

---

## 3. 설계

### 3.1 신규 파라미터 (acquisition 경계)

| 파라미터 | 기본값 | 의미 |
|---|---|---|
| `acquisition_start_min` | `0` | 런 시작(주입). 첫 segment의 `t start`. |
| `acquisition_end_min` | `NULL` (필수 권장) | LC method 총 길이. 마지막 segment의 `t stop`. |

- 분석한 사람이 입력(가장 정확). `acquisition_end_min = NULL`이면 후행 void를 닫지 못함 → **경고** 후 마지막 segment의 `rt_end`를 그대로 사용.
- 전달 경로: `export_windows_to_csv()` **인자로 직접** 받는다(S3 객체 미변경). main.R / Shiny(Step 3 download 영역)에 입력 노출.

### 3.2 경계 산출 데이터 소스 (S3 변경 없음)

- export는 `OptimizedWindows$windows`의 기존 컬럼 **`rt_start`/`rt_end`**(segment별 precursor 실측 범위; `validate_OptimizedWindows`가 이미 필수로 요구)에서 경계를 산출한다.
- **`rt_breaks` 저장이나 S3 필드 추가는 하지 않는다.** 아래 알고리즘이 segment의 정렬 순서와 자기 `rt_start/rt_end`만 쓰므로, `rt_group` 연속성(1..n_bins)이나 `rt_breaks` 인덱스 정렬 같은 **취약한 암묵 가정에 의존하지 않는다**(빈/희소 interior bin에 강건).
  - 배경: `mz_optimization.R::make_mz_range_row`는 `rt_stats$rt_start[i]`(위치)와 `filter(rt_group == i)`(값)를 혼용해, 현재 파이프라인 전체가 "rt_group 연속"을 암묵 전제한다. 새 export는 여기 의존하지 않는다.

### 3.3 경계 산출 알고리즘 (`export_windows_to_csv` 핵심)

```
# 1. segment 추출: windows에서 distinct (rt_start, rt_end), rt_start 오름차순 정렬 → segs[1..k]
# 2. 경계 배열 B (길이 k+1)
B[1]   <- acquisition_start_min                          # 선행 void 제거 (=0)
B[k+1] <- acquisition_end_min                            # 후행 void 제거 (user input)
                                                         #   NULL이면 segs[k].rt_end + 경고
for j in 1..(k-1):
  B[j+1] <- (segs[j].rt_end + segs[j+1].rt_start) / 2    # 인접 segment 중점 → 연속 보장
B <- round(B, 2)                                         # round-once, 0.01분
stopifnot(all(diff(B) > 0))                             # 단조 증가 검증
# 3. 각 window → 자기 segment 인덱스 j의 [B[j], B[j+1]] 부여
#    t start (min) = B[j],  t stop (min) = B[j+1]
```

- **연속성 보장**: 인접 segment가 동일한 `B[j+1]`을 공유 → `t_stop[j] == t_start[j+1]`. round-once이므로 **어떤 정밀도에서도 gap·overlap 0**.
- **빈/희소 interior bin에 강건**: 빈 bin은 segs에 없고, 중점이 그 빈 구간을 양옆 segment로 분배 → **coverage hole 없음, 특별처리 불필요**.
- **중점이 항상 두 segment 사이**: cut 구간 구조상 `segs[j].rt_end < segs[j+1].rt_start`(비중첩)이 보장되므로 중점은 그 사이에 위치, 단조성 유지.
- window의 내부 `rt_start/rt_end`(precursor 실측)는 **그대로 둔다** — 플롯/통계용. export 산출물만 `B`를 쓴다.

### 3.4 정확한 CSV 형식 (`mass_list_example.csv` 기준)

헤더(정확히):
```
Compound,Formula,Adduct,m/z,z,t start (min),t stop (min),Isolation Window (m/z)
```

| 컬럼 | 값 | 현재 대비 |
|---|---|---|
| `Compound` | 정수 시퀀스(non-staggered) / `Cx_RTy_Wzz`(staggered) | 불변 |
| `Formula` | `""` | 불변 |
| `Adduct` | `(no adduct)` | **변경** (현재 빈 문자열) |
| `m/z` | `round(mz_center, 4)` | 불변 |
| `z` | `charge_state`(기본 1) | 불변 |
| `t start (min)` | `B[j]` | **신규** (← `RT Time (min)` 제거) |
| `t stop (min)` | `B[j+1]` | **신규** (← `Window (min)` 제거) |
| `Isolation Window (m/z)` | `round(mz_end - mz_start, 4)` | 불변 — 경계 정수화 후 `fz_offset` shift로 비정수가 되는 게 의도된 사양, 실제 폭 유지 |

---

## 4. 데이터 흐름

```
plan_optimization() / optimize_windows()           ── 모두 unchanged ──▶ OptimizedWindows
                                                       (windows: rt_start/rt_end/rt_segment_id 이미 존재)
export_windows_to_csv(optimized_windows, ...,
                      acquisition_start_min=0, acquisition_end_min=L)   [NEW args]
  └ segs ← distinct(windows[rt_start, rt_end]) 정렬
  └ B ← [start, midpoints…, end]; round(2)
  └ 각 window → t_start=B[j], t_stop=B[j+1]
  └ CSV (t start/t stop, Adduct="(no adduct)")
```

S3 객체·optimization 경로 변경 없음. 모든 변경은 export 함수 + 호출부 인자 전달에 국한.

---

## 5. 엣지 케이스

| 상황 | 처리 |
|---|---|
| `acquisition_end_min = NULL` | 후행 void 미처리 + 경고. `B[k+1] = segs[k].rt_end`. |
| `acquisition_end_min < segs[k].rt_end` | **error** (데이터보다 먼저 끝낼 수 없음). |
| `acquisition_start_min > segs[1].rt_start` | **error/경고** (보통 0이므로 비발생). |
| 빈/희소 interior bin | 중점이 자동 흡수 → coverage hole 없음(특별처리 불요). |
| segment 1개(k==1) | `B = [start, end]`, 단일 segment가 런 전체. |
| staggered | 두 cycle이 동일 `(rt_start, rt_end)` 공유 → segment 단위 동일 처리. distinct가 segment를 1개로 묶음. |

---

## 6. 영향 받는 파일

| 파일 | 변경 |
|---|---|
| `R/export_methods.R` | `export_windows_to_csv` RT 컬럼 로직 재작성(segment 중점 연속 경계 → t_start/t_stop, round-once), `Adduct="(no adduct)"`, acquisition 인자 추가 |
| `main.R` | `run_complete_pipeline`에 `acquisition_end_min` 인자 추가 → export로 전달 |
| `inst/shiny_app/ui_step3_results.R`, `server_downloads.R` | acquisition_end 입력 + 전달 |
| `tests/testthat/` | export 연속성/형식/빈-bin 테스트 |
| `CLAUDE.md`, `docs/domain-knowledge.md` | 8-컬럼 형식 설명 갱신; dead-zone "clip by construction" 서술을 "export는 acquisition 전체를 연속으로 덮음"으로 보강 |

> 재검토 결과 **`R/window_optimization.R`·`R/s3_classes.R`는 손대지 않는다** — 중점 방식이 기존 `windows` 컬럼만 쓰므로 `rt_breaks` 저장/validator/contract test가 불필요.

---

## 7. 테스트 계획

- **연속성**: 모든 인접 segment `t_stop == t_start`; 첫 `t_start == acquisition_start`; 마지막 `t_stop == acquisition_end`; gap/overlap 0.
- **형식**: 헤더가 예시 파일과 정확히 일치; `Adduct == "(no adduct)"`; t 컬럼 2자리.
- **빈 bin 강건성**: 인위적으로 비운 interior 구간(precursor 없는 RT 띠)에서도 hole 없이 연속 타일링.
- **엣지**: `acquisition_end_min=NULL` 경고; `< segs[k].rt_end` error; `k==1`; staggered 1-segment 묶임.
- **회귀**: `tests/manual/test_full_pipeline.R` 통과.

---

## 8. 확정된 결정

1. **`Isolation Window (m/z)`**: 실제 폭 유지. 경계 정수화 후 `fz_offset` shift로 비정수가 되는 것이 의도된 사양 → `round(mz_end - mz_start, 4)` 그대로.
2. **acquisition 경계 위치**: `export_windows_to_csv` **인자로만** 받는다(S3 객체·`OptimizationPlan` 모두 불변).
3. **경계 알고리즘(재검토 변경)**: `rt_breaks` 인덱싱 대신 **segment 중점** 방식. 이유 — 현 파이프라인의 "rt_group 연속" 암묵 가정에 새로 의존하지 않기 위해. 빈/희소 bin에 강건하고 S3 변경이 불필요.

---

## 9. 관련(범위 외) 작업

- **완료**: 기존 취득 파일의 MS1-only void 1회 trim(별도 영역, msconvert) — `docs/handoff/2026-06-12-void-trim-existing-data-context.md`.
- **보류**: m/z 구조 균일화(edge-padding) — 사용자 검토 후 재논의.
