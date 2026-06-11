# T+30 POST_DEPLOY AR Overlay Review — STR_1715_AR_on_M4_R05_overlay_PG2

- **Review date**: 2026-06-12 (T+30 anchor 2026-06-11 ~ 12, executed on due date)
- **Agent**: Monitoring (Q-Lead spawned, Opus 4.8 1M)
- **Subject**: `STR_1715_AR_on_M4_R05_overlay_PG2` — single-sleeve PG2_CORE_ALPHA 100%
- **Deploy effective**: 2026-05-13 (R05 Layer-5 admit, WT-H20260513_001)
- **Cost label**: `v2.4_kr_retail_15bps` (delta-based, 06-11 flip; prior flat records labeled separately)
- **Authority boundary**: Monitoring specifies/flags only. No book_state write, no rollback execution, no Judge re-verdict — all reserved for Q-Lead + 도훈 manual.

---

## 0. Headline

**No hard rollback breach detected; but every quantitative rollback KPI is UNMEASURABLE on this clone** for two compounding reasons: (1) no live-account NAV (KOFIA tracking off), and (2) **`rawdata.parquet` on this machine is calendar-corrupted for the live window** — it carries Saturdays as trading days and is missing the entire June-crash session block (06-04…06-09). The benchmark side is clean and shows a **−14.96% KOSPI200 June peak-to-trough** (CRISIS-class regime stress, vs the strategy's predicted 1.2% CRISIS distribution). The single actionable, due-today obligation is the **AR-007 Charter §11 turnover-amendment motion (Q-Lead)**; the **AX-008 3/3 codex re-run is now technically enabled** (codex CLI restored 06-11) and awaits Q-Lead go.

---

## 1. Obligation Register (모법) — extracted from `book_state.json`

24 distinct T+30-relevant conditions across 7 sources. Full per-item {조건/원문/due/측정방법/판정} in `t30_condition_verdicts.json`. Summary by due-bucket:

| Source block | Items | Net status |
|---|---|---|
| `user_override_log` OVERRIDE_008 `rollback_conditions` (7) | KPI1 SR<1.10, KPI2 DSR<0.95, MDD>-45%, TO>600%, IR<0.80, weight_sum<0.80, (Harvey T+14 already past) | 1 PASS_PROVISIONAL (MDD) + 4 UNMEASURABLE + 1 NOT_DUE (TO annual) |
| `deploy_post_conditions` (POST_DEPLOY_004/006/009 at T+30) | AX-001v2 (Forge), AX-008 3rd-source (Architect), recent/OOS drift (Monitoring) | 1 Forge-open + 1 Layer4-satisfied/Layer5-open + 1 UNMEASURABLE |
| `wt_D20260511_001` rollback (SR<1.50, TDC>0.50) + `five_pd_grace_clauses` (PD15/PD16) | med_10pct 5-sleeve conditions | **MOOT/SUPERSEDED** — med_10pct admit fully REVOKED 2026-05-12 (`pd25_revoke_log`) |
| `grace_clauses_9_binding` T+30 (GC5/GC6/**GC7**) | C_softmax research-foundation-candidate path | OPEN but lineage-disjoint from active book (production BLOCKED) |
| `post_deploy_ar_007_binding` / `turnover_disposition` | Q-Lead Charter §11 TO-cap amendment motion | **DUE NOW — ACTION REQUIRED** |
| `ax_008_dohoon_mandate_pending_remediation` | Codex 3-stage re-run → 3/3 → promotion_wt | **ENABLED — ready to run** |
| `live_track/holdout_interval.json` (C3) | Trailing Sharpe vs [0.3929, 3.1626] | NOT_DUE (1m << 21m horizon) |

---

## 2. Realized Measurement — `metric_type = estimated(paper)`

**Method**: Paper reconstruction of the deployed portfolio (no live NAV). Holdings = 2026-04-01 sig_date **Top-20 EW** (deploy snapshot; top-5 = A005930 삼성전자 / A006400 삼성SDI / A000660 SK하이닉스 / A247540 에코프로비엠 / A009830 한화솔루션 — matches `book_state.sleeve_top_5`). Overlay = deployed May state **net 70% risk / 30% cash** (`m4`=NORMAL 1.0, `β_AR`=0.7, `β_R05`=1.0 per `manifest.may_2026_regime_state`). 15bps delta-based entry cost on risk notional. PerformanceAnalytics (`Return.cumulative` / `maxDrawdown`) only — no `prod(1+r)` self-synthesis for SR/DD.

### 2a. Benchmark (clean, 20 real sessions) — RELIABLE
| Metric | Value |
|---|---|
| KOSPI200 window total return | **+1.58%** |
| KOSPI200 window maxDD | **−14.96%** |
| June peak→trough (close) | 8801.49 (06-02) → 7484.41 (06-08) = **−14.96%**, then bounce to 7763.95 |

This is the documented June CRISIS event (cf. MEMORY: "06월 BM ±8% 급변동 = CRISIS 라벨 정합"). Predicted CRISIS distribution at admit was only **1.2%** — June is a tail-regime realization vs the backtest's regime mix.

### 2b. Portfolio (clean 10-session intersection) — LOW FIDELITY
| Metric (paper, estimated) | Value | Caveat |
|---|---|---|
| Port net window total | **−3.17%** | excludes crash week 06-04…06-09 |
| Port net maxDD (within 10d) | −4.57% | crash days absent → understates risk |
| Active vs BM (10d) | **−3.26pp** | crash-week defensive cash benefit NOT captured |
| SR_ann point | −2.139 | **uninformative**: SE ≈ 6.94 annualized (Lo 2002 iid) |

**The 10 measurable sessions exclude exactly the 06-04…06-09 crash week** (rawdata gap), so the portfolio-side numbers omit the single most decision-relevant period and the very window where the 30%-cash overlay should help most. They cannot be used for a rollback verdict.

---

## 3. Condition Verdicts (판정표)

| ID | Condition | Verdict | Basis |
|---|---|---|---|
| KPI1 | T+30 SR cost-corr < 1.10 | **UNMEASURABLE** | 1m SR SE~6.9 + rawdata gap; point estimate must not trigger (mandate) |
| KPI2 | T+30 DSR_post < 0.95 | **UNMEASURABLE** | insufficient OOS; pre-existing R05 DSR_N37 −3.596 is an *admit-time* caveat, not new |
| KPI3 | T+30 SR < 1.50 | **NOT_DUE / SUPERSEDED** | belonged to revoked med_10pct admit |
| KPI4 | T+30 TDC live > 0.50 | **NOT_DUE / SUPERSEDED** | single-sleeve book; TDC undefined; revoked admit |
| KPI5 | monthly drift > 5pp / \|ΔSR\|>0.2 | **UNMEASURABLE** | needs reliable realized SR vs 1.9536 |
| MDD | MDD > −45% (hard) | **PASS (provisional)** | no −45% evidence; clean-10d −4.57%, BM −14.96%; cash overlay dampens |
| TO | TO > 600% (hard) | **NOT_DUE** | annual metric; 1m window can't annualize; admit waiver active |
| IR | IR vs KOSPI200 < 0.80 (hard) | **UNMEASURABLE** | needs multi-month active series |
| WSUM | actual_weight_sum mean < 0.80 | **UNMEASURABLE** | live weights need May/June prod scores (absent); May risk_pct 0.70 consistent |
| PD004 | AX-001v2 conditional (T+30) | **OPEN (Forge-owned)** | R05 = pure overlay, AX-001v2 N/A; Forge backlog |
| PD006 | AX-008 3rd source (T+30) | **Layer4 SATISFIED / Layer5 OPEN** | AR-layer Architect 3rd-source PASS exists; R05-layer 2/3 → see §6 |
| PD009 | recent-12M/OOS drift (T+30) | **UNMEASURABLE** | data-integrity block |
| PD15/16 | med_10pct schedule/forge (T+30) | **MOOT / SUPERSEDED** | conditioned on revoked admit; artifacts exist but obligation void |
| GC7 | overlay-cycle 6-agent (T+30) | **OPEN (C_softmax) / done on active R05 cycle** | C_softmax candidate lineage-disjoint; R05 cycle did complete 6-agent |
| **AR-007** | **Q-Lead Charter §11 TO motion (T+30)** | **DUE NOW — ACTION REQUIRED** | 759.34%/yr under waiver; motion to formalize/affirm |
| **AX-008** | **Codex 3-stage re-run → 3/3 (T+30)** | **ENABLED — ready to run** | CLI restored 06-11; targets in §6 |
| Holdout | trailing Sharpe vs [0.39, 3.16] | **NOT_DUE** | 1m << 21m horizon; q05=0.3929 is future-month alert floor |

---

## 4. Obvious-Violation / Attention Scan

- **No hard breach.** No −45% MDD, no catastrophic divergence signature.
- **HIGH attention — DATA_INTEGRITY_001**: `rawdata.parquet` (this clone) is calendar-corrupted for the live window (Saturdays as sessions, June-crash sessions missing). **Any quantitative rollback decision must wait for a re-run/re-provisioned RAWDATA.** This is a measurement-infrastructure defect, not a strategy failure.
- **Tail-regime note (informational)**: KOSPI200 −14.96% in June is a CRISIS realization vs predicted 1.2% CRISIS share. Worth a forward eye on whether the M4/AR/R05 cash overlay de-risked appropriately (un-measurable here because `regime_daily_v2.parquet` stops 2026-04-22).

---

## 5. UNMEASURABLE List + Reasons

| Item | Reason |
|---|---|
| KPI1 SR, KPI2 DSR, KPI5 drift, IR, WSUM, PD009 | (a) 1-month sample SR SE≈6.9 uninformative; (b) rawdata calendar corruption + missing crash week; (c) no live-account NAV (KOFIA off) |
| Live overlay scalars (June regime) | `regime_daily_v2.parquet` (M4/MRS source) ends 2026-04-22 |
| Live holdings weight-sum (May/June) | production alpha-scores panels end at 2026-04-01 sig_date; no May/June rebalance scores on this clone |

---

## 6. AX-008 Re-Run — Target Paths (specification only; execution = Q-Lead)

The `ax_008_dohoon_mandate_pending_remediation` ("re-run Codex critic 3-stage → 3-source PASS") is now **technically enabled**:
- **Codex CLI**: `codex-cli 0.139.0` on PATH (`/c/Users/99922/AppData/Roaming/npm/codex`).
- **Helper**: `02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh` — Windows path fix (cygpath) confirmed; supports `--role=forge|judge|governor`; invokes `codex exec --model gpt-5.5 -c reasoning.effort=xhigh`.

**Overlay cycle = WT-H20260513_001** (R05 Layer-5). Its WT mailbox is **empty on this clone**; canonical critic targets live in production:
- Forge: `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/01_reproducible_code/forge_package.json`
- Judge: `.../03_admit_artifacts/judge_verdict.json`
- Governor: `.../03_admit_artifacts/governor_admission.json`
- (existing critic responses to supersede: `.../03_admit_artifacts/codex_critic_response_{forge,judge,governor}.json`)

**Recommended (keeps production read-only)**: restage these three packages into a fresh scratch WT dir (e.g. `qepm/mailbox/worktask/WT-AX008RERUN_20260612/`), then run the helper 3× with `--role={forge,judge,governor}` and `--output` into that dir. 3-stage PASS would clear the AX-008 dohoon-3/3 gap that currently blocks the `promotion_wt` spawn.

---

## 7. Holdout 1st-Pass (C3 live extension)

`06_Registry/live_track/STR_1715_AR_on_M4_R05_overlay_PG2/holdout_interval.json`: 21-month Sharpe pre-registered interval **[0.3929, 3.1626]** (boot_median 1.7535, B=4000, block=12, `consumed=false`). Trailing live data ≈ 1 month — far below the 21-month horizon → **no falsification possible, no breach declarable**. 1st pass registered; **q05 = 0.3929 is the lower-bound alert floor** for future monthly trailing checks (Telegram alert on breach, manual disposition per C3 — no auto-rollback). `consumed=false` retained (no parameter change).

---

## 8. Q-Lead Follow-Up Actions

1. **[DUE NOW] AR-007 Charter §11 motion** — file the turnover-cap amendment motion (formalize 759.34%/yr or affirm the 6-rationale waiver). Pure Q-Lead governance action.
2. **[ENABLED] AX-008 3-stage codex re-run** — decide whether to execute now (targets/recipe in §6). If 3/3 PASS, unblocks `promotion_wt` spawn per dohoon mandate.
3. **[P0 INFRA] RAWDATA repair** — re-run `krx_build_rawdata.R` + `rawdata_sanitize.R` with a trading-calendar filter (or re-provision RAWDATA) so the live window has the correct KR calendar + June crash sessions. **Quantitative rollback KPIs remain UNMEASURABLE until this is fixed.**
4. **[INFRA] regime_daily_v2 refresh** — extend past 2026-04-22 so live-window overlay scalars are reproducible.
5. **[OWNERSHIP] route** PD004 (AX-001v2) → Forge backlog; PD006 Layer-5 Architect 3rd-source → Architect (folds into the AX-008 re-run).
6. **[CLEANUP] formally close** PD15/PD16 + med_10pct rollback KPIs as MOOT/SUPERSEDED in the obligation ledger (admit revoked 2026-05-12) to stop them surfacing in future T+30 cycles.
7. **[NEXT CYCLE] re-execute** this T+30 measurement once RAWDATA is repaired, then re-judge KPI1/2/5/IR/WSUM with reliable data (this review explicitly defers those verdicts, not pass-them-silently).

---

## Appendix — provenance
- Input authority: `qepm/mailbox/governor/book_state.json` (read-only).
- Realized inputs (read-only): `.cache/rawdata.parquet` (Jun 12 07:57; **calendar-corrupt for live window**), `.cache/benchmark.parquet` (Jun 12 07:53; clean), production `02_holdings_universe/full_universe_2026_04_01_sigdate.csv`, `manifest.json`.
- Compute scripts: `.cache/_t30tmp/0{1..6}_*.R` (+ `.out`), realized series `.cache/_t30tmp/realized_daily.csv`.
- Condition ledger: `04_Research/monitoring/t30_ar_review_20260612/t30_condition_verdicts.json`.
