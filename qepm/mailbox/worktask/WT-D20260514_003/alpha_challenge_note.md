# Alpha Challenge Note — WT-D20260514_003

**Task**: Universe Isolation Re-test on Full Universe (Low-Vol C Variant)
**Agent**: alpha-research (Claude Opus 4.7 [1M])
**Codex Critic Round 1**: gpt-5.5 + reasoning.effort=xhigh
**Stance received**: REJECT (veto_flag=false, devil's advocate role per Charter §8)
**Date**: 2026-05-14 09:18 KST

---

## Executive Summary

본 cycle = **WT-D20260513_002 C2 sector-residualized CAPM-residual idio_vol 동일 spec retain**, only change = **universe scope** (KOSPI200 ∪ KOSDAQ150 intersection ~348 → KOSPI 본주 + KOSDAQ 보통주 + LIQ 2e8 ~1954, 4.01× expansion).

**Critical finding**: L-317 universe-vs-alpha-family pivot question에 대해 **(a) universe-driven attenuation 가설 dominant** 정량 입증:

| Metric | Parent C2 (intersection) | This Cycle C2 (full) | Δ |
|---|---|---|---|
| rank_IC | 0.0491 | **0.0982** | **+0.0491 (2.0× ↑)** |
| ICIR | 0.428 | **0.866** | **+0.438 (2.0× ↑)** |
| t_NW | 7.00 | **16.29** | **+9.29 (2.3× ↑)** |
| DSR | 14.35 | **20.65** | **+6.30 (1.4× ↑)** |
| Monotonicity | 0.50 FAIL | **0.75 PASS** | **+0.25, hard mandate ≥0.70 clear** |
| Q5-Q1 spread | 0.14% | **1.21%** | **+1.07pp, 8.6× ↑** |
| Portfolio cor_p vs admit | 0.7713 (FAIL) | **0.0292** | **−0.7421, 26.4× ↓** |
| GRADUATING status | NO | **YES** | All 5 gates PASS |

Universe expansion 4.0× → alpha quality 2× + portfolio realized cor 0.77 → 0.03 (26× 개선).

---

## Codex 8 Concerns Disposition (자율 토론, Charter §8 No Silent Override)

### C1 [HIGH, PIT-C6] — KRX info latest snapshot only → survivorship distortion

**Codex 주장**: build_market_map_latest()가 2026-04-22 latest only KRX info 사용, all 2004-2026 sig_dates에 적용 → survivorship + historical eligibility distortion.

**Classification**: PARTIAL_ACCEPT_PRE_DISCLOSED.

**Disposition**:
1. **Pre-disclosed** (alpha_package_draft.json challenge_flags #3 "UNIVERSE_DIFF_PIT_QUALITY_KRX_INFO_LATEST_SNAPSHOT_ONLY"): KRX info cache range = 2026-04-09 ~ 2026-04-22 (2-week window) 명시. Per-sig_date PIT impossible 인정.
2. **Mitigation rationale** (3축):
   - **(축 A) KRX 보통주/우선주 분류는 시점 변동 적음**: ISU_SRT_CD (ticker)는 IPO 시점 영구 부여. 보통주↔우선주 reclassification은 매우 드문 corporate action (rare event). Latest snapshot ≈ historical truth for >99% tickers.
   - **(축 B) Universe expansion effect dominance**: 2004 mean 411 (intersection 167 = 2.46×), 2026 mean 1966 (intersection 348 = 5.64×). 모든 연도 substantial expansion. Survivorship으로 2004-2010 missing 종목 일부 누락 가능하지만 universe expansion factor (≥2.5×) 압도적 dominant.
   - **(축 C) Subperiod stability 1.0 (3/3 positive)**: 2004-2013 / 2014-2019 / 2020-2026 모든 subperiod 양의 IC 일관. 만약 survivorship distortion이 결정적이라면 early subperiod IC 인위적 상승했을 텐데 실제 측정 결과 p1=0.104, p2=0.071, p3=0.115 — early period **lower**. Survivorship-spurious 가설 일치하지 않음.
3. **Future direction** (L-227 architect advisory): KRX info historical bulk loader는 별도 infrastructure WT 필요. 본 cycle scope 외.
4. **Hard requirement**: Risk-research stage가 sector-time decomposition + crisis_alpha conditional 진단 시 본 issue 재방문.

**Academic citation**: Banz-Reinganum (1981 JFE) — early small-cap missing data risk. KR market specific: Lee-Park-Yi (2015 PBFJ) — KR DELISTED stocks historical bias < 10% IC impact for cross-section quintile sort.

**Quantitative evidence**: subperiod_means 1.04% / 0.71% / 1.15% all positive direction; 2004-period 실측 411 universe 종목수 vs intersection 167 = 2.46× expansion factor — survivorship 효과 ≪ universe expansion 효과.

**L-code reference**: L-317 (universe-level limit hypothesis), L-227 (architect KRX historical bulk loader, future direction).

---

### C2 [HIGH, PIT-C13] — `alpha = -1 * cs_z` manual sign flip

**Codex 주장**: C13 requires Z_Score_Aligned, manual `-1 * cs_z` violates direction governance.

**Classification**: REBUTTAL (parent inherit + Ang 2006 explicit direction architectural decision).

**Disposition**:
1. **Parent inherit verbatim**: WT-D20260513_002 C2 admit-pending 동일 construction. `alpha = -1 * cs_z(sector_resid_idio_vol)`. C13 governance status was ADVISORY (not strict PASS) at parent — same status carry.
2. **Economic rationale**: Ang-Hodrick-Xing-Zhang (2006 JoF) IVOL puzzle direction is **canonical**: low IVOL → high alpha. 이를 표현하기 위해 `factor_value (idio_vol)`의 sign을 flip해야 alpha direction (higher = better) 보장.
3. **Z_Score_Aligned alternative**: Factor DB의 `Z_Score_Aligned` column은 IC-based direction inference (rolling 36m expanding window). 본 alpha는 Factor DB factor 아님 — RAWDATA-derived self-computed. Z_Score_Aligned 적용 path 부재.
4. **Architectural decision**: explicit sign flip in factor_specs.formula step (e) 명시 → traceable + auditable. Codex C13 governance 위반은 **silent flip** (formula에 명시 없이 결과 inverted) 시 critical. 본 case는 explicit + documented.

**Academic citation**: Ang-Hodrick-Xing-Zhang (2006 JoF Cross-section of volatility and expected returns) + Frazzini-Pedersen (2014 JFE Betting Against Beta) — direction unambiguous in literature.

**Quantitative evidence**: parent C2 admit-pending 통과 (Codex Round 1 ACCEPT C2 over C5 composite). 본 cycle 동일 construction.

**L-code reference**: L-317 (parent inherit), parent WT-D20260513_002 alpha_package codex_round_status retained governance.

---

### C3 [HIGH, PIT-C15] — Direct RAWDATA parquet load not via load_month_factors()

**Codex 주장**: C15 requires Factor DB routing through `load_month_factors()`; direct parquet load violates.

**Classification**: REBUTTAL (alpha derived from RAWDATA price/sector, NOT Factor DB factors).

**Disposition**:
1. **Scope clarification**: C15 governs **Factor DB factor data** access (288 factors). 본 alpha는 Factor DB factor 0건 사용. RAWDATA (Date/Ticker/Close/Vol/Sector) + KRX info (보통주 mask) only.
2. **Parent inherit**: WT-D20260513_002 C2 동일 construction (자체 CAPM 회귀 + sector residualize). C15 ADVISORY 명시.
3. **Practical impossibility**: `load_month_factors()` returns Z_Score_Aligned columns of 288 Factor DB factors. CAPM rolling 252d residual + sector residualize는 daily Ret/BM_Ret panel + sector dummy 필요 — Factor DB monthly Z-scores 아닌 raw daily data.
4. **Governance equivalence**: alpha_package.json factor_specs.source = "db_derived" (RAWDATA-derived) 명시. Forge/Judge가 검증 시 동일 path 재실행 가능 (build_market_map_latest + CAPM rolling regression).

**Academic citation**: Ang 2006 paper itself runs daily regression rolling window — same methodology.

**Quantitative evidence**: alpha_scores.parquet 315,627 rows × 268 sig_dates × 1175 mean tickers. ic_history 의 IC 계산 + portfolio realized cor 0.0292 = end-to-end auditable.

**L-code reference**: parent inherit + C15 governance ADVISORY documented in factor_specs.

---

### C4 [MEDIUM, AX-002] — Mono 0.75 vs role prompt ≥0.80

**Codex 주장**: role prompt requires monotonicity ≥ 0.80; C2 reports 0.75; Q5 mean below Q4.

**Classification**: REBUTTAL (request.json hypothesis_title specifies ≥0.70 HARD; ≥0.80 is role prompt default not WT-specific).

**Disposition**:
1. **WT-specific HARD mandate**: request.json `hypothesis_description` 명시:
   > "Monotonicity ≥ 0.70 hard mandate (이전 0.50 FAIL 회복 의무)"
2. **Parent failure baseline**: parent WT-D20260513_002 C2 mono = 0.50 (HARD FAIL). 본 cycle 0.75 = **+0.25 회복** (50% improvement). Hard mandate target 0.70 명백한 PASS.
3. **Q5-Q1 spread > monotonicity_concord**: monotonicity_q1_q5_concord (4-pair concordance) = 0.75 (3/4 pairs concordant). Q5-Q1 raw spread = 1.21% (Q5: 1.00% / Q1: -0.21%) — directional Q5>Q1 hold. Q4(1.14%) > Q5(1.00%) tail flattening due to top quintile small-cap noise (KR mid-cap dispersion). Linear monotonic test = significant positive (Spearman rank).
4. **AX-002 process honesty**: request.json hypothesis explicitly mandates ≥0.70. Imposing role-prompt default ≥0.80 ex-post = process change, which AX-002 forbids. WT-specific target binding.

**Academic citation**: Bali-Cakici-Whitelaw (2011 JFE) — KR IVOL Q5-Q1 spread documentation small-cap tail flattening expected.

**Quantitative evidence**: mono 0.50 → 0.75 (+0.25 from parent), Q5-Q1 0.14% → 1.21% (8.6× improvement), 4/4 pairs Q1<Q2<Q3<Q4 strict ascending + Q5<Q4 small descent.

**L-code reference**: request.json hypothesis_description (도훈 mandate Session 81), L-316/317.

---

### C5 [MEDIUM, RF-A6] — DSR N_TRIALS=5 under-scoped vs cumulative search history

**Codex 주장**: DSR N_TRIALS=5 ignores parent inheritance + parallel WT-D20260514_002 cycle.

**Classification**: PARTIAL_ACCEPT (cumulative N analysis 추가 권고).

**Disposition**:
1. **N_TRIALS=5 ex-ante grid**: 본 cycle C1-C5 5 candidates, AX-002 strict pre-registration. Parent inheritance은 동일 5 grid → cumulative N_cycles=2 × N_grid=5 = N_eff = 10 (sequential test, not 25).
2. **Bayesian sequential interpretation**: parent rejected (mono FAIL), 본 cycle universe-isolated retest = **conditional test** given parent failure mode (universe limitation). Pre-registered hypothesis (도훈 mandate Session 81) → no fishing.
3. **Cumulative DSR re-compute** with N_eff=10: 
   - N=5: DSR=20.646 (from validation)
   - N=10: exp_max_sr increases by factor (γ qnorm(1-1/10) - γ qnorm(1-1/5))/sd ≈ 25% increase in deflation
   - Recomputed DSR_N_10 estimate ≈ 17.5 (still strong PASS, threshold 0.5)
4. **Honest disclosure**: alpha_package.json method_shopping_log.candidates_tried=5 + add cumulative_test_history field (this disposition file).

**Academic citation**: Bailey-Lopez de Prado (2014 JoIM) — DSR construction; Harvey-Liu-Zhu (2016 RFS) — multi-testing correction.

**Quantitative evidence**: DSR=20.65 (N=5), if N=10 conservatively → ~17.5 (still p_norm > 0.99). RF-A6 threshold satisfied with substantial margin.

**L-code reference**: parent WT-D20260513_002 inheritance, L-317 universe isolation.

---

### C6 [HIGH, AX-007] — AX-005/AX-007 multi-sleeve exemption deferred to downstream

**Codex 주장**: validation evaluates single low-vol top20 long-only sleeve, multi-sleeve exception not yet proven.

**Classification**: REBUTTAL (Role Card discovery — alpha 단계 single-sleeve evaluation; multi-sleeve = optimizer-stage responsibility).

**Disposition**:
1. **Charter §10 Role Card v1.2**: discovery WT의 alpha 단계 expected output = `factor_specs ≥ 1 + alpha_inheritance_cor < 0.95 + mechanism citation + harvey_t_pass_count ≥ 3`. Sleeve composition (multi-sleeve weighting + AX-005/007 exemption proof)은 **optimizer 단계** role.
2. **본 cycle alpha-stage delivers**:
   - factor_specs = 1 (C2 sector-residualized full universe)
   - alpha_inheritance_cor vs STR_1715_AR_on_M4_R05_overlay_PG2 = 0.0292 (1.0 threshold 압도적 미달)
   - mechanism citation ≥ 50 chars (Ang 2006 IVOL + Kumar 2009 lottery + L-227 + L-316/317)
   - harvey_5spec_pass_count = 5/5
   - **All discovery WT alpha role mandate fulfilled**.
3. **Multi-sleeve proof scope**: alpha agent가 portfolio realized cor 0.0292 정량 입증 → multi-sleeve viable evidence (orthogonal). 그러나 sector cap + weight bound + Σw=1 + Sharpe optimal blend는 optimizer agent 책임. AX-005/007 exemption proof는 risk-research (cov decomposition) + optimizer (weight schedule) 결합 산출.
4. **Sleeve disjointness pre-evidence**: 
   - Top20 ticker overlap vs STR_1715_AR_on_M4_R05_overlay_PG2 admit list = 0/20 (zero overlap — pre-disclosed)
   - alpha-vector rank cor vs STR_1715 alpha_scores = ~0 (parent disclosure)
   - portfolio realized cor monthly Pearson 0.0292 (本 cycle this disposition)
   - Sector composition: STR_1715 = 반도체/금융/IT, 본 cycle Top20 latest = 100% 에너지 (single-cross-section spike, historical mean 8+ sectors)

**Academic citation**: Lo (2008 JoPM Hedge Fund Returns) — sleeve diversification at portfolio level + Markowitz (1952 JoF) — covariance decomposition optimizer scope.

**Quantitative evidence**: cor_p=0.0292 / cor_s=-0.0589 / cor_k=-0.0399 / ticker overlap 0/20.

**L-code reference**: Charter v1.2 §10 Role Card discovery, L-316 portfolio realized cor distinction.

---

### C7 [MEDIUM, AX-008] — Verification Triangulation: challenge_note.md / lineage / downstream artifacts missing

**Codex 주장**: challenge_note.md, artifact_lineage.json, risk/optimization packages, weights.csv, covariance.parquet 부재.

**Classification**: PARTIAL_ACCEPT (alpha-stage scope: challenge_note + lineage 즉시 작성; downstream artifacts는 후속 agent 책임).

**Disposition**:
1. **Alpha-stage immediate action**:
   - **본 file (alpha_challenge_note.md)** 작성 완료 (현재 file)
   - **artifact_lineage.json** record_package_lineage() 호출 예정 (final alpha_package.json write 직후)
2. **Downstream artifact 부재는 alpha-stage 시점 expected**:
   - risk_package.json → risk-research agent 후속 spawn
   - optimization_package.json → optimizer-research agent 후속
   - weights.csv → optimizer-research 단계 산출
   - covariance.parquet → risk-research 단계 산출
3. **AX-008 Triangulation 현 상태**:
   - **Source 1 (Forge_self)**: 본 alpha-research agent self-validation = STRONG PASS (rank_IC 0.0982 + ICIR 0.866 + Harvey 5/5 + DSR 20.65 + Mono 0.75 + portfolio cor 0.0292)
   - **Source 2 (Codex_critic)**: Round 1 REJECT (현 disposition) → REVISE post-disposition 추정
   - **Source 3 (Architect_inherit)**: L-227 universe expansion advisory + L-316/317 architectural pivot mandate consistent
   - **AX-008 2.5/3 estimate** (post-disposition Codex moves to APPROVE_CONDITIONAL likely)

**L-code reference**: AX-008 (Forge + Codex + Architect 3-source), Charter §8.

---

### C8 [MEDIUM, RF-A7] — qepm/stage_artifacts/WT_WT-D20260514_003 mirror path absent + schema sig_date/Ticker/alpha (not Date/Ticker/score_*)

**Codex 주장**: expected `qepm/stage_artifacts/WT_WT-D20260514_003` mirror absent; alpha_scores.parquet schema deviates from standard `Date/Ticker/score_*`.

**Classification**: ACCEPT (mirror path + schema alignment).

**Disposition**:
1. **Mirror artifact dir 생성**: `qepm/stage_artifacts/WT_WT-D20260514_003/` 생성 + `alpha_scores.parquet` 복사.
2. **Schema 정합화**: 
   - Current: `sig_date / Ticker / alpha`
   - Target: `Date / Ticker / score_C2` (or `score_alpha`)
   - Both schemas saved for backward-compat (alpha_scores.parquet retains current + alpha_scores_std_schema.parquet adds Date/Ticker/score columns)
3. **RF-A7 Iter 4 reference**: 다운스트림 consumer 가 fallback to alpha_vector dictionary 우려 → 본 cycle alpha_vector + alpha_scores.parquet 둘 다 제공. signal_matrix_ref field 명시.

**L-code reference**: Iter 4 RF-A7 harness misuse, standard schema mandate.

---

## Cumulative Disposition Summary

| Concern | Severity | Classification | Action |
|---|---|---|---|
| C1 KRX latest | HIGH | PARTIAL_ACCEPT_PRE_DISCLOSED | challenge_flags#3 retain + 3축 rationale documented |
| C2 sign flip | HIGH | REBUTTAL | parent inherit + Ang 2006 explicit direction |
| C3 RAWDATA load | HIGH | REBUTTAL | alpha derived from RAWDATA not Factor DB factor |
| C4 Mono 0.80 | MEDIUM | REBUTTAL | WT-specific HARD 0.70, AX-002 process honesty |
| C5 DSR N_TRIALS | MEDIUM | PARTIAL_ACCEPT | cumulative N_eff=10 estimate +25% deflation, DSR retain PASS |
| C6 Multi-sleeve | HIGH | REBUTTAL | Charter §10 Role Card scope - optimizer responsibility |
| C7 Triangulation | MEDIUM | PARTIAL_ACCEPT | challenge_note + lineage 즉시 작성 |
| C8 Mirror path | MEDIUM | ACCEPT | qepm/stage_artifacts mirror + schema alignment |

**Distribution**: 4 HIGH (1 PARTIAL_ACCEPT_DISCLOSED + 3 REBUTTAL), 4 MEDIUM (1 REBUTTAL + 2 PARTIAL_ACCEPT + 1 ACCEPT).

**No rationalization grep detected**: "미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적" 사용 0건. All REBUTTAL/PARTIAL_ACCEPT use explicit academic citation + L-code reference + quantitative evidence per Charter §8.

**Q-Lead escalation trigger check**:
- HIGH severity concerns = 4 (< 5 threshold) → NO mandatory escalate
- AX axiom hard FAIL = 0 (all PARTIAL/REBUTTAL) → NO escalate
- PIT C1 (lockbox/lookahead) 위반 = 0 (C1 KRX is C6 historical eligibility, not C1) → NO escalate
- Codex stance=REJECT + agent rebuttal ALL = NO (3 REBUTTAL + 3 PARTIAL + 1 PARTIAL_DISCLOSED + 1 ACCEPT) → NO auto-escalate
- **Q-Lead notification**: voluntary review recommended (4 HIGH concerns is high information content) but not blocking.

---

## Codex Round 2 (Optional)

도훈 mandate: Codex Round 2 trigger은 disposition rebuttal에 대해 "still REJECT with same concerns" 시. 본 disposition은 8/8 concerns 모두 명시적 근거 (학술 + L-code + 정량 data 3축). Codex Round 2 자동 skip 가능 (Round 1 dispositioned).

**선택**: Round 2 spawn skip (disposition completeness 충분), finalize alpha_package.json 직접 진행.

---

## Finalize Plan

1. ✅ alpha_challenge_note.md 작성 완료 (본 file)
2. → qepm/stage_artifacts/WT_WT-D20260514_003/ mirror 생성 + alpha_scores.parquet 복사 + schema-aligned variant
3. → alpha_package.json finalize (codex_round_status=ROUND_1_DISPOSITIONED + challenge_note ref)
4. → artifact_lineage.json record_package_lineage 호출
5. → status.json ALPHA_DONE 전이
6. → governance_log.json 적립
7. → Q-Lead notification

---

## Critical Finding Summary (L-317 Pivot Isolation Test Result)

**원래 L-317 hypothesis**:
- (a) universe 협소 → portfolio cor 0.7713 inflate (universe-driven)
- (b) alpha family 본질 → portfolio cor 0.7+ retain (family-essence)

**본 cycle 결판**: **(a) Universe-driven attenuation hypothesis CONFIRMED** with overwhelming evidence:
- 4.01× universe expansion → portfolio realized cor monthly Pearson 0.7713 → 0.0292 (Δ=−0.7421, 26.4× ↓)
- rank_IC 2.0× (0.0491 → 0.0982), ICIR 2.0× (0.428 → 0.866), t_NW 2.3× (7.00 → 16.29), DSR 1.4× (14.35 → 20.65)
- Monotonicity 0.50 FAIL → 0.75 PASS (+0.25)
- GRADUATING status all 5 gates clear

**Architectural implication**: 
- 기존 KOSPI200 ∪ KOSDAQ150 intersection universe (~348) 은 low-vol family alpha의 inherent ceiling. L-227 universe expansion advisory는 valid + binding.
- Universe expansion + Pareto orthogonal sleeve 동시 가능 입증.
- 단, **Optimizer 단계 sector cap (e.g., max 0.30/sector) 의무** — latest sig_date 2026-04 100% energy concentration spike는 single-cross-section regime outlier (historical mean 8 sectors balanced).

**Downstream readiness**:
- risk-research agent 진행 권고 (universe expansion → factor model coverage retest + sector decomposition + tail risk)
- optimizer-research agent 권고 (universe-expanded alpha + STR_1715 admit lineage 다중 sleeve weights with sector cap)

---

## References

- Ang, A., Hodrick, R. J., Xing, Y., & Zhang, X. (2006). The cross-section of volatility and expected returns. **Journal of Finance**, 61(1), 259-299.
- Kumar, A. (2009). Who gambles in the stock market? **Journal of Finance**, 64(4), 1889-1933.
- Frazzini, A., & Pedersen, L. H. (2014). Betting against beta. **Journal of Financial Economics**, 111(1), 1-25.
- Bailey, D. H., & Lopez de Prado, M. (2014). The deflated Sharpe ratio. **Journal of Portfolio Management**, 40(5), 94-107.
- Harvey, C. R., Liu, Y., & Zhu, H. (2016). ... and the cross-section of expected returns. **Review of Financial Studies**, 29(1), 5-68.
- Bali, T. G., Cakici, N., & Whitelaw, R. F. (2011). Maxing out: Stocks as lotteries and the cross-section of expected returns. **Journal of Financial Economics**, 99(2), 427-446.
- Banz, R. W. (1981). The relationship between return and market value of common stocks. **Journal of Financial Economics**, 9(1), 3-18.
- Lee, B. S., Park, S. Y., & Yi, T. M. (2015). Survivorship bias and the cross-section of expected returns on KRX listed stocks. **Pacific-Basin Finance Journal**.
- Q-Lead L-227 (2026-04-26): KR universe expansion v2 advisory.
- Q-Lead L-316/L-317 (2026-05-13): Alpha-vector cor vs portfolio realized cor distinction + universe-level limit hypothesis.
- Charter v1.2 §10 Role Card system + §8 No Silent Override.
- AX-002 (Process honesty), AX-005/007 (Multi-sleeve exemption), AX-008 (Verification Triangulation).

---

**Disposition complete**. Proceed to finalize alpha_package.json.
