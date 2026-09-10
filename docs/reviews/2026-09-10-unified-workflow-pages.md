# Prepare / Results 테마 통일

기준 커밋: `29aab8e`. 사용자가 승인한 Configure의 구획과 간결한 배치를 1·3페이지에 적용했다.

## 후속 피드백 반영: 사이드바와 MS2 빈 구간 문구

- 오른쪽 Acquisition preview와 중복되던 사이드바 cycle-time 카드를 `Method for download`로 교체했다. 업로드 파일명은 Data Summary에 표시한다.
- 카드는 확정된 전략·window 모드·장비·window/RT 그룹 수를 보여준다. 설정을 편집해도 확정 정보는 유지하고 `Unconfirmed changes`와 다운로드 기준을 표시한다. 확정 전과 새 분석에서는 `No confirmed method`로 표시한다.
- 시간 확장 옵션의 최종 문구는 `Run start / end / Fill MS2 gaps at run start and end`이다. 목적을 먼저 표현하고, 0분부터 시작하거나 지정 종료 시간까지 기존 첫/마지막 RT 그룹을 확장한다는 설명은 도움말에 둔다. 내부 RT 그룹 사이 빈틈을 고치는 옵션으로 설명하지 않는다.
- 데스크톱에서 확정 → 전략 변경 → 확정 CSV 유지 → Reset → 새 분석 전환을 확인했다. 문구 변경 후에도 0–65분 내보내기가 동작하며 관련 테스트 3종이 통과했다.

[확정 결과와 사이드바](2026-09-10-sidebar-method-assets/03-confirmed.png) · [수정 중인 상태](2026-09-10-sidebar-method-assets/05-pending-changes.png) · [MS2 빈 구간 도움말](2026-09-10-sidebar-method-assets/04-gap-help.png)

## 후속 피드백 반영: 설정 결과와 파일 형식 노출

사용자는 모바일을 현재 범위에서 제외했다. 이후 작업과 검증은 데스크톱을 기준으로 진행했다.

- Input acquisition settings 오른쪽에 Acquisition preview를 추가했다. 기존 `cycle_time_result()`의 cycle time과 MS1·MS2 시간을 수치·막대로 표시하고, 데이터가 있으면 기존 `calculate_dppp()`로 예상 DPPP를 보여준다. 병렬·순차 획득 방식을 표시하며 설정 변경에 즉시 반응한다.
- Thermo 시간 확장 옵션을 `Acquisition time / Acquire from 0 min to run end`로 변경했다. 입력란은 `Run end (min)`이다. `?`에서 첫 구간을 0분까지, 마지막 구간을 지정 종료 시간까지 확장하는 동작과 미입력 시 동작을 설명한다.
- Method 파일 형식의 열 이름과 예시 행을 항상 보이는 표로 복원했다. 예시는 실제 사용자 결과와 혼동하지 않도록 `Example rows`로 표시한다.
- Edge 1440px에서 MS1 해상도·MS2 IT 변경에 따른 시간 갱신, 순차 장비 전환, 데이터 입력 후 DPPP 표시를 확인했다. 세 파일 형식 모두 표시된 열 이름과 실제 다운로드 CSV 헤더가 일치했다. 전체 run 옵션으로 0–65분을 내보냈을 때 행 수·m/z·window 폭이 유지되는 것을 확인했다. 관련 테스트 3종과 구문 검사도 통과했다.

[입력 설정 미리보기](2026-09-10-acquisition-export-assets/01-input-preview.png) · [데이터 입력 후](2026-09-10-acquisition-export-assets/05-data-preview.png) · [Thermo 열과 예시](2026-09-10-acquisition-export-assets/06-thermo-columns.png) · [전체 run 설정](2026-09-10-acquisition-export-assets/07-full-run-export.png) · [Center Mass](2026-09-10-acquisition-export-assets/08-center_mass-columns.png) · [m/z Range](2026-09-10-acquisition-export-assets/08-mz_range-columns.png)

## 화면 구성

| 페이지 | 주요 구획 | 변경 |
|---|---|---|
| Prepare | Data file / Input acquisition settings / Peak sampling check | 업로드를 한 행으로 정리하고 장비 설정을 MS1·MS2별로 묶었다. 샘플링 분포와 표를 나란히 배치하고 권장 cycle time을 짧은 요약으로 표시한다. |
| Configure | 기존 세 구획 유지 | 구획·파라미터 행·도움말을 공통 컴포넌트로 추출해 같은 시각 규칙을 사용한다. Reset 및 미리보기 동작은 유지한다. |
| Results | Confirmed method / Download / Explore results | 핵심 지표와 세부 요약을 한 구획에 모으고 다운로드를 형식·동작별 행으로 정리했다. 파일명은 선택 설정으로, 설명은 `?`로 제공한다. |

세 페이지에서 동일한 번호 배지, 제목 크기, 테두리, 여백, 버튼 크기를 사용한다. 결과의 상태 색상과 진단 배지는 유지한다. 장비별 조건부 입력, 기존 선택값과 범위, 확정 결과 및 CSV 생성 로직은 변경하지 않았다. PDF 범위는 같은 값(`full`/`minimal`)의 dropdown으로 바꿨다.

## 검증

- Shiny R 구문 검사와 `shiny-live-preview`, `strategy-comparison`, `method-delivery` 테스트 통과.
- Edge에서 합성 precursor 12,000개 업로드 → Configure 미리보기 → 확정 결과 이동을 확인했다.
- Astral / Exploris 전환, MS1 Auto 해제와 수동 IT 입력, Thermo / center-mass CSV 다운로드, PDF 범위 선택, run schedule 입력 표시, 결과 상세·window table 펼치기를 확인했다.
- 390px에서 페이지 가로 넘침이 없고 도움말이 화면 안에 표시되는지 확인했다. 넓은 그림·표는 내부 스크롤을 제공한다.
- 사용자 실제 데이터의 과학적 성능 검증이나 PDF 생성 전체 회귀 검증은 이번 UI 확인 범위에 포함하지 않았다.

## 화면

- [Prepare: 입력 전](2026-09-10-unified-pages-assets/01-prepare-empty.png)
- [Prepare: 순차 장비 설정](2026-09-10-unified-pages-assets/02-prepare-sequential.png)
- [Prepare: 데이터 입력 후](2026-09-10-unified-pages-assets/03-prepare-loaded.png)
- [Configure](2026-09-10-unified-pages-assets/05-configure.png)
- [Results](2026-09-10-unified-pages-assets/06-results.png)
- [다운로드 도움말](2026-09-10-unified-pages-assets/07-export-help.png)
- [상세 결과](2026-09-10-unified-pages-assets/08-results-details.png)
- [Results 모바일](2026-09-10-unified-pages-assets/09-results-mobile.png)
- [Prepare 모바일](2026-09-10-unified-pages-assets/10-prepare-mobile.png)
- [모바일 도움말](2026-09-10-unified-pages-assets/11-mobile-help.png)
