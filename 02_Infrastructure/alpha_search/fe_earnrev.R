# =============================================================================
# fe_earnrev.R — Earnings-Revision / Analyst-Consensus Core 4F (STR_1715 알파원 해부)
# =============================================================================
# 가설: STR_1715(KR 고SR 1.50)의 실제 알파원은 value가 아니라 earnings-revision
#       consensus(애널리스트 이익전망 변경)다. STR_1715 Core 슬리브 4팩터:
#         C01_SUE          : Standardized Unexpected Earnings (어닝 서프라이즈)
#         C02_EPS_Chg_1m   : 1개월 EPS 전망 변경률
#         C04_ESBR         : Earnings Surprise / Broker Revision
#         C06_TP_Gap       : 목표주가 괴리 (Target Price Gap)
#       이 earnings-revision 신호가 value(BM) 대비 long-short로 얼마나 직교한가를
#       측정해 KR 직교원 지도(value / earnings-revision) 완성.
#
# ★ 단순화 (Q-Lead mandate): STR_1715 원전은 expanding IC-weighted blend(theta)지만
#   본 진단은 **동일가중 합**(equal-weight)부터. 4팩터 각 Z_Score_Aligned →
#   cross-sectional z-score 표준화 → z(C01)+z(C02)+z(C04)+z(C06) 단순 합 = Score.
#   (IC-가중·decile 비중은 driver(decile EW)가 처리. 본 fe는 Score 산출만.)
#
# ★ 계약: FACTORS(Date, Ticker, Score). universe = K200∪KQ150 + 유동성 2e8.
#   fe_valmom.R / fe_value_bm.R 패턴 재사용. LiqPass는 driver가 추가하나
#   본 fe는 자체적으로도 멤버십+유동성 필터(fe_valmom 동일 규약).
#
# ===== PIT (C1~C15) =====
#   - 각 팩터 load_month_factors(sig_date) Z_Score_Aligned = Usable_Date<=sig_date IC
#     방향정렬(C14) + 재무/애널리스트 PIT(announcement lag, factor DB 빌드 단계 반영, C4).
#     NEGATE/FLIP 없음(C13). Factor DB 직접 load 금지 → load_month_factors 경유(C15).
#   - z-score는 sig_date 시점 cross-section만(full-sample 통계 아님, C1).
#   - 동일시점 순환참조 없음(C2). earnings-revision은 announcement lag가 factor DB
#     Usable_Date에 이미 반영되어 sig_date 시점 가용분만 사용.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

# STR_1715 Core 슬리브 4팩터 (earnings-revision / analyst-consensus 축)
CORE_4F <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap")

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")          # factor DB 재무/애널리스트 가용 시작
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# ---- K200∪KQ150 멤버십 + 유동성(20일 평균 거래대금 2e8) 유니버스 (PIT 시변) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
RAWDATA[, c(".TV", ".AvgTV20") := NULL]
setkey(.mem, Date, Ticker)

# ---- cross-sectional z-score (universe 내) ----
.zsc <- function(x) {
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (x - mu) / s
}

# ---- 월별 combo: z(C01)+z(C02)+z(C04)+z(C06) 동일가중 합 ----
.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next

  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next

  # 4팩터 각각 wide (Z_Score_Aligned), universe 한정
  sub <- fdt[Factor_Name %in% CORE_4F & is.finite(Z_Score_Aligned),
             .(Ticker, Factor_Name, Z = Z_Score_Aligned)]
  sub <- sub[Ticker %in% uni_tk]
  if (nrow(sub) == 0) next
  w <- dcast(sub, Ticker ~ Factor_Name, value.var = "Z")
  avail <- intersect(CORE_4F, names(w))
  if (length(avail) == 0) next

  # 각 팩터 cross-sectional z-score (universe 내 표준화) 후 동일가중 합
  z_cols <- character(0)
  for (fn in avail) {
    zc <- paste0(".z_", fn)
    w[, (zc) := .zsc(get(fn))]
    z_cols <- c(z_cols, zc)
  }
  # 종목별 가용 팩터 z 합 (NA는 합에서 제외하지 않고 한 팩터라도 결측이면 partial 허용:
  # 모든 4팩터 동시 보유 종목만 쓰면 표본 급감 → 가용 z만 합산 + 최소 2팩터 요구)
  zmat <- as.matrix(w[, ..z_cols])
  n_valid <- rowSums(is.finite(zmat))
  w[, .Score := rowSums(zmat, na.rm = TRUE)]
  w[, .nvalid := n_valid]
  cmb <- w[.nvalid >= 2L, .(Ticker, Score = .Score)]   # 최소 2팩터 가용 종목만
  if (nrow(cmb) < 10L) next
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# decile (상위 10%) long-only EW — N marker (fe_valmom / fe_value_bm 동일 규약)
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

cat(sprintf("[fe_earnrev] STR_1715 Core 4F(C01_SUE+C02_EPS_Chg_1m+C04_ESBR+C06_TP_Gap) z-EW-sum | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N, na.rm = TRUE) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N, na.rm = TRUE) else 0L))
