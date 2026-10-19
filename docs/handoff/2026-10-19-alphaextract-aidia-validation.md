# alphaextract AIDIA export 후속 구현·실데이터 검증 인계

2026-10-19. 사용자는 PR을 직접 검토한 뒤 merge하기로 했으며, alphaextract에서 필요한 후속 작업을 기존 worktree로 연결하도록 요청했다. 기존 `2026-10-19-ms1-feature-map-input.md`는 그대로 유지한다.

## 현재 상태와 검증의 의미

- AIDIA `983eaca`: 외부 MS1 feature adapter, multi-run consensus/pooled, 고정 예산 ID/MS1 비교, Shiny 누적 업로드/Compute/DIA-NN 옵션 구현. 전체 R 검사 1,736개 통과. Vendor reader는 AIDIA에 없다.
- alphaextract `fd6006f`: `aidia-export --features ...` 및 `--raw ...` 구현. 관련 Python 테스트 23개 통과. `--raw`는 기존 reader와 feature finder를 재사용하며, 연결 테스트에서는 reader fixture를 사용했다.
- 실제 60분 Fixed 3-run parquet 184,706행을 export하고 AIDIA에서 최소 2-run consensus 53,922행 및 동일 run의 ID map을 비교했다. 이 결과는 저장된 자료를 이용한 offline 계산이다.
- **실제 vendor raw 재추출 검증**은 실제 Thermo `.raw` → reader → feature finder → 공동 export → AIDIA adapter를 새로 실행해 입력 경로가 동작하는지 확인하는 소프트웨어 통합 검증이다. 현재 코드에 raw 진입점이 없다는 뜻이 아니다. 기존 parquet 성공이나 reader fixture 통과를 이 검증의 완료로 간주하지 않는다.
- **Acquisition 비교 검증**은 같은 시료·주입량·LC·장비 시간 예산에서 ID 기반과 MS1 기반 method를 장비에 적용해 새로 측정하는 실험이다. 동정 수, 정량 CV/completeness, 간섭, 실제 cycle time·DPPP 등을 같은 분석 조건으로 평가한다. 소프트웨어 agent가 기존 cache만으로 완료할 수 없고, offline 분포·예상 부하 차이는 성능 개선의 실측 증거가 아니다.

## 수신 작업 공간과 경계

- Worktree: `C:/Users/Hayoung/orca/workspaces/alphaextract/scan-compare-group-predicted-rt`
- 브랜치: `feat/aidia-multi-run-export`; 구현 기준 커밋 `fd6006f79738f8661f38f64cd4892e976cd4596a`.
- PR의 base는 `Hayoung-hiro/scan-compare-group-predicted-rt`. 로컬 구현은 `6dc5638`에서 분기했고, 원격 base는 이후 `d9ea9a2`까지 진행했다. 이 인계 시점에 그 두 후속 커밋은 현재 feature 브랜치에 합치지 않았다. PR 범위와 현재 작업 변경을 먼저 확인한다.
- 먼저 alphaextract의 CLAUDE.md, docs/developer-guide.md, docs/aidia-export.md, 이 문서를 읽는다. AIDIA의 docs/ms1-feature-map-input.md와 docs/reviews/2026-10-19-ms1-multirun-validation.md도 참고한다.
- 코드·테스트·문서는 위 alphaextract worktree에서만 수정한다. AIDIA 코드와 다른 worktree는 읽기만 한다. 원본 raw/report/cache 및 기존 결과를 덮어쓰거나 일괄 재생성하지 않는다.
- 같은 batch/호환 LC 조건 사용은 안내하고 사용자가 선택한다. 시료 그룹·LC 길이에 따른 실행 차단을 추가하지 않는다. RT 단위·키·중복·그룹 구조 등 계산에 필요한 입력 검증은 유지한다.
- 현재 PR은 사용자가 검토한다. 이 후속 작업에서 자동 commit/push/merge하거나 현재 PR 내용을 원격에서 바꾸지 않는다. 구현과 검증을 완료하고 변경 목록과 결과를 한국어로 보고한다.

## 수행할 소프트웨어 작업

1. **추출 API와 provenance 연결 정리.** 현재 `alphaextract/aidia_export.py::extract_raw_features()`는 FeatureFinder의 private 메서드 세 개를 연결한다. 기존 `find_features()` 호출자의 기본 동작을 보존하면서 실제 FWHM 출처를 제공하는 공개 추출 진입점을 마련하고 exporter가 이를 사용하도록 한다. 실측 FWHM과 start/end 기반 대체값을 구분하며, 열 존재만으로 실제 계산 출처를 잘못 표시하지 않는지 실제 finder 코드까지 확인한다. 기존 raw reader를 재사용한다.
2. **명시적 실데이터 smoke 실행 도구.** 사용자가 입력 raw 목록과 새 출력 디렉터리를 지정하는 재현 가능한 스크립트/실행 예제를 추가한다. 실제 reader를 호출하는 검증은 opt-in으로 두고 일반 단위 테스트에 대용량 원본을 요구하지 않는다. 단일 run부터 확인한 뒤 같은 batch의 2~3 run을 공동 export하고 combined 파일과 분할 파일의 내용·그룹이 같은지 검사한다.
3. **계약과 실패 처리 검증.** run 이름과 UID, 명시적 RT/FWHM 단위, 실제 apex/경계, FWHM 출처, 중복/결측, run별 단일 그룹 관측, 동일 export_id를 확인한다. 원본 SHA-256 전후 일치, 사용한 설정·코드/환경 버전·실행 시간·행 수·예외를 기록한다. 입력 중 한 run 실패를 성공한 전체 batch처럼 보고하지 않는다. 원본이나 기존 export 덮어쓰기를 거부하는 동작을 유지한다.
4. **실제 raw → AIDIA round trip.** 생성된 파일을 AIDIA의 `create_ms1_feature_dataset()`에 넣어 pooled와 consensus/minimum-runs 처리가 되는지 확인한다. AIDIA 코드는 변경하지 않는다. 기존 parquet cache와 비교할 때는 동일 source·추출 설정·RT/스캔 범위를 확인한다. Trimmed mzML cache와 full raw의 feature 수가 같아야 한다고 단정하지 않는다.
5. **사용 문서와 회귀 테스트.** 공개 추출 API, fallback FWHM 출처, 실패 처리에 필요한 회귀 검사를 추가한다. 실행 명령, 입력 범위, 실제 성공/실패, 동일 조건 비교 가능 여부를 문서화한다. Matcher 개선은 실제 검증에서 확인한 오류를 고치는 범위로 한정하고, 자동 비선형 alignment·새 matching 알고리즘·실험 전체 재캐싱을 이번 작업의 선행 조건으로 만들지 않는다.

실제 reader 환경이 막히면 원인과 필요한 의존성을 정확히 기록하고 가능한 코드·fixture 검증을 마친다. mzML이나 모의 reader 결과를 vendor raw 성공으로 바꾸어 적지 않는다. 실제 raw에서 오류가 확인되면 재현 가능한 회귀 검사와 함께 수정한다.

## 실제 입력과 환경

Python: `C:/Users/Hayoung/miniforge3/envs/alphapept-env/python.exe`.

현재 펼쳐진 vendor raw 후보는 `D:/AIDIA_benchmark/Raw/30min/20260608_SampleA_30min_Fixed_01.raw`, `_02.raw`, `_03.raw`다. 실행 전 존재와 같은 조건 여부를 확인하고 하나부터 사용한다. 60분 raw는 `D:/AIDIA_benchmark/Raw/60min.7z`로 보관되어 있다. 30분 smoke 성공을 기존 60분 parquet 비교의 재현이라고 표현하지 않는다. 전체 archive 해제나 전체 raw 재처리를 시작하지 않는다.

기존 실제 비교 자료:

- `D:/AIDIA_benchmark/mzml/cache_60min_mzml_trimmed/20260608_SampleA_60min_Fixed_01/features.parquet` 및 `_02`, `_03` 디렉터리.
- 위 디렉터리의 `scan_meta.json`: 추출 환경·설정·원본 mzML/raw provenance. 경로의 과거 H: 드라이브 표기는 현재 경로로 오인하지 않는다.
- `D:/AIDIA_benchmark/Diann_res_261012_60min/report.parquet`; 30분과 비교가 필요하면 `Diann_res_261012_30min/report.parquet`에서 exact run만 선택한다.
- AIDIA `test_output/ms1-multirun/alphaextract-export-verified/`, `test_output/ms1-multirun/comparison-20261019-144926/`: 기존 결과는 읽기 전용.

인계 시점 C: 여유 공간은 약 0.45 GB, D:는 약 990 GB였다. 실행 전 다시 확인한다. 대용량 산출물은 D:의 명확히 구분한 새 검증 폴더에만 쓴다. 기존 cache를 삭제해 공간을 만들지 않고, 필요한 임시 경로도 이번 실행용 새 디렉터리로 지정한다. 데이터 파일은 Git에 추가하지 않는다.

## 완료 조건과 다음 실험

완료 보고에는 변경 파일, fixture 회귀 결과, 실제 vendor raw 실행 여부, run 수와 행 수, AIDIA 로딩 결과, 원본 보존 확인, 명령·로그·출력 위치를 포함한다. 검증된 범위와 아직 확인하지 못한 범위를 구분한다.

새 acquisition 실험은 이 작업의 완료 조건이 아니다. 두 method와 고정 측정 조건을 준비하는 데 필요한 입력·산출물은 설명하되, 사용자가 실제 장비에서 획득한 후에만 acquisition 성능을 판정한다. Matching precision/recall과 비선형 RT drift는 별도 근거가 필요한 검증 과제이며, 단순 run 간 일치율을 정확도나 FDR로 해석하지 않는다.
