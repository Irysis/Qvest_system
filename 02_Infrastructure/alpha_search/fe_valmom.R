# =============================================================================
# fe_valmom.R — Asness, Moskowitz & Pedersen (2013) "Value and Momentum
#               Everywhere" (Journal of Finance) 복제 (KR single-market 적용)
# =============================================================================
# 논문: AMP (2013). value와 momentum은 음(-)의 상관 → 50/50 combo가 각 단독보다
#       Sharpe 우월(분산효과). 각 시장 내에서 value/momentum 신호를 표준화 후
#       동일가중 결합한 "combo" 신호로 포트폴리오 구성.
#
# ★ 논문 완전 복제 (alpha-search 제1원칙):
#   - value 신호    : Book-to-Market (BM). AMP 원전의 value 정의(BM, EP 아님).
#                     factor DB `V01_BM` Z_Score_Aligned (load_month_factors 경유, C13/C14/C15).
#   - momentum 신호 : 12-1 (최근 1개월 제외, 과거 12개월 누적수익) = Jegadeesh-Titman 표준.
#                     RAWDATA 가격 shift(21)/shift(252)-1 (PIT-safe).
#   - combo 구성    : 각 신호를 **cross-sectional z-score 표준화 → 동일가중 합**
#                     (z(value)+z(momentum)). AMP의 50/50 equal-weight combination.
#   - 포트폴리오    : combo 상위 **decile** (상위 10%), **equal-weight** (decile EW).
#   - 리밸런싱      : 월간 (KR factor DB 월간 갱신 표준 → 월간, 명시 보충).
#   - 유니버스      : K200∪KQ150 (실투 표준, 도훈 mandate 2026-06-05) — 본 엔진에서
#                     멤버십+유동성 필터 후 그 universe 내에서 z-score 표준화(combo 정합).
#                     run_alpha_search universe="K200_KQ150" 머지는 idempotent.
#
# ===== PIT (C1~C15) =====
#   - value: load_month_factors(sig_date) Z_Score_Aligned = Usable_Date<=sig_date IC
#     방향정렬(C14) + 재무 PIT(book value 연간 5월 lag, factor DB 빌드 반영). NEGATE/FLIP 없음(C13).
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

VAL_FACTOR <- "V01_BM"   # AMP value 축 = Book-to-Market

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

# ---- momentum 12-1 신호 (월말 시점 과거 윈도우, PIT-safe) ----
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]   # 12M(~252d), 최근 1M(~21d) 제외
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
RAWDATA[, c(".TV", ".AvgTV20", ".Mom") := NULL]
setkey(.mom_all, Date, Ticker)

# ---- 월별 combo: z(value) + z(momentum), universe 내 cross-sectional 표준화 ----
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

  # momentum — universe 한정
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L]
  mom <- mom[Ticker %in% uni_tk]

  # 두 신호 모두 존재하는 종목만 combo (AMP combo = 둘 다 정의된 횡단면)
  cmb <- merge(val, mom, by = "Ticker")
  if (nrow(cmb) < 10L) next

  # cross-sectional z-score (universe 내) 후 동일가중 합 = AMP 50/50 combo
  cmb[, Zv := .zsc(Val)]
  cmb[, Zm := .zsc(Mom)]
  cmb <- cmb[is.finite(Zv) & is.finite(Zm)]
  if (nrow(cmb) < 10L) next
  cmb[, Score := Zv + Zm]
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# decile (상위 10%) long-only EW — N marker (fe_value_bm와 동일 규약)
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

cat(sprintf("[fe_valmom] AMP2013 value(BM)+mom(12-1) z-combo | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N, na.rm = TRUE) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N, na.rm = TRUE) else 0L))
