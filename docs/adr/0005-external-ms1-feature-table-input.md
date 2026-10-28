# 외부 MS1 feature table 입력 허용

2026-10-19, 이슈 #17에 대한 사용자 승인에 따라 ADR-0004의 report-only 범위를 **외부 도구가 완성한 alphaextract feature table**에 한해 확장한다. DIA-NN 결과표를 기본 입력으로 유지하고, MS1 feature table에는 별도 adapter와 명시적 입력 모드를 제공한다. Vendor raw/method reader, raw 재처리, scan-summary ingestion은 이 결정에 포함되지 않는다.

Feature key는 한 run에서 검출된 feature를 추적하는 키이며 peptide/protein identity가 아니다. 실제 apex와 단위, FWHM 출처, 추출 provenance를 보존하고 가짜 생물학적 주석을 만들지 않는다.

2026-10-19 후속 사용자 승인으로 복수 파일·복수 run을 허용한다. 동일 batch와 호환 가능한 LC·측정 조건의 자료를 사용하도록 권고하지만, 시료명·LC 길이·batch label로 입력을 차단하지 않는다. 입력 집합의 적합성 판단은 사용자에게 맡긴다. 단위·중복 key·잘못된 대응 관계처럼 계산의 의미를 깨뜨리는 구조 오류는 계속 검증한다.

일반 feature table은 모든 검출 행을 모으는 pooled 방식으로 처리한다. alphaextract가 공동 export한 `export_id`와 `feature_group_id`가 있으면 기본적으로 distinct run 검출 빈도와 중앙값을 이용한 consensus를 만든다. 검출 빈도 기본값은 DIA-NN과 같은 `ceiling(n_runs / 2)`이며 사용자가 바꿀 수 있다. 서로 다른 run의 feature_id 번호로 대응 관계를 추정하지 않는다. RT 정렬은 생산자가 명시한 분 단위 shift만 적용하고 원본 RT와 물리적 FWHM은 보존한다. 정렬을 지정하지 않으면 native RT를 사용했다고 기록한다.

ID/MS1 비교는 같은 run 집합의 map에 동일한 cycle time, window 수, instrument 설정, 전체 m/z 범위와 RT schedule을 적용한다. 빈 구간도 유지하며, 동일 MS1 평가 map으로 두 설계의 부하를 계산한다. MS1 FWHM으로 예산을 재최적화하지 않으며, 목표 미달 satisfaction은 그대로 기록한다. Offline 포함 상태와 부하는 실제 ID 증가나 정량 성능의 증거가 아니다.

입력 계약, 실행 예제와 제약은 [MS1 feature map 사용법](../ms1-feature-map-input.md)에 정의한다.
