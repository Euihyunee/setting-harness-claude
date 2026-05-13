# DINAI AI Platform

AI 기반 엔터프라이즈 플랫폼 — 4개 독립 레포로 구성된 멀티 프로젝트.

## 기술 스택

| 프로젝트 | 스택 |
|---------|------|
| **dinai-ai-api** | Python 3.12 + FastAPI + LangChain 1.x + Pydantic v2 |
| **dinai-client** | React 19.1 + TypeScript + Vite + TanStack Query v5 |
| **dinai-core-api** | Java 21 + Spring Boot 3.4 + MyBatis + Gradle |
| **dinai-db** | PostgreSQL DDL + 마이그레이션 SQL |

세부 코딩 규칙은 각 서브레포의 CLAUDE.md 참조: [dinai-ai-api](dinai-ai-api/CLAUDE.md) · [dinai-client](dinai-client/CLAUDE.md) · [dinai-core-api](dinai-core-api/CLAUDE.md) · [dinai-db](dinai-db/CLAUDE.md)

인프라: PostgreSQL, Aurora PostgreSQL, OpenSearch(벡터 검색), Amazon Bedrock, Jenkins, Docker, Nginx

## 에이전트 파일 소유권 — 다른 에이전트 담당 파일은 읽기만 가능

| 에이전트 | 담당 경로 |
|---------|---------|
| `frontend` | `dinai-client/` |
| `core-api` | `dinai-core-api/`, `dinai-db/` |
| `ai-api` | `dinai-ai-api/` |
| `devops` | `Dockerfile*`, `Jenkinsfile`, `docker-compose*`, `nginx*` |
| `security` | 전체 (읽기 전용) |

## 공통 규칙

- 해당 프로젝트는 신규 구축 프로젝트이며 새롭게 변경할 로직이 베스트 프렉티스로 판단된다면 하위호환을 위한 기존로직 Fallback, 데이터 마이그레이션, re-export, deprecated 지원을 신경쓰지 않아야함 
- `.env` 파일 수정 절대 금지 — `.env.template` 또는 `.env.example`에만 키 추가
- 커밋 메시지 접두사: `feat:` / `fix:` / `chore:` / `refactor:`
- 커밋 메시지 본문: **왜** 이 수정을 했는지 간략히 + **어떻게** 했는지 기술
- 커밋 메시지 본문 말투: "~이다 / ~한다 / ~했다 / ~된다" 평서형 종결 어미 금지. 명사형(`~ 추가`, `~ 정리`) 또는 음슴체(`~함`, `~음`)로 작성
- 커밋 대상: 코드 변경만 포함 — 문서(*.md, docs/) 파일은 커밋에서 제외
- 커밋 메시지에 `phase`, `step`, `claude`, `cowork`, `agent` 등 AI 도구 관련 용어 절대 금지 — 사람이 작성한 것처럼 자연스럽게 작성
- 시크릿/크리덴셜 하드코딩 금지, OWASP Top 10 방어 필수
- 운영 마이그레이션/폴백 코드 금지 — 미오픈 시스템이므로 새 로직만 작성
- `레거시 호환`, `deprecated`, `하위 호환` 주석 금지
- Git Worktree: 반드시 프로젝트 루트의 `worktrees/` 폴더 아래에 생성 (`git worktree add -b <branch> ./worktrees/<name> develop`). 다른 위치 생성 금지. `make wt` / `make wt-off` 로 Docker 테스트 전환.
- 환경변수 변경 시 동기화 확인: `POSTGRES_*`, AWS 크리덴셜, `BUCKET_NAME`, 암호화 키(`ENC_PASSPHRASE`/`ENCRYPTION_KEY`)는 프로젝트 간 공유 변수 — 한쪽 변경 시 다른 프로젝트도 함께 수정 필요 (관련 파일: `dinai-ai-api/.env*`, `dinai-ai-api/settings/**`, `dinai-core-api/src/main/resources/application*`, `docker-compose*`)
- Docker: 베이스 이미지 버전 피닝, 비루트 유저, HEALTHCHECK, 멀티스테이지 빌드
- Nginx: TLS 1.2+, 보안 헤더 6종 필수, Rate Limiting
- Jenkins: 선언형 파이프라인, 스테이지별 타임아웃, 크리덴셜 스토어 사용

## 검증 명령어

```bash
cd dinai-client && npm run check-all          # type-check + lint
cd dinai-client && npm run test               # Vitest
cd dinai-ai-api && pytest tests/ -v --tb=short
cd dinai-core-api && ./gradlew build
```

## 에이전트 간 소통

1. **API 계약 변경** → `frontend`에 즉시 메시지
2. **DB 스키마 변경** → `core-api` ↔ `ai-api` 상호 알림
3. **보안 이슈** → `security` → 담당 팀원 즉시 알림
4. **인프라 변경** → `devops` → 전체 브로드캐스트
5. **공유 엔드포인트 추가/변경** → 팀 리드 승인

## 팀 구성

```
팀 리드 (조율 전담)
├── frontend   — React UI
├── core-api   — Spring Boot API + DB
├── ai-api     — FastAPI AI 서비스
├── devops     — 배포/인프라
└── security   — 보안 감사
```
