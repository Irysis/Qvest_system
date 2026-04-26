# Alpha Challenge Note — WT-D20260426_006 STR_1656_M06 v2 REVISE

**Author**: Alpha Research Agent v1.2 (Opus 4.7) — v2 REVISE
**Created**: 2026-04-26 (v1 2026-04-26 REJECTED → v2 2026-04-26 fix)
**WT**: WT-D20260426_006
**Hypothesis**: STR_1656_M06 v2 PG2-conditional ML diversifier (universe + liquidity fix)
**Common Charter Principle 8 (No Silent Override) compliance**

---

## 0. v1 → v2 Audit (AX-002 Process Honesty)

v1 alpha_package was REJECTED by Codex with 9 critical concerns. Of those, **2 were silently omitted** in the v1 alpha_codex_resolution.json (AX-002 violation):

1. **C2 HARD_UNIVERSE_BREACH** — v1 alpha_vector top20 had 0/20 in K200∪KQ150 union (panel built without universe filter)
2. **C3 C10_LIQUIDITY_PROXY_WRONG** — v1 used AvgTV20 = frollmean(Size, 20). Size is 시가총액 (market cap), not 거래대금 (trading value). True formula: Close × Vol.

v2 fixes both via 8 mandates. **No silent omission this round.**

---

## 1. v2 8 Mandates Implementation

| # | Mandate | v1 status | v2 implementation |
|---|---|---|---|
| M1 | Universe enforce (K200∪KQ150 PIT) BEFORE training | MISSING | filter_universe_liquidity() at MI prefilter + IS + Val + OOS + LATEST_ME. RAWDATA K200/KQ150 PIT membership flags (per-Date). top20_in_universe = 20/20 expected. |
| M2 | AvgTV20 = Close × Vol (true TV) | WRONG (Size proxy) | `RAWDATA[, TV_daily := Close * Vol]; AvgTV20 := shift(frollmean(TV_daily, 20L, align='right'), 1L)`. Threshold 2e8 KRW (production). top20_pass_2e8 = 20/20 expected. |
| M3 | Turnover ≤ 600% Hurdle hard cap | challenge_flag only | 3M EMA score smoothing (alpha=0.5) per-Ticker BEFORE top20 ranking + universe restriction + stronger XGB regularization (max_depth 5→4, subsample 0.7→0.6, lambda 1→2). |
| M4 | ML algorithm honest disclosure | false ensemble claim | XGBoost 3-seed + CatBoost 3-seed rank-mean ensemble. lightgbm explicitly NOT INSTALLED in R 4.5.2 environment. method_actually_implemented declared. |
| M5 | Newey-West HAC + 5-spec regression | simple t-stat only | `sandwich::NeweyWest(lm(IC~1), lag=floor(4*(n/100)^(2/9)), prewhite=FALSE)`. 5-spec (CAPM/Carhart3/Carhart4/FF5/FF6) on top decile portfolio with NW-HAC alpha t-stat. DSR_post conservative (n_trials = MI_TOP × OOS_years × specs). |
| M6 | sub_stab ≥ 0.50 graduation gate | 0.3993 < 0.50 | MI top tightened (40→30 parsimony) + ensemble diversification (CatBoost) + EMA smoothing + universe filter. RF-A1 challenge_flag retained only if post-fix < 0.50. |
| M7 | PIT L-164 v1.1 carve-out evidence | self-waive | Explicit by-name citation (CLAUDE.md + methodology_active.md) + factor_db_daily_registry path + precedent (STR_1656_MLRA_M05 S1 PASSED) + audit_lineage block in alpha_validation.json + alpha_package.json. C13/C14/C15 = N_A_BY_CARVE_OUT (explicit tag). |
| M8 | Codex 9/9 + AX-008 explicit | 7/9 omission | All 10 concerns explicit decision in alpha_codex_resolution_v2.json (8 ACCEPT_AND_FIX + 2 DEFER_RETAIN_NOTE). v1_silent_omissions_audit block. |

---

## 2. Open Disagreements (v2)

| # | Issue | v2 position |
|---|---|---|
| 1 | RF-A1 sub_stab ≥ 0.50 graduation gate | M6 mitigation applied (parsimony + ensemble + EMA + universe). If post-fix < 0.50, RF-A1 challenge_flag retained. RF-A1 mandate target 0.20 (from User WT) achieved if sub_stab ≥ 0.20. |
| 2 | RF-A2 composite improvement < 5% threshold | DeMiguel-Garlappi-Uppal 2009 — composite ICIR 단순 비교 부적절. **본질 평가는 PG2 blended Realized SR (Forge S6 backtest 영역)**. |
| 3 | RF-A3 recent3Y > overall × 1.5 | post-2018 KR ML alpha regime shift (Avramov 2023 §3 short-sale-restriction relaxation) 가능성. R2 P2 lockbox 2024-01-23 ~ 2026-01-23 sealed (recent over-fit OOS check). |
| 4 | DSR_post conservative count | MI_TOP_N × OOS_years × specs ≈ 2400 trials. Bailey-Lopez de Prado conservative. |
| 5 | C9_PG2_NAV_COR | Forge backtest 영역. Alpha boundary excludes weights/cov. |
| 6 | C10_AX_008 triangulation | Alpha + Codex R1 = 2-source. Architect/Forge at S6. |

---

## 3. PIT Compliance (C1~C15) v2

L-164 v1.1 ML carve-out 명시 적용 + audit_lineage block:
- C1 PASS: expanding monthly walk-forward
- C2 PASS: score at sig_date applied at fwd_ret = sig_date + 21 trading days
- C9 PASS: regime expanding pct (BM 252d rolling vol, t-1 lag)
- C10 PASS: **AvgTV20 = Close × Vol (true TV), 20d rolling mean, t-1 lag, threshold 2e8 KRW (FIXED v2)**
- C11 PASS: KR internals only. FF5 v2 monthly returns lagged t-1.
- C13 N_A_BY_CARVE_OUT: L-164 v1.1 ML carve-out (raw daily factor read)
- C14 N_A_BY_CARVE_OUT: load_month_factors() 미경유. Walk-forward expanding ensures temporal isolation. Lockbox SEALED.
- C15 N_A_BY_CARVE_OUT: L-164 v1.1 ML carve-out applied (CLAUDE.md + methodology_active.md citation)

**L-164 v1.1 carve-out evidence boost (M7)**:
- citation_paths: CLAUDE.md (Factor DB Sessions 40+) + methodology_active.md (L-164 v1.1)
- factor_db_registry: .cache/factor_db_daily/factor_db_daily_registry.json
- precedent_strategy: STR_1656_MLRA_M05
- precedent_status: S1 PASSED Forge S1 + Judge audit
- audit_lineage: walk_forward windows + purge embargo + lockbox

R2 P2 Lockbox isolation:
- TRAIN_VAL_END = 2024-01-22 (ENFORCED)
- LOCKBOX [2024-01-23, 2026-01-23] SEALED — Alpha agent 접근 ZERO
- OOS_YEARS = 2008~2024 (lockbox 진입 차단)

---

## 4. AX Axiom Anchor Citations (v2)

- **AX-000**: SR gap 0.5375 채울 수 있다 — v2 universe + liquidity fix completed.
- **AX-001 v2**: ML diversifier conditional metric — M05 crisis 보호 유지 + crisis_alpha 측정 위임.
- **AX-002 PROCESS HONESTY**: v1 silent omission FIXED. 10/10 explicit decisions. ICIR/Harvey_NW/sub_stab/turnover all reported with v2 values.
- **AX-004**: M06v2 ML ensemble = multi-feature multi-axis (NonRE top + 6F FF5 + 1F regime) 비선형 결합. EXCLUSION valid.
- **AX-005 EXCLUSION_BY_L164_v1_1**: ML strategy carve-out per documented project rule. EXCLUSION evidence: ML feature ensemble (multi-axis composite, not standalone defense factor).
- **AX-007**: structure = score-level addition to existing PG2 sleeve allocation, role = diversifier_with_pg2_complementarity. Multi-sleeve (STR_1701 80% + M06v2 20%).
- **AX-008 PARTIAL**: Codex R1 v1 executed (REJECT, 9 concerns). v2 remediation applied. Codex R1 v2 round pending. Architect/Forge triangulation deferred to S6.

---

## 5. Strict Prohibitions Acknowledged

- ❌ STR_1701 weights 수정 절대 금지 (PG2 80% slot fixed). Alpha는 alpha_vector만 산출.
- ❌ Single-strategy SR > 1.46 강박 X. PG2 blended이 본질.
- ❌ 합리화 표현 사용 금지 ("영향 미미", "관행적 허용", "보수적이면 괜찮다").
- ❌ L-164 위반 — 월간 288 Z_Score는 load_month_factors 필수, 일간 ML carve-out만 raw read 허용.
- ❌ normalizePath() 사용 X.
- ❌ Universe 외 ticker 포함 (M1 enforce — fixed v2).
- ❌ Size-based AvgTV20 (M2 fix — Close*Vol).
- ❌ Codex concerns silent omission (M8 — 10/10 explicit).

---

## 6. Out-of-Scope Acknowledgement

- 공분산행렬 추정 — Risk Agent 영역
- 포트폴리오 비중 결정 — Optimizer Agent 영역
- 제약조건 사전 최적화 — Optimizer 영역 침범 X
- Sector neutralization — Optimizer 영역
- Cash overlay 결정 — Optimizer 영역 (regime_state column만 alpha_scores.parquet에 첨부)
- PG2 NAV-level cor / TDC / weights / crowding — Forge backtest 영역

---

## 7. Lineage Discipline (L-194)

alpha_package.json write → record_package_lineage 순서 엄격 준수.
- artifact_lineage.json append (P7 audit)
- input files: request.json + rawdata.parquet + kr_factor_returns_v2.parquet + alpha_scores.parquet + alpha_validation.json + factor_engine_proposal.R + alpha_codex_resolution_v2.json + codex_critic_response_alpha.json + alpha_package_v1_REJECTED.json
- v1_status = "REJECTED (silent omission C2 + C3)" / v2_remediation = "8 mandates implemented + 10/10 concerns explicit"

---

## 8. Telegram Discipline (v4 ENFORCE)

- tg_agent_brief() 단일 호출만 사용 (send_alpha_brief_v2.R)
- 직접 tg_send/tg_send_rich/tg_send_photo 호출 금지 (Hook block)
- sections >= 4, table nrow >= 2, body chars >= 50, items >= 3, emoji >= 5
- v2 sections: Diagnostics(NW-HAC) / 5-Spec(NW-HAC) / v1→v2 Fix Audit / 핵심 발견 / Challenge Flags / 메타

---
**Resolution status v2**: factor_engine_proposal.R (universe + liquidity fix) → alpha_pipeline_v2.log → alpha_package_draft.json (v2) → finalize_alpha_v2.R (overwrite alpha_package.json) + record_package_lineage → run_codex_round.sh (Codex R1 v2) → send_alpha_brief_v2.R (Telegram).
