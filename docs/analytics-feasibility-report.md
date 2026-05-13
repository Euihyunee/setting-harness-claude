# DINAI 분석 지표 가능성 종합 보고서

조사 일자: 2026-04-28
대상: `dinai-db/init/01_schema.sql` 및 관련 마이그레이션

---

## 0. 핵심 데이터 자산 요약

| 테이블 | 역할 | 주요 컬럼 |
|---|---|---|
| `dinai.access_logs` | 로그인/접근 이력 | employee_id, dept_id, access_type, ip_address, session_id, error_message, created_at |
| `dinai.users` | 사용자 마스터 | employee_id, username, dept_code, last_login_at |
| `dinai.dept` | 부서 마스터 | dept_code, dept_name, company_code, parent_code |
| `dinai.agents` | 에이전트(특화 포함) | id, name, agent_type, is_active |
| `dinai.agent_runs` | 에이전트 실행 단위 | id, agent_id, employee_id, status, total_duration_ms |
| `dinai.chat_agent_runs` | 대화↔에이전트 실행 매핑 | agent_run_id, conversation_id, session_id |
| `dinai.chat_sessions` | 채팅 세션 | id, employee_id, created_at |
| `dinai.conversations` | 질문/응답 1건 | id, session_id, prompt, response, created_at |
| `dinai.ai_model_calls` | LLM 호출 1건(원장) | id, model_id, employee_id, agent_run_id, input/output_tokens, cache_tokens, status, error_code, latency_ms, created_at |
| `dinai.ai_model_pricing` | 모델별 단가 | model_id, token_type, cost(USD) |
| `dinai.mart_cost_daily` | 일별 비용 마트 | (std_date, dept_id, employee_id, agent_id, model_id) PK + 토큰/비용/콜수 |
| `dinai.mart_active_users` | 일별 활성 사용자 마트 | std_date, employee_id, session_count, conversation_count |
| `dinai.cost_quota` | 부서 한도 | dept_id, limit_usd (주기 컬럼 없음) |
| `dinai.daily_cost_usage` | 일별 부서 누적 사용 | dept_code, usage_date, used_cost |
| `dinai.audit_logs` | 감사 로그 | employee_id, log_type, ip_address, error_message |
| `dinai.refresh_tokens` | 활성 세션 | employee_id, session_id, ip_address, last_seen_at |

---

## 1. 누적 접속자 수 / 일일 접속자 수

**가능. 데이터 출처:** `dinai.access_logs`

```sql
-- 누적 (중복 제거)
SELECT COUNT(DISTINCT employee_id) AS total_visitors
FROM dinai.access_logs
WHERE access_type = 'LOGIN' AND result = 'SUCCESS';

-- 일일
SELECT DATE(created_at) AS d,
       COUNT(DISTINCT employee_id) AS daily_unique_visitors
FROM dinai.access_logs
WHERE access_type = 'LOGIN' AND result = 'SUCCESS'
GROUP BY 1
ORDER BY 1 DESC;
```

---

## 2. 총 사용 비용

**가능. 데이터 출처:** `mart_cost_daily` (집계) 또는 `ai_model_calls × ai_model_pricing` (원장)

```sql
-- 누적 총비용
SELECT SUM(total_cost_usd) AS total_usd
FROM dinai.mart_cost_daily;

-- 일자별
SELECT std_date, SUM(total_cost_usd) AS daily_usd
FROM dinai.mart_cost_daily
GROUP BY std_date
ORDER BY std_date DESC;
```

---

## 3. 총 질문 수 / 일일 질문 수

**가능. 데이터 출처:** `dinai.conversations`

```sql
-- 누적
SELECT COUNT(*) AS total_questions
FROM dinai.conversations
WHERE is_deleted = false;

-- 일일
SELECT DATE(created_at) AS d, COUNT(*) AS daily_questions
FROM dinai.conversations
WHERE is_deleted = false
GROUP BY 1
ORDER BY 1 DESC;
```

대안: `mart_active_users.conversation_count` 합계로도 동일 산출.

---

## 4. 총 세션 수 / 일평균 세션 수

**가능. 데이터 출처:** `dinai.chat_sessions`

```sql
-- 누적 세션
SELECT COUNT(*) AS total_sessions FROM dinai.chat_sessions;

-- 일평균
SELECT AVG(daily_cnt) AS avg_daily_sessions
FROM (
  SELECT DATE(created_at) d, COUNT(*) daily_cnt
  FROM dinai.chat_sessions
  GROUP BY 1
) t;
```

---

## 5. Conversation 1건당 비용

**가능. 경로:** `chat_agent_runs(conversation_id ↔ agent_run_id)` → `ai_model_calls` → `ai_model_pricing`

```sql
WITH per_call AS (
  SELECT c.agent_run_id,
         c.input_tokens  * pi.cost AS input_cost,
         c.output_tokens * po.cost AS output_cost
  FROM dinai.ai_model_calls c
  JOIN dinai.ai_model_pricing pi
    ON pi.model_id = c.model_id AND pi.token_type = 'input'
  JOIN dinai.ai_model_pricing po
    ON po.model_id = c.model_id AND po.token_type = 'output'
)
SELECT car.conversation_id,
       SUM(input_cost + output_cost) AS cost_usd
FROM dinai.chat_agent_runs car
JOIN per_call p ON p.agent_run_id = car.agent_run_id
GROUP BY car.conversation_id
ORDER BY cost_usd DESC;
```

간이 추정: `mart_cost_daily.total_cost_usd / mart_active_users.conversation_count` (일자·사용자 매칭).

---

## 6. 특화 에이전트별 사용량 (질문/호출)

**가능. 출처:** `agents.agent_type` + `agent_runs.agent_id`

```sql
SELECT a.id, a.name, a.agent_type,
       COUNT(DISTINCT car.conversation_id) AS questions,
       COUNT(DISTINCT ar.id)               AS agent_runs,
       COUNT(c.id)                         AS llm_calls
FROM dinai.agents a
LEFT JOIN dinai.agent_runs ar      ON ar.agent_id      = a.id
LEFT JOIN dinai.chat_agent_runs car ON car.agent_run_id = ar.id
LEFT JOIN dinai.ai_model_calls c    ON c.agent_run_id   = ar.id
WHERE a.is_active = true
GROUP BY a.id, a.name, a.agent_type
ORDER BY questions DESC;
```

---

## 7. 특화 에이전트별 비용

**가능. 출처:** `mart_cost_daily.agent_id` (이미 분리 집계됨)

```sql
SELECT m.agent_id, a.name, a.agent_type,
       SUM(m.total_cost_usd) AS cost_usd,
       SUM(m.call_count)     AS calls
FROM dinai.mart_cost_daily m
JOIN dinai.agents a ON a.id = m.agent_id
GROUP BY m.agent_id, a.name, a.agent_type
ORDER BY cost_usd DESC;
```

---

## 8. 부서/사용자 월별 누적 사용량 · 예산 · 실사용

**부분 가능.** 사용량/실사용은 `mart_cost_daily`로 즉시 집계. **단 `cost_quota`에 주기 컬럼 부재** → 월 예산 운영 시 스키마 보강 권장.

```sql
-- 월별 누적 (부서/사용자)
SELECT TO_CHAR(std_date, 'YYYY-MM') AS ym,
       dept_id, employee_id,
       SUM(call_count)     AS monthly_calls,
       SUM(input_tokens)   AS monthly_input_tokens,
       SUM(output_tokens)  AS monthly_output_tokens,
       SUM(total_cost_usd) AS monthly_cost_usd
FROM dinai.mart_cost_daily
GROUP BY ym, dept_id, employee_id
ORDER BY ym DESC, monthly_cost_usd DESC;

-- 부서 한도 vs 실사용 비교
SELECT m.ym, m.dept_id,
       q.limit_usd AS budget_usd,
       SUM(m.monthly_cost_usd) AS actual_usd,
       q.limit_usd - SUM(m.monthly_cost_usd) AS remaining_usd
FROM (
  SELECT TO_CHAR(std_date,'YYYY-MM') ym, dept_id,
         SUM(total_cost_usd) monthly_cost_usd
  FROM dinai.mart_cost_daily GROUP BY 1,2
) m
LEFT JOIN dinai.cost_quota q ON q.dept_id = m.dept_id
GROUP BY m.ym, m.dept_id, q.limit_usd;
```

> ⚠️ **스키마 보강 필요(월 예산 운영 시):** `cost_quota`에 `period`(MONTHLY/DAILY/ANNUAL), `period_start`, `period_end` 컬럼 추가, 또는 `cost_quota_monthly(dept_id, ym, limit_usd)` 신설.

---

## 9. 다중 필터(에이전트/모델/부서/사용자/기간) → 질문 + 비용

**가능. 단일 마트로 처리.** `mart_cost_daily`의 PK가 (std_date, dept_id, employee_id, agent_id, model_id)이라 5차원 모두 동시 필터 가능.

```sql
SELECT SUM(call_count)     AS calls,
       SUM(input_tokens)   AS input_tokens,
       SUM(output_tokens)  AS output_tokens,
       SUM(total_cost_usd) AS cost_usd
FROM dinai.mart_cost_daily
WHERE std_date BETWEEN :from_date AND :to_date
  AND (:agent_id IS NULL OR agent_id    = :agent_id)
  AND (:model_id IS NULL OR model_id    = :model_id)
  AND (:dept_id  IS NULL OR dept_id     = :dept_id)
  AND (:emp_id   IS NULL OR employee_id = :emp_id);
```

질문(conversation) 수가 **정확히** 필요하면 `chat_agent_runs` 경유 별도 집계:

```sql
SELECT COUNT(DISTINCT car.conversation_id) AS questions
FROM dinai.chat_agent_runs car
JOIN dinai.agent_runs ar ON ar.id = car.agent_run_id
JOIN dinai.users u ON u.employee_id = ar.employee_id
WHERE ar.created_at BETWEEN :from_date AND :to_date
  AND (:agent_id IS NULL OR ar.agent_id   = :agent_id)
  AND (:dept_id  IS NULL OR u.dept_code   = :dept_id)
  AND (:emp_id   IS NULL OR ar.employee_id = :emp_id);
```

---

## 10. Top 10 부서 (에이전트/모델/기간 필터)

**가능.**

```sql
SELECT m.dept_id, d.dept_name,
       SUM(m.total_cost_usd) AS cost_usd,
       SUM(m.call_count)     AS calls
FROM dinai.mart_cost_daily m
LEFT JOIN dinai.dept d ON d.dept_code = m.dept_id
WHERE m.std_date BETWEEN :from_date AND :to_date
  AND (:agent_id IS NULL OR m.agent_id = :agent_id)
  AND (:model_id IS NULL OR m.model_id = :model_id)
GROUP BY m.dept_id, d.dept_name
ORDER BY cost_usd DESC
LIMIT 10;
```

---

## 11. 에이전트 1회 호출당 상세 (사용일자/사용자명/부서명/비용/토큰/IP/실패사유)

**부분 가능 — 6/7 컬럼 즉시, IP는 JOIN 추적 필요, 실패메시지는 코드만 존재.**

| 요청 컬럼 | 가능 여부 | 데이터 출처 |
|---|---|---|
| 사용일자 | ✅ | `ai_model_calls.created_at` |
| 사용자명 | ✅ | `users.username` (JOIN by employee_id) |
| 부서명 | ✅ | `dept.dept_name` (JOIN by dept_code) |
| 비용 | ✅ | `ai_model_calls × ai_model_pricing` |
| 토큰 사용량 | ✅ | `ai_model_calls.input_tokens / output_tokens / cache_*_tokens` |
| 접근 IP | ⚠️ | `ai_model_calls`엔 없음 → `access_logs`/`refresh_tokens` JOIN 필요 |
| 실패 사유 | ⚠️ | `ai_model_calls.status` + `error_code`만 존재(`error_message` 컬럼 없음) |

### SQL (현재 스키마 기준)

```sql
WITH call_cost AS (
  SELECT c.id,
         c.created_at,
         c.employee_id,
         c.agent_run_id,
         c.model_id,
         c.input_tokens,
         c.output_tokens,
         c.cache_read_tokens,
         c.cache_write_5m_tokens + c.cache_write_1h_tokens AS cache_write_tokens,
         c.status,
         c.error_code,
         c.latency_ms,
         (c.input_tokens  * COALESCE(pi.cost,0)) +
         (c.output_tokens * COALESCE(po.cost,0)) +
         (c.cache_read_tokens          * COALESCE(pcr.cost,0)) +
         (c.cache_write_5m_tokens      * COALESCE(pcw5.cost,0)) +
         (c.cache_write_1h_tokens      * COALESCE(pcw1.cost,0)) AS cost_usd
  FROM dinai.ai_model_calls c
  LEFT JOIN dinai.ai_model_pricing pi   ON pi.model_id   = c.model_id AND pi.token_type   = 'input'
  LEFT JOIN dinai.ai_model_pricing po   ON po.model_id   = c.model_id AND po.token_type   = 'output'
  LEFT JOIN dinai.ai_model_pricing pcr  ON pcr.model_id  = c.model_id AND pcr.token_type  = 'cache_read'
  LEFT JOIN dinai.ai_model_pricing pcw5 ON pcw5.model_id = c.model_id AND pcw5.token_type = 'cache_write_5m'
  LEFT JOIN dinai.ai_model_pricing pcw1 ON pcw1.model_id = c.model_id AND pcw1.token_type = 'cache_write_1h'
)
SELECT
  cc.created_at                                AS used_at,
  u.employee_id,
  u.username                                   AS user_name,
  d.dept_name,
  a.name                                       AS agent_name,
  a.agent_type,
  cc.model_id,
  cc.input_tokens,
  cc.output_tokens,
  cc.cache_read_tokens,
  cc.cache_write_tokens,
  cc.cost_usd,
  cc.status,                                   -- SUCCESS/FAILED 등
  cc.error_code,                               -- 실패 코드(메시지 컬럼은 없음)
  cc.latency_ms,
  -- IP: chat_agent_runs.session_id ↔ refresh_tokens.session_id 또는 access_logs.session_id 매칭
  rt.ip_address                                AS access_ip
FROM call_cost cc
JOIN dinai.agent_runs ar ON ar.id = cc.agent_run_id
JOIN dinai.agents a       ON a.id = ar.agent_id
JOIN dinai.users  u       ON u.employee_id = cc.employee_id
LEFT JOIN dinai.dept d    ON d.dept_code   = u.dept_code
LEFT JOIN dinai.chat_agent_runs car ON car.agent_run_id = cc.agent_run_id
LEFT JOIN LATERAL (
  SELECT ip_address
  FROM dinai.refresh_tokens rt
  WHERE rt.session_id = car.session_id
  ORDER BY rt.last_seen_at DESC
  LIMIT 1
) rt ON true
ORDER BY cc.created_at DESC;
```

### 보강 권장 (완전한 1회 호출 감사용)
1. `ai_model_calls.error_message TEXT` 컬럼 추가 — 현재는 `error_code`만 있어 원인 파악 제한적.
2. `ai_model_calls.ip_address INET` 컬럼 추가 또는 호출 시 `audit_logs`에 LLM_CALL 이벤트로 기록 — IP를 세션 JOIN으로 역추적하지 않고 직접 저장.
3. (선택) `ai_model_calls.user_agent`도 함께 기록 시 디바이스/브라우저 추적 가능.

---

## 12. 종합 가능성 매트릭스

| # | 지표 | 즉시 가능 | 필요 보강 |
|---|---|---|---|
| 1 | 누적/일일 접속자 | ✅ | — |
| 2 | 총 사용 비용 | ✅ | — |
| 3 | 총/일일 질문 수 | ✅ | — |
| 4 | 세션 수/일평균 | ✅ | — |
| 5 | Conversation당 비용 | ✅ | — |
| 6 | 에이전트별 사용량 | ✅ | — |
| 7 | 에이전트별 비용 | ✅ | — |
| 8 | 월 누적 사용/실사용 | ✅ | — |
| 8' | **월 예산** | ⚠️ | `cost_quota`에 주기 컬럼(period/period_start/end) 추가 |
| 9 | 다중필터 질문/비용 | ✅ | — |
| 10 | Top10 부서 | ✅ | — |
| 11 | 호출당 상세(IP/에러) | ⚠️ | `ai_model_calls`에 `ip_address`, `error_message` 컬럼 추가 |

---

## 13. 권장 후속 작업

1. **신규 마트:** `mart_cost_monthly` 또는 `mart_cost_dept_monthly` — 대시보드 응답속도 향상
2. **`cost_quota` 확장:** 월 단위 예산 운영을 위해 주기 컬럼 추가
3. **`ai_model_calls` 확장:** `ip_address`, `error_message` 추가로 호출 단위 감사 완전성 확보
4. **공통 뷰 추가:**
   - `v_call_detail` — 11번 SQL을 뷰화 (관리 화면 직결)
   - `v_dept_monthly_budget` — 8번 비교 쿼리 뷰화
5. **API 노출:** `dinai-core-api`에 통계 엔드포인트 그룹 (`/admin/stats/*`) 신설, 위 SQL을 MyBatis 매퍼로 래핑
