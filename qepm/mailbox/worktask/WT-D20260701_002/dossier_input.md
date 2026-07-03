# WT-D20260701_002 — PG2 오버레이 승격 dossier 입력 (forge/judge 그라운딩)

## 개선안 정의 (일체 수정 없이 논문④ 충실)
- **교체 대상**: STR_1715_AR_on_M4_R05_overlay_PG2 book의 **β_AR 층(absorption ratio, `beta_threshold_lag`)** 한 개만.
- **교체 신호**: 논문④(Safari-Schmidhuber arXiv 2606.20145) 충실 예측변동성
  `σ̂²_{t+1} = 0.13 + 0.79·σ²_t − 0.17·ϕ_t + 0.09·ϕ²_t` (논문 원계수, 주식 e=−0.17)
  - ϕ = 논문 정확정의: `w(n)=n·e^{−2n/T}` L2정규화 가중합의 표준화수익, T=16, cap±2.5
  - σ²_t = EWMA(α=1−e^{−1/16})
- **β 매핑**: 신호의 *확장 과거백분위* → {0.4,0.7,1.0} 계단, 빈도는 β_AR와 매칭(0.4=11%/0.7=25%). PIT.
- **수익경로**: `ret = β_R05_V5 × [β_faithful] × m4_weight_lag × ret_orig − Δβ_faithful×15bps − Δβ_R05×15bps`
  - M4·R05·STR1715·R05비용 전부 불변. β_AR만 교체.
- **PIT**: ϕ/σ²는 KOSPI(benchmark.parquet) ≤t-1, 월말값 lag-1, 확장백분위 과거만. β_R05 규약(t-1)과 동일.

## 검증 결과 (proxy 재구성 + 계약 PerformanceAnalytics official, 2004-2026 269m)
| 지표 | 현행(AR) | 개선(충실) |
|---|---|---|
| 샤프(계약) | 1.837 | 2.111 |
| MDD | -23.3% | -21.2% |
| Calmar | 1.659 | 2.081 |
| Sortino | 1.127 | 1.460 |
- paired-NW-t(개선−현행, 월수익) = **+2.04** (유의)
- oos_retention(개선분 diff, anchored 3-split median) = **1.10** (≥0.7 통과)
- placebo(신호 시간셔플) = 엣지 소멸(SR 1.575<book) → real 타이밍
- 호라이즌 T=8/16/32/64 전부 유의(+1.9~2.4)
- KR 계수 최적화 불필요(논문계수 ≈ PIT-KR-fit ≈ full-sample)
- holdout 사전등록: 샤프 예측구간 [0.66, 3.19] 봉인 (`holdout_paper4_ret_faith.json`)

## ★정직한 캐비앗 (dossier 필수 기재)
1. **메커니즘 = generic 비대칭 추세추종**, 논문④ 고유 아님 — plain-TS-mom(단순 하락추세 방어)도 계약SR 1.970(개선 2.111의 ~93%).
2. **결합안(min(AR,충실))은 OOS 불안정**(diff oos_retention 폭발) → 폐기, 충실 단독 채택.
3. **proxy 재구성** — forge full build_bt_result로 official 승격 필요.
4. 다변형 탐색이라 **DSR 다중검정 haircut 여지**(단 사전약정 논문계수가 placebo+oos 통과).
5. 2008 GFC 구간낙폭은 AR(9.3%)이 충실(17.5%)보다 우위 — 충실은 추세de-risk지 systemic-crash 탐지 아님.

## 입력 데이터
- `verify_overlay_series.csv`: ym·date·**ret_book(현행)**·**ret_faith(개선)**·ret_combine·ret_tsmom·ret_placebo·bmret(KOSPI 월간)
- book 원천: `05_Production/.../STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv` (읽기전용)
- 재현 스크립트: `scripts/` (ar_faithful_v3.py 등)
- book bt_result 구조 참고: `run_layer5_R05_overlay.R` (holdings=NULL, PerformanceAnalytics 표준)
