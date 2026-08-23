# =============================================================================
# fe_tper_sector_relative.R — Da & Schaumburg (2011, J. Financial Markets 14, 161-192)
#   "Relative Valuation and Analyst Target Price Forecasts" 의 KR 복제 (pg2 큐 title:relativevaluation…)
# =============================================================================
# 논문 구성 (본문 실독 — 2026-08-23 PDF 텍스트 추출, 명시값 그대로):
#   - TPER = TP/P − 1 (컨센서스 평균 12M 목표주가 / 포트 형성일 시장가). 월말 형성, 1개월 보유, 월간 리밸.
#   - 섹터 = GICS 2자리(S&P500 9섹터; 전체 표본은 24 industries 가 더 좋음 = 상대가치 해석).
#   - 섹터 **안에서** TPER 순위로 9그룹(nonile) — Portfolio 1 = 각 섹터 최상위 TPER 종목 = 롱 레그,
#     **동일가중**(EW 가 VW 보다 우수, Table 4). "decile 로 해도 거의 동일".
#   - 결과 1999-01~2005-01(72개월): 롱 레그 134bp/월 · 스프레드 203bp/월(S&P500, 5-factor α).
#   - 절대 TPER 은 무정보(베타 정렬·낙관편향) — 섹터 내 상대 순위만 정보.
# KR 재구성:
#   - TPER = C06_TP_Gap((TP−Close)/Close, factor DB 정렬 z — 원값의 단조변환이라 **섹터 내 순위 동일**).
#     커버리지 없는 종목(TP 결측)은 제외(논문도 TP 보유 종목만).
#   - 섹터 = RAWDATA$Sector(KR 분류; 표본 9 미만 섹터는 'OTHER' 통합 — 9분위가 성립하려면 ≥9 필요, 명시 보충).
#   - 각 섹터 내 TPER 상위 1/9(nonile) 선택 → 전부 EW(동적 N = 선택 종목 수, 유니버스 ~300 이면 ~35).
#     ★Production 25종 상한과 충돌 가능 — 검증 단계는 논문 우선(제1원칙 6), 충돌 명시.
#   - 보충: 논문의 'TP 수집(1~25일) → 형성일 5일 갭' 은 월말 컨센서스 1개 값만 있어 미적용(논문: 갭 없으면
#     공시효과로 더 강함 — 우리 값이 유리한 쪽 편향 가능, 진단 라벨). 유니버스 K200∪KQ150 ∧ 유동성 2e8. 기간 2005~.
# ===== PIT (C1~C15) =====
#   - C06 = load_month_factors(d) PIT z(Usable_Date ≤ sig_date, C14/C15). 섹터 = 당일 RAWDATA 값.
#   - 월별 횡단면만(C1), 미래 정보 없음(C2), NEGATE 없음(C13).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", getwd()),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

F_TPER     <- "C06_TP_Gap"
N_GROUPS   <- 9L          # 논문: 섹터 내 9그룹, Portfolio 1 = 최상위
MIN_SECTOR <- 9L          # 9분위 성립 최소 표본(미만은 OTHER 통합)

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-06-01")]

RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.panel <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                    !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                  .(Date, Ticker, Sector = as.character(Sector))]
RAWDATA[, c(".TV", ".AvgTV20") := NULL]
setkey(.panel, Date, Ticker)

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  pd <- .panel[.(d), nomatch = 0L]
  if (nrow(pd) < 30L) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = F_TPER), error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) next
  z <- fdt[Factor_Name == F_TPER & is.finite(Z_Score_Aligned), .(Ticker, TPER = Z_Score_Aligned)]
  pd <- merge(pd, z, by = "Ticker")                 # TP 보유 종목만
  if (nrow(pd) < 30L) next
  pd[is.na(Sector) | Sector == "", Sector := "OTHER"]
  pd[, .nsec := .N, by = Sector]
  pd[.nsec < MIN_SECTOR, Sector := "OTHER"]
  pd[, .nsec := NULL]
  # 섹터 내 TPER 상위 1/9 = Portfolio 1 (높을수록 상위)
  pd[, .pct := (frank(-TPER, ties.method = "first") - 0.5) / .N, by = Sector]
  keep <- pd[.pct <= 1 / N_GROUPS]
  if (nrow(keep) < 5L) next
  out <- keep[, .(Date = d, Ticker, Score = -.pct)]   # 순위용(동일 선택 집합 내)
  out[, N := .N]
  .factor_list[[i]] <- out
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
if (!nrow(FACTORS)) stop("[fe_tper_sector_relative] FACTORS 0 rows")

cat(sprintf("[fe_tper_sector_relative] Da-Schaumburg(2011) KR: 섹터 내 TPER(C06) 상위 1/9 EW 월간 | FACTORS rows=%d | signal months=%d | N range=%d~%d (median %d)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$N), max(FACTORS$N), as.integer(median(FACTORS$N))))
