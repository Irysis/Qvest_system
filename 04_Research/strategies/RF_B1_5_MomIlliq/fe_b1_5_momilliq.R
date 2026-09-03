# =============================================================================
# fe_b1_5_momilliq.R — 규칙기반 고속강화 B1-5 (rulefast 5/20)
#   모멘텀(12-1) rank-Z 50% + 비유동성(Amihud) rank-Z 50% → long-only top-25 EW
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=5
# 근거 논문 (하드코딩 금지 — 수치 결정 뿌리):
#   - 모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#     https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#   - 비유동성 프리미엄: Amihud (2002, JFM 5(1)) "Illiquidity and Stock Returns"
#     https://www.sciencedirect.com/science/article/pii/S1386418101000246
#     ILLIQ = 평균(|일수익| / 거래대금). 비유동성 높을수록 기대수익 높음(프리미엄 방향).
#
# Amihud 코드 선택 = L01_Amihud (사전 실측 진단, 2026-08-29):
#   - L01_Amihud: PIT expanding IC 부호 전 구간 +1 (2005~2025) →
#     Z_Score_Aligned 고득점 = 비유동 = 만다트 프리미엄 방향과 전 구간 일치.
#     원전(연 단위 평균 창) 정의와도 20일 창보다 정합.
#   - L09_Amihud_20d: expanding IC 부호가 2012년경 +1→-1 반전 → Z_Score_Aligned
#     소비 시 백테스트 중간에 방향이 뒤집혀 만다트(고정 프리미엄 방향) 위반.
#     수동 재반전은 C13(FLIP_SIGN 금지) 위반이므로 채택 불가.
#
# ===== PIT (C1~C15) =====
#   - C15: Amihud 는 factor DB parquet 직접 load 금지 — load_month_factors() 경유.
#   - C14/C13: Z_Score_Aligned 만 소비(방향 = Usable_Date<=sig_date expanding IC).
#     NEGATE/FLIP 없음.
#   - C10: 유동성 필터 adv20 은 t-1 기준 — frollmean(20) 후 shift(1) (시그널일
#     당일 거래대금 미포함).
#   - C2: 모멘텀 = shift(21)/shift(252) 과거 윈도우만, 동일시점 순환참조 없음.
#   - C1: rank-Z 는 sig_date 시점 cross-section 내에서만 (full-sample 통계 없음).
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

ILLIQ_FACTOR <- "L01_Amihud"   # 선택 근거 상단 헤더 — L09 는 방향 반전으로 배제

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-11-01")]  # start 2005-01 대비 여유

# ---- K200∪KQ150 멤버십 + 유동성 adv20 >= 2e8 (C10: t-1, shift 1) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  is.finite(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
setkey(.mem, Date, Ticker)

# ---- 모멘텀 12-1 (JT1993): 과거 12개월 누적, 최근 1개월 제외 — 과거 윈도우만 ----
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
RAWDATA[, c(".TV", ".AvgTV20", ".Mom") := NULL]
setkey(.mom_all, Date, Ticker)

# ---- rank-Z: cross-section 내 rank(ties=average) → z-score of ranks ----
.rank_z <- function(x) {
  r <- frank(x, ties.method = "average", na.last = "keep")
  mu <- mean(r, na.rm = TRUE); s <- sd(r, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mu) / s
}

.factor_list <- vector("list", length(.month_ends))
.iqr_diag <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  # Amihud — C15: load_month_factors 경유, Z_Score_Aligned 만 (C13/C14)
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05,
                                     factor_names = ILLIQ_FACTOR),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  ilq <- fdt[Factor_Name == ILLIQ_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, Ilq = Z_Score_Aligned)]

  # ---- 유니버스 내 Amihud 잔존 분산 진단 (만다트 보고 항목) ----
  #   full-panel IQR vs adv20-유니버스 내 IQR (같은 달, 같은 aligned-Z 스케일)
  .iqr_full <- IQR(ilq$Ilq, na.rm = TRUE)
  .iqr_uni  <- IQR(ilq[Ticker %in% uni_tk, Ilq], na.rm = TRUE)
  .iqr_diag[[i]] <- data.table(Date = d, iqr_full = .iqr_full, iqr_uni = .iqr_uni,
                               n_uni = sum(ilq$Ticker %in% uni_tk))

  ilq <- ilq[Ticker %in% uni_tk]
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L][Ticker %in% uni_tk]

  cmb <- merge(ilq, mom, by = "Ticker")
  if (nrow(cmb) < 30L) next
  cmb[, Zm := .rank_z(Mom)]
  cmb[, Zi := .rank_z(Ilq)]
  cmb <- cmb[is.finite(Zm) & is.finite(Zi)]
  if (nrow(cmb) < 30L) next
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]   # 50/50 (만다트 고정)
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

.iqr_dt <- rbindlist(Filter(Negate(is.null), .iqr_diag), use.names = TRUE)
if (nrow(.iqr_dt)) {
  cat(sprintf("[fe_b1_5][IQR-diag] %s aligned-Z IQR — full-panel median %.3f | adv20-universe median %.3f (잔존율 %.0f%%) | universe n median %d\n",
              ILLIQ_FACTOR, median(.iqr_dt$iqr_full), median(.iqr_dt$iqr_uni),
              100 * median(.iqr_dt$iqr_uni / .iqr_dt$iqr_full),
              as.integer(median(.iqr_dt$n_uni))))
  saveRDS(.iqr_dt, file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
          "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
          "04_Research/strategies/RF_B1_5_MomIlliq/iqr_diag.rds"))
}

cat(sprintf("[fe_b1_5] Mom(12-1) rankZ + %s rankZ 50/50 | FACTORS rows=%d | months=%d | tickers=%d\n",
            ILLIQ_FACTOR, nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
