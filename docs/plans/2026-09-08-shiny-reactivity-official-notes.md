# Shiny 실시간 파라미터 탐색: 공식 문서 검토

검토일: 2026-09-08. 범위는 Shiny R의 구현 가능성과 제약이다. 처리 시간은 측정하지 않았으며, 아래 지연 값은 구현 시작값 제안이다. KDE + Dense를 시작점으로 삼는 근거는 사용자가 제공한 실험 결과이며, 이 문서는 알고리즘 우열을 검증하지 않는다.

## 구현 가능성

입력값을 읽는 `reactive()`와 이를 사용하는 `renderPlot()`·`renderTable()`을 연결하면 해당 입력 변경 시 필요한 결과가 자동 갱신된다. 실행 버튼 없이 파라미터와 분포·지표를 연동하는 것은 Shiny의 기본 기능이다. 여러 출력이 동일 계산 결과를 쓰도록 계산 reactive를 공유할 수 있다. [Shiny reactivity overview](https://shiny.posit.co/r/articles/build/reactivity-overview/)

`plotOutput()`은 base R·ggplot2 그래프의 클릭, 더블클릭, hover, brush 좌표를 입력으로 제공한다. 따라서 RT 구간 선택 → 해당 구간 상세 분포, 커서 위치 → 상세 수치 표시를 구현하는 데 Plotly는 필수가 아니다. 좌표를 받아 상세 표시나 확대 동작을 연결하는 앱 코드는 필요하다. [Interactive plots](https://shiny.posit.co/r/articles/build/plot-interaction/)

## 가벼운 미리보기

`debounce()`는 입력 변경이 잠잠해질 때까지 downstream 갱신을 미루고, `throttle()`은 계속 변경되는 중에도 일정 간격으로 갱신을 전달한다. 무거운 계산을 담은 reactive 자체가 아니라 **입력을 모으는 가벼운 reactive**에 적용하고, 비싼 계산을 그 뒤에 둔다. 원래 reactive 호출 횟수 자체는 줄이지 않기 때문이다. 간격은 최소 대기 시간이며 R 처리 상황에 따라 길어질 수 있다. [debounce/throttle](https://shiny.posit.co/r/reference/shiny/latest/debounce.html)

제안: 간단한 기준선·선택 구간·설정값은 바로 표시하고, 분포 계산은 입력이 약 300–500 ms 안정된 뒤 자동 갱신한다. 드래그 도중 연속 미리보기가 필요하면 가벼운 출력에 throttle을 검토한다. 실제 지연은 대표 데이터로 측정한 뒤 정한다.

`bindCache()`는 이전 파라미터 조합의 결과를 재사용할 수 있다. 기본 범위는 앱 전체이므로 업로드 데이터에는 우선 `cache = "session"`을 사용한다. 캐시 키에는 결과에 영향을 주는 모든 설정과 데이터 식별자를 넣어야 한다. 키가 반응성 의존성도 결정하므로 빠진 입력은 갱신 누락이나 잘못된 결과로 이어질 수 있다. 매번 대형 데이터를 해시하지 않도록 업로드 시 한 번 만드는 콘텐츠 식별자 또는 확실히 갱신되는 데이터 버전을 고려한다. 이 마지막 방식은 문서 원칙을 적용한 설계 제안이다. [bindCache](https://shiny.posit.co/r/reference/shiny/latest/bindcache.html)

## 오래 걸리는 최적화

`ExtendedTask`는 Shiny **1.8.1**에서 도입되었다. 일반 reactive 안에서 promises만 반환하는 접근과 달리 같은 사용자의 세션도 작업 중 다른 입력에 반응할 수 있도록 한다. 저장소 `DESCRIPTION`은 현재 `shiny (>= 1.7.0)`이므로 이를 채택하면 최소 버전을 올려야 한다. [Posit Shiny 1.8.1 발표](https://opensource.posit.co/blog/2024-03-27_shiny-r-1.8.1/)

공식 예제의 조합은 `ExtendedTask$new(function(snapshot) promises::future_promise({...}))`와 `future::plan(multisession)`이다. `ExtendedTask`로 감싸기만 해서는 부족하고 실제 계산을 비차단 방식으로 실행해야 한다. task 내부에서 `input`이나 reactive를 직접 읽지 않고, 호출 시점의 데이터·설정을 인수로 전달한다. 세션별 task는 server 함수 내부에서 생성한다. 현재 저장소에는 promises/future 직접 의존성이 없어 채택 시 의존성 선언과 worker 수·종료 처리를 함께 설계해야 한다. [Non-blocking operations](https://shiny.posit.co/r/articles/improve/nonblocking/)

`future::future()`는 worker가 모두 사용 중이면 제출 시 메인 R을 기다리게 할 수 있다. `future_promise()`는 worker가 가용해질 때 제출하도록 대기시켜 이 문제를 피한다. 비동기는 계산 자체를 빠르게 한다는 뜻이 아니며 worker가 부족하면 결과 도착은 늦어진다. [promises future_promise reference](https://rstudio.github.io/promises/reference/future_promise.html)

## 최신 설정과 결과의 일치

R의 `ExtendedTask$invoke()`는 실행 중 추가 호출을 순서대로 대기시킨다. 같은 task 객체는 동시에 여러 호출을 실행하지 않는다. 검토한 R 공개 API에는 취소 메서드가 없으므로 자동 취소·최신 요청 우선 처리를 기본 제공한다고 가정하면 안 된다. Python의 유사 API와 혼동하지 않는다. `result()`는 실행 전·진행 중·성공·실패 상태에 따라 다르게 동작하며, 변경 알림을 받도록 일반 reactive/render에서 읽는 것이 기본이다. [ExtendedTask R reference](https://shiny.posit.co/r/reference/shiny/latest/extendedtask.html)

이를 바탕으로 한 **앱 설계 제안**:

1. 변경된 설정마다 단조 증가 요청 ID와 데이터 버전을 부여한다.
2. 실행 중에는 새 task를 계속 invoke하지 않고, 별도 pending 슬롯의 설정을 최신 1개로 교체한다.
3. 완료 후 최신 pending이 있으면 그 설정만 다음으로 실행한다.
4. 완료 결과의 요청 ID·데이터 버전이 현재 설정과 같을 때만 현재 결과로 반영한다. 이전 결과를 유지할 때는 변경 전 결과임을 표시한다.
5. 다운로드에는 확인된 결과와 해당 설정 스냅샷을 함께 사용한다.

이 방식은 실행 중 계산을 강제 종료하지 않지만 오래된 요청의 누적과 결과의 혼동을 줄인다. 실제 계산 취소가 필요하면 선택한 worker backend에 맞춘 별도 구현과 검증이 필요하다.

## 적용 판단

KDE + Dense 기본 설정에서 시작해 파라미터 옆에 분포·제약·예상 지표를 함께 보여주는 구성이 가능하다. 먼저 입력 의존성을 나누어 필요한 계산만 갱신하고, 대표 데이터에서 각 계산 시간을 측정한다. 짧은 계산은 reactive + debounce + cache로, 긴 계산은 요청 관리가 포함된 ExtendedTask로 연결한다. 빠른 미리보기와 전체 계산의 정확도 수준이 다르면 화면에서 구분한다. 아직 실제 앱 실행이나 성능 검증은 수행하지 않았다.
