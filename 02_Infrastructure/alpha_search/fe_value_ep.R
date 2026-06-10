# =============================================================================
# fe_value_ep.R — Basu (1977) Earnings-Yield (EP) Value Premium 복제
# =============================================================================
# 논문: Basu (1977) "Investment Performance of Common Stocks in Relation to
#       Their P/E Ratios", JF. high earnings-yield(EP = earnings/price, 즉 low-PE)
#       decile long-only, equal-weight, monthly rebalance.
#       (Fama-French 1992 HML의 value 축과 동렬 — EP/BM 모두 value premium 대표.)
#
# ★ 논문 완전 복제 (alpha-search 제1원칙):
#   - 시그널: Earnings-to-Price = factor DB `V02_EP` (정확히 Basu EP, earnings yield).
#     load_month_factors() 경유(C15) → Z_Score_Aligned(C13 IC-aligned higher=better, C14 PIT).
#   - 포트폴리오: high-EP **decile** (상위 10%), **equal-weight** (논문 decile EW 그대로).
#       → FACTORS$N = ceil(n_eligible/10) per month → run_monthly_simulation이 월별
#         top-decile 선택(weight_method="equal"). buffer_zone은 엔진 표준값(논문 미명시 → 보충).
#   - 리밸런싱: 월간 (Basu는 연간 재구성이나 KR factor DB 월간 갱신 표준 → 월간, 명시 보충).
#   - 유니버스: run_alpha_search universe="ALL"(엔진 내부서 K200∪KQ150 직접 적용, decile 분모 정합).
#
# ===== PIT =====
#   - load_month_factors(sig_date): Z_Score_Aligned는 Usable_Date<=sig_date IC로 방향정렬(C14),
#     재무 PIT(연간 5월 / 분기 45일 lag)는 factor DB 빌드 단계에서 이미 반영.
#   - 동일시점 순환참조 없음(각 월말 시점 factor DB 스냅샷만). NEGATE/FLIP 없음(C13).
#
# ★ AX-003 인지: market=KR, family=value, EP_STANDALONE+LOW_TURNOVER 실패(provisional, N=2~3).
#   본 검증은 그 provisional negative를 KR 대형주(K200∪KQ150) decile EW로 재도전한다.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- factor DB connector (load_month_factors, C15 경유) ----
local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

VAL_FACTOR <- "V02_EP"   # Basu Earnings-to-Price (earnings yield)

# ---- 월말 시그널 날짜 (각 달 마지막 거래일) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]

# factor DB value/재무 가용 구간 (V01_BM/V02_EP 2002-08~). start_date는 run_alpha_search서 추가 제한.
.fdb_min <- as.Date("2002-08-01")
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# ---- 유니버스: K200 ∪ KQ150 멤버십 + 유동성 2e8 (decile 분모 정합 위해 엔진 내부 적용) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
RAWDATA[, c(".TV", ".AvgTV20") := NULL]
setkey(.mem, Date, Ticker)

# ---- 각 월말: V02_EP Z_Score_Aligned → Score (멤버십 교집합) ----
.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  ep <- fdt[Factor_Name == VAL_FACTOR & is.finite(Z_Score_Aligned), .(Ticker, Score = Z_Score_Aligned)]
  if (nrow(ep) == 0) next
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  ep <- ep[Ticker %in% uni_tk]
  if (nrow(ep) == 0) next
  ep[, Date := d]
  .factor_list[[i]] <- ep
}
FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# ---- decile sizing: 유니버스 내 상위 10% (high-EP decile, equal-weight 복제) ----
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

cat(sprintf("[fe_value_ep] Basu EP (V02_EP) | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$N, na.rm = TRUE), max(FACTORS$N, na.rm = TRUE)))
