#!/bin/bash
# =============================================================================
# PostToolUse(Bash) — Git Sync Hook
# - Claude가 Bash로 git commit / pull / merge / fetch+reset 실행 후 발동
# - 각 서브레포의 CLAUDE.md / 의존성 파일 변경 여부 감지
# - 변경이 있으면 exit 2 + stderr 로 Claude에게 업데이트 필요 여부 검토 요청
#
# 자동 파일 수정은 하지 않음 (의도치 않은 변경 방지)
#
# Exit codes:
#   0 = silent pass (변경 없음 또는 비대상 명령)
#   2 = stderr 메시지를 Claude에 전달 (알림)
# =============================================================================

INPUT=$(cat)

# jq 의존성 확인
if ! command -v jq &>/dev/null; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL_NAME" != "Bash" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exitCode // 0')

# 실패한 명령은 처리 안 함
[ "$EXIT_CODE" != "0" ] && exit 0

# git 계열 명령이 아니면 스킵 (빠른 필터)
echo "$COMMAND" | grep -qE 'git\s+(commit|pull|merge|fetch|rebase|reset)' || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 감시 대상 파일 패턴 — 변경 시 루트 CLAUDE.md / agent 설정에 영향 가능
WATCH_PATTERN='^(CLAUDE\.md|package\.json|package-lock\.json|requirements\.txt|pyproject\.toml|build\.gradle(\.kts)?|settings\.gradle(\.kts)?|Dockerfile.*|docker-compose.*\.ya?ml|Jenkinsfile|nginx.*\.conf|\.env\.(template|example)|init/.*\.sql|migrations/.*\.sql)$'

# -----------------------------------------------------------------------------
# 명령이 실행된 서브레포 추정
# - command 안의 `cd dinai-xxx` 패턴
# - 없으면 PROJECT_DIR 기준 (루트 실행)
# -----------------------------------------------------------------------------
detect_repos() {
  local hits=""
  for repo in dinai-client dinai-core-api dinai-ai-api dinai-db; do
    if echo "$COMMAND" | grep -qE "(^|[[:space:];&|])cd[[:space:]]+[\"']?(\./)?$repo" \
       || echo "$COMMAND" | grep -qE -- "[-]C[[:space:]]+[\"']?(\./)?$repo"; then
      hits="$hits $repo"
    fi
  done
  # cd 패턴이 전혀 없으면 4개 모두 검사 (root 실행 가정)
  if [ -z "$hits" ]; then
    hits="dinai-client dinai-core-api dinai-ai-api dinai-db"
  fi
  echo "$hits"
}

# -----------------------------------------------------------------------------
# 특정 레포의 감시 파일 변경 목록
# -----------------------------------------------------------------------------
changed_watch_files() {
  local repo_dir="$1"
  local range="$2"
  (
    cd "$PROJECT_DIR/$repo_dir" 2>/dev/null || exit 0
    [ ! -d ".git" ] && exit 0
    git diff --name-only "$range" 2>/dev/null | grep -E "$WATCH_PATTERN" || true
  )
}

# -----------------------------------------------------------------------------
# 명령 분류 → diff 범위 결정
# commit:           HEAD~1..HEAD
# pull / merge:     ORIG_HEAD..HEAD  (없으면 HEAD~1..HEAD fallback)
# rebase / reset:   ORIG_HEAD..HEAD
# fetch:            원격만 갱신되므로 별도 알림만
# -----------------------------------------------------------------------------
determine_event_range() {
  if echo "$COMMAND" | grep -qE 'git\s+commit(\s|$)'; then
    echo "commit|HEAD~1..HEAD"
  elif echo "$COMMAND" | grep -qE 'git\s+(pull|merge|rebase|reset)(\s|$)'; then
    echo "pull|ORIG_HEAD..HEAD"
  elif echo "$COMMAND" | grep -qE 'git\s+fetch(\s|$)'; then
    echo "fetch|"
  else
    echo "|"
  fi
}

EVENT_RANGE=$(determine_event_range)
EVENT=$(echo "$EVENT_RANGE" | cut -d'|' -f1)
RANGE=$(echo "$EVENT_RANGE" | cut -d'|' -f2)

[ -z "$EVENT" ] && exit 0

# fetch는 diff 없이 단순 안내
if [ "$EVENT" = "fetch" ]; then
  exit 0
fi

REPOS=$(detect_repos)
REPORT=""

for REPO in $REPOS; do
  # ORIG_HEAD 없으면 fallback
  EFFECTIVE_RANGE="$RANGE"
  if [ "$EVENT" = "pull" ]; then
    if ! (cd "$PROJECT_DIR/$REPO" 2>/dev/null && git rev-parse --verify ORIG_HEAD >/dev/null 2>&1); then
      EFFECTIVE_RANGE="HEAD~1..HEAD"
    fi
  fi

  CHANGED=$(changed_watch_files "$REPO" "$EFFECTIVE_RANGE")
  if [ -n "$CHANGED" ]; then
    REPORT="$REPORT\n[$REPO] ($EVENT)\n$CHANGED\n"
  fi
done

if [ -n "$REPORT" ]; then
  echo -e "🔔 Git 규칙/의존성 변경 감지 — 관련 규칙 업데이트 여부 검토 권장" >&2
  echo -e "$REPORT" >&2
  echo -e "점검 대상:" >&2
  echo -e "  - 루트 CLAUDE.md 기술 스택 표 (버전/의존성 변경 반영)" >&2
  echo -e "  - 에이전트 담당 경로 (.claude/agents/*.md)" >&2
  echo -e "  - 서브레포 CLAUDE.md 세부 규칙 (의존성 추가 시)" >&2
  echo -e "  - 환경변수 동기화 (.env.*.template 변경 시 공유 변수 목록)" >&2
  exit 2
fi

exit 0
