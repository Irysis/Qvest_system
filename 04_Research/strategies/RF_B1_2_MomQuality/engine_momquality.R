# =============================================================================
# engine_momquality.R — RF_B1_2 rulefast 강화 B1-2 (설계 재량 0 — 규칙 그대로)
# =============================================================================
# 규칙 (Q-Lead 블록 지시 원문):
#   신호   = 모멘텀(12-1, t-12~t-2 누적) rank-Z + 수익성(GP/A) rank-Z, 50/50
#   근거   = Jegadeesh & Titman 1993 (모멘텀) + Novy-Marx 2013 JFE 108 (GP/A)
#            https://www.sciencedirect.com/science/article/pii/S0304405X13000044
#   GP/A   = 재무 원천 — factor DB Q01_GPA 를 load_month_factors() 경유(C15)로
#            소비한다 (C4 lag 는 DB 빌더가 보장 — annual 익년 3/31, 분기 고정일).
#   유니버스 = K200∪KQ150 (PIT 시변) + adv20(t-1) >= 2e8 (C10)
#   출력   = FACTORS(Date, Ticker, Score) — 월말 시그널일. 포트 구성(상위 25 EW
#            월간 리밸)은 러너 portfolio_spec 소관.
#
# PIT 구조:
#   - 모멘텀: 시그널월 m 월말 기준, CloseME(m-1)/CloseME(m-12) - 1
#     (최근 1개월 skip — 모든 가격이 시그널일 이전 월말, 미래참조 없음)
#   - adv20: 일별 20일 평균 거래대금을 by-Ticker shift(1) — 시그널일 t-1 까지만
#   - GP/A: load_month_factors(sig_date) — 커넥터가 PIT(expanding IC / C14) 보장
#   - rank-Z: 날짜별 횡단면 표준화 (동일 시그널일 내부 — 시계열 full-sample 아님)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

.FE_GPA_FACTOR <- "Q01_GPA"

# ── connector (C15: parquet 직접 로드 금지 — load_month_factors 경유) ──
local({
  root <- if (exists("PROJECT_ROOT", inherits = TRUE)) PROJECT_ROOT else
    Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", ""))
  conn <- file.path(root, "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

# ── 0. slim copy (원본 RAWDATA 비파괴 — 러너가 이후 시뮬레이션에 재사용) ──
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
setorder(.rd, Ticker, Date)

# ── 1. 월말 시그널 그리드 ──
.rd[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(.rd[, .(Date = max(Date)), by = .ym]$Date)
.rd[, .ym := NULL]
.fdb_min <- as.Date("2003-06-30")   # 12개월 모멘텀 lookback + factor DB 가용 하한 여유
.sig_dates <- .month_ends[.month_ends >= .fdb_min]

# ── 2. 유동성: adv20 = 20일 평균 거래대금, t-1 (C10) ──
.rd[, .TV := Close * Vol]
.rd[, .ADV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.rd[, .ADV20_L1 := shift(.ADV20, 1L, type = "lag"), by = Ticker]

.mem <- .rd[Date %in% .sig_dates & (K200 == TRUE | KQ150 == TRUE) &
              is.finite(.ADV20_L1) & .ADV20_L1 >= 2e8,
            .(Date, Ticker)]
setkey(.mem, Date, Ticker)

# ── 3. 모멘텀 12-1: 월말 종가 패널 → CloseME(m-1)/CloseME(m-12) - 1 ──
.mc <- unique(.rd[Date %in% .month_ends & is.finite(Close) & Close > 0,
                  .(Date, Ticker, Close)], by = c("Date", "Ticker"))
.mc[, ymi := year(Date) * 12L + month(Date)]

.mom <- .mc[, .(Ticker, ymi, Date)]
.mc_l1  <- .mc[, .(Ticker, ymi = ymi + 1L,  C_m1  = Close)]   # m-1 월말 종가
.mc_l12 <- .mc[, .(Ticker, ymi = ymi + 12L, C_m12 = Close)]   # m-12 월말 종가
.mom <- merge(.mom, .mc_l1,  by = c("Ticker", "ymi"))
.mom <- merge(.mom, .mc_l12, by = c("Ticker", "ymi"))
.mom[, Mom := C_m1 / C_m12 - 1]
.mom <- .mom[is.finite(Mom), .(Date, Ticker, Mom)]
setkey(.mom, Date, Ticker)

rm(.mc, .mc_l1, .mc_l12)
.rd[, c(".TV", ".ADV20", ".ADV20_L1") := NULL]
rm(.rd)
gc(verbose = FALSE)

# ── 4. 월별: GP/A 로드 → 유니버스 교차 → rank-Z 50/50 컴포짓 ──
.rankz <- function(x) {
  r <- frank(x, ties.method = "average")
  s <- sd(r)
  if (!is.finite(s) || s < 1e-12) return(rep(0, length(x)))
  (r - mean(r)) / s
}

.factor_list <- vector("list", length(.sig_dates))
for (i in seq_along(.sig_dates)) {
  d <- .sig_dates[i]
  uni <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni) < 30L) next

  fdt <- tryCatch(
    load_month_factors(d, coverage_min = 0.05, factor_names = .FE_GPA_FACTOR),
    error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0L) next
  gpa <- fdt[Factor_Name == .FE_GPA_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, GPA = Z_Score_Aligned)]
  rm(fdt)
  if (nrow(gpa) == 0L) next

  md <- merge(.mom[.(d), .(Ticker, Mom), nomatch = 0L], gpa, by = "Ticker")
  md <- md[Ticker %in% uni & is.finite(Mom) & is.finite(GPA)]
  if (nrow(md) < 30L) next    # 상위 25 선별이 의미를 갖는 최소 횡단면

  md[, Z_Mom := .rankz(Mom)]
  md[, Z_GPA := .rankz(GPA)]
  md[, Score := 0.5 * Z_Mom + 0.5 * Z_GPA]
  md[, Date := d]
  .factor_list[[i]] <- md[is.finite(Score), .(Date, Ticker, Score)]
  if (i %% 24L == 0L) gc(verbose = FALSE)
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
rm(.factor_list, .mom, .mem)
gc(verbose = FALSE)

if (nrow(FACTORS) == 0L) stop("[engine_momquality] FACTORS 0행 — factor DB/유니버스 확인")
cat(sprintf("[engine_momquality] rows=%d | months=%d | %s ~ %s | avg N/month=%.0f\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$Date), max(FACTORS$Date),
            nrow(FACTORS) / uniqueN(FACTORS$Date)))
