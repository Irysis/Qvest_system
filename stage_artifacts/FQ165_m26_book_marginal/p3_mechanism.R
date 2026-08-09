## ============================================================================
## FQ-165 P3 — D4 발동에 따른 **기전 분리 의무** (사전등록 판정규칙 D4)
##   (a) 랭킹 잡음 열화 (placebo 와 구별 불가)  vs  (b) M26 정보가 이 소비면에서 역방향
## ★핵심 통제 = **형태별 크기-정합 placebo**. F_A 는 이미 정합(같은 w, 순열)이나
##   F_B(1.79종 제외)·F_C(4슬롯)는 개입 규모가 달라 F_A 의 placebo 를 쓰면 범주 오류다.
##   각 형태를 **같은 형태·순열 M26** 으로 12 draw 돌려 그 형태 고유의 잡음 바닥을 만든다.
## 추가: 교체된 종목(빠진 base 종목 vs 들어온 M26 종목)의 실현수익 직접 분해 (WT-022 방식).
## ============================================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite)
                  library(PerformanceAnalytics); library(xts)})
options(scipen = 999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/FQ165_m26_book_marginal"
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")

P1 <- readRDS(file.path(OUT, "p1_base.rds")); P2 <- readRDS(file.path(OUT, "p2_arms.rds"))
MO <- P1$MO; BASE <- P1$BASE; eval_dates <- P1$eval_dates; bmv <- P1$bmv
TOPN <- 20L; MINN <- 15L; LAM <- 1.5; UB <- 0.20; UBCR <- 0.10; BPS <- 0.0015
n_m <- length(MO)
{ m26 <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_002/alpha_scores.parquet"))
  m26[, Date := as.Date(Date)]
  ymf <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
  m26[, ymi := ymf(Date)]
  for (k in seq_len(n_m)) { r <- m26[ymi == ymf(MO[[k]]$dd) - 2L & is.finite(M26_Revenue_Mom)]
    MO[[k]]$m26_lag1 <- setNames(r$M26_Revenue_Mom, r$Ticker) } }

.apply_tophi <- function(w_tilt, w_prev, phi, ub) {
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  cm <- intersect(names(w_tilt), names(w_prev)); wp[cm] <- w_prev[cm]
  dr <- 1 - sum(wp); if (dr > 0) wp <- wp + dr*w_tilt
  if (sum(wp) > 0) wp <- wp/sum(wp)
  b <- phi/(1+phi); normalize_long_only(b*wp + (1-b)*w_tilt, lb=0, ub=ub, target_sum=1) }
canon_w <- function(a, wp, ub) { wt <- linear_tilt_qd(a, lambda=LAM, lb=0, ub=ub)
  names(wt) <- names(a); .apply_tophi(wt, wp, 3, ub) }
dnot <- function(c1, p1) { u <- union(names(c1), names(p1))
  x <- setNames(rep(0,length(u)),u); x[names(c1)] <- c1
  y <- setNames(rep(0,length(u)),u); y[names(p1)] <- p1; sum(abs(x-y)) }
zcs <- function(v){ s <- sd(v, na.rm=TRUE); if(!is.finite(s)||s<1e-12) return(rep(0,length(v)))
  z <- (v-mean(v,na.rm=TRUE))/s; z[!is.finite(z)] <- 0; z }
elig_scores <- function(m){ sc <- m$score; tk <- intersect(names(sc), m$elig)
  if (length(tk) < 5L) tk <- names(sc); sc[tk] }
run_arm <- function(select_fn, wgt_fn = function(a,wp,ub,m) canon_w(a,wp,ub)) {
  wp <- NULL; npv <- NULL; gb <- go <- no <- tno <- numeric(n_m)
  for (k in seq_len(n_m)) { m <- MO[[k]]; ub <- if (identical(m$regime,"CRISIS")) UBCR else UB
    a <- select_fn(m); w <- wgt_fn(a, wp, ub, m)
    rv <- m$ret[names(w)]; rv[is.na(rv)] <- 0
    gb[k] <- sum(w*rv); nw <- w*m$inv; go[k] <- gb[k]*m$inv
    tno[k] <- (if (is.null(npv)) sum(abs(nw)) else dnot(nw, npv))
    no[k] <- go[k] - BPS*tno[k]; wp <- w; npv <- nw }
  list(ret_net = no, turn = tno) }
nw_t <- function(x, L=3){ x <- x[is.finite(x)]; n <- length(x); m <- mean(x); e <- x-m
  s <- sum(e^2)/n; for (l in 1:L){ ga <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s+2*(1-l/(L+1))*ga }
  m/sqrt(s/n) }
IRf <- function(r){ a <- r - bmv; mean(a)/sd(a)*sqrt(12) }

## ── 형태 정의 (P2 verbatim) ──────────────────────────────────────────────────
sel_blend <- function(w, get = function(m) m$m26) function(m) { sc <- elig_scores(m); tk <- names(sc)
  b <- zcs(sc) + w*zcs(get(m)[tk]); names(b) <- tk
  o <- order(-b); b[o][seq_len(min(TOPN,length(o)))] }
sel_filter <- function(get = function(m) m$m26) function(m) { sc <- elig_scores(m); tk <- names(sc)
  mv <- get(m)[tk]; ok <- rep(TRUE,length(tk)); names(ok) <- tk; fin <- is.finite(mv)
  if (sum(fin) >= 20) { thr <- quantile(mv[fin], 0.10, na.rm=TRUE, names=FALSE); ok[fin & mv <= thr] <- FALSE }
  sc2 <- sc[ok]; N <- min(TOPN,length(sc2)); if (N < MINN && length(sc2) >= MINN) N <- MINN
  sc2[order(-sc2)][seq_len(N)] }
sel_carve <- function(get = function(m) m$m26) function(m) { sc <- elig_scores(m); tk <- names(sc)
  mv <- get(m)[tk]; b16 <- names(sort(sc, decreasing=TRUE))[seq_len(min(16L,length(sc)))]
  rest <- setdiff(tk,b16); mvr <- mv[rest]; mvr <- mvr[is.finite(mvr)]
  cv <- if (length(mvr)) names(sort(mvr, decreasing=TRUE))[seq_len(min(4L,length(mvr)))] else character(0)
  c(sc[b16], setNames(rep(NA_real_,length(cv)), cv)) }
wgt_carve <- function(a, wp, ub, m) { ic <- is.na(a); b16 <- a[!ic]; cv <- names(a)[ic]
  wt <- linear_tilt_qd(b16, lambda=LAM, lb=0, ub=ub); names(wt) <- names(b16)
  if (length(cv)) { wt <- wt*0.80; wt <- c(wt, setNames(rep(0.20/length(cv),length(cv)), cv)) }
  .apply_tophi(wt, wp, 3, ub) }

perm_get <- function(seed_off) function(m) { v <- m$m26
  if (!length(v)) return(setNames(numeric(0), character(0)))
  setNames(sample(unname(v)), names(v)) }

## ── P3-A. 형태별 크기-정합 placebo (각 12 draw) ──────────────────────────────
forms <- list(
  F_A_blend030 = list(sel = function(g) sel_blend(0.30, g), wgt = NULL,  real = P2$A_A),
  F_B_filterD1 = list(sel = function(g) sel_filter(g),      wgt = NULL,  real = P2$A_B),
  F_C_carve4   = list(sel = function(g) sel_carve(g),       wgt = wgt_carve, real = P2$A_C))

set.seed(4165)
RES3 <- rbindlist(lapply(names(forms), function(fn) {
  f <- forms[[fn]]
  wgtf <- if (is.null(f$wgt)) function(a,wp,ub,m) canon_w(a,wp,ub) else f$wgt
  pls <- lapply(1:12, function(s) run_arm(f$sel(perm_get(s)), wgtf))
  pmat <- sapply(pls, function(A) A$ret_net); pmed <- apply(pmat, 1, median)
  d_base  <- f$real$ret_net - BASE$ret_net
  d_plc   <- f$real$ret_net - pmed
  pl_dIR  <- sapply(pls, function(A) IRf(A$ret_net) - IRf(BASE$ret_net))
  pl_dann <- sapply(pls, function(A) mean(A$ret_net - BASE$ret_net)*12*100)
  data.table(form = fn,
    real_delta_IR = IRf(f$real$ret_net) - IRf(BASE$ret_net),
    real_paired_ann_pct = mean(d_base)*12*100, real_paired_t = nw_t(d_base),
    placebo_delta_IR_median = median(pl_dIR),
    placebo_delta_IR_q05 = quantile(pl_dIR,.05), placebo_delta_IR_q95 = quantile(pl_dIR,.95),
    placebo_paired_ann_median = median(pl_dann),
    info_delta_IR = IRf(f$real$ret_net) - IRf(pmed),
    info_ann_pct = mean(d_plc)*12*100, info_t_nw3 = nw_t(d_plc),
    ## 순열 분포 대비 실제의 위치 (경험적 p, 양측 아님 — 실제가 placebo 보다 큰 비율)
    emp_pct_rank = mean(pl_dIR < (IRf(f$real$ret_net) - IRf(BASE$ret_net))))
}))
cat("\n===== [P3-A] 형태별 크기-정합 placebo 대조 =====\n")
print(RES3[, .(form, real_delta_IR = round(real_delta_IR,4),
               placebo_dIR_med = round(placebo_delta_IR_median,4),
               placebo_dIR_90band = sprintf("[%.4f, %.4f]", placebo_delta_IR_q05, placebo_delta_IR_q95),
               info_delta_IR = round(info_delta_IR,4),
               info_ann_pct = round(info_ann_pct,3), info_t = round(info_t_nw3,3),
               emp_pct_rank = round(emp_pct_rank,3))])
cat("\n  읽는 법: real_delta_IR 이 placebo 90%% 밴드 **안**이면 그 형태의 손실은 M26 정보 때문이 아니라\n")
cat("           개입 자체의 잡음 비용이다(기전 (a)). 밴드 아래로 벗어나면 기전 (b) 역방향 정보.\n")

## ── P3-B. 개입 규모 → 잡음 바닥 곡선 (placebo 만으로) ────────────────────────
set.seed(777)
sizes <- c(0.05, 0.10, 0.20, 0.30, 0.50)
NF <- rbindlist(lapply(sizes, function(w) {
  pls <- lapply(1:6, function(s) run_arm(sel_blend(w, perm_get(s))))
  nrep <- mean(sapply(seq_len(n_m), function(k) {
    m <- MO[[k]]; s <- elig_scores(m); b <- names(s[order(-s)][seq_len(min(TOPN,length(s)))])
    length(setdiff(names(sel_blend(w, perm_get(1))(m)), b)) }))
  data.table(w = w, names_replaced = nrep,
             placebo_dIR = median(sapply(pls, function(A) IRf(A$ret_net) - IRf(BASE$ret_net))),
             placebo_ann_pct = median(sapply(pls, function(A) mean(A$ret_net - BASE$ret_net)*12*100)))
}))
cat("\n===== [P3-B] 잡음 바닥 곡선 (순열 M26 = 정보 0, 개입 규모만 변화) =====\n"); print(NF)
cat("  ⇒ 정보가 0 이어도 개입 규모에 비례해 ΔIR 이 음수로 간다. **base 대비 ΔIR 은 정보의 척도가 아니다.**\n")

## ── P3-C. 교체 종목 직접 분해 (승자 컷인가) ──────────────────────────────────
dec <- rbindlist(lapply(seq_len(n_m), function(k) {
  m <- MO[[k]]; s <- elig_scores(m)
  b <- names(s[order(-s)][seq_len(min(TOPN,length(s)))])
  a <- names(sel_blend(0.30)(m))
  dropped <- setdiff(b,a); added <- setdiff(a,b)
  if (!length(dropped) || !length(added)) return(NULL)
  rd <- m$ret[dropped]; ra <- m$ret[added]
  data.table(k = k, dd = m$dd, n_swap = length(added),
             ret_dropped = mean(rd, na.rm=TRUE), ret_added = mean(ra, na.rm=TRUE),
             m26_rank_dropped = mean(rank(-m$m26[intersect(dropped, names(m$m26))]), na.rm=TRUE))
}))
dec[, edge := ret_added - ret_dropped]
cat(sprintf("\n===== [P3-C] 교체 종목 실현수익 분해 (F_A, %d개월) =====\n", nrow(dec)))
cat(sprintf("  들어온 종목 월평균 %+.4f%% · 빠진 종목 %+.4f%% · edge %+.4f%%/월 (연 %+.3f%%) · NW3 t %+.3f\n",
            mean(dec$ret_added)*100, mean(dec$ret_dropped)*100, mean(dec$edge)*100,
            mean(dec$edge)*12*100, nw_t(dec$edge)))
cat(sprintf("  월평균 교체 %.2f 종목 · edge 양수 월 비율 %.3f\n", mean(dec$n_swap), mean(dec$edge > 0)))
cat("  ★해석: edge 는 **종목 수준** 순수 선별 효과(비중·비용·overlay 제외). 포트폴리오 ΔIR 과 분리해 읽는다.\n")

## ── P3-D. 시대 조건화 (연속, 분할 금지 — advisory) ───────────────────────────
d_A <- P2$A_A$ret_net - BASE$ret_net
tt <- as.numeric(eval_dates - min(eval_dates))/365.25
fit <- lm(d_A ~ tt)
cat(sprintf("\n[P3-D advisory] paired 차이의 시간 추세: 기울기 %+.5f/yr (t %+.3f) · 절편 %+.5f — 분할 없이 연속 조건화\n",
            coef(fit)[2], summary(fit)$coefficients[2,3], coef(fit)[1]))

fwrite(RES3, file.path(OUT, "p3_placebo_matched.csv"))
fwrite(NF,   file.path(OUT, "p3_noise_floor.csv"))
fwrite(dec,  file.path(OUT, "p3_swap_decomp.csv"))
saveRDS(list(RES3=RES3, NF=NF, dec=dec, trend=fit), file.path(OUT, "p3_mechanism.rds"))
cat("\n[saved] p3_placebo_matched.csv / p3_noise_floor.csv / p3_swap_decomp.csv\n")
