## WT-D20260822_006 (FQ-246) P2 — arm 구성 + 대조군 parity + 검정력 관문 (★MEAN-BLIND)
## ★본 파일은 처치 arm 의 paired 평균·t 를 출력하지 않는다. 출력 = parity / sd / nw / MDE / 매개이동.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
source("02_Infrastructure/contracts/cluster_power.R")
OUT <- "stage_artifacts/WT-D20260822_006"; W004 <- "stage_artifacts/WT-D20260822_004"
SRC <- "stage_artifacts/fq233_probe0_20260813"

## ── 사전고정 상수 (스윕 0회) ────────────────────────────────────────────────
K <- 5L; TOPN <- 25L; COST <- 15; MIN_WARM <- 36L; UCLIP <- 2.0; SEED <- 20260822L

A  <- readRDS(file.path(W004,"p1_arms.rds"))
ST <- readRDS(file.path(OUT,"p1b_state.rds"))
FM <- readRDS(file.path(OUT,"p1c_family.rds"))
sel_rank <- A$sel_rank; months <- names(sel_rank); returns_dt <- A$returns_dt; bench_dt <- A$bench_dt
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A$anchors & is.finite(fwd_ret_1m)]
stopifnot(length(months) == 221L)

## ── 계열 방향 g_k (사전고정 · 기전 자구에서만 도출; 기전이 언급 않은 계열 = 0) ──
G_POS <- c("liquidity","crowding","investor_flow")                                   # 유동성공급·포지셔닝
G_NEG <- c("value","quality","growth","accrual","consensus","leverage")              # 펀더멘털
gmap <- FM$REG[, .(factor_id, category)]
gmap[, g := fifelse(category %in% G_POS, 1, fifelse(category %in% G_NEG, -1, 0))]
GV <- setNames(gmap$g, gmap$factor_id)
selall <- sort(unique(unlist(sel_rank)))
cat("g_k 분포 (선별 이력 103종):\n"); print(table(GV[selall]))

## ── 상태 u_t: 확장창 표준화 + clip. warm-up 36개월은 u=0 (arm ≡ C0) ────────
mk_u <- function(x) { n <- length(x); u <- rep(0, n)
  for (i in seq_len(n)) { if (i < MIN_WARM) next
    m <- mean(x[1:i], na.rm=TRUE); s <- sd(x[1:i], na.rm=TRUE)
    if (!is.finite(s) || s <= 0) next
    u[i] <- max(-UCLIP, min(UCLIP, (x[i]-m)/s)) }
  u[!is.finite(u)] <- 0; u }
setorder(ST, Date); stopifnot(identical(as.character(ST$Date), months))

## 축1 = 불일치 (당월 z 횡단면만의 함수 — 성과 무개입, C0 와 동일 vintage)
U_AGREE <- mk_u(ST$disagree)
## 축2 = 수익 횡단면 분산 (t-1 까지 실현분만 — 홀딩월 자기 분산 사용 금지)
dsp <- panh[, .(d = sd(fwd_ret_1m, na.rm=TRUE)), by=.(Date=anchor)][order(Date)]
dsp <- dsp[Date %in% as.Date(months)]
stopifnot(nrow(dsp) == 221L)
dsp[, d_lag1 := shift(d, 1L)]
dl <- dsp$d_lag1; dl[1] <- dsp$d[1]                     # 첫 달은 warm-up 구간이라 u=0 으로 흡수됨
U_DISP <- mk_u(dl)
## 보조축 = bear_prob (성과-파생, 강등 — 대조 arm 전용)
bpx <- ST$bp_mean
U_BEAR <- mk_u(ifelse(is.na(bpx), mean(bpx, na.rm=TRUE), bpx)); U_BEAR[is.na(bpx)] <- 0
set.seed(SEED); U_SHUF_A <- U_AGREE[sample.int(221L)]
set.seed(SEED + 1L); U_SHUF_D <- U_DISP[sample.int(221L)]
U_LAG1 <- c(0, head(U_AGREE, -1))
cat(sprintf("\nu_agree sd %.4f (nonzero %d/221, AR1 %.4f) · u_disp sd %.4f (nonzero %d, AR1 %.4f) · u_bear sd %.4f (nonzero %d)\n",
  sd(U_AGREE), sum(U_AGREE!=0), cor(U_AGREE[-1],U_AGREE[-221]),
  sd(U_DISP), sum(U_DISP!=0), cor(U_DISP[-1],U_DISP[-221]), sd(U_BEAR), sum(U_BEAR!=0)))
cat(sprintf("cor(u_agree, u_disp) = %+.4f  (두 축 독립성)\n", cor(U_AGREE, U_DISP)))

zc <- function(v) { ok <- is.finite(v); r <- rep(NA_real_, length(v))
  if (sum(ok) >= 5L && sd(v[ok]) > 0) r[ok] <- (v[ok]-mean(v[ok]))/sd(v[ok]); r }
wavg <- function(Z, w) { Wm <- matrix(w, nrow=nrow(Z), ncol=length(w), byrow=TRUE)
  Wm[!is.finite(Z)] <- 0; Z0 <- Z; Z0[!is.finite(Z0)] <- 0
  den <- rowSums(Wm); ifelse(den > 0, rowSums(Z0*Wm)/den, NA_real_) }

## ── arm 규칙 (전부 u=0 에서 정확히 C0 로 환원) ───────────────────────────────
build <- function(kind, ua = rep(0,221), ud = rep(0,221)) rbindlist(lapply(seq_along(months), function(m) {
  nm <- months[m]; fs <- sel_rank[[nm]]; d <- panh[anchor == as.Date(nm)]
  Z <- as.matrix(d[, ..fs]); nv <- rowSums(is.finite(Z))
  sc <- if (kind == "C0") rowMeans(Z, na.rm=TRUE)
  else if (kind == "T1") {                                  # 확신 첨예화 (불일치 축)
    c0 <- zc(rowMeans(Z, na.rm=TRUE))
    mx <- zc(apply(Z, 1L, function(x) if (all(!is.finite(x))) NA_real_ else max(x, na.rm=TRUE)))
    p <- plogis(ua[m]) - 0.5
    ifelse(is.finite(c0) & is.finite(mx), c0 + p*(mx - c0), c0)
  } else {                                                   # 팩터 가중 = 멤버십 선택
    keep <- colSums(is.finite(Z)) >= 30L
    if (sum(keep) < 2L) rowMeans(Z, na.rm=TRUE) else {
      Zk <- Z[, keep, drop=FALSE]; fk <- fs[keep]
      lw <- rep(0, ncol(Zk))
      if (kind %in% c("T2","T4")) {                          # 중심성 (불일치 축)
        cm <- suppressWarnings(cor(Zk, method="spearman", use="pairwise.complete.obs"))
        cen <- rowMeans(cm - diag(diag(cm)), na.rm=TRUE) * (ncol(cm)/(ncol(cm)-1))
        ct <- if (sd(cen, na.rm=TRUE) > 0) (cen-mean(cen,na.rm=TRUE))/sd(cen,na.rm=TRUE) else cen*0
        ct[!is.finite(ct)] <- 0; lw <- lw + ua[m]*ct }
      if (kind %in% c("T3","T4")) {                          # 계열 방향 (분산 축)
        gk <- GV[fk]; gk[!is.finite(gk)] <- 0; lw <- lw + ud[m]*as.numeric(gk) }
      w <- exp(lw); w <- w/sum(w); wavg(Zk, w) }
  }
  data.table(Date=as.Date(nm), Ticker=as.character(d$Ticker),
             score=ifelse(nv >= 1L, sc, NA_real_))[is.finite(score)] }))

cat("\n=== 1) arm 스코어 구성 ===\n")
Z0 <- rep(0, 221)
SC <- list()
SC$C0        <- build("C0")
SC$T2_AGREE  <- build("T2", ua=U_AGREE)                     # co-primary (축1: 선택 강도)
SC$T3_DISP   <- build("T3", ud=U_DISP)                      # co-primary (축2: 계열 방향)
SC$T1_AGREE  <- build("T1", ua=U_AGREE)                     # secondary (축1 다른 형태)
SC$T4_BOTH   <- build("T4", ua=U_AGREE, ud=U_DISP)          # secondary (두 축 결합)
SC$T3_BEAR   <- build("T3", ud=U_BEAR)                      # 강등 대조 (성과-파생 축)
SC$N1_SHUF_A <- build("T2", ua=U_SHUF_A)                    # 음성대조 (상태 셔플)
SC$N2_SHUF_D <- build("T3", ud=U_SHUF_D)                    # 음성대조 (상태 셔플)
SC$T2_LAG1   <- build("T2", ua=U_LAG1)                      # PIT 스트레스 (상태 1개월 지연)
for (a in names(SC)) cat(sprintf("  %-10s %6d행 · %d개월\n", a, nrow(SC[[a]]), uniqueN(SC[[a]]$Date)))

cat("\n=== 2) 축 정합 (합성 → forward rank-IC 부호) ===\n")
fwd <- panh[, .(Date=anchor, Ticker=as.character(Ticker), fwd=fwd_ret_1m)]
for (a in names(SC)) { j <- merge(SC[[a]], fwd, by=c("Date","Ticker"))
  ic <- j[, .(ic=if (.N>=30 && sd(score)>0) cor(rank(score), rank(fwd)) else NA_real_), by=Date]
  cat(sprintf("  %-10s 평균 rank-IC %+.5f\n", a, mean(ic$ic, na.rm=TRUE))) }

cat("\n=== 3) canonical_screen_bt (top-25 EW long-only · 15bps · 동점 Ticker 오름차순) ===\n")
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
  d <- act[[a]]$act - c0; n <- length(d); n_eff <- sum(d != 0)
  sd_m <- sd(d); nwi <- nw_inflation_measured(d, lag=3L)
  ro <- required_effect(n=n, t_threshold=2.0, sd_monthly=sd_m, nw_inflation=nwi)
  rb <- required_effect(n=n, t_threshold=2.0)
  se_arm <- sd_m*nwi/sqrt(n)
  data.table(arm=a, n=n, n_active_months=n_eff,
    sd_monthly_own=round(sd_m,6), sd_ratio_vs_contract=round(sd_m/SPREAD_SD_MONTHLY_25EW,4),
    nw_inflation_measured=round(nwi,4),
    mde_own_annual_pct=round(ro$required_annual*100,4),
    mde_band_annual_pct=round(rb$required_annual*100,4),
    implied_t_own=round(ro$required_monthly/se_arm,4),
    implied_t_band=round(rb$required_monthly/se_arm,4),
    material_over_mde_own=round(MATERIAL/(ro$required_annual*100),4)) }))
print(PW)

cat("\n=== 6) 매개 이동 F2 (top-25 멤버십 이동; 평균수익 미노출) ===\n")
top25 <- function(s) { s <- copy(s); setorder(s, Date, -score, Ticker)
  s[, .(tk=list(head(Ticker, TOPN))), by=Date] }
T0 <- top25(SC$C0)
MED <- rbindlist(lapply(setdiff(names(SC),"C0"), function(a) {
  TA <- top25(SC[[a]]); j <- merge(T0, TA, by="Date")
  jac <- mapply(function(x,y) length(intersect(x,y))/length(union(x,y)), j$tk.x, j$tk.y)
  data.table(arm=a, jaccard_median=round(median(jac),4), moved_median=round(median(TOPN*(1-jac)),2)) }))
print(MED)

cat("\n=== 7) F1 군집 검정력 사전 선언 (cluster_power.R — 착수 전 호출 의무) ===\n")
ncl <- uniqueN(FM$M$category)
cat("  선별 이력 103종의 선언 계열 수 =", ncl, " (registry category · 이름 접두 유추 금지)\n")
cp <- cp_declare(target_rho = 0.40, n_clusters = ncl, n_obs = 221L*K)
print(cp)

saveRDS(list(SC=SC, BT=BT, act=act,
             U=list(AGREE=U_AGREE, DISP=U_DISP, BEAR=U_BEAR, SHUF_A=U_SHUF_A, SHUF_D=U_SHUF_D, LAG1=U_LAG1),
             GV=GV, G_POS=G_POS, G_NEG=G_NEG, PW=PW, MED=MED, cp=cp,
             MATERIAL=MATERIAL, SE_C0=SE_C0, MEAN_C0=MEAN_C0,
             K=K, TOPN=TOPN, COST=COST, MIN_WARM=MIN_WARM, UCLIP=UCLIP, SEED=SEED),
        file.path(OUT,"p2_arms.rds"))
cat("\n[saved] p2_arms.rds\nOK (MEAN-BLIND)\n")
