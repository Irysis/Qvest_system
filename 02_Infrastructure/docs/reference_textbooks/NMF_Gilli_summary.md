# NMF (Numerical Methods and Optimization in Finance, Gilli-Maringer-Schumann) 핵심 챕터 요약

> **Source**: Manfred Gilli, Dietmar Maringer, Enrico Schumann. *Numerical Methods and Optimization in Finance*. Academic Press, 2011 (2nd ed. 2019). 588 pages.
> **License**: Matlab 코드 — 변환 허용 (algorithm reference). 직접 카피 금지.
> **추출 도구**: Hancom OpenDataLoader v2.4.0 (markdown 1.2MB)
> **작성일**: 2026-04-30 (Phase 2, textbook 흡수 plan)

## 책 구조 (3 Part)

- **Part 1**: Numerical analysis (Ch1-5) — linear systems, finite differences, binomial trees
- **Part 2**: Simulation (Ch6-10) — random numbers, dependence (copula), time series, agent-based
- **Part 3**: **Optimization** (Ch11-15) — building blocks, heuristics, **portfolio**, econometrics, option calibration

## Heuristics 알고리즘 (책 인덱스 기준)

| Algo # | 이름 | 챕터 | 분류 |
|---|---|---|---|
| 45 | **Simulated Annealing (SA)** | Ch12 | trajectory |
| 46 | **Threshold Accepting (TA)** | Ch12 | trajectory (deterministic SA 변종) |
| 48 | **Genetic Algorithms (GA)** | Ch12 | population-based |
| 49 | **Differential Evolution (DE)** | Ch12 | population-based |
| 50 | **Particle Swarm Optimization (PSO)** | Ch12 | population-based |
| 55 | TA portfolio application | Ch13 | applied |
| 60 | TA scenario updating | Ch13 | applied |
| 62 | DE for yield curve (Nelson-Siegel) | Ch14 | applied |
| 63 | PSO for robust regression (LMS) | Ch14 | applied |

## Agent 매핑 (우선순위)

| Ch | 주제 | Agent | R 패키지 (또는 직접) | 우선순위 |
|----|------|-------|------|---------|
| 11 | Optimization Building Blocks (Newton, gradient, direct search) | Optimizer (이미) | base R `optim`, `nloptr` | LOW (기본) |
| 12 | **Heuristics (SA/TA/GA/DE/PSO)** | **Optimizer** | `pso`, `GA`, `DEoptim` | **HIGH** ⭐ |
| 13 | Portfolio Heuristics (TA / scenario / drawdown) | **Optimizer** | 직접 구현 (Matlab→R) | **HIGH** ⭐ |
| 14 | Econometric Estimation (GARCH calib, Nelson-Siegel) | Risk (보조) | `rugarch::ugarchfit`, `YieldCurve` | MED |
| 15 | Option Pricing (Heston) | — | (본 시스템 적용 없음) | LOW |

---

## Ch11 Optimization Building Blocks (요약)

**핵심 개념**:
- **Unconstrained 1-D**: golden section search, Brent's method, Newton-Raphson
- **Unconstrained n-D gradient-based**: steepest descent, Newton, quasi-Newton (BFGS), conjugate gradient
- **Unconstrained n-D direct search**: Nelder-Mead simplex, pattern search
- **Sensitivity** (numerical condition): perturbation 영향 평가
- **Zero-finding** (root-finding): Newton, secant, bisection

**R 표준 (직접 reuse)**:
```r
optim(par, fn, method = "BFGS")          # quasi-Newton
optim(par, fn, method = "Nelder-Mead")   # simplex
optim(par, fn, method = "L-BFGS-B")      # box constraints

library(nloptr)
nloptr(x0, eval_f = obj, opts = list(algorithm = "NLOPT_LD_LBFGS"))
```

**우리 시스템 적용**: 이미 `optim()` 사용 중. **추가 필요 없음** (기본 R 표준).

---

## Ch12 Heuristic Methods (in a Nutshell) — **HIGH 우선** ⭐

**핵심 mechanism (5 algorithm)**:

### 1. Simulated Annealing (SA, Algo 45)
- 물리학 metaphor: 결정 cooling
- Solution → neighbor 이동, **probabilistic accept**:
  - Δf < 0 (개선): always accept
  - Δf ≥ 0 (악화): accept with `exp(-Δf / T)`, T (temperature) 점차 감소
- **Cooling schedule** 핵심 — 너무 빠르면 local opt 갇힘

### 2. Threshold Accepting (TA, Algo 46)
- SA의 deterministic version (Dueck-Scheuer 1990)
- accept if Δf < threshold (gradually decrease threshold)
- **No exponential — 더 빠름**, 결정적 수렴

### 3. Genetic Algorithms (GA, Algo 48)
- population of solutions, **selection / crossover / mutation**
- fitness function 기반 자연선택 시뮬레이션
- discrete + continuous 모두 가능

### 4. Differential Evolution (DE, Algo 49)
- Storn-Price (1997)
- continuous 최적화 특화
- mutation: trial = x_r1 + F * (x_r2 - x_r3), crossover with target
- 매우 robust, 적은 hyperparameter (F, CR)

### 5. Particle Swarm Optimization (PSO, Algo 50)
- Kennedy-Eberhart (1995)
- **velocity update**: v_i^{t+1} = ω·v_i^t + c1·r1·(p_i - x_i) + c2·r2·(g - x_i)
- p_i = personal best, g = global best
- inertia ω, cognitive c1, social c2

**R 패키지**:
```r
library(pso)
psoptim(par, fn, lower, upper, control = list(maxit = 1000))

library(GA)
ga(type = "real-valued", fitness = obj, lower, upper, maxiter = 1000)

library(DEoptim)
DEoptim(fn = obj, lower, upper, control = DEoptim.control(itermax = 1000))

# SA via base R
optim(par, fn, method = "SANN", control = list(maxit = 10000))
```

**우리 시스템 적용**:
- 현 Optimizer: HRP / MVO / CVaR LP / Robust resid (4 method). Heuristics 미사용.
- **추가 활용 가능**:
  - PSO / DE로 non-convex objective 최적화 (예: drawdown control with non-linear constraints)
  - GA로 discrete 종목 선택 (top-N selection)
  - SA / TA로 turnover penalty 포함 multi-objective
- **PoC R 모듈**: `02_Infrastructure/portfolio/textbook_methods/heuristic_opt.R` (Phase 5.3)

---

## Ch13 Portfolio Optimization (Heuristic 적용)

**핵심 mechanism**:
- **Heuristic으로 푸는 portfolio 문제**:
  - Min variance (closed-form 가능, but constraints 추가 시 heuristic 유용)
  - Max Sharpe (non-convex when riskless rate variable)
  - **Min Drawdown** — 경로의존, **non-convex** → heuristic 필수
  - **Min CVaR with discrete constraints** — LP 가능 but cardinality / lot size 추가 시 heuristic
- **Cardinality constraint**: portfolio에 포함되는 종목 수 ≤ K — combinatorial
- **Lot size constraint**: 정수 share 필요 — integer programming
- **Turnover penalty**: ‖w - w_prev‖ 최소화 — convex but interaction with other constraints

**Algorithms (책에서 명시)**:
- Algo 55: TA for portfolio selection (cardinality constraint)
- Algo 60: TA scenario updating (rolling)

**R 구현 예 (PSO + cardinality)**:
```r
# Cardinality K, max_w 0.20, long-only, Σw=1
obj <- function(w_full) {
  w <- w_full / sum(w_full)  # normalize
  if (sum(w > 0) > K) return(Inf)  # cardinality penalty
  if (any(w > 0.20)) return(Inf)
  -mean(R %*% w) / sd(R %*% w) * sqrt(12)  # neg Sharpe
}
result <- psoptim(rep(1/N, N), obj, lower = 0, upper = 1)
```

**우리 시스템 적용**:
- WT-D20260430_001은 meta-allocation (2-asset: STR_1715 + cash) — cardinality 의미 없음
- **추후 cross-family blender** 구축 시 (Charter §10 alpha_discovery 다수 후): cardinality 제약 + heuristic
- 현 시점 가치: 중간

---

## Ch14 Econometric Estimation (Calibration)

**핵심 mechanism**:
- **GARCH calibration**: MLE objective 비-convex 영역 존재 — heuristic 필요한 케이스 (예: t-GARCH with leverage)
- **Nelson-Siegel** yield curve: 4-param (β1, β2, β3, λ) — λ가 non-convex
  - Algo 62: DE for Nelson-Siegel
- **Robust regression (LMS)**: Least Median of Squares — non-convex
  - Algo 63: PSO for LMS

**R 함수**:
```r
library(rugarch)
ugarchfit(spec, data)  # MLE — convex 영역 OK

library(YieldCurve)
Nelson.Siegel(rate, maturity)  # OLS-based — non-robust λ

# DE-based Nelson-Siegel
library(DEoptim)
nelsonSiegelDE <- function(theta, rates, maturities) {
  beta1 <- theta[1]; beta2 <- theta[2]; beta3 <- theta[3]; lambda <- theta[4]
  fitted <- beta1 + beta2 * (1 - exp(-maturities/lambda)) / (maturities/lambda) +
            beta3 * ((1 - exp(-maturities/lambda)) / (maturities/lambda) - exp(-maturities/lambda))
  sum((rates - fitted)^2)
}
DEoptim(nelsonSiegelDE, lower, upper, ...)
```

**우리 시스템 적용**:
- KR yield curve 미사용 — **현 시스템 적용 작음**
- GARCH는 FRM Ch8 (rugarch)로 충분
- 가치: **LOW** (현 단계)

---

## Ch15 Option Pricing (Heston) — 적용 외

본 시스템은 long-only equity portfolio. 옵션 미사용. **적용 외**.

---

## 통합 적용 우선순위 (Phase 5 PoC 후보)

| 순위 | 모듈 | 챕터 | 가치 |
|---|---|---|---|
| 1 (HIGH) | PSO heuristic (`heuristic_opt.R`) | Ch12 (Algo 50) | non-convex objective 처리. drawdown control / cardinality 등 |
| 2 (MED) | DE heuristic | Ch12 (Algo 49) | continuous opt 더 robust한 alternative |
| 3 (LOW) | GA / SA / TA | Ch12 (Algo 45/46/48) | discrete combinatorial 시점 |

## 적용 시점

- **Phase 4 (즉시)**: Optimizer-research agent prompt에 Ch12-13 heuristic reference 추가 (PSO/DE/GA 자율 선택 권한)
- **Phase 5 (별도 시간)**: PoC `heuristic_opt.R` (PSO 우선)
- **Phase 5 이후 (조건부)**: cross-family blender 구축 시 cardinality + lot size 제약 도입 시점에 Ch13 본격 활용

## Matlab → R 변환 우선순위

| Matlab 코드 | R 변환 | 변환 비용 |
|---|---|---|
| Algo 50 (PSO) | `pso::psoptim` 또는 직접 구현 | 낮음 (R 패키지 존재) |
| Algo 49 (DE) | `DEoptim::DEoptim` | 낮음 (R 패키지 존재) |
| Algo 48 (GA) | `GA::ga` | 낮음 (R 패키지 존재) |
| Algo 45 (SA) | `optim(method="SANN")` | 낮음 (base R) |
| Algo 46 (TA) | 직접 구현 | 중간 (R package 부재) |
| Algo 55 (TA portfolio) | 직접 구현 | 중간 |
