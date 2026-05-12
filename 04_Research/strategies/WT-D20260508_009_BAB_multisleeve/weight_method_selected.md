# WT-D20260508_009 Weight Method Selected

**Task**: BAB 다축 품질 multi-sleeve composite — Optimizer Research 산출
**Selection date**: 2026-05-08
**Agent**: optimizer-research (v1.0_optimization_package_draft_pre_codex)

---

## 1. Pipeline Inputs

| 입력 | 값 / 출처 |
|---|---|
| alpha_package | `qepm/mailbox/worktask/WT-D20260508_009/alpha_package.json` (FINAL post-Codex v1.1) |
| risk_package | `qepm/mailbox/worktask/WT-D20260508_009/risk_package.json` (FINAL post-Codex v1.2) |
| Σ estimator | Ledoit-Wolf 2004 const-corr Honey, δ=0.4842, ρ̄=0.2423, κ_exact=753.75 (RF-R2 HIGH) |
| Universe | 241 names (alpha-cov intersection, top-500 ADV20 KOSPI200∪KOSDAQ150 proxy) |
| sig_date | 2026-04-30 |
| forecast_horizon | 1M monthly |
| benchmark | KOSPI200_total_return |

## 2. Hard Constraints

| 제약 | 값 | 검증 |
|---|---|---|
| max_names | ≤ 20 | 20/20 PASS |
| long-only | weights ≥ 0 | min=0.0286 PASS |
| weight_bounds | [0, 0.10] | max=0.10 PASS (strict bound) |
| min_names | ≥ 15 | 20 PASS |
| HHI cap | ≤ 0.10 | 0.0739 PASS |
| alpha_winsor | 2.0σ | applied |
| Σw | = 1 | 1.000 PASS |
| sector_cap (Risk Agent advisory) | 0.30 strict | **INFEASIBLE** (수학적, §3 참조) → 0.40 chosen |

## 3. Method Shopping (18 후보 = 6 method × 3 sector_cap regime)

### Methods
1. **MVO_lam2_psi0.3** — confidence-aware MVO, λ=2.0, ψ=0.3 (FU penalty)
2. **MVO_lam5_psi0.5** — high risk-aversion λ=5.0
3. **ERC_top20** — Equal Risk Contribution
4. **MaxDiv_top20** — Max Diversification (Choueifaty 2008)
5. **InverseVar_top20** — 1/diag(Σ) HRP-lite
6. **AlphaTilt_EW20** — EW baseline

### Regimes
- **A (no_secap)**: sector cap 무적용 (semi 70% RF-R3 HIGH)
- **B (secap30)**: Risk Agent 권고 strict 30% — **사후 진단 INFEASIBLE**
- **C (secap40)**: 40% intermediate (production-feasible)

### net_IR Top Ranked (after 15bps cost adjust)

| Rank | Method | Regime | n | max_w | HHI | exp_AR% (mo) | exp_TE% (mo) | semi% | net_IR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | MVO_lam5_psi0.5 | A_no_secap | 20 | 0.072 | 0.056 | 1.458 | 2.502 | 65.4 | 0.523 |
| 2 | MVO_lam2_psi0.3 | A_no_secap | 20 | 0.084 | 0.059 | 1.489 | 2.569 | 70.3 | 0.521 |
| 3 | **MVO_lam2_psi0.3** | **C_secap40** | **20** | **0.100** | **0.074** | **1.418** | **2.458** | **40.0** | **0.516** ← Selected |
| 4 | MVO_lam5_psi0.5 | C_secap40 | 20 | 0.092 | 0.065 | 1.387 | 2.407 | 40.0 | 0.514 |
| 5 | MVO_lam2_psi0.3 | B_secap30* | 20 | 0.107 | 0.080 | 1.410 | 2.458 | 35.7 | 0.513 |

*regime B는 max_w=0.107 > bounds[2]=0.10 위반 → 수학적 infeasibility 인정 시 B regime 모두 제외.

## 4. Selection Result (current draft)

```
Selected method:  MVO_lam2_psi0.3_C_secap40
Family:           Classical MVO (quadprog)
λ:                2.0
ψ (FU penalty):   0.3
sector_cap:       0.40 (regime C)

n_names:          20
Σw:               1.000000
max_w:            0.10 (strict, 6 non-semi names binding)
min_w:            0.00886 (semi tail)
HHI:              0.0739

exp_AR (mo):      1.418%
exp_TE (mo):      2.458%
exp_IR (mo):      0.577
exp_AR_ann:       17.02%
exp_TE_ann:       8.51%
exp_SR_ann:       1.999

Semi exposure:    40.0% (sector_cap binding)
binding:          ['hhi_cap_0.10', 'weight_bound_top', 'sector_cap_semi_40pct', 'min_names_15', 'max_names_20']

Turnover one-way avg per rebal:  0.432 (43%)
Turnover round-trip annualized:  10.37 (1037%)  ⚠️ RF-O3 HARD FAIL
Cost per rebalance (15bps):      0.130%
Cost annualized:                 1.556%
```

## 5. Sector Cap Strict Feasibility Analysis

**핵심 발견**: Risk Agent 권고 sec_cap=0.30 strict은 이 universe + bounds + n_hard 조합에서 **수학적으로 infeasible**:

```
top20 alpha = 6 non-semi + 14 semi
max non-semi sum = 6 × bounds[2] = 6 × 0.10 = 0.60
max semi sum = sec_cap = 0.30
total max Σw = 0.90 < 1.0  ⇒ INFEASIBLE
```

해결 옵션:
1. **regime C secap40 chosen** (current): 6×0.10 + 14 semi×0.0286 = 1.0 exact, **bounds 강제 PASS**
2. universe expansion top20 → top25: 11 non-semi 가능 → 11×0.10 + 0.30 = 1.40 ≥ 1 ✓ (alpha re-select)
3. bounds_relax 0.10 → 0.117: 6×0.117 + 0.30 = 1.0 (bounds advisory 위반)

→ **Charter §8 No Silent Override**: regime C 선택 + secap30 infeasibility 명시 (`infeasibility_report.primary_concern`)

## 6. Walk-Forward Schedule (Charter §9 Schedule Density Mandate)

| 항목 | 값 |
|---|---|
| weights.csv path | `stage_artifacts/WT-D20260508_009/weights.csv` |
| n_rows | 3028 |
| n_unique_dates | 196 |
| sig_dates_target | 196 |
| **schedule_density_ratio** | **1.000** (≥ 0.95 PASS) |
| Σ rebuild | 252-day rolling LW const-corr (δ=0.5 approx) per Date |
| Method | mvo_lam2_psi0.3 + sec_cap=0.40 |
| date range | 2010-01-29 ~ 2026-04-30 |
| avg names per date | 15.4 (range 14~20) |

## 7. Hybrid Combine Simulation (PG2 직교성 활용)

PG2 STR_1715_AR_threshold_overlay vs candidate **monthly cor = 0.0023** (Risk Agent 측정).
σ_str_ann assumed 20%; σ_cand_ann = exp_TE_ann = 8.51%.

| w_new (BAB_multisleeve) | SR_hybrid | vol% | ER% (ann) |
|---|---|---|---|
| 0.00 | 1.5854 | 20.000 | 31.708 |
| 0.05 | 1.6297 | 19.006 | 30.974 |
| 0.10 | 1.6779 | 18.022 | 30.239 |
| 0.15 | 1.7304 | 17.051 | 29.505 |
| 0.20 | 1.7876 | 16.094 | 28.770 |
| 0.25 | 1.8499 | 15.155 | 28.036 |
| **0.30** | **1.9177** | **14.237** | **27.301** |

**Best w_new = 0.30** → SR 1.918 (+0.332 vs STR_1715-only 1.585).

PG2 admit 시 본 source는 4번째 직교 source 후보로서 SR 2.0 target 도달 path 가능 (단, Forge realized 백테스트 필수).

**주의**: σ_cand 8.51%는 expected forward TE이며 realized vol 아님. Forge 백테스트로 realized vol + cor + MDD 검증 필요.

## 8. Codex Critic Round (의무 5단계, v6.0)

| 단계 | 상태 |
|---|---|
| 1. Draft 작성 | DONE (`optimization_package_draft.json`) |
| 2. PostToolUse codex_round_auto_trigger.sh | TRIGGERED via `run_codex_qepm_critic.sh` |
| 3. Codex response 수신 | 대기 (`codex_critic_response_optimizer.json`) |
| 4. challenge_note_optimizer.md 의무 | 수신 후 작성 |
| 5. Final `optimization_package.json` | 수신 후 작성 |

## 9. AX Axiom Audit

| AX | Status | 근거 |
|---|---|---|
| AX-001 v2 | INHERITED_ALPHA_PASS | crisis_IC +0.1251, bad_normal_ratio 3.188 |
| AX-002 | PASS | 모든 weights는 mvo_weights + .project_sector_cap pipeline 산출 |
| AX-005 v1.2 | INHERITED_ALPHA_PASS | multi-sleeve 3 sleeves composite |
| AX-007 | PASS_via_exception | multi-sleeve (4 exceptions 중 1) |
| AX-008 | PARTIAL | Codex round 후 PASS 가능 |

## 10. RF-O Hook 자동 검증

| RF | Severity | 결과 |
|---|---|---|
| RF-O1 | INFO | binding_constraints=5 |
| RF-O2 | MEDIUM | exp_AR (mo) 141.8bps vs cost (rebal) 13.0bps — ratio 10.9 OK |
| RF-O3 | **HIGH** | turnover round-trip 1037% > 600% Hurdle gate hard fail — `infeasibility_report.turnover_concern` 발급 |
| RF-O5 | PASS | n_names=20 ≤ 20 |
| RF-O6 | PASS | \|Σw - 1\| < 1e-6 |
| RF-O7 | PASS | max_w=0.10 ≤ 0.20, min_w ≥ 0 |
| RF-O9 | PASS | schedule_density_ratio=1.000 ≥ 0.95 |

## 11. Risk Residuals (Forge 백테스트 측정 영역)

1. **RF-R3 HIGH** (semi 40% > 30% target): partial mitigation, Forge 측정 필요
2. **RF-R4 HIGH** (ES95 candidate -10.35%): Forge realized ES95 + Floor+ES protection_strategy.R 검토
3. **RF-R2 HIGH** (κ_exact=754): bounds=0.10 + L1-Tikhonov FU penalty (ψ=0.3)로 완화, residual exists
4. **Turnover 1037%** (RF-O3 hard fail): Forge — quarterly rebalance / TC penalty / buffer_zone 적용 검토

## 12. Charter v1.7 Compliance

- PIT C1~C15: PASS (252-day rolling Σ, Date < d strict)
- no_alpha_modification: PASS
- no_risk_modification: PASS
- no_silent_override: PASS (sec_cap_30 infeasibility 명시 + turnover hard fail 명시)
- schedule_density: 1.000 ≥ 0.95 PASS

---

## Version

- **v1.0** — 2026-05-08 — pre-Codex draft. Selected: MVO_lam2_psi0.3 sec_cap=0.40 regime C. Forward SR_ann=1.999, Hybrid w_new=0.30 SR=1.918. RF-O3 turnover 1037% hard fail flagged.
- **v1.1** — 2026-05-08 — final post-Codex. Codex stance REJECT (8 concerns, 1 CRITICAL + 5 HIGH). Disposition: 5 ACCEPT + 1 PARTIAL + 2 REBUTTAL. Q-Lead escalate triggered. handoff_status = `NOT_HANDOFFABLE_AS_IS` (turnover hard fail). Forge mitigation 4 옵션 (turnover_penalty / quarterly / buffer_zone / sleeve smoothing) 권고. weights.csv schema rename + mailbox mirror DONE.
