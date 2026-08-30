# =============================================================================
# fe_rf_b1_1_momvalue.R — 규칙기반 고속강화 B1-1 (도훈 프로그램 2026-08-29)
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast attempt n=1
# 규칙 (설계 재량 0):
#   신호   = 모멘텀(12-1) rank-Z + 가치(B/M) rank-Z 의 50/50 합산 (매월 리밸일
#            횡단면 rank → z 변환 후 평균).
#   모멘텀 = 12-1: 월말 시그널 시점 m 에서 C(m-1)/C(m-12) - 1 (직전 1개월 스킵,
#            월 수익률 누적). 근거 Jegadeesh & Titman (1993), JF 48(1):65-91
#            https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#   가치   = B/M (장부가/시가). 근거 Fama & French (1992), JF 47(2):427-465
#            https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.1992.tb04398.x
#            factor DB `V01_BM` 을 load_month_factors() 경유 소비 (C15) —
#            Z_Score_Aligned (C13: NEGATE/FLIP 금지, C14: Usable_Date<=sig_date IC,
#            C4: 재무 lag 는 factor DB 빌드가 반영). rank 는 단조변환이라 방향 보존.
#   유니버스 = K200∪KQ150 (PIT 시변 멤버십) + 유동성 20일 평균 거래대금 >= 2e8
#            (★t-1: frollmean 후 shift(1) — C10).
#   포트폴리오 = 러너 portfolio_spec (top_n_long n=25, EW, 월간) — 엔진은 Score 만.
#
# ===== PIT (C1~C15) 자가점검 =====
#   C1  : rank-Z 는 시그널월 횡단면만 사용 (full-sample 통계 없음)
#   C2  : Mom = C(m-1)/C(m-12) — 시그널일(월말 m) 이전 종가만, 순환참조 없음
#   C4  : B/M 재무 lag = factor DB 빌드 반영 (annual 익년 3/31 가용)
#   C10 : 유동성 필터 = 20일 평균 거래대금의 t-1 값 (shift 1)
#   C13 : Z_Score_Aligned 그대로 (부호 조작 없음). rank = 단조변환
#   C14 : load_month_factors(sig_date) 가 Usable_Date <= sig_date 강제
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

.VAL_FACTOR <- "V01_BM"   # 가치 축 = Book-to-Market (FF1992)

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

# ---- 월별 컴포짓: (rankZ(Mom) + rankZ(Val)) / 2 ----
.factor_list <- vector("list", length(.sig_dates))
.diag_list   <- vector("list", length(.sig_dates))
for (i in seq_along(.sig_dates)) {
  d <- .sig_dates[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0L) next
  val <- fdt[Factor_Name == .VAL_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, Val = Z_Score_Aligned)]
  val <- val[Ticker %in% uni_tk]

  mom <- .mom[.(d), .(Ticker, Mom), nomatch = 0L]
  mom <- mom[Ticker %in% uni_tk]

  cmb <- merge(val, mom, by = "Ticker")
  if (nrow(cmb) < 30L) next
  cmb[, Zv := .rank_z(Val)]
  cmb[, Zm := .rank_z(Mom)]
  cmb <- cmb[is.finite(Zv) & is.finite(Zm)]
  if (nrow(cmb) < 30L) next
  cmb[, Score := (Zm + Zv) / 2]
  .factor_list[[i]] <- data.table(Date = d, cmb[, .(Ticker, Score)])
  .diag_list[[i]] <- data.table(Date = d, n = nrow(cmb),
                                cor_zm_zv = suppressWarnings(cor(cmb$Zm, cmb$Zv)),
                                sd_zm = sd(cmb$Zm), sd_zv = sd(cmb$Zv),
                                sd_score = sd(cmb$Score))
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
.diag <- rbindlist(Filter(Negate(is.null), .diag_list), use.names = TRUE)

cat(sprintf("[fe_rf_b1_1] JT1993 mom(12-1) rankZ + FF1992 B/M rankZ 50/50 | rows=%d | months=%d | 횡단면 n median=%.0f\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), median(.diag$n)))
cat(sprintf("[fe_rf_b1_1][성분진단] cor(Zm,Zv): mean=%.3f median=%.3f [p10=%.3f p90=%.3f] | sd(Zm)=%.3f sd(Zv)=%.3f (rank-Z 설계상 1) | sd(Score): mean=%.3f\n",
            mean(.diag$cor_zm_zv, na.rm = TRUE), median(.diag$cor_zm_zv, na.rm = TRUE),
            quantile(.diag$cor_zm_zv, 0.10, na.rm = TRUE), quantile(.diag$cor_zm_zv, 0.90, na.rm = TRUE),
            mean(.diag$sd_zm, na.rm = TRUE), mean(.diag$sd_zv, na.rm = TRUE),
            mean(.diag$sd_score, na.rm = TRUE)))
