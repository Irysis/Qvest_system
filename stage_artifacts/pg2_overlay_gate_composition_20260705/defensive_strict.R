## defensive(bear) 오버레이 정제 — ★strict PIT (Date<first-day-of-return_ym) + 가드
## aggregate 패널(period_returns_layer5_faith). base=m4×R05. 여러 bear 신호를 clean 타이밍서 테스트.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705"); COST<-0.0015
source(file.path(ROOT,"02_Infrastructure/validation/overlay_pit_guard.R"))
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); n<-nrow(p)
p[, hstart := overlay_signal_cutoff(return_ym)]   # ★홀딩월 시작 = clean 컷오프
assert_overlay_pit(p$hstart, p$hstart, "defensive_strict")   # 자명 통과(컷오프=홀딩월시작)
mbeta<-mean(p$beta_R05); FLOOR<-min(p$beta_R05)
p[, dR05:=abs(beta_R05-shift(beta_R05,1,fill=1.0))]; p[, ret_base:=beta_R05*m4*ret_orig-dR05*COST]
epct<-function(x){u<-rep(0.5,length(x));for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u}
load_strict<-function(f,col){urs<-as.data.table(read_parquet(file.path(WD,"pinned_cache",f)));urs[,Date:=as.Date(Date)];setorder(urs,Date)
  urs<-urs[is.finite(get(col))];v<-rep(NA_real_,n);for(i in 1:n){pv<-urs[Date<p$hstart[i]];if(nrow(pv)>0)v[i]<-tail(pv[[col]],1)};v}  # ★Date<홀딩월시작
gate<-function(sv,floorL=FLOOR,gamma=2){f<-function(th){x<-pmax(0,(sv-th)/(1-th+1e-9));mean(1-(1-floorL)*pmin(1,x)^gamma)-mbeta}
  th<-tryCatch(uniroot(f,c(0,0.999))$root,error=function(e)NA);if(is.na(th))return(rep(NA,length(sv)));x<-pmax(0,(sv-th)/(1-th+1e-9));1-(1-floorL)*pmin(1,x)^gamma}
apply_beta<-function(bt){db<-abs(bt-shift(bt,1,fill=1.0));bt*p$m4*p$ret_orig-db*COST}
met<-function(rv,tag){x<-xts(rv,order.by=p$anchor_date)
  data.table(tag=tag,SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]),MDD=as.numeric(maxDrawdown(x)),
    Calmar=as.numeric(Return.annualized(x,scale=12))/as.numeric(maxDrawdown(x)),CVaR95=-as.numeric(quantile(rv,0.05)))}
## 신호들 (strict PIT)
s_bear<-epct(load_strict("regime_jump_daily.parquet","Bear_Prob_lag"))
s_msm <-epct(load_strict("unified_regime_signal_daily.parquet","MSM_Crisis_Prob"))
s_reg <-{u<-epct(load_strict("unified_regime_signal_daily.parquet","Regime_Score"));sg<-sign(cor(p$beta_R05,u,use="complete.obs"));if(sg>=0)(1-u)else u}
base<-met(p$ret_base,"BASE(m4×R05)")
PG("[PG] BASE strict: SR=%.4f Calmar=%.4f MDD=%.4f", base$SR, base$Calmar, base$MDD)
cands<-list(Bear_strict=gate(s_bear), MSM_strict=gate(s_msm), Reg_strict=gate(s_reg),
            BearxMSM_strict=gate(pmax(s_bear,s_msm)), Bear_soft_floor0.7=gate(s_bear,floorL=0.7))
rows<-list(base)
for(nm in names(cands)){bt<-cands[[nm]];if(any(!is.finite(bt))){PG("skip %s",nm);next}
  bt<-pmin(1,pmax(FLOOR*0.9,bt));m<-met(apply_beta(bt),nm)
  rows[[length(rows)+1]]<-m
  PG("[PG] %-20s SR=%.4f Calmar=%.4f MDD=%.4f | vs base ΔCalmar=%+.3f", nm, m$SR, m$Calmar, m$MDD, m$Calmar-base$Calmar)}
## Bear: strict vs loose(anchor=look-ahead) 인플레 명시 (가드 시연)
load_anchor<-function(){urs<-as.data.table(read_parquet(file.path(WD,"pinned_cache","regime_jump_daily.parquet")));urs[,Date:=as.Date(Date)];setorder(urs,Date);urs<-urs[is.finite(Bear_Prob_lag)];v<-rep(NA_real_,n);for(i in 1:n){pv<-urs[Date<p$anchor_date[i]];if(nrow(pv)>0)v[i]<-tail(pv$Bear_Prob_lag,1)};v}
s_bear_loose<-epct(load_anchor())
b_loose<-met(apply_beta(pmin(1,pmax(FLOOR*0.9,gate(s_bear_loose)))),"Bear_loose")
b_strict<-met(apply_beta(pmin(1,pmax(FLOOR*0.9,gate(s_bear)))),"Bear_strict")
ab<-overlay_lookahead_ab(b_loose$Calmar,b_strict$Calmar,"Bear Calmar");PG("[PG] %s",ab$message)
res<-rbindlist(rows)
print(res[,.(tag,SR=round(SR,3),Calmar=round(Calmar,3),MDD=round(MDD,3),CVaR95=round(CVaR95,4))])
fwrite(res,file.path(WD,"defensive_strict_results.csv"))
PG("[PG] DONE defensive_strict")
