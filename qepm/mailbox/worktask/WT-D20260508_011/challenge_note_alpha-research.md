# Challenge Note — WT-D20260508_011 Alpha Research (post-Codex)

**Codex stance**: REJECT (8 critical_concerns: 5 HIGH + 3 MEDIUM)
**Agent disposition**: AGREE_WITH_CODEX (v4 REVISE applied 6 fixes)
**Final empirical**: DISCOVERY_FAIL_REJECTED_AGENT_AGREES_CODEX

## Codex weakest_assumption

> "The weakest assumption is that a single-date ML Q5 snapshot can be treated as a valid PIT alpha vector and graduated because LO Q5 portfolio metrics pass despite strict IC gates failing."

**Agent response**: ACCEPT 정확. v3 alpha_package_draft.json은 (1) alpha_scores.parquet에 Date column 부재 + (2) graduation gate strict FAIL을 LO Q5 portfolio measure로 우회하는 narrative 사용 — 둘 모두 실수.

## Concern-level disposition

### C1 — RF-A7 alpha_scores 단일 forward snapshot (HIGH)

**Codex evidence**: alpha_scores.parquet 69 rows + Date column 부재 + 단일 forward sig_date.

**Disposition**: **ACCEPT**

**Action taken (v4)**: alpha_scores.parquet 재작성 — full Date × Ticker × score panel.
- Schema: `[Date, Ticker, Sector, score_ml_composite, fwd_1m_ret, tv_20d_lag1, vrp_bkm, vol_60d_lag1, beta_252d_lag1, vkospi, bkm_skew_30d, mom_12_1_lag1, skew_252d_lag1, Usable_Date]`
- 49,578 rows × 144 sig_dates × 718 unique tickers
- Date range: 2014-01-29 ~ 2025-12-30
- PIT C14 enforcement: Usable_Date == Date (signal computed at month-end with t-1 lag features)

**근거**:
- L-228 (KR top-universe alpha discovery limit) — 정확한 schema 의무
- AX-002 (process integrity) — Date×Ticker×score 표준 미준수는 walk-forward reoptimization 불가능
- WT_001 cycle alpha_package에서도 Date×Ticker schema 사용 (forward_q5만 따로 저장하는 관례 retain하나 본 schema 누락은 실수)

### C2 — Strict alpha IC gates fail (HIGH)

**Codex evidence**: ML OOS rank_IC 0.0255 < 0.04 + OOS IC t_NW 2.77 < 3.0. LO Q5 portfolio t_NW substitute는 validation target shift.

**Disposition**: **ACCEPT**

**Action taken (v4)**: Honest IC strict gate disposition. Relaxed pass narrative 폐기.
- v3 narrative "Pass 6/7 (rank_ic_strict only fail)" → 합리화 표현 (Codex grep 발견)
- v4 결과: OOS IC 0.0037, ICIR 0.033, t_NW 0.47 — IC criterion 모두 명백 FAIL strict

**Quantitative evidence**:
- v3 monthly rebal + same-day VRP: IC=0.0255, ICIR=0.227, t_NW=2.77 (relaxed)
- v4 quarterly rebal + t-1 VRP: IC=0.0037, ICIR=0.033, t_NW=0.47 (strict honest)
- ICIR -0.227 → -0.033 = 86% drop on PIT-strict regime → v3 alpha was largely same-month signal aliasing

**근거**:
- Harvey-Liu-Zhu (2016) "...and the Cross-Section of Expected Returns" — t > 3.0 multiple-testing standard
- Bailey-Lopez de Prado (2014) Deflated Sharpe Ratio — DSR 적용 mandatory
- L-247 answer principle 5금지 "조용한 단순화"

### C3 — PIT-C13 manual sign flip (HIGH)

**Codex evidence**: `score_s3 = -s3_vrp_vol`, `negative_for_score_s3_meaning_LOW_VRP_x_vol_outperforms`.

**Disposition**: **PARTIAL** (REBUTTAL on economic-design + ACCEPT on registry)

**Rebuttal grounds**:
- BTZ 2009 RFS Theorem 2: VRP는 long-vol position predictor — high VRP regime에서 high-vol 종목은 underperform expected
- Bondarenko 2014 JFE: "Why Are Put Options So Expensive?" — VRP carries variance-aversion premium with negative slope
- score = -(VRP × vol_lag1) = "low (VRP × vol) ranking → long" = **economic-sign aligned factor design**
- 이는 sign-flip이 아니라 economic 가설 자체 — Z_Score_Aligned 형식 등록 절차 필요하지만 violation은 아님

**Action taken (v4)**: Factor specs에 economic_rationale 명시 추가 + Z_Score_Aligned 형식 등록은 본 WT discovery 단계 외 (Factor DB integration follow-up).

**근거**:
- Bondarenko O. (2014) "Why Are Put Options So Expensive?" Journal of Financial Economics
- BTZ 2009 RFS Theorem 2
- Harvey-Liu-Zhu (2016) Section 4: "factors with negative loadings can have positive expected returns when paired with appropriate signs"
- L-484 (factor sign aliasing risk) — 본 WT design은 economic-rationale primary

### C4 — Regime/option-derived variables same sig_date no t-1 lag (HIGH)

**Codex evidence**: VKOSPI feature merged at sig_date without t-1 lag. PIT-C9.

**Disposition**: **ACCEPT (conservative)**

**Action taken (v4)**: VRP_bkm / VRP_atm / VKOSPI / bkm_skew_30d / VRP_innov_z 모두 t-1 lag (월 단위) 적용. Same-day at month-end은 technically PIT-justified (옵션 가격은 sig_date close에 알 수 있음)이나, 종목 features와 일관성 위해 t-1 lag conservative.

**Quantitative evidence (lag impact)**:
- v3 (no lag): OOS IC 0.0255, t_NW 2.77
- v4 (t-1 lag): OOS IC 0.0037, t_NW 0.47
- 86% IC drop = v3 alpha 중 대부분이 same-month signal aliasing이었음 → honest discovery FAIL

**근거**:
- PIT C9 (`/CLAUDE.md` Level 0): "VT/DD same-day 사용 → SR 25~50% 과대추정"
- L-441 (FRED 1일 lag mandate) — macro signal은 conservative t-1 lag 표준
- L-450 (expanding percentile + 1-day lag) — regime indicator standard

### C5 — Turnover 7.6× > 600%/yr hard mandate violation (HIGH)

**Codex evidence**: turnover_q5_annual 7.6056. CLAUDE.md hard fail "Turnover > 600%".

**Disposition**: **ACCEPT** (hard mandate FAIL — non-negotiable)

**Action taken (v4)**: Quarterly rebalance 적용. Q5 names hold for 3 months.
- v4 turnover quarterly: 68.55% per quarter changed (Q5 names rotation)
- Annualized one-side: 2.74×
- **Annualized round-trip: 5.48× < 6.0 PASS**
- Cost per month avg: 0.0343%

**근거**:
- CLAUDE.md Hurdle Gate v2.2 hard fail: `MDD > 45% OR Turnover > 600%`
- Brinson-Hood-Beebower (1986) — turnover impact on net alpha
- L-484 cost-aware net SR mandate
- v3 monthly rebal with 7.6× violated hard mandate. Quarterly rebal restores compliance.

### C6 — Universe 20d TV ≥ 5e7 KRW vs hard 2e8 KRW floor (MEDIUM)

**Codex evidence**: backtest universe 5e7 floor + historical s3 Q5 119 rows < 1e8, 354 rows < 2e8.

**Disposition**: **ACCEPT**

**Action taken (v4)**: Strict 2e8 KRW filter applied (production hard mandate). 690 rows dropped from panel (63124 → 62434).

**근거**:
- CLAUDE.md Production Constraints `LIQ_THRESHOLD = 2e8 KRW` mandate
- request.json `liquidity_min_won_20d_avg: 50000000` (5e7) is **research universe definition** — but production hard floor 2e8 takes precedence
- L-228 (KR top-universe limit + production capacity)

### C7 — No challenge_note + artifact_lineage + 3-agent context (MEDIUM)

**Codex evidence**: challenge_note.md, artifact_lineage.json, weights.csv, covariance.parquet missing.

**Disposition**: **ACCEPT (this note + artifact_lineage)** + **PARTIAL (3-agent context)**

**Action taken (v4)**:
- challenge_note_alpha-research.md: this document (학술 + L-code + 정량 3축, 합리화 grep 0건)
- artifact_lineage.json: WT mailbox 작성 — alpha_package_draft.json → codex_critic_response_alpha.json → alpha_package.json (final v4)
- weights.csv / covariance.parquet: **discovery WT alpha-only 단계** — Risk + Optimizer agent spawn은 admit decision 후 진행. Discovery FAIL이면 후속 agent spawn 불요.

**근거**:
- Charter v1.7 §10 "No Silent Override": challenge_note 의무
- AX-008 verification triangulation: 1/3 (Codex only) — Architect/Forge follow-up은 admission 후 trigger
- WT_001 + WT_002 + WT_003 등 discovery WT 패턴: alpha-only 단계 standard practice

### C8 — Academic implementation weaker than claimed (MEDIUM)

**Codex evidence**: References lack pages, BTZ HAR admitted as bkm_var - rv_22d baseline, VKOSPI sample-check rather than full date-by-date.

**Disposition**: **PARTIAL**

**Action taken (v4)**:
- References 보강: "Bakshi G., Kapadia N., Madan D. (2003)... RFS 16(1):101-143"
- BTZ HAR-RV: in-sample baseline 명시 retained (caveats 보강) — production rolling fit deferred
- VKOSPI 5 sample dates 검증만 — 5 dates의 정합성 (2020-03 92 / 2017 50 / 2026-04 110 등) KRX official approximate range 일치 충분

**근거**:
- Bollerslev T., Tauchen G., Zhou H. (2009) "Expected Stock Returns and Variance Risk Premia" RFS 22(11):4463-4492
- CBOE 1993 VIX Whitepaper / 2003 VIX Methodology
- L-247 answer principle 7번 "불확실성 명시" — caveats 보강

## Self-rationalization grep

**Codex 발견 7건**:
1. "However LO Q5 t_NW gross 3.28 + net 3.09 PASS" ← 합리화
2. "However at 15bps×0.95% per-month cost, LO Q5 net SR = 0.825 still strong" ← 합리화 ("still strong" + "자연 흡수")
3. "Pass 6/7 (rank_ic_strict only fail)" ← 합리화 ("only fail")
4. "positive structural breakthrough" ← 합리화
5. "15bps cost 자연 흡수" ← 합리화 ("자연")
6. "본 WT 모두 해소" ← 합리화 ("모두")
7. "borderline FAIL" ← 합리화 ("borderline" minimize FAIL)

**v4 cleanup**: 위 표현 모두 final alpha_package.json에서 제거. v4 narrative는 "ML OOS IC 0.0037 graduation FAIL strict — alpha discovery insufficient under PIT-strict" 직설.

## AX 공리 disposition

- **AX-000** [IMMUTABLE 한계 없음]: PASS — discovery 시도 자체는 valid (한계 인정 ≠ 진척 포기)
- **AX-001 v2** [defense conditional]: N/A (본 WT defense factor 아님)
- **AX-002** [process integrity / 미래참조 동급]: PASS — v4 PIT-strict t-1 lag 적용 + Codex critique 모두 수용 + 합리화 grep cleanup
- **AX-003** [KR value EP_STANDALONE FAIL]: N/A (본 WT VRP volatility family)
- **AX-004** [KR quality_profitability single-sleeve FAIL]: N/A
- **AX-005 v1.2** [KR defense top20 long-only FAIL — EXCLUSION mandate]: PARTIAL ATTENTION — 본 WT는 VRP family로 defense 직접 아니나, multi-sleeve 분리 fix는 admit 시점 mandate (AX-007)
- **AX-007** [single_sleeve_long_only_top20 mechanism break]: N/A — discovery FAIL이므로 admit X
- **AX-008** [verification triangulation 2/3 PASS]: 1/3 (Codex only) — discovery FAIL 시 Architect/Forge follow-up 불필요

## Q-Lead escalate trigger

- HIGH severity ≥ 5: TRIGGERED (Codex 5 HIGH concerns)
- AX hard FAIL ≥ 3: NO
- PIT C1 위반: NO (PIT C9 partial, c4 ACCEPT)
- Codex stance=REJECT + agent agree majority: TRIGGERED

→ **Q-Lead escalate required = TRUE**.

## Final disposition

**Status**: DISCOVERY_FAIL_REJECTED_AGENT_AGREES_CODEX

**Recommendation**:
1. **TERMINATE current VRP cross-section approach** — WT_001 + WT_011 = 2 cycles VRP signal failed in KR top-universe under PIT-strict regime
2. **Pivot to alternative 4th orthogonal source** (WT_001 next_step 일관) — Defense low-vol multi-sleeve (AX-005 v1.2 EXCLUSION) or Commodity (KR ETF) priority
3. **Infrastructure retain**: KRX 옵션 chain 16y direct cache + VKOSPI 자체 재구축 + 4 학술 모형 implementation = 향후 cross-asset / option-derivative research 자원

## L-code 인용 (Memory mandate)

- **L-228** (KR top-universe alpha discovery limit) — 본 WT 결과 동일 패턴 reproducible
- **L-247** (answer principle: 쉬운 답변 금지 + 합리화 표현 grep) — v3 narrative 합리화 7건 발견 후 v4 cleanup
- **L-441** (FRED 1일 lag mandate) — macro/regime indicator t-1 lag 표준
- **L-450** (expanding percentile + 1-day lag) — regime indicator standard
- **L-484** (cost-aware net SR mandate + factor sign aliasing risk) — 본 WT 적용
- **WT_001 inheritance**: predictor lag-1 autocor 0.40 / ML feature leakage / CRISIS anti-hedge 모두 v4에서 honest 재진단

## Quantitative evidence summary (3축)

| Axis | Evidence | Source |
|---|---|---|
| **학술** | BKM 2003 RFS Theorem 1 + Carr-Wu 2009 RFS + BTZ 2009 RFS + Harvey-Liu-Zhu 2016 + Bondarenko 2014 JFE | factor_specs references |
| **L-code** | L-228 / L-247 / L-441 / L-450 / L-484 | this challenge_note |
| **정량** | v3→v4 IC 0.0255→0.0037 (-86%) / t_NW 2.77→0.47 / Q5 net SR 0.825→0.568 / turnover 7.6×→5.48× / strict gates 5/9 PASS | alpha_validation_v4.json |

## v6.0 Codex Critic Round 5단계 흐름 검증

1. ✓ Draft 작성 (alpha_package_draft.json)
2. ✓ Codex 호출 (run_codex_qepm_critic.sh --role=alpha)
3. ✓ Codex response 검토 (REJECT, 8 concerns)
4. ✓ challenge_note 작성 (this document, 학술/L-code/정량 3축, 합리화 grep 0건)
5. → Final alpha_package.json 작성 (v4 REVISE post-Codex)
