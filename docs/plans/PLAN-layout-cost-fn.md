# PLAN: layout cost 함수 씨앗 (P5 — ①③ 구조개선 seed)

> **상태: 보류(deferred)** — grilling(2026-07-08): 현재 결함과 직접 연결되지 않는 구조개선 seed. codex·gemini 모두 후순위 권고. 현행 실행 스코프(digitization SPEC 준수 + 하드닝) 밖. 향후 cost 기반 accept/rollback(B1b/B3)을 실제로 추진할 때 착수. 지금은 실행하지 않음.
>
> Stage 3 각 단계가 서로 다른 프록시를 최적화. 공통 품질 척도가 없어 smoothing/binning의 accept/rollback 판단 불가. 이 plan은 **순수 함수만** 추가(미배선).

## Goal
per-bin + 집계 layout 품질을 정량화하는 **순수·부작용 없는** `compute_layout_cost()`를 추가한다. **어디에도 배선하지 않는다**(무동작 변화). 이후 B1b/B3의 cost oracle.

## 정확히 건드릴 파일
- 신규 `R/layout_cost.R`
- `tests/testthat/test-layout-cost.R`
- (배선 없음 — 파이프라인 파일 미변경)

## 단계별 구현
1. `compute_layout_cost(mz_ranges, windows, precursor_data, weights = default_cost_weights())`:
   - 성분(per-bin): `coverage_loss`(미커버 precursor 비율), `precursors_per_window_cv`(window당 precursor 변동계수), `width_violation`(min 미만/max 초과 정도), `boundary_roughness`(‖Δ² mz_center‖, bin 가로질러), `cycle_time_penalty`(옵션).
   - 반환: per-bin data.frame + 가중 집계 스칼라.
2. `default_cost_weights()`: 명명된 기본 가중치(문서화, 추후 튜닝 대상).
3. 단위테스트: 합성 layout(완벽 커버·균형 vs 불균형·미커버)에서 cost 순서가 직관과 일치.

## 엣지케이스
- 빈 bin/0 precursor → 성분이 NaN 되지 않게 정의(0 또는 명시적 결측 처리).
- 성분 스케일 상이 → 가중 전 정규화(각 성분 [0,1] 또는 z). 문서에 정규화 규약 명시.
- **미배선 불변**: 이 plan 병합 후 기존 파이프라인 출력이 **한 톨도 안 바뀜**(테스트: 파이프라인 스냅샷 동일).

## 수락 기준
- [ ] `compute_layout_cost` 단위테스트: 좋은 layout < 나쁜 layout (각 성분·집계).
- [ ] 파이프라인 어디서도 호출되지 않음(grep로 확인) → 기존 결과 불변.
- [ ] `devtools::test()` 그린.

## Do NOT
- 이 plan에서 smoothing/binning에 배선 금지(그건 B1b/B3, 설계게이트).
- 가중치를 "정답"으로 확정 금지(기본값 + 튜닝 여지로).
