# =============================================================================
# fe_valmomqual.R — value(BM) + momentum(12-1) + quality(GP) 3-way z-combo
# =============================================================================
# 동기: fe_valmom.R (AMP 2013 value+momentum) 확장. Carhart4에 없는 quality
#       (Novy-Marx 2013 Gross Profitability) 축을 추가해 ① combo 알파의 Carhart4
#       직교 t(momentum 통제 후 1.63 경계미달)를 살리고 ② quality 방어성으로
#       MDD(valmom 60.4%) 완화 여부를 검증.
#
# ★ 논문 완전 복제 (alpha-search 제1원칙) — 3축 동일가중 z-combo:
#   - value    : Book-to-Market. factor DB `V01_BM` Z_Score_Aligned (AMP value 정의).
#   - momentum : 12-1 (최근 1개월 제외, 과거 12개월 누적). RAWDATA shift(21)/shift(252)-1 (PIT-safe).
#   - quality  : Gross Profit to Assets. factor DB `Q01_GPA` Z_Score_Aligned (Novy-Marx GP 정의).
#   - combo    : 세 신호 각각 universe 내 cross-sectional z-score → **동일가중 3-합**
#                (z(value)+z(momentum)+z(quality)). value+momentum+quality 1/3씩.
#   - 포트폴리오: combo 상위 **decile** (상위 10%), **equal-weight** (decile EW).
#   - 리밸런싱 : 월간 (KR factor DB 월간 갱신 표준, 명시 보충).
#   - 유니버스 : K200∪KQ150 (실투 표준, 도훈 mandate). 본 엔진 내부 멤버십+유동성 필터
#                후 그 universe 내에서 z-score 표준화. run_alpha_search universe="K200_KQ150"
#                머지는 idempotent.
#
# ===== PIT (C1~C15) =====
#   - value/quality: load_month_factors(sig_date) Z_Score_Aligned = Usable_Date<=sig_date IC
#     방향정렬(C14) + 재무 PIT(연간 5월 lag, factor DB 빌드 반영). NEGATE/FLIP 없음(C13).
#   - momentum: shift(21)/shift(252) = 과거 윈도우만, 동일시점 순환참조 없음(C2). t-1 기준.
#   - z-score는 sig_date 시점 cross-section만 사용(full-sample 통계 아님, C1).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

VAL_FACTOR <- "V01_BM"    # value 축 = Book-to-Market (AMP)
GP_FACTOR  <- "Q01_GPA"   # quality 축 = Gross Profit to Assets (Novy-Marx)

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")          # factor DB BM/GPA(재무) 가용 시작
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# ---- K200∪KQ150 멤버십 + 유동성(20일 평균 거래대금 2e8) 유니버스 (PIT 시변) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
setkey(.mem, Date, Ticker)

# ---- momentum 12-1 신호 (월말 시점 과거 윈도우, PIT-safe) ----
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]   # 12M(~252d), 최근 1M(~21d) 제외
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
RAWDATA[, c(".TV", ".AvgTV20", ".Mom") := NULL]
setkey(.mom_all, Date, Ticker)

# ---- 월별 3-way combo: z(value)+z(momentum)+z(quality), universe 내 cross-sectional 표준화 ----
.zsc <- function(x) {
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (x - mu) / s
}

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next

  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next

  # value (BM Z_Score_Aligned) — universe 한정
  val <- fdt[Factor_Name == VAL_FACTOR & is.finite(Z_Score_Aligned), .(Ticker, Val = Z_Score_Aligned)]
  val <- val[Ticker %in% uni_tk]

  # quality (GPA Z_Score_Aligned) — universe 한정
  qual <- fdt[Factor_Name == GP_FACTOR & is.finite(Z_Score_Aligned), .(Ticker, Qual = Z_Score_Aligned)]
  qual <- qual[Ticker %in% uni_tk]

  # momentum — universe 한정
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L]
  mom <- mom[Ticker %in% uni_tk]

  # 세 신호 모두 존재하는 종목만 combo (3축 모두 정의된 횡단면)
  cmb <- merge(merge(val, mom, by = "Ticker"), qual, by = "Ticker")
  if (nrow(cmb) < 10L) next

  # cross-sectional z-score (universe 내) 후 동일가중 3-합
  cmb[, Zv := .zsc(Val)]
  cmb[, Zm := .zsc(Mom)]
  cmb[, Zq := .zsc(Qual)]
  cmb <- cmb[is.finite(Zv) & is.finite(Zm) & is.finite(Zq)]
  if (nrow(cmb) < 10L) next
  cmb[, Score := Zv + Zm + Zq]
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# decile (상위 10%) long-only EW — N marker
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

cat(sprintf("[fe_valmomqual] value(BM)+mom(12-1)+quality(GPA) 3-way z-combo | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N, na.rm = TRUE) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N, na.rm = TRUE) else 0L))
