# 활동 로그 설계 문서

> 대상: `dinai-core-api` / `dinai-db`
> 한 줄 요약: 컨트롤러 메서드에 `@AuditLog` 한 줄만 붙이면, 비동기로 `dinai.audit_logs` 테이블에 누가·언제·뭘 했는지 자동으로 남는다.

---

## 1. 이 문서가 다루는 것

이 시스템에는 두 종류의 로그가 있다.

| 로그 | 주제 | 예시 |
|---|---|---|
| **접속 로그** (`access_logs`) | 로그인/로그아웃, 세션 만료 같은 **인증 이벤트** | "홍길동, 2026-04-30 11:00 로그인" |
| **활동 로그** (`audit_logs`) | 로그인 후 사용자가 **실제로 한 행동** | "홍길동, 공지사항 #12 등록", "관리자가 권한 부여" |

이 문서는 **활동 로그**만 다룬다. 접속 로그는 별도 문서.

활동 로그가 다루는 것은 한 줄로:

> "**누가** (사번/부서) — **언제** — **뭘** (활동유형 × 리소스) — **결과는** (성공/실패) — **어디서** (IP/세션) — **왜 실패했는지** (에러 코드)"

이 정보를 **컨트롤러 메서드에 어노테이션 한 줄** 붙이면 자동으로 적재한다. 개발자가 매번 `auditLogMapper.insert(...)` 같은 코드를 짤 필요가 없다.

---

## 2. 핵심 원칙 (왜 이렇게 설계했나)

| 원칙 | 무슨 뜻 |
|---|---|
| **활동유형은 8개로 고정** | CREATE/READ/UPDATE/DELETE + UPLOAD/DOWNLOAD/EXTRACT/EXECUTE. 무한정 늘리지 않는다. |
| **의미는 "활동유형 × 리소스" 조합으로** | "공지사항 등록", "권한 부여" 같은 26가지 라벨을 따로 만들지 않고, `(CREATE, NOTICE)` 조합이 자동으로 그렇게 표시된다. |
| **카테고리는 자동 결정** | USER/ADMIN/SYSTEM. 어노테이션에 명시하지 않고, **요청 URI**를 보고 Aspect가 알아서 정한다. |
| **어노테이션은 짧게** | 평소엔 `@AuditLog(action=CREATE, resource=NOTICE)` 두 필드면 끝. 추가 정보가 필요한 경우만 `AuditContext` 한 줄. |
| **자동 추출** | resourceId는 메서드 시그니처를 보고 자동으로 채운다. 컨트롤러에서 일일이 박을 필요 없다. |
| **적재 실패는 무시** | 활동 로그 INSERT가 실패해도 비즈니스 응답에는 영향 없다 (fire-and-forget). |
| **비즈니스 예외는 그대로 던진다** | Aspect는 finally에서 기록만 하고, 잡은 예외를 다시 throw해 ControllerAdvice가 받게 한다. |
| **별도 트랜잭션** | `REQUIRES_NEW` — 비즈니스 트랜잭션이 롤백돼도 활동 로그는 남는다. |

---

## 3. 활동 = (활동유형 × 리소스 타입)

### 3-1. 활동유형 8개

데이터베이스 스타일로 4개 + 도메인 행위 4개.

| 코드 | 한글 | 언제 |
|---|---|---|
| `CREATE` | 등록 | 새 리소스 생성 |
| `READ` | 조회 | 목록·상세 조회 |
| `UPDATE` | 수정 | 기존 리소스 변경 |
| `DELETE` | 삭제 | 리소스 삭제 |
| `UPLOAD` | 업로드 | 파일 업로드 |
| `DOWNLOAD` | 다운로드 | 파일 다운로드 |
| `EXTRACT` | 추출 | 검색 결과 추출 / Excel 내보내기 / RAG 검색 |
| `EXECUTE` | 실행 | 에이전트 실행 / 배포 / 일회성 작업 |

> 자동 만료(EXPIRE)나 시스템 배치 같은 건 **접속 로그** 쪽에서 처리한다. 활동 로그는 사용자 행위에만 집중.

### 3-2. 리소스 타입 14개

| 코드 | 한글 |
|---|---|
| `NOTICE` | 공지사항 |
| `PERMISSION` | 권한 |
| `USER` | 사용자 |
| `DEPT` | 부서 |
| `PROJECT` | 프로젝트 |
| `POST` | 게시글 |
| `FILE` | 파일 |
| `CONVERSATION` | 대화 |
| `AGENT` | 에이전트 |
| `KNOWLEDGE` | 지식 |
| `SETTING` | 설정 |
| `QUOTA` | 사용량 |
| `DEPLOY` | 배포 |
| `ACCOUNT` | 계정 |

### 3-3. 화면에 표시되는 라벨은 어떻게 만들어지나

`(CREATE, NOTICE)` 같은 조합을 화면에서는 **자연어**로 보여준다. 결정 순서는:

1. 어노테이션의 `description` 값이 있으면 그대로 사용 (예: `"비밀번호 변경"`, `"계정 잠금"`)
2. **`READ`인 경우** — `resource_id` 유무로 자동 분기:
   - `resource_id`가 있으면 `"{리소스} 상세조회"` (예: `(READ, NOTICE, id=1)` → "공지사항 상세조회")
   - `resource_id`가 없으면 `"{리소스} 조회"` (예: `(READ, NOTICE, id=null)` → "공지사항 조회")
3. 매트릭스에 정의된 조합이면 그 라벨 — 예: `(CREATE, NOTICE)` → "공지사항 등록"
4. 매트릭스에 없으면 **리소스 한글 + 활동유형 한글** 자동 조립 — 예: `(CREATE, DEPT)` → "부서 등록"

> READ는 `GET /notices` (목록)과 `GET /notices/{id}` (단건 상세)가 같은 활동유형을 공유한다. 화면에서 둘을 구분해 보여주기 위해 `resource_id` 유무로 라벨을 자동 분기한다 — 컨트롤러에서 별도 표시 없이도 자연스럽게 분리됨.

화면에는 활동타입 컬럼과 비고 컬럼이 나뉘어 표시된다.

| 컬럼 | 표시 내용 | 예시 |
|---|---|---|
| **활동타입** | 활동유형의 한글 라벨만 | "수정" |
| **리소스** | 리소스 + 축약 ID (hover 시 전체) | "공지사항 (12)", "사용자 (7a8b9c0d…)" |
| **비고** | 매트릭스 라벨 + count(있으면) | "공지사항 수정 (첨부 3개)" |

> **리소스 ID 표시 규칙** — 목록 셀 가독성을 위해 `resourceId`를 축약한다. UUID(36자) → 첫 8자 + ellipsis (`7a8b9c0d…`), 그 외 13자 이상 → 첫 12자 + ellipsis. 12자 이하 짧은 ID(BIGSERIAL 등)는 그대로. 셀에 마우스 hover 시 `title` 속성으로 전체 ID 노출. 상세 모달은 항상 원본 표시.

비고에 붙는 단위(unit)는 활동 종류에 따라 다르다 (목록 SQL의 `extra_data.count` 활용).

| 케이스 | 단위 | 예시 |
|---|---|---|
| `UPLOAD` + `FILE` | "파일 N개" | "파일 업로드 (파일 3개)" |
| `CREATE`/`UPDATE` + `NOTICE`/`POST` | "첨부 N개" | "공지사항 수정 (첨부 3개)" |
| `READ` / `EXTRACT` | "N건" | "공지사항 조회 (12건)" |
| `CREATE` + `KNOWLEDGE` | "N 청크" | "지식 등록 (128 청크)" |

### 3-4. 매트릭스 (자연어 라벨 정의)

`READ`는 매트릭스에 두지 않는다 — 위 3-3의 자동 분기로 `"{리소스} 조회"` / `"{리소스} 상세조회"`가 모든 리소스에 대해 일관되게 생성된다.

| action | resource | 화면 표시 |
|---|---|---|
| CREATE | NOTICE | 공지사항 등록 |
| UPDATE | NOTICE | 공지사항 수정 |
| DELETE | NOTICE | 공지사항 삭제 |
| DOWNLOAD | NOTICE | 공지사항 첨부 다운로드 |
| CREATE | PERMISSION | 권한 부여 |
| DELETE | PERMISSION | 권한 회수 |
| UPDATE | PERMISSION | 권한 변경 |
| UPDATE | USER | 사용자 수정 |
| UPLOAD | FILE | 파일 업로드 |
| DOWNLOAD | FILE | 파일 다운로드 |
| DELETE | FILE | 파일 삭제 |
| CREATE | CONVERSATION | AI 대화 시작 |
| EXECUTE | AGENT | 에이전트 실행 |
| EXTRACT | KNOWLEDGE | 지식 검색 |
| CREATE | KNOWLEDGE | 지식 등록 |
| UPDATE | SETTING | 설정 변경 |
| UPDATE | QUOTA | 사용량 변경 |
| EXECUTE | DEPLOY | 배포 |
| CREATE | PROJECT | 프로젝트 생성 |
| DELETE | PROJECT | 프로젝트 삭제 |
| CREATE | POST | 게시글 등록 |
| UPDATE | POST | 게시글 수정 |
| DELETE | POST | 게시글 삭제 |

`(UPDATE, ACCOUNT)` 처럼 같은 조합인데 의미가 다른 경우(비밀번호 변경 vs 계정 잠금)는 어노테이션에 `description`을 명시해서 구분한다.

---

## 4. 카테고리 (USER / ADMIN / SYSTEM) 자동 결정

| 코드 | 의미 | 어떻게 정해지나 |
|---|---|---|
| `USER` | 일반 사용자 활동 | HTTP 요청이 있고, URI가 `/admin/...`로 시작하지 않음 |
| `ADMIN` | 관리자 활동 | HTTP 요청이 있고, URI가 `/admin/**` 또는 `/api/admin/**`로 시작 |
| `SYSTEM` | 시스템 호출 | `AuditLogService.recordSystem()`으로 직접 적재 (배치/CI 등) |

요점:
- USER / ADMIN은 **Aspect가 URI만 보고** 알아서 정한다. 어노테이션에 명시할 필요 없음.
- SYSTEM은 별도 진입점(`recordSystem`)에서만 들어온다.
- 위 어디에도 안 맞는 경우(요청 컨텍스트 없는 비-시스템 호출)는 `null`로 적재.

---

## 5. enum 정의

```java
public enum AuditCategory {
    USER, ADMIN, SYSTEM
}

public enum AuditActionType {
    CREATE, READ, UPDATE, DELETE,
    UPLOAD, DOWNLOAD, EXTRACT, EXECUTE
}

public enum ResourceType {
    NOTICE, PERMISSION, USER, DEPT,
    PROJECT, POST, FILE,
    CONVERSATION, AGENT, KNOWLEDGE,
    SETTING, QUOTA, DEPLOY, ACCOUNT
}
```

> `AuditActionType`에는 카테고리 매핑(`getCategory()` 같은 헬퍼) **없다**. 카테고리는 URI/진입점으로 결정되는 정보지 활동유형의 속성이 아니다.

---

## 6. 어노테이션 한 장 요약

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface AuditLog {

    /** 활동유형 (필수) */
    AuditActionType action();

    /** 리소스 타입 (필수) */
    ResourceType resource();

    /** 화면 라벨을 매트릭스 대신 직접 지정하고 싶을 때만 */
    String description() default "";

    /** resourceId로 쓸 PathVariable 이름 — 비우면 마지막 PathVariable이 자동으로 선택됨 */
    String pathVar() default "";

    /** 실패한 케이스만 기록하고 싶을 때 */
    boolean onFailureOnly() default false;
}
```

**기본 사용**:
```java
@AuditLog(action = CREATE, resource = NOTICE)
```
이 한 줄이 끝. category는 자동, resourceId는 자동, 사용자/IP/세션도 자동.

**언제 추가 필드가 필요한가**:
- `description` — 매트릭스 라벨로 의미 구분이 안 될 때 (비밀번호 변경 vs 계정 잠금)
- `pathVar` — 다단 경로(`/users/{userId}/permissions/{permId}`)에서 마지막 변수가 대상이 아닐 때
- `onFailureOnly` — 실패만 기록하고 싶을 때

---

## 7. 전체 흐름 (요청 한 번이 들어올 때)

```
[HTTP 요청]
   ↓
[Spring Security Filter] — JWT 검증, sessionId를 request attribute에 넣음
   ↓
[DispatcherServlet] → [컨트롤러 메서드 (@AuditLog 부착)]
   ↓
[AuditLogAspect.@Around] — ThreadLocal(AuditContext) 초기화
   ↓
   [컨트롤러 본문 실행]
       - 필요하면 AuditContext.detail("count", N) 같은 한 줄로 추가 정보 적재
       - 서비스 호출 → 비즈니스 트랜잭션 커밋 (또는 롤백)
   ↓
   결과 마킹 (성공이면 SUCCESS, 예외면 FAILURE + 에러 코드)
   ↓
   AuditLogCommand 조립 (사용자/IP/카테고리/resourceId 자동 채움)
   ↓
   auditLogService.record(cmd)  ── @Async + REQUIRES_NEW ──→  INSERT audit_logs
                                                              (별도 트랜잭션, 별도 스레드)
   ↓
   AuditContext.clear()  (ThreadLocal 정리)
   ↓
   예외가 있었다면 그대로 throw → ControllerAdvice가 응답 변환
```

---

## 8. 사용자 입장에서 본 적재 흐름

개발자가 컨트롤러 메서드에 어노테이션을 붙인 후, 사용자가 한 번 요청을 보낼 때:

1. Aspect가 메서드 시작 직전에 ThreadLocal을 비워두고 컨트롤러 본문을 실행한다.
2. 본문이 끝나면 (정상이든 예외든) Aspect가 자동으로:
   - 누가 호출했는지 (JWT principal에서 사번/부서)
   - 어디서 호출했는지 (X-Forwarded-For 우선 IP, JWT의 session_id, MDC의 traceId)
   - URI를 보고 카테고리(USER/ADMIN) 결정
   - 메서드 시그니처를 보고 resourceId 추출
   - AuditContext에 컨트롤러가 추가로 박은 값(count, parentResource 등) 머지
   - 결과(SUCCESS/FAILURE)와 에러 코드(있으면) 결합
3. 위를 묶어서 `AuditLogService.record(cmd)`로 보낸다.
4. 그 메서드는 `@Async`라 호출자(컨트롤러)는 즉시 리턴, 별도 스레드에서 INSERT.
5. INSERT가 실패해도 사용자 응답에는 영향 없음 (try/catch로 흡수).

---

## 9. 자동 추출 — resourceId

`resourceId` 컬럼만 자동 추출한다. (description은 어노테이션 고정, extra_data는 명시 적재)

**우선순위**:

| # | 규칙 | 예 |
|---|---|---|
| 1 | 컨트롤러가 `AuditContext.resourceId(...)` 호출했으면 그 값 | `AuditContext.resourceId(String.valueOf(id))` |
| 2 | 어노테이션에 `pathVar="..."` 명시했으면 해당 PathVariable | `@AuditLog(..., pathVar="permId")` |
| 3 | 메서드의 **마지막** `@PathVariable` 값 | `/users/{userId}/permissions/{permId}` → `permId` |
| 4 | 리턴 객체에 `getId()` 메서드가 있으면 그 값 (CREATE 계열) | `return new NoticeResponse(id, ...)` |
| 5 | 위 모두 안 되면 `null` |

**왜 "마지막 PathVariable"이 기본인가**:
다단 경로 `/users/{userId}/permissions/{permId}`에서 첫 변수(userId)가 자동으로 잡히면 부모 ID가 적재되어 잘못된 자원으로 기록된다. 보통은 마지막 변수가 실제 대상이라 그걸 기본값으로 둔다. 예외 케이스에선 `pathVar`로 명시.

---

## 10. AuditContext — 컨트롤러에서 추가 정보를 한 줄로 박는 헬퍼

ThreadLocal 기반의 fluent API. Aspect가 finally에서 자동으로 `clear()`해주므로 누수 걱정 없음.

```java
public final class AuditContext {

    /** extra_data에 키 한 개 추가 (같은 키면 덮어씀) */
    public static AuditContextChain detail(String key, Object value);

    /** resourceId를 직접 지정 (자동 추출 결과를 덮어씀) */
    public static AuditContextChain resourceId(String id);

    /** 비고에 추가 메시지를 한 줄로 (description이랑 합쳐짐) */
    public static AuditContextChain message(String msg);

    /** 예외 없이 비즈니스적 실패로 기록하고 싶을 때 */
    public static AuditContextChain markFailure(String reason);

    /** 부모/연관 리소스 정보 — extra_data.context로 적재됨 */
    public static AuditContextChain parentResource(ResourceType type, String id);
    public static AuditContextChain parentResource(ResourceType type, String id, String name);
}
```

**parentResource로 박으면 extra_data에 이렇게 들어간다**:
```json
{ "context": { "type": "CONVERSATION", "id": "C-7777" } }
```

---

## 11. 흔한 사용 예시

### 11-1. 단순 CRUD

```java
@PostMapping("/notices")
@AuditLog(action = CREATE, resource = NOTICE)
public NoticeResponse create(@RequestBody NoticeCreateRequest req) {
    return noticeService.create(req);
}

@PutMapping("/notices/{id}")
@AuditLog(action = UPDATE, resource = NOTICE)
public NoticeResponse update(@PathVariable Long id, @RequestBody NoticeUpdateRequest req) {
    return noticeService.update(id, req);
}

@DeleteMapping("/notices/{id}")
@AuditLog(action = DELETE, resource = NOTICE)
public void delete(@PathVariable Long id) {
    noticeService.delete(id);
}

@GetMapping("/notices")
@AuditLog(action = READ, resource = NOTICE)
public PagedResponse<NoticeResponse> list(NoticeSearchRequest req) {
    PagedResponse<NoticeResponse> res = noticeService.list(req);
    AuditContext.detail("count", res.getTotalCount());     // 비고에 "공지사항 조회 (12건)" 표시
    return res;
}
```

### 11-2. 첨부파일이 같이 오는 경우 (1요청 = 1 row)

여러 파일을 같이 올려도 row는 하나만 적재. 갯수만 비고에 결합되도록 `count`만 박음.

```java
// 공지사항 등록 + 첨부파일
@PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
@AuditLog(action = CREATE, resource = NOTICE)
public CreatedResponse createNotice(@Valid @ModelAttribute NoticeCreateRequest req) {
    Long id = noticeService.createNotice(req);
    AuditContext.resourceId(String.valueOf(id))
                .detail("count", req.getFiles() == null ? 0 : req.getFiles().size());
    return CreatedResponse.of(id);
}
```

→ 비고 = "공지사항 등록 (첨부 3개)"

### 11-3. 게시글/채팅 첨부 같은 부모 리소스가 명확한 케이스

```java
@PostMapping("/posts/{postId}/files")
@AuditLog(action = UPLOAD, resource = FILE)
public BatchFileResponse uploadForPost(
        @PathVariable String postId,
        @RequestParam MultipartFile[] files) {

    AuditContext.parentResource(ResourceType.POST, postId)
                .detail("count", files.length);
    return fileService.uploadMany(postId, files);
}
```

→ 비고 = "파일 업로드 (파일 3개)", extra_data = `{"count":3, "context":{"type":"POST","id":"..."}}`

### 11-4. 관리자 영역 (URI prefix만으로 카테고리 자동)

```java
// URI가 /api/admin/... 라서 category=ADMIN 자동
@PostMapping("/api/admin/system/users/{userId}/permissions")
@AuditLog(action = CREATE, resource = PERMISSION)
public void grant(@PathVariable String userId, @RequestBody PermissionRequest req) {
    permissionService.grant(userId, req);
}

@DeleteMapping("/api/admin/system/users/{userId}/permissions/{permId}")
@AuditLog(action = DELETE, resource = PERMISSION, pathVar = "permId")
//                                                ^^^^^^^^^^^^^^^^^
//                                                userId가 첫 PathVariable이라 마지막인 permId를 명시
public void revoke(@PathVariable String userId, @PathVariable String permId) {
    permissionService.revoke(userId, permId);
}
```

### 11-5. 같은 조합인데 의미가 다른 경우 (description으로 구분)

```java
// 비밀번호 변경 — UPDATE + ACCOUNT
@PutMapping("/me/password")
@AuditLog(action = UPDATE, resource = ACCOUNT, description = "비밀번호 변경")
public void changePassword(@RequestBody PasswordChangeRequest req) { ... }

// 계정 잠금 — 같은 UPDATE + ACCOUNT 인데 다른 의미
@PostMapping("/api/admin/system/users/{userId}/lock")
@AuditLog(action = UPDATE, resource = ACCOUNT, description = "계정 잠금")
public void lock(@PathVariable String userId, @RequestBody LockRequest req) { ... }
```

---

## 12. 실패 처리

### 12-1. 두 가지 경로

**(A) 컨트롤러가 예외를 던졌을 때** — 자동으로 처리됨. Aspect가 catch해서 `result=FAILURE`로 마킹하고, 예외를 시스템 `ErrorCode` 이름으로 정규화해 `error_message`에 적재. 그리고 그 예외를 그대로 다시 throw해 `GlobalExceptionHandler`가 받게 함.

**(B) 컨트롤러가 200 OK로 정상 리턴했지만 비즈니스적으로는 실패** — 컨트롤러가 직접 `AuditContext.markFailure("CODE")`를 호출. (멱등 처리/부분 성공 같은 케이스)

### 12-2. 에러 코드 정책 — 시스템 ErrorCode 직접 사용

`audit_logs.error_message`에는 **별도 카탈로그 없이 시스템 `ErrorCode.name()`을 그대로 적재**한다 (예: `RES_NOT_FOUND`, `PERM_DENIED`, `RULE_CONCURRENCY_CONFLICT`).

**왜 별도 카탈로그를 두지 않나**:
- 시스템에 이미 `com.hiaas.ai.platform.common.errors.ErrorCode`가 SCREAMING_SNAKE_CASE로 정규화되어 있음
- `GlobalExceptionHandler`가 모든 Spring 예외도 `ErrorCode`로 변환해 응답에 박음 → 응답 코드와 audit_logs 코드를 같은 체계로 통일 가능
- 별도 카탈로그를 두면 `USER_NOT_FOUND` / `AGENT_NOT_FOUND` 같은 의미가 `RESOURCE_NOT_FOUND`로 묶여 정보 손실 + 매핑 유지 부담만 늘어남

DB에는 코드값(`PERM_DENIED`)만 적재. 원문 메시지/스택트레이스/PII는 절대 적재하지 않음. 화면에서 한글 라벨 변환은 프론트의 `ERROR_CODE_LABEL`에서 처리.

### 12-3. ErrorMessageResolver 매핑

```java
public String resolve(Throwable t) {
    if (t == null) return null;

    // 도메인/인프라 예외는 자체 코드(ErrorCode.name())를 그대로 사용
    if (t instanceof DomainException de) return de.getCode();
    if (t instanceof InfrastructureError ie) return ie.getCode();

    // Spring 표준 예외 — GlobalExceptionHandler와 동일 ErrorCode로 정규화
    if (t instanceof AccessDeniedException) return "PERM_DENIED";
    if (t instanceof AuthenticationException) return "AUTH_TOKEN_INVALID";
    if (t instanceof MethodArgumentNotValidException
            || t instanceof BindException) return "VAL_VALIDATION_FAILED";
    if (t instanceof DataIntegrityViolationException) return "RES_DUPLICATE_ENTRY";
    if (t instanceof RestClientException
            || t instanceof WebClientException) return "NET_UPSTREAM_FAILURE";

    return "SYS_INTERNAL_ERROR";
}
```

Spring 표준 예외의 ErrorCode 매핑은 `GlobalExceptionHandler`와 **반드시 일치**시킨다 — 응답에 박는 코드와 audit_logs에 적재되는 코드가 같은 ErrorCode를 가리켜야 운영 디버깅 일관성이 유지됨. 새 ErrorCode가 추가되거나 매핑이 바뀌면 양쪽 모두 동기화 필요.

### 12-4. markFailure 사용 — 언제 쓰고 언제 안 쓰나

**예외를 던질 거면 `markFailure`는 부르지 마라.** Aspect가 알아서 잡는다. 중복 호출이고 가독성만 떨어진다.

**쓰는 경우**: 200 OK로 응답하면서 결과 본문에 "스킵/실패/무시" 정보를 담아 보내는 케이스.

```java
@PostMapping("/agents/{id}/execute")
@AuditLog(action = EXECUTE, resource = AGENT)
public AgentResult execute(@PathVariable String id, @RequestBody AgentInput input) {
    AgentResult result = agentService.execute(id, input);
    // 외부 LLM이 거절했지만, 클라이언트에는 200 OK + 안내 메시지로 응답
    if (result.isRejectedByLlm()) {
        AuditContext.markFailure("EXTERNAL_API_ERROR");
    }
    return result;
}
```

→ HTTP 응답은 200, 활동 로그는 `result=FAILURE / error_message=EXTERNAL_API_ERROR`.

---

## 13. DB 테이블

### 13-1. 정의

마이그레이션 파일은 `dinai-db/migrations/013_audit_logs_align_with_design.sql` 한 개로 정합화 완료 (컬럼 rename + 비정규화/필터 컬럼 추가 + access_path NOT NULL + CHECK·인덱스 정의).

```sql
CREATE TABLE dinai.audit_logs (
    id            uuid PRIMARY KEY NOT NULL,
    employee_id   varchar NOT NULL,            -- 사용자 표시명은 015 비정규화 username 컬럼에서 직접 노출
    username      varchar(50),                 -- 적재 시점 dinai.users.username 스냅샷 (015)
    dept_code     varchar NOT NULL,            -- dinai.dept.dept_code 비정규화 스냅샷
    log_type      varchar(30) NOT NULL,        -- CREATE/READ/UPDATE/DELETE/UPLOAD/DOWNLOAD/EXTRACT/EXECUTE
    resource_type varchar(30),
    resource_id   varchar(100),
    result        varchar(10) NOT NULL,        -- SUCCESS/FAILURE
    ip_address    varchar(45) NOT NULL,
    user_agent    varchar(500),
    session_id    varchar(100),                -- JWT의 session_id claim
    trace_id      varchar(100),                -- W3C trace context
    error_message text,                        -- 실패 사유 코드 (카탈로그 12-2)
    extra_data    jsonb,                       -- count / context 표준 키
    created_at    timestamptz NOT NULL,
    -- 014에서 nullable 추가
    category      varchar(10),                 -- USER/ADMIN/SYSTEM
    description   text,                        -- 화면 라벨 오버라이드
    CONSTRAINT chk_audit_category CHECK (category IS NULL OR category IN ('USER','ADMIN','SYSTEM')),
    CONSTRAINT chk_audit_log_type CHECK (log_type IN
        ('CREATE','READ','UPDATE','DELETE','UPLOAD','DOWNLOAD','EXTRACT','EXECUTE')),
    CONSTRAINT chk_audit_resource CHECK (resource_type IS NULL OR resource_type IN
        ('NOTICE','PERMISSION','USER','DEPT','PROJECT','POST','FILE',
         'CONVERSATION','AGENT','KNOWLEDGE','SETTING','QUOTA','DEPLOY','ACCOUNT')),
    CONSTRAINT chk_audit_result   CHECK (result IN ('SUCCESS','FAILURE'))
);
```

### 13-2. 컬럼 한 줄 설명

| 컬럼 | NULL | 한 줄 설명 |
|---|---|---|
| `id` | NO | `UUID.randomUUID()` |
| `employee_id` | NO | 사번. 시스템 호출 시 `"SYSTEM"` |
| `username` | YES | 적재 시점 사용자 표시명 스냅샷(`dinai.users.username`). 시스템 호출 시 `"SYSTEM"` |
| `dept_code` | NO | 부서코드(`dinai.dept.dept_code`). 시스템 호출 시 `"SYSTEM"` |
| `log_type` | NO | 활동유형 enum. 어노테이션 `action()` 그대로 |
| `resource_type` | YES | 리소스 enum |
| `resource_id` | YES | 단건 리소스 식별자 |
| `result` | NO | `SUCCESS` / `FAILURE` (access_logs와 동일 컨벤션) |
| `ip_address` | NO | X-Forwarded-For 우선, 시스템은 `0.0.0.0` |
| `access_path` | **NO** | `WEB` / `MOBILE` / `API` (CHECK 강제). Aspect가 X-Client-Type 헤더 + User-Agent 휴리스틱으로 결정, 미상이면 `WEB` 기본값. 시스템 호출은 `API` |
| `user_agent` | YES | User-Agent 헤더 (500자 절단) |
| `session_id` | YES | JWT의 `session_id` claim. `JwtAuthenticationFilter`가 request attribute에 propagate |
| `trace_id` | YES | W3C trace context (MDC에서 추출). 분산 추적용 |
| `error_message` | YES | 실패 시만. 카탈로그 코드값 (PII 미포함) |
| `extra_data` | YES | JSONB. 표준 키 `count`(number), `context`(object) |
| `created_at` | NO | 적재 시각 (UTC) |
| `category` | YES | USER/ADMIN/SYSTEM. Aspect가 URI로 자동 결정. 컨텍스트 없으면 `null` |
| `description` | YES | 화면 라벨 오버라이드 |

### 13-3. NOT NULL 채움 책임 (구현 가드용)

`AuditLogAspect.buildCommand`가 **반드시** 채워야 하는 컬럼:

| 컬럼 | 출처 | 미해결 시 |
|---|---|---|
| `id` | `UUID.randomUUID().toString()` | — |
| `employee_id` | JWT principal 추출 | `"UNKNOWN"` (시스템: `"SYSTEM"`) |
| `dept_code` | JWT claim 추출 | `"UNKNOWN"` (시스템: `"SYSTEM"`) |
| `log_type` | `annotation.action().name()` | — |
| `result` | proceed 정상/예외 분기 | — |
| `ip_address` | `clientInfo.extractIp(req)` | `"0.0.0.0"` |
| `access_path` | `ClientInfoExtractor.accessPath(req)` (X-Client-Type / User-Agent 휴리스틱) | `"WEB"` (기본값, 절대 null 반환 X) |
| `created_at` | `OffsetDateTime.now()` | — |

위 8개를 단위 테스트로 매번 검증. 누락 시 `INSERT NOT NULL` 위반으로 적재가 조용히 유실됨 (fire-and-forget이라 에러도 안 남음) — **반드시 테스트로 가드**.

### 13-4. extra_data 표준 키

대부분 활동은 `extra_data = NULL`. 비고에 카운트가 필요하거나 부모 리소스를 표시할 활동만 적재.

| 키 | 타입 | 사용 활동 | 의미 | 화면 unit |
|---|---|---|---|---|
| `count` | number | UPLOAD + FILE, CREATE + NOTICE/POST | 업로드/등록 시 첨부 파일 수 | "파일 N개" / "첨부 N개" |
| `count` | number | READ, EXTRACT | 결과 건수 | "N건" |
| `count` | number | CREATE + KNOWLEDGE | 청크 수 | "N 청크" |
| `addedCount` | number | UPDATE + NOTICE/POST | 새로 추가된 첨부 파일 수 | "(첨부 +N / -M)" |
| `removedCount` | number | UPDATE + NOTICE/POST | 삭제된 첨부 파일 수 | "(첨부 +N / -M)" |
| `addedFiles` | string[] | UPDATE + NOTICE/POST | 추가된 파일명 리스트 (상세 모달 노출용) | — |
| `removedFiles` | string[] | UPDATE + NOTICE/POST | 삭제된 파일명 리스트 (상세 모달 노출용) | — |
| `fileName` | string | DOWNLOAD/DELETE + FILE/NOTICE | 사용자가 다운/삭제한 파일명 (PII 아님) | "notice.pdf" (라벨 없이 단독) |
| `context.type` | string | UPLOAD/DOWNLOAD/DELETE + FILE | 부모 ResourceType | — |
| `context.id` | string | 위 동일 | 부모 리소스 ID | — |

**카탈로그 외 키는 적재하지 않음**. 파일 size/MIME/메타데이터 등은 파일 관리 시스템에서 별도 추적 (활동 로그는 PII/민감 정보 노출 위험을 최소화하기 위해 keys를 좁게 유지).

### 13-5. 인덱스

```sql
CREATE INDEX idx_audit_emp_created      ON dinai.audit_logs (employee_id, created_at DESC);
CREATE INDEX idx_audit_dept_created     ON dinai.audit_logs (dept_code, created_at DESC);
CREATE INDEX idx_audit_log_type_created ON dinai.audit_logs (log_type, created_at DESC);
CREATE INDEX idx_audit_resource         ON dinai.audit_logs (resource_type, resource_id);
CREATE INDEX idx_audit_created          ON dinai.audit_logs (created_at DESC);
CREATE INDEX idx_audit_category_created ON dinai.audit_logs (category, created_at DESC);
```

**보관 정책**: 영구 보관. 자동 이관/삭제 없음. 파일/대화 등 외부 리소스의 만료는 해당 도메인에서 별도 관리.

---

## 14. Aspect 내부 구현

전체는 메서드 두 개로 끝난다:
- `around(...)` — 컨트롤러 메서드를 감싸고 finally에서 한 번 적재
- `buildCommand(...)` — 적재할 DTO 조립

```java
@Aspect
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)   // @Transactional 바깥에서 동작 → 커밋/롤백 결과 확정 후 기록
@RequiredArgsConstructor
@Slf4j
public class AuditLogAspect {

    private final AuditLogService auditLogService;
    private final ClientInfoExtractor clientInfo;        // X-Forwarded-For / User-Agent (access_logs와 공유)
    private final ErrorMessageResolver errorResolver;    // 예외 → 12-2 에러 코드 매핑
    private final AuditDetailExtractor detailExtractor;  // resourceId 자동 추출
    private final ObjectMapper objectMapper;             // extra_data JSON 직렬화

    @Around("@annotation(annotation)")
    public Object around(ProceedingJoinPoint pjp, AuditLog annotation) throws Throwable {
        // [1] ThreadLocal 초기화 — 컨트롤러 본문에서 AuditContext.detail(...) 등 적재할 자리
        AuditContext.init();

        String result = "SUCCESS";
        String errorMessage = null;
        Object returnValue = null;
        Throwable thrown = null;          // onFailureOnly 분기용

        try {
            // [2] 컨트롤러 본문 실제 실행
            returnValue = pjp.proceed();
            return returnValue;
        } catch (Throwable e) {
            // [3] 예외 발생 — 결과 마킹 + 코드 변환 후 그대로 다시 throw
            result = "FAILURE";
            errorMessage = errorResolver.resolve(e);
            thrown = e;
            throw e;
        } finally {
            // [4] 정상/예외 어느 경로든 여기 한 번 — 로그 적재 시도
            try {
                if (annotation.onFailureOnly() && thrown == null) {
                    // 정상 케이스 스킵
                } else {
                    AuditLogCommand cmd = buildCommand(
                        pjp, annotation, returnValue, result, errorMessage);
                    auditLogService.record(cmd);   // @Async — 응답 지연 없음
                }
            } catch (Exception ignore) {
                // [5] 적재 자체가 실패해도 비즈니스 응답에는 영향 없음
                log.warn("audit log recording failed (suppressed): {}", ignore.getMessage());
            } finally {
                // [6] ThreadLocal 누수 방지 — 무조건 clear
                AuditContext.clear();
            }
        }
    }

    private AuditLogCommand buildCommand(
            ProceedingJoinPoint pjp, AuditLog annotation,
            Object returnValue, String result, String errorMessage) {

        AuditActionType action = annotation.action();
        ResourceType resourceType = annotation.resource();   // enum이라 항상 값 존재

        // [a] 자동 추출: pathVar > 마지막 PathVariable > 리턴객체 getId()
        AutoExtracted auto = detailExtractor.extract(pjp, annotation, returnValue);

        // [b] extra_data 머지 — 자동 위에 컨트롤러가 박은 수동 값을 덮어씀
        Map<String, Object> detail = new LinkedHashMap<>(auto.detail());
        detail.putAll(AuditContext.snapshotDetail());

        // [c] resourceId — 컨트롤러가 직접 박은 값이 우선
        String resourceId = Optional.ofNullable(AuditContext.snapshotResourceId())
                                     .orElse(auto.resourceId());

        // [d] 화면 라벨 — 어노테이션 description이 기본, 런타임 message가 있으면 합침
        String description = annotation.description();
        if (AuditContext.snapshotMessage() != null) {
            description = description.isBlank()
                ? AuditContext.snapshotMessage()
                : description + " | " + AuditContext.snapshotMessage();
        }

        // [e] markFailure 처리 — 정상 리턴인데 비즈니스 실패로 마킹된 경우만
        if (AuditContext.isMarkedFailure() && result.equals("SUCCESS")) {
            result = "FAILURE";
            errorMessage = AuditContext.snapshotFailureReason();
        }

        // [f] HTTP/Auth 컨텍스트 — 배치/시스템 호출이면 req=null 정상
        HttpServletRequest req = currentRequest();
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();

        // [g] 빌더로 마무리 — NOT NULL 필드는 13-3 표 fallback 적용
        return AuditLogCommand.builder()
            .id(UUID.randomUUID().toString())
            .employeeId(extractEmployeeId(auth))           // 미인증/배치 시 "UNKNOWN" or "SYSTEM"
            .deptId(extractDeptId(auth))
            .category(resolveCategory(req))                // URI prefix 로직, null 가능
            .action(action.name())
            .resourceType(resourceType.name())
            .resourceId(resourceId)
            .resourceDetail(detail.isEmpty() ? null : objectMapper.writeValueAsString(detail))
            .description(description)
            .result(result)
            .errorMessage(errorMessage)
            .ipAddress(clientInfo.extractIp(req))          // X-Forwarded-For 우선
            .userAgent(clientInfo.extractUserAgent(req))
            .sessionId(extractSessionId(req))              // JWT session_id claim
            .traceId(MDC.get("traceId"))                   // 분산 추적 (없으면 null)
            .createdAt(OffsetDateTime.now())
            .build();
    }

    /** URI prefix로 USER/ADMIN. 요청 컨텍스트 없으면 null. SYSTEM은 recordSystem이 직접 강제. */
    private String resolveCategory(HttpServletRequest req) {
        if (req == null) return null;
        String uri = req.getRequestURI();
        if (uri == null) return null;
        if (uri.startsWith("/admin/") || uri.startsWith("/api/admin/")) return "ADMIN";
        return "USER";
    }

    /** JwtAuthenticationFilter가 인증 성공 시 request attribute에 박아둔 session_id 추출. */
    private String extractSessionId(HttpServletRequest req) {
        if (req == null) return null;
        Object value = req.getAttribute(JwtAuthenticationFilter.SESSION_ID_ATTR);
        return (value instanceof String s) ? s : null;
    }
}
```

---

## 15. 비동기 / 트랜잭션 정책

```java
@Service
@RequiredArgsConstructor
public class AuditLogService {

    private final AuditLogRepository repository;

    @Async("logExecutor")
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(AuditLogCommand cmd) {
        try {
            repository.insert(cmd.toRecord());
        } catch (Exception e) {
            log.error("audit log insert failed: action={}, resource={}, err={}",
                cmd.action(), cmd.resourceType(), e.getMessage());
        }
    }

    /** 시스템 호출용 (배치/CI) — 인증 컨텍스트 없을 때.
     *  category="SYSTEM"을 항상 강제 세팅. 호출자가 채워둔 값은 무시. */
    @Async("logExecutor")
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordSystem(AuditLogCommand cmd) {
        AuditLogCommand systemCmd = cmd.toBuilder()
            .employeeId("SYSTEM")
            .deptId("SYSTEM")
            .category("SYSTEM")
            .ipAddress("0.0.0.0")
            .build();
        record(systemCmd);
    }
}
```

| 정책 | 이유 |
|---|---|
| `@Async("logExecutor")` | 응답 지연 방지. 접속 로그 executor 재사용 |
| `REQUIRES_NEW` | 비즈니스 트랜잭션 롤백돼도 로그는 남김 |
| 내부 try/catch | 적재 실패 fire-and-forget으로 흡수 |

---

## 16. 자기 호출 / Aspect 순서 주의

- **자기 호출 문제**: `@AuditLog`는 **컨트롤러 메서드에만** 부착한다. Service 내부에서 `this.method()` 호출은 프록시를 안 거쳐서 Aspect가 발동하지 않는다. 배치는 `recordSystem()`을 직접 호출.
- **Aspect 순서**: `@Order(HIGHEST_PRECEDENCE + 10)` → `@Transactional` 바깥에서 동작. 트랜잭션 커밋 후 SUCCESS 기록 / 롤백 후 FAILURE 기록을 보장.

---

## 17. 관리자 조회 API

```
GET /admin/logs/audit                      목록
  query: page, size, from, to,
         employeeId, deptId,
         category,           -- USER/ADMIN/SYSTEM
         action,             -- 다중 선택 가능
         resourceType, resourceId,
         result
  resp:  PagedResponse<AuditLogListResponse>

GET /admin/logs/audit/{id}                 상세
  resp:  AuditLogDetailResponse  (extra_data JSON 원본 포함)

GET /admin/logs/audit/categories           카테고리/유형 메타 (드롭다운용)
```

**응답 정책**:
- 목록 응답: `user_agent`, `session_id` 제외 (`extra_data`는 비고 count 결합 위해 포함)
- 상세 응답: 모든 필드 + `companyCode` (LATERAL JOIN으로 결정성 보장)

**사용자 표시명 / 부서명 — 015 비정규화 컬럼 직접 노출**

015 마이그레이션 이후 활동 로그 테이블이 적재 시점 `username` / `dept_name` 스냅샷을 직접 들고 있다. LATERAL JOIN을 제거하고 컬럼을 그대로 SELECT 한다. 사용자가 퇴사/삭제·부서가 폐지돼도 적재 시점 표시명이 보존된다.

```sql
SELECT
    al.id,
    al.employee_id,
    al.username    AS username,
    al.dept_code,
    al.dept_name,
    ...
FROM dinai.audit_logs AS al
WHERE ...
ORDER BY al.created_at DESC;
```

상세 조회의 `company_code` 만 화면 정책상 최신값이 필요해 `dinai.users` LEFT JOIN 으로 보강한다.

페이징/정렬: page 1-based, `created_at DESC` 고정.

---

## 18. 레이어 구조 (접속 로그와 동일 패턴)

```
domain/audit/
  ├─ AuditCategory.java                      (enum: USER/ADMIN/SYSTEM)
  ├─ AuditActionType.java                    (enum: 8개)
  ├─ ResourceType.java                       (enum: 14개)
  ├─ repository/AuditLogRepository.java      (port)
  └─ model/AuditLogFilter.java               (검색 조건 VO)

application/
  ├─ AuditLogService.java                    (@Async + REQUIRES_NEW, record + recordSystem)
  ├─ AuditLogCommand.java                    (record DTO)
  └─ aspect/
      ├─ AuditLog.java                       (@interface)
      ├─ AuditLogAspect.java                 (@Aspect @Around)
      ├─ AuditContext.java                   (ThreadLocal fluent API)
      ├─ AuditDetailExtractor.java           (자동 추출)
      └─ ErrorMessageResolver.java

infrastructure/persistence/
  ├─ mapper/AuditLogMapper.java
  ├─ entity/{AuditLogRecord, AuditLogListRecord, AuditLogDetailRecord}.java
  └─ resources/mybatis/mapper/auditLogs.xml

interfaces/
  ├─ controller/AdminAuditLogController.java
  └─ dto/{request, response}/...
```

**재활용 컴포넌트**: `AsyncConfig.logExecutor`, `ClientInfoExtractor`, `validateSystemAdmin()`, `PagedResponse<T>`

---

## 19. 테스트 전략

### 19-1. Aspect 단위
- `AspectJProxyFactory`로 프록시 생성 후 모든 케이스 검증
- 정상 / 비즈니스 예외 / 시스템 예외 / `AuditContext` 적재 / `markFailure`
- `AuditContext.clear()` 검증 (ThreadLocal 누수 없음)

### 19-2. category 자동 결정
- USER (`/api/v1/...`) / ADMIN (`/api/admin/...`) / 요청 컨텍스트 없을 때 `null`
- `recordSystem()`은 항상 SYSTEM 강제

### 19-3. NOT NULL 채움 가드
- 13-3 표 기준으로 7개 NOT NULL 필드를 모두 set 했는지 검증
- 누락 시 `INSERT NOT NULL` 위반으로 조용히 유실됨 (fire-and-forget) → 반드시 단위 테스트

### 19-4. 자동 추출
- `AuditDetailExtractor` 단위 테스트
- `pathVar` 명시 / 마지막 PathVariable / 리턴 객체 `getId()` 폴백

### 19-5. 통합 테스트
- testcontainers PostgreSQL + `audit_logs` 단일 테이블
- 카테고리/리소스/result별 INSERT 적재 확인
- `@Async` 동기화: 테스트 프로파일에서 `logExecutor`를 `SyncTaskExecutor`로 오버라이드

### 19-6. 스키마 vs enum 정합성
- DB CHECK 제약과 enum 코드가 같은 집합인지 비교

---

## 20. 운영 이슈 대응

| 이슈 | 대응 |
|---|---|
| 어노테이션 부착 누락 | ArchUnit으로 controller public 메서드에 `@AuditLog` 강제 |
| `extra_data`에 PII 유출 | `SENSITIVE_FIELDS` 화이트리스트 + 코드 리뷰 체크리스트 + Jackson 마스킹 직렬화기 |
| 영구 보관 — 테이블 비대화 | 인덱스(13-5)와 `created_at` 기준 페이지네이션으로 조회 성능 유지. 자동 삭제 없음. |
| `logExecutor` 큐 포화 | `RejectedExecutionPolicy = CallerRunsPolicy` (지연 허용, 유실 방지) |
| ThreadLocal 누수 | Aspect finally의 `AuditContext.clear()` 무조건 호출 |
| 시스템 활동(배포 등) 추적 | `recordSystem()` 사용 — `employee_id=SYSTEM`, `username=SYSTEM`, `dept_code=SYSTEM`, `category=SYSTEM` 강제 |
| 활동유형 추가 | enum + DB CHECK 제약 동시 변경 (마이그레이션 1쌍) |

---

## 21. 구현 체크리스트

### 21-1. dinai-db
- [x] `tobe-schema.sql` username / track_id→trace_id 정합화
- [x] `init/01_schema.sql` 단일 테이블 정의 동기화
- [x] `migrations/013_audit_logs_align_with_design.sql` — **단일 통합 마이그레이션**:<br>① `track_id → trace_id`, `dept_id → dept_code` rename (audit_logs / access_logs 양쪽)<br>② audit_logs 컬럼 추가: `category` / `description` / `username` / `dept_name` / `access_path`<br>③ access_logs 컬럼 추가: `username` / `dept_name`<br>④ `actor_name` 레거시 컬럼 제거<br>⑤ `access_path` NOT NULL + CHECK 강제, 모든 화면 필터 인덱스 재생성

### 21-2. dinai-core-api
- [x] `domain/audit/{AuditCategory, AuditActionType, ResourceType}.java`
- [x] `domain/audit/repository/AuditLogRepository.java` (port)
- [x] `application/{AuditLogCommand, AuditLogService, AuditLogConstants}.java` — `record` + `recordSystem` 강제
- [x] `application/aspect/{AuditLog, AuditLogAspect, AuditContext, AuditDetailExtractor, ErrorMessageResolver}.java`
- [x] `infrastructure/persistence/{mapper, entity, adapter}` — INSERT/SELECT(LATERAL JOIN)
- [x] `resources/mybatis/mapper/auditLogs.xml` — `extra_data` 목록 노출 포함
- [x] `interfaces/controller/AdminAuditLogController.java` + `dto/{request, response}/`
- [x] `security/jwt/JwtAuthenticationFilter` — `SESSION_ID_ATTR` propagate
- [ ] `AsyncConfig.logExecutor` 큐/풀 사이즈 검토
- [ ] `-parameters` 컴파일 옵션 활성 확인 (PathVariable 이름 추출에 필요)

### 21-3. dinai-client
- [x] `entities/admin-log/lib/labels.ts` — 매트릭스 + count unit (NOTICE/POST에 "첨부" 추가)
- [x] `entities/admin-log/lib/mappers.ts` — `actionLabel` 분리 + `extraData` 안전 파싱
- [x] `entities/admin-log/model/types.ts` — `AuditLogRow.actionLabel`, `AuditLogListResponse.extraData`
- [x] `pages/admin/ui/LogMonitoringPage.tsx` — 활동타입 컬럼은 `actionLabel`, 비고는 `remark`

### 21-4. 검증
- [ ] Aspect 단위 테스트 (성공 / 예외 / `markFailure`)
- [ ] DetailExtractor 단위 테스트 (`pathVar` / 마지막 PathVariable / `getId()` 폴백)
- [ ] category 자동 결정 테스트 (USER / ADMIN / `null`)
- [ ] NOT NULL 채움 가드 테스트 (7개 필드)
- [ ] `recordSystem` 강제 세팅 검증
- [ ] DB CHECK vs enum 동기화 테스트
- [ ] ThreadLocal 누수 테스트
- [ ] 통합 테스트 (카테고리/리소스/result별 INSERT)

### 21-5. 적용 단계
- [ ] 1차: 관리자 영역 (`/api/admin/**`) — 감사 요구도 가장 높음
- [ ] 2차: 파일/계정 도메인 (UPLOAD/DOWNLOAD, 비밀번호 변경)
- [ ] 3차: AI/지식/프로젝트 도메인
- [ ] 시스템 호출(배치/CI): 배포 등
