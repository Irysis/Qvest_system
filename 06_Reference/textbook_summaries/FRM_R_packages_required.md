# FRM Pfaff R packages 필요 리스트

> Phase 5 PoC 진행 시 설치 필요한 R packages. 일부는 이미 시스템에 설치됨.

## 핵심 패키지 (Phase 5 PoC 시 필수)

| 패키지 | 용도 | 챕터 | 설치 명령 | CRAN URL |
|---|---|---|---|---|
| `PerformanceAnalytics` | VaR / ES / Sharpe / Sortino / maxDrawdown | Ch4 | `install.packages("PerformanceAnalytics")` | https://cran.r-project.org/package=PerformanceAnalytics |
| **`fExtremes`** | EVT (GPD / GEV / Hill / risk measures) | Ch7 | `install.packages("fExtremes")` | https://cran.r-project.org/package=fExtremes |
| `evd` | Extreme value distributions | Ch7 (alt) | `install.packages("evd")` | https://cran.r-project.org/package=evd |
| `evir` | EVT in R (alternative) | Ch7 (alt) | `install.packages("evir")` | https://cran.r-project.org/package=evir |
| **`rugarch`** | GARCH / EGARCH / GJR / DCC | Ch8 | `install.packages("rugarch")` | https://cran.r-project.org/package=rugarch |
| `fGarch` | GARCH (alternative) | Ch8 (alt) | `install.packages("fGarch")` | https://cran.r-project.org/package=fGarch |
| **`copula`** | Copula families (Gaussian/t/Clayton/Gumbel/Frank) | Ch9 | `install.packages("copula")` | https://cran.r-project.org/package=copula |
| `fCopulae` | Copula (alternative) | Ch9 (alt) | `install.packages("fCopulae")` | https://cran.r-project.org/package=fCopulae |
| **`fPortfolio`** | Portfolio optimization (MV / CVaR / MD / Robust) | Ch10-12 | `install.packages("fPortfolio")` | https://cran.r-project.org/package=fPortfolio |
| `MASS` | Robust covariance (MCD / MVE) | Ch10 | (base R install) | — |
| `robustbase` | More robust statistics | Ch10 | `install.packages("robustbase")` | https://cran.r-project.org/package=robustbase |
| `corpcor` | Shrinkage covariance | Ch10 | `install.packages("corpcor")` | https://cran.r-project.org/package=corpcor |
| **`Rsolnp`** | Non-linear constraint optimization | Ch12 | `install.packages("Rsolnp")` | https://cran.r-project.org/package=Rsolnp |
| **`Rglpk`** | Linear programming (Min CVaR LP) | Ch12 | `install.packages("Rglpk")` | https://cran.r-project.org/package=Rglpk |
| `nloptr` | Non-linear optimization (alternative) | Ch12 (alt) | `install.packages("nloptr")` | https://cran.r-project.org/package=nloptr |
| `BLCOP` | Black-Litterman | Ch13 | `install.packages("BLCOP")` | https://cran.r-project.org/package=BLCOP |

## 일괄 설치 스크립트

```r
# Phase 5 PoC 진행 시 한 번에 설치
required_packages <- c(
  "PerformanceAnalytics",
  "fExtremes", "evd", "evir",
  "rugarch", "fGarch",
  "copula", "fCopulae",
  "fPortfolio",
  "MASS", "robustbase", "corpcor",
  "Rsolnp", "Rglpk", "nloptr",
  "BLCOP"
)

missing <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing) > 0L) {
  install.packages(missing, dependencies = TRUE)
}

# 검증
sapply(required_packages, requireNamespace, quietly = TRUE)
```

## 시스템 설치 의존성 (apt / OS-level)

`Rglpk` 사용 시 GLPK system library 필요:
```bash
sudo apt install libglpk-dev
# WSL에서 sudo 막힐 시 — Phase 5 시점에 도훈 승인 필요
```

`rugarch` 일부 의존성:
```bash
sudo apt install libgsl-dev  # GSL for some compilation
```

## Phase 5 PoC 우선 검증 패키지 (선설치)

| 모듈 | 우선 패키지 |
|---|---|
| EVT engine | `fExtremes`, `evir` |
| Robust opt | `MASS`, `robustbase`, `corpcor`, `fPortfolio` |
| Heuristic opt | `pso` (NMF Ch12) — Pfaff 외 |
