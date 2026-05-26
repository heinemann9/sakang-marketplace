---
name: solo-pipeline
description: "설계(Architect) → 구현(Coder) → 리뷰(Reviewer) → 테스트(Tester) 4단계를 단계별 역할 전문 sub-agent 1명씩으로 순차 수행한다. 인원 협상 없음(항상 1/1/1/1). 모델: Architect=opus, Coder=sonnet, Reviewer=opus, Tester=sonnet (axlab 실측 패턴). 1~3 파일 단순 수정·리팩터링·버그 수정에 단계 분리 디시플린을 적용하고 싶을 때 사용. 다관점·병렬이 필요하면 team-pipeline 또는 team-flat 사용."
user-invocable: true
argument-hint: "<작업 설명> [--dry-run]"
allowed-tools: Read, Write, Edit, Bash, Agent, AskUserQuestion, ToolSearch
---

# solo-pipeline — 4단계 × 단계별 단일 sub-agent 파이프라인

설계 → 구현 → 리뷰 → 테스트 4단계를 **단계마다 새 sub-agent를 호출**하여 자가 수행한다. 인원은 항상 1/1/1/1로 고정 — 협상·산정 없음. 단계별 역할이 다르므로 모델도 다르게 배정한다.

| 단계 | 역할 | 모델 | 이유 |
|---|---|---|---|
| 1 | Architect | **opus** | 설계·대안 비교는 추론 깊이 필요 |
| 2 | Coder | **sonnet** | 사양대로 구현, 속도·비용 효율 |
| 3 | Reviewer | **opus** | 사이드 검출·근본원인 추적, 깊이 필요 |
| 4 | Tester | **sonnet** | 단위 테스트 생성은 정형, 비용 효율 |

비용: solo(스킬 없음) 대비 토큰 ~1.4~1.6× / wall-clock ~1.3×. flex(team-pipeline)의 N=1/1/1/1보다 가벼움 (인원 산정·AUQ 절차 없음).

---

## 언제 쓰고 언제 쓰지 말 것

✅ **본 스킬 적합**
- 1~3 파일 단순 수정·리팩터링·버그 수정인데 **단계 분리(설계→리뷰→테스트) 디시플린**을 적용하고 싶다
- 다관점·검출 폭은 critical 아니지만 self-review·단위 테스트는 받고 싶다
- 비용은 최저로 유지하면서 파이프라인 형식은 갖추고 싶다

❌ **다른 모드로**
- 신규 컴포넌트 / 보안·성능 critical / 사이드 스캔 필요 → **team-pipeline (flex)**
- 4+ 독립 파일에 같은 패턴 반복 (codemod·rename) → **team-flat** (향후)
- 1~2줄 단순 수정, 단계 분리 자체가 과함 → **순수 solo** (본 스킬 호출 없이 그냥 진행)

---

## 핵심 원칙

| 원칙 | 강제 수준 |
|------|-----------|
| 각 단계는 별도 sub-agent (`Agent` 도구) — 단일 컨텍스트 통합 금지 | [Critical] |
| 단계별 `model` 인자 명시 (Architect/Reviewer=opus, Coder/Tester=sonnet) | [Critical] |
| `TeamCreate` 호출 금지 — 그것이 solo의 정의 | [Critical] |
| 단계 종료 시 산출물 파일 작성 강제 (다음 단계는 파일에서 읽음, 머릿속 기억 의존 금지) | [Critical] |
| Reviewer LGTM ≠ 사람 멤버 리뷰 통과 — 자동 phase 전환 금지 | [Recommended] |
| Tester ALL PASS = 단위 테스트만. 통합·사용성·릴리즈 QA는 사람 2일/2명+ 별도 | [Critical] |
| 피드백 루프 ≤ 2회, LOW 자동·MEDIUM+ AUQ 승인 | [Recommended] |
| 에이전트는 `git commit` 직접 호출 금지 (사용자 승인 후 메인만) | [Critical] |

---

## 단계 0 — 준비

1. **deferred 도구 스키마 로드**: `ToolSearch(query: "select:Agent")`.
2. `<run-id>` 생성(`YYYYMMDD-HHMMSS`), `.claude/solo-pipeline/<run-id>/` 디렉토리 생성, 작업 설명을 `00-task.md`에 저장.
3. stdout 1줄 고지:
   ```
   [solo-pipeline 시작] run=<run-id>
   단계 1(Architect/opus) → 2(Coder/sonnet) → 3(Reviewer/opus) → 4(Tester/sonnet)
   ```
4. `--dry-run`이면 여기서 종료.

> 인원 협상·AUQ 없음. 본 스킬은 호출 자체가 "1/1/1/1로 진행" 의도.

---

## 단계 1 — Architect 에이전트

### 호출

```
Agent({
  description: "Architect 단계 — <작업 한 줄>",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: <Architect 위임 프롬프트>
})
```

### Architect 위임 프롬프트

```
Role: Architect
Task: <작업 설명>
Run ID: <run-id>
산출물 저장 경로: .claude/solo-pipeline/<run-id>/01-architect/architect.md

책임:
  - 요구사항 분석 + 컴포넌트 구조
  - 인터페이스 시그니처
  - 2+ 대안 비교 (H/M/L) — 권장안 명시
  - 영향 파일 목록
  - 구현 순서

금지:
  - 구현 코드 작성 (Coder의 책임)
  - 테스트 작성 (Tester의 책임)

디시플린:
  - context7 우선, URL 추측 금지
  - 검증 후 완료 / 근본원인
  - git commit·worklog 직접 호출 금지
```

### 단계 1 종료 후 — 사람 리뷰 게이트

- 질문: `"Architect 산출물을 바로 Coder 단계에 넘길지, 사람 멤버 리뷰 단계를 거칠지?"`
- 옵션:
  - `사람 리뷰 후 진행 (Recommended)` — 일시정지. `Coder 진행` / `다음 단계` / `진행` 입력 시 재개
  - `자동 진행` — 사람 리뷰 생략. 긴급·소규모 명시. 본인 책임

---

## 단계 2 — Coder 에이전트

### 호출

```
Agent({
  description: "Coder 단계 — <작업 한 줄>",
  subagent_type: "general-purpose",
  model: "sonnet",
  prompt: <Coder 위임 프롬프트>
})
```

### Coder 위임 프롬프트

```
Role: Coder
Task: <작업 설명>
Run ID: <run-id>
이전 단계 산출물: .claude/solo-pipeline/<run-id>/01-architect/architect.md
산출물 저장 경로:
  - .claude/solo-pipeline/<run-id>/02-impl/impl-summary.md
  - .claude/solo-pipeline/<run-id>/02-impl/diff.patch (git diff 스냅샷)

책임:
  - architect.md 설계 사양 충실 구현
  - SOLID · 최소 변경 · 기존 패턴 재사용
  - 시크릿 격리 (.env 등 커밋 금지)
  - impl-summary.md에 변경 파일·핵심 결정 기록

금지:
  - 테스트 작성 (Tester의 책임)
  - 설계 임의 변경 (이슈 발견 시 메인에 보고 후 Architect 재호출)

디시플린:
  - 검증 후 완료 / 근본원인 / context7 우선
  - git commit 직접 호출 금지
```

---

## 단계 3 — Reviewer 에이전트

### 호출

```
Agent({
  description: "Reviewer 단계 — <작업 한 줄>",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: <Reviewer 위임 프롬프트>
})
```

### Reviewer 위임 프롬프트

```
Role: Reviewer
Task: <작업 설명>
Run ID: <run-id>
이전 단계 산출물:
  - .claude/solo-pipeline/<run-id>/01-architect/architect.md
  - .claude/solo-pipeline/<run-id>/02-impl/diff.patch
  - .claude/solo-pipeline/<run-id>/02-impl/impl-summary.md
산출물 저장 경로: .claude/solo-pipeline/<run-id>/03-review/review.md

책임 — 다음 체크리스트를 모두 통과시키며 검토:
  □ 보안 (인증·인가·SQL injection·XSS·시크릿 노출)
  □ 성능 (N+1, 불필요 루프, 캐시 누락)
  □ 에러 처리 (예외 누락·과한 catch·복구 가능성)
  □ SOLID 위반 (단일 책임·결합도)
  □ 테스트 가능성 (의존성 주입·순수 함수)
  □ 중복·dead code
  □ 네이밍·가독성
  □ architect.md 사양 준수 여부

산출 형식 (review.md):
  verdict: pass | fail
  issues:
    - severity: HIGH|MEDIUM|LOW
      target_phase: Coder | Architect
      file:line
      description:
      suggested_fix:

자세 — "내가 짠 게 아닌 코드를 보는 척하라". self-review 사각지대 의식.

금지:
  - 코드 직접 수정 (Coder의 책임)
  - git commit 직접 호출
```

### 단계 3 결과 처리

**verdict: pass** → 단계 4로

**이슈 있음** → 심각도별 처리:

| 심각도 | 처리 | 사용자 승인 |
|---|---|---|
| LOW | Coder 단계 자동 재호출 | 불필요 |
| MEDIUM/HIGH | AUQ (`전체 수정 (Recommended)` / `선택 수정` / `현 상태 유지`) | 필요 |

**재호출**:
- `[→Coder]` 이슈: Coder 재호출 시 architect.md + review.md + 이전 diff.patch만 전달
- `[→Architect]` 이슈: Architect 재호출 → Coder 재호출 → Reviewer부터 재시작

**루프 ≤ 2회**. 초과 시 에스컬레이션 AUQ:
- `새 인스턴스로 재시도 (Recommended)` — fresh context
- `이대로 진행` — 현 상태 수용
- `중단` — 파이프라인 종료, 미커밋 유지

### Reviewer LGTM 시 사람 리뷰 안내

자동 phase 전환 금지. stdout 출력:

```
[Recommended] Reviewer 사전 스캔 통과.
다음은 사람 멤버 리뷰입니다. 회의·비동기 채널에서 진행하세요.
사용자 명시 입력(`다음 단계`/`Tester 진행`/`진행`) 시에만 Tester 단계로 진행합니다.
```

---

## 단계 4 — Tester 에이전트

### 호출

```
Agent({
  description: "Tester 단계 — <작업 한 줄>",
  subagent_type: "general-purpose",
  model: "sonnet",
  prompt: <Tester 위임 프롬프트>
})
```

### Tester 위임 프롬프트

```
Role: Tester
Task: <작업 설명>
Run ID: <run-id>
이전 단계 산출물:
  - .claude/solo-pipeline/<run-id>/02-impl/diff.patch
  - .claude/solo-pipeline/<run-id>/02-impl/impl-summary.md
산출물 저장 경로: .claude/solo-pipeline/<run-id>/04-test/test.md

책임:
  - Happy Path / Edge Case / Error Path 단위 테스트 작성·실행
  - 프로젝트 테스트 러너로 실행, 결과 캡처
  - test.md에 verdict(pass|fail) · 케이스 목록 · 재현 명령 기록

금지:
  - 통합·E2E·사용성 테스트 (사람 QA의 책임)
  - 프로덕션 코드 수정 (Coder의 책임)

디시플린:
  - 검증 후 완료 / context7 우선
  - git commit 직접 호출 금지
```

### Tester FAIL 시

BUG 분류 후 Coder 단계 재호출 (루프 카운터에 합산, ≤ 2회).

---

## 산출물 디렉토리 구조

```
.claude/solo-pipeline/<run-id>/
├── 00-task.md                    # 입력 작업 명세
├── 01-architect/architect.md     # 컴포넌트·인터페이스·2+ 대안
├── 02-impl/
│   ├── impl-summary.md           # 변경 파일·핵심 결정
│   └── diff.patch                # git diff 스냅샷
├── 03-review/review.md           # verdict · issues
├── 04-test/test.md               # verdict · 단위 테스트 결과 · 재현 명령
└── pipeline.log                  # 단계 전이 로그
```

재시도 산출물은 `02-impl.v2/`, `03-review.v2/` 식으로 버전 디렉토리에 보존.

---

## 완료

### 파이프라인 요약 (stdout)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ solo-pipeline 완료 — run <run-id>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  단계 운영:   Architect(opus) → Coder(sonnet) → Reviewer(opus) → Tester(sonnet)
  재호출:      Coder <N>회 / Architect <N>회
  이슈 통계:   HIGH <N>건 / MEDIUM <N>건 / LOW <N>건
  수정 파일:   <N>개
  실측 추정:   토큰 ~<X>k (solo 대비 <X.X>×)
  산출물:      .claude/solo-pipeline/<run-id>/
```

### 커밋 안내 (자동 호출 X)

```
AUQ: "코드 변경을 커밋할까요?"
  - 메인이 메시지 초안 작성 (Recommended) — 사용자 최종 승인 후 메인이 `git commit`
  - 직접 처리
  - 미커밋 유지
```

에이전트가 `git commit` 직접 호출 금지. 메인이 사용자 명시 승인 후에만 실행.

### 사람 QA 안내

문서·규칙 전용 변경(`docs/`, `*.md` 단독, `.claude/skills/*/SKILL.md`)이면 스킵. 그 외:

```
[Critical] 통합·사용성·릴리즈 QA는 사람 2일/2명+ 별도 진행.
Tester ALL PASS는 단위 테스트만 의미합니다.
```

### 산출물 정리 AUQ

`.claude/solo-pipeline/<run-id>/`는 untracked로 누적되어 워킹트리를 흐리므로 스킬 종료 시점에 사용자에게 정리 의사를 묻는다.

AUQ:
  - `현재 run-id만 삭제 (Recommended)` — 이번 실행 산출물(`<run-id>/`) 디렉터리를 제거. 다른 run-id는 유지.
  - `모든 run-id 삭제` — `.claude/solo-pipeline/` 하위 전체 정리.
  - `보존` — 그대로 둠. 디버깅/회귀 분석용으로 남기려는 경우.

안전망:
  - 커밋 안내 단계에서 사용자가 `미커밋 유지`를 선택했고 산출물 중 `diff.patch` 또는 `02-impl/` 결과물이 유일한 변경 백업이면, AUQ의 기본값을 `보존`으로 전환하고 "산출물이 유일한 백업입니다" 경고를 stdout에 명시한다.

---

## 안전망

- `Agent` 도구 미가용 → 메인이 직접 4단계 수행 + WARN (sub-agent 분리 효용은 상실)
- 동일 단계 자동 재호출 ≤ 2회, 초과 시 에스컬레이션 AUQ
- 재호출 시 이전 산출물 + 이슈 목록 + diff만 전달 (전체 코드 재전송 방지)

---

## 인자

```
/solo-pipeline <작업 설명> [--dry-run]
```

- `--dry-run`: 디렉토리 생성 + 시작 안내만 출력하고 종료
- 모델 오버라이드 옵션 없음 (axlab 패턴 고정). 다른 배정이 필요하면 `team-pipeline` 사용

---

## 메인 에이전트 행동 지침

- 단계 시작 전 stdout 한 줄: `"Phase 2 시작 — Coder(sonnet) 호출"`
- 단계 종료 후 stdout 한 줄: `"Phase 2 완료 — diff.patch 저장, 다음은 Reviewer(opus)"`
- 메인은 **오케스트레이터**. 직접 코드 작성/리뷰 금지.
- 자동 phase 전환 금지 — Reviewer LGTM 시 사람 리뷰 안내 + 사용자 명시 입력 대기.
- 재검사는 **diff + 이전 이슈만** 전달.
- `TeamCreate` 호출 절대 금지 — 본 스킬은 sub-agent (`Agent` 도구) 전용.

---

## 예시 실행 흐름

```
사용자: /solo-pipeline 결제 API 응답에 마스킹 누락된 필드 추가

메인:   [solo-pipeline 시작] run=20260520-110530
        Phase 1 시작 — Architect(opus) 호출
        [Agent architect ...] → architect.md (K=1, 단일 layer)
        [사람 리뷰 게이트] → 자동 진행

        Phase 2 시작 — Coder(sonnet) 호출
        [Agent coder ...] → diff.patch + impl-summary.md

        Phase 3 시작 — Reviewer(opus) 호출
        [Agent reviewer ...] → review.md (verdict: pass, MED×1)
        [AUQ MEDIUM 처리] → 전체 수정
        [Coder 재호출 ...] → diff.patch.v2
        [Reviewer 경량 재검사 ...] → verdict: pass
        [사람 리뷰 안내]
사용자: 다음 단계

메인:   Phase 4 시작 — Tester(sonnet) 호출
        [Agent tester ...] → test.md (ALL PASS, 단위 4건)
        [완료 요약 + 커밋 AUQ + 사람 QA 안내]
```
