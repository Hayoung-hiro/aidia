# PLAN: Stage 3 퇴화 입력 edge guards (P3 — 신규 발견)

> 단일 precursor bin·target=0·RT.Apex 부재에서 Inf/깨짐.

## Goal
전략·binning의 퇴화 입력에서 `Inf`/crash 대신 sane 값을 내도록 방어.

## 정확히 건드릴 파일 (line refs = main 기준, 구현 전 재확인)
- `R/mz_optimization.R`: outlier(L234-244 — **기본 `is.na(mz_sd)` guard는 이미 있음(PR#10)**; 이 plan은 all-NA/non-finite 미처리분만 보완), coverage `n_target` clamp(L198-220)
- `R/rt_binning.R`: `perform_fixed_rt_binning_internal`(L152-174), dispatcher rt_column(L122)
- **config 검증(SPEC §6 — ②)**: 입력/설정 진입점(`optimize_windows` 파라미터 검증부, `window_optimization.R:217-218` 인근)에 `absolute_min_width_da ≤ min_width_da < max_width_da` + 기기범위 sanity 추가
- `tests/testthat/`

## 단계별 구현
1. **outlier**: `sd()` 전 guard —
   ```r
   if (length(mz_values) < 2 || !is.finite(mz_sd <- sd(mz_values)) || mz_sd == 0)
     return(list(mz_min = min(mz_values), mz_max = max(mz_values)))
   ```
   (단일/동일 m/z bin → 범위=그 값, Inf 방지)
2. **coverage**: `n_target <- max(1L, min(n_total, n_target))` (target=0 → ≥1). 단 `n_total==0`(빈 bin)은 조기 반환(gemini — `max(1,0)=1`이 데이터>목표 모순 유발).
3. **fixed binning RT 컬럼**: dispatcher가 찾은 `rt_column`을 fixed path에 전달·사용, 또는 진입 시 `stopifnot("RT.Apex" %in% names(...))` 명확한 에러(현재는 조용히 하드코딩). 최소위험: assert(정상 데이터엔 무영향).
4. **config 검증(SPEC §6)**: 입력 단계에서 `absolute_min_width_da ≤ min_width_da < max_width_da` + `기기 m/z 범위 ≥ N·absolute_min_width_da` 확인, 위반 시 명확한 메시지로 거부. (digitization 런타임 크래시 경로를 사전 제거 — ②.)

## 엣지케이스
- outlier: `mz_values` 전부 NA → `min/max(., na.rm=TRUE)`가 Inf. `length<2` 체크를 non-NA 기준으로(`sum(!is.na)`).
- coverage `n_total==0`(빈 bin) → `min(0, ...)`=0 → 여전히 0. 빈 bin은 상류(merge_sparse_bins)에서 걸러지지만 방어적으로 `max(1, ...)` 유지 + 빈 bin 조기 반환.
- RT.Apex assert는 context상 "항상 존재"라 정상 경로 무영향 — 단 향후 다른 RT 컬럼 지원 시 assert가 막지 않도록 `rt_column` 전달이 더 견고(권장).

## 수락 기준
- [ ] 단일 precursor outlier bin → 유한 경계(테스트).
- [ ] `target=0` coverage → n_target ≥ 1, crash 없음.
- [ ] RT.Apex 없는 입력 → 명확한 에러 또는 rt_column 사용(조용한 오작동 아님).
- [ ] `devtools::test()` 그린.

## Do NOT
- 정상 입력 동작 변경 금지(퇴화 케이스만).
