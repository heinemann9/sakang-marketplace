---
name: docs-audit
description: "프로젝트 정합성 감사 — 문서·스크립트·계획서 간 정형 드리프트를 3개 트랙(LINK/PLAN/SCRIPT)으로 전수 검사한다. 범위가 크면 WBS를 세워 청크 단위로 분할 진행하되 어떤 파일도 건너뛰지 않는다. 주기적 정합성 점검, 세션 종료 전 정합성 확인, '문서와 코드 싱크 맞춰줘' 요청 시 활성. 읽기 전용."
user-invocable: true
argument-hint: "[scope-path] [--track=LINK,PLAN,SCRIPT] [--report-dir=<dir>]"
allowed-tools: Read, Glob, Grep, Bash(test:*), Bash(grep:*), Bash(find:*), Bash(git:*), Write
---

# /docs-audit — 프로젝트 정합성 감사

문서·스크립트·계획서 사이의 **정형** 드리프트를 3개 트랙으로 **전수 검사**한다.
범위가 크면 WBS 를 세워 청크로 분할 진행하되 **어떤 파일도 건너뛰지 않는다**.

> 의미 변경(함수명 변경 → 문서 갱신 등)은 본 스킬의 대상이 아니다. 그건 `/docs-sync` 영역.

## 인자

- `$ARGUMENTS`:
  - 첫 번째 위치 인자 — 감사 루트 경로 (생략 시 `pwd`)
  - `--track=LINK,PLAN,SCRIPT` — 특정 트랙만 (기본: 전 트랙)
  - `--report-dir=<dir>` — 리포트 출력 디렉토리 (기본 `.claude/reports/`)

## 운영 원칙 (CRITICAL)

1. **전수 검사** — 스캔 대상으로 선정된 파일은 단 1개도 스킵하지 않는다. 샘플링 금지
2. **계획 후 실행** — 대상 파일 총합이 임계를 넘으면 반드시 WBS 먼저 작성
3. **청크 추적** — WBS 체크박스로 진행 상황을 가시화, 청크 완료마다 갱신
4. **증거 인용** — 드리프트 보고 시 `파일:라인` 형식으로 근거 명시
5. **파괴 금지** — 본 스킬은 **읽기 전용**. 수정 제안은 리포트에 기재하되 자동 적용은 하지 않음

---

## Phase 0 — 스캔 범위 결정

1. `$ARGUMENTS` 파싱 → scope 경로 결정 (미지정 시 `pwd`)
2. 리포트 디렉토리 확인/생성 — 기본 `<scope>/.claude/reports/`
3. 제외 패턴 적용: `node_modules/`, `.git/`, `dist/`, `build/`, `target/`, `vendor/`

---

## Phase 1 — 대상 파일 인벤토리 (전수)

3개 트랙 각각의 검사 대상을 `Glob`으로 **완전 열거**한다.

| 트랙 | 대상 |
|---|---|
| **LINK** | `**/*.md`, `**/*.mdx` 내부 상대경로 링크 / 이미지 / 코드펜스 경로 |
| **PLAN** | `**/PLAN*.md`, `**/TASK*.md`, `**/ROADMAP*.md`, `**/TODO*.md` 의 체크박스 |
| **SCRIPT** | `**/*.sh`, `.claude/commands/**`, `.claude/hooks/**`, `.claude/skills/**/SKILL.md` 내부 경로·바이너리 참조 |

출력 예시:
```
[Phase 1] 인벤토리
LINK    : 82 files
PLAN    : 14 files / 96 checkbox
SCRIPT  : 47 files
──────────────────────────
합계    : 143 files
규모    : MEDIUM
```

**규모 판정**:
- SMALL ≤ 50 files → Phase 2 스킵, 즉시 Phase 3 실행
- MEDIUM 51–200 files → Phase 2 에서 WBS 3–5청크 자동 분할 후 실행
- LARGE 201+ files → Phase 2 에서 WBS 작성 후 **사용자 승인 대기**

---

## Phase 2 — WBS 작성 (MEDIUM/LARGE 만)

`<report-dir>/CONSISTENCY_PLAN.md` 생성.

```markdown
# Consistency Audit Plan — {scope} — {YYYY-MM-DD}

## 범위
- LINK: {N}
- PLAN: {N}
- SCRIPT: {N}

## 청크 분할 (건너뛰기 금지)

### Chunk 1/M — LINK 파트 A
- [ ] {파일 1}
- [ ] {파일 2}
- ...

### Chunk 2/M — LINK 파트 B
...

## 실행 규칙
- 각 청크 완료 시 체크박스 전량 ✅ → 다음 청크 진입
- 미완료 체크박스 있으면 다음 청크로 넘어가지 않는다
- 세션 중단 시 체크 상태 그대로 보존, 재개 시 미완료부터 속개
```

**청크 크기 가이드**: 트랙별 15~25 파일/청크. LARGE 일 때 Phase 3 진입 전 사용자 승인 요청.

---

## Phase 3 — 트랙별 검증 (전수 실행)

### Track A — LINK (문서 참조 실존)

각 마크다운 파일에 대해:
1. `Read`로 본문 로드
2. 상대경로 링크·이미지 추출:
   - 마크다운 링크: `\[.*?\]\((?!http|mailto)(.+?)\)`
   - 이미지: `!\[.*?\]\((?!http)(.+?)\)`
   - 코드펜스 내 경로 리터럴
3. 각 참조를 `test -e` 또는 `Glob` 으로 실존 확인
4. 결과:
   - **OK** — 실존
   - **ORPHAN** — 참조 있으나 실물 없음
   - **CASE_MISMATCH** — 경로 대소문자 불일치 (크로스플랫폼 리스크)

### Track B — PLAN (진척 vs 코드)

각 계획 문서에 대해:
1. 체크박스 파싱: `^- \[x\] (.+)$` / `^- \[ \] (.+)$`
2. 체크된 항목의 키워드(함수명·파일명·모듈명) 추출
3. `Grep` 으로 해당 키워드가 실제 코드에 존재하는지 확인
4. `git log --all -S "{키워드}" --oneline` 로 커밋 이력 확인
5. 결과:
   - **OK** — ✅ & 코드 존재 & 커밋 이력 있음
   - **DRIFT_FALSE_GREEN** — ✅ 표시되었으나 코드/커밋 흔적 없음 (가짜 완료)
   - **DRIFT_FALSE_RED** — ⬜ 미완료 표시이나 코드·커밋에는 이미 구현됨
   - **AMBIGUOUS** — 키워드 추출 실패(서술형) → 수동 검토 요망

### Track C — SCRIPT (스크립트 의존성 실존)

각 스크립트 파일에 대해:
1. 경로 리터럴 추출: 절대경로, `$VAR_ROOT/...` 패턴
2. 바이너리 참조 추출: `which` 가능한 명령
3. 결과:
   - **OK** — 모든 참조 유효
   - **ORPHAN_PATH** — 경로 없음
   - **HARDCODED_ABS_PATH** — `/Users/...`, `C:\...`, `D:\...` 등 사용자 홈/드라이브 하드코딩 (크로스플랫폼 리스크)

---

## Phase 4 — 청크 진행 추적

- 각 청크 시작: "Chunk {i}/{M} 시작 — 파일 {N}개"
- 청크 내 개별 파일 결과는 **내부 버퍼**에 누적 (대화 스팸 방지)
- 청크 종료: `CONSISTENCY_PLAN.md` 체크박스 전량 갱신 + 중간 요약 1줄

**건너뛰기 방지 가드**: Phase 3 종료 직전 `grep -c "^- \[ \]" CONSISTENCY_PLAN.md` 로 미처리 수 확인 → 0이 아니면 자동 속개.

---

## Phase 5 — 통합 리포트

`<report-dir>/CONSISTENCY_REPORT.md` 생성:

```markdown
# Consistency Audit Report — {scope} — {YYYY-MM-DD HH:MM}

## 요약
| 트랙 | OK | DRIFT | ORPHAN | 합계 |
|------|----|-------|--------|------|
| LINK   | 74 | –   | 6 | 80 |
| PLAN   | 42 | 8   | – | 50 |
| SCRIPT | 45 | –   | 2 | 47 |

## DRIFT / ORPHAN 상세

### [DRIFT_FALSE_GREEN] PLAN
- `{프로젝트}/PLAN.md:42` — "✅ {기능} 달성" → `grep` 결과 함수 `{함수명}` 미발견
  - 권고: 체크박스 ⬜로 되돌리거나, 실제 구현 파일 링크 추가

### [ORPHAN] LINK
- `docs/index.md:12` → `docs/archived/old.md` (실존 ✗)
  - 권고: 파일 생성 또는 링크 제거

### [HARDCODED_ABS_PATH] SCRIPT
- `.claude/hooks/build.sh:5` — `/Users/foo/repo` 하드코딩 발견
  - 권고: 환경변수 또는 상대경로로 치환

## 조치 우선순위
1. **P1 (즉시)** — HARDCODED_ABS_PATH, ORPHAN (크로스플랫폼/링크 깨짐)
2. **P2 (세션 내)** — DRIFT_FALSE_GREEN (가짜 완료 = 진척 오판 유발)
3. **P3 (다음 세션)** — CASE_MISMATCH, AMBIGUOUS

## 다음 단계
- 본 리포트는 읽기 전용. 수정은 별도 지시 필요
- 의미 변경 갱신은 `/docs-sync` 사용
```

---

## 종료 조건

- Phase 5 리포트 파일 작성 완료
- `CONSISTENCY_PLAN.md` 모든 체크박스 ✅
- 대화창에는 요약 표만 출력 (상세는 리포트 파일 링크)

## 실패/중단 시 거동

- 청크 중 Bash/Grep 에러 → 해당 파일 **SKIP 금지**. 리포트의 `AUDIT_ERROR` 섹션에 기록 후 다음 파일 진행
- 세션 중단 → `CONSISTENCY_PLAN.md` 체크 상태 보존 → 재호출 시 속개 (미체크부터)

## 관련 스킬

- `/docs-sync` — 의미 변경(함수명·시그니처) 기반 문서 갱신 (본 스킬과 짝)
