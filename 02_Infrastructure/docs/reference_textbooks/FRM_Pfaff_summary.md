# FRM (Financial Risk Modeling, Pfaff R-based) 핵심 챕터 요약

> **Source**: Bernhard Pfaff. *Financial Risk Modelling and Portfolio Optimization with R*. Wiley, 2nd ed. 2016. 436 pages.
> **License**: Pfaff R 코드는 공개 (CRAN packages MIT/GPL). 본 요약은 algorithm reference로만 사용.
> **추출 도구**: pdftools fallback (Hancom 파서 PDFBox NPE bug)
> **작성일**: 2026-04-30 (Phase 1, textbook 흡수 plan)

## 책 구조 (3 Part)

- **Part I**: Introduction, R, Financial market data, **Measuring risks**, MPT (Ch1-5)
- **Part II**: Distributions (Ch6), **EVT (Ch7)**, **GARCH (Ch8)**, **Copula (Ch9)** — unconditional/conditional 분포 모델링
- **Part III**: **Robust opt (Ch10)**, **Diversification (Ch11)**, **Risk-optimal (Ch12)**, **TAA (Ch13)**, Probabilistic utility (Ch14)

## Agent 매핑 (우선순위)

| Ch | 주제 | Agent | R 패키지 | 우선순위 |
|----|------|-------|---------|---------|
| 4 | VaR / CVaR / ES / Drawdown | **Risk** | `PerformanceAnalytics` | 기본 (이미 사용) |
| 7 | EVT (GPD / Hill α) | **Risk** | `fExtremes`, `evd`, `evir` | **HIGH** ⭐ |
| 8 | GARCH / EGARCH / GJR / t-GARCH | **Risk** | `rugarch`, `fGarch` | **HIGH** ⭐ |
| 9 | Copula (Gaussian/Student-t/Clayton/Gumbel/Frank) | **Risk** | `copula`, `fCopulae` | **HIGH** ⭐ |
| 10 | Robust opt (M-estimator/MCD/Shrinkage) | **Optimizer** | `fPortfolio`, `MASS::cov.mcd`, `robustbase` | **HIGH** ⭐ |
| 11 | MDP / Min Tail Dep / ERC (Risk Parity) | **Optimizer** | `fPortfolio` | **HIGH** ⭐ |
| 12 | Min CVaR / Min CDaR | **Optimizer** | `Rglpk`, `Rsolnp`, `fPortfolio::minCVaRPortfolio` | **HIGH** ⭐ |
| 13 | Black-Litterman / Copula-GARCH TAA | Alpha (보조) | `BLCOP`, `rugarch::dccfit` | MED |

---

## Ch4 Measuring Risks (p37)

**핵심 mechanism**:
- **Coherent risk measure 4 axiom** (Artzner et al. 1999): translation invariance / sub-additivity / positive homogeneity / monotonicity
- **VaR**: quantile, NOT coherent (sub-additivity 위반 가능)
- **ES (CVaR)**: coherent, **권고**
- **Lower Partial Moments (LPM)**: downside-only volatility, Sortino ratio 기반
- **Maximum Drawdown**: 경로의존, 시계열 단위

**R 함수 (`PerformanceAnalytics`)**:
```r
VaR(R, p = 0.95, method = "historical" / "gaussian" / "modified")  # Cornish-Fisher
ES(R, p = 0.95, method = "historical" / "gaussian" / "modified")
maxDrawdown(R)
SortinoRatio(R, MAR = 0)
```

**우리 시스템 적용**:
- 이미 `risk_package.json::tail_risk` 에서 VaR/CVaR/ES 사용 중. ✓
- **추가 활용 가능**: Modified Cornish-Fisher VaR (heavy-tail 보정) — `method="modified"` 옵션

---

## Ch7 Extreme Value Theory (p89)

**핵심 mechanism**:
- **Block Maxima Method (BMM)**: 데이터 블록(예: 월) 최대값 → **Generalized Extreme Value (GEV)** 분포 fit
- **Peaks-over-Threshold (POT)**: threshold u 초과 분포 → **Generalized Pareto Distribution (GPD)** fit
- **Hill estimator** for tail index α: heavy-tail 정도 측정
- **Threshold selection**: mean residual life plot, Hill plot, 80%/90%/95% quantile

**R 함수**:
```r
# fExtremes (Pfaff 우선)
library(fExtremes)
gpdFit(x, u = quantile(x, 0.90))           # GPD fit at 90% threshold
gpdRiskMeasures(fit, prob = c(0.95, 0.99)) # VaR + ES under GPD
gevFit(x, type = "mle")                    # GEV fit
hillPlot(x, ci = 0.95)                     # Hill plot for tail index

# evir (alternative)
gpd(x, threshold = quantile(x, 0.90))
quant(fit, p = 0.99)
```

**우리 시스템 적용**:
- WT-D20260430_001 risk_package에서 Hill α 2.78 (S3) / EVT-GPD ξ 0.04 산출. **이미 일부 사용**.
- **추가 활용 가능**: 
  - POT 80%/90%/95% threshold 민감도 분석 (현재 단일 threshold)
  - GPD risk measures (VaR_99 / ES_99)를 정식 산출 → tail_risk.json 보강
- **PoC R 모듈**: `02_Infrastructure/risk/textbook_methods/evt_engine.R` (Phase 5.1)

---

## Ch8 Modelling Volatility (p116)

**핵심 mechanism**:
- **ARCH(p)** (Engle 1982): conditional variance autoregressive
- **GARCH(p,q)** (Bollerslev 1986): ARCH + lagged variance
- **EGARCH** (Nelson 1991): leverage effect (asymmetric, 음의 충격 → 분산 ↑)
- **GJR-GARCH** (Glosten-Jagannathan-Runkle 1993): leverage effect 다른 방식
- **t-GARCH / Skew-t-GARCH**: heavy-tail innovation
- **DCC-GARCH** (Engle 2002): dynamic conditional correlation (multi-asset)

**R 함수 (`rugarch` — most comprehensive)**:
```r
library(rugarch)
spec <- ugarchspec(
  variance.model = list(model = "sGARCH",  # or "eGARCH", "gjrGARCH", "iGARCH"
                        garchOrder = c(1, 1)),
  mean.model = list(armaOrder = c(0, 0)),
  distribution.model = "std"  # student-t innovation
)
fit <- ugarchfit(spec, data = returns)
forecast <- ugarchforecast(fit, n.ahead = 10)
roll <- ugarchroll(spec, data = returns, n.ahead = 1, refit.every = 22)
```

**우리 시스템 적용**:
- 현 risk agent: Σ는 Ledoit-Wolf static / 또는 sample. **conditional volatility 미사용**.
- **추가 활용 가능**: 
  - regime-conditional volatility (정상/위기 별 GARCH 비교)
  - DCC-GARCH로 STR_1715 vs cash time-varying correlation
  - Risk agent의 stress test에 EGARCH leverage effect 반영

---

## Ch9 Modelling Dependence (Copula) (p133)

**핵심 mechanism**:
- **Linear correlation 한계**: only multivariate normal에서 dependence 완전 표현
- **Rank correlation**: Kendall τ (concordance/discordance), Spearman ρ
- **Tail dependence**: λ_lower (위기 동시 하락 확률), λ_upper
- **Sklar 정리**: F(x,y) = C(F_X(x), F_Y(y)) — marginal과 dependence 분리
- **Copula 패밀리**:
  - **Elliptical**: Gaussian (zero tail dep), Student-t (symmetric tail dep)
  - **Archimedean**: Clayton (lower tail), Gumbel (upper tail), Frank (no tail)
  - **Hierarchical Archimedean**, **Vine copula** (high-dim)

**R 함수 (`copula`)**:
```r
library(copula)
# Specify
nc <- normalCopula(rho = 0.5, dim = 2)
tc <- tCopula(rho = 0.5, df = 4, dim = 2)
cc <- claytonCopula(theta = 2, dim = 2)
gc <- gumbelCopula(theta = 1.5, dim = 2)
fc <- frankCopula(theta = 5, dim = 2)

# PIT marginal transformation
u <- pobs(data)  # pseudo-observations

# Fit
fit <- fitCopula(tc, u, method = "ml")
tau <- kendallsTau(tc)
lambda <- tailIndex(tc)  # (lower, upper)

# Simulate
sim <- rCopula(1000, tc)
```

**우리 시스템 적용**:
- 이전 cycle Risk agent: empirical Joe-Clayton TDC q5 산출 (위기 17개월 분리도 0.46) — copula 사용 흔적.
- **추가 활용 가능**:
  - Student-t copula로 TDC 모델 fit (현재 empirical만)
  - Vine copula로 multi-asset 확장 (단 단일 sleeve라 직접 적용 한계)
  - Copula-GARCH 통합 (Ch8 + Ch9) — TAA 시점 결정에 활용

---

## Ch10 Robust Portfolio Optimization (p163)

**핵심 mechanism**:
- **Estimation uncertainty 문제**: 표본 평균/공분산 추정 오차가 portfolio weight를 폭주시킴 (corner solution)
- **Robust statistics**:
  - **M-estimator**: maximum likelihood with influence function 제한
  - **MVE (Minimum Volume Ellipsoid)**: outlier-robust covariance
  - **MCD (Minimum Covariance Determinant)** (Rousseeuw 1985): subset 최소 결정자
  - **Stahel-Donoho**: projection-based outlier weight
- **Shrinkage estimator** (Ledoit-Wolf 2003/2004): sample → identity 또는 const-correlation 으로 수축
- **Black-Litterman**: prior + investor views

**R 함수**:
```r
# Robust covariance
library(MASS)
cov.rob(data, method = "mcd")  # MCD
cov.rob(data, method = "mve")  # MVE

library(robustbase)
covMcd(data)  # 더 정밀한 MCD

# Shrinkage (이미 사용 중 — Ledoit-Wolf)
library(corpcor)
cov.shrink(data, lambda = NULL)  # auto shrinkage

# Robust portfolio
library(fPortfolio)
spec <- portfolioSpec()
setEstimator(spec) <- "covMcdEstimator"  # robust
minRiskPortfolio(data, spec)
```

**우리 시스템 적용**:
- 이전 Risk agent: Ledoit-Wolf constcor (cond 87.46) — **이미 robust shrinkage 사용**.
- **추가 활용 가능**:
  - MCD로 robust covariance 비교 (Ledoit-Wolf vs MCD condition number)
  - Black-Litterman에 regime priors 반영 (Ch13과 통합)
- **PoC R 모듈**: `02_Infrastructure/portfolio/textbook_methods/robust_opt.R` (Phase 5.2)

---

## Ch11 Diversification Reconsidered (p198)

**핵심 mechanism**:
- **Most-Diversified Portfolio (MDP)** (Choueifaty-Coignard 2008): diversification ratio = (Σ w_i σ_i) / σ_p 최대화
- **Min Tail Dependent**: portfolio TDC 최소화 (위기 시 sub-additivity)
- **Equal Risk Contribution (ERC) / Risk Parity**: 각 asset의 marginal risk contribution 균등화
  - MRC_i = w_i * (Σw)_i / sqrt(w'Σw)
- **Hierarchical Risk Parity (HRP)** (López de Prado 2016): tree clustering + recursive bisection (이미 사용)

**R 함수 (`fPortfolio` + 직접 구현)**:
```r
library(fPortfolio)
# MDP
spec <- portfolioSpec()
setSolver(spec) <- "solveRshortExact"
mdpPortfolio(data, spec)  # diversification ratio max

# ERC (Risk Parity)
# 직접 구현 — Maillard-Roncalli-Teiletche 2010
erc_weights <- function(Sigma) {
  # objective: min sum_{i,j}(MRC_i - MRC_j)^2
  optim(...)
}
```

**우리 시스템 적용**:
- 이전 Optimizer: HRP 사용 (이미). MDP / ERC는 미사용.
- **추가 활용 가능**:
  - MDP method 추가 → method shopping 4 → 5+
  - ERC와 HRP 비교 (clustering 효과 차이)

---

## Ch12 Risk-Optimal Portfolios (p228)

**핵심 mechanism**:
- **Mean-VaR**: NLP (VaR is non-convex)
- **Mean-CVaR (Min CVaR)**: **LP (linear program)** — Rockafellar-Uryasev (2000) 정리. CVaR 최소화는 sub-additive + convex.
- **Mean-MD (Min DD)**: drawdown 직접 최소화
- **Mean-CDaR (Min Conditional Drawdown-at-Risk)**: drawdown CVaR

**R 함수**:
```r
# Min CVaR via LP
library(Rglpk)
# Rockafellar-Uryasev formulation
# minimize: alpha + (1/(N*(1-p))) * sum(z_n)
# subject to: z_n >= -r_n'*w - alpha, z_n >= 0, sum(w) = 1, w >= 0
Rglpk_solve_LP(obj, mat, dir, rhs, types)

library(fPortfolio)
spec <- portfolioSpec()
setType(spec) <- "CVaR"
setAlpha(spec) <- 0.05
minRiskPortfolio(data, spec)  # Min CVaR

# Min CDaR
# Chekhlov-Uryasev-Zabarankin (2005)
# 직접 구현 또는 PortfolioAnalytics package
```

**우리 시스템 적용**:
- 이전 Optimizer: CVaR LP 시도했으나 TDC FAIL → HRP 선정. **CVaR LP는 한 번 fail**.
- **추가 활용 가능**:
  - Min CDaR (drawdown control) → STR_1715 MDD 35.56% 직접 최소화
  - Mean-CVaR 재검토 (다른 cov matrix로)
- 단 본 시스템 alpha는 meta-allocation type이라 종목 단위 weight optimization 직접 적용 어려움

---

## Ch13 Tactical Asset Allocation (p274)

**핵심 mechanism**:
- **Black-Litterman (1992)**: equilibrium prior + investor views (Bayesian)
- **Time series models**: VAR, VECM
- **Copula-GARCH**: dependence + volatility 동시 모델링 (Ch8 + Ch9 통합)

**R 함수**:
```r
library(BLCOP)
priorViews <- BLViews(P, q, Confidences, assetNames)
posterior <- posteriorEst(views, prior_mean, prior_cov, tau)
optimal <- optimalPortfolios(posterior, ...)

library(rugarch)
specs <- multispec(replicate(2, ugarchspec(...)))
dcc.spec <- dccspec(uspec = specs, dccOrder = c(1,1), distribution = "mvt")
dcc.fit <- dccfit(dcc.spec, data = returns)
```

**우리 시스템 적용**:
- 본 WT-D20260430_001 alpha agent가 이미 Black-Litterman + regime priors (Shu-Mulvey 2024) 인용. **간접 사용**.
- **추가 활용 가능**: BLCOP 패키지로 직접 BL 산출

---

## 통합 적용 우선순위 (Phase 5 PoC 후보)

| 순위 | 모듈 | 챕터 | 가치 |
|---|---|---|---|
| 1 (HIGH) | EVT engine (`evt_engine.R`) | Ch7 | tail risk 정밀화, Hill α 보강 |
| 2 (HIGH) | Robust opt (`robust_opt.R`) | Ch10 | MCD 비교, weight stability 검증 |
| 3 (MED) | Min CDaR | Ch12 | drawdown 직접 최소화 |
| 4 (MED) | DCC-GARCH | Ch8 | regime-conditional Σ |
| 5 (LOW) | MDP / ERC | Ch11 | HRP 외 alternative |

## 적용 시점

- **Phase 4 (즉시)**: Risk-research / Optimizer-research agent prompt에 Ch4/7/8/9/10/11/12 reference 추가
- **Phase 5 (별도 시간)**: PoC R 모듈 3건 (`evt_engine.R`, `robust_opt.R`, `heuristic_opt.R`)
