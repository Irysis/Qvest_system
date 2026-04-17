---
name: s3-orthogonality
description: "S3 직교성 분석 시 적용 — 3레이어, novelty_score, independence_class"
---
## S3 직교성 분석

### 3레이어 분석
1. **전체 DB**: 288 팩터 대비 수익률 상관
2. **Active Pool**: Grade A 전략 대비 보유 종목 상관
3. **Research Fatigue**: 같은 family 최근 실패 횟수

### independence_class
| max_corr | 분류 |
|----------|------|
| < 0.3 | **independent** |
| 0.3~0.5 | **partial** |
| > 0.5 | **redundant** |

### Copula TDC + DCC-GARCH 동적 상관 (신규 — Pfaff Ch.9/Ch.8)
선형 상관 외에 **꼬리 의존성**과 **시변 상관**을 반드시 분석:
```r
source(file.path(INFRA_DIR, "regime/regime_garch.R"))
# 1. Copula TDC (위기 시 공동 폭락 측정)
tdc <- compute_copula_tdc(ret_anchor, ret_candidate)
# tdc$tdc_lower > 0.30이면 diversifier 실효성 의심

# 2. DCC-GARCH 동적 상관 (시변 프로파일)
dcc <- fit_dcc_garch(cbind(ret_anchor, ret_candidate))
# 위기 시 상관 급등 여부 확인
```

**Diversifier 이중 게이트 (PG1 연동):**
- 선형 cor < 0.30 AND Copula TDC < 0.30 → independent
- 둘 중 하나라도 > 0.30 → partial 또는 redundant

### s3_orthogonality artifact
`novelty_score`, `candidate_role_hint`, `independence_class`, `max_corr_strategy`, `max_corr_value`, `copula_tdc`, `dcc_crisis_cor`

### Novelty Bonus (hurdle v2.2)
- max_corr < 0.3 + new family → +15
- max_corr < 0.3 + existing → +10
- max_corr 0.3~0.5 → +5~8
