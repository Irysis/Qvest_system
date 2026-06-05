# Challenge Note — alpha-research v3.6 PIVOT (DRAFT)

**Task**: WT-D20260528_003
**Agent**: alpha-research-v3.6-pivot
**Codex stance**: pending_post_emit
**Codex weakest assumption**: (pending Codex Round response)
**Written**: 2026-05-28
**Charter §8 compliance**: No Silent Override — each Codex concern classified ACCEPT / PARTIAL / REBUTTAL with explicit evidence.

---

## Executive Summary

v3.6 PIVOT 3 fix axes (도훈 Option 1 mandate 2026-05-28) 적용:

| Fix axis | Target | v3.5 baseline | v3.6 result | Verdict |
|---|---|---|---|---|
| 1. Sector neutralization | retention ≥ 50% | **48.1%** FAIL | **67.8%** | **PASS** |
| 2. HMM 4-state regime | fallback < 30% | **54.2%** FAIL | **10.8%** | **PASS** |
| 3. RF-A2 composite ≥ single | composite > best single | 0.339 < 0.393 FAIL | **0.224 < 0.386** | **FAIL** |

2 of 3 fixes PASS. **RF-A2 STILL FAIL** → composite paradigm 본질 의문.

**Additional regressions post-sector-neut**:
- Rank IC: 0.0425 → **0.0201** (53% decline)
- Harvey strict 1/5 → **0/5** (full collapse)
- Harvey medium 3/5 → **0/5**
- DSR: 1.0 → **0.0000**
- AX-001 v2 bad/normal ratio: 3.45 → **-4.82** (crisis_alpha REVERSED)
- Monotonicity: 0.78 → **0.07** (decile signal almost flat)

**Verdict**: 3 cycles FAIL (v1 + v3.5 + v3.6). **Charter §5 Data Mining 방지 정합 = TERMINATE 권고**.

---

## v3.5 → v3.6 Fix Effectiveness (정량)

### Fix 1: Sector Neutralization (Asness-Frazzini 2013 sector dummy regression residual)

| Family | Raw ICIR | Neut ICIR | Retention % | Classification |
|---|---|---|---|---|
| value | 0.112 | 0.029 | **25.7%** | SECTOR_DRIVEN |
| quality | -0.133 | -0.065 | 49.2% | mixed |
| momentum | -0.055 | -0.142 | 258.3% | stock-specific (sign flipped neut) |
| growth | 0.030 | 0.100 | 335.7% | stock-specific (small base) |
| consensus | 0.267 | 0.270 | **101.4%** | **stock-specific** |
| **low_vol** | **0.386** | **0.275** | **71.2%** | mixed |
| size | 0.103 | 0.082 | 79.7% | stock-specific |
| dividend | 0.285 | 0.142 | **49.6%** | SECTOR_DRIVEN |
| **Composite (eq-w neut)** | **0.265** | **0.180** | **67.8%** | mixed |

**해석**: Consensus + size + low_vol + growth 4 family는 sector 의존이 낮음 (≥70% retention). value + dividend는 sector 의존 강함 (≤50% retention). Composite은 **67.8% retention** (≥ 50% threshold PASS).

### Fix 2: HMM 4-state (Hamilton 1989, depmixS4)

| Metric | v3.5 (K-means 9-state) | v3.6 (HMM 4-state) | Target | Verdict |
|---|---|---|---|---|
| Fallback ratio | 54.2% | **10.8%** | < 30% | PASS |
| State-specific ratio | 45.8% | **80.0%** | (informative) | improved |
| Persistence diagonal | varied | **0.965-0.983** | ≥ 0.85 | PASS |
| Per-state monthly count | 9 cells × ~10 | S1=8 / S2=9 / S3=25 / **S4=49** | ≥ 30 per state | **PARTIAL** |

**Caveat (PARTIAL)**: S1=8 / S2=9 monthly counts below target ≥ 30. HMM EM convergence 정상 + persistence high mitigates sparse-state risk. v3.6 caveat 명시.

### Fix 3: Single vs Composite vs Regime-Weighted (3-way RF-A2 verdict)

| Signal | ICIR | t_NW lag6 | Verdict |
|---|---|---|---|
| F_low_vol (raw, single) | **0.386** | 3.58 | best |
| F_dividend (raw, single) | 0.285 | 2.95 | |
| F_low_vol_neut (sector-neut single) | 0.275 | 2.15 | |
| F_consensus_neut | 0.270 | 1.95 | |
| F_consensus (raw, single) | 0.267 | 3.41 | |
| F_composite (raw, eq-w) | 0.265 | 2.94 | v3.5-equivalent |
| **alpha_rw_neut** (v3.6 selected) | **0.224** | **1.95** | regime-w composite, sector-neut |
| F_composite_neut (sector-neut eq-w) | 0.180 | 1.47 | |

**RF-A2 verdict**: alpha_rw_neut (0.224) < F_low_vol_raw (0.386) **42% dilution**. Even within sector-neut basis: 0.224 < F_low_vol_neut (0.275) **19% dilution**. Both fail RF-A2.

**Interpretation**: 8-family composite paradigm은 best single family를 못 따라감. Sector-neut 후 더 명확. **Composite 본질 의문 (Data Mining 방지)**.

---

## 9 v3.6 Critical Concerns (pre-Codex anticipation)

### A1 (HIGH) — RF-A2 FAIL 후속 처리 | **ACCEPT (post-fix)**

**자기 진단**: v3.6 3-way 시험에서 alpha_rw_neut ICIR 0.224 < F_low_vol_raw 0.386. 42% dilution.

**Action**: Charter §5 Data Mining 방지 정합 — composite paradigm 폐기 권고. Salvage path:
- (a) Long-short F_low_vol_neut vs F_quality_neut (AX-007 long-short exception)
- (b) ML-based dynamic factor selection (AX-007 ML sizing exception)
- (c) F_low_vol_neut 50+ name deployment (AX-007 diversification exception)

### A2 (HIGH) — Harvey 0/5 strict, 0/5 medium 회귀 | **ACCEPT**

**Codex anticipated**: v3.5 1/5 → v3.6 0/5 strict. Spec-by-spec:
- A_raw_ic: 3.17 → **1.95**
- B_residual: 2.05 → 1.95
- C_quintile_spread: 2.83 → **1.23**
- D_top_decile_market: 1.61 → **0.05**
- E_regime_residual: 2.80 → **0.00**

**Root cause**: Sector neutralization 후 underlying alpha signal weak이 그대로 노출. v3.5의 sector-driven boost가 사라짐.

**Action**: Charter §5 — composite paradigm 폐기 정당화 근거.

### A3 (HIGH) — DSR=0.0000 (n_trials=18) | **ACCEPT**

**자기 진단**: full method search space (8 raw + 8 neut + 1 eq-w + 1 regime-w = 18 trials)에서 v3.6 regime-w composite SR이 expected max under null 보다 -8.71 SE 낮음.

**Codex anticipated**: v3.5 DSR=1.0 (n_trials=5)는 부적절. n_trials=18로 보수적 계산 시 의미 없음.

**Action**: ACCEPT. Single low_vol family가 우월 — composite 부재가 더 정직.

### A4 (HIGH) — AX-001 v2 crisis_alpha NEGATIVE | **ACCEPT**

**자기 진단**: 3 crisis dates (2020-03/04, 2022-09/10) mean IC = **-0.123**. Bad/normal ratio = **-4.82**. Crisis에서 alpha REVERSED.

**Codex anticipated**: 방어형 factor 조건부 평가 (AX-001 v2) — crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio. **본 alpha는 bad/normal ratio < 0** → AX-001 v2 PASS 불가.

**Action**: ACCEPT. AX-001 v2 condition 미충족.

### A5 (HIGH) — Rank IC 0.020 < 0.04 graduation threshold | **ACCEPT**

**자기 진단**: v3.5 0.0425 → v3.6 0.0201. **Below graduation threshold**.

**Codex anticipated**: graduation_criteria.min_rank_ic = 0.04. FAIL.

### A6 (MEDIUM) — HMM S1/S2 sparse (n=8, 9 < target 30) | **PARTIAL**

**자기 진단**: HMM 4-state로 9-state cell sparsity 완전 해결 목표였으나 S1/S2 monthly count는 8, 9. PARTIAL.

**근거 vs rationalization**: persistence 0.965+이라 sparse cell의 mean estimate가 그래도 reasonable. Markov chain 자연 property로 dominant state (S4=52%) 정상.

**Caveat**: 7년 history로 S1/S2 같은 rare states (BULL/CRISIS extremes) 충분 학습 어려움. Out-of-sample S1/S2 적중 시 fallback 권고.

### A7 (MEDIUM) — PIT-C15 macro I/O (MA07/RE_MRS 직접 parquet) | **PARTIAL retain v3.5**

**자기 진단**: v3.5 challenge_note C6와 동일. `load_month_factors()` API는 cross-section factor용 — macro single time series에 부적합. PIT-C9 lag + expanding-z 적용으로 PIT 본질 보장.

**Action**: v3.5 PARTIAL retain. Architect agent advisory queue 적립.

### A8 (MEDIUM) — Schedule gap 7 months (P4 upstream) | **REBUTTAL retain v3.5**

**자기 진단**: v3.5와 동일. P4_multi_horizon Phase 2 upstream artifact의 zero-row months. v3.6는 v3.5 panel을 inherit하므로 same gaps.

**Mitigation downstream**: forge backtest carry-forward semantics.

### A9 (LOW) — Monotonicity 0.07 + Turnover 5.08 | **ACCEPT cofounders**

**자기 진단**: Monotonicity 0.78 → 0.07. Sector neutralize 후 decile spread (D10-D1) = 0.003 essentially zero. Turnover 5.08 annual (top decile) > 3.0 threshold.

**Root cause**: Sector exposure가 monotonic decile signal의 주력이었음. 제거 후 weak underlying alpha가 monotonic structure 잃음. Turnover는 regime-driven family weight 변동이 큼 (4 HMM state transition 시 weight matrix rebalance).

---

## Self-rationalization auto-detect

본 challenge note scan: 회피 표현 ("미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적"). **None used**. Empirical numbers + L-codes + 학술 인용 3축으로 rebuttal.

---

## Charter §5 Data Mining 방지 정합 — TERMINATE 권고

**3 cycles FAIL** (v1 GRADUATION_FAIL → v3.5 GRADUATION_FAIL → v3.6 GRADUATION_FAIL):

| Cycle | Key result | Lesson | Action |
|---|---|---|---|
| v1 (2026-05-28 16:00) | composite 64% dilution vs single low_vol | Regime PIT-C9 t-1 lag 필수 | v3.5 spawn |
| v3.5 (16:47) | ICIR 0.339, Harvey 1/5, RF-A4 48.1% | Sector exposure가 ICIR의 절반 | v3.6 spawn |
| v3.6 (17:28) | ICIR 0.224, Harvey 0/5, RF-A2 still FAIL | Sector-neut 후 composite < single | **TERMINATE** |

**Charter §5 referenced**:
> "Data Mining 방지 (composite overfitting 경계)" — composite paradigm을 forcing해 single family ICIR을 못 따라가면, hypothesis 본질 의문. 3 cycles FAIL 후 강제 termination.

**Q-Lead 의사결정 요청**:
1. **TERMINATE primary** (Charter §5 정합 default)
2. **Salvage path** (조건부, 도훈 confirm 후):
   - (a) Long-short F_low_vol_neut vs F_quality_neut (AX-007 long-short exception)
   - (b) ML factor selection (AX-007 ML sizing exception)
   - (c) F_low_vol_neut 50+ name (AX-007 diversification exception)
3. **Alternative hypothesis redirect** (도훈 mandate 시):
   - STR_1721 family 폐기 후 다른 가설

---

## Adjudication Summary Table (pre-Codex)

| Concern | Severity | Adjudication | Action |
|---|---|---|---|
| A1 RF-A2 still fail | HIGH | **ACCEPT** | TERMINATE primary recommendation |
| A2 Harvey 0/5 strict | HIGH | **ACCEPT** | Charter §5 정당화 근거 |
| A3 DSR=0.0000 | HIGH | **ACCEPT** | Composite 부재 더 정직 |
| A4 AX-001 v2 crisis NEGATIVE | HIGH | **ACCEPT** | 방어형 condition 미충족 |
| A5 Rank IC 0.020 | HIGH | **ACCEPT** | Graduation threshold FAIL |
| A6 HMM S1/S2 sparse | MEDIUM | **PARTIAL** | persistence 0.96+ mitigates |
| A7 PIT-C15 macro I/O | MEDIUM | **PARTIAL** | v3.5 retain, architect advisory |
| A8 Schedule 7 gap | MEDIUM | **REBUTTAL** | upstream Phase 2 root cause |
| A9 Mono + TO regression | LOW | **ACCEPT** | sector exposure 제거 부수 효과 |

**Quantitative breakdown** (pre-Codex):
- ACCEPT: **6 concerns** (5 HIGH + 1 LOW) — fundamental issues
- PARTIAL: **2 MEDIUM concerns** — design caveats
- REBUTTAL: **1 MEDIUM** — upstream root cause

**HIGH severity ≥ 5 trigger check**: Pre-Codex HIGH = 5. **Threshold ≥ 5 MET** → Q-Lead escalate trigger 발동.

**AX axiom hard FAIL ≥ 3 trigger check**: AX-001 v2 FAIL (crisis_alpha negative). Composite paradigm 본질 의문 — Charter §5 escalate.

**PIT C1 lockbox / lookahead detected**: No. PIT-C9 + C13 + C14 + C15 (family panel) full PASS.

---

## Codex Round response 도착 후 update 예정

Codex stance / weakest_assumption / additional concerns이 도착하면 본 challenge note에 다음 추가:
1. Codex 9 concerns adjudication
2. Alpha self-anticipation 정확도 비교
3. 최종 final stance + Q-Lead decision recommendation

---

**This is a DRAFT.** Codex Round (~9-15min background) 응답 도착 후 final challenge_note.md로 promote.
