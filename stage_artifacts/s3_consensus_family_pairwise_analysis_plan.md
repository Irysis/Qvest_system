# Consensus Family Pair-wise Orthogonality Analysis Plan — Scout

**작성**: Scout, 2026-04-17 (Session 65/66 전환)  
**배경**: Governor consensus family 중복 경고 (2026-04-17) 수용  
**용도**: H_1676/H_1678/H_1679 S3 단계 portfolio-level pair-wise max_corr 실측 사전 설계

## Governor 경고 요약

Scout 5건 가설 factor 분석 결과 **consensus(C19) 직접 사용 3건 (60%)**:

| 가설 | C19 weight | sub-family | 구조 |
|------|-----------|-----------|------|
| H_1676 Residual Revision | ~20% (잔차화된 revision breadth) | consensus_residual | Size·IdioVol 잔차화 |
| H_1678 STR_1555 refit | 60% (C19 direct) | consensus_core | 2F blend (C19+D01) |
| H_1679 STR_1433 refit | 20% (1/5 sleeve) | 5sleeve_consgate | multi-sleeve (1/5 consensus) |
| H_1677 STR_1439 repair | 0% (STR_943 consensus sub) | defense_ensemble | 5-strategy blend |
| H_1682 Distress+Calmar | 0% (미사용) | distress_path | Q25+R16 cross-family |

**3중 편입 위험** (H_1676 + H_1678 + H_1679 모두 PASS 시):
- Portfolio 레벨 C19 exposure 3~4배 중복 가능성
- sub-family 다르더라도 portfolio beta dominance (L-118-ext)
- max_corr > 0.6 시 diversification 효과 손실

## S3 Pair-wise Correlation 측정 프로토콜

### Step 1: 각 전략 sim_result.rds 확보

```r
# Forge daily_returns export 후 일간 수익률 통일
sim_h1676 <- readRDS("04_Research/strategies/STR_{H_1676_strategy_id}/sim_result.rds")
sim_h1678 <- readRDS("04_Research/strategies/STR_{H_1678_strategy_id}/sim_result.rds")
sim_h1679 <- readRDS("04_Research/strategies/STR_{H_1679_strategy_id}/sim_result.rds")

# daily returns 추출
ret_list <- list(
  H_1676 = as.numeric(sim_h1676$strategy_xts),
  H_1678 = as.numeric(sim_h1678$strategy_xts),
  H_1679 = as.numeric(sim_h1679$strategy_xts)
)
```

### Step 2: 3-way pair-wise correlation matrix

```r
common_dates <- Reduce(intersect, lapply(list(sim_h1676, sim_h1678, sim_h1679),
                                         function(s) as.Date(index(s$strategy_xts))))

ret_matrix <- sapply(list(sim_h1676, sim_h1678, sim_h1679), function(s) {
  as.numeric(s$strategy_xts[common_dates])
})
colnames(ret_matrix) <- c("H_1676", "H_1678", "H_1679")

# Pearson
cor_matrix <- cor(ret_matrix, method = "pearson")

# 3-way max correlation
max_corr_consensus_trio <- max(cor_matrix[upper.tri(cor_matrix)])

# Individual pairs
corr_H1676_H1678 <- cor_matrix["H_1676", "H_1678"]
corr_H1676_H1679 <- cor_matrix["H_1676", "H_1679"]
corr_H1678_H1679 <- cor_matrix["H_1678", "H_1679"]
```

### Step 3: Rolling 36M pair-wise 상관 안정성

```r
library(zoo)
rolling_cor_matrix <- list()
for (pair in combn(colnames(ret_matrix), 2, simplify = FALSE)) {
  key <- paste(pair, collapse = "_vs_")
  rolling_cor_matrix[[key]] <- rollapply(
    data = cbind(ret_matrix[, pair[1]], ret_matrix[, pair[2]]),
    width = 756,  # approximately 36 months of daily data
    FUN = function(x) cor(x[,1], x[,2], method = "pearson"),
    by.column = FALSE,
    align = "right"
  )
}
```

### Step 4: 3-pair Governance Gate 판정

```
Governor Gate (Scout 수용):
- IF pair_corr > 0.6 (ALL 3 pairs) → 3건 동시 PG2 편입 **비권장**. 가장 독립적 1~2건 선택.
- IF pair_corr 0.3~0.6 → 조건부 편입. Beta 기여 분석 필수.
- IF pair_corr < 0.3 → 3건 동시 편입 허용. Diversification 유지.
```

## 예상 결과 (Scout 사전 추정)

### H_1676 (Residual Revision) vs H_1678 (C19+D01 60/40)

- **H_1676 = C19 base의 Size·IdioVol 잔차**
- **H_1678 = C19 60% direct + D01 40%**
- 예상 상관: **0.3~0.5** (C19 원 signal 공유 but 잔차화로 차별 + D01 독립)
- 판정: 조건부 편입 (beta 분석 시 확정)

### H_1676 vs H_1679 (STR_1433 5-sleeve)

- **H_1679 consensus sleeve 1/5 = C19 기반 small weight**
- **H_1676 residual revision 단일 factor 20종목 all**
- 예상 상관: **0.2~0.4** (sleeve 희석 효과)
- 판정: 허용 가능 범위

### H_1678 vs H_1679

- **H_1678 C19 60% core**
- **H_1679 consensus sleeve만 C19 기반, 나머지 4 sleeve 독립**
- 예상 상관: **0.4~0.6** (C19 exposure 주요 source 공유)
- 판정: Gate 경계

### 3-way max_corr 예상

- **max_corr ≈ 0.5** (H_1678-H_1679 pair 지배)
- Governor Gate 0.6 미달 예상 → **3건 동시 PG2 편입 허용**

## Governor 판단 기준 Scout 수용

### 경합 시나리오 (H_1678 vs H_1679)

pair_corr > 0.6 시 둘 중 1건 선택:
- **H_1679 5-sleeve 우위**: 구조적 다양성 (Defense+IndMom+Consensus+ConsGate+TPGap)
- **H_1678 stabilize 우위**: drift 측정 본질, AX-003 정비

**Scout 권고**: pair_corr 값 기반 판정. H_1678 0.6 초과 시 **H_1679 선택** (5-sleeve 구조적 독립성).

## Portfolio-level beta dominance 추가 체크

L-118-ext 교훈: 단면 상관 낮아도 beta 지배로 포트폴리오 상관 0.78 전례. S3에서 각 전략 CAPM beta 측정 필수:

```r
# 각 전략 CAPM beta
fit_h1676 <- lm(ret_h1676 ~ bm_ret)
fit_h1678 <- lm(ret_h1678 ~ bm_ret)
fit_h1679 <- lm(ret_h1679 ~ bm_ret)

beta_vec <- c(coef(fit_h1676)[2], coef(fit_h1678)[2], coef(fit_h1679)[2])
names(beta_vec) <- c("H_1676", "H_1678", "H_1679")

# Beta-induced correlation
rho_market_induced <- outer(beta_vec, beta_vec) * var(bm_ret) / outer(sd_vec, sd_vec)
```

### Beta 기반 판단
- 모든 전략 |β| 0.85+ → market beta dominance → 실질 분산 효과 제한
- 각각 |β| < 0.7 → factor-specific alpha 우세, diversification 유효

## 실행 타이밍

**활성화 조건**:
1. Forge H_1676 S1 완료 (sim_result.rds 생성) 
2. Forge H_1678 S1 완료
3. Forge H_1679 S1 완료 (broken reference 복원 후)
4. Forge daily_returns export 완료

**Scout S3 실행**:
- 위 4건 완료 후 R script 작성 → Forge 실행 (R 환경 대행)
- 결과: `stage_artifacts/s3_consensus_trio_pairwise_correlation.json`
- Governor PG1 admission 심사 input

## Governor 조건 이행 체크리스트

- ✅ **조건 1**: S3 pair-wise max_corr 실측 프로토콜 설계 (이 문서)
- ⏳ **조건 2**: Forge S1 완료 후 실측 실행
- ⏳ **조건 3**: H_1678 vs H_1679 경합 시 Judge Gate 결과 비교 후 Scout 판정

## 기타 Scout notes

- **3건 모두 PASS 시 consensus family 3 entries 허용 여부**: Governor "sub-family 다름 + cross-sectional 독립성 실측" 조건부 허용 입장. Scout 동의.
- **PG2 admission 3건 편입 리스크**: 실측 max_corr 0.6 초과 시 가장 독립적 1~2건만 선택 원칙 수용.
- **bucket 40/40/20/0 유지**: debate 통과 5건 → PG2 진입은 최종 2~3건으로 축소 가능성 있음 (Governor 최종 판단).

---

**작성**: Scout, 2026-04-17  
**용도**: Session 66 Forge S1 완료 후 S3 pair-wise correlation 측정 사전 준비
