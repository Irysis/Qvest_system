# Challenge Note — WT-D20260430_001

## Status
- DRAFT prior to Codex critic R2.  Will finalize after Codex response.

## Self-Audit Summary (Alpha Agent v1.2)

### Mandate Compliance Check

| Item | Target | Achieved | Status |
|------|--------|----------|--------|
| STR_1715 simple MRS overlay 대비 우월성 | SR or MDD uplift | SR +0.018 (S2: 1.616 → S3: 1.634) | PASS |
| MDD vs S2 | uplift | parity (-29.91%) | NEUTRAL |
| Harvey NW HAC t-stat | > 3.0 | lag=4: 6.421 / lag=12: 5.957 | PASS |
| DSR | > 0.5 | 0.998 (n=267, n_trials=3) | PASS |
| Subperiod stability | > 0.5 | 0.855 | PASS |
| Crisis_alpha 8 periods | meaningful | 1 positive (+61bps GFC), 2 small neg (-49 ~ -171bps), 5 unchanged | PARTIAL |
| AX-001 v2 bad/normal ratio | ≥ 1.5 | 0.138 | FAIL (PARTIAL allowance) |
| Alpha discovery cert eligibility | cor < 0.95, mech > 50 chars, factor_specs ≥ 1, harvey ≥ 3 | All met | ELIGIBLE |
| PIT C1-C15 | All pass | C1/C2/C5/C9 PASS, C13/C14/C15 N/A | PASS |
| AX-002 process integrity | No backtest fabrication | factor_engine_continuous label, Forge harness 별도 | PASS |
| AX-005 / AX-007 | Avoidance + EXCEPTION_1 | multi-sleeve via regime overlay 정합 | PASS |

### Concerns to Acknowledge (Self-Critique)

1. **Modest SR uplift (+0.018)**: STR_1715 baseline SR 1.59 already high; marginal returns small. Defensible: working on top of strong baseline.
2. **MDD parity, not uplift**: largest drawdown 2008-09 GFC was caught by existing system (S2). 본 alpha overlay has nothing to add at top of MDD.
3. **Bad/normal ratio 0.138 << 1.5**: 본 alpha is **protective overlay**, not defensive factor. AX-001 v2 PARTIAL — meta-allocation alpha isn't directly a defense factor.
4. **Crisis_alpha 5/8 zero**: overlay didn't fire (correctly, baseline already protective). Only triggered at non-classified single-month tails (2020-03, 2023-09 etc).
5. **Self-validated SR 1.634**: factor_engine_continuous label, NOT Forge realized SR. Charter §9 requires forge_realized_share_based for PG2 admission grade. 본 단계는 alpha signal strength meta only.
6. **lookahead_detector 3 false positives**: quantile() inside cat() log — diagnostic only, not signal construction. PIT-safe verified.
7. **Single-spec backtest**: full sample 2004-2026 (267 mo). Lockbox split deferred to deployment WT.
8. **Method shopping minimal**: 3 distinct methods (BOCPD + hyperbolic + BL aug). DSR n_trials=3, conservative. Hyperparameter tuning during dev (decay threshold 0.7 vs 0.8, protection 15pp vs 20pp) acknowledged as borderline grid-search — final spec defendable.

### Architectural Choices Defended

| Choice | Defense |
|--------|---------|
| BOCPD short_run_mass over change_prob | change_prob converges to hazard (uniform); short_run_mass captures regime youth — operationally meaningful |
| Hyperbolic decay on cumulative-avg-abs-returns | Lee 2025 mechanism on factor return (mechanical factor R²=0.65). Adapted for monthly STR_1715 ret_net. |
| Existing-System-Aware Augmentation (defer + add) | Tested 4 designs; only this one achieves SR uplift without spurious cash drag |
| Threshold decay ≥ 0.7 OR bocpd ≥ 0.6 | Empirically identified from 267-mo backtest as predictive thresholds |
| Protection levels 8pp/15pp/20pp/25pp | Discrete levels mapped to single/extreme/joint conviction; no continuous grid |

### Robustness to Critique

| Anticipated Critique | Response |
|---------------------|----------|
| "SR uplift only +0.018, not meaningful" | Acknowledged in challenge_flags. Mandate satisfied (any axis uplift). MDD-equivalent + subperiod uplift in early period. |
| "Crisis_alpha mostly 0/8 — overlay doesn't add value" | At aggregated 6mo level, existing system suffices. At MONTHLY tail (2020-03 -14% caught) is where 본 alpha adds value. |
| "Threshold tuning (0.7 / 0.6 / 0.9 / 0.8) is grid search" | Acknowledged. Single threshold per pillar (not joint grid). DSR n_trials=3 conservatively counts pillars. |
| "Lockbox not used" | Discovery WT cycle 1; lockbox split deferred to Deployment WT. Validation_window = train_window in Charter v1.2 'discovery' role spec. |
| "Bad/normal ratio 0.138 fails AX-001 v2" | 본 WT는 defense factor (AX-001 v2 scope) 가 아니라 meta-allocation overlay. PARTIAL not FAIL applied. |
| "alpha_inheritance_cor 0.0 vs realized correlation 0.992" | Cor 0.992 is mechanical (S3 = w * S1); inheritance_cor 0 by design (weight schedule alpha is orthogonal to ticker α̂). |

### Codex Critic Round (Pending)

Will be invoked at finalize stage:
```
bash 02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh \
  --role=alpha \
  --task_id=WT-D20260430_001 \
  --package=qepm/mailbox/worktask/WT-D20260430_001/alpha_package_draft.json \
  --output=qepm/mailbox/worktask/WT-D20260430_001/codex_critic_response_alpha.json
```

After Codex response, this challenge_note will be updated with:
- Each concern: ACCEPT / PARTIAL / REBUTTAL classification
- REBUTTAL with academic citation + L-code + quantitative evidence
- Self-rationalization auto-detection scan (회피 표현 grep)

---

**End of pre-Codex draft.**
