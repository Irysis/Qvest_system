# =============================================================================
# fe_scibeta_defensive.R — Scientific Beta "Defensive Equity Investing Without the
#   Implicit Bets" (Aguet & Cady, white paper 2025-09) 의 KR 복제
# =============================================================================
# 논문 구성 (명시값 그대로):
#   ① 변동성 = 과거 2년 주간수익률 표준편차(모델-프리).
#   ② 섹터별 선별: 각 경제 섹터 안에서 변동성 하위 30% 선택 → 그중 valuation/quality 가 나쁜
#      1/3 제거(HFI 다중팩터 점수 = value·momentum·volatility·investment·profitability 하위 제거)
#      ⇒ 섹터당 20% 를 선택(Exhibit 5).
#   ③ 가중: Efficient Minimum Volatility 최적화(강건 공분산 + 탈집중 제약).
#   ④ 지역 중립 결합 — KR 단일시장이라 해당 없음(명시).
# 보충(논문 미명시 또는 시스템 표준):
#   - 유니버스 K200∪KQ150(PIT 시변) ∧ 유동성 2e8. 섹터 = RAWDATA$Sector(KR 분류; 표본 5종 미만
#     섹터는 'OTHER' 로 통합 — 논문은 10 경제섹터, 여기선 KR 분류를 그대로 씀: 명시 보충).
#   - 주간 변동성 ≈ 일간 로그수익률 504 거래일 sd × sqrt(5) (iid 하 순위 동일; 명시 보충).
#   - HFI 점수 = 5축 동일가중 z 평균: value=V01_BM · momentum=12-1 가격 · volatility=−vol ·
#     investment=Q06_Asset_Growth · profitability=Q01_GPA (factor DB 정렬 z = 높을수록 좋음, C13/C14).
#   - 가중 = run_alpha_search weight_method="minvar" (Ledoit-Wolf 수축, 상한 0.15 = 시스템 탈집중
#     제약; 논문의 '강건 공분산 + 탈집중' 에 대응). 리밸 = 월간(시스템 표준; 논문 분기 갱신).
#   - 종목수 = 섹터당 20% 합 ⇒ 유니버스 ~350 기준 ~60~70 종목. ★Production 25종 상한과 충돌 —
#     검증 단계는 논문 우선(제1원칙 6), 충돌 명시. FACTORS$N 으로 일자별 동적 N 전달.
#
# ===== PIT (C1~C15) =====
#   - vol/모멘텀: 과거 윈도우 shift/rolling 만(C2). 팩터 z: load_month_factors(d) PIT(C14/C15).
#   - 섹터/멤버십: RAWDATA[Date==d] 당일 값(과거 정보). full-sample 통계 없음(C1).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", getwd()),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

VOL_DAYS   <- 504L        # 2년 (≈ 104주)
SEL_LOWVOL <- 0.30        # 섹터 내 변동성 하위 30%
DROP_HFI   <- 1/3         # 그중 HFI 하위 1/3 제거 → 20%
MIN_SECTOR <- 5L          # 섹터 최소 표본(미만은 OTHER 통합)
F_VALUE <- "V01_BM"; F_INV <- "Q06_Asset_Growth"; F_PROF <- "Q01_GPA"

# ---- 일간 로그수익률 → 2년 변동성(주간 환산), 12-1 모멘텀 ----
RAWDATA[, .lr := log(Close / shift(Close, 1L)), by = Ticker]
# 롤링 sd 를 벡터화(E[x²]−E[x]²; frollapply(sd) 는 1,400만 행에서 수십 분) — 순위 동일
RAWDATA[, .m1 := frollmean(.lr, VOL_DAYS, align = "right"), by = Ticker]
RAWDATA[, .m2 := frollmean(.lr^2, VOL_DAYS, align = "right"), by = Ticker]
RAWDATA[, .vol := sqrt(pmax(.m2 - .m1^2, 0)) * sqrt(5)]
RAWDATA[, c(".m1", ".m2") := NULL]
RAWDATA[, .mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")
.month_ends <- .month_ends[.month_ends >= .fdb_min]

.panel <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                    !is.na(.AvgTV20) & .AvgTV20 >= 2e8 & is.finite(.vol) & .vol > 0,
                  .(Date, Ticker, Sector = as.character(Sector), Vol = .vol, Mom = .mom)]
RAWDATA[, c(".lr", ".vol", ".mom", ".TV", ".AvgTV20") := NULL]
setkey(.panel, Date, Ticker)

.zsc <- function(x) {
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(0, length(x)))
  z <- (x - mu) / s; z[!is.finite(z)] <- 0; z
}

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  pd <- .panel[.(d), nomatch = 0L]
  if (nrow(pd) < 30L) next
  pd[is.na(Sector) | Sector == "", Sector := "OTHER"]
  pd[, .nsec := .N, by = Sector]
  pd[.nsec < MIN_SECTOR, Sector := "OTHER"]
  pd[, .nsec := NULL]

  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05,
                                     factor_names = c(F_VALUE, F_INV, F_PROF)),
                  error = function(e) NULL)
  if (!is.null(fdt) && nrow(fdt)) {
    w <- dcast(fdt[is.finite(Z_Score_Aligned)], Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    pd <- merge(pd, w, by = "Ticker", all.x = TRUE)
  }
  for (f in c(F_VALUE, F_INV, F_PROF)) if (!(f %in% names(pd))) pd[, (f) := NA_real_]

  # ② 섹터 내 변동성 하위 30% 선택
  pd[, .vrank := frank(Vol, ties.method = "first") / .N, by = Sector]
  sel <- pd[.vrank <= SEL_LOWVOL]
  if (nrow(sel) < 10L) next

  # HFI 다중팩터 점수(5축 z 평균: value · momentum · volatility(−vol) · investment · profitability)
  sel[, z_val := .zsc(get(F_VALUE))]
  sel[, z_mom := .zsc(Mom)]
  sel[, z_vol := .zsc(-Vol)]
  sel[, z_inv := .zsc(get(F_INV))]
  sel[, z_prf := .zsc(get(F_PROF))]
  sel[, HFI := (z_val + z_mom + z_vol + z_inv + z_prf) / 5]
  # 섹터 내 HFI 하위 1/3 제거 → 섹터당 20%
  sel[, .hrank := frank(HFI, ties.method = "first") / .N, by = Sector]
  keep <- sel[.hrank > DROP_HFI]
  if (nrow(keep) < 10L) next

  # Score = 변동성 낮을수록 높음(선별된 집합 내 순위 용) · N = 선별 종목 수(동적 N → minvar 가중)
  out <- keep[, .(Date = d, Ticker, Score = -Vol)]
  out[, N := .N]
  .factor_list[[i]] <- out
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
if (!nrow(FACTORS)) stop("[fe_scibeta_defensive] FACTORS 0 rows")

cat(sprintf("[fe_scibeta_defensive] SciBeta Defensive Equity KR 복제: 섹터내 저변동 30%% → HFI 하위 1/3 제거 → 섹터당 20%% · minvar 가중 | FACTORS rows=%d | signal months=%d | N range=%d~%d (median %d)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$N), max(FACTORS$N), as.integer(median(FACTORS$N))))
