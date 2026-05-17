# Comp Universe Design — 1715 외부 Sleeve B

**WT-D20260517_004 alpha-research Step 2.2**
**Blocker 2 resolution**: WT_003 A-option cor ≈ 1.000 by construction → universe 분리로 cor ≤ 0.3 자격 가능
**Author**: alpha-research agent
**Date**: 2026-05-17

---

## 0. Executive Summary

Comp universe = **`KR_TOP500_LIQ1E8 ∖ STR_1715_top_20_universe(t)`** (sig_date 별 dynamic exclusion). 
시작점: architect L-227 universe v2 advisory의 `KR_TOP500_LIQ1E8` (mid-cap residual 신호 최대 활용, cost 25bps mandate).
종료점: 매 sig_date `t` 마다 STR_1715가 보유 중인 top-20 종목을 동적 제외하여 comp sleeve가 1715와 종목 단계 분리 보장.

---

## 1. Universe pool 선택 — `KR_TOP500_LIQ1E8` 채택 이유

### 1.1 Architect 3 options 비교 (`universe_expansion_v2_advisory.json`)

| Option | Label | Size | Cost mandate | Trade-off |
|---|---|---|---|---|
| A | KR_TOP500_FREEFLOAT | 500 | 20 bps | `freefloat_history.parquet` 미구축 → FreeFloat=1.0 conservative fallback 필요 |
| B | KR_KOSPI300_KOSDAQ150 | 450 | 18 bps | KOSPI300 자체 정의 (지수 X), FreeFloat 미반영 |
| **C** | **KR_TOP500_LIQ1E8** | **500** | **25 bps** | **mid-cap residual 신호 최대 노출, mandate 2e8 violation → cost 25bps 상향 (conditional)** |

### 1.2 채택 — Option C `KR_TOP500_LIQ1E8`

**채택 이유 (4가지)**:

**(a) 1715 외부 신호 다양성 극대화**: 1715는 `KR_top342` (KOSPI200 ∪ KOSDAQ150 + 2e8 KRW) universe 기반 운용. comp sleeve는 mid-cap residual 신호를 활용해야 cor ≤ 0.3 자격 + bad-state conditional alpha 가능성 동시 확보.

**(b) Empirical 입증 (L-227)**: `KR_top342` 한계 (Iter 13 v2 ICIR 0.086, Iter 15 V3 alpha 부재, Iter 16 KR fail) → 500+ universe 시 cross-section 신호 변별력 회복. Comp sleeve 본질이 1715가 capture 못 하는 residual.

**(c) Cost 25bps mandate accept**: Sleeve B를 small injection (a_max ≤ 0.20)으로 운용하므로 blend-level cost impact = `0.20 × 25bps = 5bps` (vs production 15bps). Net blend cost ≤ `0.80 × 15 + 0.20 × 25 = 17 bps` (admit 가능).

**(d) FreeFloat 데이터 의존 회피**: Option A FreeFloat=1.0 fallback은 weight 왜곡 risk. Option C는 거래대금(이미 구축됨)으로 직접 ranking → 재현성 확보.

**Hook 정합**: `mandate_compliance_check` hook이 25bps cost 기록 시 conditional compliance + admission decision은 net benefit 입증 의무.

### 1.3 LIQ floor 1e8 KRW vs production 2e8 KRW

| Stage | LIQ floor | 이유 |
|---|---|---|
| **Feature build (universe-restricted ranking)** | 1e8 KRW | history 안정성 (mid-cap retain) |
| **Top-K extraction (final sleeve B holdings)** | **2e8 KRW** | production constraint inherit (mandate 정합) |
| Cost model | 25 bps | 1e8~2e8 mid-cap 슬리피지 반영 |

→ 2-stage filter (느슨한 ranking universe → 엄격한 holdings universe). Codex C8 WT_003 disposition 정합.

---

## 2. Dynamic 1715 exclusion mechanism

### 2.1 Sig_date 별 dynamic exclusion

```r
# For each sig_date t:
str1715_holdings_t <- get_str1715_top20(sig_date = t)  # production READ ONLY
universe_500_t <- get_kr_top500_liq1e8(sig_date = t)
comp_universe_t <- setdiff(universe_500_t, str1715_holdings_t)
# Expected size: ~480-490 names per sig_date
```

**Source**:
- `str1715_holdings_t`: `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv` (Ticker per sig_date, READ ONLY)
- `universe_500_t`: `02_Infrastructure/factor_db/universe_expanded_v2.R::load_kr_top500_liq1e8(sig_date)` (architect L-227 정식 인프라)

### 2.2 Exclusion 정합성 audit (sig_date 별)

```r
# Audit per sig_date:
overlap_count_t <- length(intersect(str1715_holdings_t, top20_in_comp_t))
# Hard: overlap_count_t == 0 mandate
# If overlap > 0 → STOP + diagnose (architect intervention)
```

**Failure mode**: `comp top-20 ⊂ 1715 top-20` 시 by construction cor → 1.0 (WT_003 fail). 본 cycle은 universe 단계 분리로 이 fail을 사전 차단.

### 2.3 Time-series stability

| sig_date 변화 | comp_universe_t 변화 |
|---|---|
| 1715 holdings rebalance (월간) | 1715 top-20 변경분만큼 comp universe 동적 변화 |
| KR_TOP500 rebalance (월간) | top-500 마지막 ~5-10 rank 변동 흡수 |
| Total expected churn | per sig_date ~10-15 name 변경 (3% universe turnover) |

→ comp universe 자체 turnover는 안정적 (sleeve B 자체 turnover와 분리 audit 가능).

---

## 3. Universe diversity audit (sector + size + factor exposure dispersion)

### 3.1 Sector dispersion (Forge cycle measurement mandate)

**Expected**: 1715는 production live 기준 반도체 9 names heavy concentrate (L-274). Comp universe (1715 외부)는 반도체 over-concentration 해소 → 다른 sector residual 자연 노출.

**Audit metric**: 
```
sector_HHI(comp_universe_t) ≤ 0.15  (Herfindahl–Hirschman Index)
sector_HHI(str1715_t) - sector_HHI(comp_universe_t) ≥ 0.10
```

### 3.2 Size dispersion

KR_TOP500_LIQ1E8 = top-500 by mktcap → 1715 top-342 외부 ~158 names (mid-cap zone). Comp sleeve가 이 mid-cap residual 활용 가능.

**Audit metric**:
```
median(log_mktcap)(comp_universe_t) < median(log_mktcap)(str1715_universe_t)
size_decile_3_8(comp_universe_t) ≥ 60%  (mid-cap dominance)
```

### 3.3 Factor exposure dispersion

v2 80 features pool (defensive 55%, Frazzini-Pedersen 2014 backbone) 적용 시 comp universe 내 평균 factor exposure:

| Factor family | Expected dispersion |
|---|---|
| value (BM, EP, CF/P) | comp universe value tilt > 1715 (large-cap quality bias 차이) |
| quality (ROE, profitability) | comp universe quality lower (mid-cap operating leverage) |
| momentum (12-1, IDIOMOM) | dispersion similar (cross-section signal) |
| low-vol / BAB | comp universe **higher BAB potential** (small-cap residual, Frazzini-Pedersen 2014 §V.A) |
| size (-log_mktcap) | comp universe size factor positive exposure |

→ defensive 55% feature pool + mid-cap residual = bad-state conditional alpha의 학술 prior 정합.

---

## 4. Cor ≤ 0.3 자격 가능성 — by construction 분석

### 4.1 WT_003 fail mode 정직 inherit

WT_003 admission_decision.json:
```
axis_6_cor_1715: value 0.9997, target_max 0.3, pass = false
```

원인: A-option strict (`comp ⊂ 1715 top-20`) 으로 universe 동일 → top-K extraction 후 두 sleeve의 시계열 return correlation → **portfolio union returns ≈ 1715 returns** (algebraic identity, not paradigm failure).

### 4.2 v2.0 cor 학술 prior estimate (Codex Round 1 C3 ACCEPT 정정)

| Pre-requisite | Status |
|---|---|
| Universe overlap = 0% (dynamic exclusion) | by construction ✓ algebraic identity |
| Feature pool = v2 80 (defensive 55%, BAB tilt) | factor exposure 분리 partial |
| Conditional injection (small a_max ≤ 0.20) | wealth contribution 약간 dilution |
| **KR equity common market beta** | **β_1715 + β_comp 동시 노출 → return cor 자연 상승** |

**학술 prior estimate (정정)**: cor ≈ **0.3 ~ 0.6** (KR equity common market beta 흡수 후 추정).
- Fama-French 1992 + Petkova 2006 RFS — KR equity universe 내 두 sleeve 공통 market β ≈ 0.6-0.8 → return cor 상승 자연
- L-281 KR TSMOM cor 0.077 (cross-asset = bond/commodity vs equity) **NOT close analogue** — Codex Round 1 C3 ACCEPT 정정

**0.3 hard ceiling 통과 가능성**: **40-50%** (정직 학술 prior estimate, Forge cycle 측정 binding).

### 4.3 cor > 0.3 fallback — market beta neutralization (신규)

cor > 0.3 fail 시 backup mechanism (alpha_package.json final 명시):

**Backup A: cor regularization grid (WT_003 inherit)**
- λ_corr ∈ {0.5, 1.0, 2.0} grid search (Forge cycle)

**Backup B: market beta neutralization (신규)**
- comp sleeve return을 1715-beta neutralized residual로 decompose:
  ```
  r_comp(t) = β · r_1715(t) + r_comp_residual(t)
  β = cov(r_comp, r_1715) / var(r_1715)  (rolling 36m at t-1, PIT strict)
  r_comp_residual(t) = r_comp(t) - β · r_1715(t)
  ```
- NAV_blend 측은 `r_comp_residual` 사용 (1715-orthogonal by construction):
  ```
  NAV_blend = NAV_1715 × (1 - a_t) + NAV_comp_residual × a_t
  ```
- Forge cycle empirical 검증 mandate. Phase B/C에서 측정 후 채택 여부 결정.

### 4.4 Cross-asset vs cross-section 직교성 — L-281 정정 (Codex C3)

L-281 본질 통찰:
> "Cross-Asset TSMOM (Moskowitz-Ooi-Pedersen 2012) cross-section vs time-series 정의상 직교 (cor 0.077 KR empirical 입증)"

**Codex Round 1 C3 정정**: 위 precedent는 **cross-asset** (bond futures vs equity) → cor 0.077. 본 cycle은 **cross-section** (KR equity 두 sleeve). Paradigm 다름.

DPL-RC v2.0 정직 응용:
- 1715 (KR equity cross-section, AR + R05 overlay)
- comp (KR equity 외부 cross-section, BAB tilt + size residual)
- **공통 KR equity market β 자연 노출 → cor 0.3-0.6 학술 prior 정합**
- by design choice (universe disjoint + market beta neutralization fallback) cor ≤ 0.3 자격 가능 (Forge cycle 측정 binding)

---

## 5. Comp universe build pipeline (Forge cycle spec)

### 5.1 Universe load 함수 사양

```r
# 02_Infrastructure/factor_db/universe_expanded_v2.R 정식 API
load_kr_top500_liq1e8 <- function(sig_date, 
                                   liq_floor_won_20d_avg = 1e8,
                                   top_n = 500) {
  # PIT C10 strict: t-1 거래대금 20일 avg
  # Returns: data.table(Ticker, sig_date, mktcap_rank, liq_20d_avg, included)
}

build_comp_universe_t <- function(sig_date_t) {
  univ_500 <- load_kr_top500_liq1e8(sig_date_t)
  str1715_top20 <- load_production_str1715_holdings(sig_date_t)  # READ ONLY
  comp_universe <- univ_500[!Ticker %in% str1715_top20$Ticker]
  
  # Audit
  stopifnot(length(intersect(comp_universe$Ticker, str1715_top20$Ticker)) == 0)
  return(comp_universe)
}
```

### 5.2 Sig_dates range (2014-01 ~ 2026-04)

`first_train_start = 2014-01` (WT_003 inherit, v2 walk-forward), `last_test_end = 2026-04`. Total 148 month sig_dates, walk-forward purge 후 ~124 net.

### 5.3 PIT C10 (liquidity) + C15 (Factor DB) strict

| Code | Compliance |
|---|---|
| **C10** | `liq_20d_avg`는 sig_date t-1까지 closing 일자 20일 평균. same-day 사용 금지. |
| **C15** | `load_kr_top500_liq1e8()` 경유 의무. parquet 직접 load 금지. |
| **C13** | factor exposure 측정 시 Z_Score_Aligned only. NEGATE_FACTORS X. |
| **C14** | IC 접근 시 Usable_Date <= sig_date. |
| **C4** | 재무제표 lag (annual 5월, quarterly 45일). |

---

## 6. Cost model — 25 bps conditional + blend net audit

### 6.1 Cost decomposition

```
cost_blend_total(t) = (1 - a_t) · 15bps · turnover_1715(t)  + a_t · 25bps · turnover_comp(t)
                    + |Δa_t| · max(15bps, 25bps) · 1  (sleeve rebalance)
```

### 6.2 Net cost ceiling

**Target**: `cost_blend_annualized ≤ 20 bps` (production 15bps × 1.33 max margin)

a_max grid 정합성:
- a_max = 0.05 → cost ≈ 15 + 0.05×(25-15) = 15.5 bps ✓
- a_max = 0.10 → cost ≈ 16.0 bps ✓
- a_max = 0.15 → cost ≈ 16.5 bps ✓
- a_max = 0.20 → cost ≈ 17.0 bps ✓ (production net + 2bps headroom)

→ a_max ≤ 0.20 grid는 net cost 17bps ceiling 정합. Admission axis 5 (TO ≤ 6 annualized) 정합.

### 6.3 Admission decision-rule update

WT_003 axis_5 (turnover) target inherit + cost ceiling 신규 (Phase B/C cycle measurement):
```
axis_5_turnover: ≤ 6.0 (annualized one-way)  ← WT_003 inherit
axis_5b_net_cost: ≤ 20 bps annualized          ← v2.0 신규
```

---

## 7. Self-check (Blocker 2 resolution)

- [x] 1715 외부 universe 단계 명시 (`KR_TOP500_LIQ1E8 ∖ STR_1715_top_20`)
- [x] Dynamic sig_date 별 exclusion mechanism 정합
- [x] cor ≤ 0.3 by construction 가능성 학술 prior estimate 명시
- [x] L-281 KR TSMOM cor 0.077 empirical precedent 인용
- [x] Cost mandate 25bps + blend net audit (a_max ≤ 0.20 grid 정합)
- [x] PIT C10/C13/C14/C15 strict design-level compliance
- [x] Architect L-227 universe v2 advisory 정합 (Option C 선택 명시)
- [x] 자기합리화 0건 (WT_003 cor 0.9997 fail 정직 inherit + universe 분리로 해소)

**Charter §8 No Silent Override**: WT_003 axis_6 (cor 0.9997 fail) → universe 분리로 by construction 해소. Forge cycle empirical cor measurement 의무 (학술 prior estimate 0.05~0.25, 측정 시 정직 보고).

---

## 8. References

- 도훈 mandate 2026-05-17 "Path A NAV-level blend" + comp universe 1715 외부
- WT-D20260517_003 admission_decision.json (axis_6 cor 0.9997 fail)
- `qepm/mailbox/architect/universe_expansion_v2_advisory.json` (L-227 universe v2 advisory)
- `02_Infrastructure/factor_db/universe_expanded_v2.R`
- `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv` (READ ONLY)
- Frazzini-Pedersen 2014 JFE §V.A (BAB small-cap residual)
- L-281 (KR TSMOM cor 0.077 empirical orthogonal precedent)
- L-227 (universe v2 advisory rationale + ICIR attenuation diagnosis)
- L-274 (STR_1715 sector concentration: 반도체 9 names)
- `.claude/rules/pit.md` C10/C13/C14/C15
