# =============================================================================
# fe_b3_13_smallcap.R — 규칙기반 고속강화 B3-13 (rulefast 13/20)
#   신호·비중 = B1-5 승자 완전 그대로:
#     모멘텀(12-1) rank-Z 50% + 비유동성(Amihud L01) rank-Z 50% → long-only top-25 EW
#   ★바꾸는 것 = 적용 유니버스 하나뿐:
#     K200∪KQ150 멤버십  →  거래 가능 전 종목 중 시가총액 하위 1/3 (매 리밸일 횡단면)
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=13
# 근거 논문 (하드코딩 금지 — 수치 결정 뿌리):
#   - 규모 효과: Banz (1981, JFE 9(1)) "The relationship between return and market
#     value of common stocks"
#     https://www.sciencedirect.com/science/article/abs/pii/0304405X81900180
#     소형주 포트폴리오가 대형주 대비 위험조정 초과수익. 분할 기준 = 시가총액 횡단면 분위.
#   - 모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#     https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#   - 비유동성 프리미엄: Amihud (2002, JFM 5(1))
#     https://www.sciencedirect.com/science/article/pii/S1386418101000246
#
# ★필터 순서 (만다트 고정): 유동성 하한 adv20>=2e8(t-1) **먼저** → 통과 집합의
#   횡단면에서 Size 하위 1/3. 즉 "실투 가능 집합 안에서의 소형주"이지
#   "소형주 중 실투 가능한 것"이 아니다. 두 순서는 집합이 다르다.
#
# 시장 구분(KOSPI/KOSDAQ) 미적용 — 이 셀은 크기 축 단독 효과를 본다.
#
# ===== PIT (C1~C15) =====
#   - C1(급소): 시총 임계 = **그 달 횡단면 분위**(by = Date 내 quantile). 전 표본
#     분위·고정 임계값 없음. 임계 자체가 시변한다.
#   - C6(생존편향): RAWDATA 원장은 상장폐지 종목을 보유(2005 이후 최종관측 소멸
#     718종). 유니버스는 각 시점 관측 종목에서만 구성 — 미래 생존자 명부 참조 없음.
#   - C10: adv20 = frollmean(20) 후 shift(1) — 시그널일 당일 거래대금 미포함.
#   - C2: Size 도 shift(1) 사용(전일 시총) — 시그널일 종가 동일시점 참조 회피.
#     모멘텀 = shift(21)/shift(252) 과거 윈도우만.
#   - C15: Amihud 는 factor DB parquet 직접 load 금지 — load_month_factors() 경유.
#   - C13/C14: Z_Score_Aligned 만 소비. NEGATE/FLIP 없음.
# =============================================================================

suppressPackageStartupMessages(library(data.table))
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                               "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

ILLIQ_FACTOR <- "L01_Amihud"   # B1-5 와 동일 (L09 는 방향 반전으로 배제)
SIZE_FRAC    <- 1/3            # Banz(1981) 규모 분위 — 만다트 고정 하위 1/3

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-11-01")]

# ---- 유동성 adv20 >= 2e8 (C10: t-1) + 전일 시총 (C2: t-1) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
RAWDATA[, .SizeLag := shift(Size, 1L), by = Ticker]

# ── ①유동성 하한 통과 집합 (지수 멤버십 무관 = 거래 가능 전 종목) ──
.liq <- RAWDATA[Date %in% .month_ends &
                  is.finite(.AvgTV20) & .AvgTV20 >= 2e8 &
                  is.finite(.SizeLag) & .SizeLag > 0,
                .(Date, Ticker, SizeLag = .SizeLag)]

# ── ②그 집합의 **그 달 횡단면**에서 Size 하위 1/3 (C1 — 시변 임계) ──
.liq[, .thr := quantile(SizeLag, SIZE_FRAC, na.rm = TRUE, type = 7), by = Date]
.mem <- .liq[SizeLag <= .thr, .(Date, Ticker)]
setkey(.mem, Date, Ticker)

# ── 유니버스 실측 진단 (만다트 보고 항목) ──
.uni_diag <- .liq[, .(n_liq = .N,
                      thr = .thr[1],
                      n_small = sum(SizeLag <= .thr),
                      med_size_small = median(SizeLag[SizeLag <= .thr]),
                      med_size_liq = median(SizeLag)), by = Date]

# ---- 모멘텀 12-1 (JT1993) ----
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
RAWDATA[, c(".TV", ".AvgTV20", ".SizeLag", ".Mom") := NULL]
setkey(.mom_all, Date, Ticker)

# ---- rank-Z (B1-5 와 동일) ----
.rank_z <- function(x) {
  r <- frank(x, ties.method = "average", na.last = "keep")
  mu <- mean(r, na.rm = TRUE); s <- sd(r, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mu) / s
}

.factor_list <- vector("list", length(.month_ends))
.score_n <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05,
                                     factor_names = ILLIQ_FACTOR),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  ilq <- fdt[Factor_Name == ILLIQ_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, Ilq = Z_Score_Aligned)]
  ilq <- ilq[Ticker %in% uni_tk]
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L][Ticker %in% uni_tk]

  cmb <- merge(ilq, mom, by = "Ticker")
  if (nrow(cmb) < 30L) next
  cmb[, Zm := .rank_z(Mom)]
  cmb[, Zi := .rank_z(Ilq)]
  cmb <- cmb[is.finite(Zm) & is.finite(Zi)]
  if (nrow(cmb) < 30L) next
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]   # 50/50 (B1-5 그대로)
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
  .score_n[[i]] <- data.table(Date = d, n_uni = length(uni_tk), n_scored = nrow(cmb))
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# ---- 진단 저장 ----
.sn <- rbindlist(Filter(Negate(is.null), .score_n), use.names = TRUE)
.ud <- merge(.uni_diag, .sn, by = "Date", all.y = TRUE)
saveRDS(.ud, file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
        "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
        "04_Research/strategies/RF_B3_13_SmallCap/universe_diag.rds"))

cat(sprintf("[fe_b3_13][universe] adv20-pass median n=%d | smallcap(bottom 1/3) median n=%d | scored median n=%d | months=%d | 25종 미달 월=%d\n",
            as.integer(median(.ud$n_liq, na.rm = TRUE)),
            as.integer(median(.ud$n_small, na.rm = TRUE)),
            as.integer(median(.ud$n_scored)), nrow(.ud),
            sum(.ud$n_scored < 25L)))
cat(sprintf("[fe_b3_13][universe] median 시총 — smallcap %.0f억 vs adv20-pass 전체 %.0f억 (배수 %.3f) | 임계 median %.0f억\n",
            median(.ud$med_size_small, na.rm = TRUE) / 1e8,
            median(.ud$med_size_liq, na.rm = TRUE) / 1e8,
            median(.ud$med_size_small, na.rm = TRUE) / median(.ud$med_size_liq, na.rm = TRUE),
            median(.ud$thr, na.rm = TRUE) / 1e8))
cat(sprintf("[fe_b3_13] Mom(12-1) rankZ + %s rankZ 50/50 | FACTORS rows=%d | months=%d | tickers=%d\n",
            ILLIQ_FACTOR, nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
