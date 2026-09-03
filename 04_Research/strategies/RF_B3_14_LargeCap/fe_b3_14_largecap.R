# =============================================================================
# fe_b3_14_largecap.R — 규칙기반 고속강화 B3-14 (rulefast 14/20)
#   신호·비중 = B1-5 승자(RF_B1_5_MomIlliq) 완전 그대로.
#   바꾸는 것 = 적용 유니버스 하나뿐 — 시가총액 상위 1/3 밴드(시변).
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=14
# 대조 셀: B3-13(소형주 = 하위 밴드). 두 셀이 함께 크기 축의 부호·단조성을 판정한다.
#
# 근거 논문 (하드코딩 금지 — 수치 결정 뿌리):
#   - 크기 효과(size effect): Banz (1981, JFE 9(1)) "The relationship between return
#     and market value of common stocks"
#     https://www.sciencedirect.com/science/article/abs/pii/0304405X81900180
#     → 소형주 초과수익. 본 셀은 그 **반대 밴드(대형주)** 를 재는 대조군이다.
#   - 모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#     https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#   - 비유동성 프리미엄: Amihud (2002, JFM 5(1))
#     https://www.sciencedirect.com/science/article/pii/S1386418101000246
#
# Amihud 코드 선택 = L01_Amihud — B1-5 와 동일(사전 실측 진단 2026-08-29:
#   L01 은 PIT expanding IC 부호가 전 구간 +1, L09_Amihud_20d 는 2012년경 방향 반전).
#
# ===== 유니버스 필터 순서 (고정 — B3-13 과 동일해야 대조 성립) =====
#   ① K200 ∪ KQ150 멤버십 (PIT 시변, 시장 구분 없이 합집합)
#   ② 유동성 하한: adv20 = 20일 평균 거래대금 >= 2e8, t-1 기준 (C10)
#   ③ ②를 통과한 집합 **안에서** 그 리밸일의 횡단면 Size 상위 1/3 (시변 분위 — C1)
#   ★ 순서 = "하한 적용 후 상위 1/3". 고정 임계(예: 시총 1조 이상) 금지.
#
# ===== PIT (C1~C15) =====
#   - C1: Size 컷은 매 리밸일 cross-section 분위(quantile 2/3)로만 — full-sample
#     통계·고정 임계 없음. rank-Z 도 sig_date 시점 횡단면 내부에서만.
#   - C2: 모멘텀 = shift(21)/shift(252) 과거 윈도우만. Size 는 시그널일 종가 기준
#     시가총액(그 시점 관측 가능) 이며 체결은 익영업일(get_execution_date) — 순환참조 없음.
#   - C10: adv20 은 frollmean(20) 후 shift(1) — 시그널일 당일 거래대금 미포함.
#   - C13/C14: Z_Score_Aligned 만 소비. NEGATE/FLIP 없음.
#   - C15: Amihud 는 parquet 직접 load 금지 — load_month_factors() 경유.
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

ILLIQ_FACTOR <- "L01_Amihud"   # B1-5 와 동일 (방향 반전 없는 코드)
SIZE_BAND    <- "top_tertile"  # 상위 1/3 — 대조 셀 B3-13 = bottom_tertile

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-11-01")]

# ---- 필터 ①② : K200∪KQ150 멤버십 + adv20 >= 2e8 (C10: t-1) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
.base <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                   is.finite(.AvgTV20) & .AvgTV20 >= 2e8 & is.finite(Size) & Size > 0,
                 .(Date, Ticker, Size)]
setkey(.base, Date, Ticker)

# ---- 모멘텀 12-1 (JT1993) ----
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
RAWDATA[, c(".TV", ".AvgTV20", ".Mom") := NULL]
setkey(.mom_all, Date, Ticker)

.rank_z <- function(x) {
  r <- frank(x, ties.method = "average", na.last = "keep")
  mu <- mean(r, na.rm = TRUE); s <- sd(r, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mu) / s
}

.factor_list <- vector("list", length(.month_ends))
.uni_diag    <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  bs <- .base[.(d), .(Ticker, Size), nomatch = 0L]      # 기준선(B1-5) 유니버스
  if (nrow(bs) < 30L) next

  # ---- 필터 ③ : 그 달 횡단면 Size 상위 1/3 (시변 분위 — C1) ----
  cut_hi <- as.numeric(quantile(bs$Size, probs = 2/3, na.rm = TRUE, type = 7))
  band <- bs[Size >= cut_hi]
  uni_tk <- band$Ticker
  if (length(uni_tk) < 30L) next

  .uni_diag[[i]] <- data.table(
    Date = d, n_base = nrow(bs), n_uni = nrow(band),
    med_size_base = median(bs$Size), med_size_uni = median(band$Size),
    cut_hi = cut_hi)

  # Amihud — C15 경유, Z_Score_Aligned 만 (C13/C14)
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05,
                                     factor_names = ILLIQ_FACTOR),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  ilq <- fdt[Factor_Name == ILLIQ_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, Ilq = Z_Score_Aligned)][Ticker %in% uni_tk]
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L][Ticker %in% uni_tk]

  cmb <- merge(ilq, mom, by = "Ticker")
  if (nrow(cmb) < 30L) next
  cmb[, Zm := .rank_z(Mom)]
  cmb[, Zi := .rank_z(Ilq)]
  cmb <- cmb[is.finite(Zm) & is.finite(Zi)]
  if (nrow(cmb) < 30L) next
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]   # B1-5 그대로 (50/50 고정)
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

.ud <- rbindlist(Filter(Negate(is.null), .uni_diag), use.names = TRUE)
if (nrow(.ud)) {
  cat(sprintf("[fe_b3_14][UNIV-diag] 필터순서 ①K200∪KQ150 → ②adv20>=2e8(t-1) → ③횡단면 Size 상위 1/3\n"))
  cat(sprintf("[fe_b3_14][UNIV-diag] months=%d | n_base median %d → n_uni median %d (비율 %.2f)\n",
              nrow(.ud), as.integer(median(.ud$n_base)), as.integer(median(.ud$n_uni)),
              median(.ud$n_uni / .ud$n_base)))
  cat(sprintf("[fe_b3_14][UNIV-diag] median mktcap: base %.3e KRW | 상위1/3 %.3e KRW (배수 %.2fx) | 컷 median %.3e KRW\n",
              median(.ud$med_size_base), median(.ud$med_size_uni),
              median(.ud$med_size_uni) / median(.ud$med_size_base), median(.ud$cut_hi)))
  saveRDS(.ud, file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
          "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
          "04_Research/strategies/RF_B3_14_LargeCap/univ_diag.rds"))
}

cat(sprintf("[fe_b3_14] Mom(12-1) rankZ + %s rankZ 50/50 | band=%s | FACTORS rows=%d | months=%d | tickers=%d\n",
            ILLIQ_FACTOR, SIZE_BAND, nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
