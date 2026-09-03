# =============================================================================
# fe_b2_8_invvol.R — 규칙기반 고속강화 B2-8 (rulefast 8/20)
#   신호 = B1-5 그대로(모멘텀 12-1 rank-Z 50% + Amihud 비유동성 rank-Z 50%)
#   바뀌는 것 = 비중 하나뿐: EW → 역변동성 w_i ∝ 1/σ_i (σ = 직전 60거래일 일수익 sd)
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=8
#
# 근거 논문 (하드코딩 금지 — 수치 결정 뿌리):
#   - 비중(역변동성/리스크패리티): Asness, Frazzini & Pedersen (2012, FAJ 68(1))
#     "Leverage Aversion and Risk Parity"
#     https://www.tandfonline.com/doi/abs/10.2469/faj.v68.n1.1
#   - 신호(이식 · B1-5 동일):
#     · 모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#       https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#     · 비유동성 프리미엄: Amihud (2002, JFM 5(1))
#       https://www.sciencedirect.com/science/article/pii/S1386418101000246
#
# ★ B1-5 대비 변경점은 **비중 하나뿐**이다:
#   - 신호·유니버스·유동성필터·종목수(25)·리밸(월간)·선택 규칙(Score 상위 25) 전부 동일.
#   - EW(1/25) → 역변동성 w_i = (1/σ_i) / Σ_j(1/σ_j).
#
# ===== σ 정의 · 결측 규칙 (자의 규칙 추가 금지) =====
#   σ_i = 직전 60거래일 일수익(RAWDATA$Ret) 표본표준편차, **창 종점 t-1**.
#     구현: 시그널일 d 에 대해 그 티커의 `Date < d` 관측 중 **마지막 60개** 수익의 sd().
#       → 시그널일 당일 수익(= 당일 종가)이 창에서 제외된다 (C2).
#     ★모멘트 항등식(m2 − m1²) 경로는 **폐기**했다 — 실측: 진짜 분산이 0 인 종목
#       (60일 연속 동일수익 = 거래정지/상하한 고착)에서 소거오차가 σ≈1e-10 의 허수를
#       만들었고(직접 sd() 대비 상대오차 Inf, 200표본 중 발생), w∝1/σ 아래서는 그
#       한 종목이 비중 ~100% 를 가져간다. 비중을 정하는 양이므로 정확도를 택한다.
#       (모멘트식과 직접 sd() 는 비퇴화 구간에서 상대오차 median 0 으로 일치했다.)
#   결측 처리 = **제외**: σ 가 NA(60개 미충족) 이거나 σ <= 0 인 종목은 비중 대상에서 뺀다.
#     - 선택(Score 상위 25)은 B1-5 와 동일하게 먼저 수행 → 그 25종 중 σ 부적격만 제외
#       → 잔존 종목에 1/σ 비중 재정규화(Σw=1). 선택 규칙에 σ 를 개입시키지 않는다
#       (개입시키면 "비중만 바꾼다" 는 셀 정의를 위반).
#     - 제외 실측치는 아래 [sigma-diag] 로그 + invvol_diag.rds 에 남긴다.
#
# ===== PIT (C1~C15) =====
#   - C2: σ 창 종점 t-1 (shift(1L)) · 모멘텀 shift(21)/shift(252) — 당일 종가 미사용.
#   - C1: 롤링 60창만 사용(full-sample 통계 없음). rank-Z 는 sig_date cross-section 내.
#   - C10: 유동성 필터 adv20 = shift(frollmean(20), 1L) — 당일 거래대금 미포함.
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

ILLIQ_FACTOR <- "L01_Amihud"   # B1-5 선택 그대로 (L09 는 방향 반전으로 배제)
VOL_WIN      <- 60L            # 만다트: 직전 60거래일
N_LONG       <- 25L            # B1-5 동일

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-11-01")]

# ---- K200∪KQ150 멤버십 + 유동성 adv20 >= 2e8 (C10: t-1, shift 1) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  is.finite(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
setkey(.mem, Date, Ticker)

# ---- 모멘텀 12-1 (JT1993): 과거 윈도우만 ----
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
setkey(.mom_all, Date, Ticker)

RAWDATA[, c(".TV", ".AvgTV20", ".Mom") := NULL]

# ---- 역변동성 σ (AFP2012): 60거래일 일수익 sd, 창 종점 t-1 — **직접 sd()** ----
#   티커별 (Date, Ret) 를 1회 캐시한 뒤, 시그널일 d 마다 Date < d 의 마지막 60개로 sd().
#   선택된 25종에 대해서만 호출한다(월 25회 × 262개월 ≈ 6.6K회 — 정확도 우선 경로).
.RD <- RAWDATA[, .(Ticker, Date, Ret)]
setkey(.RD, Ticker, Date)
.ret_cache <- new.env(parent = emptyenv())
.get_rets <- function(tk) {
  v <- .ret_cache[[tk]]
  if (is.null(v)) {
    s <- .RD[.(tk), .(Date, Ret), nomatch = 0L]
    v <- list(Date = s$Date, Ret = s$Ret)
    assign(tk, v, envir = .ret_cache)
  }
  v
}
.sigma_at <- function(tk, d) {
  v <- .get_rets(tk)
  j <- sum(v$Date < d)                      # 창 종점 t-1 (시그널일 당일 제외)
  if (j < VOL_WIN) return(NA_real_)
  rr <- v$Ret[(j - VOL_WIN + 1L):j]
  if (anyNA(rr)) return(NA_real_)
  sd(rr)                                    # 표본표준편차 (n-1), 퇴화 시 정확히 0
}

# ---- rank-Z (B1-5 동일) ----
.rank_z <- function(x) {
  r <- frank(x, ties.method = "average", na.last = "keep")
  mu <- mean(r, na.rm = TRUE); s <- sd(r, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mu) / s
}

.pf_list  <- vector("list", length(.month_ends))
.wd_diag  <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

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
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]

  # ---- 선택: Score 상위 25 (B1-5 와 동일 — σ 개입 없음) ----
  setorder(cmb, -Score)
  sel <- head(cmb, N_LONG)
  n_sel <- nrow(sel)
  if (n_sel < 2L) next

  # ---- 비중: 역변동성 (AFP2012). σ 결측/0 = 제외 후 재정규화 ----
  sel <- sel[, .(Ticker, Score)]
  sel[, Sigma := vapply(Ticker, .sigma_at, numeric(1), d = d)]
  n_na   <- sum(!is.finite(sel$Sigma))            # 60개 미충족 또는 창 내 NA
  n_zero <- sum(is.finite(sel$Sigma) & sel$Sigma <= 0)   # 퇴화(분산 0) — 거래정지/고착
  n_bad  <- n_na + n_zero
  sel <- sel[is.finite(Sigma) & Sigma > 0]
  if (nrow(sel) < 2L) next
  sel[, InvVol := 1 / Sigma]
  sel[, Weight := InvVol / sum(InvVol)]

  .pf_list[[i]] <- sel[, .(Date = d, Ticker, Weight, Leg = "long")]
  .wd_diag[[i]] <- data.table(
    Date = d, n_selected = n_sel, n_sigma_na = n_na, n_sigma_zero = n_zero,
    n_sigma_bad = n_bad, n_held = nrow(sel),
    w_min = min(sel$Weight), w_max = max(sel$Weight),
    w_median = median(sel$Weight), w_sum = sum(sel$Weight),
    hhi = sum(sel$Weight^2), eff_n = 1 / sum(sel$Weight^2),
    sigma_min = min(sel$Sigma), sigma_median = median(sel$Sigma),
    sigma_max = max(sel$Sigma))
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .pf_list), use.names = TRUE)

.wd <- rbindlist(Filter(Negate(is.null), .wd_diag), use.names = TRUE)
if (nrow(.wd)) {
  .out <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                   "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                   "04_Research/strategies/RF_B2_8_InvVol/invvol_diag.rds")
  saveRDS(.wd, .out)
  cat(sprintf("[fe_b2_8][sigma-diag] 리밸 %d회 | 선택 25종 중 σ 부적격 제외 총 %d건 (NA %d + 퇴화0 %d | 월 median %d, max %d) | 보유수 median %d, min %d\n",
              nrow(.wd), sum(.wd$n_sigma_bad), sum(.wd$n_sigma_na), sum(.wd$n_sigma_zero),
              as.integer(median(.wd$n_sigma_bad)),
              max(.wd$n_sigma_bad), as.integer(median(.wd$n_held)), min(.wd$n_held)))
  cat(sprintf("[fe_b2_8][weight-dist] w_min median %.4f | w_max median %.4f | w_max 전체최대 %.4f | EW=%.4f | 유효종목수(1/HHI) median %.1f | Σw median %.6f\n",
              median(.wd$w_min), median(.wd$w_max), max(.wd$w_max), 1 / N_LONG,
              median(.wd$eff_n), median(.wd$w_sum)))
  cat(sprintf("[fe_b2_8][sigma-level] 보유종목 σ(일간) median %.4f | 월별 최소 median %.4f | 월별 최대 median %.4f | max/min 비율 median %.2f\n",
              median(.wd$sigma_median), median(.wd$sigma_min), median(.wd$sigma_max),
              median(.wd$sigma_max / .wd$sigma_min)))
}

cat(sprintf("[fe_b2_8] B1-5 신호 + 역변동성 비중 | PORTFOLIO rows=%d | months=%d | tickers=%d\n",
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date), uniqueN(PORTFOLIO$Ticker)))
