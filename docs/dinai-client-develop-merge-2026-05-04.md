# dinai-client `develop` → `feature/log-module` 머지 결과 (2026-05-04)

## 1. 머지 개요

| 항목 | 값 |
|---|---|
| source | `develop` (tip `6e50aec Merge pull request #85 from diningbrandsgroup/refactor/chat-hooks-cleanup`) |
| target | `feature/log-module` |
| 직전 develop 머지 (reference base) | `cb513f2 Merge branch 'develop' into feature/log-module` (2026-05-04) |
| 머지 방식 | 수동 conflict resolve + `.omc/` staged 정리 + Department.children 타입 정합 fix |

### 그룹 분류

- **A 그룹** (이번 세션 보존 대상) — `cb513f2` 이후 `feature/log-module` 의 사용자 측 commit **10건** (모두 `ehjeong@hiaas.co.kr`)
  - 태그/공통프롬프트 enum 추가 (`146e3d7`)
  - 사용량 설정 X 표기 삭제 (`0814b6c`)
  - 사용자 목록 조회 endpoint 정정 (`a63f602`, `cfe6312`)
  - 최하위 부서 lazy-load 동작 수정 (`5883576`)
  - 활동 로그 목록 포맷 / 검색 필터 / 캐싱 제거 등 audit/log/admin 작업 (`8898776`, `a746b65`, `bf6d118`, `c869380`)
  - 지식 관리자 설정 분리 (`8340db6`, `1d837f9`, `8383939`)

- **B 그룹** (develop 신규 통합 대상) — `cb513f2` 이후 `develop` 약 50여 건
  - **#85** `refactor/chat-hooks-cleanup` (yhkim) — `useChatConversation` cache flush 매커니즘 도입, 동일 질문 렌더링 버그 fix
  - **#83** `feat/creative-lab` (yskwon95) — creative-lab 페이지/위젯 다수, AppRouter 라우트, Sidebar 메뉴, customAlert toast 시스템, 미디어 도메인 (entities/media-asset, entities/media-job, features/media-generation, shared/api/mediaApi, shared/api/mediaSSE)
  - news-clipping 백그라운드 spinner fix (yskwon95 `f321df4`)
  - publishing 측 layout/style 정리 (donghobridge 다수)
  - Pub (#84) 등

## 2. 16개 충돌 파일 resolve 표

| # | 파일 | 그룹 | 결정 / 근거 |
|---|---|---|---|
| 1 | `src/app/routes/AppRouter.tsx` | A+B | 합집합 — `CreativeLabPage` import + `/creative-lab` 라우트 추가 (B), 기존 admin/log 라우트 (A) 보존 |
| 2 | `src/entities/admin-common/api/adminCommonApi.ts` | A | HEAD — `searchUsersByName` path `/admin/common/users/search` 보존 (`cfe6312` 의 endpoint 정정 결과) |
| 3 | `src/entities/quota/api/quotaApi.ts` | A | HEAD — `useDepartmentQuotaTree` 의 `staleTime: 0, gcTime: 0` 보존 (관리자 캐싱 제거 패턴 일관, `bf6d118`) |
| 4 | `src/entities/upload/api/uploadApi.ts` | A | HEAD 주석 — admin 업로드 / 비-admin 조회 권한 구분 보강된 코멘트 |
| 5 | `src/entities/upload/model/useUploadImage.ts` | A | HEAD 주석 — admin 업로드 endpoint 명시 코멘트 |
| 6 | `src/features/agent-owner-management/ui/AgentOwnerModal.tsx` | A | HEAD — audit log 폭증 방지 위해 `treeExpandedIds` 자동 펼침 제거 |
| 7 | `src/features/chat/model/useChatConversation.ts` | B | develop 베이스 — `flushCompletedStreamToCache`, `conversationQueryKey`, `getStream`, `ActiveStream` import 통합. HEAD 의 `handleCopy` / `handleImageDownload` 는 caller 부재 (`ChatMessage.tsx`, `CopyButton.tsx`, `CreativeLabPreview.tsx` 모두 자체 정의) — 안전 drop. HEAD 의 `isDuplicate` dedup 은 develop 의 cache flush 메커니즘으로 대체됨 |
| 8 | `src/features/notice/ui/NoticeDetailView.tsx` | A | HEAD — `@/entities/post` 부재 (community → notice 통합 완료), develop 의 `downloadPostFile` import 는 빌드 파괴 |
| 9 | `src/features/organization/ui/DepartmentTree.tsx` | A | HEAD — develop 의 unused `queryClient` 제거 |
| 10 | `src/features/organization/ui/DepartmentUserTree.tsx` | A | HEAD — `isLeaf: false` 보존 (`5883576` 최하위 부서 lazy-load 수정) |
| 11 | `src/pages/admin/ui/LogMonitoringPage.tsx` | A | HEAD wholesale (1688 lines, `git checkout --ours`) — develop 측 (1151 lines) 은 mock-only shell. 16자 truncate, PROMPT_TEMPLATE/TAG, 16개 enum 주석, 3필드 분리 모두 보존 검증 |
| 12 | `src/pages/admin/ui/UsageSettingsPage.tsx` | A | HEAD wholesale (`git checkout --ours`) — X cancel button 제거 (`0814b6c`) |
| 13 | `src/pages/news-clipping/ClippingViewerPage.tsx` | B | develop — `f321df4 fix(news-clipping): 백그라운드 refetch spinner` 정합 (HEAD 의 `isReportFetching` 잘못된 합산 제거) |
| 14 | `src/shared/lib/customAlert.ts` | B | develop — toast 시스템 통합 (#83), `window.alert` 차단형 모달 → 비차단 toast |
| 15 | `src/widgets/layout/lib/resolveAppMainBarLeading.ts` | A+B | 합집합 — `/creative-lab` 라벨 추가 |
| 16 | `src/widgets/sidebar/ui/Sidebar.tsx` | A+B | 합집합 — creative-lab 메뉴 + `Wand2` icon. develop 가 끌고 온 unused icons (`BarChart3`, `Shield`, `BookOpen`, `Megaphone`) 는 lint 위반 회피 위해 drop, 사용 icons (`Bot`, `ChevronDown`, `MoreVertical`, `LogOut`, `Wand2`) 만 import |

비즈니스 로직 충돌로 사용자 결정 필요 항목 — 없음. `useChatConversation.ts` 의 `handleCopy` / `handleImageDownload` drop 결정은 caller 부재 검증 후 안전 판정.

## 3. `.omc/` 처리

- develop 의 `100c489 feat(creative-lab): UX 핵심 BLOCKER 5건 일괄 수정 (B1~B5)` 가 잘못된 `.gitignore` 변경을 가져옴.
  - 변경 내용: `-.antigravity/` → `+.antigravity/.omc/` (기존 `.antigravity/` 무시 룰을 제거하고 잘못된 합성 경로 1줄로 대체).
- 결과로 `.omc/sessions/4b06dbe2-….json`, `.omc/state/mission-state.json` 2개 파일이 staged 상태로 끌려옴.
- 정리:
  - `git rm --cached -r .omc/` 로 staged 해제
  - `.gitignore` 정정 — `.antigravity/` 라인 복원 + `.omc/` 라인 신규 추가
  - `git check-ignore -v` 로 두 파일 모두 `.gitignore:36:.omc/` 매칭 확인

## 4. 추가 type 에러 fix — `Department.children`

### 사용자 보고 에러
```
Type 'Department[] | undefined' is not assignable to type 'Department[]'.
(property) Department.children: Department[]
```

### 채택 옵션 — A (옵셔널 변경)

`src/entities/organization/model/types.ts:19`
```ts
// before
children: Department[];

// after
children?: Department[];
```

### 근거

기존 사용처 grep 결과 `.children` 접근 **약 60건** 모두 이미 방어적 패턴으로 작성됨:

| 패턴 | 예시 |
|---|---|
| `dept.children ?? []` | `DepartmentTree.tsx:139`, `UsageSettingsPage.tsx:27`, `KnowledgeFileUploadModal.tsx:283` 등 |
| `dept.children?.…` | `DepartmentSearchCombobox.tsx:34`, `Tree.tsx:298`, `CascadingMenu.tsx:262` |
| `dept.children && dept.children.length > 0` | `DepartmentUserTree.tsx:181`, `KnowledgeFileEditModal.tsx:393`, `quotaApi.ts:101` |
| `dept.children \|\| []` | `DepartmentUserTree.tsx:143`, `KnowledgeFileUploadModal.tsx:283` |

타입이 비옵셔널 `Department[]` 면 위 방어 패턴들이 모두 "always truthy" 가 되어 의미 없음. 즉 코드는 이미 옵셔널 가정으로 작성돼 있는데 타입만 비정합 — 실제 BE 응답이 leaf node 의 경우 `children` 필드를 생략 또는 lazy-load 트리에서 미적재 상태로 내려올 수 있는 형태. 옵션 A 가 코드 실태 + BE 실제 응답에 부합.

### 영향 받은 사용처

기존 코드 패턴이 이미 옵셔널 가정 → **call site 추가 적응 0건**. 타입 정의 1줄 변경 (line 19) + 위 의도 명시 JSDoc 5줄 추가만으로 fix 완료.

다른 type 에러 — 없음 (`npx tsc --noEmit` 클린).

## 5. 검증

| 항목 | 결과 |
|---|---|
| `npx tsc --noEmit` | 클린 (출력 없음) |
| `git diff --check` | 0건 |
| `git status` Unmerged paths | 없음 |
| 충돌 마커 잔존 (16 파일 grep) | 0건 |
| lint — 본 resolve 신규 위반 | 0건 (기존 누적 위반은 별도 — `any` / `no-unused-vars` 다수, 본 머지 범위 외) |

## 6. 잔여 작업

- `git commit` — 사용자 직접 (자동 commit 금지, 메시지 초안 미작성)
- 백엔드 (`dinai-core-api`, `dinai-db`) 측 audit 작업은 별도 head 작업, 본 문서 범위 외
- 본 docs 는 `dinai-client` 머지 결과 한정 — `audit-log-rollout-plan.md` 등 다른 문서 갱신 없음
