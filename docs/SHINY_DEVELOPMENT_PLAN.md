# DIA Window Optimizer - Shiny Web App 개발 계획서

## 📋 개요

| 항목 | 내용 |
|------|------|
| **프로젝트** | DIA Window Optimizer Shiny App |
| **버전** | MVP (0.1.0) → Full (1.0.0) |
| **예상 기간** | MVP 2주, Full 5-6주 |
| **기술 스택** | R, Shiny, shinydashboard, shinybusy, DT |

---

## 🤖 개발 SubAgent 정의

### Agent 1: `shiny-ui-builder`
**역할**: UI 컴포넌트 설계 및 구현

```yaml
persona: frontend
skills:
  - Shiny UI 컴포넌트 작성 (dashboardPage, box, fluidRow)
  - CSS 스타일링 (tags$style, custom.css)
  - 반응형 레이아웃 설계
  - 사용자 경험 최적화
tools:
  - Write, Edit (UI 코드)
  - Read (기존 UI 패턴 분석)
triggers:
  - "UI 개선", "레이아웃 변경", "컴포넌트 추가"
```

**주요 태스크**:
1. Dashboard 레이아웃 설계
2. Input 컴포넌트 (fileInput, selectInput, sliderInput)
3. Output 컴포넌트 (infoBox, tableOutput, plotOutput)
4. 조건부 표시 (conditionalPanel)
5. CSS 커스터마이징

---

### Agent 2: `shiny-server-logic`
**역할**: Server-side 로직 및 파이프라인 통합

```yaml
persona: backend
skills:
  - Reactive programming (reactive, observe, observeEvent)
  - 기존 R 파이프라인 통합
  - 에러 핸들링 (tryCatch, validate)
  - 비동기 처리 (future, promises)
tools:
  - Write, Edit (server.R)
  - Read (기존 stage 함수들)
  - Bash (R 패키지 설치)
triggers:
  - "서버 로직", "파이프라인 연결", "reactive"
```

**주요 태스크**:
1. Reactive values 설계
2. Stage 1-4 함수 연결
3. 진행 상태 관리
4. 에러 핸들링 및 사용자 피드백
5. 파일 업로드/다운로드 핸들러

---

### Agent 3: `shiny-visualization`
**역할**: 플롯 렌더링 및 인터랙티브 시각화

```yaml
persona: frontend + analyzer
skills:
  - renderPlot, plotOutput 구현
  - ggplot2 → Shiny 통합
  - plotly 인터랙티브 변환
  - PDF 리포트 생성
tools:
  - Read (기존 plot 함수들)
  - Edit (플롯 코드 수정)
  - Write (새 시각화 모듈)
triggers:
  - "플롯", "시각화", "차트", "그래프"
```

**주요 태스크**:
1. 기존 24개 플롯 Shiny 통합
2. 인터랙티브 플롯 (plotly 변환)
3. 플롯 다운로드 기능
4. PDF 리포트 생성

---

### Agent 4: `shiny-testing`
**역할**: Shiny 앱 테스트 및 검증

```yaml
persona: qa
skills:
  - shinytest2 자동화 테스트
  - 수동 기능 테스트
  - 성능 프로파일링
  - 사용자 시나리오 테스트
tools:
  - Bash (테스트 실행)
  - Write (테스트 스크립트)
  - Read (테스트 결과 분석)
triggers:
  - "테스트", "검증", "QA", "버그"
```

**주요 태스크**:
1. UI 렌더링 테스트
2. 파이프라인 통합 테스트
3. 에러 시나리오 테스트
4. 성능 벤치마크

---

### Agent 5: `shiny-deployment`
**역할**: 배포 및 인프라 관리

```yaml
persona: devops
skills:
  - shinyapps.io 배포
  - Docker 컨테이너화
  - 환경 설정 관리
  - 모니터링 설정
tools:
  - Bash (rsconnect, docker)
  - Write (Dockerfile, manifest)
  - Read (배포 로그)
triggers:
  - "배포", "deploy", "shinyapps", "docker"
```

**주요 태스크**:
1. rsconnect 설정
2. shinyapps.io 배포
3. Docker 이미지 생성 (옵션)
4. 환경 변수 관리

---

## 📝 Skill 정의 (슬래시 명령어)

### `/shiny-init`
**목적**: Shiny 프로젝트 초기화

```yaml
description: "Shiny 앱 프로젝트 구조 생성"
actions:
  - 디렉토리 구조 생성 (shiny_app/, www/, R/)
  - 필수 패키지 확인 및 설치
  - app.R 스켈레톤 생성
  - .Rprofile 설정
output:
  - 실행 가능한 기본 Shiny 앱
```

### `/shiny-component [type]`
**목적**: UI 컴포넌트 추가

```yaml
description: "새로운 UI 컴포넌트 생성"
arguments:
  type: input | output | layout | download
examples:
  - /shiny-component input    # 새 입력 위젯
  - /shiny-component output   # 새 출력 위젯
  - /shiny-component download # 다운로드 핸들러
```

### `/shiny-integrate [stage]`
**목적**: 기존 파이프라인 단계 통합

```yaml
description: "기존 R 코드를 Shiny 서버 로직에 통합"
arguments:
  stage: 1 | 2 | 3 | 4 | all
examples:
  - /shiny-integrate 1    # Stage 1 (Validation) 통합
  - /shiny-integrate all  # 전체 파이프라인 통합
```

### `/shiny-test [scope]`
**목적**: Shiny 앱 테스트 실행

```yaml
description: "Shiny 앱 테스트"
arguments:
  scope: ui | server | e2e | performance
examples:
  - /shiny-test ui          # UI 렌더링 테스트
  - /shiny-test server      # 서버 로직 테스트
  - /shiny-test e2e         # 전체 워크플로우 테스트
```

### `/shiny-deploy [target]`
**목적**: 앱 배포

```yaml
description: "Shiny 앱 배포"
arguments:
  target: local | shinyapps | docker
examples:
  - /shiny-deploy local       # 로컬 실행
  - /shiny-deploy shinyapps   # shinyapps.io 배포
  - /shiny-deploy docker      # Docker 이미지 빌드
```

### `/shiny-style [theme]`
**목적**: UI 스타일링

```yaml
description: "앱 테마 및 스타일 적용"
arguments:
  theme: default | dark | custom
examples:
  - /shiny-style dark     # 다크 모드 적용
  - /shiny-style custom   # 커스텀 CSS 작성
```

---

## 🗓️ MVP 개발 로드맵

### Week 1: 기초 구축

| Day | 태스크 | Agent | Skill |
|-----|--------|-------|-------|
| 1 | 프로젝트 구조 확립 | - | `/shiny-init` |
| 2 | 파일 업로드 구현 | `shiny-ui-builder` | `/shiny-component input` |
| 3 | Stage 1 통합 | `shiny-server-logic` | `/shiny-integrate 1` |
| 4 | Stage 2 통합 | `shiny-server-logic` | `/shiny-integrate 2` |
| 5 | Stage 3 통합 (단일 전략) | `shiny-server-logic` | `/shiny-integrate 3` |

### Week 2: 완성 및 테스트

| Day | 태스크 | Agent | Skill |
|-----|--------|-------|-------|
| 6 | CSV 다운로드 구현 | `shiny-ui-builder` | `/shiny-component download` |
| 7 | Progress 표시 추가 | `shiny-ui-builder` | - |
| 8 | 에러 핸들링 강화 | `shiny-server-logic` | - |
| 9 | 통합 테스트 | `shiny-testing` | `/shiny-test e2e` |
| 10 | 로컬 배포 테스트 | `shiny-deployment` | `/shiny-deploy local` |

---

## 📁 프로젝트 구조

```
dia_window_optimizer/
├── shiny_app/                    # 📱 Shiny 앱 디렉토리
│   ├── app.R                     # 메인 앱 파일 (MVP)
│   ├── ui.R                      # UI 정의 (분리 시)
│   ├── server.R                  # Server 로직 (분리 시)
│   ├── global.R                  # 전역 설정 (분리 시)
│   ├── www/                      # 정적 파일
│   │   ├── custom.css            # 커스텀 스타일
│   │   ├── logo.png              # 브랜딩
│   │   └── help.html             # 도움말
│   ├── R/                        # 모듈화된 함수들
│   │   ├── mod_upload.R          # 업로드 모듈
│   │   ├── mod_settings.R        # 설정 모듈
│   │   └── mod_results.R         # 결과 모듈
│   └── tests/                    # Shiny 테스트
│       └── testthat/
│           └── test-app.R
├── R/                            # 📊 기존 파이프라인 (재사용)
│   ├── stage1_data_validation.R
│   ├── stage2_optimization_planning.R
│   ├── stage3_window_optimization.R
│   └── stage4_visualization.R
└── config/                       # ⚙️ 설정 (공유)
    └── instruments.json
```

---

## 🔧 필수 R 패키지

### MVP 필수 패키지
```r
# Install MVP dependencies
install.packages(c(
  "shiny",           # Core Shiny framework
  "shinydashboard",  # Dashboard layout
  "shinybusy",       # Progress indicators
  "DT",              # Interactive tables
  "arrow"            # Parquet support (기존 사용)
))
```

### Phase 2 추가 패키지
```r
# Install Phase 2 dependencies
install.packages(c(
  "plotly",          # Interactive plots
  "shinyWidgets",    # Enhanced widgets
  "shinycssloaders", # Loading spinners
  "shinyjs",         # JavaScript integration
  "bslib",           # Bootstrap themes
  "waiter"           # Splash screens
))
```

### 테스트 패키지
```r
# Install testing dependencies
install.packages(c(
  "shinytest2",      # Shiny app testing
  "testthat"         # Unit testing
))
```

---

## ✅ 체크리스트

### MVP 완료 조건
- [ ] 파일 업로드 작동
- [ ] Instrument 선택 작동
- [ ] DPPP 슬라이더 작동
- [ ] Stage 1-3 파이프라인 실행
- [ ] 결과 요약 표시
- [ ] CSV 다운로드 작동
- [ ] 에러 메시지 표시
- [ ] 로컬 실행 성공

### Phase 2 완료 조건
- [ ] 4개 전략 선택
- [ ] 고급 파라미터 노출
- [ ] 24개 플롯 미리보기
- [ ] PDF 다운로드
- [ ] 프리셋 저장/로드
- [ ] shinyapps.io 배포

---

## 📚 학습 리소스

### 필수
1. **[Mastering Shiny](https://mastering-shiny.org/)** - Hadley Wickham 공식 책 (무료)
2. **[Shiny Cheat Sheet](https://shiny.rstudio.com/images/shiny-cheatsheet.pdf)** - 빠른 참조

### 권장
3. **[shinydashboard](https://rstudio.github.io/shinydashboard/)** - 대시보드 레이아웃
4. **[Engineering Production-Grade Shiny Apps](https://engineering-shiny.org/)** - 프로덕션 가이드

### 참고
5. **[Shiny Gallery](https://shiny.rstudio.com/gallery/)** - 예제 앱 모음
6. **[Outstanding User Interfaces with Shiny](https://unleash-shiny.rinterface.com/)** - 고급 UI

---

## 🚀 시작 명령어

```r
# 1. 패키지 설치
install.packages(c("shiny", "shinydashboard", "shinybusy", "DT"))

# 2. 앱 실행 (프로젝트 루트에서)
shiny::runApp("shiny_app")

# 3. 브라우저에서 열기
# → http://127.0.0.1:xxxx
```

---

**문서 버전**: 1.0
**최종 수정**: 2025-01-14
**상태**: MVP 개발 준비 완료
