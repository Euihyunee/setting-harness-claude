---
name: test-all
description: 전 프로젝트 검증 실행 (type-check, lint, test, build). 코드 변경 후 전체 상태를 한번에 확인할 때 사용.
allowed-tools: Bash(npm *), Bash(npx *), Bash(pytest *), Bash(python -m pytest *), Bash(./gradlew *), Bash(ls *), Read
---

# /test-all — 전 프로젝트 검증

4개 프로젝트를 순서대로 검증하고 결과를 요약 테이블로 보고합니다.

## 사전 조건 확인

각 프로젝트 검증 전에 필수 의존성 존재 여부를 확인합니다:
- `dinai-client`: `node_modules/` 존재 확인. 없으면 해당 프로젝트를 **SKIP** 처리하고 "`npm install` 필요"를 결과에 표시
- `dinai-core-api`: `gradlew` 파일 존재 확인
- `dinai-ai-api`: `tests/` 디렉터리 존재 확인

## 실행 순서

### 1. dinai-client (프론트엔드)

```bash
cd dinai-client && npm run type-check
cd dinai-client && npm run lint
cd dinai-client && npx vitest --run
```

### 2. dinai-core-api (Core API)

```bash
cd dinai-core-api && ./gradlew classes
```

기본은 `classes`(컴파일 검증)만 실행합니다. DB 연결이 필요한 테스트는 포함하지 않습니다.
`$ARGUMENTS`에 `--full`을 전달하면 `./gradlew build`까지 실행합니다.

### 3. dinai-ai-api (AI API)

```bash
cd dinai-ai-api && python -m pytest tests/ -x --tb=short -q
```

pytest도 Bedrock/DB 등 외부 연결이 필요한 테스트가 있을 수 있습니다.
외부 의존성 오류로 실패한 테스트는 결과에 "외부 연결 필요"로 별도 표기합니다.

### 4. dinai-db (DB)

SQL 파일은 실행 검증이 불가하므로 구조만 확인합니다:
- `migrations/` 파일명 순번 규칙 준수 여부
- `init/01_schema.sql`과 `migrations/`의 테이블 정의 동기화 상태

## 결과 보고

```
| 프로젝트 | type-check | lint | test/build | 상태 |
|---------|-----------|------|-----------|------|
| dinai-client | PASS/FAIL/SKIP | PASS/FAIL/SKIP | PASS/FAIL/SKIP | ✓/✗/— |
| dinai-core-api | — | — | PASS/FAIL | ✓/✗ |
| dinai-ai-api | — | — | PASS/FAIL | ✓/✗ |
| dinai-db | — | — | SYNC/SKIP | ✓/— |
```

- **SKIP**: 의존성 미설치로 실행 불가 (안내 메시지 포함)
- 실패 항목: 에러 메시지 핵심 부분 출력
- 외부 연결 실패: 테스트 자체 오류와 구분하여 표기
