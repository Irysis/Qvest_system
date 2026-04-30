# Literature Scan Summary — WT-D20260430_001
## Regime-Conditional Dynamic Blending Alpha (meta-allocation alpha)

**Scope**: STR_1715 PG2 100% blend weight 동적 조절 자체가 alpha source인지 검증.
3 Pillar (Regime Detection × Alpha Momentum × Dynamic Allocation) 자유 탐색 명령 + 도훈 명시 (2026-04-30).
**Tool**: arxiv MCP + 9 query strands (ML / regime / Korea / change-point / online learning / RL / Black-Litterman). Jina (paid) unavailable.

---

## Section 1 — Full Picks (12 papers, 11 distinct authors)

| # | Anchor | Year | Citation | Pillar | Adoption |
|---|--------|------|----------|--------|----------|
| L1 | Hamilton (1989) — Markov-Switching AR | 1989 | *Econometrica* 57(2), 357–384 | A | Pillar A baseline (legacy). Crisis_Prob already in `.cache/msm_hybrid_latest.parquet` (Avg_Prob from MS-AR fit). |
| L2 | Adams-MacKay (2007) — Bayesian Online Change-Point Detection | 2007 | *NIPS preprint* arXiv:0710.3742 | A | BOCPD on STR_1715 monthly returns → alpha decay structural break detection. Used as Pillar B input. |
| L3 | Tsaknaki, Lillo, Mazzarisi (2024) — Bayesian AR-Online CPD with Time-Varying Parameters | 2024 | arXiv:2407.16376 (stat.ML) | A | BOCPD upgrade. AR(p) order + variance/correlation scoring rule. **Selected** as variance-of-alpha estimator. |
| L4 | Shu-Mulvey (2024) — Dynamic Factor Allocation Leveraging Regime-Switching Signals | 2024 | arXiv:2410.14841 (q-fin.PM) | A+C | **PRIMARY ANCHOR**. SJM (sparse jump model) per-factor + Black-Litterman dynamic IR=0.4-0.5. 7 long-only indices. **Direct architectural template**. |
| L5 | Lee, Chorok (2026) — Regime-Dependent Predictive Structure (Granger Causality) | 2026 | arXiv:2601.10732 (q-fin.RM) | A+B | **Student-t HMM > Gaussian (69% vs 0% detection 2011)** + Value→Size 9-day Granger lead time crisis only. Lead-time empirical evidence. |
| L6 | Lee, Chorok (2025) — Not All Factors Crowd Equally | 2025 | arXiv:2512.11913 (q-fin.PM) | B | **Hyperbolic alpha decay α(t)=K/(1+λt)** R²=0.65 momentum factor. **Mechanical vs judgment-based factor split**. crowding → tail risk asymmetry: mom 0.38× crash, reversal 1.7-1.8× crash. 1963-2024 sample. |
| L7 | Singha (2025) — Discovery of a 13-Sharpe OOS Factor: Drift Regimes | 2025 | arXiv:2511.12490 (q-fin.TR) | A+B | Drift regimes = stock-specific (60%+ positive 63d window). 1000 randomization p<0.001. **Drift-regime overlay >> RAW factor** template. SR 7+ at 30% perturbation. |
| L8 | Zhang, Goel, Ahmad, Szabo (2025) — RegimeFolio | 2025 | arXiv:2510.14986 (q-fin.PM) | A+C | VIX classifier + Random Forest/GBM sector ensemble + shrinkage MV. SR 1.17, MDD -12pp lower than benchmark. **Regime → sector → ML stacked**. |
| L9 | Chen-Li-Saunders (2025) — Exploratory Mean-Variance with Regime-Switching (EMVRS) | 2025 | arXiv:2501.16659 (q-fin.PM) | C | RL EMVRS + OC learning > TD learning. **Real market data study superiority**. RL allocation 정량 evidence (legacy: Jiang-Xu-Liang 2017). |
| L10 | Kim, Choi, Lee, Kim, Choi, Lee, Yongjae (2025) — DSL: Decision by Supervised Learning + Deep Ensembles | 2025 | arXiv:2503.13544 (cs.LG) | C | **KAIST 한국 저자 그룹**. Sharpe/Sortino reward predict portfolio weights directly + ensemble variance reduction. Korean academic anchor. |
| L11 | Kang, Sungwoo (2026) — Information Propagation Across Investor Types: TE Networks | 2026 | arXiv:2603.20271 (q-fin.ST) | B | KR (KOSDAQ + KOSPI) 2020-2025 5y. **Foreign-Institution-Individual TE network sparse + structurally heterogeneous**. **MI = 0 daily horizon** finding 신호: daily regime → monthly weight 만 의미. |
| L12 | Cho, Bae, Kim (2026) — Investor risk profiles of LLMs | 2026 | arXiv:2603.09303 (q-fin.PM) | C | KAIST 김장호 KR 저자. LLM consistency context (실험 설계 참조). |

**복합 reference (legacy seed, 사용자 제공)**:
- Gupta-Kelly (2019) "Factor Momentum Everywhere" *JFE* — verified seed, mechanism reference
- Ehsani-Linnainmaa (2022) "Factor Momentum and the Momentum Factor" *J Finance* — verified seed
- Avramov-Cheng-Metzker (2023) "ML vs. Economic Restrictions" — verified seed
- Lopez de Prado (2016) HRP / NCO clustering — verified seed
- Black-Litterman (1992) — verified seed (Shu-Mulvey 2024 application 사용)
- Garleanu-Pedersen (2013) optimal trading — verified seed
- Cesa-Bianchi-Lugosi (2006) Online Learning — verified seed
- Jiang-Xu-Liang (2017) RL portfolio — verified seed

---

## Section 2 — KR 시장 실증 비율

- KR 직접 실증 paper: 2/12 (L11 Kang 2026, L10 KAIST DSL 한국 저자)
- KR mechanism 적합 (한국 적용 가능): 11/12 (US-derived but architecturally portable)
- 단, **L8 RegimeFolio + L4 Shu-Mulvey는 아직 KR-실증 부재 → 본 WT가 KR 1차 검증** (mandate)

---

## Section 3 — 본 WT 적용 매핑 (mechanism → method)

### Pillar A (Risk-Off Regime Detection)
**선정**: existing `.cache/unified_regime_signal_daily.parquet` (3-Layer cascade MSM + FRED MRS + KTRI + VEA + BCS, monthly built monthly + daily refresh) **+** new BOCPD on STR_1715 alpha returns (L3 Tsaknaki).

이유:
1. existing system은 "macro/cross-market" regime 측정 (외부 risk).
2. BOCPD on STR_1715 monthly returns은 "alpha 자체의 structural break" 측정 (internal alpha decay).
3. 둘 결합 → meta-regime score = max(macro_regime_score, alpha_decay_score)
4. PIT 구조: t-1 lag (existing system) + BOCPD posterior at time-t use only data ≤ t-1.

### Pillar B (Alpha Momentum / Decay)
**선정**: Hyperbolic decay α(t)=K/(1+λt) (L6 Lee 2025) on STR_1715 monthly excess returns + rolling Sharpe.

이유:
1. STR_1715 자체 alpha decay 모니터링 → blend weight 결정.
2. STR_1715는 multi-factor composite (Q07/Q25/M08 등 sleeve mix) → "mechanical" 측면 強. Lee 2025 evidence: mechanical 팩터는 hyperbolic decay R²=0.65.
3. Implementation: 36-month rolling SR + hyperbolic fit residual. Recent decay → reduce STR_1715 weight.

### Pillar C (Dynamic Allocation)
**선정**: Black-Litterman with regime priors (L4 Shu-Mulvey 직접 template, alternative L8 RegimeFolio, fallback L9 EMVRS RL).

이유:
1. STR_1715 (Core_Alpha) + Cash 2-asset blend → Black-Litterman 단순 적용 가능.
2. View = "Pillar A regime score → Pillar B alpha momentum → STR_1715 expected return downgrade".
3. Long-only [0,1] 약 STR_1715 weight bounds 자연스러움 (Universe = STR_1715 자체 또는 cash).
4. EMVRS RL (L9)는 더 복잡 — discovery WT 1차 cycle에서는 BL 채택, RL은 future revision.

### 통합 Logic (Integration)
```
t-1 시점:
  macro_regime_score = .cache/unified_regime_signal_daily.parquet ≤ t-1
  alpha_decay_score  = BOCPD posterior on STR_1715 ret_net[1..t-1]
  combined_regime    = max(macro_regime_score / 100, alpha_decay_score)  # [0, 1]

  alpha_momentum     = hyperbolic_fit(STR_1715 ret_net[t-36 .. t-1])
                      → predicted_alpha[t]  (downward bias if decay detected)

  view_BL = predicted_alpha[t] × confidence_from_decay_fit_R2

t 시점 weight:
  weight_str1715 = sigmoid(view_BL × (1 - combined_regime))
                  ∈ [0, 1] long-only
  weight_cash    = 1 - weight_str1715
```

**Backstop (PIT)**:
- macro_regime은 existing system t-1 lagged
- BOCPD posterior at time t-1 use only ≤ t-1 data
- hyperbolic decay fit window [t-36 ~ t-1] (36-month rolling, expanding base)
- view_BL은 PIT-safe (no t leak)

---

## Section 4 — Validation Roadmap

1. STR_1715 baseline (no overlay): 100% weight, 267 mo, SR 1.4625 PG2 reference (Forge AB realized-share-based).
2. STR_1715 + simple MRS overlay (10/20/40% cash by Layer): user explicit baseline.
3. **Our dynamic allocation alpha**: BOCPD + hyperbolic decay + BL. **반드시 baseline #2 대비 우월**.
4. AX-001 v2 측정: crisis_alpha (8 stress periods) + bad/normal IC ratio.
5. AX-007 EXCEPTION_1: multi-sleeve via regime overlay 정합 — STR_1715 (Core sleeve) + Cash sleeve = 2-sleeve.
6. PIT C1~C15 lookahead_detector 자체 검증.
7. Harvey NW HAC t-stat (lag=4 monthly).
8. DSR n_trials = 정확 (3 pillar combinatorial: 1 regime × 1 momentum × 1 allocation = 1 spec, n_trials=3 from paper anchor count).

---

## Section 5 — 합리화 회피 명세

- "literature exhaustively scanned" 합리화 금지 → **arxiv 9 query 전수 명시 + Jina paid 부재 명시**
- "Korean empirical 강력" 합리화 금지 → KR 직접 실증 2/12 명시 (L10/L11)
- "본 mechanism 한국 검증" 합리화 → 1차 검증 mandate (Shu-Mulvey 등은 KR 미실증)

---

## Section 6 — Generated Date

2026-04-30 — Alpha Research Agent (Opus 4.7).
arxiv MCP only (jina paid 부재). 9 search strands: regime+CPD / factor mom decay / KR factor / drift regime / online learning / Bayesian CPD / RL portfolio / dynamic allocation / Black-Litterman.
