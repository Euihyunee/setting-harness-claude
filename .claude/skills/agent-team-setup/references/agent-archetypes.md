# 에이전트 아키타입 참고

프로젝트 유형별 추천 팀 구성과 역할 정의 가이드입니다.

---

## 팀 구성 결정 원칙

1. **3~5명이 최적** — 그 이상은 조율 오버헤드가 급격히 증가
2. **파일 소유권이 겹치지 않아야 함** — 같은 파일을 두 에이전트가 수정하면 충돌
3. **감사/리뷰 역할은 읽기 전용** — `tools: Read, Bash`만 부여
4. **독립 실행 가능한 단위로 분리** — 서로 결과를 기다려야 하면 병렬 가치 없음

---

## 프로젝트 유형별 추천 팀

### 웹 풀스택 (Next.js/React + 백엔드)

```
팀 구성: 3명
├── frontend   — 컴포넌트, 페이지, 스타일
├── backend    — API, DB, 비즈니스 로직
└── security   — 인증/보안 감사 (읽기 전용)
```

**파일 경계 기준:**
| 에이전트 | 담당 경로 | tools |
|---------|---------|-------|
| frontend | `src/components/`, `src/pages/`, `src/app/`, `src/styles/` | Read, Write, Edit, Bash |
| backend | `src/api/`, `server/`, `src/models/`, `src/services/`, `prisma/` | Read, Write, Edit, Bash |
| security | 전체 코드베이스 | Read, Bash |

---

### 백엔드 API 전용 (FastAPI/Django/Spring/Express)

```
팀 구성: 3명
├── api        — 라우터, 컨트롤러, 미들웨어
├── domain     — 서비스, 모델, 비즈니스 로직
└── infra      — DB 마이그레이션, 외부 연동, 설정
```

**파일 경계 기준:**
| 에이전트 | 담당 경로 | tools |
|---------|---------|-------|
| api | `app/routers/`, `app/controllers/`, `app/middleware/` | Read, Write, Edit, Bash |
| domain | `app/services/`, `app/models/`, `app/schemas/` | Read, Write, Edit, Bash |
| infra | `app/db/`, `alembic/`, `migrations/`, `app/external/` | Read, Write, Edit, Bash |

---

### 프론트엔드 전용 (React/Vue/Angular)

```
팀 구성: 3명
├── components — 공통 UI 컴포넌트 라이브러리
├── features   — 기능별 페이지/뷰
└── qa         — 테스트, 접근성, 성능 감사
```

**파일 경계 기준:**
| 에이전트 | 담당 경로 | tools |
|---------|---------|-------|
| components | `src/components/`, `src/ui/`, `src/design-system/` | Read, Write, Edit, Bash |
| features | `src/features/`, `src/pages/`, `src/views/` | Read, Write, Edit, Bash |
| qa | 전체 코드베이스 | Read, Bash |

---

### 데이터/ML 파이프라인

```
팀 구성: 3~4명
├── data-eng   — 데이터 수집, ETL, 전처리
├── modeling   — 모델 학습, 평가, 실험
├── serving    — 추론 API, 배포, 모니터링
└── analyst    — 결과 분석, 리포트 (읽기 전용)
```

**파일 경계 기준:**
| 에이전트 | 담당 경로 | tools |
|---------|---------|-------|
| data-eng | `data/`, `pipelines/`, `etl/` | Read, Write, Edit, Bash |
| modeling | `models/`, `training/`, `experiments/` | Read, Write, Edit, Bash |
| serving | `api/`, `inference/`, `deployment/` | Read, Write, Edit, Bash |
| analyst | 전체 코드베이스 | Read, Bash |

---

### 모바일 앱 (Flutter/React Native)

```
팀 구성: 3명
├── ui         — 화면, 위젯, 스타일
├── state      — 상태관리, 비즈니스 로직
└── platform   — 네이티브 연동, 권한, 빌드 설정
```

---

### 대규모 리팩터링 전용 팀

```
팀 구성: 3명
├── architect  — 설계 검토, 변경 방향 결정 (읽기 전용)
├── refactor   — 코드 변경 실행
└── verifier   — 테스트 작성, 회귀 방지 (읽기 전용)
```

**특징:** architect와 verifier는 `Read, Bash`만 허용. refactor만 쓰기 권한.

---

### 디버깅 전용 팀 (병렬 가설 검증)

```
팀 구성: 3~5명 (버그 복잡도에 따라)
├── hypothesis-N  — 각자 다른 원인 가설 검증
└── (각 팀원이 서로의 이론을 반증하는 구조)
```

**특징:** 모든 팀원이 동일한 권한. 팀 리드가 토론 후 살아남은 가설로 수정 진행.

---

## 에이전트 역할 추가 패턴

프로젝트에 필요한 경우 아래 특수 역할도 추가:

| 역할 이름 | 용도 | tools |
|---------|------|-------|
| `doc-writer` | API 명세, README, 주석 작성 | Read, Write, Edit |
| `test-writer` | 테스트 코드 작성 전담 | Read, Write, Edit, Bash |
| `perf-analyst` | 성능 프로파일링, 병목 분석 | Read, Bash |
| `db-admin` | 마이그레이션, 스키마 최적화 | Read, Write, Edit, Bash |
| `devops` | CI/CD, Docker, Kubernetes 설정 | Read, Write, Edit, Bash |

---

## tools 부여 기준

```
구현 에이전트:  tools: Read, Write, Edit, Bash
감사/분석 에이전트: tools: Read, Bash
문서 전담:     tools: Read, Write, Edit
```

Write 없이 Bash만 있으면 스크립트 실행은 가능하나 파일 직접 수정 불가.
Bash 없이 Read/Write만 있으면 파일 편집은 되나 테스트 실행 불가.
