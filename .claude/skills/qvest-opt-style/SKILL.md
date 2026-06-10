---
name: qvest-opt-style
description: optimizer-research 전용 QEPM 리서치 스타일 — Direct Portfolio Learning + Implementation Discipline. research_philosophy ④⑥ operationalize. weight 결정 시 적용.
---

# Optimizer Research Style (research_philosophy ④⑥)

**SOT**: `02_Infrastructure/docs/qvest_research_philosophy.md`. 위반 = AX-002 동급.

## ④ Direct Portfolio Learning — Integration > Two-stage (Phase 3 후보)
- features → weights 직접 학습 경로 검토(You-Zhang 2025). 단 현 단계는 α̂+Σ 수신 two-stage 유지, direct는 실험 옵션.

## ⑥ Implementation Discipline (Hook 강제, 이미 정합)
- TO ≤ 11.0/yr (도훈 mandate 2026-05-29 완화) + LIQ ≥ 2e8 + max 25 + weights [0, 0.20] + Σw=1.
- net-of-cost(15bps) objective. `selection_objective = net_ir` (raw-Sharpe-max 금지 — Hook).

## ⚠️ Cycle 2 교훈 (의무 인지)
- **1/N(EW) out-of-sample 우위** (DeMiguel-Garlappi-Uppal 2009): 20-name broad alpha에선 MVO/HRP/ERC/CVaR concentration이 net SR을 **오히려 떨어뜨림**. sizing이 SR 보강했는지 **EW baseline 대비 정량 비교 의무** — 개선 없으면 정직 보고(과장 금지).
- alpha의 edge는 name **selection**(bandbuffer)이지 **sizing**이 아닐 수 있음 — Grinold breadth.
- turnover hard cap 위반 method는 IR 높아도 **disqualify**(silent relaxation 금지). CVaR 등 solver 미설치 시 fallback 명시.

## 출력 의무 (optimization_package)
비교 method ≥3 + 선택 근거 + net-of-cost SR(선택 vs EW) + turnover(≤11 확인, 도훈 mandate 2026-05-29) + RF-O1~7 + RF-R1 대응(전후 exposure) + Σw=1/[0,0.20]/max25 확인 + schedule density(≥0.95).

## 경계
weights만. alpha 재해석 / Σ 재정의 절대 금지 (Hook 차단).
