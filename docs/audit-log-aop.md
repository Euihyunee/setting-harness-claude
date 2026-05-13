# 감사 로그 AOP 구축 — 클래스별 로직 정리

이 문서는 `dinai-core-api` 에 새로 추가된 감사 로그(audit log) AOP 모듈을 코드 diff 와 나란히 읽기 위한 가이드다. 사용자가 컨트롤러에 어노테이션 한 줄 붙이는 것만으로 감사 로그가 비동기 적재되는 흐름을 위에서 아래로 따라가며, 각 클래스가 어떤 책임을 가지는지 자세히 설명한다.

> [!info] 모듈 위치
> 어노테이션·Aspect·Context 는 `application/aspect/` 하위, 적재/조회 서비스는 `application/`, 도메인 enum 은 `domain/audit/`, 영속화는 `infrastructure/persistence/` 와 `mybatis/mapper/auditLogs.xml`, 관리자 조회 API 는 `interfaces/controller/AdminAuditLogController` 에 위치한다.

---

## 1. 왜 AOP 인가

감사 로그는 "비즈니스가 무슨 일을 했는가" 를 기록하는 횡단 관심사다. 컨트롤러 본문에 매번 적재 코드를 끼워 넣으면 다음 문제가 생긴다.

- 비즈니스 코드 가독성을 해치고, 적재 누락이 발생함
- 트랜잭션 롤백 시 감사 로그까지 같이 롤백돼서 "왜 실패했는지" 증거가 사라짐
- 적재 I/O 가 응답 지연으로 이어짐

AOP 로 분리하면 어노테이션 1 줄만 붙이면 되고, Aspect 의 `finally` 에서 `@Async + REQUIRES_NEW` 로 적재하므로 비즈니스 트랜잭션 결과와 독립적으로 SUCCESS/FAILURE 가 모두 남는다.

> [!success] 핵심 정책
> Aspect 는 **비즈니스 흐름은 절대 건드리지 않는다**. 예외는 그대로 throw 하고, 성공 시 리턴값도 그대로 반환한다. 적재 실패는 흡수해서 비즈니스 응답에 영향이 없도록 한다.

---

## 2. 사용자 관점 코드 플로우

### 2.1 정상 케이스 (공지 등록)

사용자가 `POST /notices` 로 공지를 등록한다고 가정한다.

```text
[Client]
   │  multipart/form-data POST /notices
   ▼
[JwtAuthenticationFilter]   ── access token 검증, session_id 를 request attribute 로 세팅
   │
   ▼
[NoticeController.createNotice]   ◀── @AuditLog(action=CREATE, resource=NOTICE) 부착
   │
   ┌── (AOP 진입) AuditLogAspect.around()
   │       AuditContext.init()     ── ThreadLocal 새 State 생성
   │
   ├──► pjp.proceed()              ── 컨트롤러 본문 실행
   │       NoticeService.createNotice(...)
   │       AuditContext.resourceId(id).detail("count", attachmentCount)
   │   ◀──   리턴값 = CreatedResponse(id)
   │
   └── (finally)
           buildCommand(...)        ── employeeId/deptId/category/resourceId/extra_data/traceId 조립
           AuditLogService.record(cmd)
                ├─ @Async("logExecutor")          ── 호출 스레드 비차단
                └─ @Transactional(REQUIRES_NEW)   ── 비즈니스 트랜잭션과 분리
                     auditLogRepository.save(...) → INSERT INTO dinai.audit_logs
           AuditContext.clear()      ── ThreadLocal 누수 방지
   │
   ▼
[HTTP 201 Created]   ◀── 클라이언트로 응답
```

핵심은 **`AuditLogService.record` 가 별도 스레드 + 별도 트랜잭션으로 떨어진다**는 점이다. 응답 지연이 없고, 컨트롤러 트랜잭션이 롤백돼도 로그는 남는다.

### 2.2 실패 케이스 (예외 발생)

```text
pjp.proceed()
    └─ DomainException(RES_NOT_FOUND) throw
       │
catch
    │  result = "FAILURE"
    │  errorMessage = ErrorMessageResolver.resolve(e) → "RESOURCE_NOT_FOUND"
    │  thrown = e
    │  throw e        ── 예외는 그대로 위로 전파 (응답은 평소대로 ProblemDetail)
finally
    │  buildCommand(...) → 적재 (실패 케이스로 INSERT)
    │  AuditContext.clear()
```

`onFailureOnly=true` 옵션을 쓰면 성공 케이스는 적재를 건너뛰고 실패만 남긴다 (예: 로그인 실패만 기록).

### 2.3 시스템 호출 케이스 (배치/CI)

HTTP 컨텍스트가 없는 배치/스케줄러에서는 어노테이션이 작동하지 않는다. 이 경우 호출자가 직접 `AuditLogService.recordSystem(cmd)` 을 호출하면 employeeId/deptId/category/ipAddress 가 `SYSTEM` 으로 강제 보정돼 적재된다.

---

## 3. 클래스별 로직 상세

각 클래스 파일과 함께 읽으며 책임/입출력/주의점을 확인한다.

### 3.1 `application/aspect/AuditLog.java` — 어노테이션

| 필드              | 필수 | 설명                                                              |
|-----------------|:--:|-----------------------------------------------------------------|
| `action`        | ✅  | `AuditActionType` (CREATE/READ/UPDATE/DELETE/UPLOAD/DOWNLOAD/EXTRACT/EXECUTE) |
| `resource`      | ✅  | `ResourceType` (NOTICE/USER/FILE 등 14 종)                        |
| `description`   | ❌  | 매트릭스 자동 라벨로 부족할 때만 사용 (예: UPDATE+ACCOUNT 가 비번 변경인지 잠금인지) |
| `onFailureOnly` | ❌  | `true` 면 성공 케이스는 skip                                            |
| `pathVar`       | ❌  | resourceId 로 쓸 PathVariable 이름. 비우면 마지막 PathVariable 우선 |

`category` 가 어노테이션에 없는 이유는 Aspect 가 요청 URI prefix 로 자동 결정하기 때문 (`/admin/...` → ADMIN, 그 외 → USER, HTTP 컨텍스트 부재 → SYSTEM 강제 진입점 사용).

### 3.2 `application/aspect/AuditLogAspect.java` — Around Aspect

이 모듈의 핵심. `@Around("@annotation(annotation)")` 으로 `@AuditLog` 메서드를 가로챈다.

#### 동작 순서

```java
@Around("@annotation(annotation)")
public Object around(ProceedingJoinPoint pjp, AuditLog annotation) throws Throwable {
    AuditContext.init();                       // (1) ThreadLocal 초기화

    String result = "SUCCESS";
    Throwable thrown = null;
    try {
        returnValue = pjp.proceed();           // (2) 비즈니스 실행
        return returnValue;
    } catch (Throwable e) {
        result = "FAILURE";
        errorMessage = errorResolver.resolve(e); // (3) 예외 정규화
        thrown = e;
        throw e;                                 // (4) 예외 그대로 전파
    } finally {
        try {
            if (annotation.onFailureOnly() && thrown == null) {
                // skip
            } else {
                AuditLogCommand cmd = buildCommand(...);
                auditLogService.record(cmd);     // (5) 비동기 적재
            }
        } catch (Exception ignore) {
            log.warn("[AuditLog] 적재 실패 (suppressed): ...");
        } finally {
            AuditContext.clear();                // (6) 누수 방지
        }
    }
}
```

#### `@Order(Ordered.HIGHEST_PRECEDENCE + 10)` 의 의미

이 Aspect 는 `@Transactional` 보다 **바깥** 에서 동작하도록 우선순위를 매우 높게 잡았다. 트랜잭션이 커밋/롤백 된 후 SUCCESS/FAILURE 를 정확히 기록하기 위함이다. 만약 안쪽에 있으면 트랜잭션 커밋 전에 로그가 적재돼, 후행 commit 실패가 SUCCESS 로 잘못 기록될 수 있다.

#### `buildCommand` — 16 컬럼 조립 로직

| 컬럼              | 결정 로직                                                                                          |
|-----------------|------------------------------------------------------------------------------------------------|
| `id`            | `UUID.randomUUID().toString()`                                                                 |
| `employeeId`    | `Authentication` 의 `CustomUserDetails.getUsername()`. 비인증 → `SYSTEM`, 비어있음 → `UNKNOWN` |
| `deptId`        | `CustomUserDetails.getDepartmentCode()`. 비인증 → `SYSTEM`, 부재 → `UNKNOWN`                       |
| `category`      | URI prefix `/admin/`/`/api/admin/` → `ADMIN`, 그 외 HTTP → `USER`, 요청 부재 → `null` (SYSTEM 진입점에서 강제) |
| `logType`       | `annotation.action().name()`                                                                  |
| `resourceType`  | `annotation.resource().name()`                                                                |
| `resourceId`    | **우선순위**: ① `AuditContext.resourceId()` ② `pathVar` 명시 → 일치하는 `@PathVariable` ③ 마지막 `@PathVariable` ④ 리턴 객체 `getId()` ⑤ null |
| `extraData`     | `AuditContext.detail(...)` 누적 Map → Jackson 으로 JSON 직렬화 (LinkedHashMap 으로 순서 보존)                |
| `result`        | `try` 정상 통과 → SUCCESS, catch 진입 → FAILURE. `AuditContext.markFailure(...)` 호출 시 강제 FAILURE       |
| `errorMessage`  | `ErrorMessageResolver.resolve(throwable)` 결과 (정규화 코드)                                         |
| `description`   | `annotation.description()` 우선, `AuditContext.message(...)` 가 있으면 ` \| ` 으로 결합                   |
| `ipAddress`     | `ClientInfoExtractor.ipAddress(req)` (X-Forwarded-For 우선)                                     |
| `userAgent`     | `ClientInfoExtractor.userAgent(req)`, 500 자 truncate                                          |
| `sessionId`     | `JwtAuthenticationFilter.SESSION_ID_ATTR` request attribute (stateless JWT 의 session_id claim) |
| `traceId`       | `MDC.get("traceId")` (Micrometer Tracing 채움) — 호출 스레드에서 캡처 (비동기에서는 부재 가능)               |
| `createdAt`     | `DateTimeProvider.nowUtc()`                                                                    |

> [!warning] truncate 정책
> `resourceId` 100 자, `errorMessage` 100 자, `userAgent` 500 자, `description` 1000 자로 잘라낸다. DB 컬럼 길이와 동기화돼 있으며 `AuditLogConstants` 가 단일 출처다.

### 3.3 `application/aspect/AuditContext.java` — ThreadLocal 채널

Aspect 와 컨트롤러 사이의 **fluent 데이터 채널**. 어노테이션 + 자동 추출만으로 부족한 정보를 컨트롤러 본문에서 한 줄로 명시 적재한다.

#### 제공 API

```java
AuditContext.detail("count", 3);                              // extra_data 키-값 추가
AuditContext.resourceId("a1b2-...");                          // 자동 추출 덮어쓰기
AuditContext.message("관리자 비밀번호 강제 초기화");                  // description 보조 메시지
AuditContext.markFailure("쿼터 초과");                           // 예외 없이도 FAILURE 강제
AuditContext.parentResource(ResourceType.NOTICE, noticeId);   // {type, id} 표준 키로 적재
```

체이닝을 위해 `AuditContextChain` 싱글톤을 반환한다. 내부 상태는 ThreadLocal 의 `State` 객체에 보관된다.

> [!danger] 누수 방지
> ThreadLocal 은 **반드시** Aspect 의 `finally` 에서 `clear()` 한다. 컨트롤러에서 직접 `init()`/`clear()` 호출하지 말 것 — Aspect 외부에서 사용하면 다음 요청에 누수된다.

#### snapshot 메서드

`snapshotDetail()`/`snapshotResourceId()`/`snapshotMessage()`/`isMarkedFailure()`/`snapshotFailureReason()` 는 **Aspect 전용**. 컨트롤러는 putter 만 쓴다.

### 3.4 `application/aspect/AuditDetailExtractor.java` — 시그니처/리턴 자동 추출

resourceId 자동 추출만 담당한다. 우선순위는 다음과 같다.

```text
1) AuditContext.resourceId(...)              ── Aspect 가 먼저 체크 (이 클래스 호출 안 함)
2) annotation.pathVar() 명시값 매칭 PathVariable
3) 마지막 @PathVariable 인자
4) 리턴 객체.getId() (CREATE 계열 자동 매칭)
5) null
```

> [!info] 마지막 PathVariable 우선 이유
> `/users/{userId}/permissions/{permId}` 같은 다단 경로에서 첫 PathVariable 을 잡으면 권한 ID 가 아니라 사용자 ID 가 resource_id 로 잘못 기록된다. 가장 구체적인 자식 리소스 ID 를 잡기 위해 마지막을 우선한다.

`extractReturnId` 는 리플렉션으로 `getId()` 를 찾는다. 메서드가 없거나 호출 실패하면 조용히 null 반환 (CREATE 외 메서드는 이 단계에 도달하지 않거나 도달해도 무해).

### 3.5 `application/aspect/ErrorMessageResolver.java` — 예외 정규화

`Throwable` 을 9-2 카탈로그의 정규화된 `error_message` 코드로 변환한다. 원문 메시지/스택트레이스/PII 는 적재되지 않는다.

```text
DomainException(AUTH_TOKEN_EXPIRED 등) → AUTHENTICATION_REQUIRED
DomainException(PERM_DENIED 등)        → ACCESS_DENIED
DomainException(RES_NOT_FOUND)         → RESOURCE_NOT_FOUND
DomainException(RES_ALREADY_EXISTS 등) → DUPLICATE_RESOURCE
DomainException(VAL_*)                 → VALIDATION_FAILED / FILE_SIZE_EXCEEDED
DomainException(RATE_*)                → QUOTA_EXCEEDED
DomainException(unknown)               → BUSINESS_RULE_VIOLATION
InfrastructureError(NET_UPSTREAM_*)    → EXTERNAL_API_ERROR
InfrastructureError(*)                 → INTERNAL_ERROR
AccessDeniedException                  → ACCESS_DENIED
AuthenticationException                → AUTHENTICATION_REQUIRED
MethodArgumentNotValid / BindException → VALIDATION_FAILED
DataIntegrityViolationException        → DUPLICATE_RESOURCE
RestClientException / WebClientException → EXTERNAL_API_ERROR
그 외                                    → INTERNAL_ERROR
```

> [!success] 카탈로그 고정의 효과
> 운영 시 `error_message` 컬럼으로 곧바로 GROUP BY 가 가능하다. "최근 24h 권한 거부 / 외부 API 장애" 같은 KPI 쿼리가 enum 기반이라 안정적이다.

### 3.6 `application/AuditLogConstants.java` — 정책 상수 카탈로그

DB CHECK 제약과 동기화된 단일 진실 공급원. `RESULT_SUCCESS`/`RESULT_FAILURE`, `UNKNOWN`/`SYSTEM_ACTOR` 보정값, `DEFAULT_IP`, truncate 길이 (`USER_AGENT_MAX_LENGTH=500`, `DESCRIPTION_MAX_LENGTH=1000`) 정의.

### 3.7 `application/AuditLogCommand.java` — 값 객체

Aspect 가 빌드하고 서비스로 전달하는 16 필드 record. `toRecord()` 로 영속화 record (`AuditLogRecord`) 로 변환한다. 비동기 적재 시점에는 호출 스레드 컨텍스트 (특히 `traceId` MDC) 가 사라지므로, **동기 시점에 캡처해 record 안에 들고 가는 게 핵심**이다.

### 3.8 `application/AuditLogService.java` — 적재/조회 서비스

#### `record(cmd)` — 적재 진입점

```java
@Async("logExecutor")
@Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
public void record(AuditLogCommand command) {
    if (command == null) return;
    try {
        auditLogRepository.save(command.toRecord());
    } catch (Exception ex) {
        // fire-and-forget — 비즈니스 응답에 영향 없음
        log.warn("[AuditLog] 적재 실패. logType={}, resource={}, result={}", ...);
    }
}
```

세 가지 정책이 동시에 작동한다.

1. **`@Async("logExecutor")`** — 접속 로그용 executor 를 재사용해 호출 스레드를 비차단. (executor 빈은 `AsyncConfig` 에 정의)
2. **`REQUIRES_NEW`** — 비즈니스 트랜잭션이 롤백돼도 로그는 별도 트랜잭션으로 커밋되어 보존.
3. **예외 흡수** — 적재 자체가 실패해도 비즈니스 응답에 절대 영향 주지 않음 (warn 로그만 남김).

#### `recordSystem(cmd)` — 시스템 진입점

`employeeId/deptId/category/ipAddress` 를 `SYSTEM` 디폴트로 강제 보정해 `record(...)` 를 다시 호출한다. 배치/CI 처럼 인증 컨텍스트가 없는 호출자 전용. 호출자가 채운 ID 들은 무시된다 — 이게 정책이다.

#### `search(request)` — 관리자 목록 조회

0-based page (요청) → 1-based page (응답) 변환, 정렬은 `created_at DESC` 고정. 응답은 슬림 DTO (`AuditLogListResponse`) — `userAgent`/`sessionId`/`extra_data` 는 상세 API 에서만 노출.

#### `findById(id)` — 단건 상세

미존재 시 `DomainException(RES_NOT_FOUND, "감사 로그를 찾을 수 없습니다.")`. 메시지에 ID 값 노출 금지 (CLAUDE.md 정책).

### 3.9 도메인 enum 3 종

| Enum                | 카디널리티 | 비고                                                |
|---------------------|:--:|---------------------------------------------------|
| `AuditActionType`   | 8 | CREATE/READ/UPDATE/DELETE/UPLOAD/DOWNLOAD/EXTRACT/EXECUTE. label() 한글 표시명 |
| `ResourceType`      | 14 | NOTICE/PERMISSION/USER/DEPT/PROJECT/POST/FILE/CONVERSATION/AGENT/KNOWLEDGE/SETTING/QUOTA/DEPLOY/ACCOUNT |
| `AuditCategory`     | 3 | USER/ADMIN/SYSTEM. **어노테이션에 없음** — 런타임 결정 |

세 enum 모두 DB CHECK 제약 (`chk_audit_action`, `chk_audit_resource`, `chk_audit_category`) 과 동기화. enum 추가 시 마이그레이션도 같이 변경해야 한다.

### 3.10 `domain/audit/repository/AuditLogRepository.java` — Port

도메인 레이어의 인터페이스. `save` / `findByFilter` / `countByFilter` / `findDetailById` 4 개 메서드. 조회는 용도별로 슬림(`AuditLogListRecord`) / 상세(`AuditLogDetailRecord`) 로 분리.

### 3.11 `domain/audit/model/AuditLogFilter.java` — 검색 필터 record

11 필드 (`from`/`to`/`employeeId`/`deptId`/`category`/`logType`/`resourceType`/`resourceId`/`result`/`limit`/`offset`). 모두 nullable, null/blank 이면 해당 조건 미적용. 시각 비교는 `from <= created_at < to` 미만 비교 규약.

### 3.12 `infrastructure/persistence/adapter/MybatisAuditLogRepository.java` — Adapter

도메인 Port → MyBatis Mapper 호출 위임만 하는 얇은 어댑터. 여기에 비즈니스 로직 두지 않는다.

### 3.13 `infrastructure/persistence/mapper/AuditLogMapper.java` + `auditLogs.xml`

#### 매퍼 인터페이스

`insert` / `findByFilter` / `countByFilter` / `findDetailById` 4 개. 모든 파라미터는 `@Param` 명시.

#### XML 핵심 포인트

- **record 매핑은 `<constructor>` 사용**. Java record 는 setter 가 없어 `<result>` 기반 매핑이 `ReflectionException` 을 발생시킨다. `<arg>` 순서는 record 컴포넌트 선언 순서와 정확히 일치해야 함.
- **`extra_data` 는 jsonb 캐스트**. INSERT 에서 `CAST(#{record.extraData} AS jsonb)`, SELECT 에서 `al.extra_data::text` 로 raw text 노출.
- **`actor_name` 컬럼은 적재하지 않음**. 조회 시점 `dinai.users.username` 을 LATERAL JOIN 으로 보강. 사용자 미존재(`employee_id='SYSTEM'/'UNKNOWN'`)면 `actor_name=NULL`.
- **`dept_name` LATERAL + LIMIT 1 + ORDER BY company_code**. 다회사 dept_code 중복 시 결정성 매칭 보장.
- **공통 WHERE 는 `<sql id="filterWhereConditions">`** 으로 분리. `findByFilter`/`countByFilter` 가 `<include>` 로 재사용.
- **`employee_id` 는 UPPER 비교**. 케이스 불문 매칭.

> [!warning] `${}` 금지
> 모든 동적 파라미터는 `#{}` 바인딩. SQL 인젝션 방어 (CLAUDE.md 정책).

### 3.14 `interfaces/controller/AdminAuditLogController.java` — 관리자 조회 API

```text
GET  /admin/logs/audit          ── 페이징 목록 조회 (AuditLogSearchRequest @ModelAttribute)
GET  /admin/logs/audit/{id}     ── 단건 상세
```

두 엔드포인트 모두 `perms.validateSystemAdmin()` 으로 SYSTEM_ADMIN 권한을 강제한다. 응답은 `ApiResponse.success(...)` 래퍼로 통일.

> [!info] 관리자 조회 API 자체는 `@AuditLog` 를 부착하지 않음
> 감사 로그를 보는 행위까지 감사하면 무한 증식할 위험이 있어 의도적으로 제외. 필요 시 별도 정책으로 분리.

### 3.15 컨트롤러 적용 패턴 — `NoticeController` 예시

#### 조회 (단건)

```java
@AuditLog(action = AuditActionType.READ, resource = ResourceType.NOTICE)
@GetMapping("/{id}")
public ResponseEntity<ApiResponse<NoticeDetailResponse>> getNotice(@PathVariable Long id) {
    Post notice = noticeService.getNoticeDetail(id);
    return ResponseEntity.ok(ApiResponse.success(NoticeDetailResponse.from(notice)));
}
```

자동 추출만으로 `resource_id = id` 가 잡힘 — 추가 코드 불필요.

#### 조회 (목록 — count 명시)

```java
@AuditLog(action = AuditActionType.READ, resource = ResourceType.NOTICE)
@GetMapping
public ResponseEntity<...> listNotices(...) {
    PagedResponse<...> result = noticeService.listNotices(...);
    AuditContext.detail("count", result.getPageInfo().getTotalItems());
    return ResponseEntity.ok(ApiResponse.success(result.map(...)));
}
```

목록은 PathVariable 이 없어 `resource_id=null`, `extra_data={"count":n}` 으로 적재.

#### 등록 (CREATE — 리턴 ID 자동 추출)

```java
@AuditLog(action = AuditActionType.CREATE, resource = ResourceType.NOTICE)
@PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
public ResponseEntity<...> createNotice(...) {
    Long id = noticeService.createNotice(...);
    AuditContext.resourceId(String.valueOf(id))
                .detail("count", attachmentCount);
    return ResponseEntity.status(HttpStatus.CREATED)
            .body(ApiResponse.success(CreatedResponse.of(id)));
}
```

`AuditContext.resourceId(...)` 명시. 명시 안 해도 리턴 객체 `CreatedResponse.getId()` 로도 잡히지만, 컨텍스트로 박는 게 더 명확.

#### 부모 리소스 + 자식 리소스 (DOWNLOAD)

```java
@AuditLog(action = AuditActionType.DOWNLOAD, resource = ResourceType.FILE,
          description = "공지 첨부파일 다운로드")
@GetMapping("/{noticeId}/files/{fileId}/download-url")
public ResponseEntity<...> getDownloadUrl(
        @PathVariable Long noticeId, @PathVariable UUID fileId, ...) {
    AuditContext.parentResource(ResourceType.NOTICE, String.valueOf(noticeId))
                .resourceId(fileId.toString());
    ...
}
```

resource 는 FILE (자식), parent 는 NOTICE (부모). `extra_data.context = {type:"NOTICE", id:"..."}` 로 적재돼 추적성 확보.

#### 보조 정보 — description 활용

`(UPDATE, ACCOUNT)` 매트릭스가 비밀번호 변경인지 계정 잠금인지 모호한 경우에만 `description = "비밀번호 변경"` 식으로 화면 라벨 오버라이드.

---

## 4. 정책 요약 (체크리스트)

문서를 덮은 후 코드 작성 시 참고할 핵심 정책.

- [ ] 컨트롤러 메서드에 `@AuditLog(action, resource)` 부착 — 카테고리는 명시 안 함
- [ ] resource_id 가 다단 경로/리턴 ID 로 못 잡히면 `AuditContext.resourceId(...)` 명시
- [ ] 부모 리소스가 의미 있으면 `AuditContext.parentResource(...)` 로 context 추가
- [ ] count/모드/대상 필드 같은 **표시용 보조 정보**는 `AuditContext.detail(...)` 로
- [ ] description 은 매트릭스 자동 라벨로 부족할 때만 사용 (남발 금지)
- [ ] 실패만 적재해야 할 때 `onFailureOnly = true`
- [ ] 예외 없이 FAILURE 처리는 `AuditContext.markFailure(reason)`
- [ ] 시스템 호출(배치/CI)은 `AuditLogService.recordSystem(cmd)` 직접 호출
- [ ] 어노테이션은 컨트롤러 레이어에만 — 서비스/리포지토리에 부착 금지 (URI 카테고리 결정 불가)
- [ ] enum 추가 시 DB CHECK 제약 마이그레이션도 함께 변경

> [!success] 한 줄 요약
> 어노테이션 1 개 + 필요 시 컨텍스트 putter 1~2 줄 = 비동기 트랜잭션-독립 감사 로그 적재 완료.
