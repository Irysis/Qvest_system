## WT-R20260829_005 Optimizer — Step B: 5-method walk-forward ladder
## ★사전 선언 (결과 확인 前 고정):
##   selection_objective = net_ir  (annualized IR of net-of-cost ACTIVE returns, 전 259개월 walk-forward)
##   materiality band    = |Δnet_IR| < 0.10  (≈ SE(IR) 0.215 의 절반) 이면 비결정 →
##                         tie-break ① 낮은 연회전율 ② 단순한 방법(EW 가 가장 단순)
##   HARD disqualify     = 연회전율 > 11.0 /yr  또는 제약(n>25 / Σw≠1 / w<0) 위반
## ★비교는 5종 상한. 결과를 본 뒤 축을 바꾸지 않는다.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table); library(lpSolve)})
set.seed(20260829)

S <- readRDS("stage_artifacts/WT_R20260829_005/opt_r5.rds")
A <- S$A; RET <- S$RET; BM <- S$BM; sel <- S$sel
dates <- sort(unique(A$Date))

## 광역 수익 wide matrix (PIT 슬라이싱용) — Date = 신호월 t 라벨, Ret_1m = 홀딩월 t+1 실현
RW <- dcast(RET, Date ~ Ticker, value.var = "Ret_1m")
rw_dates <- RW$Date
RWm <- as.matrix(RW[, -1]); rownames(RWm) <- as.character(rw_dates)

WIN <- 60L      # 트레일링 창 (월) — rolling, C1
MINOBS <- 24L   # 이 미만이면 위험기반 method 는 EW 로 fallback (조용한 대체 아님 — 카운트 기록)

## ---------- 방법론 ----------
w_ew <- function(tk, ...) setNames(rep(1/length(tk), length(tk)), tk)

.varvec <- function(Rt) {                              # 관측 <12개월 종목은 횡단면 중앙분산으로 대체(선언 규약)
  nobs <- colSums(!is.na(Rt))
  v <- apply(Rt, 2, var, na.rm = TRUE)
  v[nobs < 12L | !is.finite(v) | v <= 0] <- NA_real_
  v[is.na(v)] <- median(v, na.rm = TRUE)
  v
}

w_ivp <- function(tk, Rt, ...) {                       # inverse-variance (naive risk parity)
  v <- .varvec(Rt); w <- (1/v); w/sum(w)
}

w_hrp <- function(tk, Rt, ...) {                       # Lopez de Prado 2016 HRP
  C <- suppressWarnings(cor(Rt, use = "pairwise.complete.obs"))
  C <- matrix(C, ncol(Rt), ncol(Rt), dimnames = list(colnames(Rt), colnames(Rt)))
  C[!is.finite(C)] <- 0; diag(C) <- 1                  # 관측쌍 부족 = 상관 0(독립) 취급 — 선언 규약
  v <- .varvec(Rt); sdv <- sqrt(v)
  V <- C * outer(sdv, sdv)                             # 분산은 .varvec, 상관은 pairwise → PSD 아닐 수 있음(HRP 는 역행렬 불요)
  d <- sqrt(0.5*(1 - C)); d[!is.finite(d) | d < 0] <- 0; diag(d) <- 0
  d <- matrix(d, ncol(Rt), ncol(Rt), dimnames = dimnames(C))
  hc <- hclust(as.dist(d), method = "single")
  ord <- hc$order
  ivp <- function(idx) { iv <- 1/diag(V)[idx]; iv/sum(iv) }
  cvar_cluster <- function(idx) { wv <- ivp(idx); as.numeric(t(wv) %*% V[idx, idx, drop=FALSE] %*% wv) }
  w <- rep(1, length(ord)); names(w) <- colnames(Rt)[ord]
  clusters <- list(ord)
  while (length(clusters) > 0) {
    nxt <- list()
    for (cl in clusters) {
      if (length(cl) <= 1) next
      h <- floor(length(cl)/2)
      c1 <- cl[1:h]; c2 <- cl[(h+1):length(cl)]
      v1 <- cvar_cluster(c1); v2 <- cvar_cluster(c2)
      a1 <- 1 - v1/(v1 + v2)
      w[colnames(Rt)[c1]] <- w[colnames(Rt)[c1]] * a1
      w[colnames(Rt)[c2]] <- w[colnames(Rt)[c2]] * (1 - a1)
      nxt <- c(nxt, list(c1), list(c2))
    }
    clusters <- nxt
  }
  w <- w[colnames(Rt)]; w/sum(w)
}

.impute_rows <- function(Rt) {                         # 결측 셀 = 그 달 관측종목 횡단면 평균(시장동형 중립 대체)
  keep <- rowSums(!is.na(Rt)) >= max(3L, ceiling(0.5*ncol(Rt)))
  R2 <- Rt[keep, , drop = FALSE]
  if (nrow(R2) == 0L) return(NULL)
  rm_ <- rowMeans(R2, na.rm = TRUE)
  ix <- which(is.na(R2), arr.ind = TRUE)
  if (nrow(ix)) R2[ix] <- rm_[ix[, 1]]
  attr(R2, "imp_frac") <- nrow(ix)/length(R2)
  R2
}

w_mincvar <- function(tk, Rt, beta = 0.95, ...) {      # Rockafellar-Uryasev 2000 CVaR LP
  Rt2 <- .impute_rows(Rt)
  if (is.null(Rt2)) return(NULL)
  n <- ncol(Rt2); Tt <- nrow(Rt2)
  if (Tt < MINOBS) return(NULL)
  k <- 1/((1 - beta) * Tt)
  ## vars: w(1..n), zeta(n+1), u(1..T)
  obj <- c(rep(0, n), 1, rep(k, Tt))
  con <- matrix(0, nrow = Tt + 1, ncol = n + 1 + Tt)
  con[1:Tt, 1:n] <- Rt2                                 # u_j + r_j'w + zeta >= 0
  con[1:Tt, n+1] <- 1
  for (j in 1:Tt) con[j, n+1+j] <- 1
  con[Tt+1, 1:n] <- 1                                   # sum w = 1
  dir <- c(rep(">=", Tt), "=")
  rhs <- c(rep(0, Tt), 1)
  r <- lp("min", obj, con, dir, rhs)
  if (r$status != 0) return(NULL)
  w <- r$solution[1:n]; w[w < 0] <- 0
  if (sum(w) <= 0) return(NULL)
  setNames(w/sum(w), colnames(Rt2))
}

w_alb <- function(tk, Rt, alb, kappa = 0.5, ...) {     # uncertainty-aware alpha lower-bound tilt
  if (any(!is.finite(alb))) return(NULL)
  a <- pmax(alb, 0)
  if (sum(a) <= 0) return(NULL)
  w <- kappa * (a/sum(a)) + (1 - kappa) * (1/length(tk))
  setNames(w/sum(w), tk)
}

## ---------- 스케줄 생성 ----------
build <- function(fn, needs_R = TRUE, needs_alb = FALSE, label) {
  out <- vector("list", length(dates)); fb <- 0L
  for (i in seq_along(dates)) {
    d <- dates[i]
    S_i <- sel[Date == d]
    tk <- S_i$Ticker
    w <- NULL
    Rt <- NULL
    if (needs_R) {
      ## PIT: Ret_1m@Date=e 는 홀딩월 e+1 실현 → sig_date d 시점 기지분은 e < d. rolling 60M (C1)
      idx <- which(rw_dates < d)
      if (length(idx) >= MINOBS) {
        idx <- tail(idx, WIN)
        Rt <- matrix(NA_real_, length(idx), length(tk), dimnames = list(as.character(rw_dates[idx]), tk))
        have <- intersect(tk, colnames(RWm))
        if (length(have)) Rt[, have] <- RWm[idx, have, drop = FALSE]
      }
    }
    if ((!needs_R || !is.null(Rt)) && (!needs_alb || all(is.finite(S_i$alpha_lb)))) {
      w <- try(fn(tk = tk, Rt = Rt, alb = S_i$alpha_lb), silent = TRUE)
      if (inherits(w, "try-error")) w <- NULL
    }
    if (is.null(w) || any(!is.finite(w))) { w <- w_ew(tk); fb <- fb + 1L }
    w <- w[tk]
    out[[i]] <- data.table(Date = d, Ticker = tk, w = as.numeric(w/sum(w)))
  }
  list(W = rbindlist(out), fallback_n = fb, label = label)
}

## ---------- 평가 (v2.4 delta, no-drift — alpha 재현 실증 규약) ----------
eval_sched <- function(W, cost_bps = 15) {
  W2 <- merge(W, RET, by = c("Date","Ticker"), all.x = TRUE); W2[is.na(Ret_1m), Ret_1m := 0]
  ds <- sort(unique(W2$Date)); prev <- data.table(Ticker = character(), wp = numeric())
  out <- vector("list", length(ds))
  for (i in seq_along(ds)) {
    d <- ds[i]; cur <- W2[Date == d, .(Ticker, w, Ret_1m)]
    m <- merge(cur[, .(Ticker, w)], prev, by = "Ticker", all = TRUE)
    m[is.na(w), w := 0]; m[is.na(wp), wp := 0]
    to <- sum(abs(m$w - m$wp)); g <- sum(cur$w * cur$Ret_1m)
    out[[i]] <- data.table(Date = d, gross = g, cost = (cost_bps/1e4)*to, net = g - (cost_bps/1e4)*to,
                           to = to, hhi = sum(cur$w^2), wmax = max(cur$w), n = nrow(cur))
    prev <- cur[, .(Ticker, wp = w)]
  }
  rbindlist(out)
}

stats_of <- function(R) {
  r <- merge(R, BM, by = "Date")
  act <- r$net - r$BM_Ret
  cum <- cumprod(1 + r$net); yrs <- nrow(r)/12
  mdd <- min(cum/cummax(cum) - 1)
  cagr <- cum[length(cum)]^(1/yrs) - 1
  list(net_ir       = mean(act)*12 / (sd(act)*sqrt(12)),
       mean_act_ann = mean(act)*12,
       te_ann       = sd(act)*sqrt(12),
       sr_total     = mean(r$net)*12 / (sd(r$net)*sqrt(12)),
       cagr = cagr, mdd = mdd, calmar = cagr/abs(mdd),
       vol_ann = sd(r$net)*sqrt(12),
       to_ann = mean(R$to)*12, to_roundtrip = mean(R$to)*12*2,
       cost_ann = mean(R$cost)*12,
       hhi = mean(R$hhi), wmax = max(R$wmax), n_max = max(R$n),
       act_cvar95 = -mean(sort(act)[1:ceiling(0.05*length(act))]),
       gross_ir = (mean(r$gross - r$BM_Ret)*12)/(sd(r$gross - r$BM_Ret)*sqrt(12)))
}

METH <- list(
  EW       = list(fn = w_ew,      needs_R = FALSE, needs_alb = FALSE),
  IVP      = list(fn = w_ivp,     needs_R = TRUE,  needs_alb = FALSE),
  HRP      = list(fn = w_hrp,     needs_R = TRUE,  needs_alb = FALSE),
  MinCVaR  = list(fn = w_mincvar, needs_R = TRUE,  needs_alb = FALSE),
  ALB_tilt = list(fn = w_alb,     needs_R = FALSE, needs_alb = TRUE)
)

res <- list(); sched <- list()
for (nm in names(METH)) {
  t0 <- Sys.time()
  b <- build(METH[[nm]]$fn, METH[[nm]]$needs_R, METH[[nm]]$needs_alb, nm)
  R <- eval_sched(b$W); st <- stats_of(R)
  st$fallback_n <- b$fallback_n; st$secs <- as.numeric(difftime(Sys.time(), t0, units="secs"))
  res[[nm]] <- st; sched[[nm]] <- list(W = b$W, R = R)
  cat(sprintf("%-9s netIR %7.4f | actAnn %7.4f | TE %6.4f | TO %6.3f | CAGR %6.4f | MDD %7.4f | Calmar %5.3f | HHI %.4f | wmax %.3f | fb %3d | %4.1fs\n",
      nm, st$net_ir, st$mean_act_ann, st$te_ann, st$to_ann, st$cagr, st$mdd, st$calmar, st$hhi, st$wmax, st$fallback_n, st$secs))
}
saveRDS(list(res = res, sched = sched, dates = dates, WIN = WIN, MINOBS = MINOBS),
        "stage_artifacts/WT_R20260829_005/opt_r7.rds")
cat("\nsaved.\n")
