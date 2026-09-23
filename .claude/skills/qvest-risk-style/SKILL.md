---
name: qvest-risk-style
description: risk-research 전용 QEPM 리서치 스타일 — Risk Model 고도화(Σ + Crowding + Concentration). research_philosophy ⑤ operationalize. 공동위험 진단 시 적용.
---

# Risk Research Style (research_philosophy ⑤)

**SOT**: `02_Infrastructure/docs/qvest_research_philosophy.md`. 위반 = AX-002 동급.

## ⑤ Risk Model 고도화 — Σ + Crowding + Concentration
- `crowding_score_per_factor` 필수 (Acadian 2026). risk_crowding_score_check hook 강제.
- Concentration: sector HHI + n_effective + per-factor variance share.
- Σ = BΩB' + D: **conditioning 점검 의무** — cond number 보고 + ill-conditioned(예 cond>200) 시 shrinkage(Ledoit-Wolf/eigen-floor)로 개선, PSD 검증.
- Tail: empirical + EVT-GPD (VaR/ES 5%·1%) + Hill α.
- Stress: GFC/EuDebt/China2015/COVID/RateHike2022/KR_Bear. **book coverage <85% 구간은 UNRELIABLE 명시**(부분 상장 아티팩트 hard-fail 금지).

## ⚠️ Cycle 2 교훈
- vol-centric alpha(idio-vol/realized-vol 신호)는 **crowding/idio-vol tilt 반드시 점검** → Forge 재측정 권고 · 방어형 판정이면 AX-001 v3 계약 defensive_score 병기(구 v2 crisis IC 축은 `AX-001.json::history` 사료).
- as_of 단일 cross-section beta(예 1.09)는 아티팩트일 수 있음 — **walk-forward mean beta**로 판정(0.93). single-snapshot로 RF-R1 과대평가 금지.

## 출력 의무 (risk_package)
Σ 추정기 + cond(before/after shrinkage) + factor/specific variance share + EVT tail + stress(coverage 표시) + crowding_score_per_factor + style/sector HHI + RF-R1~5.

## 경계
Σ + 리스크 진단만. alpha_vector 재해석 / weight 결정 / 사전 MVO 절대 금지 (Hook 차단). RF-R1 등 exposure bound는 optimizer scope로 위임(측정·권고만).
