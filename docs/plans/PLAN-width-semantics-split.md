# PLAN: width 파라미터 3중용도 분리 (P4 — ④)

> `min_width_da` 하나가 세 뜻으로 쓰여 greedy+density 절반-완화 특례를 낳음. digitization-compliance plan의 선행 명료화.

## Goal
`min_width_da`의 3중용도를 **명명된 파생값 3개**로 분리해 의미를 명확히 한다(동작 불변).

## 정확히 건드릴 파일
- `R/window_optimization.R` L328-341(greedy+density halving 특례), L253/300/347(전달)
- `R/mz_optimization.R` L282(greedy `mz_range_per_cycle = n_windows*min_width`)
- `R/smoothing_utils.R` L364(greedy smoothing width invariant)

## 단계별 구현
1. 파생값 도입(새 로직 아님, 이름만):
   - `isolation_width_floor_da <- min_width_da`  (물리 최소폭)
   - `greedy_cycle_range_da <- n_windows_per_bin * isolation_width_floor_da`  (greedy range 용량)
   - `generation_min_width_da <- (기존 특례값; greedy+density면 max(1, min_width_da*0.5), else min_width_da)`  (생성 floor)
2. L282/L364/L328-341의 ad-hoc 식을 위 명명값으로 교체.
3. halving 특례(L334-341)를 **의도된 것으로 주석화**(density 변동 허용 목적).

## 엣지케이스
- halving 기본값 `max(1.0, min_width_da*0.5)`를 **byte-identical 유지**. "단순화"하려다 값이 바뀌면 회귀 — 스냅샷 테스트로 고정.
- 세 값이 실제로 같은 수치일 때도 이름은 유지(가독·후속 B의 전제).

## 수락 기준
- [ ] 생성 window width가 변경 전후 **동일**(스냅샷).
- [ ] 세 개념이 코드에서 이름으로 구분됨(grep로 `min_width_da` 직접용도 축소 확인).
- [ ] `devtools::test()` 그린.

## Do NOT
- 동작 변경 금지(순수 명료화). 특례 로직 자체 제거/수정 금지(이 plan은 명명만).
