# alphaextract MS1 feature map 입력과 ID map 비교

이슈 #17의 실험적 입력 확장이다. 기본 DIA-NN 입력과 기존 설계·export API는 유지한다. `create_ms1_feature_dataset()`은 외부 `features.parquet`를 읽어 `ValidatedData`로 변환하며, raw 또는 vendor method 파일을 읽지 않는다. 이미 생성된 cache를 입력으로 사용한다.

## 입력 계약

한 행은 하나의 **feature**다. `feature_isotopes.parquet`, `feature_traces.parquet`는 입력이 아니다. 필수값 누락, NA/NaN/Inf, 비양수 m/z·FWHM, 역전된 RT 경계, 경계 밖 apex, 중복 key는 오류로 처리한다. 자동 제거·대체 FWHM 생성은 하지 않는다.

| 열 | 의미와 검증 |
|---|---|
| `run_name` | 비어 있지 않은 정확한 run 이름. 모든 run을 사용하거나 `run_name=` 벡터로 정확히 선택 |
| `feature_id` 또는 `feature_uid` | run 안에서 유일한 키. 둘 다 있으면 `run_name#Ffeature_id`와 일치해야 함. UID만 있으면 같은 run의 `#F` 접두어 필요 |
| `mz` | 양수이며 유한한 feature m/z |
| `rt_start`, `rt_apex`, `rt_end` | 0 ≤ start ≤ apex ≤ end, start < end. 실제 apex 보존 |
| `rt_unit` | 파일 내 선택한 run에서 일관된 `minute(s)` 또는 `second(s)`. RT와 FWHM 모두 이 단위 |
| `fwhm`, `fwhm_source` | 양수 폭과 비어 있지 않은 출처. 알려진 출처는 `alpharaw_summed_isotope_trace`, `substituted_half_start_end`. 다른 출처도 문자열 그대로 보존 |
| `charge`, `n_isotopes`, `n_scans` | 선택 열. 값이 있으면 양의 정수, 결측은 허용 |
| `intensity_apex`, `intensity_sum` | 선택 열. 값이 있으면 비음수 유한수, 결측은 허용. 최초 설계의 가중치로 사용하지 않음 |

원래 열을 보존하고, 설계용 `Precursor.Mz`, `RT.Start`, `RT.Stop`, `RT.Apex`, `FWHM`, `Feature.Key`를 추가한다. 설계용 RT/FWHM은 분, DPPP 계산은 명시적으로 변환한 초 단위다. `Precursor.Id`, `Protein.Group`, sequence, q-value를 합성하지 않는다. Protein/sequence 정보는 unavailable이며 해당 통계를 제공하지 않는다. `quality_score=1`은 구조 검증 통과일 뿐 ID 신뢰도나 검출 정확도가 아니다.

원본 파일 경로와 FWHM 출처별 개수는 metadata에 저장한다. `provenance=`에 추출 버전·설정·원본 fingerprint를 전달하면 그대로 보존한다. `scan_meta.json`은 선택 사항이고 자동으로 주변 파일을 읽지 않는다. 데이터 프레임 입력은 파일 경로가 없으므로 필요한 출처를 직접 전달한다.

## 여러 run 사용

**같은 batch에서 얻은 자료와 호환 가능한 LC·측정 조건을 권장한다. 적합한 파일을 고르는 책임은 사용자에게 있다.** 시료명이나 LC 길이로 업로드를 차단하거나 자동 그룹 분할하지 않는다. 단, 중복 검출 행·잘못된 단위·필수값 누락은 오류로 처리한다.

`features=`에 파일 경로 벡터 또는 여러 run을 담은 한 파일을 넘긴다. 동일 파일을 두 번 넣거나 combined 파일과 그 run별 파일을 동시에 넣으면 중복 key 오류가 난다.

| 통합 방식 | 처리 |
|---|---|
| `auto` (기본) | 공동 export의 그룹 열이 있으면 consensus, 일반 feature table이면 pooled |
| `pooled` | run별 모든 검출 행을 유지. 동일 feature가 여러 run에 있어도 각각 한 번 집계. feature가 많은 run의 영향이 더 큼 |
| `consensus` | 한 공동 `export_id`의 `feature_group_id`로 대응된 검출 행을 통합. 최소 검출 run 수를 충족한 그룹의 m/z·RT·FWHM 중앙값 사용 |

Consensus의 기본 최소 run 수는 `ceiling(n_runs / 2)`이며 `min_replicates=1`이면 어느 run에서든 관측된 그룹을 유지한다. 서로 다른 시료를 함께 설계할 때 특정 시료에만 있는 feature를 유지하려면 이 값을 검토한다. CV나 intensity로 자동 필터링하지 않는다. `feature_group_id`는 생물학적 identity가 아니다. 같은 run에서 한 그룹에 두 feature가 들어가거나 독립적인 여러 export의 그룹을 섞어 consensus를 요청하면 오류가 난다. 독립 export를 함께 사용할 때는 pooled를 선택하거나 alphaextract에서 공동 export한다.

공동 export는 원본 열에 `export_id`, `feature_group_id`, `rt_shift_min`을 추가한다. Shift는 원본 단위와 관계없이 **분** 단위이며 RT 위치에만 적용하고 FWHM은 바꾸지 않는다. 0은 자동 정렬 없이 native RT를 사용한다는 뜻이다. Consensus 결과의 `$feature_observations`에 원본 행과 대응 관계를 보존하며 `$data`에는 통합한 설계 행을 둔다.

```r
files <- c("export/runs/001/features.parquet", "export/runs/002/features.parquet")
ms1 <- create_ms1_feature_dataset(files)  # joint export -> consensus
all_detections <- create_ms1_feature_dataset(files, aggregation = "pooled")
ms1_union <- create_ms1_feature_dataset(files, min_replicates = 1)
# Combined file gives the same consensus as all its run files together.
ms1_combined <- create_ms1_feature_dataset("export/features.parquet")
```

alphaextract의 `aidia-export --features ... -o 새폴더` 또는 `aidia-export --raw ... -o 새폴더`로 생성한다. 자세한 실행법은 alphaextract의 `docs/aidia-export.md`에 있다. AIDIA에는 vendor reader를 추가하지 않는다.

실제 세 run을 양쪽 입력에 동일하게 적용한 결과와 실행 산출물은 [multi-run 검증 보고서](reviews/2026-10-19-ms1-multirun-validation.md)에 기록했다.

## 일반 설계와 Shiny

```r
devtools::load_all()  # 설치된 패키지를 쓸 때는 library(aidia)
ms1 <- create_ms1_feature_dataset(
  "path/to/features.parquet", run_name = "exact_scouting_run",
  provenance = list(extractor = "alphaextract", extraction_commit = "record-the-version")
)
# 기존 ID 기준 plan을 재사용할 수 있다.
windows <- optimize_windows(ms1, reference_plan,
  strategy_config = quantile_config(apply_smoothing = FALSE))
export_windows_to_csv(windows, "ms1_method.csv", ms1)
```

Shiny Step 1에서 다음 순서로 MS1 입력을 준비한다.

1. **Input type → alphaextract MS1 features**를 선택한다.
2. **Add files...**로 각 폴더의 `features.parquet`을 차례로 추가한다. 한 번에 여러 파일을 선택하거나 combined 파일 하나를 추가해도 된다. 선택할 때마다 목록에 누적되며 아직 계산하지 않는다.
3. 목록의 **run 이름**, 파일 이름·크기를 확인한다. `features.parquet`이라는 이름이 같아도 내부 `run_name`으로 구별할 수 있다. 여러 run이 담긴 파일은 run 목록을 펼쳐 볼 수 있다. **Remove**는 해당 파일만 제거하고 **Clear list**는 목록을 비운다. 완전히 같은 파일은 한 번만 담긴다. 전체 목록의 용량 제한은 500 MB다.
4. **Combine runs**에서 통합 방식을 고르고 **Minimum runs**에 0(자동) 또는 최소 검출 run 수를 입력한 뒤 **Compute**를 누른다.
5. 계산이 끝나면 선택된 run 목록과 실제 적용된 통합 방식·설계 행 수를 확인하고 다음 단계로 이동한다.

파일 추가·제거, 입력 종류 또는 통합 설정 변경은 기존 계산 결과를 무효화한다. **Compute**를 다시 눌러야 계산한다. 목록은 현재 브라우저 세션에서만 유지되며 **New Analysis**나 세션 종료 시 제거된다. 입력 종류를 잠시 바꾸어도 각 목록은 남는다. 같은 batch의 호환 가능한 LC·acquisition 조건을 권장하며, run 선택은 사용자가 결정한다.

일반 브라우저 업로드는 원본 폴더를 전달하지 않으므로 파일 이름과 parquet의 run 이름을 표시한다. 이 단계에서는 run 이름 열만 읽으며, 검증·통합·DPPP 계산은 Compute에서 실행한다. 경로도 표시하려면 로컬 실행 시 **Add by local path → Add paths**에 파일의 전체 경로를 한 줄씩 넣는다. 파일 탐색기의 “경로로 복사”로 얻은 따옴표 포함 경로도 사용할 수 있다. 원본은 읽기만 하고 계산용 복사본을 세션에 보관한다. 로컬 경로 입력은 `run_aidia_app()`의 loopback 실행에서 기본으로 제공하며 외부 호스트 바인딩에서는 기본으로 끈다. 직접 `shiny::runApp()`을 사용하는 경우 `options(aidia.shiny.local_files = TRUE)`로 명시적으로 켤 수 있다.

### DIA-NN의 통합 및 필터 옵션

**Input type → DIA-NN ID report**에서 report 하나를 선택하고 아래 옵션을 정한 뒤 **Compute**를 누른다. report를 새로 선택하면 기존 report를 교체한다. 기본값은 기존 `create_validated_dataset()`와 `filter_diann_quality()`의 기본 인자에서 읽어 오므로 기존 처리 결과를 유지한다.

| 옵션 | 기본값 | 적용 범위 |
|---|---|---|
| Combine runs | Precursor consensus (median) | Precursor.Id별 중앙값 통합. All detections는 run별 관측을 유지한다. |
| Minimum runs | 0: 자동 | 품질 필터 후 남은 run 수의 절반을 올림한다. Consensus에서만 적용한다. |
| Apply Q-value filters | 켬 | 아래 Q-value 필터의 전체 적용 여부 |
| Q.Value / Lib.Q.Value / Global.Q.Value | 각각 0.01 | 해당 열이 존재할 때 적용 |
| Protein-group Q | 0.05 | PG.Q.Value, Lib.PG.Q.Value, Global.PG.Q.Value에 적용 |
| Apply global filters | 켬 | Global.Q.Value와 Global.PG.Q.Value 적용 여부 |
| Apply Channel.Q.Value filter | 끔 | plexDIA용. 켜면 기본 입력값 0.01을 사용하며 수정 가능 |

**DIA-NN quality filters**를 펼치면 Q-value 조건을 바꿀 수 있다. 없는 열은 기존과 같이 건너뛴다. 최소 run 수는 0 또는 양의 정수, Q-value는 0–1 범위다. 설정을 바꾸면 이전 결과가 해제되고 Compute를 다시 눌러야 한다. 실제 통합 방식과 최소 run 수는 계산 요약에서, 선택한 Q-value 조건은 **Selected DIA-NN filters**에서 확인한다. All detections도 기존 NA·중복 정리는 적용하며, Q-value 필터를 켜 두었다면 그 필터 역시 적용한다.

Shiny 일반 설계는 입력별 FWHM으로 예산을 다시 계산하므로, **조건을 고정한 ID/MS1 비교에는 아래 R API를 사용한다.**

## 예산을 고정한 비교

```r
# run_name은 exact match이며 consensus 전에 선택한다.
id <- create_validated_dataset("report.parquet", run_name = "exact_scouting_run")
ms1 <- create_ms1_feature_dataset("features.parquet", run_name = "exact_scouting_run")

# 아래는 기능 검증용 가정이다. 실제 acquisition 설정으로 해석하지 않는다.
reference_plan <- plan_optimization(id, current_cycle_time = 2.7,
  instrument_preset = "exploris", ms2_resolution = 30000,
  ms2_time_override = 0.022, target_dppp = 4, target_satisfaction = 0.8)
comparison <- compare_input_maps(id, ms1, reference_plan,
  rt_breaks = seq(10, 80, 5), mz_range = c(390, 970),
  context = list(sample = "same sample",
    lc_condition = "same scouting injection and LC condition",
    settings_source = "test reference, not historical acquisition settings"))
export_input_map_comparison(comparison, "test_output/my-new-comparison")
```

`reference_plan$actual_cycle_time_sec`를 사용한다. `current_cycle_time`과 `required_cycle_time_sec`는 비교에 사용하는 주기와 다를 수 있다. Plan은 한 번만 계산하고, 두 설계에서 `window_count_per_bin`, instrument/scan-time 설정, target을 그대로 사용한다. MS1 FWHM에 맞춰 plan을 다시 계산하지 않는다. 이미 보유한 실제 기준 plan이 있으면 그것을 전달하고 출처를 기록한다. `context`의 동일 시료/LC 설명은 사용자의 진술이며 코드가 획득 메타데이터를 독립적으로 증명하는 것은 아니다. 세 map의 `source_runs`는 코드가 정확히 일치하는지 검사한다.

첫 비교는 **전체 공통 m/z 범위를 유지한 density window 배치**다. RT schedule은 두 자리 소수 분 단위 경계로 직접 전달하고, m/z 양 끝은 정수다. Forbidden-zone offset과 overlap은 0으로 고정한다. 이는 export 후에도 평가한 경계와 동일하게 유지하기 위한 제약이다. 모든 bin은 같은 N을 갖고 관측이 없는 bin도 균등 window로 남긴다. 공통 범위를 N개의 최소 폭 window로 채울 수 없으면 오류를 낸다. 최소/최대 폭의 기존 권장값 및 digitization 규칙을 사용하며, 최대 폭은 hard instrument limit로 보장하지 않는다. 실제 기기 method에서 폭과 전체 schedule을 확인해야 한다.

`evaluation_data=`로 별도 MS1 평가 map을 지정한다. 기본값은 `ms1`이며 두 설계가 정확히 같은 평가 행을 사용한다. 여러 run의 consensus로 설계한 경우에는 같은 run 집합의 pooled map을 평가에 사용하면 consensus에서 빠진 검출 행도 평가에 남길 수 있다. ID/MS1/평가 map의 source run 집합이 같아야 하며 LC·시료 적합성은 사용자가 확인해 `context`에 기록한다. RT shift를 적용했다면 두 map과 평가 집합의 좌표가 같은지도 확인해야 한다. 강도 가중은 하지 않는다. ID map은 유일한 `Precursor.Id`를 요구하므로 multiplex/channel 선택이 필요하면 upstream에서 먼저 처리한다.

## 출력과 해석

| 파일 | 내용 |
|---|---|
| `manifest.json` | context, 고정 예산·범위, 전체 기준 plan, 각 map의 출처 |
| `input_counts.csv` | 전체 입력 수, 공통 범위 내/밖 개수 |
| `satisfaction.csv` | map·FWHM 출처별 분모/충족 수, target, tolerance/실제 threshold, 예측 satisfaction, 목표 달성 여부 |
| `inclusion.csv` | 각 설계 × 동일 ID/MS1 평가 행의 key·위치·범위 내 여부·포함 상태 |
| `window_loads.csv` | window별 `n_design_rows`와 동일 MS1 map의 `n_evaluation_features` |
| `load_summary.csv` | 동일 MS1 평가 map의 전체·RT bin별 평균/최대 부하, CV, 빈 window 수 |
| `design_differences.csv` | 같은 순번 window의 두 경계, 중심 및 폭 차이 |
| `id_method.csv`, `ms1_method.csv` | 기존 8-column Thermo exporter로 만든 mass list |
| `comparison.rds` | 다시 검사할 수 있는 전체 비교 객체와 평가 map |

이미 파일이 있는 출력 폴더에는 쓰지 않는다. 원본 cache와 다른 실행 결과를 덮어쓰지 않도록 매번 새 출력 폴더를 사용한다.

포함 상태는 **apex RT × m/z**의 기하학적 포함이다. 내부 경계는 [start, end), 최종 상단 경계는 포함한다. 이 경로는 공통 범위를 빠짐없이 덮으므로 범위 내 coverage가 100%인 것은 예상되는 결과이며 검출률·ID 개선의 근거가 아니다. `n_evaluation_features`는 bin에 속한 feature 개수이며 동시 co-elution, ion current, AGC charge 또는 실측 간섭이 아니다.

Satisfaction은 공통 범위 내 각 map 행을 분모로 하며 `DPPP = 1.7 × FWHM_seconds / 고정 cycle_time_seconds`를 계산한다. 같은 map은 두 설계에서 동일한 DPPP를 갖는다. 폭이 바뀌어도 sampling 주기를 고정했기 때문이다. FWHM 내 scan 횟수와 구분한다. ID FWHM과 MS1 trace FWHM을 같은 측정으로 간주하지 않는다. 출처별 행은 전체 집합의 부분집합이고 전체 행에 다시 더하지 않는다. 평가 범위에 행이 없으면 분모 0, satisfaction NA다. 대체 FWHM도 출처별로 분리하여 보고한다.

## 실제 parquet smoke test

저장소 루트에서 다음 명령을 실행한다. 기본 경로는 인계 문서의 로컬 데이터를 가리킨다.

```powershell
Rscript scripts/smoke_ms1_feature_map.R
# 위치 인수: features.parquet report.parquet exact_run 새_output_dir
```

같은 run의 원본 report 76,367행에서 `Decoy=0`, `Q.Value<=0.01`, `PG.Q.Value<=0.01`, `Protein.Ids/Protein.Group`의 cRAP 제외를 적용한다. Global/Lib Q-value 필터는 추가하지 않는다. 연구 필터는 smoke script에서 명시적으로 적용한 뒤 `apply_quality_filters=FALSE`로 기존 adapter에 넘기며, 일반 API의 기존 기본 ID 필터는 변경하지 않았다. MS1에는 이 ID 필터를 적용하지 않는다.

출력은 현재 worktree의 `test_output/ms1-feature-map/smoke-날짜-시각/` 아래에만 저장한다. 실제 feature map 전체와 정확히 선택한 단일 run ID map으로 비교하고, 기존 Stage 3/4·8-column export도 실행한다. 원본 두 parquet의 실행 전후 MD5, R 환경, 필터 조건을 기록한다. 전체 raw 재캐싱은 하지 않는다. 실행 수치와 최종 산출물 위치는 [검증 보고서](reviews/2026-10-19-ms1-feature-map-validation.md)에 기록한다.

## 남은 실제 acquisition 검증

- 과거 method의 실제 target·window 수·MS1/MS2 resolution/IT·AGC·LC schedule을 확보한다. 파일명의 60min은 분석 구간 이름이며 gradient 또는 injection 주기로 추정하지 않는다.
- 동일 시료/load/LC 조건에서 두 설계를 실제 획득하고, 조건별 technical replicate 그룹을 비교한다. 반복 번호로 임의 pairing하지 않는다.
- 실제 scan timing·window revisit·peak 내 sampling·기기에서 적용된 경계와 switch 시점을 확인한다.
- 같은 DIA-NN 버전/library/FDR/정량·normalization 조건으로 ID 깊이, 결측, 재현성, 알려진 혼합비의 bias를 평가한다.
- MS1 map에서 미대응인 ID 위치도 측정 대상에 남아 있는지, 검출·분할·isotope grouping 편향과 RT drift에 대한 안정성을 검증한다. 별도 run으로 일반화 평가가 필요하다.
- MS1 FWHM을 활용한 독립적인 주기 재최적화, 자동 비선형 RT 정렬·matching 정확도, run 가중치, 실제 시간 단축/SPD, MAP-MS·AGC 최적화는 별도 검증 범위다.
