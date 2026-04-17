---
name: risk-modeling-advanced
description: "리스크 모델링 고급 스킬 — EVT-VaR, CF-VaR, CDaR, GARCH, Copula, CVaR LP, SOCP. Pfaff(2016) 기반. 전략 평가/포트폴리오 위험 계산 시 적용."
context: fork
agent: general-purpose
allowed-tools: Bash(Rscript*) Read Grep Glob
---

## 리스크 모델링 고급 규칙 (Pfaff 2016 기반)

### 적용 시점
- S1 백테스트 후 tail risk 산출
- S2 프로파일링: EVT 프로파일 + 분포 피팅
- S3 직교성: Copula TDC + DCC-GARCH
- S6 검증: Gate 6 tail risk
- PG2 배분: CVaR LP / CDaR / MTD / SOCP
- 프로덕션 모니터링: 일간 EVT-VaR + DCC 상관

### 1. EVT-VaR (Ch.7 — 최우선)

포트폴리오 꼬리 위험을 GPD(Generalized Pareto Distribution)로 추정.
정규분포 VaR는 99%+ 에서 체계적으로 과소추정.

```r
source(file.path(INFRA_DIR, "portfolio/tail_risk_engine.R"))
result <- compute_evt_var(daily_returns, p = 0.99, threshold_q = 0.95)
# result$var_evt, result$es_evt, result$shape_xi
```

**필수 진단**: `evd::mrlplot()` + `evd::tcplot()` — threshold 선택 시각화
**declustering 민감도**: ξ 추정치가 run 파라미터에 민감 → 반드시 확인

### 2. Cornish-Fisher VaR (Ch.6)

왜도/첨도 보정 VaR. EVT보다 가볍지만 비정규 보정 가능.

```r
result <- compute_cf_var(daily_returns, p = 0.99)
# z_cf = z_α + (z²-1)*S/6 + (z³-3z)*K/24 - (2z³-5z)*S²/36
```

### 3. CDaR (Ch.12)

Conditional Drawdown at Risk. MDD의 확률적 버전.

```r
result <- compute_cdar(nav_series, alpha = 0.95)
# 상위 5% drawdown의 평균 = "최악 시나리오 평균 낙폭"
```

### 4. ES 성분 분해 (Ch.12)

어느 팩터/종목이 포트폴리오 꼬리 위험에 기여하는지.

```r
result <- compute_es_decomposition(factor_returns, weights, alpha = 0.05)
# 단일 팩터 기여 > 50%면 집중 경고
```

### 5. DCC-GARCH (Ch.8-9, Phase 2)

시변 상관 추정. 위기 시 상관 급등 포착.

```r
# rugarch::ugarchspec() × N팩터 → rmgarch::dccfit()
fit <- fit_dcc_garch(factor_returns_matrix, dist = "std")
es <- forecast_conditional_es(fit, p = 0.975)
```

### 6. Copula (Ch.9, Phase 2)

비선형 꼬리 의존성. 선형 상관이 0이어도 위기 시 공동 폭락 가능.

```r
tdc <- compute_copula_tdc(ret_a, ret_b)  # Clayton TDC
# TDC > 0.30이면 diversifier 실효성 의심
```

### 7. CVaR LP (Ch.12, Phase 2)

Rockafellar-Uryasev LP 최적화. 비정규 수익률에서 최적 가중치.

```r
w <- calc_cvar_lp_weights(tickers, ret_dt, alpha = 0.95, max_w = 0.15)
# fPortfolio::setType("CVaR") + solveRglpk.CVAR
```

### 8. Robust SOCP (Ch.10, Phase 2)

불확실성 집합 기반 강건 최적화.

```r
w <- solve_robust_socp_weights(mu, Sigma, uncertainty = "ellipsoid", theta = 0.5)
# cccp::socc() + nnoc()
```

### 금지사항
- `qnorm() * sd()` Normal VaR 사용 금지 (OPT-6 hook block)
- 꼬리 위험 없이 전략 평가 금지 (risk_gate hook)
- S6에서 tail_risk_result.json 없이 DONE 금지 (Phase 2)
- 단일 모델만 신뢰 금지 — EVT + CF + CDaR 최소 2개 교차 확인

### R 패키지 레퍼런스
| 패키지 | 핵심 함수 | 용도 |
|--------|----------|------|
| fExtremes | gpdFit(), gpdRiskMeasures(), mrlPlot() | EVT |
| evir | gpd(), riskmeasures(), shape() | EVT |
| evd | mrlplot(), tcplot(), fpot() | EVT 진단 |
| PerformanceAnalytics | ES(portfolio_method="component") | ES 분해 |
| rugarch | ugarchspec(), ugarchroll() | GARCH |
| rmgarch | dccfit(), dccspec() | DCC-GARCH |
| copula | fitCopula(), gofCopula(), tCopula() | Copula |
| FRAPO | PMinCDaR(), PMTD(), tdc() | CDaR/MTD |
| Rglpk | Rglpk_solve_LP() | CVaR LP |
| cccp | cccp(), socc(), rp() | SOCP |
| ghyp | fit.ghypuv(), portfolio.optimize() | GHD 최적화 |
