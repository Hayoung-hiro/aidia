# MS1 feature map 대안 입력 구현 인계

이슈: https://github.com/Hayoung-hiro/aidia/issues/17
브랜치: Hayoung-hiro/ms1-feature-map-input
기준: origin/main, 4cbb7b46cd68dd15259a73b5ee4f3933bce12ff0
작성: 2026-10-19

## 현재 요청과 권한

사용자는 alphaextract의 MS1 feature map을 AIDIA의 대안 입력으로 지원하고 기존 ID 기반 설계와 비교하는 기능을 별도 브랜치·세션에서 **구현하고 검증**하도록 요청했다. 이 문서는 새 구현 세션으로 작업을 인계한다. 계획 제시에 그치지 말고 사용 가능한 구현, 테스트, 실제 입력 smoke test, 실행 문서를 완성한다.

기존 ms1-acquisition-design 브랜치는 MS1 QC·외부 요약 입력을 검토한 설계 작업이다. 그 문서의 과거 '설계만 수행' 범위는 이번 사용자 요청의 구현 범위를 제한하지 않는다. ADR-0004의 report-only 입력 계약은 이번에 사용자가 승인한 외부 feature table 입력에 한해 새 ADR로 확장한다. vendor raw/method reader까지 확대하지 않는다.

현재 worktree에서만 코드를 변경한다. 다른 AIDIA worktree, alphaextract 작업 공간, 기존 연구 출력·cache는 참고 자료로 읽는다. 기존 uncommitted 변경을 가져오거나 다른 브랜치를 병합하지 않는다. 대량 재캐싱과 실제 장비 재획득은 이 작업에 포함되지 않는다. 원격 push/merge는 이번 인계 범위에 포함되지 않는다.

## 연구 배경과 지켜야 할 해석

- 연구 목표는 제한된 장비 시간 안에서 scan 횟수와 선택성·이온 수집시간의 균형을 조정한다는 AIDIA 가설을 검증하는 것이다.
- 현재 논문의 결론은 동일 LC 조건에서의 동정 깊이·반복 동정 성능 향상이다. 실제 시간 단축과 SPD 증가는 별도 후속 검증이다.
- 30/60/120 min이라는 파일·조건명은 void 구간을 제외한 분석 구간의 이름이다. 정확한 LC gradient 길이나 injection-to-injection 주기로 추정하지 않는다.
- 조건별 technical replicate를 그룹으로 비교한다. 반복 번호끼리 임의 pairing하지 않는다.
- ID map은 동정된 대상에, MS1 map은 검출된 feature에 의존한다. 어느 쪽이 항상 더 완전하다고 가정하지 않는다.
- 60분 D4의 물리적 평가 가능 회복 집합 6,093/6,118개 중 4,717/4,733개는 여섯 run 모두 MS1 feature 미대응이었다. 이는 신호 부재가 아니고, MS1 map에서 안 보이는 위치도 DIA window에 포함되면 측정될 수 있다.
- 현재 본문에서 적용하는 target_dppp/target_satisfaction은 실제 acquisition 생성에 사용한 설정이다. 수치를 찾지 못하면 UI/API 기본값을 실제 실험값처럼 사용하지 않는다.
- DPPP는 AIDIA의 whole-peak 기준 1.7 × FWHM / cycle time이다. ppp_fwhm 및 예상 RT ±15초에서 직접 집계한 scan 횟수와 구분한다.
- 구현 비교에서는 실제 acquisition 설정이 없어도 명시적인 test/reference 설정으로 기능을 검증할 수 있다. 이 경우 실행 설정을 가정으로 기록하고 실험 재현이라고 표현하지 않는다.

## 먼저 읽을 자료

현재 저장소의 CLAUDE.md, 적용 가능한 지침, docs/adr/0004-result-driven-input-no-raw-file.md 및 이슈 #17을 읽는다.

다음 파일은 다른 worktree에 있는 참고 문서이며 변경하지 않는다.

- C:/Users/Hayoung/orca/workspaces/aidia/ms1-acquisition-design/docs/reviews/2026-09-21-ms1-acquisition-design.md
- C:/Users/Hayoung/orca/workspaces/aidia/AIDIA-main/docs/reviews/2026-09-21-ms1-dia-integration-review.md
- C:/Users/Hayoung/orca/workspaces/aidia/AIDIA-main/docs/handoff/2026-09-21-ms1-acquisition-design.md

생산자 코드:

- C:/Users/Hayoung/orca/workspaces/alphaextract/scan-compare-group-predicted-rt/alphaextract/feature_finder.py
- C:/Users/Hayoung/orca/workspaces/alphaextract/scan-compare-group-predicted-rt/alphaextract/scanlevel/features.py
- 확인한 alphaextract HEAD: 6dc563820c3d0ffe5e6add44265707e72fd580aa

이 생산자에서 features는 feature 단위, feature_isotopes는 isotope hill 단위, feature_traces는 centroid 단위다. features의 rt_unit은 minute이고 feature_uid는 run_name + #F + feature_id로 만들어진다. FWHM 출처는 alpharaw_summed_isotope_trace 또는 substituted_half_start_end로 구분된다. 실제 파일 schema와 metadata를 다시 확인한다.

AIDIA의 현재 column selection은 Protein.Group과 Precursor.Id를 요구하고, data validation은 RT.Start/Stop 중간점으로 RT.Apex를 계산한다. 새 feature 입력에서는 실제 rt_apex를 보존하고 protein identity를 가짜로 채워 검증을 통과시키지 않는다.

## 로컬 검증 데이터

소규모 실제 입력 테스트에 아래 existing cache를 읽을 수 있다.

- feature table: D:/AIDIA_benchmark/mzml/cache_60min_mzml_trimmed/20260608_SampleA_60min_dppp4_adap_dense_01/features.parquet
- 같은 디렉터리의 feature_traces.parquet, feature_isotopes.parquet, scan_meta.json, scans.parquet는 필요할 때만 참고한다. 첫 입력 adapter에 전부 필수화하지 않는다.
- DIA-NN report: D:/AIDIA_benchmark/Diann_res_261012_60min/report.parquet
- 해당 report에서 동일 run을 정확히 선택하여 ID map과 MS1 map을 비교한다.
- 연구 참고: D:/AIDIA_benchmark/review_hye_feature_detail_261015/AIDIA_paper_summary_2026-10-15_KO.md
- Python parquet 점검이 필요하면 C:/Users/Hayoung/miniforge3/envs/alphapept-env/python.exe 사용 가능.

연구의 ID 필터는 Decoy=0, Q.Value<=0.01, PG.Q.Value<=0.01, cRAP 항목 제외다. Global.Q.Value 추가 필터는 쓰지 않았다. 이 조건을 새 MS1 feature 입력에 ID 품질 조건으로 적용하지 않는다.

원본 cache는 읽기 전용으로 사용하고 실행 산출물은 이 worktree 아래 별도 gitignored 출력 또는 명확히 구분된 검증 디렉터리에 저장한다. 전체 report/parquet를 Git에 추가하지 않는다. 기존 테스트 패턴을 따라 작고 결정적인 fixture를 만든다.

## 구현 우선순위

1. 명시적인 MS1 feature 입력 계약과 adapter, 단위/apex/key/provenance 검증.
2. 기존 ID 경로를 보존한 window 설계·export 연결. 사용할 수 있는 R/API 예제를 제공하고, 기존 Shiny 입력 경로에는 필요한 최소 입력 모드 선택을 연결한다. 별도 UX 재설계는 하지 않는다.
3. 기준 plan의 cycle time/window 수/공통 RT·m/z 범위를 고정한 ID/MS1 map 비교 및 결과 export. 같은 평가 map으로 두 설계를 비교한다.
4. 단위·계약·ID 회귀·실제 parquet smoke test와 사용자 실행 문서.
5. 완료 시 변경 내용, 수행한 검사, 실제 비교 산출물 위치, 남은 실제 acquisition 검증 항목을 한국어로 보고한다.

MS1 FWHM을 사용한 cycle-time 재최적화, 대규모 replicate feature matching, 전체 raw 재캐싱, P10–P90 진단(#16), MAP-MS/AGC 시간모델 변경은 초기 구현 완료를 막는 선행 조건으로 만들지 않는다.

## 이슈 요구사항 사본

## 목적

alphaextract가 추출한 **MS1 feature map을 AIDIA의 대안 설계 입력으로 지원**하고, 기존 DIA-NN ID 기반 map과 비교할 수 있도록 구현한다. 기존 ID 입력 경로를 유지하면서 별도 입력 모드와 재현 가능한 비교 경로를 제공하는 실험적 확장이다.

사용자 요청: 이 기능을 별도 브랜치와 구현 세션에서 개발·검증하여 테스트할 수 있게 한다.

## 배경

- 현재 RT–m/z map은 동정된 precursor를 중심으로 작성된다.
- MS1 feature map은 검출됐지만 아직 동정되지 않은 feature를 설계에 포함할 수 있다.
- MS1 feature 검출에도 감도·분할·isotope grouping에 따른 선택 편향이 있다. 현재 연구의 ID 회복 집합에도 MS1 feature 미대응 사례가 많다. 따라서 MS1 입력이 더 완전하거나 항상 우월하다고 가정하지 않는다.
- 첫 비교에서는 map을 바꾼 효과와 cycle time을 바꾼 효과를 분리한다.

## 1차 구현 범위

### 1. alphaextract feature table 입력

기존 features.parquet를 읽는 명시적 입력 모드/adapter를 추가한다. raw 재처리와 vendor reader는 필요하지 않다.

실제 schema를 확인한 후 다음 의미를 보존한다.

- 식별/출처: run_name, feature_id 또는 feature_uid, 원본 파일·추출 provenance
- 위치: mz, rt_apex, rt_start, rt_end, rt_unit
- 폭: fwhm 및 fwhm_source
- 선택 정보: charge, intensity_apex, intensity_sum, n_isotopes, n_scans

시간 단위를 명시적으로 정규화하고 실제 apex를 보존한다. Sequence/Protein.Group/q-value가 없는 feature를 처리하기 위해 허위 peptide ID나 단백질 주석을 만들지 않는다. Feature key는 이름 없는 feature를 추적하는 키이며 생물학적 ID가 아니다.

누락·비유한 값·역전된 RT 경계·중복 키 등을 검증하고, 기능에 필요한 열이 없을 때의 동작을 명시한다. Feature 한 행과 isotope/centroid 한 행을 구분하여 중복 집계하지 않는다.

### 2. 기존 설계 기능과 연결

- ID 기반 입력 경로와 기본 동작을 유지한다.
- MS1 입력으로 기존 RT–m/z density 및 isolation-window 설계·export를 수행할 수 있게 한다.
- 단백질/서열에 의존하는 출력은 입력 모드에 맞게 생략하거나 unavailable로 표시한다.
- 첫 구현의 필수 범위는 단일 run 또는 명시적으로 선택한 입력 집합이다. 서로 다른 run의 feature_id를 같은 precursor로 합치지 않는다.
- 여러 run 통합이 필요하면 동일 LC 조건과 명시적인 RT 정렬·가중 규칙을 요구한다. 정밀 feature matching이나 IonQuant 도입을 이 기능의 선행 조건으로 만들지 않는다.

### 3. 측정 예산을 고정한 ID map 대 MS1 map 비교

첫 비교는 동일 scouting run/시료/LC 조건에서 생성한 ID map과 MS1 map을 사용한다.

- Reference plan의 cycle time, window 수, instrument 설정, 총 m/z 범위, RT bin/schedule 등 비교 예산과 경계를 고정하여 map 입력에 따른 배치 차이를 비교한다.
- MS1 FWHM으로 cycle time을 자동 재최적화해 두 가지 변경을 섞지 않는다.
- 새 입력에서 계산한 satisfaction이 목표에 미달하면 그대로 보고하고, 자동으로 예산을 바꿔 충족한 것처럼 표시하지 않는다.
- ID/MS1 입력 규모, 공통 평가 집합의 window 포함 상태, 고정된 평가 map에 대한 window별 feature 부하 및 설계 차이를 export한다.
- 같은 MS1 평가 map을 두 설계에 공통 적용하여 부하를 비교한다. 각각의 설계 입력으로만 자기 성능을 평가하지 않는다.
- 관측되지 않은 RT–m/z 구간을 자동으로 측정 대상에서 제거하지 않으며, 비교할 공통 m/z/RT 범위를 명시한다.
- Offline 결과를 실측 ID 증가 또는 정량 성능 개선으로 표현하지 않는다. 최종 성능 검증은 이후 실제 비교획득의 과제다.

### 4. DPPP와 satisfaction의 의미

AIDIA 정의를 유지한다:

DPPP = 1.7 × FWHM_seconds / cycle_time_seconds

- FWHM 내 scan 횟수와 whole-peak DPPP를 구분한다.
- target_dppp와 target_satisfaction은 명시한 기존 설계 설정을 사용한다.
- ID 기반 satisfaction의 분모와 MS1 feature 기반 satisfaction의 분모를 구분한다.
- alphaextract의 실측 trace 기반 FWHM과 substituted FWHM의 provenance를 유지한다. MS1 FWHM과 DIA-NN FWHM이 동일하다고 가정하지 않는다.
- MS1 FWHM까지 사용하는 독립적인 cycle-time 재설계는 1차 비교와 구분되는 후속 범위다.

## 검증과 산출물

- [ ] 실제 alphaextract schema를 사용하는 MS1 입력 adapter와 사용 예제
- [ ] ID 입력 경로의 회귀 검증
- [ ] 시간 단위, apex 보존, feature key, 중복·결측·부적절한 입력 처리를 검증하는 의미 있는 테스트
- [ ] 고정된 cycle time/window 수/공통 범위에서 두 map을 비교하는 재현 가능한 실행 경로와 출력
- [ ] satisfaction의 target/예측값/분모/FWHM 출처가 확인 가능한 결과
- [ ] 실제 소규모 parquet 입력을 이용한 통합 검증 및 결과 요약
- [ ] 입력 schema, 제약, 실행법, 실제 비교획득에서 확인할 항목을 문서화

## 범위와 관련 작업

- 기존 cache를 재생성하거나 덮어쓰지 않고, 새 검증 결과는 별도 출력 위치에 저장한다.
- 기존 MS1 acquisition 진단 설계와 KDE/Shiny 작업 브랜치는 참고만 하며 이 이슈에서 통합하지 않는다.
- #16의 P10–P90 진단 확장, #8의 광범위한 단위 처리 변경, MAP-MS, 자동 AGC/maxIT 최적화는 별도 범위다. 이 adapter에서 필요한 명시적 단위 검증은 포함한다.
- 관련 코드: AIDIA R/column_selection.R, R/data_validation.R, R/replicate_utils.R, R/dppp.R, R/optimization_planning.R; alphaextract alphaextract/feature_finder.py 및 alphaextract/scanlevel/features.py.


