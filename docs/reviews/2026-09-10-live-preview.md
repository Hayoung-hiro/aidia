# KDE 미리보기와 확정 결과 분리

추가 개선: m/z preview에 전체 RT 보기와 RT별 window 지도를 추가하고 기본 선택으로 지정했다. [전체 보기와 다음 작업 계획](../plans/2026-09-10-shiny-next-iteration.md)을 참조한다.

작업 브랜치: `Hayoung-hiro/shiny-workflow-ux`. 앞서 검토한 세 구획의 compact 화면 위에 적용했다.

## 사용자 동작

- 슬라이더 입력 방식과 범위를 유지했다. 슬라이더용 직접 숫자 입력은 추가하지 않았다.
- 설정을 조절하고 잠시 멈추면 m/z 미리보기를 자동 갱신한다. 넓은 화면에서는 조절 항목과 미리보기를 나란히 보여 준다.
- 회색은 선택한 RT 그룹의 원본 분포, 녹색 영역은 선택된 m/z 범위, 점선은 KDE threshold다. 아래 띠는 실제 생성된 windows이며 staggered 모드는 cycle별로 나눈다.
- `View RT group`은 표시할 구간만 바꾼다. 그룹 생성 설정이나 최종 method는 바꾸지 않는다.
- `Confirm & view results`를 누르면 해당 계산 결과를 확정하고 Results로 이동한다.
- 이후 설정을 변경해도 CSV·PDF·ZIP은 이전 확정 결과를 사용한다. Results와 Configure에 이 상태를 명시한다.
- 각 구획의 `Reset`은 같은 기기의 마지막 확정 설정을 복원한다. 아직 확정 결과가 없거나 기기가 바뀌었으면 해당 기기의 기본 설정을 복원한다. 다른 구획의 입력은 유지한다.
- 잘못된 설정으로 미리보기 계산이 실패해도 확정 결과는 보존한다. 설정을 수정하거나 Reset으로 복원할 수 있다.

## 구현과 계산 의미

기존 버튼 handler의 Stage 2·3 호출과 입력 변환을 `optimization_workflow.R`로 옮겼다. 미리보기는 그 함수를 실행하고, 확정 동작은 미리보기의 plan·windows·설정·cycle 정보를 그대로 보존한다. UI 입력을 다시 읽어 다른 결과를 생성하지 않는다.

KDE의 기존 SJ / nrd0 fallback 추정기를 공통 내부 함수로 추출해 범위 선택과 그림이 같은 곡선을 사용하도록 했다. 범위 선택·window 생성 알고리즘과 공개 API 기본값은 변경하지 않았다. RT별 표시 데이터도 기존 RT binning 함수를 재사용하며, 결과의 RT 통계와 일치하는지 확인한다.

선택 범위의 inclusion은 **현재 RT 그룹의 범위 선택 지표**다. Whole-run window coverage는 기존 최종 windows 집계의 **전체 실행 지표**이며 서로 구분해 표시한다. m/z 범위의 margin과 최종 window의 제약 때문에 두 값은 다를 수 있다.

Shiny `ExtendedTask`와 `promises::future_promise()`로 계산을 별도 R 프로세스에 보낸다. 입력은 400ms 안정화 후 요청하고, 계산 중 들어온 요청은 최신 한 개만 대기시킨다. 완료 시 데이터 버전·설정·cycle이 현재 요청과 일치하는 결과만 게시한다. 계산 중 확정을 눌렀더라도 이후 입력이 바뀌면 그 확정 요청을 취소한다.

의존성은 Shiny ≥ 1.8.1, promises ≥ 1.3.0, future ≥ 1.33.0이다. 앱의 worker 수는 `options(aidia.shiny.workers = 2L)`로 설정할 수 있다. 기본 2개를 세션들이 공유하고 앱 종료 시 이전 future plan을 복원한다. 개발 worktree에서는 worker도 해당 source package를 로드하며, 오래된 설치 패키지로 대체하지 않는다.

## 검증

- `devtools::test(filter = "shiny-live-preview|strategy-comparison|method-delivery")` 통과. 이후 추가한 계산 중 확정 시나리오를 포함한 `shiny-live-preview` 재실행도 통과했다.
- 자동 테스트: 최신 요청만 유지, 오래된 결과 무시, 확정 결과 보존, 오류 복구, 구획별 복원, 계산 중 확정과 후속 변경에 따른 취소, 데이터 교체·제거, KDE 추정기 동등성.
- 실제 Edge + Shiny + background worker에서 합성 precursor 12,000개로 검증했다.
- KDE threshold 변경에 따라 그림·선택 범위가 변하고, Reset으로 기본 설정을 복원하는 것을 확인했다.
- 확정 전후 CSV를 byte 단위로 비교했다. 미확정 변경과 미리보기 오류는 기존 다운로드를 바꾸지 않았고, 새 설정을 확정한 뒤에는 CSV가 바뀌었다. 기본 결과는 728개 window 행이었다.
- 다섯 m/z 전략, 세 window mode, adaptive RT, RT 구간 선택을 실행했다.
- Exploris로 전환한 뒤 DPPP 프리셋과 Sampling Reset을 확인했다. 1440px·1024px·390px에서 페이지 가로 넘침이 없고, 좁은 화면의 그래프는 내부 스크롤을 사용한다. 마지막 브라우저 검사에서 JavaScript 및 Shiny output 오류가 없었다.
- 기존 locale/build-version 경고 및 합성 데이터의 sparse-bin fallback·plot/rt_group 경고가 남아 있다.

전체 계산을 매 요청 수행하는 첫 구현이다. 완료된 확정 결과와 현재 미리보기는 재사용하지만, KDE 중간 계산 캐시나 여러 과거 설정의 캐시는 추가하지 않았다. 실제 실험 데이터 크기별 속도·메모리·다중 사용자 부하는 별도 측정 대상이다. 400ms는 계산 시작 전 대기 시간이며 결과 도착 시간 보장이 아니다.

## 화면

- [기본 미리보기](2026-09-10-live-preview-assets/01-live-default.png)
- [KDE threshold 변경](2026-09-10-live-preview-assets/02-kde-adjusted.png)
- [미확정 변경 후 보존된 결과·다운로드](2026-09-10-live-preview-assets/03-confirmed-download-preserved.png)
- [RT 구간 선택](2026-09-10-live-preview-assets/04-selected-rt.png)
- [순차 기기](2026-09-10-live-preview-assets/05-sequential.png)
- [태블릿](2026-09-10-live-preview-assets/06-tablet.png) · [모바일](2026-09-10-live-preview-assets/07-mobile.png)

로컬 검토 앱: [http://127.0.0.1:3877](http://127.0.0.1:3877)
