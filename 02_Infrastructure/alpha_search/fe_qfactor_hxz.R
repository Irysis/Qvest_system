# =============================================================================
# fe_qfactor_hxz.R — Hou-Xue-Zhang (2015, RFS) q-factor 복제 (long-only)
# =============================================================================
# 논문: Hou, Xue, Zhang (2015) "Digesting Anomalies: An Investment Approach",
#       Review of Financial Studies 28(3):650-705. q-factor 모형 = market + size
#       + **investment(I/A)** + **profitability(ROE)** 4-factor. 핵심 알파 두 다리:
#         · investment leg  : 저 investment(낮은 I/A 자산성장) = 고 기대수익
#         · profitability leg: 고 ROE(수익성)                 = 고 기대수익
#       원논문은 2x3x3 sort 후 long high-ROE/low-I·A ∩ short low-ROE/high-I·A 의
#       factor-mimicking long-short. KR long-only이므로 short leg 제거 →
#       **고 ROE ∧ 저 investment 결합 score 상위 long-only, equal-weight, 월간 리밸**.
#
# ★ 논문 완전 복제 (alpha-search 제1원칙):
#   - 시그널 = 2개 다리 동일가중 결합(논문 정신: I/A와 ROE 두 차원 대칭).
#       investment leg   = IN06_Investment_to_Assets  (HXZ I/A = (dPPE+dInv)/lag TA)
#       profitability leg = Q02_ROE                    (HXZ ROE = NetIncome/TotalEquity)
#     Score = 0.5*z(investment leg) + 0.5*z(profitability leg). 두 다리 동일가중.
#     ★ 두 차원이 곧 HXZ 가설의 본질 — 단일 팩터가 아닌 investment+profitability *결합*.
#   - 방향 처리(C13 NEGATE/FLIP 금지): factor DB registry 정의상
#       IN06 = "Negate (dPPE+dInv)/lag TA. Low investment = better" → direction higher_better
#       Q02_ROE = NetIncome/TotalEquity                            → direction higher_better
#     둘 다 Z_Score_Aligned가 IC-direction으로 "높을수록 기대수익↑"로 이미 정렬(connector).
#     즉 저-I/A·고-ROE = 고 Z_Aligned. 수동 부호반전 없음(alignment 자동, C13 안전).
#   - ★ 두 다리 모두 가용한 종목만 채택(complete-case). q-factor 정의상 두 차원 동시 필요
#     (한 다리만 있는 종목은 HXZ q-factor 시그널이 아님 — composite 신뢰성).
#   - 포트폴리오: 결합 score 상위 **decile**(상위 10%), **equal-weight**(논문 그대로).
#       FACTORS$N = ceil(n_eligible/10) per month → run_monthly_simulation top-decile (weight="equal").
#   - 리밸런싱: 월간 (논문은 연간 ROE/투자 재정렬 + 월간 ROE 업데이트 — KR factor DB 월간 갱신
#     표준 → 월간, 명시 보충). size는 universe 고정(K200∪KQ150 = 대형)이라 명시 생략(도훈 mandate).
#   - 유니버스: run_alpha_search universe="ALL"(엔진은 ALL로 호출, 본 엔진 내부서 K200∪KQ150 직접 적용
#     해 decile 분모 정합 — fe_qmj/fe_qualitygp 동일 골격).
#
# ===== PIT (C13/C14/C15) =====
#   - load_month_factors(sig_date): Z_Score_Aligned는 Usable_Date<=sig_date IC로 방향정렬(C14),
#     재무 PIT(분기 45일 / 연간 5월 lag)는 factor DB 빌드 단계에서 이미 반영(IN06/Q02 = quarterly).
#   - 동일시점 순환참조 없음(각 월말 시점 factor DB 스냅샷만). NEGATE/FLIP 없음(C13, alignment 처리).
#   - 외부 parquet/cache 의존 없음(load_month_factors 경유, C15) → detect_lookahead 사각 아님(fe_ml류 X).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- factor DB connector (load_month_factors, C15 경유) ----
local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

# ---- HXZ q-factor 2 legs (동일가중 결합) ----
LEG_INVEST <- "IN06_Investment_to_Assets"   # 저 I/A = 고 기대수익 (registry: Low investment = better)
LEG_PROFIT <- "Q02_ROE"                     # 고 ROE = 고 기대수익
Q_FACTORS  <- c(LEG_INVEST, LEG_PROFIT)

# ---- 월말 시그널 날짜 (각 달 마지막 거래일) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]

# factor DB 재무 가용 구간 (2002-08~). start_date는 run_qfactor_paper에서 추가 제한(2005~).
.fdb_min <- as.Date("2002-08-01")
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# ---- 유니버스: K200 ∪ KQ150 멤버십 + 유동성 2e8 (decile 분모 정합 위해 엔진 내부 적용) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]   # PIT 우측정렬(과거 윈도우)
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
RAWDATA[, c(".TV", ".AvgTV20") := NULL]
setkey(.mem, Date, Ticker)

# ---- 각 월말: 2 leg Z_Score_Aligned → 동일가중 결합 score (complete-case) ----
.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  fdt <- fdt[Factor_Name %in% Q_FACTORS & is.finite(Z_Score_Aligned), .(Ticker, Factor_Name, Z_Score_Aligned)]
  if (nrow(fdt) == 0) next

  # 유니버스 교집합 (K200/KQ150 ∩ 유동성)
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  fdt <- fdt[Ticker %in% uni_tk]
  if (nrow(fdt) == 0) next

  # long→wide: 종목별 두 leg Z
  w <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  # 두 다리 모두 가용한 종목만 (HXZ q-factor = investment ∧ profitability 동시)
  if (!all(Q_FACTORS %in% names(w))) next
  w <- w[is.finite(get(LEG_INVEST)) & is.finite(get(LEG_PROFIT))]
  if (nrow(w) == 0) next

  # 결합 score = 0.5*z(investment) + 0.5*z(profitability) (두 다리 동일가중)
  w[, Score := 0.5 * get(LEG_INVEST) + 0.5 * get(LEG_PROFIT)]
  comp <- w[is.finite(Score), .(Ticker, Score)]
  if (nrow(comp) == 0) next

  comp[, Date := d]
  .factor_list[[i]] <- comp
}
FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# ---- decile sizing: 유니버스 내 상위 10% (high q-score decile, equal-weight 복제) ----
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

cat(sprintf("[fe_qfactor_hxz] HXZ(2015) q-factor (invest=%s + profit=%s, 동일가중) | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            LEG_INVEST, LEG_PROFIT, nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$N, na.rm = TRUE), max(FACTORS$N, na.rm = TRUE)))
