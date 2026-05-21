# heinemann9's Claude Code Marketplace

Claude Code 플러그인 카탈로그입니다.

## 설치

Claude Code 안에서 다음 슬래시 명령으로 마켓플레이스를 등록합니다.

```text
/plugin marketplace add https://github.com/heinemann9/sakang-marketplace.git
```

그 다음, 원하는 플러그인을 설치합니다.

```text
/plugin install agent-fleet@sakang-marketplace
```

설치 이후 업데이트가 필요하면:

```text
/plugin marketplace update sakang-marketplace
```

## 수록 플러그인

| 이름 | 설명 | 버전 |
| :--- | :--- | :--- |
| [`agent-fleet`](plugins/agent-fleet) | git/SVN 레포별·다중 Claude Code 백그라운드 에이전트 런처와 정리 도구 | 1.2.0 |
| [`dev`](plugins/dev) | 개발 작업 입구 디스패처 — 프롬프트를 분류해 solo-pipeline / team-pipeline / team-flat 중 적합 모드로 안내 | 0.1.0 |
| [`solo-pipeline`](plugins/solo-pipeline) | 4단계(Architect/Coder/Reviewer/Tester) × 단계별 단일 sub-agent 자가 수행 파이프라인 (Architect/Reviewer=opus, Coder/Tester=sonnet) | 0.1.0 |
| [`team-pipeline`](plugins/team-pipeline) | 4단계 가변 인원 팀 파이프라인 — 단계별 1~N명 자동 산정, N=1은 단일 sub-agent / N≥2는 팀(opus 팀장 + sonnet 팀원) | 0.4.0 |
| [`prd`](plugins/prd) | PRD 작성(prd-generator) + PRD 간 충돌 검증(prd-validator) 서브에이전트 플러그인 | 0.1.0 |
| [`council`](plugins/council) | 4관점 anti-anchoring 의사결정 — Architect/Skeptic/Pragmatist/Critic sub-agent 병렬 실행 후 합의·분기 추출 | 0.1.0 |
| [`docs`](plugins/docs) | 문서-코드 정합성 유지 세트 — docs-audit(정형 드리프트 전수 감사) + docs-sync(git diff 의미 변경 → 문서 갱신 후보) | 0.1.0 |

### 어떤 파이프라인을 쓸까

세 파이프라인 플러그인은 의도적으로 분리되어 있습니다. 작업 성격에 맞춰 선택:

| 작업 성격 | 권장 | 특성 |
|---|---|---|
| 1~3 파일 단순 수정·리팩터링에 단계 디시플린만 적용 | `solo-pipeline` | 비용 최저(~1.4~1.6×), 인원 협상 없음 |
| 신규 컴포넌트 / 보안·성능 critical / 사이드 스캔 필요 | `team-pipeline` | 다관점 검출, 인원 자동 산정(~1.6~3.2×) |
| 4+ 독립 파일에 같은 패턴 반복 (codemod·rename) | `team-flat` (향후) | wall-clock 5.5× 단축 |
| 1~2줄 사소 수정 | 스킬 호출 없이 그대로 | 오버헤드 제로 |
| 어느 것이 맞는지 모르겠다 | `dev` | 메인이 분류 + 안내 |

### agent-fleet

git 또는 SVN 작업 사본에 대해 `claude --bg`로 독립적인 백그라운드 세션을 띄우고 일괄 정리하는 스킬입니다.

세 가지 모드를 지원합니다.

- `scan` — 하위 폴더를 탐색해 git/SVN 작업 사본마다 에이전트 1개씩 띄우기
- `multi` — 특정 레포에 에이전트 N개 띄우기 (각 세션마다 격리된 워크트리 자동 생성 — git은 detached worktree, svn은 새 checkout)
- `cleanup` — 띄워둔 백그라운드 에이전트들을 roster/jobs까지 완전히 제거 (clean worktree/checkout도 함께 정리)

설치 후 호출:

```text
/agent-fleet:agent-fleet scan
/agent-fleet:agent-fleet multi /path/to/repo --count 3
/agent-fleet:agent-fleet cleanup
```

전제 조건:

- `git` (필수), `svn` (SVN 작업 사본을 다룰 때만)
- `jq` (cleanup 기능에 필요)
- Claude Code 네이티브 바이너리 (`~/.local/share/claude/versions/<latest>/`) — 일부 wrapper(예: cmux.app)는 `claude rm` 같은 hidden 서브커맨드를 chat prompt로 잘못 라우팅하므로, 스크립트가 자동으로 네이티브 바이너리를 우선 사용합니다. 자세한 내용은 [SKILL.md](plugins/agent-fleet/skills/agent-fleet/SKILL.md)의 "네이티브 바이너리 vs PATH wrapper" 항목 참고.

### dev

작업 프롬프트를 받아 어느 파이프라인이 적합한지 분류해주는 얇은 디스패처입니다. 디스패처는 코드 변경·sub-agent 자동 호출을 하지 않고, 분류 결과와 `/solo-pipeline ...` / `/team-pipeline ...` / `/team-flat ...` 입력 안내만 출력합니다.

```text
/dev:dev 결제 API에 PII 마스킹 미들웨어 추가
```

자세한 분류 휴리스틱은 [SKILL.md](plugins/dev/skills/dev/SKILL.md) 참고.

### solo-pipeline

설계 → 구현 → 리뷰 → 테스트 4단계를 **단계별 역할 전문 sub-agent 1명씩**으로 자가 수행합니다. 인원 협상 없음(항상 1/1/1/1). 모델은 axlab 실측 패턴을 따라 Architect/Reviewer는 opus, Coder/Tester는 sonnet로 배정합니다. `TeamCreate`는 호출하지 않습니다.

```text
/solo-pipeline:solo-pipeline 결제 API 응답에 마스킹 누락 필드 추가
```

산출물은 `.claude/solo-pipeline/<run-id>/` 하위에 단계별로 저장됩니다(`01-architect/`, `02-impl/`, `03-review/`, `04-test/`). 자세한 단계별 워크플로우는 [SKILL.md](plugins/solo-pipeline/skills/solo-pipeline/SKILL.md) 참고.

### team-pipeline

설계 → 구현 → 리뷰 → 테스트 4단계를 **단계별 1~N명의 가변 팀**으로 수행합니다. 메인이 사용자 프롬프트와 Architect 산출물을 기반으로 단계별 인원을 자동 산정(단계 0에서 AUQ 1회 확정, Architect 산출물 기반 2차 조정은 자동 적용). N=1 단계는 단일 sub-agent로, N≥2 단계는 opus 팀장 + sonnet 팀원 팀을 구성·해체합니다.

```text
/team-pipeline:team-pipeline 로그인 API에 rate limit 추가
/team-pipeline:team-pipeline 결제 마스킹 미들웨어 추가 --review 3
```

산출물은 `.claude/team-pipeline/<run-id>/` 하위에 단계별로 저장됩니다(`01-architect/`, `02-impl/`, `03-review/`, `04-test/`). 자세한 단계별 워크플로우는 [SKILL.md](plugins/team-pipeline/skills/team-pipeline/SKILL.md) 참고.

### prd

PRD 작성(`prd-generator`)과 PRD 간 충돌 검증(`prd-validator`) 서브에이전트를 함께 제공하는 기획 품질 보증 플러그인입니다. 자세한 사용법은 [플러그인 디렉토리](plugins/prd) 참고.

### council

기술/설계 의사결정 전에 Architect / Skeptic / Pragmatist / Critic 4관점 sub-agent를 독립 병렬 실행하여 anti-anchoring 합의·분기를 추출합니다. 자세한 사용법은 [SKILL.md](plugins/council/skills/council/SKILL.md) 참고.

### docs

문서-코드 정합성을 유지하기 위한 두 스킬을 제공합니다 — `docs-audit`(LINK/PLAN/SCRIPT 3트랙 정형 드리프트 전수 감사), `docs-sync`(git diff 의미 변경 → 문서 갱신 후보 제시). 자세한 사용법은 [플러그인 디렉토리](plugins/docs) 참고.

## 디렉토리 구조

```
sakang-marketplace/
├── .claude-plugin/
│   └── marketplace.json          # 마켓플레이스 카탈로그
├── plugins/
│   ├── agent-fleet/
│   ├── dev/
│   ├── solo-pipeline/
│   ├── team-pipeline/
│   ├── prd/
│   ├── council/
│   └── docs/
│       ├── .claude-plugin/
│       │   └── plugin.json       # 플러그인 매니페스트
│       └── skills/
│           └── <skill-name>/
│               └── SKILL.md
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
