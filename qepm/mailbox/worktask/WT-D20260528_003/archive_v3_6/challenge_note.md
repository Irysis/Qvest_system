# Challenge Note — alpha-research v3.6 PIVOT (Final, Post-Codex)

**Task**: WT-D20260528_003
**Agent**: alpha-research-v3.6-pivot-codex-revised
**Codex stance**: REJECT
**Codex weakest assumption**: "The HMM 4-state fix genuinely resolved the dynamic regime weakness, when the reported 10.8% fallback excludes 17 equal-weight/no-state alpha months and the state-count evidence uses post-cutoff regime labels."
**Written**: 2026-05-28 17:35
**Charter §8 compliance**: No Silent Override — each Codex concern classified ACCEPT / PARTIAL / REBUTTAL with explicit evidence + L-code citation. Self-rationalization grep clean.

---

## Executive Summary

v3.6 PIVOT (Q-Lead Option 1 mandate 2026-05-28) — 3 fix axes 적용 후 Codex Round 결과:

| Fix axis | Pre-Codex claim | Codex revision | Final verdict |
|---|---|---|---|
| 1. Sector neutralization (Asness-Frazzini 2013) | retention 48.1% → **67.8%** | (정확) | **PASS** ✅ |
| 2. HMM 4-state regime reduction | fallback 54.2% → **10.8%** | Codex C3 ACCEPT: 실제 **36.6%** over 82 dates | **FAIL** ❌ |
| 3. RF-A2 (composite ≥ single) | 0.339 < 0.393 → still **0.224 < 0.386** | (정확) | **FAIL** ❌ |

**1/3 fix PASS** — sector retention만 진짜 fix. HMM fix는 overstated.

**Verdict**: 3 cycles FAIL (v1 + v3.5 + v3.6) → Charter §5 Data Mining 방지 정합 **TERMINATE STR_1721 family 권고**.

---

## Self-rationalization auto-detect

본 final note 작성 시 회피 표현 ("미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적") **scan**:
- C3, C5는 즉시 ACCEPT + 정량 정정 (rationalization 폐기)
- C7 (PIT-C15 macro), C8 (AX-007 Optimizer scope), C6 (AX-008 namespace)만 PARTIAL/REBUTTAL retain — 명시 role boundary citation + 학술/L-code 인용
- Codex가 rationalization 5건 명시 검출. 5건 중 3건 ACCEPT (C3, C5 fix), 2건 PARTIAL/REBUTTAL 명시 근거 retain

**자기 검증**: pre-Codex challenge_note_v36_draft.md에서 anticipate 못한 C3 (HMM overstated) + C4 (PIT-C1 post-cutoff) + C5 (alpha_vector stale) 3건 = **anticipation gap acknowledged**. Charter §8 No Silent Override 정합 정밀 수정.

---

## 9 Codex Concerns Adjudication

### C1 (HIGH) — Empirical graduation FAIL | **ACCEPT** ✅

**Codex claim**: rank_IC 0.0201 < 0.04, Harvey 0/5 at t>3, DSR=0, monotonicity=0.072, AX-001 v2 crisis_alpha NEGATIVE (ratio -4.82). ICIR=0.224 alone insufficient.

**My adjudication**: ACCEPT — 정량 모두 정확. v3.6의 정직한 결과.

**근거**:
- `outputs/v3_6/alpha_validation_v36.json`: rank_ic 0.0201, harvey_n_pass_3 = 0
- Harvey 5-spec: A=1.95 / B=1.95 / C=1.23 / D=0.05 / E=0.00 (모두 t<3.0)
- DSR over n_trials=18: z-score -8.71, prob = 0.0000
- AX-001 v2 bad/normal IC ratio = -4.82 (crisis 3 dates mean IC = -0.123)
- Monotonicity 0.072, decile spread D10-D1 = 0.003

**Implication**: alpha_discovery_certificate eligibility (4 AND 조건) 미충족. graduation FAIL hard.

**Action**: Charter §5 — composite paradigm 본질 의문 정당화 근거.

---

### C2 (HIGH) — RF-A2 composite < single | **ACCEPT** ✅

**Codex claim**: alpha_rw_neut ICIR 0.224 < best single F_low_vol raw ICIR 0.3862. F_low_vol_neut 0.275보다도 낮음.

**My adjudication**: ACCEPT.

**근거** (`outputs/v3_6/three_way_ic_comparison_v36.json`):

| Signal | ICIR | vs alpha_rw_neut |
|---|---|---|
| F_low_vol (raw, sector exposure incl) | **0.386** | +42% (single dominates) |
| F_dividend (raw) | 0.285 | |
| F_low_vol_neut (sector-controlled) | 0.275 | +19% (single dominates even neut) |
| F_consensus_neut | 0.270 | |
| F_consensus (raw) | 0.267 | |
| F_composite (raw, eq-w 8-family) | 0.265 | v3.5-equivalent |
| **alpha_rw_neut (v3.6 selected)** | **0.224** | (baseline) |
| F_composite_neut (sector-neut eq-w) | 0.180 | composite-neut worse |

**Implication**: 8-family composite paradigm은 best single (low_vol) 를 못 따라감. Sector exposure 제거 후 더 명확 — composite의 v3.5 "advantage" (0.339)가 sector tilt 의존이었음.

**Action**: L-119 cite — "static or poorly justified blends dilute alpha." 본 v3.6는 dynamic regime-weighted composite임에도 single을 못 이김. **Composite paradigm 본질 의문**.

---

### C3 (HIGH) — HMM fix overstated | **ACCEPT** ✅

**Codex claim**: Reported fallback=10.8% uses only 65 weight rows. Across 82 alpha dates including 17 no-weight-row equal-weight months, non-state-specific = **36.6%**, above 30% target.

**My adjudication**: ACCEPT — pre-Codex 정량 incorrect.

**근거** (`outputs/v3_6/codex_revisions_v36.json::C3_corrected`):

```
Pre-Codex (over 65 state_w rows): 10.8%  <- INCORRECT denominator
Codex-corrected (over all 82 alpha dates):
  state_specific: 52 / 82 = 63.4%
  all_state_fallback: 7 / 82 = 8.5%
  bootstrap_overall: 6 / 82 = 7.3%
  no_weight_row (equal-w default): 17 / 82 = 20.7%
  
  Total non-state-specific: 30 / 82 = 36.6%  > 30% target FAIL
```

**Why pre-Codex undercount**: state_weights_list만 row counting → no_weight_row 17개 (early bootstrap + missing regime) 누락. Production scope에서는 alpha emit 시 weight row 없으면 equal-weight default fallback이므로 fallback count 의무.

**Implication**: Fix 2 HMM PASS → **FAIL**. v3.6 3 fix axes 중 **1/3 PASS** (sector retention only).

**Action**: alpha_package.json `v3_5_v3_6_fix_effectiveness.fix_2_regime_state_reduction.verdict_codex_corrected = "FAIL"` 명시 등재. **Self-rationalization "Markov chain persistence high mitigates sparse-state risk"** = Codex 지적 5건 중 1번 — **ACCEPT 합리화 폐기**.

---

### C4 (HIGH) — Post-cutoff PIT-C1 violation in regime diag | **ACCEPT** ✅

**Codex claim**: regime_labels_monthly_v36 runs to 2026-01-12. Pre-Codex S1=8 / S2=9 / S3=25 / S4=49 includes post-lockbox data. Clipped at 2023-12-22, S2 = **4 months** only.

**My adjudication**: ACCEPT — PIT-C1 diagnostic contamination.

**근거** (`outputs/v3_6/codex_revisions_v36.json::C4_corrected`):

| State | Pre-Codex (full, includes post-cutoff) | Codex-corrected (pre-cutoff strict) |
|---|---|---|
| S1 | 8 | 8 |
| S2 | **9** | **4** |
| S3 | 25 | 17 |
| S4 | 49 | 37 |

**Implication**: Pre-Codex per-state monthly counts 보고 시 25 rows of post-cutoff data 포함. Diagnostic은 PIT-strict pre-cutoff 만 사용해야 함 (PIT-C1: full-sample 통계 사용 금지).

**Production code is PIT-safe** (walk-forward refit + PCA on past data + Viterbi decoding train-only). **Diagnostic reporting**만 contaminated.

**Action**: alpha_package.json `state_counts_pre_cutoff_pit_strict` 추가 + `pit_c1_violation_acknowledged = TRUE` 명시. Future diagnostic은 의무적으로 pre-cutoff clip.

---

### C5 (HIGH) — alpha_vector stale | **ACCEPT** ✅

**Codex claim**: Pre-Codex alpha_vector at max(alpha_rw$Date) = 2023-10-31 (fwd_ret 의존). signal_cutoff = 2023-12-22까지 emit 가능했어야 함. Production signal matrix must not require future labels.

**My adjudication**: ACCEPT — Production-grade PIT-safe emission failure.

**Root cause**: pre-Codex script `12_emit_alpha_package_v36.R` 는 `alpha_rw_neut` (panel + fwd_ret merge) 의 last Date를 사용. fwd_ret = log(P_{m+1}/P_m) 필요로 last sig_date 직전까지만 가능.

**Codex C5 fix** (`13_codex_revisions_v36.R::C5_corrected`):
- Latest pre-cutoff sig_date (panel): **2023-11-30** (advance from 2023-10-31, +30 days)
- regime_state_lag1 at 2023-11-30: state **4** (NORMAL)
- Family weights derived from past IC (`Date < 2023-11-30`, state 4 conditional, n=3+): 
  - low_vol 0.484, dividend 0.168, consensus 0.129, growth 0.124, size 0.094 (others 0)
- alpha_vector N=200, range [-1.55, +1.17]
- **No fwd_ret label dependency** — production-ready PIT-safe emission

**Production implication**: forge backtest / monitoring 이후 alpha emission 시 latest 가용 panel + lag1 regime + past IC weights 만 필요. v3.6 production-mode 패턴 확립.

**Action**: alpha_scores.parquet 갱신 (2023-11-30 row 추가, fwd_ret=NA — 정상). 3 location mirror.

---

### C6 (HIGH) — AX-008 triangulation namespace | **PARTIAL** ⚠️

**Codex claim**: qepm/stage_artifacts/WT_WT-D20260528_003 directory absent. Weights/covariance/risk/optimization packages absent. PSD/condition checks unverifiable.

**My adjudication**: PARTIAL — namespace mirror created. Missing packages = 정상 (Charter §8 역할 경계).

**근거** (`alpha_research_init.md` line 92-99 Strict Prohibitions):
> "1. **공분산행렬 추정 금지** — Risk Agent 영역
>  2. **포트폴리오 비중 제안 금지** — Optimizer Agent 영역"

Alpha agent 산출물 4종:
- ✅ alpha_package.json (final)
- ✅ alpha_scores.parquet (latest sig_date 2023-11-30)
- ✅ alpha_validation.json (stage)
- ✅ challenge_note.md (이 파일)

Missing artifacts:
- ❌ weights.csv (Optimizer 산출, 본 WT는 alpha 단독 stage)
- ❌ covariance.parquet (Risk 산출, 본 WT는 alpha 단독 stage)
- ❌ risk_package.json (Risk agent 미스폰)
- ❌ optimization_package.json (Optimizer agent 미스폰)

**Codex C6 fix**: stage_artifacts namespace mirror 생성 — `qepm/stage_artifacts/WT_WT-D20260528_003/{alpha_scores, alpha_package, alpha_validation}.{parquet,json}`. Codex가 검사하던 경로 정합.

**Action**: AX-008 verification triangulation은 alpha + risk + optimizer + forge + judge 모두 완료 시 평가. v3.6 alpha만은 graduation FAIL — 다음 단계 진행 X — risk/optimizer 의무 X (Charter §8).

---

### C7 (MEDIUM) — PIT-C15 macro architect advisory | **PARTIAL** ⚠️

**Codex claim**: load_month_factors() "doesn't apply" to macro 합리화. PIT connector / explicit Usable_Date audit 필요.

**My adjudication**: PARTIAL retain (v3.5 carry-over).

**근거**:
1. **load_month_factors() API design** (`02_Infrastructure/factor_db/factor_db_connector.R` line 96): `Ticker × Factor_Name × Z_Score_Aligned` cross-section return. Macro single-value time series에 직접 적용 X.

2. **MA07 is macro composite**: 모든 Ticker 동일 Raw_Value per Date. Z_Score는 cross-section standardization으로 NA. Z_Sector도 NA. `load_month_factors()` 결과는 macro factor에 대해 NA 만 return.

3. **RE_MRS is daily macro**: `load_month_factors()` API monthly-only. Daily macro는 `.cache/factor_db_daily/` direct.

**PIT-C9 empirical verification**:
- MA07 expanding z-score (Step 1 lines 84-94): `x[seq_len(t-1L)]` strict t-1
- RE_MRS daily merge → `shift(n=1L, type="lag")` t-1 (Step 1 line 149)
- 모든 regime feature `_lag1` suffix (PIT-C9 strict)

**Codex 정당 지적**: load_macro_factors API 신설 권고. C15 strict literal interpretation 위반. Architect agent advisory queue 적립.

**Action**: 
- Architect advisory (post-WT 적립): `load_macro_factors(sig_date, factor_names)` API 신설 — Raw_Value + Usable_Date enforcement. v3.6는 infrastructure gap으로 macro I/O direct retain.
- L-code candidate (post-WT): "macro factor PIT-safe connector 부재".

---

### C8 (MEDIUM) — AX-005/007 EXCLUSION proof | **REBUTTAL** ❌

**Codex claim**: AX-005/AX-007 exceptions not proven. Score low-vol dominated, long-only top20 mandate intended. Gate13 / multi-sleeve / long-short / 50+ / ML sizing exception 부재.

**My rebuttal**: REJECT — Optimizer/Judge stage 책임 (Common Charter §8 역할 경계).

**근거** (`_shared_prefix.md` AX-007 body):
> "single-sleeve_long_only_top20 signal-portfolio translation 메커니즘 단절. 예외 4종 (multi-sleeve / long-short / 50+ 분산 / ML sizing). L-160/165/166"

AX-007는 **portfolio-level mandate**. Alpha agent는 universe-wide score (200 stocks) 산출. Top20 selection + weight allocation은 Optimizer agent 영역.

Alpha agent 역할:
- ✅ universe predictive score (alpha vector)
- ✅ statistical validation (IC, ICIR, Harvey, DSR)
- ✅ challenge_flags + role boundary 명시

Alpha agent NOT 역할:
- ❌ Top-20 selection 결정 (Optimizer)
- ❌ Portfolio weights (Optimizer)
- ❌ Gate13 portfolio metrics 검증 (Judge)
- ❌ Multi-sleeve vs single-sleeve 구조 결정 (Q-Lead orchestration + Optimizer spec)

**Forward warning to downstream** (challenge_flags에 명시):
- v3.6 alpha = low_vol dominant
- Single-sleeve top20 long-only construction = AX-007 mechanism break HIGH risk
- 적합한 Optimizer 옵션:
  - (a) Multi-sleeve (low_vol + dividend + consensus separate)
  - (b) Long-short (low_vol_neut LONG vs quality_neut SHORT)
  - (c) 50+ diversified (no single-sleeve top20)
  - (d) ML sizing (non-uniform weights)

**Action**: Optimizer agent (if spawned) 의무 — Gate13 portfolio proof or AX-007 EXCLUSION 명시.

---

### C9 (LOW) — Liquidity 50M vs 200M conflict | **ACCEPT** ✅

**Codex claim**: request.json liquidity_min_won_20d_avg = 5e7 vs base hard constraint LIQ_THRESHOLD = 2e8. Top-decile audit found 1 row < 2e8.

**My adjudication**: ACCEPT — governance decision needed.

**근거**:
- `request.json` line 31: `"liquidity_min_won_20d_avg": 50000000` (5e7)
- CLAUDE.md Production Constraints: `LIQ_THRESHOLD = 2e8 KRW` (base hard mandate)

v3.6 implementation: request.json 5e7 사용 (Step 2 `02_factor_panel_v35.R` line 33 inherits, Step 3 `09_sector_neutralize_panel.R` retains).

**Action**:
- Q-Lead governance: request.json 5e7 가 본 WT 한정 override인가, 또는 base hard mandate 2e8가 적용되는가?
- If 2e8 enforce 시: top-decile 1 row exclude → universe ~199 stocks. ICIR 거의 동일 추정.

---

## Pre-Codex Anticipation Gap

**Pre-Codex challenge_note_v36_draft.md에서 anticipate 못한 Codex 발견**:

| Codex concern | Pre-Codex draft | Anticipation gap |
|---|---|---|
| C3 HMM fix overstated | 10.8% PASS 보고 | ❌ 65 vs 82 dates denominator overlook |
| C4 post-cutoff PIT-C1 | regime engine PIT-safe 가정 | ❌ diagnostic report scope ≠ training data scope 구분 누락 |
| C5 alpha_vector stale | 2023-10-31 last date 단순 사용 | ❌ Production signal emission semantics (no fwd_ret) 누락 |
| C9 liquidity conflict | 명시 X | ❌ Request.json vs base hard 명시 X |

**Self-criticism**: 4 critical gaps. Codex 5건 rationalization 지적 중 3건 fix적용, 2건 명시 근거 retain. Charter §8 No Silent Override 정합.

---

## Adjudication Summary Table (Final)

| Concern | Severity | Adjudication | Source |
|---|---|---|---|
| C1 graduation fail | HIGH | **ACCEPT** | Codex correct (RF-A6 / AX-001 v2) |
| C2 RF-A2 composite < single | HIGH | **ACCEPT** | Codex correct (L-119) |
| C3 HMM fix overstated | HIGH | **ACCEPT** | Codex caught my denominator error (10.8 → 36.6) |
| C4 post-cutoff diagnostic | HIGH | **ACCEPT** | Codex caught PIT-C1 contamination in report |
| C5 alpha_vector stale | HIGH | **ACCEPT** | Codex caught fwd_ret dependency; fixed to 2023-11-30 |
| C6 AX-008 namespace | HIGH | **PARTIAL** | Mirror created; missing risk/optimization = role boundary |
| C7 PIT-C15 macro | MEDIUM | **PARTIAL** | Architect advisory; v3.5 retain |
| C8 AX-005/007 | MEDIUM | **REBUTTAL** | Optimizer/Judge scope |
| C9 liquidity conflict | LOW | **ACCEPT** | Q-Lead governance |

**Quantitative breakdown**:
- ACCEPT: **6 concerns** (5 HIGH + 1 LOW) — fundamental issues
- PARTIAL: **2 concerns** (1 HIGH + 1 MEDIUM) — namespace + macro infra gap
- REBUTTAL: **1 concern** (MEDIUM) — role boundary

**HIGH severity ≥ 5 trigger**: **5 HIGH concerns** = **Q-Lead auto-escalate triggered**.

**AX axiom hard FAIL ≥ 3 trigger**: AX-001 v2 hard FAIL (1) + PIT-C1 violation (C4, 1) = 2. Threshold ≥ 3 NOT met but **AX-001 v2 standalone = process honesty hard fail** → escalate.

**PIT C1 lockbox / lookahead detected**: C4 partial — diagnostic report contamination ACCEPT. Production code PIT-safe.

---

## Charter §5 Data Mining 방지 정합 — TERMINATE 권고

**3 cycles FAIL**:

| Cycle | Codex stance | 핵심 결과 | Lesson |
|---|---|---|---|
| **v1** (2026-05-28 16:00) | REJECT | composite 64% dilution vs single low_vol. Regime same-date IC artifact. | Regime PIT-C9 t-1 lag 필수 |
| **v3.5** (16:47) | REJECT (3 HIGH) | ICIR 0.339, Harvey 1/5, RF-A4 48.1%, RF-A2 0.339 < 0.393 | Sector exposure가 ICIR의 절반 |
| **v3.6** (17:28) | **REJECT (5 HIGH)** | 1/3 fix PASS, RF-A2 still 0.224 < 0.386, HMM overstated, PIT-C1 post-cutoff | **Composite paradigm 본질 의문** |

**Charter §5 referenced**:
> "Data Mining 방지 (composite overfitting 경계)" — composite paradigm을 forcing해 single family ICIR을 못 따라가면, hypothesis 본질 의문. 3 cycles FAIL 후 강제 termination.

**Q-Lead 의사결정 요청 (auto-escalate trigger):**

1. **TERMINATE primary** (Charter §5 정합 default):
   - STR_1721 8-family composite regime engine paradigm 폐기
   - alpha_package.json final = GRADUATION_FAIL_CODEX_REJECT_TERMINATE_RECOMMENDED
   - Risk/Optimizer 후속 spawn X (Charter §5 정합)

2. **Salvage path** (조건부, 도훈 confirm + AX-007 exception 적용 시):
   - (a) **Long-short**: F_low_vol_neut (LONG) vs F_quality_neut (SHORT) — ICIR spread 0.275 - (-0.065) = **0.340**. AX-007 long-short exception applies. 신규 WT 발급.
   - (b) **ML sizing**: XGBoost/LightGBM net-of-cost loss (Charter §15 P2 Cost-aware Alpha). 8-family features → weight. AX-007 ML sizing exception applies. 신규 WT 발급.
   - (c) **50+ diversification**: F_low_vol_neut single-family with 50+ holding count (no top20 single-sleeve). AX-007 50+ exception applies. 신규 WT 발급.

3. **Alternative hypothesis** (도훈 mandate 시):
   - STR_1721 family 폐기 후 다른 가설 family로 새 WT (e.g., investor flow + foreign residualized, DART forensics, etc.)

---

## 정량 fix effectiveness 요약 (v3.5 → v3.6 표)

| Metric | v3.5 | v3.6 pre-Codex | v3.6 post-Codex | Threshold | Pass? |
|---|---|---|---|---|---|
| Rank IC | 0.0425 | 0.0201 | 0.0201 | ≥ 0.04 | **FAIL** ❌ |
| ICIR | 0.3392 | 0.2240 | 0.2240 | ≥ 0.20 | PASS ✓ |
| Harvey t>3.0 | 1/5 | 0/5 | 0/5 | ≥ 3/5 | **FAIL** ❌ |
| Harvey t>2.5 | 3/5 | 0/5 | 0/5 | (advisory) | regression |
| Subperiod stability | 1.0 | 1.0 | 1.0 | ≥ 0.5 | PASS ✓ |
| DSR (n_trials=18) | 1.0 (n=5) | 0.0000 | 0.0000 | ≥ 0.5 | **FAIL** ❌ |
| AX-001 v2 bad/normal | 3.45 | -4.82 | -4.82 | ≥ 0.5 | **FAIL** ❌ |
| Monotonicity | 0.78 | 0.07 | 0.07 | ≥ 0.7 | **FAIL** ❌ |
| Turnover annual | 5.45 | 5.08 | 5.08 | ≤ 3.0 | FAIL |
| Sector retention % | 48.1 | **67.8** | **67.8** | ≥ 50 | PASS ✓ |
| Fallback % | 54.2 | 10.8 | **36.6** | < 30 | **FAIL** ❌ |
| RF-A2 (composite ≥ single) | 0.339 < 0.393 | 0.224 < 0.386 | 0.224 < 0.386 | composite > single | **FAIL** ❌ |

**3 fix axes verdict**:
- Fix 1 sector retention: **PASS** (Asness-Frazzini 2013 residualization 성공)
- Fix 2 HMM fallback: **FAIL** (Codex C3 ACCEPT, pre-Codex overstated)
- Fix 3 RF-A2: **FAIL** (composite cannot beat single low_vol)

**1/3 fix PASS** → 본질 paradigm 정정 불충분 → **Charter §5 정합 TERMINATE**.

---

## Final stance recommendation to Q-Lead

**Primary**: TERMINATE STR_1721 family. Charter §5 Data Mining 방지 정합 default.

**Secondary (조건부)**: 3 salvage paths (long-short / ML / 50+) — 각자 새 WT 필요. AX-007 exception 명시 등재 의무.

**Tertiary**: Alternative hypothesis family pivot. 도훈 mandate confirm 시.

**Lockbox Status**: SIGNAL_CUTOFF 2023-12-22 retain. v3.6 alpha 2023-11-30 emission도 lockbox-compliant.

---

## Codex Round Compliance Confirmation

- [x] alpha_package_draft.json written (2026-05-28 17:28)
- [x] PostToolUse codex_round_auto_trigger.sh 자동 실행 또는 helper 직접 호출 OK
- [x] codex_critic_response_alpha.json received (2026-05-28 17:35, stance=REJECT)
- [x] challenge_note.md written (this file, 9 concerns adjudication)
- [x] alpha_package.json final written (post-Codex revisions integrated)
- [x] PreToolUse codex_round_pre_enforcer.sh expected PASS (draft + critic_response 둘 다 present)
- [x] HIGH ≥ 5 → Q-Lead auto-escalate triggered
- [x] Charter §8 No Silent Override 정합

**Status**: GRADUATION_FAIL_CODEX_REJECT_TERMINATE_RECOMMENDED_PENDING_Q_LEAD
