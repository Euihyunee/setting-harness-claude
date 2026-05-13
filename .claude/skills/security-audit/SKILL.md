---
name: security-audit
description: 전체 코드베이스 보안 감사. OWASP Top 10 기반 취약점 스캔. 코드 변경 후 보안 검토가 필요할 때 사용.
allowed-tools: Read, Grep, Glob, Bash(npm audit *)
---

# /security-audit — 보안 감사

전체 코드베이스를 읽기 전용으로 스캔하여 보안 취약점을 탐지합니다.
`$ARGUMENTS`가 있으면 해당 경로/주제만 집중 감사합니다.

## 감사 항목

### 1. 시크릿 하드코딩 탐지

Grep으로 전 프로젝트에서 다음 패턴 검색:
- `password\s*=\s*["']`, `secret\s*=\s*["']`, `api_key\s*=\s*["']`, `token\s*=\s*["']`
- `.env` 파일이 각 프로젝트 `.gitignore`에 포함되어 있는지 확인
- Dockerfile에 `.env` COPY 여부

### 2. SQL 인젝션 (dinai-core-api)

- MyBatis mapper XML(`src/main/resources/mybatis/mapper/*.xml`)에서 `${` 패턴 검색
- Java 소스에서 문자열 연결로 SQL 조합하는 패턴 검색

### 3. XSS (dinai-client)

- `dangerouslySetInnerHTML` 사용 검색
- URL 파라미터의 DOM 반영 패턴

### 4. 인증/인가 (dinai-core-api)

- 컨트롤러(`interfaces/controller/`)의 엔드포인트가 `SecurityConstants.PUBLIC_URLS` 또는 `ADMIN_URLS`에 적절히 등록되어 있는지 교차 확인
- `@RequireAdminRole` 누락 가능성 검토

### 5. AI/LLM 보안 (dinai-ai-api)

- 프롬프트 인젝션: `ChatPromptTemplate`에서 시스템/사용자 메시지 분리 확인
- `guardrails/` 하위 모듈에서 비활성화 코드(`disabled`, `skip`, `bypass`) 검색
- LLM 응답 필터링 누락 검색

### 6. 의존성 (dinai-client만)

```bash
cd dinai-client && npm audit
```

dinai-ai-api는 `pip-audit`/`safety`가 미설치 상태이므로 건너뜁니다. 설치 후 재실행하면 포함됩니다.

## 보고 형식

```markdown
## 보안 감사 결과

**감사 일시**: (현재 날짜)
**감사 범위**: (전체 또는 $ARGUMENTS 대상)

### 요약
- Critical: N건 / High: N건 / Medium: N건 / Low: N건

### 발견 항목
- **[심각도]** 설명
  - 파일: 경로:줄번호
  - 문제: 구체적 설명
  - 수정 방향: 권장 조치
```

코드를 수정하지 않습니다. 결과만 보고합니다.
