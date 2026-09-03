# =============================================================================
# fe_b2_9_minvar_lw.R — 규칙기반 고속강화 B2-9 (rulefast 9/20)
#   신호 = B1-5 승자 그대로 (모멘텀 12-1 rankZ 50% + Amihud 비유동성 rankZ 50%)
#   바꾸는 것 = 비중 하나 : 상위 25종 Ledoit-Wolf 축소 공분산 하 long-only 최소분산
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=9
#
# 근거 논문 (하드코딩 금지 — 수치 결정 뿌리):
#   - 축소 공분산: Ledoit & Wolf (2004), "A well-conditioned estimator for
#     large-dimensional covariance matrices", JMVA 88(2):365-411
#     https://www.sciencedirect.com/science/article/pii/S0047259X03000964
#     → 목표행렬 = m*I (m = tr(S)/p), 축소강도 delta = b^2/d^2 (논문 식 그대로).
#       ★상수상관 목표(Ledoit-Wolf 2003 JEF)가 아니라 항등 목표(JMVA 2004)다.
#   - 신호부(이식, 무수정):
#     모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#       https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#     비유동성: Amihud (2002, JFM 5(1))
#       https://www.sciencedirect.com/science/article/pii/S1386418101000246
#
# ===== 사전 고정 규칙 (실행 전 확정 — 사후 조정 없음) =====
#   R1. 공분산 추정 데이터 = 월수익(월말 종가 기준). 명목 창 = 직전 60개월.
#   R2. 창 종점 = 시그널월 M 의 직전월 M-1 (즉 사용 자료의 마지막 시점 = 월말(M-1)
#       종가 < 시그널일 d = 월말(M)). C1 rolling · C2 동일시점 참조 없음 ·
#       전 표본 공분산 없음.
#   R3. 결측 처리 = 후행 공통창(trailing complete-case). 선정 25종 전부가 결측
#       없는 가장 최근 연속 K 개월(K <= 60)을 쓴다. 종목은 하나도 버리지 않는다
#       (선정 축을 고정해 '비중만' 바꾸기 위함).
#   R4. K < 30 (표본수가 자산수 25 를 충분히 넘지 못함) → 그 달은 EW 폴백.
#   R5. QP(solve.QP) 수렴 실패·비정칙 → 그 달은 EW 폴백.
#   R6. 최적화 = min w'Sigma w s.t. sum(w)=1, w >= 0 (long-only, Σw=1).
#   R7. 폴백 발생 횟수는 사유별로 집계해 보고한다.
#
# ===== LW 무증상 퇴화 진단 (이 셀의 필수 산출 — 성과보다 먼저 보고) =====
#   매 리밸런싱일에 ①delta ②cond(Sigma_hat) ③유효랭크(참여비 (Σλ)^2/Σλ^2)
#   ④평균 비대각 상관(축소 후/표본) 을 기록해 lw_diagnostics.csv 로 남긴다.
#   delta 가 1 에 붙거나 평균상관이 포화하면 min-var 가 조용히 EW 또는 1종목
#   집중으로 붕괴한다 — 그 사실 자체가 판정.
#
# ===== PIT (C1~C15) =====
#   - C1: 공분산·평균은 직전 60개월 후행창 안에서만. 전 표본 통계 없음.
#         rank-Z 는 시그널일 횡단면 내에서만.
#   - C2: 공분산 창 종점 = 월말(M-1) — 시그널일 d 를 포함하지 않는다.
#   - C10: 유동성 adv20 은 shift(1) — 시그널일 당일 거래대금 미포함.
#   - C13/C14: Amihud 는 Z_Score_Aligned 만 소비. 부호 수동 반전 없음.
#   - C15: factor DB 는 load_month_factors() 경유.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(quadprog)
})
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

.B29_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                                 "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                      "04_Research/strategies/RF_B2_9_MinVarLW")

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                               "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

ILLIQ_FACTOR <- "L01_Amihud"   # B1-5 선택 그대로 (L09 는 방향 반전으로 배제)
N_LONG   <- 25L                # 선정 종목수 — B1-5 와 동일 (비중만 바꾸는 셀)
COV_WIN  <- 60L                # R1 명목 창 (개월)
COV_MIN  <- 30L                # R4 최소 표본 개월

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.me_all <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .me_all[.me_all >= as.Date("2004-11-01")]  # start 2005-01 대비 여유

# ---- 월수익 패널 (월말 종가 → 월간 단순수익) : 공분산 재료 ----
.mc <- RAWDATA[Date %in% .me_all & is.finite(Close) & Close > 0, .(Date, Ticker, Close)]
.wide <- dcast(.mc, Date ~ Ticker, value.var = "Close")
setorder(.wide, Date)
.pm <- as.matrix(.wide[, -1L, with = FALSE])
.rdates <- .wide$Date[-1L]
.RETM <- .pm[-1L, , drop = FALSE] / .pm[-nrow(.pm), , drop = FALSE] - 1
rownames(.RETM) <- as.character(.rdates)
rm(.mc, .wide, .pm); gc(verbose = FALSE)
.rpos <- setNames(seq_along(.rdates), as.character(.rdates))
cat(sprintf("[fe_b2_9] 월수익 패널: %d개월 x %d종목 (%s ~ %s)\n",
            nrow(.RETM), ncol(.RETM),
            format(min(.rdates)), format(max(.rdates))))

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

# ---- rank-Z: cross-section 내 rank(ties=average) → z-score of ranks (B1-5 무수정) ----
.rank_z <- function(x) {
  r <- frank(x, ties.method = "average", na.last = "keep")
  mu <- mean(r, na.rm = TRUE); s <- sd(r, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mu) / s
}

# ---- Ledoit-Wolf (2004 JMVA) 축소: 목표 = m*I, delta = b^2/d^2 ----
.lw_shrink <- function(X) {
  n <- nrow(X); p <- ncol(X)
  Xc <- sweep(X, 2L, colMeans(X), "-")
  S  <- crossprod(Xc) / n
  m  <- sum(diag(S)) / p
  A  <- S - m * diag(p)
  d2 <- sum(A * A) / p
  b2b <- 0
  for (k in seq_len(n)) {
    Bk <- tcrossprod(Xc[k, ]) - S
    b2b <- b2b + sum(Bk * Bk) / p
  }
  b2b <- b2b / (n * n)
  b2 <- min(b2b, d2)
  dl <- if (is.finite(d2) && d2 > 0) b2 / d2 else 1
  list(Sigma = dl * m * diag(p) + (1 - dl) * S, delta = dl, S = S, m = m)
}

# ---- 진단 4종 (+ 표본 대조) ----
.offdiag_corr <- function(M) {
  s <- sqrt(diag(M))
  if (any(!is.finite(s)) || any(s <= 0)) return(NA_real_)
  R <- M / tcrossprod(s)
  mean(R[upper.tri(R)])
}
.cov_diag <- function(Sig, S) {
  ev <- eigen(Sig, symmetric = TRUE, only.values = TRUE)$values
  ev <- ev[is.finite(ev)]
  lo <- min(ev); hi <- max(ev)
  list(cond   = if (is.finite(lo) && lo > 0) hi / lo else Inf,
       erank  = if (sum(ev * ev) > 0) (sum(ev))^2 / sum(ev * ev) else NA_real_,
       rho_sh = .offdiag_corr(Sig),
       rho_sa = .offdiag_corr(S))
}

# ---- long-only min-var QP: min w'Sw s.t. sum(w)=1, w>=0 ----
.minvar_lo <- function(Sig) {
  p <- ncol(Sig)
  D <- (Sig + t(Sig)) / 2
  ridge <- 1e-10 * mean(diag(D))
  Amat <- cbind(rep(1, p), diag(p))
  bvec <- c(1, rep(0, p))
  for (k in 0:6) {
    Dk <- D + (if (k == 0) 0 else ridge * (10^k)) * diag(p)
    sol <- tryCatch(solve.QP(Dmat = Dk, dvec = rep(0, p),
                             Amat = Amat, bvec = bvec, meq = 1L),
                    error = function(e) NULL)
    if (!is.null(sol)) {
      w <- sol$solution
      w[w < 0] <- 0
      if (sum(w) > 0) return(w / sum(w))
    }
  }
  NULL
}

.pf_list  <- vector("list", length(.month_ends))
.dg_list  <- vector("list", length(.month_ends))
.n_fb_short <- 0L; .n_fb_qp <- 0L; .n_ok <- 0L

for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  # ---- 신호부 (B1-5 이식, 무수정) ----
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
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]   # 50/50 (B1-5 고정)
  setorder(cmb, -Score)
  sel <- head(cmb$Ticker, N_LONG)
  p <- length(sel)
  if (p < 2L) next

  # ---- 비중부 (이 셀의 유일한 변경) ----
  # R2: 창 종점 = 시그널월 직전월. .rdates[pos] == d 이므로 상한 인덱스 = pos-1.
  pos <- unname(.rpos[as.character(d)])
  pos <- if (is.na(pos)) sum(.rdates < d) else (pos - 1L)
  if (!is.finite(pos) || pos < COV_MIN) next
  lo <- max(1L, pos - COV_WIN + 1L)
  keep <- intersect(sel, colnames(.RETM))
  if (length(keep) < p) { .n_fb_short <- .n_fb_short + 1L
    W <- rep(1 / p, p); mode_i <- "EW_FALLBACK_MISSING"; K <- 0L; dl <- NA_real_
    dgi <- list(cond = NA_real_, erank = NA_real_, rho_sh = NA_real_, rho_sa = NA_real_)
  } else {
    Xw <- .RETM[lo:pos, sel, drop = FALSE]
    ok <- stats::complete.cases(Xw) & apply(is.finite(Xw), 1L, all)
    # R3: 후행 공통창 — 가장 최근부터 연속으로 전 종목 관측된 구간만
    run <- rev(cumprod(rev(as.integer(ok))))
    K <- sum(run == 1L)
    if (K < COV_MIN) {
      .n_fb_short <- .n_fb_short + 1L
      W <- rep(1 / p, p); mode_i <- "EW_FALLBACK_SHORT"; dl <- NA_real_
      dgi <- list(cond = NA_real_, erank = NA_real_, rho_sh = NA_real_, rho_sa = NA_real_)
    } else {
      X <- Xw[(nrow(Xw) - K + 1L):nrow(Xw), , drop = FALSE]
      lw <- .lw_shrink(X)
      dl <- lw$delta
      dgi <- .cov_diag(lw$Sigma, lw$S)
      w <- .minvar_lo(lw$Sigma)
      if (is.null(w)) { .n_fb_qp <- .n_fb_qp + 1L
        W <- rep(1 / p, p); mode_i <- "EW_FALLBACK_QP"
      } else { .n_ok <- .n_ok + 1L; W <- w; mode_i <- "MINVAR_LW" }
    }
  }

  .pf_list[[i]] <- data.table(Date = d, Ticker = sel, Weight = W, Leg = "long")
  .dg_list[[i]] <- data.table(
    Date = d, mode = mode_i, n_assets = p, n_obs = K,
    delta = dl, cond = dgi$cond, erank = dgi$erank,
    rho_shrunk = dgi$rho_sh, rho_sample = dgi$rho_sa,
    w_max = max(W), w_min = min(W), hhi = sum(W * W), n_eff = 1 / sum(W * W),
    n_zero = sum(W < 1e-6))
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .pf_list), use.names = TRUE)
.DG <- rbindlist(Filter(Negate(is.null), .dg_list), use.names = TRUE)

dir.create(.B29_DIR, recursive = TRUE, showWarnings = FALSE)
fwrite(.DG, file.path(.B29_DIR, "lw_diagnostics.csv"))

.q <- function(v, p) if (all(is.na(v))) NA_real_ else as.numeric(stats::quantile(v, p, na.rm = TRUE))
.ok <- .DG[mode == "MINVAR_LW"]
cat(sprintf("[fe_b2_9][LW-diag] n_rebal=%d | MINVAR_LW=%d · EW_FALLBACK(short)=%d · EW_FALLBACK(QP)=%d\n",
            nrow(.DG), .n_ok, .n_fb_short, .n_fb_qp))
if (nrow(.ok)) {
  cat(sprintf("[fe_b2_9][LW-diag] delta   med %.4f | p10 %.4f | p90 %.4f | max %.4f\n",
              median(.ok$delta), .q(.ok$delta, .10), .q(.ok$delta, .90), max(.ok$delta)))
  cat(sprintf("[fe_b2_9][LW-diag] cond    med %.1f | p10 %.1f | p90 %.1f\n",
              median(.ok$cond), .q(.ok$cond, .10), .q(.ok$cond, .90)))
  cat(sprintf("[fe_b2_9][LW-diag] erank   med %.2f | p10 %.2f | p90 %.2f (자산수 %d)\n",
              median(.ok$erank), .q(.ok$erank, .10), .q(.ok$erank, .90), N_LONG))
  cat(sprintf("[fe_b2_9][LW-diag] rho_shr med %.4f | p10 %.4f | p90 %.4f  (표본 rho med %.4f)\n",
              median(.ok$rho_shrunk), .q(.ok$rho_shrunk, .10), .q(.ok$rho_shrunk, .90),
              median(.ok$rho_sample)))
  cat(sprintf("[fe_b2_9][LW-diag] n_obs   med %.0f | min %.0f || w_max med %.4f p90 %.4f | n_eff med %.2f | w=0 med %.0f\n",
              median(.ok$n_obs), min(.ok$n_obs), median(.ok$w_max), .q(.ok$w_max, .90),
              median(.ok$n_eff), median(.ok$n_zero)))
}
cat(sprintf("[fe_b2_9] PORTFOLIO rows=%d | months=%d | tickers=%d | Σw 편차 max %.2e\n",
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date), uniqueN(PORTFOLIO$Ticker),
            max(abs(PORTFOLIO[, sum(Weight), by = Date]$V1 - 1))))
