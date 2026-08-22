## probe_a5_lossmap.R — 프로브 4단: 변환 소실 지점 계량 (양성 대조 포함)
##  ①패리티: 내재비중 pi 전량 보유가 지수레벨 A5 를 재현하는가 (변환 기계 검증 — 해석 前 관문)
##  ②breadth 사다리: 전량 -> top-100 -> 50 -> 25 (pi 가중, 15bps) — 절단이 어디서 무는가
##  ③신호 붕괴: pi^A5 vs pi^EW(w_f=1/21) 횡단면 상관 — 배분 정보가 종목 순위에서 상쇄되는가
##  ④가중 소실: 동일 선택 × {EW, pi-cap} 대조 (1·2단 재확인, 창 확장판)
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); setDTthreads(4)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
suppressMessages({library(sandwich); library(lmtest)})
OUT <- file.path(QM,"stage_artifacts/probe_a5_20260822")
nwt <- function(x){x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}
IRf <- function(x){x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12)}
L <- readRDS(file.path(OUT,"probe_a5_longwin.rds")); DEC <- L$DEC
ZP <- readRDS(file.path(OUT,"_zpanel_long.rds"))
FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
         Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
         Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
         Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
         LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
         Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
         Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
         ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
facn <- names(FAC)

## 지수레벨 A5 (위상 상속) — 패리티 기준자
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac <- setdiff(names(R),c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon <- R[, c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),
         by=ym,.SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NAx<-1+length(fac)
S<-matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
for(fi in seq_along(fac)) for(m in 12:NM){ w<-(m-11):m
  S[m,fi]<-prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
Wapp<-matrix(NA_real_,NM,NAx); colnames(Wapp)<-c("Market",fac)
prI<-rep(NA_real_,NM); prG<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
wprev<-rep(1/NAx,NAx); wcur<-NULL
for(m in 13:NM){ d<-m-1
  if(is.null(wcur)||((m-13)%%3==0)){ s<-S[d,];pos<-which(is.finite(s)&s>0);w<-rep(0,NAx)
    if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w }
  Wapp[m,]<-wcur; ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
  dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; prG[m]<-sum(wcur*ri); prI[m]<-prG[m]-0.0015*dlt
  wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }

## 데이터 (long 창)
RAWD <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAWD[,Date:=as.Date(Date)]; RAWD<-RAWD[Date>=as.Date("2011-01-01") & Date<=as.Date("2026-07-31")]
alld<-sort(unique(RAWD$Date)); rym<-format(alld,"%Y-%m"); ME_all<-alld[!duplicated(rym,fromLast=TRUE)]
ME <- ME_all[format(ME_all,"%Y-%m")>="2011-07" & format(ME_all,"%Y-%m")<="2026-07"]
ADV20 <- build_adv20_t1(RAWD[,.(Date,Ticker,Vol,Close)],at_dates=ME)
RAWME <- RAWD[Date %in% ME]; rm(RAWD); invisible(gc())
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily=ADV20)
RET<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]
BEN<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
LIQ<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]

## pi 패널 (A5 비중 / EW 비중)
mkpi <- function(wsrc){ rows<-vector("list",nrow(DEC))
  for(i in seq_len(nrow(DEC))){ d0<-DEC$d0[i]; z<-ZP[[as.character(d0)]]; if(is.null(z)) next
    wv <- if(identical(wsrc,"EW")) setNames(rep(1/length(facn),length(facn)),facn)
          else setNames(Wapp[DEC$mrow[i],-1],facn)
    if(sum(wv)<=1e-12) next
    f<-z$f; tk<-z$uni$Ticker; capv<-setNames(z$uni$cap,z$uni$Ticker)
    pi<-setNames(rep(0,length(tk)),tk)
    for(nm in facn){ wf<-wv[[nm]]; if(!is.finite(wf)||wf<=0) next
      sub<-f[Factor_Name==FAC[[nm]] & is.finite(Z_Score_Aligned)]; if(nrow(sub)<15) next
      thr<-quantile(sub$Z_Score_Aligned,2/3,na.rm=TRUE); H<-sub[Z_Score_Aligned>=thr,Ticker]
      if(!length(H)) next; cw<-capv[H]; pi[H]<-pi[H]+wf*cw/sum(cw) }
    keep<-pi>0; if(!any(keep)) next
    rows[[i]]<-data.table(Date=d0,Ticker=names(pi)[keep],pi=as.numeric(pi[keep]),
                          cap=as.numeric(capv[names(pi)[keep]])) }
  rbindlist(rows) }
PA <- mkpi("A5"); PE <- mkpi("EW")

## ── ① 패리티: pi 전량(무절단·무cap·0bps) vs 지수레벨 A5 gross ────────────────
full <- copy(PA); full[, w := pi/sum(pi), by=Date]
wf0 <- weighted_screen_bt(full[,.(Date,Ticker,w)], RET, BEN, cost_bps_oneway=0,
       run_id="p4_parity", strategy_id="P4_PARITY")
pp <- as.data.table(wf0$period_returns)
## 지수 gross 를 보유월 기준으로 정렬 (d0 -> 다음달 ym)
map <- data.table(d0=ME[-length(ME)], fwd_ym=format(ME[-1],"%Y-%m"))
map[, idx_gross := prG[match(fwd_ym, mon$ym)]]
cmp <- merge(pp[,.(d0=date, stock=ret_net)], map[,.(d0,idx_gross)], by="d0")
cmp <- cmp[is.finite(idx_gross)]
cat(sprintf("\n[① 패리티] pi 전량 보유(0bps) vs 지수레벨 A5 gross: n=%d cor=%.4f | 월평균차 %+.4f%%p | ann차 %+.2f%%p\n",
  nrow(cmp), cor(cmp$stock, cmp$idx_gross), 100*mean(cmp$stock-cmp$idx_gross),
  100*mean(cmp$stock-cmp$idx_gross)*12))
cat("    (완전 일치는 기대하지 않음 — 지수는 일별 VW 드리프트·월중 복리, 종목판은 월말→월말 단일구간)\n")

## ── ② breadth 사다리 (pi 가중, 0.20 cap, 15bps) ──────────────────────────────
capw<-function(v,cap=0.20){w<-v/sum(v); for(k in 1:200){ if(max(w)<=cap+1e-12) break
  ex<-pmax(w-cap,0); w<-pmin(w,cap); w<-w+sum(ex)*w/sum(w)}; w/sum(w)}
lad <- rbindlist(lapply(c(25L,50L,100L,200L,10000L), function(N){
  s <- merge(PA, LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
  setorder(s, Date, -pi); s <- s[, head(.SD, N), by=Date]
  massv <- s[, .(mass=sum(pi)), by=Date]
  s[, w := capw(pi), by=Date]
  ws <- weighted_screen_bt(s[,.(Date,Ticker,w)], RET, BEN, cost_bps_oneway=15,
        run_id=paste0("p4_lad",N), strategy_id=paste0("P4_LAD",N))
  p <- as.data.table(ws$period_returns); act <- p$ret_net-p$benchmark_ret
  conc <- s[, .(effn=1/sum(w^2), top1=max(w), n=.N), by=Date]
  data.table(topN=ifelse(N>1000,NA_integer_,N), n_mo=ws$n_months,
    pi_mass=mean(massv$mass), n_names=mean(conc$n), eff_n=mean(conc$effn), top1_w=mean(conc$top1),
    PORT_t=ws$portfolio_alpha_t_nw_lag3, IR=ws$information_ratio,
    active_ann=100*mean(act)*12, TO=ws$turnover_annual) }))
cat("\n[② breadth 사다리 — pi 가중·0.20 cap·15bps]\n"); print(lad, digits=3)

## ── ③ 신호 붕괴: pi^A5 vs pi^EW 횡단면 상관 + 상위25 집합 Jaccard ─────────────
J <- merge(PA[,.(Date,Ticker,piA=pi)], PE[,.(Date,Ticker,piE=pi)], by=c("Date","Ticker"), all=TRUE)
J[is.na(piA), piA:=0]; J[is.na(piE), piE:=0]
cs <- J[, .(sp=cor(piA,piE,method="spearman"), pe=cor(piA,piE)), by=Date]
top25 <- J[, {a<-Ticker[order(-piA)][1:25]; b<-Ticker[order(-piE)][1:25]
   .(jac=length(intersect(a,b))/length(union(a,b)))}, by=Date]
cat(sprintf("\n[③ 신호 붕괴] pi^A5 vs pi^EW(w_f=1/21): 횡단면 Spearman 중앙 %.3f (평균 %.3f) | Pearson 중앙 %.3f | top-25 Jaccard 중앙 %.3f\n",
  median(cs$sp), mean(cs$sp), median(cs$pe), median(top25$jac)))

## ── ④ 활성수익 상관: 종목판(top-25 pi) vs 지수레벨 A5 ────────────────────────
s25 <- merge(PA, LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
setorder(s25, Date, -pi); s25 <- s25[, head(.SD,25L), by=Date]; s25[, w:=capw(pi), by=Date]
w25 <- weighted_screen_bt(s25[,.(Date,Ticker,w)], RET, BEN, cost_bps_oneway=15,
       run_id="p4_t25", strategy_id="P4_T25")
p25 <- as.data.table(w25$period_returns); a25 <- p25$ret_net-p25$benchmark_ret
map2 <- map[, .(d0, idx_act = prI[match(fwd_ym,mon$ym)] - mon$Market[match(fwd_ym,mon$ym)])]
cm <- merge(data.table(d0=p25$date, a=a25), map2, by="d0")[is.finite(idx_act)]
cat(sprintf("\n[④ 활성 상관] top-25(pi,cap0.20) active vs 지수레벨 A5 active: cor=%.3f | 종목 %+.2f%%p/yr vs 지수 %+.2f%%p/yr | 보존율 %.0f%%\n",
  cor(cm$a, cm$idx_act), 100*mean(cm$a)*12, 100*mean(cm$idx_act)*12,
  100*mean(cm$a)/mean(cm$idx_act)))

## ── ⑤ 형태별 "A5 배분신호가 살아있나" paired 검정 (대조군 = w_f 1/21) ─────────
mkz <- function(wsrc){ rows<-vector("list",nrow(DEC))
  for(i in seq_len(nrow(DEC))){ d0<-DEC$d0[i]; z<-ZP[[as.character(d0)]]; if(is.null(z)) next
    wv <- if(identical(wsrc,"EW")) setNames(rep(1/length(facn),length(facn)),facn)
          else setNames(Wapp[DEC$mrow[i],-1],facn)
    if(sum(wv)<=1e-12) next
    f<-z$f; tk<-z$uni$Ticker; capv<-setNames(z$uni$cap,z$uni$Ticker)
    sc<-setNames(rep(0,length(tk)),tk); hit<-setNames(rep(0,length(tk)),tk)
    for(nm in facn){ wf<-wv[[nm]]; if(!is.finite(wf)||wf<=0) next
      sub<-f[Factor_Name==FAC[[nm]] & is.finite(Z_Score_Aligned)]; if(nrow(sub)<15) next
      v<-setNames(sub$Z_Score_Aligned,sub$Ticker); sc[names(v)]<-sc[names(v)]+wf*v
      hit[names(v)]<-hit[names(v)]+wf }
    keep<-hit>0; if(!any(keep)) next
    rows[[i]]<-data.table(Date=d0,Ticker=names(sc)[keep],score=as.numeric(sc[keep]),
                          cap=as.numeric(capv[names(sc)[keep]])) }
  rbindlist(rows) }
ZA <- mkz("A5"); ZE <- mkz("EW")
runw <- function(S, scorecol, wmode, id){
  s <- merge(S, LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
  setorderv(s, c("Date", scorecol), c(1L, -1L)); s <- s[, head(.SD,25L), by=Date]
  s[, w := if(wmode=="EW") rep(1/.N,.N) else if(wmode=="CAP") capw(cap) else capw(get(scorecol)), by=Date]
  ws <- weighted_screen_bt(s[,.(Date,Ticker,w)], RET, BEN, cost_bps_oneway=15,
        run_id=id, strategy_id=toupper(id))
  as.data.table(ws$period_returns) }
pairs <- list(
  c("Z합성×EW",      "ZA_EW", "ZE_EW"),
  c("Z합성×cap-w",   "ZA_CAP","ZE_CAP"),
  c("내재비중pi",    "PA_PI", "PE_PI"))
PPR <- list(ZA_EW=runw(ZA,"score","EW","p4_zaew"), ZE_EW=runw(ZE,"score","EW","p4_zeew"),
            ZA_CAP=runw(ZA,"score","CAP","p4_zacap"), ZE_CAP=runw(ZE,"score","CAP","p4_zecap"),
            PA_PI=runw(PA,"pi","PI","p4_papi"),      PE_PI=runw(PE,"pi","PI","p4_pepi"))
cat("\n[⑤ A5 배분신호 잔존 검정 — 각 변환 형태에서 (A5 w_f) − (w_f=1/21)]\n")
for(p in pairs){ a<-PPR[[p[2]]]; b<-PPR[[p[3]]]
  m<-merge(a[,.(date,x=ret_net)], b[,.(date,y=ret_net)], by="date")
  aa<-a$ret_net-a$benchmark_ret; bb<-b$ret_net-b$benchmark_ret
  cat(sprintf("  %-12s A5 %+.2f%%p/yr (t %+.2f)  vs  대조 %+.2f%%p/yr (t %+.2f)  |  paired NW-t %+.3f (Δ %+.2f%%p/yr)\n",
    p[1], 100*mean(aa)*12, nwt(aa), 100*mean(bb)*12, nwt(bb), nwt(m$x-m$y), 100*mean(m$x-m$y)*12)) }

fwrite(lad, file.path(OUT,"probe_a5_lossmap_ladder.csv"))
fwrite(cs,  file.path(OUT,"probe_a5_lossmap_signalcorr.csv"))
saveRDS(list(lad=lad,cs=cs,top25=top25,cmp=cmp,cm=cm), file.path(OUT,"probe_a5_lossmap.rds"))
cat("\nPROBE_A5_LOSSMAP_DONE\n")
