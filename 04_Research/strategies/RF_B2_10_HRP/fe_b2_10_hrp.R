# =============================================================================
# fe_b2_10_hrp.R — 규칙기반 고속강화 B2-10 (rulefast 10/20)
#   신호 = B1-5 승자 그대로 (모멘텀 12-1 rank-Z 50% + Amihud 비유동성 rank-Z 50%)
#   비중 = 계층적 리스크 패리티 (HRP, Lopez de Prado 2016) — 공분산 역행렬 미사용
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=10
#
# 근거 논문 (하드코딩 금지 — 모든 수치 결정의 뿌리):
#   - HRP(비중): Lopez de Prado (2016), "Building Diversified Portfolios that
#     Outperform Out of Sample", JPM 42(4):59-69
#     https://www.pm-research.com/content/iijpormgmt/42/4/59
#     ① 상관 거리 d_ij = sqrt(0.5 * (1 - rho_ij))
#     ② 단일 연결(single linkage) 계층 군집 — 원전 코드가 쓰는 연결법
#        (원전은 sch.linkage(d, 'single') 로 거리행렬 d 의 행벡터 간 유클리드
#         거리 dbar 위에서 군집한다 → 본 구현 hclust(dist(D), method="single") 동일)
#     ③ 준대각화 = 덴드로그램 잎 순서 (hclust$order)
#     ④ 재귀 이분 배분 = 클러스터 분산(역분산 가중 내부해)의 역비율로 좌/우 배분
#     ★역행렬 없음: 사용하는 공분산 연산은 대각(역분산)과 2차형식뿐이다.
#       B2-9(min-var)가 Sigma^-1 불안정으로 무너지면 이 셀이 그 대조군이 된다.
#   - 모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#     https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#   - 비유동성 프리미엄: Amihud (2002, JFM 5(1))
#     https://www.sciencedirect.com/science/article/pii/S1386418101000246
#
# Amihud 코드 선택 = L01_Amihud (B1-5 사전 실측 진단 계승):
#   L01 은 PIT expanding IC 부호가 전 구간 +1 → Z_Score_Aligned 고득점 = 비유동
#   = 프리미엄 방향과 전 구간 일치. L09_Amihud_20d 는 2012년경 부호 반전으로 배제
#   (수동 재반전은 C13 FLIP_SIGN 위반).
#
# ===== PIT (C1~C15) — 급소 = 상관 추정창 =====
#   - C1: 상관/공분산은 **직전 60개월 월수익 롤링 창**만 쓴다. 전 표본 상관 없음.
#         창 종점 <= t-1 (시그널 월 M 의 창 = 월말 인덱스 (i-60):(i-1), 즉 M-60..M-1).
#         시그널 월 M 자신의 수익은 창에 들어가지 않는다(동일시점 참조 원천 차단).
#   - C2: 모멘텀 = shift(21)/shift(252) 과거 윈도우만. 순환참조 없음.
#   - C10: 유동성 필터 adv20 은 t-1 (frollmean(20) 후 shift(1)).
#   - C13/C14: Amihud 는 Z_Score_Aligned 만 소비. NEGATE/FLIP 없음.
#   - C15: factor DB parquet 직접 load 금지 — load_month_factors() 경유.
#   - C6: K200/KQ150 멤버십은 RAWDATA 의 PIT 시변 플래그.
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

ILLIQ_FACTOR <- "L01_Amihud"   # B1-5 계승 (L09 는 방향 반전으로 배제)
CORR_LOOKBACK_M <- 60L         # Lopez de Prado(2016) 실증 설계의 장기 상관창 (월)
MIN_OBS_M       <- 24L         # 창 내 최소 관측 월수 (상관 추정 가능성 요건)
N_LONG          <- 25L         # 실투형 축 (v10 lean-loop) — 상한 없음, Σw=1

# ---- 월말 그리드 (전 이력 = 상관창 재료 / 시그널 그리드는 2004-11 이후) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.me_all <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.me_dt <- data.table(Date = .me_all, k = seq_along(.me_all))
setkey(.me_dt, Date)
.sig_idx <- which(.me_all >= as.Date("2004-11-01"))

# ---- K200∪KQ150 멤버십 + 유동성 adv20 >= 2e8 (C10: t-1, shift 1) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
.mem <- RAWDATA[Date %in% .me_all & (K200 == TRUE | KQ150 == TRUE) &
                  is.finite(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
setkey(.mem, Date, Ticker)

# ---- 모멘텀 12-1 (JT1993): 과거 12개월 누적, 최근 1개월 제외 ----
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
.mom_all <- RAWDATA[Date %in% .me_all & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
setkey(.mom_all, Date, Ticker)

# ---- 월수익 패널 (상관 추정 재료) — 인접 월말 쌍만 유효 ----
.mc <- RAWDATA[Date %in% .me_all & is.finite(Close), .(Date, Ticker, Close)]
RAWDATA[, c(".TV", ".AvgTV20", ".Mom") := NULL]
.mc <- merge(.mc, .me_dt, by = "Date")
setorder(.mc, Ticker, k)
.mc[, `:=`(.pk = shift(k, 1L), .pc = shift(Close, 1L)), by = Ticker]
.mc[, Rm := NA_real_]
.mc[is.finite(.pc) & .pc > 0 & .pk == k - 1L, Rm := Close / .pc - 1]
MRET <- .mc[is.finite(Rm), .(k, Ticker, Rm)]
setkey(MRET, k)
rm(.mc)

# ---- rank-Z: cross-section 내 rank(ties=average) → z-score of ranks ----
.rank_z <- function(x) {
  r <- frank(x, ties.method = "average", na.last = "keep")
  mu <- mean(r, na.rm = TRUE); s <- sd(r, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mu) / s
}

# =============================================================================
# HRP (Lopez de Prado 2016) — 4단계. 공분산 역행렬 미사용.
# =============================================================================
.cluster_var <- function(cm, idx) {
  cv <- cm[idx, idx, drop = FALSE]
  iv <- 1 / pmax(diag(cv), 1e-12)          # 역분산(대각만 — 역행렬 아님)
  iv <- iv / sum(iv)
  v <- as.numeric(t(iv) %*% cv %*% iv)     # 2차형식
  if (!is.finite(v) || v <= 0) 1e-12 else v
}

.hrp_weights <- function(cm) {
  n <- ncol(cm)
  nm <- colnames(cm)
  if (n == 1L) return(setNames(1, nm))
  sdv <- sqrt(pmax(diag(cm), 1e-12))
  rho <- cm / outer(sdv, sdv)
  rho[!is.finite(rho)] <- 0
  rho <- pmin(pmax(rho, -1), 1)
  diag(rho) <- 1
  D <- sqrt(0.5 * (1 - rho))               # ① 상관 거리
  hc <- hclust(dist(D), method = "single") # ② 단일 연결 (원전 sch.linkage 'single')
  sortIx <- hc$order                       # ③ 준대각화 = 잎 순서
  w <- rep(1, n)
  items <- list(sortIx)
  repeat {                                 # ④ 재귀 이분 배분
    nxt <- list()
    for (it in items) if (length(it) > 1L) {
      h <- length(it) %/% 2L
      nxt[[length(nxt) + 1L]] <- it[1:h]
      nxt[[length(nxt) + 1L]] <- it[(h + 1L):length(it)]
    }
    if (!length(nxt)) break
    j <- 1L
    while (j < length(nxt)) {
      c0 <- nxt[[j]]; c1 <- nxt[[j + 1L]]
      v0 <- .cluster_var(cm, c0); v1 <- .cluster_var(cm, c1)
      a <- 1 - v0 / (v0 + v1)
      if (!is.finite(a)) a <- 0.5
      a <- min(max(a, 0), 1)
      w[c0] <- w[c0] * a
      w[c1] <- w[c1] * (1 - a)
      j <- j + 2L
    }
    items <- nxt
  }
  w <- pmax(w, 0)
  if (sum(w) <= 0) w <- rep(1 / n, n) else w <- w / sum(w)
  setNames(w, nm)
}

# 진단 전용 군집 구조 (배분에 영향 없음): 상관거리 D 위 단일연결을 rho=0.5
#   (d = sqrt(0.5*(1-0.5)) = 0.5) 에서 절단 → "평균상관 0.5 이상으로 이어지는 묶음"
.diag_clusters <- function(cm) {
  n <- ncol(cm)
  if (n < 2L) return(c(n_cl = n, max_sz = n))
  sdv <- sqrt(pmax(diag(cm), 1e-12))
  rho <- cm / outer(sdv, sdv)
  rho[!is.finite(rho)] <- 0
  rho <- pmin(pmax(rho, -1), 1); diag(rho) <- 1
  D <- sqrt(0.5 * (1 - rho))
  hc2 <- hclust(as.dist(D), method = "single")
  g <- cutree(hc2, h = 0.5)
  c(n_cl = length(unique(g)), max_sz = max(table(g)))
}

# =============================================================================
# 월별 루프
# =============================================================================
.pf_list <- vector("list", length(.me_all))
.dg_list <- vector("list", length(.me_all))

for (i in .sig_idx) {
  d <- .me_all[i]
  if (i <= CORR_LOOKBACK_M) next
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  # ---- Amihud (C15: connector 경유 / C13·C14: Z_Score_Aligned 만) ----
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05,
                                     factor_names = ILLIQ_FACTOR),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  ilq <- fdt[Factor_Name == ILLIQ_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, Ilq = Z_Score_Aligned)][Ticker %in% uni_tk]
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L][Ticker %in% uni_tk]
  cmb <- merge(ilq, mom, by = "Ticker")
  if (nrow(cmb) < 30L) next

  # ---- 상관 추정창: 창 종점 <= t-1 (시그널 월 자신 제외) ----
  wink <- (i - CORR_LOOKBACK_M):(i - 1L)
  rw <- MRET[.(wink), nomatch = 0L][Ticker %in% cmb$Ticker]
  ok <- rw[, .N, by = Ticker][N >= MIN_OBS_M, Ticker]
  n_drop <- nrow(cmb) - length(intersect(cmb$Ticker, ok))
  cmb <- cmb[Ticker %in% ok]
  if (nrow(cmb) < 30L) next

  # ---- 신호 (B1-5 그대로 이식: 50/50 rank-Z 컴포짓) ----
  cmb[, Zm := .rank_z(Mom)]
  cmb[, Zi := .rank_z(Ilq)]
  cmb <- cmb[is.finite(Zm) & is.finite(Zi)]
  if (nrow(cmb) < 30L) next
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]
  setorder(cmb, -Score)
  sel <- head(cmb$Ticker, N_LONG)
  if (length(sel) < 2L) next

  # ---- 공분산 (동일 창) → HRP ----
  sw <- dcast(rw[Ticker %in% sel], k ~ Ticker, value.var = "Rm")
  rmat <- as.matrix(sw[, -1, with = FALSE])
  if (ncol(rmat) < 2L) next
  cm <- suppressWarnings(cov(rmat, use = "pairwise.complete.obs"))
  cm[!is.finite(cm)] <- 0
  dg <- diag(cm); dg[!is.finite(dg) | dg <= 0] <- 1e-8
  diag(cm) <- dg

  wv <- .hrp_weights(cm)
  wv <- wv[is.finite(wv) & wv > 0]
  if (!length(wv)) next
  wv <- wv / sum(wv)

  cl <- .diag_clusters(cm)
  .pf_list[[i]] <- data.table(Date = d, Ticker = names(wv),
                              Weight = as.numeric(wv), Leg = "LONG")
  .dg_list[[i]] <- data.table(
    Date = d, n_sel = length(wv), n_hist_drop = n_drop,
    n_cluster = as.integer(cl[["n_cl"]]), max_cluster = as.integer(cl[["max_sz"]]),
    w_max = max(wv), w_min = min(wv),
    w_top5 = sum(sort(wv, decreasing = TRUE)[1:min(5L, length(wv))]),
    eff_n = 1 / sum(wv^2),
    obs_med = as.numeric(median(rw[Ticker %in% names(wv), .N, by = Ticker]$N)))
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .pf_list), use.names = TRUE)

.dg <- rbindlist(Filter(Negate(is.null), .dg_list), use.names = TRUE)
if (nrow(.dg)) {
  saveRDS(.dg, file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
          "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
          "04_Research/strategies/RF_B2_10_HRP/hrp_diag.rds"))
  cat(sprintf(paste0("[fe_b2_10][HRP-diag] 군집(진단 절단 rho=0.5) 평균 %.2f개 · 최대군집 median %d ",
                     "| w_max median %.4f · w_min median %.4f · top5 비중 median %.3f ",
                     "| 유효종목수 median %.2f (명목 %d) | 창 관측월 median %.0f · 이력미달 제외 median %.1f\n"),
              mean(.dg$n_cluster), as.integer(median(.dg$max_cluster)),
              median(.dg$w_max), median(.dg$w_min), median(.dg$w_top5),
              median(.dg$eff_n), N_LONG, median(.dg$obs_med), median(.dg$n_hist_drop)))
}
cat(sprintf("[fe_b2_10] HRP(dist=sqrt(0.5(1-rho)) · single linkage · 60M 창 종점 t-1) | PORTFOLIO rows=%d | months=%d | tickers=%d | Sum(w) range [%.6f, %.6f]\n",
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date), uniqueN(PORTFOLIO$Ticker),
            min(PORTFOLIO[, sum(Weight), by = Date]$V1),
            max(PORTFOLIO[, sum(Weight), by = Date]$V1)))
