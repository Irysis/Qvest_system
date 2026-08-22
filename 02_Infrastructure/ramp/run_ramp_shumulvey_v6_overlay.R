## run_ramp_shumulvey_v6_overlay.R — T1: BL 멀티팩터 포트 위 시장-국면 오버레이 계층 (FQ-239 라운드 2)
## prereg outputs/ramp/smv_v6_prereg_20260821.json — exposure_m = 1 − 0.30·signal (자유도 0), 월말 신호 → 익월 적용(C5).
## 신호원 2종: (a) smv_breadth = mean(bear_prob 6종) (b) mkt_jm = regime_jump_daily::Bear_Prob. lag1 스트레스 팔 포함.
## 비용 근사(보수): r_ov = exp·pr_net − bps·|Δexp| (기존 거래비용을 exp로 축소하지 않음). 게이트 접근 셀은 엔진 정밀 재측정.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/validation/overlay_pit_guard.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")

`%||%`<-function(a,b)if(is.null(a))b else a
BASEKEY<-Sys.getenv("SMV_BASEKEY","f15_roll")
.dfa_rds<-function(key){p<-sprintf(".cache/_dfa_v5_%s.rds",key); if(file.exists(p))p else sprintf(".cache/_smv_v5_%s.rds",key)}
Z<-readRDS(.dfa_rds(BASEKEY)); RES<-Z$RES
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

## 시장 월수익 + 월말 날짜 그리드
R<-as.data.table(read_parquet(Z$idxfile)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
R[,ym:=format(Date,"%Y-%m")]
monM<-R[,.(mkt=prod(1+Market)-1, medate=max(Date)),by=ym]

## 신호 2종 (일별 → 월말 값)
sb<-as.data.table(read_parquet("outputs/ramp/smv_factor_regime_daily.parquet"))
sb[,Date:=as.Date(Date)]
brd<-sb[is.finite(bear_prob),.(breadth=mean(bear_prob)),by=Date]
brd[,ym:=format(Date,"%Y-%m")]; brdm<-brd[,.SD[Date==max(Date)],by=ym][,.(ym,sig=breadth)]
jm<-as.data.table(read_parquet(".cache/regime_jump_daily.parquet", col_select=c("Date","Bear_Prob")))
jm[,Date:=as.Date(Date)]; jm<-jm[is.finite(Bear_Prob)]
jm[,ym:=format(Date,"%Y-%m")]; jmm<-jm[,.SD[Date==max(Date)],by=ym][,.(ym,sig=Bear_Prob)]
SIGS<-list(smv_breadth=brdm, mkt_jm=jmm)

prev_ym<-function(yms){ d<-as.Date(paste0(yms,"-01")); format(d-1,"%Y-%m") }   # 직전 월 라벨

mk_metrics<-function(pr,mk){ act<-pr-mk; nav<-cumprod(1+pr); mdd<-min(nav/cummax(nav)-1)
  cagr<-prod(1+pr)^(12/length(pr))-1
  list(IR_vsMkt=IRf(act), pt=nwt(act), SR=IRf(pr), CAGR=cagr, MDD=mdd, calmar=cagr/abs(mdd)) }

OUT<-list(); ESS<-list()
for(sname in names(SIGS)){ SG<-SIGS[[sname]]
  for(te in c(1,2,3,4)) for(bps in c(5,15)){
    ri<-which(RES$arm=="M0" & RES$te==te & RES$cost_bps==bps)
    if(!length(ri))next
    row<-RES[ri[1]]
    if(is.null(row$series[[1]]))next
    s<-row$series[[1]]; d<-as.Date(s$months); pr<-s$pr
    aym<-format(d,"%Y-%m")            # 적용월
    dym<-prev_ym(aym)                 # 결정 월말(직전 월)
    sig <-SG[match(dym,ym),sig]       # 본선: 직전 월말 신호
    sig1<-SG[match(prev_ym(dym),ym),sig]  # lag1 스트레스: 두 달 전 신호
    ## 결측 → 직전 가용값 carry (없으면 노출 1)
    carry<-function(x){ for(i in seq_along(x)) if(!is.finite(x[i])) x[i]<-if(i>1)x[i-1] else NA; ifelse(is.finite(x),x,0) }
    sig<-carry(sig); sig1<-carry(sig1)
    for(armn in c("base","ov","ov_lag1")){
      sg<-switch(armn, base=NULL, ov=sig, ov_lag1=sig1)
      if(is.null(sg)){ prx<-pr } else {
        ex<-1-0.30*pmin(pmax(sg,0),1)
        dex<-abs(diff(c(1,ex)))
        prx<-ex*pr - (bps/1e4)*dex }
      mk<-monM[match(aym,ym),mkt]
      k<-is.finite(prx)&is.finite(mk)
      m<-mk_metrics(prx[k],mk[k])
      OUT[[length(OUT)+1]]<-data.table(signal=sname,arm=armn,te=te,cost_bps=bps,n_mo=sum(k),
        IR_vsMkt=m$IR_vsMkt,pt_capwt=m$pt,abs_SR=m$SR,abs_CAGR=m$CAGR,abs_MDD=m$MDD,calmar=m$calmar,
        avg_exposure=if(is.null(sg))1 else mean(1-0.30*pmin(pmax(sg,0),1)))
      ## PIT 구조 검사 (ov 팔): 결정 월말(직전 월 마지막 거래일) < 적용월 시작
      if(armn=="ov"){
        decd<-monM[match(dym,ym),medate]; okd<-is.finite(as.integer(decd))
        assert_overlay_pit(decd[okd], as.Date(paste0(aym,"-01"))[okd], label=sprintf("v6_overlay_%s",sname)) }
      ## 헤드라인 셀(TE3) essence 계약 채점
      if(armn=="ov" && te==3){
        sim<-list(DAILY_NAV_DT=data.table(Date=d[k],Strategy_Ret=prx[k],NAV=cumprod(1+prx[k])),
                  strategy_xts=xts(prx[k],order.by=d[k]), bm_xts=xts(mk[k],order.by=d[k]),
                  cost_model_version=sprintf("smv_v6_ov_%dbps",bps))
        spec<-list(strategy_name=sprintf("SMV_V6_OV_%s_TE3_%d",toupper(sname),bps),
                   description="Shu-Mulvey v5 M0-roll + 시장국면 오버레이(exposure=1-0.30·signal, 월말→익월)",
                   universe="7 KR style indices", rebalance="monthly", signal=sname)
        bt<-build_bt_result(sim,spec,run_id=sprintf("smv_v6_ov_%s_te3_%d",sname,bps),
              strategy_id=sprintf("SMV_V6_OV_%s_TE3_%d",toupper(sname),bps),
              benchmark_id="CAPW_PARENT",benchmark_name="cap-w parent",
              transaction_cost_bps=bps,slippage_bps=0,frequency="monthly",
              universe_id="K200_KQ150",code_version="run_ramp_shumulvey_v6_overlay.R",created_by_agent="Q-Lead")
        au<-audit_bt_result(bt); es<-essence_score(bt,n_trials_cumulative=26,selection_type="chain")
        ESS[[sprintf("%s_%d",sname,bps)]]<-list(audit=au$integrity %||% NA, grade=es$grade, essence=es$essence)
      }
    }
  }
}
AB<-rbindlist(OUT)
fwrite(AB,sprintf("outputs/ramp/smv_v6_overlay_%s_20260821.csv",BASEKEY))
saveRDS(list(AB=AB,ESS=ESS),sprintf(".cache/_smv_v6_overlay_%s.rds",BASEKEY))
cat("\n== T1 overlay (baseline=",BASEKEY,") — TE3 발췌 ==\n")
print(AB[te==3][order(signal,cost_bps,arm)],digits=3)
cat("\n== 헤드라인 essence (TE3) ==\n")
for(nm in names(ESS)){ e<-ESS[[nm]]$essence
  cat(sprintf("[%s] grade=%s pt=%.3f oos=%.3f calmar=%.3f SR=%.2f MDD=%.3f\n",
      nm,ESS[[nm]]$grade,e$portfolio_alpha_t_nw_lag3,e$oos_retention,e$calmar,e$net_sharpe,e$mdd)) }
cat("V6_OVERLAY_DONE\n")
