---
name: docs-sync
description: "소스 변경의 의미를 관련 문서에 반영 — git diff로 변경된 심볼/모듈/시그니처를 추출하고 grep으로 영향 문서를 식별하여 Edit 후보를 제시한 뒤 사용자 승인 후 적용한다. docs-audit(정형 드리프트 감지)과 짝을 이루는 의미 갱신 스킬. '소스 바꿨으니 문서 반영해줘', 큰 리팩토링 직후, 세션 종료 전 사용."
user-invocable: true
argument-hint: "[SHA | SHA1..SHA2 | --last=N] [--scope=<dir>] [--apply]"
allowed-tools: Read, Edit, Glob, Grep, Bash(git:*), Bash(grep:*), Bash(find:*), Write, AskUserQuestion
---

# /docs-sync — 소스 변경 → 문서 의미 갱신

`git diff` 기반으로 코드 변경의 **의미**를 문서에 반영한다.
`/docs-audit` 가 정형 드리프트(끊긴 링크·가짜 ✅)를 감지한다면, 본 스킬은 **의미 변경**(새 함수·삭제된 모듈·시그니처 변경·rename 등)을 문서에 전파한다.

## 인자

- `$ARGUMENTS`: 진단 범위
  - 없음 → 마지막 push 이후 ~ HEAD (`@{push}..HEAD`)
  - `{SHA}` → `{SHA}..HEAD`
  - `{SHA1}..{SHA2}` → 명시적 범위
  - `--last=N` → `HEAD~N..HEAD`
- 옵션:
  - `--scope=<dir>` : 특정 하위 디렉토리만 (예: `--scope=src/codec/`)
  - `--apply` : 후보 전량 즉시 적용 (기본은 후보 제시 후 승인 대기)

## 운영 원칙 (CRITICAL)

1. **승인 후 Edit** — 후보를 한 번에 보여주고 사용자 승인 후 적용. `--apply`가 없으면 자동 Edit 금지
2. **세션 로그/변경 이력 제외** — `CHANGELOG.md`, `HISTORY.md`, `history.md` 류는 본 스킬 대상 아님
3. **증거 인용** — 후보 제시 시 `소스 파일:라인 → 문서 파일:라인` 양방향 명시
4. **의미 ≠ 정형** — 끊긴 링크·가짜 ✅는 `/docs-audit` 영역. 본 스킬은 심볼/모듈/시그니처 의미 갱신만
5. **소규모 우선** — 후보 30건 초과 시 우선순위 P1/P2/P3 분리, P1만 우선 적용

---

## Phase 0 — 범위 결정

1. `$ARGUMENTS` 파싱 → diff 범위 확정
2. `pwd` → 프로젝트 루트 결정 (`git rev-parse --show-toplevel`)
3. 변경 파일 목록:
   ```bash
   git diff --name-only "${BASE}".."${HEAD}"
   ```

---

## Phase 1 — 변경 심볼 추출

소스 변경 파일에서 **추가/삭제/시그니처 변경**된 심볼을 추출한다.

| 언어 | 추출 대상 | 정규식 |
|---|---|---|
| C/C++ | 함수, 클래스, 구조체 | `^[+-]\s*(\w[\w\s\*&<>]*\s+)?(\w+)::(\w+)\s*\(` / `^[+-]\s*class\s+(\w+)` |
| Rust | fn, struct, enum, trait, impl | `^[+-]\s*(pub\s+)?(fn\|struct\|enum\|trait\|impl)\s+(\w+)` |
| TS/JS | function, class, export | `^[+-]\s*(export\s+)?(async\s+)?(function\|class)\s+(\w+)` |
| Python | def, class | `^[+-]\s*(async\s+)?(def\|class)\s+(\w+)` |
| Java | class, interface, method | `^[+-]\s*(public\|private\|protected)?\s*(class\|interface\|\w+\s+\w+\s*\()` |
| C# | class, method, interface | `^[+-]\s*(public\|private\|internal)?\s*(class\|interface\|\w+\s+\w+\s*\()` |
| Go | func, type, interface | `^[+-]\s*(func\|type)\s+(\w+)` |

각 심볼의 변경 종류 분류:
- **ADDED** — 새로 추가 (문서에 신규 등재 필요)
- **REMOVED** — 삭제됨 (문서 참조 정리 필요)
- **RENAMED** — 이름 변경 (문서 일괄 치환 필요)
- **SIGNATURE_CHANGED** — 시그니처 변경 (문서 인자/반환 갱신 필요)

```bash
git diff "${BASE}".."${HEAD}" -- \
  '*.cpp' '*.h' '*.c' '*.rs' '*.ts' '*.tsx' '*.js' '*.jsx' \
  '*.py' '*.cs' '*.java' '*.go' \
  | grep -E '^[+-]' \
  | grep -vE '^[+-]{3}'
```

추출 결과 예시:
```
[Phase 1] 변경 심볼
ADDED   : 4 (encoder::nv12_zerocopy, ...)
REMOVED : 1 (legacy_d3d11_path)
RENAMED : 2 (init_codec → init_encoder, ...)
SIG     : 1 (capture_frame: 인자 1개 추가)
```

---

## Phase 2 — 영향 문서 식별

각 심볼에 대해 프로젝트 내 비-로그 문서를 grep:

```bash
TARGET_DOCS=$(find . \
  -type f \( -name '*.md' -o -name '*.mdx' \) \
  ! -path './node_modules/*' \
  ! -path './.git/*' \
  ! -path './dist/*' \
  ! -path './build/*' \
  ! -path './target/*' \
  ! -iname 'CHANGELOG.md' \
  ! -iname 'HISTORY.md' \
  ! -iname 'history.md')

for SYMBOL in $SYMBOLS; do
  grep -nH "$SYMBOL" $TARGET_DOCS
done
```

매칭 결과를 심볼 → 문서 역참조 테이블로 정리.

```
[Phase 2] 영향 문서 (역참조)
encoder::nv12_zerocopy (ADDED)
  → docs/architecture.md:142 (기존 패턴 설명)
  → README.md:38 (모듈 목록)
legacy_d3d11_path (REMOVED)
  → docs/codec-modules.md:91 (제거 필요)
init_codec → init_encoder (RENAMED)
  → docs/onboarding.md:24, 56, 89 (3건)
  → README.md:12 (1건)
```

---

## Phase 3 — Edit 후보 생성

각 매칭에 대해 권고 Edit을 생성. **자동 Edit 하지 않음**.

| 변경 종류 | 권고 Edit |
|---|---|
| ADDED | 문서의 모듈 목록·기능 표·아키텍처 섹션에 신규 항목 추가 |
| REMOVED | 참조 라인 삭제 또는 "deprecated" 표기 |
| RENAMED | 일괄 치환 (`Edit replace_all=true`) |
| SIGNATURE_CHANGED | 인자/반환 설명 갱신 |

각 후보를 다음 형식으로 출력:

```
[Edit 후보 #1] RENAMED — init_codec → init_encoder
- 파일: docs/onboarding.md
- 매칭: 3건 (라인 24, 56, 89)
- 권고: replace_all 치환
- 위험도: LOW

[Edit 후보 #2] ADDED — encoder::nv12_zerocopy
- 파일: docs/architecture.md:142
- 권고: 기존 D3D11 인코더 섹션 뒤에 NV12 zero-copy 경로 한 단락 추가
- 제안 본문:
  ```
  ### NV12 zero-copy 경로
  D3D11 텍스처를 CPU 복사 없이 NVENC 입력으로 직결 — `encoder::nv12_zerocopy()` 참조.
  ```
- 위험도: MEDIUM (의미 변경, 사용자 검토 권장)
```

---

## Phase 4 — 우선순위 분류

후보 30건 초과 시 자동 분류:

- **P1** — RENAMED + REMOVED (문서가 깨진 상태, 즉시 적용)
- **P2** — SIGNATURE_CHANGED (잘못된 정보 노출 중, 세션 내 적용)
- **P3** — ADDED (정보 누락, 다음 세션 가능)

후보 30건 이하면 분류 생략.

---

## Phase 5 — 사용자 승인 + 적용

후보 일람 표시 후 `AskUserQuestion` 으로 승인 요청:

```
[승인 요청] 위 후보 N건. 어떻게 진행할까요?
1. 전량 적용 (apply all)
2. P1만 적용 (apply P1)
3. 개별 선택 (번호 지정)
4. 취소 (skip)
```

승인 응답 후:
- 적용 대상 각각 `Edit` 호출 (Read 선행 필수)
- 적용 결과를 `.claude/reports/SYNC_DOCS_REPORT.md` 에 기록
- 미적용 후보도 보고서에 "skipped" 표기

`--apply` 플래그가 있으면 Phase 5 승인 단계 생략하고 전량 즉시 적용.

---

## Phase 6 — 보고

```markdown
# Sync Docs Report — {scope} — {YYYY-MM-DD HH:MM}

## 범위
- diff: {BASE}..{HEAD} (커밋 {N}개)
- 변경 소스: {N}개
- 변경 심볼: ADDED {N} / REMOVED {N} / RENAMED {N} / SIG {N}

## 적용 결과
| # | 종류 | 심볼 | 문서 | 결과 |
|---|------|------|------|------|
| 1 | RENAMED | init_codec→init_encoder | docs/onboarding.md | ✅ 3건 치환 |
| 2 | ADDED | nv12_zerocopy | docs/architecture.md:142 | ⏭ skipped (사용자 보류) |

## 미적용 후보 (다음 세션 처리 권장)
- ...

## 다음 단계
- 적용된 변경은 별도 커밋 권장: `docs: sync source changes`
```

---

## 종료 조건

- Phase 5 승인+적용 완료 (또는 사용자 취소)
- `SYNC_DOCS_REPORT.md` 파일 작성
- 대화창에는 적용/skip 카운트만 출력 (상세는 보고서)

## 실패/중단 시 거동

- diff 범위가 비어있음 → 즉시 종료, 보고서 생성 안 함
- 심볼 추출 0건 → "의미 변경 없음 — sync 불필요" 출력 후 종료
- Edit 실패 → 해당 후보를 보고서에 `FAIL` 표기, 다음 후보 진행

## 사용 시나리오

1. **세션 종료 직전**: 마지막 push 이후 변경 분 → `/docs-sync` → 후보 검토 → 적용 → push
2. **큰 리팩토링 직후**: `/docs-sync HEAD~10..HEAD --scope=src/codec/`
3. **단일 함수 rename 후**: `/docs-sync --last=1`

## 관련 스킬

- `/docs-audit` — 정형 드리프트(끊긴 링크·가짜 ✅) 감지 (본 스킬과 짝)
