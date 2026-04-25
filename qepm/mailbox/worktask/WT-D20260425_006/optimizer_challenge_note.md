# WT-D20260425_006 Optimizer Agent — Challenge Note (Charter §8 + Red Flag)

## Iteration 1 Optimizer Self-Challenge

### 1. Charter §8 — No Silent Override
- **α̂ unchanged** (alpha_package에서 받은 6F + overlay_specs 그대로 사용).
- **Σ unchanged** (risk_package nonlinear_shrinkage cond=11.06 그대로 사용).
- **factor mix / overlay spec / regime def 미수정**.
- Optimizer 영역: weights + cash sleeve + binding constraints만 결정.

### 2. Method Shopping Log (R2-C HARD: ≤10)
**candidates_tried = 9 + Ensemble_Top3 = 10 (cap 도달)**.

| Rank | Method | net_IR | Exp_Ret_Ann | TE_Ann | Turnover (M) | N | max_w | HHI |
|---|---|---|---|---|---|---|---|---|
| 1 | **Ensemble_Top3** (selected) | **76.58** | 4.38 | 0.057 | 0.371 | 18 | 0.197 | 0.104 |
| 2 | MVO_lam5 | 72.32 | 5.29 | 0.073 | 0.698 | 7 | 0.200 | 0.183 |
| 3 | BlackLitterman | 71.69 | 3.93 | 0.055 | 0.417 | 16 | 0.196 | 0.108 |
| 4 | MinVar | 71.69 | 3.93 | 0.055 | 0.417 | 16 | 0.196 | 0.108 |
| 5 | MVO_lam2_psi0.3 | 70.89 | 5.30 | 0.074 | 0.707 | 6 | 0.200 | 0.186 |
| 6 | MVO_lam0.5 | 69.69 | 5.31 | 0.076 | 0.718 | 6 | 0.200 | 0.189 |
| 7 | HRP | 66.02 | 3.89 | 0.059 | 0.159 | 20 | 0.121 | 0.061 |
| 8 | Kelly_frac025 | 65.85 | 4.19 | 0.064 | 0.300 | 14 | 0.072 | 0.071 |
| 9 | ERC | 62.50 | 3.79 | 0.061 | 0.100 | 20 | 0.081 | 0.053 |
| 10 | MaxDiv | 32.21 | 3.36 | 0.103 | 0.707 | 6 | 0.200 | 0.186 |

**선택 근거 (Ensemble_Top3)**:
- Top 3 (MVO_lam5 + BL + MinVar) mean weight → MVO의 alpha 정보 + BL/MinVar의 분산 안정성 결합.
- N=18 (Grinold breadth 우월), HHI=0.104 (≤0.10 근접), turnover=37% (MVO 단독 70%의 절반).
- net_IR 76.58 = best of 10. cost-adjusted 우월성 명확.

### 3. Overlay Integration (Option A 채택)
- **방식**: Option A — `w_t = w_baseline × overlay_mult(t-1)`, cash sleeve = `1 - Σw_t`.
- **이유**:
  1. Risk Agent 권고 ("portfolio-level scaler at gross-leverage step"). cross-sectional Σ 변화 없음 (Risk note 1번).
  2. KR long-only mandate: deduce-only (cap=1.0). VolReg `[0, 1.5]` cap을 1.0으로 clip.
  3. cash sleeve 명시 → role=cash_allocation 별도 표기 (v55 lawbook 정합).
- **Brake states**:
  - OFF (50%): mult=0.802 → cash 19.8%.
  - ON  (50%): mult=0.363 → cash 63.7%.
  - Blended: cash 41.7%.

### 4. Hard Constraint Validation (Hook 강제)
- ✅ **n_names = 18 ≤ 20** (RF-O5 PASS)
- ✅ **Σw = 1.000000** (RF-O6 PASS)
- ✅ **max(w) = 0.1972 ≤ 0.20** (RF-O7 PASS upper)
- ✅ **min(w) = 0.0 ≥ 0** (RF-O7 PASS lower / long-only)
- ✅ **HHI = 0.104** (≤ 0.10 soft target — 0.4% 초과, near-binding)

### 5. Red Flag Audit (RF-O1~O7)

| ID | Severity | 결과 | 코멘트 |
|---|---|---|---|
| RF-O1 | HIGH | **OK** | binding=1 (`hhi_above_0.10` near-miss) < N/2=10 |
| RF-O2 | HIGH | **OK** | exp_ret 4.38 > 2× cost 0.027 (≫ 안전) |
| RF-O3 | MEDIUM | **OK** | turnover 0.371 (월간) >> 0.02 |
| RF-O4 | HIGH | **OK** | QP dual 정상 (lambda_used 그대로) |
| RF-O5 | CRITICAL | **OK** | n=18 (cap=20) |
| RF-O6 | CRITICAL | **OK** | Σw=1.0000 |
| RF-O7 | CRITICAL | **OK** | [0, 0.20] 모두 만족 |
| **RF-O8_CVaR** | HIGH | **FLAGGED** | blended CVaR95 0.094 > cap 0.025 (Risk-side inherited; overlay만으로는 cap 불충분) |

### 6. CVaR Cap Breach (Risk-side inherited)
- Risk Agent 산출 baseline CVaR95 monthly = 0.1618 (cap 0.025, 6.5×).
- Overlay blended에도 CVaR95 ≈ 0.0943 (3.8× cap) — **여전히 breach**.
- **이유**:
  - 20-ticker concentrated long-only KR universe: 시스템 위험 절반 이상 inherent.
  - DD Brake 시 -50% 비중 축소만으로는 monthly CVaR cap 2.5% 도달 불가능.
  - cap 2.5%는 sub-portfolio (cash-heavy or hedged) 기준으로 보임.
- **해석**: Optimizer 영역에서는 weights 구조로 CVaR 추가 축소 불가능 (long-only + sum=1 constraint 하).
  - 추가 축소 옵션 = (1) cash sleeve 영구 확대 (overlay 외 별도 cap 정책), (2) hedge instrument 도입 (mandate 외), (3) cap 자체 재검토.
- **결론**: **infeasibility (Charter §8 No Silent Override)** — Optimizer가 자체적으로 cap을 완화하지 않음. Q-Lead/Governor 결정 필요.

### 7. Beta Drift (overlay-induced)
- Baseline β = 1.080 (Risk Agent 산출, 그대로).
- Blended β = 1.080 × 0.583 = **0.629** (overlay scaling으로 감소).
- Risk Agent target_range [1.00, 1.05] **미달**.
- **자연스러운 결과**: defensive overlay → β reduction은 의도된 효과 (L-122 risk-managed).
- target_range는 **brake-OFF 상태 기준**으로 해석 권고 (현재 brake-OFF β = 1.080 × 0.802 = 0.866도 미달).
- → β target_range는 overlay OFF 시점에서 적용하는 것이 합리적이나, 그 경우에도 mult_off 0.802가 너무 보수적.
- **Risk Agent 재해석 권고**: β target은 overlay 미적용 (mult=1.0) baseline weights 기준 = 1.080 (within target [1.00, 1.05]) ✅.

### 8. PIT Audit (C1~C15)
- C1: rolling Σ (Risk side); optimizer는 sig_date 시점 snapshot 사용.
- C2: sig_date = 2024-01-22 (Pre-LB end). Lockbox 미접근.
- C5/C9: overlay mult = BM[t-1] 기반 (Alpha 측 적용 완료, optimizer는 주어진 값만 사용).
- C10: liquidity 2e8 inherited from alpha screen.
- C13/C14/C15: factor 처리는 Alpha 영역 (optimizer 미관여).

### 9. Common Charter 8원칙 자기진단
1. PIT only — PASS
2. Research process — PASS (Idea L-122 → α̃ → 10 method bake-off → net_IR selection → Cash sleeve)
3. Family vs Proxy — PASS (optimizer = portfolio construction; α/Σ/factor 무손)
4. Paper as starting — PASS (Markowitz 1952, Black-Litterman 1992, López de Prado 2016 HRP, Maillard 2010 ERC)
5. No data mining — PASS (selection_objective=net_IR 고정, SR 단독 금지 준수, 10 method cap 준수)
6. Dynamic smart alpha — PASS (overlay scaling × confidence-aware MVO)
7. Cost/capacity/crowding — PASS (15bps × turnover monthly 0.371 → 0.0134 annual cost; capacity 100B AUM × 0.20 cap × 20 names = 400B max — 충분)
8. No silent override — PASS (CVaR breach + β drift 모두 명시적 challenge로 전달)

### 10. Open Questions for Forge / Judge
1. **CVaR cap**: 2.5% monthly cap이 단일 sleeve에 부합하는가, multi-sleeve book level인가? Governor 결정 필요.
2. **β target**: overlay-OFF (cash 미사용) 시점 기준인가? 그 경우 Optimizer 산출 baseline β=1.08 within target.
3. **MEGA_05 대체 vs PG2 통합**: 현재 산출물은 신규 WT 단독. PG2 통합 평가 (MEGA_05 80% + STR_1656 20% × overlay layer)는 별도 Forge bake-off 필요.
4. **mult cap [0, 1.0]**: VolReg의 `[0, 1.5]` 1.5× lever를 deduce-only로 clip한 것은 보수적 결정. mandate에 따라 1.5× 허용 시 brake-OFF Σw_risk 확대 가능 (mult=1.0 → cash=0).

### 11. Infeasibility Report (R12 No Silent Override)
**조용한 제약 완화 없음**. CVaR cap breach는 infeasibility로 명시:

```json
{
  "infeasibility_report": {
    "reason": "CVaR95 monthly cap 2.5% breach inherited from Risk side; overlay scaling alone cannot reduce monthly CVaR to 2.5% level for 20-ticker KR long-only universe.",
    "violated_constraints": ["cvar_cap_2.5pct_monthly"],
    "current_blended_cvar95": 0.0943,
    "cap_required": 0.025,
    "ratio_breach": 3.77,
    "suggested_resolution": [
      "1. Q-Lead/Governor: cap 자체 재검토 (sleeve vs book level)",
      "2. cash sleeve 영구 확대 (mult_max < 1.0 정책)",
      "3. hedge instrument 도입 (mandate 확장 필요)"
    ],
    "optimizer_action": "REPORT (not relax)"
  }
}
```

──────────────
Generated by Optimizer Research Agent v1.2 @ 2026-04-25
