# SPEC: Stage 3 Window Digitization — Constraint Model

- **Date**: 2026-07-08
- **Status**: Confirmed (constraint model locked via grilling with user)
- **Scope**: AIDIA Stage 3 window generation (`R/window_generation.R`). Binning/strategy/smoothing 상류는 불변; 이 문서는 **"전략이 선택한 RT-bin의 m/z 범위를 정수 경계 window로 나누는 규칙"** 만 정의한다.
- **Author**: user (biryu32@kbsi.re.kr) + Claude (orchestrator, codex-critic/claude-main 리뷰 반영)

---

## 1. Motivation

Stage 3의 window generation은 물리·기기 제약 때문에 단순 "범위를 N등분"이 아니다. 분석물의 물리화학적 특성상 **window 경계는 fz-offset 이전에 정수여야** 하고, 이후 mass-defect 격자로 소수점 shift(fz)된다. 전략이 낸 목표 count·width는 이 정수·fz 제약 안에서 **가급적** 달성할 대상이다. 현재 구현은 제약 충돌 시 **전략 구조를 통째로 버리는 fixed 균등폭 fallback**으로 degrade하는데(`window_generation.R:452-456`), 이는 너무 뭉툭하다. 이 SPEC은 충돌 해소 우선순위를 명시해 degrade를 최소화한다.

## 2. Pipeline 위치

```
전략(optimize_mz_ranges) → RT-bin별 raw [mz_min, mz_max]  (SOFT 목표: count N, width)
  → apply_smoothing (range 평활)
  → ★ generate_windows_internal ← 이 SPEC의 대상 (정수화·width digitize·fz)
```

입력: `[mz_min, mz_max]`(전략 선택 범위), 목표 `count N`(Stage 2 capacity/duty-cycle), `min_width_da`, `max_width_da`, `fz_offset`, `window_mode`.

## 3. 제약 모델

### 3.1 HARD 불변식 (항상 성립 — 위반 시 결과 무효)

- **H1** fz 이전 모든 window 경계는 **정수**.
- **H2** **커버**: 최종 window 집합이 `[floor(mz_min), ceiling(mz_max)]` 전체를 덮는다 (edge 확장 허용).
- **H3** **contiguity**: 인접 window가 경계를 공유(gap·overlap 0). 연속 타일링.
- **H4** **fz 배치**: `fz_offset>0`이면 정수 경계에 mass-defect 격자 shift `ceil(N/1.00045475)·1.00045475 + fz_offset` 적용. **정수화(H1)를 선행**해야 snap `ceil(N/1.00045475)=N`이 성립해 fz shift가 **결정적(배치 재현)·충돌 없음(인접 정수→간격 1.0004 Da 보존)·정수 width 왜곡 없이 스케일**된다. → integerize→fz 순서 불변.
- **H5** 모든 window **width ≥ min_width_da** (굳은 하한, 물리 제약).

### 3.2 SOFT 목표 (제약 내 가급적, 우선순위 순)

- **S1** (최우선) 각 window 폭을 **전략 density shape**에 가깝게 유지(밀도 정보 보존).
- **S2** width ≤ max_width_da (**무름** — 초과 허용, 특히 sparse edge).
- **S3** count = N (**감소만 가능, 절대 증가 금지**). count가 SOFT 중 최저가치.

> 근거: count를 늘리면 "효율적 구간을 적절히 나눈다"는 전제가 깨지고 duty cycle을 초과(→DPPP 악화)한다. width를 min 아래로 내리면 물리 제약 위반. 따라서 min은 굳고 max는 무르며 count는 줄이기만 한다.

## 4. 충돌 해소 규칙 (우선순위)

`W = ceiling(mz_max) − floor(mz_min)` (정수 커버 폭).

1. **edge-expansion 관대 사용**: 정수 타일링이 안 맞으면 `[mz_min, mz_max]`를 가장자리로 확장(instrument m/z 범위 `mz_range_min/max` 내). edge는 precursor가 희소해 무해. (상한은 시나리오별 — 기본 넉넉히, 단 instrument 범위 초과 금지.)
2. **W ≥ N·min_width** (일반): **count N 유지**. 정수 width를 전략 shape 따라 배분하되 가능하면 ≤ max, 불가하면 **max 초과 허용(S2)**.
3. **W < N·min_width** (범위가 작음): **count 감소** — `N' = floor(W / min_width)`. **증가 금지**. ⇒ **bin별 count 가변** 발생. downstream(총 창수·DPPP·export·통계)이 per-bin count를 1급 데이터로 수용해야 함.
4. **fixed 균등폭 = 최후수단**: 위 규칙으로도 유효 타일링이 불가능한 경우에만. (전략 shape·밀도 정보를 버리므로 최대한 회피.)

## 5. 현재 구현과 갭

- ✅ H1/H2/H4: `integerize_boundaries()`(:532, floor/ceiling edge) + `transform_boundaries_to_fz()`(:550) + integerize→fz 순서(:448→460) — **준수**.
- ✅ H3: boundary-array-first 구조(:566 `assemble_windows_from_boundaries`) — 구조적 보장.
- ⚠️ H5/S: width digitize(Phase 3.5, :407-425) 후 `width∈[min·0.9,max·1.1]` 위반 시 **바로 fixed fallback**(:452-456), fz 후 재위반도 fixed+fz(:465-470). → **규칙 2·3(shape 보존 재분배·count 감소)을 건너뛰고 4(최후수단)로 직행.** min은 `·0.9`로 무르게, max는 `·1.1`로 취급 — SPEC(min 굳음/max 무름/count 감소)과 불일치.
- ⚠️ S3/규칙3: per-bin count 감소가 downstream에서 1급으로 다뤄지지 않음(scalar `n_windows_per_bin` 전제, `window_optimization.R:249`).

## 6. Acceptance (검증 가능 불변식)

주어진 임의 유효 입력에 대해 생성된 window 집합은:
- [ ] **A1(H1)** fz 이전 모든 경계 == 정수 (`all(boundaries == round(boundaries))`).
- [ ] **A2(H2)** `min(mz_start) ≤ floor(mz_min)` 및 `max(mz_end) ≥ ceiling(mz_max)`.
- [ ] **A3(H3)** `mz_start[i+1] == mz_end[i]` 모든 i (gap/overlap 0).
- [ ] **A4(H4)** fz 활성 시 인접 경계 간격 == 정수 width × 1.00045475 (±1e-4); 동일 입력 재실행 시 bit-동일.
- [ ] **A5(H5)** `all(width ≥ min_width_da)` — **예외 없이** (현재 `·0.9` 완화 제거).
- [ ] **A6(S3)** `count ≤ N` 항상 (증가 없음); 감소는 `W < N·min`일 때만.
- [ ] **A7(규칙4)** fixed 균등폭 fallback 발동은 "규칙 2·3으로 불가"일 때만 (로그로 사유 명시).
- [ ] **A8(shape)** 규칙 2 경로에서 생성 width의 상대 분포가 전략 raw width와 상관 ≥ 임계(shape 보존 정량).
