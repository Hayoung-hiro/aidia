# Global 분석 영역과 RT 근사: 별도 연구 브랜치 설계안

상태: 검토 제안. 새로운 알고리즘의 구현·실험 검증 결과가 아니다.
검토 기준 HEAD: `11f41b641a1e05262af6a911b8be0c4fa9df6bc2`.
현재 논문용 계산 코드와 CSV 기본값은 변경하지 않았다.

2D 분포를 활용한 추가 획득 전략과 결과 페이지의 대조 평가 설계는
[획득 비교 설계안](2026-09-10-acquisition-comparison-design.md)에 기록했다.
해당 지표는 새 raw 데이터로 확인된 성능 향상을 의미하지 않는다.

## z 운영값 정리 — 후속 논의

현재 논문용 CSV는 기존 기본값 **z=1을 유지**한다. 아래의 z=2/3 후보 논의는
기본값 변경의 근거로 채택하지 않는다. 사용자 인용 문서가 명시하는 것은 예상
precursor 전하, 범위 0–100, 기본 1, 그리고 0의 charge 무시 의미다.
최빈 전하를 CSV z에 넣어야 한다는 요구나 그로 인한 성능 개선은 이 설명에서
확인되지 않는다. NCE가 charge에 의존한다는 일반 설명만으로 해당 취득 구성에서
이 CSV 필드의 변경 효과가 확인되었다고 표현해서도 안 된다.

0과 1을 동등한 의미로 취급하지 않는다. 전하 무시를 요청하는 값은 문서상 0이고,
1은 현재 사용해 온 기본값이다. 이전 0 import 문제의 원인은 미확정이다.
이번 결정은 기존 method의 재현성과 import 호환성을 유지하려는 선택이며,
1이 물리적으로 최적이거나 획득에 영향이 전혀 없다는 주장은 아니다.

사용자가 z=0에서 import 문제가 발생하고 z=1에서는 정상임을 재확인했다.
이후 대응을 위해 Results의 export 설정에 `Thermo charge state (z)` 입력을 추가했다.
기본값은 1이며 0–100 정수를 허용한다. 선택값은 Thermo 단일 CSV, ZIP 및 배치
export에 전달되고, R export 함수와 main pipeline에서도 `charge_state`로 지정한다.
이는 다운로드 시점의 출력 설정이며 최적화된 RT/m/z 범위는 변경하지 않는다.

## 1. Global의 정의와 구현 가능성

### KDE 보존 및 비교 방법 — 후속 합의와 권고

사용자는 현재 KDE가 잘 작동한다고 설명했으며, precursor 기반과 intensity 기반
결과를 비교하여 사용자가 선택하는 구성을 요청했다. 권고는 기존 `kde`를 보존하고
새 `kde_2d`를 별도 방법으로 추가하는 것이다. 아래 전역 KDE 목적함수는 새 방법에
해당하며 현재 KDE를 대체하거나 기존 저장 설정의 의미를 바꾸지 않는다.

- 기존 KDE: RT bin별 1D m/z KDE, 주봉 상대 threshold, minimum coverage와 margin.
- 새 2D-KDE: 최종 RT bin에 독립적인 RT–m/z 밀도, 두 축 bandwidth, 전역 영역 선정.
- 밀도 가중 기준: 전구체 개수 / intensity. 새 방법 안의 비교 가능한 설정으로 두며
  서로 다른 알고리즘 이름을 무한히 늘리지 않는다. 기존 KDE의 가중치 기능을 조용히
  변경하지 않고 원래 실행 경로와 기본값을 보존한다.
- 새 RT 분할과 후속 smoothing은 새 전역 영역 경로에 우선 적용한다. 기존 KDE에
  이를 강제해 놓고 기존 결과가 보존된다고 표현하지 않는다.

2차원이라는 사실이 우수성을 보장하지 않는다. 새로운 RT bandwidth는 sparse 영역의
자료 공유를 가능하게 하지만 시간적으로 가까운 다른 집단을 합칠 수도 있다.
현재 KDE와 새 방법은 차원뿐 아니라 목적함수도 다르므로 관찰된 차이를 2D 효과만으로
설명하지 않는다. 필요하면 밀도 추정 변경과 영역 선정 규칙 변경을 분리한 비교를 한다.

비교 화면은 동일 입력·품질 필터·취득 범위·CT·cycle당 창 수를 사용하고, 각 결과의
전구체 coverage, intensity coverage, 반복 검출 대상 coverage, 단백질 그룹 coverage,
측정 폭과 window별 부하를 표시한다. 품질/coverage 지표는 run 제외 검증에서도 평가한다.
개수 coverage 80%와 intensity coverage 80%는 서로 다른 분모이므로 동일한 성능으로
표시하지 않는다. 가능한 공통 개수 coverage 조건 아래에서 비교하거나, 측정 폭과
두 coverage의 trade-off를 함께 제시한다. 사용자가 선택한 기준과 전체 설정을 저장한다.

### Intensity와 유효 전구체의 해석

Intensity는 강한 신호가 집중된 위치를 나타낼 수 있지만, 전구체 종의 수나 실제
cofragmentation interference와 같지 않다. DIA-NN 문서는 Precursor.Quantity를
MS2 기반 정량값으로, Ms1.Area를 별도 MS1 peak area로 설명한다. QuantUMS 등
정량 모드에 따라 MS1 정보도 사용될 수 있으므로 입력 버전/모드와 열 의미를 기록한다.
Precursor.Quantity를 직접적인 precursor ion flux라고 부르지 않는다. Ms1.Area도
적분 면적이며 순간 동시 용출 이온 부하와 동일하지 않다.
[DIA-NN 공식 출력 설명](https://github.com/vdemichev/DiaNN#main-output-reference),
[개발자의 정량 모드 설명](https://github.com/vdemichev/DiaNN/discussions/764).

식별된 precursor 표는 관측된 후보 집합이며 미식별 background까지 포함하는 전체
이온 집합이 아니다. 해당 표로 만든 혼잡도는 대리 지표로 보고한다.

현재 loader는 존재하는 열과 설정에 따라 Q.Value, library/global q-value 및
Quantity.Quality를 필터링하고 consensus는 반복 수와 intensity CV를 사용할 수 있다.
따라서 초기 기본안은 이미 합의한 품질 필터를 통과한 precursor의 개수 기반이다.
q-value를 개별 precursor의 오류확률로 간주해 1-q를 가중치로 쓰지 않는다.
약한 신호라는 이유만으로 무효하다고 분류하지 않는다.

추가 실험 후보로 반복 검출 가중치를 제안한다:

`w_i = r_i / S`, 여기서 r_i는 학습에 사용한 유사 run 중 품질 조건을 충족해
해당 precursor가 검출된 서로 다른 run 수, S는 전체 학습 run 수다.

반복해서 관찰되는 후보에 무게를 주지만 이것이 미래 취득의 검출 확률로 보정된
모델인 것은 아니다. 누락된 후보와 특정 시료에만 존재하는 후보를 과소평가할 수
있으므로 일반 개수 coverage를 함께 보고한다. 현재 n_replicates=n() 값을 그대로
신뢰하지 않고 Precursor.Id/run의 중복 의미를 확인하여 distinct run을 센다.
새 가중치를 기본값으로 채택하기 전에 기존 count/intensity 두 기준과 비교한다.
검증 run으로 가중치를 계산하거나 전체 run의 consensus를 미리 사용하지 않는다.

당장 복합 가중치 하나를 강제하기보다 count와 intensity의 개별 결과 및 양쪽에서
열등하지 않은 후보(Pareto 후보)를 비교하도록 한다. 반복 검출 가중은 추가 검증 대상이다.

사용자의 Global을 **전체 RT–m/z 자료로 시간에 따라 변하는 대표 영역을 추정하고,
그 다음 장비용 RT 구간으로 근사하는 방법**으로 사용자가 확인했다. RT를 없애고 m/z만
pooling하면 시간 변화가 사라지므로 이 요구를 충족하지 못한다.

현재 Greedy/KDE는 `R/mz_optimization.R`에서 `rt_group`별 계산을 수행한다.
`R/window_optimization.R`의 순서를 바꾸고 bin에 독립적인 영역 표현을 도입해야 한다.
밀도 추정용 계산 격자는 장비 RT bin과 구분하며, 최종 K 변경이 추정 영역을 바꾸지
않아야 한다. Global이라는 이름만으로 수치적 전역 최적해 보장이 생기는 것도 아니다.

권장 흐름:

`동일 batch의 유사 run → 전역 분포·초기 분석 영역 추정 → 기준 영역 고정
→ 후보 K와 RT 경계·구간별 m/z 범위 결정 → 해당 bin의 m/z 경계 smoothing
→ 최종 근사 오차·coverage 평가 → K 선택 → window 생성·최종 CSV 검증`

사용자 후속 논의에 따라 별도 경계 smoothing을 bin 결정 뒤로 이동한다.
KDE 자체의 kernel smoothing은 분포 추정에 내재하며, 여기서 이동하는 것은
구간별 m/z 경계 smoothing이다. 후보마다 정한 K와 RT 경계는 해당 smoothing 중
고정한다. 전체 후보에서 최종 K를 확정하는 것은 smoothing 후 평가를 거친 뒤다.
초기 분할에서 통과한 coverage 조건이 smoothing 후에도 유지된다고 가정하지 않는다.

새 seam은 `estimate_analysis_domain()`과 `approximate_rt_schedule()`로 둔다.
첫 결과는 실제 시간 좌표의 L(t), U(t), 추정 설정과 자료 식별자를 보유한다.
둘째 결과는 최종 RT 경계, m/z 경계, 목적함수 값과 제약 충족 상태를 보유한다.
기존 window 생성은 구간별 범위 입력을 재사용할 수 있지만 export의 중점 경계
재계산은 새로 최적화한 RT 경계를 보존하도록 별도로 처리해야 한다.

## 2. 전역 영역 추정 목적함수 후보

아래 수식은 이번 요구에 맞춘 제안이며 기존 코드나 문헌의 검증 완료 알고리즘이 아니다.

run s의 정규화된 RT–m/z 밀도를 p_s(t,m), run 수를 S로 둔다.
각 run의 총 질량을 1로 맞추고 평균 p_bar = sum_s p_s / S를 사용한다.
단순 pooling에서 검출 행이 많은 run이 지배하는 것을 줄이지만, 이 평균만으로
이상치에 대한 강건성이 보장되지는 않는다. 제외 run 검증에서 안정성을 확인한다.
전구체 수와 intensity 가중을 나란히 비교한다. RT와 m/z를 두 좌표로 유지하며,
intensity는 표면 높이/색 및 각 전구체의 KDE 가중치로 사용한다. RT 또는 m/z 축을
intensity로 대체하거나 3차원 KDE를 수행할 필요는 없다.

`p_s(t,m) = sum_i w_si K_ht(t-t_si) K_hm(m-m_si) / sum_i w_si`

- 개수 밀도: w_si=1.
- 신호 가중 밀도: w_si=I_si (run별 총 가중치로 정규화).
- 강한 소수 신호의 영향을 완화하는 별도 비교: sqrt(I_si) 등의 변환 가중치.

변환 가중치를 실제 총 intensity라고 부르지 않는다. 높은 intensity만으로 많은
전구체의 공존이나 실제 interference를 단정하지 않는다. 약한 전구체를 보호하도록
개수 기준 coverage도 유지한다. bandwidth와 가중치 변환은 저장 설정에 포함한다.
음수·비유한 intensity의 처리와 intensity 누락 시 동작을 명시하고, count 모드로
조용히 대체한 결과를 intensity 최적화 결과라고 보고하지 않는다.

기존 `Precursor.Quantity`는 consensus에서 replicate 중앙값으로 보존된다.
run 제외 검증에서는 이 전체-run consensus를 재사용하지 않고 학습 run만으로
다시 추정해야 한다. 또한 quantity가 raw MS1 intensity인지 fragment 기반 정량인지
입력 자료에서 확인한 뒤, 후자라면 직접적인 precursor ion flux로 해석하지 않는다.
현재 `plot_rt_mz_intensity_surface()`는 log10(I+1)의 보간 또는 합산이며 2D KDE가
아니다. 해당 그림의 'Summed Intensity' 라벨만으로 실제 총 신호량을 해석하지 않는다.

가중 다변량 KDE의 구현 예는 [SciPy 공식 문서](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.gaussian_kde.html)에 있다.
R의 MASS::kde2d에는 weights 인자가 없으므로 이전 구현 후보를 그대로 가중 KDE에
사용할 수는 없다. 이는 구현 검토이며 Python으로 프로젝트를 전환한다는 뜻은 아니다.

영역 A는 시간별 단일 구간 [L(t), U(t)]으로 제한한다. 시간과 m/z를 고정된
취득 범위로 정규화한 좌표에서 굴곡 비용 R을 정의해 단위 의존성을 줄인다.

### Greedy 계열: 고정 폭의 전역 경로

폭 W를 현재의 공통 창 수와 권장 폭에서 고정하고 U=L+W로 둔다.

`maximize integral_A p_bar(t,m) dt dm, with U(t)-L(t)=W`

초기 영역은 전체 RT에서 포함되는 전구체 질량을 최대화한다. 별도 굴곡 벌점은
이 단계에서 제외하고 분할 후 경계 smoothing 단계에 둔다. 시간 간 결합이 없는
제약 아래서는 각 시간 위치의 범위 선택으로 분리될 수 있다. Global의 의미는 최종
RT bin에 독립적인 전체 분포 추정이며, 수치적 공동 최적화 여부와 구분한다.
실제 최적화기는 비볼록 문제 또는 유한 후보 경로 탐색이며 전역 최적 보장 범위를
명시해야 한다. 기존 Greedy와 동일 알고리즘으로 부르지 않고 별도 버전으로 기록한다.

### KDE 계열: 목표 질량을 포함하는 최소 영역

전역 2차원 KDE로 p_s 또는 p_bar를 추정한 뒤:

`minimize area(A)`

`subject to integral_A p_s(t,m) dt dm >= q, for each preselected valid run s`

q는 목표 coverage다. 공통 window 수에서 실현 가능한 폭 제한과 단일 m/z 구간
제약을 추가한다. 모든 run 조건은 보수적이며 불가능할 수 있으므로 실패를 명시한다.
이를 완화하려면 허용할 run 비율을 사전에 정하고 최악 run 성능을 함께 보고한다.
전체 coverage만 제약하면 희소 RT에서 성능이 낮을 수 있어 RT별 coverage도 검증한다.

기존 KDE의 '주봉 상대 밀도 threshold'와 새 q는 다른 파라미터다. 자동으로 같은 값으로
치환하지 않는다. KDE 등밀도선은 여러 조각일 수 있으므로 단일 구간 제약 없이 타원형
영역을 가정하지 않는다. 순수 KDE bandwidth smoothing과 추가 경계 regularization은
분리 기록한다. 별도 경계 smoothing은 분할 후 적용한다.

R에서 RT/mz별 bandwidth를 쓰는 2D KDE는 구현 가능하다.
[MASS kde2d 공식 문서](https://stat.ethz.ch/R-manual/R-devel/library/MASS/html/kde2d.html).
이 함수의 가용성은 위 목적함수나 생물학적 성능의 검증을 뜻하지 않는다.

## 3. 권장 RT 근사 목적함수

추정한 A를 고정하고 K개 RT 구간에 대응하는 직사각형 합집합을 B_K로 둔다.
각 시간에는 하나의 외곽 m/z 범위만 활성화하며 RT 구간은 연속적으로 이어진다.

`E_geom(B_K) = area(A symmetric_difference B_K) / area(A)`

분자는 `A에서 빠진 면적 + A 밖에 추가한 면적`이다. 실제 RT 길이로 적분하므로
긴 구간의 오차가 더 크게 반영된다. 모든 범위를 넓게 덮는 해도 추가 면적 때문에
비용을 지불한다. area(A)>0일 때 정의되며 이 비율의 상한이 1인 것은 아니다.
면적 비용은 interference나 정량 손실의 직접적인 측정치가 아니다.

run s에서 새로 놓치는 비율을 다음처럼 별도로 제한한다.

`D_s(B_K) = count{(RT.Apex, m/z) in A and not in B_K} / total_precursors_s`

이는 전체 run 전구체 대비 추가 누락 비율이다. B_K가 다른 전구체를 새로 포함해도
기존 대상 누락을 상쇄하지 못한다. A 내부 대상만을 분모로 쓴 보존율도 보조 보고한다.
RT.Apex 포함 여부는 peak 전체의 보존을 뜻하지 않으므로 기존 경계 손실 평가를 유지한다.

초기 분할의 기준식은 다음과 같다:

`B_K* = argmin E_geom(B_K)`

제약:

- `max_s D_s(B_K) <= epsilon_cov` (사전에 선정한 정상 유사 run에 적용)
- 모든 bin의 CT와 cycle당 창 수 고정; 전략별 폭 조건 유지
- bin 최소 길이는 완전한 cycle/staggered 패턴과 처리 요구에 맞춤
- 실제 최종 window 및 CSV에서 폭·스케줄 제약 충족

분할 후 smoothing을 S_lambda로 표기하면 최종 후보는
`B_tilde_K = S_lambda(B_K)`다. S_lambda는 RT 경계와 K를 유지하고 m/z 경계만
조정하며, Greedy의 고정 폭 및 KDE의 coverage/폭 조건을 지켜야 한다.
bin 폭이 다르면 실제 RT 중심 간격으로 굴곡을 계산한다. Greedy는 중심 경로를
smooth하고 고정 폭으로 복원하며, KDE는 중심과 양수 폭 등의 표현을 검토한다.
현재 WH의 독립적인 하한/상한 smoothing과 사후 폭 복구만으로 이 조건이 보장되는
것은 아니다. 한 bin일 때는 경계 smoothing을 하지 않는다.

최종 목표는 **smoothing 후 E_geom을 최소화하면서 smoothing 후 누락 조건을 만족**하는
후보를 찾는 것이다. 초기 목적함수의 1등만 smoothing해서는 그 최종 목표의 전역해를
보장할 수 없다. 초기 후보 탐색과 최종 후보 순위를 구분해 저장한다.

K 선택 (아래 B_tilde_K는 평가한 최종 후보를 뜻하며 전역 최적 보장은 별도):

`K* = min {K : E_geom(B_tilde_K) <= epsilon_geom and all final constraints pass}`

즉 분석적으로 충분한 후보 안에서 작은 K를 택한다. 임의의 CSV 행 수 벌점 계수를
주요 목적함수에 넣지 않는다. 조건을 만족하는 후보가 없으면 실패를 보고하고
임계값을 자동 완화하지 않는다. epsilon_geom은 형상 근사 오차, epsilon_cov는
허용 추가 전구체 누락이라는 서로 다른 의미를 갖는다.

예시일 뿐인 판정: epsilon_geom=0.03, epsilon_cov=0.005이면
면적 불일치 3% 이내이며 모든 평가 run에서 전체 전구체의 추가 누락 0.5%p 이내인
최소 K를 고른다. 이 숫자는 권장 기본값이나 실제 데이터 결과가 아니다.

인접 병합은 빠른 근사 탐색이다. 고정 기준 영역에 대한 가산 면적 비용만 사용하면
유한 후보 경계 위에서 동적 계획법으로 각 K의 최적 분할을 구할 수 있다. 그러나
run별 누적 누락 제약까지 포함한 문제에는 단순한 하나의 비용 DP로 충분하지 않으며,
제약 상태를 유지하는 탐색이나 별도 constrained solver가 필요하다.

### 탐색 범위와 연산량

K의 최소·최대가 알려져 있어도 같은 K의 모든 경계 배치를 평가한 것은 아니다.
M개 기본 시간 셀에서 K개 연속 구간을 만드는 경계 조합 수는 choose(M-1,K-1)이며,
전체 K를 허용하면 2^(M-1)개다. 최소 길이와 스케줄 제약은 이 수를 줄인다.
연속 RT 경계까지 허용하면 먼저 후보 좌표/정밀도를 정의해야 유한 문제가 된다.

구간 비용을 사전 계산하고 가산성만 사용하는 초기 DP는 대략
O(K_max * M^2) 시간이며 사전 계산 비용은 별도다. 예를 들어 M=300, K_max=30이면
약 135만 규모의 전이 후보(삼각 합에 근거한 상한 규모)를 검토하며, 이는 실행 시간
측정 결과가 아니다. 구간당 m/z 탐색·밀도 계산·누락 제약 비용은 이 숫자에 포함되지 않는다.
전체 구간에 걸친 smoothing을 합성한 최종 목적함수에는 이 단순 DP 복잡도를 적용할 수 없다.

정확한 탐색을 우선 검토한다. 작은 격자에서는 전수 탐색으로 정답을 확보하고,
가산 목적의 DP와 비교한다. 최종 smoothing 및 run별 제약을 포함하는 탐색은
필요한 상태 확장/제약 solver와 실행 시간·메모리·최적성 gap을 측정한다.
부담이 확인되면 그때 후보 축소/병합을 도입하고 근사해라는 점을 보고한다.
현재 WH는 dense solve이며 500개 초과에서 원래 값을 반환하므로 많은 K를 다루는
새 브랜치에서는 sparse/banded 계산 또는 명시적인 한계 처리가 필요하다.

## 4. 검증과 논문 버전 분리

- 분석용 추정 해상도를 고정하고 K를 바꿔 A가 바뀌지 않는지 확인한다.
- 합성 단일 띠, 곡선 띠, 다봉, 희소 꼬리 자료에서 면적과 누락 계산을 검증한다.
- Greedy/KDE를 우선 대상으로 기존 방식과 새 방식을 같은 저장 설정에서 비교한다.
- 실제 run을 제외하는 검증으로 bandwidth/lambda 및 허용 오차 민감도를 평가한다.
  검증 중 제외 run은 A 추정에 사용하지 않는다. 최종 성능은 별도 run 또는 바깥쪽
  검증에서 평가한다. 반복 수가 부족하면 모집단 일반화 주장을 제한한다.
- 구간별 최종 CSV의 RT 경계, 고정 CT/N, staggered 변환·demultiplexing 가능성을
  확인한다. Offline coverage가 실제 identification/quantification 성능을 보장하지 않는다.
- 현재 HEAD를 기준으로 별도 `research/global-domain-v2` 브랜치에서 구현한다.
  현재 작업은 검토이므로 브랜치 전환·생성이나 계산 코드 변경은 수행하지 않았다.
- 기존 결과/설정 재실행 경로를 유지하고 새 방법에는 명시적인 알고리즘 버전을 부여한다.
  각 결과에 commit, 입력 식별자, 전체 설정, bandwidth/lambda, 목적함수, 허용 오차,
  최종 경계, z와 NCE 설정을 기록한다. 새 결과를 기존 논문 결과로 덮어쓰지 않는다.

## 5. z=0과 Excel 가설

기존 통합 검증 ZIP의 thermo.csv는 120행, z=1, 전체 ASCII, BOM 없음으로 확인했다.
UTF-8과 CP949에서 숫자 0/1/2는 각각 동일한 바이트 30/31/32(hex)다.
따라서 이 두 인코딩의 차이만으로 숫자 0만 사라진다는 설명은 약하다.
실제로 실패한 파일은 확보하지 않았으며 원인을 확정하지 않는다.

Excel의 재저장 과정에서 구분자, BOM, 파일 형식이 달라질 수 있다.
[Microsoft CSV 가져오기/내보내기](https://support.microsoft.com/en-us/excel/get-started/import-or-export-text-txt-or-csv-files),
[UTF-8과 BOM 설명](https://support.microsoft.com/en-US/Excel/opening-csv-utf-8-files-correctly-in-excel).
진단은 Excel을 거치지 않은 동일 파일에서 z만 0/1/2로 바꿔 import하고,
그 다음 Excel 재저장 전후를 비교하는 순서가 적절하다.

Exploris tMS2는 0을 charge 무시, 기본값 1로 문서화한다. NCE는 mass/charge의
영향을 받으므로 z=2를 무조건 무해한 호환성 대체값으로 간주하지 않는다.
[Thermo 공식 tMS2 문서](https://docs.thermofisher.com/r/Orbitrap-Exploris-480-Software-Manual/2075558155v2en-US).
Peptide에서 2는 타당한 대표값 후보지만 실제 import 후 적용되는 collision energy와
scan 설정을 확인하고 변경 이력을 남겨야 한다. 이번 검토에서 기본값은 바꾸지 않았다.

### 사용자 제공 tSIM=1 / tMS2=3 참고 method

사용자는 같은 DIA 구성의 다른 method에서 tSIM mass list는 z=1, tMS2는 z=3을
사용한다고 설명했다. 해당 method 파일이나 실측 전하 분포는 이번에 직접 확인하지 않았다.
tMS2의 z는 분해 전 precursor의 예상 전하이며 MS2 fragment의 전하가 아니다.
mass list의 3이라는 값 자체가 실측 precursor에서 3+가 우세하다는 증거는 아니다.
관심 분석 영역에서 precursor 3+가 우세하고 같은 장비·취득 모드의 NCE 조건이
적절하다면 3은 합리적인 대표값 후보다. 최빈 전하라는 이유만으로 최적 NCE나 정량
성능이 증명되지는 않는다. Precursor.Charge별 개수와 quantity 비중을 함께 보고,
참고 method의 NCE·scan 설정과 비교한다. 자동 최빈값 변경은 실험 간 조건을 바꿀 수
있으므로 z는 명시적으로 저장하는 acquisition 설정으로 둔다. 현재 기본 1은 유지했다.
