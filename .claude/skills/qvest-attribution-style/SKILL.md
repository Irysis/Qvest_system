---
name: qvest-attribution-style
description: judge/governor 전용 QEPM 스타일 — Attribution & Feedback Loop (factor/selection/cost/residual 분해, Brinson + Carhart 4). research_philosophy ⑦ operationalize. Gate 심사 / admission 시 적용.
---

# Attribution & Feedback Style (research_philosophy ⑦)

**SOT**: `02_Infrastructure/docs/qvest_research_philosophy.md`. 위반 = AX-002 동급.

## ⑦ Attribution & Feedback Loop
- 수익 분해 4축: **factor + selection + cost + residual** (Brinson + Carhart 4-factor). 분기별 자동(attribution_quarterly_trigger).
- admit/graduation 판정 시 alpha가 어디서 오는지(factor exposure vs 순수 selection) 분해 확인 — factor-driven이면 기존 factor와 redundant 위험.

## 판정 원칙 (Judge/Governor)
- **AX-000 reframe 정합**: 실증·PIT·수리로 입증된 한계는 **정직히 FAIL 판정**. PASS로 합리화 금지(자기합리화 grep: 미미/관행적/보수적이면OK/대부분동일).
- **portfolio-alpha t-stat이 authoritative** (rank-IC t 아님). Harvey-Liu-Zhu hurdle(t≥2.95)은 realized portfolio alpha 회귀에 적용.
- **AX-008 Verification Triangulation**: Forge + Self-Adversarial(메인 세션 모델 자체 적대검증 — v8.2 Codex 대체) + Architect 3-source 중 2 PASS. Judge는 adjudicator(source 아님).
- **graduation gate (HARD 3종, forge-authoritative — measurement-graduation.md §3)**: portfolio-α t(NW lag-3) ≥2.95 / oos_retention ≥0.7(v2 3분할 중앙값, band [0.5,0.7)는 보강증거 2/3) / calmar ≥0.64. DSR≥0.5는 **sweep형 selection에만** HARD(chain 면제). MDD 45% 단독 hard fail 폐지 → structural drawdown 기준(2026-06-13). turnover hard fail 1,100%/yr. **SR target 2.5**(2026-05-29 상향).
- PIT C1~C15 독립 검증 + lockbox 접근(Judge 유일) + lookahead false-positive 판별.

## ⚠️ Cycle 2 교훈
- discovery WT가 4-gate fail이면 **정직히 GRADUATION_FAIL → Governor 미인계**. incumbent retain. (D ML 30f 사례)
- single-cross-section 지표(beta 등)는 walk-forward로 재검 — single-snapshot 과대평가 금지.

## 경계
판정만. 전략 설계/구현/수정 금지.
