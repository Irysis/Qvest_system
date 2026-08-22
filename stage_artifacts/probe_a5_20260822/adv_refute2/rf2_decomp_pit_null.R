## rf2 — 적대 재검증 2: (a) 손실 분해 (b) 미계상비용 (c) 종목층 PIT 스트레스 (d) w_f 셔플 널
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
FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
         Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
         Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
         Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
         LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
         Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
         Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
         ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
facn <- names(FAC); WIN_F<-"2011-08"; WIN_L<-"2026-07"

R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon <- R[, c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date))),
         by=ym, .SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NAx<-1+length(fac)
S <- matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
for(fi in seq_along(fac)) for(m in 12:NM){ w<-(m-11):m
  S[m,fi] <- prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
Wapp <- matrix(NA_real_,NM,NAx); colnames(Wapp)<-c("Market",fac)
pr<-rep(NA_real_,NM); prG<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
wprev<-rep(1/NAx,NAx); wcur<-NULL
for(m in 13:NM){ d<-m-1
  if(is.null(wcur) || ((m-13)%%3==0)){ s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
    if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w }
  Wapp[m,]<-wcur
  ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
  dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; prG[m]<-sum(wcur*ri); pr[m]<-prG[m]-0.0015*dlt
  wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }

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
ZP <- readRDS(file.path(PRB,"_zpanel_long.rds"))
capw<-function(v,cap=0.20){w<-v/sum(v); for(k in 1:200){ if(max(w)<=cap+1e-12) break
  ex<-pmax(w-cap,0); w<-pmin(w,cap); w<-w+sum(ex)*w/sum(w)}; w/sum(w)}

## ── 월별 Z 행렬 사전계산 (셔플 널 고속화) ────────────────────────────────────
MZ <- vector("list", nrow(DEC))
for(i in seq_len(nrow(DEC))){ d0<-DEC$d0[i]; z<-ZP[[as.character(d0)]]; if(is.null(z)) next
  tk<-z$uni$Ticker; capv<-setNames(z$uni$cap,z$uni$Ticker)
  Zm <- matrix(NA_real_, length(tk), length(facn), dimnames=list(tk,facn))
  Hm <- matrix(FALSE, length(tk), length(facn), dimnames=list(tk,facn))
  ok <- rep(FALSE, length(facn)); names(ok)<-facn
  for(nm in facn){ sub<-z$f[Factor_Name==FAC[[nm]] & is.finite(Z_Score_Aligned)]
    if(nrow(sub)<15) next
    ok[nm]<-TRUE; Zm[sub$Ticker,nm]<-sub$Z_Score_Aligned
    thr<-quantile(sub$Z_Score_Aligned,2/3,na.rm=TRUE); Hm[sub[Z_Score_Aligned>=thr,Ticker],nm]<-TRUE }
  MZ[[i]] <- list(d0=d0, tk=tk, cap=capv[tk], Z=Zm, H=Hm, ok=ok, mrow=DEC$mrow[i]) }
cat(sprintf("[MZ] %d개월 사전계산\n", sum(!vapply(MZ,is.null,TRUE))))

## 스코어 생성기 (wsrc: 'A5' | 'EW' | 명시 w벡터 / lag: Wapp 행 오프셋)
scoreZ <- function(wsrc, lag=0L){
  rbindlist(lapply(MZ, function(M){ if(is.null(M)) return(NULL)
    r <- M$mrow + lag; if(r<1 || r>NM) return(NULL)
    wv <- if(identical(wsrc,"EW")) setNames(rep(1/length(facn),length(facn)),facn)
          else if(is.numeric(wsrc)) wsrc else setNames(Wapp[r,-1],facn)
    wv[!M$ok] <- 0; if(sum(wv)<=1e-12) return(NULL)
    Zf <- M$Z; Zf[is.na(Zf)] <- 0
    sc <- as.numeric(Zf %*% wv)
    hit <- as.numeric((!is.na(M$Z)) %*% wv)
    keep <- hit>0
    data.table(Date=M$d0, Ticker=M$tk[keep], score=sc[keep], cap=as.numeric(M$cap[keep])) })) }
scorePI <- function(wsrc, lag=0L){
  rbindlist(lapply(MZ, function(M){ if(is.null(M)) return(NULL)
    r <- M$mrow + lag; if(r<1 || r>NM) return(NULL)
    wv <- if(identical(wsrc,"EW")) setNames(rep(1/length(facn),length(facn)),facn) else setNames(Wapp[r,-1],facn)
    wv[!M$ok] <- 0; if(sum(wv)<=1e-12) return(NULL)
    capm <- M$cap * M$H                       # ticker x factor
    colsum <- colSums(capm); colsum[colsum<=0] <- NA
    piM <- sweep(capm, 2, colsum, "/"); piM[is.na(piM)] <- 0
    pv <- as.numeric(piM %*% wv); keep <- pv>0
    data.table(Date=M$d0, Ticker=M$tk[keep], score=pv[keep], cap=as.numeric(M$cap[keep])) })) }

runw <- function(S, wmode, id, topN=25L, cap=0.20, bps=15, applyliq=TRUE, pos_only=FALSE){
  s <- copy(S)[is.finite(score)]
  if(pos_only) s <- s[score>0]
  if(applyliq) s <- merge(s, LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
  setorder(s, Date, -score); if(!is.na(topN)) s <- s[, head(.SD,topN), by=Date]
  s[, w := if(wmode=="EW") rep(1/.N,.N) else if(wmode=="CAP") capw(cap_(cap),cap) else
            if(is.na(cap)) score/sum(score) else capw(pmax(score,1e-12),cap), by=Date]
  ws <- weighted_screen_bt(s[,.(Date,Ticker,w)], RET, BEN, cost_bps_oneway=bps, run_id=id, strategy_id=toupper(id))
  ws }
## helper (cap_ 은 CAP 모드에서 cap 컬럼 사용)
cap_ <- function(...) get("cap", envir=parent.frame(2))

## ══ (a) 손실 분해: 지수 → pi 전량 → 제약 하나씩 ═════════════════════════════
PA <- scorePI("A5"); PE <- scorePI("EW"); ZA <- scoreZ("A5"); ZE <- scoreZ("EW")
kw <- mon$ym>=WIN_F & mon$ym<=WIN_L & is.finite(pr)
mp <- merge(DEC[,.(d0,fwd_ym)], data.table(fwd_ym=mon$ym[kw], mkt=mon$Market[kw], a5=pr[kw], a5g=prG[kw]), by="fwd_ym")
mp <- merge(mp, BEN, by.x="d0", by.y="Date")
steps <- list()
addstep <- function(lab, ws, extra=NA_real_){ p<-as.data.table(ws$period_returns); act<-p$ret_net-p$benchmark_ret
  steps[[length(steps)+1L]] <<- data.table(step=lab, n=ws$n_months, PORT_t=ws$portfolio_alpha_t_nw_lag3,
    active_ann=100*mean(act)*12, IR=ws$information_ratio, TO=ws$turnover_annual, note=extra) }
mkw <- function(S, wtcol=c("PI","EW","CAP"), topN=NA, capv=NA, bps=0, liq=FALSE){
  wtcol<-match.arg(wtcol); s<-copy(S)[is.finite(score)]
  if(liq) s <- merge(s, LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv)|adv>=2e8]
  setorder(s, Date, -score); if(!is.na(topN)) s<-s[, head(.SD,topN), by=Date]
  if(wtcol=="EW") s[, w:=1/.N, by=Date]
  else if(wtcol=="CAP") s[, w:=if(is.na(capv)) cap/sum(cap) else capw(cap,capv), by=Date]
  else s[, w:=if(is.na(capv)) score/sum(score) else capw(pmax(score,1e-12),capv), by=Date]
  weighted_screen_bt(s[,.(Date,Ticker,w)],RET,BEN,cost_bps_oneway=bps,
     run_id="rf2", strategy_id="RF2") }
steps[[1]] <- data.table(step="0. 지수레벨 A5 (net 15bps, 지수-간 회전만)", n=nrow(mp),
  PORT_t=nwt(mp$a5-mp$BM_Ret), active_ann=100*mean(mp$a5-mp$BM_Ret)*12,
  IR=NA_real_, TO=mean(tov[kw],na.rm=TRUE)*12, note=NA_real_)
w1 <- mkw(PA,"PI",NA,NA,0,FALSE);  addstep("1. pi 전량, cap없음, liq없음, 0bps (패리티)", w1)
w2 <- mkw(PA,"PI",NA,NA,15,FALSE); addstep("2. + 15bps (실제 종목 회전 과금)", w2)
w3 <- mkw(PA,"PI",NA,NA,15,TRUE);  addstep("3. + 유동성 필터 adv20>=2e8", w3)
w4 <- mkw(PA,"PI",NA,0.20,15,TRUE);addstep("4. + 0.20 weight cap", w4)
w5 <- mkw(PA,"PI",25L,0.20,15,TRUE);addstep("5. + top-25 절단 (= 보고 T-IDX)", w5)
DEC1 <- rbindlist(steps)
cat("\n===== (a) 손실 분해: 지수레벨 → T-IDX =====\n"); print(DEC1, digits=4)
fwrite(DEC1, file.path(OUT,"v7_loss_decomp.csv"))

## ══ (b) 미계상 비용: 무제약 pi 포트의 실제 회전율 ═══════════════════════════
cat(sprintf("\n===== (b) 미계상 비용 =====\n지수레벨 TO=%.2f/yr | pi전량(무cap·무liq) TO=%.2f/yr | pi전량(cap+liq) TO=%.2f/yr\n",
  mean(tov[kw],na.rm=TRUE)*12, w2$turnover_annual, w4$turnover_annual))
cat(sprintf("  미계상 비용 = (%.2f - %.2f) x 15bps = %.3f%%p/yr  [보고값 0.32]\n",
  w2$turnover_annual, mean(tov[kw],na.rm=TRUE)*12, (w2$turnover_annual-mean(tov[kw],na.rm=TRUE)*12)*0.15))

## ══ (c) 종목층 PIT 스트레스 ═════════════════════════════════════════════════
## c1) w_f 를 한 달 더 지연(lag=-1: 더 오래된 정보) / 한 달 앞당김(lag=+1: 명시적 미래참조)
pit <- rbindlist(lapply(c(-1L,0L,1L), function(L){
  za <- scoreZ("A5", lag=L); wcap <- mkw(za,"CAP",25L,0.20,15,TRUE)
  p<-as.data.table(wcap$period_returns); act<-p$ret_net-p$benchmark_ret
  data.table(lag_wf=L, form="Z합성xcap-w top25", PORT_t=wcap$portfolio_alpha_t_nw_lag3,
             active_ann=100*mean(act)*12, IR=wcap$information_ratio) }))
cat("\n===== (c) PIT 스트레스: w_f 시점 이동 (lag=+1 은 의도적 미래참조) =====\n"); print(pit, digits=4)
fwrite(pit, file.path(OUT,"v8_pit_lag.csv"))

## c2) Z 를 한 달 지연(신호 staleness) — 전월 Z 로 이번달 선택
MZs <- MZ; for(i in seq_along(MZ)) if(!is.null(MZ[[i]])) {
  if(i>1 && !is.null(MZ[[i-1]])) { MZs[[i]]$Z <- NULL } }
ZAs <- rbindlist(lapply(seq_along(MZ), function(i){ M<-MZ[[i]]; P<-if(i>1) MZ[[i-1]] else NULL
  if(is.null(M)||is.null(P)) return(NULL)
  wv <- setNames(Wapp[M$mrow,-1],facn); wv[!P$ok]<-0; if(sum(wv)<=1e-12) return(NULL)
  Zf<-P$Z; Zf[is.na(Zf)]<-0; sc<-as.numeric(Zf%*%wv); hit<-as.numeric((!is.na(P$Z))%*%wv)
  keep<-hit>0
  # 보유는 이번달 유니버스 ∩ 전월 커버
  data.table(Date=M$d0, Ticker=P$tk[keep], score=sc[keep], cap=as.numeric(P$cap[keep])) }))
ZAs <- ZAs[Ticker %in% unique(RET$Ticker)]
wz <- mkw(ZAs,"CAP",25L,0.20,15,TRUE); pz<-as.data.table(wz$period_returns)
cat(sprintf("[c2] Z 1개월 지연(stale) Z합성xcap-w: PORT_t=%+.3f active=%+.2f%%p/yr (정본 %+.3f)\n",
  wz$portfolio_alpha_t_nw_lag3, 100*mean(pz$ret_net-pz$benchmark_ret)*12, pit[lag_wf==0L,PORT_t]))

## ══ (d) w_f 셔플 널 — '팩터 정체성'이 신호인가 ══════════════════════════════
base_cap <- mkw(ZA,"CAP",25L,0.20,15,TRUE); pb<-as.data.table(base_cap$period_returns)
ctrl_cap <- mkw(ZE,"CAP",25L,0.20,15,TRUE); pc<-as.data.table(ctrl_cap$period_returns)
mbc <- merge(pb[,.(date,x=ret_net)], pc[,.(date,y=ret_net)], by="date")
t_obs <- nwt(mbc$x-mbc$y); a_obs <- 100*mean(pb$ret_net-pb$benchmark_ret)*12
cat(sprintf("\n===== (d) w_f 셔플 널 =====\n관측: Z합성xcap-w paired NW-t = %+.3f | active %+.2f%%p/yr\n", t_obs, a_obs))
set.seed(20260822); B <- 100L
nullres <- rbindlist(lapply(seq_len(B), function(b){
  perm <- sample(facn)
  Ws <- Wapp; Ws[,-1] <- Wapp[, c(1, 1+match(perm, facn))][,-1]   # 팩터 정체성 셔플
  sb <- rbindlist(lapply(MZ, function(M){ if(is.null(M)) return(NULL)
    wv <- setNames(Ws[M$mrow,-1], facn); wv[!M$ok]<-0; if(sum(wv)<=1e-12) return(NULL)
    Zf<-M$Z; Zf[is.na(Zf)]<-0; sc<-as.numeric(Zf%*%wv); hit<-as.numeric((!is.na(M$Z))%*%wv)
    keep<-hit>0
    data.table(Date=M$d0, Ticker=M$tk[keep], score=sc[keep], cap=as.numeric(M$cap[keep])) }))
  wsb <- mkw(sb,"CAP",25L,0.20,15,TRUE); pbb<-as.data.table(wsb$period_returns)
  mm <- merge(pbb[,.(date,x=ret_net)], pc[,.(date,y=ret_net)], by="date")
  data.table(b=b, t=nwt(mm$x-mm$y), act=100*mean(pbb$ret_net-pbb$benchmark_ret)*12,
             port_t=wsb$portfolio_alpha_t_nw_lag3) }))
cat(sprintf("널 분포(B=%d): paired-t 중앙 %+.3f | p95 %+.3f | max %+.3f | P(널 >= 관측) = %.3f\n",
  B, median(nullres$t), quantile(nullres$t,.95), max(nullres$t), mean(nullres$t>=t_obs)))
cat(sprintf("             active 중앙 %+.2f | p95 %+.2f | max %+.2f | P(널 >= 관측 %.2f) = %.3f\n",
  median(nullres$act), quantile(nullres$act,.95), max(nullres$act), a_obs, mean(nullres$act>=a_obs)))
cat(sprintf("             PORT_t 중앙 %+.3f | p95 %+.3f | P(널 >= %.3f) = %.3f\n",
  median(nullres$port_t), quantile(nullres$port_t,.95), base_cap$portfolio_alpha_t_nw_lag3,
  mean(nullres$port_t>=base_cap$portfolio_alpha_t_nw_lag3)))
fwrite(nullres, file.path(OUT,"v9_shuffle_null.csv"))

## ══ (e) adv 결측 통과 건수 ══════════════════════════════════════════════════
chk <- merge(ZA, LIQ, by=c("Date","Ticker"), all.x=TRUE)
cat(sprintf("\n===== (e) 유동성 =====\nZA 종목-월 %d | adv 결측(무조건 통과) %d (%.2f%%) | adv<2e8 탈락 %d\n",
  nrow(chk), sum(is.na(chk$adv)), 100*mean(is.na(chk$adv)), sum(!is.na(chk$adv)&chk$adv<2e8)))
saveRDS(list(DEC1=DEC1,pit=pit,nullres=nullres), file.path(OUT,"rf2.rds"))
cat("\nRF2_DONE\n")
