---
name: check-ownership
description: 변경된 파일의 소유자를 판별하여 소유권 경계 위반 여부를 보고. 에이전트 팀 작업 전후로 사용.
allowed-tools: Read, Grep, Glob, Bash(git *)
---

# /check-ownership — 파일 소유권 경계 검증

각 서브 레포의 변경 파일을 감지하고, 각 파일이 어느 에이전트 소유인지를 판별합니다.

## 소유권 판별 규칙

파일 경로를 기반으로 소유자를 결정합니다. **위에서부터 순서대로 매칭하고, 먼저 매칭된 규칙을 적용합니다.**

1. 파일명이 `Dockerfile*`, `Jenkinsfile`, `docker-compose*`, `nginx*.conf` → **devops**
2. `dinai-client/` 하위 → **frontend**
3. `dinai-core-api/` 또는 `dinai-db/` 하위 → **core-api**
4. `dinai-ai-api/` 하위 → **ai-api**
5. 루트 파일 (`docker-compose.yml`, `nginx-pilot.conf` 등) → **devops**
6. 위 어디에도 해당하지 않는 파일 → **unassigned** (수동 확인 필요)

## 실행 로직

1. 4개 서브 레포(`dinai-client/`, `dinai-core-api/`, `dinai-ai-api/`, `dinai-db/`)에 각각 진입하여 `git diff --name-only HEAD` 실행
2. 변경된 파일 목록 수집
3. 각 파일에 위 판별 규칙을 적용하여 소유자 결정
4. `$ARGUMENTS`에 에이전트 이름이 있으면 해당 소유자 파일만 필터링

## 결과 보고

```
| 파일 | 소유자 |
|------|-------|
| dinai-client/src/App.tsx | frontend |
| dinai-core-api/src/.../UserService.java | core-api |
| dinai-ai-api/Dockerfile | devops |
```

### 위반 판단 기준

이 스킬은 **소유자를 판별**할 뿐, "누가 변경했는지"는 git에서 알 수 없습니다.
따라서 에이전트 팀 작업 시 다음과 같이 활용합니다:

- 팀 작업 **전**: 변경 예정 파일 목록을 입력받아 소유자를 확인 → 작업 배분 참고
- 팀 작업 **후**: 각 에이전트가 변경한 파일 목록과 소유자를 대조 → 경계 위반 수동 확인

변경 파일이 없으면 "변경 사항 없음"을 출력합니다.
