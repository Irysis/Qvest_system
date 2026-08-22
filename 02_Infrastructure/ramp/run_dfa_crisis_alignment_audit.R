## run_dfa_crisis_alignment_audit.R — R3-A: 위기-정렬 감사 (FQ-239, prereg smv_v7 r3a — 진단 라운드, 전략 주장 없음)
## 질문: 어떤 ex-ante 신호가 실현 위기월과 정렬되는가. 판정 = predictive AUC의 block-bootstrap 90% CI 하한 > 0.5.
## ⚠위기 정의(하위 분위)는 전 창 기준 사후 이벤트 정의 — 진단 전용, 거래 규칙 아님(라벨 명기).
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
set.seed(20260821)

## 시장 일별/월별
R<-as.data.table(read_parquet("outputs/ramp/shumulvey_index_returns_202608.parquet", col_select=c("Date","Market")))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
R[,ym:=format(Date,"%Y-%m")]
ewm<-function(x,hl){a<-1-exp(log(0.5)/hl);y<-numeric(length(x));acc<-NA_real_
  for(i in seq_along(x)){xi<-x[i];if(is.na(xi)){y[i]<-acc;next};acc<-if(is.na(acc))xi else a*xi+(1-a)*acc;y[i]<-acc};y}
R[,rv:=sqrt(ewm(Market^2,21))]
R[,nav:=cumprod(1+Market)][,dd:=1-nav/cummax(nav)]
mon<-R[,.(mret=prod(1+Market)-1, medate=max(Date), rv=rv[.N], dd=dd[.N]),by=ym]
setorder(mon,medate)

## 후보 신호 (월말값)
jm<-as.data.table(read_parquet(".cache/regime_jump_daily.parquet", col_select=c("Date","Bear_Prob")))
jm[,Date:=as.Date(Date)]; jm<-jm[is.finite(Bear_Prob)]; setkey(jm,Date)
g<-data.table(Date=mon$medate); setkey(g,Date); mon[,mkt_jm:=jm[g,roll=7]$Bear_Prob]
sb<-as.data.table(read_parquet("outputs/ramp/smv_factor_regime_daily.parquet", col_select=c("Date","bear_prob")))
sb[,Date:=as.Date(Date)]; brd<-sb[is.finite(bear_prob),.(b=mean(bear_prob)),by=Date]; setkey(brd,Date)
mon[,smv_breadth:=brd[g,roll=7]$b]
ec<-as.data.table(read_parquet(".cache/ecos_bond_rates.parquet"))
ec<-ec[Series %in% c("KR_Gov3Y","KR_CorpBBB") & is.finite(Value)]; ec[,Date:=as.Date(Date)]
ecw<-dcast(ec,Date~Series,value.var="Value"); setorder(ecw,Date); setkey(ecw,Date)
j2<-ecw[g,roll=7]; mon[,credit_spread:=j2$KR_CorpBBB-j2$KR_Gov3Y]
mon[,credit_d21:=NA_real_]
{ dsp<-ecw[,.(Date,sp=KR_CorpBBB-KR_Gov3Y)][is.finite(sp)]; dsp[,d21:=ewm(c(NA,diff(sp)),21)]; setkey(dsp,Date)
  mon[,credit_d21:=dsp[g,roll=7]$d21] }
setnames(mon,c("rv","dd"),c("realized_vol","dd_depth"))

CANDS<-c("mkt_jm","smv_breadth","realized_vol","dd_depth","credit_spread","credit_d21")

auc<-function(sig,y){ k<-is.finite(sig)&is.finite(y); sig<-sig[k]; y<-y[k]
  if(sum(y)<3||sum(1-y)<3)return(NA_real_)
  r<-rank(sig); (sum(r[y==1])-sum(y)*(sum(y)+1)/2)/(sum(y)*sum(1-y)) }
boot_ci<-function(sig,y,B=2000,blk=12){ n<-length(sig); nb<-ceiling(n/blk)
  vals<-rep(NA_real_,B)
  for(b in 1:B){ st<-sample.int(n,nb,replace=TRUE)
    idx<-as.vector(outer(0:(blk-1),st,`+`))%%n+1; idx<-idx[1:n]
    vals[b]<-auc(sig[idx],y[idx]) }
  quantile(vals,c(0.05,0.95),na.rm=TRUE) }
prec_at_k<-function(sig,y){ k<-is.finite(sig)&is.finite(y); sig<-sig[k]; y<-y[k]
  kk<-sum(y); if(kk<1)return(NA_real_); mean(y[order(-sig)][1:kk]) }

run_frame<-function(D,label){
  out<-list()
  for(q in c(0.10,0.05)){ thr<-quantile(D$mret,q,na.rm=TRUE); D[,crisis:=as.integer(mret<=thr)]
    for(cn in CANDS){
      sp<-shift(D[[cn]],1)                       # predictive: 신호 m-1 → 위기 m
      a_p<-auc(sp,D$crisis); ci<-if(is.finite(a_p))boot_ci(sp,D$crisis) else c(NA,NA)
      a_d<-auc(D[[cn]],D$crisis)                 # detective (사후 확인, 소비 불가)
      out[[length(out)+1]]<-data.table(window=label,crisis_q=q,signal=cn,n_mo=sum(is.finite(sp)&is.finite(D$crisis)),
        n_crisis=sum(D$crisis,na.rm=TRUE),auc_pred=a_p,ci_lo=ci[1],ci_hi=ci[2],
        aligned=is.finite(ci[1])&&ci[1]>0.5, prec_at_k=prec_at_k(sp,D$crisis), auc_detect=a_d) } }
  rbindlist(out) }

RES<-rbind(run_frame(copy(mon),"market_full"),
           run_frame(copy(mon[is.finite(smv_breadth)]),"smv_window"))
setorder(RES,window,crisis_q,-auc_pred)
fwrite(RES,"outputs/ramp/dfa_crisis_alignment_audit_20260821.csv")
cat("== R3-A 위기-정렬 감사 (predictive AUC, 90% CI, block=12 B=2000) ==\n")
print(RES[crisis_q==0.10],digits=3)
cat("\n-- 하위 5% 정의 (병기) --\n"); print(RES[crisis_q==0.05],digits=3)
cat(sprintf("\n정렬 판정(CI 하한>0.5): %s\n",
  ifelse(any(RES[crisis_q==0.10]$aligned,na.rm=TRUE),
    paste(unique(RES[crisis_q==0.10&aligned==TRUE,paste(window,signal)]),collapse=" · "),"없음")))
cat("R3A_DONE\n")
