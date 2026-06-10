# =============================================================================
# fe_qualitygp.R — Novy-Marx (2013) Gross Profitability Premium 복제
# =============================================================================
# 논문: Novy-Marx (2013) "The Other Side of Value: The Gross Profitability
#       Premium", JFE. GP = (Revenue - COGS) / Total Assets = Gross Profit / Assets.
#       → high-GP decile long-only, equal-weight, monthly rebalance.
#
# ★ 논문 완전 복제 (alpha-search 제1원칙):
#   - 시그널: Gross Profit to Assets = factor DB `Q01_GPA` (정확히 Novy-Marx GP).
#     load_month_factors() 경유(C15) → Z_Score_Aligned(C13, IC-aligned higher=better, C14 PIT).
#   - 포트폴리오: high-GP **decile** (상위 10%), **equal-weight** (논문 그대로).
#       → FACTORS$N = ceil(n_eligible/10) per month → run_monthly_simulation이 월별
#         top-decile 선택(weight_method="equal"로 호출). buffer_zone은 엔진 표준값(논문 미명시 → 보충, hysteresis 경미).
#   - 리밸런싱: 월간 (논문은 연간 재구성이나 KR factor DB 월간 갱신 표준 → 월간, 명시).
#   - 유니버스: run_alpha_search universe="K200_KQ150" (도훈 mandate: 외국논문 → KR 실투 유니버스 고정).
#
# ===== PIT =====
#   - load_month_factors(sig_date): Z_Score_Aligned 는 Usable_Date<=sig_date IC로 방향정렬(C14),
#     재무 PIT(연간 5월 lag 등)는 factor DB 빌드 단계에서 이미 반영.
#   - 동일시점 순환참조 없음(각 월말 시점 factor DB 스냅샷만 사용). NEGATE/FLIP 없음(C13).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- factor DB connector (load_month_factors, C15 경유) ----
local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

GP_FACTOR <- "Q01_GPA"   # Novy-Marx Gross Profit to Assets

# ---- 월말 시그널 날짜 (각 달 마지막 거래일) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]

# factor DB는 2002-08~ (재무/value 한계). 시그널 가용 구간만 (start_date는 run_alpha_search에서 추가 제한).
.fdb_min <- as.Date("2002-08-01")
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# ---- 유니버스: K200 ∪ KQ150 멤버십을 엔진 내부에서 적용 (decile 분모 정합 위해) ----
#   run_alpha_search universe 필터는 FACTORS merge 후라 decile N(분모)이 어긋남
#   → 여기서 직접 멤버십·유동성 필터한 뒤 그 안에서 decile N 계산. run_alpha_search는 universe="ALL"로 호출.
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
RAWDATA[, c(".TV", ".AvgTV20") := NULL]
setkey(.mem, Date, Ticker)

# ---- 각 월말: Q01_GPA Z_Score_Aligned 추출 → Score (멤버십 교집합) ----
.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  gp <- fdt[Factor_Name == GP_FACTOR & is.finite(Z_Score_Aligned), .(Ticker, Score = Z_Score_Aligned)]
  if (nrow(gp) == 0) next
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]   # 해당 월 K200/KQ150 ∩ 유동성
  gp <- gp[Ticker %in% uni_tk]
  if (nrow(gp) == 0) next
  gp[, Date := d]
  .factor_list[[i]] <- gp
}
FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# ---- decile sizing: 유니버스 내 상위 10% (high-GP decile, equal-weight로 복제) ----
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

cat(sprintf("[fe_qualitygp] Novy-Marx GP (Q01_GPA) | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$N, na.rm = TRUE), max(FACTORS$N, na.rm = TRUE)))
