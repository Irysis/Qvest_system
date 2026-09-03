# =============================================================================
# fe_b2_7_rankweight.R — 규칙기반 고속강화 B2-7 (rulefast 7/20)
#   신호 = B1-5 승자 그대로: 모멘텀(12-1) rank-Z 50% + 비유동성(Amihud) rank-Z 50%
#   비중 = 랭크 선형 가중 w_i ∝ (26 − rank_i), 상위 25종, Σw = 1  ← 유일한 변경점
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=7
#
# ── 근거 논문 (하드코딩 금지 — 수치 결정 뿌리) ──
#   [신호] B1-5 에서 그대로 이식 (재설계 없음)
#     - 모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#       https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#     - 비유동성 프리미엄: Amihud (2002, JFM 5(1))
#       https://www.sciencedirect.com/science/article/pii/S1386418101000246
#   [비중] Asness, Moskowitz & Pedersen (2013, JF 68(3)) "Value and Momentum Everywhere"
#       https://onlinelibrary.wiley.com/doi/10.1111/jofi.12021
#       rank-weighted 구성: 비중을 신호의 횡단면 *순위*에 선형 비례시킨다.
#       원전은 rank − mean(rank) 형태의 롱숏 비중이며, 본 시도는 만다트에 따라
#       long-only 상위 25종 절단판 w_i ∝ (26 − rank_i) (rank 1 = 최고 점수) 로 쓴다.
#
# ── 왜 이 셀인가 (B2-6 스코어 틸트의 순서통계 판) ──
#   틸트(Score 크기 비례)는 스코어의 스케일과 꼬리에 민감하다. 랭크 가중은 같은
#   방향의 집중(상위 과중)을 주되 스코어 *크기* 정보를 전부 버리고 *순위*만 쓴다.
#   두 셀 대조가 "스코어 크기 정보가 값을 하는가"를 판별한다.
#   결정론적 비중 벡터: w_1 = 25/325 = 7.692% … w_25 = 1/325 = 0.3077%.
#
# ===== PIT (C1~C15) — B1-5 와 동일, 비중 변경은 PIT 축을 건드리지 않는다 =====
#   - C15: Amihud 는 factor DB parquet 직접 load 금지 — load_month_factors() 경유.
#   - C14/C13: Z_Score_Aligned 만 소비(방향 = Usable_Date<=sig_date expanding IC).
#     NEGATE/FLIP 없음.
#   - C10: 유동성 필터 adv20 은 t-1 기준 — frollmean(20) 후 shift(1) (시그널일
#     당일 거래대금 미포함).
#   - C2: 모멘텀 = shift(21)/shift(252) 과거 윈도우만, 동일시점 순환참조 없음.
#   - C1: rank-Z 와 비중 랭크는 sig_date 시점 cross-section 내에서만
#     (full-sample 통계 없음). 비중은 당월 점수 순위의 결정론적 함수 —
#     미래 수익 정보가 비중 산출에 들어가지 않는다.
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

ILLIQ_FACTOR <- "L01_Amihud"   # B1-5 선택 그대로 (L09 는 방향 반전으로 배제)
N_HOLD <- 25L                  # 만다트 상한 (실투형 축)

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

.pf_list <- vector("list", length(.month_ends))
.w_diag  <- vector("list", length(.month_ends))
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
  ilq <- ilq[Ticker %in% uni_tk]
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L][Ticker %in% uni_tk]

  cmb <- merge(ilq, mom, by = "Ticker")
  if (nrow(cmb) < 30L) next
  cmb[, Zm := .rank_z(Mom)]
  cmb[, Zi := .rank_z(Ilq)]
  cmb <- cmb[is.finite(Zm) & is.finite(Zi)]
  if (nrow(cmb) < 30L) next
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]   # 50/50 (B1-5 그대로)

  # ---- 유일한 변경: 랭크 선형 가중 (AMP 2013) ----
  #  rank 1 = 최고 Score. 동점은 정렬 후 행 위치로 결정론적 배정(ties="first" 동등).
  setorder(cmb, -Score, Ticker)
  k <- min(N_HOLD, nrow(cmb))
  top <- cmb[seq_len(k)]
  top[, Rank := seq_len(.N)]
  top[, Wraw := (N_HOLD + 1L) - Rank]          # (26 − rank)
  top[, Weight := Wraw / sum(Wraw)]            # Σw = 1
  stopifnot(all(top$Weight > 0), abs(sum(top$Weight) - 1) < 1e-10)

  .w_diag[[i]] <- data.table(Date = d, n = k,
                             w_max = max(top$Weight), w_min = min(top$Weight),
                             w_top5 = sum(head(top$Weight, 5L)),
                             eff_n = 1 / sum(top$Weight^2))

  .pf_list[[i]] <- top[, .(Date = d, Ticker, Weight, Leg = "long")]
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .pf_list), use.names = TRUE)

.wd <- rbindlist(Filter(Negate(is.null), .w_diag), use.names = TRUE)
if (nrow(.wd)) {
  cat(sprintf("[fe_b2_7][weight-diag] rank-linear w ∝ (26−rank) | n median %d | w_max median %.4f | w_min median %.4f | top5합 median %.4f | 유효종목수(1/HHI) median %.2f\n",
              as.integer(median(.wd$n)), median(.wd$w_max), median(.wd$w_min),
              median(.wd$w_top5), median(.wd$eff_n)))
  saveRDS(.wd, file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
          "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
          "04_Research/strategies/RF_B2_7_RankWeight/weight_diag.rds"))
}

cat(sprintf("[fe_b2_7] Mom(12-1)rankZ + %s rankZ 50/50 → rank-weighted top-%d | PORTFOLIO rows=%d | months=%d | tickers=%d\n",
            ILLIQ_FACTOR, N_HOLD, nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date),
            uniqueN(PORTFOLIO$Ticker)))
