## run_fof_stageA_hrp.R — Stage A: C 포트폴리오-블렌딩 vs 신호-블렌딩 (cheap-kill 결정 게이트)
## 가설: 벽=롱온리 25종 *번역*. integrated(Σz→top25 select once, ~0.73)을 mixed(팩터-sleeve별 top-N → 25종)이 초과하나?
## 공정성: 양 arm 전부 canonical_screen_bt(동일 EW·15bps·liq 2e8)로 측정. mixed는 sleeve-count 선택을 synthetic score로 인코딩(비용/측정 동일, *선택*만 차이).
## arms: integrated(flat 11군 합성) / mixed_EW(K=5 sleeve 5종씩, 무-hindsight) / mixed_HRP(N_s ∝ HRP λ_s, full-sample λ=hindsight-light 라벨).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/portfolio/hrp_core.R")
OUT <- "04_Research/factor_rotation/fof_first_slice"
con <- file(file.path(OUT,"_fof_stageA.txt"),"w",encoding="UTF-8"); w <- function(...) writeLines(paste0(...),con)
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality" else if(p1=="D") "LowRisk"
  else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity" else if(p1=="R") "Reversal"
  else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals" else if(p1=="C"&&p!="CR") "Consensus"
  else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit" else if(p=="XF") "Composite"
  else if(p=="MA") "Macro" else if(p=="TR") "Size_Liquidity" else "Composite" }
w("================ Stage A — C 포트폴리오블렌딩 vs 신호블렌딩 ================")
w(sprintf("실행: %s", as.character(Sys.time())))

## ── 1) 11군 group_z (neutralized) ──
sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","neutralized_z")))
sc[, signal_date := as.Date(signal_date)]; sc[, family := sapply(factor_id, fam_of)]; sc <- sc[family!="Macro"]
grp <- sc[, .(zz=mean(neutralized_z,na.rm=TRUE)), by=.(signal_date, security_id, family)]
grp[, gz := zc(zz), by=.(signal_date, family)]; grp <- grp[, .(signal_date, security_id, family, gz)]
GRP <- sort(unique(grp$family)); nG <- length(GRP)

## ── 2) forward + 군별 return 시계열 (canonical_screen_bt per group) ──
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
run_sc <- function(sdt,id) canonical_screen_bt(scores_dt=sdt[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
  returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id=id,strategy_id=id)
greturns <- list()
for(g in GRP){ sg <- grp[family==g, .(signal_date, security_id, score=gz)]
  cs <- run_sc(sg, paste0("g_",g)); pr<-as.data.table(cs$period_returns)
  greturns[[g]] <- pr[,.(date=as.Date(date), r=ret_net-benchmark_ret)] }
gret <- Reduce(function(a,b) merge(a,b,by="date"), lapply(names(greturns), function(g){ x<-copy(greturns[[g]]); setnames(x,"r",g); x }))
setorder(gret, date)
GR_MAT <- as.matrix(gret[, ..GRP]); rownames(GR_MAT)<-as.character(gret$date)
w(sprintf("\n군별 return 시계열: %d군 × %d월", ncol(GR_MAT), nrow(GR_MAT)))

## ── 3) 클러스터 K=5 sleeve (group-return corr → ward.D2) ──
K <- 5L
cm <- cor(GR_MAT, use="pairwise.complete.obs"); d <- as.dist(sqrt(pmax(0.5*(1-cm),0)))
hc <- hclust(d, method="ward.D2"); cl <- cutree(hc, k=K)
sleeve_of <- setNames(paste0("S",cl), names(cl))
w("\n=== sleeve 클러스터 (K=5) ===")
for(s in sort(unique(sleeve_of))) w(sprintf("  %s <= %s", s, paste(names(sleeve_of)[sleeve_of==s], collapse=", ")))

## sleeve return (멤버 군 평균) → HRP λ_s (full-sample, hindsight-light 라벨)
SL <- sort(unique(sleeve_of))
sret <- sapply(SL, function(s){ mem<-names(sleeve_of)[sleeve_of==s]; rowMeans(GR_MAT[,mem,drop=FALSE],na.rm=TRUE) })
sret_dt <- data.table(Date=as.Date(rownames(GR_MAT)))
for(s in SL) sret_dt[[s]] <- sret[,s]
sret_long <- melt(sret_dt, id.vars="Date", variable.name="Ticker", value.name="Ret")[, .(Date, Ticker=as.character(Ticker), Ret)]
lam <- calc_hrp_weights(SL, sret_long, n_days=nrow(GR_MAT), max_w=0.50, cov_method="sample")
lam <- lam[SL]; lam <- lam/sum(lam)
w(sprintf("  HRP λ_s: %s", paste(sprintf("%s=%.3f",SL,lam), collapse=" / ")))

## ── 4) sleeve_score per (date, stock) = 멤버 군 gz 평균 ──
grp[, sleeve := sleeve_of[family]]
sl_sc <- grp[, .(ssc = mean(gz,na.rm=TRUE)), by=.(signal_date, security_id, sleeve)]
comp  <- grp[, .(csc = mean(gz,na.rm=TRUE)), by=.(signal_date, security_id)]   # flat 합성(integrated 신호)
## 유동성: liq at Date=signal_date
liq_ok <- liq_dt[adv>=2e8, .(signal_date=Date, security_id=Ticker, liq=1L)]

## ── 5) mixed 선택 (count-allocation) → synthetic score ──
## N_s: EW = 25를 K sleeve에 균등(5,5,5,5,5). HRP = round(25*λ_s), 합25 보정.
alloc_counts <- function(weights){ n<-round(weights*25); d<-25-sum(n)
  while(d!=0){ if(d>0){ i<-which.max(weights - n/25); n[i]<-n[i]+1; d<-d-1 } else { i<-which.max(n/25 - weights); n[i]<-n[i]-1; d<-d+1 } }
  pmax(n,0) }
N_EW  <- setNames(rep(25%/%K, K) + c(rep(1,25%%K),rep(0,K-25%%K)), SL)   # 5,5,5,5,5
N_HRP <- setNames(alloc_counts(lam), SL)
w(sprintf("  N_s (EW): %s", paste(sprintf("%s=%d",SL,N_EW),collapse=" ")))
w(sprintf("  N_s (HRP): %s", paste(sprintf("%s=%d",SL,N_HRP),collapse=" ")))

build_mixed_score <- function(Ns){
  x <- merge(sl_sc, liq_ok, by=c("signal_date","security_id"))   # 유동 종목만 sleeve 선택
  x[, rk := frank(-ssc, ties.method="first"), by=.(signal_date, sleeve)]
  x[, keep := rk <= Ns[sleeve]]
  sel <- unique(x[keep==TRUE, .(signal_date, security_id)])      # union(dedupe)
  ## topup: 월별 25 미만이면 flat 합성 상위(유동·미선택)로 채움
  cnt <- sel[, .(n_have=.N), by=signal_date]
  short <- cnt[n_have < 25L, .(signal_date, n_need = 25L - n_have)]
  if(nrow(short)>0){
    cand <- merge(comp, liq_ok, by=c("signal_date","security_id"))     # 유동 + flat score
    cand <- cand[signal_date %in% short$signal_date]
    cand <- cand[!sel, on=c("signal_date","security_id")]              # 미선택만
    cand[, rk := frank(-csc, ties.method="first"), by=signal_date]
    cand <- merge(cand, short, by="signal_date")
    add  <- cand[rk <= n_need, .(signal_date, security_id)]
    sel  <- rbind(sel, add)
  }
  sel[, selected := 1L]
  out <- merge(comp, sel, by=c("signal_date","security_id"), all.x=TRUE)
  out[is.na(selected), selected := 0L]
  out[, score := ifelse(selected==1L, 1e6 + csc, csc)]          # 선택분 top-25 강제(EW는 canonical이 처리)
  out[, .(signal_date, security_id, score)]
}
scInt <- comp[, .(signal_date, security_id, score=csc)]          # integrated = flat 합성
scMixEW  <- build_mixed_score(N_EW)
scMixHRP <- build_mixed_score(N_HRP)
common <- Reduce(intersect, list(unique(scInt$signal_date),unique(scMixEW$signal_date),unique(scMixHRP$signal_date)))
common <- sort(as.Date(common,origin="1970-01-01"))
cl2<-function(x) x[signal_date%in%common]; scInt<-cl2(scInt); scMixEW<-cl2(scMixEW); scMixHRP<-cl2(scMixHRP)

## ── 6) canonical_screen_bt 측정 ──
csI<-run_sc(scInt,"integrated"); csME<-run_sc(scMixEW,"mixed_EW"); csMH<-run_sc(scMixHRP,"mixed_HRP")
w(sprintf("\n공통 %d개월 (%s~%s)", length(common), as.character(min(common)), as.character(max(common))))
w("\n=== arm 실측 (canonical_screen_bt, advisory) ===")
ff<-function(cs,nm) w(sprintf("  [%-16s] port_t=%+.2f (p=%.3f) | net_SR=%+.3f | IR=%+.3f | TO=%.0f%%",
  nm, cs$portfolio_alpha_t_nw_lag3, cs$portfolio_alpha_t_pvalue, cs$net_sr, cs$information_ratio, 100*cs$turnover_annual))
ff(csI,"integrated"); ff(csME,"mixed_EW"); ff(csMH,"mixed_HRP")

## ── 7) paired NW-t: mixed − integrated ──
ptest<-function(csX,csA){ A<-as.data.table(csA$period_returns)[,.(date=as.Date(date),a=ret_net-benchmark_ret)]
  B<-as.data.table(csX$period_returns)[,.(date=as.Date(date),b=ret_net-benchmark_ret)]
  D<-merge(A,B,by="date"); D[,d:=b-a]; f<-lm(d~1,data=D)
  nw<-coeftest(f,vcov=sandwich::NeweyWest(f,lag=3,prewhite=FALSE)); c(t=nw[1,3],p=nw[1,4],sr_lift=csX$net_sr-csA$net_sr,n=nrow(D)) }
tME<-ptest(csME,csI); tMH<-ptest(csMH,csI)
w("\n=== 핵심 검정 (paired-NW-t lag3, mixed − integrated) ===")
w(sprintf("  mixed_EW  − integrated: t=%+.2f (p=%.3f) SR_lift=%+.3f", tME["t"],tME["p"],tME["sr_lift"]))
w(sprintf("  mixed_HRP − integrated: t=%+.2f (p=%.3f) SR_lift=%+.3f", tMH["t"],tMH["p"],tMH["sr_lift"]))
best_t<-max(tME["t"],tMH["t"]); best_lift<-max(tME["sr_lift"],tMH["sr_lift"])
verdict <- if(best_lift>0 && best_t>2) "EXPAND" else if(best_lift<=0 || best_t<1) "CHEAP-KILL" else "BORDERLINE"
w(sprintf("  → Stage A 판정: %s (best mixed t=%+.2f, SR_lift=%+.3f)", verdict, best_t, best_lift))

saveRDS(list(csI=csI,csME=csME,csMH=csMH,tME=tME,tMH=tMH,sleeve_of=sleeve_of,lam=lam,verdict=verdict), file.path(OUT,"_fof_stageA.rds"))
cat(sprintf("STAGEA|int=%.3f mixEW=%.3f mixHRP=%.3f|t_EW=%.2f t_HRP=%.2f|lift_EW=%.4f lift_HRP=%.4f|%s\n",
  csI$portfolio_alpha_t_nw_lag3,csME$portfolio_alpha_t_nw_lag3,csMH$portfolio_alpha_t_nw_lag3,
  tME["t"],tMH["t"],tME["sr_lift"],tMH["sr_lift"],verdict))
close(con); cat("FOF_STAGEA_DONE\n")
