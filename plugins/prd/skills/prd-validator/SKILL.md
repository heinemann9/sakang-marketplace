---
name: prd-validator
description: 작성된 PRD가 기존 PRD들과 정책·데이터·용어 측면에서 충돌하지 않는지 교차 검증해야 할 때 사용한다. 검증 로직은 prd-validator 서브에이전트에 위임한다.
---

# prd-validator (thin wrapper)

이 skill 은 동일 플러그인 내 `prd-validator` 서브에이전트로 검증 작업을 위임하는 얇은 진입점입니다. 실제 검증 체크리스트·CoT 프로세스·심각도 분류는 모두 서브에이전트가 보유합니다.

## 동작 방식

1. 검증 대상 PRD 경로(또는 본문)와 비교할 기존 PRD 묶음을 prd-validator 에이전트에 전달합니다.
2. 에이전트가 정책/데이터흐름/용어/엣지케이스 4 축으로 교차 검증을 수행합니다.
3. Critical/Major/Minor 심각도별 이슈 리포트를 반환하며, 사용자 확인 후에만 PRD 문서를 업데이트합니다.

## 호출 예시

```
Agent({
  subagent_type: "prd-validator",
  description: "PRD 교차 검증",
  prompt: "검증 대상: <path>\n관련 PRD: <paths>\n용어집(있다면): docs/terminology.md"
})
```

## 권장 순서

1. `prd-generator` → 신규 PRD 초안
2. `prd-validator` → 본 skill 로 기존 PRD와 교차 검증
3. 사용자 확인 → 필요 시 PRD 수정 반영
