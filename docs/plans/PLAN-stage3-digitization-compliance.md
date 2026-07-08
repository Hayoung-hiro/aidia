# PLAN: Stage 3 Digitization — SPEC 준수

> 실행자는 이 문서만으로 질문 없이 진행할 수 있어야 한다. 근거 SPEC: `docs/specs/2026-07-08-stage3-digitization-spec.md` (2026-07-08 grilling 개정판).

## Goal
`generate_windows_internal`의 density/variable 경로가 SPEC의 충돌 해소 규칙(§4)과 불변식(§7)을 따르게 한다. 핵심: width 제약 위반 시 **바로 fixed 균등폭으로 버리는 현재 동작**을, **(1) edge-expansion으로 N개 맞춤 → (2) shape 보존 정수 배분(width ≥ 절대하한 굳음·권장폭/max 무름) → (3) 권장폭 미달 허용(절대하한까지) → (4) fixed 최후수단** 순으로 교체한다. **count는 항상 N 고정**(감소·증가 없음, H6).

**성공 정의**: SPEC §7의 A1–A9가 새 단위테스트에서 모두 PASS하고, 기존 스위트가 회귀 없이 통과(단, 의도된 동작 변화 = fixed-fallback 빈도 감소·min `·0.9` 완화 제거는 스냅샷 갱신).

## 선행 의존
- **PLAN-width-semantics-split** (P4) 먼저 병합 — `isolation_width_floor_da`(=min_width_da 권장폭)/`absolute_min_width_da`(절대하한)/`greedy_cycle_range_da`/`generation_min_width_da` 명명이 이 plan의 floor 로직을 명확하게 한다. **특히 H5의 hard floor = `absolute_min_width_da`, 배분 target = `min_width_da`** 구분이 선행돼야 함.
- ~~per-bin-window-allocation~~ **폐기**: SPEC 개정으로 count는 균일 N 고정 → downstream 계약 변경 불필요. 이 plan은 항상 N개를 산출한다.

## 정확히 건드릴 파일 (line refs = main `6ebc5e4` 기준, 구현 전 재확인)
- `R/window_generation.R`
  - `generate_variable_windows_internal` (L241–, 폭 검증·fixed fallback 블록 L457–479) — 재작성 핵심
  - `generate_fixed_windows_internal` (L172–199) — 최후수단 경로 (변경 최소, 호출부만 정리)
  - `integerize_boundaries` (L541), `transform_boundaries_to_fz` (L559), `assemble_windows_from_boundaries` (L575) — **불변**(재사용만)
  - 신규 내부 헬퍼 `redistribute_integer_widths()` 추가
  - **시그니처 변경 없음**: edge-expansion은 data-relative·소규모라 `mz_range_min/max` 인자 배선 불필요(SPEC §4-1·③).
- `tests/testthat/test_window_digitization.R` — 신규 SPEC 불변식 테스트 추가
- (참고만, 수정 아님) `R/window_optimization.R:328-341` — width 명명은 P4에서

## 단계별 구현 순서

### Step 1 — 배분 헬퍼 먼저 (테스트 가능, 무배선)
`R/window_generation.R`에 순수 함수 추가:
```r
# 정수 커버폭 W를 N개 정수 width로 분배. 각 >= floor_da(굳은 하한).
# raw_widths(전략 shape) 비율을 최대한 보존. 반환 길이 N의 정수 벡터(합 == W) 또는
# NULL(분배 불가: N*floor_da > W → 호출부가 규칙4 fixed).
redistribute_integer_widths <- function(W, N, raw_widths, floor_da) {
  if (N * floor_da > W) return(NULL)               # 규칙4 신호
  target <- raw_widths / sum(raw_widths) * W        # shape 비율 → 실수 목표
  w <- pmax(floor_da, floor(target))                # 하한 적용 + 내림
  deficit <- W - sum(w)                             # 정수합 보정
  # deficit 분배: 양수면 잔차 큰 창부터 +1; 음수면 floor_da 초과 창에서만 -1
  ...
  stopifnot(sum(w) == W, all(w >= floor_da), length(w) == N)
  w
}
```
→ 단위테스트로 (a) 정확 나눔, (b) 하한 클램프+재분배, (c) `N*floor>W`→NULL, (d) 합 불변·길이 N을 검증.

**엣지케이스:**
- `floor(target)`이 합을 W 미만/초과 둘 다 만들 수 있다 — deficit 부호를 분기해 **양수면 +1(잔차 큰 창), 음수면 −1(단 결과가 floor_da 미만이 되면 그 창 건너뛰고 다음 후보)**. −1을 아무 창에나 주면 H5 위반.
- `raw_widths` 합이 0/NA(퇴화 전략 출력) → `rep(W/N, N)` 균등 target으로 폴백(여전히 정수 배분 경로, fixed와 다름).

### Step 2 — density 경로를 규칙 순서로 재작성
`generate_variable_windows_internal`에서 현재 "digitize → integerize → `if width∈[min·0.9,max·1.1] 위반 → fixed`" 블록(L457–479)을 아래로 교체:

1. `mz_lo <- floor(mz_min); mz_hi <- ceiling(mz_max); W <- mz_hi - mz_lo`.
2. **규칙1 edge-expansion (N 맞춤)**: `W < N * min_width_da`이면 부족분 `N*min_width_da - W`를 `mz_lo`↓/`mz_hi`↑로 관대하게 확장(대칭 기본). data-relative·소규모라 instrument 경계 clamp 불필요. W 재계산.
3. **working floor 결정**: 확장 후에도 `W < N * min_width_da`이면(드묾) `floor_da <- absolute_min_width_da`(권장폭 미달 허용, S3 무름), 아니면 `floor_da <- min_width_da`.
4. `w <- redistribute_integer_widths(W, N, raw_widths, floor_da)`. **항상 N개.**
5. `w`가 NULL이면(`W < N*absolute_min_width_da`, 극단) → **규칙4 fixed 최후수단**: `generate_fixed_windows_internal(mz_lo, mz_hi, N, absolute_min_width_da, max_da, fz_offset)` 반환 + `warning("digitization: N개 정수 배분 불가, fixed 폴백 (W=%d,N=%d)")`. (대개 config 검증 §6에서 사전 차단됨.)
6. `w`에서 경계 재구성: `boundaries <- mz_lo + c(0, cumsum(w))` (이미 정수).
7. **H5 검증(굳음)**: `stopifnot(all(diff(boundaries) >= absolute_min_width_da))`. 추가로 `sum(diff(boundaries) < min_width_da)`를 로그(S3 관측, 실패 아님). max는 검증 안 함(S2 무름).
8. `boundaries <- integerize_boundaries(boundaries, mz_min, mz_max)` (안전 재확인).
9. `if (fz_offset > 0) boundaries <- transform_boundaries_to_fz(boundaries)` — **H4, 순서 불변**.
10. `assemble_windows_from_boundaries(boundaries)` 반환 (N개).

**제거**: 기존 `width∈[min·0.9,max·1.1]` 이중 검증 + 두 fixed fallback(L461-464, L474-477). 대신 H1/H3만 사후 assert(H5는 7에서).

**엣지케이스:**
- fz 변환은 정수 width를 ×1.00045475로 스케일하므로 fz 후 width는 정수보다 ~0.05% 큼 — **min 하한은 fz 이전 정수 width 기준**. fz 후 min 미만 우려로 재폴백하던 기존 로직은 **불필요 → 제거**.
- **count는 항상 N**(H6): 반환 window 수 = N. 좁은 bin도 규칙1로 N 유지. `window_optimization.R:357`의 `expected = n_bins × N` deviation 로그는 정상(편차 거의 0).
- `mz_min == mz_max`(퇴화) → `W`가 작아 규칙1이 `N*min_width_da`까지 확장; 그래도 불가하면 규칙3(절대하한)→규칙4. 이 경로 테스트 추가.
- staggered 모드(`generate_staggered_windows_internal`)는 **이 plan 범위 밖**(별도 경로). fixed/density만.

### Step 3 — 테스트
`tests/testthat/test_window_digitization.R`에 SPEC §7 불변식 테스트 추가:
- `test_that("SPEC A5: all widths >= absolute_min_width (no 0.9 slack)", ...)` — 좁은 range·큰 N으로 강제.
- `test_that("SPEC A6: count == N always (edge-expand, no reduction)", ...)` — `W < N·min` 케이스에서도 반환 count == N(범위가 넓어졌는지 확인).
- `test_that("SPEC A2/A3: cover + contiguity", ...)` — 커버·gap0.
- `test_that("SPEC A4: fz deterministic + integer-width scaling", ...)` — fz 활성, 인접 간격 == 정수 × 1.00045475; 재실행 동일.
- `test_that("SPEC A7: fixed fallback only when redistribute NULL", ...)` — 정상 케이스에서 fixed 미발동.
- `test_that("shape preserved (A8)", ...)` — 전략 raw width와 생성 width 상관 ≥ 0.7.

## 검증 가능 수락 기준
- [ ] `redistribute_integer_widths` 단위테스트 4종 PASS (정확분·클램프·NULL·합/길이 불변).
- [ ] SPEC §7 A1–A9 테스트 전부 PASS.
- [ ] `devtools::test()` 전체 그린 (기존 "integer rounding violated width constraints → fixed" 경고 소멸/현저 감소; 스냅샷 갱신).
- [ ] density 경로에서 **absolute_min_width 미만 window 0개**(A5); `min_width_da` 미달은 로그로만.
- [ ] 반환 count == N **항상**(A6) — 좁은 bin은 edge-expansion으로 N 유지, 감소 없음.
- [ ] fz 활성 시 인접 경계 간격 == 정수 width×1.00045475(±1e-4), bit-재현(A4).

## Do NOT
- `integerize_boundaries`/`transform_boundaries_to_fz`/`OPTIMAL_INCREMENT` **수정 금지**(H4 결정성 근거).
- staggered 경로·smoothing·binning 건드리지 말 것(각각 별도 plan).
- count를 **증가·감소**시키는 어떤 경로도 추가 금지(H6 — 균일 N 고정). 좁은 범위는 edge로 넓혀 N 유지.
- `absolute_min_width_da`를 무르게 취급 금지(H5 굳음). max_width는 무름(S2 — 초과 허용, 로그만).
- `mz_range_min/max`를 시그니처에 추가하지 말 것(③ — edge-expansion은 data-relative, clamp 불필요).
