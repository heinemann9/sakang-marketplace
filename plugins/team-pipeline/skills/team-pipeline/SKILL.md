---
name: team-pipeline
description: "단계별 팀(설계 → 구현 → 리뷰 → 테스트)을 순차적으로 구성·해체하며 작업을 진행하는 파이프라인. 각 단계는 팀장(opus) 1명 + 팀원(sonnet) N명으로 구성되며, 단계 종료 시 해당 팀을 해체한 뒤 다음 팀을 새로 만든다. 리뷰/테스트에서 문제가 발견되면 설계 또는 구현 단계로 되돌아가 팀을 재구성하여 재시도한다. 사용자가 '설계-구현-리뷰-테스트 팀 파이프라인 돌려줘', 'team-pipeline', '단계별 팀 구성해서 진행' 등을 요청할 때 사용한다."
user-invocable: true
argument-hint: "<작업 설명> [--design N] [--impl N] [--review N] [--test N]"
allowed-tools: Read, Write, Edit, Bash, TaskCreate, TaskUpdate, TaskList, Agent, AskUserQuestion, ToolSearch
---

# Team Pipeline

설계 → 구현 → 리뷰 → 테스트 4단계를 거치며, 각 단계마다 **새로운 팀메이트(TeamCreate)** 를 구성하고 단계가 끝나면 해체(TeamDelete)한다. 단계 간 인수인계는 **산출물 파일 저장 + 메인의 요약 브리핑** 두 방식을 모두 사용한다.

## 핵심 규칙

1. **각 팀은 팀장(opus) 1명 + 팀원(sonnet) N명** — 팀장은 단계의 의사결정·통합·품질 책임, 팀원은 분할된 작업을 병렬 수행
   - `TeamCreate` 시 팀장 에이전트는 `model: "opus"`, 나머지는 `model: "sonnet"` 로 명시
   - 팀장 이름 규칙: `<phase>-lead` (예: `design-lead`, `impl-lead`)
2. **팀 규모(팀원 수)는 가변** — 작업 복잡도에 따라 메인이 판단하거나, 사용자가 `--design N` 같은 인자로 지정 (N은 팀원 수, 팀장은 별도로 +1)
3. **단계 종료 시 즉시 `TeamDelete`** 로 팀 해체 후 다음 단계 팀을 새로 만든다
4. **리뷰/테스트에서 문제 발견 시** → 설계 또는 구현 단계로 롤백, 해당 단계 팀을 새로 구성하여 재시도
5. **모든 산출물은 `.claude/team-pipeline/<run-id>/` 디렉토리에 저장**
6. **메인 에이전트는 오케스트레이터** — 직접 코드 작성/리뷰하지 않고, 팀장에게 단계 작업을 위임. 팀장이 팀원에게 세부 작업을 재위임하고 결과를 통합하여 메인에 보고

## 산출물 디렉토리 구조

```
.claude/team-pipeline/<run-id>/
├── 00-task.md              # 입력 작업 명세
├── 01-design/
│   ├── design.md           # 최종 설계 문서
│   └── notes/              # 팀원 개별 노트 (선택)
├── 02-impl/
│   ├── impl-summary.md     # 구현 요약 (변경 파일, 핵심 결정)
│   └── diff.patch          # 변경 사항 스냅샷
├── 03-review/
│   └── review.md           # 리뷰 결과 (issues: [], verdict: pass|fail)
├── 04-test/
│   └── test.md             # 테스트 결과 (verdict: pass|fail, 재현 명령)
└── pipeline.log            # 단계 전이 로그 (시작/종료/롤백)
```

`<run-id>`는 `YYYYMMDD-HHMMSS` 형식.

## 단계별 워크플로우

### Phase 0 — 준비

1. `<run-id>` 생성, 디렉토리 만들기
2. 사용자 작업 설명을 `00-task.md`에 저장
3. TaskCreate로 4단계 + 잠재적 롤백 태스크 등록
4. 각 단계 인원 수 결정:
   - 인자(`--design N` 등)가 있으면 그대로 사용
   - 없으면 메인이 기본 2명으로 시작, 복잡도가 크면 사용자에게 `AskUserQuestion`으로 확인

### Phase 1 — 설계 (Design Team)

1. `TeamCreate({ team_name: "design-<run-id>", agents: [{ name: "design-lead", model: "opus", subagent_type: "general-purpose" }, { name: "design-1", model: "sonnet", ... }, ... ×N] })`
2. 메인 → 팀장(`design-lead`)에게 작업 + 팀원 명단 전달, 팀장이 SendMessage로 팀원에게 역할 분담 설계 위임
3. 팀장이 결과 통합 → `01-design/design.md` 저장, 메인에 반환
4. 메인이 한 단락 요약 작성
5. `TeamDelete({ team_name: "design-<run-id>" })`

### Phase 2 — 구현 (Impl Team)

1. `TeamCreate({ team_name: "impl-<run-id>", agents: [impl-lead(opus), impl-1..N(sonnet)] })`
2. 메인 → 팀장에게 `01-design/design.md` 전달, 팀장이 파일별/모듈별로 팀원에 분할 위임
3. 팀장 통합 결과: 코드 변경 + `02-impl/impl-summary.md`, `git diff > 02-impl/diff.patch`
4. `TeamDelete`

### Phase 3 — 리뷰 (Review Team)

1. `TeamCreate({ team_name: "review-<run-id>", agents: [review-lead(opus), review-1..N(sonnet)] })`
2. 팀장이 팀원에게 설계+구현+diff 전달, 영역별 독립 리뷰 위임
3. 팀장이 통합 → `03-review/review.md`
   - 형식: `verdict: pass|fail`, `issues: [...]`, `target_phase: design|impl`(fail일 때)
4. `TeamDelete`
5. **`fail` 이면 Phase 1 또는 Phase 2로 롤백** — `target_phase`에 따라 해당 단계를 **새 팀**으로 재실행. 재실행 시 `03-review/review.md`를 입력으로 추가 전달

### Phase 4 — 테스트 (Test Team)

1. `TeamCreate({ team_name: "test-<run-id>", agents: [test-lead(opus), test-1..N(sonnet)] })`
2. 팀장이 빌드/테스트/스모크/시나리오 작업을 팀원에게 분할 위임
3. 팀장 통합 결과 → `04-test/test.md` (`verdict`, 실패 시 `target_phase`)
4. `TeamDelete`
5. **`fail` 이면 Phase 1 또는 2로 롤백** (리뷰와 동일 규칙)

### Phase 5 — 종료

- `pipeline.log` 마지막 항목 기록
- 사용자에게 최종 산출물 경로 + 핵심 요약 보고

## 롤백 시 주의사항

- 롤백은 **무한 루프 방지**를 위해 같은 단계 최대 **3회**까지만 자동 재시도. 초과 시 사용자에게 `AskUserQuestion`으로 중단/계속 여부 확인
- 롤백 시 이전 단계의 산출물은 보존하되, 새 시도는 `01-design.v2/`, `02-impl.v2/` 처럼 버전 디렉토리 생성
- 리뷰/테스트도 새 버전에 맞춰 재실행

## 메인 에이전트 행동 지침

- **단계 종료 직후** 반드시 `TeamDelete` 호출 (작업이 끝나도 팀이 남아있으면 안 됨)
- 단계 시작 전 사용자에게 한 줄 안내: "Phase 2 시작 — 구현팀 opus×1(팀장) + sonnet×3 구성"
- 단계 종료 후 한 줄 보고: "Phase 3 완료 — 리뷰 verdict: pass, 다음은 테스트팀"
- 팀원에게 작업 위임할 때는 **자기 완결적 프롬프트**로 (대화 컨텍스트를 모른다고 가정)
- 사용자가 `--dry-run` 인자를 주면 단계 계획만 출력하고 실제 팀 생성은 하지 않음

## 도구 사용

- `TeamCreate` / `TeamDelete` / `SendMessage` 는 deferred 도구이므로 시작 시 `ToolSearch(query: "select:TeamCreate,TeamDelete,SendMessage")` 로 스키마 로드
- 팀원 작업 위임은 `Agent` 또는 `SendMessage` 둘 다 가능 — 짧고 독립적이면 `Agent`, 여러 턴 협업이면 팀메이트 + `SendMessage`

## 인자 파싱

```
/team-pipeline <작업 설명> [--design N] [--impl N] [--review N] [--test N] [--dry-run]
```

- 작업 설명이 비어있으면 `AskUserQuestion` 으로 요청
- `--*` 인자 미지정 시 기본값 2

## 예시 실행 흐름

```
사용자: /team-pipeline 로그인 API에 rate limit 추가 --impl 3
메인:   run-id=20260515-103022, 4단계 태스크 등록 완료. Phase 1 시작.
메인:   [TeamCreate design-...×2] → 설계 위임 → design.md 저장 → [TeamDelete]
메인:   Phase 1 완료. 핵심 결정: 토큰 버킷 알고리즘, Redis 백엔드.
메인:   Phase 2 시작 — 구현팀 opus×1(팀장) + sonnet×3 구성.
메인:   [TeamCreate impl-... lead+3] → 팀장 통합 구현 → diff.patch → [TeamDelete]
...
```
