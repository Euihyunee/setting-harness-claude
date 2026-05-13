# claude-harness

Claude Code 작업 환경을 여러 프로젝트에서 공유하기 위한 harness repo. 각 프로젝트 폴더에 **junction/hardlink로 라이브 연결**되며, 이 repo에서 `git pull` 한 번이면 연결된 모든 프로젝트에 즉시 반영된다.

## 구조

```
claude-harness/
├── CLAUDE.md             # 프로젝트 루트 지침 (DINAI 기본 — 다른 프로젝트 적용 시 편집 필요)
├── .claude/              # 에이전트 / hooks / skills / settings.json
│   ├── agents/
│   ├── hooks/
│   ├── skills/
│   └── settings.json
├── docs/                 # Obsidian vault (.obsidian 설정 + 문서)
├── install.ps1           # 프로젝트 폴더에 link 설치
├── uninstall.ps1         # link 제거
├── .gitignore            # PC별 로컬 파일 제외
└── README.md             # 이 파일
```

## 새 프로젝트에 적용

대상 프로젝트 폴더를 정한 뒤 (예: `D:\hiaas\dinai`) PowerShell에서:

```powershell
D:\claude-harness\install.ps1 -Target D:\hiaas\dinai
```

생성되는 link:

| 대상 (프로젝트) | 종류 | 원본 (harness) |
|---|---|---|
| `<Target>\.claude` | Junction (`mklink /J`) | `D:\claude-harness\.claude` |
| `<Target>\docs` | Junction (`mklink /J`) | `D:\claude-harness\docs` |
| `<Target>\CLAUDE.md` | Hardlink (`mklink /H`) | `D:\claude-harness\CLAUDE.md` |

Junction은 일반 사용자 권한으로 생성 가능 (관리자 불필요). Hardlink는 같은 볼륨에서만 동작 — 다른 볼륨이면 `install.ps1`이 자동으로 symbolic link(`/D`)로 대체 시도하며, 이 경우 **개발자 모드** 또는 관리자 권한이 필요하다.

## 업데이트 워크플로 (핵심)

```powershell
cd D:\claude-harness
git pull
# 끝. 연결된 모든 프로젝트에 즉시 반영됨.
```

복사가 아니라 **같은 실체를 가리키는 link**이므로, 별도 sync 명령이 필요 없다.

## 새로 만든 변경을 harness에 반영

각 프로젝트의 `.claude/`, `docs/`, `CLAUDE.md`는 모두 harness의 같은 파일을 가리킨다. 즉 어느 프로젝트에서 수정하든 결과는 같다:

```powershell
# 어느 프로젝트에서든 (실제로는 harness 파일이 수정됨)
cd D:\hiaas\dinai
notepad .claude/agents/frontend.md

# 변경 push
cd D:\claude-harness
git add . && git commit -m "chore: frontend 에이전트 규칙 보완"
git push
```

## 제거

```powershell
D:\claude-harness\uninstall.ps1 -Target D:\hiaas\dinai
```

Junction과 hardlink만 제거되며, harness 본체와 다른 프로젝트 파일에는 영향이 없다.

## 주의사항

### 프로젝트별로 달라져야 하는 파일

- **`.claude/settings.local.json`** — PC/프로젝트별 권한·환경변수. `.gitignore`되어 있어 push되지 않지만, link 때문에 실제 파일은 공유된다. 프로젝트별로 다른 값이 필요하면 link 적용 후 별도 파일로 분리 필요.
- **`CLAUDE.md`** — 현재 내용은 DINAI 4-repo 특화. 다른 프로젝트에 가져갈 때는 그 프로젝트 컨텍스트로 편집 필요.
- **`docs/`** — Obsidian vault 자체가 공유됨. `.obsidian/` 설정/CSS/스니펫은 공유되어 OK지만, **문서 컨텐츠**가 dinai 전용이라 다른 프로젝트와 섞이는 게 문제라면 link 대상에서 `docs`를 빼고 vault 설정만 부분 link하는 변형 필요.

### 자식 git repo

대상 프로젝트 폴더 안에 다른 git repo가 들어있어도(예: `dinai-ai-api/`) harness link와 충돌하지 않는다. Git은 nested `.git`을 자동 추적하지 않으며, link는 별개 경로다.

### 이미 같은 이름 파일/폴더가 있으면

`install.ps1`은 대상 경로에 기존 파일이 있으면 **백업** 폴더(`<Target>\.harness-backup-<timestamp>\`)로 옮긴 뒤 link를 건다. 백업은 자동 삭제되지 않으므로 검증 후 수동으로 정리한다.

## Claude Code 사용자에게 (AI 어시스턴트가 이 파일을 읽을 때)

이 repo는 **harness 본체**이다. 사용자가 어떤 프로젝트 폴더에서 Claude를 실행하든, 그곳의 `.claude/`, `docs/`, `CLAUDE.md`는 여기를 link로 가리킨다. 따라서:

1. `.claude/agents/*.md`, `.claude/skills/**`, `.claude/settings.json` 수정 요청은 여기 본체에서 수정한다. 프로젝트 폴더에서 작업하면 link 통해 같은 파일을 수정하는 셈.
2. `CLAUDE.md`를 *프로젝트에 무관하게 공통화*하는 작업이라면 이 repo에서. *특정 프로젝트 전용 규칙*이라면 그 프로젝트 폴더의 CLAUDE.md를 link에서 제외하고 별도 파일로 두는 방향을 사용자에게 제안한다.
3. 변경 후 commit/push는 **반드시 사용자에게 확인받고** 진행한다 (커밋 정책: `feat:`/`fix:`/`chore:`/`refactor:` prefix, AI 도구 용어 금지, 명사형/음슴체).
4. 새 프로젝트에 harness를 적용하라는 요청이 오면 `install.ps1 -Target <경로>` 실행을 제안한다.
