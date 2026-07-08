# PLAN: Stage 3 Digitization — SPEC 준수

> 실행자는 이 문서만으로 질문 없이 진행할 수 있어야 한다. 근거 SPEC: `docs/specs/2026-07-08-stage3-digitization-spec.md`.

## Goal
`generate_windows_internal`의 density/variable 경로가 SPEC의 충돌 해소 규칙(§4)과 불변식(§6)을 따르게 한다. 핵심: width 제약 위반 시 **바로 fixed 균등폭으로 버리는 현재 동작**을, **(1) edge-expansion → (2) shape 보존 정수 재분배(min 굳음·max 무름) → (3) count 감소(증가 금지) → (4) fixed 최후수단** 순으로 교체한다.

**성공 정의**: SPEC §6의 A1–A7이 새 단위테스트에서 모두 PASS하고, 기존 스위트가 회귀 없이 통과(단, 의도된 동작 변화 = fixed-fallback 빈도 감소·min 완화 제거는 스냅샷 갱신).

## 선행 의존
- **PLAN-width-semantics-split** (P4) 먼저 병합 권장 — `isolation_width_floor_da`/`greedy_cycle_range_da`/`generation_min_width_da` 명명이 이 plan의 min-firm 로직을 명확하게 함. 없이도 가능하나 `min_width_da` 3중용도 혼동 위험.
- 규칙3의 per-bin 가변 count의 **downstream 완전 수용은 PLAN-per-bin-window-allocation(B2)** 소관. 이 plan은 generation이 **올바른 count를 산출**하는 데까지 책임지고, downstream이 이미 per-bin `rt_stats$n_precursors`/실제 window 수를 읽는 부분(있음)은 유지한다.

## 정확히 건드릴 파일
- `R/window_generation.R`
  - `generate_variable_windows_internal` (대략 L246–476) — 재분배·count·fallback 로직 (핵심)
  - `generate_fixed_windows_internal` (L172–199) — 최후수단 경로 (변경 최소, 호출부만 정리)
  - `integerize_boundaries` (L532), `transform_boundaries_to_fz` (L550), `assemble_windows_from_boundaries` (L566) — **불변**(재사용만)
  - 신규 내부 헬퍼 `redistribute_integer_widths()` 추가
- `tests/testthat/test_window_digitization.R` — 신규 SPEC 불변식 테스트 추가
- (참고만, 수정 아님) `R/window_optimization.R:328-341` — width 명명은 P4에서

## 단계별 구현 순서

### Step 1 — 불변식 헬퍼 먼저 (테스트 가능, 무배선)
`R/window_generation.R`에 순수 함수 추가:
```r
# 정수 커버폭 W를 count개 정수 width로 분배. 각 >= floor_da(굳은 하한).
# raw_widths(전략 shape) 비율을 최대한 보존. 반환 길이 count의 정수 벡터(합 == W) 또는
# NULL(분배 불가: count*floor_da > W).
redistribute_integer_widths <- function(W, count, raw_widths, floor_da) {
  if (count * floor_da > W) return(NULL)          # 규칙3 신호(호출부가 count 감소)
  target <- raw_widths / sum(raw_widths) * W       # shape 비율 → 실수 목표
  w <- pmax(floor_da, floor(target))               # 하한 적용 + 내림
  deficit <- W - sum(w)                            # 정수합 보정(항상 >= 0? 아래 주의)
  # deficit 분배: 반올림 잔차 큰 창부터 +1 (또는 음수면 floor_da 초과 창에서 -1)
  ...
  stopifnot(sum(w) == W, all(w >= floor_da))
  w
}
```
→ 단위테스트로 (a) 정확 나눔, (b) 하한 클램프+재분배, (c) `count*floor>W`→NULL, (d) 합 불변을 검증.

**엣지케이스 (약한 모델이 놓치기 쉬움):**
- `floor(target)`이 합을 W 미만/초과 둘 다 만들 수 있다 — deficit 부호를 분기해 **양수면 +1(잔차 큰 창), 음수면 −1(단 결과가 floor_da 미만이 되면 그 창 건너뛰고 다음 후보)**. −1을 아무 창에나 주면 H5 위반.
- 모든 창이 이미 floor_da인데 deficit<0 이면 분배 불가 → 이 조건은 `count*floor>W`와 동치이므로 Step 시작에서 이미 NULL 처리됨(중복 방지).
- `raw_widths` 합이 0/NA(퇴화 전략 출력) → `rep(W/count, count)` 균등 target으로 폴백(단 이건 fixed와 다름 — 여전히 정수 재분배 경로).

### Step 2 — density 경로를 규칙 순서로 재작성
`generate_variable_windows_internal`에서 현재 "Phase 3.5 digitize → integerize → `if width∈[min·0.9,max·1.1] 위반 → fixed`" 블록(L403-457)을 아래로 교체:

1. `mz_lo <- floor(mz_min); mz_hi <- ceiling(mz_max); W <- mz_hi - mz_lo`.
2. **규칙1 edge-expansion** (선택적, 규칙3 진입 전): `W < n_windows * floor_da` 이고 instrument 범위 여유가 있으면, 부족분을 `mz_lo`/`mz_hi`로 확장(각 방향 최대 `expand_cap` Da, 기본 넉넉히; `mz_range_min/max` 인자 있으면 그 안에서). W 재계산.
3. **count 결정 (규칙2/3)**: `count <- n_windows; if (count * floor_da > W) count <- floor(W / floor_da)` (증가 없음). `count < 1`이면 `count <- 1`.
4. `w <- redistribute_integer_widths(W, count, raw_widths[1:count 대응], floor_da)`.
   - `raw_widths`는 전략 raw width(smoothing 이전 shape). count가 줄면 raw를 count개로 집계(인접 병합)해서 shape 유지. (구현 노트: 단순히는 `raw`를 count 구간으로 재-비닝.)
5. `w`가 NULL이면 → **규칙4 fixed 최후수단**: `generate_fixed_windows_internal(mz_lo, mz_hi, count, floor_da, max_da, fz_offset)` 반환 + `warning("digitization: shape-preserving 분배 불가, fixed 폴백 (W=%d,count=%d)")`.
6. `w`에서 경계 재구성: `boundaries <- mz_lo + c(0, cumsum(w))` (이미 정수).
7. **H5 검증(굳음)**: `stopifnot(all(diff(boundaries) >= floor_da))`. (max는 검증 안 함 — S2 무름.)
8. `boundaries <- integerize_boundaries(boundaries, mz_min, mz_max)` (안전 재확인, 이미 정수라 no-op 수준).
9. `if (fz_offset > 0) boundaries <- transform_boundaries_to_fz(boundaries)` — **H4, 순서 불변**.
10. `assemble_windows_from_boundaries(boundaries)` 반환.

**제거**: 기존 `width∈[min·0.9,max·1.1]` 이중 검증 + 두 fixed fallback(L452-456, L465-470). 대신 위 5·9 이후 **H1/H3만** 사후 assert(H5는 7에서). max 초과는 허용(로그로 카운트만).

**엣지케이스:**
- fz 변환은 정수 width를 ×1.00045475로 스케일하므로 fz 후 실제 width는 정수보다 ~0.05% 큼 — **min 하한은 fz 이전 정수 width 기준으로 판정**(H5는 "fz 이전 정수 경계" 맥락). fz 후 width가 min을 밑돌 일은 없음(스케일이 >1). 반대로 fz 후 min 미만 우려로 재폴백하던 기존 L465 로직은 **불필요 → 제거**(SPEC상 max만 무름, min은 fz로 오히려 커짐).
- `count` 감소 시 반환 window 수 < `n_windows_per_bin` — 이는 **의도된 동작(규칙3)**. `window_optimization.R:356-363`의 "expected = n_bins × n_windows_per_bin, deviation" 로그가 편차를 경고로 낼 수 있으나 **에러 아님**. deviation 계산이 per-bin 합을 쓰는지 확인하고, 아니면 주석으로 "규칙3 의도" 명시(수정은 B2).
- `mz_min == mz_max`(퇴화, 단일 m/z) → `W = ceiling−floor`가 0 또는 1. `count = floor(W/floor_da)`가 0 → count=1로 클램프, 단일 window `[mz_lo, mz_lo+floor_da]`(H2 커버 위해 mz_hi를 floor_da 확보하도록 확장). 이 경로 테스트 추가.
- staggered 모드(`generate_staggered_windows_internal`, L578-)는 **이 plan 범위 밖**(별도 경로, min/max 미검사 이슈는 codex-critic 지적 — 후속). 이 plan은 fixed/density만.

### Step 3 — 테스트
`tests/testthat/test_window_digitization.R`에 SPEC §6 불변식 테스트 추가:
- `test_that("SPEC A5: all widths >= min_width (no 0.9 slack)", ...)` — 좁은 range·큰 count로 강제, 각 width ≥ min 정확히.
- `test_that("SPEC A6: count only reduced, never increased", ...)` — `W < N·min` 케이스에서 반환 count == `floor(W/min)` ≤ N.
- `test_that("SPEC A2/A3: cover + contiguity", ...)` — 커버·gap0.
- `test_that("SPEC A4: fz deterministic + integer-width scaling", ...)` — fz 활성, 인접 간격 == 정수 × 1.00045475; 재실행 동일.
- `test_that("SPEC A7: fixed fallback only when redistribute NULL", ...)` — 정상 케이스에서 fixed 미발동(경고 없음) 확인.
- `test_that("shape preserved (A8)", ...)` — 전략 raw width와 생성 width 상관 ≥ 0.7(균등 fixed 대비 구별).

## 검증 가능 수락 기준
- [ ] `redistribute_integer_widths` 단위테스트 4종 PASS (정확분·클램프·NULL·합불변).
- [ ] SPEC §6 A1–A7 테스트 전부 PASS.
- [ ] `devtools::test()` 전체 그린 (기존 "integer rounding violated width constraints → fixed" 경고가 **사라지거나 현저히 감소**; 관련 스냅샷 갱신).
- [ ] density 경로에서 **min_width 미만 window 0개**(A5) — 기존 `·0.9` 완화 제거 확인.
- [ ] 반환 count ≤ 목표 N 항상; 감소는 `W<N·min`일 때만(A6).
- [ ] fz 활성 시 인접 경계 간격 == 정수 width×1.00045475(±1e-4), 동일 입력 bit-재현(A4).

## Do NOT
- `integerize_boundaries`/`transform_boundaries_to_fz`/`OPTIMAL_INCREMENT` **수정 금지**(H4 결정성 근거).
- staggered 경로·smoothing·binning 건드리지 말 것(각각 별도 plan).
- count를 **증가**시키는 어떤 경로도 추가 금지(S3).
- max_width를 굳은 상한으로 취급 금지(S2 무름 — 초과 허용, 카운트만 로그).
