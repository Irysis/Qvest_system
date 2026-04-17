# H_1676 S3 Portfolio-Level ρ 측정 방법 — Scout 사전 설계

## 배경

H_1676 VERDICT conditions_for_s1[7]:
> S3 orthogonality에서 vs STR_1679 portfolio-level rho 실측 + total/market-beta/residual 3분해 보고 + rho 0.2 이상 시 diversifier role 재검토

기존 `compute_factor_orthogonality()` (factor_research_pipeline.R:48) = **factor-level** Spearman 상관. Portfolio-level ρ는 별도 측정.

## 포트폴리오 레벨 ρ 측정 3분해 방법

### Step 1: 월별 수익률 시계열 확보

```r
# H_1676 S1 완료 시 sim_result.rds 존재
sim_h1676 <- readRDS("04_Research/strategies/STR_1682_H_1676_residual/sim_result.rds")
ret_h1676 <- as.numeric(sim_h1676$strategy_xts)
dates_h1676 <- as.Date(index(sim_h1676$strategy_xts))

# STR_1679 (D안 재설계 후) sim_result.rds
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
