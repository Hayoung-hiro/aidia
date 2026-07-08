# PLAN: smoothing 불변식 guard (P1 — ②)

> smoothing이 mz_min/mz_max를 독립 평활 → `mz_min<mz_max` 미보장. quantile/outlier에서 음수 width 가능(greedy는 선형+상수width라 안전).

## Goal
smoothing 직후 `mz_min<mz_max`(+ width≥floor) 불변식을 3전략 공유로 강제. 위반 bin은 smoothing 이전 raw로 복원.

## 정확히 건드릴 파일
- `R/smoothing_utils.R`: `.smooth_mz_ranges_internal`(L440-472) 말미에 복원 훅, 또는 각 `apply_smoothing.*`(greedy L345/quantile L380/outlier L400) 공통 호출
- `tests/testthat/`

## 단계별 구현
1. 신규 `.repair_mz_ranges(smoothed, raw, floor_da)`:
   ```r
   bad <- smoothed$mz_min >= smoothed$mz_max | (smoothed$mz_max - smoothed$mz_min) < floor_da
   smoothed[bad, c("mz_min","mz_max","mz_width")] <- raw[bad, c("mz_min","mz_max","mz_width")]
   attr(smoothed, "n_repaired") <- sum(bad)
   smoothed
   ```
   `raw` = smoothing 입력(원 mz_ranges).
2. `.smooth_mz_ranges_internal`이 raw를 보존해 복원에 사용하도록, 또는 각 apply_smoothing.*에서 `smoothed <- .repair_mz_ranges(smoothed, mz_ranges, floor)` 호출 후 `.recalculate_coverage`.
3. 복원 발생 시 `n_repaired`를 로그/결과에 표면화.

## 엣지케이스
- **greedy는 사실상 발동 안 함**(선형 smoother + 상수 width → 교차 불가, 수학적). guard는 무해(no-op). 주 가치는 quantile/outlier.
- raw 자체가 이미 `mz_min>=mz_max`(퇴화 전략 출력)면 복원해도 여전히 나쁨 — 이건 P3(edge guards)에서 전략 단계 처리. guard는 "smoothing이 **악화**시킨 것"만 되돌림.
- `.recalculate_coverage`는 복원 **후** 실행(복원된 경계 기준).

## 수락 기준
- [ ] 인위적 quantile bin(좁아서 평활 시 교차)에서 음수 width → raw 복원, `n_repaired>0`.
- [ ] greedy 정상 실행 시 복원 0건, 결과 byte-identical.
- [ ] `devtools::test()` 그린.

## Do NOT
- greedy width 재중심 루프(L364-373) 제거 금지(별개). smoothing 자체 알고리즘 변경 금지.
