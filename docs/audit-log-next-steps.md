# Audit Log 다음 작업 (다음 세션 핸드오프)

> **이 파일은 Claude가 다음 세션에서 읽을 컨텍스트입니다.**
> 사람을 위한 설명이 아니라 LLM이 작업을 이어갈 수 있는 최소 정보만 담음.

---

## 지금까지 완료된 것

1. **설계 문서**: `docs/activity-log-aop-design.md` (1078줄, 한국어 본문 + 영어 코드명 audit)
2. **DB**: `dinai-db/init/01_schema.sql` + `migrations/013_audit_logs_extend.sql` + `014_audit_logs_rename_track_id_to_trace_id.sql` + `015_audit_logs_drop_unused_columns.sql`
   - 테이블 `dinai.audit_logs` (단일 테이블, 영구 보관)
   - 컬럼: id, employee_id, actor_name, dept_id, log_type, resource_type, resource_id, result, ip_address, user_agent, session_id, trace_id, error_message, extra_data, created_at, **+ category, description** (013으로 확장 → 015에서 request_uri / http_method / duration_ms / access_path 제거)
3. **백엔드 (dinai-core-api)** — 활동 로그 인프라 + 공지사항 적용 완료
   - `domain/audit/`: AuditActionType (8 enum), AuditCategory, ResourceType (14 enum), repository port, filter
   - `application/aspect/`: `@AuditLog(action, resource, description?, onFailureOnly?)` 어노테이션, `AuditLogAspect` (Around), `AuditContext` (ThreadLocal: detail, parentResource, message, markFailure, resourceId), `AuditDetailExtractor`
   - `application/`: `AuditLogService` (record + recordSystem, @Async logExecutor + REQUIRES_NEW), `AuditLogCommand`, `AuditLogConstants`
   - `infrastructure/persistence/`: AuditLogRecord/ListRecord/DetailRecord, MybatisAuditLogRepository, AuditLogMapper + auditLogs.xml
   - `interfaces/`: `AdminLogController` (접속/감사 로그 통합 — `GET /admin/logs/access`, `/access/{id}`, `/audit`, `/audit/{id}`), 검색 Request DTO, ListResponse / DetailResponse
   - `NoticeController` + `AdminNoticeController` 9개 메서드 어노테이션 적용 완료
   - `NoticeAuditLogger` (logback 파일 로그) 완전 제거됨
4. **프론트엔드 (dinai-client)** — 활동로그 탭 백엔드 연동 완료
   - `entities/admin-log/api/auditLogApi.ts`: `useAuditLogs`, `useAuditLogDetail`
   - `entities/admin-log/lib/labels.ts`: ACTIVITY_MATRIX (action × resource → 한글 라벨), getActivityLabel/getRemarkLabel/getErrorMessageLabel
   - `entities/admin-log/model/types.ts`, `mappers.ts`, `index.ts` 갱신
   - `pages/admin/ui/LogMonitoringPage.tsx`: mock 제거, 실 API 연결, 활동로그 전용 필터(logType/resourceType/category) + 11컬럼 테이블 + AuditLogDetailContent / AuditLogDetailBody

빌드 상태: 백엔드 `./gradlew build -x test` BUILD SUCCESSFUL, 프론트 `npm run type-check` / `npm run build` 통과.

---

## 다음 작업 후보 (우선순위순)

### A. 백엔드 도메인 추가 적용 (가장 가치 높음)

다음 도메인 컨트롤러에 `@AuditLog` 부착. 매번 패턴 동일:

#### A-1. 계정/인증 — UPDATE+ACCOUNT 매트릭스 (권장 다음 작업)
- 비밀번호 변경: `@AuditLog(action=UPDATE, resource=ACCOUNT, description="비밀번호 변경")`
- 계정 잠금/해제: `@AuditLog(action=UPDATE, resource=ACCOUNT, description="계정 잠금"|"계정 잠금 해제")`
- 검색 위치: `dinai-core-api/src/main/java`에서 `password|lock|unlock` 메서드 grep
- description 명시 필수 (같은 UPDATE+ACCOUNT라 매트릭스 자동 라벨로 구분 안 됨)

#### A-2. 관리자 시스템 영역 (`/api/admin/system/**`)
- 권한 부여/회수/변경: `CREATE/DELETE/UPDATE + PERMISSION`
- 사용자 관리: `READ/UPDATE/DELETE + USER`
- 설정 변경: `UPDATE + SETTING`
- 사용량 변경: `UPDATE + QUOTA`
- 검색: `AdminUserController`, `AdminPermissionController`, `AdminSettingController` 등 grep

#### A-3. 파일/대화
- 파일 단일/다중 업로드: `UPLOAD + FILE` (다중은 `AuditContext.parentResource(POST/CONVERSATION).detail("count", N)`)
- 파일 다운로드: `DOWNLOAD + FILE`
- AI 대화 시작: `CREATE + CONVERSATION`

#### A-4. AI/지식
- 에이전트 실행: `EXECUTE + AGENT`
- 지식 검색: `EXTRACT + KNOWLEDGE` + `AuditContext.detail("count", hitCount)`
- RAG 적재: `CREATE + KNOWLEDGE` + `AuditContext.detail("count", chunkCount)`

### B. 테스트 작성
- `AuditLogAspectTest`: AspectJProxyFactory 기반 단위 테스트 (성공/예외/markFailure/actor_name 미인증 케이스)
- `AuditDetailExtractorTest`: @PathVariable / 리턴 getId 추출 검증
- `AuditLogMapperRepositoryTest`: Testcontainers + init-test.sql, 새 컬럼/제약/인덱스 검증
- `ActivityCategory ↔ AuditCategory` enum 정합성: DB CHECK 제약과 enum 동기화

### C. 프론트엔드 보강
- 부서 드롭다운 하드코딩(`'생산물류본부'`) 제거 → `/admin/departments` API 연동
- 이름 검색(actorName like) — 백엔드 `AuditLogSearchRequest`에 actorName 필드 추가 + Mapper WHERE 조건
- Excel 다운로드 — 백엔드 `/admin/logs/audit/export` 엔드포인트 (CSV/XLSX) + 프론트 버튼 wiring
- 대화로그/가드레일 탭은 백엔드 API 미존재라 보류

### D. 운영 최적화 (관찰 후)
- 부분 인덱스: `CREATE INDEX idx_audit_context_id ON dinai.audit_logs ((extra_data->'context'->>'id')) WHERE log_type IN ('UPLOAD','DOWNLOAD','DELETE') AND resource_type='FILE';`
- 월별 RANGE 파티셔닝 (테이블 비대화 시)

---

## 작업 시 주의사항

### 어노테이션 부착 패턴
```java
// 단순 케이스
@AuditLog(action = READ, resource = NOTICE)
public PagedResponse<X> list(...) {
    PagedResponse<X> r = service.list();
    AuditContext.detail("count", r.getTotalCount());  // 비고에 N건
    return r;
}

// 부모 컨텍스트 + 다중 (1요청 = 1 row)
@AuditLog(action = UPLOAD, resource = FILE)
public BatchFileResponse upload(@PathVariable String postId, @RequestParam MultipartFile[] files) {
    AuditContext.parentResource("POST", postId).detail("count", files.length);
    return service.uploadMany(postId, files);
}

// 의미 모호 케이스 (description 필수)
@AuditLog(action = UPDATE, resource = ACCOUNT, description = "비밀번호 변경")
public void changePassword(...) { ... }
```

### 레이어 의존
- `interfaces → application → domain ← infrastructure`
- 새 컨트롤러 메서드는 항상 `@AuditLog` 부착 (관리자 영역 자동 분류는 Aspect가 `HttpServletRequest.getRequestURI()` prefix로 런타임 결정 — DB 미저장)

### category 자동 결정 (어노테이션에 없음)
- 요청 URI가 `/admin/**` 또는 `/api/admin/**` → ADMIN
- 인증 컨텍스트 없음 → SYSTEM
- 그 외 → USER

### actor_name
- `CustomUserDetails.getName()` 자동 추출, 미인증 시 SYSTEM, 50자 truncate

### error_message 코드 카탈로그
ACCESS_DENIED / VALIDATION_FAILED / USER_NOT_FOUND / RESOURCE_NOT_FOUND / QUOTA_EXCEEDED / FILE_SIZE_EXCEEDED / INVALID_FORMAT / DUPLICATE_RESOURCE / BUSINESS_RULE_VIOLATION / EXTERNAL_API_ERROR / INTERNAL_ERROR
(설계 문서 9-2장 참조, BusinessException.ErrorCode enum과 매핑)

---

## 핵심 파일 위치 (빠른 참조)

**설계 문서**: `docs/activity-log-aop-design.md`
**화면 mockup**: `docs/activity-log-screen-mockup.html`

**백엔드 인프라**:
- 어노테이션: `dinai-core-api/src/main/java/com/hiaas/ai/platform/application/aspect/AuditLog.java`
- Aspect: `.../aspect/AuditLogAspect.java`
- ThreadLocal 헬퍼: `.../aspect/AuditContext.java`
- Service: `dinai-core-api/.../application/AuditLogService.java`
- 컨트롤러: `dinai-core-api/.../interfaces/controller/AdminLogController.java` (접속/감사 통합)

**적용 예시 (공지사항)**:
- `dinai-core-api/.../interfaces/controller/NoticeController.java`
- `dinai-core-api/.../interfaces/controller/AdminNoticeController.java`

**프론트엔드**:
- 페이지: `dinai-client/src/pages/admin/ui/LogMonitoringPage.tsx`
- 엔티티: `dinai-client/src/entities/admin-log/`

**access_logs 참조 패턴** (audit_logs와 동일 인프라 사용):
- `dinai-core-api/.../application/AccessLogService.java`
- `dinai-core-api/.../infrastructure/persistence/mapper/AccessLogMapper.java`
- `dinai-core-api/.../infrastructure/util/ClientInfoExtractor.java`
- `dinai-core-api/.../infrastructure/config/AsyncConfig.java` (logExecutor)

---

## 검증 명령어

```bash
# 백엔드
cd dinai-core-api && ./gradlew build -x test

# 프론트
cd dinai-client && npm run check-all
```

---

## 합의된 결정 (이미 끝난 것 — 다시 묻지 말 것)

- 활동유형 = 8개 enum 매트릭스 (CRUD + UPLOAD/DOWNLOAD/EXTRACT/EXECUTE)
- 리소스 = 14개 enum (NOTICE/PERMISSION/USER/...)
- 카테고리 = USER/ADMIN/SYSTEM (Aspect 자동 결정)
- 1요청 = 1 row (다중 파일도 count만)
- extra_data JSONB에는 count + context (type/id)만 적재
- 영구 보관 (이관/삭제 정책 없음)
- 코드명 audit, 한국어 본문 "활동 로그" 유지
- DB 컬럼명: log_type / extra_data / trace_id / actor_name (Java 필드는 action / extraData / traceId / actorName)
- 기존 NoticeAuditLogger 완전 제거 (deprecated 코드 금지 정책)
