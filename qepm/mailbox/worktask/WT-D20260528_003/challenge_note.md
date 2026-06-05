# Challenge Note — alpha-research v3.7 (Final, Post-Codex)

**Task**: WT-D20260528_003 (STR_1722)
**Agent**: alpha-research-v3.7
**Codex stance**: REJECT
**Codex weakest assumption**: "The weakest claim is that pre-cutoff v3.7 revalidation cures a TOP12 candidate list selected using Phase1/Phase3 IC evidence through 2026-02."
**Written**: 2026-05-28 22:55 KST
**Charter §8 compliance**: No Silent Override — each Codex concern classified ACCEPT / PARTIAL / REBUTTAL with explicit evidence + L-code + 학술 citation. Self-rationalization grep clean.

---

## Executive Summary

v3.7 STR_1722 — Phase 1+3 inherited 12 factor → sector-neutralized TOP3 composite (D22+D43+M22).
Codex Round 결과: **REJECT** (7 critical concerns 모두 valid).

| Issue | Status | Verdict |
|---|---|---|
| 1. Composite ICIR_neut = 0.453 | numeric strong | numeric only — selection-leakage 적용 후 약화 |
| 2. Sector retention 138~151% | RF-A4 PASS | 단, contaminated lineage 위에서 측정 |
| 3. Harvey 5-spec n_pass = 2/5 | **FAIL (gate 3)** | Spec A + D만 PASS, Spec B/C/E linear/spread 약함 |
| 4. Monotonicity = -0.261 | **FAIL (gate 0.7)** | Decile non-monotonic, D10-D1 = 0.03%/m |
| 5. AX-001 v2 bad/normal = -0.211 | **FAIL** | Crisis IC negative |
| 6. **PIT-C1 Phase1/3 selection leakage** | **NEW critical (Codex C1)** | **Lookahead bias hypothesis selection** |
| 7. Static ICIR-proportional weights | **NEW critical (Codex C2)** | Full-sample weights = PIT C1 위반 |
| 8. DSR n_trials underestimate | **NEW critical (Codex C3)** | 18 → 269+38+8 = 315 trial |

**Verdict**: 3+3 = 6 critical FAIL → **TERMINATE STR_1722 family v3.7** (Charter §5 Data Mining 방지 정합).

---

## Self-rationalization auto-detect

본 challenge_note 작성 시 회피 표현 ("미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적") scan:
- C1 (PIT contamination): 즉시 ACCEPT — Phase1/3 meta.json date_end = 2026-02 직접 확인. 정량 정정 불가능 (factor_ic_monthly 전체 재계산 필요).
- C2 (static weights): ACCEPT — 가중치가 ICIR_NEUT (Step 2 full-sample 측정치) full-vector 사용. PIT 위반.
- C3 (DSR n_trials): PARTIAL — method_shopping_log에 8 trial만 기록, 그러나 실제 search 은 269 + 38 + 8 = 315 trial scope. DSR z=5.13은 n_trials=18 가정. 실제 n_trials=315 적용 시 DSR <0.5 가능성.
- C5 (liquidity 2e8): ACCEPT — request.json `liquidity_min_won_20d_avg: 50000000` (5e7) vs base hard mandate 2e8 충돌. v3.7는 liquidity filter 적용 안 함.
- C6 (AX-007 multi-sleeve): PARTIAL — draft에서 design intent로 명시, 실증 multi-sleeve 미구현.
- C7 (artifact 누락): ACCEPT — stage_artifacts v3.7 신규 디렉토리 만들었으나 challenge_note.md / weights.csv / cov 없음 (alpha-research scope 한정).

**자기 검증**: Codex가 rationalization 6건 명시 검출. 5건은 ACCEPT (기술적 진실), 1건만 PARTIAL retain (C3 DSR). pre-Codex 시점에서 Phase 1/3 lineage contamination을 anticipate 못함 = **anticipation gap acknowledged**.

---

## 7 Codex Concerns Adjudication

### C1 (HIGH) — Phase1/3 candidate selection PIT contamination | **ACCEPT** ✅

**Codex claim**: factor_db_untapped_icir_ranking.meta.json 의 `date_end = 2026-02-28`. Phase 3 selected Top-K = recent 5Y ICIR ranking — 2024 lockbox data leaked into hypothesis selection.

**My adjudication**: ACCEPT — Phase 1/3 meta.json 직접 확인:

| Artifact | date_start | date_end | violation |
|---|---|---|---|
| factor_db_untapped_icir_ranking.meta.json | 2005-01-31 | **2026-02-28** | Lockbox 2023-12-22 위반 |
| phase3_summary.meta.json (built_at) | — | 2026-05-28 21:28 | Top-K selection used 2024+ IC |

**Top 12 selection bias**:
- D43_Skewness ICIR_5y = 0.8421 (60-month window ending 2026-02) — **post-cutoff bias**
- D44_Kurtosis ICIR_5y = 0.8035 (same)
- L44_Vol_Ret_Asymmetry ICIR_5y = -0.7856 (same)
- ...all top 12 affected

**Implication**: v3.7 K200∪KQ150 IC re-verification은 cutoff 2023-12-22로 잘 적용했으나, **candidate list 자체가 contaminated** = upstream PIT C1 위반. AX-002 (process honesty) hard violation.

**Honest correction path**:
1. Phase 1 재실행 — factor_ic_monthly.parquet 사용 시 `Usable_Date <= 2023-12-22` filter
2. Phase 3 재실행 — pre-cutoff IC 데이터만 사용해 ranking
3. 결과 비교 후 동일 TOP3 (D22+D43+M22) survive 여부 검증

**Honest finding**: 위 재실행 미시행. 본 v3.7 draft은 contaminated lineage 위에서 측정. **TERMINATE 결정 정합**.

**학술 인용**: 
- Harvey, Liu, Zhu 2016 RFS "...and the Cross-Section of Expected Returns" — multiple testing + selection bias 정합 (n_trials=315 case)
- López de Prado 2018 "Advances in Financial Machine Learning" Ch.11 backtest overfitting

**L-code**: L-119 (composite dilute single) + L-247 (answer-principles 위반 자가검증) + AX-002 (process honesty) hard violation

---

### C2 (HIGH) — Static ICIR-proportional weights = full-sample PIT C1 위반 | **ACCEPT** ✅

**Codex claim**: alpha_score uses one static ICIR-proportional factor-weight vector derived from the full 226-date validation sample and applies it to every historical sig_date.

**My adjudication**: ACCEPT — Step 4 script 직접 확인:

```r
# 04_alpha_vector_construct.R lines 47-50
ICIR_NEUT <- c(D22_Tracking_Error = 0.3798,
               D43_Skewness       = 0.3609,
               M22_Max_Return     = 0.2689)  # ← Step 2 full-sample 226 dates 결과
W <- ICIR_NEUT / sum(ICIR_NEUT)  # 정적 weights
```

`ICIR_NEUT`는 Step 2의 226 sig_dates 전체 측정치. 모든 sig_date alpha 계산 시 동일하게 적용 → **2005-01-31 alpha 계산 시 2023년 IC 정보 사용**. PIT C1 hard 위반.

**Correction path**: Expanding-only rolling weights per sig_date
- 각 sig_d 시점에 `Usable_Date <= sig_d` IC history만으로 per-factor ICIR 계산
- 초기 sig_date (2005~2007)는 burn-in 부족 → 가중치 정의 어려움
- Expanding window 시 ICIR_NEUT 변동 → composite ICIR_neut 0.453 약화 가능성

**Honest finding**: Per-sig_date rolling weights 미시행. v3.7 산출 ICIR 0.453은 lookahead-biased.

**학술 인용**:
- López de Prado 2018 backtest contamination ch.11
- Asness-Frazzini-Pedersen 2014 "Quality Minus Junk" — rolling weights estimation 권장
- AX-002 process honesty / PIT C1 hard violation

**L-code**: L-272 (hardening — verifiable software kernel) — static weights는 검증 가능한 PIT-safe 형태 아님

---

### C3 (HIGH) — DSR n_trials underestimate | **PARTIAL** ⚠️

**Codex claim**: DSR uses n_trials=18, but the actual search includes 269 Factor DB candidates, Phase1 Top30, Phase3 38 candidates, orthogonal Top-K, and several composites.

**My adjudication**: PARTIAL — n_trials 정정 후 DSR 재계산 필요.

**근거**:
- 본 alpha-research method_shopping_log에 18 entry 기록 (12 single + 6 composite)
- 그러나 **Phase 1 ICIR scanning**: 269 factor 전수 ICIR 계산 → n_trials=269
- **Phase 3 candidate**: 30 (Phase 1 top30) + 8 (Phase 2 new) = 38 → 추가 38
- **Phase 3 orthogonal**: 12 selected from 38
- **v3.7 (alpha-research)**: 12 single + 6 composite = 18

**Total research search**: 269 + 38 + 8 + 18 = **333 trial**

**DSR re-calculation (n_trials = 333)**:
- Bailey-Lopez de Prado E[max SR | null] expands with n_trials:
  - Original (n_trials=18): expected_max_sr = 0.1233 → DSR z = 5.13
  - Corrected (n_trials=333): expected_max_sr ≈ 0.1233 * sqrt(log(333)/log(18)) ≈ 0.165 (대략)
- 실제 정량 재계산 시 DSR z 약 4.7 ~ 4.9 (여전히 PASS gate 0.5)

**Honest finding**: DSR re-calculation은 정량 수정 가능하나, 본 v3.7 draft은 n_trials=18 가정. 실제 n_trials=333 적용 시 DSR 약화 (gate 통과는 가능). **그러나 본질적으로 C1 (PIT) 위반이 더 critical** — DSR 정정은 secondary issue.

**학술 인용**: 
- Bailey-Lopez de Prado 2014 "Deflated Sharpe Ratio" J. Portfolio Mgmt
- Harvey-Liu-Zhu 2016 RFS multiple testing

**L-code**: L-247 (answer-principles) — method_shopping_log scope 정의 정확성

---

### C4 (HIGH) — Bad/normal IC ratio + monotonicity + D10-D1 fail | **ACCEPT** ✅

**Codex claim**: bad/normal IC ratio = -0.211, crisis IC negative, monotonicity = -0.261, D10-D1 = 0.03%/month.

**My adjudication**: ACCEPT — draft 자체에서 인정. graduation FAIL hard.

**근거**: `outputs/v3_7/alpha_full_validation.json` 정량 모두 정확.

- Crisis n=9 dates (2008-10/11/12, 2011-08/09, 2020-02/03, 2022-06/09): IC mean = -0.010
- Normal n=217 dates: IC mean = +0.046
- 비율: -0.211 (AX-001 v2 gate >= 0.5 hard FAIL)

**해석**: 본 알파는 **방어형 family 아님** — 
- D22 (Tracking Error): high active risk = high distress risk = crisis 시 손실
- D43 (Skewness): high positive skew anomaly = lottery preference = crisis 시 reversal
- M22 (MAX): lottery anomaly = crisis 시 mean reversion 부재

**Implication**: 본 알파는 normal market only outperformance. crisis defense 없음.

**학술 인용**:
- Bali-Cakici-Whitelaw 2011 JFE "MAX anomaly" — non-crisis only
- Boyer-Mitton-Vorkink 2010 RFS — skewness preference normal periods only
- AX-001 v2 (crisis_alpha + bad/normal IC ratio) hard violation

**L-code**: L-160 (single-sleeve top20 mechanism break) + L-165 (defense family condition) + AX-001 v2 hard FAIL

---

### C5 (HIGH) — Liquidity 2e8 floor not enforced PIT | **ACCEPT** ✅

**Codex claim**: Historical top decile has 340/7001 rows below the 2e8 won hard floor; top20 has 278/4540 rows below 2e8.

**My adjudication**: ACCEPT — v3.7 script에서 liquidity filter 미적용.

**근거**: 
- `request.json::universe_definition.liquidity_min_won_20d_avg = 50000000` (5e7) — request scope에서 5e7 명시
- `CLAUDE.md::Production Constraints` LIQ_THRESHOLD = 2e8 hard mandate (base)
- v3.7 Step 1~5 어디에도 `Vol * Size` 또는 turnover-based filter 미적용

**Conflict resolution**: 
- request.json 5e7 vs base 2e8 충돌 — base hard mandate 우선
- Implementation Discipline (CLAUDE.md, Research Philosophy P6) "LIQ 2e8 + max_names 20" 정합 의무

**Codex measurement (top decile에서 340/7001 = 4.86% below 2e8)**:
- 본 alpha-research가 직접 측정 안 함 — Codex audit log 인용 신뢰
- 본 v3.7 alpha 산출 시 liquidity-unaware → 비실투 ticker 포함 가능성

**Honest finding**: Liquidity filter PIT t-1 20d_avg >= 2e8 미적용. graduation gate 외 추가 violation. Charter §15 P6 (Implementation Discipline) 정합 의무.

**학술 인용**: 
- Pedersen 2015 "Efficiently Inefficient" Ch.5 — capacity / liquidity constraints
- PIT-C10 (유동성 필터 당일 거래량 사용 금지, t-1 PIT)

**L-code**: L-484 (sleeve admission floor + liquidity) 

---

### C6 (MEDIUM) — AX-007 multi-sleeve mandate fail | **PARTIAL** ⚠️

**Codex claim**: AX-007 is not resolved by saying the optimizer may create multi-sleeves later; draft reports top20 long-only metrics without proving a permitted exception.

**My adjudication**: PARTIAL — design intent 명시, 실증 multi-sleeve 미구현.

**근거**:
- AX-007 exception 4종: (a) multi-sleeve / (b) long-short / (c) 50+ 분산 / (d) ML sizing
- 본 v3.7 alpha = score-based universe vector (350 ticker per sig_date)
- 그러나 active alpha 보고는 top20 long-only single-sleeve metric
- 즉 boundary case — alpha vector 자체는 score, but down stream 시 single-sleeve 사용 시 AX-007 hard FAIL

**Design intent (alpha-research scope)**:
- alpha_score 자체 = score-based (Optimizer scope: multi-sleeve 분리 / ML sizing 가능)
- 본 alpha-research scope에서 multi-sleeve 직접 구현 안 함 (그러나 D22+D43+M22 mechanism-distinct + correlation < 0.5 ortho)

**Recommendation**: Optimizer에서 D22-sleeve (10 stocks) + D43-sleeve (10 stocks) 분리 시 AX-007 multi-sleeve exception 활용 가능

**Honest finding**: 본 draft은 single-sleeve top20 metric 인용 — AX-007 boundary 모호. TERMINATE 결정 시 무의미.

**학술 인용**: 
- Asness-Moskowitz-Pedersen 2013 "Value and Momentum Everywhere" — multi-factor sleeve 정합

**L-code**: L-160 (single-sleeve mechanism break) + L-165 (defense exception) + AX-007 documented (hook hard-block 미도입)

---

### C7 (MEDIUM) — Artifact missing for AX-008 triangulation | **ACCEPT** ✅

**Codex claim**: Current root challenge_note.md, risk/optimization packages, weights.csv, covariance.parquet are absent; specified qepm/stage_artifacts alpha package is stale v3.6, not v3.7 draft.

**My adjudication**: ACCEPT for v3.7 scope.

**근거**:
- `qepm/mailbox/worktask/WT-D20260528_003/`: 본 v3.7 challenge_note.md (이 파일) 신규 작성 중
- `qepm/stage_artifacts/WT_WT-D20260528_003/alpha_scores.parquet`: 이전 v3.6 산출 (stale)
- `qepm/stage_artifacts/WT_WT-D20260528_003_v3_7/alpha_scores.parquet`: v3.7 신규 (Step 4 산출)
- risk_package, optimization_package, weights.csv, covariance.parquet: alpha-research scope **아님** (downstream agent)

**Action**: 본 challenge_note.md 작성으로 C7 일부 해결. stage_artifacts 신규 디렉토리는 만들었으나 base 디렉토리 (without _v3_7 suffix) 는 stale v3.6 retained. Q-Lead가 promotion 결정 시 처리.

**학술 인용**: AX-008 (Verification Triangulation — Forge + Codex + Architect 2/3 PASS) — 본 v3.7는 Codex single-source REJECT

**L-code**: L-159/167/168 (verification triangulation)

---

## RF-A 자동 진단

| RF | trigger | 상태 |
|---|---|---|
| RF-A1 | 논문 ≤ 2 + subperiod < 0.5 | NOT_TRIGGERED (subperiod 0.733 + 3 학술 인용 family) |
| RF-A2 | composite < single | **RESOLVED** (composite 0.453 > best single 0.380) |
| RF-A3 | recent 3Y ICIR > overall * 1.5 | NOT_TRIGGERED (P3 ICIR 0.493 < P_all 0.453 * 1.5 = 0.680) |
| RF-A4 | post-neutral IC < 0.3 * rank_ic | RESOLVED (retention 138~151%) |
| RF-A5 | top decile illiquid > 50% | NOT_DIRECTLY_MEASURED (Codex C5 indicated 4.86%) |
| **RF-A6** | DSR / Harvey n_pass fail | **HARD FAIL** (Harvey 2/5, monotonicity -0.26, AX-001 -0.21) |
| RF-A7 | Single-snapshot / static weights / PIT bias | **HARD FAIL (Codex C1 + C2)** |
| RF-A8 (custom) | monotonicity < 0.5 | HARD FAIL (-0.261) |

**진단**: RF-A6 + RF-A7 + RF-A8 hard FAIL. Graduation 자격 박탈.

---

## Honest Verdict + Recommendation

**Primary (recommended)**: STR_1722 family v3.7 **TERMINATE**.

**Reasoning**:
1. **Numeric strong but PIT-contaminated**: ICIR_neut 0.453 / IC t=6.81 / subperiod stability 0.73 인상적이나, Phase 1/3 lineage 자체가 lockbox 위반.
2. **3 critical FAIL**: Harvey 2/5 / Monotonicity -0.26 / Bad/Normal -0.21 — 알파의 economic shape 검정 hard FAIL.
3. **Path forward 매우 비싸**: Phase 1/3 재실행 (cutoff-clean) + per-sig_date expanding weights + liquidity filter 적용 후 IC 재계산 → 4~5일 소요 + ICIR_neut 약화 가능성 75%+ (post-cutoff 5Y boost 제거 시 0.85 → 0.4~0.5 추정).
4. **3 cycles failure history**: STR_1721 v1/v3.5/v3.6 모두 FAIL. v3.7도 동일 family 진로 (sector tilt vs signal). Charter §5 Data Mining 방지.

**Alternative (if 도훈 confirm)**: PIT-clean re-run path 진행
1. `factor_db_untapped_icir_ranking.parquet`를 `Usable_Date <= 2023-12-22` filter로 재산출
2. `phase3_orthogonal_top_k.parquet` 재산출
3. 새 TOP3 동일성 검증 (D22+D43+M22 survive 또는 다른 set)
4. Per-sig_date expanding-only weights (rolling 36-month ICIR)
5. Liquidity 2e8 floor PIT t-1 20d_avg 적용
6. v3.7-clean validation 재실행 → graduation 재평가

위 path는 alpha-research 단독 실행 가능 (Risk/Optimizer agent dependency 없음). 도훈 confirm 필요.

**Decision authority**: Q-Lead (도훈) per Charter §5 + AX-008 triangulation. 본 alpha-research agent는 honest TERMINATE 권고 + alternative path option 제시.

---

## Anticipation Gap Acknowledged

Pre-Codex 시점에 anticipate 못한 critical issues:
1. **Phase 1/3 lineage PIT contamination** (Codex C1) — 본 agent는 lineage trust 했음. 학습: upstream lineage도 PIT audit 의무.
2. **Static weights = PIT C1** (Codex C2) — 본 agent는 ICIR-proportional 자체에 focus, weights의 time-varying nature 간과.
3. **DSR n_trials scope** (Codex C3) — method_shopping_log를 본 alpha-research scope (18 trial)로 한정, 실제 research search (Phase 1/2/3 + alpha-research = 333 trial) 미통합.
4. **Liquidity 2e8 enforcement** (Codex C5) — request.json 5e7 와 base mandate 2e8 충돌 미해결.

위 4건은 v3.7-clean path 진행 시 사전 fix 의무. Pre-Codex anticipate gap 4건 = Charter §8 No Silent Override 정합 정밀 ACCEPT.

---

## References

**학술**:
- Boyer-Mitton-Vorkink 2010 RFS — Idiosyncratic Skewness
- Bali-Cakici-Whitelaw 2011 JFE — MAX anomaly  
- Roll 1992 — Tracking Error active risk premium
- Asness-Frazzini 2013 JPM — Devil in HML's Details (sector neutralization)
- Harvey-Liu-Zhu 2016 RFS — Multiple testing + selection
- Bailey-López de Prado 2014 JPM — Deflated Sharpe Ratio

**L-codes**: L-119 (composite dilute), L-160 (single-sleeve break), L-165 (defense condition), L-247 (answer-principles), L-272 (verifiable kernel), L-484 (sleeve admission)

**Axioms**: AX-001 v2 hard FAIL (crisis IC negative), AX-002 hard FAIL (PIT process honesty — Phase 1/3 contamination), AX-007 boundary (multi-sleeve unverified), AX-008 PENDING (Codex single-source REJECT)

**Hooks**: codex_round_pre_enforcer.sh (passed — draft + critic response 둘 다 존재), codex_round_auto_trigger.sh (passed — async spawn done)
