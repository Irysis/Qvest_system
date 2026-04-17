# H_1676 S3 Portfolio-Level ρ 측정 방법 — Scout 사전 설계

**버전**: v2 (2026-04-17, STR_1679v2 Primary 기준점 반영)

## 배경

H_1676 VERDICT conditions_for_s1[7]:
> S3 orthogonality에서 vs STR_1679 portfolio-level rho 실측 + total/market-beta/residual 3분해 보고 + rho 0.2 이상 시 diversifier role 재검토

기존 `compute_factor_orthogonality()` (factor_research_pipeline.R:48) = **factor-level** Spearman 상관. Portfolio-level ρ는 별도 측정.

## Reference Strategy 확정 (v3 업데이트 — Judge Role Misalignment 반영)

**기준점: STR_1679v2 Primary (HRP + DD + Layer 3 overlay) — Grade A conditional**
- sim_result.rds 경로: `04_Research/strategies/STR_1679_score_blend/sim_result.rds`
- performance.json의 `primary_overlay` 섹션 데이터
- SR 1.266, CAGR 24.71%, MDD -29.06%, Sortino 1.82, Calmar 0.85
- **honest_role = core_alpha_with_overlay_dependency** (Judge Full Audit 2026-04-17)
- **ROLE_MISALIGNMENT 확정**: Def sleeve 실질 기여 **0.3pp만** (Def avg weight 10.9% × Def CAGR 2.93%). MDD 축소 22.54pp는 전적으로 **Layer 3 overlay (inverse ETF + cash)** 기여.
- S5 mutation record: `stage_artifacts/s5_mutation_record_STR_1679v2.json`
- Judge L-146: Overlay-driven MDD improvement는 Core alpha로 계상 금지 (role honesty rule)

Base HRP (no overlay) / EW base는 Grade C Hard Fail (baseline 참조용만, S3 기준점 아님).

## Dual Reference Rho 측정 (v3 추가 — Judge 결과 반영)

S3 ρ 측정 시 **2개 기준점 병행**:

1. **vs STR_1679v2 Primary (overlay 포함)**: 실전 포트폴리오 기준 diversification 효과
2. **vs STR_1679v2 Base HRP (overlay 제거)**: 순수 Core alpha 기준 diversification

이 2개 값의 차이 = **overlay 의존성 크기**. H_1676이 overlay-independent diversification 제공하는지 판정.

```r
# Dual reference comparison
# 전제: Forge가 daily_returns.csv export 완료 + Primary/Base 분리 저장
sim_primary <- readRDS("04_Research/strategies/STR_1679_score_blend/output/sim_primary.rds")
sim_base <- readRDS("04_Research/strategies/STR_1679_score_blend/output/sim_base_hrp.rds")

rho_vs_primary <- cor(r_h1676, as.numeric(sim_primary$strategy_xts), method = "pearson")
rho_vs_base <- cor(r_h1676, as.numeric(sim_base$strategy_xts), method = "pearson")

overlay_dependency_gap <- abs(rho_vs_primary - rho_vs_base)

# 해석
# overlay_dependency_gap < 0.10: H_1676 diversification이 overlay 영향 낮음 (good)
# overlay_dependency_gap >= 0.20: H_1676 diversification이 overlay 의존 (경고)
```

**중요 Known Issue**: run_all.R이 3 variant 동시 측정. `sim_result.rds` 저장 시 primary variant daily returns가 저장되었는지 Forge 확인 필요. 현재 run_log에서 tail_risk [WARN] 'daily_returns/NAV 필드 없음' 경고 상태. S3 실행 전 Forge에 sim 객체에 DAILY_NAV_DT 또는 daily NAV 포함 여부 확인 요청 필수.

## Rolling 36M Rho 추가 측정 (v2 추가 — Q-Lead 지시)

정적 전기간 rho 외에 **rolling 36M portfolio-level rho** 필수 측정 (H_1676 Codex R1 conditions 반영):

```r
# Rolling 36M rho (monthly returns, 36-month window)
library(zoo)
# Align monthly returns
r_h_m <- apply.monthly(sim_h1676$strategy_xts, sum)  # approximate monthly
r_1_m <- apply.monthly(sim_1679v2$strategy_xts, sum)
common_m <- intersect(index(r_h_m), index(r_1_m))
r_h_m <- as.numeric(r_h_m[common_m])
r_1_m <- as.numeric(r_1_m[common_m])

rolling_rho <- rollapply(
  data = cbind(r_h_m, r_1_m),
  width = 36,
  FUN = function(x) cor(x[,1], x[,2], method = "pearson"),
  by.column = FALSE,
  align = "right"
)

# Stability check
rolling_rho_sd <- sd(rolling_rho, na.rm = TRUE)
rolling_rho_max <- max(rolling_rho, na.rm = TRUE)
rolling_rho_min <- min(rolling_rho, na.rm = TRUE)
```

### Rolling Rho Stability Gate

```
IF rolling_rho_max < 0.3 AND rolling_rho_sd < 0.15:
  → stable diversifier, strong PASS
ELSE IF rolling_rho_max < 0.4 AND rolling_rho_sd < 0.20:
  → moderate stability, conditional PASS
ELSE:
  → unstable correlation, role 재검토 필요
```

### 해석 주의
- Rolling rho 상승 추세 (최근 기간 증가) → regime shift 위험
- Rolling rho 하락 추세 (최근 감소) → diversifier 강화, 긍정
- H_1676 일간 NAV 기반 측정이 이상적이나 S1 baseline이 monthly rebalance이므로 monthly returns 사용. 일간 NAV 필요 시 Forge에 별도 요청.

## 포트폴리오 레벨 ρ 측정 3분해 방법

### Step 1: 월별 수익률 시계열 확보

```r
# H_1676 S1 완료 시 sim_result.rds 존재
sim_h1676 <- readRDS("04_Research/strategies/STR_1682_H_1676_residual/sim_result.rds")
ret_h1676 <- as.numeric(sim_h1676$strategy_xts)
dates_h1676 <- as.Date(index(sim_h1676$strategy_xts))

# STR_1679v2 Primary (HRP+DD overlay, Grade A 77.1) sim_result.rds
sim_1679 <- readRDS("04_Research/strategies/STR_1679_score_blend/sim_result.rds")
ret_1679 <- as.numeric(sim_1679$strategy_xts)
dates_1679 <- as.Date(index(sim_1679$strategy_xts))

# 공통 기간 맞추기
common <- intersect(dates_h1676, dates_1679)
idx_h <- match(common, dates_h1676)
idx_1 <- match(common, dates_1679)
r_h <- ret_h1676[idx_h]
r_1 <- ret_1679[idx_1]
```

### Step 2: Total ρ (raw 상관)

```r
rho_total <- cor(r_h, r_1, method = "pearson")
# 조건: rho_total < 0.2 → diversifier role 적합
```

### Step 3: Market Beta ρ (CAPM 분해)

```r
# BM_DT에서 시장수익률
bm_ret <- sim_h1676$bm_xts[common]
r_bm <- as.numeric(bm_ret)

# 각 전략의 CAPM beta
lm_h <- lm(r_h ~ r_bm)
lm_1 <- lm(r_1 ~ r_bm)
beta_h <- coef(lm_h)[2]
beta_1 <- coef(lm_1)[2]

# Market-induced 상관
rho_market <- beta_h * beta_1 * var(r_bm) / (sd(r_h) * sd(r_1))
```

### Step 4: Residual ρ (market beta 제거 후)

```r
resid_h <- residuals(lm_h)
resid_1 <- residuals(lm_1)
rho_residual <- cor(resid_h, resid_1, method = "pearson")

# 조건: rho_residual < 0.15 → "true" diversifier (beta 외 독립성)
```

### Step 5: 3분해 검증

```r
# 수학적 검증: rho_total ≈ rho_market + rho_residual
# (approximation; 정확한 식은 공분산 분해)
cov_total <- cov(r_h, r_1)
cov_market <- beta_h * beta_1 * var(r_bm)
cov_residual <- cov(resid_h, resid_1)

stopifnot(abs(cov_total - (cov_market + cov_residual)) < 1e-6)
```

## S3 Gate 판정 로직

```
IF rho_total < 0.2 AND rho_residual < 0.15:
  → diversifier role PASS, PG1 admission 진행
ELSE IF rho_total < 0.3 AND rho_residual < 0.20:
  → conditional PASS, S5 mutation C (market beta 잔차화) 활성화 후 재측정
ELSE:
  → diversifier role FAIL, H_1676 재검토 (core_alpha 또는 폐기)
```

## L-118-ext 대응

L-118-ext: "단면 상관 낮아도 beta 지배로 포트폴리오 상관 0.78". 
- 단면 상관 (factor-level) = compute_factor_orthogonality 결과
- 포트폴리오 상관 (portfolio-level) = 위 Step 2~4
- **두 지표가 다를 수 있음** — 포트폴리오 상관이 결정적

## Scout 실행 플로우 (S3 단계)

1. H_1676 S1 완료 확인 → sim_result.rds 존재
2. STR_1679 D안 백테스트 완료 확인 → sim_result.rds 존재
3. R 스크립트 실행: 위 Step 1~5
4. 결과를 `stage_artifacts/s3_orthogonality_H_1676.json`에 저장:
   ```json
   {
     "hypothesis_id": "H_1676",
     "reference_strategy": "STR_1679_score_blend (D안)",
     "common_period_months": N,
     "rho_total": 0.XX,
     "rho_market_induced": 0.XX,
     "rho_residual": 0.XX,
     "beta_h1676": 0.XX,
     "beta_str1679": 0.XX,
     "variance_decomposition_check": "PASS/FAIL",
     "independence_verdict": "independent/partial/redundant",
     "diversifier_role_fit": "PASS/CONDITIONAL/FAIL",
     "s5_mutation_trigger": "none/market_beta_ortho/role_revisit"
   }
   ```
5. TODO S5 (if conditional) 또는 DONE S3 (if PASS) Forge inbox 라우팅

## Additional Gates (H_1676 VERDICT 반영)

- **COND_03 market_beta_gate**: portfolio |β_h1676| < 0.15 (H_1676 단독). 초과 시 S5 Mutation C 활성화.
- **COND_04 r12_stability**: rolling 3Y 잔차 ICIR drift < 30%. S2 단계 측정, S3에서 재확인.

## 문서 상태

- 작성자: Scout
- 작성일: 2026-04-17
- 용도: H_1676 S1 완료 후 S3 orthogonality 실행 사전 준비
- 실행 조건: sim_result.rds (H_1676 + STR_1679) 모두 존재
