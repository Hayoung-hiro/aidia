# 새 세션 핸드오프 — writing-plans (Contiguous RT Export, 방법 2)

> **이 문서의 용도**: 새 세션에서 이 기능의 *구현 계획*을 만들 때 첫 메시지로 제공할 컨텍스트.
> 설계는 승인 완료, 구현 미시작. 다음 행동은 **`superpowers:writing-plans` 실행**.

## 상태
- **브랜치**: `feature/contiguous-rt-export` (이미 생성, 스펙·핸드오프 커밋됨)
- **승인된 스펙**: `docs/superpowers/specs/2026-06-12-contiguous-rt-schedule-export-design.md` ← **먼저 읽을 것**
- **단계**: brainstorming(설계) 완료 → **writing-plans(구현 계획)** → 실행

## 새 세션에서 할 일
1. 위 스펙을 읽는다.
2. **`superpowers:writing-plans`** 스킬을 이 스펙에 대해 실행 → tiny-commit 단위 구현 계획 생성.
3. 계획 승인 후 구현(`superpowers:executing-plans` 또는 직접) → 테스트 → 커밋.

> 시작 멘트 예시: "`docs/superpowers/specs/2026-06-12-contiguous-rt-schedule-export-design.md` 읽고 `superpowers:writing-plans`로 구현 계획 만들어줘. 브랜치는 feature/contiguous-rt-export."

## 한 줄 요약 (스펙 미리보기)
`R/export_methods.R::export_windows_to_csv`를 고쳐 RT segment를 **연속 타일링**으로 내보낸다:
1. segment 경계 = 인접 segment(`windows$rt_start/rt_end`)의 **중점**, 가장자리는 `[acquisition_start=0, acquisition_end=user input]`.
2. 경계 배열을 **한 번만 `round(2)`** → gap/overlap 0(정밀도 무관).
3. 컬럼: **`t start (min)`/`t stop (min)`**(← `RT Time`/`Window` 대체), **`Adduct="(no adduct)"`**.
- 새 인자: `acquisition_start_min=0`, `acquisition_end_min`(필수) — **export 인자로만**, S3 불변.
- 출력 형식 기준 파일: `mass_list_example.csv`(repo 루트).

## 변경 범위
- 중심: `R/export_methods.R`
- 전달: `main.R`, `inst/shiny_app/ui_step3_results.R`·`server_downloads.R`
- 검증: `tests/testthat/`(연속성·형식·빈 bin), 회귀 `tests/manual/test_full_pipeline.R`
- 문서: `CLAUDE.md`, `docs/domain-knowledge.md`
- **손대지 않음**: `R/window_optimization.R`, `R/s3_classes.R` (중점 방식이라 `rt_breaks` 저장/validator 불요)

## 핵심 결정 (재검토 반영)
1. `Isolation Window (m/z)`: 실제 폭 유지(정수화 후 `fz_offset` shift로 비정수 = 의도).
2. acquisition 경계: `export_windows_to_csv` 인자로만(S3·`OptimizationPlan` 불변).
3. 경계 알고리즘: `rt_breaks` 인덱싱 대신 **segment 중점** — `rt_group` 연속성 가정에 의존 안 함(빈/희소 bin 강건).

## 주의/함정
- 현 파이프라인은 `mz_optimization.R::make_mz_range_row`에서 위치 인덱스와 `filter(rt_group==i)` 값을 혼용 → "rt_group 연속" 암묵 가정. **새 export는 여기 의존하지 말 것**(중점 방식이 그 이유).
- 정밀도(0.01분)는 연속성과 무관(round-once가 연속 보장). 충실도 knob일 뿐.
- staggered: 두 cycle이 같은 `(rt_start,rt_end)` → distinct로 1 segment 묶임.

## 범위 밖
- **보류**: m/z 구조 균일화(edge-padding) — 가설, 사용자 검토 후 재논의. (`docs/superpowers/specs/...` §9, task 추적)
- **완료**: 기존 취득 파일 MS1-only void 1회 trim — `docs/handoff/2026-06-12-void-trim-existing-data-context.md`.
