---
name: team-pipeline
description: "설계(Architect) → 구현(Coder) → 리뷰(Reviewer) → 테스트(Tester) 4단계 파이프라인. 단계 0에서 메인이 프롬프트 기반으로 단계별 인원을 자동 산정하고 AUQ로 1회 확정한다(Impl·Review는 Architect 산출물에 따라 자동 조정될 수 있음을 사용자에게 미리 고지). 인원 1명이면 단일 sub-agent, 2명 이상이면 팀(opus 팀장 + sonnet 팀원 N)을 구성·해체. 신규 컴포넌트 / 보안·성능 critical / 사이드 스캔이 필요한 변경에 사용."
user-invocable: true
argument-hint: "<작업 설명> [--architect N] [--impl N] [--review N] [--test N] [--dry-run]"
allowed-tools: Read, Write, Edit, Bash, Agent, AskUserQuestion, ToolSearch
---

# team-pipeline — 4단계 가변 인원 파이프라인

설계 → 구현 → 리뷰 → 테스트 4단계를 항상 수행하되, **각 단계 인원은 작업 특성에 맞춰 1~4명으로 자동 산정**한다. 단계 0에서 산정 결과를 사용자에게 한 번 보여주고 확정한 뒤, 각 단계는 인원 수에 따라 다음과 같이 실행된다.

- **N=1**: 단일 sub-agent (opus). 팀 구성 없음.
- **N≥2**: `TeamCreate`로 opus 팀장 1 + sonnet 팀원 N 구성, 단계 종료 시 즉시 `TeamDelete`.

## 비용 감수 안내

4단계 풀가동 시 solo 대비 wall-clock 2.10× · 토큰 2.83~3.23× (실측 2026-05-18 / 4 sonnet 멤버 기준). 단계별 인원을 1로 줄이면 그만큼 비용·시간이 감소. 단순 작업에 무리하게 N≥2를 강요하지 않는 것이 본 스킬의 핵심.

| 단계 인원 합계 | 대략 비용 (solo=1) | 대략 wall-clock |
|---------------|--------------------|------------------|
| 4 (1/1/1/1) | ~1.4~1.6× | ~1.3× |
| 6 (평균 ~1.5명) | ~2.0× | ~1.6× |
| 8 (2/2/2/2) | ~2.8~3.2× | ~2.1× |

---

## 핵심 원칙

| 원칙 | 강제 수준 |
|------|-----------|
| 단계 0에서 자동 산정 → AUQ로 사용자 1회 확정 → 단계 1 이후 자동 조정(AUQ 없음) | [Critical] |
| N=1 단계는 `TeamCreate` 사용 금지 — 단일 `Agent` 호출 | [Critical] |
| N≥2 단계는 팀장=opus / 팀원=sonnet `model` 인자 명시 (누락 시 부모 모델 상속 → 비용 폭증) | [Critical] |
| 단계 종료 시 즉시 `TeamDelete` (팀 잔존 금지, N≥2 단계에만 해당) | [Critical] |
| Reviewer LGTM ≠ 사람 멤버 리뷰 통과 — 자동 phase 전환 금지 | [Recommended] |
| Tester ALL PASS = 단위 테스트만. 통합·사용성·릴리즈 QA는 사람 2일/2명+ 별도 | [Critical] |
| 피드백 루프 ≤ 2회, LOW 자동·MEDIUM+ AUQ 승인 | [Recommended] |
| 에이전트·팀은 `git commit` 직접 호출 금지 (사용자 승인 후 메인만) | [Critical] |
| TeamCreate 실패 시 해당 단계만 단일 agent로 폴백 + WARN | [Critical] |

---

## 단계 0 — 준비 + 인원 산정 + 사용자 확정

1. **deferred 도구 스키마 로드**: `ToolSearch(query: "select:TeamCreate,TeamDelete,SendMessage,Agent")`.
2. `<run-id>` 생성(`YYYYMMDD-HHMMSS`), `.claude/team-pipeline/<run-id>/` 디렉토리 생성, 작업 설명을 `00-task.md`에 저장.
3. **1차 자동 산정** (입력 프롬프트 기반, 아래 §자동 인원 산정 규칙).
4. **사용자 확정 AUQ** — 1차 산정 결과 + 자동 조정 안내를 함께 보여준다:
   - 질문: `"제안 인원: Architect=A / Impl=I / Review=R / Tester=T (합계 X명, 비용 ~Y×). Impl·Review는 Architect 산출물(컴포넌트 수·cross-layer 여부)에 따라 단계 1 종료 후 자동 조정될 수 있습니다. 진행할까요?"`
   - 옵션:
     - `그대로 진행 (Recommended)` — 산정 그대로, 이후 자동 조정 허용
     - `조정` — 사용자가 단계별 인원 수동 입력
     - `취소` — 본 스킬 종료
5. `--*` 명시값이 있으면 1차 산정을 덮어씀. AUQ는 여전히 띄움.
6. **단계 1 종료 후 (2차 재산정)는 AUQ 없이 자동 적용** — 사용자는 단계 0에서 한 번만 확정. stdout 1줄 알림으로 가시성만 확보.
7. `--dry-run`이면 산정 결과만 출력하고 종료.
8. `TeamCreate` 도구 미가용(환경변수 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 누락 등) 감지 시 → N≥2 단계는 단일 agent로 강등 + WARN. N=1 단계는 영향 없음.

### 자동 인원 산정 규칙 (하한 1 · 상한 4)

메인은 다음 두 시점에 단계별 인원을 결정한다. **사용자가 `--architect N` 등 명시한 단계는 두 시점 모두 스킵**.

#### 1차 — 입력 프롬프트 기반 (단계 0)

| 단계 | 기본 | 가산 신호 | 상한 |
|------|------|-----------|------|
| Architect | 2 | "단순 버그/문구/스타일/한 줄 수정" → **1**. "보안·성능·migration·새 컴포넌트·아키텍처 결정" → **+1** | 3 |
| Impl | 2 | 프롬프트에 "4+ 파일 / 전반에 / 여러 모듈" → +1. "한 파일 / 한 함수" → 1 | 3 (1차에선 보수적) |
| Review | 1 | 리스크 키워드(보안·PII·인증·동시성·결제·외부 API·migration) hit당 +1 | 3 |
| Tester | 1 | "통합/E2E/회귀" → 2. "단위만/문서 변경" → 1 | 2 |

#### 2차 — Architect 산출물 기반 재산정 (단계 1 종료 직후)

Architect의 `architect.md`에서 메인이 추출:

- **K**: 식별된 컴포넌트/모듈 수
- **cross-layer**: 영향 파일이 2개 이상 레이어 (API+DB+UI 등)에 걸치는가

재산정:

- **Impl** = `min(max(K, 1), 4)`
- **Review** = 1차 Review + (cross-layer ? +1 : 0), 상한 4
- 1차와 차이 있으면 stdout 1줄로 알리고 자동 적용. AUQ 없음.
- 차이 없으면 출력 생략.
- 추출 실패 시 1차값 유지 + WARN.

---

## 단계 1 — 사람 리뷰 게이트 (Architect 직후)

- 질문: `"Architect 산출물을 바로 Coder 단계에 넘길지, 사람 멤버 리뷰 단계를 거칠지?"`
- 옵션:
  - `사람 리뷰 후 진행 (Recommended)` — 일시정지. `Coder 진행` / `다음 단계` / `진행` 입력 시 재개
  - `자동 진행` — 사람 리뷰 생략. 긴급·소규모 명시. 본인 책임

---

## 단계 2 — 단계별 실행 패턴

### N=1 (단일 sub-agent)

```
Agent({
  description: "<phase> 단계 — 작업 N",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: <자기 완결적 위임 프롬프트>
})
```

- `TeamCreate` 호출 금지.
- 산출물 경로는 동일 (`.claude/team-pipeline/<run-id>/0X-<phase>/...`).
- 컨텍스트 격리는 sub-agent 자체로 충분.

### N≥2 (팀)

1. `TeamCreate({ team_name: "<phase>-<run-id>", agents: [lead(opus), member-1..N(sonnet)] })`
   - 팀장 이름: `<phase>-lead` (`architect-lead` / `impl-lead` / `review-lead` / `test-lead`)
   - 팀원 이름: `<phase>-1..N`
   - **model 파라미터 명시 필수**
2. 메인 → `SendMessage(to: "<phase>-lead", ...)`로 작업 + 팀원 명단 + 직전 단계 산출물 **경로**만 전달
3. 팀장이 팀원에게 분할 위임 (`SendMessage`)
4. 팀장이 결과 통합 → 산출물 파일 저장 → 메인 반환
5. 메인이 한 단락 요약 + stdout 안내
6. **즉시** `TeamDelete({ team_name: "<phase>-<run-id>" })`

### 단계별 산출물 (N과 무관)

```
.claude/team-pipeline/<run-id>/
├── 00-task.md                 # 입력 작업 명세 + 확정 인원
├── 01-architect/architect.md  # 컴포넌트 구조, 인터페이스 시그니처, 2+ 대안(H/M/L)
├── 02-impl/
│   ├── impl-summary.md
│   └── diff.patch
├── 03-review/review.md        # verdict, issues[], severity, target_phase
├── 04-test/test.md            # verdict, 단위 테스트 결과, 재현 명령
└── pipeline.log               # 단계 전이 로그 + N 기록
```

### 자기 완결적 위임 프롬프트 (N=1 / N≥2 공통)

```
Task: <작업 설명>
Run ID: <run-id>
이전 단계 산출물: <파일 경로 목록>
이번 단계 목표: <한 줄>
산출물 저장 경로: <경로>
디시플린:
  - 검증 후 완료 / 근본원인 / URL 추측 금지 / context7 우선
  - git commit·worklog 직접 호출 금지
  - 시크릿 격리 (.env 등 커밋 금지)
```

---

## 단계 3 — 피드백 루프 (≤ 2회)

### 3-1. 결과 판독

- Reviewer/Tester `verdict: pass` → 다음 단계 또는 단계 4
- Reviewer 이슈 → 3-2 심각도 매트릭스
- Tester FAIL → BUG 분류 후 Coder 단계 재호출 (카운터 합산)

### 3-2. 심각도별 처리

| 심각도 | 처리 | 사용자 승인 |
|--------|------|-------------|
| LOW | Coder 단계 자동 수정 | 불필요 |
| MEDIUM/HIGH | AUQ (`전체 수정 (Recommended)` / `선택 수정` / `현 상태 유지`) | 필요 |

이슈 5건 이상이면 사용자 제시 전 병합·강등, 강등 항목 stdout 명시.

### 3-3. 재검사 (컨텍스트 최적화)

- `[→Coder]` 이슈: Coder 단계 재실행 → 이전 Handoff + 이슈 목록 + diff만 전달. 즉시 경량 재검사 (이전 이슈 해결 여부만).
- `[→Architect]` 이슈: Architect 재실행 → Coder 재실행 → Reviewer부터 재시작.
- 재실행 시 인원은 직전 확정값 유지 (자동 산정 다시 안 함).

### 3-4. 에스컬레이션 (2회 미해결)

AUQ:
- `Opus로 재시도 (Recommended)` — 해당 단계 팀원도 opus로 상향. 비용 증가.
- `새 인스턴스로 재시도` — fresh context, 원본 이슈만 1~3줄 전달.
- `이대로 진행` — 현 상태 수용, 사람 리뷰에서 다시 다룬다.
- `중단` — 파이프라인 종료, 미커밋 유지.

### 3-5. Reviewer LGTM 시 사람 리뷰 안내

자동 phase 전환 금지. stdout 출력:

```
[Recommended] Reviewer 사전 스캔 통과.
다음은 사람 멤버 리뷰입니다. 회의·비동기 채널에서 진행하세요.
사용자 명시 입력(`다음 단계`/`Tester 진행`/`진행`) 시에만 Tester 단계로 진행합니다.
```

---

## 단계 4 — 완료

### 4-1. 파이프라인 요약 (stdout)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ team-pipeline 완료 — run <run-id>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  확정 인원:   Architect=A / Impl=I / Review=R / Tester=T (합계 X)
  팀 운영:     N≥2 단계 <n>회 / 단일 agent 단계 <m>회
  이슈 통계:   HIGH <N>건 / MEDIUM <N>건 / LOW <N>건
  수정 파일:   <N>개
  실측 추정:   토큰 ~<X>k (solo 대비 <X.X>×)
  산출물:      .claude/team-pipeline/<run-id>/
```

### 4-2. 커밋 안내 (자동 호출 X)

```
AUQ: "코드 변경을 커밋할까요?"
  - 메인이 메시지 초안 작성 (Recommended) — 사용자 최종 승인 후 메인이 `git commit`
  - 직접 처리
  - 미커밋 유지
```

### 4-3. 사람 QA 안내

문서·규칙 전용 변경(`docs/`, `*.md` 단독, `.claude/skills/*/SKILL.md`)이면 스킵. 그 외:

```
[Critical] 통합·사용성·릴리즈 QA는 사람 2일/2명+ 별도 진행.
Tester ALL PASS는 단위 테스트만 의미합니다.
```

---

## 안전망

- env(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) 미설정 → N≥2 단계만 단일 agent로 강등 + WARN
- `TeamCreate` 실패 → 해당 단계만 단일 agent로 폴백 + WARN
- 동일 단계 자동 재시도 ≤ 2회, 초과 시 3-4 에스컬레이션
- 재시도 산출물은 `01-architect.v2/`, `02-impl.v2/` 식으로 버전 디렉토리에 보존

---

## 인자

```
/team-pipeline <작업 설명>
                  [--architect N] [--impl N] [--review N] [--test N]
                  [--dry-run]
```

- 인자 없으면 메인이 자동 산정. 명시값은 자동 산정을 덮어씀. 단계 0에서 AUQ로 1회 확정, 이후 Architect 산출물 기반 자동 조정.
- N=0은 허용 안 함. 단계를 스킵하려는 의도면 본 스킬 대신 다른 워크플로우 사용.
- `--dry-run`: 확정 인원만 출력하고 종료.

---

## 메인 에이전트 행동 지침

- 단계 0에서 확정한 인원 표를 `00-task.md` 끝에 기록.
- 단계 시작 전 stdout 한 줄: `"Phase 2 시작 — 구현 단계 (인원 N=2, 팀 구성)"` 또는 `"Phase 2 시작 — 구현 단계 (인원 N=1, 단일 agent)"`.
- 단계 종료 후 stdout 한 줄: `"Phase 3 완료 — 리뷰 verdict: pass, 다음은 테스트 단계 (N=1)"`.
- N≥2 단계 종료 직후 반드시 `TeamDelete`. 팀 잔존은 [Critical] 위반.
- 메인은 **오케스트레이터**. 직접 코드 작성/리뷰 금지.
- 자동 phase 전환 금지 — Reviewer LGTM 시 사람 리뷰 안내 + 사용자 명시 입력 대기.
- 재검사는 **diff + 이전 이슈만** 전달 (전체 코드 재전송 방지).

---

## 예시 실행 흐름

```
사용자: /team-pipeline 결제 API에 PII 마스킹 미들웨어 추가

메인:   run-id=20260520-103022, 디렉토리 생성.
        1차 산정: A=3 (보안+신규 컴포넌트) / I=2 / R=3 (PII·결제·인증 hit) / T=1 (합계 9, ~3.0×)
        [AUQ] "제안 인원 A=3/I=2/R=3/T=1. Impl·Review는 Architect 후 자동 조정될 수 있음. 진행할까요?"
사용자: 그대로 진행

메인:   Phase 1 시작 — Architect 팀 (N=3, opus 팀장 + sonnet×3)
        [TeamCreate architect-...] → architect.md (K=2, cross-layer: API+DB) → [TeamDelete]
        [자동 조정] 2차 재산정: Impl 2→2 / Review 3→4(상한 캡) — AUQ 없이 적용
        [사람 리뷰 게이트 AUQ] → 자동 진행

        Phase 2 시작 — Coder 팀 (N=2)
        [TeamCreate impl-...] → diff.patch → [TeamDelete]

        Phase 3 시작 — Reviewer 팀 (N=4)
        [TeamCreate review-...] → verdict: pass, HIGH×1(사이드 PII 추가 발견) → [TeamDelete]
        [사람 리뷰 안내 — 사용자 명시 입력 대기]
사용자: 다음 단계

메인:   Phase 4 시작 — Tester 단일 agent (N=1)
        [Agent ... opus] → test.md (ALL PASS, 단위 9건)
        [완료 요약 + 커밋 AUQ + 사람 QA 안내]
```

```
사용자: /team-pipeline 로그 메시지 오타 수정

메인:   1차 산정: A=1 (단순 수정) / I=1 (한 파일) / R=1 / T=1 (합계 4, ~1.5×)
        [AUQ] "제안 인원 A=1/I=1/R=1/T=1. Impl·Review는 Architect 후 자동 조정될 수 있음. 진행할까요?"
사용자: 그대로 진행

메인:   모든 단계 단일 agent로 진행. TeamCreate 호출 없음.
        (Architect K=1·단일 layer → 2차 재산정도 그대로)
        Phase 1~4 순차 실행 → 완료.
```
