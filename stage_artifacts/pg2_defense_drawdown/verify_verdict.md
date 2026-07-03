# 낙폭 에피소드 방어력 측정 A/B 대조·적대검증 verdict

**작성**: 2026-07-03 (독립 re-measurement 기반). 실측-only, PIT 준수. 진단적 특성화(AX-001 v2 conditional crisis-alpha) — 에피소드 라벨은 ex-post market NAV로 선별하나 팩터 시그널은 PIT(t-1). "알려진 낙폭 구간에 무엇이 버텼나"이지 "무엇이 낙폭을 예측하나" 아님.

---

## 1. 수렴 (A vs B)

**완전 수렴 — 두 CSV는 값이 15자리까지 byte-identical.** 차이는 표현뿐:
- B는 선두에 `rank_median` 컬럼 추가, 일부 name 표기 변경(예 "VaR 5%"→"Value at Risk 5pct"), M08의 defclass를 `book3_momentum`→`BENCHMARK_book3`로 라벨링.
- 수치(mean/median/hit/worst/epact 11개 국면별)는 전 팩터·전 국면 동일. 예: Q01_GPA median 0.122350649346247 (A/B 동일), D48 epact_Euro_2011 0.166399588301248 (A/B 동일).

→ A와 B는 **동일 계산 파이프라인**. 독립 재구현이 아니라 같은 코드 산출물 2벌. 따라서 "둘 중 어느 쪽이 버그"라는 판정은 무의미 — 대신 **공통 파이프라인이 옳은가**를 독립 R 재측정으로 검증했다 (아래 §2).

---

## 2. 적대검증 (독립 R 재측정 `verify_remeasure.R` / `verify_diag.R` / `verify_cash.R`)

### (a) 단일 에피소드 아티팩트인가? → 아니오, robust
- 상위 팩터 hit_rate = 11국면 중 9~11 승 (D48/D45/D57 hit 0.909, RE07/D20 hit 1.0). worst_episode도 −0.02~−0.05 수준(단 1국면만 소폭 하회).
- 국면별 epact 분포: D48은 11국면 중 10국면 양수, 유일 음수는 COVID_2020(−0.0499). 단일국면 몰빵 아님.
- deep(≥20%) 6국면 한정 재측정: D48 median_deep +0.027 hit 6/6, RE07 +0.027 hit 6/6, D45 +0.021 hit 6/6. **깊은 낙폭일수록 방어 우위 유지**(약화 아님).

### (b) 에피소드 임계 민감도 → robust
- 전체 11국면(≥10%) median vs deep 6국면(≥20%) median: 상위 클러스터 순위·부호 불변. D48·RE07·Q08·Q01은 두 임계 모두 top.

### (c) top-quintile vs top-25 → robust
- top10 팩터를 top-quintile(유니버스 1/5)로 바꿔도 median_active 0.015~0.031로 유지, hit 0.82~0.91 불변. top-25 노이즈 아티팩트 아님.

### (d) PIT / 정렬 sane 여부 → **clean, 어제 5-버그 전부 통과**
- **β-alignment check (핵심)**: EW-전체유니버스 fwd_ret를 market_fwd에 회귀 → **β(lag0)=0.735, β(mkt_lag1)=−0.068, β(mkt_lead1)=+0.030**.
  - lag0만 유의(cor 0.805), ±1 오프셋은 ~0 → **realized_ym/forward 오프셋 버그 없음**(있었다면 lag±1 중 하나가 ≈1, lag0≈0이어야). 정렬 정확.
  - β=0.735(<1)은 오정렬이 아니라 **cap-weighted KOSPI200 벤치(sd 0.0669) vs EW 소형주틸트 패널(sd 0.0611)의 damping**. β=cor×(sd_ew/sd_mkt)=0.805×0.913=0.735. [[reference-orthogonality-gross-vs-active]]의 β≈0.99는 EW-market 기준이었고, 여기 벤치는 cap-w라 EW 패널 β<1이 정상.
- **벤치 정확성**: market_fwd로 compound한 국면 depth가 episodes.csv depth_pct와 일치(GFC_2009 −41.9% vs −41.86, Bear −35.9% vs −35.89, Euro −20.7% vs −20.65). `.cache/benchmark.parquet`(IKS200 KOSPI200)를 −1 shift하면 **cor=1.000** — market_fwd는 forward-labeled KOSPI200. IKS001 전체 아님. 어제 벤치버그 미재발.
- **orient**: 패널 pre-C13 Z_Score를 survey_master `direction`(111 higher_better / 55 lower_better)으로 정렬. 예 beta 팩터가 higher_better = Z가 이미 방어정렬. 재측정서 부호 적용 확인.
- **aggregation 비합성**: 재현 결과 그들의 epact = 국면 내 **compound active**(prod(1+port)−1 − prod(1+mkt)−1). 내 cum_active 컬럼이 그들 값을 정확 재현(D48 median 0.1222, GFC_2007-12 0.1269, Euro 0.1664, COVID −0.0499). 국면 창 내 compounding은 자체합성 아님(포트 시계열 손합성 아님).

**적대검증 결론**: 파이프라인 정확. 랭킹·부호·robustness 모두 독립 재현. 5-버그 벤치 clean.

---

## 3. Book-3 대조 (낙폭구간 방어 순위)

| 팩터 | median epact | hit | rank_of_all(166) |
|---|---|---|---|
| Q07_Earnings_Stability | 0.0576 | 0.909 | **66** |
| M08_Residual_Mom | 0.0332 | 0.727 | **96** |
| Q25_Ohlson_O | 0.0301 | 0.545 | **100** |

- 저β D-family/downside-tail 상위(D48/D45/D57/RE07/D28/D49 median 0.11~0.12, hit 0.91~1.0)는 **낙폭구간서 book-3보다 시장을 확실히 덜 잃는다** (median epact 2배 이상, hit 우월).
- 즉 crash lens 한정으로는 저β 팩터가 book-3(특히 Q25 hit 0.545 = 국면 절반은 패)보다 **명백히 우월한 방어력**.

---

## 4. Cash 대비 (long-only 절대수익)

- 상위 방어팩터도 **깊은 국면 절대수익은 음수 불가피**. D48 top-25 절대 compound: GFC_2009 −0.04, COVID −0.088, DD_2026 −0.091, Bear −0.013. 국면 시장은 GFC_2009 −0.056, COVID −0.069, DD_2026 −0.202.
- 시장 대비는 이기나(active +), **cash(오버레이, 절대 0%)는 여전히 절대수익으로 지배**. 어떤 방어팩터도 깊은 국면서 절대 양수 아님.
- 이는 §6 확립 진실과 정합: long-only β≈1(cap-w 대비 0.735) 바닥 → no-short로 시장 드리프트 제거 불가 → cash overlay가 유일한 절대-방어 레버.

---

## ★ 최종 답 (도훈 직문)

### (A) 낙폭 에피소드 lens 시장-대비 아웃퍼폼 방어팩터 top

| rank | code | median epact | hit | defclass |
|---|---|---|---|---|
| 1 | D48_VaR_5pct | 0.122 | 0.909 | downside_tail |
| 2 | D45_Downside_Dev | 0.117 | 0.909 | downside_tail |
| 3 | D28_Unlevered_Beta | 0.114 | 0.909 | lowbeta |
| 4 | D49_VaR_1pct | 0.113 | 0.909 | downside_tail |
| 5 | D57_Down_Vol / R08_Semi_Variance | 0.111 | 0.909 | lowvol/tail |
| 6 | RE07_Crisis_Beta | 0.099 | **1.000** | downside_tail |
| 7 | D20_EW_Beta_126 | 0.100 | **1.000** | lowbeta |

(Q01_GPA median 0.122 hit 0.818은 quality지만 낙폭방어서도 상위 — GPA=수익성 우량주 플라이트투퀄리티). 코어 클러스터 = **downside-tail(VaR/Downside-Dev/Semi-Var) + low-beta**. 재측정서 순위·부호 독립 재현.

### (B) 원 survey "더 나은 방어팩터 없음" 결론을 뒤집나? → **부분적으로 시정, 그러나 실질 결론은 불변**

- **프레이밍 시정 (Yes)**: 원 survey는 **전기간 PORT_t**로 방어팩터를 채점했고, 저β/downside 팩터들의 PORT_t가 음수(D45 −1.423, D11 −1.322, D20 −1.256, D50 −0.742)라 "방어 실익 없음"으로 기각했다. 이는 **AX-001 v2 위반 프레이밍**이었다 — 방어형은 전기간 SR/PORT_t가 아니라 *조건부* crisis-alpha로 평가해야 한다. **낙폭 lens에선 이 팩터들이 book-3보다 확실히 우월**(median epact 2배, hit 0.9~1.0). 즉 "전기간 PORT_t 음수 = 방어 무용"은 틀린 귀속이었다.
- **실질 결론 불변 (No 뒤집힘)**: 그럼에도 §6/방어전수조사([[project-defense-factor-db-survey-settled]]) 결론은 **살아있다**. 낙폭구간 우월이 *sleeve 자격*을 주지 않는 이유:
  1. sleeve는 full-period도 살아야 하는데(measurement-graduation screening tier도 신호력 요구) 이 팩터들은 정상장서 시장을 못 이겨 전기간 PORT_t 음수 → **정상장 페널티가 crisis 이득을 상쇄**.
  2. cash overlay가 절대-방어로 여전히 지배(§4) — "시장보다 덜 잃음"은 overlay의 "안 잃음"에 strictly dominated.

### (C) 실무 함의

**(i) Q07과 직교인가 중복인가**: 상위 저β/downside 팩터는 Q07(quality)과 **defclass가 다르다**(downside_tail/lowbeta vs quality_safety). 단 [[project-defense-factor-db-survey-settled]]가 "최상위 방어후보 Q07과 active cor 0.85+ 중복"을 이미 실측 — 국면 프로파일이 겹칠 개연 높음. 낙폭 median 우월이 곧 직교 증분은 아님(active-basis cor 검증 필요, 본 과제 범위 밖 — 후속).

**(ii) cash 대체/보완하나**: **아니오. 여전히 overlay 지배.** long-only 방어팩터는 절대수익 음수(§4)라 cash(0%)를 절대-방어로 못 이긴다. crash lens 우월은 "long 유지 시 어느 종목이 덜 빠지나"의 상대 순위일 뿐, "빠지느냐 마느냐"의 overlay 결정을 대체 못함. [[reference-kr-sr-ceiling-overlay]]·[[project-pg2-offense-overlay-settled]] 정합.

**(iii) book 방어슬리브 교체·추가 실익**: **없음(교체) / 조건부(진단축).**
- 교체 불가: [[project-defense-factor-db-survey-settled]] 확정 — M08 빼면 노이즈 SR +0.065에 MDD +3.7pp(헌법위반), 방어군·직교군 대체 없음. 낙폭 median 우월 팩터도 full-period 음수 PORT_t라 sleeve 교체 시 정상장 손실.
- 조건부 활용: 이 팩터들은 **국면-조건부 오버레이 신호/RCMA CRISIS specialist 후보**로는 유효(factor-rotation Lane3, 등급무관 국면성과 admission). sleeve(전기간 상시보유)로는 부적격이나 **regime-conditional 소비 경로**는 열려있음.

---

## 결론 한 줄
낙폭 lens는 원 survey의 **평가 프레이밍(전기간 PORT_t로 방어형 기각)을 AX-001 v2 관점에서 시정**하지만, **자본/sleeve 결론은 뒤집지 못한다** — 저β·downside-tail 팩터는 crash서 book-3보다 확실히 덜 잃으나(상대 우월 실재), 정상장 페널티로 full-period 미달 + cash overlay가 절대-방어로 지배하기 때문. 실익 경로는 sleeve 교체가 아니라 **regime-conditional overlay/RCMA specialist**. 파이프라인은 5-버그 clean, A=B 완전 수렴.
