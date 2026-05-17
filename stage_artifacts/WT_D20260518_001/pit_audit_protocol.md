# SEFRS v1.0 — PIT 12-Item Audit Protocol

**Task ID**: WT-D20260518_001
**Phase**: Alpha-Research Phase A Step 4
**Date**: 2026-05-18
**Author**: Alpha Research Agent (autonomous mode)
**Compliance**: PIT C1~C15 strict + 자기합리화 0건 mandate

---

## 0. PIT 핵심 3 질문 (매 audit item)

1. 이 데이터는 의사결정 시점에 알 수 있었는가?
2. 이후 결과가 판단에 영향을 미치지 않는가?
3. "괜찮다"고 느끼는 이유가 결과를 이미 알기 때문은 아닌가?

**금지 표현**: "영향 미미", "관행적 허용", "보수적이면 괜찮다", "대부분 결과 동일", "이미 반영되어 있었을 것", "백테스트 기간이 충분히 길어서 상쇄"

---

## 1. 12-Item Audit Matrix

| ID | Audit item | Method (Forge 단계 실행) | PIT C-code | Hard fail? |
|----|-----------|--------------------------|-----------|------------|
| **P1** | SEIBro publish timing 검증 | t일 데이터 t+1 18:00 KST 보수적 가정 verify | C1, C7 | YES |
| **P2** | NAV timing (t-2 strict) | flow 계산 시 NAV_{t-2} 사용 + audit log | C2 | YES |
| **P3** | Shares reconciliation | Δshares vs creation-redemption disclosure cross-check | C7 | NO (warn) |
| **P4** | Coverage start date | 2017-01-01 (3 ETF active + 3M ramp-up) | C1 | YES |
| **P5** | Missing rate audit | per ETF missing ≤ 2% | C7 | NO (warn) |
| **P6** | Daily reset path-dependence | flow = Δshares × NAV NOT Δprice × shares (가격효과 제거) | C2, C9 | YES |
| **P7** | Corporate action retro-adjust | 액면분할/병합 retro-adjustment + discontinuity scan | C7 | YES |
| **P8** | Notional multiplier check | 2x ETF × 2.0 multiplier 명시 (252670, 122630) | n/a | YES |
| **P9** | Reverse lookahead scan | features → label reverse direction scan | C7 | YES |
| **P10** | Survivorship audit | 상장폐지 ETF 누락 audit (3 ETF는 활성, 보조 사례) | C6 | NO (warn) |
| **P11** | NAV restatement protection | NAV_{t-2} 사용으로 자동 회피 | C11 | NO (design prevents) |
| **P12** | Rolling window strict | rolling z-score 60d window: t-60 ~ t-1 (t inclusive 금지) | C1 | YES |

---

## 2. Item-by-Item Audit Method

### P1 — SEIBro publish timing 검증

**Item**: t일 데이터의 publish_timestamp가 모델 의사결정 시점 이전에 존재했는가?

**Method**:
```r
# Forge 단계 (Q-Lead confirm 후) seibro_etf_flow_collector.R 내
# 각 record에 publish_timestamp 메타 첨부
publish_meta <- list(
  source_publish_kst = "t+1 18:00 보수적",  # SEIBro 일별 disclosure
  earliest_safe_use_kst = "t+2 09:00",       # 다음 영업일 open
  api_response_timestamp = Sys.time()
)
df[, publish_lag_business_days := 1L]  # t → t+1 publish, t+2 사용 가능

# Audit:
for (sd in sig_dates) {
  features_sd <- compute_sefrs(asof = sd)
  for (col in feature_cols) {
    source_dates <- features_sd[[paste0(col, "_source_date")]]
    # all source dates must be ≤ sd - publish_lag_business_days
    assert(max(source_dates) <= sd - 2)  # t-2 strict
  }
}
```

**Hard fail**: 어떤 feature라도 t-1 date data 사용 시 (publish_lag < 2 business days).

### P2 — NAV timing (t-2 strict)

**Item**: flow_i,t = Δshares × NAV_{t-2}에서 NAV가 진정 t-2 publish 데이터인가?

**Method**:
```r
# Schema verification
assert(all(df$nav_source_date == df$Date - 2L))  # business days lag

# Cross-check with SEIBro publish history
# (Forge 단계 실측)
```

**Hard fail**: NAV의 source date != t-2.

### P3 — Shares reconciliation

**Item**: 일별 shares 변화 ≈ 공시된 creation - redemption count

**Method**:
```r
df[, dshares := shares - shift(shares, 1L, type="lag"), by = Ticker]
df[, expected_dshares := creation_unit_count - redemption_unit_count]  # from KRX KIND
df[, reconcile_diff_pct := abs(dshares - expected_dshares) / (abs(dshares) + 1e-6)]
median_diff <- df[, median(reconcile_diff_pct, na.rm=TRUE), by = Ticker]
assert(all(median_diff$V1 <= 0.01))  # 1% tolerance
```

**Soft fail (warn)**: median > 0.01. Log audit + 추가 source 확인 (운용사 contact). Hard fail X.

### P4 — Coverage start date

**Item**: 3 ETF 동시 active 시작일 + 3M ramp-up = sample start

**Method**:
```r
list_dates <- list(
  "252670" = as.Date("2016-09-22"),
  "114800" = as.Date("2009-09-16"),
  "122630" = as.Date("2010-02-22")
)
common_start <- max(unlist(list_dates))  # 2016-09-22 (252670 driven)
sample_start <- common_start + 90  # +3M ramp-up margin = 2016-12-22
# 권장: 2017-01-01 (월말 align 편의)

# Verification:
for (tk in ETF_TICKERS) {
  first_data_date <- min(df[Ticker == tk, Date], na.rm=TRUE)
  assert(first_data_date <= sample_start - 30)  # at least 1M before sample start
}
```

**Hard fail**: 어떤 ETF data가 sample_start 이후 시작.

### P5 — Missing rate audit

**Item**: ETF 별 일별 데이터 missing ≤ 2%

**Method** (이미 data_feasibility_audit_protocol.md §3.2):
```r
for (tk in ETF_TICKERS) {
  sub <- df[Ticker == tk]
  missing_share <- mean(is.na(sub$shares) | sub$shares <= 0)
  missing_nav <- mean(is.na(sub$NAV) | sub$NAV <= 0)
  cat(tk, "missing shares:", missing_share, "missing NAV:", missing_nav, "\n")
  assert(missing_share <= 0.02)
  assert(missing_nav <= 0.02)
}
```

**Soft fail (warn)**: missing > 0.02 ≤ 0.05 → log, sample restriction. > 0.05 → hard reconsider.

### P6 — Daily reset path-dependence 제거

**Item**: leveraged/inverse ETF의 daily reset이 flow 계산에 contaminate되지 않았는가?

**Mechanism explanation**:
- Leveraged 2X ETF: 매일 KOSPI200 선물 노출 = 2x daily return. NAV는 daily compounding 영향 받음.
- 만약 flow를 `flow = Δprice × shares` 또는 `flow = ΔAUM`로 계산하면, **daily reset rebalance**가 flow에 contaminate.
- SEFRS는 `flow = Δshares × NAV` 사용 → shares Δ가 진정 creation/redemption만 capture (price-effect 자동 제거).

**Method**:
```r
# Synthetic test: market jump day check
# 만약 KOSPI200 +5% jump day에 flow가 +5% × AUM 정도 자동 inflate 되면 contamination
market_jump_days <- df_kospi[abs(daily_ret) >= 0.05, Date]
for (jd in market_jump_days) {
  flow_252670_jd <- df[Date == jd & Ticker == "252670", notional_flow]
  # 진정 creation 발생 0일 경우 flow ≈ 0 expected
  # daily reset contamination 발생 시 flow ≈ |2 × 0.05 × AUM| (= 10% AUM 수준 spurious)
}
```

**Hard fail**: market jump day에서 flow spurious correlation r > 0.5.

### P7 — Corporate action retro-adjust

**Item**: 액면분할 / 병합 / 종목코드 변경 시 historical shares retro-adjust

**Method**:
```r
# 시가총액 proxy continuity check
df[, mktcap_proxy := shares * close]
df[, mktcap_jump_pct := abs(mktcap_proxy / shift(mktcap_proxy, 1L) - 1), by = Ticker]
suspicious_days <- df[mktcap_jump_pct > 0.30]  # 1일 30%+ jump

# Cross-check with KRX KIND 공시 (Forge 단계)
# 액면분할 확인 시 historical shares × split_ratio retro-adjust
```

**Hard fail**: corporate action 발견 but retro-adjust 미적용.

### P8 — Notional multiplier 명시

**Item**: 2x ETF에 multiplier 2.0이 정확히 적용되었는가?

**Method**:
```r
# notional_bear_flow_t 계산 audit
df[, notional_check := 
   (2.0) * .SD[Ticker == "252670", flow] + 
   (1.0) * .SD[Ticker == "114800", flow] + 
   (-2.0) * .SD[Ticker == "122630", flow],
   by = Date]

assert(all(notional_check == df$notional_bear_flow))
```

**Hard fail**: multiplier 누락 또는 부호 오류.

### P9 — Reverse lookahead scan

**Item**: features가 label 정보를 우회 참조하지 않는가?

**Method** (역방향 dependency scan):
```r
# pseudo-code: feature dependency graph 분석
feature_deps <- list(
  "ETF_Bear_Imbalance" = c("shares_t-2", "NAV_t-2", "rolling_60d_history"),
  "F2_cum5d" = c("notional_bear_flow_t-1...t-5"),
  # ...
  "I1_x_m4_regime" = c("ETF_Bear_Imbalance_t-1", "m4_regime_t-1")
)

# Audit:
for (feature_name in names(feature_deps)) {
  deps <- feature_deps[[feature_name]]
  for (dep in deps) {
    # dep가 t 또는 t+k (k>=0) 데이터를 참조하면 hard fail
    lag_in_dep <- extract_lag(dep)  # e.g., "shares_t-2" → -2
    assert(lag_in_dep < 0)  # strict negative lag
  }
}

# Empirical reverse scan (Forge 단계):
# - random shuffle label test
# - feature 계산 후 label 의존성 trace
```

**Hard fail**: 어떤 dependency라도 t 또는 future 데이터 참조.

### P10 — Survivorship audit

**Item**: 상장폐지 ETF로 인한 survivorship bias

**Status**: 3 target ETF (252670/114800/122630)은 2026-05 시점 모두 활성. Survivorship bias 영향 적음.

**Method** (보조):
```r
# KRX KIND에서 KOSPI 상장폐지 ETF history 조회 (Forge 단계)
delisted_etfs_2017_2026 <- query_krx_kind_delisted_etfs(
  market = "KOSPI",
  start_date = "2017-01-01",
  end_date = "2026-04-30",
  type = c("leveraged", "inverse")
)

# 유사 인버스/레버리지 ETF 상장폐지 발견 시 log audit
# 3 target은 영향 X but 일반 SEFRS framework extension 시 고려
```

**Soft fail (warn)**: 유사 ETF delisting > 10건 발견 시 — SEFRS framework generalization 시 cautious.

### P11 — NAV restatement protection

**Item**: NAV restatement (정정공시)로 인한 historical NAV 변경 회피

**Status**: NAV_{t-2} 사용 → t-2 publish 시점 NAV로 고정. t+5 정정공시는 영향 X (이미 t-2 시점 데이터로 model 결정 완료).

**Method**:
```r
# NAV restatement frequency check (Forge 단계, 보조)
# SEIBro 정정공시 history 추출
restatement_history <- query_seibro_restatement(
  etfs = ETF_TICKERS,
  start = "2017-01-01",
  end = "2026-04-30"
)

# Frequency log (per ETF / year)
restate_by_year <- restatement_history[, .N, by = .(Ticker, year(Date))]
# Expected: 매우 낮은 빈도 (<5 per year per ETF)
```

**Soft fail (warn)**: ETF 별 연간 restatement > 20건 발견 시 — design prevention 외 추가 robustness check 검토.

### P12 — Rolling window strict

**Item**: rolling z-score 60d window에 t inclusive 절대 금지

**Method** (코드 패턴 강제):
```r
# CORRECT
ETF_Bear_Imbalance_t <- (normalized_imbalance_t - 
                          mean(normalized_imbalance[t-60:t-1])) /
                         sd(normalized_imbalance[t-60:t-1])

# WRONG (t inclusive)
ETF_Bear_Imbalance_t <- (normalized_imbalance_t - 
                          mean(normalized_imbalance[t-59:t])) /  # ← t 포함 금지
                         sd(normalized_imbalance[t-59:t])

# Unit test (Forge 단계):
test_no_lookahead <- function() {
  # 인공 데이터에서 t-1까지만 보이도록 mask
  masked_df <- df
  masked_df[Date >= sig_date, normalized_imbalance := NA]
  
  ebi_masked <- compute_ebi(masked_df, sig_date)
  ebi_full <- compute_ebi(df, sig_date)
  
  # Both should be identical (window is t-60 ~ t-1, sig_date 데이터 사용 X)
  assert(all.equal(ebi_masked, ebi_full))
}
```

**Hard fail**: rolling window 정의에 t inclusive 사용.

---

## 3. Reverse Lookahead Scan (Comprehensive)

### 3.1 Static code audit pattern

Forge 단계 신규 코드 작성 시 자동 scan:

```r
source("02_Infrastructure/validation/lookahead_detector.R")
audit_result <- scan_lookahead(
  code_file = "02_Infrastructure/regime/seibro_regime_features.R",
  patterns = c(
    "shift\\(.*type\\s*=\\s*['\"]lead['\"]\\)",      # forward shift (lead)
    "rollmean\\(.*align\\s*=\\s*['\"]center['\"]\\)",  # center-aligned rolling
    "filter\\(.*Date\\s*>=\\s*sig_date\\)",            # future filter
    "max\\(.*na.rm.*\\).*-.*current"                   # full-sample stat
  )
)
assert(audit_result$violations == 0)
```

### 3.2 Empirical reverse direction scan

```r
# 가설: feature가 label 정보를 leak하면 future return shuffled시 IC가 무너져야 정상.
# 만약 shuffled label에서도 IC > 0.05 발견 → lookahead 의심.

shuffled_ic_test <- function(features, returns, n_sim = 1000) {
  baseline_ic <- cor(features, returns, method = "spearman")
  
  shuffled_ics <- replicate(n_sim, {
    shuffled_ret <- sample(returns)  # break temporal dependency
    cor(features, shuffled_ret, method = "spearman")
  })
  
  # H0: shuffled IC ~ N(0, sigma)
  # H1 (lookahead): shuffled IC distribution shifts away from 0
  p_value <- mean(abs(shuffled_ics) >= abs(baseline_ic))
  assert(p_value < 0.05 || abs(median(shuffled_ics)) < 0.01)
}
```

---

## 4. PIT Audit Output Format

### 4.1 audit log JSON schema

```json
{
  "task_id": "WT-D20260518_001",
  "audit_date": "<Forge 시점 timestamp>",
  "audit_protocol": "SEFRS_v1_pit_audit_12_item",
  "results": [
    {
      "id": "P1",
      "item": "SEIBro publish timing",
      "status": "PASS|WARN|FAIL",
      "method": "<verification method>",
      "result_value": <quantitative>,
      "tolerance": "<threshold>",
      "evidence_path": "<file ref>"
    },
    ...
  ],
  "summary": {
    "total": 12,
    "pass": <int>,
    "warn": <int>,
    "fail": <int>,
    "hard_fail_count": <int>,
    "overall_status": "PASS|WARN|HARD_FAIL"
  }
}
```

### 4.2 Pass criteria

- **12/12 PASS** = G2 admission gate (data_feasibility) PASS
- **Hard fail 1건 이상** = HARD ABORT (RC2 trigger)
- **Warn ≤ 3건 + Hard fail 0건** = PASS_WITH_WARNINGS (Forge proceed allowed)
- **Warn ≥ 4건** = REVIEW (도훈 + Codex review 의무)

---

## 5. Self-rationalization 자동 검사

### 5.1 Forge 단계 코드/log scan

```bash
# audit log + code commits 내 금지 표현 grep
prohibited_phrases=(
  "영향 미미"
  "관행적 허용"
  "보수적이면 괜찮다"
  "대부분 결과 동일"
  "이미 반영되어 있었을 것"
  "백테스트 기간이 충분히 길어서 상쇄"
  "실무적으로 유의미"
  "이 정도면 괜찮다"
)

for phrase in "${prohibited_phrases[@]}"; do
  grep -r "$phrase" \
    "stage_artifacts/WT_D20260518_001/" \
    "02_Infrastructure/data/seibro_etf_flow_collector.R" \
    "02_Infrastructure/regime/seibro_regime_features.R" \
    && exit 1
done
```

**Auto re-review trigger**: hit 1건 → Forge 단계 hard stop + Codex re-review 의무.

---

## 6. C-code mapping summary

| PIT C-code | 본 protocol coverage |
|------------|---------------------|
| C1 (full-sample 금지, rolling only) | P12 (rolling window strict) |
| C2 (same-day circular 금지) | P2 (NAV t-2), P6 (path-dependence) |
| C3 (같은 기간 집계→적용 금지) | P9 (reverse scan) |
| C4 (재무제표 lag) | n/a (재무 데이터 사용 X) |
| C5 (overlay t-1) | P1 (t+1 publish → t+2 사용) |
| C6 (survivorship) | P10 |
| C7 (자동 탐지) | P1, P3, P7, P9 |
| C8 (FM weight same-day 금지) | n/a (FM weight 사용 X) |
| C9 (VT/DD lag) | P6 (path-dependence) |
| C10 (유동성 t-1) | data_feasibility audit |
| C11 (FRED 시차) | P11 (restatement) |
| C13 (NEGATE 금지, Z_Score_Aligned) | n/a (자체 z-score, Factor DB Z_Score 사용 X) |
| C14 (Usable_Date ≤ sig_date) | P1, P2, P12 |
| C15 (Factor DB load_month_factors 경유) | n/a (Factor DB 비사용, ETF data 별도) |

---

## 7. Stage 1 (Forge data feasibility) entry gate

본 PIT audit이 12/12 PASS 시 Stage 2 (event study) 진입 자격.

Mini-Forge protocol (다음 문서 mini_forge_protocol.md) Stage 1 → Stage 2 transition gate = P1~P12 ALL PASS (hard fail 0건) + Warn ≤ 3.

---

## 8. Codex Critic readiness checklist

- [x] 12 audit items 각 정의 + method + hard/soft fail 분류
- [x] PIT C-code mapping (C1~C15 coverage)
- [x] Reverse lookahead scan (static + empirical)
- [x] Self-rationalization 자동 grep
- [x] Output format schema (JSON)
- [x] Pass criteria 정의 (12/12 PASS, hard fail 0)

**Audit complete. Forge cycle 진입 시 첫 작업 = 12-item audit execute.**
