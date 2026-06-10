# =============================================================================
# fe_valrev.R — value(BM) + short-term reversal 직교 2축 결합 (KR single-market)
# =============================================================================
# 가설: value(Fama-French BM, 펀더멘털 축)와 단기 반전(Jegadeesh 1990 short-term
#       reversal, 단기 평균회귀 축)은 서로 다른 축의 알파원이다. long-short gross
#       단독 측정에서 value(BM) Carhart4 t3.28·OOS0.41, reversal(streversal)
#       t2.76 둘 다 직교 alpha 확인됨. 두 신호가 다른 축이라면 z-combo 결합 시
#       분산효과로 valmom(t3.13)·value_bm(t3.28) 단독을 능가할 수 있다 — 검증.
#
# ★ 결합 방법론 (fe_valmom.R AMP combo 패턴 동일, momentum→reversal 교체):
#   - value 신호    : Book-to-Market (BM). factor DB `V01_BM` Z_Score_Aligned
#                     (load_month_factors 경유, C13/C14/C15). FF/AMP value 정의.
#   - reversal 신호 : 단기 반전 = -(과거 약 1개월 수익률). fe_streversal.R 신호 로직
#                     그대로 복제: Score_rev = -(shift(Close,1)/shift(Close,22)-1).
#                     최근 1개월 패자(낮은 과거수익) = 높은 reversal score.
#                     RAWDATA 가격 shift(1)/shift(22) (PIT-safe, t-1 기준).
#   - combo 구성    : 두 신호 각 universe 내 cross-sectional z-score 표준화 →
#                     **동일가중 합** (z(value)+z(reversal)). 둘 다 정의된 횡단면만.
#   - 포트폴리오    : combo 상위 decile (driver_ls_generic.R DECILE_FRAC=0.10),
#                     equal-weight. long-short = 상위 decile − 하위 decile (gross).
#   - 리밸런싱      : 월간 (KR factor DB 월간 갱신 표준 → 월간, 명시 보충).
#   - 유니버스      : K200∪KQ150 (실투 표준) — 멤버십+유동성 필터 후 그 universe
#                     내에서 z-score 표준화(combo 정합).
#
# ===== PIT (C1~C15) =====
#   - value: load_month_factors(sig_date) Z_Score_Aligned = Usable_Date<=sig_date IC
#     방향정렬(C14) + 재무 PIT(book value 연간 5월 lag, factor DB 빌드 반영). NEGATE/FLIP 없음(C13).
#   - reversal: shift(Close,1)/shift(Close,22) = 과거 윈도우만, t-1까지(C2 동일시점 순환참조 없음).
#     부호는 reversal 정의상 음수(-) — NEGATE_FACTORS(C13)가 아니라 신호 정의 자체(Jegadeesh 1990
#     "패자 매수" = 과거수익의 역). fe_streversal.R 원본과 부호 정합.
#   - z-score는 sig_date 시점 cross-section만 사용(full-sample 통계 아님, C1).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

VAL_FACTOR <- "V01_BM"   # value 축 = Book-to-Market

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")          # factor DB BM(재무) 가용 시작
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# ---- K200∪KQ150 멤버십 + 유동성(20일 평균 거래대금 2e8) 유니버스 (PIT 시변) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
setkey(.mem, Date, Ticker)

# ---- 단기 반전 신호 (fe_streversal.R 로직 그대로: -(과거 ~1개월 수익), PIT-safe) ----
RAWDATA[, .Rev := -(shift(Close, 1L) / shift(Close, 22L) - 1), by = Ticker]   # 패자 = 높은 Score
.rev_all <- RAWDATA[Date %in% .month_ends & is.finite(.Rev), .(Date, Ticker, Rev = .Rev)]
RAWDATA[, c(".TV", ".AvgTV20", ".Rev") := NULL]
setkey(.rev_all, Date, Ticker)

# ---- 월별 combo: z(value) + z(reversal), universe 내 cross-sectional 표준화 ----
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

  # value (BM Z_Score_Aligned) — universe 한정
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  val <- fdt[Factor_Name == VAL_FACTOR & is.finite(Z_Score_Aligned), .(Ticker, Val = Z_Score_Aligned)]
  val <- val[Ticker %in% uni_tk]

  # reversal — universe 한정
  rev <- .rev_all[.(d), .(Ticker, Rev), nomatch = 0L]
  rev <- rev[Ticker %in% uni_tk]

  # 두 신호 모두 존재하는 종목만 combo (둘 다 정의된 횡단면)
  cmb <- merge(val, rev, by = "Ticker")
  if (nrow(cmb) < 10L) next

  # cross-sectional z-score (universe 내) 후 동일가중 합 = value/reversal 50/50 combo
  cmb[, Zv := .zsc(Val)]
  cmb[, Zr := .zsc(Rev)]
  cmb <- cmb[is.finite(Zv) & is.finite(Zr)]
  if (nrow(cmb) < 10L) next
  cmb[, Score := Zv + Zr]
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# decile (상위 10%) long-only EW marker (fe_valmom / fe_value_bm 동일 규약)
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

cat(sprintf("[fe_valrev] value(BM)+reversal(1M) z-combo | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N, na.rm = TRUE) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N, na.rm = TRUE) else 0L))
