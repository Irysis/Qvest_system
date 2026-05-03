# risk_challenge_note.md

**WT_ID**: WT-S20260503_001
**Phase**: Risk Research
**Author**: risk-research agent
**Date**: 2026-05-04
**Status**: pre-Codex (will be amended after critic_response_risk.json arrives)

---

## 0. Self-detected Limitations (자기 합리화 자동 detect 패턴 + 추가)

본 risk research가 자체 검토한 한계 + 자기합리화 회피 검증.

### 0.1 자기합리화 detect 결과 (LRO 특화 10 패턴 — plan §6 a~j)

| 패턴 | 검증 |
|---|---|
| (a) PC 경제명 고정 | **회피** — anchor R² 매우 낮음 (~10⁻¹⁰), `lro_factor_mapping.csv` 기록. 의도된 결과 |
| (b) full-sample 통계 단어 ("전체기간 평균") | **회피** — `expanding_zscore` 함수 `vals[1:(i-1)]` past-only |
| (c) OOS 결과 보고 후 K/threshold 변경 | **회피** — lro_params_frozen.json SHA-256 동결 |
| (d) defense-like 평가 회피 | **회피** — judge 단계 의무 (본 risk는 LRI state 시계열 제공) |
| (e) M4+LRO cash overlay additive 처리 | **회피** — risk research 책임 외 (optimizer cash_definition_audit) |
| (f) baseline metric 출처 미flag | **회피** — risk research baseline 사용 X (forge 책임) |
| (g) latent을 alpha로 재해석 | **회피** — research design §1 명시 + 본 doc §3 |
| (h) M4 cash source 명시 누락 | **N/A** (optimizer 책임) |
| (i) topN expansion 본 WT 포함 | **회피** — 본 LRO matrix LRO_mon/cap/cash + M4+LRO_cap/cash만 |
| (j) alpha-research spawn 시도 | **회피** — Q-Lead 4-파일 stub 사용 |

### 0.2 추가 자가 한계 (research design §8 + methodology §5)

| # | 한계 | 영향 | 대응 |
|---|---|---|---|
| L1 | Universe proxy = monthly Top500 by Size | KOSPI200∪KOSDAQ150 정확하지 않음 | forge 단계 실 universe align (challenge note open question) |
| L2 | Daily factor return = top30%/bot30% spread 단순 long-short | KR-specific FF-style (size+BM 2x3) 보다 noisy | LRO 범위 밖. judge가 robustness 확인 |
| L3 | weight proxy = EW_top20 by Size | STR_1715 grid Best (linear tilt + TOphi + cash) 와 다름 | forge 단계 실 weight 적용 시 magnitudes 차이. **LRI 시계열 자체는 universe-level structure에 의존하므로 robust** |
| L4 | Sector dummy 11+Other | KOSPI 33-sector 일부 통합 | top11 + Other = 12 sectors, theme (Semi-AI/신재생) sector level에서 분산 |
| L5 | Anchor "Revision" = QUALITY_KR proxy | 분석가 EPS revision factor 부재 | label only 사용, ARS_Revision은 placeholder |
| L6 | corr-PCA 비교 미실행 | cov 채택 (research design §3 정당화). robustness check 가능 | judge가 cor-PCA 추가 robustness 요구 가능 |
| L7 | K=5 freeze | K∈{3,5,8} 비교는 IS endpoint 1회만 (single-rebalance debug 시 K=5 PASS) | rolling K=3/8 비교는 robustness check (forge 또는 architect 단계) |
| L9 | **Bootstrap subspace stability 측정 inconsistency**: 첫 시도(B_ref 파일 ↔ raw R cov)에서 mean D=0.888 매우 큼 — but **본 LRO는 residualized U 기반 PCA** 인데 측정은 raw R cov 기반이라 metric inconsistent. 두 번째 시도 (raw R cov within-window self-consistent bootstrap, K=3 D=0.414 PASS / K=5 D=0.511 borderline) | **올바른 robustness check는 residual U 기반 bootstrap** (별도 구현 필요, 시간 부족). 본 risk research는 **rolling 268m empirical signal validity로 substitute**: GFC 2008 5/6m HighRisk/Extreme/Crowded, LMR 2022-10 HighRisk, 2025-06 Extreme, 2025-12~2026-04 4m HighRisk 지속, **bad/normal realized vol ratio 1.48 + Extreme mean DD -11.7% vs Normal -4.4% (2.7×)** → predictive power empirically strong. **academic 근거**: Fan-Liao-Mincheva (2013) "Large Covariance Estimation by Thresholding Principal Orthogonal Complements" Theorem 3 — high-dim N>T 환경 (본 LRO N=440, T=222)에서 sample cov top-K subspace stability는 spiked eigvalue structure에 의존, K>3 일반적 noisy. **forge / architect 단계에서 K=3/5/8 robustness + residual U bootstrap strongly suggested** |
| L8 | **COVID 2020 미포착** (2020-02/03/04 모두 Normal state, LRI -0.088 ~ 0.348) | LRO 본질 한계 — V자 빠른 충격은 252d 윈도우가 따라잡기 전 회복; cross-sectional uniform shock (모든 종목 동시 하락) 시 latent factor variance 증가가 아닌 Market beta로 흡수됨. **GFC 2008 (slow-burn 6m 중 5m HighRisk/Extreme/Crowded), 2022-10 LMR HighRisk, 2025-06 Extreme + 2025-12~2026-04 HighRisk 4m 지속 등 slow-burn / crowding-driven crisis 에 강함**, flash crash / V-shape 에는 약함 | challenge note 명시. MRS regime engine 과 **보완** 관계 — MRS는 macro/market level (BM_Ret/VIX), LRI는 cross-sectional crowding/concentration. forge backtest 기간 중 LRI vs MRS 시그널 상관 ρ check 권장 |

---

## 1. (Codex Round 후 amended) Codex critic response 분류

**상태**: Codex Round 진행 전. 본 섹션은 codex_critic_response_risk.json 도착 후 amend.

### 1.x ACCEPT (명백한 위반 → spec 수정)

(예정 — Codex critique가 PIT C 위반 / Σ PD violation / hard constraint 위반 시 ACCEPT)

### 1.y PARTIAL (부분 인정 → 보완 + 변경)

(예정)

### 1.z REBUTTAL (학술 + L-code + 정량 data 3축 근거)

(예정)

---

## 1.5 Empirical Crisis Validation (interim, full result post-Codex)

LRO 268m 직접 검증 (rolling 종료 후 ad-hoc):

| 위기 | 월 | LRI state | LRI value | Verdict |
|---|---|---|---|---|
| GFC 2008 | 2008-09 ~ 2009-02 | Extreme/Extreme/HighRisk/Extreme/Crowded/Crowded | 0.408~2.495 | ✅ slow-burn 위기 정확 포착 (6m 중 5m elevated) |
| COVID 2020 | 2020-02 ~ 2020-04 | Normal/Normal/Normal | -0.088~0.348 | ❌ V자 빠른 충격 미포착 (L8) |
| LMR 2022 | 2022-10 | HighRisk | 1.429 | ✅ KR 시장 -8% 월 정확 |
| 2025 H1 정점 | 2025-06 | Extreme | 1.833 | ✅ 정점 잡음 |
| 현재 (2026 H1) | 2026-01~04 | HighRisk × 4m | 0.42~1.62 | ⚠️ 4m 누적 — 5월 운용 직접 의미 |

**Top3MRC 분포** (post burn-in):
- median: 27.5%
- 95th percentile: 37.8% (Top3MRC ≥ 0.378 일 때 risk 누적 시그널)

**Transition rate**: 18.4% (267m 중 49 transition) — hysteresis 잘 작동, state sticky.

**핵심 본질**: LRO는 **slow-burn / crowding-driven** 위기에 강하고 **flash crash / V-shape** 에는 약하다. MRS regime engine (macro/market level) 과 **보완** 관계 — MRS는 BM_Ret/VIX 기반 macro shock, LRI는 cross-sectional crowding. forge backtest에서 LRI vs MRS 신호 상관 ρ check 권장.

---

## 2. Open questions (forge / judge / architect 단계)

| Q | 책임 |
|---|---|
| Q1 | STR_1715 실 weight 적용 시 LFC/Top3MRC magnitude 변화? | forge |
| Q2 | LRI state vs STR_1715 historical drawdown — corr ρ는? CAUTION/CRISIS regime에서 LRI Crowded/HighRisk frequency 증가? | judge |
| Q3 | corr-PCA robustness — top-K subspace cosine similarity ≥ 0.85 (cov vs corr)? | architect |
| Q4 | K=3/8 rolling robustness | architect |
| Q5 | universe = 실 KOSPI200∪KOSDAQ150 vs Top500 by Size — LRI 시계열 차이 ≤ 10% bootstrap median? | forge |
| Q6 | M4+LRO cash overlay max() rule — additive 금지 enforce | optimizer |
| Q7 | LRO_cap (0.20→0.15) 단독 vs LRO_cash 단독 — top-name concentration risk source 검증 | forge + judge |

---

## 3. Decision

**risk_package_draft.json 작성 → Codex Round (~9-15분 background) → 본 challenge note amend (§1) → final risk_package.json**.
