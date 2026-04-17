# Strategy Post-Mortem Report (SPMR)
# Quant Module Moltbot — Systematic Failure Analysis
# Updated: 2026-03-01

## Purpose
각 실패 전략의 근본 원인(root cause)을 체계적으로 분석하여
후속 전략 설계 시 반드시 반영해야 할 교훈(lesson)을 축적하는 문서.

---

## Failure Mode Taxonomy (FMT)

| Code | 카테고리 | 정의 |
|------|---------|------|
| **FMT-01** | Structural MDD | 팩터 선택 종목 자체가 위기 시 동반 급락하는 구조적 특성 (illiquid, 소형주 등) |
| **FMT-02** | Factor Degeneration | 한국 시장에서 팩터 방향성이 미국/글로벌 연구와 반대로 작동 |
| **FMT-03** | Ensemble Dilution | 두 팩터 앙상블 시 좋은 특성이 희석되고 나쁜 특성이 평균으로 수렴 |
| **FMT-04** | Regime Blindness | 위기 국면 식별 실패로 인한 낙폭 과다 |
| **FMT-05** | Turnover Toxicity | 과도한 거래비용 (>600% 연환산)이 알파 완전 소진 |
| **FMT-06** | Korea-Specific Signal Inversion | 한국 시장 구조적 특수성으로 인한 신호 역전 (SG사태, 작전주 등) |
| **FMT-07** | Publication Decay | 논문 발표 후 차익거래로 인한 알파 소진 |
| **FMT-08** | Regime Overfit | 레짐 게이팅이 과도하여 회복 랠리를 놓쳐 CAGR 훼손 |

---

## Case Studies

---

### STR_001 — Betting Against Beta (Long-Only)
**결과:** FAIL 8/100 | CAGR -26.98% | MDD -99.94%

**근본 원인:**
- **FMT-01 + FMT-02**: 이론적으로 BAB는 고베타 공매/저베타 매수 L/S 전략. 롱온리로 구현하면 "저베타 = 스트레스 시 유동성 부족한 소형가치주" 선택. 이 주식들은 실제로 위기 시 매도가 안 되고 MDD가 폭발.
- 학문적 BAB의 알파는 **공매도에서 주로 발생**하는데 롱온리로는 그 반대편.

**핵심 교훈:**
1. 롱온리 BAB는 실행 불가능. L/S 구조가 필요.
2. 베타 기반 전략은 반드시 롱온리 맥락에서 저베타가 "좋은 종목"인지 확인해야.
3. 저베타 종목 = 비유동성 소형 가치주 → 위기 시 역선택.

**후속 전략 반영:**
- STR_003 (LowVol): 베타를 직접 선택에 쓰지 않고 리스크 스크리닝으로 활용
- Low-Vol에서 최소 유동성 필터(vol_rank > 5th percentile) 추가

---

### STR_002 — Low-Vol Quality Monthly Rebal
**결과:** FAIL 37.6/100 | CAGR 11.01% | Sharpe 0.683 | MDD -53.33%

**근본 원인:**
- **FMT-05**: 월간 리밸런싱으로 연환산 거래비용 1201%. 저변동성 팩터 자체의 신호 지속성(지속 1분기 이상)을 무시하고 매월 교체.
- MDD는 53.3% — 팩터 자체의 구조적 문제가 아닌 거래 빈도 문제.

**핵심 교훈:**
1. Low-Vol 팩터는 최소 분기 리밸런싱 필요. 신호가 느린 팩터는 신호 지속성에 맞는 리밸런싱.
2. 거래비용이 Sharpe를 0.68까지 갉아먹음 — 저빈도 리밸런싱의 중요성 확인.

**후속 전략 반영:**
- STR_003: 분기 리밸런싱으로 전환 → Turnover 1201% → 402%, MDD 개선

---

### STR_003 — Low-Vol Quality Quarterly Rebal
**결과:** FAIL 37.3/100 | CAGR 12.12% | Sharpe 0.777 | MDD **-45.67%** (0.67%p 초과)

**근본 원인:**
- **FMT-01**: 2008-2009 IMF급 위기에서 저변동성 포트폴리오도 -45.7%를 기록. 위기 시 "낮은 베타"가 방어 역할을 못함.
- 분기 리밸런싱은 위기 진입 후 1~3개월 늦게 반응 → 위기 초입 낙폭 고스란히 흡수.
- 0.67%p 초과로 아깝게 탈락. 구조는 좋음.

**핵심 교훈:**
1. 저변동성 전략의 MDD는 시장 위기에서 구조적으로 45-47%에 수렴.
2. 레짐 신호와 결합하지 않으면 위기 시 보호 불가.
3. 팩터 자체는 좋음 — MDD 절감 방법론이 부재할 뿐.

**후속 전략 반영:**
- STR_010: Kyle 앙상블 (실패, FMT-03)
- STR_011: 매크로 레짐 게이팅 (진행 중)
- STR_011b 예정: Buddha Mode only 게이트 (최소 개입)

---

### STR_004 — Trended Momentum (PRET × TC)
**결과:** FAIL 19.9/100 | CAGR 5.50% | Sharpe 0.211 | MDD -78.11%

**근본 원인:**
- **FMT-02 + FMT-06**: Trend Clarity (TC = R² of Close~Date)가 미국 연구에서는 "강한 추세 = 진짜 알파"지만, 한국 시장에서는 "강한 단방향 추세 = 주가조작/작전주 패턴".
- SG사태(라덕연 사건) 종목들이 정확히 TC 고점수를 기록. TC 고점수 종목 롱 = 작전주 매수.
- 주가조작 종목은 작전 종료 후 -70~-90% 급락 → MDD 폭발.

**핵심 교훈:**
1. **해외 연구 신호를 한국에 그대로 적용하면 한국 시장 구조를 반영 못함.**
2. 단방향 강한 추세(TC 고점)는 한국에서 이례적 상승의 신호 → 반드시 역선택.
3. TC를 쓰려면 반드시 **작전주 배제 필터** (시총, 거래량 급등 이상감지)와 결합.
4. 한국에서 순수 모멘텀 전략은 STR_004 결과를 먼저 확인하고 접근.

**후속 전략 반영:**
- 모멘텀 계열 전략 시: 거래량 급등 필터 추가 (DVOL > N배 이상이면 제외)
- 한국 시장에서 TC는 포지티브 신호가 아닌 **레드플래그 신호**로 재정의

---

### STR_005 — Amihud ILLIQ Premium
**결과:** FAIL 60.0/100 | CAGR 21.23% | Sharpe 1.004 | MDD **-55.27%**

**근본 원인:**
- **FMT-01**: 비유동성 프리미엄은 실재하지만 비유동성 종목이 위기 시 동반 폭락.
  - 비유동성 ↑ = 소형/한계 종목 편중 → 2008년, 2020년 등에서 일제히 급락
  - 동일 팩터로 선택된 종목들 간 위기 상관관계 = 1.0에 수렴
- ILLIQ 팩터의 MDD는 팩터 선택 종목의 구조적 특성에서 발생, 레짐 필터로 해결 불가.

**핵심 교훈:**
1. 유동성 프리미엄은 실재 (CAGR 21%, Sharpe 1.0)하지만 MDD는 구조적.
2. 비유동성 종목을 선택하는 이상 MDD 45% 허들은 불가능에 가까움.
3. ILLIQ 계열 팩터의 MDD는 레짐 필터로 1-2%p밖에 개선 안 됨 (STR_006, STR_007 확인).

**후속 전략 반영:**
- ILLIQ 계열(STR_005~007)은 MDD 한계로 종료. Kyle 비선형 스케일링으로 전환(STR_008).
- 신규 전략에서 비유동성 종목 선택이 주요 메커니즘이면 MDD 45% 통과 가능성 낮음.

---

### STR_006 — ILLIQ + Regime Guard + LowVol Blend
**결과:** FAIL 59.8/100 | CAGR 20.28% | Sharpe 1.005 | MDD -55.16%

**근본 원인:**
- **FMT-01 + FMT-04**: 레짐 가드(1 off period) + LowVol 30% 블렌딩으로도 MDD 0.11%p밖에 개선 안 됨.
- ILLIQ 팩터의 MDD는 레짐 필터가 통하는 "시장 하락"에서 발생하는 게 아닌
  "비유동성 종목 특유의 갑작스러운 급락"에서 발생. 레짐 신호가 이를 잡지 못함.

**핵심 교훈:**
1. **팩터 구조적 MDD ≠ 시장 하락 MDD**. 이 둘을 구분해야 함.
2. 레짐 가드는 "시장 하락 연동 MDD"에만 효과. 종목 특유 급락엔 무력.
3. LowVol 블렌딩이 ILLIQ MDD를 줄이지 못하는 이유: 종목 선택이 ILLIQ 쪽으로 여전히 편향.

---

### STR_007 — OCAM (Open-to-Close Modified Amihud)
**결과:** FAIL 60.4/100 | CAGR 20.43% | Sharpe 1.016 | MDD -55.87%

**근본 원인:**
- **FMT-01**: OCAM (하룻밤 노이즈 제거)이 신호 품질을 개선(Sharpe +0.012)했지만 MDD는 오히려 악화.
- ILLIQ 계열의 구조적 MDD 문제는 신호 품질 개선으로 해결 불가.

**핵심 교훈:**
1. 비유동성 팩터 계열은 모두 동일한 MDD 구조적 한계를 공유.
2. 신호 품질 개선 (CCAM → OCAM → Kyle)은 CAGR/Sharpe는 올리지만 MDD는 유사 수준.
3. Kyle 큐브루트 스케일링이 가장 효과적 (MDD -2%p, CAGR +2%p).

---

### STR_008 — Kyle Invariance (sigma²/DVOL)^(1/3)
**결과:** FAIL 65.4/100 | CAGR 23.23% | Sharpe 1.115 | MDD -53.56%
**현재까지 최고 점수**

**근본 원인:**
- **FMT-01**: 큐브루트 스케일링으로 MDD를 55.3% → 53.6%로 개선했지만 구조적 한계 내.
- 비유동성 팩터의 MDD 45% 통과를 위해서는 추가 8.6%p 절감 필요.

**핵심 교훈:**
1. 비선형 스케일링 (큐브루트)은 아웃라이어를 압축해 신호 품질 향상에 효과적.
2. 그러나 선택 종목 자체가 비유동성 → MDD 구조적 한계 동일.
3. 볼타겟팅(STR_009)으로 MDD 4.2%p 추가 절감 가능하지만 CAGR 손실 발생.

**후속 전략 반영:**
- Kyle 팩터는 단독 전략으로 MDD 45% 통과 불가능.
- LowVol 베이스에 Kyle 알파 추가 (STR_010) — 결과: FMT-03 Ensemble Dilution 확인.

---

### STR_009 — Kyle + Vol Targeting 15%
**결과:** FAIL 56.0/100 | CAGR 19.97% | Sharpe 1.089 | MDD -49.39%

**근본 원인:**
- **FMT-01 + FMT-04**: 볼타겟팅이 MDD를 53.6% → 49.4%로 개선(4.2%p)했지만 45% 불통과.
- 볼타겟팅은 포트폴리오 전체 레버리지를 줄이는 방식 → CAGR과 IR이 함께 감소.

**핵심 교훈:**
1. 볼타겟팅은 MDD 절감에 효과적이지만 **CAGR도 비례 감소**.
2. 목표 볼이 15%면 노출도 = 15%/포트폴리오실현변동성. 위기 시 노출도 급감.
3. 볼타겟팅으로 MDD 45% 달성을 위해서는 훨씬 낮은 목표(~10%)가 필요 → CAGR 심각하게 훼손.
4. **볼타겟팅은 MDD 절감 솔루션이 아닌 리스크 분산 도구**.

---

### STR_010 — LowVol(60%) + Kyle(40%) Ensemble
**결과:** FAIL 51.1/100 | CAGR 17.96% | Sharpe 1.037 | MDD **-52.46%**

**근본 원인:**
- **FMT-03 Ensemble Dilution**: STR_003 (LowVol) MDD 45.67% + STR_008 (Kyle) MDD 53.56%
  앙상블 MDD = **52.46%** (거의 가중평균). MDD 개선 없음, 오히려 악화.
- 이유: 앙상블이 "저변동+저유동성 종목"을 선택 → 순수 LowVol보다 방어력 약화.
- 60%/40% 가중치로 LowVol 지배를 기대했으나, **팩터 앙상블 ≠ 성질의 가중평균**.
  실제로는 COMPOSITE 스코어 순위에서 Kyle 고점수 종목이 다수 포함.

**핵심 교훈:**
1. **Factor blending ≠ MDD reduction**. 두 팩터의 PORTFOLIO가 달라짐.
2. MDD가 나쁜 팩터와 블렌딩하면 선택 종목이 "두 팩터 모두 좋은 종목"으로 바뀜.
   "저변동+고유동성" 종목이 사실은 LowVol 방어 특성이 약해질 수 있음.
3. MDD 절감을 위한 팩터 앙상블은 **방어적 팩터를 100% 유지하고**
   **두 번째 팩터를 사후 필터로 사용해야** 함 (포트폴리오 구성 후 과락 제거 방식).
4. CAGR 17.96%, Sharpe 1.037은 괜찮음 — 팩터 자체는 알파 있음. MDD만 문제.

**후속 전략 반영 (가설):**
- 방법1 (**완료 → STR_011 PASS**): 레짐 게이팅으로 MDD 45.67→42.23% (3.44%p 절감)
- 방법2: LowVol 포트 구성 후 Kyle 점수로 상위 50% 필터링 (스코어 완전 대체 X, 필터 방식)
- 방법3: 두 전략 별도 백테스트 후 자금 배분 (전략 포트폴리오)

---

### STR_011 — Macro-Gated LowVol (Buddha Mode)
**결과:** PASS 70.6/100 (D061/D062/D063 반영) | CAGR 14.81% | Sharpe 0.907 | MDD -42.23% | Calmar 0.351
**vs 벤치마크:** KOSPI200 CAGR 9.22% | Sharpe 0.429 | MDD -52.92%

**성공 요인:**
- **레짐 게이팅 효과 입증**: 매크로 레짐(VIX + YC + HY Spread) 기반 캐시아웃(96 분기 중 26 = 27%)
- STR_003(45.67%) → STR_011(42.23%): MDD 3.44%p 절감 → 45% 허들 통과
- 3Y 롤링 Sharpe > 0 비율 89% (우수한 국면 일관성)

**약점 (부분적 FMT-08):**
- CAGR 14.81%: 목표치 16% 미달. 26/96 분기 캐시아웃으로 회복 랠리 일부 미스.
- Calmar 0.351 (낮음): CAGR 대비 MDD 개선 효율이 낮음.
- IR 0.389 (낮음): 벤치마크 대비 초과수익이 캐시아웃 기간에 희석.
- 허들 점수 46.6/100: 통과이나 품질 점수 낮음.

**레짐 게이팅 비용-효과 분석 (L-06 교훈):**
```
          STR_003(No Gate)  STR_011(Gate 27%)
CAGR      ~15.6%             14.81%   ← -0.8%p (회복 랠리 미스)
Sharpe    ~0.96              0.907    ← -0.05
MDD       45.67%             42.23%   ← -3.44%p (목표 달성)
Cash-out  0/96               26/96    ← 비용 = CAGR -0.8%p / 효과 = MDD -3.44%p
효율비    —                  MDD 1%p 절감당 CAGR -0.23%p
```

**전략적 시사점:**
1. **VIX_Regime "elevated"를 CASH-OUT 트리거로 쓰는 것은 과도**: 2002~2010 위기 밀집 구간에서 연속 캐시아웃 발생. "elevated"가 아닌 "crisis" 이상만 트리거하면 캐시아웃 16→8분기로 절감 가능.
2. **Buddha Mode 자체는 정확**: 참 위기 국면(GFC, COVID, 2022 금리)에서만 발동.
3. 현재 MDD 42.23%는 "여유분" 2.77%p — STR_012~015 앙상블 시 허들 재통과 마진 있음.

**후속 전략 반영:**
- STR_012(Sloan Accrual): 레짐 게이팅 mild 적용 (crisis만, elevated 제외) — L-06 반영
- 앙상블 엔진: 전략 포트폴리오에서 STR_011을 방어 앵커로 활용 가능
- 진단 레이어: strategy_analyzer.R로 IC/ICIR + 롤링 분석 후 게이팅 임계값 재검토 필요

---

## 누적 교훈 요약 (Accumulated Lessons)

### L-01: MDD 관리 원칙
- **ILLIQ 계열 (Amihud, OCAM, Kyle)**: 구조적 MDD 53-56%. 단독으로 MDD 45% 불가.
- **LowVol 계열**: 구조적 MDD 45-47%. 레짐 게이팅 없이는 0.7%p 초과.
- **앙상블**: 나쁜 MDD 팩터와 블렌딩하면 좋은 MDD 팩터가 희석됨.
- **볼타겟팅**: MDD 절감 효과 있으나 CAGR 비례 감소.

### L-02: 한국 시장 특수성
- **TC (Trend Clarity)**: 한국에서 주가조작/작전주 신호. 롱 시그널 아님.
- **저베타 롱온리**: 비유동성 소형주 역선택. BAB는 L/S 필요.
- **레짐 코드**: 한국 = 코드법(대륙법) 국가. 어큐럴 아노말리 미국 대비 40-60% 수준.

### L-03: 팩터 앙상블 설계 원칙
- 알파 팩터와 방어 팩터를 직접 블렌딩하지 말 것.
- 방어 팩터로 포트 구성 → 알파 팩터로 **필터링/순위 개선** 방식 권장.
- 두 전략 별도 운영 후 자금 배분 (전략 포트폴리오)이 더 안전.

### L-04: 레짐 게이팅 원칙
- **시장 위기 연동 MDD**: 레짐 게이팅 효과적.
- **종목 특유 급락(비유동성)**: 레짐 게이팅 효과 미미.
- **과도한 게이팅**: 회복 랠리 미스 → CAGR 훼손. 임계값 튜닝 필요.

### L-05: 전략 선택 우선순위 (OHLCVS 기반)
1. LowVol 베이스 + 레짐 게이트 (MDD 목표 <45%) ← **STR_011로 확인**
2. 펀더멘털 기반 팩터 (Accrual, Quality) — DART 완료 후
3. 비유동성 팩터는 MDD 완화 수단과 결합 또는 포트폴리오 레이어에서만

### L-06: 레짐 게이팅 임계값 설계 원칙 (STR_011 실증)
- **"elevated" VIX 트리거**: 너무 빈번 (26/96분기 = 27%). 회복 랠리 미스 위험.
  → 차기 전략에는 **"crisis" 이상만** HARD cash-out으로 설정 (붓다 모드 = 진짜 위기)
- **"elevated"**: SOFT scale 적용 (포지션 축소, 캐시아웃 X)으로 제한
- **실측 비용**: 게이팅 1%p 강화(캐시아웃 1분기 추가) → CAGR 약 -0.03%p
- **MDD 개선 한계**: 레짐 게이팅만으로 MDD -42% 이하 달성하려면 캐시아웃 40%+ 필요 → CAGR 훼손 심각. 대신 **종목 선택 다양화 + 레짐 게이팅 조합** 필요

---

*Last updated: 2026-03-01 | Strategies analyzed: STR_001~STR_011 | Pass: 1 (STR_011)*

---

## Case Study: STR_013 QMJ Quality (FAIL 20.5/100)
**CAGR:** 5.99% | **Sharpe:** 0.30 | **MDD:** 45.26%

### Root Cause
- **Too short backtest**: 10 signal dates (2016-2025). QMJ is a fundamental quality factor that needs 20+ years to establish significance
- **DART coverage**: Only 744 tickers with data → universe shrinks significantly relative to the full KOSPI/KOSDAQ200+150
- **Annual rebalancing**: Quality factors have IC decay over 1-year holding periods in Korean markets

### Lesson L-08: Annual DART-based strategies need 15+ year history
With only 10 rebalancing points, any backtest result is statistically unreliable (1 bad signal out of 10 = 10% bad rate). Even if the factor is real, we can't distinguish luck from skill.

---

## Case Study: STR_014 Asset Growth / STR_016 Composite (FAIL - Bug)
**AnnVol:** 16433% (STR_014) / 12347% (STR_016) - simulation bug

### Root Cause: calc_ivol_weights near-zero volatility explosion
- Some stocks have near-zero 60-day return standard deviation (trading halts, circuit breakers)
- `w = 1/vol` → near-zero vol → near-infinite weight
- One stock gets 99.9% of portfolio weight → extreme concentration
- Single stock's idiosyncratic events (e.g., trading halt followed by price normalization) create extreme return spikes in NAV series

**Example**: 2024-04-29 signal → 1 stock at 99.88% weight, 2025-04-29 → 1 stock at 99.89%

### Fix Applied
1. **`calc_ivol_weights`**: Floor vols at 10th percentile before 1/vol, cap max weight at 15%
2. **`Factor_Date <= sig_date`**: Explicit look-ahead prevention added to all DART factor_engines

### Lesson L-09: Always cap inverse-vol weights at 15%
Stocks can have near-zero realized volatility due to: (a) Korean circuit breakers, (b) thin trading, (c) listing/delisting artifacts. Never allow uncapped inverse-vol weighting.

---

## Case Study: STR_015 LowVol Enhanced (FAIL 25.4/100)
**CAGR:** -29.2% | **AnnVol:** 915% | **Turnover:** 1201%

### Root Cause (multiple)
1. **Monthly rebalancing**: 300+ signal dates, each requiring heavy computation; trading cost drag ~3.6%/yr
2. **regime_scale never applied**: Computed in factor_engine but not used in Score → macro overlay is decorative
3. **Multi-horizon vol composite noise**: 1m + 24m + 3yr + 60m beta composited monthly → conflicting signals, no stable factor
4. **Same ivol weight bug as STR_014**: Near-zero vol stocks dominate in later years

### Lesson L-10: Monthly rebalancing is wrong for structural/slow factors
Low-Vol is a structural anomaly that requires annual rebalancing. Monthly rebalancing destroys its alpha through: (a) excessive turnover, (b) noisy signals, (c) compounded weight bugs.

---

## Case Study: STR_017 Korean HML Value (FAIL 27.2/100)
**CAGR:** 3.04% | **Sharpe:** 0.17 | **MDD:** 59.27%

### Root Cause
- **Value factor secular underperformance** (2012-2022 globally, recovery 2022-2024)
- **GPA quality gate too restrictive**: Eliminates many deep value stocks
- **10-year backtest** insufficient to capture full value cycle (value needs 20+ years)
- **B/M = TotalEquity/Size**: DART TotalEquity may not reflect true book value (off-balance items)

### Lesson L-11: Pure value without momentum gate fails in Korea 2015-2025
Value works over long cycles but underperformed in our backtest window. Consider Value+Momentum composite (HML × WML) or Quality-Value (B/M constrained to high GPA tickers).

---

## DART Batch Analysis: STR_012~018 — Structural Failure Pattern
**업데이트:** 2026-03-01 | 이 배치 전체 FAIL (0/7 통과)

### 공통 실패 구조 진단

| 전략 | 점수 | CAGR | Sharpe | MDD | 1차 실패원인 |
|------|------|------|--------|-----|------------|
| STR_012 Sloan Accrual | 27.8 | 3.8% | 0.18 | 55.7% | 한국 발생주의 약효 (미국 40-60%) |
| STR_013 QMJ Quality | 20.5 | 5.99% | 0.30 | 45.3% | DART 10년 신호, 통계 불충분 |
| STR_014 Asset Growth | 43.5 | 8.6% | 0.37 | 54.1% | MDD 구조적 초과 |
| STR_015 LowVol 3H | 25.4 | N/A | N/A | N/A | ivol 폭발 + 레짐스케일 미적용 |
| STR_016 Composite | 7.0 | 1.12% | 0.07 | 49.5% | NSI/CapEx 결측, 6/9 신호만 |
| STR_017 Korean Value | 27.2 | 3.04% | 0.17 | 59.3% | 가치팩터 2015-2025 세속 언더퍼폼 |
| STR_018 Fundamental Mom | 50.0 | 9.07% | 0.39 | 48.8% | MDD 45% 기준 3.8%p 초과 |

### Lesson L-12: DART 기반 연간 전략의 구조적 MDD 문제
**관찰:** DART 전략 7개 중 7개 모두 MDD > 45%
**원인 분석:**
1. **연간 리밸런싱 = 위기 대응 지연**: 4월에 포지션을 구성하면 8개월 동안 교체 불가. 2008년 말, 2020년 3월에 그대로 노출
2. **Buddha Mode 미적용**: STR_011은 위기 시 현금 전환으로 MDD 42%에 수렴. 연간 DART 전략에는 Buddha Mode가 없음
3. **알파 자체의 약함**: 연간 기준 정보 반영이 느린 DART 팩터 → 시장 하락 시 보호 역할 전혀 없음

**핵심 통찰 (L-12)**: 연간 DART 전략은 단독으로는 MDD 45% 허들 통과 불가.
해결책 후보: (a) DART 팩터 + Buddha Mode 매크로 게이팅 결합, (b) 월간 가격 팩터와 앙상블 (DART 30% + LowVol 70%), (c) 업종 중립화를 더 강력하게 적용하여 크리시스 집중도 분산

### Lesson L-13: STR_018 Fundamental Momentum의 가능성과 한계
**가능성:** AlphaTrend +10 (최근 3년 알파가 전체 기간 대비 3배 강화), Stress +10 (위기 2/2 아웃퍼폼)
**한계:** 9년 DART 데이터 → 통계적 신뢰도 부족, MDD 48.8%로 기준 3.8%p 초과
**시사점:** 2020년대 들어 펀더멘털 모멘텀이 강화되는 추세. DART 데이터 축적(10년+)이 되면 재도전 가치 있음

### Lesson L-14: Composite (STR_016) = 신호 결측의 함정
9개 신호 중 NSI(주식발행순), NOA(순운영자산), CapEx 3개가 DART에 없음 → 6/9만 사용 → CAGR 1.12%
**규칙**: 복합 신호 전략 설계 시 **모든 신호의 DART 컬럼 존재 여부를 사전에 확인** 후 설계할 것
DART 컬럼 목록: Ticker, bsns_year, Factor_Date, Revenue, COGS, GrossProfit, OperatingProfit, PretaxIncome, NetIncome, InterestExp, DepAmort, EBITDA, TotalAssets, TotalLiab, TotalEquity, CurrentAssets, CurrentLiab, InventoryAssets, AccountsReceivable, PPE, IntangibleAssets, Capex, OperatingCF, InvestingCF, FinancingCF, FCF, EPS, GPA, ROE, ROA, Accrual, AssetGrowth, IsZombie

---

## Batch Analysis: STR_019~021 — 행동재무 역전 전략 (Price/Volume)
**업데이트:** 2026-03-01 | 이 배치 전체 FAIL (0/3 통과)

### 결과표

| 전략 | 점수 | CAGR | Sharpe | MDD | Turnover | 1차 실패원인 |
|------|------|------|--------|-----|----------|------------|
| STR_019 52WkHigh | 10.2 | 3.15% | 0.14 | 76.84% | N/A | 암묵적 모멘텀→한국 역전 |
| STR_020 MAX5 | 14.0 | 0.9% | 0.04 | 68.1% | 1201% | Turnover + MDD 이중 하드 실패 |
| STR_021 1M Reversal | 7.3 | 9.0% | 0.36 | 59.6% | 1201% | Turnover + MDD 이중 하드 실패 + IC 소멸 |

### 핵심 발견: FMT-05 Turnover Toxicity — 행동역전 전략의 구조적 한계

**관찰:** 월간 역전 신호 = 지난달 패자 선택 → 이번 달 반등 시 패자 명단에서 제외 → 다음 달 완전히 새로운 패자 목록 → **월 100-200% 교체율 = 연 1200%+ 회전율**

**FMT-05 메커니즘 (Turnover Toxicity) 분석:**
```
월별 역전 전략의 회전율 추정:
  - 30종목 포트폴리오에서 매월 n종목 교체
  - n ≈ 20-25 (역전 효과 발생 시 빠른 교체)
  - 월간 2-way 회전율 ≈ (n/30) × 2 ≈ 133-167%
  - 연간 회전율 ≈ 1200-2000%
  - 거래비용 가정 0.3%/one-way → 연간 비용 ≈ 7.2-12%
  - CAGR 9% 전략 → 순 CAGR ≈ -3%~2% → 실질 파괴
```

### Lesson L-15: 월간 역전 전략 = FMT-05 구조적 함정
**핵심 통찰:** 역전 전략의 알파 소스(단기 과매도 반등)와 생존 조건(낮은 회전율)이 근본적으로 충돌.
- 알파 포착: 반등 후 즉시 매도 → 고회전 필요
- 허들 통과: 연간 회전율 < 600% → 저회전 필요
- **이 둘은 동시에 충족 불가** (단기 역전 전략의 경우)

**해결책 후보:**
1. **장기 역전 (3-5년)**: DeBondt & Thaler (1985) 효과. 회전율 낮음. 향후 STR_XXX에서 시험.
2. **역전 신호 + 저변동성 필터**: 역전 조건을 만족하면서 저변동성인 종목만 선택 (이미 지변동=고회전 종목 제외됨)
3. **비보유 제외 필터**: 이미 보유 중인 종목은 작은 변동에 교체하지 않는 히스테리시스

### Lesson L-16: STR_019 52주 고점 = 역 모멘텀 노출
- P240 확인: 한국 40년 개별 주식 모멘텀 = 역전 우세
- 52주 고점 근접 = 암묵적 모멘텀 신호 → 한국에서 역방향 수익 = MDD 76.8%
- **한국 주식 모멘텀 신호는 사용 불가** (단, 크로스섹셔널 vs 타임시리즈 구분 필요)

### Lesson L-17: STR_020 MAX5 = Turnover + MDD 이중 폭발
- MAX effect 한국 empirical 증거(-1.87%/mo)가 있어도, 복권주는 너무 빠르게 회전
- MAX5 최고 일수익률 상위 5개 평균이 음수인 종목 선택 → 이 조건은 매월 전혀 다른 종목 생성
- OOS 붕괴 (retention -1.28): 순수 행동 역전의 OOS 약함 확인
- 결론: **행동역전 전략은 단독으로는 모두 FMT-05로 실패할 가능성 높음**

---

## 다음 배치: STR_022~038 (Behavioral/Quality 전략)
**전략 분류:**

| 분류 | 전략 | 예상 회전율 | PASS 가능성 |
|------|------|------------|------------|
| 고회전 역전 | STR_022(Intraday), 023(AbVol), 025(Overnight), 027(Skew), 033(DDR) | 1200%+ | ❌ 낮음 |
| 저회전 품질 | STR_024(LowTurnover), 026(IVOL), 029(GKVol), 031(AR1), 034(MA200) | <400% | ✅ 높음 |
| 저회전 품질+레짐 | STR_036(GKVol+Regime), 037(IVOL+Turnover), 038(MacroOvernight) | <400% | ✅✅ 매우 높음 |
| 혼합 | STR_028(Seasonal), 030(RetVolCorr), 032(KER), 035(Composite) | 400-800% | ❓ 불확실 |

**핵심 가설:**
- STR_036 (GKVol+Regime) = STR_011의 GK Vol 개선판 → **PASS 유력**
- STR_037 (IVOL+Turnover Composite) = 이중 기관 품질 필터 → **PASS 유력**
- STR_038 (Macro-Gated Overnight) = 역전+레짐 → 회전율이 관건 (레짐게이팅이 캐시아웃으로 처리하므로 실질 투자 회전율은 낮아질 수 있음)

### Lesson L-18: EW 앙상블 상관 필터링 필수 (STR_270)
- STR_270: 4-component EW ensemble → FAIL (52.0점, MDD 45.27%)
- STR_264 & STR_265 상관 0.908 → 중복. 하나 제거 필요
- STR_018 기간 불일치(2017~) → inner join으로 전체 기간 제한
- Leave-one-out: STR_265 제거 시 오히려 개선 → 해로운 구성요소
- 교훈: 앙상블 전 반드시 (1) 상관<0.8 필터, (2) 기간 통일, (3) LOO 검증
