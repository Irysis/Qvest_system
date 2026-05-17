# DPL_KR_v3 — 7-Axis Admission Protocol

**WT-D20260519_001 · alpha-research Step 2.5**
**Date**: 2026-05-18
**Author**: alpha-research agent (autonomous)
**Lineage**: request.json §decision_gates_7_axis_v3_v5_learning + v1/v2/v5 cycle learning + Charter §10 Role Card discovery + Hurdle Gate v2.2

---

## 1. Decision Gates Definition (G0~G7)

### 1.1 G0 — PIT C1~C15 Strict

**Threshold**: All C1~C15 PASS (lookahead_detector.R scan = PASS_NO_LOOKAHEAD)

**Measurement** (Forge cycle):
```bash
Rscript 02_Infrastructure/validation/lookahead_detector.R \
    --target=WT-D20260519_001
```

**Pass criteria**:
- All C1~C15 PASS or PASS_WITH_STRUCTURAL_CAVEATS (with caveat enumeration)
- HARD_ABORT_NOT_TRIGGERED

**Failure** → HARD ABORT

**v1 inherit**: PASS_WITH_STRUCTURAL_CAVEATS (24m warm-up + macro drop + 5e7/2e8 2-stage mitigation). v3 adds rawdata.parquet SHA256 binding + self_synthesis_used audit.

---

### 1.2 G1 — SR Floor

**Threshold**: DPL_v3 SR ≥ 1.0 (52 test months PerformanceAnalytics standard)

**Measurement** (Forge cycle):
```r
library(PerformanceAnalytics)
test_returns <- ...  # 52 months from bt_result$period_returns
SR_annual <- SharpeRatio.annualized(test_returns, Rf=0, scale=12)
```

**Pass criteria**:
- Per-window median SR ≥ 1.0
- Worst-window SR ≥ 0.5 (sub-period stability proxy)

**Failure modes**:
- SR < 1.0 median → G1 FAIL
- SR < 0 any window → ABORT per request.json failure_cutoff `SR_lt_0`
- Subperiod drift > 30% → CF-A3 flag

**Rationale**: v1 -0.34 (random), v3 target ≥ 1.0 (paradigm-meaningful)

---

### 1.3 G2 — Correlation vs STR_1715

**Threshold**: 
- |cor| < 0.5 → **substitution sleeve candidate** (replaces STR_1715 in book_state)
- |cor| < 0.3 → **4th orthogonal source candidate** (joins STR_1715 + TSMOM + KR_10y? — to be decided by Governor)

**Measurement** (Forge cycle):
```r
# Same-harness PerformanceAnalytics geometric convention
alpha_v3 <- read_parquet("WT-D20260519_001/alpha_scores.parquet")
alpha_str1715 <- read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
# Inner join on (sig_date, Ticker)
merged <- inner_join(alpha_v3, alpha_str1715, by=c("sig_date", "Ticker"))
cor_per_sigdate <- merged %>% group_by(sig_date) %>% summarize(cor=cor(alpha_score.x, alpha_score.y, method="pearson"))
mean_cor <- mean(cor_per_sigdate$cor)
```

**Pass criteria**:
- Mean cor per sig_date < 0.5 (substitution)
- Mean cor per sig_date < 0.3 (4th source)

**Failure**:
- |cor| > 0.7 → DEFER per request.json `cor_vs_str1715_gt_0.7`

**Rationale**: 
- L-326 STR_1715 baseline robust (84m SR 2.0054 ≈ 255m SR 1.9536) → substitution difficult
- Orthogonal (cor < 0.3) more feasible target

---

### 1.4 G3 — Harvey-t 5-Spec

**Threshold**: t_NW ≥ 3.0 strict, 5-spec panel (CAPM/FF3/FF5/Carhart4/FF6)

**Measurement** (Forge cycle):
```r
library(sandwich)
library(lmtest)
specs <- list(
  CAPM = lm(r_p ~ MKT, data=...),
  FF3 = lm(r_p ~ MKT + SMB + HML, data=...),
  FF5 = lm(r_p ~ MKT + SMB + HML + RMW + CMA, data=...),
  Carhart4 = lm(r_p ~ MKT + SMB + HML + UMD, data=...),
  FF6 = lm(r_p ~ MKT + SMB + HML + RMW + CMA + UMD, data=...)
)
for (spec in specs) {
  nw_se <- NeweyWest(spec, lag=12)
  coef_test <- coeftest(spec, vcov=nw_se)
  t_alpha_NW <- coef_test["alpha", "t value"]
  ...
}
```

**Pass criteria** (Harvey-Liu-Zhu 2016 strict):
- ≥ 3 specs with t_NW ≥ 3.0 (genuine)
- All 5 specs documented with genuine/placeholder labels (v5 C2 lesson)

**v5 lesson**: FF5/FF6 may be **structural duplicates** of FF3/Carhart4 if no RMW/CMA data in rawdata.parquet. Report genuine count separately. If genuine ≥ 3 (CAPM + FF3 + Carhart4), G3 PASS.

**Failure**: genuine count < 3 → G3 FAIL

---

### 1.5 G4 — DSR Bailey-LdP Strict

**Threshold**: Bailey-LdP Deflated Sharpe Ratio Z ≥ 1.5 strict, n_trials=100

**Measurement** (Forge cycle):
```r
# Bailey-LdP 2014 formula
N <- 100  # 20 random search × 5 walk-forward windows
n <- 52   # test months
skew <- skewness(test_returns)
kurt <- kurtosis(test_returns)
SR_max_expected <- (1 - gamma_em) * qnorm(1 - 1/N) + gamma_em * qnorm(1 - 1/(N*e))
SR_std_expected <- sqrt((1 - skew*SR_max + (kurt - 1)/4 * SR_max^2) / (n - 1))
DSR_Z <- (SR - SR_max_expected) / SR_std_expected
```

**Pass criteria**:
- DSR_Z ≥ 1.5 strict (v5 5.63 STRONG precedent for STR_1715; v3 target conservative)

**v5 inherit**: n_trials=100 strict (20 random × 5 windows = 100)

**Failure**: DSR_Z < 1.5 → G4 FAIL (data dredging risk)

---

### 1.6 G5 — Cost Pareto vs STR_1715

**Threshold**: DPL_v3 net-of-cost (15bps × 2 round-trip) Pareto-undominated vs STR_1715

**Measurement** (Forge cycle):
```r
# Same-period overlap (52 test months)
dpl_v3_net <- dpl_v3_gross - 0.0015 * 2 * to_per_month  # 2× round-trip
str1715_net <- str1715_gross - 0.0015 * 2 * to_str1715_per_month

# Pareto frontier: (SR_net, MDD_net)
pareto_dominate <- dpl_v3_net_SR >= str1715_net_SR AND dpl_v3_net_MDD >= str1715_net_MDD
                   AND (dpl_v3_net_SR > str1715_net_SR OR dpl_v3_net_MDD > str1715_net_MDD)
```

**Pass criteria**:
- Pareto undominated OR strict Pareto-dominate STR_1715
- If only undominated, requires G2 cor < 0.3 (4th source) — different objective space

**Rationale**: Net-of-cost prevents dominant TO inflation

---

### 1.7 G6 — AX-008 Verification Triangulation

**Threshold**: ≥ 2 of 3 PASS (Forge + Codex + Architect)

**Forge**: forge_package.json + all 8-field schema + bt_result.rds sha256 binding + self_synthesis_used=false

**Codex**: codex_critic_response_forge.json stance ∈ {APPROVE, APPROVE_CONDITIONAL} OR REVISE with all concerns disposed

**Architect**: architect_audit.json `decision_outcome ∈ {PASS, PARTIAL_PASS}` + independent reproduction within 4-decimal precision

**Pass criteria**: ≥ 2/3 PASS (AX-008 hard mandate)

**Failure**: 0/3 or 1/3 → DEFER per request.json failure_cutoff `Codex_REJECT_veto_true`

---

### 1.8 G7 — EW Non-Collapse Strict (v1 EW Collapse Direct Avoidance)

**Threshold**: HHI > 0.06 strict majority sig_dates (≥ 90% of 52 test months)

**Measurement** (Forge cycle):
```r
# Per sig_date HHI
weights_df <- read_csv("WT-D20260519_001/weights.csv")
hhi_per_sig <- weights_df %>% group_by(sig_date) %>% summarize(hhi=sum(weight^2))
n_above_threshold <- sum(hhi_per_sig$hhi > 0.06)
hhi_pct_above <- n_above_threshold / nrow(hhi_per_sig)
```

**Pass criteria**:
- ≥ 90% sig_dates HHI > 0.06
- Mean HHI > 0.07 (1 SD margin over 0.06)
- Min HHI > 0.055 (close to 0.05 EW floor allowed only in rare sig_dates)

**v1 inherit failure**: HHI = 0.05 uniform 100% (51/51 sig_dates) → HARD ABORT precedent

**Rationale**: 
- EW (K=20 equal weights): HHI = 1/K = 0.05
- v3 concentration penalty target HHI ≥ 0.10 (5× EW floor)
- G7 threshold 0.06 conservative (1.2× EW, sufficient to prove differentiation)

**Failure**: HHI ≤ 0.06 majority sig_dates → HARD ABORT per request.json failure_cutoff `ew_collapse_HHI_0_05`

---

## 2. Admission Outcomes Matrix

| G0 | G1 | G2 | G3 | G4 | G5 | G6 | G7 | Outcome |
|---|---|---|---|---|---|---|---|---|
| PASS | PASS | < 0.5 | PASS | PASS | PASS | ≥ 2/3 | PASS | **substitution sleeve candidate** |
| PASS | PASS | < 0.3 | PASS | PASS | PASS | ≥ 2/3 | PASS | **4th orthogonal source candidate** |
| PASS | < 1.0 | any | any | any | any | any | any | DEFER (G1 fail) |
| PASS | PASS | > 0.7 | any | any | any | any | any | DEFER (G2 cor too high) |
| PASS | PASS | any | < 3.0 | any | any | any | any | DEFER (G3 fail) |
| PASS | PASS | any | any | < 1.5 | any | any | any | DEFER (G4 DSR fail) |
| PASS | PASS | any | any | any | dominated | any | any | DEFER (G5 cost Pareto fail) |
| PASS | any | any | any | any | any | < 2/3 | any | DEFER (G6 AX-008 fail) |
| PASS | any | any | any | any | any | any | < 0.06 | **HARD ABORT (G7 EW collapse)** |
| FAIL | any | any | any | any | any | any | any | **HARD ABORT (G0 PIT fail)** |

---

## 3. Hard Abort Conditions (request.json failure_cutoffs_v1_v5_strict)

| Condition | Action | Inherit Lesson |
|---|---|---|
| HHI ≤ 0.05 (EW collapse) | HARD ABORT | v1 L-328 |
| Synthetic detection (Codex) | HARD ABORT | v4 lesson |
| TO > 6.0 annual | HARD ABORT | v1 17.64 lesson |
| SR < 0 | ABORT | v1 -0.34 + v5 zero alpha |
| Codex REJECT veto=true | DEFER | request.json |

---

## 4. v1~v5 Cycle Comparison

| Gate | v1 result | v2 result | v3 (target) | v5 (target) |
|---|---|---|---|---|
| G0 PIT | PASS_WITH_CAVEATS | PASS | PASS | PASS |
| G1 SR | -0.34 (FAIL) | DEFER | ≥ 1.0 | DEFER (zero) |
| G2 cor | EW collapse (N/A) | DEFER | < 0.3 / < 0.5 | high cor (RC) |
| G3 Harvey-t | -0.42 (FAIL) | DEFER | ≥ 3.0 5-spec | partial (3 genuine) |
| G4 DSR | -2.27 (FAIL) | DEFER | ≥ 1.5 | partial |
| G5 cost Pareto | dominated (FAIL) | DEFER | undominated | dominated |
| G6 AX-008 | 0/3 | 1/3 | ≥ 2/3 | DEFER |
| G7 HHI | 0.05 (HARD ABORT) | DEFER | > 0.06 | DEFER |

**v3 paradigm distinction**: Original DPL (NOT RC) → cor < 0.3 achievable via standalone alpha, not architecturally cor=1.0 (v3-v5 RC inherent limitation)

---

## 5. Codex Round Mandate (per request.json codex_round_mandate=true)

### 5.1 Pre-Forge: alpha_package_draft.json Codex Round

**Spawn command**:
```bash
bash 02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh \
    --role=alpha \
    --task_id=WT-D20260519_001 \
    --package=qepm/mailbox/worktask/WT-D20260519_001/alpha_package_draft.json \
    --output=qepm/mailbox/worktask/WT-D20260519_001/codex_critic_response_alpha.json
```

**Expected duration**: ~9-15 min (GPT-5.5 xhigh)

**Stance handling**:
- APPROVE / APPROVE_CONDITIONAL → finalize alpha_package.json
- REVISE → 9 concerns disposition (ACCEPT / PARTIAL / REBUTTAL) in challenge_note → revise alpha_package.json
- REJECT → similar disposition; veto=false 시 finalize possible w/ explicit rebuttal

### 5.2 Post-Forge: forge_package_draft.json Codex Round (Forge cycle responsibility)

### 5.3 Post-Risk / Post-Optimizer: per-agent Codex Round

### 5.4 Self-Rationalization Auto-Detection

Search alpha_package.json + challenge_note.md for:
- "미미", "관행적", "실무적", "보수적이면 OK", "대부분 결과 동일", "이미 반영되어 있었을 것"
- Hit → auto RE-VIEW + REBUTTAL 강화

---

## 6. Charter §10 Role Card Discovery — Discovery_Design_Phase_A

v1/v2 inherit Charter §10 amendment proposal:

> **Role Card `discovery_design_phase_a`**:
> - **Expected Output**: architecture spec + PIT audit + training protocol + admission protocol + literature review + alpha_package_draft.json
> - **Deferred to Forge cycle**: trained metrics (rank_ic, ICIR, Harvey-t, DSR, monotonicity, weights.csv, alpha_scores.parquet, ic_history.parquet)
> - **Cert eligibility**: alpha_discovery_certificate via `alpha_discovery_certifier.sh` may pass if cor inherit pointer to v2 inherits + Forge cycle promise documented

**Status**: alpha-research Step 2.5 emit complete. Forge cycle obligation enumerated.

---

## 7. Q-Lead Notification on Codex Outcome

After Codex Round:
- HIGH severity concerns ≥ 5 → Q-Lead escalate
- AX axiom hard FAIL ≥ 3 → Q-Lead escalate
- PIT C1 violation found → IMMEDIATE Q-Lead escalate

**v1 inherit**: Q-Lead escalate triggered (Codex 9 concerns, 8 HIGH + 1 MED, REJECT veto=false). v3 expected similar caveats (architecture-only spec stage, all measurements deferred to Forge).

---

## 8. Production Promotion Eligibility (Future)

If G0~G7 ALL PASS + AX-008 ≥ 2/3:
- **Substitution sleeve**: replace STR_1715_AR_on_M4_R05_overlay_PG2 in book_state
- **4th orthogonal source**: append to multi-sleeve admit (with Governor decision on book_weights)

Promotion subject to **Governor cycle** decision.

---

**End of Admission Protocol v3**

Lineage: request.json §decision_gates_7_axis_v3_v5_learning + v1/v2/v5 cycle decision gates inherit + Charter v1.7 §10 Role Card discovery + Hurdle Gate v2.2 + 도훈 mandate 2026-05-18.
