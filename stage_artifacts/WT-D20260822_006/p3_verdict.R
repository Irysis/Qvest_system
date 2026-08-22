## WT-D20260822_006 (FQ-246) P3 — 사전등록 판정 (봉인 후 실행)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_006"; W004 <- "stage_artifacts/WT-D20260822_004"
W002 <- "stage_artifacts/WT-D20260822_002"; SRC <- "stage_artifacts/fq233_probe0_20260813"
P <- readRDS(file.path(OUT,"p2_arms.rds")); act <- P$act; c0 <- act$C0$act
MATERIAL <- P$MATERIAL; U <- P$U; SC <- P$SC; BT <- P$BT; TOPN <- P$TOPN
A4 <- readRDS(file.path(W004,"p1_arms.rds")); sel_rank <- A4$sel_rank; months <- names(sel_rank)
V4 <- readRDS(file.path(W004,"p4_verdict.rds"))
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet"))); pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]

pairedstat <- function(x, y, lab) { d <- x - y; t <- .nw_t_mean(d, lag=3L)
  se_m <- abs(mean(d)/t); ann <- mean(d)*12*100; se_a <- se_m*12*100
  data.table(contrast=lab, n=length(d), ann_pct=ann, t_nw3=t,
             ci95_lo=ann-1.96*se_a, ci95_hi=ann+1.96*se_a) }
lab_of <- function(t, hi) fifelse(t>=2,"EFFECT_POSITIVE", fifelse(t<=-2,"EFFECT_NEGATIVE",
  fifelse(hi<MATERIAL,"POWERED_NULL_NO_MATERIAL_EFFECT","UNDERPOWERED_UNRESOLVED")))

nw_slope_t <- function(y, x) {
  fit <- lm(y ~ x); b <- coef(fit)[2]; e <- residuals(fit); X <- cbind(1, x)
  bread <- solve(crossprod(X)); meat <- crossprod(X * e)
  n <- length(e)
  for (l in 1:3) { w <- 1 - l/4
    G <- crossprod(X[(l+1):n, , drop=FALSE] * e[(l+1):n], X[1:(n-l), , drop=FALSE] * e[1:(n-l)])
    meat <- meat + w * (G + t(G)) }
  Vc <- bread %*% meat %*% bread
  list(slope = unname(b), t = unname(b/sqrt(Vc[2,2]))) }

cat("=== R1 수송 게이트 (STOP, 성과 판정 전) ===\n")
ok <- V4$act$ORACLE_K$act; stopifnot(length(ok) == length(c0))
hz <- ok - c0; u <- U$AGREE; us <- (u - mean(u))/sd(u)
s1 <- nw_slope_t(hz, us)
cat(sprintf("  slope(ORACLE_K 여유폭 ~ 표준화 disagreement) = %+.6f (월) · NW3 t = %+.4f\n", s1$slope, s1$t))
cat(sprintf("  연환산 기울기 %+.4f %%p/yr per 1sd · 여유폭 평균 %+.4f %%p/yr\n", s1$slope*12*100, mean(hz)*12*100))
ub <- U$BEAR; s2 <- nw_slope_t(hz, (ub-mean(ub))/sd(ub))
cat(sprintf("  [보조축 bear_prob] slope %+.6f · NW3 t %+.4f\n", s2$slope, s2$t))
R1 <- list(state_axis="agreement_disagreement", slope_monthly=s1$slope, t_nw3=s1$t,
           annual_per_sd=s1$slope*12*100, headroom_mean_annual=mean(hz)*12*100,
           bear_axis_slope=s2$slope, bear_axis_t=s2$t, threshold="|t| >= 1.5",
           fired = abs(s1$t) < 1.5,
           verdict = if (abs(s1$t) >= 1.5) "수송 확인 — ORACLE_K 여유폭이 상태축에 종속" else
                     "MECHANISM_NOT_TRANSPORTED — 여유폭이 이 상태축에 무관")
cat("  ", R1$verdict, "\n")

cat("\n=== 1) primary paired (arm - C0), NW lag-3, n=221 ===\n")
arms_pri <- c("T1_AGREE","T2_AGREE","T2_BEAR","N1_SHUF","T2_LAG1")
PRI <- rbindlist(lapply(arms_pri, function(a) pairedstat(act[[a]]$act, c0, a)))
PRI[, label := lab_of(t_nw3, ci95_hi)]
PRI[, role := c("co_primary","co_primary","secondary_window147","negative_control_state_shuffle","pit_stress_state_lag1")]
print(PRI[, .(contrast, role, ann_pct=round(ann_pct,4), t_nw3=round(t_nw3,4),
              ci95=paste0("[",round(ci95_lo,2),", ",round(ci95_hi,2),"]"), label)])
cat(sprintf("  MATERIAL = %.4f %%p/yr\n", MATERIAL))

cat("\n=== 2) 양성 대조 ORACLE_STATE (규칙 형태 도달가능성) ===\n")
zc <- function(v){ok<-is.finite(v);r<-rep(NA_real_,length(v));if(sum(ok)>=5L&&sd(v[ok])>0)r[ok]<-(v[ok]-mean(v[ok]))/sd(v[ok]);r}
icdiff <- vapply(seq_along(months), function(m){ nm<-months[m]; fs<-sel_rank[[nm]]; d<-panh[anchor==as.Date(nm)]
  Z<-as.matrix(d[,..fs]); f<-d$fwd_ret_1m
  s0<-rowMeans(Z,na.rm=TRUE); sm<-apply(Z,1L,function(x) if(all(!is.finite(x))) NA_real_ else max(x,na.rm=TRUE))
  okk<-is.finite(s0)&is.finite(sm)&is.finite(f); if(sum(okk)<30) return(0)
  cor(rank(sm[okk]),rank(f[okk])) - cor(rank(s0[okk]),rank(f[okk])) }, 0)
uo <- (icdiff-mean(icdiff))/sd(icdiff); uo <- pmax(-2,pmin(2,uo))
buildT1 <- function(uv) rbindlist(lapply(seq_along(months), function(m){
  nm<-months[m]; fs<-sel_rank[[nm]]; d<-panh[anchor==as.Date(nm)]
  Z<-as.matrix(d[,..fs]); nv<-rowSums(is.finite(Z))
  c0z<-zc(rowMeans(Z,na.rm=TRUE)); mx<-zc(apply(Z,1L,function(x) if(all(!is.finite(x))) NA_real_ else max(x,na.rm=TRUE)))
  p<-plogis(uv[m])-0.5; sc<-ifelse(is.finite(c0z)&is.finite(mx), c0z+p*(mx-c0z), c0z)
  data.table(Date=as.Date(nm),Ticker=as.character(d$Ticker),score=ifelse(nv>=1L,sc,NA_real_))[is.finite(score)] }))
SO <- buildT1(uo); setorder(SO, Date, Ticker)
BO <- canonical_screen_bt(SO[,.(Date,Ticker,score)], A4$returns_dt, A4$bench_dt, top_n=TOPN,
        cost_bps_oneway=15, run_id="FQ246_ORACLE_STATE", strategy_id="FQ246_ORACLE_STATE", diag_dual_basis=TRUE)
ao <- as.data.table(BO$period_returns)[, .(Date=as.Date(date), act=ret_net-benchmark_ret)]
PC <- pairedstat(ao$act, c0, "ORACLE_STATE_T1"); PC[, label := lab_of(t_nw3, ci95_hi)]
print(PC[, .(contrast, ann_pct=round(ann_pct,4), t_nw3=round(t_nw3,4), label)])
cat(sprintf("  사전등록 문턱 t >= +2.0 · ORACLE_STATE PORT_t(IKS200) = %.4f\n", BO$portfolio_alpha_t_nw_lag3))

cat("\n=== 3) 창-도달가능성 (FQ-244 기측정 인용) ===\n")
OKp <- pairedstat(V4$act$ORACLE_K$act, c0, "ORACLE_K"); OFp <- pairedstat(V4$act$ORACLE$act, c0, "ORACLE_FWD")
print(rbind(OKp,OFp)[, .(contrast, ann_pct=round(ann_pct,4), t_nw3=round(t_nw3,4))])

cat("\n=== 4) basis 3종 ===\n")
p0r <- readRDS(file.path(W002,"p0_returns.rds"))
bench_parent <- as.data.table(p0r$bench)[, .(Date, BM_Ret)]; liq_dt <- as.data.table(p0r$liq)
runb <- function(s,b,id,liq=NULL){s<-copy(s);setorder(s,Date,Ticker)
  canonical_screen_bt(s[,.(Date,Ticker,score)],A4$returns_dt,b,top_n=TOPN,cost_bps_oneway=15,
    liq_dt=liq,liq_min=2e8,run_id=id,strategy_id=id,diag_dual_basis=TRUE)}
BASl <- lapply(setNames(names(SC),names(SC)), function(a) runb(SC[[a]], bench_parent, paste0("FQ246par_",a)))
actp <- lapply(BASl, function(b) as.data.table(b$period_returns)[, ret_net-benchmark_ret])
c0p <- actp$C0
BAS <- rbindlist(lapply(names(SC), function(a) data.table(
  arm=a, port_t_IKS200=BT[[a]]$portfolio_alpha_t_nw_lag3,
  port_t_parent=BASl[[a]]$portfolio_alpha_t_nw_lag3,
  port_t_EW=BT[[a]]$diag_ew_universe$portfolio_alpha_t_nw_lag3,
  ir_IKS200=BT[[a]]$information_ratio, turnover=BT[[a]]$turnover_annual,
  paired_t_parent=if (a=="C0") NA_real_ else pairedstat(actp[[a]], c0p, a)$t_nw3,
  paired_t_iks=if (a=="C0") NA_real_ else PRI[contrast==a, t_nw3])))
BAS[, basis_delta_t := paired_t_parent - paired_t_iks]
print(BAS[, .(arm, port_t_IKS200=round(port_t_IKS200,4), port_t_parent=round(port_t_parent,4),
              port_t_EW=round(port_t_EW,4), ir=round(ir_IKS200,4), turnover=round(turnover,2),
              basis_delta_t=signif(basis_delta_t,3))])

cat("\n=== 5) 매개 이동 R2 + 상태-변위 연동 R3 ===\n")
top25 <- function(s){s<-copy(s);setorder(s,Date,-score,Ticker);s[,.(tk=list(head(Ticker,TOPN))),by=Date]}
T0 <- top25(SC$C0)
R23 <- rbindlist(lapply(setdiff(names(SC),"C0"), function(a){
  TA <- top25(SC[[a]]); j <- merge(T0,TA,by="Date")
  jac <- mapply(function(x,y) length(intersect(x,y))/length(union(x,y)), j$tk.x, j$tk.y)
  uu <- if (a=="T2_BEAR") U$BEAR else if (a=="N1_SHUF") U$SHUF else if (a=="T2_LAG1") U$LAG1 else U$AGREE
  data.table(arm=a, jaccard_median=median(jac), moved_median=round(median(TOPN*(1-jac)),2),
             cor_absU_displacement=cor(abs(uu), 1-jac),
             r2_pass = median(jac) <= 0.9) }))
print(R23)

cat("\n=== 6) 강건성 ===\n")
LIQl <- lapply(setNames(names(SC),names(SC)), function(a) runb(SC[[a]], A4$bench_dt, paste0("FQ246liq_",a), liq_dt))
actl <- lapply(LIQl, function(b) as.data.table(b$period_returns)[, ret_net-benchmark_ret])
LIQ <- rbindlist(lapply(names(SC), function(a) data.table(arm=a,
  port_t_liq=LIQl[[a]]$portfolio_alpha_t_nw_lag3, n_liq=LIQl[[a]]$n_months,
  paired_t_liq=if (a=="C0") NA_real_ else pairedstat(actl[[a]], actl$C0, a)$t_nw3)))
print(LIQ)
dts <- act$C0$Date; cutd <- as.Date("2015-07-01")
SUB <- rbindlist(lapply(c("T1_AGREE","T2_AGREE"), function(a){ d <- act[[a]]$act-c0
  data.table(arm=a, pre_t=.nw_t_mean(d[dts<cutd],3L), post_t=.nw_t_mean(d[dts>=cutd],3L),
             pre_n=sum(dts<cutd), post_n=sum(dts>=cutd)) }))
print(SUB); cat("  ★진단 병기만 — era 교락 + universe_exit_unrecorded_pre201512(편향 하방/중립). 국면 주장 승격 금지.\n")
TOP5 <- rbindlist(lapply(c("T1_AGREE","T2_AGREE"), function(a){ d <- act[[a]]$act-c0
  o <- order(d, decreasing=TRUE); data.table(arm=a, full_ann=mean(d)*12*100, ex5_ann=mean(d[-o[1:5]])*12*100) }))
print(TOP5)

cat("\n=== 7) advisory 배터리 ===\n")
fwd <- panh[, .(Date=anchor, Ticker=as.character(Ticker), fwd=fwd_ret_1m)]
ADV <- rbindlist(lapply(names(SC), function(a){ j <- merge(SC[[a]], fwd, by=c("Date","Ticker"))
  icd <- j[, .(ic=if(.N>=30&&sd(score)>0) cor(rank(score),rank(fwd)) else NA_real_), by=Date]
  ic <- icd$ic; icdt <- icd$Date
  dec <- j[, {q<-cut(frank(score),breaks=quantile(frank(score),0:10/10),include.lowest=TRUE,labels=FALSE)
              .(d=seq_len(10), r=as.numeric(tapply(fwd,q,mean)))}, by=Date][, .(mr=mean(r,na.rm=TRUE)), by=d]
  mono <- cor(dec$d, dec$mr, method="spearman")
  s1i<-ic[icdt<as.Date("2014-01-01")]; s2i<-ic[icdt>=as.Date("2014-01-01")&icdt<as.Date("2020-01-01")]; s3i<-ic[icdt>=as.Date("2020-01-01")]
  sp <- mean(c(mean(s1i,na.rm=TRUE),mean(s2i,na.rm=TRUE),mean(s3i,na.rm=TRUE))>0)
  data.table(arm=a, rank_ic=mean(ic,na.rm=TRUE), icir=mean(ic,na.rm=TRUE)/sd(ic,na.rm=TRUE),
             ic_t_nw3=.nw_t_mean(ic[is.finite(ic)],3L), monotonicity=mono, subperiod_stability=sp,
             turnover=BT[[a]]$turnover_annual, port_t=BT[[a]]$portfolio_alpha_t_nw_lag3) }))
print(ADV[, lapply(.SD, function(x) if(is.numeric(x)) round(x,4) else x)])
cat("  ★rank-IC t 와 portfolio-alpha t 는 다른 양이다 (Cycle 2 교훈) — ic_t_nw3 vs port_t 대조.\n")

saveRDS(list(R1=R1, PRI=PRI, PC=PC, ORACLE=rbind(OKp,OFp), BAS=BAS, R23=R23, LIQ=LIQ,
             SUB=SUB, TOP5=TOP5, ADV=ADV, MATERIAL=MATERIAL, BO=BO, uo=uo, icdiff=icdiff,
             oracle_state_port_t=BO$portfolio_alpha_t_nw_lag3),
        file.path(OUT,"p3_verdict.rds"))
cat("\n[saved] p3_verdict.rds\nOK\n")
