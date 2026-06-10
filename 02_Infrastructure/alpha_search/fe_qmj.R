# =============================================================================
# fe_qmj.R — Asness-Frazzini-Pedersen (2019) "Quality Minus Junk" 복제
# =============================================================================
# 논문: Asness, Frazzini, Pedersen (2019) "Quality Minus Junk", Review of
#       Accounting Studies 24:34-112. Quality = 4-axis composite:
#         Quality = z(Profitability) + z(Growth) + z(Safety) + z(Payout)
#       각 축은 다수 하위지표를 횡단면 z-score 한 뒤 등가중 평균, 4축을 다시 등가중.
#       원본은 QMJ = long high-quality / short low-quality. KR long-only이므로
#       **high-Quality composite decile long-only, equal-weight, monthly rebalance**.
#
# ★ 논문 완전 복제 (alpha-search 제1원칙):
#   - 시그널 = 4축 composite. 각 축 = AFP 정의 하위지표의 Z_Score_Aligned 등가중 평균,
#     4축을 다시 등가중 평균(논문 weighting 그대로). 단일 팩터가 아닌 *다축 조합*이
#     본 가설의 핵심(직교원 = 멀티팩터 composite).
#   - 하위지표 매핑 (factor DB ↔ AFP 축):
#       Profitability : Q01_GPA, Q02_ROE, Q03_ROA, Q09_CFOA, Q10_Gross_Margin, Q35_CashBased_OpProf
#                       (AFP: GPOA/ROE/ROA/CFOA/GMAR/ACC — gross-profit·cash-flow 수익성)
#       Growth        : GR07_Composite_Growth (AFP: 위 수익성 지표들의 5년 성장 — KR factor DB는 composite로 제공)
#                       + GR04_GPA_Growth, GR05_ROE_Growth (개별 성장축 보강)
#       Safety        : D02_Beta(low=safe), Q15_Debt_to_Equity(low=safe), Q24_Altman_Z(high=safe),
#                       Q07_Earnings_Stability(high=safe), Q32_Interest_Coverage(high=safe)
#                       (AFP Safety: low beta·low leverage·low bankruptcy risk·low ROE vol)
#       Payout        : Q20_Net_Equity_Issuance(low issuance=high payout=good)
#                       (AFP Payout: net equity/debt issuance·total payout — KR은 net equity issuance 대표)
#   - 방향: Z_Score_Aligned는 connector가 IC-aligned(higher=better)로 부호정렬(C13, 수동 FLIP 없음).
#     즉 low-beta/low-leverage/low-issuance "좋음"은 align_factor_direction이 IC 부호로 자동 처리.
#   - 포트폴리오: high-Quality **decile**(상위 10%), **equal-weight**(논문 그대로).
#       FACTORS$N = ceil(n_eligible/10) per month → run_monthly_simulation top-decile (weight_method="equal").
#   - 리밸런싱: 월간(논문 연간/분기 재구성이나 KR factor DB 월간 갱신 표준 → 월간, 명시 보충).
#   - 유니버스: run_alpha_search universe="ALL"(엔진 내부서 K200∪KQ150 직접 적용, decile 분모 정합).
#
# ===== PIT (C13/C14/C15) =====
#   - load_month_factors(sig_date): Z_Score_Aligned는 Usable_Date<=sig_date IC로 방향정렬(C14),
#     재무 PIT(연간 5월 / 분기 45일 lag)는 factor DB 빌드 단계에서 이미 반영.
#   - 동일시점 순환참조 없음(각 월말 시점 factor DB 스냅샷만). NEGATE/FLIP 없음(C13, alignment가 처리).
#   - 외부 parquet/cache 의존 없음(load_month_factors 경유, C15) → detect_lookahead 사각지대 아님.
#
# ★ 직교성 가설 인지: reversal/quality-GP/low-vol/value 단일 팩터는 직교 슬리브 실패.
#   QMJ는 단일 축이 아닌 4축 composite라 STR_1715(풀 내 0.05 무상관)와 동류인 "멀티팩터 조합"
#   가설의 직접 검증. IS Carhart4 알파 + OOS retention + STR_1715/풀 상관 셋 다로 슬리브 판정.
#   (EP가 IS Carhart4 +2.13였으나 OOS -0.257로 기각된 교훈 — OOS 필수.)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- factor DB connector (load_month_factors, C15 경유) ----
local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

# ---- AFP 4-axis 하위지표 매핑 (등가중 → 축 → 등가중 → composite) ----
AXES <- list(
  Profitability = c("Q01_GPA", "Q02_ROE", "Q03_ROA", "Q09_CFOA", "Q10_Gross_Margin", "Q35_CashBased_OpProf"),
  Growth        = c("GR07_Composite_Growth", "GR04_GPA_Growth", "GR05_ROE_Growth"),
  Safety        = c("D02_Beta", "Q15_Debt_to_Equity", "Q24_Altman_Z", "Q07_Earnings_Stability", "Q32_Interest_Coverage"),
  Payout        = c("Q20_Net_Equity_Issuance")
)
ALL_FACTORS <- unique(unlist(AXES))

# ---- 월말 시그널 날짜 (각 달 마지막 거래일) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]

# factor DB value/재무 가용 구간 (2002-08~). start_date는 run_alpha_search서 추가 제한.
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

# ---- 각 월말: 4축 composite Z 산출 (등가중 평균) ----
.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  fdt <- fdt[Factor_Name %in% ALL_FACTORS & is.finite(Z_Score_Aligned)]
  if (nrow(fdt) == 0) next

  # 유니버스 교집합 (K200/KQ150 ∩ 유동성)
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  fdt <- fdt[Ticker %in% uni_tk]
  if (nrow(fdt) == 0) next

  # 각 축: 하위지표 Z_Score_Aligned 등가중 평균 (가용 지표만, NA 무시)
  axis_scores <- lapply(names(AXES), function(ax) {
    sub <- fdt[Factor_Name %in% AXES[[ax]], .(axis_z = mean(Z_Score_Aligned, na.rm = TRUE)), by = Ticker]
    setnames(sub, "axis_z", ax)
    sub
  })
  # full outer merge on Ticker
  comp <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = TRUE), axis_scores)

  # composite = 4축 등가중 평균 (가용 축만; 단 ≥3축 가용 종목만 채택 — composite 신뢰성)
  axis_cols <- names(AXES)
  comp[, n_axis := rowSums(!is.na(.SD)), .SDcols = axis_cols]
  comp[, Score := rowMeans(.SD, na.rm = TRUE), .SDcols = axis_cols]
  comp <- comp[n_axis >= 3L & is.finite(Score), .(Ticker, Score)]
  if (nrow(comp) == 0) next

  comp[, Date := d]
  .factor_list[[i]] <- comp
}
FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# ---- decile sizing: 유니버스 내 상위 10% (high-Quality decile, equal-weight 복제) ----
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

cat(sprintf("[fe_qmj] AFP(2019) QMJ 4-axis composite | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$N, na.rm = TRUE), max(FACTORS$N, na.rm = TRUE)))
