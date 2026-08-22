## WT-D20260822_006 (FQ-246) P2 — arm 구성 + 대조군 parity + 검정력 관문 (★MEAN-BLIND)
## ★본 파일은 처치 arm 의 paired 평균·t 를 출력하지 않는다. 출력 = parity / sd / nw / MDE / 매개이동.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
OUT <- "stage_artifacts/WT-D20260822_006"; W004 <- "stage_artifacts/WT-D20260822_004"
SRC <- "stage_artifacts/fq233_probe0_20260813"

## ── 사전고정 상수 (스윕 0회) ────────────────────────────────────────────────
K <- 5L; TOPN <- 25L; COST <- 15; MIN_WARM <- 36L; UCLIP <- 2.0; SEED <- 20260822L

A  <- readRDS(file.path(W004,"p1_arms.rds"))
ST <- readRDS(file.path(OUT,"p1b_state.rds"))
sel_rank <- A$sel_rank; months <- names(sel_rank); returns_dt <- A$returns_dt; bench_dt <- A$bench_dt
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A$anchors & is.finite(fwd_ret_1m)]
stopifnot(length(months) == 221L)

## ── 상태 u_t: 확장창 표준화 + clip. warm-up 36개월은 u=0 (arm ≡ C0) ────────
mk_u <- function(x) {
  n <- length(x); u <- rep(0, n)
  for (i in seq_len(n)) {
    if (i < MIN_WARM) next
    m <- mean(x[1:i], na.rm=TRUE); s <- sd(x[1:i], na.rm=TRUE)
    if (!is.finite(s) || s <= 0) next
    u[i] <- max(-UCLIP, min(UCLIP, (x[i]-m)/s))
  }
  u[!is.finite(u)] <- 0; u
}
setorder(ST, Date); stopifnot(identical(as.character(ST$Date), months))
U_AGREE <- mk_u(ST$disagree)                       # 성과 무관 축 (221m 전체)
bpx <- ST$bp_mean; bpx[!is.finite(bpx)] <- NA_real_
U_BEAR <- mk_u(ifelse(is.na(bpx), mean(bpx,na.rm=TRUE), bpx)); U_BEAR[is.na(bpx)] <- 0  # 147m 축
set.seed(SEED); U_SHUF <- U_AGREE[sample.int(length(U_AGREE))]
U_LAG1 <- c(0, head(U_AGREE, -1))
cat(sprintf("u_agree: sd %.4f · |u|>0 인 월 %d/221 · AR1 %.4f\n", sd(U_AGREE),
            sum(U_AGREE!=0), cor(U_AGREE[-1], U_AGREE[-221])))
cat(sprintf("u_bear : sd %.4f · |u|>0 인 월 %d/221\n", sd(U_BEAR), sum(U_BEAR!=0)))

zc <- function(v) { ok <- is.finite(v); r <- rep(NA_real_, length(v))
  if (sum(ok) >= 5L && sd(v[ok]) > 0) r[ok] <- (v[ok]-mean(v[ok]))/sd(v[ok]); r }

## ── arm 규칙 (전부 u_t=0 에서 정확히 C0 로 환원) ─────────────────────────────
## C0 : rowMeans(Z)                                        [대조]
## T1 : zc(C0) + p_t*(zc(maxZ) - zc(C0)),  p_t=plogis(u)-0.5 ∈(-.5,.5)   [확신 첨예화]
## T2 : 팩터 가중 w_k ∝ exp(u_t * c~_k),  c~=월내 표준화 중심성          [멤버십 선택]
build <- function(u, kind) rbindlist(lapply(seq_along(months), function(m) {
  nm <- months[m]; fs <- sel_rank[[nm]]; d <- panh[anchor == as.Date(nm)]
  Z <- as.matrix(d[, ..fs]); nv <- rowSums(is.finite(Z))
  sc <- if (kind == "C0") rowMeans(Z, na.rm=TRUE)
  else if (kind == "T1") {
    c0 <- zc(rowMeans(Z, na.rm=TRUE))
    mx <- zc(apply(Z, 1L, function(x) if (all(!is.finite(x))) NA_real_ else max(x, na.rm=TRUE)))
    p <- plogis(u[m]) - 0.5
    ifelse(is.finite(c0) & is.finite(mx), c0 + p*(mx - c0), c0)
  } else if (kind == "T2") {
    keep <- colSums(is.finite(Z)) >= 30L
    if (sum(keep) < 2L) rowMeans(Z, na.rm=TRUE) else {
      cm <- suppressWarnings(cor(Z[,keep,drop=FALSE], method="spearman", use="pairwise.complete.obs"))
      cen <- rowMeans(cm - diag(diag(cm)), na.rm=TRUE) * (ncol(cm)/(ncol(cm)-1))
      ct <- if (sd(cen, na.rm=TRUE) > 0) (cen-mean(cen,na.rm=TRUE))/sd(cen,na.rm=TRUE) else cen*0
      ct[!is.finite(ct)] <- 0
      w <- exp(u[m]*ct); w <- w/sum(w)
      Zk <- Z[,keep,drop=FALSE]; Wm <- matrix(w, nrow=nrow(Zk), ncol=length(w), byrow=TRUE)
      Wm[!is.finite(Zk)] <- 0; Zk0 <- Zk; Zk0[!is.finite(Zk0)] <- 0
      den <- rowSums(Wm); ifelse(den > 0, rowSums(Zk0*Wm)/den, NA_real_)
    }
  } else stop("kind")
  data.table(Date=as.Date(nm), Ticker=as.character(d$Ticker),
             score=ifelse(nv >= 1L, sc, NA_real_))[is.finite(score)]
}))

cat("\n=== 1) arm 스코어 구성 ===\n")
SC <- list()
SC$C0        <- build(rep(0,221), "C0")
SC$T1_AGREE  <- build(U_AGREE, "T1")
SC$T2_AGREE  <- build(U_AGREE, "T2")
SC$T2_BEAR   <- build(U_BEAR,  "T2")
SC$N1_SHUF   <- build(U_SHUF,  "T2")
SC$T2_LAG1   <- build(U_LAG1,  "T2")
for (a in names(SC)) cat(sprintf("  %-10s %6d행 · %d개월\n", a, nrow(SC[[a]]), uniqueN(SC[[a]]$Date)))

cat("\n=== 2) 축 정합 (합성 → forward rank-IC 부호) ===\n")
fwd <- panh[, .(Date=anchor, Ticker=as.character(Ticker), fwd=fwd_ret_1m)]
for (a in names(SC)) { j <- merge(SC[[a]], fwd, by=c("Date","Ticker"))
  ic <- j[, .(ic=if (.N>=30 && sd(score)>0) cor(rank(score), rank(fwd)) else NA_real_), by=Date]
  cat(sprintf("  %-10s 평균 rank-IC %+.5f\n", a, mean(ic$ic, na.rm=TRUE))) }

cat("\n=== 3) canonical_screen_bt ===\n")
run <- function(s, id) { s <- copy(s); setorder(s, Date, Ticker)
  canonical_screen_bt(s[,.(Date,Ticker,score)], returns_dt, bench_dt, top_n=TOPN,
    cost_bps_oneway=COST, run_id=id, strategy_id=id, diag_dual_basis=TRUE) }
BT <- lapply(setNames(names(SC), names(SC)), function(a) { cat("  ",a,"\n"); run(SC[[a]], paste0("FQ246_",a)) })

cat("\n=== 4) 대조군 parity (FQ-244 공표 0.94741072) ===\n")
cat(sprintf("  C0 PORT_t = %.12f   Δ = %.3e\n", BT$C0$portfolio_alpha_t_nw_lag3,
            BT$C0$portfolio_alpha_t_nw_lag3 - 0.947410715815))

act <- lapply(BT, function(b) { pr <- as.data.table(b$period_returns)
  pr[, .(Date=as.Date(date), act=ret_net - benchmark_ret)] })
c0 <- act$C0$act

cat("\n=== 5) ★검정력 관문 (MEAN-BLIND: sd/nw/MDE 만) ===\n")
MEAN_C0 <- mean(c0); SE_C0 <- abs(MEAN_C0/.nw_t_mean(c0, lag=3L))
MATERIAL <- (2.95*SE_C0 - MEAN_C0)*12*100
cat(sprintf("  C0 월평균 net active %.6f · NW3 SE %.6f · t %.4f\n", MEAN_C0, SE_C0, MEAN_C0/SE_C0))
cat(sprintf("  MATERIAL(벽 2.95 도달 필요 연 증분) = %.4f %%p/yr\n", MATERIAL))
PW <- rbindlist(lapply(setdiff(names(act), "C0"), function(a) {
  d <- act[[a]]$act - c0; n <- length(d)
  sd_m <- sd(d); nwi <- nw_inflation_measured(d, lag=3L)
  re_own <- required_effect(n=n, t_threshold=2.0, sd_monthly=sd_m, nw_inflation=nwi)
  re_bnd <- required_effect(n=n, t_threshold=2.0)
  data.table(arm=a, n=n, sd_monthly_own=sd_m, sd_ratio_vs_contract=sd_m/SPREAD_SD_MONTHLY_25EW,
             nw_inflation_measured=nwi,
             mde_own_annual_pct=re_own$required_annual_pct, mde_band_annual_pct=re_bnd$required_annual_pct,
             implied_t_own=re_own$required_annual_pct/100/12/(sd_m*nwi/sqrt(n)),
             material_over_mde_own=MATERIAL/re_own$required_annual_pct)
}))
print(PW[, lapply(.SD, function(x) if (is.numeric(x)) round(x,5) else x)])

cat("\n=== 6) 매개 이동 (top-25 멤버십이 실제로 움직였는가; 평균수익 미노출) ===\n")
top25 <- function(s) { s <- copy(s); setorder(s, Date, -score, Ticker)
  s[, .(tk=head(Ticker, TOPN)), by=Date] }
T0 <- top25(SC$C0)
MED <- rbindlist(lapply(setdiff(names(SC),"C0"), function(a) {
  TA <- top25(SC[[a]])
  j <- merge(T0[, .(s0=list(tk)), by=Date], TA[, .(s1=list(tk)), by=Date], by="Date")
  jac <- mapply(function(x,y) length(intersect(x,y))/length(union(x,y)), j$s0, j$s1)
  data.table(arm=a, jaccard_median=median(jac), names_changed_median=median(TOPN*(1-jac)/(1+jac)*2)/1)
}))
print(MED)

saveRDS(list(SC=SC, BT=BT, act=act, U=list(AGREE=U_AGREE,BEAR=U_BEAR,SHUF=U_SHUF,LAG1=U_LAG1),
             PW=PW, MED=MED, MATERIAL=MATERIAL, SE_C0=SE_C0, MEAN_C0=MEAN_C0,
             K=K, TOPN=TOPN, COST=COST, MIN_WARM=MIN_WARM, UCLIP=UCLIP, SEED=SEED),
        file.path(OUT,"p2_arms.rds"))
cat("\n[saved] p2_arms.rds\nOK (MEAN-BLIND)\n")
