# SPEC: Stage 3 Window Digitization — Constraint Model

- **Date**: 2026-07-08
- **Status**: Revised (constraint model re-locked via grilling — 2026-07-08). 초판 대비 주요 변경: (a) width hard floor를 `min_width_da` → **절대 물리 하한(absolute_min_width_da)** 으로 분리, `min_width_da`는 권장 SOFT 목표로 강등; (b) **count는 균일 N 고정**(RT 구간별 가변 count = 가변 cycle time은 장비/정량 비표준 → 배제), 규칙 3(count 감소) 삭제·좁은 bin은 edge-expansion으로 N 유지; (c) upfront config 검증 추가; (d) edge-expansion은 data-relative·소규모라 instrument 경계 인자 배선 불필요.
- **Scope**: AIDIA Stage 3 window generation (`R/window_generation.R`). Binning/strategy/smoothing 상류는 불변; 이 문서는 **"전략이 선택한 RT-bin의 m/z 범위를 고정 N개의 정수 경계 window로 나누는 규칙"** 만 정의한다.
- **Author**: user (biryu32@kbsi.re.kr) + Claude (orchestrator; codex-critic/gemini 리뷰 + grilling 반영)

---

## 1. Motivation

Stage 3의 window generation은 물리·기기 제약 때문에 단순 "범위를 N등분"이 아니다. 분석물의 물리화학적 특성상 **window 경계는 fz-offset 이전에 정수여야** 하고, 이후 mass-defect 격자로 소수점 shift(fz)된다. 전략이 낸 목표 width는 이 정수·fz 제약 안에서 **가급적** 달성할 대상이다. 현재 구현은 제약 충돌 시 **전략 구조를 통째로 버리는 fixed 균등폭 fallback**으로 degrade하는데(`window_generation.R:452-456`), 이는 너무 뭉툭하다. 이 SPEC은 충돌 해소 우선순위를 명시해 degrade를 최소화한다.

**창 개수(N)는 균일하다.** N은 상류(Stage 2 duty-cycle sync)에서 결정된 단일 값이며 **모든 RT bin이 동일한 N**을 갖는다. RT 구간마다 창 수를 바꾸면 `cycle_time = max(MS1, N × MS2)`가 구간마다 달라져 peak당 데이터 포인트(DPPP)가 불균일해지고, 표준 DIA 관행(RTwinDIA 등은 cycle 유지·m/z 범위만 이동)·다운스트림 분석 SW와 어긋난다. 따라서 digitization은 N을 **고정 입력**으로 받아 항상 N개를 산출한다 — 좁은 bin은 count를 줄이는 대신 **범위를 넓혀(edge-expansion) N개를 맞춘다.**

## 2. Pipeline 위치

```
전략(optimize_mz_ranges) → RT-bin별 raw [mz_min, mz_max]  (SOFT 목표: width shape)
  → apply_smoothing (range 평활)
  → ★ generate_windows_internal ← 이 SPEC의 대상 (고정 N개로 정수화·width digitize·fz)
```

입력: `[mz_min, mz_max]`(전략 선택 범위), **고정 count N**(Stage 2), `min_width_da`(권장 격리폭), `absolute_min_width_da`(절대 하한), `max_width_da`, `fz_offset`, `window_mode`.

## 3. 제약 모델

**용어 (① grilling):** `min_width_da`(기본 2 Da) = **사용자·기기가 권장한 격리폭**(instrument config `recommended_min_width_da`). `absolute_min_width_da`(기본 1 Da) = **펩타이드 물리화학 기반 절대 하한**. 성격이 다른 두 객체이며, 전자는 SOFT 목표·후자는 HARD 불변식이다.

### 3.1 HARD 불변식 (항상 성립 — 위반 시 결과 무효)

- **H1** fz 이전 모든 window 경계는 **정수**.
- **H2** **커버**: 최종 window 집합이 `[floor(mz_min), ceiling(mz_max)]` 전체를 덮는다 (edge 확장 허용).
- **H3** **contiguity**: 인접 window가 경계를 공유(gap·overlap 0). 연속 타일링.
- **H4** **fz 배치**: `fz_offset>0`이면 정수 경계에 mass-defect 격자 shift `ceil(N/1.00045475)·1.00045475 + fz_offset` 적용. **정수화(H1)를 선행**해야 snap이 성립해 fz shift가 결정적·충돌 없음·정수 width 왜곡 없이 스케일된다. → integerize→fz 순서 불변.
- **H5** 모든 window **width ≥ `absolute_min_width_da`** (굳은 물리 하한, 예외 없음).
- **H6** 생성된 window **count == N** (모든 bin 균일; 감소·증가 모두 금지).

### 3.2 SOFT 목표 (제약 내 가급적, 우선순위 순)

- **S1** (최우선) 각 window 폭을 **전략 density shape**에 가깝게 유지(밀도 정보 보존).
- **S2** width ≤ `max_width_da` (**무름** — 초과 허용, 특히 sparse edge).
- **S3** width ≥ `min_width_da` (**권장폭 무름** — 가능하면 권장폭 이상, 단 기기 경계로 제약될 때 `absolute_min_width_da`까지 허용). count가 아니라 **범위(edge-expansion)** 로 조정하므로, 정상 데이터에선 거의 항상 충족.

> 근거: N을 늘리면 duty cycle을 초과하고 cycle time이 불균일해진다(→DPPP 악화·비표준). N을 줄이면 RT 구간별 가변 cycle time이 되어 정량 일관성이 깨진다. 따라서 **count는 굳고(N 고정)**, 좁은 범위는 **edge로 넓혀** N을 맞춘다. width는 절대하한만 굳고 권장폭·max는 무르다.

## 4. 충돌 해소 규칙 (우선순위)

`W = ceiling(mz_max) − floor(mz_min)` (정수 커버 폭). 목표: **N개** 정수 width로 W를 타일링, 각 가급적 `min_width_da` 이상.

1. **edge-expansion (관대·data-relative)**: `W < N·min_width_da`이면 `[mz_min, mz_max]`를 가장자리로 넓혀 `W ≥ N·min_width_da`를 만든다(기본 넉넉히). 확장은 실제로 소규모(수 Da)이고 데이터는 범위 중앙에 있어 기기 경계에 거의 닿지 않는다 — 따라서 instrument 경계 인자 clamp는 **불필요**(③). 경계에 붙은 극단 케이스는 §6-config 검증 또는 아래 4로 흡수.
2. **정수 width 배분 (일반)**: `W ≥ N·min_width_da`이면 **N개** 정수 width를 전략 shape 따라 배분(S1). 각 ≥ `min_width_da`, 가능하면 ≤ `max_width_da`, 불가하면 max 초과 허용(S2 무름).
3. **권장폭 미달 허용 (제약)**: 최대 확장으로도 `W < N·min_width_da`이면(기기 경계에 붙은 드문 경우) N개를 유지하되 일부 width를 `absolute_min_width_da`까지 좁힌다(S3 무름). **count는 유지(H6).**
4. **fixed 균등폭 = 최후수단**: `W < N·absolute_min_width_da`(절대하한으로도 N개 불가 — 범위가 N Da 미만인 극단)일 때만. 이 경우 대개 **부적합 설정/데이터**이므로 사용자 안내(§6-config)로 사전 차단하거나 fixed로 degrade하고 로그.

## 5. 현재 구현과 갭

- ✅ H1/H2/H4: `integerize_boundaries()`(:532) + `transform_boundaries_to_fz()`(:550) + integerize→fz 순서(:448→460) — **준수**.
- ✅ H3: boundary-array-first 구조(:566) — 구조적 보장.
- ⚠️ H5/H6/S: width digitize(Phase 3.5, :407-425) 후 `width∈[min·0.9,max·1.1]` 위반 시 **바로 fixed fallback**(:452-456), fz 후 재위반도 fixed+fz(:465-470). → 규칙 1·2를 건너뛰고 4로 직행. min을 `·0.9`로 무르게, max를 `·1.1`로 취급 — 개정 SPEC(H5 절대하한 굳음·min 권장 무름·N 고정)과 불일치.
- ⚠️ config 검증(§6) 부재: `min_width_da < max_width_da`, `absolute_min_width_da ≤ min_width_da`, 기기 범위 sanity가 입력 단계에서 확인되지 않음.

## 6. Config 검증 (upfront, 입력 단계 — ②)

digitization 이전(입력/설정 단계)에서 **설정-불합리를 조기 거부**한다(런타임 크래시 경로 제거):
- `absolute_min_width_da ≤ min_width_da < max_width_da`.
- 기기 m/z 범위(mz_range_min/max) `≥ N · absolute_min_width_da` (절대하한으로도 N개가 불가능한 범위면 설정 오류).
- 위반 시 명확한 메시지로 거부. 데이터發 초협소 bin은 규칙 1~4가 흡수하므로 별도 런타임 로직 불필요.

## 7. Acceptance (검증 가능 불변식)

주어진 임의 유효 입력에 대해 생성된 window 집합은:
- [ ] **A1(H1)** fz 이전 모든 경계 == 정수 (`all(boundaries == round(boundaries))`).
- [ ] **A2(H2)** `min(mz_start) ≤ floor(mz_min)` 및 `max(mz_end) ≥ ceiling(mz_max)`.
- [ ] **A3(H3)** `mz_start[i+1] == mz_end[i]` 모든 i (gap/overlap 0).
- [ ] **A4(H4)** fz 활성 시 인접 경계 간격 == 정수 width × 1.00045475 (±1e-4); 동일 입력 재실행 시 bit-동일.
- [ ] **A5(H5)** `all(width ≥ absolute_min_width_da)` — **예외 없이**. 추가로 `min_width_da` 미만 window 수를 로그(S3 무름 관측, 실패 아님).
- [ ] **A6(H6)** `count == N` 항상 (감소·증가 없음). 좁은 bin은 edge-expansion으로 N 유지.
- [ ] **A7(규칙4)** fixed 균등폭 fallback 발동은 "규칙 1~3으로 불가"일 때만 (로그로 사유 명시).
- [ ] **A8(shape)** 규칙 2 경로에서 생성 width의 상대 분포가 전략 raw width와 상관 ≥ 임계(shape 보존 정량).
- [ ] **A9(config)** §6 검증이 불합리 설정을 입력 단계에서 거부.

## 8. 범위 밖 (별도 항목)

- **greedy+density ≈ fixed 안내**: greedy는 range = N×min_width_da라 밀도 변동 여지가 적어 density 모드가 fixed와 거의 같다. 전략층(`mz_optimization.R`) info 로그로 "밀도 적응은 kde/local 사용" 안내 — SPEC 밖 소항목.
- **acquisition m/z 범위 입력 승격**: 현재 `mz_range_min/max`(기본 400/1200)는 빈 bin fallback·greedy 중심에만 쓰이고 edge-expansion엔 불필요. 명시적 입력 승격은 향후 별도 PR(선택).
- **DPPP 표기**: target_dppp는 **whole-peak 기준**(`1.7×FWHM`, 검증 완료). 문헌의 PPP-FWHM은 1.7배 작으므로 UI/문서에서 단위 혼동만 방지(코드 버그 아님).
