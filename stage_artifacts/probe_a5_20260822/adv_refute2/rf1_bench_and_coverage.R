## rf1 — 적대 재검증 1: (a) 벤치마크 불일치 (b) 결측 Z 0-대입 (c) score>0 구속 (d) 헤드라인 재현
## READ-ONLY. 산출물은 adv_refute2/ 에만.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); setDTthreads(4)
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
suppressMessages({library(sandwich); library(lmtest)})
OUT <- file.path(QM,"stage_artifacts/probe_a5_20260822/adv_refute2")
PRB <- file.path(QM,"stage_artifacts/probe_a5_20260822")
nwt <- function(x){x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}
IRf <- function(x){x<-x[is.finite(x)]; mean(x)/sd(x)*sqrt(12)}
FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
         Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
         Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
         Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
         LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
         Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
         Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
         ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
facn <- names(FAC); WIN_F<-"2011-08"; WIN_L<-"2026-07"

## ── A5 지수레벨 (원 스크립트와 동일 코드) ────────────────────────────────────
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
cat(sprintf("[parquet] Date %s ~ %s | cols=%s\n", as.character(min(R$Date)), as.character(max(R$Date)),
    paste(setdiff(names(R),c("Date")), collapse=",")))
if ("as_of_date" %in% names(R)) cat(sprintf("[parquet] as_of_date uniq: %s\n", paste(unique(as.character(R$as_of_date)),collapse=",")))
if ("source_version" %in% names(R)) cat(sprintf("[parquet] source_version uniq: %s\n", paste(unique(as.character(R$source_version)),collapse=",")))
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon <- R[, c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date), nd=.N)),
         by=ym, .SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NAx<-1+length(fac)
S <- matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
for(fi in seq_along(fac)) for(m in 12:NM){ w<-(m-11):m
  S[m,fi] <- prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
Wapp <- matrix(NA_real_,NM,NAx); colnames(Wapp)<-c("Market",fac)
isdec<-rep(FALSE,NM); pr<-rep(NA_real_,NM); prG<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
wprev<-rep(1/NAx,NAx); wcur<-NULL
for(m in 13:NM){ d<-m-1
  if(is.null(wcur) || ((m-13)%%3==0)){ s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
    if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w; isdec[m]<-TRUE }
  Wapp[m,]<-wcur
  ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
  dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; prG[m]<-sum(wcur*ri); pr[m]<-prG[m]-0.0015*dlt
  wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
cat(sprintf("[A5idx] NM=%d | Market-fallback 개월(w_Mkt>0)=%d | 마지막 달 일수=%d (%s)\n",
  NM, sum(is.finite(Wapp[,1]) & Wapp[,1]>1e-8), tail(mon$nd,1), tail(mon$ym,1)))

## ── 데이터 (원 스크립트 동일) ────────────────────────────────────────────────
RAWD <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAWD[,Date:=as.Date(Date)]; RAWD<-RAWD[Date>=as.Date("2011-01-01") & Date<=as.Date("2026-07-31")]
alld<-sort(unique(RAWD$Date)); rym<-format(alld,"%Y-%m"); ME_all<-alld[!duplicated(rym,fromLast=TRUE)]
ME <- ME_all[format(ME_all,"%Y-%m")>="2011-07" & format(ME_all,"%Y-%m")<=WIN_L]
ADV20 <- build_adv20_t1(RAWD[,.(Date,Ticker,Vol,Close)], at_dates=ME)
RAWME <- RAWD[Date %in% ME]; rm(RAWD); invisible(gc())
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily=ADV20)
RET<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]
BEN<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
LIQ<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
DEC <- data.table(d0=ME[-length(ME)]); DEC[,fwd_ym:=format(ME[-1],"%Y-%m")]
DEC <- DEC[fwd_ym>=WIN_F & fwd_ym<=WIN_L]; DEC[,mrow:=match(fwd_ym,mon$ym)]
DEC[,is_dec:=isdec[mrow]]
ZP <- readRDS(file.path(PRB,"_zpanel_long.rds"))
cat(sprintf("[data] DEC=%d | ZP=%d | RET=%d행 | BEN=%d월\n", nrow(DEC), length(ZP), nrow(RET), nrow(BEN)))

## ══ V1. 벤치마크 불일치: 지수 Market vs 계약 BM ═════════════════════════════
kw <- mon$ym>=WIN_F & mon$ym<=WIN_L & is.finite(pr)
mk_idx <- data.table(fwd_ym=mon$ym[kw], mkt=mon$Market[kw], a5=pr[kw], a5g=prG[kw])
mp <- merge(DEC[,.(d0,fwd_ym)], mk_idx, by="fwd_ym")
mp <- merge(mp, BEN, by.x="d0", by.y="Date")
EWuni <- rbindlist(lapply(seq_len(nrow(DEC)),function(i){d0<-DEC$d0[i];z<-ZP[[as.character(d0)]]
  if(is.null(z)) return(NULL); data.table(Date=d0,Ticker=z$uni$Ticker)}))
EWB <- merge(EWuni,RET,by=c("Date","Ticker"))[,.(EW_Ret=mean(Ret_1m)),by=Date]
mp <- merge(mp, EWB, by.x="d0", by.y="Date")
cat("\n===== V1. 벤치마크 불일치 =====\n")
cat(sprintf("n=%d | 지수 Market 연평균 %+.2f%% | 계약 BM(cap-w) 연평균 %+.2f%% | EW-유니버스 %+.2f%%\n",
  nrow(mp), 100*mean(mp$mkt)*12, 100*mean(mp$BM_Ret)*12, 100*mean(mp$EW_Ret)*12))
cat(sprintf("  BM − Market = %+.3f%%p/yr | cor(BM,Market)=%.4f | NW-t(BM−Market)=%+.3f\n",
  100*mean(mp$BM_Ret-mp$mkt)*12, cor(mp$BM_Ret,mp$mkt), nwt(mp$BM_Ret-mp$mkt)))
cat(sprintf("  [원보고] 지수레벨 A5 active(vs Market): PORT_t=%+.3f  active=%+.2f%%p/yr  IR=%+.3f  TO=%.2f\n",
  nwt(mp$a5-mp$mkt), 100*mean(mp$a5-mp$mkt)*12, IRf(mp$a5-mp$mkt), mean(tov[kw],na.rm=TRUE)*12))
cat(sprintf("  [동일벤치] 지수레벨 A5 active(vs 계약 BM): PORT_t=%+.3f  active=%+.2f%%p/yr  IR=%+.3f\n",
  nwt(mp$a5-mp$BM_Ret), 100*mean(mp$a5-mp$BM_Ret)*12, IRf(mp$a5-mp$BM_Ret)))
cat(sprintf("  [동일벤치+실비용] A5 gross − 계약BM − (종목회전 4.45/yr×15bps): active=%+.2f%%p/yr\n",
  100*mean(mp$a5g-mp$BM_Ret)*12 - 4.45*0.15))
fwrite(mp, file.path(OUT,"v1_bench_compare.csv"))

## ══ V2. 결측 Z: 0-대입이 실제로 일어나는가 (hit 질량) ════════════════════════
cov_rows <- vector("list", nrow(DEC))
for(i in seq_len(nrow(DEC))){ d0<-DEC$d0[i]; z<-ZP[[as.character(d0)]]; if(is.null(z)) next
  wv <- setNames(Wapp[DEC$mrow[i],-1], facn); if(sum(wv)<=1e-12) next
  f<-z$f; tk<-z$uni$Ticker
  hit<-setNames(rep(0,length(tk)),tk); nf<-setNames(rep(0L,length(tk)),tk)
  wsum <- 0
  for(nm in facn){ wf<-wv[[nm]]; if(!is.finite(wf)||wf<=0) next
    sub<-f[Factor_Name==FAC[[nm]] & is.finite(Z_Score_Aligned)]; if(nrow(sub)<15) next
    wsum <- wsum + wf
    hit[sub$Ticker]<-hit[sub$Ticker]+wf; nf[sub$Ticker]<-nf[sub$Ticker]+1L }
  cov_rows[[i]] <- data.table(Date=d0, Ticker=tk, hit=as.numeric(hit), nf=as.integer(nf),
                              wsum=wsum, nuni=length(tk)) }
COV <- rbindlist(cov_rows)
COV[, frac := hit/wsum]
cat("\n===== V2. 결측 Z 처리 (선언='팩터 제외' vs 구현) =====\n")
cat(sprintf("유니버스-월 관측 %d | 커버리지 질량 frac 분위: p01=%.3f p05=%.3f p10=%.3f p25=%.3f 중앙=%.3f 평균=%.3f\n",
  nrow(COV), quantile(COV$frac,.01), quantile(COV$frac,.05), quantile(COV$frac,.10),
  quantile(COV$frac,.25), median(COV$frac), mean(COV$frac)))
cat(sprintf("frac<1.0 인 관측 비율 = %.1f%% | frac<0.9 = %.1f%% | frac<0.5 = %.1f%%\n",
  100*mean(COV$frac<0.999), 100*mean(COV$frac<0.9), 100*mean(COV$frac<0.5)))
cat(sprintf("월 평균 유니버스 %.1f | 월 평균 '전 팩터 커버' 종목수 %.1f\n",
  mean(COV[,.(n=.N),by=Date]$n), mean(COV[frac>=0.999,.(n=.N),by=Date]$n)))
fwrite(COV[,.(n=.N, mean_frac=mean(frac), p10=quantile(frac,.1), pct_full=100*mean(frac>=0.999)),by=Date],
       file.path(OUT,"v2_coverage_by_month.csv"))

## ══ V3~V5. 스코어 재구성 (원판 B1 = 0-대입 / B1n = hit-정규화 '진짜 팩터제외') ══
mkz <- function(wsrc, norm=FALSE){ rows<-vector("list",nrow(DEC))
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
    scv <- if(norm) as.numeric(sc[keep]/hit[keep]) else as.numeric(sc[keep])
    rows[[i]]<-data.table(Date=d0,Ticker=names(sc)[keep],score=scv,
                          cap=as.numeric(capv[names(sc)[keep]])) }
  rbindlist(rows) }
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
    rows[[i]]<-data.table(Date=d0,Ticker=names(pi)[keep],score=as.numeric(pi[keep]),
                          cap=as.numeric(capv[names(pi)[keep]])) }
  rbindlist(rows) }
ZA<-mkz("A5"); ZE<-mkz("EW"); ZAn<-mkz("A5",TRUE); ZEn<-mkz("EW",TRUE)
PA<-mkpi("A5"); PE<-mkpi("EW")
CAPALL<-rbindlist(lapply(seq_len(nrow(DEC)),function(i){d0<-DEC$d0[i];z<-ZP[[as.character(d0)]]
  if(is.null(z)) return(NULL); data.table(Date=d0,Ticker=z$uni$Ticker,score=z$uni$cap,cap=z$uni$cap)}))
capw<-function(v,cap=0.20){w<-v/sum(v); for(k in 1:200){ if(max(w)<=cap+1e-12) break
  ex<-pmax(w-cap,0); w<-pmin(w,cap); w<-w+sum(ex)*w/sum(w)}; w/sum(w)}

## V3. score>0 구속 개월수
bind <- ZA[is.finite(score)]; bind <- merge(bind, LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
b1 <- bind[, .(n_pos=sum(score>0), n_all=.N), by=Date]
cat("\n===== V3. score>0 선-필터 구속 =====\n")
cat(sprintf("A5-Z합성: 양수 스코어 <25 인 개월 = %d / %d (중앙 양수개수 %.0f)\n",
  sum(b1$n_pos<25), nrow(b1), median(b1$n_pos)))
bindE <- ZE[is.finite(score)]; bindE <- merge(bindE, LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
b1E <- bindE[, .(n_pos=sum(score>0)), by=Date]
cat(sprintf("EW대조(w=1/21): 양수 <25 인 개월 = %d / %d (중앙 %.0f)\n", sum(b1E$n_pos<25), nrow(b1E), median(b1E$n_pos)))

## V4/V5. 팔 재측정 (filterX = score>0 미적용, filterO = 적용)
runw <- function(S, wmode, id, filt=c("X","O")){ filt<-match.arg(filt)
  s <- merge(if(filt=="O") S[is.finite(score)&score>0] else S[is.finite(score)],
             LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
  setorder(s, Date, -score); s <- s[, head(.SD,25L), by=Date]
  s[, w := if(wmode=="EW") rep(1/.N,.N) else if(wmode=="CAP") capw(cap) else capw(pmax(score,1e-12)), by=Date]
  ws <- weighted_screen_bt(s[,.(Date,Ticker,w)], RET, BEN, cost_bps_oneway=15, run_id=id, strategy_id=toupper(id))
  list(ws=ws, pr=as.data.table(ws$period_returns), nn=s[,.N,by=Date][,mean(N)]) }
ARMS <- list(
  E1_capw_passive=list(CAPALL,"CAP","O"), E2_B1sel_capw=list(ZA,"CAP","O"),
  E3_piEW_ctrl=list(PE,"PI","O"), B3w_A5=list(PA,"PI","O"),
  B3_EW=list(PA,"EW","O"), B1_EW=list(ZA,"EW","O"), C0_EW=list(ZE,"EW","O"),
  ZA_EW_filtX=list(ZA,"EW","X"), ZE_EW_filtX=list(ZE,"EW","X"),
  ZA_CAP_filtX=list(ZA,"CAP","X"), ZE_CAP_filtX=list(ZE,"CAP","X"),
  ZAn_EW_filtX=list(ZAn,"EW","X"), ZEn_EW_filtX=list(ZEn,"EW","X"),
  ZAn_CAP_filtX=list(ZAn,"CAP","X"), ZEn_CAP_filtX=list(ZEn,"CAP","X"))
PRL<-list()
tab <- rbindlist(lapply(names(ARMS), function(nm){ a<-ARMS[[nm]]
  r <- runw(a[[1]], a[[2]], paste0("rf1_",tolower(nm)), a[[3]]); PRL[[nm]]<<-r$pr
  act <- r$pr$ret_net - r$pr$benchmark_ret; yy<-format(r$pr$date,"%Y")
  data.table(arm=nm, n=r$ws$n_months, PORT_t=r$ws$portfolio_alpha_t_nw_lag3, IR=r$ws$information_ratio,
    active_ann=100*mean(act)*12, netSR=IRf(r$pr$ret_net), TO=r$ws$turnover_annual,
    n_names=r$nn, t_pre17=nwt(act[yy<"2017"]), t_post17=nwt(act[yy>="2017"])) }))
cat("\n===== V4. 팔 재측정 (독립 재계산) =====\n"); print(tab, digits=4)
fwrite(tab, file.path(OUT,"v4_arms.csv"))

## V5. paired 검정 (원보고 ⑤ 재현 + hit-정규화판)
pairs <- list(c("Z합성×EW(0대입)","ZA_EW_filtX","ZE_EW_filtX"),
              c("Z합성×cap(0대입)","ZA_CAP_filtX","ZE_CAP_filtX"),
              c("Z합성×EW(팩터제외)","ZAn_EW_filtX","ZEn_EW_filtX"),
              c("Z합성×cap(팩터제외)","ZAn_CAP_filtX","ZEn_CAP_filtX"),
              c("내재비중pi","B3w_A5","E3_piEW_ctrl"))
cat("\n===== V5. paired NW-t (A5 w_f − 1/21) =====\n")
pp <- rbindlist(lapply(pairs, function(p){ a<-PRL[[p[2]]]; b<-PRL[[p[3]]]
  m<-merge(a[,.(date,x=ret_net)],b[,.(date,y=ret_net)],by="date")
  data.table(form=p[1], A5_act=100*mean(a$ret_net-a$benchmark_ret)*12,
             ctrl_act=100*mean(b$ret_net-b$benchmark_ret)*12,
             paired_t=nwt(m$x-m$y), delta_ann=100*mean(m$x-m$y)*12) }))
print(pp, digits=4); fwrite(pp, file.path(OUT,"v5_paired.csv"))

## V6. breadth 사다리 재현 + 전량판 대 지수 패리티
lad <- rbindlist(lapply(c(25L,50L,100L,200L,10000L), function(N){
  s <- merge(PA, LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
  setorder(s, Date, -score); s<-s[, head(.SD,N), by=Date]
  mass <- s[,.(mass=sum(score)),by=Date]; s[, w:=capw(score), by=Date]
  ws <- weighted_screen_bt(s[,.(Date,Ticker,w)],RET,BEN,cost_bps_oneway=15,
        run_id=paste0("rf1_lad",N), strategy_id=paste0("RF1_LAD",N))
  p<-as.data.table(ws$period_returns); act<-p$ret_net-p$benchmark_ret
  data.table(topN=ifelse(N>1000,NA_integer_,N), pi_mass=mean(mass$mass), n_names=s[,.N,by=Date][,mean(N)],
    PORT_t=ws$portfolio_alpha_t_nw_lag3, IR=ws$information_ratio,
    active_ann=100*mean(act)*12, TO=ws$turnover_annual) }))
cat("\n===== V6. breadth 사다리 재현 =====\n"); print(lad, digits=4)
fwrite(lad, file.path(OUT,"v6_ladder.csv"))
full<-copy(PA); full[,w:=score/sum(score),by=Date]
wf0<-weighted_screen_bt(full[,.(Date,Ticker,w)],RET,BEN,cost_bps_oneway=0,run_id="rf1_parity",strategy_id="RF1_PARITY")
p0<-as.data.table(wf0$period_returns)
mm<-merge(p0[,.(d0=date,stock=ret_net)], DEC[,.(d0,fwd_ym)], by="d0")
mm[, idxg := prG[match(fwd_ym, mon$ym)]]
mm<-mm[is.finite(idxg)]
cat(sprintf("\n[패리티 재현] n=%d cor=%.4f | ann차 %+.3f%%p | 종목 gross %+.2f%%/yr vs 지수 gross %+.2f%%/yr\n",
  nrow(mm), cor(mm$stock,mm$idxg), 100*mean(mm$stock-mm$idxg)*12,
  100*mean(mm$stock)*12, 100*mean(mm$idxg)*12))
saveRDS(list(tab=tab,pp=pp,lad=lad,mp=mp,COVsum=COV[,.(mf=mean(frac)),by=Date]), file.path(OUT,"rf1.rds"))
cat("\nRF1_DONE\n")
