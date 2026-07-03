# v3 Plan AMENDMENT v0.6 — Phase 5 결과 + Paradigm Limit + Direction Pivot

**작성**: 2026-05-26 KST Session 85+
**Owner**: Q-Lead (도훈 mandate 진행 중)
**대상**: `PLAN.md` v0.5 (2026-05-24 amendment 후)
**상태**: **DRAFT** — Phase 5 implementation 완주 결과 정리 + paradigm fundamental limit 명시 + next direction proposal
**Trigger**: Phase 5a-d 모두 완주, 5-component Tier 4 ensemble 시도 후 A LASSO Quantile single dominance + forward-looking macro features 시도 진행 중

---

## Section A: Executive Summary

Plan v0.5 Phase 5a-1 (B1) ~ Phase 5d (Tier 4 ensemble) **모두 완주**. Implementation 진단 (option 4) + v3 actual use (option 1) + Tier 4 ensemble 5-component (option 2) sequence 완료.

**핵심 결과**:
1. **Paper-faithful CNN-N reproduce success** — paper CRPS 0.5285 대비 +4.6% (Loose ± 5% 통과)
2. **A LASSO Quantile = best single component** (CRPS 0.5113) — 가장 simple 모델 우위
3. **Tier 4 ensemble FAIL** — A single 대비 +2.6% worse (5-component, 3-component 동일 결론)
4. **Forward bear catch fundamental limit** — COVID 2020-02-19 사전 P(-10%) = 1.0% (실제 -42%)
5. **alt data backward-looking signal effect = negative** (Δ CRPS -2~-8%)

**판단**: v3 distributional paradigm은 **시장 변동성 측정 도구**로 작동하나 **약세 사건 사전 감지 능력 부족**. paradigm fundamental limit 인지 + 보완 방향 모색 필요.

---

## Section B: Phase 5 Implementation 결과 (전부 정직)

### B.1 Phase 5a-1.A B1 paper baseline reproduce

**Path 진행**:
1. Initial LSTM 학습 (잘못된 spec) — sweeps 1/2/3 × 216 attempts, CRPS gap +19~22% saturation
2. Paper GitHub 비교 (`prob_nn.ipynb`) — 9건 구체적 차이 발견:
   - Architecture: **CNN** (LSTM 부분 commented out)
   - n_steps: **3** (paper Table 1 "10" 보다 작음)
   - Feature: **GKYZ vol 252d** (rolling std 22d 아님)
   - softplus(0.01 × raw) + 1e-3 offset
   - lr 0.003 / batch 64 / clipnorm 1 / patience 5
3. CNN paper-faithful 재학습:
   - **CNN-Normal**: CRPS 0.5526 ± 0.003 (5-seed) — paper 0.5285 대비 **+4.6%** PASS
   - CNN-Student-t: 0.6585 ± 0.037 (unstable)
   - CNN-Skewed-t: 0.6508 ± 0.031 (unstable)
   - LSTM-Normal (paper LSTM variant): 0.5491 (+4.7% PASS)
   - LSTM-Student-t/SSTD: 0.75-0.79 (large gap, numerical instability)

**결론**: **Normal distribution reproduce는 publication 수준**. Student-t / Skewed-t는 학습 안정성 부족.

### B.2 Phase 5a-1.B Alt Data Ablation

**v2_alt_data 8 features 중 5개 사용** (paper window 2001-2020 coverage filter):
- bbva_market_z, bbva_transmission_z, bbva_macro_composite (BBVA macro)
- us_sector_avg_z, us_sector_dispersion_z (US 섹터 flow)
- 제외: bbva_sovereign_z (2024+), k200_implied_skew/kurt (2017+)

**결과**: Δ CRPS **-2.2% (h=1) ~ -8.4% (h=21)** — alt data 효과 **negative**.

**원인**:
- BBVA macro는 유럽 기반 — KR equity transmission 약함
- US 섹터 flow는 backward-looking (전날 종가)
- CNN seq=3 짧음 — macro signal 활용 부족

### B.3 Phase 5a-2.A B5 NGBoost Baseline

**Spec**: Normal distribution, n_est=500, depth=4, lr=0.01, 5-fold purged WF + 21d embargo.
**결과**: CRPS 0.749 (h=1 21-day forward) — paper 동일 metric 없음, KR equity 첫 적용.

### B.4 Phase 5b Conformal Wrap

ACI (Gibbs-Candes 2021) primary + EnbPI fallback. Simplified version: B1 sample wrap.
**결과**: CRPS 0.572 (B1 + conformal padding) — B1 자체보다 약간 worse (over-conservative).

### B.5 Phase 5c LASSO Quantile GaR (Paradigm A)

**Spec**: sklearn QuantileRegressor with L1 (alpha=0.001), 7 quantile levels τ ∈ {0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95}, 12 core features (lagged returns + rolling vol/mean + rv_22d_z + drawdown_z), purged 5-fold WF.

**결과**:
- Pinball loss = 0.294 (12 features baseline)
- **★ Pooled CRPS = 0.5113** (paper window) — **5-component 모든 중 best single**
- 가장 simple 모델이 가장 정확

### B.6 Phase 5d Neural Lévy SDE (Paradigm C)

**Spec**: Drift + Diffusion + Jump intensity λ + Gaussian jump size, shared encoder 2×64, K_max=3 truncated compound Poisson NLL.
**결과**: CRPS 0.5285 (paper window, 3-comp Tier 4 vs single)

### B.7 Phase 5d Tier 4 Ensemble (3-comp + 5-comp)

**3-comp (B1+C+A)**: CRPS 0.5269 — A single (0.5113) 대비 **+3.04% worse**
**5-comp (B1+C+A+B5+F)**: CRPS 0.5248 — A single 대비 **+2.64% worse**

**Diversity check (Spearman ρ matrix)**:
- 3-comp: 0/3 high (ρ < 0.80) — Diversity PASS
- 5-comp: **2/10 high** (b1-f ρ=0.98, a-b5 ρ=0.84) — Standard activation FAIL

**DM test (5-comp)**:
- ensemble > B1 (sig, -11.06)
- ensemble = C (no diff)
- ensemble < A (sig, +8.22) — **A wins**
- ensemble = B5 (no diff)
- ensemble > F (sig, -14.59)

→ **A LASSO Quantile single이 모든 ensemble 능가**.

### B.8 Phase 5 Bear Event Detection

| Event | Actual | Best model P(-10%) | 평가 |
|---|---|---|---|
| Lehman 2008-09-15 | (train 기간) | NA | NA |
| Euro Crisis 2011-08-08 | -1.9% | 0.10-0.70% | OK (실제 -2% milder) |
| **COVID 2020-02-19** | **-41.6%** | **0.55-1.00%** | **사전 detect FAIL** ❌ |
| P(-10%) high signals 8건 | 모두 post-COVID 반등 | 87.95% max | **100% False Positive** ❌ |

→ **forward bear catch는 v3 distributional paradigm 한계**.

---

## Section C: Paradigm Fundamental Limit 진단

### C.1 Why distributional forecasting cannot catch forward bear?

**Input 한계**: 모든 component (B1/B5/A/F/C)의 input = 과거 변동성 + 과거 수익률 (backward-looking).

**Mechanism**:
- 과거 변동성 → 미래 변동성 inferred (volatility clustering, Engle 1982)
- 변동성 증가 → 분포 width 증가 → P(extreme) 증가
- 그러나 **변동성 spike ≠ bear continuation**:
  - Mean reversion (반등) — high vol 후 회복 (post-COVID 2020-03~04)
  - True bear (지속) — 변동성 + drift 양쪽 변화

→ **모델은 둘을 구분 못함**. P(-10%) high signal이 random에 가까운 직진/반등 결정.

### C.2 Forward-looking signals needed

| Signal | 이유 |
|---|---|
| **Yield curve (Term Spread)** | 6-12개월 선행 recession indicator (Estrella-Hardouvelis 1996) |
| **Credit spread (HY/BBB)** | 신용 시장 stress (Gilchrist-Zakrajsek 2012 EBP) |
| **Put-call ratio (KRX options)** | 옵션 시장 sentiment (forward-looking) |
| **VIX / VKOSPI implied vol** | 옵션 implied (≠ realized, 전망 정보) |
| **Macro composite (Adrian 2019 NFCI)** | 금융 condition multi-factor (forward-looking에 가깝게) |
| **Structural break detector** | regime change immediate detect |
| **Order flow imbalance** | 단기 (intraday) 매수/매도 압력 |

→ Phase 5c LASSO Quantile에 macro 추가 시도 (Session 85+ 진행 중) → 결과 대기.

### C.3 Why A LASSO Quantile is best?

가설:
1. **Distribution이 simple linear quantile mapping에 잘 fit** — KOSPI 1d return 분포가 over-engineered NN 불필요
2. **L1 penalty가 sparse feature selection** — irrelevant feature 제거 효과
3. **CNN/Neural Lévy는 over-engineered** — paper window 4800 obs 작아서 NN 학습 안정성 부족
4. **Linear models의 generalization** — small data + low SNR 환경에서 linear가 NN 능가 정합

→ **"Simple model wins in noisy financial data"** lesson — Hyndman-Athanasopoulos forecasting principle 정합.

---

## Section D: Plan v0.6 권장 변경

### D.1 Phase 5 mandate 결과 명시

PLAN.md v0.5 §5.4 Tier 4 mandate 결과 정리:
- Diversity pass (Standard, 3-comp): ✓
- Diversity fail (5-comp expansion): ✗ (b1-f 0.98, a-b5 0.84)
- DM test ensemble vs A: **A wins (+8.22, sig)**
- **★ Tier 4 mandate 결론**: A single best, ensemble 효과 없음

### D.2 Paradigm 우선순위 재조정 (Phase 6 candidate)

| 단계 | 권장 |
|---|---|
| **Primary** | **A LASSO Quantile (B1 paper-faithful 검증된 baseline)** — 도훈 confirm 필요 |
| Secondary (ensemble candidate) | C Neural Lévy (jump term 가치 있을 수 있음) — Spearman ρ 0.63 vs A (보완) |
| Tertiary | B1 CNN paper-faithful (paper reproduce documented) |
| Drop | B5 NGBoost (a-b5 ρ=0.84 너무 비슷), F Conformal (b1-f ρ=0.98 자명) |

### D.3 Forward-looking macro 시도 (2026-06-26 COMPLETED — NULL, paradigm limit 확정)

**완주**: 멈춰있던 `scripts/331_b1_macro_features.py` 완주 + 2가지 보강 (도훈 mandate 2026-06-26 "새 데이터원 허용").

**3-run 구조** (산출물 절대경로):
1. `scripts/331_b1_macro_features.py` (config `b1_macro.yaml`, paper window 2001-2020) → `03_models/b1_macro_features/macro_features_summary.json`. **결함 발견**: paper window date_end=2020-11-30 + walk-forward test=504 때문에 **COVID 2020-02-19가 test fold 밖으로 떨어져 평가 불가** (직전 세션이 멈춘 채로 못 본 부분). Lehman은 train 기간. → 유일하게 평가된 게 Euro Crisis 2011(-1.9%, 약세도 아님).
2. **확장 window** (`config/b1_macro_ext.yaml`, date_end=2024-12-31 → COVID가 test fold 안으로) → `03_models/b1_macro_features_ext/macro_features_summary.json`. **COVID 최초 평가 가능**.
3. **신규 leading 데이터원** (`scripts/332_fetch_leading_macro.py` + `scripts/333_b1_leading_macro.py`) → `03_models/b1_leading_macro/leading_macro_summary.json` + `multiseed_h21.json`. 331의 macro가 전부 *동행(coincident)* 미국 지표였던 한계를 직격: full-history *선행* 신용/금융여건 6종 추가.

**신규 forward-looking leading 데이터원 (332, .cache/fred_leading_macro.parquet, 8671/8671 full coverage)**:
- `Credit_Baa10Y` (Moody's Baa−10Y, 1953~, GZ-style 선행 신용스프레드)
- `YC_10Y3M` (10Y−3M, Estrella 선호 침체 예측 yield curve, T10Y2Y보다 우수)
- `NFCI_Credit` / `NFCI_Leverage` / `NFCI_Risk` (Chicago Fed NFCI 서브, 1971~ weekly)
- `StL_Fin_Stress4` (St.Louis Fed FSI 현행 vintage, 1993~ weekly)
- ⚠ **ICE-BofA OAS (BAMLH0A0HYM2/BBB) = 공용 FRED API 2023-06-26부터만** 제공(ICE 라이선스) → 백테 window 불가, 정직 제외. KR 고유(VKOSPI/put-call/외인플로우)는 캐시 부재 또는 2017+ coverage(v2 panel k200_implied) 또는 cross-sectional(daily index 분포예측 부적합) → full-window 가용 최강 선행원 = FRED leading credit/NFCI.

**결과 (h=21, 월간 — bear catch에 유의미한 horizon)**:

| feature set | CRPS (seed 0) | CRPS (5-seed mean±sd) | COVID P(-10%) | COVID 백분위 (모델 자체 분포 내) |
|---|---|---|---|---|
| paper_only | 4.640 | **4.48 ± 0.15** | 2.10% (seed0) | **70.7 ± 20.3** |
| **with_leading** ★ | 4.531 (−2.3%) | **7.16 ± 4.29** | 5.37 ± 0.98% | **75.3 ± 13.9** |
| with_macro_old (동행, 331 set) | 6.324 (+36%) | — | 0.65% | 35.1 (worse) |
| with_all_macro | 6.433 (+39%) | — | 0.75% | — |

**판정 — NULL (3중 근거)**:
1. **CRPS 개선은 seed 환상**: with_leading seed-0 −2.3%는 운. 5-seed CRPS 7.16±4.29(한 seed 15.7)로 baseline 4.48±0.15보다 *훨씬 나쁘고* 불안정. R17(skewed-t single-seed instability) 재확인.
2. **COVID 사전 감지 = discrimination 실패가 핵심**: with_leading가 COVID P(-10%)를 2.1%→5.4%로 올린 듯 보이나, **모델의 평소 P(-10%)도 0.85%→3.19%로 같이 부풀음**(분포 전역 fat-tail화). COVID의 *자체 분포 내 백분위*는 70.7→75.3으로 **통계적 무차별**(±20 변동 내), q95 경보선 근처도 못 감. Euro Crisis(-1.9% 약세도 아님)도 P(-10%) 0.25%→5.55%로 같이 뜀 = 표적성 0.
3. **데이터-레벨 메커니즘 확정**: PIT 검증 결과 NFCI/credit 선행지표 자체가 **COVID 직전 경보 무발생** (2020-02-19 NFCI_Credit −0.016 = 완화적, +0.057 spike는 2020-02-21에야). COVID는 **신용시장이 미가격한 외생 비-금융 충격** → 선행 금융여건 신호에 사전정보 부재. price-only가 못 본 *선행* 약세정보를 forward-macro도 **담고 있지 않음**(존재하지 않음).

**→ paradigm limit 확정**: distributional forecasting은 변동성 측정 도구로 유효하나 (forward bear *catch*는) backward price든 forward macro든 **사전 식별 불가**. v0.6 결정규칙대로 **macro null → distributional paradigm limit 확정**.

**PIT 검증**: 모든 외부 series `.shift(1)` t-1 lag(발표 시차) + ffill, feature window=rows[i-seq_len, i)(엄격 과거), target=ret_fwd(미래 label). COVID 예보일 same-day leak 없음 실측 확인. walk-forward train_min 2008 only.

### D.4 Regime-Switching paradigm 시도 (Session 85+ 진행 중)

**진행 중**: `scripts/600_regime_switching.py` v4 — Hamilton 1989 Markov-Switching 2-state / 3-state, paper KOSPI window. statsmodels API 3차례 fix 끝에 progress.

**기대**:
- Bear continuation 직접 detect (P(regime=bear) 명시)
- v3 distributional 보완 또는 대체

### D.5 New Risk 신규 (v0.6 추가)

| Risk | 평가 | Mitigation |
|---|---|---|
| **R15 (v0.6 신규)** Distributional paradigm fundamental limit (forward bear catch) | HIGH | Forward-looking macro / regime detection / event-driven 보완 |
| **R16 (v0.6 신규)** Tier 4 ensemble unable to beat best single (A LASSO) | HIGH | A single을 primary로 confirm, ensemble은 diversification 부가 가치만 |
| **R17 (v0.6 신규)** Single seed instability for Student-t/Skewed-t (CNN std 5.6%) | Medium | Normal distribution primary or multi-seed averaging |

---

## Section E: Phase 6 Entry Criteria (도훈 결정 대기)

Plan v0.5 §1.5.5에서 정의된 Phase 6 (production candidate) 진입 기준:
- ✅ A LASSO Quantile baseline 확보 (CRPS 0.5113)
- ⏸️ macro features 시도 결과 (Session 85+ 진행 중)
- ⏸️ Regime-Switching 결과 (Session 85+ 진행 중)
- ❓ 도훈 mandate "모델 성능 향상" target 어디까지인지 결정

도훈 결정 path:
1. **A baseline production candidate confirm** — 도훈 mandate 2차 (SR/CAGR) 보류 정합
2. **Macro/Regime 시도 후 best 선택** — 결과 후 confirm
3. **추가 paradigm 시도** (forward-looking 다른 sources) — long-term R&D
4. **v3 결산 + v4 paradigm 시작** — distributional → regime/event-driven shift

---

## Section F: Memory 적립 권장 (v3 lessons)

| Lesson | Memory candidate |
|---|---|
| Implementation reproduce는 paper GitHub direct 비교 필수 | `feedback_paper_cite_verification.md` 확장 |
| Backward-looking distributional model은 forward bear catch 한계 | 신규 `feedback_distributional_forecast_limit.md` |
| Diversity ≠ Ensemble Lift (best single can dominate) | 신규 `feedback_ensemble_diversity_caveat.md` |
| Simple model wins in noisy financial data (Hyndman principle 정합) | 신규 `feedback_model_complexity_tradeoff.md` |

---

## Change log

- **2026-05-26 v0.6 DRAFT** — Phase 5a-d 완주 + Tier 4 5-component 결과 + paradigm fundamental limit 진단 + macro/regime 시도 진행 중. 도훈 finalize 대기.
- 2026-05-24 v0.5 — Phase 1 paper verification 12건 정정 (AMENDMENT_v0.5.md).

---

**도훈 confirm 사항 (4건)**:
1. A LASSO Quantile primary baseline confirm?
2. macro features 결과 (진행 중) 기다린 후 v0.6 finalize?
3. Regime-Switching 결과 추가 기다림?
4. Phase 6 (production) 진입 vs Phase 5 추가 시도?
