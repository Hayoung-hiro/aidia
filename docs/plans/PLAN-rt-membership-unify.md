# PLAN: RT membership 통일 (P2 — ②/O4)

> smoothing coverage 재계산은 `RT.Apex∈[rt_start,rt_end]`, generation/statistics는 `rt_group`. adaptive+merge에서 불일치.

## Goal
precursor→bin 소속 판정을 **단일 규칙**으로 통일(rt_group 우선, 없으면 RT.Apex 범위).

## 정확히 건드릴 파일 (line refs = main 기준, 구현 전 재확인)
- `R/smoothing_utils.R`: `.recalculate_coverage`(L479-480 RT.Apex 범위 필터)
- `R/window_generation.R`: L79(generation membership, rt_group 우선) — 공유 헬퍼로 추출
- **추가 소비처(codex 발견 — 같은 RT-range membership 사용, 정합 필요)**: `R/window_evaluation.R:96`, `R/plot_rt_quality.R:139`
- (참조, rt_group 우선이라 이미 정합) `R/window_statistics.R`

## 단계별 구현
1. 공유 헬퍼:
   ```r
   bin_membership <- function(precursor_data, rt_start, rt_end, rt_segment_id) {
     if ("rt_group" %in% names(precursor_data)) precursor_data$rt_group == rt_segment_id
     else precursor_data$RT.Apex >= rt_start & precursor_data$RT.Apex <= rt_end
   }
   ```
2. `.recalculate_coverage`와 generation의 소속 판정을 이 헬퍼로 교체.

## 엣지케이스
- **rt_segment_id == rt_group 라벨 가정**: `densify_rt_group()`(R/rt_binning.R:41, fixed/adaptive 적용 L184/L341)이 조밀한 `1..n_bins` 시퀀스를 보장하므로 이 가정은 이미 상당히 해소됨(codex 확인). mz_ranges에 `rt_segment_id` 컬럼 존재만 확인.
- fixed binning: 두 규칙이 원래 동일(연속 cut + 위치=라벨) → **fixed 결과 불변**. adaptive만 정합화(회귀 아님, 정확도 개선).
- rt_group 컬럼이 있는데 값이 mz_ranges의 rt_segment_id와 매핑 안 되는 경우(예외) → 헬퍼가 빈 소속 반환하지 않도록 매핑 확인.

## 수락 기준
- [ ] fixed binning coverage 변경 전후 동일.
- [ ] adaptive+merge 케이스에서 smoothing coverage 카운트 == generation window 카운트(정합).
- [ ] `devtools::test()` 그린.

## Do NOT
- generation 소속 로직의 의미 변경 금지(추출·재사용만).
