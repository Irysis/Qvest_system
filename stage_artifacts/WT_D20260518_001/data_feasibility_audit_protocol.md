# SEFRS v1.0 — Data Feasibility Audit Protocol

**Task ID**: WT-D20260518_001
**Phase**: Alpha-Research Phase A Step 2
**Date**: 2026-05-18
**Author**: Alpha Research Agent (autonomous mode)
**Output type**: Protocol (design-only, 코드 작성 X, Forge 단계 실행 mandate)

---

## 0. Pre-check 결과 (현 인프라 확인)

| 데이터 source | 위치 | ETF 3종 coverage | 일별 발행주식수 |
|--------------|------|-------------------|-----------------|
| `.cache/shares_issued.parquet` | 분기 ISSD 주식만 | ❌ (3556 주식, ETF 부재) | ❌ (분기) |
| `.cache/krx/stk_info/stk_info_*.parquet` | 일별 (`SECUGRP_NM=주권`) | ❌ (주식만) | ❌ (LIST_SHRS는 주식) |
| `.cache/krx/stk_ohlcv/` | 일별 OHLCV | ❌ (주식만) | N/A |
| `.cache/investor_stock/investor_wide.parquet` | 주식별 외/기/개 매매 | ❌ (주식만) | N/A |
| `02_Infrastructure/data/seibro_etf_flow_collector.R` | **미존재 (신규 구축 필요)** | — | — |

**결론**: 현 인프라는 ETF 일별 발행주식수/NAV/AUM/TVA 데이터 부재. **SEIBro / KRX 외부 source 별도 수집 필요**. Fundamental impossible은 아님 (public API 존재).

---

## 1. Primary Data Source — SEIBro 정보데이터시스템

### 1.1 핵심 endpoint

**Portal**: https://seibro.or.kr/
**ETF 메뉴**: 증권정보 → ETF → 종목별 ETF 발행현황 (BIP_CNTS06042V.xml)
**Open API**: https://api.seibro.or.kr/ (회원가입 후)
**Public Data Portal**: https://www.data.go.kr/ (한국예탁결제원 주식정보서비스 = 15001145)

### 1.2 수집 대상 필드 (3 ETF × 일별)

| 필드 | 단위 | source | Schema 가정 |
|------|------|--------|-------------|
| `Date` | YYYY-MM-DD | SEIBro 일별 | KST 영업일 close |
| `Ticker` | 252670/114800/122630 | KRX 종목코드 | 6자리 |
| `발행주식수` | shares | SEIBro 종목별 ETF 발행현황 | 일별 t close 기준 |
| `NAV` | KRW | SEIBro 또는 KRX ETF data | 일별 t close 기준 |
| `종가` (close) | KRW | KRX (이미 보유 가능성) | 일별 t close |
| `AUM` | KRW | 발행주식수 × NAV (derived) | derived |
| `TVA` (거래대금) | KRW | KRX (이미 보유 가능성) | 일별 t close |
| `괴리율` | % | (close − NAV) / NAV | derived |

### 1.3 SEIBro 데이터 publish timing (보수적 가정)

- t일 KOSPI 영업일 close: ~15:30 KST
- t일 발행주식수 / NAV publish: **t+1 18:00 KST 보수적 가정** (SEIBro 일별 disclosure)
- **PIT lag rule**: t일 데이터 사용 시 t+2일 영업일 KST 09:00 부터 사용 가능
- **실제 모델 lag**: forecast horizon = 20D 이므로 t+1 lag로 충분 (강제). monthly rebalance는 사실상 D+~30 gap이므로 안전 margin 충분.

### 1.4 Coverage 추정 (각 ETF 상장일)

| ETF | 상장일 | 가능한 sample start |
|-----|--------|---------------------|
| 252670 (KODEX 200선물인버스2X) | 2016-09-22 | **2017-01 이후 안전** (3M ramp-up 제외) |
| 114800 (KODEX 인버스) | 2009-09-16 | 2010-01 이후 안전 |
| 122630 (KODEX 레버리지) | 2010-02-22 | 2010-06 이후 안전 |

**Common sample start (3종 동시)**: **2017-01-01** ~ 2026-04-30 (sample length ≈ 112 months ≈ 2350 영업일).

**2014-01 ~ 2016-09 (252670 pre-listing)**: 114800 + 122630 2종만 사용한 **degraded SEFRS variant** 별도 계산 가능 (notional_bear_flow_t = 1·flow_114800 - 2·flow_122630).

### 1.5 수집 path 후보 3종

**Path A (preferred): Public Data Portal API**
- `https://www.data.go.kr/data/15001145/openapi.do` (한국예탁결제원 주식정보서비스)
- 무료 + Python `requests` / R `httr` 호출 가능
- 인증키 발급 후 endpoint 호출

**Path B: SEIBro Open API**
- `https://api.seibro.or.kr/` 회원가입 + key 발급
- ETF-specific endpoint detail check 필요 (도훈 confirm 후 Forge 단계)

**Path C (manual fallback): SEIBro web download**
- BIP_CNTS06042V.xml 페이지에서 일별 다운로드
- 2350 영업일 × 3 ETF 수동 수집은 비현실적 — Path A/B 우선

### 1.6 Forge 단계 검증 protocol

```r
# Forge cycle 진입 시 (Q-Lead confirm 후) 신규 구축
# 02_Infrastructure/data/seibro_etf_flow_collector.R

source("02_Infrastructure/config.R")
ETF_TICKERS <- c("252670", "114800", "122630")
DATE_START <- as.Date("2017-01-01")
DATE_END <- as.Date("2026-04-30")

# Path A: Public Data Portal API
collect_seibro_etf <- function(ticker, date_start, date_end) {
  # API key from env or config
  # GET request loop with date pagination
  # Schema normalization to {Date, Ticker, shares, NAV, close, AUM, TVA}
  # Cache to .cache/seibro_etf_flow/{ticker}_{date_start}_{date_end}.parquet
  stop("Implementation deferred to Forge cycle post Q-Lead confirm")
}
```

---

## 2. Secondary Data Source — KRX Data Marketplace

### 2.1 KRX 보완 endpoint

- **Portal**: https://data.krx.co.kr/
- **MKD30040 / 30041**: ETF 일별 시세 (NAV / 종가 / 거래대금)
- **KIND (Korea Investors Network for Disclosure)**: ETF 발행/환매 disclosure

### 2.2 보완 역할

- SEIBro 결측 시 fallback NAV / close / TVA source
- Cross-validation: SEIBro 발행주식수 vs KRX disclosure 일치 여부 확인

---

## 3. Data Quality Audit — 5 Check (Stage 1 entry condition)

### 3.1 Coverage completeness check

```r
expected_business_days <- length(seq(DATE_START, DATE_END, by = "day")) * (5/7) * 0.95  # holidays 5% 제외
actual_days_per_etf <- df[, .N, by = Ticker]
coverage_rate <- actual_days_per_etf$N / expected_business_days
assert(all(coverage_rate >= 0.95))  # G1 admission gate
```

**Tolerance**: coverage ≥ 95% per ETF.

### 3.2 Missing rate check

```r
for (tk in ETF_TICKERS) {
  sub <- df[Ticker == tk]
  missing_share <- mean(is.na(sub$shares) | sub$shares <= 0)
  missing_nav <- mean(is.na(sub$NAV) | sub$NAV <= 0)
  assert(missing_share <= 0.02)  # G2 admission gate
  assert(missing_nav <= 0.02)
}
```

**Tolerance**: missing_rate ≤ 2% per ETF.

### 3.3 Shares reconciliation check (PIT C7)

```r
# 일별 Δshares vs 공시된 creation/redemption count
df[, dshares := shares - shift(shares, 1L, type="lag"), by = Ticker]
df[, expected_dshares := creation_count - redemption_count]  # if available from KRX disclosure
reconcile_diff <- abs(df$dshares - df$expected_dshares) / abs(df$dshares + 1e-6)
assert(median(reconcile_diff, na.rm=TRUE) <= 0.01)  # 1% 미만 reconciliation
```

**Tolerance**: median reconcile diff ≤ 1%.

### 3.4 Corporate action retro-adjustment (PIT C7)

- 액면분할/병합 발생 시 historical shares 모두 retro-adjust
- KRX 종목 history (`Adj_Factor`) 또는 `ISU_CD` 변경 history 확인
- Verification: `shares_t × close_t` (= 시가총액 proxy) discontinuity scan → 1일 |jump| ≥ 30% flag

### 3.5 NAV restatement scan

- T+5 NAV revision retro-adjust check (SEIBro 정정공시)
- 정합 가능성: 보수적으로 NAV_{t} 사용 X, **NAV_{t-1}** 사용 → restatement risk 자동 회피

---

## 4. Update Lag 검증 protocol

### 4.1 정상 flow lag

| 단계 | 데이터 | KST timing | PIT-safe |
|------|--------|-----------|----------|
| t close | KRX 종가 | t 15:30 | ✓ |
| t NAV settle | SEIBro/KRX NAV | t 17:00 | ✓ |
| t shares confirm | SEIBro 발행주식수 | **t+1 18:00** | t+2 사용 mandatory |
| t creation/redemption disclosure | KRX KIND | t+1 19:00 | t+2 사용 mandatory |

### 4.2 Feature lag rule (mandate)

- `flow_i,t-1 = (shares_{t-1} - shares_{t-2}) × NAV_{t-2}` — t-2 lag NAV (보수적 strict)
- 또는 **alternative**: `flow_i,t-1 = (shares_{t-1} - shares_{t-2}) × NAV_{t-1}` — t-1 lag NAV (less strict, NAV는 t-1 close 시점 알 수 있음)
- **Forge 단계 선택**: stricter version (t-2 NAV) 우선 시도. lookahead 의심 0건 확보.

### 4.3 Live 시점 lag 검증

```r
# Bootstrap PIT lag verification
# 매 sig_date에 대해 "그 시점에 알 수 있었던 데이터만 사용했는가?" 검증
for (sd in sig_dates) {
  features_sd <- compute_sefrs(asof = sd)
  # all input data must have publish_timestamp < sd 09:00 KST
  for (col in feature_cols) {
    assert(max(features_sd[[col]]$source_publish_time) < sd_open_time(sd))
  }
}
```

---

## 5. Survivorship audit

### 5.1 상장폐지 ETF 확인 protocol

3 target ETF (252670/114800/122630)은 2026-05 시점 모두 활성 상태 (KOSPI 상장 유지).

그러나 **유사 ETF 상장폐지 history** 확인:
- KOSEF / TIGER / KINDEX 등 다른 운용사 인버스/레버리지 ETF의 historical 상장폐지 사례
- KRX KIND에서 "상장폐지" 또는 "Delisting" 조회
- 본 cycle scope에선 3 ETF 고정이므로 survivorship bias 영향 적음

### 5.2 Pre-listing handling

- 252670 < 2016-09-22: 미존재. notional_bear_flow는 114800 + 122630 2종으로만 계산 (degraded variant 명시)
- 또는 보수적 권장: **sample start = 2017-01-01** (3 ETF 동시 활성 + 3M ramp-up margin)

---

## 6. Cross-source consistency check

### 6.1 SEIBro vs KRX cross-validation

```r
# 동일 일자 / 동일 ETF에 대해 두 source 비교
for (tk in ETF_TICKERS) {
  seibro_sub <- seibro_df[Ticker == tk]
  krx_sub <- krx_df[Ticker == tk]
  merged <- merge(seibro_sub, krx_sub, by = "Date", suffix = c(".sb", ".krx"))
  
  # NAV difference
  nav_diff <- abs(merged$NAV.sb - merged$NAV.krx) / merged$NAV.krx
  median_nav_diff <- median(nav_diff, na.rm=TRUE)
  assert(median_nav_diff <= 0.001)  # 10bps tolerance
  
  # Shares difference
  share_diff <- abs(merged$shares.sb - merged$shares.krx) / merged$shares.krx
  median_share_diff <- median(share_diff, na.rm=TRUE)
  assert(median_share_diff <= 0.001)
}
```

**Tolerance**: median cross-source diff ≤ 0.1% (NAV) / 0.1% (shares).

### 6.2 Inconsistency handling

Cross-source diff > 1% 발생 시:
- (a) SEIBro 우선 (official depositary)
- (b) KRX 확인 (settlement-based)
- (c) 운용사 (KODEX/Samsung Asset Management) 직접 contact (Forge 단계)
- Discrepancy log → audit trail

---

## 7. Failure Modes + Mitigation

| 실패 mode | Mitigation | Hard fail? |
|----------|-----------|------------|
| SEIBro API 인증 거부 | KRX Public Data Portal 우회 | NO (alt source) |
| Path A/B/C 모두 fail | manual export + retry | YES if 3 path 모두 fail |
| Coverage < 95% | 3M 추가 ramp-up 제외 후 재검토 | NO (sample restriction) |
| Cross-source diff > 1% | SEIBro 우선 + audit log | NO (preferred source) |
| Corporate action discontinuity | KRX KIND 공시 확인 + retro-adjust | NO |
| **NAV restatement past 5 days** | t-1 NAV 사용으로 자동 회피 | **NO** (design prevents) |
| **2016-09 이전 252670 부재** | 2017-01 sample start | NO (margin sufficient) |

---

## 8. Feasibility Verdict

### 8.1 Pre-Forge 결정 matrix

| 조건 | 결과 |
|------|------|
| Public API 존재 | ✅ (SEIBro + KRX 둘 다) |
| 일별 granularity | ✅ |
| 3 ETF 모두 cover | ✅ (2017-01 이후) |
| PIT-safe lag rule 설계 가능 | ✅ (t-1 NAV strict) |
| 현 인프라 fault | ❌ 신규 collector 구축 필요 (`02_Infrastructure/data/seibro_etf_flow_collector.R`) |

### 8.2 결론

**PROCEED_WITH_DATA_ACQUISITION_PROTOCOL** — Forge cycle 진입 시 Path A (Public Data Portal API) 우선 + Path B fallback + Path C manual emergency only.

**Q-Lead confirm 필수**: Forge cycle 시작 전 (a) API 인증 발급 + (b) collector script 신규 구축 (≈ 8~12h estimated) + (c) initial sample 수집 (≈ 2~4h) — 도훈 명시 confirm 후 진행.

### 8.3 Time + cost estimate (Forge 단계)

- API key 발급: 0.5h (data.go.kr 신청)
- Collector R/Python script 작성: 6~8h (API call loop + schema normalize + cache write + audit)
- Initial 9년 sample 수집: 2~4h (rate-limit 고려)
- Audit + cross-source verification: 2h
- **Total ~10~14h estimated** (Forge 진입 전 Q-Lead confirm 의무)

---

## 9. Codex Critic readiness checklist

- [x] Pre-check 결과 (현 인프라 부재) 명시
- [x] 외부 source 3-path (Public Data Portal / SEIBro Open API / KRX) 명시
- [x] PIT lag rule (t-1 NAV strict + t-2 NAV stricter alternative) 명시
- [x] 5 data quality check (coverage / missing / reconcile / corporate action / NAV restatement) 명시
- [x] Survivorship audit (delisted ETF + pre-listing handling) 명시
- [x] Cross-source consistency (SEIBro vs KRX) 명시
- [x] Failure modes (7건) + mitigation 명시
- [x] Feasibility verdict (PROCEED + Q-Lead confirm 의무) 명시
- [x] Time + cost estimate (10~14h) 명시

**Audit complete. Forge cycle ready post Q-Lead confirm.**
