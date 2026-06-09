# 옵시디언 다중 기기 동기화 셋업 가이드

옵시디언 Vault를 **GitHub Private Repo + Obsidian Git 플러그인**으로 데스크톱(Windows/Mac/Linux)과 모바일(iOS/Android) 전 기기에서 자동 동기화하고, 모든 변경 이력을 보관하는 시스템 구축 가이드.

> [!info] 핵심 아이디어
> Obsidian Git 플러그인 하나가 데스크톱·iOS·Android 모두에서 동작한다. 별도 앱(Working Copy, Termux 등) 설치 불필요.

---

## 1. 시스템 구성

### 1.1 아키텍처

```text
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   PC (Win)  │     │   PC (Mac)  │     │ iOS / 갤럭시 │
│  Obsidian   │     │  Obsidian   │     │  Obsidian   │
│ + Git 플러그인│    │ + Git 플러그인│    │ + Git 플러그인│
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           ▼
                  ┌─────────────────┐
                  │ GitHub Private  │
                  │   Repository    │
                  │  (전체 이력 보관) │
                  └─────────────────┘
```

### 1.2 구성 요소

| 항목 | 선택 | 비고 |
|------|------|------|
| 원격 저장소 | GitHub Private Repo | 무료, 비공개 무제한 |
| 데스크톱 동기화 | Obsidian Git 플러그인 | Windows / Mac / Linux |
| iOS 동기화 | Obsidian Git 플러그인 (내장) | 별도 앱 불필요 |
| Android 동기화 | Obsidian Git 플러그인 (내장) | 별도 앱 불필요 |
| 인증 | GitHub Personal Access Token (PAT) | 모든 기기 공통 |
| 대용량 첨부 | Git LFS | 50MB 이상 파일 대상 (선택) |

---

## 2. 사전 준비

### 2.1 필요한 것

- GitHub 계정 1개
- 메인 PC (Windows / Mac / Linux 중 택1)
- 옵시디언 데스크톱 앱
- 옵시디언 모바일 앱 (iOS / Android)
- Git 설치 (`git --version` 확인)

### 2.2 GitHub Personal Access Token 발급

1. GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)**
2. **Generate new token (classic)** 클릭
3. 설정:
   - **Note**: `obsidian-vault-sync`
   - **Expiration**: `No expiration` (또는 1년)
   - **Scopes**: `repo` 체크 (전체)
4. 토큰 생성 후 **즉시 복사** (한 번만 표시됨)
5. 비밀번호 관리자(1Password, Bitwarden 등)에 저장

> [!danger] 토큰 노출 주의
> PAT는 비밀번호와 동등한 권한을 가진다. 채팅·공개 메모·스크린샷에 포함하지 말 것. 노출 즉시 GitHub에서 revoke 후 재발급.

---

## 3. 메인 PC 셋업

### 3.1 GitHub 저장소 생성

1. GitHub에서 **New repository** 클릭
2. 설정:
   - **Repository name**: `my-obsidian-vault` (원하는 이름)
   - **Visibility**: **Private** (필수)
   - **Initialize**: README 추가 안 함 (빈 저장소)
3. **Create repository** 클릭
4. 저장소 URL 복사 (예: `https://github.com/USERNAME/my-obsidian-vault.git`)

### 3.2 로컬 Vault 폴더 준비

기존 Vault가 있는 경우 그 폴더를 사용, 없으면 새 폴더 생성.

```bash
cd ~/Documents
mkdir my-obsidian-vault
cd my-obsidian-vault
git init
git branch -M main
git remote add origin https://github.com/USERNAME/my-obsidian-vault.git
```

### 3.3 `.gitignore` 작성

Vault 루트에 `.gitignore` 파일 생성:

```text
# 옵시디언 작업 상태 (기기별로 다름)
.obsidian/workspace
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/cache
.obsidian/hotkeys.json

# 휴지통
.trash/

# 시스템 파일
.DS_Store
Thumbs.db
desktop.ini

# 임시 파일
*.tmp
*.swp
~$*
```

### 3.4 첫 커밋 및 푸시

```bash
git add .
git commit -m "init: obsidian vault"
git push -u origin main
```

> [!warning] 푸시 시 인증
> 푸시할 때 GitHub 아이디와 **PAT를 비밀번호 자리에 입력**한다 (실제 GitHub 비밀번호 아님).

### 3.5 옵시디언에서 Vault 열기

1. 옵시디언 실행 → **Open folder as vault** → 위 폴더 선택
2. **Settings → Community plugins → Turn on community plugins**
3. **Browse** → `Obsidian Git` 검색 → Install → Enable

### 3.6 Obsidian Git 플러그인 설정

`Settings → Obsidian Git`에서:

| 설정 항목 | 값 |
|---------|-----|
| Vault backup interval (minutes) | `10` |
| Auto pull interval (minutes) | `10` |
| Auto pull on startup | ON |
| Auto push on commit | ON |
| Commit message on auto backup | `vault backup: {{date}}` |
| {{date}} placeholder format | `YYYY-MM-DD HH:mm:ss` |
| Pull updates on startup | ON |

> [!success] 셋업 확인
> 명령 팔레트(`Ctrl/Cmd + P`)에서 `Git: Commit all changes` 실행 → GitHub 저장소에 새 커밋이 보이면 정상.

---

## 4. 모바일 셋업 (iOS / Android 공통)

### 4.1 옵시디언 모바일 앱 설치

- **iOS**: App Store에서 `Obsidian` 설치
- **Android (갤럭시 포함)**: Play Store에서 `Obsidian` 설치

### 4.2 빈 Vault 생성

1. 앱 실행 → **Create new vault** → 이름 입력 (예: `my-obsidian-vault`)
2. 위치는 기본값 사용 (앱 내부 저장소)

### 4.3 Obsidian Git 플러그인 설치

1. **Settings → Community plugins → Turn on community plugins**
2. **Browse** → `Obsidian Git` 검색 → Install → Enable

### 4.4 원격 저장소 클론

1. 명령 팔레트(우측 상단 메뉴 아이콘 → 슬래시 명령) → `Git: Clone an existing remote repo`
2. URL 입력: `https://github.com/USERNAME/my-obsidian-vault.git`
3. 인증 정보:
   - **Username**: GitHub 아이디
   - **Password**: 발급받은 PAT 붙여넣기
4. **Open as Vault**로 전환

### 4.5 모바일 자동 동기화 설정

`Settings → Obsidian Git`에서:

| 설정 항목 | 값 |
|---------|-----|
| Auto pull on startup | ON |
| Auto push on commit | ON |
| Vault backup interval | `0` (수동) 또는 `30` (분) |
| Commit-and-sync on mobile when app closes | ON |
| Pull on mobile startup | ON |

> [!info] 모바일 동작 방식
> 모바일은 배터리·네트워크 절약을 위해 백그라운드 자동 커밋 빈도를 낮추고, **앱 시작 시 풀 / 종료 시 푸시**를 기본 패턴으로 한다.

### 4.6 동작 테스트

1. 데스크톱에서 노트 1개 작성 → 자동 커밋 대기 (10분) 또는 수동 푸시
2. 모바일 앱 시작 → 자동 풀 → 노트가 보이면 정상
3. 모바일에서 노트 수정 → 앱 종료 → 데스크톱에서 풀 → 수정 반영 확인

---

## 5. 다른 PC 추가하기

새 PC에 환경 구성 시 절차.

### 5.1 절차

```bash
cd ~/Documents
git clone https://github.com/USERNAME/my-obsidian-vault.git
cd my-obsidian-vault
```

1. 옵시디언 실행 → **Open folder as vault** → 클론한 폴더 선택
2. Obsidian Git 플러그인은 이미 `.obsidian/plugins/` 에 포함되어 자동 설치됨
3. `Settings → Obsidian Git`에서 PAT만 다시 입력

> [!success] 끝
> 이게 다다. 새 PC에서 별도 설정 불필요 — 플러그인 설정이 Git으로 함께 동기화되기 때문.

---

## 6. 이력 관리

### 6.1 이력 확인 방법

| 방법 | 위치 | 용도 |
|------|------|------|
| 파일 이력 보기 | 명령 팔레트 → `Git: Open file history` | 현재 파일의 변경 이력 |
| 전체 커밋 로그 | 명령 팔레트 → `Git: Show log` | 전체 변경사항 타임라인 |
| GitHub 웹 | `github.com/USERNAME/my-obsidian-vault/commits` | 그래프 / diff / blame |
| 특정 시점 diff | 명령 팔레트 → `Git: Open diff view` | 두 버전 시각 비교 |

### 6.2 파일 복구

실수로 삭제하거나 잘못 수정한 경우:

1. **최근 변경 되돌리기**: 명령 팔레트 → `Git: Discard all changes` (커밋 전 변경분만)
2. **이전 커밋 시점 파일 복원**:
   ```bash
   git log -- path/to/note.md          # 해당 파일 이력 조회
   git checkout <commit-hash> -- path/to/note.md
   ```
3. **GitHub 웹에서 복원**: 커밋 → 파일 → **View at this point in time** → 내용 복사

### 6.3 충돌 발생 시

두 기기에서 같은 파일을 동시 편집한 경우:

1. Obsidian Git이 알림 표시 (`Merge conflict`)
2. 충돌 파일에 마커 삽입:
   ```text
   <<<<<<< HEAD
   로컬 변경 내용
   =======
   원격 변경 내용
   >>>>>>> origin/main
   ```
3. 옵시디언에서 직접 편집 → 마커 제거 → 의도한 내용만 남김
4. 명령 팔레트 → `Git: Commit all changes`

> [!warning] 충돌 예방
> 다른 기기에서 작업 시작 전 **반드시 풀(Pull)** 실행. 모바일은 자동 풀이 켜져 있어도, 데스크톱 작업 직전 수동 풀 권장.

---

## 7. 대용량 첨부 파일 (선택)

이미지 / PDF / 동영상 비중이 큰 경우 Git LFS 사용 고려.

### 7.1 Git LFS 설치

```bash
git lfs install
```

### 7.2 `.gitattributes` 추가

Vault 루트에 `.gitattributes` 생성:

```text
*.png filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
*.jpeg filter=lfs diff=lfs merge=lfs -text
*.gif filter=lfs diff=lfs merge=lfs -text
*.pdf filter=lfs diff=lfs merge=lfs -text
*.mp4 filter=lfs diff=lfs merge=lfs -text
*.mov filter=lfs diff=lfs merge=lfs -text
```

### 7.3 적용

```bash
git add .gitattributes
git commit -m "chore: enable git lfs for binary files"
git push
```

> [!warning] LFS 무료 한도
> GitHub LFS 무료: **저장 1GB / 월 대역폭 1GB**. 초과 시 유료 ($5 / 50GB). 첨부가 많지 않으면 LFS 없이 일반 Git으로도 충분.

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `Authentication failed` | PAT 만료 또는 오타 | 새 PAT 발급 → 플러그인 설정 갱신 |
| 모바일에서 클론 실패 | 저장소 크기 과대 | Vault 분할 또는 LFS 도입 |
| `Merge conflict` 자주 발생 | 풀 없이 작업 시작 | 작업 전 수동 풀 습관화 |
| 자동 커밋 안 됨 | 플러그인 비활성화 / 설정 오류 | `Settings → Obsidian Git → backup interval` 확인 |
| 푸시 후 다른 기기에서 안 보임 | 자동 풀 비활성화 | `Auto pull on startup` ON 확인 |
| `.obsidian/workspace` 충돌 | `.gitignore` 미설정 | 본 문서 3.3 절 `.gitignore` 적용 |

---

## 9. 체크리스트

셋업 완료 후 점검:

- [ ] GitHub Private Repo 생성 완료
- [ ] PAT 발급 및 안전한 곳에 저장
- [ ] 메인 PC `.gitignore` 적용
- [ ] 메인 PC 첫 커밋 / 푸시 성공
- [ ] Obsidian Git 플러그인 자동 백업 동작 확인
- [ ] 모바일(iOS/갤럭시) 클론 및 동기화 확인
- [ ] 양방향 편집 → 동기화 테스트 (PC ↔ 모바일)
- [ ] 파일 이력 조회 (`Git: Open file history`) 동작 확인
- [ ] 충돌 발생 시 해결 절차 숙지

---

## 10. 운영 팁

- **커밋 메시지 정책**: 자동 백업 메시지는 기본 템플릿 유지, 의미 있는 변경은 수동 커밋(`Git: Create backup with specific message`)으로 메시지 명시
- **주기적 백업 확인**: 월 1회 GitHub 웹에서 커밋 그래프 확인 — 빈 기간이 길면 자동 동기화 점검
- **PAT 갱신 주기**: 만료 1주일 전 미리 재발급 (만료되면 모든 기기에서 푸시 실패)
- **Vault 비대화 관리**: 1년에 1회 첨부 폴더 정리, 사용하지 않는 이미지 삭제
- **이중 백업**: 매우 중요한 노트는 별도로 클라우드 스토리지(Google Drive 등)에 주기 백업 권장
