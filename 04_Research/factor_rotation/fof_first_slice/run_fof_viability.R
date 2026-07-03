## run_fof_viability.R — 개별 팩터 시그널 viability map + causal viability-가중 배분 (도훈 reframe 2026-06-30)
## 도훈: 최종목표=팩터의팩터 시그널 기반 팩터배분 포트. ★중요 함의=개별 팩터 시그널이 *살아있는지(viability)*.
##   factor-RETURN-momentum(앞 B0/B1)은 null이었으나, factor-VIABILITY(IC로 본 *작동여부*)는 별개 신호·미시험.
## 산출: (1) 11군 viability map(full/recent60/recent36 rank-IC + NW-t) (2) causal rolling-IC 가중 배분 arm
##        vs flat(A0)·mom-centric(A0m). PIT: 가중은 trailing IC만(t-36..t-1), 미래 IC 미사용.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "04_Research/factor_rotation/fof_first_slice"
con <- file(file.path(OUT,"_fof_viability.txt"),"w",encoding="UTF-8")
w <- function(...) writeLines(paste0(...), con)
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
nwt1 <- function(x){ x<-x[is.finite(x)]; if(length(x)<5) return(NA_real_); f<-lm(x~1)
  as.numeric(coeftest(f, sandwich::NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p=="TR") "Size_Liquidity" else "Composite" }

w("================ FoF viability map + causal viability 배분 ================")
w(sprintf("실행: %s", as.character(Sys.time())))

## ── 1) neutralized group_z (부호정렬 안전 신호) ──
sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","neutralized_z")))
sc[, signal_date := as.Date(signal_date)]; sc[, family := sapply(factor_id, fam_of)]
sc <- sc[family != "Macro"]
grp <- sc[, .(zz=mean(neutralized_z,na.rm=TRUE)), by=.(signal_date, security_id, family)]
grp[, gz := zc(zz), by=.(signal_date, family)]
grp <- grp[, .(signal_date, security_id, family, gz)]
GRP <- sort(unique(grp$family)); nG <- length(GRP)
w(sprintf("경제군 %d: %s", nG, paste(GRP, collapse=", ")))

## ── 2) forward returns + 월별 group rank-IC (gz vs forward Ret_1m, Date+Ticker 매칭) ──
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
m <- merge(grp[, .(Date=signal_date, Ticker=security_id, family, gz)], ret_dt, by=c("Date","Ticker"))
ic <- m[, .(ic = if(.N>=10 && sd(gz,na.rm=T)>0 && sd(Ret_1m,na.rm=T)>0)
              cor(gz, Ret_1m, method="spearman", use="complete.obs") else NA_real_), by=.(Date, family)]
icw <- dcast(ic, Date ~ family, value.var="ic"); setorder(icw, Date)
ICG <- intersect(GRP, names(icw))
w(sprintf("월별 group IC 산출: %d개월 (%s ~ %s)", nrow(icw), as.character(min(icw$Date)), as.character(max(icw$Date))))

## ── 3) viability map (full / recent60 / recent36 rank-IC + NW-t) ──
w("\n=== 11군 viability map (rank-IC, metric_type=proxy/advisory) ===")
via_tab <- data.table()
for(g in ICG){ s<-icw[[g]]; sv<-s[is.finite(s)]; nn<-length(sv)
  full<-mean(sv); r60<-mean(tail(sv,60)); r36<-mean(tail(sv,36)); tt<-nwt1(s)
  via_tab <- rbind(via_tab, data.table(group=g, full_ic=full, nw_t=tt, recent60=r60, recent36=r36, n=nn))
  w(sprintf("  %-16s full=%+.4f (NW-t %+.2f) | rec60=%+.4f | rec36=%+.4f | n=%d", g, full, tt, r60, r36, nn)) }
setorder(via_tab, -recent36)
w(sprintf("  → 최근36m 살아있는 순: %s", paste(via_tab$group, collapse=" > ")))

## ── 4) causal rolling-IC viability 가중 (V_{g,t}=mean IC[t-36..t-1], W ∝ max(V,0)) ──
N_TRAIL <- 36L
icm <- as.matrix(icw[, ..ICG]); rownames(icm) <- as.character(icw$Date)
Wvia <- list()
for(t in seq_len(nrow(icm))){ lo<-t-N_TRAIL; if(lo<1) next
  V <- colMeans(icm[lo:(t-1), , drop=FALSE], na.rm=TRUE); V[!is.finite(V)] <- 0
  raw <- pmax(V, 0); if(sum(raw)<1e-9) raw[] <- 1
  full <- setNames(rep(0,length(GRP)), GRP); full[names(raw)] <- raw; full<-full/sum(full)
  Wvia[[rownames(icm)[t]]] <- full }
w(sprintf("\ncausal viability 가중: trailing %dm IC, max(V,0) 정규화. 유효월=%d (PIT trailing-only)", N_TRAIL, length(Wvia)))

## ── 5) 군가중 스킴 + 종목 score ──
W_flat <- setNames(rep(1/nG,nG), GRP)
W_momc <- setNames(rep(0,nG), GRP); if("Momentum"%in%GRP) W_momc["Momentum"]<-0.7; if("Consensus"%in%GRP) W_momc["Consensus"]<-0.3; W_momc<-W_momc/sum(W_momc)
build_scores <- function(wscheme=NULL, Wlist=NULL){
  out <- copy(grp); out[, ymk := as.character(signal_date)]
  if(is.null(Wlist)){ out[, wg := wscheme[family]] }
  else { wdt<-rbindlist(lapply(names(Wlist), function(k) data.table(ymk=k, family=names(Wlist[[k]]), wg=as.numeric(Wlist[[k]]))))
    out<-merge(out, wdt, by=c("ymk","family"), all.x=TRUE); out<-out[!is.na(wg)] }
  s <- out[, .(score=sum(wg*gz,na.rm=TRUE)), by=.(signal_date, security_id)]
  s[, score := zc(score), by=signal_date]; s }
scA0  <- build_scores(W_flat)
scA0m <- build_scores(W_momc)
scV   <- build_scores(Wlist=Wvia)
common <- Reduce(intersect, list(unique(scA0$signal_date),unique(scA0m$signal_date),unique(scV$signal_date)))
common <- sort(as.Date(common, origin="1970-01-01"))
cl<-function(x) x[signal_date%in%common]; scA0<-cl(scA0); scA0m<-cl(scA0m); scV<-cl(scV)
w(sprintf("공통 signal_date %d개월 (%s ~ %s, viability 36m 워밍업 후)", length(common), as.character(min(common)), as.character(max(common))))

## ── 6) canonical_screen_bt ──
run_arm <- function(sdt,id) canonical_screen_bt(scores_dt=sdt[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
  returns_dt=ret_dt, bench_dt=bench_dt, top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8, run_id=id, strategy_id=id)
csA0<-run_arm(scA0,"A0_flat"); csA0m<-run_arm(scA0m,"A0m_momc"); csV<-run_arm(scV,"V_viability")
w("\n=== arm 실측 (metric_type=canonical_screen advisory) ===")
ff<-function(cs,nm) w(sprintf("  [%-22s] port_t=%+.2f (p=%.3f) | net_SR=%+.3f | IR=%+.3f | TO=%.0f%%",
  nm, cs$portfolio_alpha_t_nw_lag3, cs$portfolio_alpha_t_pvalue, cs$net_sr, cs$information_ratio, 100*cs$turnover_annual))
ff(csA0,"A0 flat(baseline)"); ff(csA0m,"A0m mom-centric(static)"); ff(csV,"V viability(causal IC)")

## ── 7) paired NW-t: V vs A0(flat), V vs A0m(static mom-centric) ──
ptest <- function(csX, csA){
  prA<-as.data.table(csA$period_returns)[,.(date=as.Date(date),a=ret_net-benchmark_ret)]
  prB<-as.data.table(csX$period_returns)[,.(date=as.Date(date),b=ret_net-benchmark_ret)]
  D<-merge(prA,prB,by="date"); D[,d:=b-a]; fit<-lm(d~1,data=D)
  nw<-coeftest(fit,vcov=sandwich::NeweyWest(fit,lag=3,prewhite=FALSE)); c(t=as.numeric(nw[1,3]),p=as.numeric(nw[1,4]),n=nrow(D)) }
tV_A0  <- ptest(csV,csA0); tV_A0m <- ptest(csV,csA0m)
w("\n=== 핵심 검정 (paired-NW-t lag3) ===")
w(sprintf("  viability(V) − flat(A0):           t=%+.2f (p=%.3f) → 살아있는 팩터 배분이 flat 초과? %s", tV_A0["t"], tV_A0["p"], ifelse(tV_A0["t"]>2,"YES","NO/약")))
w(sprintf("  viability(V) − 정적mom-centric(A0m): t=%+.2f (p=%.3f) → 데이터구동이 hand-pick 초과? %s", tV_A0m["t"], tV_A0m["p"], ifelse(tV_A0m["t"]>2,"YES","NO/약")))

saveRDS(list(via_tab=via_tab, csA0=csA0, csA0m=csA0m, csV=csV, tV_A0=tV_A0, tV_A0m=tV_A0m, Wvia=Wvia),
        file.path(OUT,"_fof_viability.rds"))
fwrite(via_tab, file.path(OUT,"viability_map.csv"))
pt<-function(cs) cs$portfolio_alpha_t_nw_lag3
cat(sprintf("VIAB|A0=%.3f A0m=%.3f V=%.3f | V-flat_t=%.2f | V-momc_t=%.2f | top_alive=%s\n",
  pt(csA0),pt(csA0m),pt(csV), tV_A0["t"], tV_A0m["t"], paste(head(via_tab$group,3),collapse=">")))
close(con); cat("FOF_VIABILITY_DONE\n")
