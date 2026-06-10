# =============================================================================
# fe_value_bm.R — Fama-French (1992) Book-to-Market (HML) Value Premium 복제
# =============================================================================
# 논문: Fama-French (1992) "The Cross-Section of Expected Stock Returns", JF.
#       high book-to-market(BM = book/market) = HML value 축. high-BM decile
#       long-only, equal-weight, monthly rebalance.
#
# ★ 논문 완전 복제 (alpha-search 제1원칙):
#   - 시그널: Book-to-Market = factor DB `V01_BM` (정확히 FF HML value 축).
#     load_month_factors() 경유(C15) → Z_Score_Aligned(C13 IC-aligned, C14 PIT).
#   - 포트폴리오: high-BM **decile** (상위 10%), **equal-weight** (decile EW 그대로).
#   - 리밸런싱: 월간 (KR factor DB 월간 갱신 표준 → 월간, 명시 보충).
#   - 유니버스: run_alpha_search universe="ALL"(엔진 내부서 K200∪KQ150 적용, decile 분모 정합).
#
# ===== PIT =====
#   - load_month_factors(sig_date): Z_Score_Aligned는 Usable_Date<=sig_date IC 방향정렬(C14),
#     재무 PIT(book value 연간 5월 lag)는 factor DB 빌드 단계 반영.
#   - 동일시점 순환참조 없음. NEGATE/FLIP 없음(C13).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

VAL_FACTOR <- "V01_BM"   # Fama-French Book-to-Market

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]

.fdb_min <- as.Date("2002-08-01")
.month_ends <- .month_ends[.month_ends >= .fdb_min]

RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
RAWDATA[, c(".TV", ".AvgTV20") := NULL]
setkey(.mem, Date, Ticker)

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  bm <- fdt[Factor_Name == VAL_FACTOR & is.finite(Z_Score_Aligned), .(Ticker, Score = Z_Score_Aligned)]
  if (nrow(bm) == 0) next
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  bm <- bm[Ticker %in% uni_tk]
  if (nrow(bm) == 0) next
  bm[, Date := d]
  .factor_list[[i]] <- bm
}
FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

cat(sprintf("[fe_value_bm] FF Book-to-Market (V01_BM) | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$N, na.rm = TRUE), max(FACTORS$N, na.rm = TRUE)))
