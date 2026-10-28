# MS1 feature map 구현·검증 결과 — 2026-10-19

이슈 #17의 구현을 `Hayoung-hiro/ms1-feature-map-input` worktree에서 수행했다. 기존 인계 문서를 유지했으며 다른 worktree·alphaextract 코드·연구 cache를 변경하지 않았다. 원격 push/merge는 수행하지 않았다.

## 구현

- `create_ms1_feature_dataset()`: 실제 alphaextract feature schema를 읽는다. 실제 apex, 원래 열, 명시적 단위, run 범위 key, FWHM 출처와 추출 provenance를 보존한다. 결측·비유한 값·잘못된 RT·중복·isotope/centroid 입력은 오류로 처리한다. Protein/peptide ID를 만들지 않는다.
- 기존 Stage 2/3/4, window export와 Shiny 입력 모드에 연결했다. MS1 FWHM은 planner·미리보기·시각화·temporal-density 경로에서도 단위를 추정하지 않고 전달한다. 기존 ID의 단위 추정 동작은 이번 변경 범위에서 유지한다.
- `create_validated_dataset(run_name=)`은 report에서 정확한 run을 consensus 전에 선택한다. 기본 ID 필터·중간점 apex·consensus 동작은 그대로다.
- `compare_input_maps()` / `export_input_map_comparison()`: 같은 scouting run의 map으로 기준 cycle time·window 수·instrument 설정·전체 m/z 범위·RT schedule을 고정한다. 동일 MS1 평가 map에 대한 포함 상태·부하·설계 차이·출처별 satisfaction·manifest·Thermo CSV를 저장한다. 기존 출력 폴더를 덮어쓰지 않는다.
- ADR-0005로 외부 feature table만 허용했다. Vendor raw/method reader는 추가하지 않았다.

## 실제 입력 및 실행 조건

실행 스크립트: [scripts/smoke_ms1_feature_map.R](../../scripts/smoke_ms1_feature_map.R).

최종 smoke 산출물: `test_output/ms1-feature-map/smoke-20261019-131541/`. 비교 CSV·JSON·RDS는 하위 `comparison/`, 기존 Stage 4의 PNG 7개는 `plots/`에 있다. 출력은 gitignored이며 대형 parquet·비교 데이터를 Git에 포함하지 않는다.

정확한 run: `20260608_SampleA_60min_dppp4_adap_dense_01`.

| 항목 | 확인값 |
|---|---|
| feature 원본 | 인계 경로의 `features.parquet`, 49,205행 |
| alphaextract 참고 HEAD | `6dc563820c3d0ffe5e6add44265707e72fd580aa` |
| 실제 cache schema | `scanlevel-1.0`; `rt_unit=minute`; 모든 FWHM 출처 `alpharaw_summed_isotope_trace` |
| 추출 metadata | alpharaw `bff74598fcd4f46c94afa939ab580a040db3ebea`, feature config hash `5b9005d155a30a93` |
| report의 정확한 run | 76,367행 |
| 연구 ID 필터 후 | 75,355행: Decoy=0, Q.Value≤0.01, PG.Q.Value≤0.01, cRAP 제외 |
| 기존 ID validation 후 | 75,297행: 기존 run+m/z+RT.Start 중복 제거로 58행 감소 |
| 추가 Global/Lib Q 필터 | 없음 |
| 기준 설정 출처 | **기능 검증용 가정**, 과거 acquisition 재현 아님 |
| 기준 instrument | Exploris preset, MS2 resolution 30K, MS2 IT 22 ms |
| 목표 | whole-peak DPPP 4, satisfaction 0.80, tolerance 0 |
| 고정 cycle time | ID map으로 한 번 계획한 2.8916초 (`actual_cycle_time_sec`) |
| 고정 window 수 | RT bin당 37개, 14개 bin, 설계당 518개 |
| 공통 범위 | RT 10–80분, 5분 bin; m/z 390–970 |
| 배치 | density, overlap 0, forbidden-zone offset 0, 권장 폭 2–80 Da |

기준 plan의 cycle time·scan-rate·window-range feasibility 검사를 통과했다. MS1 FWHM으로 plan을 다시 계산하지 않았다. RT 범위는 테스트 비교 범위이며 실제 LC gradient 길이라는 의미가 아니다. 최초 탐색 실행은 기본 MS2 설정의 scan-rate 경고를 기록했으며, 위의 명시적 MS2 설정을 최종 실행에 사용했다.

## 비교 결과

| 항목 | ID map | MS1 map |
|---|---:|---:|
| 설계 입력 행 | 75,297 | 49,205 |
| 공통 범위 안의 satisfaction 분모 | 75,231 | 49,205 |
| 공통 범위 밖 | 66 | 0 |
| DPPP 목표 충족 행 | 61,534 | 40,029 |
| 예측 satisfaction | 81.7934% | 81.3515% |
| 중앙 whole-peak DPPP | 5.0284 | 4.8632 |
| 동일 MS1 평가 map의 window당 평균 feature 수 | 94.9903 | 94.9903 |
| 동일 MS1 평가 map의 최대 window 부하 | 373 | 354 |
| 동일 MS1 평가 map의 전체 window 부하 CV | 0.866109 | 0.868951 |
| MS1 평가 feature가 없는 window | 31 | 32 |

두 설계 모두 공통 범위 안의 ID 75,231개 및 MS1 feature 49,205개를 포함한다. 전체 범위를 덮도록 제약했기 때문에 예상되는 결과다. 중심 위치는 518개 window 중 479개에서 달랐고 최대 절대 중심 이동은 30.5 Da, 최대 절대 폭 변화는 5 Da였다.

이 예시에서 MS1 설계는 최대 부하가 낮고 전체 부하 CV는 약간 높다. 따라서 MS1 입력이 항상 더 낫다는 결론은 나오지 않는다. 이 수치는 apex 기반 feature 개수이며 실제 동정 수, ion current, AGC charge, 동시 간섭 또는 정량 정확도를 나타내지 않는다.

단위 테스트의 의도적인 sampling 부족 조건에서는 두 map의 목표 미달이 그대로 출력됐고 기준 plan은 변경되지 않았다. 최초 실제 탐색 조건에서도 MS1 satisfaction 79.30%가 80% 목표 미달로 기록됐다. 최종 조건에서 목표를 충족했다고 해서 자동으로 MS1 기준 예산을 조정한 것은 아니다.

원본 보존은 `source_integrity.csv`로 확인했다. 실행 전후 MD5는 feature `ec6a20fe63f8b560520c5d82056cbc4c`, report `0c0045be724baf5d12fe3290c153826b`로 각각 동일하다. isotope/trace cache는 입력이나 필수 의존성으로 사용하지 않았다.

## 자동·통합 검증

- 변경 전 관련 ID/Stage 3/S3/FWHM 테스트를 실행해 기준 상태를 확인했다.
- 전체 `devtools::test()`에서 assertion 1,591개 통과, 실패/오류 0, skip 4. 이후 추가한 시각화 단위 전달 검사를 포함한 관련 테스트도 통과했다.
- 새 검사는 parquet round-trip, 초/분·짧고 넓은 FWHM, apex 보존, 원본 열·provenance, run 선택, key 중복, 결측·무한대·RT 오류, 기존 ID midpoint/identity/consensus, 고정 예산, 빈 bin, 경계 포함, 동일 평가 map의 brute-force 부하 비교, export geometry, Shiny 모드 변경·기존 결과 무효화를 포함한다.
- 기존 `tests/manual/test_full_pipeline.R`에 `AIDIA_TEST_REPORT` 경로 선택을 추가해 실제 선택된 ID parquet로 실행했다. Stage 1의 75,297행, Stage 2/3의 bin당 104개·총 1,352개 window, Stage 4의 5개 핵심 plot 및 단계 사이 계약 검사가 통과했다. 이 통합 테스트의 Astral 설정도 실행 검증용이며 실제 시료 acquisition을 재현하는 설정이 아니다.
- MS1 실제 smoke는 기존 Stage 3/4·8-column Thermo export와 7개 PNG 생성을 완료했다. Window-layout PNG를 직접 확인했다.
- 최종 소스로 `R CMD check --no-manual`을 수행했다: **오류 0, 경고 0, NOTE 2**. 설치 패키지 테스트는 **PASS 1,578 / FAIL 0 / WARN 8 / SKIP 6**이다. Check 로그는 `test_output/ms1-feature-map/package-check-verified/aidia.Rcheck/00check.log`, 테스트 로그는 같은 폴더의 `tests/testthat.Rout`에 있다. 남은 NOTE는 기존 `future`/`promises` Imports 사용 위치와 기존 plot의 NSE/`par` 선언 항목이다. 이번 run 선택에서 새로 생긴 `Run` NSE 항목은 해결했다.

Skip 4개는 이 worktree에 없는 기존 `mass_list_example.csv`, `data/30min_report.parquet` 관련 검사다. 기존 legacy flat-parameter/context 경고, 새 빈 평가 범위에서 CV가 정의되지 않는다는 경고, 설치된 의존 패키지의 R patch-version 경고가 있으며 실패는 아니다. 실제 통합 plot에서 기존 ggplot annotation/vectorized-text 경고가 발생했다.

설치 검사에서는 패키지에 포함하지 않는 `main.R` 소스 전용 검사 2개가 추가로 skip됐다. 초기 package check는 Windows에서 지원하지 않는 상속 `C.UTF-8` locale 때문에 중단됐으며, 최종 검사 프로세스에만 `LC_ALL=C`, `LANG=C`를 설정해 해결했다. 시스템 설정은 바꾸지 않았다. `.Rbuildignore`에 worktree `.git` 파일과 `test_output`을 제외하여 로컬 경로와 검증 데이터가 패키지에 포함되지 않게 했다. `git diff --check`와 새 문서의 로컬 링크 검사도 통과했다.

## 실행 방법 및 남은 검증

[사용 문서](../ms1-feature-map-input.md)에 입력 schema, R API, Shiny 경로와 출력 해석이 있다. 기본 실제 smoke는 저장소 루트에서 `Rscript scripts/smoke_ms1_feature_map.R`로 실행한다. 기존 통합 테스트에 다른 report를 쓰려면 PowerShell에서 `$env:AIDIA_TEST_REPORT='정확한 경로'`를 설정하고, 패키지를 load한 R 세션에서 `source('tests/manual/test_full_pipeline.R')`를 실행한다.

실제 acquisition의 target·resolution/IT/AGC·window·LC schedule을 확보하고, 동일 시료/load/LC에서 두 설계를 조건별 technical replicate 그룹으로 획득해야 한다. 실제 scan timing·경계·RT drift, 고정 분석 조건의 ID 깊이·결측·재현성·혼합비 bias를 확인해야 한다. 반복 번호끼리 임의 pairing하지 않는다. MS1 map에서 보이지 않는 ID 위치가 배제되지 않는지, 별도 run에도 설계가 유지되는지 평가해야 한다. 주기 재최적화, run 통합/matching, MAP-MS·AGC 최적화, 시간 단축/SPD는 후속 범위다.
