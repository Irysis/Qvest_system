# WT-D20260508_011 후속 연구 활용 인사이트

**Status**: DISCOVERY_FAIL_REJECTED_AGENT_AGREES_CODEX
**Date**: 2026-05-08
**Inheritance target**: 옵션 파생 / cross-asset / 시장 변동성 cross-section 후속 WT

---

## 1. 핵심 보존 가치 (학술 contribution)

### 1-A. KRX 옵션 chain 16년 직접 cache ⭐⭐
- **4023 거래일 / 6,186,016 행 / 약 202MB** (2010-01-04 ~ 2026-05-07)
- 경로: `.cache/krx_options/<YYYYMMDD>.parquet`
- 4 상품 모두 retain: 코스피200 옵션 (정규) + 미니코스피200 옵션 + 위클리(목/월)
- 컬럼: ISU_CD / ISU_NM / RGHT_TP_NM (콜/풋) / TDD_CLSPRC / IMP_VOLT / ACC_TRDVOL / ACC_OPNINT_QTY
- → **한국 단일주 옵션 거래 미미** (개별주식 옵션 endpoint 없음). 활발한 주식파생 = KOSPI200 family.
- 후속 mandate: 본 cache 위에 옵션 파생 / VKOSPI surface / variance swap 직접 활용 후속 연구

### 1-B. VKOSPI 자체 재구축 ⭐
- CBOE 1993/2003 methodology 한국 정합 implementation
- 정합 검증 (KRX official):
  - 2020-03 (코로나) = **92** (예상 대 정합)
  - 2017 (저변동성) = **50** (예상 대 정합)
  - 2026-04 (현재) = **110** (위기 영역)
- 경로: `stage_artifacts/WT_D20260508_011/vkospi_reconstruction.parquet`
- → 일별 재구축 가능. KRX 공식 미공개 시점도 직접 산출
- 후속 mandate: VKOSPI surface 시계열로 시장 변동성 regime 직접 신호화 가능

### 1-C. 4 VRP variants production-ready
- **Bakshi 2003 model-free implied variance**: out-of-sample monthly stable
- **Carr-Wu 2009 synthetic variance swap**: 평균 0.87% 연환산 (S&P500 BTZ 2009 동급 정합)
- **Bollerslev-Tauchen-Zhou 2009 VRP factor**: 시장 risk premium 정상 추출
- **Britten-Jones-Neuberger 1998 model-free implied variance**: BKM 2003과 동치 검증
- 경로: `stage_artifacts/WT_D20260508_011/vrp_signals_monthly.parquet`
- 일별: `stage_artifacts/WT_D20260508_011/vrp_signals_daily.parquet`
- → 4 모형 implementation은 cross-asset / 옵션 파생 후속 연구에 직접 활용 가능

### 1-D. BKM skewness empirical (KOSPI200) ⭐
- bkm_skew 평균 -1.27 (음수, 좌편향) — KOSPI200 jumps to downside 정합
- → 한국 시장은 좌측 꼬리 위험이 우측 대비 큼 = put 보호 비용 reflect

---

## 2. 핵심 fail 패턴 (정직한 empirical)

### 2-A. v3 → v4 IC drop -86% ⭐ (가장 중요한 발견)
- v3 (relaxed PIT): rank_ic = **0.0255**
- v4 (PIT-strict t-1 lag): rank_ic = **0.0037** (-86% drop)
- → **VRP signal의 압도적 부분이 same-day aliasing이었음**
- → 학술적으로 시장 VRP는 mean-reverting하므로 t-1 lag 시 신호 즉시 소멸 정합
- 후속 mandate: **VRP는 t+1 prediction 자체보다 long-horizon (12M+) volatility forecast로 활용 가치 더 큼**

### 2-B. 2 cycles 누적 reproducible 실패
- **WT_001 (첫 시도)**: spurious cor 0.957 → 정정 -0.07
- **WT_011 (PIT-strict)**: rank_ic 0.0037 / ICIR 0.033 / t_NW 0.47
- → 2 cycles 누적 = **VRP cross-section signal 한국 top-universe alpha 부족 reproducible** (L-228 적립 mandate)
- AX-007 single_sleeve break 정합 (signal-portfolio translation 메커니즘 단절)

### 2-C. Graduation 5/9 strict gate 정직
- PASS 5: BTZ harvey-NW (시장 ETF spec) / sample size / DSR Bailey-LdP / 회전율 (548% < 600%) / 유동성 (2e8 strict)
- FAIL 4: rank_ic / ICIR / t_NW / LO Q5 t_NW
- → 신호 안정성 (DSR strict)은 양호하지만 **신호 절대치 (rank_ic absolute)가 cross-section graduation 미달**

---

## 3. 후속 연구 4 path 권고

### 3-A. Cross-asset commodity (도훈 직전 명시)
- Gold KR ETF / Copper KR ETF — Erb-Harvey 2006 / Bessembinder 1992
- KRX 옵션 chain (KOSPI200 변동성)과 직교 source 후보
- 4번째 직교 source mandate (현재 Hybrid 70/15/15 + ?)

### 3-B. VKOSPI surface time-series direct 신호
- 본 WT 재구축한 VKOSPI 일별 surface
- regime indicator로 직접 활용 (m4 strategy 확장)
- 거시 + 시장 변동성 + 거래대금 multi-axis crisis detector

### 3-C. Long-horizon (12M) variance forecast
- v3-v4 drop 통찰 → t+1 신호는 mean-revert
- 하지만 t+12M variance regime forecast는 economic significance
- Bollerslev-Tauchen-Zhou 2009 RFS "Expected Stock Returns and Variance Risk Premium" framework
- VRP가 직접 alpha source가 아니라 **regime conditioner**로 활용

### 3-D. 옵션 파생 (cross-asset spread)
- KRX 옵션 chain × KOSPI200 spot future basis
- Frazzini-Pedersen 2014 BAB style 옵션 leverage premium
- 본 16년 cache가 직접 활용 자산

---

## 4. 학술 출처 inheritance

본 WT 학술 baseline:
- **Bakshi-Kapadia-Madan 2003 RFS** "Stock Return Characteristics, Skew Laws, and the Differential Pricing of Individual Equity Options" — model-free implied variance foundational
- **Carr-Wu 2009 RFS** "Variance Risk Premiums" — synthetic variance swap
- **Bollerslev-Tauchen-Zhou 2009 RFS** "Expected Stock Returns and Variance Risk Premiums" — VRP factor
- **Britten-Jones-Neuberger 1998 JF** "Option Prices, Implied Price Processes, and Stochastic Volatility"
- **CBOE 1993/2003** VIX methodology (구버전 + Black-Scholes 자유 구버전)

후속 연구 보강:
- **Carr-Wu 2009 JFE** "A Simple Robust Link Between American Puts and Credit Insurance"
- **Frazzini-Pedersen 2014 JFE** "Betting Against Beta" — leverage constraint
- **Bessembinder-Lemmon 2002 JF** "Equilibrium Pricing and Optimal Hedging in Electricity Forward Markets"
- **Erb-Harvey 2006 FAJ** "The Strategic and Tactical Value of Commodity Futures"

---

## 5. L-code 신규 적립 (후속 세션)

**L-285 (예정)**: KR top-universe VRP cross-section alpha 2 cycles reproducible 실패 (WT_001 + WT_011). v3 → v4 IC drop -86% = same-day aliasing 입증. 학술 contribution 보존 (KRX 옵션 chain 16년 + VKOSPI 재구축 + 4 모형 production-ready). 후속 path = commodity / VKOSPI regime / long-horizon variance / 옵션 파생.

---

## 6. 산출물 inheritance (후속 WT 활용)

| 산출 | 경로 | 후속 활용 |
|---|---|---|
| KRX 옵션 chain 16년 | `.cache/krx_options/<YYYYMMDD>.parquet` (4023 files) | 옵션 파생 / VKOSPI surface / variance swap 직접 |
| VKOSPI 재구축 일별 | `stage_artifacts/WT_D20260508_011/vkospi_reconstruction.parquet` | regime indicator / m4 strategy 확장 |
| 4 VRP variants monthly | `stage_artifacts/WT_D20260508_011/vrp_signals_monthly.parquet` (197 months) | regime conditioner / forecast |
| 4 VRP variants daily | `stage_artifacts/WT_D20260508_011/vrp_signals_daily.parquet` (4023 days) | 일별 신호 분석 |
| alpha_scores full panel | `stage_artifacts/WT_D20260508_011/alpha_scores.parquet` (49,578 rows × 144 sig_dates × 718 tickers) | reproducibility audit |
| graduation strict v4 | `stage_artifacts/WT_D20260508_011/alpha_validation_v4.json` | 후속 PIT-strict baseline |
| 4 모형 R/Python implementation | `qepm/mailbox/worktask/WT-D20260508_011/build_vrp_signals.py` + `build_cross_section_signals.py` + `build_cs_v2.py` | direct reuse |

---

## 7. 핵심 1줄 요약

**"WT_011 = VRP cross-section 한국 alpha 부족 reproducible 입증 + 학술 contribution (KRX 옵션 chain 16년 cache + VKOSPI 재구축 + 4 모형 production-ready) 영구 retain. 후속 path = commodity / VKOSPI regime / long-horizon / 옵션 파생 모두 본 인프라 활용 가능."**

inheritance 의무: 후속 옵션 파생 / cross-asset / 시장 변동성 WT는 본 `insights_for_future_research.md` Read 후 path design.
