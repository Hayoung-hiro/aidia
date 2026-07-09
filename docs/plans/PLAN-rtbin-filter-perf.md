# PLAN: RT-bin 필터 O(n_bins×n_total) → split 1회 (#9 — 성능)

> GitHub issue #9. 정확성 변화 없는 순수 성능 개선.

## Goal
각 m/z 전략이 RT bin마다 `precursor_data %>% filter(rt_group == i)`로 전체 표를 재스캔하는 O(n_bins×n_total) 패턴을, **루프 전 `split()` 1회 + 인덱싱**으로 O(n_total)로 바꾼다. 결과 window·카운트는 **before==after 동일**해야 한다.

**성공 정의**: 실측 리포트에서 생성 window가 변경 전과 bit-동일, 실행 시간 유의미 감소.

## 정확히 건드릴 파일 (line refs = main 기준(codex 확인), 구현 전 재확인)
- `R/mz_optimization.R`: L141(LOCAL parent), L308(greedy), L421(KDE) — 세 곳의 per-bin filter 루프
- `R/window_generation.R`: L79 — 동일 패턴
- `tests/testthat/` — before/after 동일성 회귀테스트 + (선택) 벤치마크 스크립트

## 단계별 구현 순서
1. 각 루프 **직전**에 한 번 분할:
   ```r
   bins <- split(precursor_data, precursor_data$rt_group)   # 또는 dplyr::group_split + 키 보존
   ```
   `split`은 rt_group 값별 리스트(이름 = 값). 루프 내부에서 `bin_df <- bins[[as.character(i)]]`로 인덱싱.
2. 기존 `filter(rt_group == i)`를 `bins[[as.character(i)]] %||% precursor_data[0, ]`(빈 bin이면 0-row 동형 df)로 치환.
3. 4개 지점 모두 동일 패턴 적용. 각 지점의 downstream 계산(경계·카운트)은 **그대로**.
4. 실측 리포트로 before/after window 동일성 확인(스냅샷 또는 `all.equal`).

## 엣지케이스 (약한 모델이 놓치기 쉬움)
- **빈 bin**: `split`은 존재하는 값만 키로 만든다. `bins[[as.character(i)]]`가 **NULL**일 수 있음 → 반드시 0-row 동형 data.frame으로 폴백(컬럼·타입 보존). 그냥 NULL을 넘기면 downstream이 깨짐.
- **rt_group 밀도 가정**: #9 본문 — `densify_rt_group()`(R/rt_binning.R)이 rt_group을 dense `1..n_bins`로 보장하므로 인덱스 i가 키와 일치. 단 **정수 vs 팩터/문자** 주의: `split`은 키를 문자로 만들므로 `as.character(i)`로 접근(정수 인덱싱 `bins[[i]]`는 위치 기반이라 틀림!).
- **행 순서**: `split`은 원 순서를 bin 내에서 보존. `filter`도 보존 → 순서 동일. 단 `group_split` 사용 시 그룹 순서가 키 정렬을 따르는지 확인.
- **컬럼 부작용**: `split`은 `.pre_bin` 등 임시 컬럼도 함께 나눔 — 기존 filter 결과와 컬럼 동일하므로 문제없음(단 split 후 임시 컬럼 정리 시점 일치).
- **NA rt_group**: `split`은 NA를 기본 제외 → 기존 `filter(rt_group==i)`도 NA 제외라 동일(확인).

## 검증 가능 수락 기준
- [ ] 실측 리포트(또는 합성)에서 4개 지점 각각 before/after 생성 결과 `all.equal` (window 경계·카운트 동일).
- [ ] 빈 bin 포함 케이스에서 crash 없이 0-row 처리(테스트).
- [ ] 벤치마크: n_bins 큰 입력에서 실행시간 감소(예: `microbenchmark` 또는 `system.time` 전후 기록).
- [ ] `devtools::test()` 그린 — 특히 stage3/window_generation/mz_optimization 관련 테스트.

## Do NOT
- 경계·카운트 산출 로직 변경 금지(성능만). 결과가 달라지면 그건 이 plan의 실패.
- `bins[[i]]` 위치 인덱싱 금지(키는 문자 — `bins[[as.character(i)]]`).
- rt_group 밀도를 재보장하려 densify 로직 손대지 말 것(이미 보장됨).
