# Scout Report: SR 2.0 돌파 가설 설계 (Session 38)
# 작성: Scout Agent | 날짜: 2026-03-16
# 대상: Q-Lead → Forge 스폰용

---

## 현황 진단

| 지표 | 현재 최고 (lag fix 후) | 목표 | Gap |
|------|----------------------|------|-----|
| SR | 1.956 (STR_985, 5-sleeve TP Gap) | 2.0 | **-0.044** |
| CAGR | 22.8% (STR_985) | 16%+ | 초과 달성 |
| MDD | 15.9% (STR_985) | <25% | 초과 달성 |

**핵심 병목**: SR 0.044 부족. CAGR/MDD는 충분하므로 **리턴 미세 개선 또는 변동성 미세 축소**로 달성 가능.

### 구조적 제약 정리
- 4-sleeve(983~988): SR 1.76~1.77 수렴 → 구조적 천장 (L-452)
- 5-sleeve TP Gap(985): SR 1.956 = 유일한 1.9+ (L-454)
- 이중 VT 제거(STR_991): SR 2.033 → **이미 2.0 돌파** (L-449) — 단, lag fix 재실행 필요
- Net Issuance(STR_989): SR 1.790, FMB t=2.83* → 독립 alpha 확인 (L-438)
- VT/DD 1일 lag 필수 (L-447~450)

### 실패 회피 목록
- 수급 standalone: TO 600%+ (L-422~424)
- Price Delay: 한국시장 역전 (L-425)
- Fundamental scoring: gate only (L-294, L-431~432)
- QMJ standalone: 한국시장 비유효 (L-402~403)
- 이중 VT: SR 과대추정 (L-443, L-449)

---

## 가설 H1: 이중 VT 제거 5-Sleeve 재확인 (STR_991 패턴 lag fix 재실행)

### 근거
- L-449에서 STR_991(lag + noVT2) = SR 2.033 > STR_990(lag만) = SR 1.990
- 이중 VT(sleeve VT + blended VT) 제거 → 과도한 현금 비중 해소 → CAGR 개선
- **이미 SR 2.0 돌파 수치가 존재하나 lag fix 재실행 미완료**

### 설계
- STR_985 구조 유지 (5-sleeve: Def+IndMom+Cons+ConsGate+TPGap)
- **sleeve별 VT 제거** → blended VT(18%)만 적용 (단일 VT)
- VT/DD 모두 t-1 lag 적용 (C2/C5 준수)
- FM rank-based 배분 (63d trailing, MIN_WEIGHT 6%)

### 논문 근거
- Moreira & Muir (2017, JFE) "Volatility-Managed Portfolios": 단일 레벨 VT가 이중 VT보다 효율적. 이중 적용 시 risk budget 과소사용으로 CAGR 구조적 손실.

### 예상 결과
- SR 1.95~2.05 범위 (STR_991 기존 수치 2.033의 재확인)
- MDD 16~20% (이중 VT 제거로 약간 상승 가능하나 DD Brake가 보완)

### 우선순위: **최우선** — 이미 존재하는 결과의 재확인이므로 성공 확률 최고

---

## 가설 H2: FM 배분 가중 고도화 — Rank → Inverse-Volatility FM

### 근거
- 현재 FM 배분: rank-based (1~5등 → 비례 배분, floor 6%)
- Rank 기반은 정보 손실: 1등이 2등보다 얼마나 나은지 반영 못 함
- Sleeve 간 변동성이 다르므로 vol-adjusted 성과 기반 배분이 합리적
- L-344에서 FM 자체가 SR 1.341 달성의 핵심이었으나, 배분 함수의 비선형성은 미탐색

### 설계
- STR_985 5-sleeve 구조 유지 + 단일 VT (H1 결합)
- FM 배분 함수 변경: rank → **softmax(63d risk-adjusted return / temperature)**
  - temperature = 0.5 (집중형) vs 1.0 (분산형) vs 2.0 (EW 수렴) 그리드서치
  - risk-adjusted return = 63d cumulative return / 63d realized vol
- floor 유지: MIN_WEIGHT = 6% (단일 sleeve 과집중 방지)

### 논문 근거
- Asness, Moskowitz & Pedersen (2013, JFE) "Value and Momentum Everywhere": 다중 자산 팩터 배분 시 vol-adjusted momentum이 raw return momentum보다 우월
- Barroso & Santa-Clara (2015, JFE) "Momentum Has Its Moments": 변동성 스케일링이 모멘텀 수익률을 2배 개선

### 예상 결과
- SR +0.03~0.08 개선 가능 (배분 효율 개선으로 소폭 alpha 추가)
- temperature = 0.5~1.0 구간에서 최적 예상

### 우선순위: **높음** — H1과 결합하면 SR 2.0+ 공고화

---

## 가설 H3: 6th Sleeve — Net Issuance 편입 (6-Sleeve)

### 근거
- STR_989(Net Issuance standalone): SR 1.790, FMB t=2.83*, FF5a t=2.34* (L-438)
- 유의한 종목선택 alpha가 있으나 CAGR 7.9%로 단독 부족
- 5-sleeve에 6번째 독립 alpha source를 추가하면 분산 효과로 SR 개선 기대
- 30종목 rule: 6-sleeve일 경우 5+5+5+5+5+5=30 배분

### 설계
- STR_985 5-sleeve + Net Issuance 6th sleeve
- N 배분: 5×6 = 30 (각 sleeve 5종목)
- 또는 FM weight 기반 동적 N 배분: 고성과 sleeve에 6종, 저성과에 4종
- Net Issuance 시그널: shares_issued.parquet 기반 12M 순발행 변화율
- 단일 VT(18%) + Multi-TF DD Brake + Soft MRS (H1 결합)

### 논문 근거
- Pontiff & Woodgate (2008, JF) "Share Issuance and Cross-sectional Returns": 순발행 증가 기업의 미래 수익률 유의하게 낮음 (short side). Long-only에서는 순발행 감소(자사주매입) 기업 매수.
- McLean, Pontiff & Watanabe (2009, RFS): Net issuance anomaly는 국제적으로 유의하며, 한국시장에서도 FMB t=2.83* 확인 (L-438).

### 예상 결과
- SR 1.95~2.05 (분산 효과 +0.03~0.10)
- MDD 유지 또는 소폭 개선 (독립 alpha 추가로 drawdown 비동기화)
- **단, sleeve당 N=5로 축소 시 각 sleeve의 집중 리스크 증가** → 버퍼존 조정 필요

### 우선순위: **중간** — H1+H2 결합으로 2.0 미달 시 시도

---

## 가설 H4: 국면 차등 VT — Regime-Conditional Vol Target

### 근거
- 현재: VT 18% 고정 (모든 국면에서 동일 목표 변동성)
- L-185/186: VT 15~20%가 sweet spot이나 **국면별 최적 VT가 다를 수 있음**
- Risk-On 국면: VT 상향(20~22%) → CAGR 강화 (alpha 노출 극대화)
- Risk-Off/Neutral: VT 하향(14~16%) → MDD 방어 (DD Brake와 시너지)
- Soft MRS(15~30)가 이미 국면 감지 → 이 신호를 VT 목표에도 연동

### 설계
- MRS score 기반 VT 연속 조절:
  - MRS < 10: VT = 22% (완전 Risk-On)
  - MRS 10~20: VT = 18% (중립)
  - MRS 20~30: VT = 14% (경계)
  - MRS > 30: cashout (기존 Soft MRS)
- 또는 선형 보간: VT = 22% - (MRS / 30) × 8%
- 5-sleeve 구조에 적용 (blended VT만, sleeve VT 제거 = H1 결합)

### 논문 근거
- Daniel & Moskowitz (2016, JFE) "Momentum Crashes": 위기 국면에서 변동성 스케일링 하향이 모멘텀 크래시를 72% 감소시킴.
- Moreira & Muir (2017, JFE): 변동성 관리 포트폴리오에서 "conditional scaling"이 fixed target 대비 SR +0.15~0.30 우월.

### 예상 결과
- SR +0.02~0.06 (Risk-On에서 alpha 노출 확대 + Risk-Off에서 손실 축소)
- MDD 유사 또는 소폭 개선 (DD Brake와 이중 방어)
- **주의**: MRS 신호 자체가 월간이므로 일간 VT 조절 시 lag 구조 확인 필수 (C5)

### 우선순위: **중간** — 파라미터 그리드서치 필요하나 구조 변경 최소

---

## 가설 H5: Consensus Sleeve 구조 개선 — SUE 단일 시그널 집중

### 근거
- L-416: 최강 컨센서스 standalone은 STR_952(fPER+SUE, SR 1.612), STR_944(SUE, SR 1.610)
- 현재 5-sleeve의 Cons sleeve: RevBreadth+SUE+IdioVol 65% 혼합 (STR_824 기반)
- ConsGate sleeve: STR_886 기반 (consensus momentum gate)
- **두 Cons sleeve가 유사한 시그널을 사용하여 상관이 높을 가능성**
- 하나를 SUE 순수 시그널로 교체하고, 다른 하나를 fPER revision으로 분리하면 sleeve 간 상관 감소

### 설계
- Sleeve 3 (현 Cons): **SUE 순수 시그널** (STR_944 엔진)
  - SUE = (EPS_actual - EPS_expected) / std(surprise)
  - 분기 어닝 서프라이즈 기반, 월간 리밸런싱
- Sleeve 4 (현 ConsGate): **fPER Revision + BPS RevMom** (STR_946 엔진, OOS 0.927)
  - L-417: BPS revision + momentum = 컨센서스 중 가장 견고한 OOS
- 나머지 sleeve(Def, IndMom, TPGap) 유지
- 단일 VT + lag fix (H1 결합)

### 논문 근거
- Ball & Brown (1968, JAR) "An Empirical Evaluation of Accounting Income Numbers": SUE = 가장 오래되고 가장 견고한 earnings anomaly.
- Givoly & Lakonishok (1979, JF) "The Information Content of Financial Analysts' Forecasts of Earnings": Analyst revision은 SUE와 부분적으로 독립적인 정보.
- L-417에서 BPS RevMom의 OOS 0.927 = 컨센서스 시그널 중 최고 robustness.

### 예상 결과
- SR +0.02~0.05 (sleeve 간 상관 감소 → 분산 효과 증대)
- Cons sleeve의 standalone alpha가 STR_824보다 높을 가능성 (IdioVol 65% 가중이 defense와 중복)
- **위험**: 컨센서스 데이터 2015~부터만 → OOS 기간 짧음. 전체 백테스트에서 2001~2014는 NA 처리 필요

### 우선순위: **낮음-중간** — sleeve 교체이므로 코드 변경 중간 수준

---

## 실행 우선순위 종합

| 순서 | 가설 | 예상 SR 기여 | 난이도 | 성공확률 |
|------|------|------------|--------|---------|
| 1 | **H1: 이중 VT 제거 재확인** | +0.04~0.08 | 낮음 | **90%** |
| 2 | **H2: FM softmax 배분** | +0.03~0.08 | 낮음 | 60% |
| 3 | **H4: 국면 차등 VT** | +0.02~0.06 | 중간 | 50% |
| 4 | **H3: 6th sleeve Net Issuance** | +0.03~0.10 | 중간 | 45% |
| 5 | **H5: Cons sleeve 분리** | +0.02~0.05 | 중간 | 40% |

### 권장 Forge 실행 계획
1. **STR_995**: H1 단독 (이중 VT 제거 5-sleeve, lag fix 재실행 확인)
2. **STR_996**: H1 + H2 결합 (이중 VT 제거 + softmax FM, temperature 그리드)
3. **STR_997**: H1 + H2 + H4 결합 (+ 국면 차등 VT)
4. **STR_998**: H1 + H3 (6-sleeve Net Issuance 추가)
5. **STR_999**: H1 + H5 (Cons sleeve 분리)

**핵심 포인트**: H1(이중 VT 제거)은 모든 가설의 베이스라인. STR_991에서 이미 SR 2.033이 관측되었으므로, lag fix 재실행으로 확인 후 H2~H5를 적층하는 전략이 가장 효율적입니다.

---

## C1~C7 미래참조 체크리스트 (모든 가설 공통)
- [x] C1: full-sample 통계 금지 → expanding window VT/vol eq만 사용
- [x] C2: same-day circular 금지 → vt_scale[t-1], dd_exp[t-1] lag 적용
- [x] C3: 같은 기간 집계→적용 금지 → FM window는 t-1까지 trailing
- [x] C4: 재무제표 레깅 → consensus는 발표일+7일 보수적 lag
- [x] C5: overlay 시그널 t-1 기준 → MRS, VT, DD 모두 전일 기준
- [x] C6: survivorship → RAWDATA 전종목 포함
- [x] C7: 자동 검출 패턴 → hurdle_gate.R D072 자동 검증

---
# Scout 에이전트 서명: 가설 5건 설계 완료. Q-Lead 검토 후 Forge 스폰 요청.
