---
name: qvest-opt-style
description: optimizer-research 전용 QEPM 리서치 스타일 — Direct Portfolio Learning + Implementation Discipline. research_philosophy ④⑥ operationalize. weight 결정 시 적용.
---

# Optimizer Research Style (research_philosophy ④⑥)

**SOT**: `02_Infrastructure/docs/qvest_research_philosophy.md`. 위반 = AX-002 동급.

## ④ 피처 보존 원칙 (DPL — G-5 2026-08-24 settled-negative 선언 **철회**)
- DPL(features→weights 직접 학습)의 2026-06-26 실측(8config+GPU SR 0.75~0.89)은 **config-scoped 사실 기록**이며 **착수 금지 근거가 아니다**(measurement-graduation.md §5 G-5 · AX-000). 재도전 자격 게이트는 동일: `verify_adapter` · sweep 판별+DSR · PIT C1~C15 · 근거 논문 원문 링크. 선례 조회 = `hypothesis_index.R lookup dpl`.
- 실패 standalone 알파의 신호는 폐기 아닌 **피처로 보존**(원칙 유지). 현행은 α̂+Σ 수신 two-stage 확정.

## ⑥ Implementation Discipline (Hook 강제, 이미 정합)
- TO ≤ 11.0/yr (도훈 mandate 2026-05-29 완화) + LIQ ≥ 2e8 + max 25 + Σw=1 (v10: 비중 상한 폐지).
- net-of-cost(15bps) objective. `selection_objective = net_ir` (raw-Sharpe-max 금지 — Hook).

## ⚠️ Cycle 2 교훈 (의무 인지)
- **1/N(EW) out-of-sample 우위** (DeMiguel-Garlappi-Uppal 2009): 20-name broad alpha에선 MVO/HRP/ERC/CVaR concentration이 net SR을 **오히려 떨어뜨림**. sizing이 SR 보강했는지 **EW baseline 대비 정량 비교 의무** — 개선 없으면 정직 보고(과장 금지).
- alpha의 edge는 name **selection**(bandbuffer)이지 **sizing**이 아닐 수 있음 — Grinold breadth.
- turnover hard cap 위반 method는 IR 높아도 **disqualify**(silent relaxation 금지). CVaR 등 solver 미설치 시 fallback 명시.

## 출력 의무 (optimization_package)
비교 method ≥3 + 선택 근거 + net-of-cost SR(선택 vs EW) + turnover(≤11 확인, 도훈 mandate 2026-05-29) + RF-O1~7 + RF-R1 대응(전후 exposure) + Σw=1/max25 확인(v10: 비중 상한 폐지) + schedule density(≥0.95).

## 경계
weights만. alpha 재해석 / Σ 재정의 절대 금지 (Hook 차단).
