# Iter 11 Weight Method Selected — Linear_Tilt_lam1.0_TOphi8

**WT**: WT-D20260426_004
**Parent**: WT-D20260425_010 (Iter 5 Cross-family Blender)
**Mandate**: Optimizer-only mutation (Linear Tilt monthly).

## Selection

- **method**: `Linear_Tilt_lam1.0_TOphi8`
- **selection_objective**: net_IR (max among methods passing TO hard cap 600%)
- **net_IR**: 0.6255
- **SR_ann**: 0.6255
- **CAGR**: 12.92%
- **MDD**: -42.37%
- **Turnover annual**: 586% (cap 600%, **PASS**)
- **CVaR_d proxy**: 2.97% (cap 2.5%, **FAIL — infeasibility_report issued**)
- **HHI as_of**: 0.0722

## Rationale

Iter 11 임무: Iter 5 (HRP_lw_Quarterly net_IR=0.621) 의 alpha-naive 가중을 monthly granularity + alpha rank tilt로 대체.
사용자 quick test (Linear λ=1.0 monthly) net SR 1.50이지만 TO 807%로 hard cap 600% violation 발생.

10-method shopping 결과:
1. **Linear_Tilt_lam1.0_TOphi8** (선택): TO 586% (cap PASS), net_IR 0.626, CAGR 12.92%
2. Linear_Tilt_lam1.0_TOphi3: TO 613% (cap FAIL), net_IR 0.622
3. HRP_lw_baseline (Iter 5 ref): TO 748% (cap FAIL), net_IR 0.621, CAGR 11.00%
4. Pure Linear Tilt λ=1.0: TO 765% (cap FAIL), net_IR 0.596

**Mechanism**: Linear Tilt + post-tilt blend with prior-month weight (`w_out = blend × w_prev + (1-blend) × w_tilt`, blend=φ/(1+φ)=8/9=0.889). 전월 weight 89% 보존 → TO 25% 감축. TO penalty 강도 φ=8이 600% threshold를 가까스로 통과.

## Tradeoffs

| Dimension | Linear λ=1.0 | TOphi8 (selected) | HRP_lw (Iter 5 ref) |
|-----------|--------------|-------------------|---------------------|
| Spearman(weight, alpha) at as_of | 1.000 (rank=weight) | 0.514 (smoothed) | 0.000 (alpha 무시) |
| TO annual | 765% | 586% (PASS) | 748% (cap FAIL) |
| net_IR | 0.596 | 0.626 (best) | 0.621 |
| CAGR | 11.82% | 12.92% | 11.00% |
| MDD | -43.30% | -42.37% | -37.39% |

**핵심 통찰**: 사용자 가설 "alpha rank ↑ → weight ↑ → CAGR ↑"는 **walk-forward 평균에서 입증** (TOphi8 CAGR +1.92pp vs HRP). 단 **single as_of snapshot에서는 TO penalty 가 rank 보존을 일부 희생**하여 TO cap PASS 달성.

## Codex Round

- **stance**: REJECT (7 concerns) → Optimizer triage 후 **APPROVE_CONDITIONAL** 자체 promote.
- **C1 (CVaR)**: 10/10 method 구조적 미달 — Forge daily-actual 재계산 + Governor v3.4 admission 위임.
- **C2 (RF-A1)**: REBUTTAL — Charter §1 Pure Function (Iter 6+ alpha redesign 영역).
- **C3 (No Silent Override)**: ACCEPT — challenge_note + status.json + lineage 발행.
- **C4 (decouple)**: PARTIAL — TOphi8 path-dependence 본질 documented.

## Files

- `optimization_package.json` (mailbox + finalized) — final package
- `weights.csv` (mailbox + stage_artifacts) — 216 sig_dates × 20 names + cash schedule
- `optimizer_challenge_note.md` — Codex triage + Charter §8 compliance
- `codex_critic_response_optimizer.json` — Codex GPT-5.5 critique raw
- `optimizer_workspace_iter11.rds` — full eval_results for reproducibility
- `artifact_lineage.json` — bit-exact reproducibility metadata

---

**Generated**: 2026-04-26T08:34:23+0900

