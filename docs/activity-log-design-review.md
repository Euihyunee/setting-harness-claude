# 활동 로그(Activity Log) 설계 검토 문서

> **본 문서는 초기 설계 검토록(의사결정 이력)입니다. 최종 구현 정본은 [activity-log-aop-design.md](activity-log-aop-design.md)를 참조하세요.** 테이블/컬럼명(`activity_logs`/`activity_type` 등)은 정본에서 `audit_logs`/`log_type` 등으로 변경되었습니다.

> 대상: dinai-core-api / dinai-db
> 전제: `dinai.access_logs` 구현 완료, 같은 패턴(레이어드 + AOP/비동기/REQUIRES_NEW) 재활용

요구 필드: `일자, 사번, 이름, 부서명, 활동유형, 리소스, 비고, 결과, IP, 접속경로, 실패사유`
활동유형: `데이터 조회/수정/삭제/등록`, `상세 조회`, `파일 업로드`, `파일 다운로드`
리소스: 조회 개수, 다운로드 파일명, 업로드 파일명 등 활동마다 구조가 다름

---

## 1. 활동 로그가 접속 로그보다 어려운 이유

| 항목     | 접속 로그                         | 활동 로그             |
| ------ | ----------------------------- | ----------------- |
| 트리거 지점 | 7개 (LOGIN/LOGOUT/REFRESH/...) | 거의 모든 비즈니스 메서드    |
| 컨텍스트   | 인증 흐름 안에서 명확                  | 호출 메서드마다 다른 인자/리턴 |
| 리소스 형태 | 없음                            | 가변 (파일명/카운트/식별자)  |
| 적재 빈도  | 인증 이벤트 단위                     | 사용자 클릭마다          |

핵심 문제: **트리거 지점이 흩어져 있고, 적재할 데이터가 메서드마다 다르다.**
접속 로그처럼 컨트롤러에서 `service.log()`를 직접 호출하면 보일러플레이트가 폭발하고 누락 위험이 큼.

---

## 2. 트리거 방식 비교

### 2-1. 각 서비스/컨트롤러에서 직접 호출 (Naive)

```java
@PostMapping("/users")
public UserResponse create(@RequestBody UserCreateRequest req) {
    UserResponse res = userService.create(req);
    activityLogService.record(ActivityLogCommand.builder()
        .type(ActivityType.CREATE)
        .resourceType("USER")
        .resourceId(res.getId())
        .description("사용자 등록")
        .result("SUCCESS")
        .build());
    return res;
}
```

**문제**
- 메서드마다 5~10줄 중복 → 컨트롤러 수십 개에 적용 시 수백 줄 노이즈
- try/catch 작성 누락 시 실패 케이스 미기록
- 리팩터링하면서 `record()` 호출 한 줄 빠뜨리면 감사 공백 발생
- 비즈니스 로직과 감사 로직이 섞여 테스트 가독성 저하

**언제 쓰나** — 트리거 지점이 5개 미만이고 활동 형태가 정형화돼 있을 때(접속 로그가 이 케이스).

---

### 2-2. Filter / HandlerInterceptor (요청 단위 자동 캡처)

```java
public class ActivityLoggingInterceptor implements HandlerInterceptor {
    public void afterCompletion(HttpServletRequest req, HttpServletResponse res,
                                 Object handler, Exception ex) {
        activityLogService.record(...);  // URI, method, status만 가지고 기록
    }
}
```

**장점** — 모든 요청을 자동으로 잡음. 누락 없음.

**문제**
- "어떤 리소스인지"를 URI에서 역추적해야 함 → `/api/users/123` → USER, id=123 패턴 매칭 (취약)
- 비즈니스 의미(예: "사용자 활성화")는 URI/메서드만 봐선 알 수 없음
- 응답 바디를 다시 파싱해야 `count` 같은 필드 얻음 (성능/복잡도 낭비)
- READ_LIST와 READ_DETAIL을 GET 단일 메서드에서 구분할 수 없음

**언제 쓰나** — 단순 액세스 트레이스(URL + status)만 필요할 때. 의미 있는 활동 로그에는 부적합.

---

### 2-3. AOP + 커스텀 어노테이션 (권장)

```java
// 어노테이션 정의
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface ActivityLog {
    ActivityType type();
    String resourceType();
    String description() default "";
    String resourceIdExpr() default "";   // SpEL: "#id" or "#result.id"
    String detailExpr() default "";       // SpEL: "{'count': #result.totalCount}"
}

// 사용 예시 — 컨트롤러는 한 줄만 추가
@GetMapping("/users")
@ActivityLog(type = READ_LIST, resourceType = "USER",
             description = "사용자 목록 조회",
             detailExpr = "{'count': #result.totalCount}")
public PagedResponse<UserResponse> list(UserSearchRequest req) { ... }

@PostMapping("/files/upload")
@ActivityLog(type = FILE_UPLOAD, resourceType = "FILE",
             description = "파일 업로드",
             detailExpr = "{'fileName': #file.originalFilename, 'size': #file.size}")
public FileUploadResponse upload(@RequestParam MultipartFile file) { ... }

@DeleteMapping("/users/{id}")
@ActivityLog(type = DELETE, resourceType = "USER",
             resourceIdExpr = "#id", description = "사용자 삭제")
public void delete(@PathVariable String id) { ... }
```

**Aspect 골격**

```java
@Aspect
@Component
@RequiredArgsConstructor
public class ActivityLogAspect {
    private final ActivityLogService activityLogService;
    private final ClientInfoExtractor clientInfo;
    private final ExpressionParser parser = new SpelExpressionParser();

    @Around("@annotation(annotation)")
    public Object around(ProceedingJoinPoint pjp, ActivityLog annotation) throws Throwable {
        long start = System.currentTimeMillis();
        String result = "SUCCESS";
        String errorMessage = null;
        Object returnValue = null;
        try {
            returnValue = pjp.proceed();
            return returnValue;
        } catch (Throwable e) {
            result = "FAILURE";
            errorMessage = resolveErrorCode(e);
            throw e;                                  // 재던짐: 흐름 보존
        } finally {
            try {
                activityLogService.record(buildCommand(
                    annotation, pjp, returnValue, result, errorMessage,
                    System.currentTimeMillis() - start));
            } catch (Exception ignore) {              // 적재 실패가 비즈니스 영향 X
            }
        }
    }
}
```

**장점**
- 컨트롤러는 어노테이션 한 줄. 비즈니스 로직과 분리.
- 메서드 인자(`#file`, `#id`), 리턴값(`#result.totalCount`)을 SpEL로 직접 추출
- 예외 전파를 보존하면서 자동으로 `FAILURE` 기록
- 누락 위험은 있으나, 코드 리뷰 / 정적 분석으로 강제 가능

**문제 / 주의점**
- `@Cacheable`처럼 프록시 기반 → **같은 클래스 내부 호출은 어드바이스 미적용**. 컨트롤러 메서드에만 붙이면 안전.
- SpEL 표현식 오타는 컴파일타임에 못 잡음 → 표현식 단위 테스트 권장
- 프록시 오버헤드 (마이크로초 단위, 무시 가능)
- 리턴값을 SpEL로 다루므로 메서드 시그니처가 바뀌면 어노테이션도 같이 갱신 필요

---

### 비교 요약

| 기준 | 직접 호출 | Interceptor | AOP+어노테이션 |
|------|----------|------------|--------------|
| 누락 방지 | 낮음 | 매우 높음 | 중간 (리뷰 강제 가능) |
| 비즈니스 컨텍스트 | 명확 | 매우 약함 | 명확 |
| 가변 리소스(파일명/카운트) | 자유 | 어려움 | SpEL로 자유 |
| 보일러플레이트 | 많음 | 없음 | 매우 적음 |
| 테스트 격리 | 어려움 | 쉬움 | 쉬움 (Aspect 단위) |
| **권장 여부** | X | X (보조용) | O |

---

## 3. DB 스키마 설계

### 3-1. 권장 안

```sql
CREATE TABLE dinai.activity_logs (
    id              UUID PRIMARY KEY,
    employee_id     VARCHAR(50)  NOT NULL,
    dept_id         VARCHAR(50)  NOT NULL,

    activity_type   VARCHAR(20)  NOT NULL,    -- READ_LIST/READ_DETAIL/CREATE/UPDATE/DELETE/FILE_UPLOAD/FILE_DOWNLOAD
    resource_type   VARCHAR(50)  NOT NULL,    -- USER/DEPT/FILE/POLICY/...
    resource_id     VARCHAR(100),             -- 단건일 때만
    resource_detail JSONB,                    -- 가변 부가정보 (파일명, count, before/after 등)

    result          VARCHAR(10)  NOT NULL,    -- SUCCESS/FAILURE
    error_message   TEXT,
    description     TEXT,                     -- 어노테이션 description (사람이 읽는 비고)

    request_uri     VARCHAR(500),
    http_method     VARCHAR(10),
    duration_ms     BIGINT,

    access_path     VARCHAR(10)  NOT NULL,    -- WEB/API/MOBILE
    ip_address      VARCHAR(45)  NOT NULL,
    user_agent      VARCHAR(500),
    session_id      VARCHAR(100),

    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_activity_emp_created  ON dinai.activity_logs (employee_id, created_at DESC);
CREATE INDEX idx_activity_dept_created ON dinai.activity_logs (dept_id, created_at DESC);
CREATE INDEX idx_activity_type_created ON dinai.activity_logs (activity_type, created_at DESC);
CREATE INDEX idx_activity_resource     ON dinai.activity_logs (resource_type, resource_id);
CREATE INDEX idx_activity_created      ON dinai.activity_logs (created_at DESC);
```

### 3-2. 컬럼 설계 트레이드오프

#### `resource` 분리 vs 단일 JSONB

**나쁜 안 — 단일 컬럼**
```sql
resource VARCHAR(500)   -- "user:123" / "file:report.pdf,size=1024" 식으로 인코딩
```
- 파싱 부담, 인덱스 무용지물, "특정 사용자에 대한 모든 활동" 같은 조회 불가

**좋은 안 — 3분할**
```sql
resource_type   VARCHAR(50)   NOT NULL  -- 카테고리
resource_id     VARCHAR(100)            -- 단건 식별자 (인덱스 활용)
resource_detail JSONB                   -- 가변 필드
```

활동유형별 적재 예시:

| activity_type | resource_type | resource_id | resource_detail |
|---------------|---------------|-------------|-----------------|
| READ_LIST | USER | (null) | `{"count": 30, "filter": {"deptId":"D01"}}` |
| READ_DETAIL | USER | "U123" | (null) |
| CREATE | USER | "U999" | `{"name": "홍길동"}` |
| UPDATE | USER | "U123" | `{"changed": ["email","phone"]}` |
| DELETE | USER | "U123" | (null) |
| FILE_UPLOAD | FILE | "F-uuid" | `{"fileName":"a.pdf","size":12345,"mime":"application/pdf"}` |
| FILE_DOWNLOAD | FILE | "F-uuid" | `{"fileName":"a.pdf"}` |

#### `description` vs `resource_detail` 분리

- `description`: 어노테이션에 박혀 있는 **고정 라벨** ("사용자 등록"). 화면 비고 컬럼에 그대로 노출.
- `resource_detail`: **런타임 값** (파일명/카운트). JSONB로 자유 적재.
- 둘 합치면 검색/필터 모두 어려움 → 분리 유지.

#### `request_uri` / `http_method` / `duration_ms` 추가 이유

- 감사 시 "이 활동이 어느 엔드포인트에서 왔나" 추적 필수
- `duration_ms`는 성능 이슈 활동(느린 다운로드 등) 추적에 유용. 비용 거의 없음.

#### NOT NULL 정책

- `result`, `activity_type`, `resource_type`, `access_path`, `ip_address` 는 항상 채움 (접속 로그와 동일 정책: 모르면 `UNKNOWN` / `0.0.0.0`로 보정)
- `resource_id`, `resource_detail`, `error_message`, `session_id`, `description` 은 NULL 허용

---

## 4. 결정 필요 사항 3가지

### 4-1. 리소스 detail 추출 방식 — SpEL vs ContextHolder

**A안: SpEL (어노테이션에 표현식)**
```java
@ActivityLog(type=FILE_UPLOAD, resourceType="FILE",
             detailExpr = "{'fileName': #file.originalFilename}")
```
- 장점: 어노테이션 한 줄로 끝, 메서드 시그니처에서 직접 추출
- 단점: 표현식 오타가 런타임에 터짐, 복잡한 객체 변환 어려움

**B안: ThreadLocal ContextHolder (메서드 안에서 명시적 적재)**
```java
@ActivityLog(type=FILE_UPLOAD, resourceType="FILE")
public Response upload(MultipartFile file) {
    ActivityContext.put("fileName", file.getOriginalFilename());
    ActivityContext.put("size", file.getSize());
    return ...;
}
```
- 장점: 타입 안전, 어떤 값이 들어가는지 명시적
- 단점: 비즈니스 메서드에 감사 코드 침투 (분리 원칙 깨짐), ThreadLocal 누수 위험

**권장**: **A안(SpEL) 기본 + 복잡한 케이스만 B안 보조**
- 90%는 인자/리턴 추출이면 충분
- 변환 로직이 복잡한 5%만 B안

### 4-2. 변경 전/후(diff) 캡처

UPDATE/DELETE에서 "뭐가 바뀌었나" 기록할지:

- **요건 있음(감사/컴플라이언스)**: `resource_detail`에 `{"before": {...}, "after": {...}}` 적재
  - 비용: 수정 전 엔티티를 한 번 더 SELECT해야 함 (또는 JPA Hibernate Envers / MyBatis Interceptor)
- **요건 없음**: `{"changed": ["email","phone"]}` 정도만 (필드명 리스트)

**권장**: 우선 후자(필드명 리스트)로 시작. 컴플라이언스 요건 확정되면 before/after로 확장.

### 4-3. READ 활동 적재 범위

모든 GET 다 쌓으면 테이블이 일 단위 수십만 건 → 비용 폭증.

| 옵션 | 장 | 단 |
|------|---|---|
| 전체 GET 적재 | 완전한 추적 | 테이블 폭증, 파티셔닝 필수 |
| 관리자 페이지/민감 데이터만 | 비용 합리적 | 어노테이션 누락 시 공백 |
| 상세조회만 (LIST 제외) | 균형 | LIST는 메타정보로만 남음 |

**권장**: **관리자/민감 도메인(USER, DEPT, POLICY, FILE)만 어노테이션 부착**. 일반 콘텐츠 조회는 제외.
필요 시 활성화 정책을 `application.yml`로 토글:
```yaml
activity-log:
  read-list: true
  read-detail: true
  bulk-threshold: 1000   # count > 1000인 조회는 detail 생략
```

---

## 5. 패키지 구조 (접속 로그 패턴 그대로)

```
domain/monitoring/
  ├─ ActivityType.java                      (enum)
  ├─ repository/ActivityLogRepository.java  (port)
  └─ model/ActivityLogFilter.java

application/
  ├─ ActivityLogService.java                (@Async("logExecutor"), REQUIRES_NEW)
  ├─ ActivityLogCommand.java
  └─ aspect/
      ├─ ActivityLog.java                   (@interface)
      └─ ActivityLogAspect.java             (@Aspect @Around)

infrastructure/persistence/
  ├─ mapper/ActivityLogMapper.java
  ├─ entity/ActivityLog{Record,ListRecord,DetailRecord}.java
  └─ resources/mybatis/mapper/activityLogs.xml

interfaces/
  ├─ controller/AdminActivityLogController.java
  └─ dto/{request,response}/...
```

재활용 컴포넌트:
- `AsyncConfig.logExecutor` (접속 로그용으로 이미 존재)
- `ClientInfoExtractor` (IP / UserAgent / AccessPath)
- `validateSystemAdmin()` (관리자 권한 체크)

---

## 6. 운영 고려사항

### 6-1. 적재 실패 정책

접속 로그와 동일하게:
- `@Async` + `REQUIRES_NEW`로 비즈니스 트랜잭션과 분리
- Aspect 안 `try/finally` + 적재 실패는 로그만 찍고 흡수
- 즉, **활동 로그 적재 실패가 비즈니스 응답에 영향 주지 않음**

### 6-2. 테이블 보존 정책

- 일평균 적재량 추정 후 파티셔닝 결정 (월 단위 PARTITION BY RANGE)
- 보존 기간 정책 (예: 1년 후 archive S3, 운영 테이블에서 DROP PARTITION)
- 본 문서 범위 외 — DBA와 별도 협의

### 6-3. 민감정보 마스킹

- `resource_detail` JSONB에 비밀번호/토큰 들어가면 안 됨
- 어노테이션 `detailExpr` 작성 시 화이트리스트 필드만 추출
- 코드 리뷰 체크리스트 필수 항목으로 추가

### 6-4. 조회 API 페이징

접속 로그와 동일 패턴:
- `GET /admin/logs/activity` — 페이지/검색 조건 (from, to, employeeId, deptId, activityType, resourceType, result)
- `GET /admin/logs/activity/{id}` — 상세 조회 (resource_detail 포함)

---

## 7. 권장 결정 요약

| 항목 | 권장 |
|------|------|
| 트리거 방식 | AOP + `@ActivityLog` |
| 리소스 컬럼 | `resource_type` + `resource_id` + `resource_detail(JSONB)` 3분할 |
| detail 추출 | SpEL 기본, 복잡 케이스만 ContextHolder |
| 변경 추적 | 1차: 필드명 리스트 / 2차(요건 발생 시): before/after |
| READ 적재 | 관리자 + 민감 도메인만 |
| 패키지 | 접속 로그와 동일 구조 |
| 적재 정책 | 비동기 + REQUIRES_NEW + 실패 흡수 |

---

## 8. 진행 순서 제안

1. DDL 작성 (`dinai-db/init/01_schema.sql`에 추가)
2. enum / 어노테이션 / Aspect 골격
3. Service / Repository / Mapper / XML
4. ClientInfoExtractor 재활용 확인
5. 샘플 컨트롤러 1개 적용 (예: 사용자 목록 조회) — 어노테이션 동작 검증
6. AdminActivityLogController + DTO + 페이징
7. 핵심 도메인(USER/DEPT/FILE) 컨트롤러 일괄 어노테이션 부착
8. 통합 테스트 (성공/실패/SpEL 평가)
