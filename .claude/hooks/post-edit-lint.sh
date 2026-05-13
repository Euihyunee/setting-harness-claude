#!/bin/bash
# =============================================================================
# PostToolUse Lint Hook
# - 파일 편집 후 프로젝트별 린터/포맷터 자동 실행
# - dinai-client: eslint --fix (상대경로 변환)
# - dinai-ai-api: ruff format + check (설치된 경우)
#
# PostToolUse는 차단 불가 (정보성 훅). Exit 0 항상.
# =============================================================================

INPUT=$(cat)

# jq 의존성 확인
if ! command -v jq &>/dev/null; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Edit 또는 Write만 처리
if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
  exit 0
fi

# 파일 경로가 없으면 skip
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# -----------------------------------------------------------------------------
# dinai-client: TypeScript/TSX 파일 → eslint --fix
# -----------------------------------------------------------------------------
if echo "$FILE_PATH" | grep -qE 'dinai-client/.*\.(ts|tsx)$'; then
  CLIENT_DIR="$PROJECT_DIR/dinai-client"
  ESLINT_BIN="$CLIENT_DIR/node_modules/.bin/eslint"
  if [ -x "$ESLINT_BIN" ]; then
    # 절대경로 → dinai-client 기준 상대경로 변환
    REL_PATH=$(echo "$FILE_PATH" | sed "s|.*dinai-client/||")
    (cd "$CLIENT_DIR" && "$ESLINT_BIN" --fix "$REL_PATH" 2>/dev/null) || true
  else
    echo "SKIP: eslint not installed in dinai-client/node_modules. Run 'npm install' to enable auto-lint." >&2
  fi
  exit 0
fi

# -----------------------------------------------------------------------------
# dinai-ai-api: Python 파일 → ruff format + check (있으면)
# -----------------------------------------------------------------------------
if echo "$FILE_PATH" | grep -qE 'dinai-ai-api/.*\.py$'; then
  if command -v ruff &>/dev/null; then
    ruff format "$FILE_PATH" 2>/dev/null || true
    ruff check --fix "$FILE_PATH" 2>/dev/null || true
  else
    echo "SKIP: ruff not installed. Run 'pip install ruff' to enable auto-format." >&2
  fi
  exit 0
fi

exit 0
