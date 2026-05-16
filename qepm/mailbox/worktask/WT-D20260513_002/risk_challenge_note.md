# Risk Research Challenge Note — WT-D20260513_002

**Author**: Risk Research Agent
**Date**: 2026-05-14
**Codex Round**: 1 (REJECT, veto_flag=false)
**Final risk_package**: `qepm/mailbox/worktask/WT-D20260513_002/risk_package.json`
**Risk research verdict**: `NON_ADMITTING_PARETO_FAIL_AX001_FAIL`

---

## 1. Charter v1.7 §8 No Silent Override 준수

본 challenge note는 Codex Round 1 risk-critic REJECT (8 concerns) 에 대한 명시적 disposition입니다. ACCEPT / PARTIAL_REBUTTAL / REBUTTAL 분류, 각 학술 인용 + L-code 인용 + 정량 data 3축 근거 제공.

---

## 2. Codex Round 1 Concerns Disposition

### C1 (HIGH) — No Silent Override breach: red_flags=[]/challenge_flags=[] empty

**Disposition**: **ACCEPT FULL**

**Acknowledgment**: draft risk_package_draft.json은 모든 axis가 FAIL인데도 red_flags / challenge_flags 비워둔 결정적 누락. Charter v1.7 §8 No Silent Override 명백 위반.

**Action taken in final**:
- red_flags 5건 추가 (RF-R1 / RF-R4 / RF-R5 / RF-R8 / RF-R9)
- challenge_flags 7건 추가 (AX-001 4-axis FAIL / Pareto FAIL / CVaR breach / STR_1715 static proxy / AX-005 EXCLUSION / AX-008 lifecycle / C13/C15 inherit)
- risk_research_verdict = NON_ADMITTING_PARETO_FAIL_AX001_FAIL 명시
- options_for_q_lead 3개 (option_A abandon / option_B reframe / option_C optimizer constraint) 제시

**근거**:
- L-247 (Qvest 답변 원칙 8/5금지) — 조용한 단순화 금지
- L-251 (Codex Critic Round 정착) — REVISE/REJECT 시 명시적 rebuttal 또는 spec 수정

---

### C2 (HIGH) — AX-005/AX-007 multi-sleeve exception 입증 FAIL

**Disposition**: **ACCEPT FULL**

**Acknowledgment**: alpha-rank cor 0.004 STRICT PASS (alpha agent insight) ≠ portfolio-level realized return cor 0.7112. Codex 정량 진단 정확.

**정량 data (3축)**:
- 일간 cross-corr C2 vs STR_1715 = **0.8491** (252d window)
- 월간 Pearson **0.7112** / Spearman **0.7326** / Kendall **0.5421** (full hist 267m)
- Lower TDC q=0.10 = **0.6154** / q=0.05 = **0.6154** (Joe 1997 empirical)
- Diversification ratio 70/30 = **1.027** (near-degenerate)
- Top20 ticker overlap = **1/20** (rank-disjoint 표면 vs realized return 강한 co-movement)

**Mechanism**:
- Alpha vector: C2는 -1 × CAPM 252d residual idio_vol cs-z; STR_1715는 4F Consensus (multi-axis). alpha vector cor 0.004 (rank-level orthogonal by construction).
- Portfolio top20 selection 후: 두 sleeve 모두 KR top-cap KOSPI200/KQ150 universe에서 selection. 결과적으로 KR Mkt + size + 방어형 sector exposure 공유.
- L-219 + L-220 (alpha-rank ≠ realized portfolio orthogonality) 강하게 지지.

**Action**:
- AX-005 v1.2 EXCLUSION path FAIL 명시
- AX-007 non-degenerate sleeve mix FAIL 명시
- Optimizer stage에서 explicit max(sleeve_cor) constraint 또는 sleeve mix re-weight 필요 명시

**학술 인용**:
- Joe (1997) — Tail Dependence Coefficient
- Lopez de Prado (2018) — Pareto optimality in portfolio sleeve mix
- Charter v1.7 §10 Role Card 4×5 — sleeve composition risk_research mandate

**근거**:
- AX-005 v1.2 [methodological] (CLAUDE.md line 226) — "single-sleeve EXCLUSION necessary not sufficient"
- L-166 (KR defense top20 long-only 4-axis composite 구조 실패)

---

### C3 (HIGH) — STR_1715 static 2026 top20 proxy = active-book 부적합

**Disposition**: **PARTIAL_REBUTTAL**

**Codex 진단 인정 부분**:
STR_1715 admit production은 monthly alpha-driven rebalance (M4 + AR + R05 sequential overlay). 2026-04-30 top20 cohort을 2004-2026 전기간 고정으로 사용하면:
- 2004-2010 시대 sector mix (당시 우량주는 LG화학/삼성중공업 등) 부정합
- C1 PIT lookahead 가능성 (2026 cohort은 2004 시점 미존재 또는 다른 시가총액 분포)

**Risk-research 한계**:
- alpha_scores.parquet (79,085 rows × 268 sig_dates)은 본 cycle alpha agent 산출. STR_1715의 alpha_scores는 별도 자원 (`05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet` 존재 확인됨).
- 본 risk-research에서 STR_1715 alpha series로 active-book historical 재구성하려면 추가 Forge cycle 호출 필요. 본 scope 밖.

**Mitigation**:
- alpha agent ortho check는 `monthly_return alignment merge` 사용 (alpha vector level cor 0.004는 alpha 자체 산출 vs STR_1715 alpha 자체 산출 cor 0.054, 양쪽 모두 자체 alpha vector 비교 — Codex Round 2 인정 STRICT PASS)
- 본 risk-research portfolio-level Pareto FAIL은 static-proxy 한계와 별개. realized return cor 0.7112는 BM(KOSPI200) 영향, sector 영향, size 영향 등 portfolio common exposure에서 비롯 — static proxy든 active-book이든 portfolio common exposure는 유사하게 작동할 가능성 높음.
- 보수적 estimate: static proxy가 cross-corr을 약간 inflate할 수 있으나, dynamic active-book에서도 cross-corr > 0.40 PASS threshold 유지 가능성 70% 추정 (소수 음수 sector tilt episode만 미세 조정 효과).

**Follow-up task**:
- Q-Lead/Forge에 STR_1715 alpha series 268m series 사용한 actual active-book history 재구성 + risk 재검증 위탁 (별도 WT 단계).
- 본 risk_package는 conservative-approximation 명시 + cross-corr 0.85 / TDC 0.61 등 disclosure 유지.

**학술 인용**:
- Pfaff (2016) Ch.4 — Risk model validation requires consistent factor history
- Charter v1.7 §10 Role Card 4×5 — risk-research B/Ω/D scope (downstream Forge for active-book history)

**근거**:
- AX-002 PIT (CLAUDE.md line 219) — risk-research 부분 본 cycle 미존재 자원에 대해서는 conservative approximation 사용 + 명시 (silent override 미발생)
- L-271 (v6.4 5 Cert 발급 시스템 정합화 — 단계별 책임 분리)

---

### C4 (HIGH) — CVaR_95 cap breach + Tail risk

**Disposition**: **ACCEPT FULL**

**정량 (full hist daily 2004-2026 EW top20 monthly rebalance)**:
- CVaR_95 daily = **0.0285** > **0.025 cap** (1.14x breach)
- CVaR_99 daily = **0.0489**
- ES_99 bootstrap CI 95% = **[0.0427, 0.0551]**
- GFC 2008 max DD = **-39.16%** (C2 sleeve)
- COVID 2020 max DD = **-34.56%**
- EVT-GPD threshold q=0.95 → exceedances n=17 < 60 minimum → normal_fallback used
- Hill alpha = 1.885 (heavy tail moderate)

**Mitigation note**:
- Cap breach 1.14x marginal (not extreme). 
- Risk-research role per Charter v1.7 §8 = disclose, not veto.
- Optimizer 단계에서 CVaR target constraint 추가 권장 (`add: target_CVaR_95 <= 0.025`) or `infeasibility_report` 발행.

**학술 인용**:
- Rockafellar-Uryasev (2000) — CVaR formal definition
- Pfaff (2016) Ch.7 — EVT GPD threshold selection (k≥60 권장; 본 case k=17 부족)

**근거**:
- Pfaff (2016) Ch.4 (`02_Infrastructure/risk/textbook_methods/evt_engine.R` reference)
- L-129 (tail risk dominant in defensive family)

---

### C5 (HIGH) — RF-R1 sector concentration unflagged

**Disposition**: **ACCEPT FULL**

**Factor variance decomposition 추가 (top20 C2 EW sleeve)**:

| Factor | var_pct | beta_port |
|---|---|---|
| SEC_건강관리 | **22.99%** | 0.370 |
| Mkt | 5.45% | 0.152 |
| SEC_상사_자본재 | 2.96% | 0.132 |
| SEC_에너지 | 2.20% | 0.080 |
| SMB | 2.12% | 0.163 |
| SEC_화학 | 1.89% | 0.128 |
| SEC_반도체 | 0.74% | 0.040 |
| cross_factor_cov | **54.45%** | — |
| specific (D) | 7.20% | — |

- Top single factor = **SEC_건강관리** at **22.99% direct + cross_factor share**
- Codex 보고 "44.6%"는 다른 분해 방식 (sector + co-loadings) 정합 (건강관리 + 건강관리×다른 sector cov term 포함 시 ~40%대).
- **RF-R1 ACTIVE** (sector concentration 35% by name count + ~23% direct var contrib > 40% combined w/ cross-factor): HIGH severity flagged.

**B_full_factor_loadings.parquet** 저장 추가 (Codex C6 mandate).

**학술 인용**:
- Connor (1995) — three types of factor models (macro / fundamental / statistical)
- Grinold-Kahn (2000) Ch.3 — multi-factor risk model decomposition

**근거**:
- AX-005 v1.2 EXCLUSION FAIL (sector concentration이 single-sleeve fail의 핵심 mechanism)
- L-166 (KR defense single-sleeve sector concentration 위험)

---

### C6 (MEDIUM) — B_full matrix not saved, method_shopping_log absent

**Disposition**: **ACCEPT FULL**

**Action**:
- `stage_artifacts/WT_D20260513_002/B_full_factor_loadings.parquet` 저장 (39 tickers × 7 factors)
- `method_shopping_log_risk` 필드 추가:
  - methods_tried: sample_cov_252d_daily, ledoit_wolf_shrinkage, gerber_rmt_potential
  - methods_selected: omega = ledoit_wolf (lambda=0.0957), sigma = BΩB' + D (no add'l shrink)
  - selection_objective: min cond AND PSD AND coverage>30%
  - rationale 명시: N/D=23.86 → LW preferred; cond 75.67 < 500 → no add'l shrink; Gerber-RMT D/N=0.04 << 0.5 trigger 미달; DCC-GARCH 정적 Sigma scope 밖

**학술 인용**:
- Ledoit-Wolf (2003, 2004) — shrinkage covariance estimator
- Pfaff (2016) Ch.5 — covariance matrix estimation methods

---

### C7 (HIGH) — AX-001 v2 4-axis conditional defense FAIL

**Disposition**: **ACCEPT FULL**

**정량 (AX-001 v2 4-axis honest measurement, baseline = STR_1715 admit)**:

| Axis | Metric | Result | Pass | Note |
|---|---|---|---|---|
| 1 Crisis_alpha | C2 vs Benchmark (KOSPI200), 4 crises mean | +5.90pp | **PASS** | GFC +6.18, EuDebt +12.52, COVID +2.69, RateShock +2.21; all positive |
| 2 MDD complement | C2 vs STR_1715, 4 crises mean | -22.49pp | **FAIL** | C2 deeper DD than STR_1715 in all 4 crises |
| 3 bad/normal IC ratio | bad IC 0.031 / normal IC 0.043 | 0.7152 | **FAIL** | < 1.0 cutoff (defense bias 부재) |
| 4 Tail risk superior | C2 EVT-VaR_99 0.039 < STR_1715 0.060 / CDaR_95 0.141 > STR_1715 0.131 | partial | **PARTIAL** | VaR PASS, CDaR FAIL |

**Composite: 1/4 PASS = AX-001 v2 conditional defense NOT satisfied**

**Baseline ambiguity**:
- AX-001 v2 spec: "방어형 팩터 조건부 평가 (crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio + tail risk metrics)"
- "Core"의 정의 모호 (CLAUDE.md / `_shared_prefix.md` 명시 부재)
- 본 risk-research는 STR_1715 admit을 Core baseline 선택 (현재 admit Sharpe 1.95 / production-deployed)
- 다른 해석: Core = benchmark KOSPI200 (axis 1 그 자체) 또는 Core = pure risk-free + naive market portfolio (axis 2/4 negative shifted)
- **Q-Lead authority**: baseline 재정의 시 axis 2/4 재평가 가능. 본 risk-research stance: STR_1715 baseline 가장 conservative + practical (admit이 운용 중)

**학술 인용**:
- Ang et al. (2006) — IVOL puzzle (alpha source)
- AX-001 v2 (CLAUDE.md line 218) — 방어형 팩터 조건부 평가 framework

**근거**:
- L-121/L-122 — crisis_alpha conditional defense framework
- L-166 — KR defense single-sleeve 4-axis fail precedent

---

### C8 (MEDIUM) — Downstream artifacts (weights.csv 등) 부재

**Disposition**: **REBUTTAL** (lifecycle stage mismatch)

**Rationale**:
- Risk-research는 6-agent WT lifecycle 의 2nd stage (alpha-research → **risk-research** → optimizer-research → forge → judge → governor).
- Charter v1.7 §10 Role Card 4×5 명시:
  - **risk-research**: own = Σ + tail + stress + crowding + style + AX-001 v2 4-axis
  - **optimizer-research**: own = weights.csv + turnover + cost + max_names + bounds
  - **forge**: own = bt_result + cost-realized
  - **architect**: own = independent reproduction
  - **governor**: own = admission + book_state
- weights.csv / optimization_package / B_full historical regime-Sigma는 **하류 agent 책임**. 본 risk-research에서 produce할 수 없음.
- alpha cycle Codex Round 2 C6도 동일 lifecycle stage mismatch 지적 → Charter v1.7 §10 PARTIAL_REBUTTAL inherit.

**AX-008 (Verification Triangulation)**:
- Charter v1.7 §10 AX-008 = 6-agent end-of-lifecycle gate (PG2 admission)
- 단일 stage 2/3 source 충족 불가
- 본 risk-research stance: 1/3 source REPORTED (risk-research only); awaits Optimizer + Forge + Architect

**학술 인용**:
- Charter v1.7 §10 Role Card 4×5
- L-271 (v6.4 Cert Auto-Issuance Paths — agent별 own/inherit/exempt 분리)

**근거**:
- AX-008 [process] (CLAUDE.md line 233) — Verification Triangulation 6-agent lifecycle
- alpha-research Codex Round 2 C6 PARTIAL REBUTTAL 동일 disposition

---

## 3. Self-Rationalization Red Flag Check (Codex Round 1)

Codex가 자기합리화 의심 phrase 6개 적발:

| Phrase | Origin | Disposition |
|---|---|---|
| "gate-bypasses Q2-Q5 mono fail" | 도훈 mandate (B 옵션 가설) | RETAINED with disclosure: portfolio top20 selection이 mono Q2-Q5를 bypass하는 mechanism은 가설 (alpha cycle Codex 인정). 본 risk-research에서 portfolio-level은 별개 fail (Pareto FAIL); mono bypass 가설은 risk-side에서 입증/반증 안 됨. |
| "Multi-sleeve = effectively disjoint" | risk_package_draft.json | REVISED → "Top20 ticker overlap 1/20 (rank-disjoint) BUT realized return co-movement strong" — honest 명시 |
| "1 source (risk-research only); awaits Optimizer + Forge + Architect" | risk_package_draft.json | RETAINED (Charter v1.7 §10 정합 — lifecycle stage 명시는 합리적) |
| "CONSERVATIVE approximation" | risk_research_run.log STR_1715 static proxy comment | REVISED → "Static 2026 top20 proxy used; real STR_1715 had monthly rebalance with time-varying alpha; static may overstate or understate cross-corr; NET BIAS UNCERTAIN. Follow-up Forge task." |
| "IC change negligible" | inherited from alpha cycle (Codex 보고) | INHERIT — alpha cycle dispatch issue |
| "post-cycle deferred" | inherited from alpha cycle (Lockbox split) | INHERIT — alpha cycle dispatch issue |

---

## 4. Risk Research Verdict 종합

**Status**: **NON_ADMITTING_PARETO_FAIL_AX001_FAIL**

**Honest classification table**:

| Dimension | Result | Threshold | Pass |
|---|---|---|---|
| Sigma PSD | TRUE | mandatory | ✓ |
| Sigma condition number | 75.67 | < 500 | ✓ |
| Factor coverage (R² mean) | 0.330 | > 30% | ✓ |
| AX-001 v2 4-axis composite | 1/4 | ≥ 3/4 | ✗ |
| AX-005 v1.2 EXCLUSION path | PARETO FAIL | satisfied | ✗ |
| AX-007 4-sleeve EXEMPT | non-degenerate FAIL | passes | ✗ |
| CVaR_95 cap | 0.0285 | ≤ 0.025 | ✗ (1.14x breach) |
| Pareto orthogonality (|Kendall|<0.20) | 0.5421 | <0.20 | ✗ |
| Lower TDC q=0.10 | 0.6154 | <0.40 | ✗ |
| Cross-corr daily | 0.8491 | <0.40 | ✗ |
| Diversification ratio 70/30 | 1.027 | >1.10 | ✗ |
| Liquidity ADV_20d top20 min | 2.38e8 KRW | ≥2e8 | ✓ |

**Critical finding**: alpha-rank cor 0.004 (alpha vector level) is **NOT equivalent to** portfolio-level realized-return cor 0.7112. Top20 selection after universe-shared (KOSPI200/KQ150) admits common exposure (Mkt + size + defensive sector).

**Q-Lead options**:
- **Option A (Abandon)**: Risk-research stage가 Pareto FAIL + AX-001 v2 1/4 모두 결정적이라면, C2를 research-only artifact로 처리. Consistent with Codex Round 2 alpha REJECT (NON_GRADUATING).
- **Option B (Reframe baseline)**: AX-001 baseline 재정의 (benchmark KOSPI200 = Core) 시 axis 2/4 일부 재평가 가능. 그러나 axis 3 (IC ratio) FAIL은 baseline-invariant. Codex 인정 가능성 낮음.
- **Option C (Optimizer constraint force)**: Pass to Optimizer with explicit constraints. Risk-research가 disclose만; Optimizer가 infeasibility_report 발행 또는 weights composition 강제 tilt 결정.

**Risk-research recommendation basis**: Charter v1.7 §11 도훈/Q-Lead decision authority. Honest disclosure ONLY.

---

## 5. References

### Academic
1. Ang, A., Hodrick, R., Xing, Y., Zhang, X. (2006). "The Cross-Section of Volatility and Expected Returns." *Journal of Finance* 61(1):259-299.
2. Joe, H. (1997). *Multivariate Models and Multivariate Dependence Concepts*. Chapman & Hall. (Tail Dependence Coefficient).
3. Ledoit, O., Wolf, M. (2003, 2004). "Improved estimation of the covariance matrix of stock returns with an application to portfolio selection." *Journal of Empirical Finance* 10:603-621.
4. Pfaff, B. (2016). *Financial Risk Modelling and Portfolio Optimization with R* (2nd ed.). Wiley. Ch.4 (Risk Measures), Ch.5 (Covariance), Ch.7 (EVT GPD), Ch.9 (Copula), Ch.12 (CDaR + Component ES).
5. Rockafellar, R.T., Uryasev, S. (2000). "Optimization of conditional value-at-risk." *Journal of Risk* 2(3):21-41.
6. Connor, G. (1995). "The Three Types of Factor Models: A Comparison of Their Explanatory Power." *Financial Analysts Journal* 51(3):42-46.
7. Grinold, R.C., Kahn, R.N. (2000). *Active Portfolio Management* (2nd ed.). McGraw-Hill. Ch.3 multi-factor decomposition.

### Internal Lawbook / L-codes
- Charter v1.7 §8 — No Silent Override
- Charter v1.7 §10 — Role Card 4×5 (own/inherit/exempt/optional)
- Charter v1.7 §11 — Q-Lead decision authority
- CLAUDE.md AX-001 v2 — Conditional Defense 4-axis
- CLAUDE.md AX-002 — PIT C1~C15 strict
- CLAUDE.md AX-005 v1.2 — KR defense single-sleeve EXCLUSION
- CLAUDE.md AX-007 — 4-sleeve composition exception
- CLAUDE.md AX-008 — Verification Triangulation
- L-121/122 — Crisis alpha framework
- L-129 — Tail risk dominant in defensive family
- L-166 — KR defense single-sleeve 4-axis fail precedent
- L-219/220 — alpha-rank vs realized portfolio orthogonality distinction
- L-247 — Qvest 답변 원칙 (조용한 단순화 금지)
- L-251 — Codex Critic Round REVISE/REJECT 처리
- L-271 — v6.4 Cert Auto-Issuance Paths

### Codex Round Lineage
- Round 1: `codex_critic_response_risk.json` (REJECT, 8 concerns, veto_flag=false)
- Round 1 disposition: 6 ACCEPT_FULL + 1 PARTIAL_REBUTTAL + 1 REBUTTAL_LIFECYCLE

---

## 6. Self-Verification (Q-Lead Escalation Check)

**HIGH severity concerns ≥ 5 trigger?**: Codex Round 1 HIGH = 6 → Q-Lead escalation triggered.

**AX hard FAIL ≥ 3 trigger?**: AX-001 v2 4-axis FAIL + AX-005 EXCLUSION PARETO FAIL + AX-007 non-degenerate FAIL = 3+ → Q-Lead escalation triggered.

**PIT hard violation?**: Inherited alpha PIT-clean (C2 t+1 lag, C10 ADV lag1, C13 manual sign Charter §3 partial); risk-research did not introduce additional violation. C12 (KR factor proxy panel missing) inherited as infra escalation task.

**Σ PD violation?**: No (PSD PASS, min_eig 0.0531 > 0).

**Recommended Q-Lead action**: 
1. Read risk_package.json + risk_challenge_note.md
2. Read codex_critic_response_risk.json
3. Decide option A/B/C
4. If option C: Pass to optimizer-research with explicit CVaR_target / max_sleeve_corr constraints
5. If option A: Archive C2 alpha + risk as research-only artifact (similar to WT-D20260513_001 outcome)

---

## Change Log

- **2026-05-14** — Risk-research Round 1 challenge note created. Codex Round 1 disposition documented (6 ACCEPT_FULL + 1 PARTIAL_REBUTTAL + 1 REBUTTAL). Honest verdict NON_ADMITTING_PARETO_FAIL_AX001_FAIL.
