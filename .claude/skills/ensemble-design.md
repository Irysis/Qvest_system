---
name: ensemble-design
description: Blender agent용 앙상블 설계 가이드. 독립 alpha 4+ 확보 후 국면 조건부 배분 매트릭스 + LOO 검증. EW → RP → HRP → CVaR LP 순서.
---

# Ensemble Design Skill

## 적용 시점

- Governor가 PG2_allocation_plan 완료한 직후
- 또는 Q-Lead가 "Grade A 4건+ 확보, 앙상블 설계 검토 요청" 시
- Blender agent 전용 (일반 에이전트는 사용 금지)

## 단계별 절차

### 1. 상관 분석
```r
returns_mat <- cbind(str_a$Ret, str_b$Ret, str_c$Ret, str_d$Ret)
corr <- cor(returns_mat, use = "pairwise.complete.obs")
# 0.5+ 2쌍 이상 → 다양성 부족, 재선정
```

### 2. 국면 라벨링
- regime_v7 또는 conditional_ic_matrix_4regime 활용
- NORMAL / CAUTION / CRISIS / RECOVERY 4분면

### 3. 배분 방법 (단순→복잡)
1. **EW** (baseline) — 1/N
2. **RP** (risk parity) — 1/vol 정규화
3. **HRP** — hierarchical risk parity (Lopez de Prado 2016). Gerber correlation + RMT denoise 권장
4. **CVaR LP** — PG2 CDaR LP와 구분. 국면별 CVaR 최소화

### 4. LOO 검증
```r
for (i in seq_along(candidates)) {
  loo_portfolio <- combine(candidates[-i])  # i번째 제외
  measure_impact(base_portfolio, loo_portfolio)
}
```

- 각 전략 제외 시 SR 변화 ≥ 0.1이면 "essential", < 0.05면 "redundant"

### 5. 최종 추천
- 각 방법의 IS/OOS SR, MDD, Sortino 비교
- "단순 방법이 비슷하면 단순 선택" (Occam's razor)

## 제약 (엄수)

- **Grade A 미만 포함 금지** (CLAUDE.md)
- **종목수 30 제약**: score-level blend만 허용 (return blend는 L-484 위반)
- **PIT 필수**: 각 후보 전략의 s6_validation.pit_audit.clean 확인
- 상관 0.5+ 2쌍 이상 → 자동 reject

## 참고 문헌

- Lopez de Prado (2016): "Building Diversified Portfolios that Outperform Out-of-Sample"
- Gerber et al. (2022): "Gerber Statistic" (대안 상관)
- Maillard et al. (2010): "Risk Parity"
- Rockafellar & Uryasev (2000): "Optimization of Conditional Value-at-Risk"
