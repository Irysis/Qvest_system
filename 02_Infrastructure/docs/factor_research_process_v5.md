# Factor Research Process v5.0 — 핵심 변경 요약

## v4 → v5 변경점

1. **S5 역할 분리**: Scout 설계 + Forge 실행 (anchoring 방지)
2. **S1 순수 팩터**: DD/VT/Regime 오버레이 금지 (CLAUDE.md Level 0)
   - 예외: 전략 자체가 국면을 alpha source로 사용하는 경우 Regime 허용
3. **TODO 기반 작업 큐**: Pipeline driver → TODO → Agent 소비 → DONE
4. **Pipeline driver 라우팅**: 에이전트가 아닌 R 코드가 모든 라우팅 결정
5. **LLM 한계 반영**: 50줄 이내 핵심, 허용 목록, 보조 작업

## S5 Mutation 흐름 (v5)

```
S4 KOSPI 미달 → Pipeline: TODO_S5_DESIGN → Scout inbox
Scout: 설계 (S3 직교성 + DB 기반) → s5_mutation_design_{n}.json
Pipeline: DONE 감지 → TODO_S5_EXEC → Forge inbox
Forge: Scout 지시대로만 코드 수정 + 실행
Pipeline: hurdle 감지 → S2→S3→S4 재순환
```

## 에이전트 역할

| Agent | S0 | S1 | S2 | S3 | S4 | S5설계 | S5실행 | S6 | S7 |
|-------|----|----|----|----|----|----|----|----|-----|
| Scout | ✅ | | | ✅ | | **✅** | | | |
| Forge | | ✅ | ✅ | | ✅ | | **✅** | | |
| Judge | | | | | | | | ✅ | ✅ |

## 상세: `02_Infrastructure/factor_research_process_v5_full.md` (사용자 제공 원본)
