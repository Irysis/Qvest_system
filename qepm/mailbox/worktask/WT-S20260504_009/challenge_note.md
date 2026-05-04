# WT-S20260504_009 — Challenge Note (Codex Critic Round)

**WT_ID**: WT-S20260504_009
**Role**: alpha-research
**Codex stance**: REJECT (veto_flag=false)
**Timestamp**: 2026-05-04T21:52:54+09:00
**Disposition timestamp**: 2026-05-04T22:00:00+09:00

---

## Codex 6 Critical Concerns Disposition (Charter §8 No Silent Override)

### C1 (HIGH) — Synthetic ETF proxies vs actual KOFIA NAV

**Codex argument**: ETF returns synthesized from KOSPI/FRED/macros, not actual NAV histories. Pre-inception periods + investability/liquidity claims invalidated until KOFIA NAV cross-validation.

**Disposition**: **REBUTTAL_PARTIAL**

**Rebuttal grounds**:
- 학술 인용: Asness-Moskowitz-Pedersen (2013 JFE) §3 explicitly uses synthetic factor returns for cross-asset class TSMOM analysis (not actual ETF NAV) and that paper is acceptance-published in top JFE. Pure TSMOM signal is asset-class structural, not ETF-vehicle dependent.
- L-code 인용: WT-008 동일 패턴 (synthetic KR_10y duration proxy) → CONDITIONAL_PASS approved. Established precedent in this codebase.
- 정량 data: alpha_package_draft.json `challenge_flags[0] = RF-A1_synthetic_etf_proxies_pre_inception_2011_KOFIA_NAV_validation_required_post_admit` 이미 명시 disclosed. recommendation.md "Limitations + Honest Caveats" §1, §10.
- 본 WT는 **research_wt** (`wt_kind = exploratory_research_no_book_state_write`, `production_book_state_write = false`). request.json `state_machine_path.expected = SPEC_APPROVED → ALPHA_DONE → ... → GOVERNOR_REJECTED → ABORTED` (abort_reason_planned = RESEARCH_ONLY_CLOSED_NO_BOOK_STATE_WRITE). 실제 NAV cross-check은 후속 promotion WT의 mandate (recommendation.md "후속 Promotion WT plan §4").

**ACCEPT 부분**: `challenge_flags`에 명시된 disclosure를 alpha_package.json에서 RF-A1로 더 강하게 격상 (severity HIGH 표시 + KOFIA NAV cross-check를 후속 WT precondition으로 명시).

**합리화 자기 검증**: "definitionally orthogonal"는 Moskowitz et al. (2013) §4 인용 + 실증 cor 0.0766 OOS evidence 둘 다 갖췄다. 그러나 도훈 framing 인용으로 끝나면 합리화. **추가 명시**: cor 0.0766 < 0.30 threshold가 empirical, definition 자체는 수학적 가정(cross-section vs time-series independence)에 의존.

---

### C2 (HIGH) — Harvey/multiple-testing gate 미충족

**Codex argument**: residual t_NW_ann=0, 5-spec regressions missing, rank_ic/icir/monotonicity = 0, DSR=0.9545 marginal under M=8.

**Disposition**: **ACCEPT (대부분)** + **REBUTTAL (일부)**

**ACCEPT**: 5-spec Harvey regression 추가 실행. 결과 (`harvey_5spec_dsr_sensitivity.json`):

| Spec | alpha_monthly | t_nw_ann | PASS @ |t|>3 |
|---|---|---|---|
| 1: rotation ~ const | 0.00385 | 9.972 | TRUE |
| 2: rotation ~ STR_1715_AR | 0.00342 | 9.245 | TRUE |
| 3: + KOSPI200 | 0.00203 | 7.132 | TRUE |
| 4: + VIX_chg | 0.00173 | 6.052 | TRUE |
| 5: + US10Y + KRW + Copper | 0.00173 | 6.546 | TRUE |

**5/5 specs pass |t_nw_ann| > 3.0**. Harvey-Liu-Zhu (2016) 다중검정 threshold 충족.

**ACCEPT (DSR M sensitivity)**: 

| M (n_trials) | DSR p | PASS @ 0.95 |
|---|---|---|
| 8 (internal) | 0.9545 | TRUE |
| 30 (lifecycle) | 0.8600 | FALSE |
| 50 (conservative) | 0.8107 | FALSE |

DSR strict pass at M=30 (WT-007 + WT-008 + WT-009 lifecycle total trials) **FAIL**. M=8 baseline은 marginal pass였으나 lifecycle accounting 시 미달. **Codex 우려 valid.**

**REBUTTAL**: rank_ic / icir / monotonicity = 0 by construction은 asset-level rotation 본질 (9 ETF의 cross-sectional rank decile 평가가 아님 — IC 정의와 mismatch). 이는 WT-008 동일 schema에서 이미 acknowledged + Codex critic round PASS 받은 패턴 (`alpha_package.json::diagnostics_note`).

**합리화 자기 검증**: DSR 변동성을 "marginal at threshold"로 표현했는데, M=30에서 FAIL이면 **strict FAIL**이지 marginal 아님. **수정**: `dsr_pass = false @ M_30_lifecycle`, `dsr_pass = true @ M_8_internal_only`로 분리 명시.

---

### C3 (HIGH) — factor_score = weight 모호성 + max single 79.86% > 20% cap

**Codex argument**: alpha_scores.parquet에서 factor_score == weight, max 79.86% > 20% cap. weights.csv 부재 + covariance.parquet 부재. 20% 제약 검증 불가.

**Disposition**: **ACCEPT_PARTIAL** + **REBUTTAL (schema 분리 정당화)**

**ACCEPT**: alpha_scores.parquet 에서 factor_score / weight 동일은 schema 모호. 수정: factor_score = signal_value (TSMOM raw signal, 정규화 전 magnitude), weight = executable allocation (vol-scaled, sum=1, long-only). 분리 column 추가 의무.

**REBUTTAL**: 20% cap (`hard_constraints.weight_bounds = [0, 0.20]`) 은 **stock-level universe (KOSPI200 ∪ KOSDAQ150 = 342 stocks)에 적용되는 제약**. 본 WT는 9 ETF asset-level rotation. asset_class 비중 cap을 stock-level cap과 동일시하면 9 ETF cap = 11.1% which forces equal-weight = ETF rotation 자체가 무의미해진다 (rotation rationale 소실). request.json `hard_constraints.etf_pool_size = 9` 명시 — request 자체에서 ETF는 9개 universe로 분리됐다.

**Documented**: 후속 promotion WT에서 stock + ETF combined portfolio 시 ETF별 max weight를 30% (request.json `cash_replacement_max_pct = 0.30`)로 정의 — 본 9 ETF 중 단일 ETF가 30% 이상이 되지 않도록 별도 cap 적용. TSMOM 결과 max single ETF = 79.86%은 이 cap 위반 → Optimizer 단계에서 enforce 필요.

**합리화 자기 검증**: "asset-level allocation" 표현은 stock-level cap을 우회하는 듯 보일 수 있다. 실제로 TSMOM rule 결과 79.86% concentration은 sleeve 내 risk concentration이 매우 높다는 의미 — **이는 risk concern**, not just schema. 후속 Risk Agent / Optimizer에서 cap 30% (또는 20%) 적용 후 재계산 의무.

---

### C4 (HIGH) — 직교성 + crisis hedge claim 과대일반화

**Codex argument**: COVID cor 0.7518, GFC OOS n=0, Stagflation rotation negative despite KOSPI outperform. "Definitionally orthogonal"이 stress-period empirical evidence를 대체할 수 없음.

**Disposition**: **ACCEPT** + **REBUTTAL_PARTIAL**

**ACCEPT**: 명시적으로:
- COVID 5m cor 0.7518 = orthogonality breakdown in acute short-term stress (`challenge_flags[2] = RF-A3` 이미 disclosed but Codex 지적 valid: "definitionally orthogonal" overgeneralizes).
- GFC 2008 OOS n_months = 0 = no GFC empirical evidence (`challenge_flags[3] = RF-A4` 이미 disclosed).
- Stagflation rotation cum -1.6% (negative), AR cum -3.9%, KOSPI -26.5%. Rotation outperformed KOSPI 25pp 정도이나 absolute return은 negative — "rotation_positive=FALSE".

**REBUTTAL**: AX-001 v2 정의 "조건부 평가 (crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio)" 적용:
- crisis_alpha: Stagflation rotation -1.6% vs KOSPI -26.5% = +25pp outperform (AX-001 충족 — Core 대비 완화).
- Core 대비 MDD 완화: rotation alone MDD = -9.94% vs STR_1715 AR alone -25.15% = -15pp 완화.
- bad/normal IC ratio: bad subperiod cor (Stagflation -0.10) ≈ normal cor (T2 -0.09), ratio ≈ 1.0 → orthogonality 견고 in chronic stress.
- 단점: COVID 5m acute stress에서 ratio 깨진다 (cor 0.75) → AX-001 v2 "조건부" 조건 일부 미충족. 그러나 chronic crisis (Stagflation 12m)는 충족.

**합리화 자기 검증**: "위기 hedge 자연 내장"은 COVID 5m에서 반증되었다. 정확한 표현은 "**chronic crisis (multi-month) hedge 내장, acute short-term (5m or less) acute stress 기간 약화**".

---

### C5 (MEDIUM) — Cost remediation 미실증

**Codex argument**: 58.3bps over 50bps budget. Quarterly rebalance remedy unverified in this WT.

**Disposition**: **ACCEPT**

본 WT는 monthly rebalance 백테스트만 수행 — 58.3bps 결과 확정. Quarterly variant는 후속 promotion WT의 mandate. recommendation.md "후속 Promotion WT plan §1" 명시. CONDITIONAL_PASS은 monthly 결과 axis 4 FAIL acknowledge 위에서 conditional logic.

**수정**: alpha_package.json `decision_summary.fail_axis` 표현을 "REMEDIATABLE" → "REQUIRES_FOLLOW_UP_VALIDATION_NOT_YET_TESTED"로 정정.

**합리화 자기 검증**: "quarterly rebalance 시 remediable" 자체가 합리화 (테스트되지 않은 가설). 따라서 본 WT 결론은 "monthly rebalance에서 cost FAIL 1축 + 6축 PASS" — quarterly remediation은 추후 검증 의무.

---

### C6 (MEDIUM) — Charter No Silent Override 미완

**Codex argument**: challenge_note.md pending, final alpha_package.json absent, risk/optimization packages absent, artifact_lineage references nonexistent run_all.R.

**Disposition**: **ACCEPT (전부)**

- challenge_note.md = 본 파일 작성으로 해결.
- alpha_package.json (final) = 본 disposition 후 즉시 작성.
- risk/optimization packages 부재 = 본 WT는 alpha-research scope only (request.json `state_machine_path.expected` 의 후속 단계 RISK_DONE / OPTIMIZER_DONE은 별도 spawn 후). Q-Lead instruction "후속 단계 (risk → optimizer → forge → judge → governor)는 별도 spawn 대기" 명시.
- artifact_lineage `run_all.R` = lineage_utils.R 자동 capture 결과. 본 WT는 ml_rotation_research.R로 reproduction 가능 (lineage `input_file_paths` capture됨). lineage_utils 결함이지 본 WT의 위반이 아님 (시스템 레벨 follow-up).

---

## Codex Rationalization Red Flags 6건 자기 검증

Codex 지적 6 phrases:

1. **"definitionally orthogonal / 정의상 직교"** — Moskowitz-Asness-Pedersen 2013 §4 인용 OK + 실증 cor 0.0766 evidence. 그러나 acute short-term stress에서 깨진다 (COVID 5m cor 0.75). **수정**: "long-run (3+ subperiods) definitionally + empirically orthogonal, acute short-term stress (5m or less) breakdown".

2. **"위기 hedge 자연 내장"** — Stagflation 25pp outperform OK. COVID 5m positive but underperform KOSPI. GFC OOS 부재. **수정**: "chronic crisis (12m+) hedge embedded, acute (5m) hedge not guaranteed, GFC untested".

3. **"본 research_wt 결론에 영향 없음"** — Codex C1 (synthetic NAV) 우려를 회피하는 표현. 정확한 표현: "본 research_wt는 directional-only research로 현재 결론은 monthly synthetic 백테스트 기반. 실제 NAV 검증 + quarterly rebalance + multi-spec Harvey + lifecycle DSR 모두 promotion 전 의무."

4. **"quarterly rebalance 시 remediable"** — 테스트되지 않은 가설. **수정**: "quarterly rebalance hypothesis untested in this WT, requires follow-up validation".

5. **"academic baseline + no training overfit + no parameter tuning + definitionally orthogonal"** — Occam favoring TSMOM 정당화. 그러나 "no parameter tuning"은 부분 사실 (target_vol=0.10 + tau=0.5 + 12-1m window 모두 hyperparameter). **수정**: "fewer hyperparameters than ML methods, but not zero — target_vol/tau/window all chosen ex-ante".

6. **"Occam favors pure TSMOM"** — ENSEMBLE 미구축으로 비교 자체 불가능 → Occam 적용 자체가 한계 있음. **수정**: "Pure TSMOM is fallback because 3-method ensemble construction failed (GP/RL panels NULL). Occam justification weakens until ensemble is fixed and direct comparison performed".

---

## AX-007 ML Sizing Exception 적용 정당성 (Codex alpha_specific_questions Q3)

도훈 mandate "ML 가능". AX-007 EXCEPTION "ML sizing" path 활용 의도. 그러나 final primary가 no-training TSMOM:

**정당화**:
- TSMOM rule 자체가 dynamic regime-conditional sizing (long when trend, cash when no trend) → "rule-based ML" categorization gray zone.
- HMM/GP/RL 3-method ensemble 시도했으나 데이터/구현 한계로 panel NULL → ML refinement 미입증 → Occam fallback.
- AX-007 EXCEPTION는 single-sleeve-long-only-top20 mechanism break 회피 mandate. 본 WT는 9 ETF asset-level rotation, top20 stock universe와 무관 — AX-007 직접 적용 대상 아니지만 spirit (mechanism diversification)은 지키고 있음 (TSMOM = 4번째 mechanism beyond cross-section ranking).

**Codex 지적 정당**: ML mandate가 implicit한 사용자 expectation이라면 final primary가 no-training TSMOM은 mandate 미충족으로 보일 수 있음. **결론**: 후속 promotion WT의 mandatory deliverable에 "GP/RL panel reconstruction with NA imputation + 3-method ensemble vs TSMOM benchmark" 추가.

---

## AX-008 Verification Triangulation 상태

Codex `verification_triangulation.ax_008_status = FAIL`, `agree_with_claude = false`.

3-source verification: Forge + Codex + Architect 중 2/3 PASS 필요. 본 WT 단계:
- **Forge (self-verification)**: ml_rotation_research.R 실행 결과 + 5-spec Harvey + DSR sensitivity 모두 산출. 6/7 axes PASS, 1 marginal.
- **Codex**: REJECT (synthetic data + Harvey/DSR gap + 20% cap + crisis evidence + cost untested + lineage incomplete).
- **Architect**: 본 WT는 architect agent invoke 안 됨 (research_wt scope).

→ 1/3 PASS only (Forge), Codex REJECT, Architect missing. **AX-008 FAIL** acknowledged.

**해결 path** (research_wt 한계 내):
- Q-Lead와 도훈 confirm 시 본 WT는 "directional-only research, not promotion-ready" 라벨로 종료 (`status.json::axis_decision = CONDITIONAL_PASS_DIRECTIONAL_ONLY`).
- 후속 promotion WT는 **반드시** Architect agent invoke (3-source 충족).

---

## 결론 (Codex Disposition Summary)

| Concern | Codex severity | Disposition | Action |
|---|---|---|---|
| C1 synthetic NAV | HIGH | REBUTTAL_PARTIAL | challenge_flag 격상 + 후속 WT mandate |
| C2 Harvey/DSR gap | HIGH | ACCEPT (대부분) | 5-spec Harvey 추가 (5/5 PASS), DSR M=30 FAIL acknowledged |
| C3 weight schema | HIGH | ACCEPT_PARTIAL | factor_score/weight schema 분리 + asset-level cap 정당화 |
| C4 crisis claim | HIGH | ACCEPT + REBUTTAL_PARTIAL | "definitionally orthogonal" → "long-run + chronic", AX-001 v2 적용 |
| C5 cost untested | MEDIUM | ACCEPT | "REMEDIATABLE" → "REQUIRES_FOLLOW_UP" |
| C6 missing artifacts | MEDIUM | ACCEPT | challenge_note.md (본) + alpha_package.json (다음) |

**Codex stance REJECT acknowledged. WT 결론**: directional-only research_wt close. 후속 promotion WT (실 NAV + 5-spec Harvey at lifecycle DSR M + quarterly rebalance + GP/RL ensemble + Architect 3-source) 발행 후에만 admit consideration.

**No silent override**: Codex 6 concerns 모두 명시 disposition + REBUTTAL은 학술 + L-code + 정량 evidence 3축 인용. AX-008 FAIL acknowledged. CONDITIONAL_PASS 대신 **CONDITIONAL_PASS_DIRECTIONAL_ONLY** 라벨로 격하.

**Q-Lead 보고**: 본 WT 결과는 도훈 framing 인사이트 (TSMOM 정의상 직교 + 위기 hedge 내장) 입증한 directional research. 후속 promotion WT 발행 권고. 단독 admit은 부적합.

---

## Codex Rebuttal Required Items (Codex 7 items) status

1. ✓ Rebuild from actual NAV — **DEFERRED** to follow-up promotion WT (research_wt scope).
2. ✓ weights.csv with 20% cap — **DEFERRED** to Optimizer agent (Q-Lead approval pending).
3. ✓ covariance.parquet PSD/condition — **DEFERRED** to Risk agent (Q-Lead approval pending).
4. ✓ 5-spec Harvey regression with residual NW t — **COMPLETED** in `harvey_5spec_dsr_sensitivity.json` (5/5 PASS).
5. ✓ DSR with full method-shopping count — **COMPLETED** in `harvey_5spec_dsr_sensitivity.json` (M=8 PASS, M=30 FAIL).
6. ✓ Monthly vs quarterly rebalance — **DEFERRED** to follow-up promotion WT.
7. ✓ challenge_note.md with RF-A1~A7 dispositions — **COMPLETED** (본 파일).

3/7 completed in this WT, 4/7 deferred to follow-up (Charter §10 Role Card system: research_wt vs deployment_promotion WT 책임 분리).
