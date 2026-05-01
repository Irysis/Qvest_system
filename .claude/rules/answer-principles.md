# Qvest 답변 원칙 (Level 0)

**원칙**: 쉬운/빠른/그럴듯한 답변 ❌ → 정확/완결/실행가능 답변 ✓
**위반 = AX-002 동급**
**발효**: 2026-04-29 (L-247) / Session 75 v6.4 rule 분리

## 8원칙 (모든 비단순 작업)

1. 표면 아닌 실제 목적
2. 하위 과제 분해
3. 명시적 처리
4. 일반론 회피, 구체적 (파일경로 + line + 수치 + 출처)
5. 가정/예외/리스크 점검
6. 어려운 부분 생략 ❌
7. 불확실성 명시
8. 실행가능 결론

## 5금지

- 조용한 단순화
- TODO·추상화 대체
- hallucination
- 검증 없이 완료
- 얕고 그럴듯한 마무리

## 자가체크 (제출 전)

> "나는 실제 문제를 해결했는가, 쉬운 답변을 만든 것인가?" → 쉬우면 수정 후 제출

## 비단순 작업 boundary

다중 검증 / 의사결정 영향 / 메모리 commit / 백테스트 보고 / 팀 공유 파일 수정 / 비교·분해 분석 / WT 단계 전이 / 사용자 비판·정정 응답 — 경계 모호 시 비단순 분류 (보수적).

## 회피 표현 grep (검증 증거 없이 사용 시 위반)

"유사 / 동일 / 거의 / 대략 / 근사 / 추정 / 예상 / 아마 / TBD / 추후 / 이정도 / 관행 / 영향미미 / 보수적이면 / 이미반영"

명시 라벨 ("검증 안 됨 (가정)", "TBD — task #N 후속") 은 허용.

## 백테스트 자체 합성 금지

PerformanceAnalytics 표준 함수만:
- `Return.portfolio`
- `Return.cumulative`
- `apply.monthly`
- `table.AnnualizedReturns`
- `maxDrawdown`

`prod(1+r)-1` / `cumprod(1+r)` / `0.8*r1+0.2*r2` 자체 합성 ❌.

예외: Charter v1.4 §12 ER-based Sharpe.

## 참조

- `00_Lawbook/Multi_Agent/qvest_answer_principles.md`
- `_shared_prefix.md::<answer_principles>`
- L-247 사례
- `02_Infrastructure/hooks/answer_principles_grep.sh` (PostToolUse Level 2 soft alert)
