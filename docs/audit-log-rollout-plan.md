# 감사 로그 도메인 롤아웃 계획 (진행도 체크용)

> [!info] 이 문서의 용도
> `dinai-core-api` 의 나머지 컨트롤러에 `@AuditLog` 를 부착하는 작업을 단계별로 추적하는 라이브 체크리스트.
> 메서드 한 건 적용 완료 시 해당 줄의 `[ ]` 를 `[x]` 로 바꿈. 단계 전체 완료 시 단계 헤딩 옆 ✅ 표시.
> 모듈 동작 원리는 [audit-log-aop.md](audit-log-aop.md) 참조.

---

## 1. 진행 현황 대시보드

| 단계                                          | 진행도   | 상태  |
| ------------------------------------------- | :---: | :-: |
| 0단계 — 사전 결정 (A~E)                           | 5 / 5 | ✅   |
| 1단계 — 인증/계정                                 | 5 / 5 | ✅   |
| 2단계 — 사용자/권한 관리                             | 5 / 5 | ✅   |
| 3단계 — 지식/에이전트 관리                            | 14 / 14 (+1 신규: KB 부서 설명 단독 endpoint) | ✅  |
| 4단계 — 사용량/프롬프트                              | 9 / 9 (전부 활성) | ✅   |
| 5단계 — 사용자 작업 도메인 (Project/Chat/Agent/MyPrompt) | 0 / 18 | ⏳ |
| 6단계 — Clipping 운영                            | — | ❌ 배제 |
| D 보류 풀 — 단순 조회 (화면 보고 단계별 결정)               | 10 / 11 (#7 배제 1건 제외 전부 활성) | ✅   |
| 7단계 — 검증 + 라벨 동기화                           | 0 / 5 | ⏳   |
| **합계 (활성 + 신규 endpoint)**                                 | **44 / 65** | |

> [!success] 상태 아이콘
> ⏳ 대기 · 🔧 진행 중 · ✅ 완료 · ⚠️ 보류 (결정 대기) · ⏸ 의도적 유보 · ❌ 배제

---

## 2. 0단계 — 사전 결정 사항

| 코드 | 항목                                            | 결정                                                       | 근거                                    | 체크 |
| -- | --------------------------------------------- | -------------------------------------------------------- | ------------------------------------- | --- |
| A  | Prompt 영역 리소스                                 | **(2) PROMPT_TEMPLATE enum 신규** — 016 마이그레이션 + ResourceType.java 갱신. PromptTemplate / PromptTag 단일 enum 통일 (별도 PROMPT_TAG 미도입) | SETTING 재활용 시 의미 모호 + Prompt 도메인 가시 분리 필요 | [x] |
| B  | Clipping 운영 액션                                | **배제** — 본 롤아웃 범위 외, 별도 일정으로 전환                          | 사용자 본인 개발 영역 아님                       | [x] |
| C  | 로그인/로그아웃/refresh 적재                           | **(1) 안 적재**                                             | `access_logs` 에 이미 적재됨                | [x] |
| D  | 단순 GET 조회 적재 범위                               | **단계별 화면 보고 결정** — 후보 항목은 "D 보류 풀" 로 모아 두고 화면 검토 시 활성/배제 | 일괄 정책보다 화면 단위 판단이 더 정확                | [x] |
| E  | MyPrompt 적재 여부                                | **(1) 적재** — 5단계에 포함 (단, 리소스 enum 은 A 결정에 묶임)            | 개인 영역도 변경 이력 추적 필요                    | [x] |

---

## 3. 1단계 — 인증/계정 ⭐ 가치 최상

> [!info] 매트릭스 보조 라벨 필수
> `UPDATE + ACCOUNT` 가 무엇인지(비번 변경/잠금 해제/초기화) 자동 라벨로는 구분 불가 → `description` 명시 필수.
>
> ❌ login/logout/refresh 는 C 결정에 따라 본 롤아웃에서 제외 (`access_logs` 가 담당).

| # | 위치 (file)                                                                      | 메서드                       | 어노테이션                                                           | 체크 |
|--|--------------------------------------------------------------------------------|---------------------------|----------------------------------------------------------------|----|
| 1 | `AuthController.java`                                                          | `changePassword`          | `@AuditLog(UPDATE, ACCOUNT, description="비밀번호 변경")` + `resourceId(resolved)` | [x] |
| 2 | `AuthController.java`                                                          | `resetPasswordRequest`    | `@AuditLog(UPDATE, ACCOUNT, description="비밀번호 초기화 요청")` + `resourceId(normalized)` | [x] |
| 3 | `SystemAdminController.java` (`/admin/system/users/{employeeId}/unlock`)      | `unlockUser`              | `@AuditLog(UPDATE, ACCOUNT, description="계정 잠금 해제")` + `detail("ticketNo","note")` | [x] |
| 4 | `SystemAdminController.java` (`/admin/system/users/{employeeId}/reset-initial-password`) | `resetInitialPassword` | `@AuditLog(UPDATE, ACCOUNT, description="초기 비밀번호 재설정")` + `detail("ticketNo","note")` | [x] |
| 5 | `SystemAdminController.java` (`/admin/system/users/{employeeId}/deactivate`)  | `deactivateUser`          | `@AuditLog(UPDATE, USER, description="비활성화")` + `detail("ticketNo","note")` | [x] |

### 3.1 단계 검증 — 화면 체크리스트

> [!info] 시나리오 단위 검증
> 각 항목 = (실행 화면) → 액션 → `/admin/logs/audit` 에서 노출 확인.
> 비교할 컬럼: `logType` / `resourceType` / `description` / `result` / `actor` / `resourceId` / `extra_data` / `error_message` 8개 핵심.

#### 사전 확인 (한 번만)

- [ ] `/admin/logs/audit` 페이지가 정상 노출 (적재 0건이어도 빈 표 + 필터 UI 정상)
- [ ] 적재 지연 — 액션 후 새로고침 시 1~2초 내 즉시 보임 (지연 시 logExecutor 큐 적체/예외 의심 → 서버 로그 `[AuditLog] 적재 실패` 검색)

#### 시나리오 1 — changePassword (성공)

- [ ] 일반 사용자 로그인 → 마이페이지/계정 설정 → 비밀번호 변경
- [ ] 현재 비밀번호 + 신규 비밀번호 정상 입력 → 200 응답 + "비밀번호가 변경되었습니다" 메시지
- [ ] `/admin/logs/audit` 적재 행:
  - `logType=UPDATE` / `resourceType=ACCOUNT` / `description="비밀번호 변경"`
  - `actor=본인 사번` / `resourceId=본인 사번` (대문자 정규화) / `category=USER`
  - `result=SUCCESS` / `error_message=NULL`
  - 상세 모달: `traceId` 채워짐, `userAgent` 채워짐, `ipAddress` 채워짐

#### 시나리오 2 — changePassword (실패)

- [ ] 동일 화면에서 **현재 비밀번호를 일부러 틀리게** 입력
- [ ] 422/4xx 응답 + 에러 메시지 노출
- [ ] `/admin/logs/audit` 적재 행:
  - `result=FAILURE` / `error_message=BUSINESS_RULE_VIOLATION` 또는 `VALIDATION_FAILED` (도메인 예외 종류 의존)
  - 나머지 필드는 시나리오 1과 동일

#### 시나리오 3 — resetPasswordRequest (이메일 등록 사용자)

- [ ] 로그아웃 상태 → 로그인 화면 → "임시 비밀번호 발급" → 등록 이메일 있는 사번 입력 → 발송
- [ ] 200 응답 + "임시 비밀번호 발송 완료" 안내 메시지
- [ ] `/admin/logs/audit` 적재 행:
  - `description="비밀번호 초기화 요청"` / `resourceType=ACCOUNT`
  - `actor=SYSTEM` (미인증 상태) / `category=USER` (URI 가 `/admin` prefix 아님)
  - `resourceId=요청 사번` (대문자)
  - `result=SUCCESS`

#### 시나리오 4 — resetPasswordRequest (이메일 미등록 사용자)

- [ ] 동일 화면에서 **등록 이메일 없는 사번**으로 발급 요청
- [ ] 200 응답 + "관리자 초기화 필요" 안내 메시지
- [ ] `/admin/logs/audit` 적재 행:
  - `result=SUCCESS` (정상 안내 흐름이라 SUCCESS 가 맞음)
  - 응답 메시지로만 분기 가능 — 시나리오 3 과 audit 상으로 구분 어려움. 구분 필요 시 추후 `AuditContext.detail("manualResetRequired", true)` 보강 후보

#### 시나리오 5 — unlockUser (관리자)

- [ ] 관리자 로그인 → 관리자 > 사용자 관리 > 잠금 계정 → 대상 사용자 "해제"
- [ ] ticketNo + note 입력 후 해제 → 200 응답
- [ ] `/admin/logs/audit` 적재 행:
  - `logType=UPDATE` / `resourceType=ACCOUNT` / `description="계정 잠금 해제"`
  - `actor=관리자 사번` / `resourceId=대상 사용자 사번` / `category=ADMIN`
  - 상세 모달 `extra_data` 에 `{"ticketNo":"..."}` 포함

#### 시나리오 6 — deactivateUser (관리자)

- [ ] 관리자 > 사용자 관리 > 활성 사용자 1명 "비활성화"
- [ ] ticketNo + note 입력 → 200 응답
- [ ] `/admin/logs/audit` 적재 행:
  - `logType=UPDATE` / `resourceType=USER` ← **USER (ACCOUNT 아님) 주의**
  - `description="비활성화"` / `category=ADMIN`
  - `extra_data.ticketNo` 포함

#### 시나리오 7 — resetInitialPassword (관리자)

- [ ] 관리자 > 사용자 관리 > 활성 사용자 1명 "초기 비밀번호 재설정"
- [ ] ticketNo + note 입력 → 200 응답 + "생년월일 8자리로 재설정" 안내
- [ ] `/admin/logs/audit` 적재 행:
  - `description="초기 비밀번호 재설정"` / `resourceType=ACCOUNT` / `category=ADMIN`
  - `extra_data.ticketNo` 포함

#### 프론트 라벨 동기화 (7단계 일괄 처리 가능 — 우선순위 낮음)

- [ ] `/admin/logs/audit` 표의 "활동" 컬럼에서 시나리오 1·5·6·7 이 같은 매트릭스(UPDATE+ACCOUNT 또는 UPDATE+USER) 라 라벨이 동일하게 노출되는지 확인
- [ ] 매트릭스만으로 구분 어려우면 `entities/admin-log/lib/labels.ts` 에서 `description` 우선 표시 또는 description 별 라벨 매핑 보강 필요
- [ ] 신규 description ("비밀번호 변경" / "비밀번호 초기화 요청" / "계정 잠금 해제" / "초기 비밀번호 재설정" / "비활성화") 5종 라벨 사전 정의 여부 확인

#### 빌드 검증

- [ ] `./gradlew compileJava` BUILD SUCCESSFUL ← 이미 통과
- [ ] (선택) `./gradlew build` 풀 빌드 — 사용자 환경에서 toolchain 21 자동 다운로드 후 실행

### 3.2 메모

```text
2026-05-04 1단계 코드 적용 완료 (5/5)
  · AuthController: changePassword + resetPasswordRequest
  · AdminController: unlockUser + deactivateUser + resetInitialPassword
  · 적재 보강: AuditContext.resourceId(...)/actor(...) (Auth) / AuditContext.detail("ticketNo","note", ...) (Admin)
  · UserApplicationService 의 service-side 레거시 recordAuditLog 5곳 제거 (1단계 영역)
    → completeTemporaryPasswordIssue / changePassword / unlockUser / deactivateUser / resetToInitialPassword
    · 이전엔 logType="PASSWORD_RESET","PASSWORD_CHANGE","ACCOUNT_UNLOCK","ACCOUNT_DEACTIVATE" 등 자유 문자열 적재 →
      013 마이그레이션 chk_audit_log_type CHECK 위반으로 INSERT 실패 상태였음. Aspect 일원화로 해결.
  · 정보 손실 없음 — previousLockedReason 은 unlockUser service 내부에서 AuditContext.detail() 박음

ErrorCode 쪼개기 (1단계 보강) — RULE_BUSINESS_VIOLATION 한 코드로 묶이던 비밀번호 도메인 실패를 의미별 분리:
  · VAL_PASSWORD_MISMATCH (현재 비밀번호 불일치)
  · VAL_PASSWORD_POLICY (복잡도/길이/패턴/PII)
  · VAL_PASSWORD_REUSED (현재 동일 / 최근 사용)
  · RULE_PASSWORD_CHANGE_DENIED (TEMP_PASSWORD 비대상 등 변경 자체 불가)
  · UserApplicationService 적용처 9곳 (validateNewPassword + validateComplexity + validateDisallowedTokens)
  · 임시 비밀번호 메일 발송 실패 → InfrastructureError(NET_UPSTREAM_FAILURE, ..., cause)
    (DomainException(RULE_BUSINESS_VIOLATION) 에서 변경 — SMTP 외부 의존성 장애 정합화)
  · dinai-client/entities/admin-log/lib/labels.ts 의 ERROR_CODE_LABEL 한글 라벨 4개 추가

운영 인프라 보강 (1단계 부수):
  · AuditContext.actor(employeeId, name) 신규 추가 — self-service 인증 미수립 흐름에서 actor 명시
  · UserApplicationService.ActorSnapshot record + resolveActorSnapshot(employeeId) 헬퍼 추가
    (사번 → username/dept_code/dept_name 일괄 조회)
  · AuditLogAspect.buildCommand 끝에 ActorSnapshot 자동 폴백 추가
    (사번이 채워졌고 username/dept_name 비어있거나 SYSTEM 이면 DB 조회로 보강)
    → 임시 비밀번호 발급 / 비밀번호 변경 실패 등 미인증 흐름의 사원명/부서명 누락 자동 해결
  · access_logs 보강 (logout/refresh/session-expire 모두 resolveActorSnapshot 패턴 통일,
    UserLoginFailureTxService.insertAuditLog 가 User 객체 받아 username/dept_name 적재)

보안 정책 변경 (default-deny 도입):
  · ServerSecurityConfig + LocalSecurityConfig 의 .anyRequest().permitAll() → .authenticated()
  · 매칭되지 않은 신규 엔드포인트는 인증 필수가 자동 적용 (게스트 노출은 PUBLIC_URLS 명시 등록만)
  · 영향: /notices 등 공지 조회가 인증 없으면 audit_logs 에 SYSTEM 박히던 케이스 → 401/403 차단
  · ASYNC dispatch 호환: JwtAuthenticationFilter.shouldNotFilterAsyncDispatch=false override
    (Mono 리턴 컨트롤러의 async 응답 처리 단계에서 anonymous 로 떨어져 403 나던 race fix)

→ 화면 검증 대기 (사용자 환경 PowerShell 에서 실행):
  · /admin/users/{id}/unlock 로 잠금 해제 1건 → /admin/logs/audit 노출 + sticketNo/note/previousLockedReason 확인
  · changePassword 잘못된 현재 비밀번호 → result=FAILURE, error_message=VAL_PASSWORD_MISMATCH 확인
  · 임시 비밀번호 발급 → audit row 의 username/dept_name 채워짐 (Aspect 폴백 동작 검증)
  · 프론트 ACTIVITY_MATRIX 라벨 추가 (UPDATE+ACCOUNT, UPDATE+USER 매트릭스에 description별 표시) — 7단계와 묶음
```

---

## 4. 2단계 — 사용자/권한 관리 ✅

> [!info] D 보류 항목 분리
> `AdminCommonController.searchUsersByName` 은 단순 검색 조회 → "D 보류 풀" 로 이동.

| # | 위치 (file)                                                                                  | 메서드                                 | 어노테이션                                                | 체크 |
|--|--------------------------------------------------------------------------------------------|------------------------------------|------------------------------------------------------|----|
| 1 | `SystemAdminController.java` (`/admin/system/users/{employeeId}/role`)                    | `changeUserRole`                   | `@AuditLog(UPDATE, USER, description="역할 변경")` + `detail("toRole", ...)` (service 측 `detail("fromRole", ...)`) | [x] |
| 2 | `SystemAdminController.java` (`/admin/system/users/{employeeId}/active`)                  | `updateUserActiveStatus`           | `@AuditLog(UPDATE, USER, description="활성 상태 변경")` + `detail("isActive", ...)` + `message("활성화"/"비활성화")` | [x] |
| 3 | `SystemAdminController.java` (`/admin/system/users/{employeeId}/admin`)                   | `updateAdminStatus`                | `@AuditLog(UPDATE, PERMISSION, description="관리자 권한")` + `detail("isAdmin", ...)` + `message("부여"/"해제")` | [x] |
| 4 | `SystemAdminController.java` (`/admin/system/system-admins/{employeeId}/active`)          | `updateSystemAdminRoleActiveStatus` | `@AuditLog(UPDATE, PERMISSION, description="시스템 관리자 권한")` + `resourceId` + `detail("isActive", ...)` + `message("부여"/"해제")` | [x] |
| 5 | `SystemAdminController.java` (`/admin/system/agents/{agentId}/owners`)                    | `updateAgentOwners`                | `@AuditLog(UPDATE, PERMISSION, description="에이전트 오너 수정")` + service `addedOwners`/`removedOwners` diff detail | [x] |

### 4.1 단계 검증

- [x] `docker compose build core-api` BUILD SUCCESSFUL + healthy 확인 (사용자 환경)
- [ ] 역할 변경 1건 → audit 적재 확인 (description="역할 변경", `extra_data.fromRole`/`toRole`)
- [ ] 활성 상태 변경 1건 → `extra_data.isActive` 확인
- [ ] 에이전트 오너 변경 1건 → `extra_data.context.type=AGENT`, `count` 확인
- [ ] 프론트 라벨 동기화 (UPDATE+USER, UPDATE+PERMISSION 매트릭스 — 7단계 묶음)

### 4.2 메모

```text
2026-05-04 2단계 코드 적용 완료 (5/5)
  · AdminController.changeUserRole 어노테이션 부착 + service-side 레거시 recordAuditLog 호출 제거
  · UserApplicationService.recordAuditLog 헬퍼 메서드 자체 삭제 (호출자 0)
    + safeIp / resolveAccessPathFromUserAgent / buildExtraData / escapeJson 헬퍼 + auditLogService /
      ClientInfoExtractor import 까지 동반 정리. UserLoginFailureTxService 만 잔존.
  · AuthorityController.updateUserActiveStatus / updateAdminStatus 부착 + AuditContext.resourceId(employeeId)
    명시 (PathVariable 아닌 RequestParam 흐름이라 자동 추출 X) + detail boolean 박음.
  · SystemAdminController.updateSystemAdminRoleActiveStatus 부착 + resourceId(targetEmployeeId).
  · SystemAdminController.updateAgentOwners 부착 + parentResource(AGENT, agentId) + detail("count", N).
    resourceId 는 PathVariable agentId 자동 추출.
  · 토글 케이스 (#2/#3/#4) 는 description 동적 보강 — AuditContext.message("활성화"/"비활성화", "부여"/"해제")
    로 부여/해제 방향성을 description 컬럼에 결합 (예: "관리자 권한 | 부여"). 화면 활동/비고 컬럼 자동 노출.
  · docker compose build core-api → healthy. 화면 검증 대기.
```

---

## 5. 3단계 — 지식/에이전트 관리

> [!info] D 보류 항목 분리
> `AdminAgentController.getAgentDocuments` (단순 목록 조회) 는 "D 보류 풀" #2 로 이동 후 "RAG 목록 조회" 로 활성.

| # | 위치 (file)                                                                       | 메서드                              | 어노테이션 + 컨텍스트                                                       | 체크 |
|--|---------------------------------------------------------------------------------|----------------------------------|-----------------------------------------------------------------|----|
| 1  | `AdminAgentController.java`                                                    | `updateAgentActiveStatus`        | `@AuditLog(UPDATE, AGENT, description="활성 상태")` + `detail("isActive", ...)` + `message("활성화"/"비활성화")` | [x] |
| 2  | `AdminAgentController.java`                                                    | `updateAgentDescription`         | `@AuditLog(UPDATE, AGENT, description="정보 수정")`                  | [x] |
| 3  | `AdminAgentController.java`                                                    | `updateAgentScopes`              | `@AuditLog(UPDATE, AGENT, description="범위 변경")`                  | [x] |
| 4  | `AdminAgentController.java`                                                    | `registerAgentDocument`          | `@AuditLog(UPLOAD, AGENT, description="RAG 업로드")` + controller `resourceName(file.originalFilename)` + `detail("docId", newDocId)` | [x] |
| 5  | `AdminAgentController.java`                                                    | `updateAgentDocument`            | `@AuditLog(UPDATE, AGENT, description="RAG 수정")` + service `resourceName(existing.fileName)` + `detail("docId", ...)` + `detail("newDocId", ...)` | [x] |
| 6  | `AdminAgentController.java`                                                    | `updateAgentDocumentMetadata`    | `@AuditLog(UPDATE, AGENT, description="RAG 메타데이터")` + service `resourceName(existing.fileName)` + `detail("docId", ...)` | [x] |
| 7  | `AdminAgentController.java`                                                    | `deleteAgentDocument`            | `@AuditLog(DELETE, AGENT, description="RAG 삭제")` + service `resourceName(existing.fileName)` + `detail("docId", ...)` | [x] |
| 8  | `AdminKBController.java`                                                       | `registerKnowledgeDocument`      | `@AuditLog(UPLOAD, KNOWLEDGE)` + `parentResource(DEPT, deptCode, deptName)` + `resourceName(file)` + `resourceId(newDocId)` | [x] |
| 9  | `AdminKBController.java`                                                       | `updateKnowledgeDocument`        | `@AuditLog(UPDATE, KNOWLEDGE)` + `parentResource(DEPT, deptCode, deptName)` + service `resourceName(existing.fileName)` | [x] |
| 10 | `AdminKBController.java`                                                       | `updateKnowledgeDocumentStatus`  | `@AuditLog(UPDATE, KNOWLEDGE, description="활성 상태")` + `detail("isActive", ...)` + `message("활성"/"비활성")` + service `resourceName(existing.fileName)` | [x] |
| 11 | `AdminKBController.java`                                                       | `updateKnowledgeMetadata`        | `@AuditLog(UPDATE, KNOWLEDGE, description="메타데이터")` + `parentResource(DEPT, deptCode, deptName)` + service `resourceName(existing.fileName)` | [x] |
| 12 | `AdminKBController.java`                                                       | `deleteKnowledgeDocument`        | `@AuditLog(DELETE, KNOWLEDGE)` + service `resourceName(existing.fileName)` | [x] |
| 13 | `SystemAdminController.java` (`POST /admin/system/kb-managements`)             | `createKnowledgeManagement`      | `@AuditLog(CREATE, KNOWLEDGE, description="지식부서 생성")` + `detail("deptName", request.getName())` | [x] |
| 14 | `SystemAdminController.java` (`PUT /admin/system/kb-managements/{deptCode}`)   | `updateKnowledgeManagement`      | `@AuditLog(UPDATE, KNOWLEDGE, description="지식 관리자 수정")` + service `addedAdmins`/`removedAdmins` diff detail | [x] |
| 15 | `SystemAdminController.java` (`DELETE /admin/system/kb-managements/{id}`)      | `deleteKnowledgeManagement`      | ❌ 적재 미적용 — 사용자 운영 결정 (삭제 흐름 비사용) | [—] |
| ⊕  | `SystemAdminController.java` (`PUT /admin/system/kb-managements/{id}/description`) | `updateKnowledgeManagementDescription` | `@AuditLog(UPDATE, KNOWLEDGE, description="설명 변경")` (KB 부서 설명 단독 endpoint, 신규 추가) | [x] |

### 5.1 단계 검증

- [ ] 지식 문서 업로드 1건 → audit 적재 확인 (`extra_data.context` 부모 정보 포함)
- [ ] 다중 파일 업로드 케이스에서 `count` 적재 확인
- [ ] 프론트 라벨 동기화

---

## 6. 4단계 — 사용량/프롬프트 ✅

> [!info] A=(2) 결정 — PROMPT_TEMPLATE enum 신규
> 016 마이그레이션 (`dinai-db/migrations/016_audit_logs_add_prompt_template.sql`) + `ResourceType.java` enum 추가
> + `init/01_schema.sql` chk_audit_resource 동기. PromptTemplate / PromptTag 모두 단일 PROMPT_TEMPLATE 자원으로 통일
> (별도 PROMPT_TAG 미도입). description 으로 "템플릿 ..." vs "태그 ..." 구분.
>
> D 보류 항목: `AdminQuotaController.java:38` `getDepartmentQuotaDetail` (활성 — D 보류 풀 #3).
> Prompt 측 단순 조회 2건 (getPromptTemplates / getAdminPromptTags) — D 보류 풀 #10 / #11 모두 활성 (✅ 적재).

| # | 위치 (file:line)                              | 메서드                          | 어노테이션 + 컨텍스트                                                              | 체크 |
|--|---------------------------------------------|------------------------------|---------------------------------------------------------------------------|----|
| 1  | `AdminQuotaController.java:48`              | `updateDepartmentQuota`      | `@AuditLog(UPDATE, QUOTA, "부서 쿼터 변경")` + `detail("limitUsd", request.limitUsd())` (controller) + `detail("oldLimitUsd", existing.getLimitUsd())` (service, 신규 생성 분기 제외) | [x] |
| 2  | `AdminCommonPromptController.java` (POST `""`)        | `createPromptTemplate`       | `@AuditLog(CREATE, PROMPT_TEMPLATE, "공통프롬프트 등록")` + `resourceName(request.getTitle())` + `resourceId(createdId)` | [x] |
| 3  | `AdminCommonPromptController.java` (PUT `/{id}`)      | `updatePromptTemplate`       | `@AuditLog(UPDATE, PROMPT_TEMPLATE, "공통프롬프트 수정")` + service `resourceName(existing.getTitle())` | [x] |
| 4  | `AdminCommonPromptController.java` (PUT `/{id}/state`)| `updatePromptTemplateState`  | `@AuditLog(UPDATE, PROMPT_TEMPLATE, "공통프롬프트 상태 변경")` + `detail("status", status)` + service `resourceName(existing.getTitle())` | [x] |
| 5  | `AdminCommonPromptController.java` (DELETE `/{id}`)   | `deletePromptTemplate`       | `@AuditLog(DELETE, PROMPT_TEMPLATE, "공통프롬프트 삭제")` + service `resourceName(existing.getTitle())` | [x] |
| 6  | `AdminPromptTagController.java` (POST `""`)           | `createPromptTag`            | `@AuditLog(CREATE, TAG, "태그 등록")` + `resourceName(request.tagName())` + `resourceId(created.tagId())` | [x] |
| 7  | `AdminPromptTagController.java` (PUT `/{id}`)         | `updatePromptTag`            | `@AuditLog(UPDATE, TAG, "태그 수정")` + service `resourceName(existing.tagName())` | [x] |
| 8  | `AdminPromptTagController.java` (DELETE `/{id}`)      | `deletePromptTag`            | `@AuditLog(DELETE, TAG, "태그 삭제")` + service `resourceName(existing.tagName())` | [x] |
| 9  | `AdminCommonPromptController.java` (GET `/export`)    | `exportPromptTemplate`       | `@AuditLog(DOWNLOAD, FILE, "공통프롬프트 다운로드")` + `resourceName("prompt-templates.xlsx")`. PathVariable 없음 → resourceId 없음. | [x] |

### 6.1 단계 검증

- [ ] 마이그레이션 016 적용 후 enum CHECK 제약 일치 확인 (`\d dinai.audit_logs` 또는 init.sql 비교)
- [ ] 쿼터 변경 1건 → audit 확인
- [ ] 프롬프트 템플릿 등록 1건 → audit 확인 (resourceType=PROMPT_TEMPLATE, description "템플릿 등록", resource_name = title)
- [ ] 템플릿 export 1건 → audit (DOWNLOAD+FILE, resource_name=prompt-templates.xlsx)

---

## 7. 5단계 — 사용자 작업 도메인

> [!info] MyPrompt 포함 (E 결정 — 적재). A=(2) PROMPT_TEMPLATE 결정 완료.
> MyPrompt 4 항목 (#15~#18) 의 리소스 enum 은 PROMPT_TEMPLATE 단일 사용 — description 으로 "개인 프롬프트 ..."
> 어휘 통일하여 공통 프롬프트 (4단계) 와 라벨 분리.

| # | 위치 (file)                        | 메서드                       | 어노테이션 + 컨텍스트                                                                | 체크 |
|--|----------------------------------|---------------------------|--------------------------------------------------------------------------|----|
| 1  | `ProjectController.java`         | `createProject`           | `@AuditLog(CREATE, PROJECT)`                                              | [ ] |
| 2  | `ProjectController.java`         | `updateProject` (PATCH)   | `@AuditLog(UPDATE, PROJECT)`                                              | [ ] |
| 3  | `ProjectController.java`         | `deleteProject`           | `@AuditLog(DELETE, PROJECT)`                                              | [ ] |
| 4  | `ProjectController.java`         | `pinProject`              | `@AuditLog(UPDATE, PROJECT, description="핀")`                             | [ ] |
| 5  | `ProjectController.java`         | `updateInstruction`       | `@AuditLog(UPDATE, PROJECT, description="지침 변경")`                         | [ ] |
| 6  | `ProjectController.java`         | `pinSession`              | `@AuditLog(UPDATE, CONVERSATION, description="세션 핀")` + `parentResource(PROJECT)` | [ ] |
| 7  | `ProjectController.java`         | `uploadProjectFile`       | `@AuditLog(UPLOAD, FILE)` + `parentResource(PROJECT)`                     | [ ] |
| 8  | `ProjectController.java`         | `deleteProjectFile`       | `@AuditLog(DELETE, FILE)` + `parentResource(PROJECT)`                     | [ ] |
| 9  | `ChatController.java`            | `createChatSession`       | `@AuditLog(CREATE, CONVERSATION)`                                         | [ ] |
| 10 | `ChatController.java`            | `updateChatSession`       | `@AuditLog(UPDATE, CONVERSATION)`                                         | [ ] |
| 11 | `ChatController.java`            | `closeChatSession`        | `@AuditLog(UPDATE, CONVERSATION, description="세션 종료")`                    | [ ] |
| 12 | `ChatController.java`            | `submitFeedback`          | `@AuditLog(UPDATE, CONVERSATION, description="피드백")`                      | [ ] |
| 13 | `ChatController.java`            | `uploadSessionFile`       | `@AuditLog(UPLOAD, FILE)` + `parentResource(CONVERSATION)`                | [ ] |
| 14 | `AgentController.java`           | `chatStream`              | `@AuditLog(EXECUTE, AGENT)` + `detail("model", ...)`                      | [ ] |
| 15 | `MyPromptController.java`        | `createMyPrompt`          | `@AuditLog(CREATE, PROMPT_TEMPLATE, description="개인 프롬프트 등록")`            | [ ] |
| 16 | `MyPromptController.java`        | `updateMyPrompt`          | `@AuditLog(UPDATE, PROMPT_TEMPLATE, description="개인 프롬프트 수정")`            | [ ] |
| 17 | `MyPromptController.java`        | `deleteMyPrompt`          | `@AuditLog(DELETE, PROMPT_TEMPLATE, description="개인 프롬프트 삭제")`            | [ ] |
| 18 | `MyPromptController.java`        | `togglePin`               | `@AuditLog(UPDATE, PROMPT_TEMPLATE, description="개인 프롬프트 핀 토글")`           | [ ] |

> [!info] 스트리밍 + EXECUTE 주의
> `chatStream` 같은 SSE 응답은 컨트롤러 메서드가 즉시 리턴하므로 Aspect 의 `finally` 가 스트리밍 종료 전에 실행됨. result 는 "스트리밍 시작 성공" 의미로 SUCCESS. 스트리밍 중 실패는 별도 메커니즘에서 처리해야 하며, 이번 단계에서는 시작 시점만 적재.

### 7.1 단계 검증

- [ ] 프로젝트 1건 생성/수정/삭제 풀 사이클 → audit 3건 확인
- [ ] 파일 업로드 시 `extra_data.context = {type:"PROJECT", id:"..."}` 확인
- [ ] AI 대화 1건 시작 → `EXECUTE+AGENT` 적재 확인 (스트리밍 종료와 무관)
- [ ] MyPrompt CRUD 1사이클 적재 확인 (A 결정 후)

---

## 8. 6단계 — Clipping 운영 ❌ 배제

> [!warning] 본 롤아웃에서 제외 — B 결정
> Clipping 도메인은 사용자 담당 영역이 아니므로 별도 일정으로 분리.
> 추후 진행 시: (a) `ResourceType.CLIPPING` 신규 enum vs (b) `EXECUTE+DEPLOY` 재활용 결정 → 별도 계획서 신설.

대상 메서드 참조용 (적용 보류):
- `AdminClippingController.java:82~274` 12개 메서드 (excludeArticle/includeArticle/addArticle/removeAdded/overrideField/enrich/publish/runPipeline/ogMetadata/preview/publishHistory/agentRuns)

---

## 9. D 보류 풀 — 단순 조회 (화면 보고 단계별 결정) ⏸

> [!info] 운영 방식
> 단계 진행 중 해당 화면을 마주치면 결정 → 적재 확정 시 본래 단계 표로 옮기고 체크박스 활성, 미적재 확정 시 표에서 제거.

| # | 위치 (file:line)                    | 메서드                       | 후보 어노테이션                                                | 결정    | 체크 |
|--|----------------------------------|---------------------------|----------------------------------------------------------|------|----|
| 1 | `AdminCommonController.java` (`/admin/common/users/search`) | `searchUsersByName` | `@AuditLog(READ, USER, "사용자 검색")` + `message(name)` (비고에 검색어 결합) + `detail("count", n)` | ✅ 적재 | [x] |
| 6 | `AdminCommonController.java` (`/admin/common/users`)        | `getUsers` (이전 AdminController 에서 이동) | `@AuditLog(READ, USER, "사용자 목록 조회")` + `detail("count", n)` | ✅ 적재 | [x] |
| 2 | `AdminAgentController.java:73`   | `getAgentDocuments`       | `@AuditLog(READ, AGENT, "RAG 목록 조회")` + `detail("count", n)` (resourceId=agentId 자동, resource_name 자동 폴백 → agentName) | ✅ 적재 | [x] |
| 3 | `AdminQuotaController.java:38`   | `getDepartmentQuotaDetail`| `@AuditLog(READ, QUOTA, "부서 쿼터 상세 조회")` (resourceId=deptCode 자동, resource_name 폴백 미동작 — NULL 허용) | ✅ 적재 | [x] |
| 4 | `AuthorityController.java`       | `getDepartmentChildren`   | `@AuditLog(READ, DEPT, "부서 구성원 조회")` + `detail("count", n)` (resourceId=deptCode 자동, resourceName 자동 폴백 → 부서명) | ✅ 적재 | [x] |
| 5 | `SystemAdminController.java`     | `getUserDetail`           | `@AuditLog(READ, USER, "사용자 상세 조회")` (resourceId=employeeId 자동, resourceName 자동 폴백 → 사용자명) | ✅ 적재 | [x] |
| 7 | `AdminCommonController.java` (`/admin/common/departments/{deptCode}/users-with-roles`) | `getUsersWithRolesByDepartment` | ❌ 적재 미적용 — `AuthorityController` → `AdminCommonController` 이전 + audit 제거 (운영 노이즈 회피, 빈번 호출) | ❌ 배제 | [—] |
| 8 | `AdminAgentController.java:69`   | `getAgentStatus`          | `@AuditLog(READ, AGENT, "개별 상태 조회")` (resourceId=agentId 자동, resource_name 자동 폴백 → agentName) | ✅ 적재 | [x] |
| 9 | `AdminAgentController.java:157`  | `getAgentScopes`          | `@AuditLog(READ, AGENT, "사용범위 조회")` + `detail("count", n)` (resourceId=agentId 자동) | ✅ 적재 | [x] |
| 10 | `AdminCommonPromptController.java` (GET `""`) | `getPromptTemplates`     | `@AuditLog(READ, PROMPT_TEMPLATE, "공통프롬프트 목록 조회")` + `detail("count", response.pageInfo.totalItems)` (resourceId 없음 — 목록 조회) | ✅ 적재 | [x] |
| 11 | `AdminPromptTagController.java` (GET `""`)    | `getAdminPromptTags`     | `@AuditLog(READ, TAG, "태그 목록 조회")` + `detail("count", result.pageInfo.totalItems)` (resourceId 없음 — 목록 조회) | ✅ 적재 | [x] |

> [!info] 추가 조회 후보
> 작업 진행 중 "이 조회도 audit 가 필요할 듯" 판단되는 메서드는 본 표에 추가 후 결정.

---

## 10. 7단계 — 검증 + 라벨 동기화

| # | 작업                                                       | 체크 |
|--|----------------------------------------------------------|----|
| 1 | (A=2 시) `dinai-db/migrations/016_*.sql` enum CHECK 제약 추가     | [ ] |
| 2 | `dinai-core-api && ./gradlew build` 풀 빌드 통과 (테스트 포함)       | [ ] |
| 3 | `dinai-client/src/entities/admin-log/lib/labels.ts` ACTIVITY_MATRIX 라벨 추가 (모든 신규 매트릭스) | [ ] |
| 4 | `dinai-client && npm run check-all` 통과                     | [ ] |
| 5 | `/admin/logs/audit` 화면에서 단계별 적재 결과 시각 확인 (필터로 logType/resourceType 분리) | [ ] |

---

## 11. 작업 규약 (반복 참조용)

> [!info] 매번 같은 패턴
> 단계 진행 시 (1) 결정 의존 확인 → (2) 컨트롤러 메서드 어노테이션 + AuditContext 보조 → (3) `./gradlew build -x test` → (4) 화면에서 1건 적재 확인 → (5) 본 문서 체크박스 갱신.

### 11.1 어노테이션 부착 패턴

```java
// 단순 케이스 (resourceId = PathVariable 자동)
@AuditLog(action = UPDATE, resource = AGENT, description = "활성 상태")
@PutMapping("/{agentId}/active")
public ResponseEntity<...> updateAgentActiveStatus(@PathVariable String agentId, ...) { ... }

// 부모 컨텍스트 + 다중
@AuditLog(action = UPLOAD, resource = FILE)
@PostMapping("/{projectId}/files")
public ResponseEntity<...> upload(@PathVariable String projectId, MultipartFile[] files) {
    AuditContext.parentResource(ResourceType.PROJECT, projectId)
                .detail("count", files.length);
    return service.upload(...);
}

// 의미 모호 (description 필수)
@AuditLog(action = UPDATE, resource = ACCOUNT, description = "비밀번호 변경")
public ... changePassword(...) { ... }
```

### 11.2 enum 추가 시 체크

- [ ] `ResourceType.java` 또는 `AuditActionType.java` enum 값 추가
- [ ] `dinai-db/init/01_schema.sql` 의 CHECK 제약 갱신
- [ ] `dinai-db/migrations/` 신규 마이그레이션 파일 (운영 적용용이 아닌 신규 환경 갱신용)
- [ ] 프론트 `entities/admin-log/lib/labels.ts` 라벨 매트릭스 갱신

### 11.3 진행 메모

```text
2026-05-04 — 사전 결정 4건 확정:
  · B 배제 (Clipping 별도 일정)
  · C (1) 안 적재 (access_logs 담당)
  · D 화면 보고 단계별 결정 (보류 풀 운영)
  · E (1) MyPrompt 적재 — 5단계에 4건 추가
A 미결정 → 4단계 + 5단계 MyPrompt 4건은 ⟨A⟩ 자리 채운 뒤 진행 가능.

2026-05-04 — 1단계 ✅ 마감 + 인프라/보안 보강 통합:
  · ErrorCode 4개 신규 (VAL_PASSWORD_MISMATCH/POLICY/REUSED, RULE_PASSWORD_CHANGE_DENIED) +
    UserApplicationService 비밀번호 도메인 9곳 적용. RULE_BUSINESS_VIOLATION 단일 코드 → 의미별 분리.
  · service-side 레거시 recordAuditLog 5곳 제거 — Aspect 일원화. 013 CHECK 위반 INSERT 실패 케이스 해소.
  · AuditContext.actor(employeeId, name) + UserApplicationService.resolveActorSnapshot 헬퍼 추가.
  · AuditLogAspect 자동 폴백 — 사번 있고 username/dept 비어있으면 DB 조회로 보강 (규칙: 사번 row 는
    username/dept_name 도 반드시 채움). access_logs 측 logout/refresh/session-expire 도 동일 패턴 통일.
  · SecurityConfig default-deny 도입 — anyRequest().permitAll() → authenticated(). public 은 PUBLIC_URLS
    명시만. 인증 누락 호출 시 audit_logs 에 SYSTEM 박히던 케이스가 차단됨.
  · ASYNC dispatch 호환 — JwtAuthenticationFilter.shouldNotFilterAsyncDispatch=false override.
    (Mono 리턴 컨트롤러의 async dispatch 단계에서 anonymous 로 떨어져 403 나던 race 해결)
  · 임시 비밀번호 메일 실패 → InfrastructureError(NET_UPSTREAM_FAILURE, ..., cause) 정합화.
  · dinai-client ERROR_CODE_LABEL 한글 라벨 4개 추가.

2단계 진입 시 선행/병합 체크:
  · UserApplicationService.recordAuditLog 헬퍼는 changeUserRole 1곳만 호출 잔존 (logType="PERMISSION_CHANGE"
    가 enum 위반). 2단계 #1 (AdminController.changeUserRole 어노테이션 부착) 시 같이 제거 → 헬퍼 자체 삭제 후보.
  · UserLoginFailureTxService.insertAuditLog 가 박는 logType "DORMANT_LOCK"/"ACCOUNT_LOCK" 도 enum 위반 →
    UPDATE+ACCOUNT description="휴면 잠금"/"로그인 5회 실패 잠금" 으로 정합화 필요. 별도 로그인 도메인
    리팩토링 사이클로 처리.

2026-05-04 — 2단계 ✅ 마감:
  · 컨트롤러 5개 메서드 어노테이션 부착 + AuditContext 보강 (resourceId/parentResource/detail)
  · UserApplicationService.recordAuditLog 헬퍼 + 부수 헬퍼 (safeIp / resolveAccessPathFromUserAgent /
    buildExtraData / escapeJson) + auditLogService 의존 + ClientInfoExtractor import 일괄 제거.
  · 잔여 — UserLoginFailureTxService.insertAuditLog 만 service-side 레거시 적재 잔존 (별도 로그인 도메인
    리팩토링 사이클에서 처리 예정).

2026-05-04 — 사용자 관리 엔드포인트 SystemAdminController 통합 이전:
  · AdminController 의 changeUserRole / unlockUser / deactivateUser / resetInitialPassword (4개) 와
    AuthorityController 의 updateUserActiveStatus / updateAdminStatus (2개) 를 SystemAdminController 로 이동.
    path prefix 통일: 모두 /admin/system/users/{employeeId}/... 형태. SecurityConstants.ADMIN_SYSTEM_URLS
    매처(hasRole("SYSTEM_ADMIN")) 자동 적용으로 가드 일관화.
  · employeeId 가 RequestParam 이던 2건도 PathVariable 로 정합화 (자동 resourceId 추출 가능).
  · AdminController 의 inner record (UnlockUserRequest / DeactivateUserRequest / ResetInitialPasswordRequest) 3개를
    interfaces.dto.request 별도 파일로 분리 (재사용 가능).
  · 클라이언트 authorityApi.updateUserActive path 갱신 (/authorities/user/active → /admin/system/users/{employeeId}/active).
    다른 5개는 클라이언트 호출 사이트 없음 — 백엔드만 갱신.
  · AdminController 의 unused import + AuthSessionService 의존 정리.

2026-05-04 — 3단계 #13/#14 (KB 관리 부서 생성/변경) 부착 (Step A):
  · createKnowledgeManagement (#13): @AuditLog(CREATE, KNOWLEDGE, "지식부서 생성") + detail("deptName", request.getName())
  · updateKnowledgeManagement (#14): description "지식그룹 변경" → "지식부서 변경" 으로 용어 통일 + detail("deptName", request.getName())
  · deleteKnowledgeManagement (#15): 사용자 운영 결정으로 적재 미적용 (삭제 흐름 비사용). 합계에서 제외.
    KnowledgeBaseService.deleteKnowledgeManagement 시그니처 void 원복.
  · 사용자 시야: audit_logs.extra_data.deptName 으로 화면이 resourceId 옆 이름 결합 표시 가능 (Step C).

2026-05-04 — 3단계 ✅ 마감 (#1~#12 일괄 부착):
  · AdminAgentController 7곳 (#1~#7) + AdminKBController 5곳 (#8~#12) 어노테이션 부착.
  · 토글 패턴 (#1 updateAgentActiveStatus / #10 updateKnowledgeDocumentStatus): description 고정 + AuditContext.message
    로 부여 방향성 결합. 예: "활성 상태 | 활성화", "활성 상태 | 비활성".
  · KNOWLEDGE 산하 자원이 AGENT 인 경우 (#4~#7) parentResource(AGENT, agentId), KB 산하 (#8/#9/#11) 는
    parentResource(DEPT, deptCode, deptName) 으로 부모 컨텍스트 박음 — 화면에서 "어느 부서/에이전트 산하 문서인가"
    한눈에 식별 가능.
  · 신규 등록 (#4 registerAgentDocument / #8 registerKnowledgeDocument) 은 path 에 docId 가 없으므로 service 리턴값을
    AuditContext.resourceId(newDocId) 로 명시. resourceName 은 업로드 파일의 originalFilename 을 직접 박음
    (가장 정확한 시점값 — 삭제/이름 변경되어도 보존).
  · #5 updateAgentDocument (버전 업그레이드) 는 신규 docId 가 새로 발급되므로 detail("newDocId") 로 보존하되
    resourceId 는 PathVariable 의 기존 docId 유지 — 변경 대상 식별이 자연스러움.
  · 단일 파일 업로드 흐름이라 표 가이드라인의 "다중파일이면 detail("count", N)" 조건은 비적용.

2026-05-04 — KNOWLEDGE 자동 폴백 추가 (resource_name 매트릭스 보강):
  · KnowledgeBaseMapper.findKnowledgeNameById 신규 + knowledge_base.xml UNION 쿼리 (dinai.documents +
    dinai.agent_documents) — docId 한 건으로 두 테이블의 file_name 을 한 번에 조회. NULLIF + ::uuid 캐스팅으로
    잘못된 UUID 입력은 NULL 처리 (Aspect 의 try-catch 가 추가 흡수).
  · AuditLogAspect.resolveResourceNameByType 의 KNOWLEDGE case 추가 + safeKnowledgeName 헬퍼.
  · 폴백 매트릭스 갱신: USER/ACCOUNT → username, DEPT → dept_name, AGENT → agentName, KNOWLEDGE → fileName,
    PERMISSION → 사용자 우선 → 없으면 에이전트.
  · 효과: AdminAgentController/AdminKBController 의 KNOWLEDGE 케이스 (#5~#7, #9~#12) 가 resourceName 명시
    없이도 자동으로 file_name 적재 → audit 화면의 "리소스명" 컬럼에서 운영자가 docId UUID 대신 파일명으로 식별 가능.
  · DB 스키마 변경 없음 (Aspect 코드 + Mapper 추가만).

2026-05-04 — audit_logs.resource_name 컬럼 도입 + UI 3컬럼 분할:
  · DB: 014_audit_logs_resource_name.sql 신규 마이그레이션 + init/01_schema.sql 동기. resource_name VARCHAR(255) NULL
    + idx_audit_resource_name 부분 인덱스. dept_name/username 과 동일 비정규화 스냅샷 패턴.
  · 백엔드 일괄: AuditLogCommand/Record/ListRecord/DetailRecord/ListResponse/DetailResponse + auditLogs.xml 4쿼리 +
    AuditContext.resourceName(...) + snapshotResourceName() + AuditLogAspect.buildCommand 결합.
  · AuditLogAspect 자동 폴백 — 컨트롤러가 resourceName 명시 안 했고 resourceId 가 식별 가능하면 resourceType 기준 단건 조회:
    USER/ACCOUNT → 사번 → username, AGENT → agentId → agentName, PERMISSION → 사용자 우선 → 없으면 에이전트.
    AgentMapper.findAgentNameById 신규 + UserApplicationService.resolveActorSnapshot 활용.
  · 컨트롤러 마이그레이션: AuditContext.detail("deptName", ...) → AuditContext.resourceName(...). KB 관리 4곳.
  · description 단순화 + extra_data 활용:
    - updateAgentOwners "에이전트 오너" → "에이전트 오너 수정". parentResource/count 제거. service 가 added/removed
      diff 계산 후 AuditContext.detail("addedOwners","removedOwners") 박음 (UI 표시 X, extra_data 보존).
    - updateKnowledgeManagement "지식부서 변경" → "지식 관리자 수정". service 가 KB_ADMIN diff 결과 detail 박음
      (addedAdmins/removedAdmins).
  · 클라이언트: AuditLogListResponse/DetailResponse 에 resourceName 필드 + AuditLogRow.resourceName 추가.
    mappers.ts 의 pickResourceName/resolveResourceIdDisplay 헬퍼 + extra_data 추출 로직 모두 제거 (extra_data 는
    UI 조회용 X — 디버그/원본 보존만). LogMonitoringPage 헤더 "리소스 → 리소스 ID" → "리소스 타입 → 리소스 ID
    → 리소스명" 3컬럼 분할.

2026-05-04 — KB 부서 설명 단독 수정 흐름 분리 (한 화면 통합 모달 → 행 액션 분리):
  · 백엔드: PUT /admin/system/kb-managements/{id}/description 신규 endpoint + KnowledgeBaseService
    .updateKnowledgeManagementDescription(id, description, updater) 신규 (적재 시점 부서명 리턴).
    @AuditLog(UPDATE, KNOWLEDGE, "설명 변경"). 통합 update 의 KnowledgeManagementUpdateRequest 에서 description 필드
    제거 (이름 + KB_ADMIN 멤버만 변경) → service 가 description 기존값 그대로 유지.
  · 클라이언트: features/kb-management/ 디렉터리 신규 (KnowledgeRowActions, KnowledgeDescriptionModal). 통합 모달
    (KnowledgeManagementFormModal) 의 description textarea + state 제거. KnowledgeManagerTable 의 행 액션 드롭다운에
    "설명 수정" 항목 통합. updateKnowledgeManagement 호출도 description 인자 제거.

2026-05-04 — 컨트롤러 파일 통합:
  · AdminAccessLogController + AdminAuditLogController → AdminLogController 1개로 통합. path 변경 X
    (/admin/logs/access, /audit 그대로). 클라이언트 호출 사이트 변경 없음.
  · 테스트 AdminAccessLogControllerTest → AdminLogControllerTest 로 rename + InjectMocks 타겟 변경 + AuditLogService
    mock 추가 (생성자 주입 호환).

2026-05-04 — D 보류 풀 부분 활성화 (사용자 권한 화면 흐름):
  · #1 AdminCommonController.searchUsersByName: @AuditLog(READ, USER, "사용자 검색") + AuditContext.message(검색어)
    로 비고에 검색어 결합 (description="사용자 검색 | 홍길동" 형태) + detail("count", totalItems).
  · #4 AuthorityController.getDepartmentChildren (조직도 클릭 시 호출): @AuditLog(READ, DEPT, "부서 구성원 조회")
    + detail("count", N). resourceId=deptCode (PathVariable 자동), resource_name 자동 폴백 (DEPT case 추가) → 부서명.
  · #5 SystemAdminController.getUserDetail (사용자 클릭 → 상세): @AuditLog(READ, USER, "사용자 상세 조회").
    resourceId=employeeId 자동, resource_name 자동 폴백 → 사용자명.
  · #7 AuthorityController.getUsersWithRolesByDepartment (부서별 사용자 권한 목록): @AuditLog(READ, DEPT, "부서
    사용자 권한 목록") + detail("count", N).
  · AuditLogAspect.resolveResourceNameByType 에 DEPT case 추가 + OrganizationMapper.findDeptNameByCode 신규
    (Java + XML).

2026-05-04 — 사용자 목록/검색 endpoint 통합 정리 (AdminController → AdminCommonController):
  · AdminController.getUsers 메서드 + 의존(UserApplicationService) + 관련 imports 모두 제거.
  · AdminCommonController 에 getUsers (@AuditLog(READ, USER, "사용자 목록 조회") + count) 추가 (path: /admin/common/users).
  · AdminCommonController.searchUsersByName path: /admin/common/users → /admin/common/users/search (충돌 회피).
  · 클라이언트 3곳 path 갱신:
    - entities/admin-common/api/adminCommonApi.ts:62 — searchUsersByName /admin/common/users → /admin/common/users/search
    - entities/user/api/userApi.ts:41 — getUsersList /admin/users → /admin/common/users
    - entities/authority/api/authorityApi.ts:106 — searchUserAuthority no-deptCode 분기 /admin/users → /admin/common/users

============================================================================
세션 종료 요약 (2026-05-04)
============================================================================
이번 세션의 변경 종합 — 다음 세션 시작 시 컨텍스트로:

1. 백엔드 파일 변경:
   · 신규: AdminLogController, AgentMapper.findAgentNameById, OrganizationMapper.findDeptNameByCode,
     AuditContext.resourceName, KnowledgeBaseService.updateKnowledgeManagementDescription,
     KnowledgeManagementDescriptionUpdateRequest, UnlockUser/Deactivate/ResetInitialPassword Request DTO 분리,
     UserApplicationService.ActorSnapshot record + resolveActorSnapshot.
   · 통합/이동: AdminLogController = AdminAccessLogController + AdminAuditLogController. SystemAdminController 가
     사용자 관리 6개 메서드 (changeUserRole / unlockUser / deactivateUser / resetInitialPassword /
     updateUserActiveStatus / updateAdminStatus) 통합. AdminCommonController 가 사용자 목록/검색 통합.
   · 삭제: AdminAccessLogController, AdminAuditLogController, UserApplicationService.recordAuditLog 헬퍼 등.

2. DB:
   · 014_audit_logs_resource_name.sql 신규 마이그레이션 + init/01_schema.sql 동기 (resource_name VARCHAR(255) +
     idx_audit_resource_name 부분 인덱스). 컨테이너 DB 에 직접 ALTER 적용 완료.

3. AuditLogAspect 자동 폴백 매트릭스:
   · employee_id 폴백: 사번이 실제 사원이면 username/dept_code/dept_name 도 보강 (UserApplicationService.resolveActorSnapshot).
   · resource_name 폴백: USER/ACCOUNT → username, DEPT → dept_name, AGENT → agentName,
     PERMISSION → 사용자 우선 → 없으면 에이전트.
   · ASYNC dispatch 호환: shouldNotFilterAsyncDispatch=false (Mono 리턴 컨트롤러 race fix).

4. 보안 정책:
   · default-deny 도입 (.anyRequest().permitAll() → .authenticated()) ServerSecurityConfig + LocalSecurityConfig.
     PUBLIC 노출은 SecurityConstants.PUBLIC_URLS 명시 등록만.

5. ErrorCode 분리:
   · VAL_PASSWORD_MISMATCH/POLICY/REUSED + RULE_PASSWORD_CHANGE_DENIED 신규. UserApplicationService 9곳 적용.
   · 임시 비밀번호 메일 발송 실패 → InfrastructureError(NET_UPSTREAM_FAILURE, ..., cause).
   · 클라이언트 ERROR_CODE_LABEL 4개 한글 라벨.

6. 클라이언트:
   · LogMonitoringPage 컬럼 3분할: 리소스 → 리소스 타입 + 리소스 ID + 리소스명.
   · AuditLogListResponse/DetailResponse 타입에 resourceName 추가, mappers.ts 의 extra_data 추출 로직 제거
     (extra_data 는 디버그/원본 보존 — UI 조회용 X).
   · features/kb-management/ 신규 (KnowledgeRowActions + KnowledgeDescriptionModal).
   · KnowledgeManagementFormModal 의 description textarea 제거 + KnowledgeManagementUpdateRequest 타입에서 description 제거.
   · 사용자 목록/검색 path 3곳 갱신.

7. 잔여 (다음 세션):
   · 3단계 #1~#12, #14 의 일부 미완 (AdminAgentController + AdminKBController 전 메서드).
   · 4단계 (사용량/프롬프트, A 결정 의존), 5단계 (사용자 작업 도메인), 7단계 (검증 + 라벨 동기화) 미진입.
   · D 보류 풀 #2 (AdminAgentController.getAgentDocuments), #3 (AdminQuotaController.getDepartmentQuotaDetail) 미결정.
   · UserLoginFailureTxService.insertAuditLog 의 logType "DORMANT_LOCK"/"ACCOUNT_LOCK" enum 정합화 (별도 사이클).
   · KB 화면 행 액션 "설명 수정" 모달 — frontend agent 가 통합 완료. 실제 동작 검증은 사용자 환경에서.
   · core-api 빌드/재기동: make bounce-core (사용자 환경 PowerShell 에서).

============================================================================
세션 종료 요약 (2026-05-04 — #3)
============================================================================
1차 세션 종료 요약 (line 549~597) + 2차 세션 통합 요약 — 다음 세션 시작 시 컨텍스트로.
2차 세션의 개별 진행 메모 블록 (RAG resourceType AGENT 통일 / 정보 수정 보정 / D 보류 풀 #2/#3 활성 /
4단계 #1 부서 쿼터 / RAG description 통일 / QUOTA 폴백 / fileName 명시 박기 / 4단계 #2~#9 Prompt + PROMPT_TEMPLATE
enum 신규 / 표 stale 정리 + 메모 통합) 는 본 요약 블록으로 통합. 정보 손실 회피 위해 결정 근거 + 운영자 표현 보존.

1. 컨트롤러 어노테이션 부착 (백엔드 25건 신규/보정):
   · 3단계 #1~#12 (12건) 일괄 부착 — AdminAgentController 7건 (활성/정보 수정/범위 + RAG 등록/수정/메타데이터/삭제),
     AdminKBController 5건 (KB 부서 지식 등록/수정/상태/메타데이터/삭제). 3단계 14/14 ✅ 마감.
   · 3단계 ⊕ KB 부서 설명 단독 endpoint (PUT /admin/system/kb-managements/{id}/description) 신규 — frontend
     행 액션 모달 분리에 따라 endpoint + service 메서드 + DTO 신설.
   · 4단계 9건 일괄 — #1 updateDepartmentQuota (UPDATE+QUOTA, "부서 쿼터 변경") + #2~#8 Prompt CRUD 7건
     (PROMPT_TEMPLATE 자원, AdminCommonPromptController 5 + AdminPromptTagController 3 분리됨) + #9
     exportPromptTemplate (DOWNLOAD+FILE, "템플릿 export"). 4단계 9/9 ✅ 마감.
   · D 보류 풀 #2 (getAgentDocuments READ+AGENT "RAG 목록 조회" + count=totalItems) + #3 (getDepartmentQuotaDetail
     READ+QUOTA) + #8 (getAgentStatus READ+AGENT "개별 상태 조회") + #9 (getAgentScopes READ+AGENT "사용범위 조회"
     + count) 4건 활성. D 보류 풀 9/11 (Prompt 단순 조회 2건 #10/#11 미정 추가). 합계 D 활성 9건.
   · 보정 — #2 updateAgentDescription description "설명 변경" → "정보 수정" (Swagger summary 와 사용자
     운영 표현 일치).

2. 자원 모델 재정의:
   · 에이전트 RAG ↔ KB 부서 지식 도메인 분리 — RAG 4건 (#4~#7) resourceType KNOWLEDGE → AGENT 통일.
     parentResource(AGENT) 호출 제거 (자기 자신 가리킴), pathVar="docId" 풀어 docId 는 detail 보존.
     KB 부서 지식 (#8~#12, #13~#14) 만 KNOWLEDGE 유지. KnowledgeBaseMapper.findKnowledgeNameById +
     knowledge_base.xml UNION 제거 (agent_documents 분기 불필요) → documents 단일 lookup.
   · description 용어 통일 — 에이전트 RAG 5건 ("문서 ..." / "지식 파일 ...") → "RAG ..." 접두어 (RAG 업로드/
     수정/메타데이터/삭제/목록 조회). KB 측은 기존 어휘 유지 ("메타데이터", "활성 상태", "지식부서 생성/변경",
     "지식 관리자 수정", "설명 변경"). 화면 라벨 도메인 충돌 회피.
   · ResourceType.java enum — PROMPT_TEMPLATE("프롬프트 템플릿") 신규 (KNOWLEDGE 다음, SETTING 직전).
     카탈로그 14 → 15개. PromptTemplate / PromptTag 단일 PROMPT_TEMPLATE 으로 통일 (별도 PROMPT_TAG 미도입,
     description 으로 "템플릿 ..." vs "태그 ..." 구분). MyPrompt 4건 (5단계 #15~#18) 도 동일 enum 사용 —
     description "개인 프롬프트 ..." 어휘로 공통 프롬프트와 분리.

3. AuditLogAspect 자동 폴백 매트릭스 (resolveResourceNameByType) 갱신:
   · KNOWLEDGE → fileName (KB 부서 지식 단독, agent_documents 분기 제거됨)
   · QUOTA → dept_name 신규 — DEPT case 와 multi-label fall-through 로 묶음 (case "DEPT": case "QUOTA":
     → safeDeptName(resourceId)). resourceId=deptCode 라 OrganizationMapper.findDeptNameByCode 재활용,
     신규 매퍼 추가 0건.
   · 최종 매트릭스: USER/ACCOUNT → username, DEPT/QUOTA → dept_name, AGENT → agentName, KNOWLEDGE →
     fileName, PERMISSION → 사용자 우선 → 없으면 에이전트, PROMPT_TEMPLATE → 폴백 미정의 (service 명시 박기).

4. resourceName 명시 박기 (자동 폴백 한계 보강 — service layer 진입 즉시):
   · 사유: KNOWLEDGE 폴백은 documents 단일 lookup 인데 (1) deleteKnowledgeDocument 의 soft delete 후 폴백 NULL,
     (2) AGENT 폴백은 agentName 이라 RAG 파일 식별성 부족 (운영자 시야는 fileName 이 더 유용).
   · AgentServiceImpl 3건 (#5/#6/#7) — AuditContext.resourceName(existing.getFileName()) 1줄씩.
   · KnowledgeBaseService 4건 (#9/#10/#11/#12) — 동일 패턴.
   · PromptTemplateService 3건 (#3/#4/#5) — existing.getTitle() 재사용.
   · PromptTagService 2건 (#7/#8) — existing.tagName() 재사용. 매퍼 신규 추가 0건 (기존 service 가 진입 직후
     entity lookup 중이라 재사용 가능).
   · 등록 4건 (#4/#8/#2 createPromptTemplate/#6 createPromptTag) 은 컨트롤러에서 request 시점 originalFilename/
     title/tagName 명시 — 등록 시점은 식별자 미발급이라 폴백 불가.
   · #9 exportPromptTemplate — PathVariable 없음 → resourceName("prompt-templates.xlsx") 컨트롤러 명시.

5. 클라이언트 (LogMonitoringPage 후속):
   · 리소스 ID 컬럼 16자 초과 시 앞 16자 + ellipsis truncate (UUID 36자 길이 식별자 화면 깨짐 방지), hover
     full ID 툴팁. 상세 드로어는 full 표시 + 활동 리소스 / 활동 리소스 ID / 활동 리소스명 3필드 분리 노출.
   · entities/admin-log/lib/format.ts 신규 + Vitest 8개 케이스. format 헬퍼만 entities/admin-log/index.ts
     re-export.

6. DB:
   · 014_audit_logs_resource_name.sql — resource_name VARCHAR(255) 컬럼 + idx_audit_resource_name 부분 인덱스
     (1차 세션 적용 완료).
   · 016_audit_logs_add_prompt_template.sql 신규 (본 세션) — chk_audit_resource DROP/ADD 패턴으로 'PROMPT_TEMPLATE'
     추가 (BEGIN/COMMIT 트랜잭션 안전). init/01_schema.sql 의 chk_audit_resource 도 동기 (신규 환경 갱신용).
   · 사용자 환경 적용 명령어 — `make bounce-core` 전에 컨테이너 DB 직접 ALTER:
     `docker exec -i <postgres-container> psql -U dba -d devdb -f /migrations/016_audit_logs_add_prompt_template.sql`
     또는 호스트에서 `psql -h localhost -p <port> -U dba -d devdb -f dinai-db/migrations/016_audit_logs_add_prompt_template.sql`.

7. 0단계 사전 결정 — A=(2) 마감:
   · A=(2) PROMPT_TEMPLATE enum 신규 채택. 근거: SETTING 재활용 시 의미 모호 + Prompt 도메인 가시 분리 필요.
     B (배제) / C (1 안 적재) / D (보류 풀 운영) / E (1 적재) 는 1차 세션에 마감. 0단계 5/5 ✅.

8. 진행 현황 (대시보드 line 14~23):
   · 0단계 5/5 ✅ · 1단계 5/5 ✅ · 2단계 5/5 ✅ · 3단계 14/14 (+1 KB 설명 신규) ✅
   · 4단계 9/9 ✅ · 5단계 0/18 ⏳ · 6단계 ❌ 배제
   · D 보류 풀 9/11 ✅ 부분 (#10 getPromptTemplates / #11 getAdminPromptTags 미정)
   · 7단계 0/5 ⏳
   · 합계 43/65.

9. 표 위치 컬럼 정합화 (본 세션 마지막 정리):
   · 1단계/2단계/3단계/5단계 표의 "위치 (file:line)" 헤더 → "위치 (file)" 로 단순화. line 번호는 commit
     시점에 따라 변동되어 신뢰성 낮으므로 일괄 제거. SystemAdminController 통합 후 path 형태 (예: /admin/system/...)
     로 식별 — IDE 메서드명 검색 가능하면 line 불필요.
   · 4단계 / §9 D 보류 풀 표는 이미 path 형태로 정합 (직전 작업에서 처리됨).
   · 5단계 표 ⟨A⟩ 자리 모두 PROMPT_TEMPLATE 으로 채움 (MyPrompt #15~#18).

10. 잔여 (다음 세션):
   · 5단계 #1~#14 (Project/Chat/Agent 14건) + #15~#18 (MyPrompt 4건) 일괄 부착 — A 결정 완료 상태라 모두
     진입 가능. ProjectController / ChatController / AgentController / MyPromptController 4파일.
     CONVERSATION 자원 + parentResource(PROJECT/CONVERSATION) 패턴 + chatStream 의 EXECUTE+AGENT 시작 시점
     적재 (SSE 스트리밍 종료 무관) 주의.
   · D 보류 풀 #10 (getPromptTemplates) / #11 (getAdminPromptTags) 단순 조회 — 사용자 결정 후 활성/배제.
   · 7단계 라벨 매트릭스 동기화 (frontend ACTIVITY_MATRIX) — 본 세션 신규 description 약 23종 누적:
     - UPDATE+AGENT 3종 ("활성 상태" / "정보 수정" / "범위 변경")
     - UPLOAD/UPDATE/DELETE+AGENT 4종 ("RAG 업로드/수정/메타데이터/삭제")
     - READ+AGENT 3종 ("개별 상태 조회" / "사용범위 조회" / "RAG 목록 조회")
     - UPLOAD/UPDATE/DELETE+KNOWLEDGE 5종 ("메타데이터" / "활성 상태" / KB 등록/수정/삭제 자동 라벨)
     - CREATE/UPDATE+KNOWLEDGE 3종 ("지식부서 생성" / "지식 관리자 수정" / "설명 변경")
     - UPDATE+QUOTA 1종 ("부서 쿼터 변경")
     - READ+QUOTA 1종 ("부서 쿼터 상세 조회")
     - CREATE/UPDATE/DELETE+PROMPT_TEMPLATE 6종 ("템플릿 등록" / "상태 변경" / "태그 등록/수정/삭제" + 무라벨
       UPDATE/DELETE 2종은 enum label "프롬프트 템플릿 수정/삭제" 자동)
     - DOWNLOAD+FILE 1종 ("템플릿 export")
   · 016 마이그레이션 적용 — 사용자 환경 PowerShell `docker exec ... psql` 또는 `make bounce-core` 후 audit
     적재 row 의 resourceType=PROMPT_TEMPLATE 동작 확인.
   · UserLoginFailureTxService.insertAuditLog 의 logType "DORMANT_LOCK"/"ACCOUNT_LOCK" enum 정합화 (별도
     로그인 도메인 리팩토링 사이클).
   · 화면 시각 검증 — make bounce-core 후 신규 적재 row 의 resource_name 자동 폴백 (KNOWLEDGE/QUOTA)
     동작 확인 + 도메인 분리 가시성 (resourceType 필터 AGENT / KNOWLEDGE / PROMPT_TEMPLATE / QUOTA / FILE)
     확인.

============================================================================
세션 종료 요약 (2026-05-04 — #4)
============================================================================
세션 종료 요약 #3 직후 추가 7건 변경 + 클라이언트 측 4건 변경 통합. #3 블록 보존, 본 #4 만 신규.

1. getUsersWithRolesByDepartment 이전 + audit 미적재 (D 보류 풀 #7 ❌ 배제):
   · 사용자 운영 결정 — 본 endpoint 는 빈번 호출 발생, 운영 로그 노이즈 회피로 audit 미적재.
   · AuthorityController → AdminCommonController 메서드 이전. URL: /authorities/departments/{deptCode}/users-with-roles
     → /admin/common/departments/{deptCode}/users-with-roles. @AuditLog 미부착, 메서드 위 1줄 WHY 주석으로
     의도 보존 ("// 로그 미적재 — 빈번 호출 노이즈 회피 (사용자 운영 결정)").
   · AuthorityController 측 미사용 import 3종 (User / PaginationRequest / jakarta.validation.Valid) 일괄 제거.
     AuditContext / AuditLog 등은 getDepartmentChildren 도 사용 중이라 유지.
   · AdminCommonController 에 AuthorityApplicationService final 필드 + import 3종 (AuthorityApplicationService /
     User / PathVariable) 추가. service 시그니처 변경 X (interface 그대로 복제).
   · 인증 가드 — 별도 명시 안 함. /admin/common/** 매칭 + Spring 기본 인증으로 충분 (보수적 선택). SecurityConstants
     측 정합화 별도 결정 사이클 후보.
   · 클라이언트 path 갱신은 frontend 영역 (별도 진행).

2. resourceName 명시 박기 (RAG/KB 지식 변경/삭제 — service 진입 시 fileName 스냅샷):
   · 사유: KNOWLEDGE 폴백은 documents 단일 lookup 인데 (1) deleteKnowledgeDocument 의 soft delete 후 폴백
     NULL, (2) AGENT 폴백은 agentName 이라 RAG 파일 식별성 부족. service layer 진입 즉시 명시 박기로 일괄 해결.
   · AgentServiceImpl 3건 (#5/#6/#7) — AuditContext import 1줄 + AuditContext.resourceName(existing.getFileName())
     1줄씩 (updateDocument 변경 전 fileName / updateDocumentMetadata fileName 불변 / deleteDocument soft
     delete 직전 스냅샷).
   · KnowledgeBaseService 4건 (#9/#10/#11/#12) — 동일 패턴 (AuditContext import 기존 존재).
   · 매퍼 추가 0건 — service 코드가 이미 진입 직후 existing 레코드 조회 중이라 existing.getFileName() 재사용.
   · 등록 (#4 / #8) 점검 — 둘 다 컨트롤러에서 originalFilename 명시 박음, 추가 변경 없음.
   · 자동 폴백 매트릭스 (Aspect) 미수정 — 본 작업은 service layer 명시로만 해결.

3. PROMPT_TEMPLATE enum 신규 + 4단계 #2~#9 8건 부착 (A=(2) 결정):
   · A=(2) PROMPT_TEMPLATE enum 신규. PromptTemplate / PromptTag 단일 enum 통일 (별도 PROMPT_TAG 미도입,
     description 으로 "템플릿 ..." vs "태그 ..." 구분) — 후속 6번에서 TAG 분리로 정정됨.
   · DB:
     - dinai-db/migrations/016_audit_logs_add_prompt_template.sql 신규 (BEGIN/COMMIT + chk_audit_resource
       DROP/ADD 패턴) — 후속 7번에서 014 통합 + 016 파일 제거됨.
     - dinai-db/init/01_schema.sql 의 chk_audit_resource 동기.
   · ResourceType.java enum 카탈로그 14 → 15개 (PROMPT_TEMPLATE 추가, KNOWLEDGE 다음 SETTING 직전).
   · 컨트롤러 분리 인지 — AdminController → AdminCommonPromptController (`/admin/prompt-templates`) 5건 +
     AdminPromptTagController (`/admin/prompt-tags`) 3건.
   · 어노테이션 + resourceName 명시 패턴 (기존 service 의 entity lookup 재사용 — 매퍼 신규 추가 0건):
     - #2 createPromptTemplate: CREATE+PROMPT_TEMPLATE + 컨트롤러 resourceName(request.getTitle()) +
       resourceId(createdId).
     - #3 updatePromptTemplate / #4 updatePromptTemplateState / #5 deletePromptTemplate: service entry
       resourceName(existing.getTitle()).
     - #6 createPromptTag: CREATE + 컨트롤러 resourceName(request.tagName()) + resourceId(created.tagId()).
     - #7 updatePromptTag / #8 deletePromptTag: service entry resourceName(existing.tagName()).
     - #9 exportPromptTemplate: DOWNLOAD+FILE + 컨트롤러 resourceName("prompt-templates.xlsx"), PathVariable
       없음 → resourceId 없음.
   · PromptTemplateService 3건 (#3/#4/#5) + PromptTagService 2건 (#7/#8) service-side resourceName 박기.

4. PromptTemplate description "공통프롬프트 …" 통일 (운영자 비고 컬럼 일관성):
   · 사유: 클라이언트 비고 컬럼이 description 원본을 그대로 노출 — "어느 도메인의 어떤 동작" 한눈에 파악되도록
     description 자체에 도메인 명사 결합. "공통프롬프트" 표현은 Swagger Tag "공통 프롬프트 관리 APIs" + 사용자
     운영 표현 일치.
   · AdminCommonPromptController 5건 description 변경:
     - #2 "템플릿 등록" → "공통프롬프트 등록"
     - #3 (무라벨) → "공통프롬프트 수정"
     - #4 "상태 변경" → "공통프롬프트 상태 변경"
     - #5 (무라벨) → "공통프롬프트 삭제"
     - #9 "템플릿 export" → "공통프롬프트 다운로드"
   · resource enum / action enum / resourceId / resourceName / detail 변경 X — description 문자열 5건만 교체.
   · PromptTag (#6/#7/#8) description 그대로 유지 ("태그 등록/수정/삭제").

5. D 보류 풀 #11 활성 (getAdminPromptTags 태그 목록 조회 적재):
   · AdminPromptTagController.getAdminPromptTags: @AuditLog(READ, TAG, "태그 목록 조회") + AuditContext.detail
     ("count", result.getPageInfo().getTotalItems()) — totalItems 기준 (getAgentDocuments 동일 패턴).
   · resourceId 없음 (PathVariable 없음), resourceName 명시 X — 목록 조회라 단일 자원 식별자 부재. null
     PageInfo 가드 1줄 포함.
   · imports 변경 0건 — 잔존 메서드들이 이미 모두 사용 중.
   · D 보류 풀 #10 (getPromptTemplates) 도 후속 활성화 (다음 메모 블록 참조). 본 시점엔 미정 잔존.

6. TAG enum 분리 (PromptTag 도메인 PROMPT_TEMPLATE → TAG):
   · 사유: PromptTag 와 PromptTemplate 운영 도메인 분리 가시성 확보. 직전 결정 (단일 PROMPT_TEMPLATE 통일)
     정정. 화면 필터에서 resourceType=TAG / PROMPT_TEMPLATE 분리 노출 가능, 운영자가 태그 운영 흔적과
     공통프롬프트 운영 흔적 분리 추적 가능.
   · ResourceType.java enum — PROMPT_TEMPLATE("프롬프트 템플릿") 다음에 TAG("태그") 추가. 카탈로그 15 → 16개.
   · AdminPromptTagController 4건 resource enum 일괄 정정 (PROMPT_TEMPLATE → TAG): #6 createPromptTag, #7
     updatePromptTag, #8 deletePromptTag, #11 getAdminPromptTags. description 그대로.
   · AdminCommonPromptController 변경 없음 — PromptTemplate 5건 (#2/#3/#4/#5/#9) resource = PROMPT_TEMPLATE
     그대로, description "공통프롬프트 …" 그대로.
   · imports 변경 0건.

7. DB 014 + 016 통합 (016 파일 제거):
   · dinai-db/migrations/014_audit_logs_resource_name.sql 에 016 의 chk_audit_resource DROP/ADD 통합 + 'TAG'
     추가. 헤더 주석도 "(2) chk_audit_resource CHECK 제약 — PROMPT_TEMPLATE + TAG 추가" 로 갱신.
   · dinai-db/migrations/016_audit_logs_add_prompt_template.sql 파일 제거 — 014 단일 마이그레이션으로 통합.
   · init/01_schema.sql 의 chk_audit_resource enum 16개 동기.
   · 사용자 환경 적용 — 014 재실행 (idempotent, DROP/ADD 패턴): `docker exec -i <postgres-container> psql
     -U dba -d devdb -f /migrations/014_audit_logs_resource_name.sql` 또는 호스트 psql.

8. 클라이언트 측 변경 (frontend 에이전트 병렬 진행, 본 작업 범위 외 — 컨텍스트 보존):
   · entities/admin-log/model/types.ts — AuditResourceType union 16개 (PROMPT_TEMPLATE + TAG 추가).
   · entities/admin-log/lib/labels.ts — RESOURCE_LABEL: PROMPT_TEMPLATE = "공통프롬프트", TAG = "태그".
   · pages/admin/ui/LogMonitoringPage.tsx — AUDIT_RESOURCE_OPTIONS 두 옵션 추가.
   · ACTIVITY_MATRIX 변경 0건 (자동 fallback 활용 — RESOURCE_LABEL + ACTION_LABEL 결합).
   · getUsersWithRolesByDepartment path 갱신 (/authorities/... → /admin/common/...) — frontend 영역.

9. 진행 현황 (대시보드 line 14~23):
   · 0단계 5/5 ✅ · 1단계 5/5 ✅ · 2단계 5/5 ✅ · 3단계 14/14 (+1) ✅
   · 4단계 9/9 ✅ · 5단계 0/18 ⏳ · 6단계 ❌ 배제
   · D 보류 풀 10/11 ✅ (#7 ❌ 배제 1건 제외 전부 활성 — #10 후속 활성화로 마감 단계 진입)
   · 7단계 0/5 ⏳
   · 합계 44/65.

10. 잔여 (다음 세션):
    · 5단계 #1~#14 (Project/Chat/Agent 14건) + #15~#18 (MyPrompt 4건) 일괄 부착 — A 결정 완료 상태라 모두
      진입 가능. ProjectController / ChatController / AgentController / MyPromptController 4파일.
      MyPrompt 도 PROMPT_TEMPLATE 자원 사용 (TAG 분리는 PromptTag 한정). chatStream 의 EXECUTE+AGENT 시작
      시점 적재 (SSE 스트리밍 종료 무관) 주의.
    · D 보류 풀 마감 단계 — #10 활성으로 #7 배제 1건 제외 전부 활성. (다음 세션) 진입 시 추가 단순 조회
      후보 재검토 가능.
    · 7단계 라벨 매트릭스 동기화 (frontend ACTIVITY_MATRIX) — 본 세션 description 누적 약 24종:
      - UPDATE+AGENT 3종 ("활성 상태" / "정보 수정" / "범위 변경")
      - UPLOAD/UPDATE/DELETE+AGENT 4종 ("RAG 업로드/수정/메타데이터/삭제")
      - READ+AGENT 3종 ("개별 상태 조회" / "사용범위 조회" / "RAG 목록 조회")
      - UPLOAD/UPDATE/DELETE+KNOWLEDGE 5종 (KB 측)
      - CREATE/UPDATE+KNOWLEDGE 3종 ("지식부서 생성" / "지식 관리자 수정" / "설명 변경")
      - UPDATE+QUOTA 1종 ("부서 쿼터 변경") · READ+QUOTA 1종 ("부서 쿼터 상세 조회")
      - CREATE/UPDATE/DELETE+PROMPT_TEMPLATE 4종 ("공통프롬프트 등록/수정/상태 변경/삭제")
      - READ+PROMPT_TEMPLATE 1종 ("공통프롬프트 목록 조회")
      - DOWNLOAD+FILE 1종 ("공통프롬프트 다운로드")
      - CREATE/UPDATE/DELETE/READ+TAG 4종 ("태그 등록/수정/삭제/목록 조회")
    · 014 마이그레이션 적용 (TAG 포함) — 사용자 환경 PowerShell 에서 docker exec 또는 호스트 psql.
    · UserLoginFailureTxService.insertAuditLog logType enum 정합화 (별도 사이클).
    · 화면 시각 검증 — make bounce-core 후 resourceType 필터 분리 (AGENT / KNOWLEDGE / PROMPT_TEMPLATE /
      TAG / QUOTA / FILE) 동작 확인.

2026-05-04 — D 보류 풀 #10 활성 (getPromptTemplates 공통프롬프트 목록 조회 적재 → D 보류 풀 마감 단계):
  · 사유: 사용자 화면 검증에서 누락 발견 + 결정 활성화. PromptTag 측 #11 (getAdminPromptTags) 만 활성된
    상태에서 PromptTemplate 측 목록 조회가 미적재면 운영자 시야 비대칭 — 양쪽 도메인 동일 패턴 통일.
  · AdminCommonPromptController.getPromptTemplates: @AuditLog(READ, PROMPT_TEMPLATE, "공통프롬프트 목록 조회")
    + AuditContext.detail("count", response.getPageInfo().getTotalItems()) — totalItems 기준 (#11
    getAdminPromptTags 동일 패턴, 페이지 size 보다 운영자 시야 유용).
  · resourceId 없음 (PathVariable 없음, 목록 조회 단일 자원 식별자 부재 자연스러움), resourceName 명시 X.
    null PageInfo 가드 1줄 포함.
  · description "공통프롬프트 목록 조회" — PromptTemplate 도메인의 기존 description ("공통프롬프트 등록/수정/
    상태 변경/삭제/다운로드") 와 어휘 일치. resource = PROMPT_TEMPLATE 통일.
  · imports 변경 0건 — AuditLog / AuditActionType / ResourceType / AuditContext 모두 잔존 메서드 사용 중.
  · D 보류 풀 진행도 9/11 → 10/11 (#7 배제 1건 제외 전부 활성). 합계 43/65 → 44/65.
  · ./gradlew compileJava BUILD SUCCESSFUL (JDK 21, --rerun-tasks).
  · 7단계 라벨 매트릭스 추가 대상 (frontend) — READ+PROMPT_TEMPLATE description "공통프롬프트 목록 조회"
    1종 (잔여 description 누적 합 25종).
```
