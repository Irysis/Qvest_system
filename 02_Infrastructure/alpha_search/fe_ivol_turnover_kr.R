# =============================================================================
# fe_ivol_turnover_kr.R — "Idiosyncratic volatility, turnover and the cross-section of stock
#   returns: evidence from the Korean stock market" (IJOEM 18(12), 2023) 의 KR 복제
#   (pg2 큐 title:idiosyncraticvolatilityturnoverandthecrosssection… — abstract/pg2 기록 수준)
# =============================================================================
# 논문 핵심(pg2 기록): KR 에서 IVOL 퍼즐(고 IVOL → 저수익)은 **고회전율 종목에 집중** — 고IVOL ∧ 고TO
#   셀이 저수익. 내부 스케치는 이를 STR_1715 배제 스크린으로 썼으나 lean 라운드는 독립 전략만 다루므로
#   논문 L/S 의 **롱 레그**(저IVOL ∧ 저TO 셀)를 long-only 로 사상(제1원칙 2).
# KR 재구성:
#   - D01_IdioVol · L02_Turnover = factor DB 정렬 z(C13: 정렬 z 는 '높을수록 좋음' 으로 부호 맞춰짐 —
#     IVOL·TO 모두 저값이 선호 → 정렬 z 상위 = 저IVOL / 저TO). 독립 이중정렬: 각 상위 quintile 교집합.
#   - 롱 레그 = 저IVOL ∧ 저TO 셀 **전부 EW**(동적 N, 유니버스 ~300 → ~15~30). 월간 리밸(시스템 표준).
#   - 논문 표본 2016 종료 — 2017+ 감쇠는 판정 라벨로 확인. 유니버스 K200∪KQ150 ∧ 유동성 2e8. 기간 2005~.
# ===== PIT (C1~C15) =====
#   - 두 팩터 모두 load_month_factors(d) PIT z (Usable_Date ≤ sig_date; L02 는 t-1 회전율 C10).
#   - 월별 횡단면만(C1), 미래 정보 없음(C2), NEGATE 없음(C13 — 정렬 z 그대로).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", getwd()),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

F_IVOL <- "D01_IdioVol"; F_TO <- "L02_Turnover"
Q_CUT  <- 0.20        # 독립 이중정렬 상위 quintile

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
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = c(F_IVOL, F_TO)),
                  error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) next
  w <- dcast(fdt[Factor_Name %in% c(F_IVOL, F_TO) & is.finite(Z_Score_Aligned)],
             Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  if (!all(c(F_IVOL, F_TO) %in% names(w))) next
  w <- w[Ticker %in% uni_tk & is.finite(get(F_IVOL)) & is.finite(get(F_TO))]
  if (nrow(w) < 30L) next
  # 독립 정렬: 정렬 z 상위(=저IVOL / 저TO) quintile 각각 → 교집합 셀
  w[, p_iv := (frank(-get(F_IVOL), ties.method = "first") - 0.5) / .N]
  w[, p_to := (frank(-get(F_TO),   ties.method = "first") - 0.5) / .N]
  cell <- w[p_iv <= Q_CUT & p_to <= Q_CUT]
  if (nrow(cell) < 5L) next
  out <- cell[, .(Date = d, Ticker, Score = (get(F_IVOL) + get(F_TO)) / 2)]
  out[, N := .N]
  .factor_list[[i]] <- out
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
if (!nrow(FACTORS)) stop("[fe_ivol_turnover_kr] FACTORS 0 rows")

cat(sprintf("[fe_ivol_turnover_kr] KR IVOL×TO 이중정렬 롱 레그(저IVOL ∧ 저TO quintile 교집합) EW | FACTORS rows=%d | signal months=%d | N range=%d~%d (median %d)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$N), max(FACTORS$N), as.integer(median(FACTORS$N))))
