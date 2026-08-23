# =============================================================================
# fe_max_arbrisk_kr.R — "The role of arbitrage risk in the MAX effect: evidence from the Korean
#   stock market" (JDQS 32(2), 2024) 의 KR 복제 (pg2 큐 title:theroleofarbitrageriskinthemaxeffect…)
# =============================================================================
# 논문 핵심(abstract/pg2 기록 수준): Bali-Cakici-Whitelaw(2011) MAX 효과(직전 1개월 최대 일수익 高 →
#   저수익, 복권 수요)가 KR 에서 **차익거래 위험(arbitrage risk = 고유변동성)이 큰 종목에 집중** —
#   차익자가 교정하기 어려운 곳에서만 고평가가 잔존. 내부 스케치는 STR_1715 배제 스크린이나 lean 라운드는
#   독립 전략이므로 논문 L/S 의 롱 레그(고IVOL ∧ 저MAX)를 long-only 로 사상(제1원칙 2).
# KR 재구성:
#   - M22_Max_Return(Bali 2011 MAX, lower_better) · D01_IdioVol = factor DB 정렬 z(C13: 정렬 z 높을수록
#     선호 ⇒ 정렬 z 상위 = 저MAX / 저IVOL). 조건부 이중정렬: IVOL **하위** 정렬 z(=고IVOL) quintile →
#     그 안에서 MAX 정렬 z 상위(=저MAX) quintile. 롱 레그 셀 전부 EW(동적 N ≈ 12~15). 월간 리밸.
#   - 유니버스 K200∪KQ150 ∧ 유동성 2e8. 기간 2005~.
# ===== PIT (C1~C15) =====
#   - 두 팩터 load_month_factors(d) PIT z(Usable_Date ≤ sig_date). 월별 횡단면만(C1), NEGATE 없음(C13).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", getwd()),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

F_MAX <- "M22_Max_Return"; F_IVOL <- "D01_IdioVol"
Q_CUT <- 0.20

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-06-01")]

RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(.mem, Date, Ticker)
RAWDATA[, c(".TV", ".AvgTV20") := NULL]

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = c(F_MAX, F_IVOL)),
                  error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) next
  w <- dcast(fdt[Factor_Name %in% c(F_MAX, F_IVOL) & is.finite(Z_Score_Aligned)],
             Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  if (!all(c(F_MAX, F_IVOL) %in% names(w))) next
  w <- w[Ticker %in% uni_tk & is.finite(get(F_MAX)) & is.finite(get(F_IVOL))]
  if (nrow(w) < 30L) next
  # 조건부 정렬: 고IVOL(정렬 z 하위) quintile → 그 안에서 저MAX(정렬 z 상위) quintile
  w[, p_iv := (frank(get(F_IVOL), ties.method = "first") - 0.5) / .N]   # 작은 정렬 z = 고IVOL = 상위
  hi_iv <- w[p_iv <= Q_CUT]
  if (nrow(hi_iv) < 10L) next
  hi_iv[, p_mx := (frank(-get(F_MAX), ties.method = "first") - 0.5) / .N]  # 큰 정렬 z = 저MAX = 상위
  cell <- hi_iv[p_mx <= Q_CUT]
  if (nrow(cell) < 3L) next
  out <- cell[, .(Date = d, Ticker, Score = get(F_MAX))]
  out[, N := .N]
  .factor_list[[i]] <- out
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
if (!nrow(FACTORS)) stop("[fe_max_arbrisk_kr] FACTORS 0 rows")

cat(sprintf("[fe_max_arbrisk_kr] KR MAX×차익위험: 고IVOL quintile 내 저MAX quintile 롱 레그 EW 월간 | FACTORS rows=%d | signal months=%d | N range=%d~%d (median %d)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$N), max(FACTORS$N), as.integer(median(FACTORS$N))))
