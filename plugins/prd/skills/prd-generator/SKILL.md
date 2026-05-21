---
name: prd-generator
description: 새로운 기능/제품에 대한 PRD(제품 요구사항 문서)를 작성해야 할 때 사용한다. 모호한 아이디어를 표준화된 PRD 문서로 변환하기 위해 prd-generator 서브에이전트에 작업을 위임한다.
---

# prd-generator (thin wrapper)

이 skill 은 동일 플러그인 내 `prd-generator` 서브에이전트로 작업을 위임하는 얇은 진입점입니다. 실제 PRD 작성 로직·템플릿·체크리스트는 모두 서브에이전트가 보유합니다.

## 동작 방식

1. 사용자의 요청 원문(추가 컨텍스트 포함)을 그대로 prd-generator 에이전트에 전달합니다.
2. 에이전트가 명확화 질문 → 초안 작성 → 자체 체크리스트 검증을 수행합니다.
3. 결과를 받으면 사용자에게 다음 단계로 `prd-validator` 실행을 안내합니다.

## 호출 예시

```
Agent({
  subagent_type: "prd-generator",
  description: "PRD 초안 작성",
  prompt: "<사용자 요청 원문 + 알려진 컨텍스트>"
})
```

## 사용하지 않는 경우

- 이미 PRD가 존재하고 충돌/일관성만 확인하면 될 때 → `prd-validator` 사용
- 단순 기능 설명 1~2줄로 충분할 때 (PRD 양식이 과한 경우)
