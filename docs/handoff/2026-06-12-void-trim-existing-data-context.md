# Context — 기존 DIA 데이터의 void(MS1-only) 1회 trimming

> **이 문서의 용도**: 새 세션(별도 작업 영역)에서 *이미 취득된* DIA 원시 데이터의
> 선행/후행 MS1-only void 구간을 1회성으로 제거하기 위한 자립형 컨텍스트.
> AIDIA R 패키지 밖에서 수행한다(ADR 0004: AIDIA는 결과 기반, raw/mzML 미취급).

---

## 1. 문제 (왜 이 작업이 필요한가)

- AIDIA는 RT-segment 기반 DIA isolation-window method를 생성하며, 스케줄 RT 범위를
  **precursor가 존재하는 구간으로 clip**한다.
  - `R/rt_binning.R`: segment stats `rt_start = min(RT.Apex)`, `rt_end = max(RT.Apex)`
  - `docs/domain-knowledge.md`(746–757): "LC dead zones are excluded by construction"
- 결과적으로, 취득된 raw에서 **첫 segment 이전 / 마지막 segment 이후** 시간대에는
  스케줄된 DIA window가 없어, 기기가 그 구간을 **MS1-only survey scan**으로 채운다("void").
- 이 MS1-only 구간이 DIA-NN이 기대하는 **균일한 DIA duty-cycle 구조를 깨뜨려**
  cycle 처리와 DIA-NN의 내부 self-calibration(충분한 confident ID에 의존)을 저해한다.
- 이는 **의도된 설계이지 버그가 아니다**. 향후 재발 방지(=method export에서 첫/마지막
  segment를 acquisition 경계로 확장, "방법 2")는 **이 작업의 범위 밖**이며 별도로 논의한다.
- **이 작업의 목표**: 이미 취득돼 MS1-only void가 박혀 있는 파일들을 지금 깨끗하게
  분석되도록 1회 교정한다.

## 2. 목표 / 완료 기준

- 선행/후행 MS1-only void scan을 제거한 trimmed mzML 생성 → DIA-NN이 **균일한 cycle 구조**만 보게 함.
- 검증:
  - DIA-NN가 cycle 구조 문제 없이 실행됨
  - precursor/protein ID 수가 untrimmed 대비 회복됨
  - 결과 파일의 첫/마지막 scan time이 DIA 스케줄 RT 범위 안에 들어옴

## 3. 입력물

- **취득된 Thermo `.raw`**(또는 이미 변환된 `.mzML`) 파일 목록.
- 각 데이터 취득에 사용한 **AIDIA export method CSV**(8컬럼 Thermo Xcalibur 포맷).
  trim 경계는 여기서 도출한다:
  - 컬럼: `RT Time (min)`(= segment 중심), `Window (min)`(= segment RT 폭)
  - **trim 시작(min)** = `min(RT Time − Window/2)` (전체 행 기준)
  - **trim 종료(min)** = `max(RT Time + Window/2)` (전체 행 기준)
  - msconvert는 초 단위 → ×60
  - CSV가 없으면: untrimmed DIA-NN report의 DIA window RT min/max, 또는 Xcalibur method에서 도출.
- **ProteoWizard(msconvert)** 설치(Windows).

## 4. 접근법 (권장: msconvert)

msconvert가 raw→mzML 변환 + RT trim을 한 번에 수행한다:

```powershell
msconvert INPUT.raw --filter "scanTime [START_SEC,END_SEC]" --mzML -o OUT_DIR
```

- `START_SEC`,`END_SEC` = 위에서 구한 trim window(초). scanTime은 **초 단위**, 범위 *안*을 keep.
- 시간 기준이라 양 끝의 MS1-only 구간이 통째로(거의 cycle 경계에서) 잘려나가 균일 cycle만 남음.
- 이미 `.mzML`이면 동일 필터로 mzML→mzML.
- 주의:
  - `peakPicking` 필터는 **추가하지 말 것** — 기존 취득/분석이 쓰던 centroiding 설정을 보존
    (Thermo는 MS2를 centroid로 저장하는 경우가 흔함). 불필요하게 바꾸면 비교가 깨짐.
  - 다수 파일은 CSV→[start,end]초 계산→파일별 msconvert 호출하는 **얇은 래퍼 스크립트**(PowerShell/Python/Bash)로 배치.
- 대안(순수 RT trim에는 불필요): per-scan 커스텀 로직이 필요할 때만 Python `pyopenms`.

## 5. 작업 위치 (별도 영역)

- 이 작업은 AIDIA **상류(upstream)**이며 AIDIA R 패키지에 넣지 않는다(ADR 0004).
- 별도 작업 디렉터리/리포(예: `aidia-void-trim` 또는 단순 `scripts/` 폴더)에서 수행.
- 완성도 높은 도구일 필요 없음 — **AIDIA CSV 읽기 → [start,end]초 산출 → 파일별 msconvert 실행**
  하는 1회성 스크립트로 충분.

## 6. 범위 밖 (하지 말 것)

- 방법 2(AIDIA export 설계 변경으로 재발 방지) — 별도 brainstorming, 보류 중.
- 재사용 가능한 범용 preprocessing "기능" 제작 — 불필요.
  (문헌 검토 결과 void trim의 FDR/데이터-품질 이득은 실증되지 않았고, FDR은
  query space·decoy·시료 복잡도가 지배하며, DIA-NN이 mass/RT calibration을 내부 수행함.
  trim의 유일한 확실한 효과는 "cycle 정상화"인데, 기존 파일엔 trim이 유일한 소급 수단.)

## 7. 검증 체크리스트

- [ ] before/after DIA-NN precursor & protein ID 수 비교(회복 확인)
- [ ] trimmed 파일에 MS1-only 연속 구간이 없는지(scan 목록/SeeMS 등으로 점검)
- [ ] 첫/마지막 MS time ≈ trim window
- [ ] 동일 DIA-NN 설정으로 재현(설정 변경 없이 입력만 교체)

## 8. AIDIA repo 참조 (D:\Projects\aidia)

- `R/rt_binning.R` — RT를 precursor span으로 clip(rt_start/rt_end 출처)
- `R/export_methods.R` — `RT Time (min)` / `Window (min)` 컬럼(trim 경계 도출원)
- `docs/domain-knowledge.md` (~746–757) — dead-zone 설계 근거
- `docs/adr/0004-result-driven-input-no-raw-file.md` — raw/mzML이 AIDIA 밖인 이유

## 9. 이후 연결

이 1회 trim 완료 후, **방법 2(향후 데이터용 export RT 확장)** 설계 논의를 AIDIA 세션에서 재개한다.
방법 2의 첫 미해결 질문: *initial/end point를 무엇으로 잡을지(0 & gradient length인지),
그리고 AIDIA가 현재 gradient 전체 길이/acquisition 윈도우 값을 보유하는지.*
