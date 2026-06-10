# B1 — STR_1715 PG2 4-Family Forensic Decomposition (1차)

**작성**: 2026-06-10 · **성격**: 진단(diagnostic) 전용 — 등급 선언 없음, admission 근거 사용 금지
**대상**: STR_1715_AR_on_M4_R05_overlay_PG2 (production PG2 book) L1 알파 7팩터
**후속**: E7 sleeve-level dynamic tilt 설계의 전제조건 분석

> **모든 수치 라벨 원칙**: 이 문서의 IC·재구성 포트 수치는 전부 `metric_type=proxy` (진단 전용).
> 의사결정 지표는 PORT_t (rank-IC는 advisory — `measurement-graduation.md` §3).
> 실제 book 수익률 권위 = `04_backtest_results/period_returns_layer5.csv`의 `ret_orig` (`metric_type=backtested`).

---

## 0. 데이터 정합 검증 (분석 전제 — b0 시리즈에서 실증)

| 검증 항목 | 결과 | 근거 스크립트 |
|---|---|---|
| `Ret_1m` @ score Date t의 커버 월 | **calendar month(t)+1** (BM 대비 corr 0.8985) | `b0b_align_check.R` |
| Factor DB 월 m 빌드 vintage | month-end(m) 데이터 (parquet Date col = 월말, builder PIT `Date <= sig_date`) | `b0d_fdb_vintage.R` |
| production `realized_ym=m` 행의 커버 월 | **calendar m−1** (period-end 라벨링; BM 대비 corr 0.71 @ m−1) | `b0c_retorig_check.R` |
| production 정합 (lookahead 부재) | top-20 EW 재구성 vs `ret_orig`: **pearson 0.81 @ realized_ym = month(t)+2** (offset 0/+1/+3은 모두 ~0) | `b0e_prod_coherence.R` |
| `Ret_1m` forward 구조 | NA 348건 전부 마지막 score date(2026-04-01)에만 존재 — forward return 구조 확인 | `b0_explore.R` |
| 7팩터 식별 충실도 | factor z 재구성 sleeve score vs production sleeve score: **core spearman 0.965 / defense 0.989** (월별 median) | `b1_step1_factor_pull.R` |
| blend 공식 | `score_eff = 0.65·score_core_z + 0.35·score_defense_z` **exact (max|diff|=0)** | `b1_step3_ablation_oos.R` |

→ 과제 명세의 PIT 구조("점수는 t월말, 수익은 t+1월")가 **parquet에서 그대로 성립함을 검증 후 사용**했습니다.

---

## 1. 7팩터 rank-IC 진단 (`b1_factor_ic_table.json`)

라벨: **diagnostic_only — 의사결정 지표는 PORT_t (rank-IC는 advisory, measurement-graduation §3)**
방법: 월간 cross-sectional Spearman, Z_Score_Aligned(`load_month_factors()` 경유, C13/C14/C15 준수) vs Ret_1m. 267개월 (2004-01~2026-03 score dates).

| 팩터 | sleeve | mean IC | ICIR | NW-t(lag3) | hit | 최근36m IC | 최근36m hit |
|---|---|---|---|---|---|---|---|
| C04_ESBR | core | **0.0390** | **0.505** | **8.70** | 68.2% | 0.0440 | **86.1%** |
| C01_SUE | core | 0.0304 | 0.398 | 6.29 | 67.4% | 0.0438 | 77.8% |
| Q07_Earnings_Stability | defense | 0.0281 | 0.263 | 4.47 | 61.8% | **0.0522** | 75.0% |
| C06_TP_Gap | core | 0.0274 | 0.213 | 3.60 | 58.4% | 0.0172 | 55.6% |
| C02_EPS_Chg_1m | core | 0.0267 | 0.329 | 5.13 | 65.5% | 0.0177 | 75.0% |
| M08_Residual_Mom | defense | 0.0205 | 0.153 | 2.48 | 57.7% | 0.0346 | 52.8% |
| Q25_Ohlson_O | defense | 0.0130 | 0.121 | 2.02 | 56.9% | **0.0031** | 58.3% |

**관찰** (진단):
- **C04_ESBR가 전 구간·최근 공히 최강** (NW-t 8.7, 최근 hit 86%). C01_SUE가 2위.
- **Q07_Earnings_Stability는 defense인데 최근 36m IC가 7팩터 중 1위** (0.0522) — 최근 장세에서 quality-stability가 잘 작동.
- **Q25_Ohlson_O는 최근 36m IC 0.0031로 사실상 0** (전기간도 최약 0.0130).
- C06_TP_Gap·C02_EPS_Chg_1m은 최근 감쇠 (0.017대). 참고로 production의 IC-weighted theta가 이미 이를 반영 중 — 최신 월(2026-04) theta_core = C01 0.268 / C02 0.275 / C04 0.450 / **C06 0.007** (C06은 사실상 배제 상태).

---

## 2. Core-4 중복도 (`b1_redundancy_matrix.json`)

라벨: diagnostic_only (top-quintile EW 월수익 시계열은 진단용 — 백테스트·NAV 합성 아님).

- **Score 횡단면 corr** (268개월 평균 Spearman): 평균 pairwise **0.120**. 단 **C01_SUE × C04_ESBR = 0.679**로 유일하게 높음. 나머지 5쌍은 |ρ| ≤ 0.065.
- **팩터 수익률 corr** (top-quintile EW 월수익): raw는 0.88~0.97 (시장베타 공통항). **market-excess 기준 평균 0.068** — 단 **C01×C04 = 0.579**. C02×C06 = **−0.298** (상호보완적).
- **판정**: **"내부 분산 존재"** (avg score ρ 0.120 < 0.3, avg excess return ρ 0.068 < 0.5) — Core 4가 단일 Earnings 베팅은 아님. **유일한 예외 = C01_SUE↔C04_ESBR 부분 중복** (어닝 서프라이즈↔추정치 brea​dth가 같은 정보원 공유). E7 설계 시 이 쌍을 한 클러스터로 취급할 것.

---

## 3. Sleeve ablation (`b1_family_attribution.json`)

라벨: **proxy** — top-20 EW 재구성은 production(λ-tilt Iter31 + 유동성 필터 + buffer zone)의 **근사이며 production 재현이 아님** (production 정합 corr 0.81). 포트 수익률은 전부 `PerformanceAnalytics::Return.portfolio` (자체합성 없음). 기간 267개월, gross 기준 (net은 production 비용공식 estimated — JSON 참조).

| 변형 | SR (gross) | MDD | ann.ret | 비고 |
|---|---|---|---|---|
| **production ret_orig (권위)** | **1.631** | **40.7%** | 43.5% | metric_type=**backtested** |
| blend 65/35 (score_eff) | 1.044 | 37.4% | 26.0% | proxy 재구성 |
| core_only | 0.974 | 41.7% | 23.8% | |
| defense_only | 0.721 | 48.2% | 20.2% | |
| blend core65+Q07단독 | 0.972 | 40.2% | 23.2% | |
| blend core65+M08단독 | 0.915 | 39.6% | 23.3% | |
| blend core65+Q25단독 | 0.982 | 43.3% | 23.0% | |
| defense Q07 단독 | 0.486 | 48.7% | 9.6% | TO 0.087/mo (저회전) |
| defense M08 단독 | 0.659 | 53.2% | 19.4% | |
| defense Q25 단독 | 0.548 | 44.4% | 11.7% | |

- **ΔSR(blend − core_only) = +0.070 / ΔMDD = −4.4pp** (blend가 MDD 개선). ΔSR(blend − defense_only) = +0.323 / ΔMDD = −10.8pp.
- **Defense 3팩터 EW 복합이 어떤 단일 defense 대체보다 우월** (1.044 vs 0.915~0.982) — defense 내부 분산이 실제로 기여.
- **defense_only 단독은 "방어적"이지 않음** (MDD 48.2% > core_only 41.7%) — defense sleeve의 가치는 단독 방어가 아니라 **blend 한계 개선**(ΔSR/ΔMDD)에 있음. 단독 defense 약세는 AX-004/005/007 (KR single-signal long-only 구조적 실패)과 정합.
- 전기간 CRISIS 라벨 월이 3개뿐이라 위기-조건부(AX-001식) 평가는 이 표본으로 불가 — 정직 보고.
- production(1.631)과 blend proxy(1.044)의 SR 격차 = λ-tilt(λ=1.5) 최적화 가중 + 유동성/buffer + 비용·실행 차이의 합 — **본 분해는 sleeve 간 상대 비교에만 사용할 것**.

---

## 4. 최근 27개월 분해 (`b1_oos27m_decomposition.json`)

라벨: **"27m은 PASS_LOW_INFO 영역 (Sharpe SE ±0.6) — admission 근거 사용 금지"** + proxy.
윈도우: 수익월 2024-02 ~ 2026-04 (27개월), score dates 2024-01 ~ 2026-03.

- 변형별 (gross): blend SR 1.99/MDD 12.2% · core_only 1.87/13.9% · defense_only 1.33/21.8%. (production 참조 27행: SR 4.00/MDD 7.4%, backtested, calendar 2024-01~2026-03 — overlay 레이어 포함이라 직접 비교 불가.)
- **원천은 Core 우세**: blend top-20 명단 중첩 평균 — core_only와 13.5/20, defense_only와 6.5/20 (약 2:1). 월수익 corr: vs core 0.959, vs defense 0.906.
- regime별 (score date 기준, 월평균 gross): NORMAL(22m) blend 3.66% vs core 3.38% vs defense 2.78% — 최근 성과의 주 엔진은 core. CAUTION(2m)에서는 defense_only 8.46% > core 1.25% (표본 2개월 — 해석 금지 수준).
- 특이: blend core65+**Q25단독**이 27m SR 2.07로 최고 — 그러나 Q25의 최근 IC는 0.003. **rank-IC와 포트 성과의 괴리 실례** (PORT_t가 의사결정 지표인 이유). low-info 윈도우라 우연일 수 있음 — E7에서 placebo 검증 대상.

---

## 5. Core-Satellite 분류 제안 (진단 기반 — 등급 아님, E7 입력용)

| 팩터 | 제안 | 근거 (수치는 §1~4) |
|---|---|---|
| C04_ESBR | **core 유지** | 전기간·최근 최강 IC/ICIR/NW-t, 최근 hit 86% |
| C01_SUE | **core 유지** (단 C04와 클러스터 관리) | IC 2위·최근 견조. C04와 score ρ 0.68 / excess ret ρ 0.58 부분 중복 — E7에서 둘을 한 redundancy cluster로 |
| Q07_Earnings_Stability | **core 승격 후보** (defense 소속이나 최근 1위 IC) | 최근 36m IC 0.0522 (7팩터 중 1위), hit 75% |
| C02_EPS_Chg_1m | **satellite** | 전기간 healthy (ICIR 0.33)·최근 감쇠 (IC 0.018). C06과 excess ret ρ −0.30 보완성은 가치 |
| M08_Residual_Mom | **satellite** | IC 약함 (전기간 0.021, 최근 hit 52.8%). defense를 M08 단독으로 대체 시 blend SR 1.044→0.915 (3변형 중 최저) — 단독으론 약하나 3팩터 복합엔 기여 (복합 1.044 > 모든 단독대체) |
| C06_TP_Gap | **satellite / 축소 관찰** | 최근 36m IC 0.017·hit 55.6%. production IC-weighting이 이미 theta 0.007로 사실상 배제 중 |
| Q25_Ohlson_O | **제외 후보 (조건부)** | 전기간 IC 최약 0.013·최근 0.003 — 신호 사멸 의심. **단** §4의 Q25단독-defense blend가 27m 최고 SR (low-info) + §3 전기간 0.982로 중립 — 제거는 placebo/홀드아웃 검증 후 결정 권고 |

**E7 시사점**: ① sleeve tilt의 1차 후보축 = Q07↑(최근 강) vs C06/Q25↓(감쇠) — 단 production theta가 core 내부는 이미 동적이므로, **미커버 영역은 defense 내부 가중(현 EW 고정 1/3)과 sleeve 비율(고정 65/35)**. ② C01·C04 클러스터 중복 관리. ③ 모든 tilt 설계는 PORT_t 실측 게이트(NW lag-3) + placebo로 검증 — rank-IC만으로 tilt 금지.

---

## 6. 한계 정직 보고

1. **top-20 EW 재구성 ≈ production 근사** (corr 0.81): λ-tilt Iter31 가중·유동성 필터·buffer zone 미반영. sleeve 간 **상대 비교 전용**이며 절대 수준은 production `ret_orig`와 다름.
2. **IC 지표는 전부 advisory** — graduation/admission 게이트와 무관. 이 분석으로 등급·편입 판단 불가.
3. **27m 윈도우는 PASS_LOW_INFO** (Sharpe SE ±0.6) — §4·§5의 "최근" 논거는 가설 생성용.
4. **방향 정렬은 connector의 expanding-IC 기반** (PIT, Usable_Date ≤ sig_date) — 초기 연도 direction 추정 불안정 가능. 충실도 (월별 median 0.965/0.989)로 대체 검증, 월별 충실도는 `intermediate/construction_fidelity_by_month.csv` 보존.
5. **C01_SUE 커버리지 82.8%** (타 팩터 93~99%) — SUE 결측 패턴이 IC 비교에 영향 가능 (월 평균 246종목으로 계산 자체는 안정).
6. **net 수치는 estimated** (production 비용공식 ret − 0.0015×one-way TO 재적용) — 실측 체결 비용 아님.
7. **전기간 CRISIS 표본 3개월** — 위기-조건부 defense 평가 (AX-001 양식) 불가. 별도 일간 데이터 기반 분석 필요.
8. `.cache/benchmark.parquet`의 2026-06 일자 구간에 비정상 변동(일간 ±8%, naver patch 백업 다수)이 관찰됨 — 본 분석의 정렬 검증 윈도우(~2026-04)는 그 이전 구간이며 corr 0.90/0.81로 판정에 충분했음. 단 **BM 캐시 최근 구간 정합은 별도 점검 권고**.
9. 산출물 미포함: 개별 팩터 단위의 진짜 4-family "기여 분해"(Shapley 등) — 선택(top-20) 비선형성 때문에 가산 분해가 정의되지 않아 ablation(변형 비교)으로 대체. 명세 범위 내.

---

## 산출물 맵

| 파일 | 내용 |
|---|---|
| `b1_factor_ic_table.json` | 7팩터 rank-IC 진단 (라벨 포함) |
| `b1_redundancy_matrix.json` | Core-4 score/return corr + 판정 |
| `b1_family_attribution.json` | sleeve ablation 9변형 + production 권위 + ΔSR/ΔMDD |
| `b1_oos27m_decomposition.json` | 최근 27m 변형·regime·sleeve 원천 분해 |
| `b0_explore.R` ~ `b0g_json_check.R` | 데이터 정합 검증 스크립트 (재현용) |
| `b1_step1_factor_pull.R` / `b1_step2_ic_redundancy.R` / `b1_step3_ablation_oos.R` | 본 분석 스크립트 (재현용) |
| `intermediate/` | factor_panel_7f.parquet · 월별 IC · top-quintile 시계열 · 선택명단 · xts RDS · 충실도 CSV |
