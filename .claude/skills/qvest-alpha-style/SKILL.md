---
name: qvest-alpha-style
description: alpha-research 전용 QEPM 리서치 스타일 — Factor Zoo 축소 / Cost-aware alpha / Uncertainty-aware forecasting. research_philosophy 7-trend의 alpha 역할 operationalize. alpha 산출 시 적용.
---

# Alpha Research Style (research_philosophy ①②③)

**SOT**: `02_Infrastructure/docs/qvest_research_philosophy.md`. 위반 = AX-002 동급.

## ① Factor Zoo 축소 — Validation > Discovery
- 신규 factor마다 `economic_rationale`(왜 작동하는가, 메커니즘) + `redundancy_cluster_id`(기존 factor와 중복 cluster) 의무.
- "발굴"보다 "기존 factor 검증·정제" 우선. 무근거 factor 추가 금지.

## ② Cost-aware Alpha — Net > Gross
- ML loss에 turnover penalty 통합: `-E[ret] + γ·|Δw|` (Jensen-Kelly-Malamud-Pedersen 2022).
- 모든 SR/IC는 **net-of-cost(15bps)** 로 보고. gross만 보고 금지.

## ③ Uncertainty-aware — CI > Point Estimate
- 예측은 점추정 아닌 하한: `μ̃ = μ̂ − k·SE(μ̂)` (Liao 2025 RFS).
- harvey-t는 **분포 3축 이상** (subperiod stability).

## ⚠️ Cycle 2 검증 교훈 (2026-05-29, 의무 인지)
- **IC t-stat ≠ portfolio-alpha t-stat**. rank-IC harvey_t가 높아도(예 4.31) 실제 portfolio alpha 회귀 t는 다를 수 있음(2.31). **alpha_package에 둘을 명시 구분 보고** — Judge는 portfolio-alpha t(forge 5-spec)를 authoritative로 채택.
- **단일-alpha는 DSR 천장**(net SR ~0.3, DSR<0.5 binding). SR 2.5 목표는 단일 신호로 불가 → multi-sleeve/이종 ensemble 전제.
- feature pruning trade-off: 30f vs 162f — in-sample IC만 보지 말고 net-of-cost SR + turnover + AX-001 v2로 결정(162f가 IC 높아도 turnover/AX-001 fail 가능).

## 출력 의무 (alpha_package)
IC + ICIR + harvey-t(rank-IC) + **portfolio-alpha t 별도** + net-of-cost SR + turnover + DSR + AX-001 v2 ratio + economic_rationale + redundancy_cluster_id + cor vs 기존 admitted(<0.95).

## 경계
α̂만. Σ/weight/사전 최적화 절대 금지 (agent_role_guard Hook 차단).
