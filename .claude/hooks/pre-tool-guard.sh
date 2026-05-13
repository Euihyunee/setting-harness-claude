#!/bin/bash
# =============================================================================
# PreToolUse Guard Hook
# - 위험 명령 차단 (rm -rf, git push --force, git reset --hard)
# - 보호 파일 수정 차단 (.env, package-lock.json, gradlew 등)
# - 에이전트 파일 소유권 경계 검증
#
# Exit codes:
#   0 = allow (진행 허용)
#   2 = deny  (차단, stderr 메시지가 Claude에 전달됨)
# =============================================================================

INPUT=$(cat)

# jq 의존성 확인
if ! command -v jq &>/dev/null; then
  echo "WARNING: jq is not installed. Hook skipped." >&2
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# -----------------------------------------------------------------------------
# 1. Bash 명령 가드
#    (rm -rf, git push --force, git reset --hard 은 settings.json deny에서
#     이미 차단되므로 여기서는 deny로 잡히지 않는 추가 위험만 방어)
# -----------------------------------------------------------------------------
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  # DROP TABLE / DROP DATABASE 차단
  if echo "$COMMAND" | grep -qiE '(DROP\s+TABLE|DROP\s+DATABASE|TRUNCATE\s+TABLE)'; then
    echo "BLOCKED: Destructive SQL operations are prohibited." >&2
    exit 2
  fi

  # curl/wget로 외부 스크립트 파이핑 차단
  if echo "$COMMAND" | grep -qE '(curl|wget)\s+.*\|\s*(bash|sh|python|node)'; then
    echo "BLOCKED: Piping external scripts to shell is prohibited." >&2
    exit 2
  fi

  # git push --force 차단 (--force-with-lease는 허용)
  if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force($|\s)' && \
     ! echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force-with-lease'; then
    echo "BLOCKED: git push --force is prohibited. Use --force-with-lease instead." >&2
    exit 2
  fi

  # -----------------------------------------------------------------------------
  # 보호 브랜치(main / master / develop) 직접 push 차단
  # 정책: feature 브랜치에서 작업 후 PR/머지. 보호 브랜치 직접 push 금지.
  # -----------------------------------------------------------------------------
  PROTECTED='main|master|develop'

  # git push 감지 (git 뒤에 -C <dir>, --git-dir=, --work-tree= 등의 옵션이 낄 수 있음)
  GIT_PUSH='(^|[[:space:];&|])git[[:space:]]+((-C|--git-dir|--work-tree)([[:space:]]+|=)\S+[[:space:]]+)*push'

  if echo "$COMMAND" | grep -qE "$GIT_PUSH"; then
    # Case A: --all / --mirror — 보호 브랜치 포함 가능
    if echo "$COMMAND" | grep -qE 'push[[:space:]]+.*(--all|--mirror)(\s|$)' || \
       echo "$COMMAND" | grep -qE '(--all|--mirror)[[:space:]].*push'; then
      echo "BLOCKED: git push --all / --mirror includes protected branches. Push specific feature branch instead." >&2
      exit 2
    fi

    # Case B: 명시적 브랜치 인자 (git push [opts] <remote> <refspec>)
    #   refspec 형태: <branch> / +<branch> / <src>:<dst> / +<src>:<dst>
    #   dst(또는 단일 branch)가 보호 브랜치면 차단
    #   예: origin main / origin HEAD:main / origin +main / origin +feat:develop
    if echo "$COMMAND" | grep -qE "(^|[[:space:]])\+?([^[:space:]]+:)?($PROTECTED)([[:space:]]|$)"; then
      HIT=$(echo "$COMMAND" | grep -oE "(^|[[:space:]])\+?([^[:space:]]+:)?($PROTECTED)([[:space:]]|$)" | grep -oE "($PROTECTED)" | head -1)
      echo "BLOCKED: Direct push to protected branch '$HIT' is prohibited. Work on a feature branch and merge via PR." >&2
      exit 2
    fi

    # Case C: 인자 없는 `git push` — 현재 브랜치가 보호 브랜치이면 차단
    #   command 안의 `cd <dir>` 또는 `git -C <dir>` 로 작업 디렉터리 추출 시도
    if echo "$COMMAND" | grep -qE 'git[[:space:]]+push[[:space:]]*(\s--[[:alnum:]-]+(=\S+)?)*[[:space:]]*$'; then
      WORK_DIR=$(echo "$COMMAND" | grep -oE 'cd[[:space:]]+[^[:space:]&|;]+' | head -1 | sed -E 's/^cd[[:space:]]+//')
      [ -z "$WORK_DIR" ] && WORK_DIR=$(echo "$COMMAND" | grep -oE -- '-C[[:space:]]+[^[:space:]&|;]+' | head -1 | sed -E 's/^-C[[:space:]]+//')
      [ -z "$WORK_DIR" ] && WORK_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
      # 상대경로면 PROJECT_DIR 기준으로 해석
      case "$WORK_DIR" in
        /*|[A-Za-z]:*) ;;
        *) WORK_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/$WORK_DIR" ;;
      esac

      CURRENT_BRANCH=$(cd "$WORK_DIR" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
      if echo "$CURRENT_BRANCH" | grep -qE "^($PROTECTED)$"; then
        echo "BLOCKED: Current branch '$CURRENT_BRANCH' in '$WORK_DIR' is protected. Switch to a feature branch first." >&2
        exit 2
      fi
    fi
  fi
fi

# -----------------------------------------------------------------------------
# 2. 파일 수정 가드 (Edit / Write)
# -----------------------------------------------------------------------------
if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  # .env 파일 수정 차단 (.env.template, .env.example만 허용)
  if echo "$FILE_PATH" | grep -qE '\.env($|\..*)' && \
     ! echo "$FILE_PATH" | grep -qE '\.(template|example)$'; then
    echo "BLOCKED: .env files must not be modified. Use .env.template or .env.example instead." >&2
    exit 2
  fi

  # package-lock.json 직접 수정 차단
  if echo "$FILE_PATH" | grep -qE 'package-lock\.json$'; then
    echo "BLOCKED: package-lock.json should not be edited directly. Use npm install." >&2
    exit 2
  fi

  # gradlew / gradlew.bat 수정 차단
  if echo "$FILE_PATH" | grep -qE 'gradlew(\.bat)?$'; then
    echo "BLOCKED: Gradle wrapper files should not be modified directly." >&2
    exit 2
  fi

  # .git/ 내부 파일 수정 차단
  if echo "$FILE_PATH" | grep -qE '[/\\]\.git[/\\]'; then
    echo "BLOCKED: .git internal files must not be modified." >&2
    exit 2
  fi
fi

# -----------------------------------------------------------------------------
# All checks passed
# -----------------------------------------------------------------------------
exit 0
