#!/bin/bash
# =============================================================================
# Stop Hook — Quality Gate
# - Claude 응답 완료 시 각 서브 레포별로 변경 감지 → 검증 실행
# - dinai-client: type-check + lint
# - dinai-core-api: gradlew classes (컴파일 검증)
# - dinai-ai-api: pytest (빠른 테스트만)
#
# 주의: temp/ 는 git 레포가 아님. 4개 서브디렉터리가 각각 독립 레포.
#
# Exit codes:
#   0 = pass (정상 완료)
#   2 = fail (Claude에게 수정 요청)
# =============================================================================

INPUT=$(cat)

# jq 의존성 확인
if ! command -v jq &>/dev/null; then
  echo "WARNING: jq is not installed. Hook skipped." >&2
  exit 0
fi

# 무한루프 방지: 파일 기반 재시도 카운터
# Stop 훅 실패 → Claude 수정 → 다시 Stop 훅 반복을 최대 2회로 제한
RETRY_FILE="${TMPDIR:-/tmp}/dinai-stop-hook-retry"
RETRY_COUNT=0
if [ -f "$RETRY_FILE" ]; then
  RETRY_COUNT=$(cat "$RETRY_FILE" 2>/dev/null || echo 0)
  # 카운터 파일이 5분 이상 오래됐으면 리셋 (이전 세션의 잔여 파일)
  if [ "$(find "$RETRY_FILE" -mmin +5 2>/dev/null)" ]; then
    RETRY_COUNT=0
  fi
fi

if [ "$RETRY_COUNT" -ge 2 ]; then
  echo "WARNING: Quality gate failed 2+ times. Skipping to prevent infinite loop. Fix issues manually." >&2
  rm -f "$RETRY_FILE"
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ERRORS=""

# C: 용량 절약을 위해 Gradle/캐시 경로를 D: 로 강제
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-D:/caches/gradle}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-D:/caches/pip}"
export npm_config_cache="${npm_config_cache:-D:/caches/npm}"
mkdir -p "$GRADLE_USER_HOME" "$PIP_CACHE_DIR" "$npm_config_cache" 2>/dev/null

# Temp 폴더가 비어 있거나 삭제되었으면 재생성 (Java JNI 추출 실패 방지)
mkdir -p "$LOCALAPPDATA/Temp" "/c/Users/$USER/AppData/Local/Temp" 2>/dev/null

# JAVA_HOME 자동 탐지 (미설정이거나 Java 17 미만인 경우 — Spring Boot 3.4 요건)
needs_jdk=true
if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  jver=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed -nE 's/.*"([0-9]+).*/\1/p')
  if [ -n "$jver" ] && [ "$jver" -ge 17 ] 2>/dev/null; then
    needs_jdk=false
  fi
fi
if [ "$needs_jdk" = "true" ]; then
  for jdk in \
    "$HOME/.jdks"/graalvm-jdk-21* \
    "$HOME/.jdks"/ms-21* \
    "$HOME/.jdks"/jdk-21* \
    "/c/Program Files/Java"/jdk-21* \
    "/c/Program Files/Java"/jdk-17* \
    "/c/Program Files/Eclipse Adoptium"/jdk-21* \
    "/c/Program Files/Eclipse Adoptium"/jdk-17*; do
    if [ -x "$jdk/bin/java" ]; then
      export JAVA_HOME="$jdk"
      export PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi

# =============================================================================
# 헬퍼: 서브 레포에 변경 사항이 있는지 확인
# - unstaged changes (git diff)
# - staged changes (git diff --cached)
# - untracked files (git ls-files --others --exclude-standard)
# =============================================================================
has_changes() {
  local repo_dir="$1"
  if [ ! -d "$repo_dir/.git" ]; then
    return 1
  fi
  # subshell로 cd를 격리하여 호출자의 cwd 오염 방지
  (
    cd "$repo_dir" || exit 1
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      exit 0
    fi
    local untracked
    untracked=$(git ls-files --others --exclude-standard 2>/dev/null | head -1)
    if [ -n "$untracked" ]; then
      exit 0
    fi
    exit 1
  )
}

# -----------------------------------------------------------------------------
# dinai-client 변경 감지 시 type-check + lint
# -----------------------------------------------------------------------------
CLIENT_DIR="$PROJECT_DIR/dinai-client"
if has_changes "$CLIENT_DIR"; then
  if [ -f "$CLIENT_DIR/package.json" ] && [ -d "$CLIENT_DIR/node_modules" ] && command -v npm &>/dev/null; then
    echo "Running dinai-client type-check + lint..." >&2
    TYPE_CHECK_OUT=$(cd "$CLIENT_DIR" && npm run type-check 2>&1) || ERRORS="$ERRORS\n[dinai-client] type-check failed:\n$TYPE_CHECK_OUT"
    LINT_OUT=$(cd "$CLIENT_DIR" && npm run lint 2>&1) || ERRORS="$ERRORS\n[dinai-client] lint failed:\n$LINT_OUT"
  elif ! command -v npm &>/dev/null; then
    echo "SKIP: dinai-client changes detected but npm not found in PATH." >&2
  else
    echo "SKIP: dinai-client changes detected but node_modules missing. Run 'npm install' to enable quality gate." >&2
  fi
fi

# -----------------------------------------------------------------------------
# dinai-core-api 변경 감지 시 build 검증
# -----------------------------------------------------------------------------
CORE_DIR="$PROJECT_DIR/dinai-core-api"
if has_changes "$CORE_DIR"; then
  if [ -f "$CORE_DIR/gradlew" ]; then
    if [ -z "$JAVA_HOME" ] && ! command -v java &>/dev/null; then
      echo "SKIP: dinai-core-api changes detected but JAVA_HOME/java not found." >&2
    else
      echo "Running dinai-core-api build check..." >&2
      BUILD_OUT=$(cd "$CORE_DIR" && ./gradlew classes 2>&1) || ERRORS="$ERRORS\n[dinai-core-api] build failed:\n$BUILD_OUT"
    fi
  fi
fi

# -----------------------------------------------------------------------------
# dinai-ai-api 변경 감지 시 빠른 테스트
# -----------------------------------------------------------------------------
AI_DIR="$PROJECT_DIR/dinai-ai-api"
if has_changes "$AI_DIR"; then
  if [ -f "$AI_DIR/pytest.ini" ] || [ -f "$AI_DIR/pyproject.toml" ]; then
    echo "Running dinai-ai-api quick tests..." >&2
    if docker compose -f "$PROJECT_DIR/docker-compose.yml" ps ai-api --status running -q 2>/dev/null | grep -q .; then
      TEST_OUT=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T ai-api python -m pytest tests/ -x --tb=short -q 2>&1) || ERRORS="$ERRORS\n[dinai-ai-api] tests failed:\n$TEST_OUT"
    elif command -v python &>/dev/null && python -c "import pytest" 2>/dev/null; then
      TEST_OUT=$(cd "$AI_DIR" && python -m pytest tests/ -x --tb=short -q 2>&1) || ERRORS="$ERRORS\n[dinai-ai-api] tests failed:\n$TEST_OUT"
    else
      echo "SKIP: ai-api container not running and local pytest unavailable. Start container or 'pip install pytest' to enable." >&2
    fi
  fi
fi

# -----------------------------------------------------------------------------
# 결과 판정
# -----------------------------------------------------------------------------
if [ -n "$ERRORS" ]; then
  # 재시도 카운터 증가
  echo $((RETRY_COUNT + 1)) > "$RETRY_FILE"
  echo -e "Quality gate FAILED. Please fix the following issues:\n$ERRORS" >&2
  exit 2
fi

# 성공 시 카운터 리셋
rm -f "$RETRY_FILE"
exit 0
