# PLAN: per-bin window allocation (B2 — ①의 참해결, 설계게이트)

> **설계결정 필요·핵심 데이터 계약 변경.** 약한 모델 단독 실행 부적합 — 사용자 사인오프 후 진행. digitization-compliance plan의 규칙3(count 감소)이 이미 per-bin 가변 count를 만들므로, 그 downstream 수용의 정본.

## Goal
`n_windows_per_bin`을 **scalar → per-bin 벡터**로 승격해, (a) digitization 규칙3의 count 감소와 (b) 향후 밀도-적응 창수 배분을 downstream이 1급으로 수용하게 한다.

## 선행/게이트
- **PLAN-stage3-digitization-compliance** 병합 후(규칙3이 count 감소를 이미 산출).
- **설계결정(사용자)**: 배분 정책 — "capacity budget 내에서 어떻게 bin별 창수를 정할지"(균등 vs 밀도비례 vs digitization이 정한 실측 count 채택). 이 plan은 **"digitization이 산출한 실측 per-bin count를 정본으로 삼아 downstream을 정합화"** 를 기본안으로 하되, 밀도-적응 증가는 별도(S3=증가 금지와 충돌하므로 SPEC 재검토 필요).

## 정확히 건드릴 파일 (계약 변경 — 광범위)
- `R/optimization_planning.R`: `window_count_per_bin` 산출(현 scalar) → 벡터 옵션
- `R/window_optimization.R`: L249-254(결정), L296-304/343-354(전달), L356-363(expected/deviation 계산)
- `R/window_generation.R`: `generate_windows_internal`이 per-bin count 수용
- DPPP 재검증: `R/window_optimization.R` L392-397(현 `total/n_bins` 균등 분배) → per-bin count 사용
- export/statistics: per-bin count를 읽는 지점 정합
- `tests/testthat/`: 균등벡터 회귀앵커 + 가변벡터 신규

## 단계별 구현
1. Stage 2 plan 계약에 `windows_per_bin`(정수 벡터, 길이 n_bins) 추가. 하위호환: scalar면 `rep(scalar, n_bins)`.
2. generation·DPPP·export·stats가 벡터를 소비하도록 순차 전환. **각 단계마다 "균등 벡터 = 기존 scalar 동작"을 회귀앵커로 고정.**
3. digitization 규칙3의 실측 count를 이 벡터에 반영(생성 후 실제 window 수 = per-bin count).
4. `expected_windows`/deviation 로그(L356-363)를 per-bin 합으로 정정.

## 엣지케이스
- **회귀 위험 최상**: 총 window 수·DPPP·cycle time 산식이 scalar×n_bins 전제. 균등 벡터가 **기존 출력과 bit-동일**해야(앵커). 안 그러면 그 단계 전환 실패.
- S3(count 증가 금지)와 "밀도-적응 증가"는 상충 — 이 plan은 **감소/정합화만** 기본. 증가 배분을 원하면 SPEC의 S3를 사용자와 재협의(별도).
- export 형식(contiguous-rt·Thermo)이 per-bin 균등을 가정하는지 확인(가변 count에서 t start/stop 배치 영향).

## 수락 기준
- [ ] 균등 벡터 입력 시 전체 파이프라인 출력이 scalar 시절과 **동일**(앵커 스냅샷).
- [ ] digitization 규칙3로 count 감소된 bin이 DPPP·export·stats에 **정확히 반영**(총 window 수 = per-bin 합).
- [ ] deviation 로그가 per-bin 합 기준으로 정확.
- [ ] `devtools::test()` 그린.

## Do NOT
- 사용자 설계 사인오프 없이 배분 정책(밀도-적응 증가) 도입 금지.
- S3(count 증가 금지)를 임의로 뒤집지 말 것 — 증가가 필요하면 SPEC 재협의.
