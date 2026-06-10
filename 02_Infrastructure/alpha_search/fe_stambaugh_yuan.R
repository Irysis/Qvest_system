# =============================================================================
# fe_stambaugh_yuan.R — Stambaugh-Yuan (2017, RFS) Mispricing Factors 완전 복제
# =============================================================================
# "Mispricing Factors" (Stambaugh & Yuan, Review of Financial Studies 2017).
#   11 anomaly → 2 cluster(management / performance) 각 cluster rank-percentile
#   평균 → 2 cluster 평균 = mispricing score. 저-mispricing(저평가) long-only top-N.
#
# ★ 논문 복제 충실 (alpha-search 제1원칙):
#   - 11 anomaly: 원논문 NYSE-listed 11개와 1:1 KR factor DB 매핑(전부 실재, 부족 0).
#   - 2 cluster 구성: 원논문 Table 1 PCA로 management/performance 2 cluster 분류 그대로.
#   - 결합: 각 anomaly를 universe rank-percentile로 변환 → cluster 내 평균 → 2 cluster 평균.
#   - long-only(도훈 제약): 저-mispricing 상위(저평가) long top-N만(short leg 미사용 — 논문은
#     low-minus-high long-short이나 본 검증은 long leg만, 명시 차이).
#   - 유니버스 K200∪KQ150 / 2005~ / top25: run_alpha_search가 처리(universe/start_date/n_holdings).
#
# ★ 부호 처리 (C13 NEGATE/FLIP 금지 준수):
#   _sy_cache.rds의 Z_Score_Aligned는 build_stambaugh_cache가 load_month_factors(IC-direction
#   PIT-safe, Usable_Date<=sig_date)로 "높을수록 기대수익↑"로 이미 정렬. Stambaugh-Yuan의
#   "저-mispricing = 저평가 = 고-기대수익 = long" 와 일치 → 11 Z_Aligned의 2-cluster 평균
#   composite_alpha 가 **높을수록 저-mispricing(=long)**. 수동 부호반전 0. higher Score = buy.
#   (rank-percentile는 cluster 내 동일 스케일 보장용 — Z 자체도 std화돼 있으나 논문은
#    cross-sectional rank percentile 사용하므로 frank로 cluster-내 [0,1] 정규화 후 평균.)
#
# ★ PIT 보증 (detect_lookahead 정적분석 사각 보완 / Cycle 50 교훈):
#   본 engine은 외부 RDS(_sy_cache.rds)를 읽으나, 그 캐시는 build_stambaugh_cache.R이
#   load_month_factors(d) — align_factor_direction PIT-safe(IC Usable_Date<=d, 36m burn-in,
#   C14) — 경유로 생성됨. forward return label을 쓰는 자체 ML 파이프라인이 아니므로
#   forward-label lookahead 없음. 각 sig_date d의 Z는 d 시점 cross-section + d 이하 IC만 사용.
#   재무 lag(C4)는 factor DB 빌더(Factor_Date 가용일)에서 이미 반영. 캐시 부재 시 fail-fast.
#
# 산출: FACTORS(Date, Ticker, Score = composite_alpha). EW/ivol top-N 선택(run_alpha_search).
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
suppressMessages({library(data.table)})

.SY_CACHE <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
                       "stage_artifacts", "alpha_search", "stambaugh", "_sy_cache.rds")
if (!file.exists(.SY_CACHE))
  stop("[fe_stambaugh_yuan] _sy_cache.rds 부재 — 먼저 build_stambaugh_cache.R 실행 필요.")

.SY <- readRDS(.SY_CACHE)
stopifnot(is.data.table(.SY), all(c("Date","Ticker","Factor_Name","Z_Score_Aligned") %in% names(.SY)))

# ---- 2 cluster 정의 (Stambaugh-Yuan 2017 Table 1) -----------------------------
.MGMT <- c("IN04_Net_Equity_Issuance","V21_Composite_Equity_Issuance",
           "AC07_Operating_Accruals","AC05_NOA","GR03_Asset_Growth",
           "IN06_Investment_to_Assets")          # management cluster (6)
.PERF <- c("Q24_Altman_Z","Q25_Ohlson_O","M01_Mom_12_1","Q01_GPA","Q03_ROA")  # performance cluster (5)
.SY[, cluster := fifelse(Factor_Name %in% .MGMT, "mgmt",
                  fifelse(Factor_Name %in% .PERF, "perf", NA_character_))]
.SY <- .SY[!is.na(cluster)]

# ---- 1. anomaly별 cross-sectional rank-percentile (각 Date 내, [0,1], 높을수록 저평가) -
#   논문: 각 anomaly를 universe percentile로 변환(스케일 통일). Z_Score_Aligned는 이미
#   "높을수록 기대수익↑(=저평가)"이므로 frank(+Z)/N → 높을수록 저평가 percentile.
.SY[, pct := (frank(Z_Score_Aligned, ties.method = "average") - 0.5) / .N,
    by = .(Date, Factor_Name)]

# ---- 2. cluster 내 평균 (각 Date·Ticker, 가용 anomaly 평균) --------------------
#   논문: cluster score = 그 cluster anomaly percentile의 평균. NA anomaly는 가용분 평균(부분 정보).
.clu <- .SY[, .(clu_score = mean(pct, na.rm = TRUE), n_anom = .N),
            by = .(Date, Ticker, cluster)]
#   각 cluster 최소 1개 anomaly 가용 행만(둘 다 가용해야 2-cluster 평균 의미 — 논문 정합)
.wide <- dcast(.clu, Date + Ticker ~ cluster, value.var = "clu_score")
.wide <- .wide[is.finite(mgmt) & is.finite(perf)]

# ---- 3. 2 cluster 평균 = mispricing-based composite alpha ----------------------
#   논문: mispricing score = 2 cluster score 평균. 본 percentile은 "높을수록 저평가" 방향이므로
#   평균값 높을수록 저-mispricing(저평가) → long. higher Score = buy (C13 안전, 수동반전 0).
.wide[, Score := (mgmt + perf) / 2]

# ---- 4. 월말 sig_date 한정 + 유동성 통과 종목만 -------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.liq <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE, .(Date, Ticker)]

FACTORS <- merge(.wide[Date %in% .month_ends, .(Date, Ticker, Score)],
                 .liq, by = c("Date", "Ticker"))[is.finite(Score), .(Date, Ticker, Score)]

cat(sprintf("[fe_stambaugh_yuan] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
cat(sprintf("[fe_stambaugh_yuan] clusters: mgmt %d anomaly + perf %d anomaly = 11. Score=저-mispricing(높을수록 long)\n",
            length(.MGMT), length(.PERF)))
