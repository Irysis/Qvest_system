# =============================================================================
# fe_rf_b1_4_momrevision.R — 규칙기반 고속강화 B1-4 (도훈 프로그램 2026-08-29)
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast attempt n=4
# 규칙 (설계 재량 0 — B1-1 엔진 규약 미러, 가치 축만 이익수정 브레드스로 교체):
#   신호   = 모멘텀(12-1) rank-Z + 이익수정 브레드스(3개월) rank-Z 의 50/50 합산
#            (매월 리밸일 횡단면 rank → z 변환 후 평균).
#   모멘텀 = 12-1: 월말 시그널 시점 m 에서 C(m-1)/C(m-12) - 1 (직전 1개월 스킵).
#            근거 Jegadeesh & Titman (1993), JF 48(1):65-91
#            https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#   이익수정 = factor DB `C13_Revision_Breadth_3m` (smoothed ESBR — 최근 3개
#            분기 릴리스 평균, FQ-218 런 기반 창). 근거 Chan, Jegadeesh &
#            Lakonishok (1996), Momentum Strategies, JF 51(5):1681-1713
#            https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.1996.tb05222.x
#            load_month_factors() 경유 소비 (C15) — Z_Score_Aligned
#            (C13룰: NEGATE/FLIP 금지, C14: Usable_Date<=sig_date).
#   ★C01_SUE 단독 사용 금지 (1/20 정적 검증기 FAIL_LOOKAHEAD 전례 — 컨센서스
#            33종 공통 same-day 이슈). C13 도 같은 컨센서스 계열이므로
#            Usable_Date 준수를 별도 감사 스크립트로 명시 검증
#            (audit_c14_esbr_usable_date.R — esbr 릴리스(런 시작일)가 월말
#            시그널일과 동일한 건수 실측).
#   ★컨센서스 결측 종목 = 컴포짓에서 제외 (모멘텀 z 단독 폴백 금지 — 규칙).
#   유니버스 = K200∪KQ150 (PIT 시변 멤버십) + 유동성 20일 평균 거래대금 >= 2e8
#            (★t-1: frollmean 후 shift(1) — C10).
#   포트폴리오 = 러너 portfolio_spec (top_n_long n=25, EW, 월간) — 엔진은 Score 만.
#
# ===== PIT (C1~C15) 자가점검 =====
#   C1  : rank-Z 는 시그널월 횡단면만 사용 (full-sample 통계 없음)
#   C2  : Mom = C(m-1)/C(m-12) — 시그널일(월말 m) 이전 종가만, 순환참조 없음
#   C4  : 컨센서스 릴리스 = 벤더 공표일 기준 런 경계 (compute_consensus FQ-218,
#         Date <= sig_d 재절단) — 재무제표 lag 는 factor DB 빌드가 반영
#   C10 : 유동성 필터 = 20일 평균 거래대금의 t-1 값 (shift 1)
#   C13 : Z_Score_Aligned 그대로 (부호 조작 없음). rank = 단조변환
#   C14 : load_month_factors(sig_date) 방향정렬 IC = Usable_Date <= sig_date 강제
#         + esbr 릴리스일 vs 시그널일 동일일 건수 별도 실측 (감사 스크립트)
#   C15 : parquet 직접 load 없음 — load_month_factors() 경유
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                               "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

.REV_FACTOR <- "C13_Revision_Breadth_3m"   # 이익수정 축 = 3개월 수정 브레드스 (CJL1996)

# ---- 월말(시그널) 그리드 (전 시장 공통) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.gen_from <- as.Date("2004-01-01")   # 러너가 2005-01-01 로 절단 — 여유 생성
.sig_dates <- .month_ends[.month_ends >= .gen_from]

# ---- 유동성: 20일 평균 거래대금 >= 2e8, ★t-1 (C10) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20_L1 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
.mem <- RAWDATA[Date %in% .sig_dates & (K200 == TRUE | KQ150 == TRUE) &
                  is.finite(.AvgTV20_L1) & .AvgTV20_L1 >= 2e8,
                .(Date, Ticker)]
setkey(.mem, Date, Ticker)

# ---- 모멘텀 12-1: 종목별 월말 종가 패널 → C(m-1)/C(m-12) - 1 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.mc <- RAWDATA[, .SD[which.max(Date)], by = .(Ticker, .ym), .SDcols = c("Date", "Close")]
RAWDATA[, c(".ym", ".TV", ".AvgTV20_L1") := NULL]
.mc[, ymi := as.integer(substr(.ym, 1, 4)) * 12L + as.integer(substr(.ym, 6, 7))]
.m1  <- .mc[, .(Ticker, ymi = ymi + 1L,  C1  = Close)]   # m 시점에서 보는 m-1 월말 종가
.m12 <- .mc[, .(Ticker, ymi = ymi + 12L, C12 = Close)]   # m 시점에서 보는 m-12 월말 종가
.mom <- merge(.m1, .m12, by = c("Ticker", "ymi"))
.mom <- .mom[is.finite(C1) & is.finite(C12) & C12 > 0, .(Ticker, ymi, Mom = C1 / C12 - 1)]
.sig_ymi <- data.table(Date = .sig_dates,
                       ymi = as.integer(format(.sig_dates, "%Y")) * 12L +
                             as.integer(format(.sig_dates, "%m")))
.mom <- merge(.mom, .sig_ymi, by = "ymi")[, .(Date, Ticker, Mom)]
setkey(.mom, Date, Ticker)

# ---- rank → z 변환 (횡단면, 시그널월만 — C1) ----
.rank_z <- function(x) {
  r <- frank(x, ties.method = "average")
  s <- sd(r)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mean(r)) / s
}

# ---- 월별 컴포짓: (rankZ(Mom) + rankZ(Rev)) / 2 — 컨센서스 결측 = 제외 ----
.factor_list <- vector("list", length(.sig_dates))
.diag_list   <- vector("list", length(.sig_dates))
for (i in seq_along(.sig_dates)) {
  d <- .sig_dates[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0L) next
  rev <- fdt[Factor_Name == .REV_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, Rev = Z_Score_Aligned)]
  rev <- rev[Ticker %in% uni_tk]

  mom <- .mom[.(d), .(Ticker, Mom), nomatch = 0L]
  mom <- mom[Ticker %in% uni_tk]

  # ★inner join = 컨센서스(또는 모멘텀) 결측 종목 제외 — 폴백 없음 (규칙)
  cmb <- merge(rev, mom, by = "Ticker")
  n_cov <- nrow(rev)                      # 유니버스 내 C13 커버 종목 수 (커버리지 보고용)
  if (nrow(cmb) < 30L) {
    .diag_list[[i]] <- data.table(Date = d, n_uni = length(uni_tk), n_c13 = n_cov,
                                  n = nrow(cmb), cor_zm_zr = NA_real_, used = FALSE)
    next
  }
  cmb[, Zr := .rank_z(Rev)]
  cmb[, Zm := .rank_z(Mom)]
  cmb <- cmb[is.finite(Zr) & is.finite(Zm)]
  if (nrow(cmb) < 30L) next
  cmb[, Score := (Zm + Zr) / 2]
  .factor_list[[i]] <- data.table(Date = d, cmb[, .(Ticker, Score)])
  .diag_list[[i]] <- data.table(Date = d, n_uni = length(uni_tk), n_c13 = n_cov,
                                n = nrow(cmb),
                                cor_zm_zr = suppressWarnings(cor(cmb$Zm, cmb$Zr)),
                                used = TRUE)
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
.diag <- rbindlist(Filter(Negate(is.null), .diag_list), use.names = TRUE)
.diag_used <- .diag[used == TRUE]
.diag_used[, cov_ratio := n_c13 / n_uni]

cat(sprintf("[fe_rf_b1_4] JT1993 mom(12-1) rankZ + CJL1996 C13 revision-breadth rankZ 50/50 | rows=%d | months=%d | 횡단면 n median=%.0f\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), median(.diag_used$n)))
cat(sprintf("[fe_rf_b1_4][커버리지] C13 실측정 개시월=%s | 유니버스 대비 커버 비율: median=%.3f [p10=%.3f p90=%.3f] | 컴포짓 채택월=%d / 시도월=%d\n",
            as.character(min(.diag_used$Date)),
            median(.diag_used$cov_ratio), quantile(.diag_used$cov_ratio, 0.10),
            quantile(.diag_used$cov_ratio, 0.90), nrow(.diag_used), nrow(.diag)))
cat(sprintf("[fe_rf_b1_4][성분진단] cor(Zm,Zr): mean=%.3f median=%.3f [p10=%.3f p90=%.3f]\n",
            mean(.diag_used$cor_zm_zr, na.rm = TRUE), median(.diag_used$cor_zm_zr, na.rm = TRUE),
            quantile(.diag_used$cor_zm_zr, 0.10, na.rm = TRUE),
            quantile(.diag_used$cor_zm_zr, 0.90, na.rm = TRUE)))

# 커버리지 진단 저장 (전략 디렉터리 내부만 — 병렬 B1 경계 준수)
tryCatch({
  .diag_out <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                         "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                         "04_Research", "strategies", "RF_B1_4_MomRevision",
                         "coverage_diag.csv")
  fwrite(.diag, .diag_out)
}, error = function(e) cat("[fe_rf_b1_4] 진단 저장 실패(비치명):", conditionMessage(e), "\n"))
