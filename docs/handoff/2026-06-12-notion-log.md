# Notion 수행 로그 (붙여넣기용)

> Notion MCP가 현재 세션에 미연결이라 자동 게시 불가.
> 아래 블록을 수행 로그 페이지에 붙여넣으세요:
> https://www.notion.so/2fe8b5b7cd298196adcbc1df19ff1006

---

### [2026-06-12] - AIDIA

**작업**: void(MS1-only) 영역 처리 방향 결정 — 기존 데이터 1회 trim + 향후 방법 2(export 설계 변경)

**논의 내용**:
- 문제: AIDIA가 RT 범위를 precursor span으로 clip(`rt_binning.R`: rt_start=min(RT.Apex), rt_end=max(RT.Apex)) → 생성된 method의 첫 segment 이전 / 마지막 segment 이후 시간대는 스케줄된 DIA window가 없음 → 기기가 MS1-only로 취득 → DIA-NN duty cycle 구조 깨짐. **의도된 설계, 버그 아님**.
- 두 해법 비교
  - 방법 1: mzML로 변환하며 void 구간 trimming (소급/별도 작업)
  - 방법 2: export에서 첫/마지막 segment의 RT를 acquisition 경계로 확장 (향후 예방)
- 핵심 재구성: 현재 clip 설계는 **이미 void에 MS2를 안 찍고 있음**(void=MS1-only). 즉 "데이터 작게 + FP 줄이기"라는 원래 목표는 이미 달성, 부작용(cycle 깨짐)만 남은 상태. 따라서 실제 선택지는 "void MS2 찍느냐"가 아니라 trim(삭제) vs extend(채움).
- trimming 가치 검토 (문헌 포함)
  - 데이터 사이즈 이득: 작음. 단 짧은 gradient(Astral high-throughput)일수록 void 비율↑.
  - FDR 이득: **직접 실증 문헌 없음**. FDR은 query space·decoy 모델·시료 복잡도가 지배하지, void scan 포함 여부가 아님. void는 라이브러리 entry를 늘리지 않음.
  - proteomics vs metabolomics: DIA-NN/Spectronaut가 mass recalibration(per-run·국소적) + 비선형 RT/iRT alignment + MS1/MS2 interference correction을 **내부에서 고도로 자동 수행** → raw 직접 사용이 표준. metabolomics식 사용자 preprocessing은 결을 거스름.
  - 운영 포인트: Windows에서 DIA-NN은 `.raw`를 직접 read → 방법 1은 불필요한 mzML 변환을 강제(대용량에서 비용↑).

**결정사항**:
- **향후 데이터 → 방법 2 채택**(export RT 확장). 설계 논의는 별도 세션에서 진행 예정. 근거: trim의 데이터-품질 이득이 실증되지 않고, raw 직접 분석이 도구 설계 철학에 부합하며, 방법 1은 불필요한 변환 비용을 강제.
- **기존 데이터 → 1회 trim 필수**(이미 MS1-only가 박힘). msconvert `scanTime` 필터로 수행. AIDIA 패키지 밖 별도 영역에서 1회성 작업으로 처리(ADR 0004와 일관).
- trim은 "가치 있는 표준 기능"이 아니라 **기존 파일용 1회성 교정**으로 격하.

**참고**:
- 코드: `R/rt_binning.R`(RT clip), `R/export_methods.R`(`RT Time`/`Window` 컬럼 = trim 경계 출처)
- 문서: `docs/domain-knowledge.md` 746–757(dead-zone 근거), `docs/adr/0004-result-driven-input-no-raw-file.md`
- 문헌: DIA-NN Discussion #1035(FDR 동인), Issue #1026(mass calibration은 충분한 confident ID 필요), Nature Methods 2019(interference correction)
- 다음 작업: 기존 데이터 trim(별도 세션, 컨텍스트 문서 `docs/handoff/2026-06-12-void-trim-existing-data-context.md`) → 이후 방법 2 설계 재개

---
