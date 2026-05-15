# heinemann9's Claude Code Marketplace

Claude Code 플러그인 카탈로그입니다.

## 설치

Claude Code 안에서 다음 슬래시 명령으로 마켓플레이스를 등록합니다.

```text
/plugin marketplace add https://github.com/heinemann9/sakang-marketplace.git
```

그 다음, 원하는 플러그인을 설치합니다.

```text
/plugin install rs-fleet@sakang-marketplace
```

설치 이후 업데이트가 필요하면:

```text
/plugin marketplace update sakang-marketplace
```

## 수록 플러그인

| 이름 | 설명 | 버전 |
| :--- | :--- | :--- |
| [`rs-fleet`](plugins/rs-fleet) | git/SVN 레포별·다중 Claude Code 백그라운드 에이전트 런처와 정리 도구 | 1.2.0 |

### rs-fleet

git 또는 SVN 작업 사본에 대해 `claude --bg`로 독립적인 백그라운드 세션을 띄우고 일괄 정리하는 스킬입니다.

세 가지 모드를 지원합니다.

- `scan` — 하위 폴더를 탐색해 git/SVN 작업 사본마다 에이전트 1개씩 띄우기
- `multi` — 특정 레포에 에이전트 N개 띄우기 (각 세션마다 격리된 워크트리 자동 생성 — git은 detached worktree, svn은 새 checkout)
- `cleanup` — 띄워둔 백그라운드 에이전트들을 roster/jobs까지 완전히 제거 (clean worktree/checkout도 함께 정리)

설치 후 호출:

```text
/rs-fleet:rs-fleet scan
/rs-fleet:rs-fleet multi /path/to/repo --count 3
/rs-fleet:rs-fleet cleanup
```

전제 조건:

- `git` (필수), `svn` (SVN 작업 사본을 다룰 때만)
- `jq` (cleanup 기능에 필요)
- Claude Code 네이티브 바이너리 (`~/.local/share/claude/versions/<latest>/`) — 일부 wrapper(예: cmux.app)는 `claude rm` 같은 hidden 서브커맨드를 chat prompt로 잘못 라우팅하므로, 스크립트가 자동으로 네이티브 바이너리를 우선 사용합니다. 자세한 내용은 [SKILL.md](plugins/rs-fleet/skills/rs-fleet/SKILL.md)의 "네이티브 바이너리 vs PATH wrapper" 항목 참고.

## 디렉토리 구조

```
sakang-marketplace/
├── .claude-plugin/
│   └── marketplace.json          # 마켓플레이스 카탈로그
├── plugins/
│   └── rs-fleet/
│       ├── .claude-plugin/
│       │   └── plugin.json       # 플러그인 매니페스트
│       └── skills/
│           └── rs-fleet/
│               ├── SKILL.md
│               └── spawn.sh
└── README.md
```

## 플러그인 추가 방법

1. `plugins/<plugin-name>/` 디렉토리 생성
2. `plugins/<plugin-name>/.claude-plugin/plugin.json` 작성 (`name`, `description`, `version` 필수)
3. 스킬은 `plugins/<plugin-name>/skills/<skill-name>/SKILL.md` 위치에 배치
4. 루트의 `.claude-plugin/marketplace.json`의 `plugins` 배열에 항목 추가
5. `plugin.json` / `marketplace.json` 모두 `version`을 bump 한 뒤 commit & push

## 버전 운영

- `plugin.json`의 `version`이 바뀌어야 사용자에게 업데이트가 전파됩니다 (SemVer 권장).
- 마켓플레이스 자체의 `marketplace.json`도 변경 사항이 있으면 함께 커밋하세요.
- 사용자 쪽에서는 `/plugin marketplace update sakang-marketplace`로 갱신합니다.

## License

MIT

## 참고

- [Create and distribute a plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
- [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins)
- [Create plugins](https://code.claude.com/docs/en/plugins)
