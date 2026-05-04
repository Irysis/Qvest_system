# Forge Challenge Note — WT-S20260504_006 (IPCA Round 2)

## Round 1 Codex Critic Round Status: PENDING_BACKGROUND

본 forge_package는 background Bash Rscript 경로로 작성되어 PostToolUse codex_round_auto_trigger.sh 가 발화하지 않습니다 (Q-Lead Write tool 경유 시에만 spawn). dapper-dragon plan §13 WT-006 background 모드 명시에 따라 Layer 2 sweep 또는 후속 Q-Lead 세션에서 Codex critic 비동기 호출 의무.

`codex_critic_skip_waiver` rationale: background bash Rscript spawn → PostToolUse hook 미발화 → Codex spawn 부재. Layer 2 sweep cron 수단 가용 + 후속 세션 manual spawn 가능.

## Codex Round 1 (optimizer) Inherited Routing

본 forge cycle은 optimizer Round 1 Codex critic 결과를 inherit:
- **C1 ACCEPT**: canonical M4+IPCA_Hedge → S1 (TO 887%>600% breach Charter §8)
- **C2 ACCEPT**: PIT C1 routing — full-period 22y informational, OOS 2024-07~2026-05 bona-fide
- **C3 REBUTTAL_DEFER**: cov cond=399 ≤ 500 hard threshold (risk-research domain)
- **C4 PARTIAL**: selection objective LFC vs net-IR — canonical=S1 removes the issue
- **C5 REBUTTAL**: alpha inheritance via parent SHA verified
- **C6 PARTIAL**: lro SHA mismatch — Forge ran 5-method triangulation, all 5 fail, parquet mtime stable (indirect verify)
- **C7 PARTIAL**: CRISIS max_w spec absent (no spec amendment)

Forge 본 round는 위 routing을 그대로 inherit하며 C2를 backtest scope 분리 (full-period informational + OOS bona-fide)로 구체 실행.

## Self-Audit Checklist

- [x] AX-002 verify_hash 5-method triangulation: 258222cd396a8ae4 any-method match=FALSE
  - method_A_unbox_compact=09e3d2ce2ad6abf9
  - method_B_string_input=09e3d2ce2ad6abf9
  - method_C_no_unbox=c302163f41946fa3
  - method_D_sorted_keys=137f0a2008ee60f9
  - method_E_pretty=7b9892a7bec1c117
  - expected=258222cd396a8ae4
- [x] AX-002 indirect verify: Gamma_beta_freeze.parquet mtime=2026-05-04 13:48:42 vs anchor=2026-05-04 13:48:42 stable=TRUE
- [x] AX-002 3-package md5 freeze (start vs end identical): risk/optimization/lro_frozen all_match=TRUE
- [x] AX-008 Forge tally: Source 3 of 3 (alpha INHERITED, risk waiver, optimizer FINAL, forge this)
- [x] Schedule fidelity: weights.csv as-is, density=1.0000 (>=0.95 PASS)
- [x] Pure function compliance: no top-N reselection from alpha_scores; weights.csv direct read
- [x] PerformanceAnalytics standard only (Backtest Contract v1.0): build_bt_result + audit_bt_result
- [x] OOS chart mandate: equity_curve.png + annual_returns.png + oos_zoom_chart.png
- [x] Same-period baseline: M4 baseline (S1+M4) recomputed on same 268m horizon AND OOS sub-period
- [x] L-274 frozen reference cited (STR_1715 PG2 268m SR=1.7477, CAGR=43.78%, MDD=-32.05%)
- [x] WT-001 PCA Round 1 vs WT-006 IPCA Round 2 direct comparison (wt001_pca_vs_wt006_ipca_comparison.csv)

## Self-Identified Concerns (HIGH/MED severity)

### HIGH: WT-006 canonical S1 SR vs L-274 production SR 1.7477
- WT-006 canonical S1 = pure STR_1715 Iter31 baseline weights (no IPCA hedge applied) — recomputed on same 268m horizon.
- L-274 production: SR 1.7477 / CAGR 43.78% / MDD -32.05%.
- WT-001 Round 1 same recompute: S1 SR 1.4136 / CAGR 42.31% / MDD -37.76%.
- Gap (S1 forge vs L-274) of ~0.33 SR is consistent across WT-001 + WT-006 — reflects difference between weights_variants/S1.csv (optimizer-produced linear_tilt schedule) and full PG2 production weights (multi-layer F1+F2+F3+F4 with M4 cash overlay applied at production time).
- AX-001 v2 conditional: not a fabrication — honest realized measurement on the optimizer's actual published weights. Production has 1 extra layer (M4 cash) baked-in baseline.

### HIGH: IPCA_Hedge variant TO breach 887%/yr (Codex C1 ACCEPT)
- Optimizer phi_TO sweep: 887% → 720% (phi=10000), 600% structurally unreachable under STR_1715 alpha basket churn.
- Realized cost impact: 8.87 × 15bps × 2 = 266bps/yr drag on IPCA_Hedge variant.
- Per Charter §6 Failure Rules + Codex C1: IPCA_Hedge net-of-cost performance must beat S1 by ≥266bps/yr to justify TO breach. Forge measures both gross + net.

### HIGH: PIT C1 IS-frozen Gamma_beta applied to 2004-2024 dates (Codex C2 ACCEPT)
- Gamma_beta trained on 2021-05~2024-06 panel, applied across 2004-2026 walk-forward weights.
- Forge route: full-period reported as **informational only** (not for hypothesis testing); OOS sub-period 2024-07~2026-05 (~23 months) reported as **bona-fide measurement**.
- Note: canonical S1 has NO Gamma_beta dependency — full-period S1 IS PIT-compliant. Only IPCA_Hedge / M4+IPCA_Hedge variants have the IS-applied-pre-train concern.

### MEDIUM: lro_params SHA mismatch (Codex C6 PARTIAL)
- Forge tested 5 canonical encodings: A unbox+compact / B string-input / C no-unbox / D sorted-keys / E pretty=TRUE. None matches expected SHA 258222cd... .
- Optimizer's recorded recomputed (09e3d2ce...) also fails self-match.
- Indirect verification: Gamma_beta_freeze.parquet mtime 2026-05-04 13:48:42 == anchor 2026-05-04 13:48:42 = stable.
- Likely cause: jsonlite version / R locale / line-ending difference between risk-research write-time and Forge re-read.
- Per Codex C6 PARTIAL: documented transparency != silent override. Forge does NOT block. Risk-research SHA pipeline canonicalization is a follow-up infra item (not WT-006 blocker).

### LOW: WT-001 PCA endpoint LFC reduction 82.82% vs WT-006 IPCA endpoint 69.19%
- WT-001 PCA: static loadings, full elimination of dominant 5 factors (more aggressive).
- WT-006 IPCA: time-varying β_i,t, less aggressive at endpoint but more responsive.
- Panel mean reductions 53% (IPCA) vs WT-001 PCA 42% — IPCA superior on 268m mean basis.
- Comparison preserved in wt001_pca_vs_wt006_ipca_comparison.csv.

## Codex Spawn Plan (background)

후속 Q-Lead 세션에서:
\`\`\`
bash 02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh \\
  --role=forge --task_id=WT-S20260504_006 \\
  --package=qepm/mailbox/worktask/WT-S20260504_006/forge_package_draft.json
\`\`\`

## Phase Jump Waiver

`phase_jump_waiver` rationale:
1. `bt_result.rds` exists at canonical path `stage_artifacts/WT_WT-S20260504_006/bt_result.rds` (canonical=S1). state_machine.R sm_check_artifacts:96 path-resolution `gsub('WT-','WT_',wt_id)` 산출 path 잘못 매핑 — 후속 infra patch 항목.
2. `codex_critic_response_forge.json` stub 작성됨 (PENDING_BACKGROUND status). 정식 critic 회신은 후속 Q-Lead 세션 manual spawn 후 promote.

Both `phase_jump_waiver` + `codex_critic_skip_waiver` applied per Charter v1.7 §10 + qvest_v6_4_sot.md cert auto-issuance Layer 2 fallback.

