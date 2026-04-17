---
name: defense-evaluation
description: "Defense Sleeve 전용 평가 — 조건부 성과, 8대 스트레스 구간, beta/IC/상관 기준"
---
## Defense Sleeve 평가 규칙

### 평가 원칙 (L-112)
- **전기간 SR/CAGR이 아닌 조건부 성과로 평가**
- 위기 시 기능 여부가 핵심. 전기간 SR 0.5라도 스트레스 5/8 승리면 우수
- 포트폴리오 레벨 MDD 기여가 궁극 평가 기준

### Defense Grade 기준 (hurdle_gate.R 연동)
| Grade | 조건 |
|-------|------|
| **A_DEF** | stress_outperform >= 5/8 AND bad_ic_ratio >= 1.5 AND beta < 0.85 AND mdd < 40% |
| **B_DEF** | stress_outperform >= 3/8 AND bad_ic_ratio >= 1.2 AND beta < 0.90 |
| **F** | stress < 2/8 또는 beta >= 0.95 |

### 8대 스트레스 구간
1. 9/11 Terror (2001-09 ~ 2001-12)
2. GFC (2007-10 ~ 2009-03)
3. Euro Debt (2011-07 ~ 2011-12)
4. China Shock (2015-06 ~ 2016-02)
5. US-China Trade War (2018-03 ~ 2018-12)
6. COVID (2020-01 ~ 2020-06)
7. Rate Hike (2022-01 ~ 2022-12)
8. Iran War (2026-02 ~ 2026-04)

### 필수 평가 항목 (S1/S2에서 측정)
1. **bad_ic_ratio** = ic_bad / ic_normal (>= 1.5 우수, >= 1.2 수용)
2. **stress_outperform_rate** (8구간 중 BM 상회 횟수)
3. **market_beta** (CAPM 회귀, < 0.85 필수)
4. **core_correlation** (C19/Core Alpha 대비, < 0.5 필수)
5. **portfolio_mdd_contribution** (Core Alpha 합산 시 MDD 감소폭)
6. **copula_crisis_cor** (Copula TDC, Pfaff Ch.9) — `compute_copula_tdc()`
7. **garch_conditional_es** (조건부 ES, Pfaff Ch.8) — `forecast_conditional_es()`

### S4 Defense 분기
- `sg_determine_role()`에서 `provisional_role == "defense"` 결정
- pipeline_trigger.sh가 defense 전용 경로로 라우팅
- defense는 S5 overlay 전에 S6 Judge로 직행 가능 (base alpha가 defense 평가에 더 적합)

### Forge S1 코드 필수 포함
```r
# Defense 전용 분석 블록
beta <- coef(lm(as.numeric(sim$strategy_xts) ~ as.numeric(sim$bm_xts)))[2]
cat(sprintf("  Beta: %.3f %s\n", beta, if(beta < 0.85) "PASS" else "FAIL"))

# 8대 스트레스 구간 alpha
stress_periods <- list(
  list(label="9/11", start="2001-09-01", end="2001-12-31"),
  list(label="GFC", start="2007-10-01", end="2009-03-31"),
  list(label="EuDebt", start="2011-07-01", end="2011-12-31"),
  list(label="ChinaShock", start="2015-06-01", end="2016-02-29"),
  list(label="TradeWar", start="2018-03-01", end="2018-12-31"),
  list(label="COVID", start="2020-01-01", end="2020-06-30"),
  list(label="RateHike", start="2022-01-01", end="2022-12-31"),
  list(label="IranWar", start="2026-02-01", end="2026-04-30")
)
```

### 텔레그램 (10번 템플릿)
defense 결과는 반드시 🛡️ 이모지 + stress 구간별 ✅❌ + beta/IC ratio 포함.
