# MS1 multi-run 구현과 같은 조건 비교 검증

2026-10-19. 이슈 #17의 후속 사용자 요청에 따라 AIDIA와 alphaextract 모두 여러 run을 지원한다. 기존 handoff 문서는 수정하지 않았다.

## 변경 범위

- AIDIA: 현재 `Hayoung-hiro/ms1-feature-map-input` worktree에서 다중 파일 업로드, pooled/consensus 선택, 최소 검출 run 수, 선택 run 목록, 다중 run 비교를 구현했다.
- alphaextract: 사용자가 지정한 기존 `scan-compare-group-predicted-rt` worktree의 깨끗한 `6dc5638`에서 `feat/aidia-multi-run-export` 브랜치를 만들었다. 별도 `aidia-export` CLI, 데이터 계약·matching·manifest·사용 문서·테스트를 추가했다.
- 같은 batch·호환 가능한 LC/측정 조건을 권고한다. 시료명·LC 길이로 입력을 차단하거나 자동 분할하지 않는다. 자료 선택과 해석은 사용자에게 맡긴다.
- Source key/단위/숫자값, 중복 업로드, 공동 export의 그룹 무결성은 검증한다. 기존 cache를 수정하거나 remote push/merge하지 않았다.

## 통합의 의미

일반 feature 표는 검출 행을 모두 보존하는 pooled map으로 사용할 수 있다. 각 검출 행이 한 표를 가지므로 검출이 많은 run의 영향이 크다. Run 균등 가중이나 intensity 가중을 했다고 해석하면 안 된다.

alphaextract 공동 export의 그룹은 동일 charge, 기본 10 ppm 및 apex RT 0.15분 범위의 상호 유일한 후보로 만든다. 그룹 전체의 범위도 같은 tolerance 안에 있도록 제한하고, 모호한 후보는 별도 그룹으로 남긴다. 한 run에서 두 feature를 같은 그룹으로 합치지 않는다. 입력 파일 순서에 독립적이며 그룹 번호는 생물학적 ID가 아니다.

AIDIA consensus는 distinct run 검출 빈도와 중앙값을 사용한다. 기본 최소 검출 수는 DIA-NN과 같은 `ceiling(n_runs/2)`이며 사용자가 조정한다. Raw 관측 행을 `$feature_observations`에 보존한다. Native RT가 기본이고 자동 RT 정렬을 수행했다고 주장하지 않는다. 명시적인 run별 상수 shift를 적용할 수 있지만 FWHM은 바꾸지 않는다.

## 비교 입력과 고정 조건

이전 화면 비교의 30분 단일 MS1 run 대 60분 36-run ID report는 조건이 달라 근거에서 제외한다. 이번 비교에는 양쪽 모두 아래 세 run만 사용한다.

```text
20260608_SampleA_60min_Fixed_01
20260608_SampleA_60min_Fixed_02
20260608_SampleA_60min_Fixed_03
```

원본은 `D:/AIDIA_benchmark/mzml/cache_60min_mzml_trimmed/<run>/features.parquet` 세 파일과 `D:/AIDIA_benchmark/Diann_res_261012_60min/report.parquet`다. ID는 exact run 선택 후 Decoy=0, Q.Value≤0.01, PG.Q.Value≤0.01, cRAP 제외를 적용했고 Global/Lib 필터를 추가하지 않았다. 양쪽 최소 검출 수는 2/3이다. MS1 shift는 0으로 두어 native RT 좌표에서 비교했다.

ID map에서 만든 plan을 양쪽에 그대로 적용했다. 테스트 기준은 Exploris, MS2 30K/22ms, DPPP 4, 목표 충족률 80%다. 최종 고정 cycle time은 2.8916초, RT bin당 37 windows, RT 10–80분/5분 간격, m/z 390–970이다. 실제 과거 method의 시간 재구성이 아니라 동일 예산 비교를 위한 테스트 기준이다.

## 결과

| 항목 | ID consensus | MS1 consensus | 공통 MS1 평가 집합 |
|---|---:|---:|---:|
| 선택 run 수 | 3 | 3 | 3 |
| 전체 행 | 60,843 | 53,922 | 184,706 |
| 공통 범위 내 행 | 60,843 | 53,713 | 183,407 |
| DPPP≥4 충족 행 | 49,516 | 38,157 | 123,507 |
| 충족률 | 81.3832% | 71.0387% | 67.3404% |

alphaextract 입력 관측 수는 61,656 / 61,652 / 61,398개다. 전체 95,357개 그룹 중 1-run 그룹 41,435개, 2-run 그룹 18,495개, 3-run 그룹 35,427개이며, 2회 이상 검출된 53,922개를 설계에 사용했다. 평가에는 singleton을 포함한 모든 관측을 유지했다.

두 설계 모두 518 windows다. 동일 평가 집합에서 평균 부하는 354.07행/window이고, 최대 부하는 ID 설계 1,252 대 MS1 설계 1,278, CV는 0.81970 대 0.82180, 빈 window는 각각 22개다. 402/518 windows의 중심이 달라졌고 최대 중심 이동은 17 Da다. 전체 공통 범위를 덮으므로 범위 내 포함률 100%는 설계상 예상되는 값이며 동정률이 아니다.

같은 조건에서도 MS1 map은 낮은 m/z 쪽에 더 많이 분포했다. 서로 다른 검출 모집단의 차이를 확인한 것이며, MS1 map이 더 우수하거나 열등하다는 acquisition 증거는 아니다. FWHM 목표 미달도 자동으로 예산을 늘려 숨기지 않고 기록했다.

## 실행과 산출물

alphaextract worktree에서:

```powershell
python -m alphaextract.cli aidia-export --features <run01/features.parquet> <run02/features.parquet> <run03/features.parquet> -o <새 export 폴더>
```

AIDIA worktree에서:

```powershell
Rscript scripts/smoke_ms1_multirun.R test_output/ms1-multirun/alphaextract-export-verified
```

최종 export: `test_output/ms1-multirun/alphaextract-export-verified/`.
비교: `test_output/ms1-multirun/comparison-20261019-144926/`.

비교 폴더에는 원본 MD5 전후 기록, 입력별 DPPP 분모·출처, 동일 평가 집합 부하, window 위치 차이, 두 method CSV, 전체 비교 RDS/manifest, 기존 Stage 3/4 출력 7종, 공통 bandwidth를 쓴 m/z·RT·FWHM 분포 그림이 있다. 원본 세 feature 파일과 report의 MD5는 실행 전후 같았다.

## 검사

- Python: export/기존 matching/linked feature 관련 22 tests 통과. 최종 raw run 이름 override 및 UID-only 파일 혼합 지원 후 exporter 6 tests 통과. 커밋 전 전체 변경 파일을 대상으로 한 정적 검사 결과와 기존 항목 예외는 아래 최종 리뷰에 기록했다.
- AIDIA: 설치된 패키지 tests PASS 1,621 / FAIL 0 / SKIP 6. Skip은 기존 fixture 부재 또는 source 전용 main.R 때문이다. 기존 테스트 경고 8개는 데이터·패키지 빌드 버전·deprecated API 관련이다.
- `R CMD check --no-manual`: 오류 0, 경고 0, 기존 NOTE 2개(Shiny에서 쓰는 Imports, 기존 plot NSE/global symbol).
- 실제 동일 조건 parquet → alphaextract export → AIDIA consensus/pooled → 고정 예산 비교 → 기존 window export/시각화 경로 통과.
- 기존 `tests/manual/test_full_pipeline.R`도 선택된 실제 ID report로 통과. 이 테스트의 Astral 설정은 통합 검증용이며 과거 acquisition 재현이 아니다.
- Shiny `http://127.0.0.1:3839`에서 실제 run 파일 세 개 동시 업로드 후 `3 run(s), 53,922 design rows`와 `at least 2 runs` 표시를 확인했다.

## Shiny 파일 선택 목록 후속 검증

서로 다른 폴더의 `features.parquet`을 **Add files...**로 차례로 추가하도록 변경했다. 선택은 목록에 누적되며 **Compute** 전에는 adapter와 DPPP 계산을 실행하지 않는다. 개별 **Remove**, **Clear list**, 동일 내용 중복 방지, 설정 변경 시 결과 무효화와 재계산을 지원한다. 파일은 세션 전용 임시 디렉터리에 복사하므로 다음 업로드가 이전 Shiny 임시 파일을 교체해도 유지된다. 목록 초기화와 세션 종료 시 해당 복사본만 정리한다. DIA-NN report의 자동 처리는 유지했다.

- `devtools::test(filter = "ms1|shiny-intent")`: PASS 224 / FAIL 0 / WARN 3. 경고는 기존 빈 평가 집합의 CV 2건과 Shiny의 R 빌드 버전 1건이다.
- `devtools::test(filter = "shiny")`: PASS 146 / FAIL 0 / WARN 1. 경고는 Shiny의 R 빌드 버전이다. 위 검사와 일부 중복되므로 두 PASS 수를 합산하지 않는다.
- 임시 업로드 원본을 매번 삭제하는 회귀 테스트에서, 세 파일이 Compute까지 유지되고 3-run consensus로 계산됐다. 동일 파일 중복, 파일 제거·전체 초기화·New Analysis, 잘못된 파일과 최소 run 수 오류 복구, 세션 종료 시 복사본 정리도 통과했다.
- 브라우저에서 `alphaextract-export-verified/runs/001`, `002`, `003`의 실제 파일을 각각 업로드했다. 목록이 1→2→3개로 늘어나는 동안 `data_loaded = FALSE`이고 계산 요약이 비어 있었다. Compute 후 **3 run(s), 53,922 design rows**, 최소 검출 2 runs를 확인했다.
- 브라우저에서 첫 파일을 제거하면 계산 상태가 해제됐고, 같은 파일을 다시 추가한 뒤 Compute를 눌러 같은 결과를 얻었다. 사이드바도 **3 files / 3 runs**를 표시하며 화면 오류가 없었다. 세 입력 파일의 SHA-256은 검증 전후 동일했다.
- 로그: `test_output/test-feature-upload-queue.log`, `test_output/test-feature-upload-shiny.log`. 브라우저 상태 기록: `test_output/feature-queue-browser-before-compute.json`, `test_output/feature-queue-browser-after-compute.json`. 화면: `test_output/feature-upload-queue.png`.
- 갱신한 앱: `http://127.0.0.1:3839`, 실행 로그: `test_output/shiny-queue-20261019-151330/`. 기존 3838 앱 프로세스는 유지했다. 이 후속 변경에서는 alphaextract 코드와 원본 cache를 수정하지 않았다.

## DIA-NN 옵션과 파일 식별 표시 후속 검증

이후 요청에 따라 DIA-NN도 report 선택 후 **Compute**로 처리하도록 통일했다. **Combine runs**(기본: precursor 중앙값 consensus), **Minimum runs**(기본: 0 → run 수의 절반 올림), Q-value 필터를 사용자가 변경할 수 있다. 기본값은 기존 Stage 1 함수 인자에서 가져온다. Q/Lib.Q/Global.Q는 0.01, protein-group Q는 0.05, global 필터는 켬, channel 필터는 끔이다. 옵션 변경은 기존 결과를 무효화하고 재계산을 기다린다.

파일명이 모두 `features.parquet`이어도 구별할 수 있도록 업로드 시 **run 이름 열만 읽어 목록에 표시**한다. 이때 feature 검증·consensus·DPPP 계산은 실행하지 않는다. 일반 업로드의 원본 폴더 경로는 브라우저가 전달하지 않는다. 로컬 경로를 직접 추가하면 전체 경로도 표시하며, 이 기능은 loopback 실행에서만 기본으로 켠다. 숨겨진 입력 종류의 목록도 초기화하도록 처리해 브라우저에서 빈 목록 출력이 계속 대기하던 문제를 해결했다.

- `devtools::test(filter = "ms1|shiny")`: PASS 383 / FAIL 0 / WARN 3. 마지막 필터 요약 표시와 launcher 검사 추가 후 `shiny-diann-input` 재검사: PASS 53 / FAIL 0 / WARN 1. 두 결과에는 중복 검사가 있다. 경고는 기존 빈 집합 CV와 R 빌드 버전 관련이다.
- 기본 DIA-NN UI 인자로 만든 데이터가 `create_validated_dataset(path)`의 기존 결과와 동일한지 확인했다. 3-run fixture에서 최소 검출 1/2/3, 모든 관측 유지, Q/Lib/Global/PG/Channel 필터, 잘못된 값과 오류 복구를 검증했다.
- 경로에 공백과 따옴표가 있는 파일, 같은 파일명·다른 run 표시, DIA-NN 다중 report 거부, 원본 보존, loopback과 외부 호스트의 로컬 경로 기능 기본값 및 옵션 복원을 검사했다.
- 실제 `comparison-20261019-144926/selected_id.parquet`의 3 runs를 DIA-NN 기본 설정으로 처리하여 **60,843 rows**, 최소 검출 2 runs를 확인했다. 이 파일은 앞선 비교에서 추출·필터링한 입력이며 원본 전체 report의 필터 민감도 시험은 아니다.
- 실제 MS1 세 파일을 각각 브라우저로 추가했을 때 Compute 전부터 `...Fixed_01`, `...Fixed_02`, `...Fixed_03`이 구분되고 `data_loaded = FALSE`였다. Compute 후 **53,922 rows**를 다시 확인했다. 두 입력 화면의 표시 오류는 없었다.
- 실제 ID 입력으로 `tests/manual/test_full_pipeline.R` 통과. 로그: `test_output/diann-controls-manual-full.log`.
- 검사 로그: `test_output/test-diann-input-controls-final.log`, `test_output/test-diann-controls-final-targeted.log`. 화면: `test_output/ms1-run-labels.png`, `test_output/diann-options.png`. 브라우저 상태: `test_output/ms1-run-labels-browser-before.json`, `test_output/ms1-run-labels-browser-after.json`, `test_output/diann-options-browser-default.json`.
- 최신 앱: `http://127.0.0.1:3839`, 실행 로그: `test_output/shiny-diann-controls-20261019-153451/`. 기존 cache, 다른 worktree와 인계 문서는 유지했다.

## 커밋 전 최종 리뷰

리뷰 기준은 AIDIA `4cbb7b46cd68dd15259a73b5ee4f3933bce12ff0`, alphaextract `6dc563820c3d0ffe5e6add44265707e72fd580aa` 이후의 작업 트리 변경 전체다. 저장소 지침과 구현 명세를 별도 검토했다. 명세에는 issue #17과 인계 문서 외에 사용자가 후속 승인한 multi-run, 같은 batch 권고, Compute, DIA-NN 옵션과 파일 식별 표시를 포함했다.

- **Standards:** 두 저장소 모두 커밋을 막는 문서화된 규칙 위반은 없었다. 선택적 유지보수 의견 1건은 alphaextract `extract_raw_features()`가 FWHM 출처를 보존하려고 `FeatureFinder`의 private 메서드 세 개를 연결한다는 점이다. 향후 공개 추출 API에서 provenance를 반환하면 기존 추출 순서와의 결합을 줄일 수 있다. 현재 동작 오류는 확인되지 않았다.
- **Spec:** 수정이 필요한 확정 이슈 0건. 단위·apex·그룹 무결성, 동일 run 집합과 고정 측정 조건, 공통 평가 map, 파일 누적과 Compute 전후 상태, DIA-NN 기존 기본값, 원본 보존을 확인했다.
- **최종 R 전체 테스트:** `devtools::test(stop_on_failure = TRUE)`는 PASS 1,736 / FAIL 0 / WARN 8 / SKIP 4. Skip은 로컬 fixture 부재에 따른 기존 검사이며, 경고는 빈 집합 계산·R 패키지 빌드 버전·deprecated API 관련이다. 로그: `test_output/review-full-tests.log`.
- **최종 Python 테스트:** `pytest tests/unit/test_aidia_export.py tests/scanlevel/test_matching.py tests/scanlevel/test_features_linked.py`는 23 passed. 의존성 matplotlib/pyparsing의 deprecation warning 14건이 있었다. 검토한 producer 구현은 alphaextract의 로컬 커밋 `fd6006f`에 기록했다.
- **최종 패키지 검사:** 현재 추적 파일의 작업 트리 내용을 별도 소스 사본으로 만들어 `R CMD check --no-tests --no-manual`을 실행했고 오류 0 / 경고 0 / 기존 NOTE 2건으로 완료했다. 전체 테스트는 위에서 별도로 실행했다. 최초 직접 빌드는 제외 대상까지 임시 복사하는 단계에서 디스크 공간 부족으로 종료됐으며, 원본이나 cache를 삭제하지 않고 17 MB의 소스 사본으로 재검사했다. 로그: `test_output/review-package-check-snapshot/aidia.Rcheck/00check.log`.
- **Ruff:** 새 exporter와 테스트는 통과했다. 함께 변경한 `alphaextract/cli.py` 전체 검사에서는 이번에 수정하지 않은 import block의 `I001` 2건이 남는다. 기준 커밋에서도 같은 두 항목을 재현했으므로 이번 변경으로 생긴 경고는 없다.
- **공백 검사와 인계 보존:** alphaextract의 `git diff --check HEAD`는 통과했다. AIDIA는 원본 인계 문서 끝의 기존 빈 줄 1건만 보고되며, 해당 문서를 제외한 변경은 통과했다. 원문 보존 요청에 따라 그 빈 줄까지 유지했다.

## 남은 실제 검증

- Vendor raw 전체 파일을 새 CLI로 재추출하는 실환경 시험. 이번 raw CLI 연결 검사는 reader fixture이고, 실제 end-to-end 입력은 보존된 parquet cache다.
- Matching tolerance와 모호한 후보 처리의 precision/recall, 독립 run에서의 재현성, RT drift와 비선형 정렬 필요성.
- MS1/ID FWHM 차이와 폭이 넓거나 짧은 feature의 검출 선택 편향. 두 FWHM 정의가 동일하다고 가정하지 않는다.
- 같은 sample/batch와 동일 예산으로 ID/MS1 설계 method를 실제 획득하여 ID 수, 정량 CV, completeness, 간섭, 실제 cycle time 및 DPPP를 비교한다.

같은 batch 권고는 위 검증을 대신하지 않는다. 데이터 선택은 사용자가 하고, 프로그램은 선택과 계산 근거를 남긴다.
