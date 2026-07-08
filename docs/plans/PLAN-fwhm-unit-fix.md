# PLAN: FWHM 단위 명시화 (#8 — silent 60× 오류 제거)

> GitHub issue #8. 근거: FWHM 단위 추측 휴리스틱이 broad/sub-second 피크에서 60× 오변환.

## Goal
`ensure_fwhm_seconds()`의 "중앙값 < 1 → 분(×60)" 휴리스틱을 제거하고, **소스 툴(DIA-NN 등)의 고정 FWHM 단위를 로더에서 명시적으로 단언**하도록 바꾼다. DIA-NN 리포트는 단위 라벨을 안 담지만 **해당 툴의 시간 단위는 항상 고정**이므로, 추측 대신 소스별 고정 단위를 주입한다.

**성공 정의**: 분/초 두 단위 fixture에서 DPPP가 정확히 계산되고, 휴리스틱이 오변환하던 broad(≥1 min)·sub-second 케이스가 올바르게 처리됨. 단위 추측 경로 제거(또는 명시적 fallback+경고로 강등).

## Step 0 — DIA-NN FWHM 단위 확정 (필수 선행, 추측 금지)
실행자는 아래로 **DIA-NN report의 FWHM 컬럼 단위를 확정**한다:
1. 실제 리포트 확인: `data/` 또는 사용자 제공 `report.parquet`/`report.tsv`의 `FWHM` 컬럼 통계(중앙값·범위)를 `RT.Start`/`RT.Stop` 차이(= peak 폭, 분 단위)와 비교 — 스케일 일치 여부로 분/초 판정.
2. DIA-NN 문서/출력 규약 교차확인.
3. **판정 결과를 이 plan과 코드 주석에 기록**(예: "DIA-NN FWHM = minutes, 확인: report.parquet 중앙값 0.3 ≈ RT.Stop−RT.Start 중앙값"). 이후 단계는 이 상수를 사용.

## 정확히 건드릴 파일
- `R/dppp.R` — `ensure_fwhm_seconds()` (L172-179): 시그니처에 명시적 단위 인자 추가
- `R/data_loader.R` — DIA-NN 로더가 소스 고정 단위를 데이터/설정에 부착(예: attribute `fwhm_unit` 또는 ValidatedData 필드)
- 호출부: `R/plot_rt_quality.R:145`, `R/window_evaluation.R:85`, `R/s3_classes.R:676` — 명시적 단위 전달로 변경
- `tests/testthat/` — 신규 fixture(분·초)

## 단계별 구현 순서
1. **Step 0 완료**(단위 확정).
2. `R/data_loader.R`: DIA-NN 경로에서 로드된 데이터에 **소스 고정 단위**를 부착. 예: `attr(prec, "fwhm_unit") <- "minutes"` 또는 ValidatedData에 `fwhm_unit` 필드. 소스가 여럿이면 소스→단위 매핑 테이블.
3. `R/dppp.R`: `ensure_fwhm_seconds(fwhm_vector, unit = c("minutes","seconds"))` — `unit`이 주어지면 **그대로 변환**(minutes→×60, seconds→그대로), 추측 안 함. `unit` 미지정 시에만 기존 휴리스틱을 **경고와 함께** 사용(하위호환 fallback) 또는 에러.
4. 전체 벡터에 **한 번** 결정 적용(현재 per-subset 재추론 위험 제거) — 호출부가 상류에서 확정된 `unit`을 넘김.
5. 호출부 3곳을 `unit=<부착된 단위>` 전달로 갱신.

## 엣지케이스 (약한 모델이 놓치기 쉬움)
- **per-subset 재추론이 진짜 버그의 핵심**: `ensure_fwhm_seconds`가 bin/subset마다 호출되면 subset의 중앙값이 1을 넘나들며 **같은 런 안에서 단위가 뒤바뀔 수** 있다. 명시적 `unit`은 이걸 원천 차단 — 반드시 **런 전역 단위 1개**를 상류에서 확정해 모든 호출에 전달.
- FWHM에 NA/0/음수 혼입: 단위 변환 전 그대로 두되(변환은 곱셈이라 NA 보존), 후속 DPPP가 NA-safe인지 확인(감사 PR #10의 satisfaction NA 처리와 정합).
- 하위호환: 기존 저장된 결과/호출이 `unit` 없이 부르면 즉시 깨지지 않게 fallback 경로 유지(단 경고). 신규 로더 경로는 항상 `unit` 부착.
- 다른 로더 추가 대비: `unit`을 소스별로 선언하는 구조(하드코딩 산재 금지).

## 검증 가능 수락 기준
- [ ] Step 0 단위 판정이 문서·주석에 근거와 함께 기록됨.
- [ ] fixture(분: 중앙값 0.3 / 초: 중앙값 18) 두 개에서 DPPP 결과가 **동일한 초 기준 값**으로 수렴.
- [ ] broad 피크(1.2 min, 중앙값 ≥1) → 72s로 변환(기존 휴리스틱은 1.2s로 오변환하던 것) 회귀테스트 PASS.
- [ ] sub-second(0.5s, 중앙값 <1, seconds) → 0.5s 유지(기존은 30s로 오변환) 회귀테스트 PASS.
- [ ] 같은 런에서 subset별 호출이 **단위 뒤바뀜 없음**(전역 unit 고정) 테스트.
- [ ] `devtools::test()` 그린.

## Do NOT
- DIA-NN이 리포트에 단위를 담는다고 가정 금지(안 담음 — 소스 고정단위로 해결).
- 물리 임계값·DPPP 로직 자체 변경 금지(이건 단위 정확화만).
