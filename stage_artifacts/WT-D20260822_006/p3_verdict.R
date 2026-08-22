## WT-D20260822_006 (FQ-246) P3 — 사전등록 판정 (PREREG.json 봉인 후 실행)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_006"; W004 <- "stage_artifacts/WT-D20260822_004"
W002 <- "stage_artifacts/WT-D20260822_002"; SRC <- "stage_artifacts/fq233_probe0_20260813"
P <- readRDS(file.path(OUT,"p2_arms.rds")); act <- P$act; c0 <- act$C0$act
MATERIAL <- P$MATERIAL; U <- P$U; SC <- P$SC; BT <- P$BT; TOPN <- P$TOPN; GV <- P$GV
A4 <- readRDS(file.path(W004,"p1_arms.rds")); sel_rank <- A4$sel_rank; months <- names(sel_rank)
V4 <- readRDS(file.path(W004,"p4_verdict.rds"))
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet"))); pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]

pairedstat <- function(x, y, lab) { d <- x - y; t <- .nw_t_mean(d, lag=3L)
  se_m <- if (is.finite(t) && t != 0) abs(mean(d)/t) else NA_real_
  ann <- mean(d)*12*100; se_a <- se_m*12*100
  data.table(contrast=lab, n=length(d), ann_pct=ann, t_nw3=t,
             ci95_lo=ann-1.96*se_a, ci95_hi=ann+1.96*se_a) }
lab_of <- function(t, hi) fifelse(t>=2,"EFFECT_POSITIVE", fifelse(t<=-2,"EFFECT_NEGATIVE",
  fifelse(hi<MATERIAL,"POWERED_NULL_NO_MATERIAL_EFFECT","UNDERPOWERED_UNRESOLVED")))
nw_slope_t <- function(y, x) {
  fit <- lm(y ~ x); b <- coef(fit)[2]; e <- residuals(fit); X <- cbind(1, x)
  bread <- solve(crossprod(X)); meat <- crossprod(X * e); n <- length(e)
  for (l in 1:3) { w <- 1 - l/4
    G <- crossprod(X[(l+1):n, , drop=FALSE]*e[(l+1):n], X[1:(n-l), , drop=FALSE]*e[1:(n-l)])
    meat <- meat + w*(G + t(G)) }
  Vc <- bread %*% meat %*% bread; list(slope=unname(b), t=unname(b/sqrt(Vc[2,2]))) }
std <- function(x) (x-mean(x))/sd(x)

cat("=== R1 수송 게이트 (STOP, 성과 판정 전) ===\n")
hz <- V4$act$ORACLE_K$act - c0
s_ag <- nw_slope_t(hz, std(U$AGREE)); s_dp <- nw_slope_t(hz, std(U$DISP)); s_br <- nw_slope_t(hz, std(U$BEAR))
cat(sprintf("  여유폭 평균 = %+.4f %%p/yr (ORACLE_K − C0)\n", mean(hz)*12*100))
cat(sprintf("  축1 disagreement : slope %+.6f/월 (%+.3f %%p/yr per 1sd) · NW3 t %+.4f\n", s_ag$slope, s_ag$slope*12*100, s_ag$t))
cat(sprintf("  축2 dispersion   : slope %+.6f/월 (%+.3f %%p/yr per 1sd) · NW3 t %+.4f\n", s_dp$slope, s_dp$slope*12*100, s_dp$t))
cat(sprintf("  [강등축] bear_prob: slope %+.6f/월 · NW3 t %+.4f\n", s_br$slope, s_br$t))
R1_pass <- max(abs(s_ag$t), abs(s_dp$t)) >= 1.5
R1 <- list(headroom_mean_annual_pct=mean(hz)*12*100,
           axis1=list(slope=s_ag$slope, t=s_ag$t), axis2=list(slope=s_dp$slope, t=s_dp$t),
           bear_axis=list(slope=s_br$slope, t=s_br$t), threshold="|t| >= 1.5 (둘 중 하나)",
           passed=R1_pass,
           verdict=if (R1_pass) "수송 확인 — ORACLE_K 여유폭이 최소 한 상태축에 종속" else
                   "MECHANISM_NOT_TRANSPORTED — 완전예지 여유폭이 두 상태축 어디에도 무관")
cat("  ->", R1$verdict, "\n")

cat("\n=== F1 방향 매개 (군집-내부 대체설계: 월 단위 2군 IC 차) ===\n")
zc <- function(v){ok<-is.finite(v);r<-rep(NA_real_,length(v));if(sum(ok)>=5L&&sd(v[ok])>0)r[ok]<-(v[ok]-mean(v[ok]))/sd(v[ok]);r}
D <- vapply(seq_along(months), function(m){ nm<-months[m]; fs<-sel_rank[[nm]]; d<-panh[anchor==as.Date(nm)]
  f <- d$fwd_ret_1m
  icv <- vapply(fs, function(fk){ v<-d[[fk]]; ok<-is.finite(v)&is.finite(f)
    if (sum(ok)<30L) return(NA_real_); cor(rank(v[ok]), rank(f[ok])) }, 0)
  g <- as.numeric(GV[fs]); g[!is.finite(g)] <- 0
  ip <- mean(icv[g>0], na.rm=TRUE); im <- mean(icv[g<0], na.rm=TRUE)
  if (!is.finite(ip) || !is.finite(im)) NA_real_ else ip - im }, 0)
okD <- is.finite(D)
cat(sprintf("  D_t (IC_pos − IC_neg) 유효 %d/221 · 평균 %+.5f · sd %.5f\n", sum(okD), mean(D[okD]), sd(D[okD])))
f1 <- nw_slope_t(D[okD], std(U$DISP[okD]))
cat(sprintf("  slope(D_t ~ 표준화 u_disp) = %+.6f · NW3 t = %+.4f  [문턱 t >= +1.5]\n", f1$slope, f1$t))
set.seed(20260824L)
perm <- replicate(1000L, { xs <- std(sample(U$DISP[okD])); abs(nw_slope_t(D[okD], xs)$t) })
p_emp <- mean(perm >= abs(f1$t))
cat(sprintf("  순열 통제 1000회: 경험적 p(|t| >= 관측) = %.4f\n", p_emp))
F1 <- list(slope=f1$slope, t_nw3=f1$t, perm_p=p_emp, threshold="t >= +1.5",
           passed=f1$t >= 1.5, n=sum(okD),
           verdict=if (f1$t >= 1.5) "방향 축 성립 — 분산 상태가 계열별 차월 순위정보를 조건화" else
                   "방향 축 기각 — 상태가 '신뢰할 계열' 을 지목하지 못함")
cat("  ->", F1$verdict, "\n")

cat("\n=== 1) primary paired (arm − C0), NW lag-3, n=221 ===\n")
arms_pri <- c("T2_AGREE","T3_DISP","T1_AGREE","T4_BOTH","T3_BEAR","N1_SHUF_A","N2_SHUF_D","T2_LAG1")
roles <- c("co_primary_axis1","co_primary_axis2","secondary_axis1_alt","secondary_two_axis",
           "demoted_contrast_perf_derived","negative_control_shuffle_a","negative_control_shuffle_d","pit_stress_state_lag1")
PRI <- rbindlist(lapply(arms_pri, function(a) pairedstat(act[[a]]$act, c0, a)))
PRI[, role := roles][, label := lab_of(t_nw3, ci95_hi)]
print(PRI[, .(contrast, role, ann_pct=round(ann_pct,4), t_nw3=round(t_nw3,4),
              ci95=paste0("[",round(ci95_lo,2),", ",round(ci95_hi,2),"]"), label)])
cat(sprintf("  MATERIAL = %.4f %%p/yr\n", MATERIAL))

cat("\n=== 2) 양성 대조 ORACLE_STATE (규칙 형태 도달가능성) ===\n")
icdiff <- vapply(seq_along(months), function(m){ nm<-months[m]; fs<-sel_rank[[nm]]; d<-panh[anchor==as.Date(nm)]
  Z<-as.matrix(d[,..fs]); f<-d$fwd_ret_1m
  s0<-rowMeans(Z,na.rm=TRUE); sm<-apply(Z,1L,function(x) if(all(!is.finite(x))) NA_real_ else max(x,na.rm=TRUE))
  okk<-is.finite(s0)&is.finite(sm)&is.finite(f); if(sum(okk)<30) return(0)
  cor(rank(sm[okk]),rank(f[okk])) - cor(rank(s0[okk]),rank(f[okk])) }, 0)
uo <- pmax(-2, pmin(2, std(icdiff)))
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
PC[, passed := t_nw3 >= 2.0]
print(PC[, .(contrast, ann_pct=round(ann_pct,4), t_nw3=round(t_nw3,4), passed, label)])
cat(sprintf("  ORACLE_STATE PORT_t(IKS200) = %.4f\n", BO$portfolio_alpha_t_nw_lag3))

cat("\n=== 3) 창-도달가능성 (FQ-244 기측정 인용) ===\n")
OKp <- pairedstat(V4$act$ORACLE_K$act, c0, "ORACLE_K"); OFp <- pairedstat(V4$act$ORACLE$act, c0, "ORACLE_FWD")
print(rbind(OKp,OFp)[, .(contrast, ann_pct=round(ann_pct,4), t_nw3=round(t_nw3,4))])
cat(sprintf("  ORACLE_K PORT_t(IKS200) = 4.64699909 > 벽 2.95 (FQ-244 실측) — null 을 '창이 좁아서' 로 설명 불가\n"))

cat("\n=== 4) 여유폭 회수율 ===\n")
REC <- PRI[, .(arm=contrast, ann_pct, recovery_share_of_headroom = ann_pct/OKp$ann_pct)]
print(REC[, .(arm, ann_pct=round(ann_pct,4), recovery_pct=round(100*recovery_share_of_headroom,2))])
cat(sprintf("  분모 = ORACLE_K 여유폭 %.4f %%p/yr\n", OKp$ann_pct))

cat("\n=== 5) basis 3종 ===\n")
p0r <- readRDS(file.path(W002,"p0_returns.rds"))
bench_parent <- as.data.table(p0r$bench)[, .(Date, BM_Ret)]; liq_dt <- as.data.table(p0r$liq)
runb <- function(s,b,id,liq=NULL){s<-copy(s);setorder(s,Date,Ticker)
  canonical_screen_bt(s[,.(Date,Ticker,score)],A4$returns_dt,b,top_n=TOPN,cost_bps_oneway=15,
    liq_dt=liq,liq_min=2e8,run_id=id,strategy_id=id,diag_dual_basis=TRUE)}
BASl <- lapply(setNames(names(SC),names(SC)), function(a) runb(SC[[a]], bench_parent, paste0("FQ246par_",a)))
actp <- lapply(BASl, function(b) as.data.table(b$period_returns)[, ret_net-benchmark_ret]); c0p <- actp$C0
BAS <- rbindlist(lapply(names(SC), function(a) data.table(
  arm=a, port_t_IKS200=BT[[a]]$portfolio_alpha_t_nw_lag3, port_t_parent=BASl[[a]]$portfolio_alpha_t_nw_lag3,
  port_t_EW=BT[[a]]$diag_ew_universe$portfolio_alpha_t_nw_lag3,
  ir_IKS200=BT[[a]]$information_ratio, turnover=BT[[a]]$turnover_annual,
  paired_t_parent=if (a=="C0") NA_real_ else pairedstat(actp[[a]], c0p, a)$t_nw3,
  paired_t_iks=if (a=="C0") NA_real_ else PRI[contrast==a, t_nw3])))
BAS[, basis_delta_t := paired_t_parent - paired_t_iks]
print(BAS[, .(arm, port_t_IKS200=round(port_t_IKS200,4), port_t_parent=round(port_t_parent,4),
              port_t_EW=round(port_t_EW,4), ir=round(ir_IKS200,4), turnover=round(turnover,2),
              basis_delta_t=signif(basis_delta_t,3))])

cat("\n=== 6) F2 매개 이동 + 상태-변위 연동 ===\n")
top25 <- function(s){s<-copy(s);setorder(s,Date,-score,Ticker);s[,.(tk=list(head(Ticker,TOPN))),by=Date]}
T0 <- top25(SC$C0)
uof <- list(T2_AGREE=U$AGREE, T3_DISP=U$DISP, T1_AGREE=U$AGREE, T4_BOTH=U$AGREE,
            T3_BEAR=U$BEAR, N1_SHUF_A=U$SHUF_A, N2_SHUF_D=U$SHUF_D, T2_LAG1=U$LAG1)
F2 <- rbindlist(lapply(setdiff(names(SC),"C0"), function(a){
  TA <- top25(SC[[a]]); j <- merge(T0,TA,by="Date")
  jac <- mapply(function(x,y) length(intersect(x,y))/length(union(x,y)), j$tk.x, j$tk.y)
  data.table(arm=a, jaccard_median=round(median(jac),4), moved_median=round(median(TOPN*(1-jac)),2),
             cor_absU_displacement=round(cor(abs(uof[[a]]), 1-jac),4),
             mediator_pass = median(jac) <= 0.90) }))
print(F2)

cat("\n=== 7) F3 agent 실재 (개인 순매수 집중 vs 분산 상태) ===\n")
fp <- ".cache/investor_stock/investor_wide.parquet"
F3 <- list(attempted=TRUE, path=fp, available=file.exists(fp))
if (!file.exists(fp)) { cat("  패널 부재 —", fp, "\n  라벨: 미검(UNMEASURED). 임의 대체 지표 사용 금지.\n")
  F3$verdict <- "UNMEASURED_PANEL_ABSENT"
} else {
  iw <- tryCatch(as.data.table(read_parquet(fp)), error=function(e) NULL)
  if (is.null(iw)) { cat("  패널 읽기 실패 — 미검\n"); F3$verdict <- "UNMEASURED_READ_FAIL"
  } else {
    cat("  컬럼:", paste(head(names(iw),15), collapse=", "), "\n")
    F3$columns <- names(iw); F3$verdict <- "COLUMNS_PROBED_SEE_P4"
  }
}

cat("\n=== 8) 강건성 ===\n")
LIQl <- lapply(setNames(names(SC),names(SC)), function(a) runb(SC[[a]], A4$bench_dt, paste0("FQ246liq_",a), liq_dt))
actl <- lapply(LIQl, function(b) as.data.table(b$period_returns)[, ret_net-benchmark_ret])
LIQ <- rbindlist(lapply(names(SC), function(a) data.table(arm=a,
  port_t_liq=round(LIQl[[a]]$portfolio_alpha_t_nw_lag3,4), n_liq=LIQl[[a]]$n_months,
  paired_t_liq=if (a=="C0") NA_real_ else round(pairedstat(actl[[a]], actl$C0, a)$t_nw3,4))))
print(LIQ)
dts <- act$C0$Date; cutd <- as.Date("2015-07-01")
SUB <- rbindlist(lapply(c("T2_AGREE","T3_DISP","T1_AGREE","T4_BOTH"), function(a){ d <- act[[a]]$act-c0
  data.table(arm=a, pre_t=round(.nw_t_mean(d[dts<cutd],3L),4), post_t=round(.nw_t_mean(d[dts>=cutd],3L),4),
             pre_n=sum(dts<cutd), post_n=sum(dts>=cutd)) }))
print(SUB); cat("  ★진단 병기만 — era 교락 + universe_exit_unrecorded_pre201512(편향 하방/중립). 국면 주장 승격 금지.\n")
TOP5 <- rbindlist(lapply(c("T2_AGREE","T3_DISP","T1_AGREE","T4_BOTH"), function(a){ d <- act[[a]]$act-c0
  o <- order(d, decreasing=TRUE); data.table(arm=a, full_ann=round(mean(d)*12*100,4), ex5_ann=round(mean(d[-o[1:5]])*12*100,4)) }))
print(TOP5)

cat("\n=== 9) advisory 배터리 (게이트 아님) ===\n")
fwd <- panh[, .(Date=anchor, Ticker=as.character(Ticker), fwd=fwd_ret_1m)]
ADV <- rbindlist(lapply(names(SC), function(a){ j <- merge(SC[[a]], fwd, by=c("Date","Ticker"))
  icd <- j[, .(ic=if(.N>=30&&sd(score)>0) cor(rank(score),rank(fwd)) else NA_real_), by=Date]
  ic <- icd$ic; icdt <- icd$Date
  dec <- j[, {q<-cut(frank(score),breaks=quantile(frank(score),0:10/10),include.lowest=TRUE,labels=FALSE)
              .(d=seq_len(10), r=as.numeric(tapply(fwd,q,mean)))}, by=Date][, .(mr=mean(r,na.rm=TRUE)), by=d]
  s1i<-ic[icdt<as.Date("2014-01-01")]; s2i<-ic[icdt>=as.Date("2014-01-01")&icdt<as.Date("2020-01-01")]; s3i<-ic[icdt>=as.Date("2020-01-01")]
  data.table(arm=a, rank_ic=round(mean(ic,na.rm=TRUE),5), icir=round(mean(ic,na.rm=TRUE)/sd(ic,na.rm=TRUE),4),
             ic_t_nw3=round(.nw_t_mean(ic[is.finite(ic)],3L),4),
             monotonicity=round(cor(dec$d, dec$mr, method="spearman"),4),
             subperiod_stability=mean(c(mean(s1i,na.rm=TRUE),mean(s2i,na.rm=TRUE),mean(s3i,na.rm=TRUE))>0),
             turnover=round(BT[[a]]$turnover_annual,2), port_t=round(BT[[a]]$portfolio_alpha_t_nw_lag3,4)) }))
print(ADV)
cat("  ★rank-IC t 와 portfolio-alpha t 는 다른 양이다 (Cycle 2 교훈) — ic_t_nw3 vs port_t 대조.\n")

saveRDS(list(R1=R1, F1=F1, D=D, PRI=PRI, PC=PC, ORACLE=rbind(OKp,OFp), REC=REC, BAS=BAS,
             F2=F2, F3=F3, LIQ=LIQ, SUB=SUB, TOP5=TOP5, ADV=ADV, MATERIAL=MATERIAL,
             oracle_state_port_t=BO$portfolio_alpha_t_nw_lag3, icdiff=icdiff, uo=uo),
        file.path(OUT,"p3_verdict.rds"))
cat("\n[saved] p3_verdict.rds\nOK\n")
