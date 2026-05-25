---
name: agent-fleet
description: "Repository fleet launcher for git and SVN working copies. Scan subfolders from the current directory and start one Claude Code background agent per repo, start multiple background agents for one specific repo (each in an isolated worktree / svn checkout), or clean up previously spawned background agents. Use when the user asks to spawn/manage/cleanup agents for many repositories or multiple agents for a single repository."
user-invocable: true
argument-hint: "scan [root] [--max-depth N] [--prefix NAME] [--worktree|--no-worktree] [--dry-run] [--force-respawn] | multi <repo> --count N [--prefix NAME] [--worktree|--no-worktree] [--dry-run] [--force-respawn] | cleanup [--prefix NAME] [--pattern REGEX] [--dry-run]"
allowed-tools: Read, Bash(git:*), Bash(svn:*), Bash(bash:*), Bash(claude:*), Bash(find:*), Bash(jq:*), Bash(sort:*), Bash(awk:*), Bash(sed:*)
---

# Agent Fleet

git 또는 SVN 작업 사본에 대해 `claude --bg`로 독립적인 Claude Code 백그라운드 세션을 띄우고 정리한다.

세 가지 워크플로우를 지원한다.

1. **scan**: 현재 폴더의 하위 디렉토리를 탐색해 git/SVN 작업 사본을 찾고, 레포당 에이전트 1개씩 띄운다.
2. **multi**: 특정 git/SVN 작업 사본에 에이전트를 N개 띄운다. 각 세션은 격리된 워크트리(git: `git worktree add --detach`, svn: 새 `svn checkout`)에서 동작한다.
3. **cleanup**: 이 스킬로 띄운 백그라운드 에이전트들을 일괄 제거한다. 깨끗한 워크트리/체크아웃은 함께 정리한다.

띄워진 세션은 Claude Code가 관리하는 독립 백그라운드 세션이다. `claude agents`로 목록을 확인할 수 있고, `claude attach <name-or-id>`로 각 세션에 진입한다.

## 언제 사용하는가

다음과 같은 요청에서 이 스킬을 사용한다.

- "현재 폴더 아래 git repo마다 agent 띄워줘"
- "서브 폴더 검색해서 레포별로 agent 하나씩 실행"
- "특정 repo에 agent 여러 개 띄워줘"
- "agentfleet으로 띄운 세션들 정리해줘"
- "agent-fleet", "repo agents", "multi agent for repo"

## 명령 개요

스킬 디렉토리의 번들 스크립트를 실행한다.

```bash
bash ~/.claude/skills/agent-fleet/spawn.sh scan
bash ~/.claude/skills/agent-fleet/spawn.sh multi /path/to/repo --count 3
bash ~/.claude/skills/agent-fleet/spawn.sh cleanup
```

## Mode 1: 하위 폴더 스캔 후 레포당 에이전트 1개

루트 경로 기본값은 현재 작업 디렉토리.

```bash
bash ~/.claude/skills/agent-fleet/spawn.sh scan
```

루트 경로를 명시할 때:

```bash
bash ~/.claude/skills/agent-fleet/spawn.sh scan /Users/sakang/repo
```

자주 쓰는 옵션:

```bash
bash ~/.claude/skills/agent-fleet/spawn.sh scan . --max-depth 3
bash ~/.claude/skills/agent-fleet/spawn.sh scan . --prefix repo
bash ~/.claude/skills/agent-fleet/spawn.sh scan . --dry-run
bash ~/.claude/skills/agent-fleet/spawn.sh scan . --force-respawn
```

**동작**

- `.git` 또는 `.svn` 디렉토리를 가진 폴더를 찾는다. `.git`/`.svn` 내부는 탐색 대상에서 제외한다.
- 각 작업 사본의 최상위 경로마다 백그라운드 세션 1개를 띄운다.
- 격리 모드:
  - **기본 (`--no-worktree`)**: 레포 최상위에서 in-place 실행. 사용자 미커밋 변경과 같은 작업 트리를 공유.
  - **`--worktree`**: 레포마다 `~/.claude/agent-fleet/worktrees/<session-name>`에 격리된 워크트리/체크아웃을 만들고 그 안에서 실행. scan 대상이 많거나 동시 편집 충돌이 우려될 때 사용.
- `svn`이 PATH에 없으면 SVN 탐색은 건너뛴다.
- 세션 이름 포맷: `<prefix>-<repo-name>` (prefix와 repo-name이 같으면 중복 제거)
- 기본 prefix: `agentfleet`
- 같은 이름의 세션이 이미 있으면 스킵한다.
- `--force-respawn`은 기존 세션을 중지하고 다시 띄운다.

## Mode 2: 한 레포에 에이전트 N개

```bash
bash ~/.claude/skills/agent-fleet/spawn.sh multi /path/to/repo --count 4
```

레포 내부에서 실행할 때:

```bash
bash ~/.claude/skills/agent-fleet/spawn.sh multi . --count 4
```

자주 쓰는 옵션:

```bash
bash ~/.claude/skills/agent-fleet/spawn.sh multi /path/to/repo --count 4 --prefix webssh
bash ~/.claude/skills/agent-fleet/spawn.sh multi /path/to/repo --count 4 --dry-run
bash ~/.claude/skills/agent-fleet/spawn.sh multi /path/to/repo --count 4 --force-respawn
```

**동작**

- 대상 폴더가 git 작업 트리 또는 SVN 작업 사본 안에 있는지 확인한다.
- 실제 작업 사본 최상위 경로를 해석한다 (`git rev-parse --show-toplevel` 또는 `svn info --show-item wc-root`).
- 격리 모드:
  - **기본 (`--worktree`)**: 세션마다 `~/.claude/agent-fleet/worktrees/<session-name>`에 격리된 워크트리/체크아웃을 만든다.
    - git: `git worktree add --detach <wt> HEAD`
    - svn: `svn checkout <wc-url> <wt>` (새 작업 사본)
  - **`--no-worktree`**: 모든 세션이 원본 작업 사본에서 동작. 동일 파일 동시 편집 위험 — 사용자가 작업 분담을 명확히 한 경우(폴더별/모듈별 분담)에만 사용.
- 세션 이름 포맷: `<prefix>-<repo-name>-NN` (prefix와 repo-name이 같으면 `<prefix>-NN`으로 축약)
- 기본 prefix: `agentfleet`
- `--count`는 최대 50까지 허용한다.

## Mode 3: 띄운 에이전트 정리

이 스킬로 띄운 백그라운드 세션들을 정지하고 roster/jobs에서 완전히 제거한다.

```bash
bash ~/.claude/skills/agent-fleet/spawn.sh cleanup
```

자주 쓰는 옵션:

```bash
bash ~/.claude/skills/agent-fleet/spawn.sh cleanup --prefix rvbox
bash ~/.claude/skills/agent-fleet/spawn.sh cleanup --pattern '^agentfleet-rvbox-st-' --dry-run
```

**동작**

- `~/.claude/daemon/roster.json`을 읽어 활성 백그라운드 세션과 이름을 수집한다.
- 기본적으로 이름이 `<prefix>-`로 시작하는 세션을 매칭한다(기본 prefix `agentfleet`).
- `--pattern REGEX`를 주면 prefix 필터 대신 확장 정규식으로 이름을 매칭한다.
- 각 매칭에 대해 `claude stop <short>` 후 `claude rm <short>`를 실행한다. `rm`은 세션을 roster에서 완전히 제거하고 worktree를 정리하는 공식 명령이다(Claude Code agent-view 문서 참고).
- 세션 제거 후 `~/.claude/agent-fleet/worktrees/<session-name>`의 워크트리도 정리한다.
  - git 워크트리: `git worktree remove` (uncommitted 변경 있으면 보존)
  - svn 체크아웃: `svn status`가 비어 있으면 `rm -rf`, 그 외에는 보존
- `--dry-run`은 제거 대상만 출력한다.
- `jq`가 필요하다.

### 왜 stop과 rm을 둘 다 호출하는가

`claude stop`은 세션을 "Stopped" 상태로만 만들고, supervisor는 `claude agents` 목록과 `~/.claude/jobs/<short>/state.json`을 유지한다. 진짜 제거는 `claude rm`이 한다 — roster에서 항목을 지우고 worktree도 함께 정리한다(uncommitted 변경이 없을 때).

### 네이티브 바이너리 vs PATH wrapper (중요)

`PATH`에 있는 `claude` 명령이 단순 wrapper인 경우가 있다(예: **cmux.app 번들**). 이 wrapper는 `rm` · `stop` · `respawn` 같은 hidden 서브커맨드를 정상적으로 라우팅하지 못하고, **chat prompt로 잘못 해석해 새 세션을 시작**해 버린다 — 결과적으로 명령은 무시되고 사용량(quota)만 소비된다.

이 스크립트는 `~/.local/share/claude/versions/<latest>/`에 있는 **네이티브 바이너리를 자동 탐지해 우선 사용**하고, 없을 때만 `PATH`의 `claude`로 폴백한다.

직접 셸에서 관리 명령을 실행할 때는 반드시 네이티브 바이너리 경로를 명시해야 한다:

```bash
~/.local/share/claude/versions/2.1.142 rm <session-short>
~/.local/share/claude/versions/2.1.142 stop <session-short>
```

agent-view CLI 레퍼런스: <https://code.claude.com/docs/en/agent-view>

## 결과 확인

세션 띄운 뒤:

```bash
claude agents                  # 전체 세션 대시보드
claude attach <session-name>   # 해당 세션에 진입
claude logs <session-name>     # 최근 출력 확인
```

## 안전성 안내

- 이 스킬은 Claude Code 백그라운드 세션을 띄우거나 정리할 뿐, **레포지토리 파일을 변경하지 않는다.**
- `--dry-run`으로 실제 띄우거나 제거하기 전에 대상 목록을 미리 확인할 수 있다.
- 쉘 rc 파일을 수정하거나 alias를 자동 설치하지 않는다.
- `~/.claude/daemon/roster.json`을 읽어 같은 이름의 세션 중복 생성을 피한다.
- `--force-respawn`은 매칭 세션을 `claude stop`으로 정지하고 새로 띄운다 — 기존 standby 세션을 의도적으로 교체할 때만 사용한다.
- `--no-worktree`로 동일 작업 사본에 여러 세션을 띄울 경우 파일 충돌·미커밋 변경 소실 책임은 사용자에게 있다. `git status`/`svn status`를 자주 확인.
- **⚠️ `PATH`의 `claude`가 wrapper(cmux.app 등)이면 `rm`/`stop`/`respawn` 같은 hidden 서브커맨드를 chat prompt로 오인 처리해 사용량을 소비할 수 있다.** 스크립트는 네이티브 바이너리를 자동 탐지하지만, **셸에서 직접 관리 명령을 칠 때는 네이티브 경로를 명시**해야 안전하다. 자세한 내용은 Mode 3의 "네이티브 바이너리 vs PATH wrapper" 절 참고.

## 트러블슈팅

- **`claude` not found**: Claude Code CLI를 먼저 설치하고 인증한다.
- **레포지토리를 찾지 못함**: 루트 경로를 확인하거나 `--max-depth`를 늘린다.
- **대상이 git 레포지토리가 아님**: 유효한 git 작업 트리 또는 SVN 작업 사본 안의 폴더를 인자로 준다.
- **SVN 레포 인식 안 됨**: PATH에 `svn` 명령이 있는지 확인한다. 없으면 SVN 탐색/스폰이 비활성화된다.
- **기존 세션이 스킵됨**: `claude agents`로 확인하거나 `--force-respawn`으로 재실행한다.
- **cleanup이 "still present in roster"로 실패**: `PATH`의 `claude`가 wrapper일 가능성이 높다. `~/.local/share/claude/versions/<latest>/ rm <id>`를 직접 실행해 확인한다. 직접 실행이 성공하면 스크립트의 네이티브 바이너리 자동 탐지가 실패한 것이므로, `~/.local/share/claude/versions/` 디렉토리에 실행 가능한 버전 폴더가 있는지 점검한다.

## 번들 리소스

- [`spawn.sh`](spawn.sh) — 레포지토리 탐색, 중복 처리, `claude --bg` 런처, 그리고 네이티브 바이너리 기반 cleanup 로직.
