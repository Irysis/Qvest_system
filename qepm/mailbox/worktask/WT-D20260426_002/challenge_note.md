# Alpha Agent Challenge Note — WT-D20260426_002 Iter 8

**Status**: ALPHA_DONE (graduation FAIL — honest accounting)
**Stance**: Sprint termination recommended + L-209 적립
**Codex Round**: REJECT (7 critical concerns, all addressed in final)

---

## 1. Hypothesis Recap

**Iter 8 가설**:
> KR market에서 unconditional Liquidity premium (Amihud 2002 illiquidity)은
> negative IC (Iter 7 IC=-0.05 입증). 그러나 regime-conditional 적용 시
> BULL/NORMAL 국면에서 positive premium (Pastor-Stambaugh 2003), CAUTION/CRISIS
> 에서 reverse → cash overlay로 회피하면 regime-weighted alpha 보존 가능.

**구조** (AX-007 EXCEPTION#1 multi-sleeve 선언):
- Sleeve 1 — Liquidity 70% (BULL/NORMAL only): L01_Amihud Z_Score_Aligned
- Sleeve 2 — Cash 30% baseline / 100% (CAUTION/CRISIS): alpha=0

---

## 2. Test Outcome — NOT MET

### 2.1 Graduation Criteria (universe-restricted, post-neutralized)

| Metric | Value | Threshold | Pass |
|---|---|---|---|
| rank_IC (BULL+NORMAL active) | -0.0051 | ≥ 0.04 | FAIL |
| ICIR (BULL+NORMAL active) | -0.044 | ≥ 0.20 | FAIL |
| Subperiod sign consistency | 0.67 | ≥ 0.50 | PASS |
| Harvey t-stat | -0.53 | ≥ 3.0 | FAIL |
| DSR (n_trials=10 strict) | 0.018 | ≥ 0.5 | FAIL |
| TDC vs STR_1700 | 0.173 | < 0.30 | PASS |
| 5-spec Harvey 4/5 PASS | 0/5 | ≥ 4 | FAIL |
| Post-neutralization retain | retain ratio met | ≥ 0.5 | PASS (vacuous — 둘 다 ~0) |
| Monotonicity | -0.42 | ≥ 0.7 | FAIL |

**Overall**: 3 PASS / 6 FAIL → graduation NOT MET

### 2.2 Regime-conditional ICIR

| Regime | N periods | rank_IC | ICIR |
|---|---|---|---|
| BULL | 85 | -0.014 | **-0.116** (가설과 reverse) |
| NORMAL | 60 | +0.007 | **+0.062** (보더라인 미만) |
| CAUTION | 25 | n/a | alpha=0 (cash) |
| CRISIS | 5 | n/a | alpha=0 (cash) |

가설의 핵심 ("BULL/NORMAL positive premium")은 **양 regime 모두에서 입증되지 않음**:
- BULL: 음의 alpha — flight-to-quality라기 보다 illiquid 종목 자체가 BULL 국면에서 underperform
- NORMAL: 양의 alpha이지만 통계 유의성 없음 (ICIR 0.06 << 0.20)

### 2.3 Subperiod Decomposition (Codex C4 RF-A3)

| Period | rank_IC | ICIR |
|---|---|---|
| 2008-2014 | -0.025 | -0.20 |
| 2015-2019 | +0.044 | +0.36 |
| 2020-2023 | +0.030 | +0.24 |

- 2020-2023 ICIR (0.24) / overall ICIR (0.026) = **9x ratio** → recent-bias trigger HIGH
- 2008-2014이 명확히 reverse → 가설 조건부조차 sample-selected 가능성

---

## 3. Codex Round 응답 (전체 7 concerns)

| ID | Severity | Concern | Resolution |
|---|---|---|---|
| C1 | HIGH | 모든 graduation metric fail | honest_verdict NOT MET 명시 |
| C2 | HIGH | universe 제약 미적용 (3064 → 773) | STR_1700 audited universe 적용, 재측정 |
| C3 | HIGH | AX-007 cash overlay overclaim | classification='overlay_not_alpha' 정직 표기 |
| C4 | HIGH | RF-A3 recent-bias 9x | challenge_flag 추가 |
| C5 | HIGH | challenge_note 누락 | 본 문서 동시 작성 |
| C6 | MEDIUM | DSR n_trials=5 understated | n_trials=10 (Iter7 4-spec + Iter8 5-spec + 1) |
| C7 | MEDIUM | post-neutralization 미실행 | mom12-orthogonal 적용, IC=-0.009 |

Codex VETO_FLAG: FALSE (단순 REJECT — 데이터 자체로 알파 부재 입증, veto 불필요)

---

## 4. Lessons & L-209 Draft

### L-209 (proposed — for L-code 적립)

**Title**: "KR Liquidity_Risk family — unconditional fail + regime-conditional partial fail; single-axis regime overlay rescue insufficient"

**Conditional learning**:
- Condition: market=KR, family=Liquidity_Risk (L01_Amihud single + L01-L11-L12-R13 composite), universe=KOSPI200∪KOSDAQ150, structure=long-only top-20 single-axis 또는 4-axis composite, period=2004~2023
- Outcome: unconditional IC=-0.05 (Iter 7 composite), regime-conditional IC=-0.005 (Iter 8 single-axis BULL/NORMAL active)
- Mechanism: (a) KR retail-driven market에서 illiquidity premium 부재 / (b) BULL 국면 illiquid 종목 underperform (가설 reverse) / (c) NORMAL 부분 입증되나 통계 유의성 부재 / (d) cash overlay = overlay-not-alpha → mechanism break 미해소
- Exclusion: regime-overlay rescue로 single-axis liquidity signal 살릴 수 없음
- Exception: 향후 Liquidity_Risk family 사용 시 long-short 또는 Kelly fractional sizing 등 AX-007 다른 예외 (#3 50+ 분산, #4 ML sizing) 시도 필요

### Cross-sprint comparison

| Iter | Family | Structure | Active IC | ICIR | Verdict |
|---|---|---|---|---|---|
| 7 | L01+L11+L12+R13 (Liquidity×Tail composite) | EW 4-axis | -0.051 | -0.48 | NOT MET |
| 8 | L01_Amihud single, regime-conditional 70/30 | multi-sleeve | -0.005 | -0.044 | NOT MET |

→ Liquidity_Risk family 자체가 KR market에서 alpha origin으로서 한계 있음.

---

## 5. Recommendations (Sprint Decision)

### Option A — Sprint 종결 + L-209 적립 (권고)
- Iter 7+8 연속 fail → Liquidity_Risk family 자체에 대한 confidence 소진
- Existing portfolio (STR_1631 80% + STR_1656 20% + STR_1700) admission cycle re-sequence
- 절약된 budget을 다른 family 새 sprint에 배정

### Option B — Iter 9 cross-family pivot
- **Pivot A**: Growth × Investor_Flow residualized (DART quarterly + investor_wide.parquet)
  - Cross-family + KR domestic flow signal — STR_1700과 직교 가능
- **Pivot B**: Skewness Forensics × CFO accrual (Chen-Hong-Stein 2001 + Sloan 1996)
  - tail-risk × earnings quality — multi-axis 가능

### Option C — re-design with AX-007 다른 예외
- 현 Iter 8은 EXCEPTION#1 (multi-sleeve) 시도 → mechanism insufficient
- EXCEPTION#3 (50+ 분산) 또는 #4 (ML sizing Kelly fractional) 재시도 가능하지만 alpha origin이 약하면 효과 제한

**최종 Alpha Agent 권고: Option A 또는 Option B Pivot A.**

---

## 6. AX Compliance — Honest Statement

| AX | Original Claim | Honest Status |
|---|---|---|
| AX-003 (KR value EP) | EXCLUSION | EXCLUSION holds (no value) |
| AX-004 (single quality) | EXCLUSION | EXCLUSION holds (no quality) |
| AX-005 (BAB single-sleeve) | EXCLUSION | EXCLUSION holds (Liquidity_Risk ≠ low-beta) |
| AX-007 (single-sleeve top-20) | EXCEPTION#1 (multi-sleeve) | **EXCEPTION DECLARED BUT INSUFFICIENT** — cash sleeve = overlay, not independent alpha. Mechanism break 잔존. |

본 alpha는 AX-007 EXCEPTION#1을 형식상 충족하나, Codex C3 지적대로 **실질적 mechanism rescue는 미달성**. 정직하게 'overlay_not_alpha' 분류.

---

## 7. Process Integrity (AX-002)

- Window isolation: train_window + validation_window only (sig_dates ≤ 2023-11-30, lockbox 미접근)
- PIT C9: regime_state lag-1 적용
- PIT C14: load_month_factors() Usable_Date <= sig_date
- Method shopping log: candidates_tried=3 (under 5 limit)
- Codex round invoked: TRUE
- Lineage recorded: TRUE
- No silent override: 모든 결과 정직 기록, graduation FAIL 표기

---

## 8. Hand-off

**Status transition**: SPEC_APPROVED → ALPHA_DONE (graduation=FAIL, recommend_termination=TRUE)
**Risk Agent 진행 여부**: 결정권자(Q-Lead)에게 위임. Alpha 부재 명확하므로 Risk/Optimizer 진행 무의미. Sprint termination 권고.
**Next WT 후보**: WT-D20260427_001 (Growth × Investor_Flow) 또는 sprint 완전 종결.
