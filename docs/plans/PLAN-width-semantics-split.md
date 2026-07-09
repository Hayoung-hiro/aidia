# PLAN: width 파라미터 다중용도 분리 (P4 — ④)

> `min_width_da` 하나가 여러 뜻(권장 격리폭·greedy range 용량·생성 floor)으로 쓰이고, 별개 객체인 **절대 물리 하한**과도 혼동됨. digitization-compliance plan의 선행 명료화. **동작 불변(순수 명명).**

## Goal
width 관련 값을 **명명된 파생값으로 분리**해 의미를 명확히 한다(동작 불변). 특히 digitization의 H5(굳은 하한)와 S3(권장폭 무름)이 **서로 다른 상수**임을 코드에서 드러낸다.

## 정확히 건드릴 파일 (line refs = main 기준, 구현 전 재확인)
- `R/window_optimization.R` L328–341(greedy+density halving 특례), L253/300/347(전달)
- `R/mz_optimization.R` L291(greedy `mz_range_per_cycle = n_windows*min_width`)
- `R/smoothing_utils.R` L364(greedy smoothing width invariant)

## 단계별 구현
1. 파생값 도입(새 로직 아님, 이름만):
   - `absolute_min_width_da`  — **절대 물리 하한**(펩타이드 물리화학 기반, 기본 1 Da). digitization H5의 굳은 하한. 현재 코드의 `max(1.0, ...)`의 그 1.0을 명명.
   - `isolation_width_floor_da <- min_width_da`  — **권장 격리폭**(instrument `recommended_min_width_da`, 기본 2 Da). digitization S3의 무른 목표(권장폭). **hard floor 아님.**
   - `greedy_cycle_range_da <- n_windows_per_bin * isolation_width_floor_da`  — greedy range 용량
   - `generation_min_width_da <- (greedy+density면 max(absolute_min_width_da, min_width_da*0.5), else min_width_da)`  — 생성 floor. **halving은 절대하한(1 Da)을 존중하므로 개정 SPEC(H5=절대하한) 위반 아님** — 밀도 변동 목적으로 유지.
2. L291/L364/L328–341의 ad-hoc 식을 위 명명값으로 교체.
3. halving 특례(L334–341)를 **의도된 것으로 주석화**(density 변동 허용 목적; 절대하한 클램프 유지).

## 엣지케이스
- halving 기본값 `max(1.0, min_width_da*0.5)`를 **byte-identical 유지**(값 = `max(absolute_min_width_da, min_width_da*0.5)`). "단순화"하려다 값이 바뀌면 회귀 — 스냅샷 테스트로 고정.
- 네 개념이 실제로 같은 수치일 때도 이름은 유지(가독·flagship의 H5/S3 구분 전제).
- `absolute_min_width_da`는 현재 하드코딩 1.0 — 향후 config화 가능하나 이 plan은 **명명만**(값·동작 불변).

## 수락 기준
- [ ] 생성 window width가 변경 전후 **동일**(스냅샷).
- [ ] 네 개념이 코드에서 이름으로 구분됨(grep로 `min_width_da` 직접용도 축소 확인).
- [ ] `absolute_min_width_da`(하한)와 `isolation_width_floor_da`(권장)가 명확히 분리됨 — flagship이 H5/S3에 각각 참조 가능.
- [ ] `devtools::test()` 그린.

## Do NOT
- 동작 변경 금지(순수 명료화). 특례 로직 자체 제거/수정 금지(이 plan은 명명만).
- `absolute_min_width_da`와 `min_width_da`를 병합 금지(성격이 다른 별개 객체 — ① 결정).
