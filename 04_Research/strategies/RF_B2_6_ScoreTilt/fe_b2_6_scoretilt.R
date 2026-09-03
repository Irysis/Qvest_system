# =============================================================================
# fe_b2_6_scoretilt.R — 규칙기반 고속강화 B2-6 (rulefast 6/20)
#   신호 = B1-5 승자 컴포짓 이식(불변): 모멘텀(12-1) rank-Z 50% + Amihud rank-Z 50%
#   변경 = 비중 하나뿐: 상위 25종 EW → **팩터 스코어 틸트**
#          w_i ∝ (z_i − min(z_25) + eps), Σw = 1, w >= 0
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=6
#
# 근거 논문 (하드코딩 금지 — 수치 결정 뿌리):
#   - 비중 틸트(본 시도의 유일한 변경): Grinold (1989) "The Fundamental Law of
#     Active Management", JPM 15(3):30-37
#     https://www.pm-research.com/content/iijpormgmt/15/3/30
#     핵심 = 최적 액티브 비중은 알파(예측 신호)에 비례한다. 본 구현은 그 명제를
#     long-only 제약(w>=0, Σw=1) 하에서 선택 집합(top-25) 내부에 적용한다 —
#     비음(非負) 제약 아래 "알파 비례"의 자연한 사영이 (z − min(z)) 이다.
#   - 신호(이식·불변) 모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#     https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#   - 신호(이식·불변) 비유동성: Amihud (2002, JFM 5(1))
#     https://www.sciencedirect.com/science/article/pii/S1386418101000246
#
# Amihud 코드 = L01_Amihud — B1-5 의 사전 실측 진단 결과를 그대로 승계한다
#   (L01 은 PIT expanding IC 부호가 전 구간 +1, L09_Amihud_20d 는 2012년경 반전 →
#    Z_Score_Aligned 소비 시 방향 뒤집힘. 수동 재반전은 C13 위반이라 채택 불가).
#
# ===== PIT (C1~C15) — B1-5 와 동일 구조 =====
#   - C15: Amihud 는 factor DB parquet 직접 load 금지 — load_month_factors() 경유.
#   - C14/C13: Z_Score_Aligned 만 소비. NEGATE/FLIP 없음.
#   - C10: 유동성 필터 adv20 은 t-1 — frollmean(20) 후 shift(1).
#   - C2: 모멘텀 = shift(21)/shift(252) 과거 윈도우만. 동일시점 순환참조 없음.
#   - C1: rank-Z 와 틸트 비중 모두 sig_date 시점 cross-section 내에서만 산출
#         (full-sample 통계·미래 분위 사용 없음). 비중은 그 달 선택된 25종의
#         그 달 스코어만으로 결정된다 — 시계열 정보 무사용.
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

ILLIQ_FACTOR <- "L01_Amihud"   # B1-5 승계 (L09 는 방향 반전으로 배제)
N_LONG       <- 25L            # 실투형 축 상한 (v10 lean-loop) — B1-5 와 동일
TILT_EPS     <- 1e-6           # ε: 최하위 종목 비중 0 방지용 수치 가드.
                               #    스코어 스케일(rank-Z, sd≈1) 대비 무시가능 크기 —
                               #    Grinold 비례성을 왜곡하지 않도록 최소로 잡는다.

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

.pf_list   <- vector("list", length(.month_ends))
.wdiag_list <- vector("list", length(.month_ends))

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
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]   # 50/50 (B1-5 이식 — 불변)

  # ---- 선정: 상위 25종 (B1-5 와 동일) ----
  setorder(cmb, -Score)
  sel <- head(cmb, N_LONG)
  if (nrow(sel) < 2L) next

  # ---- 비중: 팩터 스코어 틸트 (Grinold 1989) — 유일한 변경 ----
  #   w_i ∝ (z_i − min(z_25) + eps), Σw = 1, w >= 0, 상한 없음(v10)
  raw_w <- sel$Score - min(sel$Score) + TILT_EPS
  if (!is.finite(sum(raw_w)) || sum(raw_w) <= 0) next
  wv <- raw_w / sum(raw_w)

  .pf_list[[i]] <- data.table(Date = d, Ticker = sel$Ticker,
                              Weight = wv, Leg = "long")
  .wdiag_list[[i]] <- data.table(
    Date = d, n_sel = nrow(sel),
    w_max = max(wv), w_min = min(wv),
    w_top5 = sum(head(sort(wv, decreasing = TRUE), 5L)),
    eff_n = 1 / sum(wv^2),
    score_spread = max(sel$Score) - min(sel$Score))
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .pf_list), use.names = TRUE)

.wdiag <- rbindlist(Filter(Negate(is.null), .wdiag_list), use.names = TRUE)
if (nrow(.wdiag)) {
  saveRDS(.wdiag, file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
          "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
          "04_Research/strategies/RF_B2_6_ScoreTilt/weight_diag.rds"))
  cat(sprintf(paste0("[fe_b2_6][weight-diag] eps=%.1e | w_max median %.4f (max %.4f) | ",
                     "w_min median %.6f | top5합 median %.4f | 유효종목수(1/sum w^2) median %.2f | ",
                     "score spread median %.3f\n"),
              TILT_EPS, median(.wdiag$w_max), max(.wdiag$w_max), median(.wdiag$w_min),
              median(.wdiag$w_top5), median(.wdiag$eff_n), median(.wdiag$score_spread)))
}

cat(sprintf("[fe_b2_6] Mom(12-1)+%s 50/50 컴포짓 · top-%d · score-tilt | PORTFOLIO rows=%d | months=%d | tickers=%d\n",
            ILLIQ_FACTOR, N_LONG, nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date),
            uniqueN(PORTFOLIO$Ticker)))
