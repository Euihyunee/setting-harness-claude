#!/bin/bash
# =============================================================================
# PostToolUse Hook - README.md 의 에이전트/스킬 목록 자동 동기화
# - .claude/agents/*.md 또는 .claude/skills/*/SKILL.md 가 편집될 때만 동작
# - README.md 의 AUTO-GENERATED 마커 사이를 재생성
#
# PostToolUse 는 차단 불가 (정보성 훅). Exit 0 항상.
# =============================================================================

INPUT=$(cat)

if command -v jq &>/dev/null; then
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
else
  TOOL_NAME=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
  exit 0
fi

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

NORMALIZED=$(echo "$FILE_PATH" | tr '\\' '/')
if ! echo "$NORMALIZED" | grep -qE '\.claude/agents/[^/]+\.md$|\.claude/skills/[^/]+/SKILL\.md$'; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
README="$PROJECT_DIR/README.md"
AGENTS_DIR="$PROJECT_DIR/.claude/agents"
SKILLS_DIR="$PROJECT_DIR/.claude/skills"

if [ ! -f "$README" ]; then
  exit 0
fi

START_MARKER="<!-- AUTO-GENERATED:AGENTS-SKILLS:START -->"
END_MARKER="<!-- AUTO-GENERATED:AGENTS-SKILLS:END -->"

if ! grep -qF "$START_MARKER" "$README" || ! grep -qF "$END_MARKER" "$README"; then
  echo "WARN: README.md 에 AUTO-GENERATED 마커가 없습니다. 동기화 건너뜀." >&2
  exit 0
fi

extract_meta() {
  local file="$1"
  local name desc
  name=$(awk '
    /^---[[:space:]]*$/ { n++; if (n>=2) exit; next }
    n==1 && /^name:/ {
      sub(/^name:[[:space:]]*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print; exit
    }
  ' "$file")

  desc=$(awk '
    /^---[[:space:]]*$/ { n++; if (n>=2) exit; next }
    n!=1 { next }
    collecting && /^[a-zA-Z][a-zA-Z0-9_-]*:/ { exit }
    /^description:/ {
      sub(/^description:[[:space:]]*[>|]?[-+]?[[:space:]]*/, "")
      if (length($0) > 0) print
      collecting=1; next
    }
    collecting && /^[[:space:]]+/ {
      line=$0; sub(/^[[:space:]]+/, "", line); print line
    }
  ' "$file" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//; s/|/\\|/g')

  if [ -z "$name" ]; then
    name=$(basename "$(dirname "$file")")
    if [ "$name" = "agents" ] || [ "$name" = "skills" ]; then
      name=$(basename "$file" .md)
    fi
  fi

  printf '%s\t%s\n' "$name" "$desc"
}

gen_section() {
  local title="$1" dir="$2" pattern="$3"
  local has_any=0 line name desc

  for f in $dir/$pattern; do
    [ -f "$f" ] || continue
    has_any=1
    break
  done

  if [ "$has_any" -eq 0 ]; then
    echo "### $title"
    echo ""
    echo "_(없음)_"
    echo ""
    return
  fi

  echo "### $title"
  echo ""
  echo "| 이름 | 설명 |"
  echo "|---|---|"
  for f in $dir/$pattern; do
    [ -f "$f" ] || continue
    line=$(extract_meta "$f")
    name="${line%%	*}"
    desc="${line#*	}"
    [ "$desc" = "$line" ] && desc=""
    echo "| \`$name\` | $desc |"
  done
  echo ""
}

NEW_CONTENT=$(
  gen_section "에이전트" "$AGENTS_DIR" "*.md"
  gen_section "스킬" "$SKILLS_DIR" "*/SKILL.md"
)

TEMP=$(mktemp)
awk -v start="$START_MARKER" -v end="$END_MARKER" -v content="$NEW_CONTENT" '
  $0 == start { print; print ""; print content; in_block=1; next }
  $0 == end { in_block=0; print; next }
  !in_block { print }
' "$README" > "$TEMP"

if ! cmp -s "$TEMP" "$README"; then
  mv "$TEMP" "$README"
  echo "SYNC: README.md 의 에이전트/스킬 목록을 갱신했습니다." >&2
else
  rm -f "$TEMP"
fi

exit 0
